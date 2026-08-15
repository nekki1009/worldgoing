class_name WorldData
extends RefCounted

const SiteLayoutDataType = preload("res://scripts/data/site_layout_data.gd")
const SiteLayoutGeneratorType = preload("res://scripts/core/site_layout_generator.gd")

const WORLD_CELLS: Vector2i = Vector2i(256, 256)

var regions: Dictionary = {}
var terrain_generator: RegionTerrainGenerator = RegionTerrainGenerator.new()
var overview_generator: WorldOverviewGenerator
var site_content_generator: RegionSiteContentGenerator = RegionSiteContentGenerator.new()
var poi_generator: WorldPOIGenerator
var road_generator: WorldRoadGenerator
var world_overview: WorldOverviewData
var manifest_cache: Dictionary = {}
var poi_cache: Dictionary = {}
var poi_id_cache: Dictionary = {}
var travel_data_cache: Dictionary = {}

func _init() -> void:
	overview_generator = WorldOverviewGenerator.new(terrain_generator)
	poi_generator = WorldPOIGenerator.new(terrain_generator)
	road_generator = WorldRoadGenerator.new(terrain_generator, Callable(self, "_get_road_pois_for_generator"))
	_build_test_data()

func _build_test_data() -> void:
	# World bounds are intentionally lazy: generated RegionData is allocated only
	# when a query, view, or command needs that World Cell.
	return

func is_valid_world_cell(world_cell: Vector2i) -> bool:
	return world_cell.x >= 0 and world_cell.y >= 0 \
		and world_cell.x < WORLD_CELLS.x and world_cell.y < WORLD_CELLS.y

func get_region(world_cell: Vector2i) -> RegionData:
	if not is_valid_world_cell(world_cell):
		return null
	var existing: RegionData = regions.get(world_cell) as RegionData
	if existing != null:
		return existing
	var region: RegionData = RegionData.new(
			"region_%03d_%03d" % [world_cell.x, world_cell.y],
			world_cell,
			"Region %03d,%03d" % [world_cell.x, world_cell.y],
			_terrain_for_world_cell(world_cell)
		)
	regions[world_cell] = region
	return region

func get_or_generate_world_overview(world_seed: int) -> WorldOverviewData:
	if world_seed == 0:
		return null
	if world_overview == null or not world_overview.is_valid() or world_overview.world_seed != world_seed:
		world_overview = overview_generator.generate(world_seed, WORLD_CELLS)
		manifest_cache.clear()
	return world_overview

func get_or_generate_region_manifest(
		world_cell: Vector2i,
		world_seed: int
	) -> RegionGenerationManifest:
	if not is_valid_world_cell(world_cell) or world_seed == 0:
		return null
	var cache_key: String = "%d:%d:%d:%d" % [
		world_seed,
		world_cell.x,
		world_cell.y,
		RegionGenerationManifest.GENERATION_VERSION,
	]
	var cached: Variant = manifest_cache.get(cache_key, null)
	if cached is RegionGenerationManifest:
		return (cached as RegionGenerationManifest).copy()
	var overview: WorldOverviewData = get_or_generate_world_overview(world_seed)
	var generated: RegionGenerationManifest = overview_generator.manifest_for(
		world_seed,
		world_cell,
		overview
	)
	manifest_cache[cache_key] = generated
	return generated.copy() if generated != null else null

func get_or_generate_region_terrain(world_cell: Vector2i, world_seed: int) -> RegionTerrainData:
	var region: RegionData = get_region(world_cell)
	if region == null:
		return null
	var region_seed: int = RegionData.derive_seed(
		world_seed,
		world_cell,
		RegionTerrainGenerator.GENERATION_VERSION
	)
	if region.terrain_data == null \
		or region.source_world_seed != world_seed \
		or region.seed != region_seed \
		or region.terrain_generation_version != RegionTerrainGenerator.GENERATION_VERSION:
		region.terrain_data = terrain_generator.generate(world_seed, world_cell)
		region.generated_poi_ids.clear()
		region.generated_route_ids.clear()
		region.source_world_seed = world_seed
		region.seed = region_seed
		region.terrain_generation_version = RegionTerrainGenerator.GENERATION_VERSION
	return region.terrain_data

