class_name BattlePreviewRuntime
extends RefCounted

const BattleSiteSnapshotType = preload("res://scripts/runtime/battle_site_snapshot.gd")
const BattleSiteGeneratorType = preload("res://scripts/core/battle_site_generator.gd")

var session: GameSession
var world_data: WorldData
var region_runtime: RegionRuntime
var generator: BattleSiteGenerator = BattleSiteGeneratorType.new()

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
