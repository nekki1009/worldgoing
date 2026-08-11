class_name SiteLayoutGenerator
extends RefCounted

const SiteLayoutDataType = preload("res://scripts/data/site_layout_data.gd")

const GENERATION_VERSION: int = 5
const THUMBNAIL_GRID_SIZE: int = 8
const DETAIL_MARGIN_METERS: int = 8
const MIN_DETAIL_SEPARATION_METERS: int = 12
const PATH_BEND_LIMIT_METERS: int = 12
const HUB_X_SALT: int = 41_003
const HUB_Y_SALT: int = 41_004
const PATH_BEND_SALT: int = 41_005
const LANDMARK_SALT: int = 41_100
const CELL_BASE_SALT: int = 41_500
const CELL_ROAD_FALLBACK_SALT: int = 41_501
const CELL_RIVER_FALLBACK_SALT: int = 41_502
const ROAD_HALF_WIDTH_METERS: float = 3.0
const RIVER_HALF_WIDTH_METERS: float = 4.0
const CROSSING_RADIUS_METERS: float = 12.0
const PATH_HALF_WIDTH_METERS: float = 2.5
const PASSAGE_HALF_WIDTH_METERS: float = 10.0
const LANDMARK_RADIUS_METERS: float = 5.0
const HUB_RADIUS_METERS: float = 5.0

static func generate(definition: SiteData) -> SiteLayoutDataType:
	if definition == null or definition.site_id.is_empty() or definition.site_seed == 0:
		return null
	var key: Vector2i = definition.global_region_cell
	var layout: SiteLayoutDataType = SiteLayoutDataType.new()
	layout.site_id = definition.site_id
	layout.generation_version = GENERATION_VERSION
	layout.site_seed = definition.site_seed
	layout.global_region_cell = definition.global_region_cell
	layout.entrance_local_meters = definition.entrance_local_meters
	layout.terrain_type = definition.source_terrain_type
	layout.site_landform = definition.site_landform
	layout.travel_exit_mask = definition.travel_exit_mask
	layout.elevation = definition.source_elevation
	layout.moisture = definition.source_moisture
	layout.river_strength = 1.0 if definition.source_river_nearby else 0.0
	var half_size: Vector2i = Vector2i(
		floori(float(SiteLayoutDataType.SIZE_METERS.x) * 0.5),
		floori(float(SiteLayoutDataType.SIZE_METERS.y) * 0.5)
	)
	layout.bounds_meters = Rect2i(
		-half_size,
		SiteLayoutDataType.SIZE_METERS
	)
	var minimum: Vector2i = layout.bounds_meters.position + Vector2i.ONE * DETAIL_MARGIN_METERS
	var maximum: Vector2i = layout.bounds_meters.end - Vector2i.ONE * (DETAIL_MARGIN_METERS + 1)
	layout.hub_local_meters = Vector2i(
		DeterministicHash.int_range(definition.site_seed, key, HUB_X_SALT, minimum.x, maximum.x),
		DeterministicHash.int_range(
			definition.site_seed,
			key,
			HUB_Y_SALT,
			minimum.y,
			mini(-floori(float(SiteLayoutDataType.SIZE_METERS.y) / 3.0), maximum.y)
		)
	)
	var midpoint: Vector2i = Vector2i(
		floori(float(layout.entrance_local_meters.x + layout.hub_local_meters.x) * 0.5),
		floori(float(layout.entrance_local_meters.y + layout.hub_local_meters.y) * 0.5)
	)
	midpoint.x = clampi(
		midpoint.x + DeterministicHash.int_range(
			definition.site_seed, key, PATH_BEND_SALT,
			-PATH_BEND_LIMIT_METERS, PATH_BEND_LIMIT_METERS
		),
		minimum.x,
		maximum.x
	)
	layout.primary_path_meters.append(layout.entrance_local_meters)
	layout.primary_path_meters.append(midpoint)
	layout.primary_path_meters.append(layout.hub_local_meters)
	_generate_landmarks(layout, definition, minimum, maximum)
	_generate_navigation_flags(layout)
	_generate_visual_cells(layout)
	return layout

static func generate_cell_base(
		p_world_seed: int,
		resolved_cell: Dictionary
	) -> SiteLayoutDataType:
	var layout: SiteLayoutDataType = _build_cell_base_layout(p_world_seed, resolved_cell)
	if layout == null:
		return null
	_generate_navigation_flags(layout)
	_generate_visual_cells(layout)
	return layout

