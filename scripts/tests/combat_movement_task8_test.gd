extends SceneTree
## Unit test suite for Task 8: Meaningful Progress, Stall Clock eligibility,
## Staged Obstacle Recovery (Stages 0-4), CONGESTED vs BLOCKED differentiation,
## and ENGAGING tactical overlay.

const Recovery = preload("res://scripts/terrain_lab/formation_recovery_controller.gd")
const MovePlan = preload("res://scripts/terrain_lab/combat_move_plan.gd")
const Profile = preload("res://scripts/terrain_lab/formation_movement_profile.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")
const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Running Task 8 Progress, Staged Recovery & ENGAGING Test ---")
	
	var plan = MovePlan.new()
	plan.eligible_member_count = 100
	plan.current_width = 4
	
	# 1. Meaningful Progress test
	# Initial progress check sets baseline
	Recovery.check_meaningful_progress(plan, 5.0, 0, 0, 0)
	assert(plan.previous_median_path_s == 5.0)
	
	# Simulate 1 second of stall
	Recovery.update_stall_clock(plan, 1.0)
	assert(abs(plan.active_stall_total_sec - 1.0) < 0.001)
	
	# Small progress (+0.2) is not meaningful (must be >= 0.5)
	var prog1 := Recovery.check_meaningful_progress(plan, 5.2, 0, 0, 0)
	assert(not prog1, "Progress under 0.5 is not meaningful")
	assert(plan.active_stall_total_sec > 0.9)
	
	# Meaningful progress (+0.6 >= 0.5): resets stall clock!
	var prog2 := Recovery.check_meaningful_progress(plan, 5.6, 0, 0, 0)
	assert(prog2, "Progress >= 0.5 is meaningful")
	assert(plan.active_stall_total_sec == 0.0, "Stall clock must reset to 0 upon meaningful progress")
	print("TASK 8: Meaningful progress median_path_s detection and stall reset verified")
	
	# 2. Stall Clock Exclusions test
	# Exclusion A: scheduler_deferred
	plan.scheduler_deferred = true
	Recovery.update_stall_clock(plan, 2.0)
	assert(plan.active_stall_total_sec == 0.0, "Scheduler deferred must freeze stall clock")
	plan.scheduler_deferred = false
	
	# Exclusion B: waiting_animation_only
	plan.waiting_animation_only = true
	Recovery.update_stall_clock(plan, 2.0)
	assert(plan.active_stall_total_sec == 0.0, "Waiting animation must freeze stall clock")
	plan.waiting_animation_only = false
	
	# Exclusion C: ENGAGING overlay
	Recovery.set_engaging_overlay(plan, true)
	assert(plan.tactical_overlay == Types.TacticalOverlay.ENGAGING)
	Recovery.update_stall_clock(plan, 5.0)
	assert(plan.active_stall_total_sec == 0.0, "ENGAGING overlay must freeze stall clock")
	Recovery.set_engaging_overlay(plan, false)
	assert(plan.tactical_overlay == Types.TacticalOverlay.NONE)
	print("TASK 8: Stall clock exclusions (scheduler, animation, ENGAGING) verified")
	
	# 3. Staged Obstacle Recovery test
	var u_map = Helper.build_u_turn_map()
	var test_data: TerrainData = u_map["data"]
	var prof = Profile.default_infantry()
	plan.resolved_anchor = Vector2i(30, 40)
	var test_path: Array[Vector2i] = [Vector2i(30, 20), Vector2i(30, 21), Vector2i(30, 22)]
	plan.macro_path = test_path
	
	# Stage 0: Initial wait (0.6s)
	plan.recovery_stage = 0
	plan.stage_elapsed_sec = 0.7
	Recovery.process_recovery(plan, Vector2i(30, 20), test_data, prof, 10.0)
	assert(plan.recovery_stage == 1, "Must advance to Stage 1 after wait grace period")
	
	# Stage 1: Slot adjustment observe (0.6s)
	plan.stage_elapsed_sec = 0.7
	Recovery.process_recovery(plan, Vector2i(30, 20), test_data, prof, 10.7)
	assert(plan.recovery_stage == 2, "Must advance to Stage 2 after slot adjust observe")
	assert(plan.current_width == 1, "Stage 2 must force single-file column width = 1")
	
	# Stage 2: Single file observe (0.8s)
	plan.stage_elapsed_sec = 0.9
	Recovery.process_recovery(plan, Vector2i(30, 21), test_data, prof, 11.6)
	assert(plan.recovery_stage == 3, "Must advance to Stage 3 after single file observe")
	print("TASK 8: Staged recovery progression (Stages 0 to 3) verified")
	
	# 4. Final failure classification: CONGESTED vs BLOCKED
	# Case A: Static path exists but stall reached 12.0s -> CONGESTED
	plan.active_stall_total_sec = 12.5
	var code_congested := Recovery.process_recovery(plan, Vector2i(30, 20), test_data, prof, 25.0)
	assert(code_congested == Types.RuntimeMoveFailureCode.CONGESTED, "Must classify as CONGESTED when static path exists")
	assert(plan.phase == Types.CombatMovePhase.FAILED)
	
	# Case B: Static path does NOT exist (wall blocking completely) -> BLOCKED
	# Make destination completely blocked
	var wall_pos := Vector2i(5, 5)
	test_data.flags[test_data.index(wall_pos)] = 0
	test_data.static_blocked[test_data.index(wall_pos)] = 1
	plan.resolved_anchor = wall_pos
	plan.active_stall_total_sec = 12.5
	var code_blocked := Recovery.process_recovery(plan, Vector2i(30, 20), test_data, prof, 30.0)
	assert(code_blocked == Types.RuntimeMoveFailureCode.BLOCKED, "Must classify as BLOCKED when static path is impossible")
	print("TASK 8: Accurate differentiation between CONGESTED and BLOCKED verified")
	
	print("TASK 8 COMPLETE: Progress, Staged Recovery & ENGAGING fully operational!")
	quit(0)
