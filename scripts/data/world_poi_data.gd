class_name WorldPOIData
extends RefCounted

var poi_id: String = ""
var poi_type: int = WorldPOIType.VILLAGE
var global_region_cell: Vector2i = Vector2i.ZERO
var world_cell: Vector2i = Vector2i.ZERO
var region_cell: Vector2i = Vector2i.ZERO
var site_name: String = ""
var importance: int = 0
var generation_seed: int = 0
var candidate_cell: Vector2i = Vector2i.ZERO
var deterministic_priority: float = 0.0
var terrain_type: int = TerrainType.PLAINS
var elevation: float = 0.0
var moisture: float = 0.0
var river_nearby: bool = false

func _init(
		p_poi_id: String,
		p_poi_type: int,
		p_global_region_cell: Vector2i,
		p_world_cell: Vector2i,
		p_region_cell: Vector2i,
		p_site_name: String,
		p_candidate_cell: Vector2i,
		p_deterministic_priority: float,
		p_terrain_type: int,
		p_elevation: float,
		p_moisture: float,
		p_river_nearby: bool,
		p_generation_seed: int,
		p_importance: int = 0
	) -> void:
	poi_id = p_poi_id
	poi_type = p_poi_type
	global_region_cell = p_global_region_cell
	world_cell = p_world_cell
	region_cell = p_region_cell
	site_name = p_site_name
	candidate_cell = p_candidate_cell
	deterministic_priority = p_deterministic_priority
	terrain_type = p_terrain_type
	elevation = p_elevation
	moisture = p_moisture
	river_nearby = p_river_nearby
	generation_seed = p_generation_seed
	importance = p_importance