static func generate_cell_base_thumbnail(
		p_world_seed: int,
		resolved_cell: Dictionary,
		thumbnail_size: int = THUMBNAIL_GRID_SIZE
	) -> PackedByteArray:
	var layout: SiteLayoutDataType = _build_cell_base_layout(p_world_seed, resolved_cell)
	var result: PackedByteArray = PackedByteArray()
	if layout == null or thumbnail_size <= 0:
		return result
	result.resize(thumbnail_size * thumbnail_size)
	for y: int in range(thumbnail_size):
		for x: int in range(thumbnail_size):
			var local_cell: Vector2i = _thumbnail_local_cell(Vector2i(x, y), thumbnail_size)
			result[y * thumbnail_size + x] = _visual_code_for_layout_cell(layout, local_cell)
	return result

static func generate_cell_base_visual_code(
		p_world_seed: int,
		resolved_cell: Dictionary,
		local_cell: Vector2i = Vector2i(25, 25)
	) -> int:
	var layout: SiteLayoutDataType = _build_cell_base_layout(p_world_seed, resolved_cell)
	if layout == null or not SiteLayoutDataType.is_valid_cell(local_cell):
		return 0
	return _visual_code_for_layout_cell(layout, local_cell)

static func _build_cell_base_layout(
		p_world_seed: int,
		resolved_cell: Dictionary
	) -> SiteLayoutDataType:
	if resolved_cell == null or not resolved_cell.has("global_region_cell"):
		return null
	var global_cell: Vector2i = resolved_cell["global_region_cell"] as Vector2i
	var site_seed: int = DeterministicHash.value(
		p_world_seed,
		global_cell,
		CELL_BASE_SALT + GENERATION_VERSION * 101
	)
	var layout: SiteLayoutDataType = SiteLayoutDataType.new()
	layout.site_id = "site_cell_%d_%d" % [global_cell.x, global_cell.y]
	layout.layout_kind = SiteLayoutDataType.LayoutKind.CELL_BASE
	layout.generation_version = GENERATION_VERSION
	layout.site_seed = site_seed
	layout.global_region_cell = global_cell
	var half_size: Vector2i = Vector2i(
		floori(float(SiteLayoutDataType.SIZE_METERS.x) * 0.5),
		floori(float(SiteLayoutDataType.SIZE_METERS.y) * 0.5)
	)
	layout.bounds_meters = Rect2i(-half_size, SiteLayoutDataType.SIZE_METERS)
	layout.terrain_type = int(resolved_cell.get("terrain_type", TerrainType.PLAINS))
	layout.site_landform = int(resolved_cell.get(
		"site_landform",
		SiteLayoutDataType.Landform.NONE
	))
	layout.travel_exit_mask = int(resolved_cell.get(
		"travel_exit_mask",
		SiteLayoutDataType.EXIT_ALL
	))
	layout.elevation = float(resolved_cell.get("elevation", 0.0))
	layout.moisture = float(resolved_cell.get("moisture", 0.0))
	layout.river_strength = float(resolved_cell.get("river_strength", 0.0))
	layout.river_crossing = bool(resolved_cell.get("river_crossing", false))
	if bool(resolved_cell.get("road", false)):
		layout.road_connection_offsets = _normalized_offsets(
			resolved_cell.get("road_connection_offsets", []),
			site_seed,
			global_cell,
			CELL_ROAD_FALLBACK_SALT
		)
	if bool(resolved_cell.get("river", false)):
		layout.river_connection_offsets = _normalized_offsets(
			resolved_cell.get("river_connection_offsets", []),
			site_seed,
			global_cell,
			CELL_RIVER_FALLBACK_SALT
		)
	return layout

static func _thumbnail_local_cell(thumbnail_cell: Vector2i, thumbnail_size: int) -> Vector2i:
	if thumbnail_size <= 1:
		return Vector2i.ZERO
	var last_thumbnail_cell: float = float(thumbnail_size - 1)
	var last_local_cell: float = float(SiteLayoutDataType.GRID_SIZE.x - 1)
	return Vector2i(
		clampi(roundi(float(thumbnail_cell.x) * last_local_cell / last_thumbnail_cell), 0, SiteLayoutDataType.GRID_SIZE.x - 1),
		clampi(roundi(float(thumbnail_cell.y) * last_local_cell / last_thumbnail_cell), 0, SiteLayoutDataType.GRID_SIZE.y - 1)
	)

