class_name BattlePreviewRuntime
extends RefCounted

const BattleSiteSnapshotType = preload("res://scripts/runtime/battle_site_snapshot.gd")
const BattleSiteGeneratorType = preload("res://scripts/core/battle_site_generator.gd")
const BattleRuntimeStateType = preload("res://scripts/runtime/battle_runtime_state.gd")
const BattleRuntimeResultType = preload("res://scripts/runtime/battle_runtime_result.gd")
const BattleFormationDataType = preload("res://scripts/data/battle_formation_data.gd")
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
	return query_preview(
		center_global_cell,
		BattleParticipantData.new("test_attacker", "Army A", 1000),
		BattleParticipantData.new("test_defender", "Army B", 800),
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
	_create_formations(state)
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
	var result: BattleRuntimeResult = BattleRuntimeResultType.new()
	if session == null or not session.has_active_battle():
		return result.failure(BattleRuntimeResult.Code.NO_ACTIVE_BATTLE)
	var state: BattleRuntimeState = session.active_battle_state
	var formation: BattleFormationData = state.find_formation(formation_id)
	if formation == null:
		return result.failure(BattleRuntimeResult.Code.INVALID_FORMATION)
	result.formation_id = formation_id
	if not formation.is_controllable():
		return result.failure(BattleRuntimeResult.Code.NOT_CONTROLLABLE)
	if not _is_valid_target(target_position_m):
		return result.failure(BattleRuntimeResult.Code.INVALID_TARGET)
	if _formation_target_occupied(state, formation, target_position_m):
		return result.failure(BattleRuntimeResult.Code.OCCUPIED)
	var start: Vector2i = _position_to_cell(formation.battle_position_m)
	var goal: Vector2i = _position_to_cell(target_position_m)
	var path_result: Dictionary = pathfinder.find_path(
		start,
		goal,
		BATTLE_GRID_MIN,
		BATTLE_GRID_MAX,
		Callable(self, "_battle_cell_info"),
		Callable(self, "_battle_step_cost"),
		0.01
	)
	var path_value: Variant = path_result.get("path", [])
	if not path_value is Array or (path_value as Array).is_empty():
		return result.failure(BattleRuntimeResult.Code.NO_PATH)
	formation.path.clear()
	for cell: Variant in path_value as Array:
		if cell is Vector2i:
			formation.path.append(cell as Vector2i)
	formation.path_index = 0
	formation.target_position_m = _cell_to_position(goal)
	formation.state = BattleFormationData.State.MOVING if formation.path.size() > 1 \
		else BattleFormationData.State.IDLE
	state.revision += 1
	result.path = formation.path.duplicate()
	result.cost_seconds = float(path_result.get("cost", 0.0))
	result.changed = true
	return result.succeed()

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

func _create_formations(state: BattleRuntimeState) -> void:
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

func _create_side_formations(
		state: BattleRuntimeState,
		deployment: Dictionary,
		side: int
	) -> void:
	var deployed: int = int(deployment.get("initial_deployed_personnel", 0))
	var positions: Array = deployment.get("marker_positions_meters", []) as Array
	var facing: Vector2 = deployment.get("facing", Vector2.DOWN) as Vector2
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
		state.add_formation(formation)

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
