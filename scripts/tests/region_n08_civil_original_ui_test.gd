extends "res://scripts/tests/region_controlled_death_restriction_test.gd"
## Only the pinned manifest/freeze helpers are reused. No accepted arrival,
## owner receipt, N08 completion, elapsed clock or successful permission is seeded.
const N08Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const N08Stocks = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const N08Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const N08Orders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")

var n08_nation := "civil_transport"
var n08_order := ""
var n08_source_warehouse := ""
var n08_destination_warehouse := ""
var n08_vehicle := ""
var n08_driver := 0
var n08_trip := ""
var n08_form: Dictionary = {}
var n08_route: Dictionary = {}
var n08_steps := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 480000 # Crowd port: 180 s → 480 s (outer 600), the over-budget rule.
	out = "res://.godot-temp/region_n08_civil_original_ui/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	fixture_land_condition_rule = "terrain_mapped_potential_v1" # Founding needs mapped land.
	last_world_exists = FileAccess.file_exists(Entry.LAST_WORLD)
	if last_world_exists: last_world_bytes = FileAccess.get_file_as_bytes(Entry.LAST_WORLD)
	_run.call_deferred()

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest(): _finish(false); return
	var packed := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if not _check(packed != null, "Actual formal PackedScene exists"): _finish(false); return
	lab = packed.instantiate() as TerrainLab
	lab.restore_only = true; lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false; lab.visible = false
	root.add_child(lab)
	controller = lab.site_controller; _freeze(lab)
	var bootstrap := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345, {"size": Vector2i(32, 32)})
	Env.initialize(bootstrap, "n08:archive")
	lab.bind_terrain(bootstrap); lab.restore_only = false
	controller.save_root = out.path_join("archive")
	world_id = "n08_civil_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened: Dictionary = controller.open_fixed_world(manifest_path, world_id, "main", Vector2i.ZERO, true)
	if not _check(opened.ok, "Original first-world publication and bind", opened): _finish(false); return
	_freeze(lab); slot = controller.region_slot
	var wired: Dictionary = lab._wire_region_gameplay_adapters(slot)
	if not _check(wired.ok and slot.has_method("nation_route_options"), "Original same-Slot civil ports exist", wired): _finish(false); return
	owner_id = str(lab.terrain.site.id)
	cold_id = Grid.site_id(str(slot.pin.atlas_id), Vector2i(1, 0))
	var destination: Dictionary = lab._region_gameplay_owner_lab(cold_id, "cold_exact")
	if not _check(destination.get("ok") == true and destination.get("lab") is TerrainLab, "Actual cold destination scene owns all original systems", destination): _finish(false); return
	cold = destination.lab; _freeze(cold)
	if not _n08_genesis(): _finish(false); return
	var saved: Dictionary = controller.checkpoint_region_internal("region_checkpoint", true)
	if not _check(saved.ok, "Original checkpoint saves both actual warehouse Sites", saved): _finish(false); return
	var prepared: Dictionary = controller.person_actions.prepare_scope_technology(lab.controlled_person_id(), n08_driver, "N08", n08_nation)
	if not _check(prepared.ok and not N08Technology.scope_known(_n08_nation().technology, "N08"), "True first N08 project starts unknown", prepared): _finish(false); return
	if not _n08_ui_and_refusals(): _finish(false); return
	if not _n08_original_load_and_departure(): _finish(false); return
	await _n08_original_journey()
	if failed: _finish(false); return
	if not _n08_final_and_replay(): _finish(false); return
	_finish(true)

## Explicit initial scenario antecedents use original building and deployment
## constructors, before the first N08 command. These are not delivery receipts.
## Since 11/03 the controlled head is a row of their own start team: place that row too.
func _n08_place_controlled(original: TerrainLab, cell: Vector2i) -> bool:
	var placed: bool = original.character.place(cell, true)
	var control := int(original.controlled_person_id())
	for own_team: TerrainArmy in original.combat_armies:
		var index := own_team.index_for_identity(control)
		if own_team.has_army() and index >= 0 and index < own_team.cells.size():
			# As the nation earned fixtures do: the scenario's civil head acts for a real side, not the neutral start.
			own_team.faction_id = int(original.character.faction_id)
			own_team.cells[index] = cell
	return placed

