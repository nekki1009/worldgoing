class_name SiteLayoutData
extends RefCounted

enum LayoutKind {
	POI,
	CELL_BASE,
}

enum Landform {
	NONE,
	MOUNTAIN_PASS,
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
const NAV_BLOCKED: int = 8
const EXIT_NORTH: int = 1 << 0
const EXIT_NORTH_EAST: int = 1 << 1
const EXIT_EAST: int = 1 << 2
const EXIT_SOUTH_EAST: int = 1 << 3
const EXIT_SOUTH: int = 1 << 4
const EXIT_SOUTH_WEST: int = 1 << 5
const EXIT_WEST: int = 1 << 6
const EXIT_NORTH_WEST: int = 1 << 7
const EXIT_ALL: int = 0xff
const EXIT_DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i(1, -1),
	Vector2i.RIGHT,
	Vector2i(1, 1),
	Vector2i.DOWN,
	Vector2i(-1, 1),
	Vector2i.LEFT,
	Vector2i(-1, -1),
]
const VISUAL_TERRAIN_MASK: int = 0x07
const VISUAL_ROAD: int = 0x08
const VISUAL_RIVER: int = 0x10
const VISUAL_PATH: int = 0x20
const VISUAL_LANDMARK: int = 0x40
const VISUAL_HUB: int = 0x80

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
var site_landform: int = Landform.NONE
var travel_exit_mask: int = EXIT_ALL
var elevation: float = 0.0
var moisture: float = 0.0
var river_strength: float = 0.0
var road_connection_offsets: Array[Vector2i] = []
var river_connection_offsets: Array[Vector2i] = []
var river_crossing: bool = false
var navigation_flags: PackedByteArray = PackedByteArray()
var visual_cells: PackedByteArray = PackedByteArray()
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

func has_visual_base() -> bool:
	return visual_cells.size() == NAVIGATION_CELL_COUNT

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

static func exit_bit(direction: Vector2i) -> int:
	var normalized: Vector2i = Vector2i(clampi(direction.x, -1, 1), clampi(direction.y, -1, 1))
	for index: int in range(EXIT_DIRECTIONS.size()):
		if EXIT_DIRECTIONS[index] == normalized:
			return 1 << index
	return 0

static func exit_mask_from_offsets(offsets: Variant) -> int:
	var result: int = 0
	if offsets is Array:
		for value: Variant in offsets as Array:
			if value is Vector2i:
				result |= exit_bit(value as Vector2i)
	return result

static func exit_offsets(exit_mask: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for index: int in range(EXIT_DIRECTIONS.size()):
		if (exit_mask & (1 << index)) != 0:
			result.append(EXIT_DIRECTIONS[index])
	return result

static func landform_for_travel_cell(terrain_type: int, road_connection_offsets: Variant) -> int:
	var road_mask: int = exit_mask_from_offsets(road_connection_offsets)
	if terrain_type == TerrainType.MOUNTAIN and (road_mask & (road_mask - 1)) != 0:
		return Landform.MOUNTAIN_PASS
	return Landform.NONE

static func exit_mask_for_travel_cell(
		passable: bool,
		landform: int,
		road_connection_offsets: Variant
	) -> int:
	if not passable:
		return 0
	if landform == Landform.MOUNTAIN_PASS:
		var road_mask: int = exit_mask_from_offsets(road_connection_offsets)
		if road_mask != 0:
			return road_mask
	return EXIT_ALL

static func landform_name(landform: int) -> String:
	return "Mountain Pass" if landform == Landform.MOUNTAIN_PASS else "None"

func visual_code_at(cell: Vector2i) -> int:
	if not has_visual_base() or not is_valid_cell(cell):
		return 0
	return int(visual_cells[cell.y * GRID_SIZE.x + cell.x])

static func visual_color(code: int) -> Color:
	if (code & VISUAL_HUB) != 0:
		return Color("f3cf68")
	if (code & VISUAL_LANDMARK) != 0:
		return Color("d68b63")
	if visual_has_crossing(code):
		return Color("f1e6a8")
	if (code & VISUAL_ROAD) != 0:
		return Color("d1a35d")
	if (code & VISUAL_PATH) != 0:
		return Color("caa66b")
	if (code & VISUAL_RIVER) != 0:
		return Color("49a9cf")
	return TerrainType.to_color(code & VISUAL_TERRAIN_MASK).darkened(0.08)

static func visual_has_crossing(code: int) -> bool:
	var crossing_mask: int = VISUAL_ROAD | VISUAL_RIVER
	return (code & crossing_mask) == crossing_mask

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
	result.site_landform = site_landform
	result.travel_exit_mask = travel_exit_mask
	result.elevation = elevation
	result.moisture = moisture
	result.river_strength = river_strength
	result.road_connection_offsets = road_connection_offsets.duplicate()
	result.river_connection_offsets = river_connection_offsets.duplicate()
	result.river_crossing = river_crossing
	result.navigation_flags = navigation_flags.duplicate()
	result.visual_cells = visual_cells.duplicate()
	result.details = details.duplicate(true)
	return result
