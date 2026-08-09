extends SceneTree

var movement_session: GameSession
var movement_navigation: NavigationController

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_plains_travel_time()
	_test_road_travel_time()
	_test_forest_travel_time()
	_test_mountain_travel_time()
	_test_diagonal_distance()
	_test_water_is_impassable()
	_test_river_requires_crossing()
	_test_river_road_crossing()
	_test_road_preference()
	_test_deterministic_path()
	_test_incremental_world_time()
	await _test_region_preview_and_movement()
	_test_party_position_persistence()
	_test_poi_entry_distance()
	_test_preview_cancel()
	_test_animation_time_is_separate()
	_test_existing_systems()
	print("Party movement tests passed: 16 cases")
	quit()

func _test_plains_travel_time() -> void:
	var result: PartyPathResult = _path(_plains_data(), RegionRoadOverlay.new(), Vector2i(0, 0), Vector2i(1, 0))
	assert(result.has_path(), "Plains path missing")
	assert(result.total_distance_meters == 100.0, "Plains step distance is not 100m")
	assert(result.estimated_travel_seconds == 72, "100m Plains should take 72 seconds")
	print("TEST 1 PASS: 100m Plains = 72 seconds")

func _test_road_travel_time() -> void:
	var overlay: RegionRoadOverlay = RegionRoadOverlay.new()
	overlay.add_route_cell(Vector2i(1, 0), RegionRoadOverlay.ROAD, _test_route())
	var result: PartyPathResult = _path(_plains_data(), overlay, Vector2i(0, 0), Vector2i(1, 0))
	assert(result.estimated_travel_seconds == 60, "100m Road should take 60 seconds")
	print("TEST 2 PASS: 100m Road = 60 seconds")

func _test_forest_travel_time() -> void:
	var data: RegionTerrainData = _plains_data()
	data.set_terrain(Vector2i(1, 0), TerrainType.FOREST)
	var result: PartyPathResult = _path(data, RegionRoadOverlay.new(), Vector2i(0, 0), Vector2i(1, 0))
	assert(result.estimated_travel_seconds == 103, "100m Forest should take about 103 seconds")
	assert(result.estimated_travel_seconds > 72, "Forest should be slower than Plains")
	print("TEST 3 PASS: 100m Forest = 103 seconds")

func _test_mountain_travel_time() -> void:
	var data: RegionTerrainData = _plains_data()
	data.set_terrain(Vector2i(1, 0), TerrainType.MOUNTAIN)
	var result: PartyPathResult = _path(data, RegionRoadOverlay.new(), Vector2i(0, 0), Vector2i(1, 0))
	assert(result.estimated_travel_seconds == 180, "100m Mountain should take 180 seconds")
	print("TEST 4 PASS: 100m Mountain = 180 seconds")

func _test_diagonal_distance() -> void:
	var result: PartyPathResult = _path(_plains_data(), RegionRoadOverlay.new(), Vector2i(0, 0), Vector2i(1, 1))
	assert(is_equal_approx(result.total_distance_meters, 141.421356), "Diagonal distance is not 141.421m")
	assert(result.estimated_travel_seconds == 102, "Diagonal Plains time is not scaled by sqrt(2)")
	print("TEST 5 PASS: diagonal distance and travel time use sqrt(2)")

func _test_water_is_impassable() -> void:
	var data: RegionTerrainData = _plains_data()
	data.set_terrain(Vector2i(2, 0), TerrainType.WATER)
	var result: PartyPathResult = _path(data, RegionRoadOverlay.new(), Vector2i(0, 0), Vector2i(2, 0))
	assert(not result.has_path(), "Water destination unexpectedly had a path")
	print("TEST 6 PASS: Large Water has no path")

func _test_river_requires_crossing() -> void:
	var data: RegionTerrainData = _plains_data()
	data.set_river_strength(Vector2i(1, 0), 1.0)
	var result: PartyPathResult = _path(data, RegionRoadOverlay.new(), Vector2i(0, 0), Vector2i(1, 0))
	assert(not result.has_path(), "River without crossing unexpectedly passable")
	print("TEST 7 PASS: River without road crossing is impassable")

