extends "res://scripts/tests/region_siege_cold_action_epoch_test.gd"
## NEW Source-only physical fixture. Each runtime assertion is NOT_RUN until Root.
## Explicit test-only boat genesis is separate from false-dispatch public work.
const ShipCoastGenesis = preload("res://scripts/tests/region_ship_coast_legal_named_genesis.gd")
const ShipGarrison = preload("res://scripts/terrain_lab/site_garrison.gd")
const PhysicalSustain = preload("res://scripts/terrain_lab/site_sustain.gd")
var ship_team_id := 0
var ship_actor_id := 0
var ship_people: Array[int] = []
var ship_ids: Array[String] = []
var ship_barriers: Array[String] = []
var ship_observation := "settled"
var ship_cold_evidence: Array[Dictionary] = []
var ship_food_initial := 8.0
var ship_consumed_rations := 0.0
var ship_food_party_token := ""
var ship_food_source_site := ""
var ship_food_results: Array[Dictionary] = []

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 300000
	out = "res://.godot-temp/region_c06_ship_physical/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	last_world_exists = FileAccess.file_exists(Entry.LAST_WORLD)
	if last_world_exists: last_world_bytes = FileAccess.get_file_as_bytes(Entry.LAST_WORLD)
	action_speed = 1.0
	action_fault = "none"
	action_coordinate = Vector2i.ZERO
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_msec() > deadline: _finish(false, "300-second original ship physical deadline")
	return false

func _write_manifest() -> bool:
	return ShipCoastGenesis.write(self)

func _ship_team() -> TerrainArmy:
	for team: TerrainArmy in action_owner.combat_armies:
		if team.team_id == ship_team_id: return team
	return null

func _ship_vehicle(index: int) -> Dictionary:
	return action_owner.terrain.site.vehicles.get(ship_ids[index], {})

func _action_vehicle() -> Dictionary:
	return {} if ship_ids.is_empty() else _ship_vehicle(0)

func _ship_supply() -> Dictionary:
	return action_owner.site_controller._supply_entry(_ship_team())

func _ship_build_barrier(anchor: Vector2i, length: int) -> bool:
	var data := action_owner.terrain
	# A 1-wide north-south wall faces its work entrance east (quarter 3), on the
	# ship side the builder stands on. The default south quarter offers only the cell
	# below a segment's end, which for the last segment (ending at y 99) is off the map.
	var options := {"owner_faction": action_owner.character.faction_id, "quarter": 3}
	var layout: Dictionary = SiteRuntime.building_cells(data, "stone_wall", anchor, Vector2i(1, length), options)
	if not _check(layout.ok, "original legal land barrier layout respects per-request limits", layout): return false
	var cells: Array[int] = []; cells.assign(layout.cells)
	var before: Dictionary = data.site.inventory.duplicate(true)
	var built: Dictionary = SiteRuntime.request_build(data, "stone_wall", cells, Callable(), options)
	if not _check(built.ok, "GENESIS original wall request pays finite materials once", built): return false
	var key := str(built.feature)
	var feature: Dictionary = data.site.features[key]
	for resource: String in feature.cost:
		if not _check(int(data.site.inventory.get(resource, 0)) == int(before.get(resource, 0)) - int(feature.cost[resource]), "GENESIS wall material debit is exact", resource): return false
	var task := {"version": 2, "zone": -1, "target": "feature:" + key, "action": "construct", "work_cell": int(feature.entrance), "cell": int(feature.entrance), "mode": "work", "progress": 0.0, "status": "", "work_slot": -1}
	SiteRuntime._feature_work(data, key, float(feature.work), Callable(), Callable(), task, {}, 20, action_owner.character.faction_id)
	if not _check(str(feature.stage) == "complete", "GENESIS original structural work finishes without terrain or HP rewriting", key): return false
	ship_barriers.append(key)
	return true

