extends SceneTree
## Observe the real MOVE/Grid/Army completion path at two action-step cadences.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const ORIGIN := Vector2i(5, 5)
const GOAL := Vector2i(12, 5)
const DURATION := 0.38
const EPSILON := 0.000001
const MAX_SECONDS := 20.0
const FRACTIONS := [0.25, 0.5, 0.75]

var _army: TerrainArmy
var _coordinator: SiteCombatMovementCoordinator
var _wall_start := 0

func _initialize() -> void:
	_wall_start = Time.get_ticks_msec()
	call_deferred("_run")

func _dispose() -> void:
	if is_instance_valid(_army):
		_coordinator.unregister_formation(_army)
		_army.free()
	_army = null

func _finish(exit_code: int) -> void:
	_dispose()
	# All case/query users have stopped before releasing the root-owned sources.
	TerrainArmy.release_contact_source()
	await process_frame
	quit(exit_code)

func _require(condition: bool, message: String) -> bool:
	if not condition:
		push_error("PHYSICAL CADENCE FAIL: " + message)
		_finish.call_deferred(1)
	return condition

func _run() -> void:
	var slow := _run_case(1.0 / 30.0)
	if slow.is_empty(): return
	var fast := _run_case(1.0 / 120.0)
	if fast.is_empty(): return
	if not _require(slow.cells == fast.cells and slow.steps == fast.steps, "Both cadences must execute the same legal steps and final assignment"): return
	# Fixed action steps may quantize the endpoint by less than one delta per
	# physical step. They must never halve duration or accumulate unbounded drift.
	var count: int = slow.steps
	if not _require(absf(float(slow.physical_seconds) - float(fast.physical_seconds)) <= count / 30.0 + EPSILON, "30/120 Hz cumulative physical times differ beyond their endpoint quantization allowance"): return
	if not _require(absf(float(slow.span_seconds) - float(fast.span_seconds)) <= count * (1.0 / 30.0 + 1.0 / 120.0) + EPSILON, "30/120 Hz multi-step elapsed spans diverged beyond bounded step/scheduling quantization"): return
	print("COMBAT MOVEMENT PHYSICAL CADENCE PASS: duration=0.38 samples=25/50/75% slow=", slow, " fast=", fast)
	_finish.call_deferred(0)