func _n08_birth_warehouse(original: TerrainLab, anchor: Vector2i, faction: int) -> String:
	var data := original.terrain
	data.site.inventory.wood = 64; data.site.inventory.stone = 64; data.site.inventory.rope = 64 # Original warehouse cost: wood, stone and rope.
	# Construction keeps (does not consume) one tool; a fixed-geography Site starts with none.
	if int(data.site.inventory.get("tools", 0)) < 1: data.site.inventory["tools"] = 1
	var settings := {"layout_version": 1, "quarter": 0, "owner_faction": faction}
	var placement: Dictionary = N08Runtime.building_cells(data, "warehouse", anchor, Vector2i.ONE, settings)
	if not _check(placement.ok, "Original warehouse blueprint has legal cells", placement): return ""
	var built: Dictionary = N08Runtime.request_build(data, "warehouse", placement.cells, Callable(), settings)
	if not _check(built.ok, "Original constructor creates the initial warehouse", built): return ""
	var key := str(built.feature)
	var feature: Dictionary = data.site.features[key]
	var old_worker: Dictionary = data.site.worker.duplicate(true)
	N08Runtime.assign_task(data, N08Runtime.ok("", {"target": "feature:" + key, "action": "construct", "cell": feature.entrance}))
	data.site.worker.cell = int(feature.entrance); data.site.worker.mode = "work"
	N08Runtime._feature_work(data, key, float(feature.get("pending_build", feature).work) + 1.0,
		Callable(), Callable(), null, null, N08Runtime.CARRY_CAPACITY, faction)
	data.site.worker = old_worker
	if not _check(feature.stage == "complete" and not feature.has("pending_build"), "Original finite construction completes the initial warehouse", feature): return ""
	if not _check(N08Stocks.ensure_storage(data, key, faction).ok, "Original stockpile holder is installed"): return ""
	return key