func _setup_action_world() -> bool:
	lab = _shell()
	if not _check(lab != null, "original restore shell exists"): return false
	controller = lab.site_controller
	var archive := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345, {"size": Vector2i(32, 32)})
	Env.initialize(archive, "c06-ship-original:archive")
	lab.bind_terrain(archive)
	lab.restore_only = false
	controller.save_root = out.path_join("archive")
	world_id = "r0_siege_action_%d_ship_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened: Dictionary = controller.open_fixed_world(manifest_path, world_id, "main", Vector2i.ZERO, true)
	if not _check(opened.ok, "original Controller creates one named fixed coast World", opened): return false
	_freeze(lab)
	slot = controller.region_slot
	action_owner = lab
	lab.simulation_speed = action_speed
	var wired: Dictionary = lab._wire_region_gameplay_adapters(slot)
	if not _check(wired.ok, "original common Slot adapters wire the actual active owner", wired): return false
	var data := lab.terrain
	for key: String in data.resource_base: Env.change(data, key, {"cleared": true, "remaining": 0})
	data.site.capacity = 100000
	for resource: String in Env.ITEM_NAMES: data.site.inventory[resource] = 1000
	data.site.inventory.grain = int(ship_food_initial)
	data.site.depot_cell = data.index(Vector2i(30, 20))
	if not _check(SiteRuntime.initialize_item_storage(data.site).ok, "original Depot owns the finite authored genesis grain and building stock"): return false
	if not _check(lab.character.place(Vector2i(30, 21), true), "original founder is authored at an actual dry shore before paid work"): return false
	var actor: TerrainTestCharacter = lab.controlled_target().owner
	ship_actor_id = actor.person_id
	if not _check(actor == lab.character and lab.player_army() == null and float(data.site.get("combat_left", 0.0)) <= 0.0, "GENESIS uses original unaffiliated controlled Actor with no control identity rewrite"): return false
	var promoted: Dictionary = ShipGarrison.set_military_role(lab, ship_actor_id, "officer")
	if not _check(promoted.ok, "original Garrison role transaction qualifies the same Actor", promoted): return false
	var side := {"prefix": "friendly", "count": 3, "slot_count": 3, "female_count": 0, "faction": actor.faction_id, "training": 0.0, "role": "combat", "troop_type": "melee_infantry", "attack": false, "cart_count": 0, "wagon_count": 0, "abilities": {}, "ai_enabled": false}
	var other: Dictionary = side.duplicate(true)
	other.prefix = "enemy"; other.count = 1; other.slot_count = 1
	var sides: Array[Dictionary] = [side, other]
	var source_cells: Array[Vector2i] = [Vector2i(30, 24), Vector2i(30, 20), Vector2i(35, 20)]
	var other_cells: Array[Vector2i] = [Vector2i(31, 24)]
	var born: Dictionary = lab._deploy_trial_teams(sides, [source_cells, other_cells], 0)
	if not _check(born.ok, "original typed finite genesis allocates four real rows and original holders", born): return false
	var source: TerrainArmy = lab.combat_armies[0]
	var recipient: TerrainArmy = lab.combat_armies[1]
	var joined: Dictionary = source.join_player(actor)
	if not _check(joined.ok and source.player_member == actor, "original join keeps the actual Actor as role-only PLAYER_MEMBER", joined): return false
	var qualified: Dictionary = source.set_military_role(ship_actor_id, "officer")
	if not _check(qualified.ok, "original Army role transaction qualifies the joined Actor", qualified): return false
	var old_captain := source.combat_identity(source.formal_commander)
	var moved: Dictionary = source.transfer_members_to(recipient, [old_captain], source.current_commander, recipient.current_commander)
	if not _check(moved.ok and source.formal_commander == TerrainArmy.PLAYER_MEMBER and source.current_commander == TerrainArmy.PLAYER_MEMBER and source.command_eligible(source.current_commander), "original transfer and settle select the same controlled Actor Captain", moved): return false
	ship_team_id = source.team_id
	for row: Dictionary in source.combat_units: ship_people.append(int(row.person_id))
	if not _check(ship_people.size() == 2 and source.cells[0] == Vector2i(30, 20) and source.cells[1] == Vector2i(35, 20), "original transfer retains the two true shoreline bodies and positions"): return false
	var offices: Dictionary = source.team_offices()
	var seat_id := str(offices.duties.get("team.training", ""))
	var seat: Dictionary = SiteOffices.position(offices, seat_id)
	if not _check(not seat.is_empty() and not bool(seat.head) and str(seat.office_class) == "military" and int(seat.holder) <= 0, "original existing training duty has a vacant military seat"): return false
	var staffed: Dictionary = source.apply_office_plan(ship_actor_id, int(offices.revision), [{"op": "set_role", "person_id": ship_people[0], "role": "officer"}, {"op": "appoint", "position_id": seat_id, "person_id": ship_people[0]}])
	if not _check(staffed.ok and source.command_eligible(0) and source.is_serving_military(0), "original two-phase appointment seats the true future NPC Captain", staffed): return false
	for anchor: Vector2i in [Vector2i(30, 19), Vector2i(35, 19)]:
		var boat: Dictionary = controller.vehicles.deploy_ship(source, "ferry", anchor, Vector2i.LEFT, true)
		if not _check(boat.ok, "explicit original TEST_ONLY boat genesis admits complete hull and unique owner; production is outside scope", boat): return false
		ship_ids.append(str(boat.vehicle_id))
	if not _check(ship_ids.size() == 2 and ship_ids[0] != ship_ids[1] and controller.vehicles.ship_contacts(_ship_vehicle(0)).has(source.cells[0]) and controller.vehicles.ship_contacts(_ship_vehicle(1)).has(source.cells[1]), "two original full hulls have their genuine distinct shore contacts"): return false
	var person: Dictionary = controller.vehicles.ship_person(ship_people[0])
	var stocked: Dictionary = SiteRuntime.transfer_items(data, data.site.depot_items, data.site.inventory, person.holder, person.cargo, {"wood": 2}, [], int(data.site.depot_items.version), int(person.holder.version), SiteRuntime.CARRY_CAPACITY)
	if not _check(stocked.ok and int(person.cargo.get("wood", 0)) == 2, "GENESIS existing finite Depot stock transfers to the true row holder once", stocked): return false
	for segment: Vector2i in [Vector2i(20, 36), Vector2i(56, 36), Vector2i(92, 8)]:
		if not _ship_build_barrier(Vector2i(25, segment.x), segment.y): return false
	if not _check(data.path_between(Vector2i(30, 21), Vector2i(20, 21)).is_empty(), "original completed barrier closes the entire ground approach while source ocean stays open"): return false
	action_context = {"key": ship_ids[0], "crew": ship_people.duplicate(), "commander": ship_actor_id}
	if not _check(action_paid == 0.0 and action_game_paid == 0.0, "all named geography, body/boat birth and initial material work precede paid simulation"): return false
	var saved: Dictionary = controller.checkpoint_region_internal("region_checkpoint", true)
	if not _check(saved.ok, "original joint publisher stores authored owner graph and initial holders", saved): return false
	var due: Dictionary = slot.consume_due_region_events()
	return _check(due.ok and due.get("complete", false), "original same-point owners settle before actual positive intervals", due)

