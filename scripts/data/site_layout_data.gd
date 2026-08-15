class_name SiteLayoutData
extends RefCounted

const SiteTransitionDataType = preload("res://scripts/data/site_transition_data.gd")

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
const HEIGHT_LEVEL_METERS: float = 1.0
const SURFACE_WATER: int = 1 << 0
const SURFACE_PLATFORM: int = 1 << 1
const SURFACE_STAIR: int = 1 << 2
const SURFACE_RAMP: int = 1 << 3
const SURFACE_BRIDGE: int = 1 << 4
const SURFACE_DOCK: int = 1 << 5
const SURFACE_WALL: int = 1 << 6
const SURFACE_CLIFF: int = 1 << 7
const EDGE_NORTH: int = 1 << 0
const EDGE_EAST: int = 1 << 1
const EDGE_SOUTH: int = 1 << 2
const EDGE_WEST: int = 1 << 3
const EXIT_NORTH: int = 1 << 0
const EXIT_EAST: int = 1 << 1
const EXIT_SOUTH: int = 1 << 2
const EXIT_WEST: int = 1 << 3
const EXIT_ALL: int = 0x0f
const EXIT_DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
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
var site_type: int = WorldPOIType.VILLAGE
var site_landform: int = Landform.NONE
var travel_exit_mask: int = EXIT_ALL
var elevation: float = 0.0
var moisture: float = 0.0
var river_strength: float = 0.0
var road_connection_offsets: Array[Vector2i] = []
var river_connection_offsets: Array[Vector2i] = []
var river_crossing: bool = false
var native_surface_cells: PackedByteArray = PackedByteArray()
var resource_placements: Array[Dictionary] = []
var facility_placements: Array[Dictionary] = []
var wall_edges: Array[Dictionary] = []
var navigation_flags: PackedByteArray = PackedByteArray()
var visual_cells: PackedByteArray = PackedByteArray()
var elevation_levels: PackedInt32Array = PackedInt32Array()
var surface_flags: PackedByteArray = PackedByteArray()
var height_edge_flags: PackedByteArray = PackedByteArray()
var transitions: Array[SiteTransitionData] = []
var details: Dictionary = {}

func is_valid() -> bool:
	var common_valid: bool = not site_id.is_empty() \
		and generation_version > 0 \
		and bounds_meters.size.x > 0 \
		and bounds_meters.size.y > 0
	if not common_valid:
		return false
	if layout_kind == LayoutKind.CELL_BASE:
		return has_navigation_base() and has_height_base()
	return bounds_meters.has_point(entrance_local_meters) \
		and bounds_meters.has_point(hub_local_meters) \
		and primary_path_meters.size() >= 2 \
		and has_navigation_base() \
		and has_height_base()

func has_navigation_base() -> bool:
	return navigation_flags.size() == NAVIGATION_CELL_COUNT \
		and is_valid_cell(Vector2i.ZERO) \
		and is_valid_cell(GRID_SIZE - Vector2i.ONE)

func has_height_base() -> bool:
	return elevation_levels.size() == NAVIGATION_CELL_COUNT \
		and surface_flags.size() == NAVIGATION_CELL_COUNT \
		and height_edge_flags.size() == NAVIGATION_CELL_COUNT

func has_native_surface_base() -> bool:
	return native_surface_cells.size() == NAVIGATION_CELL_COUNT

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

func elevation_level_at(cell: Vector2i) -> int:
	if not has_height_base() or not is_valid_cell(cell):
		return 0
	return elevation_levels[cell.y * GRID_SIZE.x + cell.x]

func surface_flags_at(cell: Vector2i) -> int:
	if not has_height_base() or not is_valid_cell(cell):
		return 0
	return int(surface_flags[cell.y * GRID_SIZE.x + cell.x])

func height_edge_flags_at(cell: Vector2i) -> int:
	if not has_height_base() or not is_valid_cell(cell):
		return 0
	return int(height_edge_flags[cell.y * GRID_SIZE.x + cell.x])

