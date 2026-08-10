class_name BattleParticipantData
extends RefCounted

enum CommanderKind {
	PLAYER,
	NPC,
}

var participant_id: String = ""
var display_name: String = ""
var total_personnel: int = 0
var commander_id: String = ""
var commander_kind: int = CommanderKind.NPC
var commander_formation_index: int = 0

func _init(
		p_participant_id: String = "",
		p_display_name: String = "",
		p_total_personnel: int = 0,
		p_commander_id: String = "",
		p_commander_kind: int = CommanderKind.NPC,
		p_commander_formation_index: int = 0
	) -> void:
	participant_id = p_participant_id
	display_name = p_display_name
	total_personnel = maxi(p_total_personnel, 0)
	commander_id = p_commander_id if not p_commander_id.strip_edges().is_empty() \
		else participant_id
	commander_kind = p_commander_kind
	commander_formation_index = maxi(p_commander_formation_index, 0)

func copy() -> BattleParticipantData:
	return BattleParticipantData.new(
		participant_id,
		display_name,
		total_personnel,
		commander_id,
		commander_kind,
		commander_formation_index
	)

func has_valid_commander() -> bool:
	return not commander_id.strip_edges().is_empty() \
		and commander_kind >= CommanderKind.PLAYER \
		and commander_kind <= CommanderKind.NPC
