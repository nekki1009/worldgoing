extends SceneTree

const CAPTURE_DIR: String = "res://.visual_captures/site_scene_composed_a28"
const SiteLayoutGeneratorType = preload("res://scripts/core/site_layout_generator.gd")
const SiteLayoutDataType = preload("res://scripts/data/site_layout_data.gd")
const MapArtCatalogType = preload("res://scripts/data/map_art_catalog.gd")

var capture_count: int = 0
var minimum_fps: float = INF

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	OS.low_processor_usage_mode = false
	Engine.max_fps = 0
	var main_scene: PackedScene = load("res://scenes/Main.tscn") as PackedScene
	assert(main_scene != null, "Main scene could not be loaded")
	var main: Node2D = main_scene.instantiate() as Node2D
	get_root().add_child(main)
	await _settle(30)
	var debug_ui: CanvasLayer = main.get_node_or_null("DebugUI") as CanvasLayer
	if debug_ui != null:
		for child: Node in debug_ui.get_children():
			if child is Control:
				(child as Control).visible = false
	var navigation: NavigationController = main.get_node("NavigationController") as NavigationController
	assert(navigation != null, "NavigationController could not be loaded")

	var grassland: SiteLayoutDataType = SiteLayoutGeneratorType.generate(_fixture(
		"p6_grassland_village",
		WorldPOIType.VILLAGE,
		TerrainType.PLAINS,
		PackedInt32Array([300, 0, 0, 0, 0, 0, 0])
	))
	await _capture_scene(
		navigation,
		grassland,
		"01_grassland_village",
		_building_focus(grassland)
	)

	var forest: SiteLayoutDataType = SiteLayoutGeneratorType.generate(_fixture(
		"p6_forest_orchard",
		WorldPOIType.VILLAGE,
		TerrainType.FOREST,
		PackedInt32Array([36, 10, 48, 0, 0, 0, 0]),
		SiteLayoutDataType.Landform.NONE,
		SiteLayoutDataType.EXIT_ALL,
		SiteLayoutDataType.LayoutKind.CELL_BASE
	))
	await _capture_scene(
		navigation,
		forest,
		"02_forest_fruit_trees",
		_resource_focus(forest, SiteContentTypes.RESOURCE_FRUIT_TREE)
	)

	var mine: SiteLayoutDataType = SiteLayoutGeneratorType.generate(_fixture(
		"p6_mining_area",
		WorldPOIType.CAVE,
		TerrainType.MOUNTAIN,
		PackedInt32Array([0, 0, 0, 48, 28, 12, 6]),
		SiteLayoutDataType.Landform.NONE,
		SiteLayoutDataType.EXIT_ALL,
		SiteLayoutDataType.LayoutKind.CELL_BASE
	))
	await _capture_scene(
		navigation,
		mine,
		"03_mining_area",
		_resource_focus(mine, SiteContentTypes.RESOURCE_GOLD_ORE)
	)

	var mountain_pass: SiteLayoutDataType = SiteLayoutGeneratorType.generate(_fixture(
		"p6_double_cliff_pass",
		WorldPOIType.VILLAGE,
		TerrainType.MOUNTAIN,
		PackedInt32Array([0, 0, 0, 16, 3, 0, 0]),
		SiteLayoutDataType.Landform.MOUNTAIN_PASS,
		SiteLayoutDataType.EXIT_EAST | SiteLayoutDataType.EXIT_WEST
	))
	_assert_scene_kind(mountain_pass, "mountain_pass")
	await _capture_scene(
		navigation,
		mountain_pass,
		"04_double_cliff_mountain_pass",
		_transition_focus(mountain_pass)
	)

	var river_definition: SiteData = _fixture(
		"p6_river_bridge_stair",
		WorldPOIType.VILLAGE,
		TerrainType.PLAINS,
		PackedInt32Array([24, 2, 8, 0, 0, 0, 0]),
		SiteLayoutDataType.Landform.NONE,
		SiteLayoutDataType.EXIT_ALL,
		SiteLayoutDataType.LayoutKind.CELL_BASE
	)
	river_definition.source_road = true
	river_definition.source_river_nearby = true
	river_definition.source_river_crossing = true
	river_definition.source_road_connection_offsets = [Vector2i.LEFT, Vector2i.RIGHT]
	var river: SiteLayoutDataType = SiteLayoutGeneratorType.generate(river_definition)
	_assert_scene_kind(river, "river_bridge")
	await _capture_scene(
		navigation,
		river,
		"05_river_bridge_height_stair",
		_facility_focus(river, SiteContentTypes.Facility.BRIDGE)
	)

	var sand: SiteLayoutDataType = SiteLayoutGeneratorType.generate(_fixture(
		"a5_sand_dryland",
		WorldPOIType.VILLAGE,
		TerrainType.SAND,
		PackedInt32Array([24, 0, 0, 0, 0, 0, 0]),
		SiteLayoutDataType.Landform.NONE,
		SiteLayoutDataType.EXIT_ALL,
		SiteLayoutDataType.LayoutKind.CELL_BASE
	))
	_assert_scene_kind(sand, "sand_dryland")
	await _capture_scene(
		navigation,
		sand,
		"06_sand_dryland",
		_resource_focus(sand, SiteContentTypes.RESOURCE_GRASS)
	)

	var snow: SiteLayoutDataType = SiteLayoutGeneratorType.generate(_fixture(
		"a5_snow_ore_shelf",
		WorldPOIType.CAVE,
		TerrainType.SNOW,
		PackedInt32Array([0, 0, 0, 20, 8, 2, 0]),
		SiteLayoutDataType.Landform.NONE,
		SiteLayoutDataType.EXIT_ALL,
		SiteLayoutDataType.LayoutKind.CELL_BASE
	))
	_assert_scene_kind(snow, "snow_ore_shelf")
	await _capture_scene(
		navigation,
		snow,
		"07_snow_ore_shelf",
		_resource_focus(snow, SiteContentTypes.RESOURCE_STONE_ORE)
	)

	var swamp: SiteLayoutDataType = SiteLayoutGeneratorType.generate(_fixture(
		"a5_swamp_wetland",
		WorldPOIType.VILLAGE,
		TerrainType.SWAMP,
		PackedInt32Array([30, 5, 24, 0, 0, 0, 0]),
		SiteLayoutDataType.Landform.NONE,
		SiteLayoutDataType.EXIT_ALL,
		SiteLayoutDataType.LayoutKind.CELL_BASE
	))
	_assert_scene_kind(swamp, "swamp_wetland")
	await _capture_scene(
		navigation,
		swamp,
		"08_swamp_wetland",
		_resource_focus(swamp, SiteContentTypes.RESOURCE_FOREST)
	)

	var ocean: SiteLayoutDataType = SiteLayoutGeneratorType.generate(_fixture(
		"a5_ocean_coast",
		WorldPOIType.VILLAGE,
		TerrainType.OCEAN,
		PackedInt32Array([0, 0, 0, 0, 0, 0, 0]),
		SiteLayoutDataType.Landform.NONE,
		SiteLayoutDataType.EXIT_ALL,
		SiteLayoutDataType.LayoutKind.CELL_BASE
	))
	_assert_scene_kind(ocean, "ocean_coast")
	await _capture_scene(
		navigation,
		ocean,
		"09_ocean_coast",
		Vector2(ocean.bounds_meters.get_center())
	)

	var orchard: SiteLayoutDataType = SiteLayoutGeneratorType.generate(_fixture(
		"a5_plains_orchard",
		WorldPOIType.VILLAGE,
		TerrainType.PLAINS,
		PackedInt32Array([0, 12, 0, 0, 0, 0, 0]),
		SiteLayoutDataType.Landform.NONE,
		SiteLayoutDataType.EXIT_ALL,
		SiteLayoutDataType.LayoutKind.CELL_BASE
	))
	await _capture_scene(
		navigation,
		orchard,
		"10_plains_orchard",
		_resource_focus(orchard, SiteContentTypes.RESOURCE_FRUIT_TREE)
	)

	var forest_cluster: SiteLayoutDataType = SiteLayoutGeneratorType.generate(_fixture(
		"a5_forest_cluster",
		WorldPOIType.VILLAGE,
		TerrainType.FOREST,
		PackedInt32Array([0, 0, 40, 0, 0, 0, 0]),
		SiteLayoutDataType.Landform.NONE,
		SiteLayoutDataType.EXIT_ALL,
		SiteLayoutDataType.LayoutKind.CELL_BASE
	))
	await _capture_scene(
		navigation,
		forest_cluster,
		"11_forest_cluster",
		_resource_focus(forest_cluster, SiteContentTypes.RESOURCE_FOREST)
	)

	var success: bool = capture_count == 22 and minimum_fps >= 30.0
	print("A5 PREVIEW SUMMARY: captures=%d/22 minimum_fps=%.2f" % [capture_count, minimum_fps])
	main.queue_free()
	await process_frame
	quit(0 if success else 2)

