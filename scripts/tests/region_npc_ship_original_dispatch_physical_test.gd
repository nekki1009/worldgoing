extends "res://scripts/tests/region_ship_finite_food_physical_test.gd"
## Source continuation of the v2 actual public ship lane, not an extract surrogate.
var sea_nation_id := ""
var sea_nation_head := 0
var sea_token := ""
var sea_goal_coordinate := Vector2i(-1, 0)
var sea_observation: Dictionary = {}
var sea_departure_refs: Dictionary = {}
var sea_cold_evidence: Array[Dictionary] = []
var sea_food_held_begin := 0.0
var sea_food_consumed_begin := 0.0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 420000
	out = "res://.godot-temp/region_c06_npc_ship_dispatch/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	last_world_exists = FileAccess.file_exists(Entry.LAST_WORLD)
	if last_world_exists: last_world_bytes = FileAccess.get_file_as_bytes(Entry.LAST_WORLD)
	action_speed = 1.0
	action_fault = "none"
	action_coordinate = Vector2i.ZERO
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_msec() > deadline: _finish(false, "420-second original NPC ship dispatch deadline")
	return false

## Crowd port: the base walks the ship bodies to their contacts through the first paid interval, so this Nation and
## destination genesis runs in its pre-paid genesis hook.
func _ship_more_genesis() -> bool:
	if not super._ship_more_genesis(): return false
	# This finite initial Nation is the existing original-test GENESIS boundary.
	# All member IDs and the resident dispatch head come from the original bodies.
	# Crowd port (2026-11-08): the ship team and the resident team are crowd owners; the player's start team (the shore
	# person and its cadres) is not a Nation member, as the old shore Actor was not.
	var members: Array[int] = []
	var headquarters: Variant = null
	for owner: Variant in lab.crowd_site.person_owners():
		if not owner is CrowdPersonOwner: continue
		if int(owner.team_id) != ship_team_id and int(owner.team_id) != ship_resident_team_id: continue
		for index: int in owner.records: members.append(owner.combat_identity(index))
		if int(owner.team_id) == ship_resident_team_id: headquarters = owner
	if not _check(headquarters != null and headquarters.command_eligible(int(headquarters.current_commander)), "initial true resident HQ captain supplies the original Nation head"): return false
	sea_nation_head = headquarters.combat_identity(int(headquarters.current_commander))
	sea_nation_id = "c06_ship_source_nation_%d" % OS.get_process_id()
	# A Site with no Nation yet has no equipment_nations container; the original
	# trial Nation register creates it the same way before its first Nation.
	if not lab.terrain.site.has("equipment_nations"): lab.terrain.site.equipment_nations = {}
	lab.terrain.site.equipment_nations[sea_nation_id] = {"members": members, "standards": {}, "offices": SiteOffices.default_offices("nation", sea_nation_head, true)}
	var offices: Dictionary = lab.terrain.site.equipment_nations[sea_nation_id].offices
	var explicit_head: Dictionary = lab.site_controller.equipment_orders.apply_nation_office_plan(sea_nation_head, sea_nation_id, int(offices.revision), [{"op": "assign", "duty_id": "nation.dispatch", "position_id": str(SiteOffices.head_position(offices).id)}])
	if not _check(explicit_head.ok and sea_nation_head != lab.controlled_person_id(), "original public office transaction assigns strategic dispatch to its actual NPC head", explicit_head): return false
	var destination: Dictionary = lab._region_gameplay_owner_lab(Grid.site_id(str(slot.pin.atlas_id), sea_goal_coordinate), "cold_exact")
	if not _check(destination.ok and destination.lab is TerrainLab, "original adjacent coast Site has its actual complete cold owner", destination.get("code")): return false
	_freeze(destination.lab)
	if not _check(action_paid == 0.0 and action_game_paid == 0.0, "initial Nation and destination birth precede all actual productive or tactical intervals"): return false
	return _check(controller.checkpoint_region_internal("region_checkpoint", true).ok, "original joint publication stores initial Nation and both actual Site graphs")

func _sea_selected() -> Dictionary:
	return slot._region_npc_party(sea_token)

