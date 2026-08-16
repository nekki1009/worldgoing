class_name RegionSiteContentData
extends RefCounted

const GENERATION_VERSION: int = 3
const CELL_COUNT: int = WorldCoordinates.REGION_GRID_SIZE * WorldCoordinates.REGION_GRID_SIZE

var world_cell: Vector2i = Vector2i(-1, -1)
var world_seed: int = 0
var generation_version: int = GENERATION_VERSION
var native_surface_hints: PackedByteArray = PackedByteArray()
var rock_ratios: PackedByteArray = PackedByteArray()
var river_width_classes: PackedByteArray = PackedByteArray()
var coast_masks: PackedByteArray = PackedByteArray()
var resource_amounts: PackedInt32Array = PackedInt32Array()

func _init() -> void:
	native_surface_hints.resize(CELL_COUNT)
	rock_ratios.resize(CELL_COUNT)
	river_width_classes.resize(CELL_COUNT)
	coast_masks.resize(CELL_COUNT)
	resource_amounts.resize(CELL_COUNT * SiteContentTypes.RESOURCE_COUNT)

func is_valid() -> bool:
	return world_seed != 0 \
		and native_surface_hints.size() == CELL_COUNT \
		and resource_amounts.size() == CELL_COUNT * SiteContentTypes.RESOURCE_COUNT

func profile_at(region_cell: Vector2i) -> Dictionary:
	if not WorldCoordinates.is_valid_region_cell(region_cell):
		return {}
	var index: int = _index(region_cell)
	var amounts: PackedInt32Array = PackedInt32Array()
	amounts.resize(SiteContentTypes.RESOURCE_COUNT)
	for resource_type: int in range(SiteContentTypes.RESOURCE_COUNT):
		amounts[resource_type] = resource_amounts[index * SiteContentTypes.RESOURCE_COUNT + resource_type]
	return {
		"native_surface_hint": int(native_surface_hints[index]),
		"rock_ratio": float(rock_ratios[index]) / 255.0,
		"river_width_class": int(river_width_classes[index]),
		"coast_mask": int(coast_masks[index]),
		"resource_amounts": amounts,
	}

func resource_total(resource_type: int) -> int:
	if not SiteContentTypes.is_resource(resource_type):
		return 0
	var total: int = 0
	for index: int in range(CELL_COUNT):
		total += resource_amounts[index * SiteContentTypes.RESOURCE_COUNT + resource_type]
	return total

func payload_bytes() -> int:
	return native_surface_hints.size() + rock_ratios.size() \
		+ river_width_classes.size() + coast_masks.size() + resource_amounts.size() * 4

func _index(region_cell: Vector2i) -> int:
	return region_cell.y * WorldCoordinates.REGION_GRID_SIZE + region_cell.x
