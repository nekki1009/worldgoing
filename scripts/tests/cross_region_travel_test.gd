extends SceneTree

const TEST_SEED: int = 123456789
const GlobalTravelPathType = preload("res://scripts/data/global_travel_path.gd")

var world_data: WorldData
var global_path: GlobalTravelPathType

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	assert(load("res://scenes/Main.tscn") is PackedScene, "Main scene could not be loaded")
	world_data = WorldData.new()
	_test_canonical_party_position()
	_test_east_west_border()
	_test_north_south_border()
	_test_negative_border()
	_test_corner_border()
	_test_border_cost_matches_local()
	_test_lazy_world_sampling()
	_test_global_path()
	_test_global_path_metadata_and_continuity()
	_test_regions_crossed_are_distinct()
	_test_path_cache_independence()
	_test_local_global_cost_contract()
	_test_session_path_persistence()
	_test_no_repath_index_progression()
	_test_speed_multiplier_is_visual_only()
	_test_cancel_keeps_position_and_time()
	_test_poi_site_gate()
	_test_search_limit()
	print("Cross-region travel tests passed: 18 cases")
	quit()

func _test_canonical_party_position() -> void:
	var party: PartyData = PartyData.new()
	assert(party.current_global_region_cell == Vector2i(350, 450), "Party global default changed")
	assert(party.get_world_cell() == Vector2i(3, 4), "Party world derivation failed")
	assert(party.get_region_cell() == Vector2i(50, 50), "Party region derivation failed")
	party.set_global_region_cell(Vector2i(320, 430))
	assert(party.get_world_cell() == Vector2i(3, 4), "Party world derivation lost global source")
	assert(party.get_region_cell() == Vector2i(20, 30), "Party region derivation lost global source")
	print("TEST 1 PASS: PartyData has one canonical global position")

func _test_east_west_border() -> void:
	var east: Dictionary = WorldCoordinates.global_region_cell_to_world_region(Vector2i(100, 50))
	assert(east["world_cell"] == Vector2i(1, 0), "East border world conversion failed")
	assert(east["region_cell"] == Vector2i(0, 50), "East border region conversion failed")
	var west: Dictionary = WorldCoordinates.global_region_cell_to_world_region(Vector2i(99, 50))
	assert(west["world_cell"] == Vector2i(0, 0), "West border world conversion failed")
	assert(west["region_cell"] == Vector2i(99, 50), "West border region conversion failed")
	print("TEST 2 PASS: East and West Region border conversion")

func _test_north_south_border() -> void:
	var south: Dictionary = WorldCoordinates.global_region_cell_to_world_region(Vector2i(50, 100))
	assert(south["world_cell"] == Vector2i(0, 1), "South border world conversion failed")
	assert(south["region_cell"] == Vector2i(50, 0), "South border region conversion failed")
	var north: Dictionary = WorldCoordinates.global_region_cell_to_world_region(Vector2i(50, 99))
	assert(north["world_cell"] == Vector2i(0, 0), "North border world conversion failed")
	assert(north["region_cell"] == Vector2i(50, 99), "North border region conversion failed")
	print("TEST 3 PASS: North and South Region border conversion")

func _test_negative_border() -> void:
	var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(Vector2i(-1, 50))
	assert(converted["world_cell"] == Vector2i(-1, 0), "Negative border world conversion failed")
	assert(converted["region_cell"] == Vector2i(99, 50), "Negative border region conversion failed")
	print("TEST 4 PASS: negative global coordinate uses floor division")

func _test_corner_border() -> void:
	var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(Vector2i(100, 100))
	assert(converted["world_cell"] == Vector2i(1, 1), "Corner border world conversion failed")
	assert(converted["region_cell"] == Vector2i.ZERO, "Corner border region conversion failed")
	assert(not is_finite(TravelCostConfig.step_distance_meters(Vector2i.ONE)), "Diagonal travel distance was accepted")
	var info: Dictionary = {"passable": true, "travel_exit_mask": SiteLayoutData.EXIT_ALL}
	assert(not TravelCostConfig.can_traverse_site_edge(info, info, Vector2i.ONE), "Diagonal Site edge was accepted")
	print("TEST 5 PASS: corner coordinate conversion is separate from four-way travel")

func _test_border_cost_matches_local() -> void:
	var info: Dictionary = {
		"passable": true,
		"terrain_type": TerrainType.PLAINS,
		"road": false,
		"river": false,
		"river_crossing": false,
		"elevation": 0.0,
	}
	var border_seconds: int = roundi(TravelCostConfig.step_travel_seconds(
			info,
			info,
			Vector2i.RIGHT,
			TravelCostConfig.DEFAULT_WALK_SPEED_KMH
		))
	assert(border_seconds == 72, "Region border added time to a Plains step")
	print("TEST 6 PASS: border step uses the normal 100m Plains cost")

