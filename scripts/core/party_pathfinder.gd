class_name PartyPathfinder
extends RefCounted

const GlobalTravelPathType = preload("res://scripts/data/global_travel_path.gd")

const BOUNDS_MIN: Vector2i = Vector2i.ZERO
const BOUNDS_MAX: Vector2i = Vector2i(
	WorldCoordinates.REGION_GRID_SIZE - 1,
	WorldCoordinates.REGION_GRID_SIZE - 1
)
const GLOBAL_PATH_MARGIN_CELLS: int = 50
const GLOBAL_PATH_FALLBACK_MARGINS: Array[int] = [GLOBAL_PATH_MARGIN_CELLS, 100, 200]
const MAX_GLOBAL_PATH_SEARCH_CELLS: int = 500_000
const GLOBAL_PATH_MAX_EXPANSIONS: int = 300_000

var grid_pathfinder: WeightedGridPathfinder = WeightedGridPathfinder.new()
var terrain_data: RegionTerrainData
var road_overlay: RegionRoadOverlay
var base_speed_kmh: float = TravelCostConfig.DEFAULT_WALK_SPEED_KMH
var global_world_data: WorldData
var global_world_seed: int = 0
var global_cell_info_cache: Dictionary = {}

func find_path(
		p_terrain_data: RegionTerrainData,
		p_road_overlay: RegionRoadOverlay,
		start: Vector2i,
		destination: Vector2i,
		p_base_speed_kmh: float
	) -> PartyPathResult:
	var result: PartyPathResult = PartyPathResult.new()
	terrain_data = p_terrain_data
	road_overlay = p_road_overlay if p_road_overlay != null else RegionRoadOverlay.new()
	base_speed_kmh = p_base_speed_kmh
	var astar_result: Dictionary = grid_pathfinder.find_path(
			start,
			destination,
			BOUNDS_MIN,
			BOUNDS_MAX,
			Callable(self, "_cell_info"),
			Callable(self, "_step_cost"),
			TravelCostConfig.minimum_step_seconds(base_speed_kmh)
		)
	var raw_path: Variant = astar_result.get("path", [])
	if not raw_path is Array or (raw_path as Array).is_empty():
		return result
	for cell: Variant in raw_path:
		if cell is Vector2i:
			result.cells.append(cell as Vector2i)
	if result.cells.is_empty():
		return result
	result.total_cost = float(astar_result.get("cost", 0.0))
	_calculate_path_totals(result)
	return result

func find_global_path(
		p_world_data: WorldData,
		start_global_region_cell: Vector2i,
		destination_global_region_cell: Vector2i,
		p_world_seed: int,
		p_base_speed_kmh: float
	) -> GlobalTravelPathType:
	var result: GlobalTravelPathType = GlobalTravelPathType.new()
	result.start_global_cell = start_global_region_cell
	result.destination_global_cell = destination_global_region_cell
	global_world_data = p_world_data
	global_world_seed = p_world_seed
	base_speed_kmh = p_base_speed_kmh
	global_cell_info_cache.clear()
	var started_at_usec: int = Time.get_ticks_usec()
	if global_world_data == null:
		result.error_message = "World data unavailable"
		return result
	var start_info: Dictionary = _global_cell_info(start_global_region_cell)
	var destination_info: Dictionary = _global_cell_info(destination_global_region_cell)
	if not bool(start_info.get("passable", false)):
		result.error_message = "Current Party Cell is impassable"
		return result
	if not bool(destination_info.get("passable", false)):
		result.error_message = "Destination is impassable"
		return result

	var exceeded_search_limit: bool = false
	for margin: int in GLOBAL_PATH_FALLBACK_MARGINS:
		var bounds_min: Vector2i = Vector2i(
			mini(start_global_region_cell.x, destination_global_region_cell.x) - margin,
			mini(start_global_region_cell.y, destination_global_region_cell.y) - margin
		)
		var bounds_max: Vector2i = Vector2i(
			maxi(start_global_region_cell.x, destination_global_region_cell.x) + margin,
			maxi(start_global_region_cell.y, destination_global_region_cell.y) + margin
		)
		var search_cell_count: int = (bounds_max.x - bounds_min.x + 1) * (bounds_max.y - bounds_min.y + 1)
		if search_cell_count > MAX_GLOBAL_PATH_SEARCH_CELLS:
			exceeded_search_limit = true
			continue
		global_cell_info_cache.clear()
		var astar_result: Dictionary = grid_pathfinder.find_path(
				start_global_region_cell,
				destination_global_region_cell,
				bounds_min,
				bounds_max,
				Callable(self, "_global_cell_info"),
				Callable(self, "_global_step_cost"),
				TravelCostConfig.minimum_step_seconds(base_speed_kmh),
				GLOBAL_PATH_MAX_EXPANSIONS
			)
		var raw_path: Variant = astar_result.get("path", [])
		if not raw_path is Array or (raw_path as Array).is_empty():
			continue
		result.search_margin = margin
		result.search_bounds_min = bounds_min
		result.search_bounds_max = bounds_max
		for cell: Variant in raw_path:
			if cell is Vector2i:
				result.cells.append(cell as Vector2i)
		_build_global_path_totals(result)
		result.path_calculation_milliseconds = float(Time.get_ticks_usec() - started_at_usec) / 1000.0
		return result
	result.error_message = "Path search limit exceeded" if exceeded_search_limit else "No Global Path"
	result.path_calculation_milliseconds = float(Time.get_ticks_usec() - started_at_usec) / 1000.0
	return result