static func _generate_visual_cells(layout: SiteLayoutDataType) -> void:
	if layout == null:
		return
	layout.visual_cells.resize(SiteLayoutDataType.NAVIGATION_CELL_COUNT)
	for y: int in range(SiteLayoutDataType.GRID_SIZE.y):
		for x: int in range(SiteLayoutDataType.GRID_SIZE.x):
			var local_cell: Vector2i = Vector2i(x, y)
			layout.visual_cells[y * SiteLayoutDataType.GRID_SIZE.x + x] = _visual_code_for_layout_cell(
				layout,
				local_cell
			)

static func _generate_navigation_flags(layout: SiteLayoutDataType) -> void:
	if layout == null:
		return
	layout.navigation_flags.resize(SiteLayoutDataType.NAVIGATION_CELL_COUNT)
	for y: int in range(SiteLayoutDataType.GRID_SIZE.y):
		for x: int in range(SiteLayoutDataType.GRID_SIZE.x):
			var local_cell: Vector2i = Vector2i(x, y)
			layout.navigation_flags[y * SiteLayoutDataType.GRID_SIZE.x + x] = \
				_navigation_flags_for_layout_cell(layout, local_cell)

static func _navigation_flags_for_layout_cell(
		layout: SiteLayoutDataType,
		local_cell: Vector2i
	) -> int:
	var point: Vector2 = layout.cell_center_meters(local_cell)
	var flags: int = 0
	if not _passage_open_at(layout, point):
		flags |= SiteLayoutDataType.NAV_BLOCKED
	if not layout.road_connection_offsets.is_empty() \
		and _near_segments(point, layout.road_connection_offsets, ROAD_HALF_WIDTH_METERS):
		flags |= SiteLayoutDataType.NAV_ROAD
	if not layout.river_connection_offsets.is_empty() \
		and _near_segments(point, layout.river_connection_offsets, RIVER_HALF_WIDTH_METERS):
		flags |= SiteLayoutDataType.NAV_RIVER
	if layout.river_crossing and point.length() <= CROSSING_RADIUS_METERS:
		flags |= SiteLayoutDataType.NAV_CROSSING
	return flags

static func _visual_code_for_layout_cell(
		layout: SiteLayoutDataType,
		local_cell: Vector2i
	) -> int:
	var terrain_type: int = layout.terrain_type
	if not TerrainType.is_valid(terrain_type):
		terrain_type = TerrainType.PLAINS
	var code: int = terrain_type & SiteLayoutDataType.VISUAL_TERRAIN_MASK
	var point: Vector2 = layout.cell_center_meters(local_cell)
	if layout.layout_kind == SiteLayoutDataType.LayoutKind.CELL_BASE:
		var navigation: int = _navigation_flags_for_layout_cell(layout, local_cell)
		if navigation & SiteLayoutDataType.NAV_ROAD:
			code |= SiteLayoutDataType.VISUAL_ROAD
		if navigation & SiteLayoutDataType.NAV_RIVER:
			code |= SiteLayoutDataType.VISUAL_RIVER
		if navigation & SiteLayoutDataType.NAV_CROSSING:
			code |= SiteLayoutDataType.VISUAL_ROAD | SiteLayoutDataType.VISUAL_RIVER
		return code
	if layout.site_landform == SiteLayoutDataType.Landform.MOUNTAIN_PASS \
		and _near_segments(
			point,
			SiteLayoutDataType.exit_offsets(layout.travel_exit_mask),
			PATH_HALF_WIDTH_METERS
		):
		code |= SiteLayoutDataType.VISUAL_PATH
	if _near_polyline(point, layout.primary_path_meters, PATH_HALF_WIDTH_METERS):
		code |= SiteLayoutDataType.VISUAL_PATH
	for landmark: Vector2i in layout.landmark_points_meters:
		if point.distance_to(Vector2(landmark)) <= LANDMARK_RADIUS_METERS:
			code |= SiteLayoutDataType.VISUAL_LANDMARK
			break
	if point.distance_to(Vector2(layout.hub_local_meters)) <= HUB_RADIUS_METERS:
		code |= SiteLayoutDataType.VISUAL_HUB
	if layout.river_strength > 0.0 and _poi_river_band_contains(layout, point):
		code |= SiteLayoutDataType.VISUAL_RIVER
	return code

