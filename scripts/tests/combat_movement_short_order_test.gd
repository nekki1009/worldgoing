extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")

func _initialize() -> void:
	call_deferred("_run")

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false

func _run() -> void:
	var data := Helper.build_flat_map(16, 16)
	var army := Helper.create_test_army(data, 1, 0, 3, Vector2i(3, 5))
	var coordinator := Coordinator.new()
	coordinator.register_formation(army)
	var short_goal := Vector2i(7, 5)
	if not _require(bool(army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, short_goal).get("ok", false)), "Short MOVE must be accepted"): return
	var plan = army.get_active_deployment_plan()
	if not _require(army.get_active_move_plan() != null and plan != null and plan.member_slot_map.size() == 3, "Short MOVE must use the canonical movement and deployment plans"): return
	for slot: Vector2i in plan.member_slot_map.values():
		if not _require(coordinator.deployment_registry.is_slot_reserved(slot), "Short MOVE final slots must be leased"): return
	var previous: Array[Vector2i] = army.cells.duplicate()
	var finished := false
	for tick in range(600):
		coordinator.combat_logic_tick(0.05)
		army.prepare_combat(0.05)
		coordinator.complete_committed_moves()
		var seen: Dictionary = {}
		for i in range(3):
			if not _require(not seen.has(army.cells[i]) and (army.cells[i] == previous[i] or data.can_step(previous[i], army.cells[i])), "Short MOVE must keep unique cells and legal physical steps at tick %d" % tick): return
			seen[army.cells[i]] = true
			previous[i] = army.cells[i]
		if army.combat_order == TerrainArmy.CombatOrder.HOLD:
			finished = army.command_status.begins_with("已抵達")
			break
	if not _require(finished and Destination.is_settled(plan, army.get_active_members_occupancy()), "Short MOVE must reach its assigned final formation"): return
	coordinator.unregister_formation(army)
	army.free()

	var point_army := Helper.create_test_army(data, 2, 0, 1, Vector2i(3, 10))
	var point_coordinator := Coordinator.new()
	point_coordinator.register_formation(point_army)
	point_army.facing[0] = Vector2i.UP
	var point_cell: Vector2i = point_army.cells[0]
	if not _require(bool(point_army.issue_combat_order(point_army.current_commander, TerrainArmy.CombatOrder.MOVE, point_cell).get("ok", false)), "Same-cell point-click must create a deployment command"): return
	var point_plan = point_army.get_active_deployment_plan()
	if not _require(point_army.get_active_move_plan() != null and point_plan != null and point_plan.final_facing == Vector2i.UP, "Same-cell order must inherit the commander's facing"): return
	var previous_point := point_cell
	for tick in range(300):
		point_coordinator.combat_logic_tick(0.05)
		point_army.prepare_combat(0.05)
		point_coordinator.complete_committed_moves()
		if not _require(point_army.cells[0] == previous_point or data.can_step(previous_point, point_army.cells[0]), "Same-cell deployment must use a legal physical step"): return
		previous_point = point_army.cells[0]
		if point_army.combat_order == TerrainArmy.CombatOrder.HOLD:
			break
	if not _require(point_army.combat_order == TerrainArmy.CombatOrder.HOLD and point_army.command_status.begins_with("已抵達"), "Same-cell deployment must settle: status=%s cell=%s slot=%s" % [point_army.command_status, point_army.cells[0], point_plan.get_slot_for_member(point_army.combat_identity(0))]): return
	if not _require(point_army.cells[0] == point_plan.get_slot_for_member(point_army.combat_identity(0)) and point_army.facing[0] == Vector2i.UP, "Point-click must reach the final slot and orient without a physical jump"): return
	print("COMBAT MOVEMENT SHORT ORDER PASS")
	point_coordinator.unregister_formation(point_army)
	point_army.free()
	quit(0)
