class_name WorldPOIGenerator
extends RefCounted

const GENERATION_VERSION: int = 2
const POI_CANDIDATE_GRID_SIZE: int = 10
const SETTLEMENT_SPACING_RADIUS: int = 1
const CANDIDATE_EXISTS_CHANCE: float = 0.24

const VILLAGE_WEIGHT: float = 1.00
const TOWN_WEIGHT: float = 0.08
const CASTLE_WEIGHT: float = 0.03
const RUINS_WEIGHT: float = 0.24
const CAVE_WEIGHT: float = 0.12

const EXISTENCE_SALT: int = 101
const TYPE_SALT: int = 103
const OFFSET_X_SALT: int = 107
const OFFSET_Y_SALT: int = 109
const PRIORITY_SALT: int = 113
const NAME_PREFIX_SALT: int = 127
const NAME_SUFFIX_SALT: int = 131
const GENERATION_SEED_SALT: int = 137

const NAME_PREFIXES: Array[String] = ["Green", "Stone", "Oak", "Iron", "Red", "North"]
const NAME_SUFFIXES: Array[String] = ["ford", "hill", "vale", "keep", "watch", "cave"]

var terrain_generator: RegionTerrainGenerator
var macro_sampler: WorldMacroTerrainSampler
var candidate_type_cache_by_seed: Dictionary = {}

func _init(p_terrain_generator: RegionTerrainGenerator = null) -> void:
	terrain_generator = p_terrain_generator if p_terrain_generator != null else RegionTerrainGenerator.new()
	macro_sampler = terrain_generator.macro_sampler

func generate_for_region(world_seed: int, world_cell: Vector2i) -> Array[WorldPOIData]:
	var global_min: Vector2i = Vector2i(
		world_cell.x * WorldCoordinates.REGION_GRID_SIZE,
		world_cell.y * WorldCoordinates.REGION_GRID_SIZE
	)
	var global_max: Vector2i = global_min + Vector2i(
		WorldCoordinates.REGION_GRID_SIZE - 1,
		WorldCoordinates.REGION_GRID_SIZE - 1
	)
	var candidate_min: Vector2i = Vector2i(
		WorldCoordinates.floor_divide(global_min.x, POI_CANDIDATE_GRID_SIZE) - SETTLEMENT_SPACING_RADIUS,
		WorldCoordinates.floor_divide(global_min.y, POI_CANDIDATE_GRID_SIZE) - SETTLEMENT_SPACING_RADIUS
	)
	var candidate_max: Vector2i = Vector2i(
		WorldCoordinates.floor_divide(global_max.x, POI_CANDIDATE_GRID_SIZE) + SETTLEMENT_SPACING_RADIUS,
		WorldCoordinates.floor_divide(global_max.y, POI_CANDIDATE_GRID_SIZE) + SETTLEMENT_SPACING_RADIUS
	)
	var result: Array[WorldPOIData] = []
	for candidate_y: int in range(candidate_min.y, candidate_max.y + 1):
		for candidate_x: int in range(candidate_min.x, candidate_max.x + 1):
			var candidate_cell: Vector2i = Vector2i(candidate_x, candidate_y)
			var poi: WorldPOIData = _generate_candidate(world_seed, candidate_cell)
			if poi == null:
				continue
			if poi.global_region_cell.x < global_min.x or poi.global_region_cell.x > global_max.x:
				continue
			if poi.global_region_cell.y < global_min.y or poi.global_region_cell.y > global_max.y:
				continue
			result.append(poi)
	return result

func clear_cache() -> void:
	candidate_type_cache_by_seed.clear()

static func candidate_cell_for_global_region_cell(global_region_cell: Vector2i) -> Vector2i:
	return Vector2i(
		WorldCoordinates.floor_divide(global_region_cell.x, POI_CANDIDATE_GRID_SIZE),
		WorldCoordinates.floor_divide(global_region_cell.y, POI_CANDIDATE_GRID_SIZE)
	)

func _generate_candidate(world_seed: int, candidate_cell: Vector2i) -> WorldPOIData:
	var poi_type: int = _candidate_type(world_seed, candidate_cell)
	if poi_type < 0:
		return null
	var global_region_cell: Vector2i = _candidate_global_cell(world_seed, candidate_cell)
	var macro_sample: Vector4 = macro_sampler.sample(world_seed, global_region_cell)
	var terrain_type: int = terrain_generator.classify_region_sample(
		world_seed,
		global_region_cell,
		macro_sample
	)
	var river_nearby: bool = _river_nearby(world_seed, global_region_cell)
	var priority: float = DeterministicHash.normalized(world_seed, candidate_cell, PRIORITY_SALT)
	if WorldPOIType.is_settlement(poi_type) \
		and not _passes_settlement_spacing(world_seed, candidate_cell, priority):
		return null
	var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(global_region_cell)
	var world_cell: Vector2i = converted["world_cell"] as Vector2i
	var region_cell: Vector2i = converted["region_cell"] as Vector2i
	var poi_id: String = "poi_%s_%d_%d" % [
		WorldPOIType.to_id_prefix(poi_type),
		global_region_cell.x,
		global_region_cell.y
	]
	var generation_seed: int = DeterministicHash.value(world_seed, candidate_cell, GENERATION_SEED_SALT)
	return WorldPOIData.new(
		poi_id,
		poi_type,
		global_region_cell,
		world_cell,
		region_cell,
		_poi_name(world_seed, candidate_cell, poi_type),
		candidate_cell,
		priority,
		terrain_type,
		macro_sample.x,
		macro_sample.y,
		river_nearby,
		generation_seed,
		_importance(poi_type)
	)

