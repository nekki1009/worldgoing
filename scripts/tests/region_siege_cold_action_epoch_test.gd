extends "res://scripts/tests/region_siege_center_original_test.gd"
## True common Slot and cold original owners. Every observed partial state is
## paid by the original shared step, then reopened and continued by that owner.
## Initial fixture construction pays original materials/work without claiming
## construction-time calibration. No Native or whole C01-C09 acceptance here.
const SiegeCheckpoint = preload("res://scripts/terrain_lab/site_region_checkpoint.gd")
var action_case := "translate"
var action_kind := "ram"
var action_speed := 1.0
var action_min_crew := false
var action_owner: TerrainLab
var action_coordinate := Vector2i(1, 0)
var action_context: Dictionary = {}
var action_evidence: Array[Dictionary] = []
var action_trace: Array[Dictionary] = []
var action_paid := 0.0
var action_game_paid := 0.0
var action_initial_sequence := 0
var action_initial_holder := 0
var action_initial_inventory: Dictionary = {}
var action_fault := "none"
var action_fault_sequence := 0
var action_fault_facts: Dictionary = {}
var action_target_hp := 0.0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 240000
	out = "res://.godot-temp/region_siege_cold_action_epoch/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	fixture_land_condition_rule = "terrain_mapped_potential_v1" # The original target wall needs mapped land.
	last_world_exists = FileAccess.file_exists(Entry.LAST_WORLD)
	if last_world_exists: last_world_bytes = FileAccess.get_file_as_bytes(Entry.LAST_WORLD)
	for argument: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument.begins_with("--capture-stage="): action_case = argument.trim_prefix("--capture-stage=")
		if argument.begins_with("--siege-kind="): action_kind = argument.trim_prefix("--siege-kind=")
		if argument.begins_with("--sim-speed="): action_speed = float(argument.trim_prefix("--sim-speed="))
		if argument == "--crew=min": action_min_crew = true
		if argument.begins_with("--fault="): action_fault = argument.trim_prefix("--fault=")
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_msec() > deadline: _finish(false, "240-second original action epoch deadline")
	return false

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	action_evidence.append({"ok": condition, "check": message, "details": detail if not detail is Object else str(detail)})
	if not condition:
		failed = true
		push_error("REGION_SIEGE_COLD_ACTION_EPOCH_FAIL: " + message + " " + str(detail))
	return condition

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _check(action_fault in ["none", "crew_loss", "below_min", "stop", "wreck", "no_ammo"], "one actual original fault choice", action_fault): _finish(); return
	if not _check(action_case in ["translate", "crew_approach", "approach", "rotate", "return", "crew_release", "loading", "aiming", "flight", "preparing", "collision", "recovering", "tower_deploy", "tower_retract"]
		and action_speed in [0.5, 1.0, 2.0, 4.0] and SiteRuntime.SIEGE_DEFINITIONS.has(action_kind), "one bounded actual original action observation", {"stage": action_case, "kind": action_kind, "speed": action_speed}): _finish(); return
	if not _check((action_kind == "ram" if action_case in ["translate", "crew_approach", "preparing", "collision"] else true)
		and (action_kind == "siege_tower" if action_case in ["tower_deploy", "tower_retract"] else true)
		and (action_kind in ["ballista", "traction_trebuchet", "counterweight_trebuchet"] if action_case in ["loading", "aiming", "flight"] else true), "actual mechanic supports the requested partial stage"): _finish(); return
	if not _write_manifest(): _finish(); return
	if not await _setup_action_world(): _finish(); return
	if not await _enter_actual_partial(): _finish(); return
	if not _apply_actual_fault(): _finish(); return
	if not await _reopen_actual_partial(): _finish(); return
	if not await _continue_actual_partial(): _finish(); return
	_finish()

func _setup_action_world() -> bool:
	lab = _shell()
	if not _check(lab != null, "actual original pinned restore shell exists"): return false
	controller = lab.site_controller
	var archive := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345, {"size": Vector2i(32, 32)})
	Env.initialize(archive, "siege-action-original:archive")
	lab.bind_terrain(archive)
	lab.restore_only = false
	controller.save_root = out.path_join("archive")
	world_id = "r0_siege_action_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened: Dictionary = controller.open_fixed_world(manifest_path, world_id, "main", Vector2i.ZERO, true)
	if not _check(opened.ok, "original Controller creates one genuine fixed world", opened): return false
	_freeze(lab)
	slot = controller.region_slot
	lab.simulation_speed = action_speed
	var wired := lab._wire_region_gameplay_adapters(slot)
	if not _check(wired.ok, "same original common Slot adapters wire", wired): return false
	var cold: Dictionary = lab._region_gameplay_owner_lab(Grid.site_id(str(slot.pin.atlas_id), action_coordinate), "cold_exact")
	if not _check(cold.ok and cold.lab is TerrainLab, "actual cached cold owner completes its full original graph", cold): return false
	action_owner = cold.lab
	_freeze(action_owner)
	return _fixture_action_owner()

