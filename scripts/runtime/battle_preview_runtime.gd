class_name BattlePreviewRuntime
extends RefCounted

const BattleSiteSnapshotType = preload("res://scripts/runtime/battle_site_snapshot.gd")
const BattleSiteGeneratorType = preload("res://scripts/core/battle_site_generator.gd")
const BattleRuntimeStateType = preload("res://scripts/runtime/battle_runtime_state.gd")
const BattleRuntimeResultType = preload("res://scripts/runtime/battle_runtime_result.gd")
const BattleFormationDataType = preload("res://scripts/data/battle_formation_data.gd")
const BattleOrderDataType = preload("res://scripts/data/battle_order_data.gd")
const BattleDispatchDataType = preload("res://scripts/data/battle_dispatch_data.gd")
const WeightedGridPathfinderType = preload("res://scripts/core/weighted_grid_pathfinder.gd")

const BATTLE_GRID_SIZE: Vector2i = Vector2i(150, 150)
const BATTLE_GRID_MIN: Vector2i = Vector2i.ZERO
const BATTLE_GRID_MAX: Vector2i = BATTLE_GRID_SIZE - Vector2i.ONE
const FORMATION_CLEARANCE_CELLS: int = 5

var session: GameSession
var world_data: WorldData
var region_runtime: RegionRuntime
var generator: BattleSiteGenerator = BattleSiteGeneratorType.new()
var pathfinder: WeightedGridPathfinder = WeightedGridPathfinderType.new()

func _init(
		p_session: GameSession = null,
		p_world_data: WorldData = null,
		p_region_runtime: RegionRuntime = null
	) -> void:
	bind(p_session, p_world_data, p_region_runtime)

func bind(
		p_session: GameSession,
		p_world_data: WorldData,
		p_region_runtime: RegionRuntime
	) -> void:
	session = p_session
	world_data = p_world_data
	region_runtime = p_region_runtime

func query_debug_preview(center_global_cell: Vector2i) -> BattleSiteSnapshot:
	var attacker: BattleParticipantData = BattleParticipantData.new("test_attacker", "Army A", 1000)
	if session != null and session.party != null:
		attacker.commander_id = session.party.party_id
		attacker.commander_kind = BattleParticipantData.CommanderKind.PLAYER
	var defender: BattleParticipantData = BattleParticipantData.new("test_defender", "Army B", 800)
	return query_preview(
		center_global_cell,
		attacker,
		defender,
		BattleSiteContext.EntryDirection.SOUTH,
		BattleSiteContext.EntryDirection.NORTH
	)

func query_preview(
		center_global_cell: Vector2i,
		attacker: BattleParticipantData,
		defender: BattleParticipantData,
		attacker_entry_direction: int,
		defender_entry_direction: int,
		battle_sequence: int = 0
	) -> BattleSiteSnapshot:
	var snapshot: BattleSiteSnapshot = BattleSiteSnapshotType.new()
	if session == null or world_data == null or region_runtime == null:
		snapshot.failure_reason = BattleSiteSnapshot.FailureReason.RUNTIME_UNAVAILABLE
		return snapshot
	if session.has_travel_plan():
		snapshot.failure_reason = BattleSiteSnapshot.FailureReason.TRAVEL_IN_PROGRESS
		return snapshot
	var context: BattleSiteContext = BattleSiteContext.create(
		session.world_seed,
		center_global_cell,
		attacker,
		defender,
		attacker_entry_direction,
		defender_entry_direction,
		battle_sequence,
		session.world_time_seconds
	)
	if context == null:
		snapshot.failure_reason = BattleSiteSnapshot.FailureReason.INVALID_PARTICIPANT
		return snapshot
	var cells: Array[Dictionary] = []
	for global_cell: Vector2i in BattleSiteGenerator.footprint_global_cells(center_global_cell):
		var cell: Dictionary = _query_resolved_cell(global_cell)
		if cell.is_empty():
			snapshot.failure_reason = BattleSiteSnapshot.FailureReason.INVALID_DESTINATION
			return snapshot
		cells.append(cell)
	var center_cell: Dictionary = cells[4]
	if not bool(center_cell["passable"]):
		snapshot.failure_reason = BattleSiteSnapshot.FailureReason.IMPASSABLE
		return snapshot
	for cell: Dictionary in cells:
		if bool(cell["road"]):
			cell["road_connection_offsets"] = _road_connection_offsets(cell)
		if bool(cell["river"]):
			cell["river_connection_offsets"] = _river_connection_offsets(
				cell["global_region_cell"] as Vector2i
			)
	var generated: Dictionary = generator.generate(context, cells)
	if generated.is_empty():
		snapshot.failure_reason = BattleSiteSnapshot.FailureReason.INVALID_DESTINATION
		return snapshot
	_apply_generated(snapshot, generated)
	snapshot.success = true
	return snapshot

func begin_battle(preview: BattleSiteSnapshot) -> BattleRuntimeResult:
	var result: BattleRuntimeResult = BattleRuntimeResultType.new()
	if session == null or world_data == null or region_runtime == null:
		return result.failure(BattleRuntimeResult.Code.RUNTIME_UNAVAILABLE)
	if preview == null or not preview.has_preview() or preview.context == null:
		return result.failure(BattleRuntimeResult.Code.INVALID_BATTLE)
	var context: BattleSiteContext = preview.context
	var refreshed: BattleSiteSnapshot = query_preview(
		context.center_global_region_cell,
		context.attacker,
		context.defender,
		context.attacker_entry_direction,
		context.defender_entry_direction,
		context.battle_sequence
	)
	if not refreshed.has_preview() or refreshed.context.battle_id != context.battle_id:
		return result.failure(BattleRuntimeResult.Code.INVALID_BATTLE)
	var state: BattleRuntimeState = BattleRuntimeStateType.new(refreshed)
	_build_clearance_mask(state)
	if not _create_formations(state):
		return result.failure(BattleRuntimeResult.Code.INVALID_BATTLE)
	if not session.set_active_battle_state(state):
		return result.failure(BattleRuntimeResult.Code.INVALID_BATTLE)
	result.snapshot = state.snapshot()
	return result.succeed()