func _sea_plan() -> Dictionary:
	return slot._region_npc_plan(sea_token)

func _sea_owner() -> Dictionary:
	# The game creates an NPC party's original owner Lab at its zero-time endpoint, which also records the Lab's own
	# capture as the party (RegionSaveSlot._finish_original_cold_region_points -> region_original_party_zero). A crowd
	# departure carries entry rows (cadre seating, integer fields, aboard slots) that are canonical only after that first
	# capture, so the first owner of this party comes from the same endpoint, not from a bare bind of the entry rows.
	# (A reopened slot before its original Lab wires the Region adapters has no endpoint to run; its party record is
	# already a checkpoint capture.)
	if not is_instance_valid(slot.get_meta(&"region_party_owner_labs", {}).get(sea_token)) and slot.region_original_party_zero.is_valid():
		var settled: Variant = slot.region_original_party_zero.call()
		if not settled is Dictionary or not settled.get("ok", false): return settled if settled is Dictionary else {"ok": false, "code": "INCOMPLETE_PARTY_ENDPOINT"}
	var selected := _sea_selected()
	if not selected.ok: return selected
	return lab.prepare_region_party_original_owner(sea_token, selected.party, slot)

func _sea_goal() -> Dictionary:
	return lab._region_gameplay_owner_lab(Grid.site_id(str(slot.pin.atlas_id), sea_goal_coordinate), "cold_exact")

func _sea_site_graph(original: TerrainLab) -> Dictionary:
	var context: Dictionary = slot.region_checkpoint_context(original.terrain, "region_checkpoint", "c06_sea_source_observer", true, {})
	if not _check(context.ok, "actual original Site graph receives the current common context", context): return {}
	var captured: Dictionary = original.capture_region_owner_state(context.context)
	if not _check(captured.ok and captured.owner_states.get("scene") is Dictionary, "actual original Site graph captures every original owner alias", captured.get("code")): return {}
	return {"root": captured.owner_states.scene.root.duplicate(true), "nodes": captured.owner_states.scene.nodes.duplicate(true)}

func _sea_graphs(in_transit: bool) -> Dictionary:
	var goal: Dictionary = _sea_goal()
	if not _check(goal.ok, "current Slot resolves the exact destination owner", goal.get("code")): return {}
	var graphs := {"source": _sea_site_graph(lab), "destination": _sea_site_graph(goal.lab)}
	if graphs.source.is_empty() or graphs.destination.is_empty(): return {}
	if in_transit:
		var selected: Dictionary = _sea_selected()
		var owner: Dictionary = _sea_owner()
		if not _check(selected.ok and owner.ok, "original selected party and complete actual host resolve together", owner.get("code")): return {}
		var proof: Dictionary = slot.region_original_party_runtime_proof(sea_token, selected.party)
		if not _check(proof.ok and proof.lab == owner.lab, "same original runtime proof names the current complete NPC party host", proof.get("code")): return {}
		var captured: Dictionary = slot._region_capture_party_graph(sea_token, selected.party)
		if not _check(captured.ok and not captured.original_live_graph.is_empty(), "original full party graph retains actual sparse body and transport owners", captured.get("code")): return {}
		var owners: Dictionary = captured.original_live_graph.owners
		graphs["party"] = {"root": owners.scene.root.duplicate(true), "nodes": owners.scene.nodes.duplicate(true), "transport": owners.transport.duplicate(true)}
	return graphs

## A fresh-Slot reopen restores the actual destination cold owner from the same
## selected commit, exactly as the inherited reopen restores its cold action owner,
## and the common factory adopts that same original. Without it the fresh Slot has
## no original for the destination and refuses to advance its stale saved body.
func _restore_sea_goal_owner() -> bool:
	var cold_read: Dictionary = slot.open_site(sea_goal_coordinate)
	if not _check(cold_read.ok and cold_read.data.site.has("region_snapshot"), "mode-aware open retains the destination's real cold fullgraph", cold_read.get("code")): return false
	var next_cold := _restore_selected(cold_read.data, slot, true)
	if next_cold == null: return false
	slot._region_original_labs[str(next_cold.terrain.site.id)] = next_cold
	var adopted: Dictionary = lab._region_gameplay_owner_lab(str(next_cold.terrain.site.id), "cold_exact")
	if not _check(adopted.ok and adopted.lab == next_cold, "actual factory uses the same positively restored destination cold owner", adopted.get("code")): return false
	_freeze(next_cold)
	return true

