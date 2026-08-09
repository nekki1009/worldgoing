class_name SiteFeatureState
extends RefCounted

var feature_id: String = ""
var feature_type: String = ""
var enabled: bool = true

func _init(
		p_feature_id: String = "",
		p_feature_type: String = "TEST",
		p_enabled: bool = true
	) -> void:
	feature_id = p_feature_id
	feature_type = p_feature_type
	enabled = p_enabled

func copy() -> SiteFeatureState:
	return SiteFeatureState.new(feature_id, feature_type, enabled)