func active_snapshot() -> BattleSiteSnapshot:
	if session == null or not session.has_active_battle():
		return null
	return session.active_battle_state.snapshot()

func leave_battle() -> BattleRuntimeResult:
	var result: BattleRuntimeResult = BattleRuntimeResultType.new()
	if session == null:
		return result.failure(BattleRuntimeResult.Code.RUNTIME_UNAVAILABLE)
	if not session.has_active_battle():
		return result.failure(BattleRuntimeResult.Code.NO_ACTIVE_BATTLE)
	session.clear_active_battle()
	return result.succeed()

func issue_move(formation_id: String, target_position_m: Vector2) -> BattleRuntimeResult:
	if session == null:
		return BattleRuntimeResultType.new().failure(BattleRuntimeResult.Code.RUNTIME_UNAVAILABLE)
	return issue_fine_order(
		session.party.party_id,
		formation_id,
		BattleOrderData.FineIntent.MOVE_TO,
		target_position_m
	)

func issue_simple_order(
		source_id: String,
		target_formation_id: String,
		intent: int,
		focus_target_formation_id: String = ""
	) -> BattleRuntimeResult:
	return issue_order(
		source_id,
		target_formation_id,
		BattleOrderDataType.make_simple(
			source_id,
			target_formation_id,
			intent,
			focus_target_formation_id
		)
	)

func issue_fine_order(
		source_id: String,
		target_formation_id: String,
		intent: int,
		target_position_m: Vector2 = Vector2.ZERO,
		target_facing: Vector2 = Vector2.DOWN,
		focus_target_formation_id: String = ""
	) -> BattleRuntimeResult:
	return issue_order(
		source_id,
		target_formation_id,
		BattleOrderDataType.make_fine(
			source_id,
			target_formation_id,
			intent,
			target_position_m,
			target_facing,
			focus_target_formation_id
		)
	)

func issue_order(
		source_id: String,
		target_formation_id: String,
		order: BattleOrderData
	) -> BattleRuntimeResult:
	var result: BattleRuntimeResult = BattleRuntimeResultType.new()
	if session == null or not session.has_active_battle():
		return result.failure(BattleRuntimeResult.Code.NO_ACTIVE_BATTLE)
	if order == null or (not order.is_simple() and not order.is_fine()):
		return result.failure(BattleRuntimeResult.Code.INVALID_TARGET)
	var state: BattleRuntimeState = session.active_battle_state
	var target: BattleFormationData = state.find_formation(target_formation_id)
	if target == null:
		return result.failure(BattleRuntimeResult.Code.INVALID_FORMATION)
	var side: int = _side_for_commander(source_id, state.base_snapshot.context)
	if side < 0 or target.side != side:
		return result.failure(BattleRuntimeResult.Code.NOT_CONTROLLABLE)
	var commander_formation_id: String = str(state.commander_formation_ids.get(side, ""))
	var commander_formation: BattleFormationData = state.find_formation(commander_formation_id)
	if commander_formation == null:
		return result.failure(BattleRuntimeResult.Code.INVALID_BATTLE)
	if order.is_fine() and state.has_dispatch_for_target(target_formation_id):
		return result.failure(BattleRuntimeResult.Code.ORDER_IN_TRANSIT)
	order.source_id = source_id
	order.source_formation_id = commander_formation_id
	order.target_formation_id = target_formation_id
	order.order_id = _allocate_order_id(state, side)
	order.issued_at = state.elapsed_seconds
	if not state.add_order(order):
		return result.failure(BattleRuntimeResult.Code.INVALID_BATTLE)
	if target_formation_id == commander_formation_id:
		var direct_result: BattleRuntimeResult = _apply_order_to_formation(state, order, target)
		result.order_id = order.order_id
		result.order_state = order.state
		if not direct_result.success:
			order.state = BattleOrderData.State.FAILED
			order.failure_code = direct_result.failure_code
			result.order_state = order.state
			return result.failure(direct_result.failure_code)
		if order.state != BattleOrderData.State.DEFERRED:
			order.state = BattleOrderData.State.DELIVERED
		result.order_state = order.state
		result.formation_id = target_formation_id
		result.path = target.path.duplicate()
		result.changed = true
		state.revision += 1
		return result.succeed_with_code(BattleRuntimeResult.Code.ORDER_APPLIED)
	if order.is_simple():
		order.execute_at = state.elapsed_seconds + _command_delay(commander_formation, target)
		order.state = BattleOrderData.State.QUEUED
		state.pending_orders.append(order)
		result.order_id = order.order_id
		result.order_state = order.state
		result.cost_seconds = order.execute_at - state.elapsed_seconds
		return result.succeed_with_code(BattleRuntimeResult.Code.ORDER_QUEUED)
	return _create_dispatch(state, order, commander_formation, target)