func get_or_generate_region_site_content(
		world_cell: Vector2i,
		world_seed: int
	) -> RegionSiteContentData:
	var region: RegionData = get_region(world_cell)
	if region == null:
		return null
	var manifest: RegionGenerationManifest = get_or_generate_region_manifest(world_cell, world_seed)
	var terrain: RegionTerrainData = get_or_generate_region_terrain(world_cell, world_seed)
	if manifest == null or terrain == null:
		return null
	if region.site_content_data == null \
		or not region.site_content_data.is_valid() \
		or region.site_content_data.world_seed != world_seed \
		or region.site_content_data.generation_version != RegionSiteContentData.GENERATION_VERSION:
		region.generation_manifest = manifest.copy()
		region.site_content_data = site_content_generator.generate(manifest, terrain)
	return region.site_content_data

func get_or_generate_region_thumbnail(world_cell: Vector2i, world_seed: int) -> PackedByteArray:
	var region: RegionData = get_region(world_cell)
	if region == null:
		return PackedByteArray()
	var region_seed: int = RegionData.derive_seed(
		world_seed,
		world_cell,
		RegionTerrainGenerator.GENERATION_VERSION
	)
	if region.terrain_thumbnail_data.size() != RegionTerrainGenerator.THUMBNAIL_CELL_COUNT \
		or region.source_world_seed != world_seed \
		or region.terrain_thumbnail_seed != region_seed \
		or region.terrain_thumbnail_generation_version != RegionTerrainGenerator.GENERATION_VERSION:
		region.terrain_thumbnail_data = terrain_generator.generate_thumbnail(world_seed, world_cell)
		region.source_world_seed = world_seed
		region.terrain_thumbnail_seed = region_seed
		region.terrain_thumbnail_generation_version = RegionTerrainGenerator.GENERATION_VERSION
	return region.terrain_thumbnail_data

func get_pois_for_region(world_cell: Vector2i, world_seed: int) -> Array[WorldPOIData]:
	var region: RegionData = get_region(world_cell)
	var generated: Array[WorldPOIData] = _get_pois_for_generator(world_cell, world_seed)
	_record_generated_poi_ids(region, generated)
	return _copy_pois(generated)

func _get_pois_for_generator(world_cell: Vector2i, world_seed: int) -> Array[WorldPOIData]:
	var cache_key: String = "poi:%d:%d:%d:%d" % [
		world_seed,
		world_cell.x,
		world_cell.y,
		WorldPOIGenerator.GENERATION_VERSION * 100 + RegionTerrainGenerator.GENERATION_VERSION
	]
	var cached: Variant = poi_cache.get(cache_key, null)
	if cached is Array:
		return cached as Array[WorldPOIData]
	var generated: Array[WorldPOIData] = poi_generator.generate_for_region(world_seed, world_cell)
	poi_cache[cache_key] = generated
	for poi: WorldPOIData in generated:
		poi_id_cache[_poi_id_cache_key(world_seed, poi.poi_id)] = poi
	return generated

func _get_road_pois_for_generator(world_cell: Vector2i, world_seed: int) -> Array[WorldPOIData]:
	if not is_valid_world_cell(world_cell):
		return []
	return _get_pois_for_generator(world_cell, world_seed)

func clear_poi_cache() -> void:
	poi_cache.clear()
	# Stable POI identity references remain available to Runtime queries; only
	# the generated Region arrays are discarded.
	poi_generator.clear_cache()
	for region: RegionData in regions.values():
		region.generated_poi_ids.clear()

func get_roads_for_region(world_cell: Vector2i, world_seed: int) -> RegionRoadOverlay:
	var overlay: RegionRoadOverlay = road_generator.get_roads_for_region(world_cell, world_seed)
	_record_generated_route_ids(get_region(world_cell), get_route_edges_for_region(world_cell, world_seed))
	return overlay

func get_route_edges_for_region(world_cell: Vector2i, world_seed: int) -> Array[WorldRoadRoute]:
	var routes: Array[WorldRoadRoute] = road_generator.get_route_edges_for_region(world_cell, world_seed)
	_record_generated_route_ids(get_region(world_cell), routes)
	return routes

