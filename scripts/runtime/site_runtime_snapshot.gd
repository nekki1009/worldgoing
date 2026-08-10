class_name SiteRuntimeSnapshot
extends RefCounted

const SiteLayoutDataType = preload("res://scripts/data/site_layout_data.gd")

var site_id: String = ""
var source_poi_id: String = ""
var site_name: String = ""
var site_type: int = WorldPOIType.VILLAGE
var parent_world_cell: Vector2i = Vector2i(-1, -1)
var parent_region_cell: Vector2i = Vector2i(-1, -1)
var global_region_cell: Vector2i = Vector2i(-1, -1)
var parent_region_id: String = ""
var parent_region_name: String = ""
var base_generation_version: int = 0
var site_seed: int = 0
var entrance_local_meters: Vector2i = Vector2i.ZERO
var entrance_global_meters: Vector2i = Vector2i.ZERO
var source_terrain_type: int = TerrainType.PLAINS
var source_elevation: float = 0.0
var source_moisture: float = 0.0
var source_river_nearby: bool = false
var source_candidate_cell: Vector2i = Vector2i.ZERO
var source_priority: float = 0.0
var layout: SiteLayoutDataType
var world_seed: int = 0
var world_time_seconds: int = 0
var party_id: String = ""
var party_global_region_cell: Vector2i = Vector2i(-1, -1)
var party_at_site: bool = false
var party_site_local_cell: Vector2i = SiteLayoutDataType.INVALID_CELL
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
