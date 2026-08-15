extends SceneTree

const CAPTURE_DIR: String = "res://.visual_captures/battle_site_scene_a1"
const BattleSiteGeneratorType = preload("res://scripts/core/battle_site_generator.gd")
const BattleSiteSnapshotType = preload("res://scripts/runtime/battle_site_snapshot.gd")
const SiteLayoutDataType = preload("res://scripts/data/site_layout_data.gd")
const MapArtCatalogType = preload("res://scripts/data/map_art_catalog.gd")

const TEST_SEED: int = 123456789
const CENTER_CELL: Vector2i = Vector2i(500, 500)
var generator: BattleSiteGenerator

var capture_count: int = 0
var minimum_fps: float = INF

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	generator = BattleSiteGeneratorType.new()
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1440, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	OS.low_processor_usage_mode = false
	Engine.max_fps = 0
	var battle_scene: PackedScene = load("res://scenes/site/BattleSite.tscn") as PackedScene
	assert(battle_scene != null, "Battle Site scene could not be loaded")
	var map: BattleSiteMap = battle_scene.instantiate() as BattleSiteMap
	get_root().add_child(map)
	await _settle(12)
	var snapshot: BattleSiteSnapshot = _build_snapshot()
	assert(snapshot.has_preview(), "3x3 Battle Site fixture did not produce a preview")
	assert(snapshot.site_layouts.size() == 9, "Battle fixture must contain nine Site layouts")
	assert(int(snapshot.attacker_deployment.get("initial_deployed_personnel", 0)) > 0,
		"Attacker deployment was incorrectly removed from the preview")
	assert(int(snapshot.defender_deployment.get("initial_deployed_personnel", 0)) > 0,
		"Defender deployment was incorrectly removed from the preview")
	_assert_deployment_positions_are_passable(snapshot.attacker_deployment, snapshot.footprint_cells)
	_assert_deployment_positions_are_passable(snapshot.defender_deployment, snapshot.footprint_cells)
	_assert_rejected_deployment_is_reserved(snapshot.attacker_deployment)
	_assert_rejected_deployment_is_reserved(snapshot.defender_deployment)
	for layout: SiteLayoutDataType in snapshot.site_layouts:
		assert(MapArtCatalogType.site_scene_texture(layout) != null,
			"Battle fixture Site has no authored scene texture: %s" % layout.site_id)
	for kind: String in [
		"site_cliff_horizontal", "site_cliff_vertical",
		"site_path_horizontal", "site_path_vertical",
		"site_river_horizontal", "site_river_vertical"
	]:
		assert(MapArtCatalogType.site_texture(kind) != null,
			"Battle connection variant is missing: %s" % kind)
	map.setup(snapshot)
	var debug_panel: CanvasLayer = map.get_node("BattleDebugPanel") as CanvasLayer
	if debug_panel != null:
		debug_panel.visible = false
	map.camera.position = BattleSiteMap.meters_to_pixels(snapshot.size_meters * 0.5)
	map.camera.zoom = Vector2.ONE * 0.62
	await _settle(30)
	await _capture("01_battle_3x3_site_full")
	map.camera.zoom = Vector2.ONE * 0.92
	await _settle(30)
	await _capture("02_battle_3x3_site_close")
	# A focused crop makes the shared-edge proof inspectable: the horizontal
	# cliff/stair, road join, and vertical river bridge are all in one frame.
	map.soldier_instances.visible = false
	map.camera.position = Vector2(600.0, 400.0)
	map.camera.zoom = Vector2.ONE * 1.50
	await _settle(30)
	await _capture("03_boundary_connections_detail")
	var success: bool = capture_count == 3 and minimum_fps >= 30.0
	print("BATTLE SCENE PREVIEW SUMMARY: captures=%d/3 minimum_fps=%.2f sites=%d" % [
		capture_count,
		minimum_fps,
		snapshot.site_layouts.size(),
	])
	map.queue_free()
	await process_frame
	MapArtCatalogType.clear_site_scene_texture_cache()
	quit(0 if success else 2)