func query_order(order_id: String) -> BattleRuntimeResult:
	var result: BattleRuntimeResult = BattleRuntimeResultType.new()
	if session == null or not session.has_active_battle():
		return result.failure(BattleRuntimeResult.Code.NO_ACTIVE_BATTLE)
	var order: BattleOrderData = session.active_battle_state.find_order(order_id)
	if order == null:
		return result.failure(BattleRuntimeResult.Code.ORDER_NOT_FOUND)
	result.order_id = order.order_id
	result.order_state = order.state
	var dispatch: BattleDispatchData = session.active_battle_state.find_dispatch(order.order_id)
	if dispatch != null:
		result.dispatch_position_m = dispatch.position_m
	match order.state:
		BattleOrderData.State.INTERCEPTED:
			return result.failure(BattleRuntimeResult.Code.MESSENGER_INTERCEPTED)
		BattleOrderData.State.TARGET_UNAVAILABLE:
			return result.failure(BattleRuntimeResult.Code.TARGET_UNAVAILABLE)
		BattleOrderData.State.FAILED:
			return result.failure(order.failure_code)
		_:
			return result.succeed()

func _allocate_order_id(state: BattleRuntimeState, side: int) -> String:
	state.order_sequence += 1
	return "%s_order_%s_%04d" % [
		state.base_snapshot.context.battle_id,
		BattleFormationData.side_code(side),
		state.order_sequence,
	]

func _side_for_commander(source_id: String, context: BattleSiteContext) -> int:
	if context == null:
		return -1
	if context.attacker.commander_id == source_id:
		return BattleFormationData.Side.ATTACKER
	if context.defender.commander_id == source_id:
		return BattleFormationData.Side.DEFENDER
	return -1

func _command_delay(
		commander_formation: BattleFormationData,
		target: BattleFormationData
	) -> float:
	return BattleRules.COMMAND_BASE_DELAY_SECONDS \
		+ commander_formation.battle_position_m.distance_to(target.battle_position_m) \
		/ BattleRules.COMMAND_SIGNAL_SPEED_MPS

func _create_dispatch(
		state: BattleRuntimeState,
		order: BattleOrderData,
		commander_formation: BattleFormationData,
		target: BattleFormationData
	) -> BattleRuntimeResult:
	var result: BattleRuntimeResult = BattleRuntimeResultType.new()
	var path_result: Dictionary = _find_path(
		_position_to_cell(commander_formation.battle_position_m),
		_position_to_cell(target.battle_position_m),
		Callable(self, "_battle_step_cost")
	)
	var path_value: Variant = path_result.get("path", [])
	if not path_value is Array or (path_value as Array).is_empty():
		order.state = BattleOrderData.State.FAILED
		order.failure_code = BattleRuntimeResult.Code.NO_MESSENGER_ROUTE
		return result.failure(BattleRuntimeResult.Code.NO_MESSENGER_ROUTE)
	var dispatch: BattleDispatchData = BattleDispatchDataType.new()
	dispatch.order_id = order.order_id
	dispatch.target_formation_id = target.formation_id
	dispatch.position_m = commander_formation.battle_position_m
	dispatch.previous_position_m = dispatch.position_m
	for cell: Variant in path_value as Array:
		if cell is Vector2i:
			dispatch.path.append(cell as Vector2i)
	dispatch.speed_mps = BattleRules.MESSENGER_SPEED_MPS
	dispatch.eta_seconds = state.elapsed_seconds + _path_seconds(
		dispatch.path,
		dispatch.speed_mps
	)
	dispatch.state = BattleOrderData.State.EN_ROUTE
	order.state = BattleOrderData.State.EN_ROUTE
	state.add_dispatch(dispatch)
	result.order_id = order.order_id
	result.order_state = order.state
	result.dispatch_position_m = dispatch.position_m
	result.cost_seconds = dispatch.eta_seconds - state.elapsed_seconds
	return result.succeed_with_code(BattleRuntimeResult.Code.DISPATCH_CREATED)

func advance_battle(seconds: float) -> BattleRuntimeResult:
	var result: BattleRuntimeResult = BattleRuntimeResultType.new()
	if session == null or not session.has_active_battle():
		return result.failure(BattleRuntimeResult.Code.NO_ACTIVE_BATTLE)
	var state: BattleRuntimeState = session.active_battle_state
	var budget: float = maxf(seconds, 0.0)
	if budget <= 0.0:
		return result.succeed()
	var changed: bool = false
	var keys: Array[String] = []
	for key: Variant in state.formations.keys():
		keys.append(str(key))
	keys.sort()
	for key: String in keys:
		var formation: BattleFormationData = state.formations[key] as BattleFormationData
		if formation == null or formation.state != BattleFormationData.State.MOVING:
			continue
		if _advance_formation(state, formation, budget):
			changed = true
	state.elapsed_seconds += budget
	if _resolve_contacts(state):
		changed = true
	if _process_pending_orders(state):
		changed = true
	if _advance_dispatches(state, budget):
		changed = true
	if changed:
		state.revision += 1
	result.changed = changed
	return result.succeed()

func _advance_formation(
		state: BattleRuntimeState,
		formation: BattleFormationData,
		budget: float
	) -> bool:
	var changed: bool = false
	var remaining: float = budget
	while remaining > 0.0 and formation.state == BattleFormationData.State.MOVING:
		if formation.path_index < 0 or formation.path_index + 1 >= formation.path.size():
			formation.clear_path()
			changed = true
			break
		var next_cell: Vector2i = formation.path[formation.path_index + 1]
		var next_position: Vector2 = _cell_to_position(next_cell)
		var next_info: Dictionary = _battle_cell_info(next_cell)
		var occupied: bool = _formation_cell_occupied(state, formation, next_position)
		if not bool(next_info.get("passable", false)) or occupied:
			formation.clear_path()
			changed = true
			break
		var current_cell: Vector2i = _position_to_cell(formation.battle_position_m)
		var direction: Vector2i = next_cell - current_cell
		var step_seconds: float = BattleRules.tactical_step_seconds(
			_battle_cell_info(current_cell),
			_battle_cell_info(next_cell),
			direction,
			formation.base_move_speed_mps
		)
		if not is_finite(step_seconds) or step_seconds <= 0.0:
			formation.clear_path()
			changed = true
			break
		formation.facing_direction = Vector2(direction).normalized()
		if remaining >= step_seconds:
			formation.battle_position_m = next_position
			formation.path_index += 1
			remaining -= step_seconds
			changed = true
			if formation.path_index + 1 >= formation.path.size():
				formation.clear_path()
		else:
			var fraction: float = remaining / step_seconds
			formation.battle_position_m = formation.battle_position_m.lerp(next_position, fraction)
			remaining = 0.0
			changed = true
	return changed

