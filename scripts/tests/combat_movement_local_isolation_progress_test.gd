extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

func _initialize() -> void:
	call_deferred("_run")

func _require(ok: bool, message: String) -> bool:
	if ok:
		return true
	push_error(message)
	quit(1)
	return false

func _fixture(retry_count: int) -> Dictionary:
	var terrain := Helper.build_flat_map(12, 8)
	var plan := CombatDeploymentPlan.new()
	var move := CombatMovePlan.new()
	move.destination_plan = plan
	move.planning_time_sec = 2.0
	move.last_platform_progress_time_sec = 2.0
	var waiting := 99
	var vacancy := Vector2i(5, 2)
	var cells: Dictionary = {waiting: Vector2i(2, 4)}
	plan.ingress_cell = Vector2i(1, 4)
	plan.final_facing = Vector2i.RIGHT
	for x in range(2, 9):
		for y in range(1, 7):
			plan.platform_footprint.append(Vector2i(x, y))
	var next_id := 1
	for x in range(3, 8):
		for y in range(1, 6):
			var slot := Vector2i(x, y)
			var mid: int = waiting if slot == vacancy else next_id
			if mid == next_id:
				next_id += 1
			plan.platform_slots.append(slot)
			plan.member_slot_map[mid] = slot
			plan.slot_owner_map[slot] = mid
			plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
			plan.slot_tactical_roles[slot] = Types.TacticalSlotRole.FLEX
			plan.admitted_platform_member_ids.append(mid)
			if mid != waiting:
				cells[mid] = slot
				plan.settled_platform_member_ids.append(mid)
				plan.member_slot_locked[mid] = true
	move.member_route_retry_count[waiting] = retry_count
	return {"terrain": terrain, "plan": plan, "move": move, "cells": cells, "waiting": waiting, "vacancy": vacancy}

func _run() -> void:
	var low := _fixture(11)
	if not _require(not Destination.recover_stalled_platform_slots(low.move, low.plan, low.cells, low.terrain) and low.plan.assignment_epoch == 0,
		"Recent global progress must still prevent low-retry ownership recovery"): return
	var claimed := _fixture(12)
	if not _require(not Destination.recover_stalled_platform_slots(claimed.move, claimed.plan, claimed.cells, claimed.terrain, {claimed.vacancy: true}) and claimed.plan.assignment_epoch == 0,
		"An in-flight Grid claim must block the local isolation shortcut"): return
	var arriving := _fixture(12)
	arriving.plan.settled_platform_member_ids.resize(20)
	if not _require(not Destination.recover_stalled_platform_slots(arriving.move, arriving.plan, arriving.cells, arriving.terrain) and arriving.plan.assignment_epoch == 0,
		"Recent global progress during 20/25 ordinary arrivals must keep isolated-slot recovery behind the normal stall gate"): return
	var isolated := _fixture(12)
	var original_cells: Dictionary = isolated.cells.duplicate()
	if not _require(Destination.recover_stalled_platform_slots(isolated.move, isolated.plan, isolated.cells, isolated.terrain),
		"A high-retry FLEX owner with an unreachable vacant final must recover despite unrelated recent platform progress"): return
	if not _require(isolated.cells == original_cells and isolated.plan.assignment_epoch == 1 and not isolated.move.active_vacancy_chain_actors.is_empty() and isolated.plan.get_slot_for_member(isolated.waiting) != isolated.vacancy,
		"Local isolation recovery may rotate only final ownership; physical occupancy stays with Grid"): return
	print("COMBAT MOVEMENT LOCAL ISOLATION PROGRESS PASS")
	quit(0)
