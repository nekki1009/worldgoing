class_name BattleSiteSnapshot
extends RefCounted

enum FailureReason {
	NONE,
	RUNTIME_UNAVAILABLE,
	INVALID_DESTINATION,
	IMPASSABLE,
	TRAVEL_IN_PROGRESS,
	INVALID_PARTICIPANT,
}

var success: bool = false
var failure_reason: int = FailureReason.NONE
var context: BattleSiteContext
var footprint_cells: Array[Dictionary] = []
var size_meters: Vector2 = Vector2.ZERO
var bounds_meters: Rect2 = Rect2()
var center_cell: Dictionary = {}
var center_terrain: int = -1
var attacker_deployment: Dictionary = {}
var defender_deployment: Dictionary = {}
var terrain_debug_representation: String = ""
var terrain_hash: String = ""
var preview_hash: String = ""

func has_preview() -> bool:
	return success and context != null and footprint_cells.size() == 9

static func failure_code(reason: int) -> String:
	match reason:
		FailureReason.RUNTIME_UNAVAILABLE:
			return "RUNTIME_UNAVAILABLE"
		FailureReason.INVALID_DESTINATION:
			return "INVALID_DESTINATION"
		FailureReason.IMPASSABLE:
			return "IMPASSABLE"
		FailureReason.TRAVEL_IN_PROGRESS:
			return "TRAVEL_IN_PROGRESS"
		FailureReason.INVALID_PARTICIPANT:
			return "INVALID_PARTICIPANT"
		_:
			return "NONE"
