class_name RegionConstructionResult
extends RefCounted

enum FailureReason {
	NONE,
	RUNTIME_UNAVAILABLE,
	INVALID_REGION,
	INVALID_CELL,
	PARTY_NOT_READY,
	PARTY_NOT_IN_REGION,
	TRAVEL_IN_PROGRESS,
	IMPASSABLE,
	OCCUPIED,
	ALREADY_EXISTS,
	NOT_FOUND,
	WRONG_FEATURE_TYPE,
}

var success: bool = false
var changed: bool = false
var failure_reason: int = FailureReason.NONE
var world_cell: Vector2i = Vector2i(-1, -1)
var region_cell: Vector2i = Vector2i(-1, -1)
var feature_id: String = ""
var revision: int = 0

static func failure_code(reason: int) -> String:
	match reason:
		FailureReason.RUNTIME_UNAVAILABLE:
			return "RUNTIME_UNAVAILABLE"
		FailureReason.INVALID_REGION:
			return "INVALID_REGION"
		FailureReason.INVALID_CELL:
			return "INVALID_CELL"
		FailureReason.PARTY_NOT_READY:
			return "PARTY_NOT_READY"
		FailureReason.PARTY_NOT_IN_REGION:
			return "PARTY_NOT_IN_REGION"
		FailureReason.TRAVEL_IN_PROGRESS:
			return "TRAVEL_IN_PROGRESS"
		FailureReason.IMPASSABLE:
			return "IMPASSABLE"
		FailureReason.OCCUPIED:
			return "OCCUPIED"
		FailureReason.ALREADY_EXISTS:
			return "ALREADY_EXISTS"
		FailureReason.NOT_FOUND:
			return "NOT_FOUND"
		FailureReason.WRONG_FEATURE_TYPE:
			return "WRONG_FEATURE_TYPE"
		_:
			return "NONE"
