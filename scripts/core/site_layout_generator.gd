class_name SiteLayoutGenerator
extends RefCounted

const SiteLayoutDataType = preload("res://scripts/data/site_layout_data.gd")

const GENERATION_VERSION: int = 2
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

static func generate(definition: SiteData) -> SiteLayoutDataType:
	if definition == null or definition.site_id.is_empty() or definition.site_seed == 0:
		return null
	var key: Vector2i = definition.global_region_cell
	var layout: SiteLayoutDataType = SiteLayoutDataType.new()
	layout.site_id = definition.site_id
	layout.generation_version = GENERATION_VERSION
	layout.site_seed = definition.site_seed
	layout.entrance_local_meters = definition.entrance_local_meters
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
	return layout

static func generate_cell_base(
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
	layout.terrain_type = int(resolved_cell.get("terrain_type", -1))
	layout.elevation = float(resolved_cell.get("elevation", 0.0))
	layout.moisture = float(resolved_cell.get("moisture", 0.0))
	layout.river_strength = float(resolved_cell.get("river_strength", 0.0))
	layout.river_crossing = bool(resolved_cell.get("river_crossing", false))
	var road_offsets: Array[Vector2i] = []
	if bool(resolved_cell.get("road", false)):
		road_offsets = _normalized_offsets(
			resolved_cell.get("road_connection_offsets", []),
			site_seed,
			global_cell,
			CELL_ROAD_FALLBACK_SALT
		)
	layout.road_connection_offsets = road_offsets
	var river_offsets: Array[Vector2i] = []
	if bool(resolved_cell.get("river", false)):
		river_offsets = _normalized_offsets(
			resolved_cell.get("river_connection_offsets", []),
			site_seed,
			global_cell,
			CELL_RIVER_FALLBACK_SALT
		)
	layout.river_connection_offsets = river_offsets
	layout.navigation_flags.resize(SiteLayoutDataType.NAVIGATION_CELL_COUNT)
	for y: int in range(SiteLayoutDataType.GRID_SIZE.y):
		for x: int in range(SiteLayoutDataType.GRID_SIZE.x):
			var local_cell: Vector2i = Vector2i(x, y)
			var point: Vector2 = layout.cell_center_meters(local_cell)
			var flags: int = 0
			if bool(resolved_cell.get("road", false)) \
				and _near_segments(point, layout.road_connection_offsets, ROAD_HALF_WIDTH_METERS):
				flags |= SiteLayoutDataType.NAV_ROAD
			if bool(resolved_cell.get("river", false)) \
				and _near_segments(point, layout.river_connection_offsets, RIVER_HALF_WIDTH_METERS):
				flags |= SiteLayoutDataType.NAV_RIVER
			if layout.river_crossing and point.length() <= CROSSING_RADIUS_METERS:
				flags |= SiteLayoutDataType.NAV_CROSSING
			layout.navigation_flags[y * SiteLayoutDataType.GRID_SIZE.x + x] = flags
	return layout

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