func _n08_genesis() -> bool:
	n08_source_warehouse = _n08_birth_warehouse(lab, Vector2i(78, 48), int(lab.character.faction_id))
	n08_destination_warehouse = _n08_birth_warehouse(cold, Vector2i(20, 48), int(lab.character.faction_id))
	if n08_source_warehouse.is_empty() or n08_destination_warehouse.is_empty(): return false
	var entrance: Vector2i = lab.terrain.cell_from_index(int(lab.terrain.site.features[n08_source_warehouse].entrance))
	if not _check(_n08_place_controlled(lab, entrance), "Genesis Source head physically stands at its warehouse"): return false
	var setups: Array[Dictionary] = [{"count": 2, "role": "logistics", "faction": int(lab.character.faction_id),
		"wagon_count": 1, "spawn": entrance + Vector2i.RIGHT, "entry": "east", "attack": false, "ai_enabled": false}]
	var deployed: Dictionary = lab.deploy_trial_armies(setups)
	if not _check(deployed.ok, "Original deployment births one true NPC driver and one real wagon", deployed): return false
	_freeze(lab)
	# Crowd port (2026-11-11): the scenario's teams are deployed on the inactive Site, then the Site converts to the native
	# crowd, as a hand-built fixture does (crowd_fixture_port_guide). --grid keeps the retired army.
	if not OS.get_cmdline_user_args().has("--grid"):
		if lab.crowd_site == null: # The restore_only shell requested no crowd: attach one as a crowd bind does.
			lab.crowd_site = TerrainLab.CrowdSiteScript.new()
			lab.crowd_site.name = "CrowdSite"
			lab.add_child(lab.crowd_site)
			lab.crowd_site.setup(lab)
		var converted: Dictionary = lab.crowd_site.convert_existing()
		if converted.ok: converted = lab._region_write_converted_crowd_section()
		if not _check(converted.ok, "Crowd port: the deployed Site converts to the native crowd", converted): return false
	for key: String in controller.vehicles.records():
		var vehicle: Dictionary = controller.vehicles.records()[key]
		if vehicle.kind == "wagon" and int(vehicle.operator_id) > 0: n08_vehicle = key; n08_driver = int(vehicle.operator_id); break
	if not _check(n08_driver > 0 and n08_driver != lab.controlled_person_id(), "Carrier is a genuine NPC, while actual head stays controlled"): return false
	var carrier: Dictionary = slot._region_n08_wagon(lab, n08_vehicle, n08_driver)
	if not _check(carrier.ok, "Actual NPC captain/driver and complete wagon cohort are eligible", carrier): return false
	# Scenario enables the real captain's autonomous team.work decisions. The
	# eventual consent is obtained from that owner, never authored by this fixture.
	carrier.get("original", carrier.team).team_offices().duty_ai = true # Crowd: the source TerrainArmy owns the offices.
	var supply: Dictionary = controller._enable_team_supply(carrier.team)
	if not _check(not supply.is_empty(), "Original team sustenance holder exists"): return false
	supply.inventory["grain"] = 2
	var technology: Dictionary = N08Technology.empty_scope_record(owner_id)
	technology.known = ["N06"] # Named prerequisite antecedent only; N08 stays unknown.
	if not lab.terrain.site.has("equipment_nations"): lab.terrain.site.equipment_nations = {}
	lab.terrain.site.equipment_nations[n08_nation] = {"offices": SiteOffices.default_offices("nation", lab.controlled_person_id()),
		"members": [lab.controlled_person_id(), n08_driver], "standards": {}, "technology": technology}
	var funding_person: Dictionary = controller.person_actions._person(lab.controlled_person_id())
	if not _check(not funding_person.is_empty(), "Finite genesis cargo belongs to the true original controlled person"): return false
	funding_person.cargo["grain"] = 4 # Finite unspent genesis property, before any route.
	if not _check(int(N08Stocks.storage(cold.terrain, n08_destination_warehouse).cargo.get("grain", 0)) == 0,
		"Destination begins with no delivered grain"): return false
	return true

func _n08_nation() -> Dictionary:
	return lab.terrain.site.get("equipment_nations", {}).get(n08_nation, {})

func _n08_order_record() -> Dictionary:
	return _n08_nation().get("technology_operations", {}).get("public_orders", {}).get(n08_order, {})

func _n08_form_open() -> void:
	var body := VBoxContainer.new(); lab.add_child(body)
	var status := Label.new(); lab.add_child(status)
	var nation_choice := OptionButton.new(); lab.add_child(nation_choice)
	nation_choice.add_item(n08_nation); nation_choice.set_item_metadata(0, n08_nation); nation_choice.select(0)
	var technology := OptionButton.new(); lab.add_child(technology)
	technology.add_item("N08"); technology.set_item_metadata(0, "N08"); technology.select(0)
	n08_form = {"data": lab.terrain, "site": lab.terrain.site, "requester": lab.controlled_person_id(),
		"body": body, "status": status, "nation_choice": nation_choice, "technology": technology}
	controller._nation_ui_render(n08_form)

func _n08_choose(key: String, wanted: Variant) -> bool:
	var choice := n08_form.controls.get(key) as OptionButton
	if choice == null: return _check(false, "Original UI field exists: " + key)
	for index: int in choice.item_count:
		var metadata: Variant = choice.get_item_metadata(index)
		# Mixed metadata types (a String placeholder beside Dictionary routes) never compare across types.
		if typeof(metadata) == typeof(wanted) and metadata == wanted: choice.select(index); return true
	return _check(false, "Original UI exposes actual metadata: " + key, wanted)