func _paid_ship_step(request: float = TerrainLab.EXCHANGE_ACTION_STEP) -> bool:
	if not _observe_ship_food_results(): return false
	var result: Dictionary = lab._advance_original_shared_step(request)
	if not _check(result.get("ok", false), "original common producer accepts actual ship/body/food work or due zero endpoint", result): return false
	if result.get("completed", false):
		if not _check(float(result.action_seconds) > 0.0 and float(result.game_seconds) > 0.0 and float(result.action_seconds) <= request + EPS, "one accepted original bounded positive interval owns both clocks", result): return false
		action_paid += float(result.action_seconds); action_game_paid += float(result.game_seconds)
		if action_trace.size() < 4000: action_trace.append({"action": result.action_seconds, "game": result.game_seconds, "observation": ship_observation, "world": slot.control.logical_game_seconds, "action_at": slot.control.fire_clock.action_seconds})
	else:
		if not _check(float(result.get("action_seconds", 0.0)) == 0.0 and float(result.get("game_seconds", 0.0)) == 0.0, "original due endpoint consumes zero elapsed work", result): return false
	return _observe_ship_food_results()

func _action_step() -> bool:
	return _paid_ship_step()

func _ship_until(predicate: Callable, label: String) -> bool:
	for count: int in range(18000):
		if predicate.call(): return _check(true, label)
		if Time.get_ticks_msec() > deadline: return _check(false, label + " exceeded deadline")
		if not _paid_ship_step(): return false
		if count % 60 == 0: await process_frame
	return _check(false, label + " exceeded bounded original caller attempts")

