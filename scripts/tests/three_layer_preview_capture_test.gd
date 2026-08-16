extends SceneTree

const TEST_SEED: int = 123456789
const CAPTURE_DIR: String = "res://.visual_captures/three_layer_preview"
const INVALID_CELL: Vector2i = Vector2i(-1, -1)
const SiteLayoutDataType = preload("res://scripts/data/site_layout_data.gd")

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
	# POIs are intentionally deferred to Region/Site entry; World is an
	# Overview-only layer and must not allocate or draw a POI list.
	print("THREE LAYER WORLD DISPLAY POIS: 0 (deferred)")

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
	_assert_region_contract(navigation, region_map, site_cell)
	navigation.enter_site_at(site_cell)
	await _settle(60)
	var site_map: SiteMap = navigation.get_current_map() as SiteMap
	assert(site_map != null, "Site map was not displayed")
	assert(site_map.is_composite_view(), "Region entry did not display a 3x3 Site composite")
	assert(site_map.composite_tiles.size() == 9, "Site composite did not contain nine Site tiles")
	var rendered_river_tiles: int = 0
	for river_tile: SiteMap in site_map.composite_tiles:
		if river_tile.runtime_snapshot.layout != null \
			and not river_tile.runtime_snapshot.layout.river_connection_offsets.is_empty():
			rendered_river_tiles += 1
	if rendered_river_tiles > 0:
		assert(site_map.composite_scene_river_axis >= 0, "Site composite did not resolve a shared river axis")
	assert(
		site_map.composite_background_kind == "generated_mixed_v1",
		"River Site composite did not select one native stitched background"
	)
	assert(site_map.composite_background_texture != null, "Site composite background texture was missing")
	_assert_site_contract(navigation, site_map)
	for tile: SiteMap in site_map.composite_tiles:
		assert(
			tile.composite_scene_river_axis == site_map.composite_scene_river_axis,
			"Site composite river artwork broke the shared-edge axis"
		)
	site_map.camera.zoom = Vector2.ONE * 3.4
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
	var fallback: Vector2i = INVALID_CELL
	# Prefer a river cell so the captured three-layer proof exercises the
	# Region/Site water direction contract instead of only showing plain land.
	for y: int in range(1, WorldCoordinates.REGION_GRID_SIZE - 1):
		for x: int in range(1, WorldCoordinates.REGION_GRID_SIZE - 1):
			var cell: Vector2i = Vector2i(x, y)
			var global_cell: Vector2i = WorldCoordinates.world_region_to_global_region_cell(
				navigation.session.selected_world_cell,
				cell
			)
			var info: Dictionary = navigation.travel_runtime._travel_cell_info(global_cell)
			if not bool(info.get("valid", false)):
				continue
			if bool(info.get("river", false)) \
				and not _cardinal_offsets(info.get("river_connection_offsets", [])).is_empty():
				return cell
			if fallback == INVALID_CELL and bool(info.get("road", false)):
				fallback = cell
	if fallback != INVALID_CELL:
		return fallback
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