## Builds the siege engine, walls and attacker crew in the cold owner. A subclass that founds
## the defender first calls this only after the founder has handed over and left.
func _fixture_action_owner() -> bool:
	if not _check(action_owner.crowd_site == null or not action_owner.crowd_site.active, "this actual partial continuation uses admitted GD bodies"): return false
	var data := action_owner.terrain
	for key: String in data.resource_base: Env.change(data, key, {"cleared": true, "remaining": 0})
	data.site.capacity = 100000
	for resource: String in Env.ITEM_NAMES: data.site.inventory[resource] = 1000
	var fixture_ammo := str(SiteRuntime.SIEGE_DEFINITIONS[action_kind].ammo)
	if not fixture_ammo.is_empty(): data.site.inventory[fixture_ammo] = 1
	if not _check(SiteRuntime.initialize_item_storage(data.site).ok, "original Depot owns explicit initial fixture stock"): return false
	if not _check(action_owner.character.place(Vector2i(80, 80), true), "actual cold founder starts outside the siege bodies and stations"): return false
	var target := _action_target()
	if target.is_empty(): return false
	action_target_hp = _actual_target_hp(target)
	var needs_ram_contact := action_kind == "ram" and action_case not in ["approach", "rotate", "return", "crew_release"]
	var pose: Dictionary = _action_ram_pose(target) if needs_ram_contact else {"start": Vector2i(20, 41), "goal": Vector2i(20, 41), "facing": Vector2i.RIGHT}
	if pose.is_empty(): return false
	var definition: Dictionary = SiteRuntime.SIEGE_DEFINITIONS[action_kind]
	var inventory_before: Dictionary = data.site.inventory.duplicate(true)
	var built := SiteRuntime.begin_siege_build(data, action_kind, pose.start, pose.facing, 1, 1)
	if not _check(built.ok, "original siege construction reserves real materials once", built): return false
	var key := str(built.vehicle)
	var vehicle: Dictionary = data.site.vehicles[key]
	for resource: String in definition.cost:
		if not _check(int(data.site.inventory.get(resource, 0)) == int(inventory_before.get(resource, 0)) - int(definition.cost[resource]), "original siege material debit is exact", resource): return false
	var station: Dictionary = SiteRuntime.siege_work_slots(data, vehicle)[0]
	var completed := SiteRuntime.advance_siege_work(data, key, "construct", float(definition.work_seconds), data.cell_from_index(int(station.cell)), 0, 1)
	if not _check(completed.ok and vehicle.build.is_empty(), "initial paid fixture construction completes through original work owner", completed): return false
	var ammo := str(definition.ammo)
	if not ammo.is_empty():
		var transferred := SiteRuntime.transfer_items(data, data.site.depot_items, data.site.inventory, vehicle.holder, vehicle.cargo, {ammo: 1}, [], int(data.site.depot_items.version), int(vehicle.holder.version), int(definition.capacity))
		if not _check(transferred.ok and int(vehicle.cargo.get(ammo, 0)) == 1 and int(data.site.inventory.get(ammo, 0)) == 0, "the sole actual finite round leaves Depot for the original vehicle holder", transferred): return false
		var transfer_before := var_to_bytes([data.site.inventory, data.site.depot_items, vehicle])
		var second_transfer := SiteRuntime.transfer_items(data, data.site.depot_items, data.site.inventory, vehicle.holder, vehicle.cargo, {ammo: 1}, [], int(data.site.depot_items.version), int(vehicle.holder.version), int(definition.capacity))
		if not _check(not second_transfer.ok and str(second_transfer.code) == "EMPTY" and transfer_before == var_to_bytes([data.site.inventory, data.site.depot_items, vehicle]), "actual empty source cannot duplicate the same last round; original positive transfer already succeeded", second_transfer): return false
	var count := int(definition.min_crew) if action_min_crew else int(definition.standard_crew)
	var positions: Array[Vector2i] = [pose.start - pose.facing * 3 + Vector2i(-pose.facing.y, pose.facing.x) * 3]
	for number: int in count: positions.append(SiteRuntime.siege_crew_cell(data, vehicle, number) - pose.facing)
	action_owner._ensure_army_slots(1)
	var team: TerrainArmy = action_owner.army
	team.faction_id = 1
	team.roster_size = positions.size()
	if not _check(team.deploy_at(data, null, null, positions) and team.enable_combat(false), "original actual army births captain and original crew rows"): return false
	action_owner.site_controller.initialize_team_items(team)
	data.site.army_next_team = action_owner._next_army_identity()
	if not _check(team.team_id == int(vehicle.team_id) and team.command_eligible(team.current_commander), "vehicle and real captain share original team authority"): return false
	var commander := team.combat_identity(team.current_commander)
	var crew: Array[int] = []
	for index: int in count:
		var identity := team.combat_identity(index + 1)
		var assigned: Dictionary = action_owner.site_controller.vehicles.assign_crew(key, identity, str(index), commander, true)
		if not _check(assigned.ok, "existing NPC dispatch entry assigns a real same-team row; no control identity is forged", assigned): return false
		crew.append(identity)
	if action_kind == "siege_tower":
		for offset: int in range(3):
			var support := Vector2i(25, 41 + offset)
			data.site.terrain_changes[str(data.index(support))] = 2
			data.height_levels[data.index(support)] = 2
		SiteRuntime.rebuild_terrain_edges(data)
		SiteEnvironment.rebuild_indexes(data)
	action_context = {"key": key, "target": target, "goal": pose.goal, "facing": pose.facing, "commander": commander, "crew": crew, "count": count}
	action_initial_sequence = int(vehicle.next_attack_seq)
	action_initial_holder = int(vehicle.holder.version)
	action_initial_inventory = data.site.inventory.duplicate(true)
	var saved: Dictionary = controller.checkpoint_region_internal("region_checkpoint", true)
	if not _check(saved.ok, "actual common publisher stores original authored bodies, materials and holders together", saved): return false
	var due: Dictionary = slot.consume_due_region_events()
	return _check(due.ok and due.get("complete", false), "actual same-point due owners consume before positive action", due)

