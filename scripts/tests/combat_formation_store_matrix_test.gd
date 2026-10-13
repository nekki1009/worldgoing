extends SceneTree
## Real SiteStore round-trips for every fixed formation during MOVE and HOLD.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const BASE := "res://.godot-temp/site_combat/formation-store-matrix-"
const PRESETS := ["square", "wedge", "goose", "circle", "hook", "loose"]
const STEP := 0.05

func _initialize() -> void:
	call_deferred("_run")

func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok

func _advance(army: TerrainArmy, coordinator: SiteCombatMovementCoordinator) -> void:
	coordinator.combat_logic_tick(STEP)
	army.prepare_combat(STEP)
	coordinator.complete_committed_moves()

func _physical_ok(army: TerrainArmy, data: TerrainData, previous: Array[Vector2i]) -> bool:
	var sources: Dictionary = {}
	var claims: Dictionary = {}
	for index in range(army.roster_size):
		var cell: Vector2i = army.cells[index]
		if not _require(data.is_walkable(cell) and not sources.has(cell), "Duplicate or blocked physical source at member %d" % index): return false
		if cell != previous[index] and not _require(data.can_step(previous[index], cell), "Non-adjacent physical step at member %d" % index): return false
		sources[cell] = true
		var claim: Vector2i = army.moving_to[index]
		if claim != TerrainArmy.INVALID_CELL:
			if not _require(data.can_step(cell, claim) and not claims.has(claim), "Invalid or duplicate in-flight claim at member %d" % index): return false
			claims[claim] = true
	return true

func _animated(army: TerrainArmy) -> bool:
	for index in range(army.roster_size):
		if army.moving_to[index] != TerrainArmy.INVALID_CELL and army.move_progress[index] > 0.0 and army.move_progress[index] < 1.0:
			return true
	return false

func _check_contract(source: TerrainArmy, restored: TerrainArmy, coordinator: SiteCombatMovementCoordinator, preset: String, members: int, hold: bool) -> bool:
	var source_plan: CombatDeploymentPlan = source.get_active_deployment_plan()
	var plan: CombatDeploymentPlan = restored.get_active_deployment_plan()
	if not _require(source_plan != null and plan != null, "%s lost its deployment contract" % preset): return false
	if not _require(restored.formation_preset_id == preset and plan.formation_preset_id == preset and plan.shape_version == 2
		and restored.get_order_serial() == source.get_order_serial() and plan.order_serial == source_plan.order_serial
		and plan.requested_count == members and plan.member_slot_map.size() == members and plan.platform_slots.size() == members
		and plan.queue_member_ids.is_empty() and plan.member_slot_map == source_plan.member_slot_map
		and plan.platform_slots == source_plan.platform_slots and plan.resolved_anchor == source_plan.resolved_anchor
		and plan.final_facing == source_plan.final_facing, "%s lost its frozen preset, serial, or exact slots" % preset): return false
	if not _require(restored.cells == source.cells and restored.moving_to == source.moving_to and restored.facing == source.facing,
		"%s changed physical cells, claims, or facing on load" % preset): return false
	for index in range(members):
		if not _require(absf(restored.move_progress[index] - source.move_progress[index]) < 0.000001,
			"%s changed physical interpolation at member %d" % [preset, index]): return false
	var expected: Dictionary = {}
	for cell: Vector2i in Destination.shape_slots(preset, members, plan.resolved_anchor, plan.final_facing):
		expected[cell] = true
	for slot: Vector2i in plan.member_slot_map.values():
		if not _require(expected.erase(slot), "%s assigned a slot outside its exact template" % preset): return false
		var lease = coordinator.deployment_registry.owner_of(slot)
		if not _require(lease != null and lease.formation_id == restored.team_id and lease.order_serial == plan.order_serial,
			"%s lost its final slot lease" % preset): return false
	if not _require(expected.is_empty(), "%s left an expected slot unassigned" % preset): return false
	if hold:
		if not _require(restored.combat_order == TerrainArmy.CombatOrder.HOLD and restored.get_active_move_plan() == null
			and Destination.is_settled(plan, restored.get_active_members_occupancy())
			and restored._reserved_cells.is_empty() and coordinator.get_inflight_batches_for_formation(restored).is_empty(),
			"%s HOLD did not restore exact settled physical state" % preset): return false
		for index in range(members):
			var slot: Vector2i = plan.get_slot_for_member(restored.combat_identity(index))
			if not _require(restored.cells[index] == slot and restored.moving_to[index] == TerrainArmy.INVALID_CELL
				and restored.facing[index] == plan.get_facing_for_slot(slot), "%s HOLD member %d is not settled" % [preset, index]): return false
	else:
		var source_move: CombatMovePlan = source.get_active_move_plan()
		var move: CombatMovePlan = restored.get_active_move_plan()
		if not _require(restored.combat_order == TerrainArmy.CombatOrder.MOVE and source_move != null and move != null
			and move.phase == source_move.phase and move.order_serial == plan.order_serial and _animated(restored)
			and not coordinator.get_inflight_batches_for_formation(restored).is_empty(),
			"%s MOVE lost its phase or in-flight physical batch" % preset): return false
	return true