func _ship_job_facts() -> Dictionary:
	var result := {}
	for identity: int in ship_people:
		var job: Dictionary = action_owner.site_controller.person_actions._jobs.get(str(identity), {})
		var fields := {}
		for field: String in ["kind", "executor_id", "requester_id", "vehicle_id", "berth_id", "duration", "elapsed", "shore", "path", "test_dispatch", "retreat"]:
			if job.has(field): fields[field] = job[field]
		result[str(identity)] = fields
	return result

func _action_facts() -> Dictionary:
	var bodies := {}
	for identity: int in ship_people:
		var person: Dictionary = action_owner.site_controller.vehicles.ship_person(identity)
		if person.is_empty(): bodies[str(identity)] = {"missing": true}; continue
		bodies[str(identity)] = {"row": person.owner.materialized_combat_rows()[int(person.unit)].duplicate(true), "cell": person.cell, "moving": person.moving, "holder": person.holder.duplicate(true), "cargo": person.cargo.duplicate(true)}
	var supply := _ship_supply()
	var delivery := {}
	for field: String in ["requester_id", "player_id", "representative_id", "quantity", "left", "pending", "target_location", "source_version", "source_cell", "target_cell"]:
		if supply.get("delivery", {}).has(field): delivery[field] = supply.delivery[field]
	return {"vehicles": action_owner.terrain.site.vehicles.duplicate(true), "people": bodies, "jobs": _ship_job_facts(), "sustain": supply.get("sustain", {}).duplicate(true), "locations": supply.get("locations", {}).duplicate(true), "supply_revision": int(supply.get("revision", 0)), "delivery": delivery, "depot": action_owner.terrain.site.inventory.duplicate(true), "depot_holder": action_owner.terrain.site.depot_items.duplicate(true), "items": action_owner.terrain.site.item_records.duplicate(true), "captain": _ship_team().combat_identity(_ship_team().current_commander), "controlled": action_owner.controlled_person_id()}

func _partial_ready() -> bool:
	if ship_observation == "delivery":
		var job: Dictionary = _ship_supply().get("delivery", {})
		return not job.is_empty() and float(job.left) > EPS and float(job.left) < 2.0 + 0.2 * float(job.quantity) - EPS
	if ship_observation == "move":
		var move: Dictionary = _ship_vehicle(0).move
		return not move.is_empty() and float(move.elapsed) > EPS and float(move.elapsed) < float(move.duration) - EPS
	if ship_observation in ["board", "helm"]:
		for job: Dictionary in action_owner.site_controller.person_actions._jobs.values():
			if str(job.kind) in ["ship_board", "ship_helm"] and float(job.elapsed) > EPS and float(job.elapsed) < float(job.duration) - EPS: return true
		return false
	return true

