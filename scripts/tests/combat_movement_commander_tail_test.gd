extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")

var _army: TerrainArmy
var _coordinator

func _initialize() -> void:
	call_deferred("_run")

func _finish(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
	if _coordinator != null and _army != null:
		_coordinator.unregister_formation(_army)
	if _army != null:
		_army.free()
	TerrainArmy.release_contact_source() # Headless teardown: release the shared contact rig before the post-quit frame (as 8ab42b0/54cd151).
	quit(0 if ok else 1)

func _run() -> void:
	var fixture := Helper.build_bottleneck_map(Vector2i(150, 22), 10, 40, 90, 1)
	var terrain: TerrainData = fixture["data"]
	_army = Helper.create_test_army(terrain, 1, 0, 4, Vector2i(5, 9))
	_coordinator = Coordinator.new()
	_coordinator.register_formation(_army)
	var order: Dictionary = _army.issue_combat_order(_army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(135, 10), -1, Vector2i.RIGHT)
	if not bool(order.get("ok", false)):
		_finish(false, "Long-route Commander MOVE was rejected: " + str(order))
		return
	var plan: CombatDeploymentPlan = _army.get_active_deployment_plan()
	var move: CombatMovePlan = _army.get_active_move_plan()
	if plan == null or move == null or move.macro_path.size() < 120:
		_finish(false, "Fixture must have a long verified macro route")
		return
	var commander: int = _army.combat_identity(0)
	var start: Vector2i = _army.cells[0]
	var previous: Array[Vector2i] = _army.cells.duplicate()
	var crossed: Dictionary = {}
	var marched_before_settlement := false
	var completed := -1
	for tick in range(4000):
		_coordinator.combat_logic_tick(0.05)
		_army.prepare_combat(0.05)
		_coordinator.complete_committed_moves()
		var unique: Dictionary = {}
		for index in range(4):
			var cell: Vector2i = _army.cells[index]
			if unique.has(cell) or not terrain.contains(cell) or not terrain.is_walkable(cell) or (cell != previous[index] and not terrain.can_step(previous[index], cell)):
				_finish(false, "Commander route collision or illegal physical edge at tick %d" % tick)
				return
			unique[cell] = true
			previous[index] = cell
			if cell.x > 90:
				crossed[index] = true
		if _army.cells[0] != start and plan.settled_platform_member_ids.size() < 3:
			marched_before_settlement = true
		if _army.combat_order == TerrainArmy.CombatOrder.HOLD:
			completed = tick
			break
	if completed < 0 or not _army.command_status.begins_with("已抵達") or not marched_before_settlement or crossed.size() != 4 or not Destination.is_settled(plan, _army.get_active_members_occupancy()):
		_finish(false, "Commander must move under the same cell contract and complete exact final arrival; tick=%d status=%s" % [completed, _army.command_status])
		return
	var final_cells: Array[Vector2i] = _army.cells.duplicate()
	var leases: Array[Vector2i] = _coordinator.deployment_registry.get_formation_reserved_slots(_army.team_id)
	if leases.size() != 4:
		_finish(false, "All four final leases must remain owned at arrival")
		return
	for quiet_tick in range(100):
		_coordinator.combat_logic_tick(0.05)
		_army.prepare_combat(0.05)
		_coordinator.complete_committed_moves()
		if _army.cells != final_cells or not _army.get_active_movement_claims().is_empty() or not _army._combat_batch_members.is_empty() or not _coordinator._inflight_batches.is_empty():
			_finish(false, "Final formation or claims changed during five-second stable window")
			return
		for index in range(4):
			if _army.facing[index] != Vector2i.RIGHT or _army.moving_to[index] != TerrainArmy.INVALID_CELL:
				_finish(false, "Final facing or idle state changed during stable window")
				return
	var leases_after: Array[Vector2i] = _coordinator.deployment_registry.get_formation_reserved_slots(_army.team_id)
	if leases_after.size() != leases.size():
		_finish(false, "Final leases changed during stable window")
		return
	for slot in leases:
		if not leases_after.has(slot):
			_finish(false, "Final lease disappeared during stable window")
			return
	print("COMBAT MOVEMENT COMMANDER PARITY PASS tick=", completed, " macro=", move.macro_path.size(), " commander=", commander)
	_finish(true, "")
