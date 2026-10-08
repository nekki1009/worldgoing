extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
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

func _plan_for(slots: Dictionary) -> CombatDeploymentPlan:
	var plan := CombatDeploymentPlan.new()
	plan.ingress_cell = Vector2i(0, 1)
	for mid in slots:
		var slot: Vector2i = slots[mid]
		plan.platform_slots.append(slot)
		plan.platform_footprint.append(slot)
		plan.member_slot_map[mid] = slot
		plan.slot_owner_map[slot] = mid
		plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
		plan.slot_tactical_roles[slot] = Types.TacticalSlotRole.FLEX
		plan.admitted_platform_member_ids.append(mid)
	return plan

func _move_for(plan: CombatDeploymentPlan) -> CombatMovePlan:
	var move := CombatMovePlan.new()
	move.destination_plan = plan
	move.phase = Types.CombatMovePhase.PLATFORM_INGRESS
	move.previous_platform_settled = 2
	move.platform_settled_highwater = 2
	move.previous_median_path_s = 0.0
	move.previous_macro_cursor = 0
	move.previous_checkpoint_count = 0
	move.resolved_anchor = Vector2i(6, 1)
	for x in range(1, 7):
		move.macro_path.append(Vector2i(x, 1))
	return move

func _run() -> void:
	var terrain := Helper.build_flat_map(8, 3)
	var slot_a := Vector2i(2, 1)
	var slot_b := Vector2i(5, 1)
	var cells: Dictionary = {1: Vector2i(1, 1), 2: Vector2i(4, 1)}
	var plan := _plan_for({1: slot_a, 2: slot_b})
	var move := _move_for(plan)
	var actor_a: Array[int] = [1]
	var actor_b: Array[int] = [2]
	move.active_stall_total_sec = 8.0
	Destination._begin_vacancy_chain(move, actor_a, cells)
	if not _require(not Recovery.check_meaningful_progress(move, 0.0, 0, 0, 0), "Assigning a chain without a physical step must not reset stall"): return
	if not _require(terrain.can_step(cells[1], slot_a), "The first arrival must use a legal physical edge"): return
	cells[1] = slot_a
	Destination.update_movement_phase(move, plan, cells, null, 0.05)
	if not _require(move.verified_chain_arrival_pending and move.verified_chain_arrival_members.has(1), "Only the physical first arrival earns a chain credit"): return
	if not _require(is_equal_approx(move.last_platform_progress_time_sec, move.planning_time_sec), "A first physical chain arrival must refresh the platform recovery clock"): return
	if not _require(Recovery.check_meaningful_progress(move, 0.0, plan.settled_platform_member_ids.size(), 0, 0) and move.active_stall_total_sec == 0.0, "A new actor at its chain target must reset stall within the unchanged 12-second rule"): return
	move.active_stall_total_sec = 8.0
	if not _require(not Recovery.check_meaningful_progress(move, 0.0, plan.settled_platform_member_ids.size(), 0, 0), "The same arrival must not be credited every tick"): return

	# Simulate a later target rotation and legal return step by the same actor.
	# The source/target change is real, but a repeated actor is finite credit.
	plan.member_slot_map[1] = Vector2i(1, 1)
	plan.slot_owner_map.erase(slot_a)
	plan.slot_owner_map[Vector2i(1, 1)] = 1
	plan.platform_slots.erase(slot_a)
	plan.platform_slots.append(Vector2i(1, 1))
	plan.platform_footprint.erase(slot_a)
	plan.platform_footprint.append(Vector2i(1, 1))
	move.phase = Types.CombatMovePhase.PLATFORM_INGRESS
	var platform_progress_before := move.last_platform_progress_time_sec
	Destination._begin_vacancy_chain(move, actor_a, cells)
	if not _require(terrain.can_step(cells[1], Vector2i(1, 1)), "The repeated actor also uses a legal physical edge"): return
	cells[1] = Vector2i(1, 1)
	Destination.update_movement_phase(move, plan, cells, null, 0.05)
	if not _require(not move.verified_chain_arrival_pending and not Recovery.check_meaningful_progress(move, 0.0, plan.settled_platform_member_ids.size(), 0, 0), "Target cycling by the same actor cannot hide a real stall"): return
	if not _require(move.last_platform_progress_time_sec == platform_progress_before, "Repeated chain arrival by the same actor must not refresh the platform recovery clock"): return
	move.active_stall_total_sec = Recovery.CONGESTION_ABORT_SEC
	if not _require(Recovery.process_recovery(move, Vector2i(1, 1), terrain, null, 0.0) == Types.RuntimeMoveFailureCode.CONGESTED, "After finite actor credit is spent, a genuine 12-second stall must still stop"): return

	# A different actor's first legal completion is an independent event.
	move.phase = Types.CombatMovePhase.PLATFORM_INGRESS
	move.active_stall_total_sec = 8.0
	Destination._begin_vacancy_chain(move, actor_b, cells)
	if not _require(terrain.can_step(cells[2], slot_b), "The second actor must use a legal physical edge"): return
	cells[2] = slot_b
	Destination.update_movement_phase(move, plan, cells, null, 0.05)
	if not _require(Recovery.check_meaningful_progress(move, 0.0, plan.settled_platform_member_ids.size(), 0, 0) and move.active_stall_total_sec == 0.0, "A distinct actor may earn one physical chain credit"): return
	var sidestep_plan := _plan_for({4: Vector2i(6, 1)})
	var sidestep_move := _move_for(sidestep_plan)
	var sidestep_cells: Dictionary = {4: Vector2i(5, 1)}
	var sidestep_actors: Array[int] = [4]
	Destination._begin_vacancy_chain(sidestep_move, sidestep_actors, sidestep_cells)
	var chain_progress_before: float = sidestep_move.vacancy_chain_last_progress_sec
	if not _require(terrain.can_step(sidestep_cells[4], Vector2i(5, 0)), "The sidestep must be a legal physical edge"): return
	sidestep_cells[4] = Vector2i(5, 0)
	Destination.update_movement_phase(sidestep_move, sidestep_plan, sidestep_cells, null, 0.05)
	if not _require(not sidestep_move.verified_chain_arrival_pending and sidestep_move.vacancy_chain_arrived_count == 0 and sidestep_move.vacancy_chain_last_progress_sec == chain_progress_before,
		"A physical sidestep short of the assigned chain target must not earn arrival or advance chain progress"): return
	if not _require(sidestep_move.last_platform_progress_time_sec == 0.0, "A sidestep short of the chain target must not refresh platform recovery"): return

	var fake_plan := _plan_for({3: Vector2i(6, 1)})
	var fake_move := _move_for(fake_plan)
	var fake_cells: Dictionary = {3: Vector2i(6, 1)}
	var fake_actor: Array[int] = [3]
	Destination._begin_vacancy_chain(fake_move, fake_actor, fake_cells)
	Destination.update_movement_phase(fake_move, fake_plan, fake_cells, null, 0.05)
	if not _require(not fake_move.verified_chain_arrival_pending and not Recovery.check_meaningful_progress(fake_move, 0.0, fake_plan.settled_platform_member_ids.size(), 0, 0), "Changing only target ownership to the standing cell must never earn physical credit"): return
	if not _require(fake_move.last_platform_progress_time_sec == 0.0, "Target ownership alone must not refresh platform recovery"): return

	# A vacancy chain with a turn may require several sequential 0.38-second
	# commits. Unmoved participants are not arrivals, while each real commit
	# extends the same chain instead of letting its two-second clock expire.
	var serial_plan := _plan_for({5: Vector2i(2, 1), 6: Vector2i(3, 1), 7: Vector2i(4, 1)})
	var serial_move := _move_for(serial_plan)
	var serial_cells: Dictionary = {5: Vector2i(1, 1), 6: Vector2i(2, 1), 7: Vector2i(3, 1)}
	Destination._begin_vacancy_chain(serial_move, [5, 6, 7], serial_cells)
	Destination.update_movement_phase(serial_move, serial_plan, serial_cells, null, 1.5)
	if not _require(serial_move.active_vacancy_chain_actors.size() == 3 and serial_move.vacancy_chain_arrived_count == 0,
		"Unmoved chain participants must not be counted as physical arrivals"): return
	serial_cells[7] = Vector2i(4, 1)
	Destination.update_movement_phase(serial_move, serial_plan, serial_cells, null, 0.1)
	if not _require(serial_move.vacancy_chain_arrived_count == 1 and is_equal_approx(serial_move.vacancy_chain_last_progress_sec, serial_move.planning_time_sec),
		"The vacant-tail actor must extend the chain only after its physical step"): return
	Destination.update_movement_phase(serial_move, serial_plan, serial_cells, null, 1.5)
	if not _require(serial_move.active_vacancy_chain_actors.size() == 3,
		"A live sequential chain must not expire while its actors continue to arrive"): return
	serial_cells[6] = Vector2i(3, 1)
	Destination.update_movement_phase(serial_move, serial_plan, serial_cells, null, 0.1)
	if not _require(serial_move.vacancy_chain_arrived_count == 2 and serial_move.active_vacancy_chain_actors.size() == 3,
		"The second legal arrival must refresh sequential chain progress"): return
	print("COMBAT MOVEMENT VERIFIED CHAIN PROGRESS PASS")
	quit(0)
