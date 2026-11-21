extends "res://scripts/tests/site_fire_suppress_navigation_test.gd"
## UNRUN leaf: parallel jobs in the same original Army and Grid.

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	for f: Dictionary in fixtures.duplicate(): _close(f)
	TerrainArmy.release_contact_source()
	print("SITE_FIRE_MULTI_WORK_NAVIGATION_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	await process_frame
	quit(0 if ok else 1)

func _parallel_cancel() -> bool:
	var f := _fixture()
	var army: TerrainArmy = f.army
	var first := army.combat_identity(0)
	var second := army.combat_identity(1)
	var source_a: Vector2i = army.cells[0]
	var source_b: Vector2i = army.cells[1]
	var target_a := source_a + Vector2i(0, 2)
	var target_b := source_b + Vector2i(0, -2)
	var a := army.begin_suppress_approach(first, 101, target_a, army.get_order_serial())
	var b := army.begin_suppress_approach(second, 102, target_b, army.get_order_serial())
	if not _check(a.ok and b.ok and army._suppress_approaches.size() == 2, "Two people in same original Army reserve two different work slots"): return false
	var before: Dictionary = f.coordinator.deployment_registry.capture_handoff_state()
	if not _check(not army.begin_suppress_approach(first, 103, source_a, army.get_order_serial()).ok
		and before == f.coordinator.deployment_registry.capture_handoff_state(), "One person cannot run a second parallel job"): return false
	_tick(f)
	if not _check(army.moving_to[0] != TerrainArmy.INVALID_CELL and army.moving_to[1] != TerrainArmy.INVALID_CELL
		and f.coordinator.route_budget.site_calls_used == 2, "Both real work searches and original physical commits use same budget"): return false
	var endpoint_a: Vector2i = army.moving_to[0]
	var release := army.release_suppress_approach(first, 101)
	if not _check(release.phase == "SETTLING" and is_same(b.lease, f.coordinator.deployment_registry.owner_of(target_b))
		and army.suppress_approach_query(second, 102).ok, "Cancel first job preserves second exact lease and intent"): return false
	for tick in range(60): _tick(f)
	if not _check(army.cells[0] == endpoint_a and army.suppress_approach_query(first, 101).done
		and army.cells[1] == target_b and army.suppress_approach_query(second, 102).phase == "ARRIVED"
		and army._suppress_approaches.size() == 1 and army._reserved_cells.is_empty(),
		"First committed step settles once while second job really arrives at its own centre"): return false
	if not _check(not army.release_suppress_approach(second, 101).ok and is_same(b.lease, f.coordinator.deployment_registry.owner_of(target_b)),
		"Stale first token cannot release second member's lease"): return false
	army.release_suppress_approach(second, 102)
	_close(f)
	return true

func _parallel_new_order() -> bool:
	var f := _fixture()
	var army: TerrainArmy = f.army
	var ids: Array[int] = [army.combat_identity(0), army.combat_identity(1)]
	for index in range(2):
		var target: Vector2i = army.cells[index] + Vector2i(0, 2 if index == 0 else -2)
		if not _check(army.begin_suppress_approach(ids[index], 201 + index, target, army.get_order_serial()).ok, "Parallel work admits before new MOVE"): return false
	_tick(f)
	var endpoints: Array[Vector2i] = [army.moving_to[0], army.moving_to[1]]
	var result := army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(12, 10))
	if not _check(result.ok, "Original full reservation transaction accepts later MOVE", result): return false
	var plan := army.get_active_move_plan()
	var paths := plan.member_paths.duplicate(true)
	for index in range(2):
		if not _check(not army.suppress_approach_query(ids[index], 201 + index).ok
			and army.release_suppress_approach(ids[index], 201 + index).phase == "SETTLING", "Both old job intents become stale independently"): return false
	for tick in range(20):
		army.prepare_combat(STEP, STEP)
		f.coordinator.complete_committed_moves()
	if not _check(army.cells[0] == endpoints[0] and army.cells[1] == endpoints[1] and is_same(plan, army.get_active_move_plan())
		and plan.member_paths == paths and army._move_landed_members.is_empty() and army._reserved_cells.is_empty(),
		"Two old completions cannot pop any later MOVE route or land its members"): return false
	_close(f)
	return true

func _run() -> void:
	_finish(_parallel_cancel() and _parallel_new_order())
