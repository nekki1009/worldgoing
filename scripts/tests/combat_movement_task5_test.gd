extends SceneTree
## Unit test suite for Task 5: Macro pathfinding (U-turn navigation),
## dynamic width detection, 3-tick hysteresis, monotonic cursor,
## and 100-member unique transit slot generation.

const Planner = preload("res://scripts/terrain_lab/formation_transit_planner.gd")
const MovePlan = preload("res://scripts/terrain_lab/combat_move_plan.gd")
const Profile = preload("res://scripts/terrain_lab/formation_movement_profile.gd")
const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Running Task 5 Macro Path & Transit Planner Test ---")
	
	# 1. Macro pathfinding on U-turn obstacle map
	var u_map = Helper.build_u_turn_map()
	var u_data: TerrainData = u_map["data"]
	var start_pos: Vector2i = u_map["start_area"] # (30, 20)
	var goal_pos: Vector2i = u_map["goal_area"]   # (30, 40)
	
	var prof = Profile.default_infantry()
	var macro_path = Planner.build_macro_path(u_data, start_pos, goal_pos, prof)
	assert(not macro_path.is_empty(), "Macro path around U-turn obstacle must be found")
	assert(macro_path[0] == start_pos, "Path must start at start_pos")
	assert(macro_path[macro_path.size() - 1] == goal_pos, "Path must terminate at goal_pos")
	
	# Verify all steps in path are valid
	for i in range(macro_path.size() - 1):
		assert(u_data.can_step(macro_path[i], macro_path[i + 1]), "Every step along macro path must be walkable")
	print("TASK 5: U-turn macro pathfinding verified (path length = %d)" % macro_path.size())
	
	# 2. Corridor width detection & 3-tick hysteresis
	var bottleneck_map = Helper.build_bottleneck_map(Vector2i(80, 40), 20, 25, 45, 1)
	var b_data: TerrainData = bottleneck_map["data"]
	
	# Center of corridor (x=30, y=20) has width 1
	var w_narrow = Planner.detect_corridor_width(b_data, Vector2i(30, 20), Vector2i(1, 0), prof)
	assert(w_narrow == 1, "Bottleneck corridor width must be 1")
	
	# Open area (x=10, y=20) has width 4
	var w_open = Planner.detect_corridor_width(b_data, Vector2i(10, 20), Vector2i(1, 0), prof)
	assert(w_open == 4, "Open area corridor width must be 4")
	
	# Test 3-tick hysteresis
	var plan = MovePlan.new()
	plan.current_width = 4
	plan.pending_width = 4
	
	# Tick 1: Detect width 1 -> pending becomes 1, counter = 1, current remains 4
	Planner.update_width_hysteresis(plan, 1)
	assert(plan.current_width == 4 and plan.pending_width == 1 and plan.width_confirm_counter == 1)
	
	# Tick 2: Detect width 1 -> counter = 2, current remains 4
	Planner.update_width_hysteresis(plan, 1)
	assert(plan.current_width == 4 and plan.width_confirm_counter == 2)
	
	# Tick 3: Detect width 1 -> confirmed! Current width switches to 1
	Planner.update_width_hysteresis(plan, 1)
	assert(plan.current_width == 1 and plan.width_confirm_counter == 0)
	print("TASK 5: Corridor width detection and 3-tick hysteresis verified")
	
	# 3. Monotonic macro cursor test
	plan.macro_path = macro_path
	plan.macro_cursor = 5
	
	# Moving forward to node 10 updates cursor
	var next_node: Vector2i = macro_path[10]
	Planner.update_macro_cursor(plan, next_node)
	assert(plan.macro_cursor == 10, "Cursor must advance forward to node 10")
	
	# Retreating position must NOT decrease cursor
	var prev_node: Vector2i = macro_path[3]
	Planner.update_macro_cursor(plan, prev_node)
	assert(plan.macro_cursor == 10, "Monotonic cursor must never decrease")
	print("TASK 5: Monotonic cursor update verified")
	
	# 4. 100-member unique transit slot generation in 1-cell wide corridor
	plan.macro_cursor = 25
	plan.current_width = 1 # Single file!
	var member_ids: Array[int] = []
	var current_cells: Dictionary = {}
	for i in range(100):
		var mid := 1000 + i
		member_ids.append(mid)
		current_cells[mid] = Vector2i(10 + (i % 10), 10 + (i / 10))
		
	var slots_1col = Planner.calculate_transit_slots(plan, u_data, prof, member_ids, current_cells)
	assert(slots_1col.size() == 100, "Must calculate transit slot for all 100 members")
	
	# Invariant check: NO DUPLICATE SLOTS!
	var unique_cells: Dictionary = {}
	for mid in member_ids:
		var slot: Vector2i = slots_1col[mid]
		assert(not unique_cells.has(slot), "Duplicate transit slot detected at %s for member %d!" % [str(slot), mid])
		unique_cells[slot] = mid
	assert(unique_cells.size() == 100, "All 100 transit slots must be strictly unique")
	print("TASK 5: 100-member single-file column unique transit slots verified")
	
	# 5. 100-member unique transit slot generation in 4-column open width
	plan.current_width = 4
	var slots_4col = Planner.calculate_transit_slots(plan, u_data, prof, member_ids, current_cells)
	assert(slots_4col.size() == 100)
	var unique_4col: Dictionary = {}
	for mid in member_ids:
		var slot: Vector2i = slots_4col[mid]
		assert(not unique_4col.has(slot), "Duplicate 4-column transit slot detected at %s!" % str(slot))
		unique_4col[slot] = mid
	assert(unique_4col.size() == 100, "All 100 4-column transit slots must be strictly unique")
	print("TASK 5: 100-member 4-column open transit slots verified")
	
	print("TASK 5 COMPLETE: Macro Path & Transit Planner fully operational!")
	quit(0)
