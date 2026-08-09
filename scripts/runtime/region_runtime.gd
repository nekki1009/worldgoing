class_name RegionRuntime
extends RefCounted

const RegionFeatureDeltaType = preload("res://scripts/runtime/region_feature_delta.gd")
const RegionStateResolverType = preload("res://scripts/runtime/region_state_resolver.gd")

var session: GameSession
var world_data: WorldData
var context_region: RegionData
var context_world_cell: Vector2i = Vector2i(-1, -1)
var context_terrain: RegionTerrainData
var context_pois: Array[WorldPOIData] = []
var context_roads: RegionRoadOverlay

func _init(p_session: GameSession = null, p_world_data: WorldData = null) -> void:
	bind(p_session, p_world_data)

func bind(p_session: GameSession, p_world_data: WorldData) -> void:
	session = p_session
	world_data = p_world_data

func set_region_context(
		region: RegionData,
		terrain: RegionTerrainData,
		pois: Array[WorldPOIData],
		roads: RegionRoadOverlay
	) -> void:
	context_region = region
	context_world_cell = region.world_cell if region != null else Vector2i(-1, -1)
	context_terrain = terrain
	context_pois = pois
	context_roads = roads

func clear_region_context() -> void:
	context_region = null
	context_world_cell = Vector2i(-1, -1)
	context_terrain = null
	context_pois = []
	context_roads = null

func query_region(world_cell: Vector2i) -> RegionStateResolver:
	var region: RegionData = context_region if context_world_cell == world_cell else null
	var terrain: RegionTerrainData = context_terrain if region != null else null
	var pois: Array[WorldPOIData] = []
	if region != null:
		pois = context_pois
	var roads: RegionRoadOverlay = context_roads if region != null else null
	if region == null and world_data != null:
		region = world_data.get_region(world_cell)
		if region != null:
			terrain = world_data.get_or_generate_region_terrain(
				world_cell,
				session.world_seed if session != null else GameSession.DEFAULT_WORLD_SEED
			)
			pois = _get_pois_for_region(world_cell)
			roads = world_data.get_roads_for_region(
				world_cell,
				session.world_seed if session != null else GameSession.DEFAULT_WORLD_SEED
			)
	if session == null or region == null:
		return RegionStateResolverType.new(region, terrain, pois, roads)
	var state: RegionRuntimeState = session.find_region_runtime_state(world_cell)
	var current_version: int = region.terrain_generation_version
	if current_version <= 0:
		current_version = RegionData.BASE_GENERATION_VERSION
	var delta: RegionDelta = state.delta if state != null else null
	if delta != null:
		delta.ensure_base_generation_version(current_version)
	return RegionStateResolverType.new(region, terrain, pois, roads, delta, current_version)

func _get_pois_for_region(world_cell: Vector2i) -> Array[WorldPOIData]:
	var result: Array[WorldPOIData] = []
	if world_data == null:
		return result
	var world_seed: int = session.world_seed if session != null else GameSession.DEFAULT_WORLD_SEED
	for poi: Variant in world_data.get_pois_for_region(world_cell, world_seed):
		if poi is WorldPOIData:
			result.append(poi as WorldPOIData)
	return result

func apply_test_terrain_override(world_cell: Vector2i, region_cell: Vector2i, terrain_type: int) -> bool:
	var resolver: RegionStateResolver = query_region(world_cell)
	if not resolver.is_valid() or session == null:
		return false
	return session.get_region_runtime_state(world_cell).delta.set_terrain_override(region_cell, terrain_type)

func clear_test_terrain_override(world_cell: Vector2i, region_cell: Vector2i) -> bool:
	var resolver: RegionStateResolver = query_region(world_cell)
	if not resolver.is_valid() or session == null:
		return false
	return session.get_region_runtime_state(world_cell).delta.clear_terrain_override(region_cell)

func apply_test_feature_add(
		world_cell: Vector2i,
		feature_id: String,
		feature_type: StringName,
		region_cell: Vector2i,
		payload: Dictionary = {}
	) -> bool:
	var resolver: RegionStateResolver = query_region(world_cell)
	if not resolver.is_valid() or session == null:
		return false
	return session.get_region_runtime_state(world_cell).delta.add_feature(
		RegionFeatureDeltaType.new(feature_id, feature_type, region_cell, payload)
	)

func apply_test_feature_remove(world_cell: Vector2i, feature_id: String) -> bool:
	var resolver: RegionStateResolver = query_region(world_cell)
	if not resolver.is_valid() or session == null:
		return false
	return session.get_region_runtime_state(world_cell).delta.remove_feature(feature_id)