func _reopen_actual_partial() -> bool:
	if not _observe_ship_food_results(): return false
	var facts := _action_facts()
	var clock := [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
	var saved: Dictionary = controller.checkpoint_region_internal("region_checkpoint", true)
	if not _check(saved.ok and facts == _action_facts() and clock == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence], "joint fullgraph checkpoint consumes no additional job, food, transfer or time", saved): return false
	var graph := _action_graph()
	if graph.is_empty(): return false
	var proof := slot.region_bind_proof(action_owner.terrain)
	var generation := int(slot._marker.generation)
	var reopened := RegionSaveSlot.new()
	var opened: Dictionary = reopened.open_map(slot.source, world_id, "main")
	if not _check(opened.ok and int(reopened._marker.generation) == generation, "fresh original Slot selects the exact same whole epoch", opened): return false
	var read: Dictionary = reopened.open_site(Vector2i.ZERO)
	if not _check(read.ok and read.data.site.has("region_snapshot"), "mode-aware original open retains complete active physical owner graph", read.get("code")): return false
	var restored := _restore_selected(read.data, reopened, false)
	if restored == null: return false
	lab = restored; controller = lab.site_controller; slot = reopened; action_owner = lab
	lab.simulation_speed = action_speed
	var next_graph := _action_graph()
	# The facts cross a saved JSON round trip and a fresh original Lab: the restored
	# rows read back whole-number ids as floats (person_id 3.0, target -1.0). Compare
	# them in the store's own saved JSON domain, as the inherited helper does; the
	# graph, partial job, bind proof and clocks stay exact.
	if not _check(not next_graph.is_empty() and _saved_json_domain(facts) == _saved_json_domain(_action_facts()) and graph == next_graph and _partial_ready() and proof == slot.region_bind_proof(action_owner.terrain) and clock == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence], "true cold bind restores every original body/boat/job/holder alias and both clocks", ship_observation): return false
	if not _observe_ship_food_results(): return false
	var before := var_to_bytes([slot.control, _action_facts(), next_graph])
	var retry: Dictionary = slot.consume_due_region_events()
	var retry_graph := _action_graph()
	if not _check(retry.ok and retry.get("complete", false) and before == var_to_bytes([slot.control, _action_facts(), retry_graph]), "same selected endpoint retry replays no work, meal or load/unload", retry): return false
	if not _observe_ship_food_results(): return false
	ship_cold_evidence.append({"observation": ship_observation, "proof": proof, "generation": generation, "clock": clock, "graph_sha256": SiegeCheckpoint.state_hash(graph), "whole_graph_equal": true, "facts": facts})
	return true

func _ship_public_cargo() -> bool:
	var owner: SiteController = action_owner.site_controller
	var person: Dictionary = owner.vehicles.ship_person(ship_people[0])
	var boat := _ship_vehicle(0)
	var before := [int(person.holder.version), int(boat.holder.version)]
	var loaded: Dictionary = owner.vehicles.transfer("person:" + str(ship_people[0]), ship_ids[0], {"wood": 2}, [], before[0], before[1], ship_actor_id, false)
	if not _check(loaded.ok and int(person.cargo.get("wood", 0)) == 0 and int(boat.cargo.get("wood", 0)) == 2 and int(person.holder.version) == before[0] + 1 and int(boat.holder.version) == before[1] + 1, "false-dispatch public LOAD moves the finite actual person stack and both versions exactly once", loaded): return false
	var source := var_to_bytes([person.cargo, person.holder, boat.cargo, boat.holder, slot.control])
	var empty: Dictionary = owner.vehicles.transfer("person:" + str(ship_people[0]), ship_ids[0], {"wood": 2}, [], int(person.holder.version), int(boat.holder.version), ship_actor_id, false)
	if not _check(not empty.ok and source == var_to_bytes([person.cargo, person.holder, boat.cargo, boat.holder, slot.control]), "actual empty source refuses a second finite LOAD without extra stock/version/time", empty): return false
	var unloaded: Dictionary = owner.vehicles.transfer(ship_ids[0], "person:" + str(ship_people[0]), {"wood": 2}, [], int(boat.holder.version), int(person.holder.version), ship_actor_id, false)
	return _check(unloaded.ok and int(person.cargo.get("wood", 0)) == 2 and int(boat.cargo.get("wood", 0)) == 0 and int(person.holder.version) == before[0] + 2 and int(boat.holder.version) == before[1] + 2, "false-dispatch public UNLOAD returns the same finite stack through real shore contact", unloaded)

func _ship_board(index: int, cold_partial: bool) -> bool:
	ship_observation = "board"
	var begun: Dictionary = action_owner.site_controller.person_actions.begin_ship_board(ship_people[index], ship_ids[index], 1, ship_actor_id, false)
	if not _check(begun.ok and not action_owner.site_controller.vehicles.is_embarked(ship_people[index]), "false-dispatch public boarding creates a pending true job without premature attachment", begun): return false
	if cold_partial:
		if not await _ship_until(func() -> bool: return _partial_ready(), "actual paid boarding obtains a true partial interval"): return false
		if not await _reopen_actual_partial(): return false
	if not await _ship_until(func() -> bool: return action_owner.site_controller.vehicles.is_embarked(ship_people[index]) and not action_owner.site_controller.person_actions.is_busy(ship_people[index]), "original paid boarding commits its actual berth exactly once"): return false
	var person: Dictionary = action_owner.site_controller.vehicles.ship_person(ship_people[index])
	return _check(str(person.row.embarked_vehicle_id) == ship_ids[index] and int(person.row.berth_id) == 1, "true body attachment uses the requested original boat and berth", person.row)