func _action_vehicle() -> Dictionary:
	return action_owner.terrain.site.get("vehicles", {}).get(str(action_context.get("key", "")), {})

func _action_target() -> Dictionary:
	var material := "wood" if action_kind == "ram" else "stone"
	var anchor := Vector2i(48, 40 if material == "wood" else 41)
	var options := {"owner_faction": 2, "material": "stone", "quarter": 1}
	var layout := SiteRuntime.building_cells(action_owner.terrain, "gate" if material == "wood" else "stone_wall", anchor, Vector2i.ONE, options)
	if not _check(layout.ok, "original actual target geometry is legal", layout): return {}
	var cells: Array[int] = []; cells.assign(layout.cells)
	var built := SiteRuntime.request_build(action_owner.terrain, "gate" if material == "wood" else "stone_wall", cells, Callable(), options)
	if not _check(built.ok, "original target construction pays materials", built): return {}
	var key := str(built.feature)
	var feature: Dictionary = action_owner.terrain.site.features[key]
	var task := {"version": 2, "zone": -1, "target": "feature:" + key, "action": "construct", "work_cell": int(feature.entrance), "cell": int(feature.entrance), "mode": "work", "progress": 0.0, "status": "", "work_slot": -1}
	SiteRuntime._feature_work(action_owner.terrain, key, float(feature.work), Callable(), Callable(), task, {}, 20, 2)
	var part := "leaf:left" if material == "wood" else "c:%d" % action_owner.terrain.index(anchor)
	var geometry := SiteRuntime.feature_geometry(action_owner.terrain, feature)
	if not _check(str(feature.stage) == "complete" and geometry.parts.has(part), "actual paid target part completes", geometry.get("parts", {})): return {}
	return {"type": "structure", "feature_id": key, "part_id": part}

func _action_ram_pose(target: Dictionary) -> Dictionary:
	var data := action_owner.terrain
	var feature: Dictionary = data.site.features[str(target.feature_id)]
	var part: Dictionary = SiteRuntime.feature_geometry(data, feature).parts[str(target.part_id)]
	var cell := data.cell_from_index(int(part.cells[0]))
	for facing: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		for dy: int in range(-4, 5):
			for dx: int in range(-4, 5):
				var anchor := cell + Vector2i(dx, dy)
				var vehicle := {"kind": "ram", "cell": data.index(anchor), "facing": [facing.x, facing.y], "team_id": 1, "id": "candidate"}
				if not action_owner.siege_ram_preview(vehicle, target).ok: continue
				var events: Array[Dictionary] = action_owner._siege_ram_prism_events(vehicle, 0.0, 1.0)
				if events.is_empty(): continue
				events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.fraction) < float(b.fraction) if not is_equal_approx(float(a.fraction), float(b.fraction)) else str(a.stable) < str(b.stable))
				if str(events[0].get("feature", "")) != str(target.feature_id) or str(events[0].get("part", "")) != str(target.part_id): continue
				var clear := true
				for body: Vector2i in SiteRuntime.siege_cells(data, vehicle):
					if not data.is_walkable(body): clear = false
				for number: int in range(int(SiteRuntime.SIEGE_DEFINITIONS.ram.standard_crew)):
					var station := SiteRuntime.siege_crew_cell(data, vehicle, number)
					if not data.is_walkable(station) or int(data.feature_at[data.index(station)]) != 0: clear = false
				if not clear: continue
				for back: int in range(1, 5):
					var start := anchor - facing * back
					if SiteRuntime.begin_siege_build(data, "ram", start, facing, 1, 1, Callable(), true).ok: return {"start": start, "goal": anchor, "facing": facing}
	_check(false, "actual RAM prism finds a legal paid target approach", target)
	return {}

func _action_step() -> bool:
	var request := TerrainLab.EXCHANGE_ACTION_STEP if lab.exchange_enabled else TerrainLab.ACTION_STEP
	var result: Dictionary = lab._advance_original_shared_step(request)
	if not _check(result.get("ok", false), "actual common producer accepts original work or its due zero endpoint", result): return false
	if result.get("completed", false):
		if not _check(float(result.get("action_seconds", 0.0)) > 0.0 and float(result.get("game_seconds", 0.0)) > 0.0 and float(result.action_seconds) <= request + EPS, "actual common interval pays positive bounded ACTION and GAME", result): return false
		action_paid += float(result.action_seconds)
		action_game_paid += float(result.game_seconds)
		if action_trace.size() < 4000: action_trace.append({"action": result.action_seconds, "game": result.game_seconds, "stage": str(_action_vehicle().get("action", {}).get("stage", "")), "vehicle_move": not _action_vehicle().get("move", {}).is_empty(), "game_at": float(slot.control.logical_game_seconds), "action_at": float(slot.control.fire_clock.action_seconds)})
	else:
		if not _check(float(result.get("action_seconds", 0.0)) == 0.0 and float(result.get("game_seconds", 0.0)) == 0.0, "due original endpoint consumes zero time", result): return false
	return true

