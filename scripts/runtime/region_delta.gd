class_name RegionDelta
extends RefCounted

const RegionFeatureDeltaType = preload("res://scripts/runtime/region_feature_delta.gd")

var world_cell: Vector2i = Vector2i.ZERO
var base_generation_version: int = 0
var revision: int = 0
var terrain_overrides: Dictionary = {}
var added_features: Dictionary = {}
var removed_feature_ids: Dictionary = {}
var owner_id: String = "neutral"
var development_level: int = 0

func _init(
		p_world_cell: Vector2i = Vector2i.ZERO,
		p_base_generation_version: int = RegionData.BASE_GENERATION_VERSION
	) -> void:
	world_cell = p_world_cell
	base_generation_version = p_base_generation_version

func set_terrain_override(region_cell: Vector2i, terrain_type: int) -> bool:
	if not WorldCoordinates.is_valid_region_cell(region_cell) or not TerrainType.is_valid(terrain_type):
		return false
	if terrain_overrides.get(region_cell, null) == terrain_type:
		return false
	terrain_overrides[region_cell] = terrain_type
	revision += 1
	return true

func clear_terrain_override(region_cell: Vector2i) -> bool:
	if not terrain_overrides.has(region_cell):
		return false
	terrain_overrides.erase(region_cell)
	revision += 1
	return true

func has_terrain_override(region_cell: Vector2i) -> bool:
	return terrain_overrides.has(region_cell)

func get_terrain_override(region_cell: Vector2i, fallback: int = -1) -> int:
	return int(terrain_overrides.get(region_cell, fallback))

func add_feature(feature: RegionFeatureDelta) -> bool:
	if feature == null or feature.feature_id.is_empty() \
		or not WorldCoordinates.is_valid_region_cell(feature.region_cell):
		return false
	var feature_copy: RegionFeatureDelta = feature.copy()
	var previous: Variant = added_features.get(feature_copy.feature_id, null)
	if previous is RegionFeatureDelta \
		and _same_feature(previous as RegionFeatureDelta, feature_copy):
		return false
	added_features[feature_copy.feature_id] = feature_copy
	removed_feature_ids.erase(feature_copy.feature_id)
	revision += 1
	return true

func add_feature_record(
		feature_id: String,
		feature_type: StringName,
		region_cell: Vector2i,
		payload: Dictionary = {}
	) -> bool:
	return add_feature(RegionFeatureDeltaType.new(feature_id, feature_type, region_cell, payload))

func remove_feature(feature_id: String) -> bool:
	if feature_id.is_empty():
		return false
	if added_features.has(feature_id):
		added_features.erase(feature_id)
		revision += 1
		return true
	if removed_feature_ids.has(feature_id):
		return false
	removed_feature_ids[feature_id] = true
	revision += 1
	return true

func is_feature_removed(feature_id: String) -> bool:
	return removed_feature_ids.has(feature_id)

func set_owner(value: String) -> bool:
	if owner_id == value:
		return false
	owner_id = value
	revision += 1
	return true

func set_development_level(value: int) -> bool:
	if value < 0 or development_level == value:
		return false
	development_level = value
	revision += 1
	return true

func copy() -> RegionDelta:
	var result: RegionDelta = RegionDelta.new(world_cell, base_generation_version)
	result.revision = revision
	result.terrain_overrides = terrain_overrides.duplicate()
	for feature_id: Variant in added_features.keys():
		var feature: Variant = added_features[feature_id]
		if feature is RegionFeatureDelta:
			result.added_features[feature_id] = (feature as RegionFeatureDelta).copy()
	result.removed_feature_ids = removed_feature_ids.duplicate()
	result.owner_id = owner_id
	result.development_level = development_level
	return result

func terrain_override_count() -> int:
	return terrain_overrides.size()

func added_feature_count() -> int:
	return added_features.size()

func is_empty() -> bool:
	return terrain_overrides.is_empty() \
		and added_features.is_empty() \
		and removed_feature_ids.is_empty() \
		and owner_id == "neutral" \
		and development_level == 0

func _same_feature(left: RegionFeatureDelta, right: RegionFeatureDelta) -> bool:
	return left.feature_id == right.feature_id \
		and left.feature_type == right.feature_type \
		and left.region_cell == right.region_cell \
		and left.payload == right.payload
