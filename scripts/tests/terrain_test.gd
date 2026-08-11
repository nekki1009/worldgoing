extends SceneTree

const TEST_SEED: int = 123456789
const DIFFERENT_SEED: int = 987654321
const BORDER_SCAN_RADIUS: int = 5
const BORDER_SCAN_EXTENT: int = 500

func _init() -> void:
	assert(load("res://scenes/Main.tscn") is PackedScene, "Main scene could not be loaded")
	var generator: RegionTerrainGenerator = RegionTerrainGenerator.new()
	var sampler: WorldMacroTerrainSampler = WorldMacroTerrainSampler.new()
	var sample_cell: Vector2i = Vector2i(537, 280)

	_test_deterministic_sampler(sampler, sample_cell)
	print("TEST 1 PASS: same seed and global cell produce identical elevation/moisture/river/temperature")

	var first_sample: Vector4 = sampler.sample(TEST_SEED, sample_cell)
	var other_sample: Vector4 = sampler.sample(DIFFERENT_SEED, sample_cell)
	assert(first_sample != other_sample, "Different seeds produced identical macro samples")
	print("TEST 2 PASS: different seed changes the World Macro Terrain sample")

	_test_horizontal_border(sampler)
	print("TEST 3 PASS: horizontal Region border uses global x=99 and x=100")

	_test_independent_slices(generator, sampler)
	print("TEST 4 PASS: independently generated Regions equal direct global slices")

	_test_vertical_border(sampler)
	print("TEST 5 PASS: vertical Region border uses global y=99 and y=100")

	_test_negative_coordinate(sampler)
	print("TEST 6 PASS: negative World Cell samples global (-1,50) without clamping")

	var river_crossing: Vector4i = _find_river_border_crossing(sampler)
	assert(river_crossing.w != -1, "No deterministic river skeleton crossing was found in the scan")
	print(
		"TEST 7 PASS: river crosses Region border at global (%d,%d) -> (%d,%d)" % [
			river_crossing.x,
			river_crossing.y,
			river_crossing.z,
			river_crossing.w
		]
	)

	_test_region_reentry(generator)
	print("TEST 8 PASS: Region re-entry preserves terrain and river hashes")

	_test_region_thumbnail(generator)
	print("TEST 9 PASS: World Region thumbnails are deterministic and cached")

	var default_region: RegionTerrainData = generator.generate(TEST_SEED, Vector2i(3, 4))
	print("Terrain distribution for World Cell (3,4): ", _count_terrain_types(default_region))
	print("River cells for World Cell (3,4): ", _count_river_cells(default_region))
	print("Terrain tests passed: 9 cases")
	quit()

func _test_deterministic_sampler(sampler: WorldMacroTerrainSampler, global_cell: Vector2i) -> void:
	var first: Vector4 = sampler.sample(TEST_SEED, global_cell)
	var second: Vector4 = sampler.sample(TEST_SEED, global_cell)
	assert(first == second, "Same seed and global cell are not deterministic")
	assert(first.x >= 0.0 and first.x <= 1.0, "Elevation is not normalized")
	assert(first.y >= 0.0 and first.y <= 1.0, "Moisture is not normalized")
	assert(first.z >= 0.0 and first.z <= 1.0, "River strength is not normalized")
	assert(first.w >= 0.0 and first.w <= 1.0, "Temperature is not normalized")

func _test_horizontal_border(sampler: WorldMacroTerrainSampler) -> void:
	var left_global_cell: Vector2i = WorldCoordinates.world_region_to_global_region_cell(
		Vector2i(0, 0),
		Vector2i(99, 50)
	)
	var right_global_cell: Vector2i = WorldCoordinates.world_region_to_global_region_cell(
		Vector2i(1, 0),
		Vector2i(0, 50)
	)
	assert(left_global_cell == Vector2i(99, 50), "Horizontal left border coordinate failed")
	assert(right_global_cell == Vector2i(100, 50), "Horizontal right border coordinate failed")
	var left_sample: Vector4 = sampler.sample(TEST_SEED, left_global_cell)
	var right_sample: Vector4 = sampler.sample(TEST_SEED, right_global_cell)
	assert(left_sample == sampler.sample(TEST_SEED, Vector2i(99, 50)), "Left border is not from the shared field")
	assert(right_sample == sampler.sample(TEST_SEED, Vector2i(100, 50)), "Right border is not from the shared field")

