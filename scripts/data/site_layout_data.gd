class_name SiteLayoutData
extends RefCounted

enum LayoutKind {
	POI,
	CELL_BASE,
}

const GRID_SIZE: Vector2i = Vector2i(50, 50)
const CELL_SIZE_METERS: int = 2
const SIZE_METERS: Vector2i = GRID_SIZE * CELL_SIZE_METERS
const ENTRANCE_CELL: Vector2i = Vector2i(25, 25)
const INVALID_CELL: Vector2i = Vector2i(-1, -1)
const NAVIGATION_CELL_COUNT: int = GRID_SIZE.x * GRID_SIZE.y
const NAV_ROAD: int = 1
const NAV_RIVER: int = 2
const NAV_CROSSING: int = 4

var site_id: String = ""
var layout_kind: int = LayoutKind.POI
var generation_version: int = 0
var site_seed: int = 0
var global_region_cell: Vector2i = INVALID_CELL
var bounds_meters: Rect2i = Rect2i()
var entrance_local_meters: Vector2i = Vector2i.ZERO
var hub_local_meters: Vector2i = Vector2i.ZERO
var primary_path_meters: Array[Vector2i] = []
var landmark_points_meters: Array[Vector2i] = []
var terrain_type: int = -1
var elevation: float = 0.0
var moisture: float = 0.0
var river_strength: float = 0.0
var road_connection_offsets: Array[Vector2i] = []
var river_connection_offsets: Array[Vector2i] = []
var river_crossing: bool = false
var navigation_flags: PackedByteArray = PackedByteArray()
var details: Dictionary = {}

func is_valid() -> bool:
	var common_valid: bool = not site_id.is_empty() \
		and generation_version > 0 \
		and bounds_meters.size.x > 0 \
		and bounds_meters.size.y > 0
	if not common_valid:
		return false
	if layout_kind == LayoutKind.CELL_BASE:
		return has_navigation_base()
	return bounds_meters.has_point(entrance_local_meters) \
		and bounds_meters.has_point(hub_local_meters) \
		and primary_path_meters.size() >= 2

func has_navigation_base() -> bool:
	return navigation_flags.size() == NAVIGATION_CELL_COUNT \
		and is_valid_cell(Vector2i.ZERO) \
		and is_valid_cell(GRID_SIZE - Vector2i.ONE)

static func is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 \
		and cell.x < GRID_SIZE.x and cell.y < GRID_SIZE.y

func cell_center_meters(cell: Vector2i) -> Vector2:
	return Vector2(bounds_meters.position + cell * CELL_SIZE_METERS) \
		+ Vector2.ONE * float(CELL_SIZE_METERS) * 0.5

func navigation_flags_at(cell: Vector2i) -> int:
	if not has_navigation_base() or not is_valid_cell(cell):
		return 0
	return int(navigation_flags[cell.y * GRID_SIZE.x + cell.x])

func copy() -> SiteLayoutData:
	var result: SiteLayoutData = SiteLayoutData.new()
	result.site_id = site_id
	result.layout_kind = layout_kind
	result.generation_version = generation_version
	result.site_seed = site_seed
	result.global_region_cell = global_region_cell
	result.bounds_meters = bounds_meters
	result.entrance_local_meters = entrance_local_meters
	result.hub_local_meters = hub_local_meters
	result.primary_path_meters = primary_path_meters.duplicate()
	result.landmark_points_meters = landmark_points_meters.duplicate()
	result.terrain_type = terrain_type
	result.elevation = elevation
	result.moisture = moisture
	result.river_strength = river_strength
	result.road_connection_offsets = road_connection_offsets.duplicate()
	result.river_connection_offsets = river_connection_offsets.duplicate()
	result.river_crossing = river_crossing
	result.navigation_flags = navigation_flags.duplicate()
	result.details = details.duplicate(true)
	return result