func _ship_public_food() -> bool:
	ship_observation = "delivery"
	var before_depot := int(action_owner.terrain.site.inventory.grain)
	var before_holder := int(action_owner.terrain.site.depot_items.version)
	ship_food_source_site = str(action_owner.terrain.site.id)
	if not _observe_ship_food_results(): return false
	var before_food := ship_consumed_rations
	var begun: Dictionary = action_owner.site_controller.begin_team_food(_ship_team(), 4.0, ship_people[0], {"kind": "depot"})
	if not _check(begun.ok and not _ship_supply().delivery.is_empty() and int(action_owner.terrain.site.inventory.grain) == before_depot, "public finite Depot fill starts an actual productive-time job with no immediate debit", begun): return false
	for attempt: int in range(12):
		if _partial_ready(): break
		if not _paid_ship_step(0.001): return false
	if not _check(_partial_ready(), "food partial contains actual paid GAME work with positive retained left"): return false
	if not await _reopen_actual_partial(): return false
	if not await _ship_until(func() -> bool: return _ship_supply().delivery.is_empty(), "same real cold delivery continues and commits finite food once"): return false
	var supply := _ship_supply()
	var boat_key := "vehicle:" + ship_ids[0]
	if not _check(int(action_owner.terrain.site.inventory.grain) == before_depot - 4 and int(action_owner.terrain.site.depot_items.version) == before_holder + 1 and supply.locations.has(boat_key), "real completed Depot fill debits exactly four finite units and creates only the actual receiving boat pool"): return false
	var held := 0.0
	for stock: Dictionary in supply.locations.values(): held += PhysicalSustain.rations(stock, stock.inventory)
	var consumed := ship_consumed_rations - before_food
	if not _check(absf(held + consumed - 4.0) <= EPS, "finite original held plus consumed meal conserves the four actual delivered rations", {"held": held, "consumed": consumed}): return false
	var shore_key := "shore:%d" % action_owner.terrain.index(Vector2i(30, 20))
	var revision := int(supply.revision)
	var unloaded: Dictionary = action_owner.site_controller.transfer_ship_supply(_ship_team(), boat_key, shore_key, {"grain": 1}, 0.0, ship_actor_id, false)
	if not _check(unloaded.ok and int(_ship_supply().revision) == revision + 1 and int(_ship_supply().locations[shore_key].inventory.get("grain", 0)) == 1, "false-dispatch public food UNLOAD uses the real boat/shore contact and version once", unloaded): return false
	if not _observe_ship_food_results(): return false
	var loaded: Dictionary = action_owner.site_controller.transfer_ship_supply(_ship_team(), shore_key, boat_key, {"grain": 1}, 0.0, ship_actor_id, false)
	if not _check(loaded.ok and int(_ship_supply().revision) == revision + 2 and int(_ship_supply().locations[shore_key].inventory.get("grain", 0)) == 0, "false-dispatch public food LOAD returns the same finite shore stack without minting a meal", loaded): return false
	if not _observe_ship_food_results(): return false
	var facts := var_to_bytes([_ship_supply().locations, _ship_supply().sustain, _ship_supply().revision, slot.control])
	var empty: Dictionary = action_owner.site_controller.transfer_ship_supply(_ship_team(), shore_key, boat_key, {"grain": 1}, 0.0, ship_actor_id, false)
	if not _check(slot.take_original_food_results().is_empty(), "rejected original transfer publishes no accepted food result"): return false
	return _check(not empty.ok and facts == var_to_bytes([_ship_supply().locations, _ship_supply().sustain, _ship_supply().revision, slot.control]), "the actual empty shore pool refuses another LOAD without food, hunger, version or clock drift", empty)

