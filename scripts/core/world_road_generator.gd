class_name WorldRoadGenerator
extends RefCounted

const GENERATION_VERSION: int = 2

# These are global Region Cells: 1 cell = 100m.
const ROAD_CONNECTION_RADIUS_CELLS: int = 300
const ROAD_PATH_MARGIN_CELLS: int = 48
const ROAD_PATH_FALLBACK_MARGIN_CELLS: int = 96
const ROAD_PATH_MAX_EXPANSIONS: int = 300_000
const ROAD_QUERY_SOURCE_PADDING_CELLS: int = ROAD_CONNECTION_RADIUS_CELLS + ROAD_PATH_MARGIN_CELLS
const ROAD_QUERY_POOL_PADDING_CELLS: int = ROAD_CONNECTION_RADIUS_CELLS * 2 + ROAD_PATH_MARGIN_CELLS
# ponytail: bounded POI scan keeps the lazy query simple; add a spatial index when density makes it measurable.

const MAX_VILLAGE_CONNECTIONS: int = 2
const MAX_TOWN_CONNECTIONS: int = 4
const MAX_CASTLE_CONNECTIONS: int = 3

var terrain_generator: RegionTerrainGenerator
var macro_sampler: WorldMacroTerrainSampler
var poi_provider: Callable
var grid_pathfinder: WeightedGridPathfinder = WeightedGridPathfinder.new()
var path_world_seed: int = 0
var path_sample_cache: Dictionary = {}
var graph_cache: Dictionary = {}
var overlay_cache: Dictionary = {}
var route_cache: Dictionary = {}

func _init(p_terrain_generator: RegionTerrainGenerator, p_poi_provider: Callable) -> void:
	terrain_generator = p_terrain_generator
	macro_sampler = terrain_generator.macro_sampler
	poi_provider = p_poi_provider

func get_roads_for_region(world_cell: Vector2i, world_seed: int) -> RegionRoadOverlay:
	var cache_key: String = _region_cache_key(world_cell, world_seed)
	var cached: Variant = overlay_cache.get(cache_key, null)
	if cached is RegionRoadOverlay:
		return cached as RegionRoadOverlay

	var overlay: RegionRoadOverlay = RegionRoadOverlay.new()
	var global_min: Vector2i = _region_global_min(world_cell)
	var global_max: Vector2i = global_min + Vector2i(
		WorldCoordinates.REGION_GRID_SIZE - 1,
		WorldCoordinates.REGION_GRID_SIZE - 1
	)
	for route: WorldRoadRoute in get_route_edges_for_region(world_cell, world_seed):
		if not _route_may_reach_region(route, global_min, global_max):
			continue
		_ensure_route_path(route, world_seed)
		if not route.path_generated or route.path.is_empty():
			continue
		for global_cell: Vector2i in route.path:
			if not _contains(global_min, global_max, global_cell):
				continue
			var region_cell: Vector2i = global_cell - global_min
			var cell_flags: int = RegionRoadOverlay.ROAD
			if route.river_crossing_cells.has(global_cell):
				cell_flags |= RegionRoadOverlay.RIVER_CROSSING
			overlay.add_route_cell(region_cell, cell_flags, route)
	overlay_cache[cache_key] = overlay
	return overlay

func get_route_edges_for_region(world_cell: Vector2i, world_seed: int) -> Array[WorldRoadRoute]:
	var cache_key: String = _region_cache_key(world_cell, world_seed)
	var cached: Variant = graph_cache.get(cache_key, null)
	if cached is Array:
		return _copy_routes(cached as Array)

	var global_min: Vector2i = _region_global_min(world_cell)
	var global_max: Vector2i = global_min + Vector2i(
		WorldCoordinates.REGION_GRID_SIZE - 1,
		WorldCoordinates.REGION_GRID_SIZE - 1
	)
	var pool: Array[WorldPOIData] = _collect_settlements(
		world_seed,
		global_min - Vector2i.ONE * ROAD_QUERY_POOL_PADDING_CELLS,
		global_max + Vector2i.ONE * ROAD_QUERY_POOL_PADDING_CELLS
	)
	var sources: Array[WorldPOIData] = []
	var source_min: Vector2i = global_min - Vector2i.ONE * ROAD_QUERY_SOURCE_PADDING_CELLS
	var source_max: Vector2i = global_max + Vector2i.ONE * ROAD_QUERY_SOURCE_PADDING_CELLS
	for poi: WorldPOIData in pool:
		if _contains(source_min, source_max, poi.global_region_cell):
			sources.append(poi)
	var routes: Array[WorldRoadRoute] = _build_route_graph(world_seed, sources, pool)
	graph_cache[cache_key] = routes
	return _copy_routes(routes)

