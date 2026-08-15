class_name SiteFeatureState
extends RefCounted

var feature_id: String = ""
var feature_type: String = ""
var enabled: bool = true
var placement: Dictionary = {}

func _init(
		p_feature_id: String = "",
		p_feature_type: String = "TEST",
		p_enabled: bool = true,
		p_placement: Dictionary = {}
	) -> void:
	feature_id = p_feature_id
	feature_type = p_feature_type
	enabled = p_enabled
	placement = p_placement.duplicate(true)

func copy() -> SiteFeatureState:
	return SiteFeatureState.new(feature_id, feature_type, enabled, placement)