func _action_until(predicate: Callable, label: String) -> bool:
	for count: int in range(18000):
		if predicate.call(): return _check(true, label)
		if Time.get_ticks_msec() > deadline: return _check(false, label + " exceeded deadline")
		if not _action_step(): return false
		if count % 60 == 0: await process_frame
	return _check(false, label + " exceeded bounded original interval count", _action_vehicle())

func _actual_crew_moving() -> bool:
	for identity: int in action_context.crew:
		var person: Dictionary = action_owner.site_controller.person_actions._person(identity, false)
		if not person.is_empty() and person.moving and float(person.owner.move_progress[int(person.unit)]) > 0.0 and float(person.owner.move_progress[int(person.unit)]) < 1.0: return true
	return false

func _partial_ready() -> bool:
	var vehicle := _action_vehicle()
	if action_case == "translate": return not vehicle.move.is_empty() and _actual_crew_moving()
	if action_case == "crew_approach": return vehicle.move.is_empty() and _actual_crew_moving()
	if action_case in ["approach", "return"]: return str(vehicle.action.get("stage", "")) == action_case and _actual_crew_moving()
	if action_case == "crew_release": return str(vehicle.command.get("type", "")) == "release" and str(vehicle.action.get("stage", "")) == "rotate" and float(vehicle.action.get("elapsed", 0.0)) > 0.0 and action_owner.site_controller.vehicles.region_siege_action_remaining(vehicle) > TerrainLab.ACTION_TIME_EPSILON
	if action_case == "flight":
		for flight: Dictionary in action_owner.siege_projectiles:
			if float(flight.get("elapsed", 0.0)) > 0.0 and float(flight.get("elapsed", 0.0)) < float(flight.get("total", INF)): return true
		return false
	return str(vehicle.action.get("stage", "")) == action_case and float(vehicle.action.get("elapsed", 0.0)) > 0.0 and action_owner.site_controller.vehicles.region_siege_action_remaining(vehicle) > TerrainLab.ACTION_TIME_EPSILON

func _enter_actual_partial() -> bool:
	var transport: SiteVehicleTransport = action_owner.site_controller.vehicles
	if action_case != "crew_approach":
		if not await _action_until(func() -> bool: return transport.crew_ready(_action_vehicle()), "actual original crew reaches its real stations"): return false
	var vehicle := _action_vehicle()
	var ordered: Dictionary
	if action_case in ["translate", "crew_approach"]:
		ordered = transport.order_siege(str(action_context.key), "move", {"type": "ground", "cell": [action_context.goal.x, action_context.goal.y]}, int(action_context.commander), true)
	elif action_case in ["approach", "rotate", "return", "crew_release"]:
		var old := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
		var direction := Vector2i(-old.y, old.x)
		ordered = transport.order_siege(str(action_context.key), "turn", {"facing": [direction.x, direction.y]}, int(action_context.commander), true)
	elif action_case in ["tower_deploy", "tower_retract"]:
		ordered = transport.order_siege(str(action_context.key), "deploy", {}, int(action_context.commander), true)
		if not _check(ordered.ok, "original tower deploy begins through its true authority", ordered): return false
		if action_case == "tower_retract":
			if not await _action_until(func() -> bool: return _action_vehicle().action.is_empty() and str(_action_vehicle().phase) == "deployed", "actual tower commits its original derived deployed surface"): return false
			ordered = transport.order_siege(str(action_context.key), "retract", {}, int(action_context.commander), true)
	else:
		if action_kind == "ram":
			ordered = transport.order_siege(str(action_context.key), "move", {"type": "ground", "cell": [action_context.goal.x, action_context.goal.y]}, int(action_context.commander), true)
			if not _check(ordered.ok, "original RAM moves to actual front contact", ordered): return false
			if not await _action_until(func() -> bool: return _action_vehicle().move.is_empty() and int(_action_vehicle().cell) == action_owner.terrain.index(action_context.goal) and transport.crew_ready(_action_vehicle()), "actual RAM compound reaches its real front pose"): return false
		ordered = transport.order_siege(str(action_context.key), "attack", action_context.target, int(action_context.commander), true)
	if not _check(ordered.ok, "original dispatch entry accepts one real action order", ordered): return false
	if action_case == "crew_release":
		if not await _action_until(func() -> bool: return str(_action_vehicle().action.get("stage", "")) == "rotate" and float(_action_vehicle().action.get("elapsed", 0.0)) > 0.0, "actual turn obtains a paid retained rotate before release"): return false
		var released := transport.unassign_crew(str(action_context.key), int(action_context.crew[0]), int(action_context.commander), true)
		if not _check(released.ok, "original release queues a true row behind the already committed rotation", released): return false
	if not await _action_until(_partial_ready, "actual shared steps reach a genuine partial " + action_case): return false
	return _check(action_paid > 0.0 and _partial_ready(), "partial state contains actual paid elapsed or movement progress", _action_facts())

