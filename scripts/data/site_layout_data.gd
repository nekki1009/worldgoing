class_name SiteLayoutData
extends RefCounted

var site_id: String = ""
var generation_version: int = 0
var site_seed: int = 0
var bounds_meters: Rect2i = Rect2i()
var entrance_local_meters: Vector2i = Vector2i.ZERO
var hub_local_meters: Vector2i = Vector2i.ZERO
var primary_path_meters: Array[Vector2i] = []
var landmark_points_meters: Array[Vector2i] = []

func is_valid() -> bool:
	return not site_id.is_empty() \
		and generation_version > 0 \
		and bounds_meters.size.x > 0 \
		and bounds_meters.size.y > 0 \
		and bounds_meters.has_point(entrance_local_meters) \
		and bounds_meters.has_point(hub_local_meters) \
		and primary_path_meters.size() >= 2
