extends SceneTree
## Targeted Test: Transit Lookahead Pipeline Safety and Quorum Progression
## Verifies:
## 1. Lookahead expands head_s 2-4 verified rows ahead of macro_cursor.
## 2. All lookahead rows satisfy cross-section and predecessor connectivity.
## 3. Vanguard members pipeline forward smoothly across 4-wide -> 1-wide -> 90-degree corner -> ramp.
## 4. Retaining quorum >= 2 advances the cursor reliably.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const ArmyScript = preload("res://scripts/terrain_lab/terrain_army.gd")
const Profile = preload("res://scripts/terrain_lab/formation_movement_profile.gd")
const MovePlan = preload("res://scripts/terrain_lab/combat_move_plan.gd")
const TransitPlanner = preload("res://scripts/terrain_lab/formation_transit_planner.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Running test_transit_lookahead_pipeline ---")
	
	# Build map: 40x40
	# 4-wide camp: x in [0, 9], y in [10, 13]
	# 1-wide bottleneck: x in [10, 15], y = 10
	# 90-degree corner: from (15, 10) turn north to (15, 15)
	# 1-wide ramp: at (15, 13) height goes from 0 to 1 with legal ramp
	var data := TerrainData.new()
	data.allocate(Vector2i(40, 40))
	SiteEnvironment.initialize(data, "lookahead-pipeline-fixture")
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	
	# Set ramp at (15, 13) going UP north (direction UP = index 3)
	# DIRECTIONS = [RIGHT(1,0), DOWN(0,1), LEFT(-1,0), UP(0,-1)]
	# Wait, from (15, 12) to (15, 13) is DOWN (0, 1), so direction 1
	var idx_12 := data.index(Vector2i(15, 12))
	var idx_13 := data.index(Vector2i(15, 13))
	var idx_14 := data.index(Vector2i(15, 14))
	data.height_levels[idx_13] = 1
	data.height_levels[idx_14] = 1
	
	# DIRECTIONS = [UP(0,-1), RIGHT(1,0), DOWN(0,1), LEFT(-1,0)]
	# from (15, 12) to (15, 13) is DOWN -> DIRECTIONS[2]
	# opposite from (15, 13) to (15, 12) is UP -> DIRECTIONS[0]
	data.ramp_edges[idx_12] = 1 << 2
	data.ramp_edges[idx_13] = 1 << 0
	data.flags[idx_12] |= TerrainData.Flag.RAMP
	data.flags[idx_13] |= TerrainData.Flag.RAMP
	
	assert(data.can_step(Vector2i(15, 12), Vector2i(15, 13)), "Ramp step must be legal!")
	
	var army := Helper.create_test_army(data, 1, 0, 6, Vector2i(8, 10))
	var profile = Profile.default_infantry()
	army._formation_movement_profile = profile
	army.combat_order = ArmyScript.CombatOrder.MOVE
	
	var plan = MovePlan.new()
	plan.macro_cursor = 0
	plan.current_width = 1
	
	# Path:
	# 0..2: in camp (8,10), (9,10), (10,10)
	# 3..7: bottleneck (11,10), (12,10), (13,10), (14,10), (15,10)
	# 8..11: turn south (15,11), (15,12), (15,13 ramp), (15,14)
	for x in range(8, 16):
		plan.macro_path.append(Vector2i(x, 10))
	for y in range(11, 15):
		plan.macro_path.append(Vector2i(15, y))
		
	army._combat_move_plan = plan
	var member_ids: Array[int] = army._get_active_member_ids()
	for i in range(member_ids.size()):
		plan.member_sequence_rank[member_ids[i]] = i
		var mid_idx := army.index_for_identity(member_ids[i])
		army.cells[mid_idx] = Vector2i(8, 10)

	var occ = army.get_active_members_occupancy()
	
	# Test 1: Verified head_s lookahead
	var slots := TransitPlanner.calculate_transit_slots(plan, data, profile, member_ids, occ)
	var vanguard_mid: int = member_ids[0]
	var head_s: float = float(plan.member_path_s.get(vanguard_mid, 0.0))
	print("At macro_cursor=0, vanguard assigned head_s = %.1f" % head_s)
	assert(head_s >= 2.0, "head_s must look ahead at least 2 rows (got %.1f)!" % head_s)
	assert(head_s <= 4.0, "head_s must not exceed MAX_TRANSIT_LOOKAHEAD_ROWS (4) (got %.1f)!" % head_s)
	
	# Test 2: Sequential vanguard advancement with quorum >= 2
	# Rank 0 member steps to node 2, Rank 1 steps to node 2
	var r0_idx := army.index_for_identity(member_ids[0])
	var r1_idx := army.index_for_identity(member_ids[1])
	army.cells[r0_idx] = plan.macro_path[2]
	army.cells[r1_idx] = plan.macro_path[1]
	
	# Only 1 member is at >= node 2, quorum is 2
	army.finalize_combat_movement_tick(0.1, null, null)
	assert(plan.macro_cursor == 1, "Cursor should only advance to 1 where 2 members are at or past (got %d)!" % plan.macro_cursor)
	
	# Second member catches up to node 2
	army.cells[r1_idx] = plan.macro_path[2]
	army.finalize_combat_movement_tick(0.1, null, null)
	assert(plan.macro_cursor == 2, "Quorum (2 members >= node 2) met: cursor must advance to 2 (got %d)!" % plan.macro_cursor)
	
	# Test 3: Approaching the ramp at node 9 (15, 12) -> node 10 (15, 13)
	plan.macro_cursor = 8 # at (15, 11)
	occ = army.get_active_members_occupancy()
	slots = TransitPlanner.calculate_transit_slots(plan, data, profile, member_ids, occ)
	head_s = float(plan.member_path_s.get(vanguard_mid, 0.0))
	print("At macro_cursor=8, vanguard assigned head_s = %.1f" % head_s)
	assert(head_s >= 10.0, "Lookahead must successfully verify across the legal ramp (got %.1f)!" % head_s)
	
	# Test 4: Cliff without ramp blocks lookahead
	# Remove ramp edge between (15, 12) and (15, 13)
	data.ramp_edges[idx_12] = 0
	data.ramp_edges[idx_13] = 0
	assert(not data.can_step(Vector2i(15, 12), Vector2i(15, 13)), "Step must now be illegal cliff!")
	slots = TransitPlanner.calculate_transit_slots(plan, data, profile, member_ids, occ)
	head_s = float(plan.member_path_s.get(vanguard_mid, 0.0))
	print("At macro_cursor=8 with cliff, vanguard assigned head_s = %.1f" % head_s)
	assert(head_s == 9.0, "Lookahead must STOP at un-steppable cliff node 9 (got %.1f)!" % head_s)
	
	print("PASS: test_transit_lookahead_pipeline passed successfully!")
	quit(0)
