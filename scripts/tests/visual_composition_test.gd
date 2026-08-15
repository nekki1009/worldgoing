extends SceneTree

const TEST_SEED: int = 123456789
const MapArtCatalogType = preload("res://scripts/data/map_art_catalog.gd")
const SiteLayoutDataType = preload("res://scripts/data/site_layout_data.gd")
const SiteLayoutGeneratorType = preload("res://scripts/core/site_layout_generator.gd")

var world_data: WorldData = WorldData.new()

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_site_visual_base()
	_test_cell_visual_composition()
	_test_eight_terrain_visual_codes()
	_test_world_thumbnail_uses_site_visual_rules()
	_test_world_bounds_are_lazy()
	_test_map_art_assets()
	_test_site_art_assets_and_generated_layout()
	await _test_map_textures()
	print("Visual composition tests passed: 8 cases")
	quit()

func _test_site_visual_base() -> void:
	var poi: WorldPOIData = _first_poi()
	assert(poi != null, "No deterministic POI was available for Site visual test")
	var layout: SiteLayoutData = world_data.get_site_layout(world_data.get_site_definition(poi))
	assert(layout != null and layout.has_visual_base(), "Site did not generate a complete 50x50 visual base")
	assert(layout.visual_cells.size() == SiteLayoutDataType.NAVIGATION_CELL_COUNT, "Site visual cell count is wrong")
	var first_hash: int = _hash_bytes(layout.visual_cells)
	var regenerated: SiteLayoutData = world_data.get_site_layout(world_data.get_site_definition(poi))
	assert(first_hash == _hash_bytes(regenerated.visual_cells), "Site visual base is not deterministic")
	var has_path: bool = false
	var has_landmark: bool = false
	var has_hub: bool = false
	for code: int in layout.visual_cells:
		has_path = has_path or (code & SiteLayoutDataType.VISUAL_PATH) != 0
		has_landmark = has_landmark or (code & SiteLayoutDataType.VISUAL_LANDMARK) != 0
		has_hub = has_hub or (code & SiteLayoutDataType.VISUAL_HUB) != 0
	assert(has_path and has_landmark and has_hub, "Site visual base lost path, landmark, or hub markers")
	print("VISUAL TEST 1 PASS: Site owns deterministic 50x50 visual base")

func _test_cell_visual_composition() -> void:
	var global_cell: Vector2i = Vector2i(301, -27)
	var resolved_cell: Dictionary = {
		"global_region_cell": global_cell,
		"terrain_type": TerrainType.FOREST,
		"elevation": 0.55,
		"moisture": 0.72,
		"river_strength": 0.8,
		"river": true,
		"road": true,
		"river_crossing": true,
	}
	var layout: SiteLayoutData = SiteLayoutGeneratorType.generate_cell_base(TEST_SEED, resolved_cell)
	assert(layout != null and layout.has_navigation_base(), "Region Strategic Cell did not produce Site cell base")
	assert(layout.has_visual_base(), "Region Strategic Cell did not produce Site visual base")
	var has_road: bool = false
	var has_river: bool = false
	var has_crossing: bool = false
	for code: int in layout.visual_cells:
		has_road = has_road or (code & SiteLayoutDataType.VISUAL_ROAD) != 0
		has_river = has_river or (code & SiteLayoutDataType.VISUAL_RIVER) != 0
		has_crossing = has_crossing or SiteLayoutDataType.visual_has_crossing(code)
	assert(has_road and has_river and has_crossing, "Site cell visual base lost road, river, or crossing")
	var thumbnail: PackedByteArray = SiteLayoutGeneratorType.generate_cell_base_thumbnail(TEST_SEED, resolved_cell)
	assert(thumbnail.size() == SiteLayoutGeneratorType.THUMBNAIL_GRID_SIZE * SiteLayoutGeneratorType.THUMBNAIL_GRID_SIZE, "Site cell thumbnail size is wrong")
	print("VISUAL TEST 2 PASS: Region is composed from Site cell visual rules")

