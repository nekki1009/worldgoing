extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const Grid = preload("res://scripts/terrain_lab/site_movement_reservation_grid.gd")
const Registry = preload("res://scripts/terrain_lab/site_deployment_reservation_registry.gd")
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
	var terrain := Helper.build_flat_map(16, 12)
	var plan := CombatDeploymentPlan.new()
	plan.ingress_cell = Vector2i.ZERO
	plan.ingress_buffer_cells.append(Vector2i(0, 1))
	var next_id := 3
	for x in range(4, 9):
		for y in range(4, 9):
			var slot := Vector2i(x, y)
			var mid: int = 1 if slot == Vector2i(6, 6) else 2 if slot == Vector2i(7, 6) else next_id
			if mid == next_id:
				next_id += 1
			plan.platform_slots.append(slot)
			plan.platform_footprint.append(slot)
			plan.member_slot_map[mid] = slot
			plan.slot_owner_map[slot] = mid
			plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
			plan.slot_tactical_roles[slot] = Types.TacticalSlotRole.FLEX
	for x in range(9, 13):
		plan.platform_footprint.append(Vector2i(x, 6))
	var move := CombatMovePlan.new()
	move.destination_plan = plan
	move.formation_id = 1
	plan.formation_id = 1
	move.macro_path.append(Vector2i.ZERO)
	move.member_route_retry_count[1] = 12
	var cells: Dictionary = {1: Vector2i(12, 6), 2: Vector2i(6, 6)}
	var occupied: Dictionary = {Vector2i(12, 6): true, Vector2i(6, 6): true}
	var owned_before: Dictionary = plan.member_slot_map.duplicate()
	if not _require(Destination._outer_approach_waypoint(move, plan, cells[1], plan.get_slot_for_member(1), occupied, {}, terrain) == Vector2i(11, 6),
		"A blocked outer FLEX entrant must choose a free non-final step with strictly shorter terrain distance to its fixed final"): return
	Destination.late_bind_ingress_target(move, plan, cells, terrain)
	if not _require(move.member_entry_waypoint.get(1, Vector2i(-1, -1)) == Vector2i(11, 6) and Destination.resolve_member_target(move, plan, 1, cells[1]).target == Vector2i(11, 6) and plan.member_slot_map == owned_before and cells[1] == Vector2i(12, 6),
		"The temporary target must route through the existing Grid without changing final ownership or physical cells"): return
	plan.lock_member_slot(1)
	Destination.late_bind_ingress_target(move, plan, cells, terrain)
	if not _require(not move.member_entry_waypoint.has(1),
		"A locked outer member must not receive a temporary waypoint"): return
	plan.member_slot_locked.erase(1)
	plan.slot_tactical_roles[plan.get_slot_for_member(1)] = Types.TacticalSlotRole.COMMANDER
	Destination.late_bind_ingress_target(move, plan, cells, terrain)
	if not _require(not move.member_entry_waypoint.has(1),
		"A non-FLEX outer member must keep its designated final target"): return
	plan.slot_tactical_roles[plan.get_slot_for_member(1)] = Types.TacticalSlotRole.FLEX
	occupied.erase(cells[1])
	cells[1] = Vector2i(11, 6)
	occupied[cells[1]] = true
	if not _require(Destination._outer_approach_waypoint(move, plan, cells[1], plan.get_slot_for_member(1), occupied, {}, terrain) == Vector2i(10, 6),
		"After one physical step the next target must strictly approach the same final"): return
	occupied.erase(cells[1])
	cells[1] = Vector2i(9, 6)
	occupied[cells[1]] = true
	if not _require(Destination._outer_approach_waypoint(move, plan, cells[1], plan.get_slot_for_member(1), occupied, {}, terrain) == cells[1],
		"At the final-slot boundary the approach must stop rather than bounce or take another member's final"): return
	occupied.erase(cells[1])
	cells[1] = Vector2i(12, 6)
	occupied[cells[1]] = true
	move.member_entry_waypoint[88] = Vector2i(11, 6)
	if not _require(Destination._outer_approach_waypoint(move, plan, cells[1], plan.get_slot_for_member(1), occupied, {}, terrain) == cells[1],
		"Two blocked members cannot claim the same temporary target in one planning tick"): return
	move.member_entry_waypoint.clear()
	plan.slot_lease_timers[Vector2i(11, 6)] = 4.0
	if not _require(Destination._outer_approach_waypoint(move, plan, cells[1], plan.get_slot_for_member(1), occupied, {}, terrain) == cells[1],
		"A temporary target must not borrow another reserved slot"): return
	plan.slot_lease_timers.clear()
	occupied[Vector2i(11, 6)] = true
	if not _require(Destination._outer_approach_waypoint(move, plan, cells[1], plan.get_slot_for_member(1), occupied, {}, terrain) == cells[1],
		"An occupied cross-team candidate must not be selected"): return
	var grid: SiteMovementReservationGrid = Grid.new()
	grid.begin_tick({Vector2i(12, 6): 1, Vector2i(11, 6): 77}, terrain)
	var proposal: int = grid.propose_move(1, 1, 1, Vector2i(12, 6), Vector2i(11, 6))
	grid.resolve_all()
	if not _require(proposal >= 0 and grid.proposal_lookup[proposal].status == Types.MoveProposalStatus.REJECTED_DEPENDENCY,
		"The authoritative Grid must reject a waypoint occupied by an unmoving other-team member"): return
	# One cell outside the final block has no closer non-final footprint cell.
	# The usual late-bind entry step must remain available in that case.
	cells[1] = Vector2i(9, 6)
	occupied = {cells[1]: true, cells[2]: true}
	plan.ingress_buffer_cells[0] = Vector2i(1, 0)
	if not _require(Destination._outer_approach_waypoint(move, plan, cells[1], plan.get_slot_for_member(1), occupied, {}, terrain) == cells[1],
		"The outer approach must decline when every closer footprint cell is a final slot"): return
	Destination.late_bind_ingress_target(move, plan, cells, terrain)
	if not _require(move.member_entry_waypoint.get(1, Vector2i(-1, -1)) == Vector2i(8, 6),
		"With no valid outer waypoint, existing late-bind entry recovery must still run"): return
	cells[1] = Vector2i(12, 6)
	occupied = {cells[1]: true, cells[2]: true}
	plan.ingress_buffer_cells[0] = Vector2i(0, 1)
	var foreign_registry: SiteDeploymentReservationRegistry = Registry.new()
	if not _require(bool(foreign_registry.try_replace_reservations(77, -1, 1, [Vector2i(11, 6)]).get("ok", false)),
		"The foreign empty waypoint fixture must hold a real final-slot lease"): return
	if not _require(Destination._outer_approach_waypoint(move, plan, cells[1], plan.get_slot_for_member(1), occupied, {}, terrain, foreign_registry) == cells[1],
		"An empty final slot leased to another team cannot be an outer waypoint"): return
	Destination.late_bind_ingress_target(move, plan, cells, terrain, foreign_registry)
	if not _require(not move.member_entry_waypoint.has(1),
		"Legacy entry recovery must not borrow a foreign lease after outer waypoint rejection"): return
	var own_registry: SiteDeploymentReservationRegistry = Registry.new()
	if not _require(bool(own_registry.try_replace_reservations(1, -1, 1, [Vector2i(11, 6)]).get("ok", false)),
		"The own empty waypoint fixture must hold a real lease"): return
	Destination.late_bind_ingress_target(move, plan, cells, terrain, own_registry)
	if not _require(move.member_entry_waypoint.get(1, Vector2i(-1, -1)) == Vector2i(11, 6),
		"An own-formation lease remains eligible under the registry exclusion"): return
	var edge_terrain := Helper.build_flat_map(60, 40)
	var edge_plan := CombatDeploymentPlan.new()
	edge_plan.ingress_cell = Vector2i(20, 18)
	edge_plan.ingress_buffer_cells.append(Vector2i(19, 18))
	for x in range(29, 38):
		edge_plan.platform_footprint.append(Vector2i(x, 18))
	for entry in [[1, Vector2i(29, 18)], [2, Vector2i(35, 18)]]:
		var mid: int = entry[0]
		var slot: Vector2i = entry[1]
		edge_plan.platform_slots.append(slot)
		edge_plan.member_slot_map[mid] = slot
		edge_plan.slot_owner_map[slot] = mid
		edge_plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
		edge_plan.slot_tactical_roles[slot] = Types.TacticalSlotRole.FLEX
	var edge_move := CombatMovePlan.new()
	edge_move.destination_plan = edge_plan
	edge_move.member_route_retry_count[1] = 12
	edge_plan.lock_member_slot(2)
	var edge_cells: Dictionary = {1: Vector2i(36, 18), 2: Vector2i(29, 18)}
	Destination.late_bind_ingress_target(edge_move, edge_plan, edge_cells, edge_terrain)
	if not _require(not edge_move.member_entry_waypoint.has(1),
		"At the final boundary, fallback must not send a blocked member outward from (36,18) to (37,18); waypoint=" + str(edge_move.member_entry_waypoint.get(1, TerrainArmy.INVALID_CELL))): return
	if not _require(not edge_move.member_entry_hold.has(1),
		"Rejecting an outward waypoint must not leave a current-cell hold"): return
	var edge_target: Dictionary = Destination.resolve_member_target(edge_move, edge_plan, 1, edge_cells[1])
	if not _require(edge_target.get("target", TerrainArmy.INVALID_CELL) == Vector2i(29, 18),
		"Rejecting an outward waypoint must restore the fixed final target; resolved=" + str(edge_target)): return
	edge_cells[1] = Vector2i(37, 18)
	Destination.late_bind_ingress_target(edge_move, edge_plan, edge_cells, edge_terrain)
	if not _require(edge_move.member_entry_waypoint.get(1, Vector2i(-1, -1)) == Vector2i(36, 18),
		"An outer waypoint may bring the same member inward from (37,18) to (36,18)"): return
	var side_plan := CombatDeploymentPlan.new()
	side_plan.ingress_cell = Vector2i(20, 22)
	side_plan.ingress_buffer_cells.append(Vector2i(19, 22))
	side_plan.platform_footprint.append_array([Vector2i(30, 19), Vector2i(31, 19), Vector2i(30, 22), Vector2i(31, 22)])
	for entry in [[1, Vector2i(30, 19)], [2, Vector2i(31, 19)]]:
		var mid: int = entry[0]
		var slot: Vector2i = entry[1]
		side_plan.platform_slots.append(slot)
		side_plan.member_slot_map[mid] = slot
		side_plan.slot_owner_map[slot] = mid
		side_plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
		side_plan.slot_tactical_roles[slot] = Types.TacticalSlotRole.FLEX
	side_plan.lock_member_slot(2)
	var side_move := CombatMovePlan.new()
	side_move.destination_plan = side_plan
	side_move.member_route_retry_count[1] = 12
	var side_cells: Dictionary = {1: Vector2i(30, 22), 2: Vector2i(30, 19)}
	Destination.late_bind_ingress_target(side_move, side_plan, side_cells, edge_terrain)
	var side_step: Vector2i = Vector2i(31, 22) - side_cells[1]
	var side_toward: Vector2i = side_plan.get_slot_for_member(1) - side_cells[1]
	if not _require(side_move.member_entry_waypoint.get(1, Vector2i(-1, -1)) == Vector2i(31, 22) and side_step.x * side_toward.x + side_step.y * side_toward.y == 0,
		"A legal perpendicular side step must stay available to clear the current cell for a following member"): return
	var side_grid: SiteMovementReservationGrid = Grid.new()
	side_grid.begin_tick({Vector2i(30, 22): 1, Vector2i(29, 22): 3, Vector2i(30, 19): 2}, edge_terrain)
	var step_a: int = side_grid.propose_move(1, 1, 1, Vector2i(30, 22), Vector2i(31, 22))
	var step_b: int = side_grid.propose_move(1, 3, 1, Vector2i(29, 22), Vector2i(30, 22))
	side_grid.resolve_all()
	if not _require(side_grid.proposal_lookup[step_a].status == Types.MoveProposalStatus.ACCEPTED and side_grid.proposal_lookup[step_b].status == Types.MoveProposalStatus.ACCEPTED,
		"The ordinary Grid must commit the side step before another member occupies the vacated cell"): return
	var follow_plan := CombatDeploymentPlan.new()
	follow_plan.ingress_cell = Vector2i(20, 22)
	follow_plan.ingress_buffer_cells.append(Vector2i(20, 21))
	follow_plan.platform_footprint.append_array([Vector2i(30, 17), Vector2i(30, 18), Vector2i(31, 18), Vector2i(29, 22), Vector2i(30, 22), Vector2i(30, 23)])
	for entry in [[1, Vector2i(30, 18)], [2, Vector2i(30, 17)], [3, Vector2i(31, 18)]]:
		var mid: int = entry[0]
		var slot: Vector2i = entry[1]
		follow_plan.platform_slots.append(slot)
		follow_plan.member_slot_map[mid] = slot
		follow_plan.slot_owner_map[slot] = mid
		follow_plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
		follow_plan.slot_tactical_roles[slot] = Types.TacticalSlotRole.FLEX
	follow_plan.lock_member_slot(3)
	var follow_move := CombatMovePlan.new()
	follow_move.destination_plan = follow_plan
	follow_move.member_route_retry_count[1] = 12
	var follow_cells: Dictionary = {1: Vector2i(30, 22), 2: Vector2i(29, 22), 3: Vector2i(30, 18)}
	Destination.late_bind_ingress_target(follow_move, follow_plan, follow_cells, edge_terrain)
	if not _require(not follow_move.member_entry_waypoint.has(1),
		"An outward fallback must remain blocked even if an adjacent teammate could later occupy the vacated cell"): return
	var ramp_plan := CombatDeploymentPlan.new()
	ramp_plan.ingress_cell = Vector2i(35, 5)
	ramp_plan.ingress_buffer_cells.append(Vector2i(34, 5))
	for x in range(44, 48):
		ramp_plan.platform_footprint.append(Vector2i(x, 5))
	for entry in [[1, Vector2i(45, 5)], [2, Vector2i(46, 5)], [3, Vector2i(47, 5)]]:
		var mid: int = entry[0]
		var slot: Vector2i = entry[1]
		ramp_plan.platform_slots.append(slot)
		ramp_plan.member_slot_map[mid] = slot
		ramp_plan.slot_owner_map[slot] = mid
		ramp_plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
		ramp_plan.slot_tactical_roles[slot] = Types.TacticalSlotRole.FLEX
	var ramp_move := CombatMovePlan.new()
	ramp_move.destination_plan = ramp_plan
	ramp_move.member_route_retry_count[1] = 12
	ramp_move.macro_path.append(Vector2i(45, 5))
	var ramp_cells: Dictionary = {1: Vector2i(44, 5), 2: Vector2i(46, 5)}
	Destination.late_bind_ingress_target(ramp_move, ramp_plan, ramp_cells, edge_terrain)
	if not _require(ramp_move.member_entry_waypoint.get(1, Vector2i(-1, -1)) == Vector2i(45, 5),
		"A narrow plateau boundary must still permit the legacy inward step from (44,5) to final (45,5)"): return
	print("COMBAT MOVEMENT OUTER APPROACH WAYPOINT PASS")
	quit(0)
