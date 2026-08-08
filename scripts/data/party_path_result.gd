class_name PartyPathResult
extends RefCounted

var cells: Array[Vector2i] = []
var step_travel_seconds: Array[int] = []
var total_distance_meters: float = 0.0
var estimated_travel_seconds: int = 0
var total_cost: float = 0.0

func has_path() -> bool:
	return not cells.is_empty()

func estimated_duration() -> String:
	return TravelCostConfig.format_duration(estimated_travel_seconds)
