class_name WorldOverviewData
extends RefCounted

const GENERATION_VERSION: int = 3
const FEATURE_COAST: int = 1 << 0
const FEATURE_RIVER: int = 1 << 1
const FEATURE_RIDGE: int = 1 << 2

var grid_size: Vector2i = Vector2i.ZERO
var world_seed: int = 0
var generation_version: int = GENERATION_VERSION
var biome_codes: PackedByteArray = PackedByteArray()
var passage_masks: PackedByteArray = PackedByteArray()
var feature_flags: PackedByteArray = PackedByteArray()
var resource_budgets: PackedInt32Array = PackedInt32Array()
var generation_milliseconds: float = 0.0

func _init(p_grid_size: Vector2i = Vector2i(256, 256)) -> void:
	grid_size = p_grid_size
	var cell_count: int = grid_size.x * grid_size.y
	biome_codes.resize(cell_count)
	passage_masks.resize(cell_count)
	feature_flags.resize(cell_count)
	resource_budgets.resize(cell_count * SiteContentTypes.RESOURCE_COUNT)

func is_valid() -> bool:
	return world_seed != 0 \
		and generation_version == GENERATION_VERSION \
		and grid_size.x > 0 and grid_size.y > 0 \
		and biome_codes.size() == grid_size.x * grid_size.y \
		and passage_masks.size() == biome_codes.size() \
		and feature_flags.size() == biome_codes.size() \
		and resource_budgets.size() == biome_codes.size() * SiteContentTypes.RESOURCE_COUNT

func biome_at(world_cell: Vector2i) -> int:
	return int(biome_codes[_index(world_cell)]) if _valid_cell(world_cell) else TerrainType.PLAINS

func passage_mask_at(world_cell: Vector2i) -> int:
	return int(passage_masks[_index(world_cell)]) if _valid_cell(world_cell) else 0

func features_at(world_cell: Vector2i) -> int:
	return int(feature_flags[_index(world_cell)]) if _valid_cell(world_cell) else 0

func resource_budget_at(world_cell: Vector2i, resource_type: int) -> int:
	if not _valid_cell(world_cell) or not SiteContentTypes.is_resource(resource_type):
		return 0
	return resource_budgets[_index(world_cell) * SiteContentTypes.RESOURCE_COUNT + resource_type]

func payload_bytes() -> int:
	return biome_codes.size() + passage_masks.size() + feature_flags.size() \
		+ resource_budgets.size() * 4

func signature() -> int:
	var result: int = 17
	for index: int in range(biome_codes.size()):
		result = posmod(result * 31 + biome_codes[index], DeterministicHash.MODULUS)
		result = posmod(result * 31 + passage_masks[index], DeterministicHash.MODULUS)
		result = posmod(result * 31 + feature_flags[index], DeterministicHash.MODULUS)
		for resource_type: int in range(SiteContentTypes.RESOURCE_COUNT):
			result = posmod(
				result * 31 + resource_budgets[index * SiteContentTypes.RESOURCE_COUNT + resource_type],
				DeterministicHash.MODULUS
			)
	return result

func _valid_cell(world_cell: Vector2i) -> bool:
	return world_cell.x >= 0 and world_cell.y >= 0 \
		and world_cell.x < grid_size.x and world_cell.y < grid_size.y

func _index(world_cell: Vector2i) -> int:
	return world_cell.y * grid_size.x + world_cell.x