func _capture_scene(
		navigation: NavigationController,
		layout: SiteLayoutDataType,
		label: String,
		focus: Vector2
	) -> void:
	var map: SiteMap = await _show_layout(navigation, layout, label)
	if map.camera != null:
		map.camera.position = Vector2(layout.bounds_meters.get_center())
		map.camera.zoom = Vector2.ONE * 10.0
	await _settle(30)
	_capture("%s_full" % label)
	if map.camera != null:
		map.camera.position = focus
		map.camera.zoom = Vector2.ONE * 16.0
	await _settle(30)
	_capture("%s_close" % label)
	var started_usec: int = Time.get_ticks_usec()
	await _settle(120)
	var elapsed_usec: int = maxi(1, Time.get_ticks_usec() - started_usec)
	var fps: float = 120.0 * 1_000_000.0 / float(elapsed_usec)
	minimum_fps = minf(minimum_fps, fps)
	print("A5 PREVIEW FPS (%s): %.2f" % [label, fps])

func _show_layout(
		navigation: NavigationController,
		layout: SiteLayoutDataType,
		label: String
	) -> SiteMap:
	assert(layout != null and layout.is_valid(), "%s layout is invalid" % label)
	var snapshot: SiteRuntimeSnapshot = SiteRuntimeSnapshot.new()
	snapshot.site_id = layout.site_id
	snapshot.source_poi_id = layout.site_id if layout.layout_kind == SiteLayoutDataType.LayoutKind.POI else ""
	snapshot.site_name = label
	snapshot.site_type = layout.site_type
	snapshot.global_region_cell = layout.global_region_cell
	snapshot.site_seed = layout.site_seed
	snapshot.source_terrain_type = layout.terrain_type
	snapshot.site_landform = layout.site_landform
	snapshot.travel_exit_mask = layout.travel_exit_mask
	snapshot.source_elevation = layout.elevation
	snapshot.source_moisture = layout.moisture
	snapshot.source_river_nearby = layout.river_strength > 0.0
	snapshot.entrance_local_meters = layout.entrance_local_meters
	snapshot.entrance_global_meters = layout.global_region_cell * 100
	snapshot.layout = layout
	snapshot.world_seed = 123456789
	snapshot.party_id = "preview_party"
	snapshot.party_global_region_cell = layout.global_region_cell
	snapshot.party_site_local_cell = SiteLayoutDataType.INVALID_CELL
	var map_scene: PackedScene = load("res://scenes/site/SiteMap.tscn") as PackedScene
	var map: SiteMap = navigation._replace_map(map_scene) as SiteMap
	navigation.current_layer = NavigationController.MapLayer.SITE
	map.setup(snapshot)
	await _settle(30)
	return map

