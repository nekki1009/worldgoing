class_name WorldRoadRoute
extends RefCounted

var route_id: String = ""
var start_poi_id: String = ""
var end_poi_id: String = ""
var start_global_cell: Vector2i = Vector2i.ZERO
var end_global_cell: Vector2i = Vector2i.ZERO
var path: Array[Vector2i] = []
var river_crossing_cells: Array[Vector2i] = []
var requires_bridge: bool = false
var estimated_cost: float = 0.0
var path_generated: bool = false

func _init(
		p_route_id: String,
		p_start_poi_id: String,
		p_end_poi_id: String,
		p_start_global_cell: Vector2i,
		p_end_global_cell: Vector2i
	) -> void:
	route_id = p_route_id
	start_poi_id = p_start_poi_id
	end_poi_id = p_end_poi_id
	start_global_cell = p_start_global_cell
	end_global_cell = p_end_global_cell

func crosses_river() -> bool:
	return not river_crossing_cells.is_empty()

func straight_distance_cells() -> float:
	return Vector2(
		float(start_global_cell.x),
		float(start_global_cell.y)
	).distance_to(Vector2(
		float(end_global_cell.x),
		float(end_global_cell.y)
	))

func path_length_cells() -> float:
	if path.size() < 2:
		return 0.0
	var length: float = 0.0
	for index: int in range(1, path.size()):
		var delta: Vector2i = path[index] - path[index - 1]
		length += sqrt(2.0) if delta.x != 0 and delta.y != 0 else 1.0
	return length

func path_length_meters() -> float:
	return path_length_cells() * float(WorldCoordinates.REGION_CELL_SIZE_METERS)

func debug_summary() -> String:
	return "%s %s -> %s | straight %.1f km | path %.1f km | cost %.1f | river %s" % [
		route_id,
		start_poi_id,
		end_poi_id,
		straight_distance_cells() * float(WorldCoordinates.REGION_CELL_SIZE_METERS) / 1000.0,
		path_length_meters() / 1000.0,
		estimated_cost,
		"Yes" if crosses_river() else "No"
	]
