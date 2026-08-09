class_name TravelCellResult
extends RefCounted

const TravelFailureReasonType = preload("res://scripts/runtime/travel_failure_reason.gd")

var success: bool = false
var failure_reason: int = TravelFailureReasonType.Code.NONE
var global_cell: Vector2i = Vector2i.ZERO
var passable: bool = false
var terrain_type: int = -1
var road: bool = false
var river: bool = false
var river_crossing: bool = false
var elevation: float = 0.0
var speed: float = 0.0
var travel_seconds: int = 0
