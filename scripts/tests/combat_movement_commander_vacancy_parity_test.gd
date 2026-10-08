extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

const COMMANDER := 1000
const WAITING := 999
const VACANCY := Vector2i(5, 2)

func _initialize() -> void:
	call_deferred("_run")

func _require(ok: bool, message: String) -> bool:
	if ok:
		return true
	push_error("COMMANDER VACANCY PARITY FAIL: " + message)
	quit(1)
	return false

func _assert_ownership(plan: CombatDeploymentPlan, commander: int) -> bool:
	if not _require(plan.member_slot_map.size() == plan.slot_owner_map.size(), "Every member must own exactly one target"): return false
	var seen: Dictionary = {}
	var commander_markers := 0
	for mid in plan.member_slot_map.keys():
		var slot: Vector2i = plan.get_slot_for_member(mid)
		if not _require(not seen.has(slot) and int(plan.slot_owner_map.get(slot, -1)) == mid,
			"Target ownership must remain bijective"): return false
		seen[slot] = true
		if int(plan.slot_tactical_roles.get(slot, Types.TacticalSlotRole.FLEX)) == Types.TacticalSlotRole.COMMANDER:
			commander_markers += 1
			if not _require(mid == commander, "The commander marker must follow the member, not the former cell"): return false
	return _require(commander_markers == 1, "The plan must have exactly one commander marker")

func _vacancy_case(commander_waits: bool) -> Dictionary:
	var terrain: TerrainData = Helper.build_flat_map(12, 8)
	var plan := CombatDeploymentPlan.new()
	var move := CombatMovePlan.new()
	move.destination_plan = plan
	var waiting: int = COMMANDER if commander_waits else WAITING
	var commander_slot: Vector2i = VACANCY if commander_waits else Vector2i(5, 1)
	var cells: Dictionary = {waiting: Vector2i(2, 4)}
	var next_id := 1
	for x in range(2, 9):
		for y in range(1, 7):
			plan.platform_footprint.append(Vector2i(x, y))
	for x in range(3, 8):
		for y in range(1, 6):
			var slot := Vector2i(x, y)
			plan.platform_slots.append(slot)
			var mid: int = waiting if slot == VACANCY else (COMMANDER if slot == commander_slot else next_id)
			if mid == next_id and slot != VACANCY and slot != commander_slot:
				next_id += 1
			plan.member_slot_map[mid] = slot
			plan.slot_owner_map[slot] = mid
			plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
			plan.slot_tactical_roles[slot] = Types.TacticalSlotRole.COMMANDER if mid == COMMANDER else Types.TacticalSlotRole.FLEX
			plan.admitted_platform_member_ids.append(mid)
			if mid == waiting:
				continue
			cells[mid] = slot
			# With an ordinary waiting owner, the commander is the only movable
			# neighbour of its vacant final. The other three neighbours remain
			# physically present but have not yet settled their slots.
			if not commander_waits and slot in [Vector2i(4, 2), Vector2i(6, 2), Vector2i(5, 3)]:
				continue
			plan.settled_platform_member_ids.append(mid)
			plan.member_slot_locked[mid] = true
	return {"terrain": terrain, "plan": plan, "move": move, "cells": cells, "waiting": waiting}

func _test_commander_waiter() -> bool:
	var case: Dictionary = _vacancy_case(true)
	var terrain: TerrainData = case.terrain
	var plan: CombatDeploymentPlan = case.plan
	var move: CombatMovePlan = case.move
	var cells: Dictionary = case.cells
	var occupied: Dictionary = {}
	for cell in cells.values():
		occupied[cell] = true
	var allowed: Dictionary = {}
	for cell in plan.platform_footprint:
		allowed[cell] = true
	var before: Dictionary = cells.duplicate()
	var epoch: int = plan.assignment_epoch
	if not _require(Destination._recover_isolated_final_vacancy(move, plan, cells, terrain, occupied, allowed),
		"A commander waiting for an enclosed final must receive the same vacancy recovery as any friendly"): return false
	if not _require(cells == before and plan.assignment_epoch == epoch + 1 and move.vacancy_waiting_id == COMMANDER
		and move.member_recovery_hold.has(COMMANDER) and move.active_vacancy_chain_actors.size() == 1
		and plan.get_slot_for_member(COMMANDER) != VACANCY,
		"Recovery must rotate only target ownership while the commander waits for a physical opening"): return false
	return _assert_ownership(plan, COMMANDER)

