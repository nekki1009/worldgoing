class_name RegionData
extends RefCounted

var region_id: String = ""
var world_cell: Vector2i = Vector2i.ZERO
var region_name: String = ""
var terrain_type: String = "Plains"
var terrain_data: RegionTerrainData
var seed: int = 0
var terrain_generation_version: int = 0
var terrain_thumbnail_data: PackedByteArray = PackedByteArray()
var terrain_thumbnail_seed: int = 0
var terrain_thumbnail_generation_version: int = 0

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
