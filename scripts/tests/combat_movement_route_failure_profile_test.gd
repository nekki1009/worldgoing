extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var data := Helper.build_flat_map(12, 12)
	var army := Helper.create_test_army(data, 1, 0, 1, Vector2i(2, 2))
	var mid := army.combat_identity(0)
	var start := army.cells[0]
	var goal := Vector2i(6, 2)
	var goal_index := data.index(goal)
	army._combat_move_plan = CombatMovePlan.new()
	army._combat_move_plan.member_route_retry_count[mid] = 12
	army.combat_profile_enabled = true
	data.static_blocked[goal_index] = 1
	if not _require(army._find_combat_route_after_rejection(mid, start, goal, 64).is_empty(), "First blocked route must fail"): return
	if not _require(army._find_combat_route_after_rejection(mid, start, goal, 64).is_empty(), "Repeated blocked route must fail"): return
	if not _require(army.profiled_route_failures == 2 and army.profiled_retry12_failures == 2 and army.profiled_repeated_retry12_failures == 1,
		"Only the second high-retry failure at the same cell and goal is repeated"): return
	army._combat_move_plan.member_reservation_wait_age[mid] = 3
	if not _require(army._find_combat_route_after_rejection(mid, start, goal, 64).is_empty() and army.profiled_repeated_retry12_failures == 1,
		"Free-first-step mode must not count as the previous ordinary query"): return
	if not _require(army._find_combat_route_after_rejection(mid, start, goal, 64).is_empty() and army.profiled_repeated_retry12_failures == 1,
		"Returning from free-first-step mode must also start a fresh query sequence"): return
	if not _require(army._find_combat_route_after_rejection(mid, start, goal, 63).is_empty() and army.profiled_repeated_retry12_failures == 1,
		"A changed search quota must not count as the same query"): return
	if not _require(army._find_combat_route_after_rejection(mid, start, goal, 63).is_empty() and army.profiled_repeated_retry12_failures == 2,
		"A repeated query with the same mode and quota must be counted"): return
	data.static_blocked[goal_index] = 0
	if not _require(army._find_combat_route_after_rejection(mid, start, goal, 64).size() > 1 and army.profiled_route_successes == 1 and army.profiled_retry12_successes == 1,
		"A success must clear the failed-query diagnostic state"): return
	data.static_blocked[goal_index] = 1
	if not _require(army._find_combat_route_after_rejection(mid, start, goal, 64).is_empty() and army.profiled_repeated_retry12_failures == 2,
		"A failure after success must start a fresh sequence"): return
	army.reset_movement_metrics()
	if not _require(army.profiled_route_failures == 0 and army.profiled_repeated_retry12_failures == 0,
		"Reset must clear the profile counters and failed-query state"): return
	army.combat_profile_enabled = false
	if not _require(army._find_combat_route_after_rejection(mid, start, goal, 64).is_empty() and army.profiled_route_failures == 0,
		"Disabled profiling must leave all profile counters untouched"): return
	print("COMBAT MOVEMENT ROUTE FAILURE PROFILE PASS")
	army.free()
	quit(0)

func _require(ok: bool, message: String) -> bool:
	if ok:
		return true
	push_error(message)
	quit(1)
	return false