func native_surface_at(cell: Vector2i) -> int:
	if not has_native_surface_base() or not is_valid_cell(cell):
		return SiteContentTypes.NativeSurface.DIRT
	return int(native_surface_cells[cell.y * GRID_SIZE.x + cell.x])

func generated_resource(resource_id: String) -> Dictionary:
	for placement: Dictionary in resource_placements:
		if str(placement.get("id", "")) == resource_id:
			return placement.duplicate(true)
	return {}

func generated_facility(facility_id: String) -> Dictionary:
	for placement: Dictionary in facility_placements:
		if str(placement.get("id", "")) == facility_id:
			return placement.duplicate(true)
	return {}

func resolved_without(removed_ids: Array[String]) -> SiteLayoutData:
	if removed_ids.is_empty():
		return copy()
	var result: SiteLayoutData = copy()
	result.resource_placements = result.resource_placements.filter(func(item: Dictionary) -> bool:
		return not removed_ids.has(str(item.get("id", "")))
	)
	var removed_facilities: Array[Dictionary] = []
	for facility: Dictionary in result.facility_placements:
		if removed_ids.has(str(facility.get("id", ""))):
			removed_facilities.append(facility)
	result.facility_placements = result.facility_placements.filter(func(item: Dictionary) -> bool:
		return not removed_ids.has(str(item.get("id", "")))
	)
	result.wall_edges = result.wall_edges.filter(func(item: Dictionary) -> bool:
		return not removed_ids.has(str(item.get("id", "")))
	)
	for facility: Dictionary in removed_facilities:
		var facility_type: int = int(facility.get("type", -1))
		if facility_type == SiteContentTypes.Facility.BRIDGE:
			result._remove_facility_surface(facility, SURFACE_BRIDGE | SURFACE_DOCK)
			result.transitions = result.transitions.filter(func(transition: SiteTransitionData) -> bool:
				return transition != null and transition.kind != SiteTransitionData.Kind.BRIDGE
			)
		elif facility_type in [SiteContentTypes.Facility.WOOD_STAIR, SiteContentTypes.Facility.STONE_STAIR]:
			var origin: Variant = facility.get("origin", INVALID_CELL)
			var target: Variant = facility.get("target", INVALID_CELL)
			if origin is Vector2i and target is Vector2i:
				result.transitions = result.transitions.filter(func(transition: SiteTransitionData) -> bool:
					return transition == null or not transition.connects(origin as Vector2i, target as Vector2i)
				)
	result._recompile_navigation_after_delta()
	return result

func resolved_with_delta(added_features: Array, removed_ids: Array[String]) -> SiteLayoutData:
	var result: SiteLayoutData = resolved_without(removed_ids)
	for value: Variant in added_features:
		if not value is SiteFeatureState:
			continue
		var feature: SiteFeatureState = value as SiteFeatureState
		if not feature.enabled or feature.feature_type != "FACILITY" or feature.placement.is_empty():
			continue
		result._apply_added_facility(feature.feature_id, feature.placement)
	result._recompile_navigation_after_delta()
	return result