func get_cell_info(region_cell: Vector2i) -> Dictionary:
	if terrain_data == null or not WorldCoordinates.is_valid_region_cell(region_cell):
		return {"passable": false}
	var terrain_type: int = terrain_data.get_terrain(region_cell)
	var road: bool = road_overlay != null and road_overlay.has_road(region_cell)
	var river: bool = terrain_data.has_river(region_cell)
	var river_crossing: bool = road_overlay != null and road_overlay.has_river_crossing(region_cell)
	var passable: bool = TravelCostConfig.is_passable(terrain_type, river, river_crossing)
	return {
		"passable": passable,
		"terrain_type": terrain_type,
		"road": road,
		"river": river,
		"river_crossing": river_crossing,
		"elevation": terrain_data.get_elevation(region_cell),
		"speed": TravelCostConfig.get_speed_kmh(terrain_type, road, base_speed_kmh),
	}

func get_step_travel_seconds(from_cell: Vector2i, to_cell: Vector2i) -> int:
	var direction: Vector2i = to_cell - from_cell
	var current_info: Dictionary = get_cell_info(from_cell)
	var next_info: Dictionary = get_cell_info(to_cell)
	var seconds: float = TravelCostConfig.step_travel_seconds(
			current_info,
			next_info,
			direction,
			base_speed_kmh
		)
	return maxi(roundi(seconds), 0)

func _cell_info(region_cell: Vector2i) -> Dictionary:
	return get_cell_info(region_cell)

func _step_cost(
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
			base_speed_kmh
		)

func _calculate_path_totals(result: PartyPathResult) -> void:
	var distance: float = 0.0
	var total_seconds: int = 0
	result.step_travel_seconds.clear()
	for index: int in range(1, result.cells.size()):
		var from_cell: Vector2i = result.cells[index - 1]
		var to_cell: Vector2i = result.cells[index]
		var direction: Vector2i = to_cell - from_cell
		distance += TravelCostConfig.step_distance_meters(direction)
		var step_seconds: int = maxi(roundi(TravelCostConfig.step_travel_seconds(
			get_cell_info(from_cell),
			get_cell_info(to_cell),
			direction,
			base_speed_kmh
		)), 0)
		result.step_travel_seconds.append(step_seconds)
		total_seconds += step_seconds
	result.total_distance_meters = distance
	result.estimated_travel_seconds = total_seconds

func _global_cell_info(global_region_cell: Vector2i) -> Dictionary:
	var cached: Variant = global_cell_info_cache.get(global_region_cell, null)
	if cached is Dictionary:
		return cached as Dictionary
	if global_world_data == null:
		return {"passable": false}
	var result: Dictionary = global_world_data.sample_travel_data(global_world_seed, global_region_cell)
	global_cell_info_cache[global_region_cell] = result
	return result

func _global_step_cost(
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
			base_speed_kmh
		)

func _build_global_path_totals(result: GlobalTravelPathType) -> void:
	var distance: float = 0.0
	var seconds: int = 0
	var regions: Dictionary = {}
	result.step_travel_seconds.clear()
	for cell: Vector2i in result.cells:
		var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(cell)
		regions[converted["world_cell"] as Vector2i] = true
	for index: int in range(1, result.cells.size()):
		var from_cell: Vector2i = result.cells[index - 1]
		var to_cell: Vector2i = result.cells[index]
		var direction: Vector2i = to_cell - from_cell
		distance += TravelCostConfig.step_distance_meters(direction)
		var step_seconds: int = maxi(roundi(TravelCostConfig.step_travel_seconds(
				_global_cell_info(from_cell),
				_global_cell_info(to_cell),
				direction,
				base_speed_kmh
			)), 0)
		result.step_travel_seconds.append(step_seconds)
		seconds += step_seconds
	result.total_distance_meters = distance
	result.estimated_travel_seconds = seconds
	result.regions_crossed = regions.size()