func clear_cache() -> void:
	graph_cache.clear()
	overlay_cache.clear()
	route_cache.clear()

static func stable_route_id(poi_id_a: String, poi_id_b: String) -> String:
	var first: String = poi_id_a
	var second: String = poi_id_b
	if second < first:
		var swap: String = first
		first = second
		second = swap
	return "road_%s_%s" % [first, second]

func _build_route_graph(
		world_seed: int,
		sources: Array[WorldPOIData],
		pool: Array[WorldPOIData]
	) -> Array[WorldRoadRoute]:
	var routes: Array[WorldRoadRoute] = []
	var edge_keys: Dictionary = {}
	var degree: Dictionary = {}
	for source: WorldPOIData in sources:
		degree[source.poi_id] = 0

	for source: WorldPOIData in sources:
		var candidates: Array[Dictionary] = _rank_neighbors(source, pool)
		var connection_limit: int = _max_connections(source.poi_type)
		var selected: int = 0
		for entry: Dictionary in candidates:
			if selected >= connection_limit:
				break
			var candidate: WorldPOIData = entry["poi"] as WorldPOIData
			var edge_key: String = stable_route_id(source.poi_id, candidate.poi_id)
			if edge_keys.has(edge_key):
				continue
			edge_keys[edge_key] = true
			routes.append(_get_or_create_route(world_seed, source, candidate))
			degree[source.poi_id] = int(degree.get(source.poi_id, 0)) + 1
			degree[candidate.poi_id] = int(degree.get(candidate.poi_id, 0)) + 1
			selected += 1

	# A nearby settlement that had no outgoing choice gets one deterministic fallback.
	for source: WorldPOIData in sources:
		if int(degree.get(source.poi_id, 0)) > 0:
			continue
		var fallback: Array[Dictionary] = _rank_neighbors(source, pool)
		for entry: Dictionary in fallback:
			var candidate: WorldPOIData = entry["poi"] as WorldPOIData
			var edge_key: String = stable_route_id(source.poi_id, candidate.poi_id)
			if edge_keys.has(edge_key):
				continue
			edge_keys[edge_key] = true
			routes.append(_get_or_create_route(world_seed, source, candidate))
			degree[source.poi_id] = 1
			degree[candidate.poi_id] = int(degree.get(candidate.poi_id, 0)) + 1
			break

	routes.sort_custom(Callable(self, "_route_less"))
	return routes

func _rank_neighbors(source: WorldPOIData, pool: Array[WorldPOIData]) -> Array[Dictionary]:
	var ranked: Array[Dictionary] = []
	var radius_squared: int = ROAD_CONNECTION_RADIUS_CELLS * ROAD_CONNECTION_RADIUS_CELLS
	for candidate: WorldPOIData in pool:
		if candidate.poi_id == source.poi_id:
			continue
		var delta: Vector2i = candidate.global_region_cell - source.global_region_cell
		var distance_squared: int = delta.x * delta.x + delta.y * delta.y
		if distance_squared > radius_squared:
			continue
		var distance: float = sqrt(float(distance_squared))
		var type_rank: int = _type_preference_rank(source.poi_type, candidate.poi_type)
		var score: float = distance + float(type_rank * 24) - float(candidate.importance * 5)
		ranked.append({
			"poi": candidate,
			"score": score,
			"type_rank": type_rank,
		})
	ranked.sort_custom(Callable(self, "_neighbor_less"))
	return ranked

func _neighbor_less(a: Dictionary, b: Dictionary) -> bool:
	var score_a: float = float(a["score"])
	var score_b: float = float(b["score"])
	if not is_equal_approx(score_a, score_b):
		return score_a < score_b
	var type_a: int = int(a["type_rank"])
	var type_b: int = int(b["type_rank"])
	if type_a != type_b:
		return type_a < type_b
	var poi_a: WorldPOIData = a["poi"] as WorldPOIData
	var poi_b: WorldPOIData = b["poi"] as WorldPOIData
	if poi_a.importance != poi_b.importance:
		return poi_a.importance > poi_b.importance
	return poi_a.poi_id < poi_b.poi_id

func _route_less(a: WorldRoadRoute, b: WorldRoadRoute) -> bool:
	return a.route_id < b.route_id

func _type_preference_rank(source_type: int, candidate_type: int) -> int:
	match source_type:
		WorldPOIType.VILLAGE:
			if candidate_type == WorldPOIType.TOWN:
				return 0
			if candidate_type == WorldPOIType.CASTLE:
				return 1
			return 2
		WorldPOIType.TOWN:
			if candidate_type == WorldPOIType.TOWN:
				return 0
			if candidate_type == WorldPOIType.CASTLE:
				return 1
			return 2
		WorldPOIType.CASTLE:
			if candidate_type == WorldPOIType.TOWN:
				return 0
			if candidate_type == WorldPOIType.VILLAGE:
				return 1
			return 2
		_:
			return 3

