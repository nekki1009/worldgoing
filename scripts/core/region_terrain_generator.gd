class_name RegionTerrainGenerator
extends RefCounted

const SiteLayoutGeneratorType = preload("res://scripts/core/site_layout_generator.gd")
const SiteLayoutDataType = preload("res://scripts/data/site_layout_data.gd")

const GENERATION_VERSION: int = RegionData.BASE_GENERATION_VERSION
const MOUNTAIN_THRESHOLD: float = 0.63
const SNOW_TEMPERATURE_THRESHOLD: float = 0.25
const SNOW_ELEVATION_THRESHOLD: float = 0.82
const SWAMP_MAX_ELEVATION: float = 0.54
const SWAMP_MOISTURE_THRESHOLD: float = 0.68
const SAND_TEMPERATURE_THRESHOLD: float = 0.52
const SAND_MOISTURE_THRESHOLD: float = 0.42
const FOREST_MOISTURE_THRESHOLD: float = 0.55
const REGION_PATCH_SIZE: int = 8
const REGION_PATCH_ELEVATION_SALT: int = 61_001
const REGION_PATCH_MOISTURE_SALT: int = 61_003
const REGION_PATCH_TEMPERATURE_SALT: int = 61_007
const THUMBNAIL_GRID_SIZE: int = 8
const THUMBNAIL_CELL_COUNT: int = THUMBNAIL_GRID_SIZE * THUMBNAIL_GRID_SIZE
const THUMBNAIL_TERRAIN_MASK: int = SiteLayoutDataType.VISUAL_TERRAIN_MASK
const THUMBNAIL_RIVER_BIT: int = SiteLayoutDataType.VISUAL_RIVER

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
			var macro_sample: Vector4 = macro_sampler.sample(world_seed, global_region_cell)
			terrain_data.set_elevation(region_cell, macro_sample.x)
			terrain_data.set_moisture(region_cell, macro_sample.y)
			terrain_data.set_river_strength(region_cell, macro_sample.z)
			terrain_data.set_terrain(
				region_cell,
				classify_region_sample(world_seed, global_region_cell, macro_sample)
			)
	terrain_data.freeze()
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
			var macro_sample: Vector4 = macro_sampler.sample(world_seed, global_region_cell)
			var terrain_type: int = classify_region_sample(
				world_seed,
				global_region_cell,
				macro_sample
			)
			var visual_code: int = SiteLayoutGeneratorType.generate_cell_base_visual_code(
				world_seed,
				{
					"global_region_cell": global_region_cell,
					"terrain_type": terrain_type,
					"elevation": macro_sample.x,
					"moisture": macro_sample.y,
					"river_strength": macro_sample.z,
					"river": macro_sample.z > 0.0,
					"road": false,
					"river_crossing": false,
				}
			)
			var packed_cell: int = visual_code & SiteLayoutDataType.VISUAL_TERRAIN_MASK
			if (visual_code & SiteLayoutDataType.VISUAL_RIVER) != 0:
				packed_cell |= THUMBNAIL_RIVER_BIT
			thumbnail[_thumbnail_index(thumbnail_cell)] = packed_cell
	return thumbnail

static func thumbnail_terrain(packed_cell: int) -> int:
	return packed_cell & THUMBNAIL_TERRAIN_MASK

static func thumbnail_has_river(packed_cell: int) -> bool:
	return (packed_cell & THUMBNAIL_RIVER_BIT) != 0

func classify_sample(macro_sample: Vector4) -> int:
	if macro_sample.x < WorldMacroTerrainSampler.DEEP_WATER_LEVEL:
		return TerrainType.OCEAN
	if macro_sample.x < WorldMacroTerrainSampler.SEA_LEVEL:
		return TerrainType.WATER
	if macro_sample.w <= SNOW_TEMPERATURE_THRESHOLD \
		or macro_sample.x >= SNOW_ELEVATION_THRESHOLD:
		return TerrainType.SNOW
	if macro_sample.x > MOUNTAIN_THRESHOLD:
		return TerrainType.MOUNTAIN
	if macro_sample.x <= SWAMP_MAX_ELEVATION \
		and macro_sample.y >= SWAMP_MOISTURE_THRESHOLD:
		return TerrainType.SWAMP
	if macro_sample.w >= SAND_TEMPERATURE_THRESHOLD \
		and macro_sample.y <= SAND_MOISTURE_THRESHOLD:
		return TerrainType.SAND
	if macro_sample.y > FOREST_MOISTURE_THRESHOLD:
		return TerrainType.FOREST
	return TerrainType.PLAINS