func _reopen_actual_partial() -> bool:
	if not await super._reopen_actual_partial(): return false
	return _restore_sea_goal_owner()

## Test-only failure evidence: the first differing path between two states,
## comparing key names, key types, sizes and values.
func _sea_first_difference(first: Variant, second: Variant, path: String) -> String:
	if typeof(first) != typeof(second): return "%s type %d != %d" % [path, typeof(first), typeof(second)]
	if first is Dictionary:
		var first_names: Dictionary = {}
		var second_names: Dictionary = {}
		for key: Variant in first: first_names[str(key)] = key
		for key: Variant in second: second_names[str(key)] = key
		for label: String in first_names:
			if not second_names.has(label): return "%s/%s missing after" % [path, label]
			var own_key: Variant = first_names[label]
			var other: Variant = second_names[label]
			if typeof(own_key) != typeof(other): return "%s/%s key type %d != %d" % [path, label, typeof(own_key), typeof(other)]
			var inner: String = _sea_first_difference(first[own_key], second[other], path + "/" + label)
			if not inner.is_empty(): return inner
		for label: String in second_names:
			if not first_names.has(label): return "%s/%s added after" % [path, label]
		return ""
	if first is Array:
		if first.size() != second.size(): return "%s size %d != %d" % [path, first.size(), second.size()]
		for index: int in range(first.size()):
			var inner: String = _sea_first_difference(first[index], second[index], "%s[%d]" % [path, index])
			if not inner.is_empty(): return inner
		return ""
	if first is PackedByteArray and first != second:
		return _sea_first_difference(bytes_to_var(first), bytes_to_var(second), path + "<bytes>")
	return "" if first == second else "%s value %s != %s" % [path, str(first).left(200), str(second).left(200)]

## Test-only failure evidence: up to `cap` differing paths, in walk order.
func _sea_differences(first: Variant, second: Variant, path: String, cap: int) -> Array:
	var found: Array = []
	_sea_collect_differences(first, second, path, cap, found)
	return found

func _sea_collect_differences(first: Variant, second: Variant, path: String, cap: int, found: Array) -> void:
	if found.size() >= cap: return
	if typeof(first) != typeof(second):
		found.append("%s type %d != %d" % [path, typeof(first), typeof(second)])
		return
	if first is Dictionary:
		var first_names: Dictionary = {}
		var second_names: Dictionary = {}
		for key: Variant in first: first_names[str(key)] = key
		for key: Variant in second: second_names[str(key)] = key
		for label: String in first_names:
			if found.size() >= cap: return
			if not second_names.has(label):
				found.append("%s/%s missing after" % [path, label])
				continue
			var own_key: Variant = first_names[label]
			var other: Variant = second_names[label]
			if typeof(own_key) != typeof(other):
				found.append("%s/%s key type %d != %d" % [path, label, typeof(own_key), typeof(other)])
				continue
			_sea_collect_differences(first[own_key], second[other], path + "/" + label, cap, found)
		for label: String in second_names:
			if found.size() >= cap: return
			if not first_names.has(label): found.append("%s/%s added after" % [path, label])
		return
	if first is Array:
		if first.size() != second.size():
			found.append("%s size %d != %d" % [path, first.size(), second.size()])
			return
		for index: int in range(first.size()): _sea_collect_differences(first[index], second[index], "%s[%d]" % [path, index], cap, found)
		return
	if first is PackedByteArray and first != second:
		_sea_collect_differences(bytes_to_var(first), bytes_to_var(second), path + "<bytes>", cap, found)
		return
	if first != second: found.append("%s value %s != %s" % [path, str(first).left(200), str(second).left(200)])

