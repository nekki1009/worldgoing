class_name PersistenceResult
extends RefCounted

enum Code {
	NONE,
	INVALID_SESSION,
	INVALID_PATH,
	TRAVEL_IN_PROGRESS,
	IO_ERROR,
	CORRUPT_DATA,
	UNSUPPORTED_VERSION,
	INVALID_DATA,
	INVALID_REGION_DELTA,
	INVALID_WORLD_POSITION,
}

var success: bool = false
var failure_reason: int = Code.NONE
var session: GameSession
var file_path: String = ""
var bytes_written: int = 0

static func to_code(reason: int) -> String:
	match reason:
		Code.INVALID_SESSION:
			return "INVALID_SESSION"
		Code.INVALID_PATH:
			return "INVALID_PATH"
		Code.TRAVEL_IN_PROGRESS:
			return "TRAVEL_IN_PROGRESS"
		Code.IO_ERROR:
			return "IO_ERROR"
		Code.CORRUPT_DATA:
			return "CORRUPT_DATA"
		Code.UNSUPPORTED_VERSION:
			return "UNSUPPORTED_VERSION"
		Code.INVALID_DATA:
			return "INVALID_DATA"
		Code.INVALID_REGION_DELTA:
			return "INVALID_REGION_DELTA"
		Code.INVALID_WORLD_POSITION:
			return "INVALID_WORLD_POSITION"
		_:
			return "NONE"