func _run_case(delta: float) -> Dictionary:
	var data := Helper.build_flat_map(24, 12)
	_army = Helper.create_test_army(data, 1, 0, 1, ORIGIN)
	_coordinator = Coordinator.new()
	_coordinator.register_formation(_army)
	var identity := _army.combat_identity(0)
	var order: Dictionary = _army.issue_combat_order(_army.current_commander, TerrainArmy.CombatOrder.MOVE, GOAL, -1, Vector2i.RIGHT)
	if not _require(bool(order.get("ok", false)), "Formal MOVE rejected at delta=%s: %s" % [delta, order]): return {}
	var plan: CombatDeploymentPlan = _army.get_active_deployment_plan()
	if not _require(plan != null and plan.member_slot_map.size() == 1, "MOVE must create the original one-member deployment"): return {}
	var final_cell: Vector2i = plan.get_slot_for_member(identity)
	var expected_steps := final_cell.x - ORIGIN.x
	if not _require(final_cell.y == ORIGIN.y and expected_steps >= 5, "The straight unblocked fixture must require at least five real steps"): return {}
	var elapsed := 0.0
	var active: Dictionary = {}
	var completed: Array[Dictionary] = []
	var visited: Array[Vector2i] = [ORIGIN]
	var physical_seconds := 0.0
	var first_start := -1.0
	var last_completion := -1.0
	var quantum := ceili((DURATION - EPSILON) / delta) * delta
	for tick in range(ceili(MAX_SECONDS / delta)):
		if not _require(Time.get_ticks_msec() - _wall_start < 30000, "30-second wall deadline reached; delta=%s tick=%d completed=%d active=%s" % [delta, tick, completed.size(), active]): return {}
		var before_cell: Vector2i = _army.cells[0]
		var before_progress: float = _army.move_progress[0]
		_coordinator.combat_logic_tick(delta)
		if not _require(_army.cells[0] == before_cell, "Planning/Grid start jumped a physical cell before Army advancement"): return {}
		if not active.is_empty():
			if not _require(absf(_army.move_progress[0] - before_progress) <= EPSILON, "Planning tick advanced the original physical clock a second time"): return {}
		elif _army.moving_to[0] != TerrainArmy.INVALID_CELL:
			var target: Vector2i = _army.moving_to[0]
			if not _require(target == before_cell + Vector2i.RIGHT and data.can_step(before_cell, target), "Unblocked cadence fixture took an unexpected or illegal step"): return {}
			if not _require(absf(_army.move_duration[0] - DURATION) <= EPSILON and absf(_army.move_progress[0]) <= EPSILON, "Original Grid commit must start a fresh 0.38-second step at progress zero"): return {}
			if not _require(_coordinator.get_inflight_batches_for_formation(_army).size() == 1, "The original Grid step must have a coordinator completion batch"): return {}
			active = {"source": before_cell, "target": target, "start": elapsed, "samples": []}
			if first_start < 0.0: first_start = elapsed
			if last_completion >= 0.0 and not _require(elapsed - last_completion <= delta + EPSILON, "Unblocked consecutive steps inserted more than one scheduling tick of idle time"): return {}
		_army.prepare_combat(delta)
		elapsed += delta
		if not active.is_empty():
			var age: float = elapsed - float(active.start)
			var expected_progress := minf(1.0, age / DURATION)
			var progress: float = _army.move_progress[0]
			if not _require(absf(progress - expected_progress) <= EPSILON, "Physical progress disagrees with elapsed/0.38 at delta=%s age=%s progress=%s expected=%s" % [delta, age, progress, expected_progress]): return {}
			if not _require(_army.cells[0] == active.source and _army._cell_owners.get(active.source, -1) == 0 and not _army._cell_owners.has(active.target), "Source ownership changed before the physical completion barrier"): return {}
			if not _require(_army.moving_to[0] == active.target and _army._reserved_cells.get(active.target, -1) == 0, "In-flight destination or reservation was lost"): return {}
			var source_center := (Vector2(active.source) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
			var target_center := (Vector2(active.target) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
			# This is the authored ease-out contract, evaluated independently of
			# CombatTimings.movement_weight so a changed curve cannot validate itself.
			var expected_ground := source_center.lerp(target_center, expected_progress * (2.0 - expected_progress))
			if not _require(_army.combat_ground(0).distance_to(expected_ground) < 0.001, "Original combat_ground does not follow elapsed physical interpolation"): return {}
			for fraction: float in FRACTIONS:
				if active.samples.size() >= FRACTIONS.size(): break
				if fraction != FRACTIONS[active.samples.size()] or progress + EPSILON < fraction: continue
				if not _require(age >= fraction * DURATION - EPSILON and age < fraction * DURATION + delta + EPSILON and progress < 1.0, "Quarter-step sample was skipped or only observed at completion"): return {}
				active.samples.append({"fraction": fraction, "age": age, "progress": progress, "ground_x": _army.combat_ground(0).x})
		_coordinator.complete_committed_moves()
		if not active.is_empty():
			var age: float = elapsed - float(active.start)
			if _army.cells[0] != active.source:
				if not _require(_army.cells[0] == active.target and age >= DURATION - EPSILON and absf(age - quantum) <= EPSILON, "Completion time must be the first action tick at/after 0.38 seconds; delta=%s age=%s expected=%s" % [delta, age, quantum]): return {}
				if not _require(active.samples.size() == 3 and _army.moving_to[0] == TerrainArmy.INVALID_CELL and _army._reserved_cells.is_empty() and _coordinator.get_inflight_batches_for_formation(_army).is_empty(), "Completion lost an interpolation sample or left physical claims/batches"): return {}
				if not _require(_army._cell_owners.get(active.target, -1) == 0 and not _army._cell_owners.has(active.source), "Completion did not atomically transfer original occupancy"): return {}
				active["duration"] = age
				completed.append(active)
				visited.append(_army.cells[0])
				physical_seconds += age
				last_completion = elapsed
				print("PHYSICAL_CADENCE_STEP delta=", delta, " step=", completed.size(), " observed=", active)
				active = {}
			elif not _require(age < DURATION + EPSILON, "Ready single-member step failed to commit at its first legal barrier"): return {}
		_army.settle_combat_command()
		if _army.combat_order != TerrainArmy.CombatOrder.MOVE: break
	if not _require(_army.combat_order == TerrainArmy.CombatOrder.HOLD and _army.command_status.begins_with("已抵達") and _army.cells[0] == final_cell and _army.facing[0] == Vector2i.RIGHT and active.is_empty(), "Full MOVE did not reach its exact final HOLD within 20 simulated seconds; delta=%s status=%s" % [delta, _army.command_status]): return {}
	if not _require(completed.size() == expected_steps and absf(physical_seconds - expected_steps * quantum) <= EPSILON, "Cumulative physical time drifted across consecutive steps"): return {}
	var span := last_completion - first_start
	if not _require(span >= expected_steps * DURATION - EPSILON and span <= expected_steps * quantum + (expected_steps - 1) * delta + EPSILON, "Multi-step elapsed span exceeded physical-duration and one-tick-per-gap bounds"): return {}
	var result := {"delta": delta, "steps": completed.size(), "physical_seconds": physical_seconds,
		"span_seconds": span, "order_to_hold_seconds": elapsed, "cells": visited}
	_dispose()
	return result
