class_name RegionFeatureDelta
extends RefCounted

var feature_id: String = ""
var feature_type: StringName = &""
var region_cell: Vector2i = Vector2i.ZERO
var payload: Dictionary = {}

func _init(
		p_feature_id: String = "",
		p_feature_type: StringName = &"",
		p_region_cell: Vector2i = Vector2i.ZERO,
		p_payload: Dictionary = {}
	) -> void:
	feature_id = p_feature_id
	feature_type = p_feature_type
	region_cell = p_region_cell
	payload = p_payload.duplicate(true)

func copy() -> RegionFeatureDelta:
	return RegionFeatureDelta.new(feature_id, feature_type, region_cell, payload)