func _build_snapshot() -> BattleSiteSnapshot:
	var attacker: BattleParticipantData = BattleParticipantData.new("preview_attacker", "Attacker", 800)
	var defender: BattleParticipantData = BattleParticipantData.new("preview_defender", "Defender", 800)
	var context: BattleSiteContext = BattleSiteContext.create(
		TEST_SEED,
		CENTER_CELL,
		attacker,
		defender,
		BattleSiteContext.EntryDirection.SOUTH,
		BattleSiteContext.EntryDirection.NORTH,
		0,
		GameSession.INITIAL_WORLD_TIME_SECONDS
	)
	assert(context != null, "Battle Site preview context could not be created")
	var resolved_cells: Array[Dictionary] = []
	for global_cell: Vector2i in BattleSiteGeneratorType.footprint_global_cells(CENTER_CELL):
		var offset: Vector2i = global_cell - CENTER_CELL
		var terrain_type: int = _terrain_for_offset(offset)
		var road_offsets: Array[Vector2i] = _road_offsets_for_offset(offset)
		var river_offsets: Array[Vector2i] = _river_offsets_for_offset(offset)
		var river: bool = not river_offsets.is_empty()
		resolved_cells.append({
			"global_region_cell": global_cell,
			"world_cell": Vector2i.ZERO,
			"region_cell": global_cell,
			"terrain_type": terrain_type,
			"elevation": 0.35 + float(offset.y + 1) * 0.12,
			"moisture": 0.45 + float(posmod(offset.x + offset.y + 3, 3)) * 0.12,
			"river_strength": 0.95 if river else 0.0,
			"river": river,
			"road": not road_offsets.is_empty(),
			"river_crossing": terrain_type == TerrainType.WATER,
			"passable": true,
			"road_connection_offsets": road_offsets,
			"river_connection_offsets": river_offsets,
		})
	var generated: Dictionary = generator.generate(context, resolved_cells)
	assert(not generated.is_empty(), "Battle Site 3x3 fixture generation failed")
	var snapshot: BattleSiteSnapshot = BattleSiteSnapshotType.new()
	snapshot.success = true
	snapshot.context = generated["context"] as BattleSiteContext
	for value: Variant in generated["site_layouts"] as Array:
		snapshot.site_layouts.append((value as SiteLayoutDataType).copy())
	snapshot.footprint_cells = (generated["footprint_cells"] as Array[Dictionary]).duplicate(true)
	for footprint_index: int in range(snapshot.footprint_cells.size()):
		var cell: Dictionary = snapshot.footprint_cells[footprint_index]
		var offset: Vector2i = (cell["global_region_cell"] as Vector2i) - CENTER_CELL
		var layout: SiteLayoutDataType = cell["site_layout"] as SiteLayoutDataType
		if layout != null:
			# Keep the nine authored terrain scenes visible while deliberately
			# forcing reciprocal road/river edges for the connection preview.
			var scene_kind: String = _scene_kind_for_offset(offset)
			layout.details["scene_art"] = scene_kind
			# `snapshot.site_layouts` contains independent copies of the
			# generated layouts.  Set the same presentation hint on that copy;
			# otherwise the visual gate checks a blank CELL_BASE archetype and
			# incorrectly reports that authored scene art is missing.
			if footprint_index < snapshot.site_layouts.size():
				snapshot.site_layouts[footprint_index].details["scene_art"] = scene_kind
	snapshot.size_meters = generated["size_meters"] as Vector2
	snapshot.bounds_meters = generated["bounds_meters"] as Rect2
	snapshot.center_cell = (generated["center_cell"] as Dictionary).duplicate(true)
	snapshot.center_terrain = int(generated["center_terrain"])
	snapshot.attacker_deployment = (generated["attacker_deployment"] as Dictionary).duplicate(true)
	snapshot.defender_deployment = (generated["defender_deployment"] as Dictionary).duplicate(true)
	snapshot.terrain_debug_representation = str(generated["terrain_debug_representation"])
	snapshot.terrain_hash = str(generated["terrain_hash"])
	snapshot.preview_hash = str(generated["preview_hash"])
	return snapshot

