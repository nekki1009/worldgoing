class_name RegionRuntimeState
extends RefCounted

# Session-owned mutable state; RegionData remains regenerable from seed + data.
var region_coord: Vector2i = Vector2i.ZERO
var owner_id: String = "neutral"
var discovered: bool = true
var development_level: int = 0
var discovered_site_ids: Dictionary = {}

func _init(
		p_region_coord: Vector2i = Vector2i.ZERO,
		p_owner_id: String = "neutral",
		p_discovered: bool = true,
		p_development_level: int = 0
	) -> void:
	region_coord = p_region_coord
	owner_id = p_owner_id
	discovered = p_discovered
	development_level = p_development_level
