extends SceneTree

const CAPTURE_DIR: String = "res://.visual_captures/site_tile_join_review"
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
	var battle_scene: PackedScene = load("res://scenes/site/BattleSite.tscn") as PackedScene
	assert(battle_scene != null, "Battle Site scene could not be loaded")
	var map: BattleSiteMap = battle_scene.instantiate() as BattleSiteMap
	get_root().add_child(map)
	await _settle(12)
	var attacker: BattleParticipantData = BattleParticipantData.new("join_attacker", "Join Attacker", 1)
	var defender: BattleParticipantData = BattleParticipantData.new("join_defender", "Join Defender", 1)
	map.context = BattleSiteContext.create(
		123456789,
		Vector2i(500, 500),
		attacker,
		defender,
		BattleSiteContext.EntryDirection.SOUTH,
		BattleSiteContext.EntryDirection.NORTH,
		0,
		GameSession.INITIAL_WORLD_TIME_SECONDS
	)
	assert(map.context != null, "Site join visual context could not be created")
	var cells: Array[Dictionary] = []
	for y: int in range(3):
		for x: int in range(3):
			cells.append(_cell(x, y))
	map.generated = {
		"footprint_cells": cells,
		"size_meters": Vector2(300.0, 300.0),
		"bounds_meters": Rect2(Vector2.ZERO, Vector2(300.0, 300.0)),
		"center_cell": cells[4],
		"attacker_deployment": _empty_deployment(Vector2(300.0, 300.0)),
		"defender_deployment": _empty_deployment(Vector2(300.0, 300.0)),
		"terrain_hash": "site_tile_join",
		"preview_hash": "site_tile_join",
	}
	map.active_formations.clear()
	map.active_dispatches.clear()
	map.active_orders.clear()
	map.soldier_instances.visible = false
	var debug_panel: CanvasLayer = map.get_node("BattleDebugPanel") as CanvasLayer
	if debug_panel != null:
		debug_panel.visible = false
	map.camera.position = BattleSiteMap.meters_to_pixels(Vector2(150.0, 150.0))
	map.camera.zoom = Vector2.ONE * 0.80
	map.queue_redraw()
	await _settle(30)
	_capture("01_site_tiles_full")
	map.camera.position = Vector2(600.0, 400.0)
	map.camera.zoom = Vector2.ONE * 1.65
	await _settle(30)
	_capture("02_site_tiles_shared_edges")
	assert(capture_count == 2, "Site tile join visual captures incomplete")
	print("SITE TILE JOIN VISUAL PASS: captures=%d/2" % capture_count)
	map.queue_free()
	await process_frame
	quit(0)

func _cell(x: int, y: int) -> Dictionary:
	var layout: SiteLayoutDataType = SiteLayoutDataType.new()
	layout.site_id = "join_%d_%d" % [x, y]
	layout.site_seed = 1000 + x + y * 3
	layout.terrain_type = _terrain_for_cell(x, y)
	layout.bounds_meters = Rect2i(Vector2i.ZERO, SiteLayoutDataType.SIZE_METERS)
	layout.details["scene_art"] = _scene_for_cell(x, y)
	var road_offsets: Array[Vector2i] = []
	var river_offsets: Array[Vector2i] = []
	if y == 1:
		road_offsets.append(Vector2i.LEFT)
		road_offsets.append(Vector2i.RIGHT)
	if x == 1:
		road_offsets.append(Vector2i.UP)
		road_offsets.append(Vector2i.DOWN)
	if x == 2:
		if y > 0:
			river_offsets.append(Vector2i.UP)
		if y < 2:
			river_offsets.append(Vector2i.DOWN)
	layout.road_connection_offsets = road_offsets
	layout.river_connection_offsets = river_offsets
	layout.river_strength = 1.0 if not river_offsets.is_empty() else 0.0
	var global_cell: Vector2i = Vector2i(499 + x, 499 + y)
	return {
		"global_region_cell": global_cell,
		"local_origin_meters": Vector2(float(x * 100), float(y * 100)),
		"terrain_type": layout.terrain_type,
		"elevation": 1.0 if y == 0 and x == 1 else 0.25,
		"site_layout": layout,
		"details": {},
		"road": not road_offsets.is_empty(),
		"river": not river_offsets.is_empty(),
		"river_crossing": false,
		"road_connection_offsets": road_offsets,
		"river_connection_offsets": river_offsets,
	}

func _terrain_for_cell(x: int, y: int) -> int:
	match Vector2i(x, y):
		Vector2i(0, 0): return TerrainType.SNOW
		Vector2i(1, 0): return TerrainType.MOUNTAIN
		Vector2i(2, 0): return TerrainType.FOREST
		Vector2i(0, 1): return TerrainType.SAND
		Vector2i(1, 1): return TerrainType.PLAINS
		Vector2i(2, 1): return TerrainType.WATER
		Vector2i(0, 2): return TerrainType.SWAMP
		Vector2i(1, 2): return TerrainType.OCEAN
		_: return TerrainType.FOREST

func _scene_for_cell(x: int, y: int) -> String:
	match Vector2i(x, y):
		Vector2i(0, 0): return "strategic_snow_v1"
		Vector2i(1, 0): return "strategic_mountain_v1"
		Vector2i(2, 0): return "strategic_meadow_v2"
		Vector2i(0, 1): return "strategic_sand_v1"
		Vector2i(1, 1): return "strategic_meadow_v1"
		Vector2i(2, 1): return "strategic_river_meadow_vertical_v1"
		Vector2i(0, 2): return "strategic_swamp_v1"
		Vector2i(1, 2): return "strategic_ocean_v1"
		_: return "strategic_meadow_v2"

func _empty_deployment(size_meters: Vector2) -> Dictionary:
	return {
		"zone_meters": Rect2(Vector2.ZERO, size_meters),
		"marker_positions_meters": [],
		"marker_personnel": [],
		"marker_count": 0,
		"initial_deployed_personnel": 0,
		"total_personnel": 0,
		"reserve_personnel": 0,
	}

func _settle(frame_count: int) -> void:
	for _frame: int in range(frame_count):
		await process_frame

func _capture(label: String) -> void:
	var image: Image = get_root().get_viewport().get_texture().get_image()
	assert(image != null and not image.is_empty(), "Site tile join capture is empty")
	var absolute_dir: String = ProjectSettings.globalize_path(CAPTURE_DIR)
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
	assert(mkdir_error == OK or mkdir_error == ERR_ALREADY_EXISTS, "Could not create Site tile join directory")
	var path: String = "%s/%s.png" % [CAPTURE_DIR, label]
	assert(image.save_png(path) == OK, "Could not save Site tile join capture")
	capture_count += 1
	print("SITE TILE JOIN CAPTURE: %s" % ProjectSettings.globalize_path(path))
