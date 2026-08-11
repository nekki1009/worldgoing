extends SceneTree

const TEST_SEED: int = 123456789
const DIFFERENT_SEED: int = 987654321

func _init() -> void:
	assert(load("res://scenes/Main.tscn") is PackedScene, "Main scene could not be loaded")
	var terrain_generator: RegionTerrainGenerator = RegionTerrainGenerator.new()
	var poi_generator: WorldPOIGenerator = WorldPOIGenerator.new(terrain_generator)

	_test_deterministic(poi_generator)
	print("POI TEST 1 PASS: repeated Region query is deterministic")
	_test_reload_order(poi_generator)
	print("POI TEST 2 PASS: Region query order does not affect POI results")
	_test_different_seed(poi_generator)
	print("POI TEST 3 PASS: different World Seed changes POI distribution")
	var stable_poi: WorldPOIData = _find_first_poi(poi_generator, TEST_SEED)
	assert(stable_poi != null, "No POI was generated for stable ID test")
	_test_stable_id(poi_generator, stable_poi)
	print("POI TEST 4 PASS: POI ID and name are stable")
	_test_border_spacing(poi_generator)
	print("POI TEST 5 PASS: settlement spacing is enforced across Region border")
	_test_coordinate_conversion()
	print("POI TEST 6 PASS: global cell converts to World Cell and Region Cell")
	_test_negative_coordinate(poi_generator)
	print("POI TEST 7 PASS: negative coordinates use floor candidate division")
	_test_terrain_suitability(poi_generator, terrain_generator)
	print("POI TEST 8 PASS: POI terrain suitability rules hold")
	_test_site_context(poi_generator)
	print("POI TEST 9 PASS: Site Map receives complete POI context")
	_test_cache_independence()
	print("POI TEST 10 PASS: clearing POI cache preserves deterministic results")
	var distribution: Array[int] = _count_types(poi_generator)
	print("POI distribution sample: VILLAGE=%d TOWN=%d CASTLE=%d RUINS=%d CAVE=%d" % distribution)
	print("World POI tests passed: 10 cases")
	quit()

func _test_deterministic(generator: WorldPOIGenerator) -> void:
	var first: Array[WorldPOIData] = generator.generate_for_region(TEST_SEED, Vector2i(3, 4))
	var second: Array[WorldPOIData] = generator.generate_for_region(TEST_SEED, Vector2i(3, 4))
	assert(not first.is_empty(), "Default test Region has no POI")
	assert(_signature(first) == _signature(second), "Repeated POI query changed its result")

func _test_reload_order(generator: WorldPOIGenerator) -> void:
	var first_a: Array[WorldPOIData] = generator.generate_for_region(TEST_SEED, Vector2i(0, 0))
	var first_b: Array[WorldPOIData] = generator.generate_for_region(TEST_SEED, Vector2i(1, 0))
	var second_b: Array[WorldPOIData] = generator.generate_for_region(TEST_SEED, Vector2i(1, 0))
	var second_a: Array[WorldPOIData] = generator.generate_for_region(TEST_SEED, Vector2i(0, 0))
	assert(_signature(first_a) == _signature(second_a), "Region (0,0) depends on query order")
	assert(_signature(first_b) == _signature(second_b), "Region (1,0) depends on query order")

func _test_different_seed(generator: WorldPOIGenerator) -> void:
	var first: Array[WorldPOIData] = generator.generate_for_region(TEST_SEED, Vector2i(3, 4))
	var second: Array[WorldPOIData] = generator.generate_for_region(DIFFERENT_SEED, Vector2i(3, 4))
	assert(_signature(first) != _signature(second), "Different seeds produced identical POI distribution")

func _find_first_poi(generator: WorldPOIGenerator, world_seed: int) -> WorldPOIData:
	for y: int in range(0, WorldData.WORLD_CELLS.y, 8):
		for x: int in range(0, WorldData.WORLD_CELLS.x, 8):
			var pois: Array[WorldPOIData] = generator.generate_for_region(world_seed, Vector2i(x, y))
			if not pois.is_empty():
				return pois[0]
	return null