func _n08_press(action: String) -> bool:
	var button := n08_form.body.find_child("NationOperation_" + action, true, false) as Button
	if not _check(button != null and not button.disabled, "Actual original action button: " + action): return false
	button.pressed.emit()
	return _check((str(n08_form.status.text).begins_with("OK:") or str(n08_form.status.text).begins_with("OK：")), "Original button accepts: " + action, n08_form.status.text)

func _n08_ui_and_refusals() -> bool:
	var options: Dictionary = controller.nation_route_options()
	if not _check(options.ok and options.routes.size() == 1, "Original same-Slot UI projects one real route/wagon/warehouse", options): return false
	n08_route = options.routes[0]
	_n08_form_open()
	if not _n08_choose("reserve", n08_source_warehouse) or not _n08_choose("route", n08_route): return false
	var before := JSON.stringify([slot._marker, slot.control, lab.terrain.site, cold.terrain.site], "", true, true)
	var wrong: Dictionary = controller.nation_route_query("not_the_original_route", cold_id, n08_vehicle, n08_driver, "feature:" + n08_destination_warehouse)
	if not _check(not wrong.ok and wrong.get("code") == "STALE_ROUTE", "Wrong route id refuses through the true route owner", wrong): return false
	var unauthorized: Dictionary = controller.equipment_orders.authorize_public_transport_route(n08_driver, n08_nation,
		n08_source_warehouse, str(n08_route.route_id), cold_id, "feature:" + n08_destination_warehouse, n08_vehicle, n08_driver)
	if not _check(not unauthorized.ok and unauthorized.get("code") == "NO_AUTHORITY", "NPC driver cannot impersonate controlled civil authorizer", unauthorized): return false
	if not _check(before == JSON.stringify([slot._marker, slot.control, lab.terrain.site, cold.terrain.site], "", true, true), "Rejected route and authority change no original owner or marker"): return false
	if not _n08_press("approve_route"): return false
	var keys: Array = _n08_nation().technology_operations.public_orders.keys()
	if not _check(keys.size() == 1, "Actual UI creates exactly one original order"): return false
	n08_order = str(keys[0])
	var consent: Dictionary = controller.person_actions.request_scope_technology_consent(lab.controlled_person_id(), "nation", n08_nation, n08_driver)
	if not _check(consent.ok, "Actual captain accepts named N08 work through original team.work", consent): return false
	controller._nation_ui_render(n08_form)
	if not _n08_choose("order", n08_order): return false
	n08_form.resources.grain.quantity.value = 4
	if not _n08_press("grant_source"): return false
	if not _n08_press("fund"): return false
	var funding_person: Dictionary = controller.person_actions._person(lab.controlled_person_id())
	return _check(not funding_person.is_empty() and int(funding_person.cargo.get("grain", 0)) == 0 and int(N08Stocks.storage(lab.terrain, n08_source_warehouse).cargo.get("grain", 0)) == 4,
		"UI funding physically transfers the same four finite grains into Source warehouse")

func _n08_original_load_and_departure() -> bool:
	if not _n08_press("load_route"): return false
	var project: Dictionary = N08Technology.active_project(_n08_nation().technology)
	if not _check(_n08_order_record().payload.loaded and int(controller.vehicles.records()[n08_vehicle].cargo.get("grain", 0)) == 4
		and int(N08Stocks.storage(lab.terrain, n08_source_warehouse).cargo.get("grain", 0)) == 0
		and project.budget.payments.size() == 1 and project.budget.payments[0].materials == {"grain": 4},
		"One real warehouse-to-NPC-wagon load is also exactly one original four-grain phase payment", project): return false
	if not _check(not N08Technology.scope_known(_n08_nation().technology, "N08") and _n08_order_record().receipts.is_empty(), "Loaded vehicle earns no premature route evidence"): return false
	if not _n08_press("begin_route"): return false
	n08_trip = str(_n08_order_record().payload.travel_token)
	var reference: Dictionary = slot.region_registry().parties.get(n08_trip, {})
	if not _check(not n08_trip.is_empty() and reference.get("transfer_receipt", {}).get("kind") == "nation_public_route",
		"Original NPC publisher owns the actual accepted civil journey", reference): return false
	if not _check(lab.controlled_person_id() == 1 and _n08_nation().technology.holder_site_id == owner_id
		and controller.person_actions._person(n08_driver).is_empty(), "Partial original Nation and controlled head stay Source; actual NPC body departs once"): return false
	lab.simulation_speed = 4.0; lab.exchange_enabled = true
	report["departure_generation"] = int(slot._marker.generation)
	report["trip_token"] = n08_trip
	return true