func _apply_added_facility(feature_id: String, placement_value: Dictionary) -> void:
	var placement: Dictionary = placement_value.duplicate(true)
	placement["id"] = feature_id
	var facility_type: int = int(placement.get("type", -1))
	if not SiteContentTypes.is_facility(facility_type):
		return
	if facility_type == SiteContentTypes.Facility.WOOD_WALL \
		or facility_type == SiteContentTypes.Facility.STONE_WALL:
		var wall_from: Variant = placement.get("origin", INVALID_CELL)
		var wall_to: Variant = placement.get("target", INVALID_CELL)
		if wall_from is Vector2i and wall_to is Vector2i:
			wall_edges.append({
				"id": feature_id,
				"type": facility_type,
				"from": wall_from as Vector2i,
				"to": wall_to as Vector2i,
			})
		return
	facility_placements.append(placement)
	var origin_value: Variant = placement.get("origin", INVALID_CELL)
	var size_value: Variant = placement.get("size", Vector2i.ONE)
	if not origin_value is Vector2i or not size_value is Vector2i:
		return
	var origin: Vector2i = origin_value as Vector2i
	var size: Vector2i = size_value as Vector2i
	if facility_type == SiteContentTypes.Facility.BRIDGE:
		for y: int in range(size.y):
			for x: int in range(size.x):
				var bridge_cell: Vector2i = origin + Vector2i(x, y)
				if not is_valid_cell(bridge_cell):
					continue
				var index: int = bridge_cell.y * GRID_SIZE.x + bridge_cell.x
				surface_flags[index] = int(surface_flags[index]) | SURFACE_BRIDGE
				if SiteContentTypes.is_water_surface(native_surface_at(bridge_cell)):
					navigation_flags[index] = int(navigation_flags[index]) & ~NAV_BLOCKED
		var step: Vector2i = Vector2i.RIGHT if size.x > 1 else Vector2i.DOWN
		var length: int = size.x if size.x > 1 else size.y
		for offset: int in range(length - 1):
			var from_cell: Vector2i = origin + step * offset
			var to_cell: Vector2i = from_cell + step
			transitions.append(SiteTransitionData.new(
				from_cell,
				to_cell,
				elevation_level_at(from_cell),
				elevation_level_at(to_cell),
				SiteTransitionData.Kind.BRIDGE
			))
	elif facility_type == SiteContentTypes.Facility.WOOD_STAIR \
		or facility_type == SiteContentTypes.Facility.STONE_STAIR:
		var target_value: Variant = placement.get("target", INVALID_CELL)
		if target_value is Vector2i and is_valid_cell(target_value as Vector2i):
			var target: Vector2i = target_value as Vector2i
			var origin_index: int = origin.y * GRID_SIZE.x + origin.x
			var target_index: int = target.y * GRID_SIZE.x + target.x
			surface_flags[origin_index] = int(surface_flags[origin_index]) | SURFACE_STAIR
			surface_flags[target_index] = int(surface_flags[target_index]) | SURFACE_STAIR
			transitions.append(SiteTransitionData.new(
				origin,
				target,
				elevation_level_at(origin),
				elevation_level_at(target),
				SiteTransitionData.Kind.STAIR
			))

func _remove_facility_surface(facility: Dictionary, flags_to_remove: int) -> void:
	var origin_value: Variant = facility.get("origin", INVALID_CELL)
	var size_value: Variant = facility.get("size", Vector2i.ZERO)
	if not origin_value is Vector2i or not size_value is Vector2i:
		return
	var origin: Vector2i = origin_value as Vector2i
	var size: Vector2i = size_value as Vector2i
	for y: int in range(size.y):
		for x: int in range(size.x):
			var cell: Vector2i = origin + Vector2i(x, y)
			if not is_valid_cell(cell):
				continue
			var index: int = cell.y * GRID_SIZE.x + cell.x
			surface_flags[index] = int(surface_flags[index]) & ~flags_to_remove

func _recompile_navigation_after_delta() -> void:
	for y: int in range(GRID_SIZE.y):
		for x: int in range(GRID_SIZE.x):
			var cell: Vector2i = Vector2i(x, y)
			var index: int = y * GRID_SIZE.x + x
			var flags: int = int(navigation_flags[index])
			var surface: int = surface_flags_at(cell)
			if SiteContentTypes.is_water_surface(native_surface_at(cell)) \
				and (surface & (SURFACE_BRIDGE | SURFACE_DOCK)) == 0:
				flags |= NAV_BLOCKED
			elif SiteContentTypes.is_water_surface(native_surface_at(cell)) \
				and (surface & (SURFACE_BRIDGE | SURFACE_DOCK)) != 0:
				flags &= ~NAV_BLOCKED
			navigation_flags[index] = flags

