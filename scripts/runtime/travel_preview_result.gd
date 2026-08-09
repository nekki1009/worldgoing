class_name TravelPreviewResult
extends RefCounted

const GlobalTravelPathType = preload("res://scripts/data/global_travel_path.gd")
const TravelFailureReasonType = preload("res://scripts/runtime/travel_failure_reason.gd")
const TravelCostConfigType = preload("res://scripts/core/travel_cost_config.gd")

var party_id: String = ""
var success: bool = false
var failure_reason: int = TravelFailureReasonType.Code.NONE
var start_global_cell: Vector2i = Vector2i.ZERO
var destination_global_cell: Vector2i = Vector2i.ZERO
var path: GlobalTravelPathType
var total_distance_meters: float = 0.0
var estimated_travel_seconds: int = 0
var regions_crossed: int = 0
var destination_poi_id: String = ""

func has_path() -> bool:
	return success and path != null and path.has_path()

func set_path(p_path: GlobalTravelPathType) -> void:
	path = p_path
	if path == null:
		return
	total_distance_meters = path.total_distance_meters
	estimated_travel_seconds = path.estimated_travel_seconds
	regions_crossed = path.regions_crossed

func estimated_duration() -> String:
	return TravelCostConfigType.format_duration(estimated_travel_seconds)