func clear_road_cache() -> void:
	road_generator.clear_cache()
	travel_data_cache.clear()
	for region: RegionData in regions.values():
		region.generated_route_ids.clear()

func clear_generated_cache() -> void:
	for region: RegionData in regions.values():
		region.terrain_data = null
		region.source_world_seed = 0
		region.seed = 0
		region.terrain_generation_version = 0
		region.terrain_thumbnail_data = PackedByteArray()
		region.terrain_thumbnail_seed = 0
		region.terrain_thumbnail_generation_version = 0
		region.generated_poi_ids.clear()
		region.generated_route_ids.clear()
		region.generation_manifest = null
		region.site_content_data = null
	poi_cache.clear()
	# Deterministic POI identity references stay available to detached Runtime
	# queries even when generated terrain/POI arrays are discarded.
	poi_generator.clear_cache()
	road_generator.clear_cache()
	travel_data_cache.clear()
	manifest_cache.clear()
	world_overview = null

func sample_travel_data(world_seed: int, global_region_cell: Vector2i) -> Dictionary:
	var cache_key: String = "travel:%d:%d:%d" % [world_seed, global_region_cell.x, global_region_cell.y]
	var cached: Variant = travel_data_cache.get(cache_key, null)
	if cached is Dictionary:
		return cached as Dictionary
	var macro_sample: Vector4 = terrain_generator.macro_sampler.sample(world_seed, global_region_cell)
	var terrain_type: int = terrain_generator.classify_region_sample(
		world_seed,
		global_region_cell,
		macro_sample
	)
	var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(global_region_cell)
	var world_cell: Vector2i = converted["world_cell"] as Vector2i
	var region_cell: Vector2i = converted["region_cell"] as Vector2i
	# Travel sampling only needs the generated overlay; Region metadata is recorded by the public Region query.
	var road_overlay: RegionRoadOverlay = road_generator.get_roads_for_region(world_cell, world_seed)
	var road: bool = road_overlay != null and road_overlay.has_road(region_cell)
	var road_connection_offsets: Array[Vector2i] = []
	if road_overlay != null and road:
		road_connection_offsets = road_overlay.get_connection_offsets(region_cell, global_region_cell)
	var river: bool = macro_sample.z > 0.0
	var river_crossing: bool = road_overlay != null and road_overlay.has_river_crossing(region_cell)
	var passable: bool = TravelCostConfig.is_passable(terrain_type, river, river_crossing)
	var site_landform: int = SiteLayoutDataType.landform_for_travel_cell(
		terrain_type,
		road_connection_offsets
	)
	var result: Dictionary = {
		"passable": passable,
		"terrain_type": terrain_type,
		"site_landform": site_landform,
		"travel_exit_mask": SiteLayoutDataType.exit_mask_for_travel_cell(
			passable,
			site_landform,
			road_connection_offsets
		),
		"road": road,
		"road_connection_offsets": road_connection_offsets,
		"river": river,
		"river_crossing": river_crossing,
		"elevation": macro_sample.x,
		"moisture": macro_sample.y,
		"river_strength": macro_sample.z,
		"travel_speed_kmh": TravelCostConfig.get_speed_kmh(
			terrain_type,
			road,
			TravelCostConfig.DEFAULT_WALK_SPEED_KMH
		),
		"global_region_cell": global_region_cell,
		"world_cell": world_cell,
		"region_cell": region_cell,
	}
	var profile: Dictionary = _site_content_profile_for(world_cell, region_cell, world_seed)
	for key: Variant in profile.keys():
		result[key] = profile[key]
	travel_data_cache[cache_key] = result
	return result