func _fixture(
		site_id: String,
		site_type: int,
		terrain_type: int,
		resource_amounts: PackedInt32Array,
		landform: int = SiteLayoutDataType.Landform.NONE,
		exit_mask: int = SiteLayoutDataType.EXIT_ALL,
		layout_kind: int = SiteLayoutDataType.LayoutKind.POI
	) -> SiteData:
	var definition: SiteData = SiteData.new(
		site_id,
		site_id,
		site_type,
		Vector2i(2, 2),
		Vector2i(25, 25),
		Vector2i(125, 125)
	)
	definition.layout_kind = layout_kind
	definition.site_seed = abs(hash(site_id)) + 1
	definition.entrance_local_meters = Vector2i.ZERO
	definition.source_terrain_type = terrain_type
	definition.site_landform = landform
	definition.travel_exit_mask = exit_mask
	definition.source_elevation = 1.0
	definition.source_moisture = 0.65
	definition.native_surface_hint = SiteContentTypes.NativeSurface.ROCK \
		if terrain_type == TerrainType.MOUNTAIN else SiteContentTypes.NativeSurface.DIRT
	definition.rock_ratio = 0.84 if terrain_type == TerrainType.MOUNTAIN else 0.0
	definition.resource_amounts = resource_amounts.duplicate()
	definition.source_road_connection_offsets = [Vector2i.LEFT, Vector2i.RIGHT]
	return definition

