class_name RegionStateResolver
extends RefCounted

const RegionFeatureDeltaType = preload("res://scripts/runtime/region_feature_delta.gd")

var base_region: RegionData
var base_terrain: RegionTerrainData
var base_pois: Array[WorldPOIData] = []
var base_roads: RegionRoadOverlay
var delta: RegionDelta
var valid: bool = false
var failure_code: StringName = &""

func _init(
		p_base_region: RegionData,
		p_base_terrain: RegionTerrainData,
		p_base_pois: Array[WorldPOIData],
		p_base_roads: RegionRoadOverlay,
		p_delta: RegionDelta = null,
		p_base_generation_version: int = 0
	) -> void:
	base_region = p_base_region
	base_terrain = p_base_terrain
	base_pois = p_base_pois
	base_roads = p_base_roads
	delta = p_delta
	if base_region == null or base_terrain == null:
		failure_code = &"INVALID_REGION_BASE"
		return
	if delta != null and delta.world_cell != base_region.world_cell:
		failure_code = &"DELTA_REGION_MISMATCH"
		return
	var expected_version: int = p_base_generation_version
	if expected_version <= 0:
		expected_version = base_region.terrain_generation_version
	if delta != null and delta.base_generation_version != expected_version:
		failure_code = &"DELTA_BASE_VERSION_MISMATCH"
		return
	valid = true

func is_valid() -> bool:
	return valid

func get_terrain(region_cell: Vector2i) -> int:
	if not valid or not WorldCoordinates.is_valid_region_cell(region_cell):
		return -1
	if delta != null and delta.has_terrain_override(region_cell):
		return delta.get_terrain_override(region_cell)
	return base_terrain.get_terrain(region_cell)

func get_base_terrain(region_cell: Vector2i) -> int:
	if not valid:
		return -1
	return base_terrain.get_terrain(region_cell)

func get_elevation(region_cell: Vector2i) -> float:
	return base_terrain.get_elevation(region_cell) if valid else 0.0

func get_moisture(region_cell: Vector2i) -> float:
	return base_terrain.get_moisture(region_cell) if valid else 0.0

func get_river_strength(region_cell: Vector2i) -> float:
	return base_terrain.get_river_strength(region_cell) if valid else 0.0

func has_river(region_cell: Vector2i) -> bool:
	return get_river_strength(region_cell) > 0.0

func has_road(region_cell: Vector2i) -> bool:
	if not valid or not WorldCoordinates.is_valid_region_cell(region_cell):
		return false
	if base_roads != null:
		for route_id: String in base_roads.get_route_ids(region_cell):
			if _is_active(route_id):
				return true
	if delta != null:
		for item: Variant in delta.added_features.values():
			if item is RegionFeatureDelta:
				var feature: RegionFeatureDelta = item as RegionFeatureDelta
				if feature.feature_type == &"road" and feature.region_cell == region_cell and _is_active(feature.feature_id):
					return true
	return false

func has_river_crossing(region_cell: Vector2i) -> bool:
	if not valid or not WorldCoordinates.is_valid_region_cell(region_cell):
		return false
	var global_cell: Vector2i = WorldCoordinates.world_region_to_global_region_cell(
			base_region.world_cell,
			region_cell
		)
	if base_roads != null:
		for route_id: String in base_roads.get_route_ids(region_cell):
			if not _is_active(route_id):
				continue
			var route: WorldRoadRoute = base_roads.get_route(route_id)
			if route != null and route.river_crossing_cells.has(global_cell):
				return true
	if delta != null:
		for item: Variant in delta.added_features.values():
			if item is RegionFeatureDelta:
				var feature: RegionFeatureDelta = item as RegionFeatureDelta
				if feature.feature_type == &"road" and feature.region_cell == region_cell \
					and _is_active(feature.feature_id) \
					and bool(feature.payload.get("river_crossing", false)):
					return true
	return false

func get_owner() -> String:
	return delta.owner_id if valid and delta != null else "neutral"

func get_development_level() -> int:
	return delta.development_level if valid and delta != null else 0

func get_features_at(region_cell: Vector2i) -> Array[RegionFeatureDelta]:
	var result: Array[RegionFeatureDelta] = []
	if not valid or not WorldCoordinates.is_valid_region_cell(region_cell):
		return result
	for poi: WorldPOIData in base_pois:
		if poi.region_cell == region_cell and _is_active(poi.poi_id):
			result.append(RegionFeatureDeltaType.new(
				poi.poi_id,
				&"poi",
				poi.region_cell,
				{"poi_id": poi.poi_id}
			))
	if base_roads != null:
		for route_id: String in base_roads.get_route_ids(region_cell):
			if _is_active(route_id):
				result.append(RegionFeatureDeltaType.new(
					route_id,
					&"road",
					region_cell,
					{"route_id": route_id}
				))
	if delta != null:
		for item: Variant in delta.added_features.values():
			if item is RegionFeatureDelta:
				var feature: RegionFeatureDelta = item as RegionFeatureDelta
				if feature.region_cell == region_cell and _is_active(feature.feature_id):
					result.append(feature.copy())
	result.sort_custom(Callable(self, "_feature_less"))
	return result

func has_feature(feature_id: String) -> bool:
	if not valid or feature_id.is_empty() or not _is_active(feature_id):
		return false
	if delta != null and delta.added_features.has(feature_id):
		return true
	for poi: WorldPOIData in base_pois:
		if poi.poi_id == feature_id:
			return true
	if base_roads == null:
		return false
	for y: int in range(WorldCoordinates.REGION_GRID_SIZE):
		for x: int in range(WorldCoordinates.REGION_GRID_SIZE):
			if base_roads.get_route_ids(Vector2i(x, y)).has(feature_id):
				return true
	return false

func is_feature_active(feature_id: String) -> bool:
	return valid and _is_active(feature_id)

func _is_active(feature_id: String) -> bool:
	return delta == null or not delta.is_feature_removed(feature_id)

func _feature_less(left: RegionFeatureDelta, right: RegionFeatureDelta) -> bool:
	return left.feature_id < right.feature_id
