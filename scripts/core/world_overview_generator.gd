class_name WorldOverviewGenerator
extends RefCounted

const OVERVIEW_SAMPLE_SPACING: int = WorldCoordinates.REGION_GRID_SIZE
const SALT_PASSAGE: int = 71_001
const SALT_RESOURCE_BASE: int = 71_100

var terrain_generator: RegionTerrainGenerator

func _init(p_terrain_generator: RegionTerrainGenerator = null) -> void:
	terrain_generator = p_terrain_generator if p_terrain_generator != null else RegionTerrainGenerator.new()

func generate(world_seed: int, grid_size: Vector2i) -> WorldOverviewData:
	var started: int = Time.get_ticks_msec()
	var result: WorldOverviewData = WorldOverviewData.new(grid_size)
	result.world_seed = world_seed
	for y: int in range(grid_size.y):
		for x: int in range(grid_size.x):
			var world_cell: Vector2i = Vector2i(x, y)
			var global_center: Vector2i = world_cell * WorldCoordinates.REGION_GRID_SIZE \
				+ Vector2i.ONE * (WorldCoordinates.REGION_GRID_SIZE / 2)
			var sample: Vector4 = terrain_generator.macro_sampler.sample(world_seed, global_center)
			var biome: int = terrain_generator.classify_sample(sample)
			var index: int = y * grid_size.x + x
			result.biome_codes[index] = biome
			result.feature_flags[index] = _feature_flags(biome, sample)
			result.passage_masks[index] = _passage_mask(world_seed, world_cell, biome)
			for resource_type: int in range(SiteContentTypes.RESOURCE_COUNT):
				result.resource_budgets[index * SiteContentTypes.RESOURCE_COUNT + resource_type] = \
					_resource_budget(world_seed, world_cell, biome, sample, resource_type)
	result.generation_milliseconds = float(Time.get_ticks_msec() - started)
	return result

func manifest_for(
		world_seed: int,
		world_cell: Vector2i,
		overview: WorldOverviewData,
		poi_ids: Array[String] = [],
		route_ids: Array[String] = []
	) -> RegionGenerationManifest:
	if overview == null or not overview.is_valid():
		return null
	var result: RegionGenerationManifest = RegionGenerationManifest.new()
	result.world_seed = world_seed
	result.world_cell = world_cell
	result.biome_code = overview.biome_at(world_cell)
	result.passage_mask = overview.passage_mask_at(world_cell)
	result.feature_flags = overview.features_at(world_cell)
	for resource_type: int in range(SiteContentTypes.RESOURCE_COUNT):
		result.resource_budgets[resource_type] = overview.resource_budget_at(world_cell, resource_type)
	result.surface_quotas = _surface_quotas(result.biome_code, result.feature_flags)
	result.edge_contracts = _edge_contracts(world_seed, world_cell, overview)
	result.poi_ids = poi_ids.duplicate()
	result.route_ids = route_ids.duplicate()
	return result

func _feature_flags(biome: int, sample: Vector4) -> int:
	var flags: int = 0
	if biome == TerrainType.WATER or biome == TerrainType.OCEAN:
		flags |= WorldOverviewData.FEATURE_COAST
	if sample.z > 0.0:
		flags |= WorldOverviewData.FEATURE_RIVER
	if biome == TerrainType.MOUNTAIN or sample.x >= RegionTerrainGenerator.MOUNTAIN_THRESHOLD:
		flags |= WorldOverviewData.FEATURE_RIDGE
	return flags

func _passage_mask(world_seed: int, world_cell: Vector2i, biome: int) -> int:
	if biome == TerrainType.OCEAN:
		return 0
	if biome != TerrainType.MOUNTAIN:
		return SiteLayoutData.EXIT_ALL
	var horizontal: bool = DeterministicHash.value(world_seed, world_cell, SALT_PASSAGE) % 2 == 0
	return SiteLayoutData.EXIT_EAST | SiteLayoutData.EXIT_WEST if horizontal \
		else SiteLayoutData.EXIT_NORTH | SiteLayoutData.EXIT_SOUTH

