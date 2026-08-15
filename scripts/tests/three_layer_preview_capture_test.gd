extends SceneTree

const TEST_SEED: int = 123456789
const CAPTURE_DIR: String = "res://.visual_captures/three_layer_preview"
const INVALID_CELL: Vector2i = Vector2i(-1, -1)

var capture_count: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1440, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	OS.low_processor_usage_mode = false
	Engine.max_fps = 0

	var main_scene: PackedScene = load("res://scenes/Main.tscn") as PackedScene
	assert(main_scene != null, "Main scene could not be loaded")
	var main: Node2D = main_scene.instantiate() as Node2D
	get_root().add_child(main)
	await _settle(45)

	var navigation: NavigationController = main.get_node("NavigationController") as NavigationController
	assert(navigation != null, "NavigationController could not be loaded")
	navigation.session.world_seed = TEST_SEED
	navigation.session.selected_world_cell = Vector2i.ZERO
	navigation.session.selected_region_cell = Vector2i(50, 50)
	navigation.session.party.set_global_region_cell(
		WorldCoordinates.world_region_to_global_region_cell(
			Vector2i.ZERO,
			Vector2i(50, 50)
		)
	)
	navigation.session.party.initialized = true
	navigation.show_world()
	await _settle(45)
	var world_map: WorldMap = navigation.get_current_map() as WorldMap
	assert(world_map != null, "World map was not displayed")
	world_map.camera.zoom = Vector2.ONE * 1.35
	await _settle(20)
	_capture("01_world_map")
	var displayed_world_pois: int = 0
	for cached: Variant in world_map.world_poi_cache.values():
		if cached is Array:
			displayed_world_pois += world_map._world_poi_display_list(cached as Array).size()
	assert(displayed_world_pois <= 80,
		"World overview POI display is too dense: %d" % displayed_world_pois)
	print("THREE LAYER WORLD DISPLAY POIS: %d" % displayed_world_pois)

	navigation.enter_region(Vector2i.ZERO)
	await _settle(60)
	var region_map: RegionMap = navigation.get_current_map() as RegionMap
	assert(region_map != null, "Region map was not displayed")
	region_map.camera.position = Vector2(RegionMap.GRID_SIZE) * RegionMap.CELL_PIXEL_SIZE * 0.5
	region_map.camera.zoom = Vector2.ONE * 0.24
	var terrain_counts: Dictionary = {}
	var min_elevation: float = 1.0
	var max_elevation: float = 0.0
	var min_moisture: float = 1.0
	var max_moisture: float = 0.0
	if region_map.terrain_data != null:
		for y: int in range(WorldCoordinates.REGION_GRID_SIZE):
			for x: int in range(WorldCoordinates.REGION_GRID_SIZE):
				var cell: Vector2i = Vector2i(x, y)
				var terrain_type: int = region_map.terrain_data.get_terrain(cell)
				terrain_counts[terrain_type] = int(terrain_counts.get(terrain_type, 0)) + 1
				min_elevation = minf(min_elevation, region_map.terrain_data.get_elevation(cell))
				max_elevation = maxf(max_elevation, region_map.terrain_data.get_elevation(cell))
				min_moisture = minf(min_moisture, region_map.terrain_data.get_moisture(cell))
				max_moisture = maxf(max_moisture, region_map.terrain_data.get_moisture(cell))
	print("THREE LAYER REGION TERRAIN COUNTS: %s ELEVATION=%.3f..%.3f MOISTURE=%.3f..%.3f" % [terrain_counts, min_elevation, max_elevation, min_moisture, max_moisture])
	assert(terrain_counts.size() >= 4,
		"Region terrain palette is too uniform: %s" % terrain_counts)
	var rendered_road_routes: int = 0
	for route_id: String in region_map.road_overlay.routes_by_id.keys():
		var route: WorldRoadRoute = region_map.road_overlay.get_route(route_id)
		if route != null and route.path.size() > 1:
			route.path_length_cells()
			rendered_road_routes += 1
	print("THREE LAYER REGION ORTHOGONAL ROUTES: %d" % rendered_road_routes)
	await _settle(20)
	_capture("02_region_map")

	var site_cell: Vector2i = _find_enterable_site(navigation)
	assert(site_cell != INVALID_CELL, "No enterable Site tile was found in the Region")
	navigation.enter_site_at(site_cell)
	await _settle(60)
	var site_map: SiteMap = navigation.get_current_map() as SiteMap
	assert(site_map != null, "Site map was not displayed")
	site_map.camera.zoom = Vector2.ONE * 12.0
	await _settle(20)
	_capture("03_site_map")

	print("THREE LAYER PREVIEW SUMMARY: captures=%d/3 site_cell=%s" % [
		capture_count,
		site_cell,
	])
	main.queue_free()
	await process_frame
	quit(0 if capture_count == 3 else 2)

func _find_enterable_site(navigation: NavigationController) -> Vector2i:
	var center: int = floori(float(WorldCoordinates.REGION_GRID_SIZE) * 0.5)
	for radius: int in range(0, center + 1):
		var candidates: Array[Vector2i] = [
			Vector2i(center + radius, center),
			Vector2i(center - radius, center),
			Vector2i(center, center + radius),
			Vector2i(center, center - radius),
		]
		for cell: Vector2i in candidates:
			if navigation.can_enter_site_at(cell):
				return cell
	return INVALID_CELL

func _settle(frame_count: int) -> void:
	for _frame: int in range(frame_count):
		await process_frame

func _capture(label: String) -> void:
	var viewport_texture: ViewportTexture = get_root().get_viewport().get_texture()
	assert(viewport_texture != null, "Viewport texture was unavailable for %s" % label)
	var image: Image = viewport_texture.get_image()
	assert(image != null and not image.is_empty(), "Viewport image was empty for %s" % label)
	var absolute_dir: String = ProjectSettings.globalize_path(CAPTURE_DIR)
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
	assert(mkdir_error == OK or mkdir_error == ERR_ALREADY_EXISTS,
		"Could not create three-layer preview directory")
	var path: String = "%s/%s.png" % [CAPTURE_DIR, label]
	assert(image.save_png(path) == OK, "Could not save three-layer preview %s" % label)
	capture_count += 1
	print("THREE LAYER CAPTURE: %s" % ProjectSettings.globalize_path(path))
