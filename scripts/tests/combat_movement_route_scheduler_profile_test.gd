extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")

class Budget:
	extends RefCounted
	var calls := 0
	var expansions := 0
	func get_allocation(_fid: int) -> Dictionary:
		return {"remaining_calls": 8 - calls, "remaining_expansions": 1024 - expansions}
	func can_request_route(_fid: int) -> bool:
		return calls < 8 and expansions < 1024
	func request_route_budget(_fid: int) -> int:
		return mini(256, 1024 - expansions)
	func record_route_result(_fid: int, used_calls: int, used_expansions: int) -> void:
		calls += used_calls
		expansions += used_expansions

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var data := Helper.build_flat_map(60, 60)
	var army := Helper.create_test_army(data, 1, 0, 16, Vector2i(5, 5))
	var plan := CombatMovePlan.new()
	plan.current_width = 4
	army._combat_move_plan = plan
	army.combat_profile_enabled = true
	var mids := army._get_active_member_ids()
	for rank in range(16):
		var mid: int = mids[rank]
		var idx := army.index_for_identity(mid)
		plan.member_sequence_rank[mid] = rank
		army.combat_slots[idx] = army.cells[idx] if rank in range(1, 8) else Vector2i(20 + rank % 3, 10 + floori(float(rank) / 3.0))
	# Rank 8 is a genuine capped failure. Eight other requests can fill the
	# budget, including Pass 3's return of unused front capacity to the rear.
	var blocked_goal: Vector2i = army.combat_slots[army.index_for_identity(mids[8])]
	data.static_blocked[data.index(blocked_goal)] = 1
	var budget := Budget.new()
	army._refresh_member_route_caches(budget)
	var m: Dictionary = army.profiled_scheduler_metrics
	if not _require(budget.calls == 8 and int(m.get("pass1_rear_calls", 0)) == 4 and int(m.get("pass2_front_calls", 0)) == 1 and int(m.get("pass3_rear_calls", 0)) == 3,
		"Profile buckets must count actual Pass 1/2/3 route calls, including rear return flow"): return
	if not _require(int(m.get("pass1_rear_fail", 0)) == 1 and int(m.get("pass1_rear_success", 0)) == 3 and int(m.get("pass2_front_success", 0)) == 1,
		"Outcome buckets must separate a capped failed route from successful routes"): return
	if not _require(army.profiled_search_cap_failures >= 1 and int(m.get("pass1_rear_cap_fail", 0)) >= 1,
		"An open frontier cut off by the expansion quota must register in the executing pass"): return
	if not _require(int(m.get("needs_route", 0)) == 9 and int(m.get("rear_candidates", 0)) == 8 and int(m.get("front_candidates", 0)) == 1 and int(m.get("rear_backlog", 0)) == 1 and int(m.get("front_backlog", 0)) == 0,
		"Backlog must count unserved members, not failed but scheduled searches"): return
	if not _require(int(m.get("pass1_rear_actual_expansions", 0)) >= 256 and int(m.get("pass1_rear_billed_expansions", 0)) > 0,
		"Actual capped heap work and the independent route-budget accounting must stay visible"): return
	army.reset_movement_metrics()
	if not _require(army.profiled_scheduler_metrics.is_empty() and army.profiled_search_cap_failures == 0,
		"Reset must clear scheduler profiling without changing routes"): return
	print("COMBAT MOVEMENT ROUTE SCHEDULER PROFILE PASS")
	army.free()
	quit(0)

func _require(ok: bool, message: String) -> bool:
	if ok:
		return true
	push_error(message)
	quit(1)
	return false
