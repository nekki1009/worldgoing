class_name RegionRuntimeState
extends RefCounted

# Session-owned mutable state; RegionData remains regenerable from seed + base data.
const RegionDeltaType = preload("res://scripts/runtime/region_delta.gd")

var region_coord: Vector2i = Vector2i.ZERO
var delta: RegionDelta
var discovered: bool = true
var discovered_site_ids: Dictionary = {}

var owner_id: String:
	get:
		return delta.owner_id if delta != null else "neutral"
	set(value):
		if delta != null:
			delta.set_owner(value)

var development_level: int:
	get:
		return delta.development_level if delta != null else 0
	set(value):
		if delta != null:
			delta.set_development_level(value)

func _init(
		p_region_coord: Vector2i = Vector2i.ZERO,
		p_owner_id: String = "neutral",
		p_discovered: bool = true,
		p_development_level: int = 0,
		p_base_generation_version: int = RegionData.BASE_GENERATION_VERSION
	) -> void:
	region_coord = p_region_coord
	delta = RegionDeltaType.new(region_coord, p_base_generation_version)
	owner_id = p_owner_id
	discovered = p_discovered
	development_level = p_development_level

func get_delta() -> RegionDelta:
	return delta