func _resource_focus(layout: SiteLayoutDataType, resource_type: int) -> Vector2:
	for placement: Dictionary in layout.resource_placements:
		if int(placement.get("type", -1)) != resource_type:
			continue
		var origin: Variant = placement.get("origin", SiteLayoutDataType.ENTRANCE_CELL)
		if origin is Vector2i:
			return layout.cell_center_meters(origin as Vector2i)
	return Vector2(layout.bounds_meters.get_center())

func _assert_scene_kind(layout: SiteLayoutDataType, expected: String) -> void:
	var actual: String = MapArtCatalogType.site_scene_kind(layout)
	assert(actual == expected, "%s scene mapping expected %s, got %s" % [layout.site_id, expected, actual])
	assert(MapArtCatalogType.site_scene_texture(layout) != null, "%s scene texture missing for %s" % [layout.site_id, expected])

func _facility_focus(layout: SiteLayoutDataType, facility_type: int) -> Vector2:
	for placement: Dictionary in layout.facility_placements:
		if int(placement.get("type", -1)) != facility_type:
			continue
		var origin: Variant = placement.get("origin", SiteLayoutDataType.ENTRANCE_CELL)
		var size: Variant = placement.get("size", Vector2i.ONE)
		if origin is Vector2i and size is Vector2i:
			return Vector2(layout.bounds_meters.position) \
				+ (Vector2(origin as Vector2i) + Vector2(size as Vector2i) * 0.5) \
				* float(SiteLayoutDataType.CELL_SIZE_METERS)
	return Vector2(layout.bounds_meters.get_center())

func _building_focus(layout: SiteLayoutDataType) -> Vector2:
	return _facility_focus(layout, SiteContentTypes.Facility.BUILDING)

func _transition_focus(layout: SiteLayoutDataType) -> Vector2:
	for transition: SiteTransitionData in layout.transitions:
		if transition != null and transition.kind == SiteTransitionData.Kind.STAIR:
			return (layout.cell_center_meters(transition.from_cell) + layout.cell_center_meters(transition.to_cell)) * 0.5
	return Vector2(layout.bounds_meters.get_center())

func _settle(frame_count: int) -> void:
	for _frame: int in range(frame_count):
		await process_frame

func _capture(label: String) -> void:
	if OS.has_feature("headless") or DisplayServer.get_name() == "headless":
		return
	var viewport_texture: ViewportTexture = get_root().get_viewport().get_texture()
	if viewport_texture == null:
		return
	var image: Image = viewport_texture.get_image()
	if image == null or image.is_empty():
		return
	var absolute_dir: String = ProjectSettings.globalize_path(CAPTURE_DIR)
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
	assert(mkdir_error == OK or mkdir_error == ERR_ALREADY_EXISTS, "Could not create preview directory")
	var path: String = "%s/%s.png" % [CAPTURE_DIR, label]
	assert(image.save_png(path) == OK, "Could not save %s" % path)
	capture_count += 1
	print("A5 PREVIEW: %s" % ProjectSettings.globalize_path(path))
