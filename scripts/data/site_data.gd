class_name SiteData
extends RefCounted

const BASE_GENERATION_VERSION: int = 1
const SITE_SEED_SALT: int = 29_011

var site_id: String = ""
var source_poi_id: String = ""
var site_name: String = ""
var site_type: int = WorldPOIType.VILLAGE
var parent_world_cell: Vector2i = Vector2i(-1, -1)
var parent_region_cell: Vector2i = Vector2i(-1, -1)
var global_region_cell: Vector2i = Vector2i(-1, -1)
var base_generation_version: int = BASE_GENERATION_VERSION
var site_seed: int = 0
var entrance_local_meters: Vector2i = Vector2i.ZERO
var entrance_global_meters: Vector2i = Vector2i.ZERO
var source_terrain_type: int = TerrainType.PLAINS
var source_elevation: float = 0.0
var source_moisture: float = 0.0
var source_river_nearby: bool = false
var source_candidate_cell: Vector2i = Vector2i.ZERO
var source_priority: float = 0.0

func _init(
		p_site_id: String = "",
		p_site_name: String = "",
		p_site_type: int = WorldPOIType.VILLAGE,
		p_parent_world_cell: Vector2i = Vector2i(-1, -1),
		p_parent_region_cell: Vector2i = Vector2i(-1, -1),
		p_global_region_cell: Vector2i = Vector2i(-1, -1)
	) -> void:
	site_id = p_site_id
	source_poi_id = p_site_id
	site_name = p_site_name
	site_type = p_site_type
	parent_world_cell = p_parent_world_cell
	parent_region_cell = p_parent_region_cell
	global_region_cell = p_global_region_cell

static func from_poi(poi: WorldPOIData) -> SiteData:
	if poi == null:
		return null
	var definition: SiteData = SiteData.new(
			poi.poi_id,
			poi.site_name,
			poi.poi_type,
			poi.world_cell,
			poi.region_cell,
			poi.global_region_cell
		)
	definition.source_poi_id = poi.poi_id
	definition.site_seed = derive_seed(poi)
	definition.entrance_global_meters = WorldCoordinates.global_region_cell_to_global_meters(
		poi.global_region_cell
	) + Vector2i.ONE * floori(float(WorldCoordinates.REGION_CELL_SIZE_METERS) * 0.5)
	definition.source_terrain_type = poi.terrain_type
	definition.source_elevation = poi.elevation
	definition.source_moisture = poi.moisture
	definition.source_river_nearby = poi.river_nearby
	definition.source_candidate_cell = poi.candidate_cell
	definition.source_priority = poi.deterministic_priority
	return definition

static func derive_seed(poi: WorldPOIData) -> int:
	if poi == null:
		return 0
	return DeterministicHash.value(
		poi.generation_seed,
		poi.global_region_cell,
		SITE_SEED_SALT + BASE_GENERATION_VERSION * 101 + poi.poi_type
	)

func local_to_global_meters(local_meters: Vector2i) -> Vector2i:
	return entrance_global_meters + local_meters - entrance_local_meters

func global_to_local_meters(global_meters: Vector2i) -> Vector2i:
	return entrance_local_meters + global_meters - entrance_global_meters