func _round_trip(data: TerrainData, source: TerrainArmy, preset: String, members: int, hold: bool) -> Dictionary:
	var label := "%s-%d-%s" % [preset, members, "hold" if hold else "move"]
	data.site.armies = [source.capture_combat_state()]
	var path := BASE + label + ".json"
	var saved: Dictionary = Store.save(data, path)
	if not _require(bool(saved.get("ok", false)), "SiteStore.save rejected %s: %s" % [label, saved]): return {}
	var loaded: Dictionary = Store.load_site(path)
	if not _require(bool(loaded.get("ok", false)), "SiteStore.load_site rejected %s: %s" % [label, loaded]): return {}
	var restored_data: TerrainData = loaded.data
	var snapshot: Dictionary = restored_data.site.armies[0]
	if not _require(snapshot.formation_preset_id == preset and snapshot.combat_deployment_plan.formation_preset_id == preset
		and int(snapshot.combat_order_serial) == int(snapshot.combat_deployment_plan.order_serial),
		"SiteStore changed %s preset or order serial" % label): return {}
	var restored := TerrainArmy.new()
	# Production armies live in the scene tree; fixtures step them explicitly.
	root.add_child(restored)
	restored.set_process(false)
	restored.roster_size = members
	restored.exchange_enabled = true
	var coordinator := Coordinator.new()
	coordinator.register_formation(restored)
	restored.restore_combat_state(snapshot, restored_data, null, null)
	if not _check_contract(source, restored, coordinator, preset, members, hold): return {}
	return {"data": restored_data, "army": restored, "coordinator": coordinator}

func _free_army(army: TerrainArmy, coordinator: SiteCombatMovementCoordinator) -> void:
	coordinator.unregister_formation(army)
	army.free()

func _find_origin(data: TerrainData, members: int) -> Vector2i:
	var rows := ceili(float(members) / 10.0)
	for y in range(2, data.size.y - rows - 2):
		for x in range(2, mini(24, floori(float(data.size.x) / 3.0))):
			var clear := true
			for index in range(members):
				if not data.is_walkable(Vector2i(x + index % 10, y + floori(float(index) / 10.0))):
					clear = false
					break
			if clear:
				return Vector2i(x, y)
	return TerrainArmy.INVALID_CELL

func _find_goal(data: TerrainData, army: TerrainArmy, origin: Vector2i, preset: String, members: int) -> Vector2i:
	var first_x := maxi(origin.x + (18 if members < 200 else 30), 20)
	for x in range(first_x, data.size.x - 3):
		for y in range(8, data.size.y - 8):
			var candidate := Vector2i(x, y)
			if not data.is_walkable(candidate):
				continue
			var slots := Destination.shape_slots(preset, members, candidate, Vector2i.RIGHT)
			if slots.size() != members:
				continue
			var clear := true
			for slot: Vector2i in slots:
				if not data.is_walkable(slot):
					clear = false
					break
			if not clear:
				continue
			var preview: Dictionary = army.preview_combat_move(candidate, Vector2i.RIGHT, preset)
			if bool(preview.get("ok", false)) and preview.platform_slots.size() == members and preview.resolved_anchor == candidate:
				return candidate
	return TerrainArmy.INVALID_CELL

