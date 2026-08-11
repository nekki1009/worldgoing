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

func get_connection_offsets(
		region_cell: Vector2i,
		global_cell: Vector2i,
		route_active: Callable = Callable()
	) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for route_id: String in get_route_ids(region_cell):
		if route_active.is_valid() and not bool(route_active.call(route_id)):
			continue
		var route: WorldRoadRoute = get_route(route_id)
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

func _append_unique_offset(result: Array[Vector2i], delta: Vector2i) -> void:
	var offset: Vector2i = Vector2i(clampi(delta.x, -1, 1), clampi(delta.y, -1, 1))
	if offset != Vector2i.ZERO and not result.has(offset):
		result.append(offset)

func _offset_less(left: Vector2i, right: Vector2i) -> bool:
	return left.y < right.y or (left.y == right.y and left.x < right.x)
