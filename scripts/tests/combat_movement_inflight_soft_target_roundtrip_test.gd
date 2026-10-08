extends SceneTree
## A transient transit target change must not discard a route during an already committed edge.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var data := Helper.build_flat_map(45, 21)
	var army := Helper.create_test_army(data, 1, 0, 2, Vector2i(9, 10))
	var coordinator := Coordinator.new()
	coordinator.register_formation(army)
	var order: Dictionary = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(38, 10), -1, Vector2i.RIGHT)
	if not _require(bool(order.get("ok", false)), "Two-person MOVE must be accepted"): return
	if not _require(army.current_commander == 0, "Fixture needs the ordinary member in the second physical cell"): return
	army._order_delay = 0.0
	var mid := army.combat_identity(1)
	var index := army.index_for_identity(mid)
	var start: Vector2i = army.cells[index]
	var first := start + Vector2i.RIGHT
	var move: CombatMovePlan = army.get_active_move_plan()
	move.macro_path.clear()
	for x in range(4, 41):
		move.macro_path.append(Vector2i(x, 10))
	move.macro_cursor = 20
	# The real final deployment is far beyond this focused transit window.
	move.destination_plan.queue_hold_path_s = 9999.0
	move.member_observed_path_s[mid] = 6.0
	move.member_checkpoint_path_k[mid] = 6
	var no_search := SiteRouteBudget.new() # Keep route allocation out of this cache test.
	army.prepare_combat_movement_tick(1.0 / 30.0, no_search, coordinator.deployment_registry)
	print("INFLIGHT_FIXTURE phase=", move.phase, " slots=", move.member_transit_slots,
		" active_plan=", army.get_active_move_plan() == move, " order=", army.combat_order,
		" mid=", mid, " index=", index, " start=", start)
	if not _require(move.phase == CombatMovementTypes.CombatMovePhase.TRANSIT and move.member_transit_slots.has(mid), "Fixture must retain an active transit target"): return
	var original_target: Vector2i = move.member_transit_slots[mid]
	if not _require(army.combat_slots[index] == original_target and original_target.x > first.x
		and absi(original_target.y - start.y) <= 1, "Initial ordinary transit target must lie ahead in the flat row section"): return

	var route: Array[Vector2i] = [start]
	for x in range(start.x + 1, original_target.x + 1):
		route.append(Vector2i(x, start.y))
	var route_y := start.y
	while route_y != original_target.y:
		route_y += signi(original_target.y - route_y)
		route.append(Vector2i(original_target.x, route_y))
	move.member_paths[mid] = route.duplicate()
	move.stamp_member_route(mid, original_target)
	coordinator._rebuild_occupancy()
	var grid = coordinator.movement_reservation_grid
	grid.begin_tick(coordinator._current_occupancy, data)
	var pid: int = grid.propose_move(army.formation_runtime_id, mid, move.order_serial, start, first)
	grid.resolve_all()
	if not _require(pid > 0 and grid.proposal_lookup[pid].status == Types.MoveProposalStatus.ACCEPTED, "Grid must accept the original first edge"): return
	grid.commit_all(coordinator._member_lookup, 1)
	coordinator._register_started_batches()
	army.prepare_combat(0.10)
	if not _require(army.cells[index] == start and army.moving_to[index] == first and army.move_progress[index] > 0.0 and army.move_progress[index] < 1.0 and move.is_member_route_current(mid, original_target), "Original source and cached route must remain live midway through the committed edge"): return

	move.macro_cursor = 21
	move.member_route_retry_count[mid] = 3
	army.prepare_combat_movement_tick(1.0 / 30.0, no_search, coordinator.deployment_registry)
	var changed_target: Vector2i = move.member_transit_slots.get(mid, TerrainArmy.INVALID_CELL)
	if not _require(changed_target != original_target and army.moving_to[index] == first and army.cells[index] == start, "Retry must produce a different soft target while the Grid edge remains in flight"): return
	move.macro_cursor = 20
	army.prepare_combat_movement_tick(1.0 / 30.0, no_search, coordinator.deployment_registry)
	var returned_target: Vector2i = move.member_transit_slots.get(mid, TerrainArmy.INVALID_CELL)
	if not _require(returned_target == original_target and army.moving_to[index] == first and army.cells[index] == start, "Soft target must return before the committed edge completes"): return
	print("INFLIGHT_SOFT_ROUNDTRIP original=", original_target, " changed=", changed_target,
		" returned=", returned_target, " route_cached=", move.member_paths.has(mid),
		" physical=", army.cells[index], " committed_to=", army.moving_to[index])
	if not _require(move.is_member_route_current(mid, original_target) and move.member_paths[mid] == route,
		"A reversible soft target change during an in-flight edge must retain its legal cached route"): return

	army.prepare_combat(0.30)
	coordinator.complete_committed_moves()
	if not _require(army.cells[index] == first and army.moving_to[index] == TerrainArmy.INVALID_CELL
		and move.is_member_route_current(mid, original_target) and move.member_paths[mid][0] == first,
		"The original Grid edge must finish once and consume only the cached first node"): return

	# A second committed edge leaves T2 in place. Its old T1 cache is useful
	# until the physical edge finishes, then the next planning tick must discard it.
	var second := first + Vector2i.RIGHT
	coordinator._rebuild_occupancy()
	grid.begin_tick(coordinator._current_occupancy, data)
	var second_pid: int = grid.propose_move(army.formation_runtime_id, mid, move.order_serial, first, second)
	grid.resolve_all()
	if not _require(second_pid > 0 and grid.proposal_lookup[second_pid].status == Types.MoveProposalStatus.ACCEPTED,
		"Grid must accept the independent second physical edge"): return
	grid.commit_all(coordinator._member_lookup, 2)
	coordinator._register_started_batches()
	army.prepare_combat(0.10)
	if not _require(army.cells[index] == first and army.moving_to[index] == second
		and move.is_member_route_current(mid, original_target),
		"T1 route must still be live at the start of the second committed edge"): return
	move.macro_cursor = 21
	move.member_route_retry_count[mid] = int(move.member_route_retry_count.get(mid, 0)) + 3
	army.prepare_combat_movement_tick(1.0 / 30.0, no_search, coordinator.deployment_registry)
	var persistent_target: Vector2i = move.member_transit_slots.get(mid, TerrainArmy.INVALID_CELL)
	if not _require(persistent_target != original_target and army.combat_slots[index] == persistent_target
		and move.is_member_route_current(mid, original_target) and army.moving_to[index] == second,
		"Persistent T2 must preserve the old route only during the committed edge"): return
	army.prepare_combat(0.30)
	coordinator.complete_committed_moves()
	if not _require(army.cells[index] == second and army.moving_to[index] == TerrainArmy.INVALID_CELL
		and move.member_paths.has(mid) and move.member_paths[mid][0] == second,
		"Second Grid edge must finish before its old T1 cache is reconsidered"): return
	army.prepare_combat_movement_tick(1.0 / 30.0, no_search, coordinator.deployment_registry)
	print("INFLIGHT_SOFT_PERSISTENT original=", original_target, " persistent=", persistent_target,
		" after_arrival=", move.member_transit_slots.get(mid, TerrainArmy.INVALID_CELL),
		" route_cached=", move.member_paths.has(mid), " physical=", army.cells[index])
	if not _require(move.member_transit_slots.get(mid, TerrainArmy.INVALID_CELL) == persistent_target
		and army.combat_slots[index] == persistent_target and not move.member_paths.has(mid),
		"A soft target still at T2 after arrival must discard the stale T1 route on the next planning tick"): return
	print("COMBAT MOVEMENT INFLIGHT SOFT TARGET ROUNDTRIP PASS")
	coordinator.unregister_formation(army)
	army.free()
	quit(0)

func _require(ok: bool, message: String) -> bool:
	if ok:
		return true
	push_error(message)
	quit(1)
	return false
