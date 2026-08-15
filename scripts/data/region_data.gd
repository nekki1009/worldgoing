class_name RegionData
extends RefCounted

const REGION_SEED_SALT: int = 17_009
const BASE_GENERATION_VERSION: int = 4

var region_id: String = ""
var world_cell: Vector2i = Vector2i.ZERO
var region_name: String = ""
var terrain_type: String = "Plains"
var terrain_data: RegionTerrainData
var source_world_seed: int = 0
@warning_ignore("shadowed_global_identifier")
var seed: int = 0
var terrain_generation_version: int = 0
var terrain_thumbnail_data: PackedByteArray = PackedByteArray()
var terrain_thumbnail_seed: int = 0
var terrain_thumbnail_generation_version: int = 0
var generated_poi_ids: Array[String] = []
var generated_route_ids: Array[String] = []
var generation_manifest: RegionGenerationManifest
var site_content_data: RegionSiteContentData

func _init(
		p_region_id: String,
		p_world_cell: Vector2i,
		p_region_name: String,
		p_terrain_type: String
	) -> void:
	region_id = p_region_id
	world_cell = p_world_cell
	region_name = p_region_name
	terrain_type = p_terrain_type

static func derive_seed(world_seed: int, p_world_cell: Vector2i, generation_version: int) -> int:
	return DeterministicHash.value(world_seed, p_world_cell, REGION_SEED_SALT + generation_version)
