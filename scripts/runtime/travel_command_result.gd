class_name TravelCommandResult
extends RefCounted

const GlobalTravelPathType = preload("res://scripts/data/global_travel_path.gd")
const TravelFailureReasonType = preload("res://scripts/runtime/travel_failure_reason.gd")

var success: bool = false
var failure_reason: int = TravelFailureReasonType.Code.NONE
var party_id: String = ""
var destination_global_cell: Vector2i = Vector2i.ZERO
var path: GlobalTravelPathType
var cancel_requested: bool = false

func has_path() -> bool:
	return path != null and path.has_path()