func _site_content_profile_for(
		world_cell: Vector2i,
		region_cell: Vector2i,
		world_seed: int
	) -> Dictionary:
	var region: RegionData = regions.get(world_cell) as RegionData
	if region != null and region.site_content_data != null \
		and region.site_content_data.world_seed == world_seed:
		return region.site_content_data.profile_at(region_cell)
	var global_cell: Vector2i = WorldCoordinates.world_region_to_global_region_cell(
		world_cell,
		region_cell
	)
	var sample: Vector4 = terrain_generator.macro_sampler.sample(world_seed, global_cell)
	var terrain_type: int = terrain_generator.classify_region_sample(
		world_seed,
		global_cell,
		sample
	)
	var amounts: PackedInt32Array = PackedInt32Array()
	amounts.resize(SiteContentTypes.RESOURCE_COUNT)
	for resource_type: int in range(SiteContentTypes.RESOURCE_COUNT):
		amounts[resource_type] = maxi(0, DeterministicHash.int_range(
			world_seed,
			global_cell,
			73_000 + resource_type,
			0,
			_site_profile_resource_max(terrain_type, resource_type)
		))
	return {
		"native_surface_hint": _native_surface_hint(terrain_type),
		"rock_ratio": 0.82 if terrain_type == TerrainType.MOUNTAIN else 0.08,
		"river_width_class": clampi(ceili(sample.z * 3.0), 0, 3),
		"coast_mask": 0,
		"resource_amounts": amounts,
	}

func _native_surface_hint(terrain_type: int) -> int:
	if terrain_type == TerrainType.OCEAN:
		return SiteContentTypes.NativeSurface.SEA_WATER
	if terrain_type == TerrainType.WATER:
		return SiteContentTypes.NativeSurface.RIVER_WATER
	if terrain_type == TerrainType.MOUNTAIN:
		return SiteContentTypes.NativeSurface.ROCK
	return SiteContentTypes.NativeSurface.DIRT

func _site_profile_resource_max(terrain_type: int, resource_type: int) -> int:
	match resource_type:
		SiteContentTypes.RESOURCE_GRASS:
			return 140 if not TerrainType.is_water_like(terrain_type) else 0
		SiteContentTypes.RESOURCE_FRUIT_TREE:
			return 18 if terrain_type in [TerrainType.PLAINS, TerrainType.FOREST, TerrainType.SWAMP] else 0
		SiteContentTypes.RESOURCE_FOREST:
			return 80 if terrain_type in [TerrainType.FOREST, TerrainType.PLAINS] else 0
		SiteContentTypes.RESOURCE_STONE_ORE:
			return 90 if terrain_type in [TerrainType.MOUNTAIN, TerrainType.SNOW] else 8
		SiteContentTypes.RESOURCE_IRON_ORE:
			return 28 if terrain_type == TerrainType.MOUNTAIN else 0
		SiteContentTypes.RESOURCE_SILVER_ORE:
			return 8 if terrain_type == TerrainType.MOUNTAIN else 0
		SiteContentTypes.RESOURCE_GOLD_ORE:
			return 3 if terrain_type == TerrainType.MOUNTAIN else 0
	return 0

func find_nearest_passable_global_cell(
		world_cell: Vector2i,
		center_region_cell: Vector2i,
		world_seed: int
	) -> Vector2i:
	var center: Vector2i = Vector2i(
		clampi(center_region_cell.x, 0, WorldCoordinates.REGION_GRID_SIZE - 1),
		clampi(center_region_cell.y, 0, WorldCoordinates.REGION_GRID_SIZE - 1)
	)
	for radius: int in range(WorldCoordinates.REGION_GRID_SIZE):
		var min_x: int = maxi(0, center.x - radius)
		var max_x: int = mini(WorldCoordinates.REGION_GRID_SIZE - 1, center.x + radius)
		var min_y: int = maxi(0, center.y - radius)
		var max_y: int = mini(WorldCoordinates.REGION_GRID_SIZE - 1, center.y + radius)
		for y: int in range(min_y, max_y + 1):
			for x: int in range(min_x, max_x + 1):
				var region_cell: Vector2i = Vector2i(x, y)
				if maxi(absi(x - center.x), absi(y - center.y)) != radius:
					continue
				var global_cell: Vector2i = WorldCoordinates.world_region_to_global_region_cell(
					world_cell,
					region_cell
				)
				if bool(sample_travel_data(world_seed, global_cell).get("passable", false)):
					return global_cell
	return Vector2i(-1, -1)

func find_poi_at(world_cell: Vector2i, region_cell: Vector2i, world_seed: int) -> WorldPOIData:
	for poi: WorldPOIData in get_pois_for_region(world_cell, world_seed):
		if poi.region_cell == region_cell:
			return poi
	return null

