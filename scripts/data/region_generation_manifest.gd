class_name RegionGenerationManifest
extends RefCounted

const GENERATION_VERSION: int = 1

var world_cell: Vector2i = Vector2i(-1, -1)
var world_seed: int = 0
var generation_version: int = GENERATION_VERSION
var biome_code: int = TerrainType.PLAINS
var passage_mask: int = 0
var feature_flags: int = 0
var resource_budgets: PackedInt32Array = PackedInt32Array()
var surface_quotas: PackedInt32Array = PackedInt32Array()
var edge_contracts: Dictionary = {}
var poi_ids: Array[String] = []
var route_ids: Array[String] = []

func _init() -> void:
	resource_budgets.resize(SiteContentTypes.RESOURCE_COUNT)
	surface_quotas.resize(SiteContentTypes.NativeSurface.COUNT)

func is_valid() -> bool:
	return world_seed != 0 \
		and resource_budgets.size() == SiteContentTypes.RESOURCE_COUNT \
		and surface_quotas.size() == SiteContentTypes.NativeSurface.COUNT \
		and edge_contracts.size() == 4

func copy() -> RegionGenerationManifest:
	var result: RegionGenerationManifest = RegionGenerationManifest.new()
	result.world_cell = world_cell
	result.world_seed = world_seed
	result.generation_version = generation_version
	result.biome_code = biome_code
	result.passage_mask = passage_mask
	result.feature_flags = feature_flags
	result.resource_budgets = resource_budgets.duplicate()
	result.surface_quotas = surface_quotas.duplicate()
	result.edge_contracts = edge_contracts.duplicate(true)
	result.poi_ids = poi_ids.duplicate()
	result.route_ids = route_ids.duplicate()
	return result