func _test_commander_actor() -> bool:
	var case: Dictionary = _vacancy_case(false)
	var terrain: TerrainData = case.terrain
	var plan: CombatDeploymentPlan = case.plan
	var move: CombatMovePlan = case.move
	var cells: Dictionary = case.cells
	var occupied: Dictionary = {}
	for cell in cells.values():
		occupied[cell] = true
	var allowed: Dictionary = {}
	for cell in plan.platform_footprint:
		allowed[cell] = true
	var before: Dictionary = cells.duplicate()
	var old_commander_slot: Vector2i = plan.get_slot_for_member(COMMANDER)
	if not _require(Destination._recover_isolated_final_vacancy(move, plan, cells, terrain, occupied, allowed),
		"A settled commander next to the vacancy must be eligible as its physical chain actor"): return false
	if not _require(cells == before and move.active_vacancy_chain_actors == [COMMANDER]
		and plan.get_slot_for_member(COMMANDER) == VACANCY and plan.get_slot_for_member(WAITING) == old_commander_slot
		and terrain.can_step(cells[COMMANDER], VACANCY),
		"The commander must receive one legal adjacent step, with no premature physical cell change"): return false
	return _assert_ownership(plan, COMMANDER)

func _test_target_exchange_then_physical_step() -> bool:
	var terrain: TerrainData = Helper.build_flat_map(24, 16)
	var army: TerrainArmy = Helper.create_test_army(terrain, 1, 0, 2, Vector2i(5, 5))
	var coordinator: SiteCombatMovementCoordinator = Coordinator.new()
	coordinator.register_formation(army)
	var order: Dictionary = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(15, 5), -1, Vector2i.RIGHT)
	if not _require(bool(order.get("ok", false)), "The physical step requires an accepted MOVE order"): return false
	var commander_index: int = army.current_commander
	var other_index: int = 1 if commander_index == 0 else 0
	var commander_id: int = army.combat_identity(commander_index)
	var other_id: int = army.combat_identity(other_index)
	var source: Vector2i = army.cells[commander_index]
	var open_cell: Vector2i = source + Vector2i.UP
	var other_source: Vector2i = army.cells[other_index]
	var plan := CombatDeploymentPlan.new()
	plan.platform_slots.assign([source, open_cell])
	plan.platform_footprint.assign([source, open_cell])
	plan.member_role_map[commander_id] = Types.CombatDestinationRole.PLATFORM
	plan.member_role_map[other_id] = Types.CombatDestinationRole.PLATFORM
	plan.member_slot_map[commander_id] = source
	plan.member_slot_map[other_id] = open_cell
	plan.slot_owner_map[source] = commander_id
	plan.slot_owner_map[open_cell] = other_id
	plan.slot_tactical_roles[source] = Types.TacticalSlotRole.COMMANDER
	plan.slot_tactical_roles[open_cell] = Types.TacticalSlotRole.FLEX
	army._combat_deployment_plan = plan
	var active_move: CombatMovePlan = army.get_active_move_plan()
	active_move.destination_plan = plan
	if not _require(plan.swap_member_slots(other_id, commander_id) and plan.get_slot_for_member(commander_id) == open_cell,
		"Another friendly must be able to exchange target ownership with the commander"): return false
	if not _assert_ownership(plan, commander_id): return false
	coordinator._rebuild_occupancy()
	var grid: SiteMovementReservationGrid = coordinator.movement_reservation_grid
	grid.begin_tick(coordinator._current_occupancy, terrain)
	var proposal_id: int = grid.propose_move(army.formation_runtime_id, commander_id, army.get_order_serial(), source, open_cell)
	grid.resolve_all()
	if not _require(grid.proposal_lookup[proposal_id].status == Types.MoveProposalStatus.ACCEPTED,
		"The commander's newly owned empty target must accept its physical step"): return false
	grid.commit_all(coordinator._member_lookup, 1)
	coordinator._register_started_batches()
	if not _require(army.cells[commander_index] == source and army.moving_to[commander_index] == open_cell
		and is_equal_approx(army.move_duration[commander_index], 0.38),
		"Starting the step must retain the source for the 0.38-second move"): return false
	army.prepare_combat(0.19)
	coordinator.complete_committed_moves()
	if not _require(army.cells[commander_index] == source and army.move_progress[commander_index] > 0.0
		and army.move_progress[commander_index] < 1.0,
		"The target exchange must not teleport the commander during interpolation"): return false
	army.prepare_combat(0.19)
	coordinator.complete_committed_moves()
	if not _require(army.cells[commander_index] == open_cell and army.cells[other_index] == other_source
		and army.moving_to[commander_index] == TerrainArmy.INVALID_CELL
		and army._cell_owners.size() == 2 and army._cell_owners.get(source, -1) == -1
		and army._cell_owners.get(open_cell, -1) == commander_index
		and army._cell_owners.get(other_source, -1) == other_index and army._reserved_cells.is_empty()
		and coordinator._current_occupancy.get(source, -1) == -1
		and coordinator._current_occupancy.get(open_cell, -1) == commander_id,
		"At 0.38 seconds the commander must own the exact target cell without duplicating occupancy"): return false
	if not _assert_ownership(plan, commander_id): return false
	coordinator.unregister_formation(army)
	army.free()
	return true

func _run() -> void:
	if not _test_commander_waiter(): return
	if not _test_commander_actor(): return
	if not _test_target_exchange_then_physical_step(): return
	print("COMBAT MOVEMENT COMMANDER VACANCY PARITY PASS")
	quit(0)
