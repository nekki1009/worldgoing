class_name RegionTerrainGenerator
extends RefCounted

const GENERATION_VERSION: int = 2
const MOUNTAIN_THRESHOLD: float = 0.64
const FOREST_MOISTURE_THRESHOLD: float = 0.60
const THUMBNAIL_GRID_SIZE: int = 8
const THUMBNAIL_CELL_COUNT: int = THUMBNAIL_GRID_SIZE * THUMBNAIL_GRID_SIZE
const THUMBNAIL_TERRAIN_MASK: int = 0x0F
const THUMBNAIL_RIVER_BIT: int = 0x10

var macro_sampler: WorldMacroTerrainSampler = WorldMacroTerrainSampler.new()

func generate(world_seed: int, world_cell: Vector2i) -> RegionTerrainData:
	var terrain_data: RegionTerrainData = RegionTerrainData.new()
	for y: int in range(WorldCoordinates.REGION_GRID_SIZE):
		for x: int in range(WorldCoordinates.REGION_GRID_SIZE):
			var region_cell: Vector2i = Vector2i(x, y)
			var global_region_cell: Vector2i = WorldCoordinates.world_region_to_global_region_cell(
				world_cell,
				region_cell
			)
			var macro_sample: Vector3 = macro_sampler.sample(world_seed, global_region_cell)
			terrain_data.set_elevation(region_cell, macro_sample.x)
			terrain_data.set_moisture(region_cell, macro_sample.y)
			terrain_data.set_river_strength(region_cell, macro_sample.z)
			terrain_data.set_terrain(region_cell, classify_sample(macro_sample))
	return terrain_data

func generate_thumbnail(world_seed: int, world_cell: Vector2i) -> PackedByteArray:
	var thumbnail: PackedByteArray = PackedByteArray()
	thumbnail.resize(THUMBNAIL_CELL_COUNT)
	for y: int in range(THUMBNAIL_GRID_SIZE):
		for x: int in range(THUMBNAIL_GRID_SIZE):
			var thumbnail_cell: Vector2i = Vector2i(x, y)
			var region_cell: Vector2i = _thumbnail_region_cell(thumbnail_cell)
			var global_region_cell: Vector2i = WorldCoordinates.world_region_to_global_region_cell(
				world_cell,
				region_cell
			)
			var macro_sample: Vector3 = macro_sampler.sample(world_seed, global_region_cell)
			var packed_cell: int = classify_sample(macro_sample)
			if macro_sample.z > 0.0:
				packed_cell |= THUMBNAIL_RIVER_BIT
			thumbnail[_thumbnail_index(thumbnail_cell)] = packed_cell
	return thumbnail

static func thumbnail_terrain(packed_cell: int) -> int:
	return packed_cell & THUMBNAIL_TERRAIN_MASK

static func thumbnail_has_river(packed_cell: int) -> bool:
	return (packed_cell & THUMBNAIL_RIVER_BIT) != 0

func classify_sample(macro_sample: Vector3) -> int:
	if macro_sample.x < WorldMacroTerrainSampler.SEA_LEVEL:
		return TerrainType.WATER
	if macro_sample.x > MOUNTAIN_THRESHOLD:
		return TerrainType.MOUNTAIN
	if macro_sample.y > FOREST_MOISTURE_THRESHOLD:
		return TerrainType.FOREST
	return TerrainType.PLAINS

func _thumbnail_region_cell(thumbnail_cell: Vector2i) -> Vector2i:
	var last_region_cell: float = float(WorldCoordinates.REGION_GRID_SIZE - 1)
	var last_thumbnail_cell: float = float(THUMBNAIL_GRID_SIZE - 1)
	return Vector2i(
		clampi(roundi(float(thumbnail_cell.x) * last_region_cell / last_thumbnail_cell), 0, WorldCoordinates.REGION_GRID_SIZE - 1),
		clampi(roundi(float(thumbnail_cell.y) * last_region_cell / last_thumbnail_cell), 0, WorldCoordinates.REGION_GRID_SIZE - 1)
	)

func _thumbnail_index(thumbnail_cell: Vector2i) -> int:
	return thumbnail_cell.y * THUMBNAIL_GRID_SIZE + thumbnail_cell.x