func _action_facts() -> Dictionary:
	var people: Dictionary = {}
	for identity: int in action_context.crew:
		var person: Dictionary = action_owner.site_controller.person_actions._person(identity, false)
		if person.is_empty(): people[str(identity)] = {"missing": true}; continue
		var owner: TerrainArmy = person.owner
		var index := int(person.unit)
		people[str(identity)] = {"cell": person.cell, "moving": person.moving, "moving_to": owner.moving_to[index], "progress": owner.move_progress[index], "duration": owner.move_duration[index], "pose": owner.combat_hot_get(index, &"pose", ""), "hp": person.hp, "ko": person.ko, "holder": person.holder.duplicate(true), "cargo": person.cargo.duplicate(true), "fatigue": PersonFatigue.read(owner.combat_units[index])}
	return {"vehicle": _action_vehicle().duplicate(true), "people": people, "flights": action_owner.siege_projectiles.duplicate(true), "contacts": action_owner.siege_contacts, "shots": action_owner.siege_shots, "features": action_owner.terrain.site.features.duplicate(true), "inventory": action_owner.terrain.site.inventory.duplicate(true), "items": action_owner.terrain.site.item_records.duplicate(true)}

func _action_graph() -> Dictionary:
	var context: Dictionary = slot.region_checkpoint_context(action_owner.terrain, "region_checkpoint", "siege_actual_observer", true, {})
	if not _check(context.ok, "original Slot derives actual dual-clock full graph context", context): return {}
	var graph := action_owner.capture_region_owner_state(context.context)
	if not _check(graph.ok and graph.owner_states.get("scene") is Dictionary, "actual original owner captures its full live aliases", graph.get("code")): return {}
	var scene: Dictionary = graph.owner_states.scene
	return {"root": scene.root.duplicate(true), "nodes": scene.nodes.duplicate(true)}

## The store's own save path: stringify(sort_keys, full_precision) -> parse ->
## stringify. No custom rounding.
func _saved_json_domain(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, true)), "", true, true)

func _reopen_actual_partial() -> bool:
	var source_facts := _action_facts()
	var source_clock := {"world": float(slot.control.logical_game_seconds), "action": float(slot.control.fire_clock.action_seconds), "sequence": int(slot.control.fire_clock.sequence)}
	var checkpoint: Dictionary = controller.checkpoint_region_internal("region_checkpoint", true)
	if not _check(checkpoint.ok, "actual joint checkpoint stores an in-progress action and compound at its completed common endpoint", checkpoint): return false
	if not _check(source_facts == _action_facts() and float(slot.control.logical_game_seconds) == float(source_clock.world) and float(slot.control.fire_clock.action_seconds) == float(source_clock.action) and int(slot.control.fire_clock.sequence) == int(source_clock.sequence), "checkpoint pays no extra work, material, flight or time"): return false
	var source_graph := _action_graph()
	if source_graph.is_empty(): return false
	var generation := int(slot._marker.generation)
	var selected := slot.region_bind_proof(action_owner.terrain)
	var reopened := RegionSaveSlot.new()
	var opened: Dictionary = reopened.open_map(slot.source, world_id, "main")
	if not _check(opened.ok and int(reopened._marker.generation) == generation, "fresh original Slot reopens the exact joint selected epoch", opened): return false
	var main_read: Dictionary = reopened.open_site(Vector2i.ZERO)
	if not _check(main_read.ok and main_read.data.site.has("region_snapshot"), "mode-aware open retains real active fullgraph", main_read.get("code")): return false
	var next_main := _restore_selected(main_read.data, reopened, false)
	if next_main == null: return false
	var cold_read: Dictionary = reopened.open_site(action_coordinate)
	if not _check(cold_read.ok and cold_read.data.site.has("region_snapshot"), "mode-aware open retains real cold action fullgraph", cold_read.get("code")): return false
	var next_cold := _restore_selected(cold_read.data, reopened, true)
	if next_cold == null: return false
	reopened._region_original_labs[str(next_cold.terrain.site.id)] = next_cold
	var adopted: Dictionary = next_main._region_gameplay_owner_lab(str(next_cold.terrain.site.id), "cold_exact")
	if not _check(adopted.ok and adopted.lab == next_cold, "actual factory uses the same positively restored cold owner", adopted.get("code")): return false
	lab = next_main
	controller = next_main.site_controller
	slot = reopened
	action_owner = next_cold
	lab.simulation_speed = action_speed
	var restored_graph := _action_graph()
	if restored_graph.is_empty(): return false
	# The graph comparison replaces an exact equality that cannot hold across a
	# JSON reopen (number types and last-ulp floats change in the store round
	# trip); facts, clocks, proof and partial progress stay compared value by value.
	if not _check(source_facts == _action_facts() and _saved_json_domain(source_graph) == _saved_json_domain(restored_graph) and (_partial_ready() if action_fault == "none" else true)
		and float(slot.control.logical_game_seconds) == float(source_clock.world) and float(slot.control.fire_clock.action_seconds) == float(source_clock.action) and int(slot.control.fire_clock.sequence) == int(source_clock.sequence)
		and selected == slot.region_bind_proof(action_owner.terrain), "positive reopen restores exact hot graph, partial progress, stable items, reserved cells and both clocks", {"source_graph_sha": SiegeCheckpoint.state_hash(source_graph), "restored_graph_sha": SiegeCheckpoint.state_hash(restored_graph), "clock": source_clock}): return false
	# A manual fresh-Slot reopen wires the restored main original as the common
	# adapter host, as the original controller did for the first Slot, and
	# completes the positive restore of every travelling party's original owner
	# before the same-point retry is measured.
	var rewired := lab._wire_region_gameplay_adapters(slot)
	if not _check(rewired.ok, "fresh Slot adapters wire to the positively restored main original", rewired): return false
	for token: String in slot.region_registry().parties:
		if str(slot.region_registry().parties[token].get("phase", "")) not in ["travelling", "pending_life"]: continue
		var travelling := slot._region_npc_party(token)
		var owner: Dictionary = lab.prepare_region_party_original_owner(token, travelling.party, slot) if travelling.ok else travelling
		if not _check(owner.ok, "fresh Slot restores the travelling party's actual original owner", owner.get("code")): return false
	var retry_before := var_to_bytes([slot.control, _action_facts(), restored_graph])
	var retry: Dictionary = slot.consume_due_region_events()
	var retry_graph := _action_graph()
	if not _check(retry.ok and retry.get("complete", false) and retry_before == var_to_bytes([slot.control, _action_facts(), retry_graph]), "true same-point retry consumes zero time and replays no action/effect/transfer", retry): return false
	report["selected_epoch"] = {"generation": generation, "proof": selected, "clock": source_clock, "stage": action_case, "kind": action_kind, "partial_facts": source_facts, "graph_sha256": SiegeCheckpoint.state_hash(source_graph), "complete_restore": true}
	return true