func _apply_order_to_formation(
		state: BattleRuntimeState,
		order: BattleOrderData,
		formation: BattleFormationData
	) -> BattleRuntimeResult:
	var result: BattleRuntimeResult = BattleRuntimeResultType.new()
	if formation == null:
		return result.failure(BattleRuntimeResult.Code.TARGET_UNAVAILABLE)
	if formation.autonomy_state == BattleFormationData.AutonomyState.ENGAGED:
		order.state = BattleOrderData.State.DEFERRED
		if not state.pending_orders.has(order):
			state.pending_orders.append(order)
		return result.succeed_with_code(BattleRuntimeResult.Code.ORDER_APPLIED)
	if order.is_simple():
		return _apply_simple_order(state, order, formation)
	match order.fine_intent:
		BattleOrderData.FineIntent.MOVE_TO:
			formation.intent = BattleFormationData.Intent.HOLD
			formation.intent_target_formation_id = ""
			return _start_formation_move(state, formation, order.target_position_m)
		BattleOrderData.FineIntent.SET_FACING:
			if order.target_facing.length_squared() <= 0.000001:
				return result.failure(BattleRuntimeResult.Code.INVALID_TARGET)
			formation.facing_direction = order.target_facing.normalized()
			formation.intent = BattleFormationData.Intent.HOLD
			formation.intent_target_formation_id = ""
			formation.clear_path()
			return result.succeed_with_code(BattleRuntimeResult.Code.ORDER_APPLIED)
		BattleOrderData.FineIntent.HOLD_POSITION:
			formation.intent = BattleFormationData.Intent.HOLD
			formation.intent_target_formation_id = ""
			formation.clear_path()
			return result.succeed_with_code(BattleRuntimeResult.Code.ORDER_APPLIED)
		BattleOrderData.FineIntent.FOCUS_TARGET:
			var enemy: BattleFormationData = state.find_formation(order.focus_target_formation_id)
			if enemy == null or enemy.side == formation.side:
				return result.failure(BattleRuntimeResult.Code.INVALID_TARGET)
			formation.intent = BattleFormationData.Intent.ATTACK
			formation.intent_target_formation_id = enemy.formation_id
			return _start_formation_move(state, formation, enemy.battle_position_m)
		_:
			return result.failure(BattleRuntimeResult.Code.INVALID_TARGET)

func _apply_simple_order(
		state: BattleRuntimeState,
		order: BattleOrderData,
		formation: BattleFormationData
	) -> BattleRuntimeResult:
	var result: BattleRuntimeResult = BattleRuntimeResultType.new()
	var goal: Vector2 = formation.battle_position_m
	var facing: Vector2 = formation.facing_direction.normalized()
	if facing.length_squared() <= 0.000001:
		facing = Vector2.DOWN
	var focus: BattleFormationData = state.find_formation(order.focus_target_formation_id)
	match order.simple_intent:
		BattleOrderData.SimpleIntent.ADVANCE:
			formation.intent = BattleFormationData.Intent.ADVANCE
			goal += facing * 60.0
		BattleOrderData.SimpleIntent.FALL_BACK:
			formation.intent = BattleFormationData.Intent.FALL_BACK
			goal -= facing * 60.0
		BattleOrderData.SimpleIntent.ATTACK:
			formation.intent = BattleFormationData.Intent.ATTACK
			if focus != null and focus.side != formation.side:
				formation.intent_target_formation_id = focus.formation_id
				goal = focus.battle_position_m
			else:
				goal += facing * 60.0
		BattleOrderData.SimpleIntent.WITHDRAW:
			formation.intent = BattleFormationData.Intent.WITHDRAW
			goal -= facing * 120.0
		BattleOrderData.SimpleIntent.FLANK_REAR:
			formation.intent = BattleFormationData.Intent.FLANK_REAR
			if focus != null and focus.side != formation.side:
				formation.intent_target_formation_id = focus.formation_id
				var enemy_facing: Vector2 = focus.facing_direction.normalized()
				if enemy_facing.length_squared() <= 0.000001:
					enemy_facing = Vector2.DOWN
				goal = focus.battle_position_m + enemy_facing * 40.0
			else:
				goal += facing.orthogonal() * 60.0
		_:
			return result.failure(BattleRuntimeResult.Code.INVALID_TARGET)
	if not _is_valid_target(goal):
		return result.failure(BattleRuntimeResult.Code.INVALID_TARGET)
	return _start_formation_move(state, formation, goal)

