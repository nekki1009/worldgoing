class_name BattleDispatchData
extends RefCounted

var order_id: String = ""
var target_formation_id: String = ""
var position_m: Vector2 = Vector2.ZERO
var previous_position_m: Vector2 = Vector2.ZERO
var path: Array[Vector2i] = []
var path_index: int = 0
var speed_mps: float = 0.0
var eta_seconds: float = 0.0
var state: int = BattleOrderData.State.EN_ROUTE
var intercepted_by_formation_id: String = ""
var intercepted_at_m: Vector2 = Vector2.ZERO

func copy() -> BattleDispatchData:
	var result: BattleDispatchData = BattleDispatchData.new()
	result.order_id = order_id
	result.target_formation_id = target_formation_id
	result.position_m = position_m
	result.previous_position_m = previous_position_m
	result.path = path.duplicate()
	result.path_index = path_index
	result.speed_mps = speed_mps
	result.eta_seconds = eta_seconds
	result.state = state
	result.intercepted_by_formation_id = intercepted_by_formation_id
	result.intercepted_at_m = intercepted_at_m
	return result