## The changed fields of every stored siege snapshot, without its own source
## stamp and hash, so the readout names the original body/structure field.
func _sea_siege_differences(before_control: Dictionary, after_control: Dictionary, cap: int) -> Array:
	var found: Array = []
	var before_battles: Dictionary = before_control.get("region_gameplay", {}).get("battles", {})
	var after_battles: Dictionary = after_control.get("region_gameplay", {}).get("battles", {})
	for id: Variant in before_battles:
		var old_siege: Dictionary = before_battles[id].get("siege", {})
		var new_siege: Dictionary = after_battles.get(id, {}).get("siege", {})
		for field: Variant in old_siege:
			if str(field) in ["source", "source_sha256"]: continue
			_sea_collect_differences(old_siege[field], new_siege.get(field), "battles/%s/siege/%s" % [str(id), str(field)], cap, found)
	return found

## Test-only hooks for subclass evidence; the base records nothing.
func _sea_after_checkpoint() -> void:
	pass

func _sea_retry_failure_extra() -> Dictionary:
	return {}

func _sea_reopen(in_transit: bool) -> bool:
	if not _observe_ship_food_results(): return false
	var clock := [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
	var saved: Dictionary = controller.checkpoint_region_internal("region_checkpoint", true)
	if not _check(saved.ok and clock == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence], "actual joint sea checkpoint consumes zero extra time", saved): return false
	_sea_after_checkpoint()
	var graphs := _sea_graphs(in_transit)
	if graphs.is_empty(): return false
	var reference: Dictionary = slot.region_registry().parties[sea_token].duplicate(true)
	var selected: Dictionary = _sea_selected() if in_transit else {}
	var party_bytes := var_to_bytes(selected.party) if in_transit else PackedByteArray()
	var proof: Dictionary = slot.region_live_party_proof(sea_token).proof if in_transit else {}
	var reopened := RegionSaveSlot.new()
	var opened: Dictionary = reopened.open_map(slot.source, world_id, "main")
	if not _check(opened.ok and int(reopened._marker.generation) == int(slot._marker.generation), "fresh Slot chooses the same source/party/destination publication", opened): return false
	var read: Dictionary = reopened.open_site(Vector2i.ZERO)
	if not _check(read.ok and read.data.site.has("region_snapshot"), "fresh selected source retains its whole original graph", read.get("code")): return false
	var restored := _restore_selected(read.data, reopened, false)
	if restored == null: return false
	lab = restored; controller = lab.site_controller; slot = reopened; action_owner = lab
	lab.simulation_speed = action_speed
	if not _restore_sea_goal_owner(): return false
	var next_graphs := _sea_graphs(in_transit)
	# Owner graphs are stored in the Store's saved JSON (plain JSON numbers), so they
	# are compared in that domain, exactly as the inherited reopen and the cold bind
	# compare them; the registry reference and both clocks stay exact.
	var reopen_facts := {"graphs_present": not next_graphs.is_empty(),
		"source": _saved_json_domain(graphs.get("source")) == _saved_json_domain(next_graphs.get("source")),
		"destination": _saved_json_domain(graphs.get("destination")) == _saved_json_domain(next_graphs.get("destination")),
		"party": _saved_json_domain(graphs.get("party")) == _saved_json_domain(next_graphs.get("party")),
		"reference": reference == slot.region_registry().parties[sea_token],
		"clock": clock == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]}
	if not _check(not reopen_facts.values().has(false), "true selected reopen preserves both full Sites and the full actual party graph without clock drift", reopen_facts): return false
	if in_transit:
		var next: Dictionary = _sea_selected()
		if not _check(next.ok and party_bytes == var_to_bytes(next.party) and proof == slot.region_live_party_proof(sea_token).proof, "actual sea cursor, body, stock, holders and selected proof survive full cold reopen"): return false
	# A manual fresh-Slot reopen wires the restored main original as the common
	# adapter host, as the original controller did for the first Slot (the inherited
	# reopen does the same after its own graph comparison).
	var rewired := lab._wire_region_gameplay_adapters(slot)
	if not _check(rewired.ok, "fresh Slot adapters wire to the positively restored main original", rewired): return false
	if not _observe_ship_food_results(): return false
	var before_state := [slot.control.duplicate(true), _sea_graphs(in_transit)]
	var before := var_to_bytes(before_state)
	var retry: Dictionary = slot.consume_due_region_events()
	var after_state := [slot.control.duplicate(true), _sea_graphs(in_transit)]
	var unchanged := before == var_to_bytes(after_state)
	if not _check(retry.ok and retry.get("complete", false) and unchanged, "same selected sea endpoint retry owns zero time and no duplicate physical arrival",
		retry if unchanged else {"retry": retry, "first_difference": _sea_first_difference(before_state, after_state, "[control, graphs]"),
		"differences": _sea_differences(before_state, after_state, "[control, graphs]", 10), "siege_differences": _sea_siege_differences(before_state[0], after_state[0], 10),
		"extra": _sea_retry_failure_extra()}): return false
	if not _observe_ship_food_results(): return false
	sea_cold_evidence.append({"in_transit": in_transit, "clock": clock, "reference": reference, "graphs": graphs, "proof": proof})
	return true