func _candidate_type(world_seed: int, candidate_cell: Vector2i) -> int:
	var seed_cache: Dictionary = candidate_type_cache_by_seed.get(world_seed, {}) as Dictionary
	if not candidate_type_cache_by_seed.has(world_seed):
		candidate_type_cache_by_seed[world_seed] = seed_cache
	if seed_cache.has(candidate_cell):
		return int(seed_cache[candidate_cell])
	var result: int = _calculate_candidate_type(world_seed, candidate_cell)
	seed_cache[candidate_cell] = result
	return result

func _calculate_candidate_type(world_seed: int, candidate_cell: Vector2i) -> int:
	if DeterministicHash.normalized(world_seed, candidate_cell, EXISTENCE_SALT) >= CANDIDATE_EXISTS_CHANCE:
		return -1
	var global_region_cell: Vector2i = _candidate_global_cell(world_seed, candidate_cell)
	var macro_sample: Vector4 = macro_sampler.sample(world_seed, global_region_cell)
	var terrain_type: int = terrain_generator.classify_region_sample(
		world_seed,
		global_region_cell,
		macro_sample
	)
	var river_nearby: bool = _river_nearby(world_seed, global_region_cell)
	var mountain_nearby: bool = _mountain_nearby(world_seed, global_region_cell)
	var village_score: float = VILLAGE_WEIGHT * _suitability(
		WorldPOIType.VILLAGE,
		terrain_type,
		macro_sample.x,
		macro_sample.y,
		river_nearby,
		mountain_nearby
	)
	var town_score: float = TOWN_WEIGHT * _suitability(
		WorldPOIType.TOWN,
		terrain_type,
		macro_sample.x,
		macro_sample.y,
		river_nearby,
		mountain_nearby
	)
	var castle_score: float = CASTLE_WEIGHT * _suitability(
		WorldPOIType.CASTLE,
		terrain_type,
		macro_sample.x,
		macro_sample.y,
		river_nearby,
		mountain_nearby
	)
	var ruins_score: float = RUINS_WEIGHT * _suitability(
		WorldPOIType.RUINS,
		terrain_type,
		macro_sample.x,
		macro_sample.y,
		river_nearby,
		mountain_nearby
	)
	var cave_score: float = CAVE_WEIGHT * _suitability(
		WorldPOIType.CAVE,
		terrain_type,
		macro_sample.x,
		macro_sample.y,
		river_nearby,
		mountain_nearby
	)
	var total_score: float = village_score + town_score + castle_score + ruins_score + cave_score
	if total_score <= 0.0:
		return -1
	var roll: float = DeterministicHash.normalized(world_seed, candidate_cell, TYPE_SALT) * total_score
	if roll < village_score:
		return WorldPOIType.VILLAGE
	roll -= village_score
	if roll < town_score:
		return WorldPOIType.TOWN
	roll -= town_score
	if roll < castle_score:
		return WorldPOIType.CASTLE
	roll -= castle_score
	if roll < ruins_score:
		return WorldPOIType.RUINS
	return WorldPOIType.CAVE

func _candidate_global_cell(world_seed: int, candidate_cell: Vector2i) -> Vector2i:
	return Vector2i(
		candidate_cell.x * POI_CANDIDATE_GRID_SIZE + DeterministicHash.int_range(
			world_seed, candidate_cell, OFFSET_X_SALT, 0, POI_CANDIDATE_GRID_SIZE - 1
		),
		candidate_cell.y * POI_CANDIDATE_GRID_SIZE + DeterministicHash.int_range(
			world_seed, candidate_cell, OFFSET_Y_SALT, 0, POI_CANDIDATE_GRID_SIZE - 1
		)
	)

func _passes_settlement_spacing(world_seed: int, candidate_cell: Vector2i, priority: float) -> bool:
	# ponytail: fixed local neighborhood keeps queries lazy; use a world index if spacing becomes global.
	for offset_y: int in range(-SETTLEMENT_SPACING_RADIUS, SETTLEMENT_SPACING_RADIUS + 1):
		for offset_x: int in range(-SETTLEMENT_SPACING_RADIUS, SETTLEMENT_SPACING_RADIUS + 1):
			if offset_x == 0 and offset_y == 0:
				continue
			var neighbor_cell: Vector2i = candidate_cell + Vector2i(offset_x, offset_y)
			var neighbor_type: int = _candidate_type(world_seed, neighbor_cell)
			if not WorldPOIType.is_settlement(neighbor_type):
				continue
			var neighbor_priority: float = DeterministicHash.normalized(world_seed, neighbor_cell, PRIORITY_SALT)
			if neighbor_priority > priority:
				return false
			if is_equal_approx(neighbor_priority, priority) and _candidate_key(neighbor_cell) < _candidate_key(candidate_cell):
				return false
	return true

