extends SceneTree

const TEST_SEED: int = 123456789
const CAPTURE_DIR: String = "res://.visual_captures/site_composite_rules"
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

	# The deterministic fixture used by the previous visual baseline is a
	# known no-river meadow cell. Prefer it so the preview test does not spend
	# two minutes regenerating every possible 3x3 footprint before drawing.
	var target: Vector2i = Vector2i(75, 1)
	if not navigation.can_enter_site_at(target):
		target = _find_no_river_meadow_site(navigation)
	assert(target != INVALID_CELL, "No no-river meadow 3x3 footprint was found")
	navigation.enter_site_at(target)
	await _settle(60)
	var site_map: SiteMap = navigation.get_current_map() as SiteMap
	assert(site_map != null and site_map.is_composite_view(), "Composite Site was not displayed")
	assert(site_map.composite_tiles.size() == 9, "Composite Site did not contain nine tiles")
	assert(
		site_map.composite_background_kind == "generated_mixed_v1",
		"No-river meadow did not use the native stitched background"
	)
	assert(site_map.composite_background_texture != null, "Native stitched background was missing")
	for tile: SiteMap in site_map.composite_tiles:
		assert(
			MapArtCatalog.site_scene_kind(tile.runtime_snapshot.layout).is_empty(),
			"Generated Region cell still selected a baked scene painting"
		)
	site_map.camera.zoom = Vector2.ONE * 3.4
	await _settle(20)
	_capture("01_no_river_meadow_3x3")
	print("SITE COMPOSITE RULES PREVIEW: target=%s background=%s" % [
		target,
		site_map.composite_background_kind,
	])
	main.queue_free()
	await process_frame
	quit(0)

func _find_no_river_meadow_site(navigation: NavigationController) -> Vector2i:
	for y: int in range(WorldCoordinates.REGION_GRID_SIZE):
		for x: int in range(WorldCoordinates.REGION_GRID_SIZE):
			var cell := Vector2i(x, y)
			if not navigation.can_enter_site_at(cell):
				continue
			var footprint: Array[SiteRuntimeSnapshot] = navigation.travel_runtime.query_site_snapshot_footprint(
				navigation.session.selected_world_cell,
				cell,
				1
			)
			if footprint.size() != 9:
				continue
			var has_river: bool = false
			for snapshot: SiteRuntimeSnapshot in footprint:
				if snapshot == null or snapshot.layout == null:
					continue
				if snapshot.layout.river_strength > 0.0 \
					or not snapshot.layout.river_connection_offsets.is_empty():
					has_river = true
			if not has_river:
				return cell
	return INVALID_CELL

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
	print("SITE COMPOSITE RULES CAPTURE: %s/%s.png" % [CAPTURE_DIR, label])
