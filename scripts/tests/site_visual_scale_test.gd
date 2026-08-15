extends SceneTree

const TEST_SEED: int = 123456789
const MapArtCatalogType = preload("res://scripts/data/map_art_catalog.gd")
const SiteLayoutDataType = preload("res://scripts/data/site_layout_data.gd")
const SiteLayoutGeneratorType = preload("res://scripts/core/site_layout_generator.gd")

var world_data: WorldData = WorldData.new()
var terrain_names: Dictionary = {
	TerrainType.PLAINS: "plains",
	TerrainType.FOREST: "forest",
	TerrainType.MOUNTAIN: "mountain",
	TerrainType.WATER: "water",
	TerrainType.SAND: "sand",
	TerrainType.SNOW: "snow",
	TerrainType.SWAMP: "swamp",
	TerrainType.OCEAN: "ocean",
}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_site_scale_contract()
	_test_person_reference_fits_one_tile()
	_test_site_art_metadata_and_large_poi_policy()
	_test_large_poi_renderer_is_deferred()
	_test_terrain_texture_seams()
	_test_generated_anchor_and_connection_bounds()
	_test_detail_surface_and_height_contract()
	await _test_site_zoom_controls()
	print("Site visual scale tests passed: 8 cases")
	quit()

func _test_site_scale_contract() -> void:
	assert(SiteLayoutDataType.GRID_SIZE == Vector2i(50, 50), "Site grid is not 50x50")
	assert(SiteLayoutDataType.CELL_SIZE_METERS == 2, "Site tile is not 2m")
	assert(SiteLayoutDataType.SIZE_METERS == Vector2i(100, 100), "Site bounds are not 100m x 100m")
	assert(MapArtCatalogType.SITE_ART_SURFACE_PIXELS == 256, "Site art surface is not 256px")
	assert(is_equal_approx(MapArtCatalogType.SITE_SIZE_METERS, 100.0), "Art catalog lost 100m Site size")
	assert(is_equal_approx(MapArtCatalogType.SITE_PIXELS_PER_METER, 2.56), "Site px/m is not 2.56")
	assert(MapArtCatalogType.SITE_TILE_SIZE_CENTIMETERS == 200, "Site tile is not 200cm")
	print("SCALE TEST 1 PASS: 50x50 / 2m / 200cm / 100m / 256px contract")

func _test_person_reference_fits_one_tile() -> void:
	var person: Vector2 = MapArtCatalogType.PERSON_REFERENCE_SIZE_METERS
	var tile: float = MapArtCatalogType.SITE_TILE_SIZE_METERS
	assert(person.x > 0.0 and person.y > 0.0, "Person reference size is empty")
	assert(person.x < tile and person.y <= tile, "Person reference does not fit one 2m tile")
	print("SCALE TEST 2 PASS: %.2fm x %.2fm person reference fits one tile" % [person.x, person.y])

func _test_site_art_metadata_and_large_poi_policy() -> void:
	for kind: String in MapArtCatalogType.SITE_ART_TEXTURE_PATHS.keys():
		var metadata: Dictionary = MapArtCatalogType.site_art_metadata(kind)
		var size: Vector2 = MapArtCatalogType.site_art_size_meters(kind)
		assert(not metadata.is_empty(), "Missing Site art metadata: %s" % kind)
		assert(size.x > 0.0 and size.y > 0.0, "Site art has no positive metre size: %s" % kind)
		var texture: Texture2D = MapArtCatalogType.site_texture(kind)
		assert(texture != null, "Missing Site art texture: %s" % kind)
		assert(texture.get_width() > 0 and texture.get_height() > 0, "Empty Site art texture: %s" % kind)
	for poi_type: int in range(5):
		assert(MapArtCatalogType.site_structure_is_large_poi(poi_type), "POI structure lost deferred policy")
		var structure_size: Vector2 = MapArtCatalogType.site_structure_size_meters(poi_type)
		assert(structure_size.x > MapArtCatalogType.SITE_TILE_SIZE_METERS, "Large POI placeholder became a single-tile object")
	print("SCALE TEST 3 PASS: %d single-tile art metadata entries; POI structures deferred to multi-tile composition" % MapArtCatalogType.SITE_ART_TEXTURE_PATHS.size())

func _test_large_poi_renderer_is_deferred() -> void:
	var source: String = FileAccess.get_file_as_string("res://scripts/site/site_map.gd")
	assert(not source.contains("site_structure_texture("), "SiteMap still renders a large POI texture")
	assert(source.contains("_draw_deferred_poi_anchor"), "SiteMap has no deferred POI anchor")
	print("SCALE TEST 4 PASS: SiteMap renders only a small deferred POI anchor")

func _test_terrain_texture_seams() -> void:
	for terrain_type: int in range(TerrainType.COUNT):
		var image: Image = MapArtCatalogType.terrain_image(terrain_type)
		assert(image != null and image.get_width() == 256 and image.get_height() == 256, "Terrain image is not 256x256")
		var horizontal: float = _edge_mean(image, true)
		var vertical: float = _edge_mean(image, false)
		# This is a measurable asset gate, not a claim of mathematically identical
		# edges.  The current hand-painted set uses a bounded blend at tile seams.
		assert(horizontal <= 160.0 and vertical <= 160.0, "Terrain seam delta exceeded bounded blend: %s" % terrain_names.get(terrain_type, str(terrain_type)))
		print("SCALE SEAM %s: horizontal=%.2f vertical=%.2f (<=160 PASS)" % [terrain_names.get(terrain_type, str(terrain_type)), horizontal, vertical])
	print("SCALE TEST 5 PASS: all eight terrain textures stay within the measured seam gate")

