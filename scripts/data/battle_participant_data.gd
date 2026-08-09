class_name BattleParticipantData
extends RefCounted

var participant_id: String = ""
var display_name: String = ""
var total_personnel: int = 0

func _init(
		p_participant_id: String = "",
		p_display_name: String = "",
		p_total_personnel: int = 0
	) -> void:
	participant_id = p_participant_id
	display_name = p_display_name
	total_personnel = maxi(p_total_personnel, 0)

func copy() -> BattleParticipantData:
	return BattleParticipantData.new(participant_id, display_name, total_personnel)