func find_poi_by_id(poi_id: String, world_seed: int) -> WorldPOIData:
	if poi_id.is_empty():
		return null
	return poi_id_cache.get(_poi_id_cache_key(world_seed, poi_id)) as WorldPOIData

func get_site_definition(poi: WorldPOIData) -> SiteData:
	var definition: SiteData = SiteData.from_poi(poi)
	if definition == null:
		return null
	var travel_data: Dictionary = sample_travel_data(poi.generation_seed, poi.global_region_cell)
	definition.site_landform = int(travel_data.get(
		"site_landform",
		SiteLayoutDataType.Landform.NONE
	))
	definition.travel_exit_mask = int(travel_data.get(
		"travel_exit_mask",
		SiteLayoutDataType.EXIT_ALL
	))
	definition.apply_content_profile(travel_data)
	return definition

func get_site_definition_at(
		world_cell: Vector2i,
		region_cell: Vector2i,
		world_seed: int
	) -> SiteData:
	if not is_valid_world_cell(world_cell) or not WorldCoordinates.is_valid_region_cell(region_cell):
		return null
	var poi: WorldPOIData = find_poi_at(world_cell, region_cell, world_seed)
	if poi != null:
		return get_site_definition(poi)
	var global_cell: Vector2i = WorldCoordinates.world_region_to_global_region_cell(
		world_cell,
		region_cell
	)
	return SiteData.from_region_cell(
		world_seed,
		world_cell,
		region_cell,
		sample_travel_data(world_seed, global_cell)
	)

func get_site_definition_by_id(site_id: String, world_seed: int) -> SiteData:
	if site_id.is_empty():
		return null
	var poi: WorldPOIData = find_poi_by_id(site_id, world_seed)
	if poi != null:
		return get_site_definition(poi)
	var parts: PackedStringArray = site_id.split("_")
	if parts.size() != 4 or parts[0] != "site" or parts[1] != "cell":
		return null
	if not _is_integer_string(parts[2]) or not _is_integer_string(parts[3]):
		return null
	var global_cell: Vector2i = Vector2i(int(parts[2]), int(parts[3]))
	var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(global_cell)
	var world_cell: Vector2i = converted["world_cell"] as Vector2i
	var region_cell: Vector2i = converted["region_cell"] as Vector2i
	return get_site_definition_at(world_cell, region_cell, world_seed)

func get_site_layout(definition: SiteData) -> SiteLayoutDataType:
	return SiteLayoutGeneratorType.generate(definition)

func get_sites_for_region(world_cell: Vector2i, world_seed: int) -> Array[SiteData]:
	var result: Array[SiteData] = []
	for poi: WorldPOIData in get_pois_for_region(world_cell, world_seed):
		var definition: SiteData = get_site_definition(poi)
		if definition != null:
			result.append(definition)
	return result

func find_site_at(world_cell: Vector2i, region_cell: Vector2i, world_seed: int) -> SiteData:
	return get_site_definition_at(world_cell, region_cell, world_seed)

func _is_integer_string(value: String) -> bool:
	return not value.is_empty() and value.is_valid_int()

func _copy_pois(source: Array) -> Array[WorldPOIData]:
	var result: Array[WorldPOIData] = []
	for item: Variant in source:
		if item is WorldPOIData:
			result.append(item as WorldPOIData)
	return result

func _record_generated_poi_ids(region: RegionData, source: Array) -> void:
	if region == null:
		return
	region.generated_poi_ids.clear()
	for item: Variant in source:
		if item is WorldPOIData:
			region.generated_poi_ids.append((item as WorldPOIData).poi_id)

func _record_generated_route_ids(region: RegionData, source: Array[WorldRoadRoute]) -> void:
	if region == null:
		return
	region.generated_route_ids.clear()
	for route: WorldRoadRoute in source:
		region.generated_route_ids.append(route.route_id)

func _terrain_for_world_cell(world_cell: Vector2i) -> String:
	var terrain_index: int = posmod(world_cell.x + world_cell.y * 3, TerrainType.COUNT)
	return TerrainType.to_display_name(terrain_index)

func _poi_id_cache_key(world_seed: int, poi_id: String) -> String:
	return "%d|%s" % [world_seed, poi_id]