func _continue_actual_partial() -> bool:
	var facts := _action_facts()
	var paid_before := action_paid
	if not _action_step(): return false
	if not _check(action_paid > paid_before and facts != _action_facts(), "same restored actual original owner continues a positive interval"): return false
	var transport: SiteVehicleTransport = action_owner.site_controller.vehicles
	if action_fault != "none": return await _finish_actual_fault(paid_before)
	if action_case == "translate":
		var partial: Dictionary = facts.vehicle.move
		var stop := transport.order_siege(str(action_context.key), "stop", {}, int(action_context.commander), true)
		if not _check(stop.ok, "original stop preserves an already committed whole-group translation", stop): return false
		if not await _action_until(func() -> bool: return _action_vehicle().move.is_empty(), "actual restored compound completes its sole all-member barrier"): return false
		if not _check(int(_action_vehicle().cell) == int(partial.cell), "one original compound commits vehicle at its accepted target"): return false
		for movement: Dictionary in partial.participants:
			var person: Dictionary = action_owner.site_controller.person_actions._person(int(movement.person_id), false)
			if not _check(not person.is_empty() and action_owner.terrain.index(person.cell) == int(movement.to) and not person.moving, "every original member commits the same retained compound target once", movement): return false
	elif action_case == "crew_approach":
		if not await _action_until(func() -> bool: return _action_vehicle().move.is_empty() and int(_action_vehicle().cell) == action_owner.terrain.index(action_context.goal), "restored original crew approach proceeds to its real complete-group destination"): return false
	elif action_case in ["approach", "rotate", "return"]:
		if not await _action_until(func() -> bool: return _action_vehicle().action.is_empty() and transport.crew_ready(_action_vehicle()), "original restored turn and return reach the actual new stations"): return false
	elif action_case == "crew_release":
		if not await _action_until(func() -> bool: return str(_action_vehicle().command.get("type", "")) != "release", "original queued crew release follows the retained rotation barrier"): return false
		if not _check(not _action_vehicle().crew_slots.values().has(int(action_context.crew[0])) and _action_vehicle().crew_slots.size() == int(action_context.count) - 1, "one real queued row is released exactly once"): return false
	elif action_case in ["tower_deploy", "tower_retract"]:
		if not await _action_until(func() -> bool: return _action_vehicle().action.is_empty(), "restored tower commits its original surface endpoint"): return false
		if not _check((not _action_vehicle().deployed_pose.is_empty()) == (action_case == "tower_deploy"), "one original derived tower surface commits the retained action"): return false
	else:
		if not await _action_until(func() -> bool: return int(_action_vehicle().next_attack_seq) == action_initial_sequence + 1, "same original accepted attack obtains its first real release/contact identity"): return false
		var stopped := transport.order_siege(str(action_context.key), "stop", {}, int(action_context.commander), true)
		if not _check(stopped.ok, "original stop retains the already paid shot/collision and recovery", stopped): return false
		if not await _action_until(func() -> bool: return _action_vehicle().action.is_empty() and action_owner.siege_projectiles.is_empty(), "actual retained original impact and recovery finish after reopen"): return false
		var ammo := str(SiteRuntime.SIEGE_DEFINITIONS[action_kind].ammo)
		if not _check(int(_action_vehicle().next_attack_seq) == action_initial_sequence + 1
			and (int(_action_vehicle().holder.version) == action_initial_holder + 1 and int(_action_vehicle().cargo.get(ammo, 0)) == 0 and action_owner.siege_shots == 1 if not ammo.is_empty() else true), "actual resumed attack pays a single original ammo/version/sequence transaction", _action_vehicle()): return false
	if not _check(action_owner.terrain.site.inventory == action_initial_inventory, "continuation and reopen pay no construction or Depot materials again"): return false
	var final_checkpoint: Dictionary = controller.checkpoint_region_internal("region_checkpoint", true)
	if not _check(final_checkpoint.ok, "positive continued owners publish one further genuine common epoch", final_checkpoint): return false
	report["continuation"] = {"original_profile": SiteCombatRules.siege_attack(action_kind), "initial_actual_target_hp": action_target_hp, "final_actual_target_hp": _actual_target_hp(action_context.target), "raw_actual_damage": action_target_hp - _actual_target_hp(action_context.target), "coefficient_calibrated": false, "tolerance": null, "actual_action_paid": action_paid - paid_before, "actual_total_action": action_paid, "actual_total_game": action_game_paid, "final_facts": _action_facts(), "final_generation": int(slot._marker.generation), "clock_ratio_is_original_measurement": true}
	return true

