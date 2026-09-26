class_name FormationMovementProfile
extends RefCounted
## Encapsulates the traversal capability profile of a formation.
## In v3, the formation's capability is the strict intersection of all active members' capabilities
## (i.e. the most restricted member defines the formation limits).

var allowed_terrain_mask: int = TerrainData.Flag.WALKABLE
var max_step_height: int = 1
var can_use_ramp: bool = true
var footprint_cells: int = 1
var profile_hash: int = 0

func _init(p_mask: int = TerrainData.Flag.WALKABLE, p_max_height: int = 1, p_ramp: bool = true, p_footprint: int = 1) -> void:
	allowed_terrain_mask = p_mask
	max_step_height = p_max_height
	can_use_ramp = p_ramp
	footprint_cells = p_footprint
	recompute_hash()

func recompute_hash() -> void:
	# Deterministic 64-bit integer hash for profile comparison and plan invalidation
	profile_hash = (allowed_terrain_mask & 0xFFFFFFFF) | ((max_step_height & 0xFF) << 32) | ((1 if can_use_ramp else 0) << 40) | ((footprint_cells & 0xFF) << 41)

## Creates default profile for standard infantry units.
static func default_infantry() -> RefCounted:
	var script = load("res://scripts/terrain_lab/formation_movement_profile.gd") as GDScript
	return script.new(TerrainData.Flag.WALKABLE, 1, true, 1)

## Derives the formation movement profile from all active members in the army.
## All pathfinding, footprint evaluation, and local routing must use this unified profile.
static func from_members(member_ids: Array[int], army: Object) -> RefCounted:
	if member_ids.is_empty():
		return default_infantry()

	var mask: int = TerrainData.Flag.WALKABLE
	var step_height := 1
	var ramp := true
	var footprint := 1

	# If army has custom member query/profiles, intersect them here
	if army != null and army.has_method("member_movement_capabilities"):
		for mid: int in member_ids:
			var caps: Dictionary = army.member_movement_capabilities(mid)
			if not caps.is_empty():
				mask = mask & int(caps.get("mask", mask))
				step_height = mini(step_height, int(caps.get("max_step_height", step_height)))
				ramp = ramp and bool(caps.get("can_use_ramp", ramp))
				footprint = maxi(footprint, int(caps.get("footprint", footprint)))

	var script = load("res://scripts/terrain_lab/formation_movement_profile.gd") as GDScript
	return script.new(mask, step_height, ramp, footprint)

func is_compatible_with(other: RefCounted) -> bool:
	if other == null:
		return false
	return profile_hash == int(other.get("profile_hash"))

func duplicate_profile() -> RefCounted:
	var script = get_script() as Script
	var copy = script.new(allowed_terrain_mask, max_step_height, can_use_ramp, footprint_cells)
	copy.profile_hash = profile_hash
	return copy