func _start_formation_move(
		state: BattleRuntimeState,
		formation: BattleFormationData,
		target_position_m: Vector2
	) -> BattleRuntimeResult:
	var result: BattleRuntimeResult = BattleRuntimeResultType.new()
	if formation == null or not _is_valid_target(target_position_m):
		return result.failure(BattleRuntimeResult.Code.INVALID_TARGET)
	var start: Vector2i = _position_to_cell(formation.battle_position_m)
	var goal: Vector2i = _position_to_cell(target_position_m)
	var path_result: Dictionary = _find_path(
		start,
		goal,
		Callable(self, "_battle_step_cost")
	)
	var path_value: Variant = path_result.get("path", [])
	if not path_value is Array or (path_value as Array).is_empty():
		return result.failure(BattleRuntimeResult.Code.NO_PATH)
	formation.path.clear()
	for cell: Variant in path_value as Array:
		if cell is Vector2i:
			formation.path.append(cell as Vector2i)
	formation.path_index = 0
	formation.target_position_m = target_position_m
	formation.state = BattleFormationData.State.MOVING if formation.path.size() > 1 \
		else BattleFormationData.State.IDLE
	if formation.path.size() > 1:
		formation.facing_direction = Vector2(formation.path[1] - formation.path[0]).normalized()
	result.formation_id = formation.formation_id
	result.path = formation.path.duplicate()
	return result.succeed_with_code(BattleRuntimeResult.Code.ORDER_APPLIED)

func _find_path(start: Vector2i, goal: Vector2i, cost: Callable) -> Dictionary:
	return pathfinder.find_path(
		start,
		goal,
		BATTLE_GRID_MIN,
		BATTLE_GRID_MAX,
		Callable(self, "_battle_cell_info"),
		cost
	)

func _process_pending_orders(state: BattleRuntimeState) -> bool:
	if state.pending_orders.is_empty():
		return false
	var changed: bool = false
	var remaining: Array[BattleOrderData] = []
	for order: BattleOrderData in state.pending_orders:
		if order == null:
			continue
		if order.state == BattleOrderData.State.QUEUED and state.elapsed_seconds < order.execute_at:
			remaining.append(order)
			continue
		var target: BattleFormationData = state.find_formation(order.target_formation_id)
		if target == null:
			order.state = BattleOrderData.State.TARGET_UNAVAILABLE
			order.failure_code = BattleRuntimeResult.Code.TARGET_UNAVAILABLE
			changed = true
			continue
		var applied: BattleRuntimeResult = _apply_order_to_formation(state, order, target)
		if not applied.success:
			order.state = BattleOrderData.State.FAILED
			order.failure_code = applied.failure_code
			changed = true
			continue
		if order.state == BattleOrderData.State.DEFERRED:
			remaining.append(order)
			continue
		order.state = BattleOrderData.State.DELIVERED
		changed = true
	state.pending_orders = remaining
	return changed

func _advance_dispatches(state: BattleRuntimeState, budget: float) -> bool:
	var changed: bool = false
	var keys: Array[String] = []
	for key: Variant in state.dispatches.keys():
		keys.append(str(key))
	keys.sort()
	for key: String in keys:
		var dispatch: BattleDispatchData = state.dispatches[key] as BattleDispatchData
		if dispatch == null or dispatch.state != BattleOrderData.State.EN_ROUTE:
			continue
		var order: BattleOrderData = state.find_order(dispatch.order_id)
		if order == null:
			dispatch.state = BattleOrderData.State.FAILED
			changed = true
			continue
		var target: BattleFormationData = state.find_formation(dispatch.target_formation_id)
		if target == null:
			order.state = BattleOrderData.State.TARGET_UNAVAILABLE
			order.failure_code = BattleRuntimeResult.Code.TARGET_UNAVAILABLE
			dispatch.state = BattleOrderData.State.TARGET_UNAVAILABLE
			changed = true
			continue
		var source: BattleFormationData = state.find_formation(order.source_formation_id)
		var enemy_side: int = BattleFormationData.Side.DEFENDER if source == null \
			or source.side == BattleFormationData.Side.ATTACKER \
			else BattleFormationData.Side.ATTACKER
		var interceptor: BattleFormationData = _find_interceptor(
			state,
			dispatch.position_m,
			dispatch.position_m,
			enemy_side
		)
		if interceptor != null:
			_mark_dispatch_intercepted(dispatch, order, interceptor)
			changed = true
			continue
		var remaining: float = budget
		while remaining > 0.0 and dispatch.state == BattleOrderData.State.EN_ROUTE:
			if dispatch.path_index + 1 >= dispatch.path.size():
				_complete_dispatch(state, dispatch, order, target)
				changed = true
				break
			var next_cell: Vector2i = dispatch.path[dispatch.path_index + 1]
			var current_cell: Vector2i = _position_to_cell(dispatch.position_m)
			var direction: Vector2i = next_cell - current_cell
			var step_seconds: float = BattleRules.tactical_step_seconds(
				_battle_cell_info(current_cell),
				_battle_cell_info(next_cell),
				direction,
				dispatch.speed_mps
			)
			if not is_finite(step_seconds) or step_seconds <= 0.0:
				dispatch.state = BattleOrderData.State.FAILED
				order.state = BattleOrderData.State.FAILED
				order.failure_code = BattleRuntimeResult.Code.NO_MESSENGER_ROUTE
				changed = true
				break
			var next_position: Vector2 = _cell_to_position(next_cell)
			var previous: Vector2 = dispatch.position_m
			if remaining >= step_seconds:
				dispatch.position_m = next_position
				dispatch.path_index += 1
				remaining -= step_seconds
			else:
				dispatch.position_m = previous.lerp(next_position, remaining / step_seconds)
				remaining = 0.0
			dispatch.previous_position_m = previous
			interceptor = _find_interceptor(state, previous, dispatch.position_m, enemy_side)
			changed = true
			if interceptor != null:
				_mark_dispatch_intercepted(dispatch, order, interceptor)
				break
		if dispatch.state == BattleOrderData.State.EN_ROUTE \
				and dispatch.path_index + 1 >= dispatch.path.size():
			_complete_dispatch(state, dispatch, order, target)
			changed = true
	return changed

