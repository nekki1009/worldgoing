class_name SiteRuntimeState
extends RefCounted

const SiteRuntimeFailureReasonType = preload("res://scripts/runtime/site_runtime_failure_reason.gd")
const SiteRuntimeSnapshotType = preload("res://scripts/runtime/site_runtime_snapshot.gd")

var site_id: String = ""
var source_poi_id: String = ""
var parent_world_cell: Vector2i = Vector2i(-1, -1)
var parent_region_cell: Vector2i = Vector2i(-1, -1)
var global_region_cell: Vector2i = Vector2i(-1, -1)
var base_generation_version: int = 0
var site_seed: int = 0
var revision: int = 0
var architecture_test_flag: bool = false
var added_features: Array[SiteFeatureState] = []
var removed_feature_ids: Array[String] = []

func _init(p_definition: SiteData = null) -> void:
	if p_definition != null:
		site_id = p_definition.site_id
		source_poi_id = p_definition.source_poi_id
		parent_world_cell = p_definition.parent_world_cell
		parent_region_cell = p_definition.parent_region_cell
		global_region_cell = p_definition.global_region_cell
		base_generation_version = p_definition.base_generation_version
		site_seed = p_definition.site_seed

func matches_definition(definition: SiteData) -> bool:
	return definition != null \
		and site_id == definition.site_id \
		and source_poi_id == definition.source_poi_id \
		and parent_world_cell == definition.parent_world_cell \
		and parent_region_cell == definition.parent_region_cell \
		and global_region_cell == definition.global_region_cell \
		and base_generation_version == definition.base_generation_version \
		and site_seed == definition.site_seed

func set_test_flag(value: bool) -> bool:
	if architecture_test_flag == value:
		return false
	architecture_test_flag = value
	revision += 1
	return true

func add_feature(feature: SiteFeatureState) -> int:
	if feature == null or feature.feature_id.is_empty():
		return SiteRuntimeFailureReasonType.Code.INVALID_FEATURE_ID
	if has_feature(feature.feature_id) or removed_feature_ids.has(feature.feature_id):
		return SiteRuntimeFailureReasonType.Code.DUPLICATE_FEATURE
	added_features.append(feature.copy())
	revision += 1
	return SiteRuntimeFailureReasonType.Code.NONE

func remove_feature(feature_id: String) -> int:
	if feature_id.is_empty():
		return SiteRuntimeFailureReasonType.Code.INVALID_FEATURE_ID
	for index: int in range(added_features.size()):
		if added_features[index].feature_id == feature_id:
			added_features.remove_at(index)
			revision += 1
			return SiteRuntimeFailureReasonType.Code.NONE
	return SiteRuntimeFailureReasonType.Code.FEATURE_NOT_FOUND

func mark_generated_feature_removed(feature_id: String) -> int:
	if feature_id.is_empty():
		return SiteRuntimeFailureReasonType.Code.INVALID_FEATURE_ID
	if removed_feature_ids.has(feature_id):
		return SiteRuntimeFailureReasonType.Code.FEATURE_NOT_FOUND
	removed_feature_ids.append(feature_id)
	revision += 1
	return SiteRuntimeFailureReasonType.Code.NONE

func has_feature(feature_id: String) -> bool:
	for feature: SiteFeatureState in added_features:
		if feature.feature_id == feature_id and feature.enabled:
			return true
	return false

func to_snapshot(allocated: bool = true) -> SiteRuntimeSnapshot:
	var snapshot: SiteRuntimeSnapshot = SiteRuntimeSnapshotType.new()
	snapshot.site_id = site_id
	snapshot.source_poi_id = source_poi_id
	snapshot.parent_world_cell = parent_world_cell
	snapshot.parent_region_cell = parent_region_cell
	snapshot.global_region_cell = global_region_cell
	snapshot.base_generation_version = base_generation_version
	snapshot.site_seed = site_seed
	snapshot.revision = revision
	snapshot.runtime_allocated = allocated
	snapshot.architecture_test_flag = architecture_test_flag
	for feature: SiteFeatureState in added_features:
		snapshot.added_features.append(feature.copy())
	snapshot.removed_feature_ids.append_array(removed_feature_ids)
	return snapshot