func _assert_deployment_positions_are_passable(
		deployment: Dictionary,
		cells: Array[Dictionary]
	) -> void:
	var deployed: int = int(deployment.get("initial_deployed_personnel", 0))
	var facing: Vector2 = deployment.get("facing", Vector2.DOWN) as Vector2
	for index: int in range((deployment.get("marker_positions_meters", []) as Array).size()):
		var value: Variant = (deployment.get("marker_positions_meters", []) as Array)[index]
		assert(value is Vector2, "Deployment marker is not a meter position")
		var personnel: int = mini(
			BattleFormationData.DEFAULT_PERSONNEL,
			maxi(deployed - index * BattleFormationData.DEFAULT_PERSONNEL, 0)
		)
		assert(BattleSiteGeneratorType._deployment_formation_is_passable(
				value as Vector2, personnel, facing, cells),
			"Deployment formation overlaps a blocked Site cell: %s" % str(value))

func _assert_rejected_deployment_is_reserved(deployment: Dictionary) -> void:
	var total: int = int(deployment.get("total_personnel", 0))
	var initial: int = int(deployment.get("initial_deployed_personnel", 0))
	var reserve: int = int(deployment.get("reserve_personnel", 0))
	assert(initial + reserve == total,
		"Rejected formations must remain in reserve instead of being relocated")

func _terrain_for_offset(offset: Vector2i) -> int:
	match offset:
		Vector2i(-1, -1):
			return TerrainType.SNOW
		Vector2i(0, -1):
			return TerrainType.MOUNTAIN
		Vector2i(1, -1):
			return TerrainType.FOREST
		Vector2i(-1, 0):
			return TerrainType.SAND
		Vector2i(0, 0):
			return TerrainType.PLAINS
		Vector2i(1, 0):
			return TerrainType.WATER
		Vector2i(-1, 1):
			return TerrainType.SWAMP
		Vector2i(0, 1):
			return TerrainType.OCEAN
		_:
			return TerrainType.FOREST

func _road_offsets_for_offset(offset: Vector2i) -> Array[Vector2i]:
	match offset:
		Vector2i(-1, 0):
			return [Vector2i.RIGHT]
		Vector2i(0, -1):
			return [Vector2i.DOWN]
		Vector2i(0, 0):
			return [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]
		Vector2i(0, 1):
			return [Vector2i.UP]
		_:
			return []

func _river_offsets_for_offset(offset: Vector2i) -> Array[Vector2i]:
	match offset:
		Vector2i(1, -1):
			return [Vector2i.DOWN]
		Vector2i(1, 0):
			return [Vector2i.UP]
		Vector2i(1, 1):
			return []
		_:
			return []

func _scene_kind_for_offset(offset: Vector2i) -> String:
	match offset:
		Vector2i(-1, -1):
			return "snow_ore_shelf"
		Vector2i(0, -1):
			return "mountain_mine"
		Vector2i(1, -1):
			return "river_bridge_vertical"
		Vector2i(-1, 0):
			return "sand_dryland"
		Vector2i(0, 0):
			return "grassland_village"
		Vector2i(1, 0):
			return "river_bridge_vertical"
		Vector2i(-1, 1):
			return "swamp_wetland"
		Vector2i(0, 1):
			return "ocean_coast"
		_:
			return "forest_orchard"

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
	assert(image != null and not image.is_empty(), "Battle preview capture is empty")
	var absolute_dir: String = ProjectSettings.globalize_path(CAPTURE_DIR)
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
	assert(mkdir_error == OK or mkdir_error == ERR_ALREADY_EXISTS, "Could not create battle preview directory")
	var path: String = "%s/%s.png" % [CAPTURE_DIR, label]
	assert(image.save_png(path) == OK, "Could not save Battle preview %s" % label)
	capture_count += 1
	var started_usec: int = Time.get_ticks_usec()
	await _settle(60)
	var elapsed_usec: int = maxi(1, Time.get_ticks_usec() - started_usec)
	minimum_fps = minf(minimum_fps, 60.0 * 1_000_000.0 / float(elapsed_usec))
	print("BATTLE SCENE PREVIEW: %s" % ProjectSettings.globalize_path(path))
