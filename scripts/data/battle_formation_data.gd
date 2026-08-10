class_name BattleFormationData
extends RefCounted

enum Side {
	ATTACKER,
	DEFENDER,
}

enum State {
	IDLE,
	MOVING,
}

const DEFAULT_PERSONNEL: int = 100
const DEFAULT_MOVE_SPEED_MPS: float = 1.5
const DEFAULT_WIDTH_METERS: float = 20.0
const DEFAULT_DEPTH_METERS: float = 10.0

var formation_id: String = ""
var side: int = Side.ATTACKER
var personnel_count: int = 0
var battle_position_m: Vector2 = Vector2.ZERO
var target_position_m: Vector2 = Vector2.ZERO
var facing_direction: Vector2 = Vector2.DOWN
var base_move_speed_mps: float = DEFAULT_MOVE_SPEED_MPS
var width_m: float = DEFAULT_WIDTH_METERS
var depth_m: float = DEFAULT_DEPTH_METERS
var state: int = State.IDLE
var path: Array[Vector2i] = []
var path_index: int = -1

func _init(
		p_formation_id: String = "",
		p_side: int = Side.ATTACKER,
		p_personnel_count: int = DEFAULT_PERSONNEL,
		p_position_m: Vector2 = Vector2.ZERO
	) -> void:
	formation_id = p_formation_id
	side = p_side
	personnel_count = maxi(p_personnel_count, 0)
	battle_position_m = p_position_m
	target_position_m = p_position_m

func is_controllable() -> bool:
	return side == Side.ATTACKER

func clear_path() -> void:
	path.clear()
	path_index = -1
	state = State.IDLE
	target_position_m = battle_position_m

func copy() -> BattleFormationData:
	var result: BattleFormationData = BattleFormationData.new(
		formation_id,
		side,
		personnel_count,
		battle_position_m
	)
	result.target_position_m = target_position_m
	result.facing_direction = facing_direction
	result.base_move_speed_mps = base_move_speed_mps
	result.width_m = width_m
	result.depth_m = depth_m
	result.state = state
	result.path = path.duplicate()
	result.path_index = path_index
	return result

static func side_code(value: int) -> String:
	return "attacker" if value == Side.ATTACKER else "defender"

static func state_code(value: int) -> String:
	return "moving" if value == State.MOVING else "idle"
