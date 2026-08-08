class_name GlobalTravelPath
extends RefCounted

var start_global_cell: Vector2i = Vector2i.ZERO
var destination_global_cell: Vector2i = Vector2i.ZERO
var cells: Array[Vector2i] = []
var step_travel_seconds: Array[int] = []
var total_distance_meters: float = 0.0
var estimated_travel_seconds: int = 0
var regions_crossed: int = 0
var search_margin: int = 0
var search_bounds_min: Vector2i = Vector2i.ZERO
var search_bounds_max: Vector2i = Vector2i.ZERO
var path_calculation_milliseconds: float = 0.0
var error_message: String = ""
var destination_poi_id: String = ""

func has_path() -> bool:
	return not cells.is_empty()

func remaining_distance_from(path_index: int) -> float:
	var distance: float = 0.0
	var first_step: int = maxi(path_index + 1, 1)
	for index: int in range(first_step, cells.size()):
		distance += TravelCostConfig.step_distance_meters(cells[index] - cells[index - 1])
	return distance

func remaining_travel_seconds_from(path_index: int) -> int:
	var seconds: int = 0
	var first_step: int = maxi(path_index, 0)
	for index: int in range(first_step, step_travel_seconds.size()):
		seconds += step_travel_seconds[index]
	return seconds

func estimated_duration() -> String:
	return TravelCostConfig.format_duration(estimated_travel_seconds)

func remaining_duration_from(path_index: int) -> String:
	return TravelCostConfig.format_duration(remaining_travel_seconds_from(path_index))

func path_hash() -> String:
	var result: Array[String] = []
	for cell: Vector2i in cells:
		result.append("%d,%d" % [cell.x, cell.y])
	return ";".join(result)