func _suitability(
		poi_type: int,
		terrain_type: int,
		elevation: float,
		moisture: float,
		river_nearby: bool,
		mountain_nearby: bool
	) -> float:
	match poi_type:
		WorldPOIType.VILLAGE:
			if TerrainType.is_water_like(terrain_type) or terrain_type == TerrainType.MOUNTAIN:
				return 0.0
			var village_score: float = 0.68
			match terrain_type:
				TerrainType.PLAINS:
					village_score = 1.0
				TerrainType.SAND:
					village_score = 0.30 if river_nearby else 0.0
				TerrainType.SNOW:
					village_score = 0.24
				TerrainType.SWAMP:
					village_score = 0.20
			if village_score <= 0.0:
				return 0.0
			village_score *= 0.80 + clampf(1.0 - absf(elevation - 0.50), 0.0, 1.0) * 0.25
			if river_nearby:
				village_score += 0.20
			return village_score + moisture * 0.10
		WorldPOIType.TOWN:
			if TerrainType.is_water_like(terrain_type) \
				or terrain_type == TerrainType.MOUNTAIN \
				or terrain_type == TerrainType.SWAMP:
				return 0.0
			var town_score: float = 0.20
			match terrain_type:
				TerrainType.PLAINS:
					town_score = 1.25
				TerrainType.SAND:
					town_score = 0.12 if river_nearby else 0.0
				TerrainType.SNOW:
					town_score = 0.06
			town_score *= 0.75 + clampf(1.0 - absf(elevation - 0.48), 0.0, 1.0) * 0.30
			if river_nearby:
				town_score += 0.35
			return town_score
		WorldPOIType.CASTLE:
			if TerrainType.is_water_like(terrain_type):
				return 0.0
			var castle_score: float = 0.85 if terrain_type == TerrainType.PLAINS else 0.35
			if terrain_type == TerrainType.SNOW:
				castle_score = 0.25
			elif terrain_type == TerrainType.SWAMP:
				castle_score = 0.18
			if mountain_nearby:
				castle_score += 0.45
			castle_score += clampf(1.0 - absf(elevation - 0.62) * 3.0, 0.0, 1.0) * 0.25
			return castle_score
		WorldPOIType.RUINS:
			if TerrainType.is_water_like(terrain_type):
				return 0.0
			var ruins_score: float = 0.70 if terrain_type == TerrainType.PLAINS else 0.85
			if terrain_type == TerrainType.SWAMP:
				ruins_score = 0.95
			if mountain_nearby:
				ruins_score += 0.30
			return ruins_score
		WorldPOIType.CAVE:
			if TerrainType.is_water_like(terrain_type) \
				or (not mountain_nearby and elevation < 0.58):
				return 0.0
			var cave_score: float = 0.55
			if terrain_type == TerrainType.MOUNTAIN \
				or (terrain_type == TerrainType.SNOW and elevation >= 0.58):
				cave_score += 0.90
			if mountain_nearby:
				cave_score += 0.30
			return cave_score + clampf(elevation - 0.58, 0.0, 0.42)
		_:
			return 0.0

func _river_nearby(world_seed: int, global_region_cell: Vector2i) -> bool:
	var offsets: Array[Vector2i] = [
		Vector2i.ZERO,
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
	]
	for offset: Vector2i in offsets:
		if macro_sampler.sample(world_seed, global_region_cell + offset).z > 0.0:
			return true
	return false

func _mountain_nearby(world_seed: int, global_region_cell: Vector2i) -> bool:
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			var sample_cell: Vector2i = global_region_cell + Vector2i(offset_x, offset_y)
			var sample: Vector4 = macro_sampler.sample(world_seed, sample_cell)
			if terrain_generator.classify_region_sample(world_seed, sample_cell, sample) == TerrainType.MOUNTAIN \
				or sample.x >= RegionTerrainGenerator.MOUNTAIN_THRESHOLD:
				return true
	return false

func _poi_name(world_seed: int, candidate_cell: Vector2i, poi_type: int) -> String:
	var prefix: String = NAME_PREFIXES[DeterministicHash.int_range(
		world_seed, candidate_cell, NAME_PREFIX_SALT + poi_type, 0, NAME_PREFIXES.size() - 1
	)]
	var suffix: String = NAME_SUFFIXES[DeterministicHash.int_range(
		world_seed, candidate_cell, NAME_SUFFIX_SALT + poi_type, 0, NAME_SUFFIXES.size() - 1
	)]
	return "%s %s" % [prefix, suffix]

func _importance(poi_type: int) -> int:
	match poi_type:
		WorldPOIType.VILLAGE:
			return 1
		WorldPOIType.TOWN:
			return 2
		WorldPOIType.CASTLE:
			return 3
		WorldPOIType.RUINS, WorldPOIType.CAVE:
			return 1
		_:
			return 0

func _candidate_key(candidate_cell: Vector2i) -> int:
	return candidate_cell.x * 1_000_000 + candidate_cell.y
