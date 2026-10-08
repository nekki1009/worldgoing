extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const MEMBERS := 9
const STEP := 0.05
const MAX_ARRIVAL_TICKS := 2400
const WAIT_TICKS := 300 # Fifteen simulated seconds exceeds the old twelve-second cancellation.

var _army: TerrainArmy
var _coordinator := Coordinator.new()
var _terrain: TerrainData
var _plan: CombatDeploymentPlan
var _move: CombatMovePlan
var _previous: Array[Vector2i] = []
var _original_ids: Array = []
var _blocked_cell := Vector2i(-1, -1)
var _block_enabled := true
var _follower := -1
var _follower_steps := 0
var _tick := 0

func _initialize() -> void:
	call_deferred("_run")

func _blocks(cell: Vector2i) -> bool:
	return _block_enabled and cell == _blocked_cell

func _assigned_settled() -> int:
	var count := 0
	for mid: int in _plan.member_slot_map:
		var index := _army.index_for_identity(mid)
		if index >= 0 and _army.cells[index] == _plan.member_slot_map[mid] and _army.moving_to[index] == TerrainArmy.INVALID_CELL:
			count += 1
	return count

func _diagnostic() -> String:
	return "tick=%d seconds=%.2f order=%d status=%s phase=%d stall=%.2f assigned_settled=%d followers=%s follower_steps=%d cells=%s claims=%s final_slots=%s soft=%s route_target=%s route_status=%s" % [
		_tick, _tick * STEP, _army.combat_order, _army.command_status,
		_move.phase if _move != null else -1, _move.active_stall_total_sec if _move != null else -1.0,
		_assigned_settled() if _plan != null else -1, _plan.following_member_ids if _plan != null else [],
		_follower_steps, _army.cells, _army.moving_to, _plan.member_slot_map if _plan != null else {},
		_move.member_transit_slots if _move != null else {}, _move.member_route_target if _move != null else {},
		_move.member_route_status if _move != null else {}]

func _finish(ok: bool, message: String) -> void:
	if not ok and is_instance_valid(_army):
		message += " | " + _diagnostic()
	if is_instance_valid(_army):
		_coordinator.unregister_formation(_army)
		_army.free()
	if ok:
		print(message)
	else:
		push_error(message)
	quit(0 if ok else 1)

func _require(ok: bool, message: String) -> bool:
	if not ok:
		_finish(false, message)
	return ok

func _step() -> bool:
	_coordinator.combat_logic_tick(STEP)
	_army.prepare_combat(STEP)
	_coordinator.complete_committed_moves()
	_tick += 1
	var occupied: Dictionary = {}
	var claims: Dictionary = {}
	var current_ids := _army.get_active_members_occupancy().keys()
	current_ids.sort()
	if not _require(current_ids == _original_ids and _army.cells.size() == MEMBERS, "Partial movement changed the original member roster"): return false
	for index in range(MEMBERS):
		var cell: Vector2i = _army.cells[index]
		if not _require(_terrain.is_walkable(cell) and not occupied.has(cell) and not _blocks(cell), "A physical cell overlapped, left terrain, or entered the blocker"): return false
		occupied[cell] = true
		if cell != _previous[index]:
			if not _require(_terrain.can_step(_previous[index], cell), "A member skipped a legal physical edge"): return false
			if index == _army.index_for_identity(_follower): _follower_steps += 1
		_previous[index] = cell
		var claim: Vector2i = _army.moving_to[index]
		if claim != TerrainArmy.INVALID_CELL:
			if not _require(not claims.has(claim) and not _blocks(claim) and _terrain.can_step(cell, claim), "A movement claim overlapped or targeted an illegal edge"): return false
			claims[claim] = true
	return true

