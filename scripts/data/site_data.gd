class_name SiteData
extends RefCounted

var site_id: String = ""
var site_name: String = ""
var region_cell: Vector2i = Vector2i.ZERO
var site_type: String = ""

func _init(p_site_id: String, p_site_name: String, p_region_cell: Vector2i, p_site_type: String) -> void:
	site_id = p_site_id
	site_name = p_site_name
	region_cell = p_region_cell
	site_type = p_site_type
