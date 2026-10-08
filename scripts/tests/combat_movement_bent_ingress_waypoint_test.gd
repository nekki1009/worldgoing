extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var terrain := Helper.build_flat_map(70, 55)
	var plan := CombatDeploymentPlan.new()
	plan.ingress_cell = Vector2i(61, 47)
	# The actual highland route bends in its three-cell ingress buffer.
	plan.ingress_buffer_cells.append_array([Vector2i(63, 48), Vector2i(63, 47), Vector2i(62, 47)])
	plan.platform_footprint.append_array([Vector2i(61, 47), Vector2i(60, 47), Vector2i(61, 46)])
	var lane: Dictionary = {Vector2i(61, 47): true, Vector2i(60, 47): true}
	var occupied: Dictionary = {Vector2i(61, 47): true, Vector2i(62, 47): true}
	var next: Vector2i = Destination._entry_lane_waypoint(plan.ingress_cell, plan, lane, occupied, terrain)
	if next != Vector2i(60, 47) or not terrain.can_step(plan.ingress_cell, next):
		push_error("Bent ingress must offer the legal forward cell instead of a diagonal step: " + str(next))
		quit(1)
		return
	occupied[next] = true
	next = Destination._entry_lane_waypoint(plan.ingress_cell, plan, lane, occupied, terrain)
	if next != Vector2i(61, 46) or not terrain.can_step(plan.ingress_cell, next):
		push_error("A blocked forward cell must offer the legal side cell: " + str(next))
		quit(1)
		return
	var move := CombatMovePlan.new()
	move.macro_path = [Vector2i(63, 48), Vector2i(63, 47), Vector2i(62, 47), plan.ingress_cell]
	plan.queue_member_ids.append(11)
	plan.member_role_map[11] = Types.CombatDestinationRole.APPROACH_QUEUE
	plan.member_slot_map[11] = Vector2i(62, 49)
	plan.pending_platform_member_ids.append(12)
	Destination.assign_queue_egress_waypoints(move, plan, {11: Vector2i(62, 47), 12: Vector2i(63, 47)}, terrain)
	var side: Vector2i = move.member_queue_egress_waypoint.get(11, Vector2i(-1, -1))
	if side != Vector2i(62, 48) or not terrain.can_step(Vector2i(62, 47), side):
		push_error("Bent ingress queue egress must use a legal adjacent side cell: " + str(side))
		quit(1)
		return
	print("COMBAT MOVEMENT BENT INGRESS WAYPOINT PASS")
	quit(0)