func _sea_dispatch() -> bool:
	sea_token = "c06_original_npc_ship_%d" % OS.get_process_id()
	# Stable person/team/nation/vehicle refs come from the original travel identity
	# allocator, which a departure would run; nothing has travelled from this Site
	# yet, and the resident head's observation needs them first. They index the
	# actual current Site, and the same whole-graph checkpoint publishes them.
	var identified := RegionTravel.prepare_identity(lab.terrain.site)
	if not _check(identified.ok, "original identity allocator indexes the source Site's nation, teams, people and boats", identified): return false
	lab.terrain.site.travel_identity = identified.state.travel_identity
	if not _check(controller.checkpoint_region_internal("region_checkpoint", true).ok, "the indexed source identity publishes with the same whole graphs"): return false
	if not _check(preload("res://scripts/region_lab/region_gameplay_ai.gd").valid_person_ref(preload("res://scripts/region_lab/region_gameplay_ai.gd").person_ref(lab.terrain.site, sea_nation_head)), "the resident Nation head has a real typed person reference"): return false
	var before := var_to_bytes([slot.control, lab.terrain.site])
	var unknown: Dictionary = slot.prepare_npc_region_dispatch(lab, sea_nation_id, ship_team_id, sea_goal_coordinate, 0, [], sea_token)
	if not _check(not unknown.ok and str(unknown.code) == "UNKNOWN_TARGET" and before == var_to_bytes([slot.control, lab.terrain.site]), "original Nation refuses dispatch before its true scoped geography observation", unknown): return false
	var observed: Dictionary = slot.record_region_officer_geography_observation(lab, sea_nation_head, sea_goal_coordinate)
	if not _check(observed.ok and observed.receipt.value.keys().size() == 3 and not observed.receipt.value.has("power"), "actual original officer observes only public Atlas geography at its settled clock", observed): return false
	sea_observation = observed.receipt.duplicate(true)
	var goal: Dictionary = _sea_goal()
	if not _check(goal.ok and not lab.controlled_target().is_empty(), "both true original owners are bound before actual dispatch", goal.get("code")): return false
	var prepared: Dictionary = slot.prepare_npc_region_dispatch(lab, sea_nation_id, ship_team_id, sea_goal_coordinate, 0, [], sea_token)
	if not _check(prepared.ok and prepared.party.mode == "sea" and prepared.plan.version == 2 and prepared.plan.action_steps.size() > 0 and prepared.request.known_receipt == str(sea_observation.id) and prepared.request.decider == sea_nation_head, "original Nation authority and original Route compile actual two-hull adjacent sea ACTION steps", prepared.get("code")): return false
	sea_departure_refs = prepared.party.content.travel_identity.refs.duplicate(true)
	var people: Array = prepared.party.person_ids.duplicate()
	people.sort()
	var expected_people: Array = ship_people.duplicate()
	expected_people.sort()
	if not _check(people == expected_people and prepared.party.content.actors.is_empty() and not prepared.party.content.equipment_nations.has(sea_nation_id), "original partial Nation membership travels with genuine two-row closure while its sole head remains resident"): return false
	var clock := [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds]
	var committed: Dictionary = slot.commit_npc_region_dispatch(prepared)
	if not _check(committed.ok and slot.region_registry().parties[sea_token].phase == "travelling" and clock == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds] and lab.controlled_person_id() == ship_actor_id, "original one-marker source removal and real NPC party publication retain human control and pay no extra interval", committed): return false
	for boat: String in ship_ids:
		if not _check(not lab.terrain.site.vehicles.has(boat), "source actually relinquishes the dispatched hull once", boat): return false
	var owner: Dictionary = _sea_owner()
	var selected := _sea_selected()
	if not _check(selected.ok, "food baseline comes from the genuine committed NPC party", selected.get("code")): return false
	ship_food_party_token = sea_token
	sea_food_consumed_begin = ship_consumed_rations
	for supply: Dictionary in selected.party.content.get("team_supply", {}).values(): sea_food_held_begin += PhysicalSustain.rations(supply.sustain, supply.locations)
	if not _check(absf(sea_food_held_begin + ship_consumed_rations - 4.0) <= EPS, "real outbound food plus original accepted consumption conserves the four finite delivered rations"): return false
	return _check(owner.ok and owner.lab is TerrainLab and owner.lab.terrain.site.id == "travel:" + sea_token and owner.lab.terrain.site.controlled_person_id == -1, "original complete NPC party host owns actual bodies and hull projection without controlled NPC", owner.get("code"))