func _max_connections(poi_type: int) -> int:
	match poi_type:
		WorldPOIType.VILLAGE:
			return MAX_VILLAGE_CONNECTIONS
		WorldPOIType.TOWN:
			return MAX_TOWN_CONNECTIONS
		WorldPOIType.CASTLE:
			return MAX_CASTLE_CONNECTIONS
		_:
			return 0

func _get_or_create_route(
		world_seed: int,
		poi_a: WorldPOIData,
		poi_b: WorldPOIData
	) -> WorldRoadRoute:
	var first: WorldPOIData = poi_a
	var second: WorldPOIData = poi_b
	if second.poi_id < first.poi_id:
		var swap: WorldPOIData = first
		first = second
		second = swap
	var route_id: String = stable_route_id(first.poi_id, second.poi_id)
	var cache_key: String = "%d|%d|%s" % [world_seed, GENERATION_VERSION, route_id]
	var cached: Variant = route_cache.get(cache_key, null)
	if cached is WorldRoadRoute:
		return cached as WorldRoadRoute
	var route: WorldRoadRoute = WorldRoadRoute.new(
		route_id,
		first.poi_id,
		second.poi_id,
		first.global_region_cell,
		second.global_region_cell
	)
	route_cache[cache_key] = route
	return route

func _ensure_route_path(route: WorldRoadRoute, world_seed: int) -> void:
	if route.path_generated:
		return
	var result: Dictionary = _find_path_with_fallback(
		world_seed,
		route.start_global_cell,
		route.end_global_cell
	)
	var result_path: Variant = result.get("path", [])
	if result_path is Array:
		for cell: Variant in result_path:
			if cell is Vector2i:
				route.path.append(cell as Vector2i)
	var crossings: Variant = result.get("river_crossing_cells", [])
	if crossings is Array:
		for cell: Variant in crossings:
			if cell is Vector2i:
				route.river_crossing_cells.append(cell as Vector2i)
	route.requires_bridge = not route.river_crossing_cells.is_empty()
	route.estimated_cost = float(result.get("cost", 0.0))
	route.path_generated = true

func _route_may_reach_region(
		route: WorldRoadRoute,
		global_min: Vector2i,
		global_max: Vector2i
	) -> bool:
	var route_min: Vector2i = Vector2i(
		mini(route.start_global_cell.x, route.end_global_cell.x) - ROAD_PATH_FALLBACK_MARGIN_CELLS,
		mini(route.start_global_cell.y, route.end_global_cell.y) - ROAD_PATH_FALLBACK_MARGIN_CELLS
	)
	var route_max: Vector2i = Vector2i(
		maxi(route.start_global_cell.x, route.end_global_cell.x) + ROAD_PATH_FALLBACK_MARGIN_CELLS,
		maxi(route.start_global_cell.y, route.end_global_cell.y) + ROAD_PATH_FALLBACK_MARGIN_CELLS
	)
	return not (
		route_max.x < global_min.x
		or route_min.x > global_max.x
		or route_max.y < global_min.y
		or route_min.y > global_max.y
	)

func _find_path_with_fallback(world_seed: int, start: Vector2i, goal: Vector2i) -> Dictionary:
	var result: Dictionary = _find_path_in_bounds(
		world_seed,
		start,
		goal,
		ROAD_PATH_MARGIN_CELLS
	)
	var path: Variant = result.get("path", [])
	if path is Array and not (path as Array).is_empty():
		return result
	return _find_path_in_bounds(
		world_seed,
		start,
		goal,
		ROAD_PATH_FALLBACK_MARGIN_CELLS
	)

func _find_path_in_bounds(
		world_seed: int,
		start: Vector2i,
		goal: Vector2i,
		margin: int
	) -> Dictionary:
	var bounds_min: Vector2i = Vector2i(
		mini(start.x, goal.x) - margin,
		mini(start.y, goal.y) - margin
	)
	var bounds_max: Vector2i = Vector2i(
		maxi(start.x, goal.x) + margin,
		maxi(start.y, goal.y) + margin
	)
	path_world_seed = world_seed
	path_sample_cache.clear()
	var astar_result: Dictionary = grid_pathfinder.find_path(
			start,
			goal,
			bounds_min,
			bounds_max,
			Callable(self, "_road_cell_info"),
			Callable(self, "_road_step_cost"),
			TravelCostConfig.minimum_step_seconds(TravelCostConfig.DEFAULT_WALK_SPEED_KMH),
			ROAD_PATH_MAX_EXPANSIONS
		)
	var raw_path: Variant = astar_result.get("path", [])
	if not raw_path is Array or (raw_path as Array).is_empty():
		return _empty_path_result()
	var path: Array[Vector2i] = []
	for cell: Variant in raw_path:
		if cell is Vector2i:
			path.append(cell as Vector2i)
	return _path_result(path, float(astar_result.get("cost", 0.0)))