func _assert_region_contract(
		navigation: NavigationController,
		region_map: RegionMap,
		center_region_cell: Vector2i
	) -> void:
	var center_global_cell: Vector2i = WorldCoordinates.world_region_to_global_region_cell(
		navigation.session.selected_world_cell,
		center_region_cell
	)
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			var region_cell: Vector2i = center_region_cell + Vector2i(offset_x, offset_y)
			if not WorldCoordinates.is_valid_region_cell(region_cell):
				continue
			var global_cell: Vector2i = center_global_cell + Vector2i(offset_x, offset_y)
			var info: Dictionary = navigation.travel_runtime._travel_cell_info(global_cell)
			assert(bool(info.get("valid", false)), "Region travel contract was invalid")
			var expected_river: bool = bool(info.get("river", false)) \
				and not _cardinal_offsets(info.get("river_connection_offsets", [])).is_empty()
			assert(
				region_map.travel_river_cells.has(region_cell) == expected_river,
				"Region river visual diverged from travel contract at %s" % region_cell
			)
			assert(
				_offsets_equal(
					region_map.travel_river_offsets.get(region_cell, []),
					info.get("river_connection_offsets", [])
				),
				"Region river direction diverged from travel contract at %s" % region_cell
			)
			var expected_road: bool = bool(info.get("road", false))
			assert(
				region_map.travel_road_cells.has(region_cell) == expected_road,
				"Region road visual diverged from travel contract at %s" % region_cell
			)
			assert(
				_offsets_equal(
					region_map.travel_road_offsets.get(region_cell, []),
					info.get("road_connection_offsets", [])
				),
				"Region road direction diverged from travel contract at %s" % region_cell
			)
	for crossing_variant: Variant in region_map.travel_road_crossings.keys():
		var crossing_cell: Vector2i = crossing_variant as Vector2i
		assert(
			region_map.travel_river_cells.has(crossing_cell),
			"Region road crossing has no matching river contract at %s" % crossing_cell
		)
	print("THREE LAYER CONTRACT: Region visual water/roads use the selected global cell contract")

func _assert_site_contract(
		navigation: NavigationController,
		site_map: SiteMap
	) -> void:
	for tile: SiteMap in site_map.composite_tiles:
		var snapshot: SiteRuntimeSnapshot = tile.runtime_snapshot
		assert(snapshot != null and snapshot.layout != null, "Composite tile lost its Site layout")
		var info: Dictionary = navigation.travel_runtime._travel_cell_info(
			snapshot.global_region_cell
		)
		assert(bool(info.get("valid", false)), "Site tile travel contract was invalid")
		assert(
			snapshot.layout.terrain_type == int(info.get("terrain_type", -1)),
			"Site terrain diverged from Region at %s" % snapshot.global_region_cell
		)
		var site_river_offsets: Array[Vector2i] = _cardinal_offsets(
			snapshot.layout.river_connection_offsets
		)
		var contract_river_offsets: Array[Vector2i] = _cardinal_offsets(
			info.get("river_connection_offsets", [])
		)
		assert(
			_offsets_equal(site_river_offsets, contract_river_offsets),
			"Site river direction diverged from Region at %s" % snapshot.global_region_cell
		)
		assert(
			_offsets_equal(
				snapshot.layout.road_connection_offsets,
				info.get("road_connection_offsets", [])
			),
			"Site road direction diverged from Region at %s" % snapshot.global_region_cell
		)
		var expected_water: bool = TerrainType.is_water_like(int(info.get("terrain_type", -1))) \
			or bool(info.get("river", false))
		assert(
			_layout_has_water(snapshot.layout) == expected_water,
			"Region/Site water presence diverged at %s" % snapshot.global_region_cell
		)
	print("THREE LAYER CONTRACT: Site terrain/water/road/river directions match Region")

func _layout_has_water(layout: SiteLayoutDataType) -> bool:
	for y: int in range(SiteLayoutDataType.GRID_SIZE.y):
		for x: int in range(SiteLayoutDataType.GRID_SIZE.x):
			if SiteContentTypes.is_water_surface(layout.native_surface_at(Vector2i(x, y))):
				return true
	return false

func _offsets_equal(left_value: Variant, right_value: Variant) -> bool:
	var left: Dictionary = {}
	var right: Dictionary = {}
	for offset: Vector2i in _cardinal_offsets(left_value):
		left[offset] = true
	for offset: Vector2i in _cardinal_offsets(right_value):
		right[offset] = true
	return left == right

func _cardinal_offsets(value: Variant) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not value is Array:
		return result
	for offset: Variant in value as Array:
		if offset is Vector2i:
			var direction: Vector2i = offset as Vector2i
			if absi(direction.x) + absi(direction.y) == 1 and not result.has(direction):
				result.append(direction)
	return result

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