func _case(data: TerrainData, preset: String, members: int, hold_after_load: bool) -> bool:
	var origin := _find_origin(data, members)
	if not _require(origin != TerrainArmy.INVALID_CELL, "No persistently walkable %d-person spawn rectangle" % members): return false
	var source := Helper.create_test_army(data, 1, 0, members, origin)
	var source_coordinator := Coordinator.new()
	source_coordinator.register_formation(source)
	var goal := _find_goal(data, source, origin, preset, members)
	if not _require(goal != TerrainArmy.INVALID_CELL, "No preview-approved %s destination for %d members" % [preset, members]): return false
	var issued: Dictionary = source.issue_combat_order(source.current_commander, TerrainArmy.CombatOrder.MOVE, goal, -1, Vector2i.RIGHT, preset)
	if not _require(bool(issued.get("ok", false)), "%s %d-person MOVE was rejected: %s" % [preset, members, issued]): return false
	var animated := false
	for tick in range(600):
		var before: Array[Vector2i] = source.cells.duplicate()
		_advance(source, source_coordinator)
		if not _physical_ok(source, data, before): return false
		if _animated(source):
			animated = true
			break
	if not _require(animated and source.combat_order == TerrainArmy.CombatOrder.MOVE, "%s %d-person MOVE never entered a physical step" % [preset, members]): return false
	var move_result := _round_trip(data, source, preset, members, false)
	if move_result.is_empty(): return false
	_free_army(source, source_coordinator)
	var moving: TerrainArmy = move_result.army
	var moving_coordinator: SiteCombatMovementCoordinator = move_result.coordinator
	var moving_data: TerrainData = move_result.data
	if not hold_after_load:
		_free_army(moving, moving_coordinator)
		print("COMBAT FORMATION STORE MATRIX MOVE PASS: preset=", preset, " members=", members)
		return true
	var completed := false
	for tick in range(3500):
		var before: Array[Vector2i] = moving.cells.duplicate()
		_advance(moving, moving_coordinator)
		if not _physical_ok(moving, moving_data, before): return false
		if moving.combat_order == TerrainArmy.CombatOrder.HOLD:
			completed = moving.command_status.begins_with("已抵達")
			break
	if not _require(completed, "%s loaded MOVE did not reach HOLD" % preset): return false
	var hold_result := _round_trip(moving_data, moving, preset, members, true)
	if hold_result.is_empty(): return false
	_free_army(moving, moving_coordinator)
	var held: TerrainArmy = hold_result.army
	var held_coordinator: SiteCombatMovementCoordinator = hold_result.coordinator
	var settled: Array[Vector2i] = held.cells.duplicate()
	for tick in range(100):
		_advance(held, held_coordinator)
		if not _require(held.combat_order == TerrainArmy.CombatOrder.HOLD and held.cells == settled
			and held_coordinator.get_inflight_batches_for_formation(held).is_empty(), "%s loaded HOLD drifted within five seconds" % preset): return false
	_free_army(held, held_coordinator)
	print("COMBAT FORMATION STORE MATRIX HOLD PASS: preset=", preset, " members=", members)
	return true

func _run() -> void:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581, {"size": Vector2i(80, 65)})
	SiteEnvironment.initialize(data, "formation-store-matrix-fixture")
	for index in range(data.height_levels.size()):
		data.height_levels[index] = 0
		data.site.terrain_changes[str(index)] = 0
	SiteRuntime.rebuild_terrain_edges(data)
	data.site.army_trial_active = true
	data.site.army_next_team = 2
	data.site.actors = {}
	data.site.combat_left = 0.0
	for preset: String in PRESETS:
		if not _case(data, preset, 25, true): return
	if not _case(data, "square", 200, false): return
	print("COMBAT FORMATION STORE MATRIX PASS: six MOVE+HOLD presets, 200-person in-flight MOVE")
	quit(0)
