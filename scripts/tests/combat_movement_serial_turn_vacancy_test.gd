extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

func _initialize() -> void:
	call_deferred("_run")

func _require(ok: bool, message: String) -> bool:
	if ok:
		return true
	push_error(message)
	quit(1)
	return false

func _changed_target_ids(before: Dictionary, after: Dictionary) -> Array[int]:
	var changed: Array[int] = []
	for mid in before.keys():
		if before[mid] != after.get(mid):
			changed.append(int(mid))
	changed.sort()
	return changed

func _run() -> void:
	var terrain := Helper.build_flat_map(32, 18)
	var vacancy := Vector2i(6, 5)
	var edge := Vector2i(4, 4)
	var waiting_cell := Vector2i(3, 4)
	var chain_cells: Array[Vector2i] = [edge, Vector2i(5, 4), Vector2i(5, 5)]
	# Every non-chain owner is far away and separated by an empty cell. Terrain,
	# rather than tactical labels, leaves exactly one legal way into the vacancy.
	var remote_slots: Array[Vector2i] = []
	for y in [1, 3, 5, 7]:
		for x in [12, 14, 16, 18, 20]:
			remote_slots.append(Vector2i(x, y))
	var passage: Array[Vector2i] = [waiting_cell, vacancy]
	passage.append_array(chain_cells)
	for y in range(3, 7):
		for x in range(3, 8):
			var cell := Vector2i(x, y)
			if passage.has(cell):
				continue
			terrain.flags[terrain.index(cell)] = 0
			terrain.static_blocked[terrain.index(cell)] = 1
	terrain.navigation_revision += 1
	var physical_route: Array[Vector2i] = [waiting_cell, chain_cells[0], chain_cells[1], chain_cells[2], vacancy]
	for i in range(physical_route.size() - 1):
		if not _require(terrain.can_step(physical_route[i], physical_route[i + 1]), "Every corner of the vacancy corridor must be a legal terrain edge"): return
	for neighbor in [Vector2i(6, 4), Vector2i(7, 5), Vector2i(6, 6)]:
		if not _require(not terrain.can_step(neighbor, vacancy), "The vacancy must have no free side entrance around the three physical occupants"): return
	var final_slots: Array[Vector2i] = remote_slots.duplicate()
	final_slots.append_array(chain_cells)
	final_slots.append(vacancy)
	var placements: Array[Vector2i] = remote_slots.duplicate()
	placements.append_array(chain_cells)
	placements.append(waiting_cell)
	var army := TerrainArmy.new()
	army.team_id = 1
	army.faction_id = 0
	army.roster_size = placements.size()
	army.exchange_enabled = true
	army.set_process(false)
	if not _require(army.deploy_at(terrain, null, null, placements) and army.enable_combat(false), "The physical fixture must deploy all original members"): return
	var coordinator := Coordinator.new()
	coordinator.register_formation(army)
	var order: Dictionary = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(24, 10), -1, Vector2i.RIGHT)
	if not _require(bool(order.get("ok", false)), "The physical vacancy test needs a live MOVE order"): return

	var plan := CombatDeploymentPlan.new()
	var move := CombatMovePlan.new()
	move.destination_plan = plan
	move.phase = Types.CombatMovePhase.PLATFORM_INGRESS
	move.planning_time_sec = 10.0
	move.platform_settled_highwater = placements.size() - 1
	plan.ingress_cell = Vector2i(0, 4)
	plan.queue_released = true
	var waiting := army.combat_identity(placements.size() - 1)
	var commander := army.combat_identity(0)
	# The formal highland stragglers previously entered the platform, then took
	# an exterior detour; their exposed edge remains a platform-return target.
	plan.ever_admitted_platform_member_ids[waiting] = true
	var member_at: Dictionary = {}
	for index in range(placements.size()):
		member_at[placements[index]] = army.combat_identity(index)
	for slot in final_slots:
		var mid: int = waiting if slot == vacancy else int(member_at[slot])
		plan.platform_slots.append(slot)
		plan.platform_footprint.append(slot)
		plan.member_slot_map[mid] = slot
		plan.slot_owner_map[slot] = mid
		plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
		plan.slot_tactical_roles[slot] = Types.TacticalSlotRole.COMMANDER if mid == commander else Types.TacticalSlotRole.FLEX
		plan.admitted_platform_member_ids.append(mid)
		if mid != waiting:
			plan.settled_platform_member_ids.append(mid)
			plan.member_slot_locked[mid] = true
	army._combat_move_plan = move
	army._combat_deployment_plan = plan
	var occupied: Dictionary = {}
	for cell in placements:
		occupied[cell] = true
	var allowed: Dictionary = {}
	for slot in plan.platform_footprint:
		allowed[slot] = true
	var initial_targets: Dictionary = plan.member_slot_map.duplicate()
	if not _require(Destination._recover_isolated_final_vacancy(move, plan, army.get_active_members_occupancy(), terrain, occupied, allowed), "The enclosed final must start a three-person turning vacancy chain"): return
	var ordered_actors: Array[int] = [int(member_at[chain_cells[2]]), int(member_at[chain_cells[1]]), int(member_at[chain_cells[0]])]
	var ordered_targets: Array[Vector2i] = [vacancy, chain_cells[2], chain_cells[1]]
	var first_changed: Array[int] = [waiting, ordered_actors[0]]
	first_changed.sort()
	if not _require(_changed_target_ids(initial_targets, plan.member_slot_map) == first_changed, "The first exchange may change only the waiting owner and one settled actor's targets"): return
	if not _require(move.active_vacancy_chain_actors == [ordered_actors[0]] and move.queued_vacancy_steps.size() == 2 and move.vacancy_waiting_id == waiting and move.member_recovery_hold.has(waiting), "Only the actor beside the empty cell may receive the first target"): return
	if not _require(plan.get_slot_for_member(waiting) == chain_cells[2] and army.cells == placements and plan.settled_platform_member_ids.size() == placements.size() - 2, "A target exchange must keep every physical cell and dislodge at most one settled actor"): return
	if not _require(plan.get_slot_for_member(commander) == placements[0], "The commander keeps his own identity and target during ordinary vacancy recovery"): return

	for step_index in range(3):
		var actor: int = ordered_actors[step_index]
		var target: Vector2i = ordered_targets[step_index]
		if not _require(move.active_vacancy_chain_actors == [actor] and plan.get_slot_for_member(actor) == target and plan.get_slot_for_member(waiting) == chain_cells[2 - step_index], "The next target must wait for the preceding physical arrival"): return
		if not _require(plan.settled_platform_member_ids.size() >= placements.size() - 2 and move.member_recovery_hold.has(waiting), "The waiting member must stay parked while only one settled actor is displaced"): return
		var parked: Dictionary = Destination.resolve_member_target(move, plan, waiting, waiting_cell)
		if not _require(parked.get("kind", "") == "recovery_hold" and parked.get("target", Vector2i(-1, -1)) == waiting_cell, "The waiting member must retain a physical hold until the edge is vacant"): return
		var source_cells: Array[Vector2i] = army.cells.duplicate()
		coordinator._rebuild_occupancy()
		var grid = coordinator.movement_reservation_grid
		grid.begin_tick(coordinator._current_occupancy, terrain)
		var index := army.index_for_identity(actor)
		var proposal: int = grid.propose_move(army.formation_runtime_id, actor, army.get_order_serial(), army.cells[index], target)
		grid.resolve_all()
		if not _require(proposal >= 0 and grid.proposal_lookup[proposal].status == Types.MoveProposalStatus.ACCEPTED, "Each isolated vacancy step must be accepted by the original Grid contract"): return
		grid.commit_all(coordinator._member_lookup, step_index + 1)
		coordinator._register_started_batches()
		if not _require(army.cells == source_cells and army.moving_to[index] == target and coordinator._inflight_batches.size() == 1, "A committed step must interpolate without changing its source occupancy"): return
		army.prepare_combat(0.19)
		coordinator.complete_committed_moves()
		if not _require(army.cells == source_cells and army.move_progress[index] > 0.0 and army.move_progress[index] < 1.0 and plan.get_slot_for_member(waiting) == chain_cells[2 - step_index], "Neither the actor nor waiting member may teleport halfway through 0.38 seconds"): return
		army.prepare_combat(0.20)
		coordinator.complete_committed_moves()
		if not _require(army.cells[index] == target and army.cells[army.index_for_identity(waiting)] == waiting_cell and army.moving_to[index] == TerrainArmy.INVALID_CELL and coordinator._inflight_batches.is_empty(), "Each actor must finish one legal physical step while the waiting member stays put"): return
		var targets_before_completion: Dictionary = plan.member_slot_map.duplicate()
		Destination.update_movement_phase(move, plan, army.get_active_members_occupancy(), terrain, 0.39)
		if step_index < 2:
			var next_changed: Array[int] = [waiting, ordered_actors[step_index + 1]]
			next_changed.sort()
			if not _require(_changed_target_ids(targets_before_completion, plan.member_slot_map) == next_changed, "A completed step may change only the waiting owner and the next adjacent actor's targets"): return
			if not _require(move.active_vacancy_chain_actors == [ordered_actors[step_index + 1]] and move.queued_vacancy_steps.size() == 1 - step_index and move.member_recovery_hold.has(waiting), "The next turn must dispatch immediately after the real arrival, without another stall wait"): return
		else:
			if not _require(_changed_target_ids(targets_before_completion, plan.member_slot_map).is_empty(), "The final physical arrival must not reshuffle finished targets"): return
			if not _require(move.active_vacancy_chain_actors.is_empty() and move.queued_vacancy_steps.is_empty() and not move.member_recovery_hold.has(waiting) and plan.get_slot_for_member(waiting) == edge, "The exposed edge slot must be released to the waiting member after the third step"): return

	var waiting_target: Dictionary = Destination.resolve_member_target(move, plan, waiting, waiting_cell)
	if not _require(waiting_target.get("target", Vector2i(-1, -1)) == edge and waiting_target.get("kind", "") == "platform_return", "The waiting former entrant must resume a legal target toward the exposed edge"): return
	coordinator._rebuild_occupancy()
	var waiting_grid = coordinator.movement_reservation_grid
	waiting_grid.begin_tick(coordinator._current_occupancy, terrain)
	var waiting_proposal: int = waiting_grid.propose_move(army.formation_runtime_id, waiting, army.get_order_serial(), waiting_cell, edge)
	waiting_grid.resolve_all()
	if not _require(waiting_proposal >= 0 and waiting_grid.proposal_lookup[waiting_proposal].status == Types.MoveProposalStatus.ACCEPTED, "The exposed edge must accept the original waiting member"): return
	waiting_grid.commit_all(coordinator._member_lookup, 4)
	coordinator._register_started_batches()
	army.prepare_combat(0.39)
	coordinator.complete_committed_moves()
	Destination.update_movement_phase(move, plan, army.get_active_members_occupancy(), terrain, 0.39)
	if not _require(army.cells[army.index_for_identity(waiting)] == edge and Destination.is_settled(plan, army.get_active_members_occupancy()) and plan.settled_platform_member_ids.size() == placements.size(), "All members must occupy their exact final targets after the waiting member takes the edge"): return
	print("COMBAT MOVEMENT SERIAL TURN VACANCY PASS")
	coordinator.unregister_formation(army)
	army.free()
	quit(0)