func _complete_dispatch(
		state: BattleRuntimeState,
		dispatch: BattleDispatchData,
		order: BattleOrderData,
		target: BattleFormationData
	) -> void:
	dispatch.state = BattleOrderData.State.DELIVERED
	var applied: BattleRuntimeResult = _apply_order_to_formation(state, order, target)
	if applied.success:
		if order.state != BattleOrderData.State.DEFERRED:
			order.state = BattleOrderData.State.DELIVERED
	else:
		order.state = BattleOrderData.State.FAILED
		order.failure_code = applied.failure_code

func _mark_dispatch_intercepted(
		dispatch: BattleDispatchData,
		order: BattleOrderData,
		interceptor: BattleFormationData
	) -> void:
	dispatch.state = BattleOrderData.State.INTERCEPTED
	dispatch.intercepted_by_formation_id = interceptor.formation_id
	dispatch.intercepted_at_m = dispatch.position_m
	order.state = BattleOrderData.State.INTERCEPTED
	order.failure_code = BattleRuntimeResult.Code.MESSENGER_INTERCEPTED

func _find_interceptor(
		state: BattleRuntimeState,
		segment_start: Vector2,
		segment_end: Vector2,
		enemy_side: int
	) -> BattleFormationData:
	var best: BattleFormationData = null
	var best_distance: float = INF
	var ids: Array[String] = []
	for key: Variant in state.formations.keys():
		ids.append(str(key))
	ids.sort()
	for id: String in ids:
		var formation: BattleFormationData = state.formations[id] as BattleFormationData
		if formation == null or formation.side != enemy_side:
			continue
		var distance: float = _distance_to_segment(
			formation.battle_position_m,
			segment_start,
			segment_end
		)
		var radius: float = BattleRules.MESSENGER_INTERCEPT_RADIUS_M \
			+ maxf(formation.width_m, formation.depth_m) * 0.5
		if distance > radius:
			continue
		if best == null or distance < best_distance - 0.001 \
			or (is_equal_approx(distance, best_distance) and id < best.formation_id):
			best = formation
			best_distance = distance
	return best

func _distance_to_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment: Vector2 = end - start
	var length_squared: float = segment.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(start)
	var t: float = clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * t)

func _path_seconds(path: Array[Vector2i], speed_mps: float) -> float:
	var total: float = 0.0
	for index: int in range(path.size() - 1):
		var current: Vector2i = path[index]
		var next: Vector2i = path[index + 1]
		var step: float = BattleRules.tactical_step_seconds(
			_battle_cell_info(current),
			_battle_cell_info(next),
			next - current,
			speed_mps
		)
		if not is_finite(step):
			return INF
		total += step
	return total

func _resolve_contacts(state: BattleRuntimeState) -> bool:
	var changed: bool = false
	var keys: Array[String] = []
	for key: Variant in state.formations.keys():
		keys.append(str(key))
	keys.sort()
	for key: String in keys:
		var formation: BattleFormationData = state.formations[key] as BattleFormationData
		if formation == null:
			continue
		var enemy: BattleFormationData = _nearest_contact(state, formation)
		if enemy == null:
			if formation.autonomy_state != BattleFormationData.AutonomyState.NONE:
				formation.autonomy_state = BattleFormationData.AutonomyState.NONE
				formation.contact_target_id = ""
				changed = true
			continue
		if formation.autonomy_state != BattleFormationData.AutonomyState.ENGAGED \
			or formation.contact_target_id != enemy.formation_id:
			formation.autonomy_state = BattleFormationData.AutonomyState.ENGAGED
			formation.contact_target_id = enemy.formation_id
			_apply_captain_decision(state, formation, enemy)
			changed = true
	return changed

func _nearest_contact(
		state: BattleRuntimeState,
		formation: BattleFormationData
	) -> BattleFormationData:
	var best: BattleFormationData = null
	var best_distance: float = INF
	var ids: Array[String] = []
	for key: Variant in state.formations.keys():
		ids.append(str(key))
	ids.sort()
	for id: String in ids:
		var other: BattleFormationData = state.formations[id] as BattleFormationData
		if other == null or other.side == formation.side:
			continue
		var contact_distance: float = maxf(formation.width_m, formation.depth_m) * 0.5 \
			+ maxf(other.width_m, other.depth_m) * 0.5 \
			+ BattleRules.FORMATION_CONTACT_RADIUS_M
		var distance: float = formation.battle_position_m.distance_to(other.battle_position_m)
		if distance > contact_distance:
			continue
		if best == null or distance < best_distance - 0.001 \
			or (is_equal_approx(distance, best_distance) and id < best.formation_id):
			best = other
			best_distance = distance
	return best

func _apply_captain_decision(
		state: BattleRuntimeState,
		formation: BattleFormationData,
		enemy: BattleFormationData
	) -> void:
	match formation.intent:
		BattleFormationData.Intent.FALL_BACK, BattleFormationData.Intent.WITHDRAW:
			var away: Vector2 = formation.battle_position_m - enemy.battle_position_m
			if away.length_squared() > 0.000001:
				_start_formation_move(
					state,
					formation,
					formation.battle_position_m + away.normalized() * 50.0
				)
			else:
				formation.clear_path()
		BattleFormationData.Intent.ATTACK, BattleFormationData.Intent.ADVANCE, \
			BattleFormationData.Intent.FLANK_REAR:
			formation.intent = BattleFormationData.Intent.ATTACK
			formation.intent_target_formation_id = enemy.formation_id
			formation.clear_path()
		_:
			formation.clear_path()

func _create_formations(state: BattleRuntimeState) -> bool:
	_create_side_formations(
		state,
		state.base_snapshot.attacker_deployment,
		BattleFormationData.Side.ATTACKER
	)
	_create_side_formations(
		state,
		state.base_snapshot.defender_deployment,
		BattleFormationData.Side.DEFENDER
	)
	return state.commander_formation_ids.has(BattleFormationData.Side.ATTACKER) \
		and state.commander_formation_ids.has(BattleFormationData.Side.DEFENDER)

