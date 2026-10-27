extends SceneTree
## A full 200-person roster accepts a legal destination and retains it when a
## reachable but undersized destination rejects a replacement MOVE.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Transit = preload("res://scripts/terrain_lab/formation_transit_planner.gd")

const MEMBERS := 200
const OLD_GOAL := Vector2i(24, 22)
const SMALL_GOAL := Vector2i(46, 20)

var _army: TerrainArmy
var _coordinator: SiteCombatMovementCoordinator

func _initialize() -> void:
	call_deferred("_run")

func _finish(ok: bool, message: String) -> void:
	if ok:
		print(message)
	else:
		push_error(message)
	if is_instance_valid(_army):
		_coordinator.unregister_formation(_army)
		_army.free()
	TerrainArmy.release_contact_source() # Headless teardown: release the shared contact rig before the post-quit frame (as 8ab42b0/54cd151).
	quit(0 if ok else 1)

func _require(condition: bool, message: String) -> bool:
	if not condition:
		_finish(false, message)
	return condition

func _open_rect(data: TerrainData, x0: int, y0: int, x1: int, y1: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var index := data.index(Vector2i(x, y))
			data.flags[index] = TerrainData.Flag.WALKABLE
			data.static_blocked[index] = 0

func _build_map() -> TerrainData:
	var data: TerrainData = Helper.build_flat_map(80, 60)
	data.flags.fill(0)
	data.static_blocked.fill(1)
	# The western room fits the original roster and a full 200-slot order.
	_open_rect(data, 2, 10, 31, 35)
	# Only a south/east U-shaped path reaches the small eastern pocket. The
	# last approach runs west, so its legal queue cannot fill the western room.
	_open_rect(data, 30, 35, 30, 40)
	_open_rect(data, 30, 40, 60, 40)
	_open_rect(data, 60, 20, 60, 40)
	_open_rect(data, 50, 20, 60, 20)
	_open_rect(data, 43, 15, 50, 25)
	data.navigation_revision += 1
	return data

func _run() -> void:
	var data := _build_map()
	_army = Helper.create_test_army(data, 1, 0, MEMBERS, Vector2i(5, 10))
	_coordinator = Coordinator.new()
	_coordinator.register_formation(_army)
	if not _require(_army.roster_size == MEMBERS and _army.combat_units.size() == MEMBERS
		and _army.get_active_members_occupancy().size() == MEMBERS, "The original 200 people were not deployed uniquely"): return
	var narrow_path: Array[Vector2i] = Transit.build_macro_path(data, _army.cells[_army.current_commander], SMALL_GOAL)
	if not _require(not narrow_path.is_empty() and narrow_path.has(Vector2i(60, 40))
		and narrow_path.has(Vector2i(60, 20)) and narrow_path[-1] == SMALL_GOAL,
		"The undersized destination must remain reachable through the real U-shaped path"): return
	var first: Dictionary = _army.issue_combat_order(_army.current_commander, TerrainArmy.CombatOrder.MOVE, OLD_GOAL, -1, Vector2i.RIGHT)
	if not _require(bool(first.get("ok", false)), "A 200-person legal MOVE was rejected: " + str(first)): return
	var old_plan: CombatDeploymentPlan = _army.get_active_deployment_plan()
	var old_move: CombatMovePlan = _army.get_active_move_plan()
	if not _require(old_plan != null and old_move != null and old_plan.member_slot_map.size() == MEMBERS
		and old_plan.slot_owner_map.size() == MEMBERS and old_plan.final_facing == Vector2i.RIGHT,
		"The accepted 200-person order did not assign 200 unique final slots"): return
	var old_leases: Array[Vector2i] = _coordinator.deployment_registry.get_formation_reserved_slots(_army.team_id)
	if not _require(old_leases.size() == MEMBERS, "The accepted 200-person order did not reserve every final slot"): return
	for slot: Vector2i in old_leases:
		var lease = _coordinator.deployment_registry.owner_of(slot)
		if not _require(data.is_walkable(slot) and old_plan.slot_owner_map.has(slot) and lease != null
			and lease.formation_id == _army.team_id and lease.order_serial == old_plan.order_serial,
			"The old deployment contains an illegal, unowned, or stale lease at " + str(slot)): return
	var original_serial := _army.get_order_serial()
	var original_cells: Array[Vector2i] = _army.cells.duplicate()
	var original_targets: Array[Vector2i] = _army.moving_to.duplicate()
	var original_slots: Array[Vector2i] = _army.combat_slots.duplicate()
	var original_goal: Vector2i = _army.combat_goal
	var rejected: Dictionary = _army.issue_combat_order(_army.current_commander, TerrainArmy.CombatOrder.MOVE, SMALL_GOAL, -1, Vector2i.LEFT)
	if not _require(not bool(rejected.get("ok", false)) and str(rejected.get("code", "")) == "INSUFFICIENT_SPACE",
		"A reachable destination with fewer than 200 final cells must fail capacity preflight: " + str(rejected)): return
	if not _require(_army.combat_order == TerrainArmy.CombatOrder.MOVE and _army.get_order_serial() == original_serial
		and _army.get_active_move_plan() == old_move and _army.get_active_deployment_plan() == old_plan
		and _army.combat_goal == original_goal and _army.cells == original_cells
		and _army.moving_to == original_targets and _army.combat_slots == original_slots,
		"Rejected MOVE changed the old order, physical cells, or assigned slots"): return
	var leases_after: Array[Vector2i] = _coordinator.deployment_registry.get_formation_reserved_slots(_army.team_id)
	if not _require(leases_after.size() == MEMBERS and _coordinator.deployment_registry.slot_owners.size() == MEMBERS,
		"Rejected MOVE changed the number of deployment leases"): return
	for slot: Vector2i in old_leases:
		var lease = _coordinator.deployment_registry.owner_of(slot)
		if not _require(leases_after.has(slot) and lease != null and lease.formation_id == _army.team_id
			and lease.order_serial == original_serial and old_plan.slot_owner_map.has(slot),
			"Rejected MOVE lost or replaced an original final-slot lease at " + str(slot)): return
	# The old command is still executable, not merely retained as a stale object.
	_coordinator.combat_logic_tick(0.05)
	_army.prepare_combat(0.05)
	_coordinator.complete_committed_moves()
	if not _require(_army.combat_order == TerrainArmy.CombatOrder.MOVE and _army.get_active_move_plan() == old_move
		and _army.get_active_deployment_plan() == old_plan, "The preserved order cannot continue after rejection"): return
	_finish(true, "COMBAT MOVEMENT 200 CAPACITY ROLLBACK PASS: 200 legal final slots; reachable undersized destination rejected; old order and leases preserved")
