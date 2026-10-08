extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
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

func _make_plan() -> CombatDeploymentPlan:
	var plan := CombatDeploymentPlan.new()
	plan.formation_id = 1
	plan.ingress_cell = Vector2i(5, 5)
	plan.ingress_buffer_cells.append(Vector2i(4, 5))
	plan.platform_slots.append(Vector2i(10, 5))
	plan.platform_footprint.append(Vector2i(10, 5))
	plan.approach_queue_slots.append(Vector2i(3, 5))
	plan.member_role_map[1] = Types.CombatDestinationRole.APPROACH_QUEUE
	plan.member_role_map[2] = Types.CombatDestinationRole.PLATFORM
	plan.member_slot_map[1] = Vector2i(3, 5)
	plan.member_slot_map[2] = Vector2i(10, 5)
	plan.slot_owner_map[Vector2i(3, 5)] = 1
	plan.slot_owner_map[Vector2i(10, 5)] = 2
	plan.queue_member_ids.append(1)
	return plan

func _make_move(plan: CombatDeploymentPlan) -> CombatMovePlan:
	var move := CombatMovePlan.new()
	move.formation_id = 1
	move.destination_plan = plan
	move.macro_path.assign([Vector2i(3, 5), Vector2i(4, 5), Vector2i(5, 5)])
	return move

func _run() -> void:
	var terrain := Helper.build_flat_map(16, 12)
	var cells: Dictionary = {1: Vector2i(4, 5), 2: Vector2i(6, 5)}
	var foreign_registry: SiteDeploymentReservationRegistry = Registry.new()
	if not _require(bool(foreign_registry.try_replace_reservations(77, -1, 1, [Vector2i(4, 4)]).get("ok", false)),
		"The foreign queue-egress fixture must hold a real empty final-slot lease"): return
	var foreign_plan := _make_plan()
	var foreign_move := _make_move(foreign_plan)
	Destination.update_movement_phase(foreign_move, foreign_plan, cells, terrain, 0.0, foreign_registry)
	if not _require(foreign_plan.pending_platform_member_ids == [2] and not foreign_plan.queue_released,
		"The platform entrant must still be pending while the queue member clears ingress"): return
	if not _require(foreign_move.member_queue_egress_waypoint.get(1, Vector2i(-1, -1)) == Vector2i(4, 6),
		"A queue member must take the free alternate side step, not the other formation's empty final lease"): return
	if not _require(foreign_plan.member_slot_map[1] == Vector2i(3, 5) and foreign_plan.member_slot_map[2] == Vector2i(10, 5) and cells[1] == Vector2i(4, 5),
		"Queue egress is temporary and must not alter final ownership or physical cells"): return
	var own_registry: SiteDeploymentReservationRegistry = Registry.new()
	if not _require(bool(own_registry.try_replace_reservations(1, -1, 1, [Vector2i(4, 4)]).get("ok", false)),
		"The own queue-egress fixture must hold a real lease"): return
	var own_plan := _make_plan()
	var own_move := _make_move(own_plan)
	Destination.update_movement_phase(own_move, own_plan, cells, terrain, 0.0, own_registry)
	if not _require(own_move.member_queue_egress_waypoint.get(1, Vector2i(-1, -1)) == Vector2i(4, 4),
		"A temporary queue step may still use this formation's own lease"): return
	print("QUEUE_EGRESS_FOREIGN_LEASE_PASS")
	quit(0)