func _test_eight_terrain_visual_codes() -> void:
	for terrain_type: int in range(TerrainType.COUNT):
		var visual_code: int = SiteLayoutGeneratorType.generate_cell_base_visual_code(
			TEST_SEED,
			{
				"global_region_cell": Vector2i(100 + terrain_type, 200),
				"terrain_type": terrain_type,
				"river": false,
				"road": false,
			}
		)
		assert(
			(visual_code & SiteLayoutDataType.VISUAL_TERRAIN_MASK) == terrain_type,
			"Terrain visual code was truncated"
		)
		assert(TerrainType.to_color(terrain_type) != Color.TRANSPARENT, "Terrain color is missing")
	print("VISUAL TEST 3 PASS: all eight main terrain codes survive byte packing")

func _test_world_thumbnail_uses_site_visual_rules() -> void:
	var generator: RegionTerrainGenerator = RegionTerrainGenerator.new()
	var world_thumbnail: PackedByteArray = generator.generate_thumbnail(TEST_SEED, Vector2i(3, 4))
	assert(world_thumbnail.size() == RegionTerrainGenerator.THUMBNAIL_CELL_COUNT, "World thumbnail size is wrong")
	var visual_code: int = SiteLayoutGeneratorType.generate_cell_base_visual_code(
		TEST_SEED,
		{
			"global_region_cell": WorldCoordinates.world_region_to_global_region_cell(Vector2i(3, 4), Vector2i.ZERO),
			"terrain_type": RegionTerrainGenerator.new().classify_sample(generator.macro_sampler.sample(TEST_SEED, WorldCoordinates.world_region_to_global_region_cell(Vector2i(3, 4), Vector2i.ZERO))),
			"river": false,
			"road": false,
		}
	)
	assert(
		RegionTerrainGenerator.thumbnail_terrain(world_thumbnail[0]) == (visual_code & RegionTerrainGenerator.THUMBNAIL_TERRAIN_MASK),
		"World thumbnail did not use the shared Site visual terrain code"
	)
	print("VISUAL TEST 4 PASS: World thumbnail is derived through shared Site visual rules")

func _test_world_bounds_are_lazy() -> void:
	assert(WorldData.WORLD_CELLS == Vector2i(256, 256), "V3 World bounds are not 256x256")
	var bounded_data: WorldData = WorldData.new()
	assert(bounded_data.regions.is_empty(), "WorldData eagerly allocated the full World bounds")
	assert(bounded_data.get_region(Vector2i(255, 255)) != null, "Last V3 World Cell is not queryable")
	assert(bounded_data.regions.size() == 1, "WorldData allocated more than the queried Region")
	assert(bounded_data.get_region(Vector2i(256, 0)) == null, "World bounds accepted an out-of-range cell")
	print("VISUAL TEST 5 PASS: 256x256 World bounds are centralized and lazy")

func _test_map_art_assets() -> void:
	for terrain_type: int in range(TerrainType.COUNT):
		var texture: Texture2D = MapArtCatalogType.terrain_texture(terrain_type)
		assert(texture != null, "Missing map art texture for terrain %d" % terrain_type)
		assert(texture.get_width() == 256 and texture.get_height() == 256, "Map art texture size is not 256x256")
	for poi_type: int in range(5):
		var poi_texture: Texture2D = MapArtCatalogType.poi_texture(poi_type)
		assert(poi_texture != null, "Missing POI art texture for type %d" % poi_type)
		assert(poi_texture.get_width() == 128 and poi_texture.get_height() == 128, "POI art texture size is not 128x128")
	var outpost_texture: Texture2D = MapArtCatalogType.outpost_texture()
	assert(outpost_texture != null, "Missing outpost art texture")
	assert(outpost_texture.get_width() == 128 and outpost_texture.get_height() == 128, "Outpost art texture size is not 128x128")
	print("VISUAL TEST 6 PASS: terrain and POI map art load through the shared catalog")

