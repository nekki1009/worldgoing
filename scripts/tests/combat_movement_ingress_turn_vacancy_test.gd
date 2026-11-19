extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const Grid = preload("res://scripts/terrain_lab/site_movement_reservation_grid.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

func _initialize() -> void:
	call_deferred("_run")

func _require(ok: bool, message: String) -> bool:
	if ok:
		return true
	push_error(message)
	quit(1)
	return false

func _run() -> void:
	var terrain := Helper.build_flat_map(12, 12)
	var cells: Array[Vector2i] = [Vector2i(4, 4), Vector2i(5, 4), Vector2i(5, 5), Vector2i(6, 5)]
	var current: Dictionary = {1: cells[0], 2: cells[1], 3: cells[2], 4: Vector2i(3, 5)}
	var plan := CombatDeploymentPlan.new()
	var move := CombatMovePlan.new()
	move.destination_plan = plan
	move.planning_time_sec = 10.0
	move.last_platform_progress_time_sec = 0.0
	move.macro_path = [cells[0]]
	plan.ingress_cell = Vector2i(3, 4)
	plan.queue_released = true
	for i in range(cells.size()):
		var mid := i + 1
		plan.platform_slots.append(cells[i])
		plan.platform_footprint.append(cells[i])
		plan.member_slot_map[mid] = cells[i]
		plan.slot_owner_map[cells[i]] = mid
		plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
		plan.admitted_platform_member_ids.append(mid)
		if mid != 4:
			plan.settled_platform_member_ids.append(mid)
			plan.member_slot_locked[mid] = true
	if not _require(Destination.recover_stalled_platform_slots(move, plan, current, terrain), "Ingress blockage must start one legal vacancy step"): return
	if not _require(move.active_vacancy_chain_actors == [3] and move.queued_vacancy_steps.size() == 2 and move.vacancy_waiting_id == 4 and move.member_recovery_hold.has(4), "A turning ingress chain must queue its earlier actors and hold the vacancy owner"): return
	if not _require(plan.get_slot_for_member(4) == cells[2] and plan.get_slot_for_member(1) == cells[0] and plan.get_slot_for_member(2) == cells[1], "Only the tail actor and vacancy owner may exchange targets before the first physical step"): return
	var actors: Array[int] = [3, 2, 1]
	var targets: Array[Vector2i] = [cells[3], cells[2], cells[1]]
	for i in range(actors.size()):
		var actor: int = actors[i]
		var target: Vector2i = targets[i]
		var occupancy: Dictionary = {}
		for mid in current.keys():
			occupancy[current[mid]] = mid
		var grid := Grid.new()
		grid.begin_tick(occupancy, terrain)
		var proposal: int = grid.propose_move(1, actor, 1, current[actor], target)
		grid.resolve_all()
		if not _require(proposal >= 0 and grid.proposal_lookup[proposal].status == Types.MoveProposalStatus.ACCEPTED, "Every turning vacancy step must have an open physical tail in Grid"): return
		current[actor] = target
		Destination.update_movement_phase(move, plan, current, terrain, 0.39)
		if i < 2 and not _require(move.active_vacancy_chain_actors == [actors[i + 1]] and move.member_recovery_hold.has(4) and plan.get_slot_for_member(4) == cells[2 - i - 1], "Next target may change only after the preceding physical arrival"): return
	if not _require(move.active_vacancy_chain_actors.is_empty() and move.queued_vacancy_steps.is_empty() and not move.member_recovery_hold.has(4) and plan.get_slot_for_member(4) == cells[0], "The exposed ingress slot must return to the waiting owner after the chain finishes"): return
	var crossed_plan := CombatDeploymentPlan.new()
	var crossed_move := CombatMovePlan.new()
	crossed_move.planning_time_sec = 10.0
	crossed_move.macro_path = [cells[0]]
	crossed_plan.ingress_cell = Vector2i(3, 4)
	for i in range(cells.size()):
		var mid := i + 1
		crossed_plan.platform_slots.append(cells[i])
		crossed_plan.platform_footprint.append(cells[i])
		crossed_plan.member_slot_map[mid] = cells[i]
		crossed_plan.slot_owner_map[cells[i]] = mid
		crossed_plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
		crossed_plan.admitted_platform_member_ids.append(mid)
	crossed_plan.member_slot_map[1] = cells[1]
	crossed_plan.member_slot_map[2] = cells[0]
	crossed_plan.slot_owner_map[cells[0]] = 2
	crossed_plan.slot_owner_map[cells[1]] = 1
	crossed_plan.settled_platform_member_ids.append(3)
	var crossed_current: Dictionary = {1: cells[0], 2: cells[1], 3: cells[2], 4: Vector2i(3, 5)}
	if not _require(not Destination.recover_stalled_platform_slots(crossed_move, crossed_plan, crossed_current, terrain) and crossed_plan.member_slot_map[1] == cells[1] and crossed_plan.member_slot_map[2] == cells[0], "An occupied final is not a vacancy-chain node unless its occupant owns that final"): return
	print("COMBAT MOVEMENT INGRESS TURN VACANCY PASS")
	quit(0)