func _create_side_formations(
		state: BattleRuntimeState,
		deployment: Dictionary,
		side: int
	) -> void:
	var deployed: int = int(deployment.get("initial_deployed_personnel", 0))
	var positions: Array = deployment.get("marker_positions_meters", []) as Array
	var facing: Vector2 = deployment.get("facing", Vector2.DOWN) as Vector2
	var context: BattleSiteContext = state.base_snapshot.context
	var participant: BattleParticipantData = context.attacker if side == BattleFormationData.Side.ATTACKER \
		else context.defender
	for index: int in range(positions.size()):
		var position: Vector2 = positions[index] as Vector2
		var personnel: int = mini(
			BattleFormationData.DEFAULT_PERSONNEL,
			maxi(deployed - index * BattleFormationData.DEFAULT_PERSONNEL, 0)
		)
		if personnel <= 0:
			continue
		var id: String = "%s_%s_%03d" % [
			state.base_snapshot.context.battle_id,
			BattleFormationData.side_code(side),
			index,
		]
		var formation: BattleFormationData = BattleFormationDataType.new(
			id,
			side,
			personnel,
			position
		)
		formation.facing_direction = facing
		formation.is_commander_formation = index == participant.commander_formation_index
		formation.captain_id = "%s_captain" % id
		state.add_formation(formation)
		if formation.is_commander_formation:
			state.commander_formation_ids[side] = id

func _build_clearance_mask(state: BattleRuntimeState) -> void:
	state.clearance_blocked.resize(BATTLE_GRID_SIZE.x * BATTLE_GRID_SIZE.y)
	for y: int in range(BATTLE_GRID_SIZE.y):
		for x: int in range(BATTLE_GRID_SIZE.x):
			var cell: Vector2i = Vector2i(x, y)
			var blocked: bool = false
			for offset_y: int in range(-FORMATION_CLEARANCE_CELLS, FORMATION_CLEARANCE_CELLS + 1):
				for offset_x: int in range(-FORMATION_CLEARANCE_CELLS, FORMATION_CLEARANCE_CELLS + 1):
					if Vector2i(offset_x, offset_y).length_squared() > FORMATION_CLEARANCE_CELLS * FORMATION_CLEARANCE_CELLS:
						continue
					var neighbor: Vector2i = cell + Vector2i(offset_x, offset_y)
					if not _contains_battle_cell(neighbor) or not _base_cell_passable(state, neighbor):
						blocked = true
						break
				if blocked:
					break
			state.clearance_blocked[y * BATTLE_GRID_SIZE.x + x] = 1 if blocked else 0

func _battle_cell_info(cell: Vector2i) -> Dictionary:
	if session == null or not session.has_active_battle() or not _contains_battle_cell(cell):
		return {"passable": false}
	var state: BattleRuntimeState = session.active_battle_state
	var info: Dictionary = _base_cell_info(state, cell)
	if info.is_empty():
		return {"passable": false}
	var index: int = cell.y * BATTLE_GRID_SIZE.x + cell.x
	if index < state.clearance_blocked.size() and state.clearance_blocked[index] != 0:
		info["passable"] = false
	return info

func _base_cell_info(state: BattleRuntimeState, cell: Vector2i) -> Dictionary:
	var tile: Vector2i = Vector2i(floori(float(cell.x) / 50.0), floori(float(cell.y) / 50.0))
	var layout_index: int = tile.y * 3 + tile.x
	if layout_index < 0 or layout_index >= state.base_snapshot.site_layouts.size():
		return {}
	var layout: SiteLayoutData = state.base_snapshot.site_layouts[layout_index]
	var local_cell: Vector2i = Vector2i(posmod(cell.x, 50), posmod(cell.y, 50))
	var flags: int = layout.navigation_flags_at(local_cell)
	var river: bool = (flags & SiteLayoutData.NAV_RIVER) != 0
	var road: bool = (flags & SiteLayoutData.NAV_ROAD) != 0
	var crossing: bool = layout.river_crossing and (flags & SiteLayoutData.NAV_CROSSING) != 0
	return {
		"passable": TravelCostConfig.is_passable(layout.terrain_type, river, crossing),
		"terrain_type": layout.terrain_type,
		"road": road,
		"river": river,
		"river_crossing": crossing,
	}

func _base_cell_passable(state: BattleRuntimeState, cell: Vector2i) -> bool:
	var info: Dictionary = _base_cell_info(state, cell)
	return not info.is_empty() and bool(info.get("passable", false))

func _battle_step_cost(
		_current: Vector2i,
		_next: Vector2i,
		direction: Vector2i,
		current_info: Dictionary,
		next_info: Dictionary
	) -> float:
	return BattleRules.tactical_step_seconds(
		current_info,
		next_info,
		direction,
		BattleFormationData.DEFAULT_MOVE_SPEED_MPS
	)

func _formation_target_occupied(
		state: BattleRuntimeState,
		formation: BattleFormationData,
		target_position_m: Vector2
	) -> bool:
	for other: Variant in state.formations.values():
		if other is BattleFormationData \
			and (other as BattleFormationData).formation_id != formation.formation_id \
			and (other as BattleFormationData).battle_position_m.distance_to(target_position_m) \
			< minf(formation.width_m, formation.depth_m):
			return true
	return false

func _formation_cell_occupied(
		state: BattleRuntimeState,
		formation: BattleFormationData,
		position_m: Vector2
	) -> bool:
	for other: Variant in state.formations.values():
		if other is BattleFormationData \
			and (other as BattleFormationData).formation_id != formation.formation_id \
			and (other as BattleFormationData).battle_position_m.distance_to(position_m) \
			< minf(formation.width_m, formation.depth_m):
			return true
	return false