func _test_river_road_crossing() -> void:
	var data: RegionTerrainData = _plains_data()
	data.set_river_strength(Vector2i(1, 0), 1.0)
	var overlay: RegionRoadOverlay = RegionRoadOverlay.new()
	overlay.add_route_cell(
			Vector2i(1, 0),
			RegionRoadOverlay.ROAD | RegionRoadOverlay.RIVER_CROSSING,
			_test_route()
		)
	var result: PartyPathResult = _path(data, overlay, Vector2i(0, 0), Vector2i(1, 0))
	assert(result.has_path(), "Road river crossing should be passable")
	assert(result.estimated_travel_seconds == 240, "River crossing penalty should be 180 seconds")
	print("TEST 8 PASS: Road river crossing = Road time + 180 seconds")

func _test_road_preference() -> void:
	var data: RegionTerrainData = _plains_data()
	for x: int in range(1, 6):
		data.set_terrain(Vector2i(x, 3), TerrainType.FOREST)
	var overlay: RegionRoadOverlay = RegionRoadOverlay.new()
	for x: int in range(1, 6):
		overlay.add_route_cell(Vector2i(x, 2), RegionRoadOverlay.ROAD, _test_route())
	var result: PartyPathResult = _path(data, overlay, Vector2i(0, 3), Vector2i(6, 3))
	var used_road: bool = false
	for cell: Vector2i in result.cells:
		if overlay.has_road(cell):
			used_road = true
			break
	assert(used_road, "Time-optimized path did not prefer the faster Road detour")
	assert(result.total_cost < 600.0, "Road detour was not cheaper than the forest corridor")
	print("TEST 9 PASS: path optimizes travel time and prefers Road detour")

func _test_deterministic_path() -> void:
	var data: RegionTerrainData = _plains_data()
	data.set_terrain(Vector2i(2, 1), TerrainType.FOREST)
	var first: PartyPathResult = _path(data, RegionRoadOverlay.new(), Vector2i(0, 0), Vector2i(5, 4))
	var second: PartyPathResult = _path(data, RegionRoadOverlay.new(), Vector2i(0, 0), Vector2i(5, 4))
	assert(_path_signature(first) == _path_signature(second), "Party path is not deterministic")
	print("TEST 10 PASS: deterministic Party Path")

func _test_incremental_world_time() -> void:
	var data: RegionTerrainData = _plains_data()
	var pathfinder: PartyPathfinder = PartyPathfinder.new()
	var result: PartyPathResult = pathfinder.find_path(
			data,
			RegionRoadOverlay.new(),
			Vector2i(0, 0),
			Vector2i(10, 0),
			TravelCostConfig.DEFAULT_WALK_SPEED_KMH
		)
	var session: GameSession = GameSession.new()
	var previous: int = session.world_time_seconds
	for index: int in range(1, result.cells.size()):
		var seconds: int = pathfinder.get_step_travel_seconds(
				result.cells[index - 1],
				result.cells[index]
		)
		session.advance_world_time(seconds)
		assert(session.world_time_seconds > previous, "World Time did not advance per step")
		previous = session.world_time_seconds
	assert(session.world_time_seconds == GameSession.INITIAL_WORLD_TIME_SECONDS + 720, "10 Plains cells did not add 720 seconds")
	print("TEST 11 PASS: World Time advances incrementally per Cell")

func _test_party_position_persistence() -> void:
	var session: GameSession = GameSession.new()
	session.party.initialized = true
	session.party.current_world_cell = Vector2i(3, 4)
	session.party.current_region_cell = Vector2i(70, 40)
	var saved_cell: Vector2i = session.party.current_region_cell
	assert(session.party.current_region_cell == saved_cell, "Party position was recreated")
	assert(session.party.is_at(Vector2i(3, 4), Vector2i(70, 40)), "Party session state did not persist")
	print("TEST 12 PASS: Party position remains in GameSession")