func classify_region_sample(
		world_seed: int,
		global_region_cell: Vector2i,
		macro_sample: Vector4
	) -> int:
	var base_terrain: int = classify_sample(macro_sample)
	if TerrainType.is_water_like(base_terrain):
		return base_terrain
	# The macro sampler deliberately keeps World biomes broad. Region cells get
	# a second deterministic patch field so a 100x100 Region contains readable
	# local forest/sand/swamp/highland bands without allocating Site layouts.
	var local_elevation: float = clampf(
		macro_sample.x + (_patch_field(
			world_seed,
			global_region_cell,
			REGION_PATCH_ELEVATION_SALT
		) - 0.5) * 0.34,
		0.0,
		1.0
	)
	var local_moisture: float = clampf(
		macro_sample.y + (_patch_field(
			world_seed,
			global_region_cell,
			REGION_PATCH_MOISTURE_SALT
		) - 0.5) * 0.48,
		0.0,
		1.0
	)
	var local_temperature: float = clampf(
		macro_sample.w + (_patch_field(
			world_seed,
			global_region_cell,
			REGION_PATCH_TEMPERATURE_SALT
		) - 0.5) * 0.28,
		0.0,
		1.0
	)
	var local_terrain: int = classify_sample(Vector4(
		local_elevation,
		local_moisture,
		macro_sample.z,
		local_temperature
	))
	# A land patch may become a mountain/forest/sand/swamp/snow patch, but
	# inland river/ocean classification remains owned by the macro water field.
	return base_terrain if TerrainType.is_water_like(local_terrain) else local_terrain

func _patch_field(world_seed: int, global_region_cell: Vector2i, salt: int) -> float:
	var patch_x: int = WorldCoordinates.floor_divide(global_region_cell.x, REGION_PATCH_SIZE)
	var patch_y: int = WorldCoordinates.floor_divide(global_region_cell.y, REGION_PATCH_SIZE)
	var local_x: float = float(posmod(global_region_cell.x, REGION_PATCH_SIZE)) / float(REGION_PATCH_SIZE)
	var local_y: float = float(posmod(global_region_cell.y, REGION_PATCH_SIZE)) / float(REGION_PATCH_SIZE)
	var p00: float = DeterministicHash.normalized(world_seed, Vector2i(patch_x, patch_y), salt)
	var p10: float = DeterministicHash.normalized(world_seed, Vector2i(patch_x + 1, patch_y), salt)
	var p01: float = DeterministicHash.normalized(world_seed, Vector2i(patch_x, patch_y + 1), salt)
	var p11: float = DeterministicHash.normalized(world_seed, Vector2i(patch_x + 1, patch_y + 1), salt)
	return lerpf(lerpf(p00, p10, local_x), lerpf(p01, p11, local_x), local_y)

func _thumbnail_region_cell(thumbnail_cell: Vector2i) -> Vector2i:
	var last_region_cell: float = float(WorldCoordinates.REGION_GRID_SIZE - 1)
	var last_thumbnail_cell: float = float(THUMBNAIL_GRID_SIZE - 1)
	return Vector2i(
		clampi(roundi(float(thumbnail_cell.x) * last_region_cell / last_thumbnail_cell), 0, WorldCoordinates.REGION_GRID_SIZE - 1),
		clampi(roundi(float(thumbnail_cell.y) * last_region_cell / last_thumbnail_cell), 0, WorldCoordinates.REGION_GRID_SIZE - 1)
	)

func _thumbnail_index(thumbnail_cell: Vector2i) -> int:
	return thumbnail_cell.y * THUMBNAIL_GRID_SIZE + thumbnail_cell.x