func _test_independent_slices(
		generator: RegionTerrainGenerator,
		sampler: WorldMacroTerrainSampler
	) -> void:
	var region_a: RegionTerrainData = generator.generate(TEST_SEED, Vector2i(0, 0))
	var region_b: RegionTerrainData = generator.generate(TEST_SEED, Vector2i(1, 0))
	for y: int in range(WorldCoordinates.REGION_GRID_SIZE):
		for x: int in range(WorldCoordinates.REGION_GRID_SIZE):
			var region_cell: Vector2i = Vector2i(x, y)
			var sample_a: Vector4 = sampler.sample(TEST_SEED, Vector2i(x, y))
			var sample_b: Vector4 = sampler.sample(TEST_SEED, Vector2i(x + WorldCoordinates.REGION_GRID_SIZE, y))
			assert(region_a.get_terrain(region_cell) == generator.classify_sample(sample_a), "Region A terrain slice mismatch")
			assert(region_b.get_terrain(region_cell) == generator.classify_sample(sample_b), "Region B terrain slice mismatch")
			assert(absf(region_a.get_elevation(region_cell) - sample_a.x) <= 0.5 / 255.0 + 0.00001, "Region A elevation slice mismatch")
			assert(absf(region_b.get_elevation(region_cell) - sample_b.x) <= 0.5 / 255.0 + 0.00001, "Region B elevation slice mismatch")
			assert(absf(region_a.get_moisture(region_cell) - sample_a.y) <= 0.5 / 255.0 + 0.00001, "Region A moisture slice mismatch")
			assert(absf(region_b.get_moisture(region_cell) - sample_b.y) <= 0.5 / 255.0 + 0.00001, "Region B moisture slice mismatch")
			assert(absf(region_a.get_river_strength(region_cell) - sample_a.z) <= 1.0 / 255.0 + 0.00001, "Region A river slice mismatch")
			assert(absf(region_b.get_river_strength(region_cell) - sample_b.z) <= 1.0 / 255.0 + 0.00001, "Region B river slice mismatch")
			assert(region_a.has_river(region_cell) == (sample_a.z > 0.0), "Region A river slice mismatch")
			assert(region_b.has_river(region_cell) == (sample_b.z > 0.0), "Region B river slice mismatch")

func _test_vertical_border(sampler: WorldMacroTerrainSampler) -> void:
	var top_global_cell: Vector2i = WorldCoordinates.world_region_to_global_region_cell(
		Vector2i(0, 0),
		Vector2i(50, 99)
	)
	var bottom_global_cell: Vector2i = WorldCoordinates.world_region_to_global_region_cell(
		Vector2i(0, 1),
		Vector2i(50, 0)
	)
	assert(top_global_cell == Vector2i(50, 99), "Vertical top border coordinate failed")
	assert(bottom_global_cell == Vector2i(50, 100), "Vertical bottom border coordinate failed")
	assert(sampler.sample(TEST_SEED, top_global_cell) == sampler.sample(TEST_SEED, Vector2i(50, 99)), "Top border is not from the shared field")
	assert(sampler.sample(TEST_SEED, bottom_global_cell) == sampler.sample(TEST_SEED, Vector2i(50, 100)), "Bottom border is not from the shared field")

func _test_negative_coordinate(sampler: WorldMacroTerrainSampler) -> void:
	var negative_global_cell: Vector2i = WorldCoordinates.world_region_to_global_region_cell(
		Vector2i(-1, 0),
		Vector2i(99, 50)
	)
	assert(negative_global_cell == Vector2i(-1, 50), "Negative global coordinate was clamped or converted incorrectly")
	var sample: Vector4 = sampler.sample(TEST_SEED, negative_global_cell)
	assert(sample.x >= 0.0 and sample.x <= 1.0, "Negative elevation sample is invalid")
	assert(sample.y >= 0.0 and sample.y <= 1.0, "Negative moisture sample is invalid")
	assert(sample.z >= 0.0 and sample.z <= 1.0, "Negative river sample is invalid")
	assert(sample.w >= 0.0 and sample.w <= 1.0, "Negative temperature sample is invalid")

