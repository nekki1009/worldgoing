class_name SiteRuntimeSnapshot
extends RefCounted

var site_id: String = ""
var source_poi_id: String = ""
var parent_world_cell: Vector2i = Vector2i(-1, -1)
var parent_region_cell: Vector2i = Vector2i(-1, -1)
var global_region_cell: Vector2i = Vector2i(-1, -1)
var revision: int = 0
var runtime_allocated: bool = false
var architecture_test_flag: bool = false
var added_features: Array[SiteFeatureState] = []
var removed_feature_ids: Array[String] = []

func has_feature(feature_id: String) -> bool:
	for feature: SiteFeatureState in added_features:
		if feature.feature_id == feature_id and feature.enabled:
			return true
	return false
