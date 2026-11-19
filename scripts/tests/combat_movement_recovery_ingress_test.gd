extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Recovery = preload("res://scripts/terrain_lab/formation_recovery_controller.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

func _initialize() -> void:
	call_deferred("_run")

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false

func _run() -> void:
	var terrain := Helper.build_flat_map(30, 20)
	var plan := CombatMovePlan.new()
	var deployment := CombatDeploymentPlan.new()
	for x in range(5, 16):
		plan.macro_path.append(Vector2i(x, 5))
	plan.macro_cursor = 10
	plan.resolved_anchor = Vector2i(15, 5)
	plan.terrain_revision = terrain.navigation_revision
	plan.phase = Types.CombatMovePhase.PLATFORM_INGRESS
	plan.recovery_stage = 4
	plan.active_stall_total_sec = 4.0
	deployment.terrain_revision = terrain.navigation_revision
	deployment.member_slot_map[1] = Vector2i(15, 5)
	plan.destination_plan = deployment
	var original_path := plan.macro_path.duplicate()
	var result: int = Recovery.process_recovery(plan, Vector2i(7, 5), terrain, null, 10.0)
	if not _require(result == Types.RuntimeMoveFailureCode.NONE and plan.macro_path == original_path \
		and plan.macro_cursor == 10 and plan.path_epoch == 0,
		"Ingress recovery must retain a valid final path and forward cursor"): return
	plan.active_stall_total_sec = Recovery.CONGESTION_ABORT_SEC
	if not _require(Recovery.process_recovery(plan, Vector2i(7, 5), terrain, null, 11.0) \
		== Types.RuntimeMoveFailureCode.CONGESTED,
		"A truly stalled ingress must still report congestion"): return
	plan.phase = Types.CombatMovePhase.PLATFORM_INGRESS
	plan.active_stall_total_sec = 4.0
	terrain.navigation_revision += 1
	if not _require(Recovery.process_recovery(plan, Vector2i(7, 5), terrain, null, 12.0) \
		== Types.RuntimeMoveFailureCode.NONE and plan.path_epoch == 1 and plan.macro_cursor == 0,
		"A terrain revision must still permit macro replanning"): return
	print("COMBAT MOVEMENT RECOVERY INGRESS PASS")
	quit(0)