func _resource_budget(
		world_seed: int,
		world_cell: Vector2i,
		biome: int,
		sample: Vector4,
		resource_type: int
	) -> int:
	var jitter: float = 0.85 + DeterministicHash.normalized(
		world_seed,
		world_cell,
		SALT_RESOURCE_BASE + resource_type
	) * 0.30
	var moisture: float = sample.y
	var rock: float = clampf((sample.x - 0.45) * 2.2, 0.0, 1.0)
	var base: float = 0.0
	match resource_type:
		SiteContentTypes.RESOURCE_GRASS:
			base = 12000.0 * moisture if biome != TerrainType.OCEAN else 0.0
		SiteContentTypes.RESOURCE_FRUIT_TREE:
			base = 900.0 * moisture if biome in [TerrainType.PLAINS, TerrainType.FOREST, TerrainType.SWAMP] else 0.0
		SiteContentTypes.RESOURCE_FOREST:
			base = 8000.0 * moisture if biome in [TerrainType.FOREST, TerrainType.PLAINS, TerrainType.SWAMP] else 0.0
		SiteContentTypes.RESOURCE_STONE_ORE:
			base = 5200.0 * rock
		SiteContentTypes.RESOURCE_IRON_ORE:
			base = 1200.0 * rock
		SiteContentTypes.RESOURCE_SILVER_ORE:
			base = 220.0 * rock
		SiteContentTypes.RESOURCE_GOLD_ORE:
			base = 60.0 * rock
	return maxi(0, roundi(base * jitter))

func _surface_quotas(biome: int, feature_flags: int) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	result.resize(SiteContentTypes.NativeSurface.COUNT)
	var cell_count: int = WorldCoordinates.REGION_GRID_SIZE * WorldCoordinates.REGION_GRID_SIZE
	match biome:
		TerrainType.OCEAN:
			result[SiteContentTypes.NativeSurface.SEA_WATER] = cell_count
		TerrainType.WATER:
			result[SiteContentTypes.NativeSurface.RIVER_WATER] = cell_count * 3 / 5
			result[SiteContentTypes.NativeSurface.DIRT] = cell_count - result[SiteContentTypes.NativeSurface.RIVER_WATER]
		TerrainType.MOUNTAIN:
			result[SiteContentTypes.NativeSurface.ROCK] = cell_count * 4 / 5
			result[SiteContentTypes.NativeSurface.DIRT] = cell_count - result[SiteContentTypes.NativeSurface.ROCK]
		_:
			result[SiteContentTypes.NativeSurface.ROCK] = cell_count / 10
			result[SiteContentTypes.NativeSurface.DIRT] = cell_count - result[SiteContentTypes.NativeSurface.ROCK]
	if (feature_flags & WorldOverviewData.FEATURE_RIVER) != 0 \
		and result[SiteContentTypes.NativeSurface.SEA_WATER] == 0:
		var river_quota: int = cell_count / 20
		result[SiteContentTypes.NativeSurface.RIVER_WATER] += river_quota
		var land_surface: int = SiteContentTypes.NativeSurface.ROCK \
			if result[SiteContentTypes.NativeSurface.ROCK] >= river_quota \
			else SiteContentTypes.NativeSurface.DIRT
		result[land_surface] = maxi(0, result[land_surface] - river_quota)
	return result

func _edge_contracts(
		world_seed: int,
		world_cell: Vector2i,
		overview: WorldOverviewData
	) -> Dictionary:
	return {
		"north": _shared_edge(world_seed, world_cell + Vector2i.UP, world_cell, overview),
		"east": _shared_edge(world_seed, world_cell, world_cell + Vector2i.RIGHT, overview),
		"south": _shared_edge(world_seed, world_cell, world_cell + Vector2i.DOWN, overview),
		"west": _shared_edge(world_seed, world_cell + Vector2i.LEFT, world_cell, overview),
	}

func _shared_edge(
		world_seed: int,
		first: Vector2i,
		second: Vector2i,
		overview: WorldOverviewData
	) -> Dictionary:
	var minimum: Vector2i = Vector2i(mini(first.x, second.x), mini(first.y, second.y))
	var maximum: Vector2i = Vector2i(maxi(first.x, second.x), maxi(first.y, second.y))
	var key: Vector2i = minimum * 4096 + maximum
	var endpoint: int = DeterministicHash.int_range(
		world_seed,
		key,
		SALT_PASSAGE + 17,
		10,
		WorldCoordinates.REGION_GRID_SIZE - 11
	)
	var first_flags: int = overview.features_at(first)
	var second_flags: int = overview.features_at(second)
	return {
		"endpoint": endpoint,
		"river": (first_flags & WorldOverviewData.FEATURE_RIVER) != 0 \
			or (second_flags & WorldOverviewData.FEATURE_RIVER) != 0,
		"coast": (first_flags & WorldOverviewData.FEATURE_COAST) != 0 \
			or (second_flags & WorldOverviewData.FEATURE_COAST) != 0,
		"ridge": (first_flags & WorldOverviewData.FEATURE_RIDGE) != 0 \
			and (second_flags & WorldOverviewData.FEATURE_RIDGE) != 0,
	}