func _test_lazy_world_sampling() -> void:
	var sample: Dictionary = world_data.sample_travel_data(TEST_SEED, Vector2i(100, 50))
	for key: String in ["terrain_type", "elevation", "road", "river", "river_crossing", "passable", "travel_speed_kmh"]:
		assert(sample.has(key), "Global travel sample is missing %s" % key)
	assert(sample["global_region_cell"] == Vector2i(100, 50), "Global sample changed its coordinate")
	print("TEST 7 PASS: global sampling uses WorldData without a Region Scene")

func _test_global_path() -> void:
	var pathfinder: PartyPathfinder = PartyPathfinder.new()
	var start: Vector2i = _find_clear_cell(Vector2i(0, 0))
	assert(start != Vector2i(-1, -1), "Could not find a passable start cell")
	var found: GlobalTravelPathType
	for y: int in range(0, 3):
		for x: int in range(2, 4):
			var destination: Vector2i = _find_clear_cell(Vector2i(x, y))
			if destination == Vector2i(-1, -1):
				continue
			var candidate: GlobalTravelPathType = pathfinder.find_global_path(
					world_data,
					start,
					destination,
					TEST_SEED,
					TravelCostConfig.DEFAULT_WALK_SPEED_KMH
				)
			if candidate.has_path() and candidate.regions_crossed >= 2:
				found = candidate
				break
		if found != null:
			break
	assert(found != null and found.has_path(), "No cross-Region Global Path was generated")
	global_path = found
	print("TEST 8 PASS: Global Path generated across %d Regions (%.1f km)" % [global_path.regions_crossed, global_path.total_distance_meters / 1000.0])

func _test_global_path_metadata_and_continuity() -> void:
	assert(global_path.start_global_cell == global_path.cells.front(), "Global Path start metadata is wrong")
	assert(global_path.destination_global_cell == global_path.cells.back(), "Global Path destination metadata is wrong")
	assert(global_path.step_travel_seconds.size() == global_path.cells.size() - 1, "Global Path step metadata is incomplete")
	assert(global_path.search_margin <= PartyPathfinder.GLOBAL_PATH_FALLBACK_MARGINS.back(), "Global Path margin exceeded fallback limit")
	for index: int in range(1, global_path.cells.size()):
		var delta: Vector2i = global_path.cells[index] - global_path.cells[index - 1]
		assert(absi(delta.x) + absi(delta.y) == 1, "Global Path contains a diagonal or zero-length step")
	print("TEST 9 PASS: one continuous bounded orthogonal Global Path with metadata")

func _test_regions_crossed_are_distinct() -> void:
	var distinct: Dictionary = {}
	for cell: Vector2i in global_path.cells:
		var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(cell)
		distinct[converted["world_cell"] as Vector2i] = true
	assert(global_path.regions_crossed == distinct.size(), "Regions Crossed was guessed from endpoints")
	print("TEST 10 PASS: Regions Crossed counts distinct path Regions")

func _test_path_cache_independence() -> void:
	var pathfinder: PartyPathfinder = PartyPathfinder.new()
	var first: GlobalTravelPathType = pathfinder.find_global_path(
			world_data,
			global_path.start_global_cell,
			global_path.destination_global_cell,
			TEST_SEED,
			TravelCostConfig.DEFAULT_WALK_SPEED_KMH
		)
	world_data.clear_road_cache()
	var second: GlobalTravelPathType = pathfinder.find_global_path(
			world_data,
			global_path.start_global_cell,
			global_path.destination_global_cell,
			TEST_SEED,
			TravelCostConfig.DEFAULT_WALK_SPEED_KMH
		)
	assert(first.path_hash() == second.path_hash(), "Global Path changed after cache clear")
	print("TEST 11 PASS: Global Path is cache-independent")

func _test_local_global_cost_contract() -> void:
	var local: PartyPathResult = PartyPathfinder.new().find_path(
			RegionTerrainData.new(),
			RegionRoadOverlay.new(),
			Vector2i.ZERO,
			Vector2i.RIGHT,
			TravelCostConfig.DEFAULT_WALK_SPEED_KMH
		)
	assert(local.has_path() and local.step_travel_seconds[0] == 72, "Local Plains cost changed")
	var info: Dictionary = {
		"passable": true,
		"terrain_type": TerrainType.PLAINS,
		"road": false,
		"river": false,
		"river_crossing": false,
		"elevation": 0.0,
	}
	var global_seconds: int = roundi(TravelCostConfig.step_travel_seconds(info, info, Vector2i.RIGHT, TravelCostConfig.DEFAULT_WALK_SPEED_KMH))
	assert(global_seconds == local.step_travel_seconds[0], "Local and global travel costs diverged")
	print("TEST 12 PASS: local and global path costs share TravelCostConfig")

