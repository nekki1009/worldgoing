class_name RegionRoadOverlay
extends RefCounted

const ROAD: int = 1
const RIVER_CROSSING: int = 2
const CELL_COUNT: int = WorldCoordinates.REGION_GRID_SIZE * WorldCoordinates.REGION_GRID_SIZE

var flags: PackedByteArray = PackedByteArray()
var route_ids_by_index: Dictionary = {}
var routes_by_id: Dictionary = {}

func _init() -> void:
	flags.resize(CELL_COUNT)
	flags.fill(0)

func get_flags(region_cell: Vector2i) -> int:
	if not WorldCoordinates.is_valid_region_cell(region_cell):
		return 0
	return flags[_index_for(region_cell)]

func has_road(region_cell: Vector2i) -> bool:
	return (get_flags(region_cell) & ROAD) != 0

func has_river_crossing(region_cell: Vector2i) -> bool:
	return (get_flags(region_cell) & RIVER_CROSSING) != 0

func add_route_cell(
		region_cell: Vector2i,
		cell_flags: int,
		route: WorldRoadRoute
	) -> void:
	if not WorldCoordinates.is_valid_region_cell(region_cell) or route == null:
		return
	var index: int = _index_for(region_cell)
	flags[index] = flags[index] | cell_flags
	var route_ids: Array[String] = _route_ids_for_index(index)
	if not route_ids.has(route.route_id):
		route_ids.append(route.route_id)
		route_ids.sort()
	route_ids_by_index[index] = route_ids
	routes_by_id[route.route_id] = route

func get_route_ids(region_cell: Vector2i) -> Array[String]:
	if not WorldCoordinates.is_valid_region_cell(region_cell):
		return []
	return _route_ids_for_index(_index_for(region_cell))

func get_routes(region_cell: Vector2i) -> Array[WorldRoadRoute]:
	var result: Array[WorldRoadRoute] = []
	for route_id: String in get_route_ids(region_cell):
		var route: WorldRoadRoute = routes_by_id.get(route_id) as WorldRoadRoute
		if route != null:
			result.append(route)
	return result

func get_route(route_id: String) -> WorldRoadRoute:
	return routes_by_id.get(route_id) as WorldRoadRoute

func _route_ids_for_index(index: int) -> Array[String]:
	var result: Array[String] = []
	var stored: Variant = route_ids_by_index.get(index, null)
	if stored is Array:
		for route_id: Variant in stored:
			result.append(str(route_id))
	result.sort()
	return result

func _index_for(region_cell: Vector2i) -> int:
	return region_cell.y * WorldCoordinates.REGION_GRID_SIZE + region_cell.x