func _actual_target_hp(target: Dictionary) -> float:
	var feature: Dictionary = action_owner.terrain.site.features.get(str(target.get("feature_id", "")), {})
	if feature.is_empty(): return 0.0
	var geometry := SiteRuntime.feature_geometry(action_owner.terrain, feature)
	return float(geometry.get("parts", {}).get(str(target.get("part_id", "")), {}).get("hp", 0.0))

func _apply_actual_fault() -> bool:
	if action_fault == "none": return true
	var vehicle := _action_vehicle()
	var transport: SiteVehicleTransport = action_owner.site_controller.vehicles
	var before := _action_facts()
	if action_fault == "crew_loss":
		var person: Dictionary = action_owner.site_controller.person_actions._person(int(action_context.crew[0]), false)
		if not _check(not person.is_empty() and person.owner is TerrainArmy, "actual crew loss resolves its original row"): return false
		person.owner.apply_unit_contact(int(person.unit), {"result": {"hp": 1.0, "stun": 110.0, "guard_break": false}, "shield": false, "environmental": true})
		var knocked: Dictionary = action_owner.site_controller.person_actions._person(int(action_context.crew[0]), false)
		if not _check(float(knocked.ko) > 0.0 and float(knocked.hp) > 0.0, "original contact supplies real crew KO and original life duration", {"hp": knocked.hp, "ko": knocked.ko}): return false
		var stopped := transport.order_siege(str(action_context.key), "stop", {}, int(action_context.commander), true)
		if not _check(stopped.ok, "original voluntary stop retains accepted work after a real crew KO", stopped): return false
	elif action_fault == "below_min":
		var minimum := int(SiteRuntime.SIEGE_DEFINITIONS[action_kind].min_crew)
		for identity: int in action_context.crew:
			if vehicle.crew_slots.size() < minimum: break
			var released := transport.unassign_crew(str(action_context.key), identity, int(action_context.commander), true)
			if not _check(released.ok, "original crew release requests a real row removal", released): return false
			# A committed compound/rotation retains the real queued participants;
			# removal completes at its original barrier, not by editing the roster.
			if str(vehicle.command.get("type", "")) == "release" and not vehicle.command.get("people", []).is_empty():
				var retained := int(vehicle.command.people.size())
				if vehicle.crew_slots.size() - retained < minimum: break
	elif action_fault == "wreck":
		var destroyed := SiteRuntime.damage_siege_vehicle(action_owner.terrain, str(vehicle.id), float(vehicle.hp))
		if not _check(destroyed.ok and float(vehicle.hp) == 0.0 and vehicle.ever_hp_damaged, "original structure damage owner creates a true wreck during the paid action", destroyed): return false
	elif action_fault == "no_ammo":
		var ammo := str(SiteRuntime.SIEGE_DEFINITIONS[action_kind].ammo)
		if not _check(not ammo.is_empty() and int(vehicle.cargo.get(ammo, 0)) == 1 and int(vehicle.next_attack_seq) == action_initial_sequence, "ammo fault observes a true paid pre-release action"): return false
		var cancelled := transport.order_siege(str(action_context.key), "stop", {}, int(action_context.commander), true)
		if not _check(cancelled.ok, "original stop releases the uncommitted firing action while preserving already paid fatigue", cancelled): return false
		var stowed := SiteRuntime.transfer_items(action_owner.terrain, vehicle.holder, vehicle.cargo, action_owner.terrain.site.depot_items, action_owner.terrain.site.inventory, {ammo: 1}, [], int(vehicle.holder.version), int(action_owner.terrain.site.depot_items.version), int(action_owner.terrain.site.capacity))
		if not _check(stowed.ok and int(vehicle.cargo.get(ammo, 0)) == 0 and int(action_owner.terrain.site.inventory.get(ammo, 0)) == 1, "last real round returns through its original holder transaction", stowed): return false
		var ordered := transport.order_siege(str(action_context.key), "attack", action_context.target, int(action_context.commander), true)
		if not _check(ordered.ok, "original legal empty-ammo command remains an actual finite-resource wait", ordered): return false
	else:
		var stopped := transport.order_siege(str(action_context.key), "stop", {}, int(action_context.commander), true)
		if not _check(stopped.ok, "original stop retains already committed movement, contact and recovery", stopped): return false
	action_fault_sequence = int(vehicle.next_attack_seq)
	action_fault_facts = _action_facts()
	return _check(before != action_fault_facts, "original fault changes actual owner state before a genuine selected checkpoint", {"fault": action_fault, "sequence": action_fault_sequence, "facts": action_fault_facts})