func _test_session_path_persistence() -> void:
	var session: GameSession = GameSession.new()
	session.party.set_global_region_cell(global_path.start_global_cell)
	session.party.initialized = true
	session.set_travel_plan(global_path)
	var path_hash: String = session.active_global_travel_path.path_hash()
	assert(session.has_travel_plan(), "Session did not retain Global Path preview")
	assert(session.active_global_travel_path.path_hash() == path_hash, "Session changed the stored path")
	print("TEST 13 PASS: Session retains full Global Path state")

func _test_no_repath_index_progression() -> void:
	var session: GameSession = GameSession.new()
	session.set_travel_plan(global_path)
	var path_hash: String = session.active_global_travel_path.path_hash()
	session.global_travel_path_index = mini(3, global_path.cells.size() - 1)
	assert(session.active_global_travel_path.path_hash() == path_hash, "Path changed while index advanced")
	assert(session.global_travel_path_index >= 0, "Path index was reset at a Region boundary")
	print("TEST 14 PASS: Region transition advances index without repathing")

func _test_speed_multiplier_is_visual_only() -> void:
	var session: GameSession = GameSession.new()
	session.set_travel_plan(global_path)
	var step_seconds: int = global_path.step_travel_seconds[0]
	session.travel_speed_multiplier = 16.0
	assert(global_path.step_travel_seconds[0] == step_seconds, "Speed multiplier changed World Time cost")
	print("TEST 15 PASS: Travel Speed Multiplier changes playback only")

func _test_cancel_keeps_position_and_time() -> void:
	var session: GameSession = GameSession.new()
	session.party.set_global_region_cell(global_path.cells[mini(2, global_path.cells.size() - 1)])
	session.party.initialized = true
	session.set_travel_plan(global_path)
	var position_before: Vector2i = session.party.current_global_region_cell
	var time_before: int = session.world_time_seconds
	session.travel_cancel_requested = true
	session.clear_travel()
	assert(session.party.current_global_region_cell == position_before, "Cancel moved the Party")
	assert(session.world_time_seconds == time_before, "Cancel refunded or added World Time")
	print("TEST 16 PASS: cancel preserves current global cell and consumed time")

func _test_poi_site_gate() -> void:
	var poi: WorldPOIData = _find_poi()
	assert(poi != null, "No deterministic POI found for arrival gate")
	var navigation: NavigationController = NavigationController.new()
	navigation.world_data = world_data
	navigation.session.world_seed = TEST_SEED
	navigation.session.selected_world_cell = poi.world_cell
	navigation.session.party.set_global_region_cell(poi.global_region_cell)
	navigation.session.party.initialized = true
	assert(navigation.can_enter_site_at(poi.region_cell), "Party at remote POI could not enter Site")
	var away: Vector2i = poi.region_cell + Vector2i.RIGHT if poi.region_cell.x < 99 else poi.region_cell - Vector2i.RIGHT
	navigation.session.party.set_global_region_cell(
		WorldCoordinates.world_region_to_global_region_cell(poi.world_cell, away)
	)
	assert(navigation.can_enter_site_at(poi.region_cell), "Site entry still depends on Party position")
	navigation.free()
	print("TEST 17 PASS: any Region tile can enter Site without Party locality")

func _test_search_limit() -> void:
	var far: Vector2i = _find_clear_global_cell_near(global_path.start_global_cell + Vector2i(5000, 0))
	assert(far != Vector2i(-1, -1), "Could not find a passable far destination")
	var result: GlobalTravelPathType = PartyPathfinder.new().find_global_path(
			world_data,
			global_path.start_global_cell,
			far,
			TEST_SEED,
			TravelCostConfig.DEFAULT_WALK_SPEED_KMH
		)
	assert(not result.has_path() and result.error_message == "Path search limit exceeded", "Far Global Path did not fail safely")
	print("TEST 18 PASS: bounded search rejects an over-limit destination safely")

func _find_clear_cell(world_cell: Vector2i) -> Vector2i:
	return _find_clear_global_cell_near(WorldCoordinates.world_region_to_global_region_cell(world_cell, Vector2i(50, 50)))

func _find_clear_global_cell_near(center: Vector2i) -> Vector2i:
	for radius: int in range(50):
		for y: int in range(center.y - radius, center.y + radius + 1):
			for x: int in range(center.x - radius, center.x + radius + 1):
				if maxi(abs(x - center.x), abs(y - center.y)) != radius:
					continue
				var global_cell: Vector2i = Vector2i(x, y)
				var sample: Vector4 = world_data.terrain_generator.macro_sampler.sample(TEST_SEED, global_cell)
				var terrain_type: int = world_data.terrain_generator.classify_sample(sample)
				if not TerrainType.is_water_like(terrain_type) and sample.z <= 0.0:
					return global_cell
	return Vector2i(-1, -1)

func _find_poi() -> WorldPOIData:
	for y: int in range(1, 5):
		for x: int in range(1, 5):
			var pois: Array[WorldPOIData] = world_data.get_pois_for_region(Vector2i(x, y), TEST_SEED)
			if not pois.is_empty():
				return pois[0]
	return null