func _n08_original_journey() -> void:
	while n08_steps < 20000 and not finished and Time.get_ticks_msec() < deadline:
		if _n08_order_record().get("status") == "complete": return
		var advanced: Dictionary = lab._advance_original_shared_step(lab.EXCHANGE_ACTION_STEP)
		if not _check(advanced.ok, "One actual shared step advances live, cold and original NPC journey together", advanced): return
		var consumed: Dictionary = slot.consume_due_region_events()
		if not _check(consumed.ok, "Original Slot consumes true due arrival/contact/work events", consumed): return
		if n08_steps % 256 == 0: report["last_consumed"] = JSON.stringify(consumed).left(800) # Failure context only.
		for original: TerrainLab in slot._region_original_labs.values(): _freeze(original)
		n08_steps += 1
		if n08_steps % 64 == 0: await process_frame
	# Failure context (read-only): the entered carrier's own refusal at its destination.
	var entered: Dictionary = slot._region_n08_entered_context(n08_trip)
	report["entered_context"] = str(entered.get("code", "ok"))
	if entered.ok:
		var dest: TerrainLab = entered.destination_lab
		report["destination_crowd"] = dest.crowd_site != null and dest.crowd_site.active
		report["destination_site"] = str(dest.terrain.site.id)
		report["carrier"] = JSON.stringify(slot._region_n08_wagon(dest, str(entered.vehicle_id), int(entered.driver_id))).left(300)
		var vehicle: Dictionary = dest.site_controller.vehicles.records().get(str(entered.vehicle_id), {})
		report["vehicle"] = JSON.stringify({"operator": vehicle.get("operator_id"), "move": vehicle.get("move"), "team": vehicle.get("team_id")}).left(300)
		var driver: Dictionary = dest.site_controller.vehicles._operator(int(entered.driver_id))
		report["driver_owner"] = str(driver.get("owner")) if not driver.is_empty() else "none"
		if not driver.is_empty():
			report["driver_cell"] = str(driver.cell)
			report["horse_cell"] = str(dest.site_controller.vehicles.operator_cell(vehicle))
			report["driver_available"] = dest.site_controller.vehicles._available(driver)
			report["driver_walking"] = driver.owner.is_walking(int(driver.unit)) if driver.owner is CrowdPersonOwner else false
			report["driver_team"] = int(driver.owner.team_id)
	_check(false, "Actual journey must reach original physical unloading within bounded original steps", slot.region_registry().parties.get(n08_trip, {}))