static func _passage_open_at(layout: SiteLayoutDataType, point: Vector2) -> bool:
	if layout.site_landform != SiteLayoutDataType.Landform.MOUNTAIN_PASS:
		return true
	var exits: Array[Vector2i] = SiteLayoutDataType.exit_offsets(layout.travel_exit_mask)
	if exits.is_empty() or _near_segments(point, exits, PASSAGE_HALF_WIDTH_METERS):
		return true
	if layout.layout_kind != SiteLayoutDataType.LayoutKind.POI:
		return false
	if _near_polyline(point, layout.primary_path_meters, PATH_HALF_WIDTH_METERS):
		return true
	if point.distance_to(Vector2(layout.hub_local_meters)) <= HUB_RADIUS_METERS:
		return true
	for landmark: Vector2i in layout.landmark_points_meters:
		if point.distance_to(Vector2(landmark)) <= LANDMARK_RADIUS_METERS:
			return true
	return false

static func _poi_river_band_contains(layout: SiteLayoutDataType, point: Vector2) -> bool:
	var axis: int = posmod(layout.site_seed, 2)
	var center: float = float(
		DeterministicHash.int_range(layout.site_seed, layout.global_region_cell, CELL_RIVER_FALLBACK_SALT, -18, 18)
	)
	return absf(point.x - center) <= RIVER_HALF_WIDTH_METERS if axis == 0 else absf(point.y - center) <= RIVER_HALF_WIDTH_METERS

static func _near_polyline(point: Vector2, points: Array[Vector2i], half_width: float) -> bool:
	if points.size() < 2:
		return false
	for index: int in range(points.size() - 1):
		if _distance_to_segment(
				point,
				Vector2(points[index]),
				Vector2(points[index + 1])
			) <= half_width:
			return true
	return false

static func _normalized_offsets(
		source: Variant,
		seed_value: int,
		global_cell: Vector2i,
		salt: int
	) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if source is Array:
		for value: Variant in source as Array:
			if value is Vector2i:
				_append_unique_offset(result, value as Vector2i)
	if not result.is_empty():
		result.sort_custom(Callable(SiteLayoutGenerator, "_offset_less"))
		return result
	if DeterministicHash.value(seed_value, global_cell, salt) % 2 == 0:
		result.append(Vector2i(-1, 0))
		result.append(Vector2i(1, 0))
	else:
		result.append(Vector2i(0, -1))
		result.append(Vector2i(0, 1))
	return result

static func _append_unique_offset(result: Array[Vector2i], delta: Vector2i) -> void:
	var offset: Vector2i = Vector2i(
		clampi(delta.x, -1, 1),
		clampi(delta.y, -1, 1)
	)
	if offset != Vector2i.ZERO and not result.has(offset):
		result.append(offset)

static func _near_segments(
		point: Vector2,
		offsets: Array[Vector2i],
		half_width: float
	) -> bool:
	for offset: Vector2i in offsets:
		if _distance_to_segment(point, Vector2.ZERO, Vector2(offset) * 50.0) <= half_width:
			return true
	return false

static func _distance_to_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var delta: Vector2 = end - start
	var length_squared: float = delta.length_squared()
	if length_squared <= 0.0:
		return point.distance_to(start)
	var factor: float = clampf((point - start).dot(delta) / length_squared, 0.0, 1.0)
	return point.distance_to(start + delta * factor)

static func _offset_less(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)

static func _generate_landmarks(
		layout: SiteLayoutDataType,
		definition: SiteData,
		minimum: Vector2i,
		maximum: Vector2i
	) -> void:
	var target_count: int = _landmark_count(definition.site_type)
	for attempt: int in range(target_count * 4):
		var point: Vector2i = Vector2i(
			DeterministicHash.int_range(
				definition.site_seed, definition.global_region_cell,
				LANDMARK_SALT + attempt * 2, minimum.x, maximum.x
			),
			DeterministicHash.int_range(
				definition.site_seed, definition.global_region_cell,
				LANDMARK_SALT + attempt * 2 + 1, minimum.y, maximum.y
			)
		)
		if _too_close(point, layout.entrance_local_meters) \
			or _too_close(point, layout.hub_local_meters) \
			or layout.landmark_points_meters.has(point):
			continue
		layout.landmark_points_meters.append(point)
		if layout.landmark_points_meters.size() == target_count:
			break
	# ponytail: vector anchors are enough until Site gameplay needs a real local grid.
	if layout.landmark_points_meters.is_empty():
		layout.landmark_points_meters.append(minimum)

static func _landmark_count(site_type: int) -> int:
	match site_type:
		WorldPOIType.TOWN:
			return 8
		WorldPOIType.CASTLE:
			return 6
		WorldPOIType.CAVE:
			return 4
		_:
			return 5

static func _too_close(first: Vector2i, second: Vector2i) -> bool:
	return absi(first.x - second.x) + absi(first.y - second.y) < MIN_DETAIL_SEPARATION_METERS