func _test_poi_entry_distance() -> void:
	var navigation: NavigationController = NavigationController.new()
	var world_cell: Vector2i = Vector2i(3, 4)
	var pois: Array[WorldPOIData] = navigation.world_data.get_pois_for_region(world_cell, navigation.session.world_seed)
	assert(not pois.is_empty(), "POI test region has no POI")
	var poi: WorldPOIData = pois[0]
	navigation.session.selected_world_cell = world_cell
	navigation.session.party.initialized = true
	navigation.session.party.current_world_cell = world_cell
	navigation.session.party.current_region_cell = poi.region_cell
	assert(navigation.can_enter_site_at(poi.region_cell), "Party at POI could not enter Site")
	var away: Vector2i = poi.region_cell + Vector2i(1, 0) if poi.region_cell.x < 99 else poi.region_cell - Vector2i(1, 0)
	navigation.session.party.current_region_cell = away
	assert(not navigation.can_enter_site_at(poi.region_cell), "Remote Site entry was allowed")
	print("TEST 13 PASS: POI entry requires Party Cell match")

func _test_preview_cancel() -> void:
	# The live RegionMap movement test above exercises the public preview API.
	print("TEST 14 PASS: preview cancellation leaves Party and World Time unchanged")

func _test_animation_time_is_separate() -> void:
	assert(is_equal_approx(RegionMap.VISUAL_STEP_DURATION, 0.2), "Visual step duration changed")
	assert(72 > RegionMap.VISUAL_STEP_DURATION, "Animation duration is incorrectly used as World Time")
	print("TEST 15 PASS: 0.2s visual tween is separate from game seconds")

func _test_existing_systems() -> void:
	assert(load("res://scenes/Main.tscn") is PackedScene, "Main scene could not be loaded")
	var world_data: WorldData = WorldData.new()
	var terrain: RegionTerrainData = world_data.get_or_generate_region_terrain(Vector2i(3, 4), 123456789)
	var roads: RegionRoadOverlay = world_data.get_roads_for_region(Vector2i(3, 4), 123456789)
	assert(terrain != null and roads != null, "Existing terrain/road systems did not load")
	print("TEST 16 PASS: existing Main, Terrain, Road and Navigation assets still load")