func _run() -> void:
	_terrain = Helper.build_flat_map(48, 30)
	_army = Helper.create_test_army(_terrain, 1, 0, MEMBERS, Vector2i(3, 10))
	if not _require(is_instance_valid(_army), "The real Army fixture could not be constructed"): return
	_coordinator.register_formation(_army)
	var goal := Vector2i(30, 15)
	var full_shape := Destination.shape_slots("square", MEMBERS, goal, Vector2i.RIGHT)
	_blocked_cell = full_shape[0]
	_army.external_blocker = _blocks
	var order := _army.issue_combat_order(_army.current_commander, TerrainArmy.CombatOrder.MOVE, goal, -1, Vector2i.RIGHT, "square")
	if not _require(bool(order.get("ok", false)), "Partial fixed MOVE was refused: " + str(order)): return
	_plan = _army.get_active_deployment_plan()
	_move = _army.get_active_move_plan()
	if not _require(_plan != null and _move != null and _plan.following_member_ids.size() == 1 and _plan.member_slot_map.size() == 8 and _plan.platform_slots.size() == 8, "Actual Army order did not create an eight-slot, one-follower contract"): return
	_follower = _plan.following_member_ids[0]
	_previous = _army.cells.duplicate()
	_original_ids = _army.get_active_members_occupancy().keys()
	_original_ids.sort()
	var serial := _plan.order_serial
	var front_settled_tick := -1
	for unused in range(MAX_ARRIVAL_TICKS):
		if not _step(): return
		if not _require(_army.combat_order == TerrainArmy.CombatOrder.MOVE and _army.get_active_deployment_plan() == _plan and _move.phase != CombatMovementTypes.CombatMovePhase.FAILED, "Partial MOVE was canceled before the front settled"): return
		if _assigned_settled() == 8:
			front_settled_tick = _tick
			break
	if not _require(front_settled_tick >= 0 and _follower_steps > 0, "The front did not settle with its original follower physically following"): return
	for unused in range(WAIT_TICKS):
		if not _step(): return
		if not _require(_army.combat_order == TerrainArmy.CombatOrder.MOVE and _army.get_active_deployment_plan() == _plan and _plan.order_serial == serial and _move.phase != CombatMovementTypes.CombatMovePhase.FAILED and _plan.following_member_ids == [_follower] and _assigned_settled() == 8, "Waiting for room canceled or disturbed the settled partial formation"): return
	if not _require(not Destination.is_settled(_plan, _army.get_active_members_occupancy()), "A waiting follower was incorrectly counted as full formation arrival"): return
	var before_resume_steps := _follower_steps
	_block_enabled = false
	var resumed_tick := -1
	for unused in range(MAX_ARRIVAL_TICKS):
		if not _step(): return
		if _army.combat_order == TerrainArmy.CombatOrder.HOLD:
			resumed_tick = _tick
			break
		if not _require(_army.combat_order == TerrainArmy.CombatOrder.MOVE and _army.get_active_deployment_plan() == _plan and _plan.order_serial == serial and _move.phase != CombatMovementTypes.CombatMovePhase.FAILED, "The resumed follower lost its original MOVE contract"): return
	if not _require(resumed_tick >= 0 and _army.command_status.begins_with("已抵達") and _plan.following_member_ids.is_empty() and _follower_steps > before_resume_steps and _assigned_settled() == MEMBERS and Destination.is_settled(_plan, _army.get_active_members_occupancy()), "Removing the blocker did not automatically finish all nine original members"): return
	if not _require(_plan.member_slot_map.has(_follower) and _plan.platform_slots.has(_blocked_cell), "The reopened real slot or original follower was omitted from the completed square"): return
	var expected: Dictionary = {}
	for slot: Vector2i in full_shape: expected[slot] = true
	for slot: Vector2i in _plan.member_slot_map.values():
		if not _require(expected.erase(slot), "A final slot differs from the original exact square template"): return
		var lease = _coordinator.deployment_registry.owner_of(slot)
		if not _require(lease != null and lease.formation_id == _army.team_id and lease.order_serial == serial, "A real final slot lost its original-order lease"): return
	if not _require(expected.is_empty(), "An original square slot is missing after automatic follower promotion"): return
	var final_cells: Array[Vector2i] = _army.cells.duplicate()
	for unused in range(100):
		if not _step(): return
		if not _require(_army.combat_order == TerrainArmy.CombatOrder.HOLD and _army.cells == final_cells and _coordinator.get_inflight_batches_for_formation(_army).is_empty(), "The completed full square drifted during five simulated seconds"): return
	_finish(true, "COMBAT MOVEMENT PARTIAL FOLLOW RUNTIME PASS: front_tick=%d waited=15s resume_tick=%d follower_steps=%d all_nine_exact=true" % [front_settled_tick, resumed_tick, _follower_steps])
