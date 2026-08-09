class_name SiteData
extends RefCounted

var site_id: String = ""
var source_poi_id: String = ""
var site_name: String = ""
var site_type: int = WorldPOIType.VILLAGE
var parent_world_cell: Vector2i = Vector2i(-1, -1)
var parent_region_cell: Vector2i = Vector2i(-1, -1)
var global_region_cell: Vector2i = Vector2i(-1, -1)

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
	return definition
