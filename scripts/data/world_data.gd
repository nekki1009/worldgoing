class_name WorldData
extends RefCounted

const WORLD_CELLS: Vector2i = Vector2i(10, 10)

var regions: Dictionary = {}
var sites_by_region: Dictionary = {}
var terrain_generator: RegionTerrainGenerator = RegionTerrainGenerator.new()
var poi_generator: WorldPOIGenerator
var road_generator: WorldRoadGenerator
var poi_cache: Dictionary = {}
var travel_data_cache: Dictionary = {}

func _init() -> void:
	poi_generator = WorldPOIGenerator.new(terrain_generator)
	road_generator = WorldRoadGenerator.new(terrain_generator, Callable(self, "get_pois_for_region"))
	_build_test_data()

func _build_test_data() -> void:
	for y: int in range(WORLD_CELLS.y):
		for x: int in range(WORLD_CELLS.x):
			var world_cell: Vector2i = Vector2i(x, y)
			var terrain_type: String = _terrain_for_world_cell(world_cell)
			var region_id: String = "region_%02d_%02d" % [x, y]
			var region: RegionData = RegionData.new(
				region_id,
				world_cell,
				"Region %02d,%02d" % [x, y],
				terrain_type
			)
			regions[world_cell] = region

			var sites: Array[SiteData] = []
			sites.append(SiteData.new("test_village", "Test Village", Vector2i(50, 50), "Village"))
			sites_by_region[world_cell] = sites

func is_valid_world_cell(world_cell: Vector2i) -> bool:
	return world_cell.x >= 0 and world_cell.y >= 0 \
		and world_cell.x < WORLD_CELLS.x and world_cell.y < WORLD_CELLS.y

func get_region(world_cell: Vector2i) -> RegionData:
	return regions.get(world_cell) as RegionData

func get_or_generate_region_terrain(world_cell: Vector2i, world_seed: int) -> RegionTerrainData:
	var region: RegionData = get_region(world_cell)
	if region == null:
		return null
	if region.terrain_data == null \
		or region.seed != world_seed \
		or region.terrain_generation_version != RegionTerrainGenerator.GENERATION_VERSION:
		region.terrain_data = terrain_generator.generate(world_seed, world_cell)
		region.seed = world_seed
		region.terrain_generation_version = RegionTerrainGenerator.GENERATION_VERSION
	return region.terrain_data

func get_or_generate_region_thumbnail(world_cell: Vector2i, world_seed: int) -> PackedByteArray:
	var region: RegionData = get_region(world_cell)
	if region == null:
		return PackedByteArray()
	if region.terrain_thumbnail_data.size() != RegionTerrainGenerator.THUMBNAIL_CELL_COUNT \
		or region.terrain_thumbnail_seed != world_seed \
		or region.terrain_thumbnail_generation_version != RegionTerrainGenerator.GENERATION_VERSION:
		region.terrain_thumbnail_data = terrain_generator.generate_thumbnail(world_seed, world_cell)
		region.terrain_thumbnail_seed = world_seed
		region.terrain_thumbnail_generation_version = RegionTerrainGenerator.GENERATION_VERSION
	return region.terrain_thumbnail_data

func get_pois_for_region(world_cell: Vector2i, world_seed: int) -> Array[WorldPOIData]:
	var cache_key: String = "poi:%d:%d:%d:%d" % [
		world_seed,
		world_cell.x,
		world_cell.y,
		WorldPOIGenerator.GENERATION_VERSION * 100 + RegionTerrainGenerator.GENERATION_VERSION
	]
	var cached: Variant = poi_cache.get(cache_key, null)
	if cached is Array:
		return _copy_pois(cached)
	var generated: Array[WorldPOIData] = poi_generator.generate_for_region(world_seed, world_cell)
	poi_cache[cache_key] = generated
	return _copy_pois(generated)

func clear_poi_cache() -> void:
	poi_cache.clear()

func get_roads_for_region(world_cell: Vector2i, world_seed: int) -> RegionRoadOverlay:
	return road_generator.get_roads_for_region(world_cell, world_seed)

func get_route_edges_for_region(world_cell: Vector2i, world_seed: int) -> Array[WorldRoadRoute]:
	return road_generator.get_route_edges_for_region(world_cell, world_seed)

func clear_road_cache() -> void:
	road_generator.clear_cache()
	travel_data_cache.clear()

func sample_travel_data(world_seed: int, global_region_cell: Vector2i) -> Dictionary:
	var cache_key: String = "travel:%d:%d:%d" % [world_seed, global_region_cell.x, global_region_cell.y]
	var cached: Variant = travel_data_cache.get(cache_key, null)
	if cached is Dictionary:
		return cached as Dictionary
	var macro_sample: Vector3 = terrain_generator.macro_sampler.sample(world_seed, global_region_cell)
	var terrain_type: int = terrain_generator.classify_sample(macro_sample)
	var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(global_region_cell)
	var world_cell: Vector2i = converted["world_cell"] as Vector2i
	var region_cell: Vector2i = converted["region_cell"] as Vector2i
	var road_overlay: RegionRoadOverlay = get_roads_for_region(world_cell, world_seed)
	var road: bool = road_overlay != null and road_overlay.has_road(region_cell)
	var river: bool = macro_sample.z > 0.0
	var river_crossing: bool = road_overlay != null and road_overlay.has_river_crossing(region_cell)
	var result: Dictionary = {
		"passable": TravelCostConfig.is_passable(terrain_type, river, river_crossing),
		"terrain_type": terrain_type,
		"road": road,
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
	travel_data_cache[cache_key] = result
	return result

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

func get_sites_for_region(world_cell: Vector2i) -> Array[SiteData]:
	var result: Array[SiteData] = []
	var stored_sites: Variant = sites_by_region.get(world_cell, [])
	if stored_sites is Array:
		for site: Variant in stored_sites:
			if site is SiteData:
				result.append(site as SiteData)
	return result

func find_site_at(world_cell: Vector2i, region_cell: Vector2i) -> SiteData:
	for site: SiteData in get_sites_for_region(world_cell):
		if site.region_cell == region_cell:
			return site
	return null

func _copy_pois(source: Array) -> Array[WorldPOIData]:
	var result: Array[WorldPOIData] = []
	for item: Variant in source:
		if item is WorldPOIData:
			result.append(item as WorldPOIData)
	return result

func _terrain_for_world_cell(world_cell: Vector2i) -> String:
	var terrain_index: int = posmod(world_cell.x + world_cell.y * 3, 4)
	match terrain_index:
		0:
			return "Plains"
		1:
			return "Forest"
		2:
			return "Mountain"
		_:
			return "Water"