func _test_stable_id(generator: WorldPOIGenerator, expected: WorldPOIData) -> void:
	var first: Array[WorldPOIData] = generator.generate_for_region(TEST_SEED, expected.world_cell)
	var second: Array[WorldPOIData] = generator.generate_for_region(TEST_SEED, expected.world_cell)
	var first_match: WorldPOIData = _find_poi_by_id(first, expected.poi_id)
	var second_match: WorldPOIData = _find_poi_by_id(second, expected.poi_id)
	assert(first_match != null and second_match != null, "Stable POI disappeared on repeated query")
	assert(first_match.poi_id == second_match.poi_id, "Stable POI ID changed")
	assert(first_match.site_name == second_match.site_name, "Stable POI name changed")

func _find_poi_by_id(pois: Array[WorldPOIData], poi_id: String) -> WorldPOIData:
	for poi: WorldPOIData in pois:
		if poi.poi_id == poi_id:
			return poi
	return null

func _test_border_spacing(generator: WorldPOIGenerator) -> void:
	var left: Array[WorldPOIData] = generator.generate_for_region(TEST_SEED, Vector2i(0, 0))
	var right: Array[WorldPOIData] = generator.generate_for_region(TEST_SEED, Vector2i(1, 0))
	var all_pois: Array[WorldPOIData] = []
	all_pois.append_array(left)
	all_pois.append_array(right)
	var ids: Dictionary = {}
	for poi: WorldPOIData in all_pois:
		assert(not ids.has(poi.poi_id), "Duplicate POI ID across Region border")
		ids[poi.poi_id] = true
	for left_poi: WorldPOIData in left:
		if not WorldPOIType.is_settlement(left_poi.poi_type):
			continue
		for right_poi: WorldPOIData in right:
			if not WorldPOIType.is_settlement(right_poi.poi_type):
				continue
			var candidate_distance: Vector2i = left_poi.candidate_cell - right_poi.candidate_cell
			assert(
				abs(candidate_distance.x) > WorldPOIGenerator.SETTLEMENT_SPACING_RADIUS \
				or abs(candidate_distance.y) > WorldPOIGenerator.SETTLEMENT_SPACING_RADIUS,
				"Adjacent settlement candidates bypassed border spacing"
			)

func _test_coordinate_conversion() -> void:
	var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(Vector2i(320, 430))
	assert(converted["world_cell"] as Vector2i == Vector2i(3, 4), "World Cell reverse conversion failed")
	assert(converted["region_cell"] as Vector2i == Vector2i(20, 30), "Region Cell reverse conversion failed")

func _test_negative_coordinate(generator: WorldPOIGenerator) -> void:
	var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(Vector2i(-1, 50))
	assert(converted["world_cell"] as Vector2i == Vector2i(-1, 0), "Negative World Cell conversion failed")
	assert(converted["region_cell"] as Vector2i == Vector2i(99, 50), "Negative Region Cell conversion failed")
	assert(WorldCoordinates.floor_divide(-1, WorldPOIGenerator.POI_CANDIDATE_GRID_SIZE) == -1, "Negative candidate floor division failed")
	var negative_sample: Vector4 = generator.macro_sampler.sample(TEST_SEED, Vector2i(-1, 50))
	assert(negative_sample.x >= 0.0 and negative_sample.x <= 1.0, "Negative POI terrain sample failed")

func _test_terrain_suitability(generator: WorldPOIGenerator, terrain_generator: RegionTerrainGenerator) -> void:
	var counts: Array[int] = [0, 0, 0, 0, 0]
	for y: int in range(0, WorldData.WORLD_CELLS.y, 8):
		for x: int in range(0, WorldData.WORLD_CELLS.x, 8):
			for poi: WorldPOIData in generator.generate_for_region(TEST_SEED, Vector2i(x, y)):
				counts[poi.poi_type] += 1
				if poi.poi_type == WorldPOIType.VILLAGE or poi.poi_type == WorldPOIType.TOWN:
					assert(not TerrainType.is_water_like(poi.terrain_type), "Settlement generated in water")
				if poi.poi_type == WorldPOIType.CASTLE:
					assert(not TerrainType.is_water_like(poi.terrain_type), "Castle generated in water")
				if poi.poi_type == WorldPOIType.CAVE:
					assert(_has_mountain_nearby(generator, terrain_generator, poi), "Cave lacks mountain/high elevation context")
	for poi_type: int in range(WorldPOIType.CAVE + 1):
		assert(counts[poi_type] > 0, "POI type was not represented in suitability sample")