func _ship_helm(index: int, cold_partial: bool) -> bool:
	ship_observation = "helm"
	var begun: Dictionary = action_owner.site_controller.person_actions.begin_ship_helm(ship_people[index], ship_ids[index], ship_actor_id, false)
	if not _check(begun.ok and int(_ship_vehicle(index).operator_id) == 0, "false-dispatch public helm job keeps the true uncommitted operator empty", begun): return false
	if cold_partial:
		if not await _ship_until(_partial_ready, "original paid helm job obtains real retained partial progress"): return false
		if not await _reopen_actual_partial(): return false
	if not await _ship_until(func() -> bool: return int(_ship_vehicle(index).operator_id) == ship_people[index] and not action_owner.site_controller.person_actions.is_busy(ship_people[index]), "original helm path completes and seats the true body as operator"): return false
	return _check(action_owner.site_controller.vehicles.ship_driver_ready(_ship_vehicle(index)) and action_owner.site_controller.vehicles.ship_crew_count(_ship_vehicle(index)) == 1, "each genuine ferry has its original one capable crew at actual helm")

func _ship_open_sea_positive() -> bool:
	ship_observation = "move"
	var data := action_owner.terrain
	if not _check(data.path_between(Vector2i(30, 21), Vector2i(20, 21)).is_empty(), "closed original land approach remains closed after genuine loading and boarding"): return false
	var source_cell := int(_ship_vehicle(0).cell)
	var begun: Dictionary = action_owner.site_controller.vehicles.ship_order(ship_ids[0], "sail", Vector2i(23, 19), ship_actor_id, false)
	if not _check(begun.ok, "false-dispatch original sail command takes the actual open sea route beside the closed land barrier", begun): return false
	if not await _ship_until(_partial_ready, "original whole-hull reservation obtains actual paid sea displacement"): return false
	if not await _reopen_actual_partial(): return false
	var paid_before := action_paid
	if not await _ship_until(func() -> bool: return int(_ship_vehicle(0).cell) == action_owner.terrain.index(Vector2i(23, 19)) and _ship_vehicle(0).move.is_empty() and _ship_vehicle(0).command.is_empty(), "same restored original whole hull completes the positive sea crossing"): return false
	return _check(source_cell != int(_ship_vehicle(0).cell) and action_paid > paid_before and action_owner.terrain.path_between(Vector2i(30, 21), Vector2i(20, 21)).is_empty(), "true accepted hull movement crosses the barrier's ocean end while ground stays blocked")

func _ship_original_two_boat_closure() -> bool:
	ship_observation = "settled"
	var team := _ship_team()
	if not _check(team.current_commander == TerrainArmy.PLAYER_MEMBER and team.command_eligible(team.current_commander) and team.command_eligible(team.index_for_identity(ship_people[0])), "original Actor Captain and appointed actual NPC successor remain eligible before public leave"): return false
	var left: Dictionary = action_owner.leave_player_army()
	team = _ship_team()
	if not _check(left.ok and team.player_member == null and team.combat_identity(team.formal_commander) == ship_people[0] and team.combat_identity(team.current_commander) == ship_people[0] and team.command_eligible(team.current_commander), "public original leave and serving-cadre succession select the same true NPC Captain without control rewrite", left): return false
	if not await _reopen_actual_partial(): return false
	var captured: Dictionary = action_owner.site_controller._capture_for_save()
	if not _check(captured.ok, "original capture derives departure bytes from the actual restored physical owners", captured): return false
	var state: Dictionary = action_owner.terrain.site
	var source := var_to_bytes(state)
	var closure: Dictionary = Travel.extract(state, {"mode": "sea", "controller": "npc", "team_id": ship_team_id, "person_id": ship_people[0], "game_seconds": float(slot.control.logical_game_seconds)}, "c06_physical_source_closure_%d" % OS.get_process_id())
	if not _check(closure.ok and source == var_to_bytes(state), "original NPC sea extraction accepts genuine full two-boat closure and preserves its physical source", closure.get("code")): return false
	var party: Dictionary = closure.party
	if not _check(party.person_ids == ship_people and party.vehicle_ids == ship_ids and party.content.actors.is_empty() and not party.person_ids.has(ship_actor_id) and closure.origin.actors.has("player"), "true original closure carries exactly two actual bodies/boats and leaves the same shore Actor at source", party.person_ids): return false
	var owners: Array[Dictionary] = Travel._feeding(party.content, Travel._body_records(party.content))
	var food_key := "vehicle:" + ship_ids[0]
	if not _check(owners.size() == 1 and owners[0].stock.has(food_key) and not owners[0].stock.has("vehicle:" + ship_ids[1]) and str(owners[0].context.food_locations[ship_people[0]]) == food_key and str(owners[0].context.food_locations[ship_people[1]]) == "", "actual boarded/filled/unloaded original closure uses own boat pool and empty access on the missing second pool"): return false
	var transport: Dictionary = Travel.prepare_transport(party.duplicate(true))
	if not _check(transport.ok and transport.can_move and Travel.party_speed(party.content) > 0.0, "original true two-helm closure remains sea-capable with a missing food pool", transport.get("code")): return false
	report["physical_source_closure"] = {"people": party.person_ids, "boats": party.vehicle_ids, "captain": ship_people[0], "source_actor": ship_actor_id, "food_locations": owners[0].context.food_locations, "party": party, "formal_world_departure": "OPEN_NOT_RUN", "npc_dispatch_and_region_route": "OPEN_NOT_RUN"}
	return true

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest() or not _setup_action_world(): _finish(); return
	if not _ship_public_cargo(): _finish(); return
	if not await _ship_board(0, true): _finish(); return
	if not await _ship_public_food(): _finish(); return
	if not await _ship_board(1, false): _finish(); return
	if not _check(not _ship_supply().locations.has("vehicle:" + ship_ids[1]), "second real boarding does not mint a missing own boat pool"): _finish(); return
	if not await _ship_helm(0, false) or not await _ship_helm(1, true): _finish(); return
	if not await _ship_open_sea_positive(): _finish(); return
	if not await _ship_original_two_boat_closure(): _finish(); return
	report["physical_cold_epochs"] = ship_cold_evidence
	report["actual_positive_action"] = action_paid
	report["actual_positive_game"] = action_game_paid
	_finish()