func _is_valid_target(position_m: Vector2) -> bool:
	return position_m.x >= 0.0 and position_m.y >= 0.0 \
		and position_m.x < float(BATTLE_GRID_SIZE.x * SiteLayoutData.CELL_SIZE_METERS) \
		and position_m.y < float(BATTLE_GRID_SIZE.y * SiteLayoutData.CELL_SIZE_METERS)

func _position_to_cell(position_m: Vector2) -> Vector2i:
	return Vector2i(
		clampi(floori(position_m.x / float(SiteLayoutData.CELL_SIZE_METERS)), 0, BATTLE_GRID_MAX.x),
		clampi(floori(position_m.y / float(SiteLayoutData.CELL_SIZE_METERS)), 0, BATTLE_GRID_MAX.y)
	)

func _cell_to_position(cell: Vector2i) -> Vector2:
	return Vector2(cell) * float(SiteLayoutData.CELL_SIZE_METERS) \
		+ Vector2.ONE * float(SiteLayoutData.CELL_SIZE_METERS) * 0.5

func _contains_battle_cell(cell: Vector2i) -> bool:
	return cell.x >= BATTLE_GRID_MIN.x and cell.y >= BATTLE_GRID_MIN.y \
		and cell.x <= BATTLE_GRID_MAX.x and cell.y <= BATTLE_GRID_MAX.y

func _query_resolved_cell(global_cell: Vector2i) -> Dictionary:
	var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(global_cell)
	var world_cell: Vector2i = converted["world_cell"] as Vector2i
	var region_cell: Vector2i = converted["region_cell"] as Vector2i
	if not world_data.is_valid_world_cell(world_cell):
		return {}
	var resolver: RegionStateResolver = region_runtime.query_region(world_cell)
	if resolver == null or not resolver.is_valid():
		return {}
	var terrain_type: int = resolver.get_terrain(region_cell)
	var road: bool = resolver.has_road(region_cell)
	var river: bool = resolver.has_river(region_cell)
	var river_crossing: bool = resolver.has_river_crossing(region_cell)
	return {
		"global_region_cell": global_cell,
		"world_cell": world_cell,
		"region_cell": region_cell,
		"terrain_type": terrain_type,
		"elevation": resolver.get_elevation(region_cell),
		"moisture": resolver.get_moisture(region_cell),
		"river_strength": resolver.get_river_strength(region_cell),
		"river": river,
		"road": road,
		"river_crossing": river_crossing,
		"passable": TravelCostConfig.is_passable(terrain_type, river, river_crossing),
		"road_connection_offsets": [],
		"river_connection_offsets": [],
		"resolver": resolver,
	}

func _road_connection_offsets(cell: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var resolver: RegionStateResolver = cell["resolver"] as RegionStateResolver
	var overlay: RegionRoadOverlay = resolver.base_roads if resolver != null else null
	var region_cell: Vector2i = cell["region_cell"] as Vector2i
	var global_cell: Vector2i = cell["global_region_cell"] as Vector2i
	if overlay == null:
		return result
	for route_id: String in overlay.get_route_ids(region_cell):
		if not resolver.is_feature_active(route_id):
			continue
		var route: WorldRoadRoute = overlay.get_route(route_id)
		if route == null:
			continue
		for index: int in range(route.path.size()):
			if route.path[index] != global_cell:
				continue
			if index > 0:
				_append_unique_offset(result, route.path[index - 1] - global_cell)
			if index + 1 < route.path.size():
				_append_unique_offset(result, route.path[index + 1] - global_cell)
	result.sort_custom(Callable(self, "_offset_less"))
	return result

func _river_connection_offsets(global_cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			var offset: Vector2i = Vector2i(offset_x, offset_y)
			if offset == Vector2i.ZERO:
				continue
			var neighbor: Dictionary = _query_resolved_cell(global_cell + offset)
			if not neighbor.is_empty() and bool(neighbor["river"]):
				result.append(offset)
	result.sort_custom(Callable(self, "_offset_less"))
	return result

func _append_unique_offset(result: Array[Vector2i], delta: Vector2i) -> void:
	var offset: Vector2i = Vector2i(clampi(delta.x, -1, 1), clampi(delta.y, -1, 1))
	if offset != Vector2i.ZERO and not result.has(offset):
		result.append(offset)

func _apply_generated(snapshot: BattleSiteSnapshot, generated: Dictionary) -> void:
	snapshot.context = generated["context"] as BattleSiteContext
	var generated_layouts: Array = generated.get("site_layouts", []) as Array
	snapshot.site_layouts.clear()
	for value: Variant in generated_layouts:
		if value is SiteLayoutData:
			snapshot.site_layouts.append((value as SiteLayoutData).copy())
	snapshot.footprint_cells = (generated["footprint_cells"] as Array[Dictionary]).duplicate(true)
	snapshot.size_meters = generated["size_meters"] as Vector2
	snapshot.bounds_meters = generated["bounds_meters"] as Rect2
	snapshot.center_cell = (generated["center_cell"] as Dictionary).duplicate(true)
	snapshot.center_terrain = int(generated["center_terrain"])
	snapshot.attacker_deployment = (generated["attacker_deployment"] as Dictionary).duplicate(true)
	snapshot.defender_deployment = (generated["defender_deployment"] as Dictionary).duplicate(true)
	snapshot.terrain_debug_representation = str(generated["terrain_debug_representation"])
	snapshot.terrain_hash = str(generated["terrain_hash"])
	snapshot.preview_hash = str(generated["preview_hash"])

func _offset_less(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
