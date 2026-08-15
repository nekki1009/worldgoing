extends SceneTree

const TEST_SEED: int = 123456789
const OVERVIEW_SIZE: Vector2i = Vector2i(1024, 1024)
const CAPTURE_DIR: String = "res://.visual_captures"
const CAPTURE_PATH: String = CAPTURE_DIR + "/terrain_overview.png"
const RIVER_COLOR: Color = Color("49a9cf")
const MIN_MAJOR_RIVERS_TO_OCEAN: int = 3
const MAX_MAJOR_RIVERS_TO_OCEAN: int = 24
const MIN_MAJOR_RIVER_LAND_PIXELS: int = 12

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	assert(TerrainType.COUNT == 8, "Terrain type contract is not eight main terrains")
	var generator: RegionTerrainGenerator = RegionTerrainGenerator.new()
	var sampler: WorldMacroTerrainSampler = generator.macro_sampler
	var total_pixels: int = OVERVIEW_SIZE.x * OVERVIEW_SIZE.y
	var terrain_cells: PackedByteArray = PackedByteArray()
	var major_river_cells: PackedByteArray = PackedByteArray()
	var terrain_counts: PackedInt64Array = PackedInt64Array()
	terrain_cells.resize(total_pixels)
	major_river_cells.resize(total_pixels)
	terrain_counts.resize(TerrainType.COUNT)
	terrain_counts.fill(0)
	var image: Image = Image.create(
		OVERVIEW_SIZE.x,
		OVERVIEW_SIZE.y,
		false,
		Image.FORMAT_RGBA8
	)
	var global_size: Vector2i = WorldData.WORLD_CELLS * WorldCoordinates.REGION_GRID_SIZE
	for y: int in range(OVERVIEW_SIZE.y):
		var global_y: int = roundi(
			float(y) * float(global_size.y - 1) / float(OVERVIEW_SIZE.y - 1)
		)
		for x: int in range(OVERVIEW_SIZE.x):
			var global_x: int = roundi(
				float(x) * float(global_size.x - 1) / float(OVERVIEW_SIZE.x - 1)
			)
			var global_cell: Vector2i = Vector2i(global_x, global_y)
			var sample: Vector4 = sampler.sample(TEST_SEED, global_cell)
			var terrain_type: int = generator.classify_sample(sample)
			var index: int = y * OVERVIEW_SIZE.x + x
			terrain_cells[index] = terrain_type
			terrain_counts[terrain_type] += 1
			var major_strength: float = sampler.sample_major_river_strength(
				TEST_SEED,
				global_cell,
				sample.x
			)
			major_river_cells[index] = 1 if major_strength > 0.0 else 0
			image.set_pixel(
				x,
				y,
				RIVER_COLOR if sample.z > 0.0 else TerrainType.to_color(terrain_type)
			)
	var absolute_capture_dir: String = ProjectSettings.globalize_path(CAPTURE_DIR)
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(absolute_capture_dir)
	assert(mkdir_error == OK or mkdir_error == ERR_ALREADY_EXISTS, "Could not create visual capture directory")
	var save_error: Error = image.save_png(CAPTURE_PATH)
	assert(save_error == OK, "Could not save terrain overview")
	var validation_errors: Array[String] = _validate_proportions(terrain_counts, total_pixels)
	var major_rivers_to_ocean: int = _count_major_rivers_to_ocean(
		terrain_cells,
		major_river_cells
	)
	print("MAJOR_RIVERS_TO_OCEAN: %d" % major_rivers_to_ocean)
	if major_rivers_to_ocean < MIN_MAJOR_RIVERS_TO_OCEAN:
		validation_errors.append("Fewer than three major river systems reach the ocean")
	if major_rivers_to_ocean > MAX_MAJOR_RIVERS_TO_OCEAN:
		validation_errors.append("Major river systems are too dense")
	print("TERRAIN_OVERVIEW_CAPTURE: %s" % ProjectSettings.globalize_path(CAPTURE_PATH))
	if not validation_errors.is_empty():
		for message: String in validation_errors:
			push_error(message)
		quit(1)
		return
	print("World terrain overview passed: eight terrain ratios and major rivers to ocean")
	quit()

func _validate_proportions(counts: PackedInt64Array, total: int) -> Array[String]:
	var errors: Array[String] = []
	for terrain_type: int in range(TerrainType.COUNT):
		var ratio: float = float(counts[terrain_type]) / float(total)
		var expected: Vector2 = _expected_ratio_range(terrain_type)
		print("TERRAIN_RATIO %s: %.2f%%" % [
			TerrainType.to_display_name(terrain_type),
			ratio * 100.0,
		])
		if ratio < expected.x or ratio > expected.y:
			errors.append("%s ratio %.2f%% is outside %.2f%%..%.2f%%" % [
				TerrainType.to_display_name(terrain_type),
				ratio * 100.0,
				expected.x * 100.0,
				expected.y * 100.0,
			])
	return errors

func _expected_ratio_range(terrain_type: int) -> Vector2:
	match terrain_type:
		TerrainType.PLAINS:
			return Vector2(0.18, 0.32)
		TerrainType.FOREST:
			return Vector2(0.08, 0.20)
		TerrainType.MOUNTAIN:
			return Vector2(0.05, 0.14)
		TerrainType.WATER:
			return Vector2(0.06, 0.14)
		TerrainType.SAND:
			return Vector2(0.02, 0.08)
		TerrainType.SNOW:
			return Vector2(0.05, 0.15)
		TerrainType.SWAMP:
			return Vector2(0.01, 0.06)
		TerrainType.OCEAN:
			return Vector2(0.24, 0.38)
		_:
			return Vector2.ZERO

func _count_major_rivers_to_ocean(
		terrain_cells: PackedByteArray,
		major_river_cells: PackedByteArray
	) -> int:
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(major_river_cells.size())
	visited.fill(0)
	var result: int = 0
	for start_index: int in range(major_river_cells.size()):
		if major_river_cells[start_index] == 0 or visited[start_index] != 0:
			continue
		var queue: Array[int] = [start_index]
		var head: int = 0
		var land_pixels: int = 0
		var touches_ocean: bool = false
		visited[start_index] = 1
		while head < queue.size():
			var index: int = queue[head]
			head += 1
			var point: Vector2i = Vector2i(
				index % OVERVIEW_SIZE.x,
				floori(float(index) / float(OVERVIEW_SIZE.x))
			)
			var terrain_type: int = terrain_cells[index]
			if not TerrainType.is_water_like(terrain_type):
				land_pixels += 1
			for offset: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var neighbor: Vector2i = point + offset
				if neighbor.x < 0 or neighbor.y < 0 \
					or neighbor.x >= OVERVIEW_SIZE.x or neighbor.y >= OVERVIEW_SIZE.y:
					continue
				var neighbor_index: int = neighbor.y * OVERVIEW_SIZE.x + neighbor.x
				if terrain_cells[neighbor_index] == TerrainType.OCEAN:
					touches_ocean = true
				if major_river_cells[neighbor_index] == 0 or visited[neighbor_index] != 0:
					continue
				visited[neighbor_index] = 1
				queue.append(neighbor_index)
		if touches_ocean and land_pixels >= MIN_MAJOR_RIVER_LAND_PIXELS:
			result += 1
	return result
