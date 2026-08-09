class_name TravelStepResult
extends RefCounted

const TravelFailureReasonType = preload("res://scripts/runtime/travel_failure_reason.gd")

var success: bool = false
var failure_reason: int = TravelFailureReasonType.Code.NONE
var path_index: int = -1
var from_global_cell: Vector2i = Vector2i.ZERO
var next_global_cell: Vector2i = Vector2i.ZERO
var previous_world_cell: Vector2i = Vector2i.ZERO
var next_world_cell: Vector2i = Vector2i.ZERO
var next_region_cell: Vector2i = Vector2i.ZERO
var step_travel_seconds: int = 0