func _sea_partial() -> bool:
	if str(slot.region_registry().parties[sea_token].phase) != "travelling": return false
	var selected := _sea_selected()
	return selected.ok and float(selected.party.upkeep.sea_cursor.elapsed) > EPS and float(selected.party.upkeep.sea_cursor.elapsed) < float(selected.party.upkeep.sea_cursor.duration) - EPS

func _sea_arrived() -> bool:
	var reference: Dictionary = slot.region_registry().parties[sea_token]
	if not _check(reference.phase == "entered" and reference.destination_site == Grid.site_id(str(slot.pin.atlas_id), sea_goal_coordinate) and not slot.region_registry().modes.has("travel:" + sea_token), "actual original arrival removes travel ownership and names the true adjacent destination"): return false
	var goal: Dictionary = _sea_goal()
	if not _check(goal.ok, "arrival destination is the actual complete original owner", goal.get("code")): return false
	var original: TerrainLab = goal.lab
	var mapping: Dictionary = reference.arrival_mapping.maps
	for index: int in ship_people.size():
		var person := int(mapping.person[str(ship_people[index])])
		var boat := str(mapping.vehicle[ship_ids[index]])
		var row: Dictionary = original.site_controller.vehicles.ship_person(person)
		if not _check(not row.is_empty() and row.row.embarked_vehicle_id == boat and original.terrain.site.vehicles.has(boat) and original.terrain.site.travel_identity.refs.person[str(person)] == sea_departure_refs.person[str(ship_people[index])] and original.terrain.site.travel_identity.refs.vehicle[boat] == sea_departure_refs.vehicle[ship_ids[index]], "same genuine body/boat stable references and original boarding relation survive actual insert/bind", index): return false
	return _check(lab.controlled_person_id() == ship_actor_id and not lab.controlled_target().is_empty(), "same shore Actor retains actual control after genuine NPC sea arrival")

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest() or not await _setup_action_world(): _finish(); return
	if not _ship_public_cargo(): _finish(); return
	if not await _ship_board(0, true) or not await _ship_public_food() or not await _ship_board(1, false): _finish(); return
	if not _check(not _ship_supply().locations.has("vehicle:" + ship_ids[1]), "second true boat still has no invented own food pool"): _finish(); return
	if not await _ship_helm(0, false) or not await _ship_helm(1, true) or not await _ship_open_sea_positive() or not await _ship_original_two_boat_closure(): _finish(); return
	if not _sea_dispatch(): _finish(); return
	ship_observation = "region_sea"
	if not await _ship_until(_sea_partial, "true original common ACTION step reaches a physically projected partial sea move"): _finish(); return
	if not await _sea_reopen(true): _finish(); return
	var before := action_paid
	if not await _ship_until(func() -> bool: return str(slot.region_registry().parties[sea_token].phase) == "entered", "same true original NPC sea ACTION plan reaches and binds the actual adjacent Site"): _finish(); return
	if not _check(action_paid > before and _sea_arrived(), "genuine actual accepted voyage has positive work and one physical arrival"): _finish(); return
	if not _sea_food_conserved(): _finish(); return
	if not await _sea_reopen(false) or not _sea_arrived(): _finish(); return
	if not _sea_food_conserved(): _finish(); return
	report["original_npc_sea"] = {"token": sea_token, "nation": sea_nation_id, "head": sea_nation_head, "observation": sea_observation, "departure_refs": sea_departure_refs, "arrival": slot.region_registry().parties[sea_token].duplicate(true), "cold": sea_cold_evidence, "scope": "source-only authored genuine dispatch/host/adjacent ACTION/arrival/fullcold lane; first hostile siege contact and full six cases remain OPEN_NOT_RUN"}
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
	var evidence := {"failed": failed, "checks": checks, "cases": report, "checks_evidence": action_evidence, "paid_action": action_paid, "paid_game": action_game_paid, "source_scope": "original finite physical work followed by authentic NPC Nation sea dispatch, true adjacent original Route, actual body host, accepted ACTION advancement, full cold graph and same-body physical arrival; no hostile contact/six-case/performance acceptance"}
	var file := FileAccess.open(out.path_join("original_npc_ship_dispatch_receipt.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(evidence, "\t", true, true)); file.close()
	print("REGION_NPC_SHIP_ORIGINAL_DISPATCH_", "FAILED" if failed else "PASS", " ", JSON.stringify(evidence))
	quit(1 if failed else 0)
func _sea_food_conserved() -> bool:
	if not _observe_ship_food_results(): return false
	var goal := _sea_goal()
	if not goal.ok: return _check(false, "food conservation reads the actual bound arrival owner", goal)
	var original: TerrainLab = goal.lab
	var mapping: Dictionary = slot.region_registry().parties[sea_token].arrival_mapping.maps
	var held := 0.0
	var supplies: Array[Dictionary] = []
	var all_held := 0.0
	for index: int in ship_people.size():
		var person := int(mapping.person[str(ship_people[index])])
		var boat := str(mapping.vehicle[ship_ids[index]])
		var row: Dictionary = original.site_controller.vehicles.ship_person(person)
		if row.is_empty(): return _check(false, "food holder belongs to the actual mapped original row", person)
		var supply: Dictionary = original.site_controller._supply_entry(row.owner)
		if supply.is_empty(): return _check(false, "actual mapped row retains its original supply owner", person)
		var key := "vehicle:" + boat
		if supply.locations.has(key):
			var stock: Dictionary = supply.locations[key]
			held += PhysicalSustain.rations(stock, stock.inventory)
		if index == 1:
			var locations: Dictionary = original.site_controller.ship_food_locations(row.owner, original.site_controller._team_members(row.owner))
			if not _check(not supply.locations.has(key) and str(locations.get(person, "")) == "", "actual second boat has no food pool and cannot borrow the first boat meal"): return false
		var seen := false
		for prior: Dictionary in supplies: seen = seen or is_same(prior, supply)
		if not seen:
			supplies.append(supply)
			all_held += PhysicalSustain.rations(supply.sustain, supply.locations)
	var consumed := ship_consumed_rations - sea_food_consumed_begin
	return _check(absf(held - all_held) <= EPS and consumed >= 0.0 and absf(held + consumed - sea_food_held_begin) <= EPS and absf(held + ship_consumed_rations - 4.0) <= EPS, "actual two-boat arrival held plus original accepted voyage consumption conserves finite food without minting or shore leakage", {"held": held, "accepted_voyage_consumed": consumed, "accepted_total_consumed": ship_consumed_rations, "outbound_held": sea_food_held_begin, "outcomes": ship_food_results})
