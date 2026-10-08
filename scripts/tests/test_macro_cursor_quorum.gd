extends SceneTree
## Test D: Vanguard cohort quorum requirement for macro cursor advance
## Verifies that:
## 1. A single vanguard outlier rushing ahead cannot drag the macro cursor (Pegasus prevention).
## 2. When a quorum of vanguard members reaches the line, the cursor advances monotonically.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const ArmyScript = preload("res://scripts/terrain_lab/terrain_army.gd")
const Profile = preload("res://scripts/terrain_lab/formation_movement_profile.gd")
const MovePlan = preload("res://scripts/terrain_lab/combat_move_plan.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Running Test D: Macro Cursor Quorum Test ---")
	
	var data := Helper.build_flat_map(50, 50)
	var army := Helper.create_test_army(data, 1, 0, 8, Vector2i(10, 10))
	army._formation_movement_profile = Profile.default_infantry()
	army.combat_order = ArmyScript.CombatOrder.MOVE
	
	var plan = MovePlan.new()
	plan.macro_cursor = 0
	plan.current_width = 2 # Lane count = 2 -> quorum = 2
	
	# Macro path from (10, 10) to (25, 10)
	for x in range(10, 26):
		plan.macro_path.append(Vector2i(x, 10))
	army._combat_move_plan = plan
	
	var member_ids: Array[int] = army._get_active_member_ids()
	for i in range(member_ids.size()):
		var mid: int = member_ids[i]
		var idx := army.index_for_identity(mid)
		army.cells[idx] = Vector2i(10, 10) # All start at node 0
		plan.member_sequence_rank[mid] = i
		
	# Scenario 1: Single outlier (Rank 0 member) jumps ahead to node 5 (x=15, y=10)
	var rank0_mid: int = member_ids[0]
	var rank0_idx := army.index_for_identity(rank0_mid)
	army.cells[rank0_idx] = Vector2i(15, 10)
	army.finalize_combat_movement_tick(0.1, null, null)
	
	print("After single outlier jump: macro_cursor = %d" % plan.macro_cursor)
	assert(plan.macro_cursor == 0, "Single outlier must NOT advance macro cursor without quorum (expected 0, got %d)!" % plan.macro_cursor)
	
	# Scenario 2: Second vanguard member (Rank 1 member) reaches node 2 (x=12, y=10)
	# Now 2 vanguard members are at node >= 2!
	var rank1_mid: int = member_ids[1]
	var rank1_idx := army.index_for_identity(rank1_mid)
	army.cells[rank1_idx] = Vector2i(12, 10)
	army.finalize_combat_movement_tick(0.1, null, null)
	
	print("After second vanguard reaches node 2: macro_cursor = %d" % plan.macro_cursor)
	assert(plan.macro_cursor == 2, "Quorum (2 members >= node 2) met: macro cursor must advance to 2 (got %d)!" % plan.macro_cursor)
	
	# Scenario 3: Rank 1 member advances to node 3 (x=13, y=10)
	# Now 2 vanguard members are at node >= 3!
	army.cells[rank1_idx] = Vector2i(13, 10)
	army.finalize_combat_movement_tick(0.1, null, null)
	
	print("After second vanguard reaches node 3: macro_cursor = %d" % plan.macro_cursor)
	assert(plan.macro_cursor == 3, "Quorum (2 members >= node 3) met: macro cursor must advance to 3 (got %d)!" % plan.macro_cursor)
	
	# Scenario 4: Stretch guard test:
	# Vanguard members teleport to node 25 (x=35), but rear ranks remain at node 0 (x=10).
	# Stretch > MAX_FORMATION_STRETCH (20): cursor advancement must halt!
	plan.macro_cursor = 3
	army.cells[rank0_idx] = Vector2i(25, 10) # node 15
	army.cells[rank1_idx] = Vector2i(25, 10) # node 15
	# Remaining 6 members stay at (10, 10) [node 0]
	army.finalize_combat_movement_tick(0.1, null, null)
	print("After stretch test (vanguard at node 15, rear at node 0): macro_cursor = %d" % plan.macro_cursor)
	assert(plan.macro_cursor <= 3 + 3, "Macro cursor advancement must be restrained when formation stretch exceeds limit!")
	
	# Scenario 5: 100-member width-1 column depth fixture
	# Verifies that a normal 100-man column spanning 75 tiles is NOT halted by Stretch Guard,
	# but excess stretch beyond expected_depth + FORMATION_STRETCH_SLACK is halted.
	var col_data := Helper.build_flat_map(160, 20)
	var col_army := Helper.create_test_army(col_data, 2, 0, 100, Vector2i(0, 5))
	col_army._formation_movement_profile = Profile.default_infantry()
	col_army.combat_order = ArmyScript.CombatOrder.MOVE
	
	var col_plan = MovePlan.new()
	col_plan.current_width = 1 # Single-file column (lane_count = 1)
	col_plan.macro_cursor = 96
	for x in range(160):
		col_plan.macro_path.append(Vector2i(x, 10))
	col_army._combat_move_plan = col_plan
	
	var col_mids: Array[int] = col_army._get_active_member_ids()
	# Distribute 100 members uniformly along the single-file path (nodes 99 down to 0)
	for r in range(100):
		var mid: int = col_mids[r]
		var idx := col_army.index_for_identity(mid)
		var node_k: int = 99 - r
		col_army.cells[idx] = Vector2i(node_k, 10)
		col_plan.member_sequence_rank[mid] = r
		col_plan.member_observed_path_k[mid] = node_k
		
	# Sub-case 5A: Natural column depth (~75 tiles between head and p25)
	# With rank 0 at node 99 and rank 1 at node 98, quorum = 2 requires 2 members >= candidate, so candidate = 98.
	# Stretch guard must NOT halt advancement: cursor advances from 96 to 98!
	col_army.finalize_combat_movement_tick(0.1, null, null)
	print("100-member width-1 natural column: macro_cursor = %d (expected 98)" % col_plan.macro_cursor)
	assert(col_plan.macro_cursor == 98, "Natural 75-tile column depth must advance to quorum node 98 without being halted by stretch guard (got %d)!" % col_plan.macro_cursor)
	
	# Sub-case 5B: Excess stretch: rear ranks (ranks 50..99) fall severely behind to node 0
	col_plan.macro_cursor = 96
	# Head remains at node 99, rank 1 at node 98
	for r in range(50, 100):
		var mid: int = col_mids[r]
		var idx := col_army.index_for_identity(mid)
		col_army.cells[idx] = Vector2i(0, 10)
		col_plan.member_observed_path_k[mid] = 0
		
	col_army.finalize_combat_movement_tick(0.1, null, null)
	print("100-member excess stretch column: macro_cursor = %d (expected halted at 96)" % col_plan.macro_cursor)
	assert(col_plan.macro_cursor == 96, "Excess stretch (> 75 + slack) must halt macro cursor advancement (got %d)!" % col_plan.macro_cursor)
	
	print("TEST D PASSED: Vanguard cohort quorum & stretch guard verified!")
	quit(0)