func _find_river_border_crossing(sampler: WorldMacroTerrainSampler) -> Vector4i:
	for region_boundary: int in range(-BORDER_SCAN_RADIUS, BORDER_SCAN_RADIUS + 1):
		var left_x: int = region_boundary * WorldCoordinates.REGION_GRID_SIZE - 1
		for global_y: int in range(-BORDER_SCAN_EXTENT, BORDER_SCAN_EXTENT + 1):
			if sampler.is_river(TEST_SEED, Vector2i(left_x, global_y)) and sampler.is_river(TEST_SEED, Vector2i(left_x + 1, global_y)):
				return Vector4i(left_x, global_y, left_x + 1, global_y)
		var top_y: int = region_boundary * WorldCoordinates.REGION_GRID_SIZE - 1
		for global_x: int in range(-BORDER_SCAN_EXTENT, BORDER_SCAN_EXTENT + 1):
			if sampler.is_river(TEST_SEED, Vector2i(global_x, top_y)) and sampler.is_river(TEST_SEED, Vector2i(global_x, top_y + 1)):
				return Vector4i(global_x, top_y, global_x, top_y + 1)
	return Vector4i(0, 0, 0, -1)

func _test_region_reentry(generator: RegionTerrainGenerator) -> void:
	var world_data: WorldData = WorldData.new()
	var first: RegionTerrainData = world_data.get_or_generate_region_terrain(Vector2i(3, 4), TEST_SEED)
	var second: RegionTerrainData = world_data.get_or_generate_region_terrain(Vector2i(3, 4), TEST_SEED)
	var regenerated: RegionTerrainData = generator.generate(TEST_SEED, Vector2i(3, 4))
	var region: RegionData = world_data.get_region(Vector2i(3, 4))
	assert(first == second, "Region cache did not preserve the generated object")
	assert(region.terrain_generation_version == RegionTerrainGenerator.GENERATION_VERSION, "Region generation version was not recorded")
	assert(_hash_bytes(first.terrain_array) == _hash_bytes(second.terrain_array), "Terrain hash changed on re-entry")
	assert(_hash_bytes(first.river_strength_data) == _hash_bytes(second.river_strength_data), "River hash changed on re-entry")
	assert(first.terrain_array == regenerated.terrain_array, "Re-entry data differs from deterministic regeneration")
	assert(first.river_strength_data == regenerated.river_strength_data, "Re-entry river data differs from deterministic regeneration")

func _count_terrain_types(terrain_data: RegionTerrainData) -> Array[int]:
	var counts: Array[int] = []
	counts.resize(TerrainType.COUNT)
	counts.fill(0)
	for terrain_type: int in terrain_data.terrain_array:
		counts[terrain_type] += 1
	return counts

func _test_region_thumbnail(generator: RegionTerrainGenerator) -> void:
	var world_data: WorldData = WorldData.new()
	var thumbnail_a: PackedByteArray = world_data.get_or_generate_region_thumbnail(Vector2i(3, 4), TEST_SEED)
	var thumbnail_b: PackedByteArray = world_data.get_or_generate_region_thumbnail(Vector2i(3, 4), TEST_SEED)
	var thumbnail_direct: PackedByteArray = generator.generate_thumbnail(TEST_SEED, Vector2i(3, 4))
	assert(thumbnail_a.size() == RegionTerrainGenerator.THUMBNAIL_CELL_COUNT, "Region thumbnail size is invalid")
	assert(thumbnail_a == thumbnail_b, "Region thumbnail cache is not deterministic")
	assert(thumbnail_a == thumbnail_direct, "Cached thumbnail differs from generator output")

func _hash_bytes(values: PackedByteArray) -> int:
	var result: int = 17
	for value: int in values:
		result = posmod(result * 31 + value, 2_147_483_647)
	return result

func _count_river_cells(terrain_data: RegionTerrainData) -> int:
	var count: int = 0
	for river_strength: int in terrain_data.river_strength_data:
		if river_strength > 0:
			count += 1
	return count