func transition_between(from_cell: Vector2i, to_cell: Vector2i) -> SiteTransitionData:
	for transition: SiteTransitionData in transitions:
		if transition != null and transition.connects(from_cell, to_cell):
			return transition
	return null

func can_traverse(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if not is_valid_cell(from_cell) or not is_valid_cell(to_cell):
		return false
	if absi(to_cell.x - from_cell.x) + absi(to_cell.y - from_cell.y) != 1:
		return false
	if not has_navigation_base() \
		or (navigation_flags_at(from_cell) & NAV_BLOCKED) != 0 \
		or (navigation_flags_at(to_cell) & NAV_BLOCKED) != 0:
		return false
	if not has_height_base():
		return true
	var destination_surface: int = surface_flags_at(to_cell)
	if SiteContentTypes.is_water_surface(native_surface_at(to_cell)) \
		and (destination_surface & (SURFACE_BRIDGE | SURFACE_DOCK)) == 0:
		return false
	var source_surface: int = surface_flags_at(from_cell)
	if SiteContentTypes.is_water_surface(native_surface_at(from_cell)) \
		and (source_surface & (SURFACE_BRIDGE | SURFACE_DOCK)) == 0:
		return false
	if _wall_blocks(from_cell, to_cell):
		return false
	if elevation_level_at(from_cell) == elevation_level_at(to_cell):
		return true
	return transition_between(from_cell, to_cell) != null

func _wall_blocks(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	for wall: Dictionary in wall_edges:
		var wall_from: Variant = wall.get("from", INVALID_CELL)
		var wall_to: Variant = wall.get("to", INVALID_CELL)
		if wall_from is Vector2i and wall_to is Vector2i \
			and ((wall_from == from_cell and wall_to == to_cell) \
			or (wall_from == to_cell and wall_to == from_cell)):
			return true
	return false

static func exit_bit(direction: Vector2i) -> int:
	if absi(direction.x) + absi(direction.y) != 1:
		return 0
	for index: int in range(EXIT_DIRECTIONS.size()):
		if EXIT_DIRECTIONS[index] == direction:
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

static func landform_for_travel_cell(p_terrain_type: int, p_road_connection_offsets: Variant) -> int:
	var road_mask: int = exit_mask_from_offsets(p_road_connection_offsets)
	if p_terrain_type == TerrainType.MOUNTAIN and (road_mask & (road_mask - 1)) != 0:
		return Landform.MOUNTAIN_PASS
	return Landform.NONE

static func exit_mask_for_travel_cell(
		passable: bool,
		landform: int,
		p_road_connection_offsets: Variant
	) -> int:
	if not passable:
		return 0
	if landform == Landform.MOUNTAIN_PASS:
		var road_mask: int = exit_mask_from_offsets(p_road_connection_offsets)
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
	result.site_type = site_type
	result.site_landform = site_landform
	result.travel_exit_mask = travel_exit_mask
	result.elevation = elevation
	result.moisture = moisture
	result.river_strength = river_strength
	result.road_connection_offsets = road_connection_offsets.duplicate()
	result.river_connection_offsets = river_connection_offsets.duplicate()
	result.river_crossing = river_crossing
	result.native_surface_cells = native_surface_cells.duplicate()
	result.resource_placements = resource_placements.duplicate(true)
	result.facility_placements = facility_placements.duplicate(true)
	result.wall_edges = wall_edges.duplicate(true)
	result.navigation_flags = navigation_flags.duplicate()
	result.visual_cells = visual_cells.duplicate()
	result.elevation_levels = elevation_levels.duplicate()
	result.surface_flags = surface_flags.duplicate()
	result.height_edge_flags = height_edge_flags.duplicate()
	result.transitions.clear()
	for transition: SiteTransitionData in transitions:
		if transition != null:
			result.transitions.append(transition.copy())
	result.details = details.duplicate(true)
	return result