func _test_site_art_assets_and_generated_layout() -> void:
	var expected_keys: Array[String] = [
		"path_straight", "road_bend", "road_t_junction", "road_crossing",
		"river_straight", "river_bend", "river_source", "river_mouth",
		"bridge", "mountain_pass_cliff", "entrance_gate", "stone_marker",
		"tree_cluster", "rock_cluster", "swamp_reeds", "snow_dune",
		"sand_dune", "dry_bush", "snowdrift", "deadwood",
	]
	for key: String in expected_keys:
		var texture: Texture2D = MapArtCatalogType.site_texture(key)
		assert(texture != null, "Missing Site art texture: %s" % key)
		assert(texture.get_width() > 0 and texture.get_height() > 0, "Empty Site art texture: %s" % key)
		var image: Image = texture.get_image()
		assert(image != null and not image.is_empty(), "Site art texture has no image: %s" % key)
		assert(image.get_pixel(0, 0).a < 0.1, "Site art texture is not transparent at border: %s" % key)
	var poi: WorldPOIData = _first_poi()
	var definition: SiteData = world_data.get_site_definition(poi)
	var layout: SiteLayoutData = world_data.get_site_layout(definition)
	assert(layout != null and layout.is_valid(), "Generated Site layout is invalid for art coverage")
	assert(layout.primary_path_meters.size() >= 3, "Generated Site path is incomplete for art coverage")
	assert(layout.landmark_points_meters.size() >= 4, "Generated Site landmarks are incomplete for art coverage")
	assert(layout.has_visual_base(), "Generated Site visual base missing for art coverage")
	assert(SiteLayoutDataType.visual_has_crossing(SiteLayoutDataType.VISUAL_ROAD | SiteLayoutDataType.VISUAL_RIVER), "Visual crossing contract was lost")
	print("VISUAL TEST 8 PASS: Site traffic, landmark, transport, cliff and terrain-detail art load and cover a generated layout")

func _test_map_textures() -> void:
	var poi: WorldPOIData = _first_poi()
	var main_scene: PackedScene = load("res://scenes/Main.tscn") as PackedScene
	var main: Node2D = main_scene.instantiate() as Node2D
	get_root().add_child(main)
	await process_frame
	var navigation: NavigationController = main.get_node("NavigationController") as NavigationController
	navigation.session.world_seed = TEST_SEED
	navigation.session.party.initialized = true
	navigation.session.party.set_global_region_cell(poi.global_region_cell)
	navigation.enter_region(poi.world_cell)
	await process_frame
	var region_map: RegionMap = navigation.get_current_map() as RegionMap
	assert(region_map != null and region_map.static_visual != null, "RegionMap was not created")
	assert(region_map.static_visual.terrain_texture != null, "RegionMap did not bake a composed texture")
	assert(region_map.static_visual.terrain_texture.get_width() == 800, "Region texture does not preserve 100x100 strategic cells")
	navigation.enter_site_at(poi.region_cell)
	await process_frame
	var site_map: SiteMap = navigation.get_current_map() as SiteMap
	assert(site_map != null and site_map.site_texture != null, "SiteMap did not create a visual texture")
	assert(
		site_map.site_texture.get_width() == MapArtCatalogType.SITE_DETAIL_SURFACE_PIXELS,
		"Site texture did not use the near-camera detail surface"
	)
	main.queue_free()
	await process_frame
	print("VISUAL TEST 7 PASS: World -> Region -> Site presentation textures are present")

func _first_poi() -> WorldPOIData:
	for y: int in range(WorldData.WORLD_CELLS.y):
		for x: int in range(WorldData.WORLD_CELLS.x):
			var pois: Array[WorldPOIData] = world_data.get_pois_for_region(Vector2i(x, y), TEST_SEED)
			if not pois.is_empty():
				return pois[0]
	return null

func _hash_bytes(values: PackedByteArray) -> int:
	var result: int = 17
	for value: int in values:
		result = posmod(result * 31 + value, 2_147_483_647)
	return result
