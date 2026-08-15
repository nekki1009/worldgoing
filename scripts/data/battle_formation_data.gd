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

enum Intent {
	HOLD,
	ADVANCE,
	FALL_BACK,
	ATTACK,
	WITHDRAW,
	FLANK_REAR,
}

enum AutonomyState {
	NONE,
	ENGAGED,
}

const DEFAULT_PERSONNEL: int = 100
const DEFAULT_MOVE_SPEED_MPS: float = 1.5
const FORMATION_COLUMNS: int = 20
const FORMATION_ROWS: int = 5
const SOLDIER_CANVAS_SIZE_METERS: Vector2 = Vector2(1.20, 2.40)
const SOLDIER_SPACING_METERS: Vector2 = Vector2(0.50, 0.80)
const DEFAULT_WIDTH_METERS: float = 33.50
const DEFAULT_DEPTH_METERS: float = 15.20

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
var intent: int = Intent.HOLD
var intent_target_formation_id: String = ""
var is_commander_formation: bool = false
var captain_id: String = ""
var autonomy_state: int = AutonomyState.NONE
var contact_target_id: String = ""

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
	var formation_size: Vector2 = formation_size_for_personnel(personnel_count)
	width_m = formation_size.x
	depth_m = formation_size.y

static func formation_size_for_personnel(personnel: int) -> Vector2:
	var count: int = clampi(personnel, 1, FORMATION_COLUMNS * FORMATION_ROWS)
	var columns: int = mini(FORMATION_COLUMNS, count)
	var rows: int = ceili(float(count) / float(FORMATION_COLUMNS))
	return Vector2(
		float(columns) * SOLDIER_CANVAS_SIZE_METERS.x
			+ float(maxi(columns - 1, 0)) * SOLDIER_SPACING_METERS.x,
		float(rows) * SOLDIER_CANVAS_SIZE_METERS.y
			+ float(maxi(rows - 1, 0)) * SOLDIER_SPACING_METERS.y
	)

static func formation_slot_local(
	index: int,
	personnel_count: int,
	width_m: float,
	depth_m: float
) -> Vector2:
	var count: int = clampi(personnel_count, 1, FORMATION_COLUMNS * FORMATION_ROWS)
	var row: int = floori(float(index) / float(FORMATION_COLUMNS))
	var slot: int = index % FORMATION_COLUMNS
	var count_in_row: int = mini(FORMATION_COLUMNS, count - row * FORMATION_COLUMNS)
	var row_width: float = float(count_in_row) * SOLDIER_CANVAS_SIZE_METERS.x \
		+ float(maxi(count_in_row - 1, 0)) * SOLDIER_SPACING_METERS.x
	var row_start_x: float = -width_m * 0.5 \
		+ (width_m - row_width) * 0.5 \
		+ SOLDIER_CANVAS_SIZE_METERS.x * 0.5
	var x: float = row_start_x + float(slot) * (
		SOLDIER_CANVAS_SIZE_METERS.x + SOLDIER_SPACING_METERS.x
	)
	var row_start_y: float = depth_m * 0.5 - SOLDIER_CANVAS_SIZE_METERS.y * 0.5
	var y: float = row_start_y - float(row) * (
		SOLDIER_CANVAS_SIZE_METERS.y + SOLDIER_SPACING_METERS.y
	)
	return Vector2(x, y)

static func formation_world_position(
	position_m: Vector2,
	facing_direction: Vector2,
	local_slot: Vector2
) -> Vector2:
	var facing: Vector2 = facing_direction.normalized()
	if facing == Vector2.ZERO:
		facing = Vector2.DOWN
	var lateral: Vector2 = Vector2(facing.y, -facing.x)
	return position_m + lateral * local_slot.x + facing * local_slot.y

func is_controllable() -> bool:
	return is_commander_formation

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
	result.intent = intent
	result.intent_target_formation_id = intent_target_formation_id
	result.is_commander_formation = is_commander_formation
	result.captain_id = captain_id
	result.autonomy_state = autonomy_state
	result.contact_target_id = contact_target_id
	return result

static func side_code(value: int) -> String:
	return "attacker" if value == Side.ATTACKER else "defender"

static func state_code(value: int) -> String:
	return "moving" if value == State.MOVING else "idle"
