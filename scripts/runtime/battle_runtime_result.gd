class_name BattleRuntimeResult
extends RefCounted

enum Code {
	NONE,
	RUNTIME_UNAVAILABLE,
	NO_ACTIVE_BATTLE,
	INVALID_BATTLE,
	INVALID_FORMATION,
	NOT_CONTROLLABLE,
	INVALID_TARGET,
	IMPASSABLE,
	OCCUPIED,
	NO_PATH,
	ORDER_QUEUED,
	DISPATCH_CREATED,
	ORDER_APPLIED,
	ORDER_IN_TRANSIT,
	MESSENGER_INTERCEPTED,
	NO_MESSENGER_ROUTE,
	ORDER_NOT_FOUND,
	TARGET_UNAVAILABLE,
	SPEED_CHANGED,
	INVALID_SPEED,
}

var success: bool = false
var changed: bool = false
var failure_code: int = Code.NONE
var formation_id: String = ""
var path: Array[Vector2i] = []
var cost_seconds: float = 0.0
var snapshot: BattleSiteSnapshot
var order_id: String = ""
var order_state: int = BattleOrderData.State.FAILED
var dispatch_position_m: Vector2 = Vector2.ZERO
var battle_speed_multiplier: float = 1.0

func failure(code: int) -> BattleRuntimeResult:
	success = false
	failure_code = code
	return self

func succeed() -> BattleRuntimeResult:
	success = true
	failure_code = Code.NONE
	return self

func succeed_with_code(code: int) -> BattleRuntimeResult:
	success = true
	failure_code = code
	return self

static func code_name(code: int) -> String:
	match code:
		Code.RUNTIME_UNAVAILABLE:
			return "RUNTIME_UNAVAILABLE"
		Code.NO_ACTIVE_BATTLE:
			return "NO_ACTIVE_BATTLE"
		Code.INVALID_BATTLE:
			return "INVALID_BATTLE"
		Code.INVALID_FORMATION:
			return "INVALID_FORMATION"
		Code.NOT_CONTROLLABLE:
			return "NOT_CONTROLLABLE"
		Code.INVALID_TARGET:
			return "INVALID_TARGET"
		Code.IMPASSABLE:
			return "IMPASSABLE"
		Code.OCCUPIED:
			return "OCCUPIED"
		Code.NO_PATH:
			return "NO_PATH"
		Code.ORDER_QUEUED:
			return "ORDER_QUEUED"
		Code.DISPATCH_CREATED:
			return "DISPATCH_CREATED"
		Code.ORDER_APPLIED:
			return "ORDER_APPLIED"
		Code.ORDER_IN_TRANSIT:
			return "ORDER_IN_TRANSIT"
		Code.MESSENGER_INTERCEPTED:
			return "MESSENGER_INTERCEPTED"
		Code.NO_MESSENGER_ROUTE:
			return "NO_MESSENGER_ROUTE"
		Code.ORDER_NOT_FOUND:
			return "ORDER_NOT_FOUND"
		Code.TARGET_UNAVAILABLE:
			return "TARGET_UNAVAILABLE"
		Code.SPEED_CHANGED:
			return "SPEED_CHANGED"
		Code.INVALID_SPEED:
			return "INVALID_SPEED"
		_:
			return "NONE"
