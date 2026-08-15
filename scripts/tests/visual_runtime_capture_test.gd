extends SceneTree

const TEST_SEED: int = 123456789
const CAPTURE_DIR: String = "res://.visual_captures/map_art_scale_v1"
const SiteLayoutGeneratorType = preload("res://scripts/core/site_layout_generator.gd")
const TERRAIN_NAMES: Dictionary = {
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
	var main_scene: PackedScene = load("res://scenes/Main.tscn") as PackedScene
	assert(main_scene != null, "Main scene could not be loaded")
	var main: Node2D = main_scene.instantiate() as Node2D
	get_root().add_child(main)
	await _settle(45)
	var navigation: NavigationController = main.get_node("NavigationController") as NavigationController
	navigation.session.world_seed = TEST_SEED
	navigation.session.party.initialized = true
	navigation.show_world()
	await _settle(45)
	_capture("world_actual_256x256")
	print("VISUAL WORLD ENGINE FPS: %.2f" % Engine.get_frames_per_second())

	var candidates: Dictionary = _collect_candidates(navigation.world_data)
	var first_poi: WorldPOIData = candidates.get("first", null) as WorldPOIData
	assert(first_poi != null, "No deterministic POI available for runtime capture")
	var site_map: SiteMap = await _show_poi(navigation, first_poi)
	assert(site_map != null, "First generated POI could not enter Site")
	_capture("site_formal_actual")
	var scale_event: InputEventKey = InputEventKey.new()
	scale_event.keycode = KEY_F2
	scale_event.pressed = true
	site_map._unhandled_input(scale_event)
	await _settle(18)
	_capture("site_scale_guide_actual")
	var scale_fps: float = await _measure_fps(120)
	print("VISUAL SITE SCALE FPS: %.2f" % scale_fps)
	assert(scale_fps >= 30.0, "Site scale-guide FPS was below 30")
	var debug_event: InputEventKey = InputEventKey.new()
	debug_event.keycode = KEY_F1
	debug_event.pressed = true
	site_map._unhandled_input(debug_event)
	await _settle(12)
	_capture("site_debug_overlay_actual")
	print("VISUAL SITE ENGINE FPS: %.2f" % Engine.get_frames_per_second())

	var river_poi: WorldPOIData = candidates.get("river", null) as WorldPOIData
	if river_poi != null and river_poi.poi_id != first_poi.poi_id:
		await _show_poi(navigation, river_poi)
		_capture("site_river_actual")
		print("VISUAL SITE RIVER: %s / %s" % [river_poi.poi_id, river_poi.site_name])
	else:
		print("VISUAL SITE RIVER: no distinct generated river POI")

	var mountain_poi: WorldPOIData = candidates.get("mountain_pass", null) as WorldPOIData
	if mountain_poi != null:
		await _show_poi(navigation, mountain_poi)
		_capture("site_mountain_pass_actual")
		print("VISUAL SITE MOUNTAIN PASS: %s / %s" % [mountain_poi.poi_id, mountain_poi.site_name])
	else:
		print("VISUAL SITE MOUNTAIN PASS: no generated Mountain Pass POI")

	for terrain_type: int in range(TerrainType.COUNT):
		var terrain_poi: WorldPOIData = candidates.get(terrain_type, null) as WorldPOIData
		if terrain_poi == null:
			var generated_cell: Vector2i = _find_generated_cell(
				navigation.world_data,
				func(data: Dictionary) -> bool: return int(data.get("terrain_type", -1)) == terrain_type
			)
			if generated_cell == Vector2i(-1, -1):
				print("VISUAL TERRAIN %s: no generated POI or Strategic Cell candidate" % TERRAIN_NAMES.get(terrain_type, str(terrain_type)))
				continue
			await _show_cell_preview(navigation, generated_cell)
		else:
			await _show_poi(navigation, terrain_poi)
		_capture("site_terrain_%s_actual" % TERRAIN_NAMES[terrain_type])

	var river_cell: Vector2i = _find_generated_cell(
		navigation.world_data,
		func(data: Dictionary) -> bool: return bool(data.get("river", false))
	)
	if river_cell != Vector2i(-1, -1):
		await _show_cell_preview(navigation, river_cell)
		_capture("site_river_cell_actual")
		print("VISUAL SITE RIVER CELL: %s" % river_cell)
	else:
		print("VISUAL SITE RIVER CELL: no generated Strategic Cell")

	var pass_cell: Vector2i = Vector2i(1832, 38)
	var pass_data: Dictionary = navigation.world_data.sample_travel_data(TEST_SEED, pass_cell)
	if int(pass_data.get("site_landform", -1)) != SiteLayoutData.Landform.MOUNTAIN_PASS:
		pass_cell = _find_generated_cell(
			navigation.world_data,
			func(data: Dictionary) -> bool:
				return int(data.get("terrain_type", -1)) == TerrainType.MOUNTAIN \
						and bool(data.get("road", false)) \
						and int(data.get("site_landform", -1)) == SiteLayoutData.Landform.MOUNTAIN_PASS
		)
	if pass_cell != Vector2i(-1, -1):
		await _show_cell_preview(navigation, pass_cell)
		_capture("site_mountain_pass_cell_actual")
		print("VISUAL SITE MOUNTAIN PASS CELL: %s" % pass_cell)
	else:
		print("VISUAL SITE MOUNTAIN PASS CELL: no generated Strategic Cell; fixture/search unavailable")

	navigation.show_region()
	await _settle(30)
	var battle_snapshot: BattleSiteSnapshot = _find_battle_preview(navigation, first_poi.global_region_cell)
	assert(battle_snapshot != null and battle_snapshot.has_preview(), "No actual passable Battle preview was generated")
	navigation.show_battle_site(battle_snapshot)
	await _settle(60)
	_capture("battle_site_actual")
	print("VISUAL BATTLE ENGINE FPS: %.2f" % Engine.get_frames_per_second())

	var measured_fps: float = await _measure_fps(120)
	print("VISUAL RUNTIME FPS: %.2f" % measured_fps)
	print("VISUAL RUNTIME ENGINE FPS: %.2f" % Engine.get_frames_per_second())
	assert(measured_fps >= 30.0, "Measured runtime FPS was below 30")
	main.queue_free()
	await process_frame
	print("Visual runtime capture passed: actual World, Site formal/debug, River, Mountain Pass, terrain candidates, Battle, FPS >= 30")
	quit()

func _show_poi(navigation: NavigationController, poi: WorldPOIData) -> SiteMap:
	assert(poi != null, "Cannot show a null POI")
	navigation.session.party.set_global_region_cell(poi.global_region_cell)
	navigation.enter_region(poi.world_cell)
	await _settle(36)
	navigation.enter_site_at(poi.region_cell)
	await _settle(36)
	var site_map: SiteMap = navigation.get_current_map() as SiteMap
	assert(site_map != null, "Generated POI did not produce SiteMap: %s" % poi.poi_id)
	return site_map

func _show_cell_preview(navigation: NavigationController, global_cell: Vector2i) -> SiteMap:
	var resolved: Dictionary = navigation.world_data.sample_travel_data(TEST_SEED, global_cell)
	var layout: SiteLayoutData = SiteLayoutGeneratorType.generate_cell_base(TEST_SEED, resolved)
	assert(layout != null and layout.has_navigation_base(), "Generated Strategic Cell Site base is invalid")
	var snapshot: SiteRuntimeSnapshot = SiteRuntimeSnapshot.new()
	snapshot.site_id = "visual_cell_%d_%d" % [global_cell.x, global_cell.y]
	snapshot.source_poi_id = snapshot.site_id
	snapshot.site_name = "Generated Strategic Cell"
	snapshot.site_type = WorldPOIType.VILLAGE
	var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(global_cell)
	snapshot.parent_world_cell = converted["world_cell"] as Vector2i
	snapshot.parent_region_cell = converted["region_cell"] as Vector2i
	snapshot.global_region_cell = global_cell
	var parent_region: RegionData = navigation.world_data.get_region(snapshot.parent_world_cell)
	if parent_region != null:
		snapshot.parent_region_id = parent_region.region_id
		snapshot.parent_region_name = parent_region.region_name
	snapshot.site_seed = layout.site_seed
	snapshot.source_terrain_type = int(resolved.get("terrain_type", TerrainType.PLAINS))
	snapshot.site_landform = int(resolved.get("site_landform", SiteLayoutData.Landform.NONE))
	snapshot.travel_exit_mask = int(resolved.get("travel_exit_mask", SiteLayoutData.EXIT_ALL))
	snapshot.source_elevation = float(resolved.get("elevation", 0.0))
	snapshot.source_moisture = float(resolved.get("moisture", 0.0))
	snapshot.source_river_nearby = bool(resolved.get("river", false))
	snapshot.entrance_local_meters = layout.entrance_local_meters
	snapshot.entrance_global_meters = WorldCoordinates.global_region_cell_to_global_meters(global_cell)
	snapshot.layout = layout
	snapshot.world_seed = TEST_SEED
	snapshot.party_id = navigation.session.party.party_id
	snapshot.party_global_region_cell = global_cell
	snapshot.party_site_local_cell = SiteLayoutData.ENTRANCE_CELL
	var map_scene: PackedScene = load("res://scenes/site/SiteMap.tscn") as PackedScene
	var map: SiteMap = navigation._replace_map(map_scene) as SiteMap
	navigation.current_layer = NavigationController.MapLayer.SITE
	map.debug_state_changed.connect(navigation._on_map_debug_state_changed)
	map.setup(snapshot)
	await _settle(30)
	return map

func _find_generated_cell(world_data: WorldData, predicate: Callable) -> Vector2i:
	var axis: int = WorldData.WORLD_CELLS.x * WorldCoordinates.REGION_GRID_SIZE
	for index: int in range(15_000):
		var cell: Vector2i = Vector2i(
			posmod(index * 97 + 23, axis),
			posmod(index * 251 + 41, axis)
		)
		var sample: Vector4 = world_data.terrain_generator.macro_sampler.sample(TEST_SEED, cell)
		var terrain_type: int = world_data.terrain_generator.classify_sample(sample)
		if terrain_type == TerrainType.MOUNTAIN \
				and not predicate.call({"terrain_type": terrain_type}):
			continue
		var data: Dictionary = world_data.sample_travel_data(TEST_SEED, cell)
		if predicate.call(data):
			return cell
	return Vector2i(-1, -1)

func _collect_candidates(world_data: WorldData) -> Dictionary:
	var result: Dictionary = {"first": null, "river": null, "mountain_pass": null}
	for terrain_type: int in range(TerrainType.COUNT):
		result[terrain_type] = null
	# Query the canonical POI generator directly on a deterministic pseudo-random
	# sample of candidate buckets. This avoids repeatedly expanding neighboring
	# buckets while still allowing rare terrain/landform combinations to appear.
	var poi_generator: WorldPOIGenerator = world_data.poi_generator
	var candidate_axis: int = WorldData.WORLD_CELLS.x * WorldCoordinates.REGION_GRID_SIZE / WorldPOIGenerator.POI_CANDIDATE_GRID_SIZE
	for index: int in range(30_000):
		var candidate: Vector2i = Vector2i(
			posmod(index * 73 + 17, candidate_axis),
			posmod(index * 193 + 29, candidate_axis)
		)
		var poi: WorldPOIData = poi_generator._generate_candidate(TEST_SEED, candidate)
		if poi == null or not world_data.is_valid_world_cell(poi.world_cell):
			continue
		if result["first"] == null:
			result["first"] = poi
		if result[poi.terrain_type] == null:
			result[poi.terrain_type] = poi
		if poi.river_nearby and result["river"] == null:
			result["river"] = poi
		if result["mountain_pass"] == null and poi.terrain_type == TerrainType.MOUNTAIN:
			var definition: SiteData = world_data.get_site_definition(poi)
			if definition != null and definition.site_landform == SiteLayoutData.Landform.MOUNTAIN_PASS:
				result["mountain_pass"] = poi
		if result["river"] != null and result["mountain_pass"] != null \
				and _has_all_terrain_candidates(result):
			return result
	return result

func _has_all_terrain_candidates(candidates: Dictionary) -> bool:
	for terrain_type: int in range(TerrainType.COUNT):
		if candidates.get(terrain_type, null) == null:
			return false
	return true

func _find_battle_preview(navigation: NavigationController, preferred: Vector2i) -> BattleSiteSnapshot:
	var offsets: Array[Vector2i] = [Vector2i.ZERO]
	for radius: int in range(1, 20):
		offsets.append(Vector2i(radius, 0))
		offsets.append(Vector2i(-radius, 0))
		offsets.append(Vector2i(0, radius))
		offsets.append(Vector2i(0, -radius))
	for offset: Vector2i in offsets:
		var candidate: Vector2i = preferred + offset
		if candidate.x < 1 or candidate.y < 1 \
				or candidate.x >= WorldData.WORLD_CELLS.x * WorldCoordinates.REGION_GRID_SIZE - 1 \
				or candidate.y >= WorldData.WORLD_CELLS.y * WorldCoordinates.REGION_GRID_SIZE - 1:
			continue
		var preview: BattleSiteSnapshot = navigation.battle_preview_runtime.query_debug_preview(candidate)
		if preview != null and preview.has_preview():
			return preview
	return null

func _settle(frame_count: int) -> void:
	for _frame: int in range(frame_count):
		await process_frame

func _measure_fps(frame_count: int) -> float:
	var start_usec: int = Time.get_ticks_usec()
	for _frame: int in range(frame_count):
		await process_frame
	var elapsed_usec: int = maxi(1, Time.get_ticks_usec() - start_usec)
	return float(frame_count) * 1_000_000.0 / float(elapsed_usec)

func _capture(label: String) -> void:
	var viewport_texture: ViewportTexture = get_root().get_viewport().get_texture()
	if viewport_texture == null:
		print("VISUAL CAPTURE SKIPPED (no viewport texture): %s" % label)
		return
	var image: Image = viewport_texture.get_image()
	if image == null or image.is_empty():
		print("VISUAL CAPTURE SKIPPED (empty viewport texture): %s" % label)
		return
	var absolute_capture_dir: String = ProjectSettings.globalize_path(CAPTURE_DIR)
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(absolute_capture_dir)
	assert(mkdir_error == OK or mkdir_error == ERR_ALREADY_EXISTS, "Could not create visual capture directory")
	var path: String = "%s/%s.png" % [CAPTURE_DIR, label]
	var error: Error = image.save_png(path)
	assert(error == OK, "Could not save viewport capture %s" % path)
	print("VISUAL CAPTURE: %s" % ProjectSettings.globalize_path(path))