func _has_mountain_nearby(
		generator: WorldPOIGenerator,
		terrain_generator: RegionTerrainGenerator,
		poi: WorldPOIData
	) -> bool:
	if poi.terrain_type == TerrainType.MOUNTAIN or poi.elevation >= 0.58:
		return true
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			var sample: Vector4 = generator.macro_sampler.sample(
				TEST_SEED,
				poi.global_region_cell + Vector2i(offset_x, offset_y)
			)
			if terrain_generator.classify_sample(sample) == TerrainType.MOUNTAIN \
				or sample.x >= RegionTerrainGenerator.MOUNTAIN_THRESHOLD:
				return true
	return false

func _test_site_context(generator: WorldPOIGenerator) -> void:
	var poi: WorldPOIData = _find_first_poi(generator, TEST_SEED)
	var world_data: WorldData = WorldData.new()
	var queried_poi: WorldPOIData = world_data.find_poi_at(
		poi.world_cell,
		poi.region_cell,
		TEST_SEED
	)
	assert(queried_poi != null and queried_poi.poi_id == poi.poi_id, "Region POI query lost site entry")
	var site_map: SiteMap = SiteMap.new()
	var session: GameSession = GameSession.new()
	session.world_seed = TEST_SEED
	session.selected_world_cell = poi.world_cell
	session.selected_region_cell = poi.region_cell
	var runtime: TravelRuntime = TravelRuntime.new(session, world_data)
	var definition: SiteData = world_data.get_site_definition(queried_poi)
	var snapshot: SiteRuntimeSnapshot = runtime.query_site_snapshot(definition.site_id).snapshot
	site_map.setup(snapshot)
	var state: Dictionary = site_map.get_debug_state()
	assert(state["poi_id"] == poi.poi_id, "Site context lost POI ID")
	assert(state["poi_type"] == WorldPOIType.to_display_name(poi.poi_type), "Site context lost POI type")
	assert(state["global_region_cell"] == _format_cell(poi.global_region_cell), "Site context lost global cell")
	site_map.free()

func _test_cache_independence() -> void:
	var world_data: WorldData = WorldData.new()
	var first: Array[WorldPOIData] = world_data.get_pois_for_region(Vector2i(3, 4), TEST_SEED)
	world_data.clear_poi_cache()
	var second: Array[WorldPOIData] = world_data.get_pois_for_region(Vector2i(3, 4), TEST_SEED)
	assert(_signature(first) == _signature(second), "Clearing cache changed POI result")

func _signature(pois: Array[WorldPOIData]) -> String:
	var entries: Array[String] = []
	for poi: WorldPOIData in pois:
		entries.append("%s|%d|%d,%d|%s" % [
			poi.poi_id,
			poi.poi_type,
			poi.global_region_cell.x,
			poi.global_region_cell.y,
			poi.site_name
		])
	entries.sort()
	return "|".join(entries)

func _count_types(generator: WorldPOIGenerator) -> Array[int]:
	var counts: Array[int] = [0, 0, 0, 0, 0]
	for y: int in range(0, WorldData.WORLD_CELLS.y, 8):
		for x: int in range(0, WorldData.WORLD_CELLS.x, 8):
			for poi: WorldPOIData in generator.generate_for_region(TEST_SEED, Vector2i(x, y)):
				counts[poi.poi_type] += 1
	return counts

func _format_cell(cell: Vector2i) -> String:
	return "(%d, %d)" % [cell.x, cell.y]
