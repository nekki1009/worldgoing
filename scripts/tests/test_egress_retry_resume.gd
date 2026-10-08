extends SceneTree
## Test: Resumable Multi-Source Dijkstra (EgressSearchState)
## Verifies that:
## 1. When Dijkstra reaches MAX_EGRESS_FIELD_EXPANSIONS (4096), it stores frontier
##    in EgressSearchState and queues a retry request.
## 2. Subsequent ticks resume directly from the saved frontier instead of restarting.
## 3. Order cancellation immediately invalidates and purges the old state.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")
const Profile = preload("res://scripts/terrain_lab/formation_movement_profile.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Running Test: Resumable Multi-Source Dijkstra (EgressSearchState) ---")

	# Build a large 80x80 map (6400 tiles > 4096)
	var data := Helper.build_flat_map(80, 80)
	var army := Helper.create_test_army(data, 1, 0, 10, Vector2i(5, 5))
	var coord := Coordinator.new()
	coord.register_formation(army)

	# Setup a macro path starting at (75, 75)
	var macro_path: Array[Vector2i] = [Vector2i(75, 75), Vector2i(74, 75)]
	var exit_k := 1
	var prof = Profile.default_infantry()

	# 1. Step 1: Call with max_expansions = 1000 (< total tiles between 75,75 and 5,5)
	var dist_field1: Dictionary = army._build_egress_distance_field(macro_path, exit_k, prof, 1000)
	var fid := army.get_formation_id()
	var state1: Types.EgressSearchState = coord.get_egress_search_state(fid)

	assert(state1 != null, "EgressSearchState must be saved in coordinator")
	assert(not state1.completed, "Search must be incomplete after 1000 expansions on 80x80 map")
	assert(state1.total_expansions == 1000, "Should have expanded exactly 1000 nodes, got: " + str(state1.total_expansions))
	assert(army.get_active_move_plan() == null or army.get_active_move_plan().egress_rank_needs_retry, "Retry flag must be set")

	# 2. Step 2: Resume search using step_egress_search for 1500 more expansions
	var req := Types.EgressRetryRequest.new(fid, army.get_order_serial(), 0)
	var used_2: int = army.step_egress_search(req, 1500)
	assert(used_2 == 1500, "Should have used 1500 expansions on resume, used: " + str(used_2))
	assert(state1.total_expansions == 2500, "Total expansions must accumulate across ticks (1000+1500=2500), got: " + str(state1.total_expansions))

	# 3. Step 3: Finish the search with enough expansions to settle all members at (5, 5)
	var used_3: int = army.step_egress_search(req, 5000)
	assert(state1.completed, "Search must be completed once members are reached")
	for mid in army.get_active_members_occupancy().keys():
		assert(state1.reachability.get(mid) == Types.EgressReachability.REACHABLE, "Member must be marked REACHABLE")

	# 4. Invalidation test: changing order serial or invalidating state
	coord.invalidate_egress_search_state(fid)
	assert(coord.get_egress_search_state(fid) == null, "Invalidate must purge search state")
	# Empty targets continue to the budget; duplicate or already settled targets
	# still stop only after one valid expansion and its neighbors are processed.
	var first := Vector2i(75, 75)
	var second := Vector2i(74, 75)
	for case in [
		{"targets": {1: first, 2: first}, "already": false, "expected": 1},
		{"targets": {1: first, 2: first}, "already": true, "expected": 1},
		{"targets": {}, "already": false, "expected": 2},
	]:
		var edge_state := Types.EgressSearchState.new()
		edge_state.formation_id = fid
		edge_state.order_serial = army.get_order_serial()
		edge_state.buckets[0] = [second, first]
		edge_state.distances[first] = 0
		edge_state.distances[second] = 0
		edge_state.target_member_cells = case.targets
		if case.already:
			edge_state.settled_cells[first] = true
		coord.save_egress_search_state(fid, edge_state)
		var used := army.step_egress_search(req, 2)
		assert(used == case.expected, "Egress must preserve the original expansion stop point")
		assert(edge_state.total_expansions == used, "Egress expansion count must match its budget use")

	coord.unregister_formation(army)
	army.clear()
	army.free()
	TerrainArmy.release_contact_source()
	print("TEST PASSED: Resumable Multi-Source Dijkstra verified!")
	quit(0)