func _n08_final_and_replay() -> bool:
	var destination: Dictionary = lab._region_gameplay_owner_lab(cold_id, "cold_exact")
	if not _check(destination.get("ok") == true, "Selected destination restores through original factory", destination): return false
	cold = destination.lab; _freeze(cold)
	var order: Dictionary = _n08_order_record()
	var record: Dictionary = _n08_nation().technology
	var reference: Dictionary = slot.region_registry().parties[n08_trip]
	if not _check(order.status == "complete" and order.receipts.size() == 1 and N08Technology.scope_known(record, "N08") and int(record.active) == 0,
		"Only true Destination receipt completes the first N08 project and order", order): return false
	if not _check(int(N08Stocks.storage(cold.terrain, n08_destination_warehouse).cargo.get("grain", 0)) == 4, "Destination real holder received exactly four grains"): return false
	var genuine_p0 := false
	for original_event: Dictionary in slot.region_registry().events:
		if original_event.kind == "player_encounter" and original_event.status == "complete" and original_event.player == true \
			and original_event.owner == owner_id and original_event.payload.get("token") == n08_trip:
			genuine_p0 = true
	# Region round 13 (10/12): a party just extracted from the player's own active Site does not meet
	# the player on its departure segment, so the carrier unloads directly without a P0 resume.
	if not _check(not genuine_p0, "The stationary Source head makes no road contact with its own departing carrier"): return false
	var physical_event := str(reference.get("nation_delivery_event", ""))
	var receipt: Dictionary = slot.region_nation_route_receipt(lab, "feature:" + n08_destination_warehouse, physical_event)
	if not _check(receipt.ok and receipt.receipt.transfer_token == n08_trip and receipt.physical_event.status == "complete"
		and receipt.receipt.operator_reference == reference.transfer_receipt.person_reference, "Canonical receipt resolves same journey and true original typed driver", receipt): return false
	var before := JSON.stringify([lab.terrain.site.equipment_nations, cold.terrain.site.stockpiles, slot.region_registry().parties[n08_trip]], "", true, true)
	var replay: Dictionary = slot.consume_due_region_events()
	if not _check(replay.ok and before == JSON.stringify([lab.terrain.site.equipment_nations, cold.terrain.site.stockpiles, slot.region_registry().parties[n08_trip]], "", true, true), "Replay neither unloads nor completes the research twice", replay): return false
	var source_saved: Dictionary = slot._load_checked(slot.site_path(Vector2i.ZERO), Vector2i.ZERO)
	var destination_saved: Dictionary = slot._load_checked(slot.site_path(Vector2i(1, 0)), Vector2i(1, 0))
	if not _check(source_saved.ok and destination_saved.ok, "Both complete original selected payloads pass Store readback", [source_saved.get("code"), destination_saved.get("code")]): return false
	var durable_order: Dictionary = source_saved.data.site.equipment_nations[n08_nation].technology_operations.public_orders[n08_order]
	if not _check(durable_order == order and N08Technology.scope_known(source_saved.data.site.equipment_nations[n08_nation].technology, "N08")
		and int(N08Stocks.storage(destination_saved.data, n08_destination_warehouse).cargo.get("grain", 0)) == 4,
		"Single original marker durably selects both paid Source research and received Destination cargo"): return false
	report.merge({"steps": n08_steps, "world_seconds": float(slot.control.logical_game_seconds), "event_id": physical_event,
		"source_site": owner_id, "destination_site": cold_id, "original_ui": ["approve_route", "grant_source", "fund", "load_route", "begin_route"],
		"receipt": receipt.receipt}, true)
	return true

func _finish(ok: bool = true, message: String = "") -> void:
	if finished: return
	finished = true; failed = failed or not ok
	if not message.is_empty(): print(message)
	paused = false
	if is_instance_valid(lab): lab.free()
	var current: Variant = JSON.parse_string(FileAccess.get_file_as_string(Entry.LAST_WORLD)) if FileAccess.file_exists(Entry.LAST_WORLD) else null
	if current is Dictionary and current.get("world_id") == world_id:
		if last_world_exists:
			var restored := FileAccess.open(Entry.LAST_WORLD, FileAccess.WRITE); restored.store_buffer(last_world_bytes); restored.close()
		else: DirAccess.remove_absolute(ProjectSettings.globalize_path(Entry.LAST_WORLD))
	TerrainArmy.release_contact_source()
	var evidence := {"checks": checks, "failed": failed, "report": report, "artifact_root": out,
		"scope": "actual_original_ui_civil_authority_four_grain_load_phase_payment_npc_wagon_region_clock_physical_destination_unload_single_marker_replay"}
	var output := FileAccess.open(out.path_join("receipt.json"), FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify(evidence, "\t", true, true)); output.close()
	print("REGION_N08_CIVIL_ORIGINAL_UI_", "FAILED" if failed else "PASS", " ", JSON.stringify(evidence))
	quit(1 if failed else 0)
