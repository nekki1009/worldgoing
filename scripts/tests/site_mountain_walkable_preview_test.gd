extends SceneTree

const TEST_SEED: int = 123456789
const CAPTURE_DIR: String = "res://.visual_captures/site_mountain_walkable_v1"
const SiteLayoutGeneratorType = preload("res://scripts/core/site_layout_generator.gd")

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
	var debug_ui: CanvasLayer = main.get_node_or_null("DebugUI") as CanvasLayer
	if debug_ui != null:
		for child: Node in debug_ui.get_children():
			if child is Control:
				(child as Control).visible = false

	var layout: SiteLayoutData = SiteLayoutGeneratorType.generate_cell_base(TEST_SEED, {
		"global_region_cell": Vector2i(515, 515),
		"terrain_type": TerrainType.MOUNTAIN,
		"site_landform": SiteLayoutData.Landform.NONE,
		"travel_exit_mask": SiteLayoutData.EXIT_ALL,
		"elevation": 0.68,
		"moisture": 0.32,
		"native_surface_hint": SiteContentTypes.NativeSurface.ROCK,
		"rock_ratio": 0.82,
		"resource_amounts": PackedInt32Array([0, 0, 0, 28, 10, 3, 1]),
	})
	assert(layout != null and layout.is_valid(), "Mountain walkable fixture is invalid")
	# A generated stair is valid only when it bridges two adjacent, different
	# elevation levels.  This catches the old regression where a flat-cell stair
	# flag survived even though no visible highland existed at that coordinate.
	assert(layout.transitions.size() == 2, "Mountain plateau must expose exactly two boundary stairs")
	var stair_surface_cells: int = 0
	for y: int in range(SiteLayoutData.GRID_SIZE.y):
		for x: int in range(SiteLayoutData.GRID_SIZE.x):
			if (layout.surface_flags_at(Vector2i(x, y)) & SiteLayoutData.SURFACE_STAIR) != 0:
				stair_surface_cells += 1
	for transition: SiteTransitionData in layout.transitions:
		assert(transition != null, "Mountain transition entry is null")
		assert(transition.kind == SiteTransitionData.Kind.STAIR, "Mountain plateau transition is not a stair")
		assert(transition.height_delta() > 0, "Mountain stair connects equal-height cells")
		var delta: Vector2i = transition.to_cell - transition.from_cell
		assert(absi(delta.x) + absi(delta.y) == 1, "Mountain stair endpoints are not adjacent")
		assert((layout.surface_flags_at(transition.from_cell) & SiteLayoutData.SURFACE_STAIR) != 0,
			"Mountain stair origin is missing stair surface")
		assert((layout.surface_flags_at(transition.to_cell) & SiteLayoutData.SURFACE_STAIR) != 0,
			"Mountain stair target is missing stair surface")
	assert(stair_surface_cells >= layout.transitions.size() * 2,
		"Mountain plateau stair flags are not attached to both endpoints")
	var plateau_cells: Array = layout.details.get("mountain_plateau_cells", []) as Array
	assert(plateau_cells.size() > 0, "Mountain plateau has no raised cells")

	var blocked_cells: int = 0
	var walkable_cells: int = 0
	var traversable_edges: int = 0
	for y: int in range(SiteLayoutData.GRID_SIZE.y):
		for x: int in range(SiteLayoutData.GRID_SIZE.x):
			var cell := Vector2i(x, y)
			if (layout.navigation_flags_at(cell) & SiteLayoutData.NAV_BLOCKED) != 0:
				blocked_cells += 1
			else:
				walkable_cells += 1
			for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				if layout.can_traverse(cell, cell + direction):
					traversable_edges += 1
	assert(walkable_cells > 0, "Mountain Site has no walkable cells")
	assert(traversable_edges > 0, "Mountain Site has no traversable edges")
	print("MOUNTAIN WALKABILITY: blocked=%d walkable=%d traversable_edges=%d transitions=%d" % [
		blocked_cells,
		walkable_cells,
		traversable_edges,
		layout.transitions.size(),
	])

	var snapshot: SiteRuntimeSnapshot = SiteRuntimeSnapshot.new()
	snapshot.site_id = "mountain_walkable_preview"
	snapshot.source_poi_id = ""
	snapshot.site_name = "Walkable Mountain Ground"
	snapshot.site_type = WorldPOIType.VILLAGE
	snapshot.global_region_cell = layout.global_region_cell
	snapshot.site_seed = layout.site_seed
	snapshot.source_terrain_type = TerrainType.MOUNTAIN
	snapshot.site_landform = layout.site_landform
	snapshot.travel_exit_mask = layout.travel_exit_mask
	snapshot.source_elevation = layout.elevation
	snapshot.source_moisture = layout.moisture
	snapshot.entrance_local_meters = layout.entrance_local_meters
	snapshot.entrance_global_meters = layout.global_region_cell * 100
	snapshot.layout = layout
	snapshot.world_seed = TEST_SEED
	snapshot.party_id = "preview_party"
	snapshot.party_global_region_cell = layout.global_region_cell
	snapshot.party_site_local_cell = SiteLayoutData.INVALID_CELL
	var map_scene: PackedScene = load("res://scenes/site/SiteMap.tscn") as PackedScene
	var map: SiteMap = navigation._replace_map(map_scene) as SiteMap
	navigation.current_layer = NavigationController.MapLayer.SITE
	map.setup(snapshot)
	await _settle(30)
	map.camera.position = Vector2(layout.bounds_meters.get_center())
	map.camera.zoom = Vector2.ONE * 5.0
	await _settle(30)
	_capture("01_mountain_walkable_full")
	map.camera.position = Vector2(0.0, 0.0)
	map.camera.zoom = Vector2.ONE * 10.0
	await _settle(30)
	_capture("02_mountain_walkable_close")

	main.queue_free()
	await process_frame
	quit(0)

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
	var path: String = "%s/%s.png" % [CAPTURE_DIR, label]
	assert(image.save_png(path) == OK, "Could not save %s" % path)
	print("MOUNTAIN WALKABILITY CAPTURE: %s" % ProjectSettings.globalize_path(path))
