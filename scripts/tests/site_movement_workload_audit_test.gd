extends "res://scripts/tests/site_movement_r3_replay_test.gd"
## Diagnostic only: preserve the original action trace and observe work outside its timer.

const AUDIT_DIR := "res://output/site_movement_event_audit_20260928"
const MOVE_GROUPS := {
	"macro": ["macro_path", "macro_cursor", "path_epoch", "current_width", "pending_width", "width_confirm_counter"],
	"assignments": ["member_transit_slots", "member_path_s", "member_assignment_epoch", "member_soft_assignment_epoch"],
	"roles": ["phase", "tactical_overlay", "member_entry_hold", "member_entry_waypoint", "member_crossed_swap_hold", "member_vacancy_chain_target", "member_queue_egress_waypoint"],
	"retry": ["member_reservation_wait_age", "member_defer_count", "member_route_retry_count", "member_route_target", "member_route_epoch"],
	"deadlines": ["next_late_swap_time_sec", "next_platform_recovery_time_sec", "next_queue_recovery_time_sec", "vacancy_chain_started_sec", "vacancy_chain_last_progress_sec"],
}
const DEPLOY_FIELDS := ["assignment_epoch", "member_slot_map", "member_role_map", "platform_footprint", "platform_slots", "admitted_platform_member_ids", "settled_platform_member_ids", "settled_queue_member_ids", "following_member_ids", "ingress_cell", "ingress_buffer_cells", "queue_released"]

func _fields(owner: Object, names: Array) -> Array:
	var values: Array = []
	for key: String in names:
		var value: Variant = owner.get(key)
		values.append(value.duplicate(true) if value is Dictionary or value is Array else value)
	return values

func _observe(army: TerrainArmy) -> Dictionary:
	var move: CombatMovePlan = army.get_active_move_plan()
	var deployment: CombatDeploymentPlan = army.get_active_deployment_plan()
	var result := {"has_move": move != null, "order": army.combat_order, "serial": army.get_order_serial(),
		"cells": army.cells.duplicate(), "claims": army.moving_to.duplicate(), "targets": army.combat_slots.duplicate(),
		"eligible": 0, "moving": 0, "ready": 0, "unfinished_ready": 0, "gated": 0, "identity": [], "time": 0.0}
	for index in range(army.combat_units.size()):
		if not army.is_member(index) or not army.combat_can_act(index) or army.is_controlled_person(index):
			continue
		result.identity.append(army.combat_identity(index))
		result.eligible += 1
		if army.moving_to[index] != TerrainArmy.INVALID_CELL:
			result.moving += 1
		elif army._combat_action_blocks_step(index):
			result.gated += 1
		else:
			result.ready += 1
			if army.cells[index] != army.combat_slots[index]:
				result.unfinished_ready += 1
	if move != null:
		for group: String in MOVE_GROUPS:
			result[group] = _fields(move, MOVE_GROUPS[group])
		result.time = move.planning_time_sec
		result["terrain_revision"] = move.terrain_revision
		result["phase"] = move.phase
	if deployment != null:
		result["deployment"] = _fields(deployment, DEPLOY_FIELDS)
	return result

func _stage_counters(world: Dictionary) -> Dictionary:
	var counters := {}
	for key: String in world.lab.combat_profile_usec:
		counters["lab_" + key] = int(world.lab.combat_profile_usec[key])
	for key: String in world.coordinator.profile_usec:
		counters["coordinator_" + key] = int(world.coordinator.profile_usec[key])
	for army: TerrainArmy in world.armies:
		for key: String in army.combat_profile_usec:
			counters["army_" + key] = int(counters.get("army_" + key, 0)) + int(army.combat_profile_usec[key])
	return counters

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args != PackedStringArray(["--profiled"]) and args != PackedStringArray(["--unprofiled"]):
		push_error("Use --profiled or --unprofiled")
		quit(1)
		return
	var profiled := args[0] == "--profiled"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AUDIT_DIR)) != OK:
		push_error("Cannot create workload audit directory")
		quit(1)
		return
	_output_path = "%s/%s_%d.json" % [AUDIT_DIR, "profiled" if profiled else "unprofiled", int(Time.get_unix_time_from_system())]
	var sources := _sources()
	sources["res://scripts/tests/site_movement_workload_audit_test.gd"] = FileAccess.get_sha256("res://scripts/tests/site_movement_workload_audit_test.gd")
	var world := _fixture(true)
	world.lab.combat_profile_enabled = profiled
	world.coordinator.profile_enabled = profiled
	for army: TerrainArmy in world.armies:
		army.combat_profile_enabled = profiled
	var initial := _hash(_state(world))
	var previous: Array = []
	for army: TerrainArmy in world.armies:
		previous.append(_observe(army))
	var rows: Array = []
	var previous_counters := _stage_counters(world)
	for step in range(1, STEPS + 1):
		if not _faults.is_empty() or Time.get_ticks_usec() >= _deadline_usec:
			_faults.append("Audit deadline or fixture failure at step " + str(step))
			break
		var elapsed := _advance(world)
		var row := {"step": step, "warmup": step <= WARMUP_STEPS, "action_usec": elapsed, "armies": [],
			"proposals": world.coordinator.movement_reservation_grid.proposals.size()}
		var counters := _stage_counters(world)
		var stage_deltas := {}
		for key: String in counters:
			stage_deltas[key] = int(counters[key]) - int(previous_counters.get(key, 0))
		row["stage_deltas_usec"] = stage_deltas
		previous_counters = counters
		for side in range(world.armies.size()):
			var now := _observe(world.armies[side])
			var before: Dictionary = previous[side]
			var changed: Array[String] = []
			for key: String in ["order", "serial", "cells", "claims", "targets", "identity", "macro", "assignments", "roles", "retry", "deadlines", "deployment", "terrain_revision"]:
				if before.get(key) != now.get(key):
					changed.append(key)
			row.armies.append({"team": side + 1, "has_move": now.has_move, "eligible": now.eligible,
				"moving": now.moving, "ready": now.ready, "unfinished_ready": now.unfinished_ready,
				"gated": now.gated, "changed_groups": changed, "planning_time": now.time, "phase": now.get("phase", -1)})
			previous[side] = now
		rows.append(row)
	var final_hash := _hash(_state(world))
	var sources_after := _sources()
	sources_after["res://scripts/tests/site_movement_workload_audit_test.gd"] = FileAccess.get_sha256("res://scripts/tests/site_movement_workload_audit_test.gd")
	if sources != sources_after:
		_faults.append("Source changed during audit")
	var result := {"scope": "Formal UI PLAINS 581 100x3 fixed action workload audit; observed groups are not a proof that planning may be skipped; not FPS",
		"profiled": profiled, "warmup_steps": WARMUP_STEPS, "step_seconds": STEP, "steps": rows,
		"coverage": _coverage(world),
		"initial_state_hash": initial, "final_state_hash": final_hash, "terrain_hash": world.terrain_hash,
		"sources_before": sources, "sources_after": sources_after, "faults": _faults, "passed": _faults.is_empty() and rows.size() == STEPS}
	var file := FileAccess.open(_output_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write workload audit")
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	world.root.free()
	TerrainArmy.release_contact_source()
	print("MOVEMENT_WORKLOAD_AUDIT ", "PASS" if result.passed else "FAIL", " ", _output_path)
	quit(0 if result.passed else 1)