func _finish_actual_fault(paid_before: float) -> bool:
	var transport: SiteVehicleTransport = action_owner.site_controller.vehicles
	if not await _action_until(func() -> bool: return _action_vehicle().move.is_empty() and _action_vehicle().action.is_empty() and action_owner.siege_projectiles.is_empty() and not _actual_crew_moving() and str(_action_vehicle().command.get("type", "")) != "release", "restored original fault tail reaches its legal physical barrier"): return false
	if action_fault == "no_ammo":
		for count: int in range(120):
			if not _action_step(): return false
		if not _check(int(_action_vehicle().next_attack_seq) == action_initial_sequence and action_owner.siege_shots == 0 and _action_vehicle().action.is_empty(), "positive original empty-ammo intervals create no free attack or release"): return false
	elif action_fault == "below_min":
		var minimum := int(SiteRuntime.SIEGE_DEFINITIONS[action_kind].min_crew)
		if not _check(_action_vehicle().crew_slots.size() < minimum, "true original queued removals leave fewer than minimum crew"): return false
		var seq := int(_action_vehicle().next_attack_seq)
		var rejected := transport.order_siege(str(action_context.key), "attack", action_context.target, int(action_context.commander), true)
		if not _check(not rejected.ok, "original authority refuses a fresh below-minimum operation after positive restore and tail completion", rejected): return false
		if not _action_step(): return false
		if not _check(seq == int(_action_vehicle().next_attack_seq) and _action_vehicle().action.is_empty(), "true future original interval creates no below-minimum new round"): return false
	if not _check(int(_action_vehicle().next_attack_seq) >= action_fault_sequence and int(_action_vehicle().next_attack_seq) <= action_fault_sequence + 1, "fault restore finishes at most its one already accepted original attack identity", _action_vehicle()): return false
	if not _check(action_paid > paid_before and _action_vehicle().move.is_empty() and _action_vehicle().action.is_empty(), "fault proof includes actual positive original continuation and complete atomic tail"): return false
	var checkpoint: Dictionary = controller.checkpoint_region_internal("region_checkpoint", true)
	if not _check(checkpoint.ok, "continued original fault result publishes another complete selected epoch", checkpoint): return false
	report["fault_continuation"] = {"fault": action_fault, "fault_source_facts": action_fault_facts, "final_facts": _action_facts(), "actual_action_paid": action_paid - paid_before, "actual_total_game": action_game_paid, "generation": int(slot._marker.generation), "original_profile": SiteCombatRules.siege_attack(action_kind), "initial_actual_target_hp": action_target_hp, "final_actual_target_hp": _actual_target_hp(action_context.target), "coefficient_calibrated": false, "tolerance": null}
	return true

func _finish(ok: bool = true, message: String = "") -> void:
	if finished: return
	finished = true
	failed = failed or not ok
	if not message.is_empty(): printerr(message)
	paused = false
	for scene: TerrainLab in capture_scenes:
		if is_instance_valid(scene): scene.free()
	var current: Variant = JSON.parse_string(FileAccess.get_file_as_string(Entry.LAST_WORLD)) if FileAccess.file_exists(Entry.LAST_WORLD) else null
	if current is Dictionary and str(current.get("world_id", "")).begins_with("r0_siege_action_%d_" % OS.get_process_id()):
		if last_world_exists:
			var restored := FileAccess.open(Entry.LAST_WORLD, FileAccess.WRITE); restored.store_buffer(last_world_bytes); restored.close()
		else: DirAccess.remove_absolute(ProjectSettings.globalize_path(Entry.LAST_WORLD))
	TerrainArmy.release_contact_source()
	var receipt := {"failed": failed, "fault": action_fault, "checks": checks, "stage": action_case, "kind": action_kind, "sim_speed": action_speed, "minimum_crew": action_min_crew, "report": report, "checks_evidence": action_evidence, "actual_interval_trace": action_trace, "scope": "true common Slot original cold partial action and whole-crew graph selected reopen, zero retry and positive single continuation; GD only, fixture construction time not calibrated, no full C03/C09/four-phase/player-menu/native acceptance"}
	var file := FileAccess.open(out.path_join("siege_cold_action_epoch_receipt.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(receipt, "\t", true, true)); file.close()
	print("REGION_SIEGE_COLD_ACTION_EPOCH_", "FAILED" if failed else "PASS", " ", action_kind, " ", action_case, " checks=", checks)
	quit(1 if failed else 0)
