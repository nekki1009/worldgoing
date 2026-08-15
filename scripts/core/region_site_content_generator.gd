class_name RegionSiteContentGenerator
extends RefCounted

const SALT_ALLOCATION_BASE: int = 72_100

func generate(
		manifest: RegionGenerationManifest,
		terrain: RegionTerrainData
	) -> RegionSiteContentData:
	if manifest == null or not manifest.is_valid() or terrain == null:
		return null
	var result: RegionSiteContentData = RegionSiteContentData.new()
	result.world_cell = manifest.world_cell
	result.world_seed = manifest.world_seed
	for y: int in range(WorldCoordinates.REGION_GRID_SIZE):
		for x: int in range(WorldCoordinates.REGION_GRID_SIZE):
			var cell: Vector2i = Vector2i(x, y)
			var index: int = y * WorldCoordinates.REGION_GRID_SIZE + x
			var terrain_type: int = terrain.get_terrain(cell)
			result.native_surface_hints[index] = _surface_hint(terrain_type)
			result.rock_ratios[index] = roundi(_rock_ratio(terrain_type, terrain.get_elevation(cell)) * 255.0)
			result.river_width_classes[index] = clampi(ceili(terrain.get_river_strength(cell) * 3.0), 0, 3)
			result.coast_masks[index] = _coast_mask(terrain, cell)
	for resource_type: int in range(SiteContentTypes.RESOURCE_COUNT):
		_allocate_resource(result, manifest, terrain, resource_type)
	return result

func _allocate_resource(
		result: RegionSiteContentData,
		manifest: RegionGenerationManifest,
		terrain: RegionTerrainData,
		resource_type: int
	) -> void:
	var budget: int = manifest.resource_budgets[resource_type]
	if budget <= 0:
		return
	var candidates: Array[Dictionary] = []
	var weight_total: int = 0
	for y: int in range(WorldCoordinates.REGION_GRID_SIZE):
		for x: int in range(WorldCoordinates.REGION_GRID_SIZE):
			var cell: Vector2i = Vector2i(x, y)
			var weight: int = _resource_weight(terrain, cell, resource_type)
			if weight <= 0:
				continue
			weight_total += weight
			candidates.append({
				"cell": cell,
				"weight": weight,
				"tie": DeterministicHash.value(
					manifest.world_seed,
					WorldCoordinates.world_region_to_global_region_cell(manifest.world_cell, cell),
					SALT_ALLOCATION_BASE + resource_type
				),
			})
	if candidates.is_empty() or weight_total <= 0:
		return
	var assigned: int = 0
	for item: Dictionary in candidates:
		var numerator: int = budget * int(item["weight"])
		var amount: int = numerator / weight_total
		item["remainder"] = numerator % weight_total
		var cell: Vector2i = item["cell"] as Vector2i
		result.resource_amounts[_resource_index(cell, resource_type)] = amount
		assigned += amount
	var remaining: int = budget - assigned
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_remainder: int = int(left["remainder"])
		var right_remainder: int = int(right["remainder"])
		return left_remainder > right_remainder \
			or (left_remainder == right_remainder and int(left["tie"]) < int(right["tie"]))
	)
	for index: int in range(remaining):
		var cell: Vector2i = candidates[index % candidates.size()]["cell"] as Vector2i
		var resource_index: int = _resource_index(cell, resource_type)
		result.resource_amounts[resource_index] += 1

func _surface_hint(terrain_type: int) -> int:
	if terrain_type == TerrainType.OCEAN:
		return SiteContentTypes.NativeSurface.SEA_WATER
	if terrain_type == TerrainType.WATER:
		return SiteContentTypes.NativeSurface.RIVER_WATER
	if terrain_type == TerrainType.MOUNTAIN:
		return SiteContentTypes.NativeSurface.ROCK
	return SiteContentTypes.NativeSurface.DIRT

func _rock_ratio(terrain_type: int, elevation: float) -> float:
	if terrain_type == TerrainType.MOUNTAIN:
		return clampf(0.65 + elevation * 0.30, 0.0, 1.0)
	if terrain_type == TerrainType.SNOW:
		return clampf(0.15 + elevation * 0.35, 0.0, 0.60)
	return clampf((elevation - 0.45) * 0.35, 0.0, 0.20)

func _coast_mask(terrain: RegionTerrainData, cell: Vector2i) -> int:
	var water: bool = TerrainType.is_water_like(terrain.get_terrain(cell))
	var result: int = 0
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for index: int in range(directions.size()):
		var neighbor: Vector2i = cell + directions[index]
		if not WorldCoordinates.is_valid_region_cell(neighbor):
			continue
		if TerrainType.is_water_like(terrain.get_terrain(neighbor)) != water:
			result |= 1 << index
	return result

func _resource_weight(terrain: RegionTerrainData, cell: Vector2i, resource_type: int) -> int:
	var terrain_type: int = terrain.get_terrain(cell)
	var moisture: float = terrain.get_moisture(cell)
	var elevation: float = terrain.get_elevation(cell)
	if TerrainType.is_water_like(terrain_type):
		return 0
	match resource_type:
		SiteContentTypes.RESOURCE_GRASS:
			return maxi(1, roundi(10.0 + moisture * 90.0))
		SiteContentTypes.RESOURCE_FRUIT_TREE:
			return maxi(0, roundi((moisture - 0.35) * 100.0))
		SiteContentTypes.RESOURCE_FOREST:
			return maxi(0, roundi((moisture - 0.25) * 120.0))
		SiteContentTypes.RESOURCE_STONE_ORE:
			return maxi(1, roundi((elevation - 0.40) * 140.0))
		SiteContentTypes.RESOURCE_IRON_ORE:
			return maxi(1, roundi((elevation - 0.50) * 110.0))
		SiteContentTypes.RESOURCE_SILVER_ORE:
			return maxi(1, roundi((elevation - 0.60) * 90.0))
		SiteContentTypes.RESOURCE_GOLD_ORE:
			return maxi(1, roundi((elevation - 0.70) * 70.0))
	return 0

func _resource_index(cell: Vector2i, resource_type: int) -> int:
	return (cell.y * WorldCoordinates.REGION_GRID_SIZE + cell.x) \
		* SiteContentTypes.RESOURCE_COUNT + resource_type
