extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Recovery = preload("res://scripts/terrain_lab/formation_recovery_controller.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

func _initialize() -> void:
	call_deferred("_run")

func _require(ok: bool, message: String) -> bool:
	if ok:
		return true
	push_error(message)
	quit(1)
	return false

func _new_plan() -> CombatMovePlan:
	var plan := CombatMovePlan.new()
	plan.phase = Types.CombatMovePhase.TRANSIT
	plan.resolved_anchor = Vector2i(15, 5)
	plan.eligible_member_count = 8
	for x in range(5, 16):
		plan.macro_path.append(Vector2i(x, 5))
	for mid in range(1, 9):
		plan.member_observed_path_s[mid] = 0.0
		plan.member_checkpoint_best_k[mid] = 0
	return plan

func _run() -> void:
	var moving := _new_plan()
	Recovery.check_meaningful_progress(moving, 0.0, 0, 0, 0)
	moving.active_stall_total_sec = 5.0
	moving.recovery_stage = 3
	# One of eight physical high-water marks crosses a four-node checkpoint.
	# Median, front quartile, cursor, and final-settle counts remain fixed.
	moving.member_checkpoint_best_k[1] = 4
	if not _require(Recovery.check_meaningful_progress(moving, 0.0, 0, 0, 0) and moving.active_stall_total_sec == 0.0 and moving.recovery_stage == 0,
		"A real minority checkpoint must prevent a false convoy stall"): return
	if not _require(not Recovery.check_meaningful_progress(moving, 0.0, 0, 0, 0),
		"A historical checkpoint must not repeatedly count as new progress"): return

	var stuck := _new_plan()
	var terrain := Helper.build_flat_map(30, 20)
	Recovery.check_meaningful_progress(stuck, 0.0, 0, 0, 0)
	for tick in range(241):
		# Assignment churn and one member's local observed oscillation do not
		# change a physical cell or earn a new checkpoint.
		stuck.assignment_epoch += 1
		stuck.member_transit_slots[1] = Vector2i(7 + tick % 2, 5)
		stuck.member_observed_path_s[1] = float(tick % 2)
		if not _require(not Recovery.check_meaningful_progress(stuck, 0.0, 0, 0, 0),
			"Standing reassignment or local oscillation reset the stall clock"): return
		Recovery.update_stall_clock(stuck, 0.05)
	if not _require(stuck.active_stall_total_sec >= Recovery.CONGESTION_ABORT_SEC and Recovery.process_recovery(stuck, Vector2i(5, 5), terrain, null, 20.0) == Types.RuntimeMoveFailureCode.CONGESTED,
		"A stationary convoy must still terminate at the original twelve-second boundary"): return
	print("COMBAT MOVEMENT PHYSICAL CHECKPOINT PROGRESS PASS")
	quit(0)
