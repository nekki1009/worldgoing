extends SceneTree
## Test A: Corridor with cliff on cross-section
## Verifies that corridor width detection and transit slot calculation
## never place slots across cliff edges or into illegal vertical steps.

const Planner = preload("res://scripts/terrain_lab/formation_transit_planner.gd")
const MovePlan = preload("res://scripts/terrain_lab/combat_move_plan.gd")
const Profile = preload("res://scripts/terrain_lab/formation_movement_profile.gd")
const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Running Test A: Transit Cliff Cross-Section Test ---")
	
	var prof := Profile.default_infantry()
	prof.max_step_height = 1 # Cliff of 2 cannot be stepped over
	var center := Vector2i(10, 10)
	var forward := Vector2i(1, 0) # Normal is (0, 1)

	# 1. Test 1-cell wide canyon bounded by cliffs on both sides (y <= 9 and y >= 11)
	var canyon_data := Helper.build_flat_map(40, 40)
	for y in range(40):
		if y != 10:
			for x in range(40):
				var idx := canyon_data.index(Vector2i(x, y))
				canyon_data.height_levels[idx] = 2

	var canyon_width := Planner.detect_corridor_width(canyon_data, center, forward, prof)
	print("Detected canyon width between two cliffs: %d" % canyon_width)
	assert(canyon_width == 1, "Canyon corridor bounded by height-2 cliffs on both sides must be width 1")

	# 2. Test one-sided cliff: y >= 11 is cliff (height 2), y <= 10 is flat (height 0)
	var single_cliff_data := Helper.build_flat_map(40, 40)
	for y in range(11, 40):
		for x in range(40):
			var idx := single_cliff_data.index(Vector2i(x, y))
			single_cliff_data.height_levels[idx] = 2

	# Left span (+y towards cliff) must be 0, right span (-y into open flat) can be up to 3
	var semi_width := Planner.detect_corridor_width(single_cliff_data, center, forward, prof)
	print("Detected width with one-sided cliff: %d" % semi_width)
	assert(semi_width == 4, "Width with one open side should utilize open ground")

	# 3. Test calculate_transit_slots: must never place slots on the cliff side (y >= 11)
	var plan := MovePlan.new()
	plan.macro_path = [Vector2i(5, 10), Vector2i(6, 10), Vector2i(7, 10), Vector2i(8, 10), Vector2i(9, 10), Vector2i(10, 10)]
	plan.macro_cursor = 5
	plan.current_width = 4 # 4 columns requested
	
	var member_ids: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]
	var current_cells: Dictionary = {}
	for mid in member_ids:
		current_cells[mid] = Vector2i(5, 10)
		
	var slots := Planner.calculate_transit_slots(plan, single_cliff_data, prof, member_ids, current_cells)
	assert(slots.size() == 8, "All 8 members must receive unique transit slots")
	
	for mid in member_ids:
		var slot: Vector2i = slots[mid]
		var h: int = int(single_cliff_data.height_levels[single_cliff_data.index(slot)])
		assert(h == 0, "Member %d transit slot %s has height %d; must not be placed on cliff (height 2)!" % [mid, str(slot), h])
		assert(slot.y <= 10, "Slot %s crossed into cliff area y >= 11!" % str(slot))
		
	# 4. Test 4-lanes -> 1-lane necking with longitudinal connectivity & Zipper Merge
	var necking_data := Helper.build_flat_map(40, 40)
	# At x >= 7: bottleneck (only y=10 is height 0, y != 10 is height 2)
	for y in range(40):
		if y != 10:
			for x in range(7, 40):
				necking_data.height_levels[necking_data.index(Vector2i(x, y))] = 2

	var plan_neck := MovePlan.new()
	plan_neck.macro_path = [
		Vector2i(4, 10), Vector2i(5, 10), Vector2i(6, 10),
		Vector2i(7, 10), Vector2i(8, 10), Vector2i(9, 10), Vector2i(10, 10)
	]
	plan_neck.macro_cursor = 6
	plan_neck.current_width = 4 # requested 4 lanes
	
	var neck_mids: Array[int] = [101, 102, 103, 104, 105, 106]
	var neck_curr: Dictionary = {}
	for mid in neck_mids:
		neck_curr[mid] = Vector2i(4, 10)
		
	var neck_slots := Planner.calculate_transit_slots(plan_neck, necking_data, prof, neck_mids, neck_curr)
	assert(neck_slots.size() == 6, "All 6 members in necking test must receive slots")
	
	# Unique check
	var seen_neck: Dictionary = {}
	for mid in neck_mids:
		var s: Vector2i = neck_slots[mid]
		assert(not seen_neck.has(s), "Duplicate slot %s assigned in necking test!" % str(s))
		seen_neck[s] = true
		var h: int = int(necking_data.height_levels[necking_data.index(s)])
		assert(h == 0, "Slot %s is on cliff height %d" % [str(s), h])
		
	# Front members in the bottleneck (x >= 7) must be single-file along y=10
	assert(neck_slots[101] == Vector2i(10, 10), "Rank 0 must take front bottleneck slot (10, 10)")
	assert(neck_slots[102] == Vector2i(9, 10), "Rank 1 must take next bottleneck slot (9, 10)")
	assert(neck_slots[103] == Vector2i(8, 10), "Rank 2 must take next bottleneck slot (8, 10)")
	assert(neck_slots[104] == Vector2i(7, 10), "Rank 3 must take next bottleneck slot (7, 10)")
	# Back members (x=6) can expand laterally
	assert(neck_slots[105].x <= 6, "Rank 4 must be behind the bottleneck")
	
	print("TEST A PASSED: Cross-section cliff isolation & Zipper Merge necking verified!")
	quit(0)
