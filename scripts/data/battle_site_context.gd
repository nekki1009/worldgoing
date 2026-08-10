class_name BattleSiteContext
extends RefCounted

enum EntryDirection {
	NORTH,
	EAST,
	SOUTH,
	WEST,
}

const FOOTPRINT_SIZE_CELLS: Vector2i = Vector2i(3, 3)
const BATTLE_ID_SALT: int = 41_009
const MAX_TOTAL_PERSONNEL: int = 9_000

var battle_id: String = ""
var battle_seed: int = 0
var world_seed: int = 0
var center_global_region_cell: Vector2i = Vector2i.ZERO
var center_world_cell: Vector2i = Vector2i.ZERO
var center_region_cell: Vector2i = Vector2i.ZERO
var footprint_size: Vector2i = FOOTPRINT_SIZE_CELLS
var attacker: BattleParticipantData
var defender: BattleParticipantData
var attacker_entry_direction: int = EntryDirection.SOUTH
var defender_entry_direction: int = EntryDirection.NORTH
var battle_sequence: int = 0
var world_time_seconds: int = -1

static func create(
		p_world_seed: int,
		p_center_global_region_cell: Vector2i,
		p_attacker: BattleParticipantData,
		p_defender: BattleParticipantData,
		p_attacker_entry_direction: int,
		p_defender_entry_direction: int,
		p_battle_sequence: int = 0,
		p_world_time_seconds: int = -1
	) -> BattleSiteContext:
	if p_attacker == null or p_defender == null:
		return null
	if p_attacker.participant_id.strip_edges().is_empty() \
			or p_defender.participant_id.strip_edges().is_empty() \
			or p_attacker.participant_id == p_defender.participant_id \
			or not p_attacker.has_valid_commander() \
			or not p_defender.has_valid_commander() \
			or p_attacker.commander_id == p_defender.commander_id \
			or p_attacker.total_personnel <= 0 \
			or p_defender.total_personnel <= 0 \
			or p_attacker.total_personnel + p_defender.total_personnel > MAX_TOTAL_PERSONNEL \
			or p_battle_sequence < 0:
		return null
	if not is_valid_entry_direction(p_attacker_entry_direction) \
			or not is_valid_entry_direction(p_defender_entry_direction):
		return null
	var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(
		p_center_global_region_cell
	)
	var identity: String = "%s|%s|%d" % [
		p_attacker.participant_id,
		p_defender.participant_id,
		p_battle_sequence,
	]
	var context: BattleSiteContext = BattleSiteContext.new()
	context.world_seed = p_world_seed
	context.center_global_region_cell = p_center_global_region_cell
	context.center_world_cell = converted["world_cell"] as Vector2i
	context.center_region_cell = converted["region_cell"] as Vector2i
	context.attacker = p_attacker.copy()
	context.defender = p_defender.copy()
	context.attacker_entry_direction = p_attacker_entry_direction
	context.defender_entry_direction = p_defender_entry_direction
	context.battle_sequence = p_battle_sequence
	context.world_time_seconds = p_world_time_seconds
	context.battle_seed = DeterministicHash.value(
		p_world_seed,
		p_center_global_region_cell,
		BATTLE_ID_SALT + posmod(identity.hash(), DeterministicHash.MODULUS)
	)
	context.battle_id = "battle_%d_%d_%d" % [
		p_center_global_region_cell.x,
		p_center_global_region_cell.y,
		context.battle_seed,
	]
	return context

static func is_valid_entry_direction(direction: int) -> bool:
	return direction >= EntryDirection.NORTH and direction <= EntryDirection.WEST

static func entry_vector(direction: int) -> Vector2i:
	match direction:
		EntryDirection.NORTH:
			return Vector2i(0, -1)
		EntryDirection.EAST:
			return Vector2i(1, 0)
		EntryDirection.SOUTH:
			return Vector2i(0, 1)
		EntryDirection.WEST:
			return Vector2i(-1, 0)
		_:
			return Vector2i.ZERO

static func entry_name(direction: int) -> String:
	match direction:
		EntryDirection.NORTH:
			return "NORTH"
		EntryDirection.EAST:
			return "EAST"
		EntryDirection.SOUTH:
			return "SOUTH"
		EntryDirection.WEST:
			return "WEST"
		_:
			return "UNKNOWN"