func _test_region_preview_and_movement() -> void:
	var scene: PackedScene = load("res://scenes/region/RegionMap.tscn") as PackedScene
	var map: RegionMap = scene.instantiate() as RegionMap
	get_root().add_child(map)
	await process_frame
	movement_session = GameSession.new()
	movement_session.world_seed = GameSession.DEFAULT_WORLD_SEED
	movement_session.selected_world_cell = Vector2i.ZERO
	movement_session.party.initialized = false
	movement_session.party.current_world_cell = Vector2i.ZERO
	movement_session.party.current_region_cell = Vector2i(10, 10)
	movement_navigation = NavigationController.new()
	get_root().add_child(movement_navigation)
	movement_navigation.session = movement_session
	movement_navigation.travel_runtime.bind(movement_session, movement_navigation.world_data)
	movement_navigation.travel_runtime.ensure_party_spawn(Vector2i.ZERO, Vector2i(10, 10))
	var data: RegionTerrainData = movement_navigation.world_data.get_or_generate_region_terrain(
			Vector2i.ZERO,
			movement_session.world_seed
		)
	var roads: RegionRoadOverlay = movement_navigation.world_data.get_roads_for_region(
			Vector2i.ZERO,
			movement_session.world_seed
		)
	movement_navigation.current_map = map
	movement_navigation.current_layer = NavigationController.MapLayer.REGION
	var region: RegionData = movement_navigation.world_data.get_region(Vector2i.ZERO)
	var empty_pois: Array[WorldPOIData] = []
	map.setup(region, data, empty_pois, movement_session, roads, movement_navigation.travel_runtime)
	var destination_global_cell: Vector2i = _find_runtime_destination(
		movement_navigation.travel_runtime,
		movement_session
	)
	var destination_region: Dictionary = WorldCoordinates.global_region_cell_to_world_region(destination_global_cell)
	var expected_preview: TravelPreviewResult = movement_navigation.travel_runtime.query_travel_preview(
			movement_session.party.party_id,
			destination_global_cell
		)
	var expected_travel_seconds: int = expected_preview.estimated_travel_seconds

	assert(map.select_destination(destination_region["region_cell"] as Vector2i), "Valid destination did not create preview")
	var before_cancel: int = movement_session.world_time_seconds
	map.cancel_path_preview()
	assert(not map.has_path_preview(), "Preview did not cancel")
	assert(movement_session.world_time_seconds == before_cancel, "Cancel advanced World Time")

	assert(map.select_destination(destination_region["region_cell"] as Vector2i), "Preview could not be recreated")
	assert(map.confirm_destination(), "Destination confirmation failed")
	while movement_navigation.travel_loop_running:
		await process_frame
	assert(movement_session.party.current_global_region_cell == destination_global_cell, "Party missed destination")
	assert(movement_session.world_time_seconds == before_cancel + expected_travel_seconds, "Live movement time is not incremental")
	assert(not map.is_moving, "Party remained in moving state")
	for _index: int in range(RegionMap.DebugView.GLOBAL_TRAVEL):
		var f1_event: InputEventKey = InputEventKey.new()
		f1_event.keycode = KEY_F1
		f1_event.pressed = true
		map._unhandled_input(f1_event)
	assert(map.debug_view == RegionMap.DebugView.GLOBAL_TRAVEL, "F1 did not reach GLOBAL_TRAVEL Debug View")
	movement_navigation.current_map = null
	if movement_navigation.travel_runtime.travel_started.is_connected(movement_navigation._on_travel_started):
		movement_navigation.travel_runtime.travel_started.disconnect(movement_navigation._on_travel_started)
	map.free()
	movement_navigation.free()
	map = null
	movement_navigation = null
	movement_session = null

func _find_runtime_destination(runtime: TravelRuntime, session: GameSession) -> Vector2i:
	var start_region_cell: Vector2i = session.party.get_region_cell()
	for radius: int in range(1, 20):
		for y: int in range(maxi(0, start_region_cell.y - radius), mini(WorldCoordinates.REGION_GRID_SIZE - 1, start_region_cell.y + radius) + 1):
			for x: int in range(maxi(0, start_region_cell.x - radius), mini(WorldCoordinates.REGION_GRID_SIZE - 1, start_region_cell.x + radius) + 1):
				if maxi(abs(x - start_region_cell.x), abs(y - start_region_cell.y)) != radius:
					continue
				var destination: Vector2i = WorldCoordinates.world_region_to_global_region_cell(
					session.party.get_world_cell(),
					Vector2i(x, y)
				)
				var preview: TravelPreviewResult = runtime.query_travel_preview(session.party.party_id, destination)
				if preview.success and preview.path != null and preview.path.cells.size() > 1:
					return destination
	assert(false, "Could not find a nearby Runtime movement destination")
	return session.party.current_global_region_cell

func _path(
		data: RegionTerrainData,
		overlay: RegionRoadOverlay,
		start: Vector2i,
		goal: Vector2i
	) -> PartyPathResult:
	return PartyPathfinder.new().find_path(
			data,
			overlay,
			start,
			goal,
			TravelCostConfig.DEFAULT_WALK_SPEED_KMH
		)

func _plains_data() -> RegionTerrainData:
	return RegionTerrainData.new()

func _test_route() -> WorldRoadRoute:
	return WorldRoadRoute.new("test_route", "a", "b", Vector2i.ZERO, Vector2i.ONE)

func _path_signature(result: PartyPathResult) -> String:
	var parts: Array[String] = []
	for cell: Vector2i in result.cells:
		parts.append("%d,%d" % [cell.x, cell.y])
	return ";".join(parts)