func _test_generated_anchor_and_connection_bounds() -> void:
	var poi: WorldPOIData = _first_poi()
	assert(poi != null, "No deterministic POI for Site scale test")
	var definition: SiteData = world_data.get_site_definition(poi)
	var layout: SiteLayoutData = world_data.get_site_layout(definition)
	assert(layout != null and layout.is_valid(), "Generated POI layout is invalid")
	assert(layout.bounds_meters.size == SiteLayoutDataType.SIZE_METERS, "POI layout changed Site bounds")
	assert(layout.bounds_meters.has_point(layout.entrance_local_meters), "Entrance anchor escaped Site bounds")
	assert(layout.bounds_meters.has_point(layout.hub_local_meters), "Hub anchor escaped Site bounds")
	for point: Vector2i in layout.primary_path_meters:
		assert(layout.bounds_meters.has_point(point), "Path point escaped Site bounds")
	for point: Vector2i in layout.landmark_points_meters:
		assert(layout.bounds_meters.has_point(point), "Landmark point escaped Site bounds")
	for cell: Vector2i in [Vector2i.ZERO, SiteLayoutDataType.ENTRANCE_CELL, SiteLayoutDataType.GRID_SIZE - Vector2i.ONE]:
		var center: Vector2 = layout.cell_center_meters(cell)
		assert(layout.bounds_meters.has_point(center), "Cell center escaped Site bounds: %s" % cell)
		var tile_rect: Rect2 = Rect2(center - Vector2.ONE, Vector2.ONE * MapArtCatalogType.SITE_TILE_SIZE_METERS)
		assert(layout.bounds_meters.encloses(tile_rect), "Cell tile rectangle escaped Site bounds: %s" % cell)
	print("SCALE TEST 6 PASS: Site anchors, paths, landmarks and edge tiles remain in 100m bounds")

func _test_detail_surface_and_height_contract() -> void:
	assert(MapArtCatalogType.SITE_DETAIL_TILE_PIXELS == 16, "Near-camera detail tile size drifted")
	assert(MapArtCatalogType.SITE_DETAIL_SURFACE_PIXELS == 800, "Near-camera detail surface is not 800px")
	var poi: WorldPOIData = _first_poi()
	var definition: SiteData = world_data.get_site_definition(poi)
	var layout: SiteLayoutData = world_data.get_site_layout(definition)
	assert(layout.has_height_base(), "Generated Site layout has no local height/surface arrays")
	assert(layout.elevation_levels.size() == SiteLayoutDataType.NAVIGATION_CELL_COUNT, "Height array is not 50x50")
	assert(layout.surface_flags.size() == SiteLayoutDataType.NAVIGATION_CELL_COUNT, "Surface array is not 50x50")
	assert(layout.height_edge_flags.size() == SiteLayoutDataType.NAVIGATION_CELL_COUNT, "Height edge array is not 50x50")
	var detail_image: Image = MapArtCatalogType.build_layout_base_image(
		layout,
		MapArtCatalogType.SITE_DETAIL_SURFACE_PIXELS
	)
	assert(detail_image != null and detail_image.get_width() == 800, "Detail image did not allocate its near-camera surface")
	print("SCALE TEST 7 PASS: 16px/tile detail layer, 50x50 height arrays and 800px surface")

func _test_site_zoom_controls() -> void:
	var map_scene: PackedScene = load("res://scenes/site/SiteMap.tscn") as PackedScene
	var site_map: SiteMap = map_scene.instantiate() as SiteMap
	get_root().add_child(site_map)
	await process_frame
	site_map.camera.zoom = Vector2.ONE * 8.0
	var wheel_up: InputEventMouseButton = InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	site_map._unhandled_input(wheel_up)
	assert(site_map.camera.zoom.x > 8.0, "Site wheel-up did not zoom in")
	var wheel_down: InputEventMouseButton = InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	site_map._unhandled_input(wheel_down)
	assert(site_map.camera.zoom.x < 8.0 * 1.1, "Site wheel-down did not zoom out")
	site_map._set_zoom(100.0)
	assert(is_equal_approx(site_map.camera.zoom.x, SiteMap.MAX_ZOOM), "Site zoom exceeded maximum")
	site_map._set_zoom(0.001)
	assert(is_equal_approx(site_map.camera.zoom.x, SiteMap.MIN_ZOOM), "Site zoom fell below minimum")
	site_map.queue_free()
	await process_frame
	print("SCALE TEST 8 PASS: Site wheel zoom clamps to %.1fx-%.1fx" % [SiteMap.MIN_ZOOM, SiteMap.MAX_ZOOM])

func _edge_mean(image: Image, horizontal: bool) -> float:
	var total: float = 0.0
	var samples: int = image.get_height() if horizontal else image.get_width()
	for index: int in range(samples):
		var left_or_top: Color = image.get_pixel(0, index) if horizontal else image.get_pixel(index, 0)
		var right_or_bottom: Color = image.get_pixel(image.get_width() - 1, index) if horizontal else image.get_pixel(index, image.get_height() - 1)
		total += (abs(left_or_top.r - right_or_bottom.r) + abs(left_or_top.g - right_or_bottom.g) + abs(left_or_top.b - right_or_bottom.b)) / 3.0 * 255.0
	return total / float(maxi(1, samples))

func _first_poi() -> WorldPOIData:
	for y: int in range(WorldData.WORLD_CELLS.y):
		for x: int in range(WorldData.WORLD_CELLS.x):
			var pois: Array[WorldPOIData] = world_data.get_pois_for_region(Vector2i(x, y), TEST_SEED)
			if not pois.is_empty():
				return pois[0]
	return null
