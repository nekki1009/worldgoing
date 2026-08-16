extends SceneTree

const TEST_SEED: int = 123456789
const CAPTURE_DIR: String = "res://.visual_captures/site_composite_mixed"
const INVALID_CELL: Vector2i = Vector2i(-1, -1)

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
	navigation.show_region()
	await _settle(60)

	var target: Vector2i = _find_mixed_site(navigation)
	assert(target != INVALID_CELL, "No mixed terrain 3x3 footprint was found")
	var terrain_data: RegionTerrainData = navigation.travel_runtime.world_data.get_or_generate_region_terrain(
		navigation.session.selected_world_cell,
		navigation.session.world_seed
	)
	var region_map: RegionMap = navigation.get_current_map() as RegionMap
	assert(region_map != null, "Region map was not displayed")
	region_map.camera.position = Vector2(RegionMap.GRID_SIZE) * RegionMap.CELL_PIXEL_SIZE * 0.5
	region_map.camera.zoom = Vector2.ONE * 0.24
	await _settle(20)
	_capture("01_region_mixed_target")

	navigation.enter_site_at(target)
	await _settle(60)
	var site_map: SiteMap = navigation.get_current_map() as SiteMap
	assert(site_map != null and site_map.is_composite_view(), "Composite Site was not displayed")
	assert(site_map.composite_tiles.size() == 9, "Composite Site did not contain nine tiles")
	assert(site_map.composite_background_kind == "generated_mixed_v1", "Mixed Site did not use one stitched background")
	assert(site_map.composite_background_texture != null, "Mixed Site stitched background was missing")
	for tile: SiteMap in site_map.composite_tiles:
		var parent_cell: Vector2i = tile.runtime_snapshot.parent_region_cell
		assert(
			tile.runtime_snapshot.source_terrain_type == terrain_data.get_terrain(parent_cell),
			"Region terrain did not survive Region -> Site mapping at %s" % parent_cell
		)
	site_map.camera.zoom = Vector2.ONE * 3.4
	await _settle(20)
	_capture("02_site_mixed_target")
	print("SITE COMPOSITE MIXED PREVIEW: target=%s backgrounds=%s terrains=%s" % [
		target,
		_site_backgrounds(site_map),
		_site_terrains(site_map),
	])
	main.queue_free()
	await process_frame
	quit(0)

func _find_mixed_site(navigation: NavigationController) -> Vector2i:
	var terrain_data: RegionTerrainData = navigation.travel_runtime.world_data.get_or_generate_region_terrain(
		navigation.session.selected_world_cell,
		navigation.session.world_seed
	)
	for y: int in range(WorldCoordinates.REGION_GRID_SIZE):
		for x: int in range(WorldCoordinates.REGION_GRID_SIZE):
			var cell := Vector2i(x, y)
			if terrain_data.get_terrain(cell) != TerrainType.SAND or not navigation.can_enter_site_at(cell):
				continue
			var footprint: Array[SiteRuntimeSnapshot] = navigation.travel_runtime.query_site_snapshot_footprint(
				navigation.session.selected_world_cell,
				cell,
				1
			)
			if footprint.size() != 9:
				continue
			var has_plains: bool = false
			var has_sand: bool = false
			for snapshot: SiteRuntimeSnapshot in footprint:
				if snapshot.source_terrain_type == TerrainType.PLAINS:
					has_plains = true
				if snapshot.source_terrain_type == TerrainType.SAND:
					has_sand = true
			if has_plains and has_sand:
				return cell
	return INVALID_CELL

func _site_backgrounds(site_map: SiteMap) -> String:
	var result: Array[String] = []
	for tile: SiteMap in site_map.composite_tiles:
		var layout: SiteLayoutData = tile.runtime_snapshot.layout
		result.append("%s:%s" % [tile.runtime_snapshot.parent_region_cell, MapArtCatalog.site_scene_kind(layout)])
	return ",".join(result)

func _site_terrains(site_map: SiteMap) -> String:
	var result: Array[String] = []
	for tile: SiteMap in site_map.composite_tiles:
		result.append("%s:%s" % [tile.runtime_snapshot.parent_region_cell, TerrainType.to_display_name(tile.runtime_snapshot.source_terrain_type)])
	return ",".join(result)

func _settle(frame_count: int) -> void:
	for _frame: int in range(frame_count):
		await process_frame

func _capture(label: String) -> void:
	var viewport_texture: ViewportTexture = get_root().get_viewport().get_texture()
	assert(viewport_texture != null, "Viewport texture was unavailable")
	var image: Image = viewport_texture.get_image()
	assert(image != null and not image.is_empty(), "Viewport image was empty")
	var absolute_dir: String = ProjectSettings.globalize_path(CAPTURE_DIR)
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
	assert(mkdir_error == OK or mkdir_error == ERR_ALREADY_EXISTS, "Could not create preview directory")
	assert(image.save_png("%s/%s.png" % [CAPTURE_DIR, label]) == OK, "Could not save preview")
	print("SITE COMPOSITE MIXED CAPTURE: %s/%s.png" % [CAPTURE_DIR, label])