func _finish(ok: bool = true, message: String = "") -> void:
	if finished: return
	finished = true
	failed = failed or not ok
	if not message.is_empty(): printerr(message)
	paused = false
	for scene: TerrainLab in capture_scenes:
		if is_instance_valid(scene): scene.free()
	var current: Variant = JSON.parse_string(FileAccess.get_file_as_string(Entry.LAST_WORLD)) if FileAccess.file_exists(Entry.LAST_WORLD) else null
	if current is Dictionary and str(current.get("world_id", "")) == world_id:
		if last_world_exists:
			var restored := FileAccess.open(Entry.LAST_WORLD, FileAccess.WRITE); restored.store_buffer(last_world_bytes); restored.close()
		else: DirAccess.remove_absolute(ProjectSettings.globalize_path(Entry.LAST_WORLD))
	TerrainArmy.release_contact_source()
	var receipt := {"failed": failed, "checks": checks, "report": report, "checks_evidence": action_evidence, "actual_interval_trace": action_trace, "scope": "original public finite cargo/food work, two physical boat attachments/helms, active whole owner graph cold bind, ground barrier/open local sea and actual physical-source NPC extraction; named/test-only genesis; no formal World NPC dispatch/sea Party bind, full six cases, parser/native/performance/release acceptance"}
	var file := FileAccess.open(out.path_join("ship_finite_food_physical_receipt.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(receipt, "\t", true, true)); file.close()
	print("REGION_SHIP_FINITE_FOOD_PHYSICAL_", "FAILED" if failed else "PASS", " checks=", checks)
	quit(1 if failed else 0)
func _observe_ship_food_results() -> bool:
	for result: Dictionary in slot.take_original_food_results():
		var local_team: bool = result.owner_kind == "team" and result.owner_id == str(ship_team_id) and result.site_id == ship_food_source_site
		var actual_party: bool = not ship_food_party_token.is_empty() and result.owner_kind == "party" and result.owner_id == ship_food_party_token
		if not local_team and not actual_party: continue
		var consumed := float(result.consumed_rations)
		if not _check(is_finite(consumed) and consumed > 0.0, "observed food consumption is the positive original accepted per-call return", result): return false
		ship_consumed_rations += consumed
		ship_food_results.append(result.duplicate(true))
	return _check(slot.take_original_food_results().is_empty(), "original accepted result readout drains once and retries replay no consumption")
