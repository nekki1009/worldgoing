extends SceneTree

const TEST_SEED: int = 123456789
const CAPTURE_DIR: String = "res://.visual_captures/site_forest_composite_v1"
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

	var target: Vector2i = _find_forest_mixed_site(navigation)
	assert(target != INVALID_CELL, "No mixed Forest 3x3 footprint was found")
	var terrain_data: RegionTerrainData = navigation.travel_runtime.world_data.get_or_generate_region_terrain(
		navigation.session.selected_world_cell,
		navigation.session.world_seed
	)
	var region_map: RegionMap = navigation.get_current_map() as RegionMap
	assert(region_map != null, "Region map was not displayed")
	region_map.camera.position = Vector2(RegionMap.GRID_SIZE) * RegionMap.CELL_PIXEL_SIZE * 0.5
	region_map.camera.zoom = Vector2.ONE * 0.24
	await _settle(20)
	_capture("01_region_forest_target")

	navigation.enter_site_at(target)
	await _settle(60)
	var site_map: SiteMap = navigation.get_current_map() as SiteMap
	assert(site_map != null and site_map.is_composite_view(), "Composite Forest Site was not displayed")
	assert(site_map.composite_tiles.size() == 9, "Composite Forest Site did not contain nine tiles")
	var center_tile: SiteMap = null
	for tile: SiteMap in site_map.composite_tiles:
		if tile.runtime_snapshot != null and tile.runtime_snapshot.parent_region_cell == target:
			center_tile = tile
			break
	assert(center_tile != null, "Composite center Forest tile was missing")
	var expected_mask: int = _expected_forest_mask(target, site_map.composite_tiles)
	assert(center_tile.forest_clear_edge_mask == expected_mask, "Forest edge mask did not follow neighboring terrain")
	assert(center_tile.forest_clear_edge_mask != 15, "Mixed Forest center cleared all edges despite Forest neighbors")
	assert(terrain_data.get_terrain(target) == TerrainType.FOREST, "Target was not Forest in Region terrain")
	var selected_river_columns: Dictionary = {}
	for tile: SiteMap in site_map.composite_tiles:
		if not tile.composite_river_enabled or tile.runtime_snapshot.layout.river_connection_offsets.is_empty():
			continue
		selected_river_columns[tile.runtime_snapshot.parent_region_cell.x] = true
	if site_map.composite_scene_river_axis == 0:
		assert(selected_river_columns.size() <= 1, "Composite kept parallel vertical river columns")
	print("SITE FOREST DATA: terrain=%s source=%s placements=%d amounts=%s" % [
		TerrainType.to_display_name(center_tile.runtime_snapshot.layout.terrain_type),
		TerrainType.to_display_name(center_tile.runtime_snapshot.source_terrain_type),
		center_tile.runtime_snapshot.layout.resource_placements.size(),
		center_tile.runtime_snapshot.layout.details.get("resource_amounts", PackedInt32Array()),
	])
	var manifest: RegionGenerationManifest = navigation.travel_runtime.world_data.get_or_generate_region_manifest(
		navigation.session.selected_world_cell,
		navigation.session.world_seed
	)
	print("SITE FOREST BUDGET: forest=%d" % manifest.resource_budgets[SiteContentTypes.RESOURCE_FOREST])
	site_map.camera.zoom = Vector2.ONE * 3.4
	await _settle(20)
	_capture("02_site_forest_target")
	print("SITE FOREST COMPOSITE PREVIEW: target=%s mask=%d terrains=%s" % [
		target,
		center_tile.forest_clear_edge_mask,
		_site_terrains(site_map),
	])
	print("SITE FOREST COMPOSITE BACKGROUND: kind=%s river_axis=%d" % [
		site_map.composite_background_kind,
		site_map.composite_scene_river_axis,
	])
	for tile: SiteMap in site_map.composite_tiles:
		print("SITE FOREST RIVER TILE: cell=%s offsets=%s enabled=%s" % [
			tile.runtime_snapshot.parent_region_cell,
			tile.runtime_snapshot.layout.river_connection_offsets,
			tile.composite_river_enabled,
		])
		for facility: Dictionary in tile.runtime_snapshot.layout.facility_placements:
			if int(facility.get("type", -1)) != SiteContentTypes.Facility.BRIDGE:
				continue
			print("SITE FOREST BRIDGE TILE: cell=%s river_enabled=%s river_crossing=%s" % [
				tile.runtime_snapshot.parent_region_cell,
				tile.composite_river_enabled,
				tile.runtime_snapshot.layout.river_crossing,
			])
	main.queue_free()
	await process_frame
	quit(0)

func _find_forest_mixed_site(navigation: NavigationController) -> Vector2i:
	var terrain_data: RegionTerrainData = navigation.travel_runtime.world_data.get_or_generate_region_terrain(
		navigation.session.selected_world_cell,
		navigation.session.world_seed
	)
	for y: int in range(WorldCoordinates.REGION_GRID_SIZE):
		for x: int in range(WorldCoordinates.REGION_GRID_SIZE):
			var cell := Vector2i(x, y)
			if terrain_data.get_terrain(cell) != TerrainType.FOREST or not navigation.can_enter_site_at(cell):
				continue
			var footprint: Array[SiteRuntimeSnapshot] = navigation.travel_runtime.query_site_snapshot_footprint(
				navigation.session.selected_world_cell,
				cell,
				1
			)
			if footprint.size() != 9:
				continue
			var has_other: bool = false
			var forest_neighbors: int = 0
			for snapshot: SiteRuntimeSnapshot in footprint:
				if snapshot == null or snapshot.parent_region_cell == cell:
					continue
				if snapshot.source_terrain_type == TerrainType.FOREST:
					forest_neighbors += 1
				else:
					has_other = true
			if has_other and forest_neighbors > 0:
				return cell
	return INVALID_CELL

func _expected_forest_mask(center: Vector2i, tiles: Array[SiteMap]) -> int:
	var mask: int = 0
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for index: int in range(directions.size()):
		var neighbor_cell: Vector2i = center + directions[index]
		var found: bool = false
		for tile: SiteMap in tiles:
			if tile == null or tile.runtime_snapshot == null or tile.runtime_snapshot.parent_region_cell != neighbor_cell:
				continue
			found = true
			if tile.runtime_snapshot.source_terrain_type != TerrainType.FOREST:
				mask |= 1 << index
			break
		if not found:
			mask |= 1 << index
	return mask

func _site_terrains(site_map: SiteMap) -> String:
	var result: Array[String] = []
	for tile: SiteMap in site_map.composite_tiles:
		result.append("%s:%s" % [
			tile.runtime_snapshot.parent_region_cell,
			TerrainType.to_display_name(tile.runtime_snapshot.source_terrain_type),
		])
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
	print("SITE FOREST COMPOSITE CAPTURE: %s/%s.png" % [CAPTURE_DIR, label])
