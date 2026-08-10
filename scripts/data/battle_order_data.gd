class_name BattleOrderData
extends RefCounted

enum Kind {
	SIMPLE,
	FINE,
}

enum SimpleIntent {
	ADVANCE,
	FALL_BACK,
	ATTACK,
	WITHDRAW,
	FLANK_REAR,
}

enum FineIntent {
	MOVE_TO,
	SET_FACING,
	HOLD_POSITION,
	FOCUS_TARGET,
}

enum State {
	QUEUED,
	EN_ROUTE,
	DEFERRED,
	DELIVERED,
	INTERCEPTED,
	TARGET_UNAVAILABLE,
	FAILED,
}

var order_id: String = ""
var source_id: String = ""
var source_formation_id: String = ""
var target_formation_id: String = ""
var kind: int = Kind.SIMPLE
var simple_intent: int = SimpleIntent.ADVANCE
var fine_intent: int = FineIntent.MOVE_TO
var target_position_m: Vector2 = Vector2.ZERO
var target_facing: Vector2 = Vector2.DOWN
var focus_target_formation_id: String = ""
var issued_at: float = 0.0
var execute_at: float = 0.0
var state: int = State.QUEUED
var failure_code: int = 0

static func make_simple(
		p_source_id: String,
		p_target_formation_id: String,
		p_intent: int,
		p_focus_target_formation_id: String = ""
	) -> BattleOrderData:
	var result: BattleOrderData = BattleOrderData.new()
	result.source_id = p_source_id
	result.target_formation_id = p_target_formation_id
	result.kind = Kind.SIMPLE
	result.simple_intent = p_intent
	result.focus_target_formation_id = p_focus_target_formation_id
	return result

static func make_fine(
		p_source_id: String,
		p_target_formation_id: String,
		p_intent: int,
		p_target_position_m: Vector2 = Vector2.ZERO,
		p_target_facing: Vector2 = Vector2.DOWN,
		p_focus_target_formation_id: String = ""
	) -> BattleOrderData:
	var result: BattleOrderData = BattleOrderData.new()
	result.source_id = p_source_id
	result.target_formation_id = p_target_formation_id
	result.kind = Kind.FINE
	result.fine_intent = p_intent
	result.target_position_m = p_target_position_m
	result.target_facing = p_target_facing
	result.focus_target_formation_id = p_focus_target_formation_id
	return result

func is_simple() -> bool:
	return kind == Kind.SIMPLE

func is_fine() -> bool:
	return kind == Kind.FINE

func copy() -> BattleOrderData:
	var result: BattleOrderData = BattleOrderData.new()
	result.order_id = order_id
	result.source_id = source_id
	result.source_formation_id = source_formation_id
	result.target_formation_id = target_formation_id
	result.kind = kind
	result.simple_intent = simple_intent
	result.fine_intent = fine_intent
	result.target_position_m = target_position_m
	result.target_facing = target_facing
	result.focus_target_formation_id = focus_target_formation_id
	result.issued_at = issued_at
	result.execute_at = execute_at
	result.state = state
	result.failure_code = failure_code
	return result

static func state_code(value: int) -> String:
	match value:
		State.QUEUED:
			return "QUEUED"
		State.EN_ROUTE:
			return "EN_ROUTE"
		State.DEFERRED:
			return "DEFERRED"
		State.DELIVERED:
			return "DELIVERED"
		State.INTERCEPTED:
			return "INTERCEPTED"
		State.TARGET_UNAVAILABLE:
			return "TARGET_UNAVAILABLE"
		State.FAILED:
			return "FAILED"
		_:
			return "UNKNOWN"
