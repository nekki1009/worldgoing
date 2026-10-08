extends SceneTree
## Test C: Route budget aging fairness & rear rank starvation prevention
## Verifies that:
## 1. Tight route budget (e.g. 4 calls/tick) does not permanently starve rear ranks.
## 2. Unserved members accumulate defer ticks and receive priority via aging.
## 3. All 16 members successfully acquire routes within bounded ticks.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const ArmyScript = preload("res://scripts/terrain_lab/terrain_army.gd")
const Profile = preload("res://scripts/terrain_lab/formation_movement_profile.gd")
const MovePlan = preload("res://scripts/terrain_lab/combat_move_plan.gd")

class MockTightRouteBudget:
	extends RefCounted
	var max_calls_per_tick: int = 4
	var calls_used: int = 0
	var expansions_used: int = 0
	var total_calls: int = 0
	var total_expansions: int = 0
	var call_records: Array[Dictionary] = []
	
	func begin_tick() -> void:
		calls_used = 0
		expansions_used = 0
		call_records.clear()
		
	func can_request_route(_formation_id: int) -> bool:
		return calls_used < max_calls_per_tick
		
	func request_route_budget(_formation_id: int) -> int:
		return 256
		
	func record_route_result(_formation_id: int, calls: int, expansions: int) -> void:
		calls_used += calls
		expansions_used += expansions
		total_calls += calls
		total_expansions += expansions
		call_records.append({"calls": calls, "expansions": expansions})

	func get_allocation(_formation_id: int) -> Dictionary:
		return {
			"remaining_calls": max_calls_per_tick - calls_used,
			"remaining_expansions": 1024 - expansions_used
		}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Running Test C: Route Budget Aging Fairness Test ---")
	
	var data := Helper.build_flat_map(60, 60)
	var army := Helper.create_test_army(data, 1, 0, 16, Vector2i(5, 5))
	army._formation_movement_profile = Profile.default_infantry()
	army.combat_order = ArmyScript.CombatOrder.MOVE
	
	var plan = MovePlan.new()
	plan.current_width = 4
	army._combat_move_plan = plan
	
	var member_ids: Array[int] = army._get_active_member_ids()
	for i in range(member_ids.size()):
		var mid: int = member_ids[i]
		var idx := army.index_for_identity(mid)
		# Set goal 20 cells away so local route A* is required
		var goal := Vector2i(35 + (i % 4), 35 + (i / 4))
		army.combat_slots[idx] = goal
		plan.member_sequence_rank[mid] = i
		plan.member_defer_count[mid] = 0
		
	var budget = MockTightRouteBudget.new()
	budget.max_calls_per_tick = 4
	
	# Simulate ticks
	var max_deferred_observed := 0
	var total_ticks := 6
	
	for tick in range(1, total_ticks + 1):
		budget.begin_tick()
		army._refresh_member_route_caches(budget)
		
		# In Tick 1, verify that Aging pool ran Pass 1 first and served rear ranks with actual expansions
		if tick == 1:
			assert(plan.member_paths.has(member_ids[8]), "Aging pool must serve rear member rank 8 in Tick 1!")
			assert(plan.member_paths.has(member_ids[9]), "Aging pool must serve rear member rank 9 in Tick 1!")
			assert(budget.call_records.size() >= 2, "At least 2 calls must be recorded in Tick 1")
			var aging_exp1: int = int(budget.call_records[0].get("expansions", 0))
			var aging_exp2: int = int(budget.call_records[1].get("expansions", 0))
			print("Tick 1 aging rear-rank expansions consumed: %d, %d" % [aging_exp1, aging_exp2])
			assert(aging_exp1 > 0 and aging_exp2 > 0, "Aging requests must consume positive expansion budget, not empty call slots!")
		
		var routes_count := 0
		for mid in member_ids:
			if plan.member_paths.has(mid):
				routes_count += 1
			else:
				var def_ticks: int = int(plan.member_defer_count.get(mid, 0))
				max_deferred_observed = maxi(max_deferred_observed, def_ticks)
		print("Tick %d: %d/16 members have routes (budget used=%d calls, %d exp, max_defer=%d)" % [
			tick, routes_count, budget.calls_used, budget.expansions_used, max_deferred_observed
		])
		
	var final_routes: int = plan.member_paths.size()
	print("Final members with routes: %d/16" % final_routes)
	assert(final_routes == 16, "All 16 members must receive routes within %d ticks" % total_ticks)
	assert(max_deferred_observed <= 4, "No member should suffer excessive starvation (max_defer=%d <= 4)" % max_deferred_observed)
	
	# Verify that rear ranks (ranks 8..15) actually got paths
	for rank in range(8, 16):
		var mid: int = member_ids[rank]
		assert(plan.member_paths.has(mid), "Rear member %d (rank %d) must have a valid route" % [mid, rank])
		
	print("TEST C PASSED: Aging scheduler eliminates starvation!")
	quit(0)
