extends SceneTree
## Logical stall time is distinct from physical movement and scheduler waiting.
## Physical .38-second stepping is covered by combat_movement_physical_chain_test (retired 2026-11-02).

const Plan = preload("res://scripts/terrain_lab/combat_move_plan.gd")
const Recovery = preload("res://scripts/terrain_lab/formation_recovery_controller.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var plan = Plan.new()
	plan.eligible_member_count = 1
	Recovery.update_stall_clock(plan, 0.5)
	assert(is_equal_approx(plan.active_stall_total_sec, 0.5))
	assert(not Recovery.check_meaningful_progress(plan, 2.0, 0, 0, 0))
	Recovery.update_stall_clock(plan, 0.5)
	assert(is_equal_approx(plan.active_stall_total_sec, 1.0))
	assert(not Recovery.check_meaningful_progress(plan, 2.0, 0, 0, 0))
	assert(Recovery.check_meaningful_progress(plan, 2.5, 0, 0, 0))
	assert(is_zero_approx(plan.active_stall_total_sec))
	Recovery.update_stall_clock(plan, 0.2)
	plan.scheduler_deferred = true
	Recovery.update_stall_clock(plan, 0.5)
	assert(is_equal_approx(plan.active_stall_total_sec, 0.2))
	print("MOVE CADENCE STALL CLOCK PASS")
	quit(0)