func _path_result(path: Array[Vector2i], cost: float) -> Dictionary:
	var crossings: Array[Vector2i] = []
	for cell: Vector2i in path:
		if bool(_road_cell_info(cell).get("river_crossing", false)):
			crossings.append(cell)
	return {
		"path": path,
		"cost": cost,
		"river_crossing_cells": crossings,
	}

func _empty_path_result() -> Dictionary:
	return {"path": [], "cost": 0.0, "river_crossing_cells": []}

func _road_cell_info(global_cell: Vector2i) -> Dictionary:
	var cached: Variant = path_sample_cache.get(global_cell, null)
	var sample: Vector3
	if cached is Vector3:
		sample = cached as Vector3
	else:
		sample = macro_sampler.sample(path_world_seed, global_cell)
		path_sample_cache[global_cell] = sample
	var terrain_type: int = terrain_generator.classify_sample(sample)
	var river: bool = sample.z > 0.0
	return {
		"passable": TravelCostConfig.is_passable(terrain_type, river, river),
		"terrain_type": terrain_type,
		"road": false,
		"river": river,
		"river_crossing": river,
		"elevation": sample.x,
	}

func _road_step_cost(
		_current: Vector2i,
		_next: Vector2i,
		direction: Vector2i,
		current_info: Dictionary,
		next_info: Dictionary
	) -> float:
	return TravelCostConfig.step_travel_seconds(
			current_info,
			next_info,
			direction,
			TravelCostConfig.DEFAULT_WALK_SPEED_KMH
		)

func _collect_settlements(
		world_seed: int,
		global_min: Vector2i,
		global_max: Vector2i
	) -> Array[WorldPOIData]:
	var region_min: Vector2i = Vector2i(
		WorldCoordinates.floor_divide(global_min.x, WorldCoordinates.REGION_GRID_SIZE),
		WorldCoordinates.floor_divide(global_min.y, WorldCoordinates.REGION_GRID_SIZE)
	)
	var region_max: Vector2i = Vector2i(
		WorldCoordinates.floor_divide(global_max.x, WorldCoordinates.REGION_GRID_SIZE),
		WorldCoordinates.floor_divide(global_max.y, WorldCoordinates.REGION_GRID_SIZE)
	)
	var by_id: Dictionary = {}
	for y: int in range(region_min.y, region_max.y + 1):
		for x: int in range(region_min.x, region_max.x + 1):
			var region_pois: Variant = poi_provider.call(Vector2i(x, y), world_seed)
			if not (region_pois is Array):
				continue
			for item: Variant in region_pois:
				if item is WorldPOIData:
					var poi: WorldPOIData = item as WorldPOIData
					if WorldPOIType.is_settlement(poi.poi_type) \
						and _contains(global_min, global_max, poi.global_region_cell):
						by_id[poi.poi_id] = poi
	var result: Array[WorldPOIData] = []
	for item: Variant in by_id.values():
		if item is WorldPOIData:
			result.append(item as WorldPOIData)
	result.sort_custom(Callable(self, "_poi_less"))
	return result

func _poi_less(a: WorldPOIData, b: WorldPOIData) -> bool:
	return a.poi_id < b.poi_id

func _copy_routes(source: Array) -> Array[WorldRoadRoute]:
	var result: Array[WorldRoadRoute] = []
	for item: Variant in source:
		if item is WorldRoadRoute:
			result.append(item as WorldRoadRoute)
	return result

func _region_global_min(world_cell: Vector2i) -> Vector2i:
	return Vector2i(
		world_cell.x * WorldCoordinates.REGION_GRID_SIZE,
		world_cell.y * WorldCoordinates.REGION_GRID_SIZE
	)

func _region_cache_key(world_cell: Vector2i, world_seed: int) -> String:
	return "%d|%d|%d|%d|%d|%d" % [
		world_seed,
		GENERATION_VERSION,
		WorldPOIGenerator.GENERATION_VERSION,
		RegionTerrainGenerator.GENERATION_VERSION,
		world_cell.x,
		world_cell.y,
	]

func _contains(min_cell: Vector2i, max_cell: Vector2i, cell: Vector2i) -> bool:
	return cell.x >= min_cell.x and cell.y >= min_cell.y \
		and cell.x <= max_cell.x and cell.y <= max_cell.y
