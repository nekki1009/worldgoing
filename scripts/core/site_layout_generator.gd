class_name SiteLayoutGenerator
extends RefCounted

const SiteLayoutDataType = preload("res://scripts/data/site_layout_data.gd")

const GENERATION_VERSION: int = 1
const ENTRANCE_MARGIN_METERS: int = 32
const DETAIL_MARGIN_METERS: int = 48
const MIN_DETAIL_SEPARATION_METERS: int = 72
const WIDTH_SALT: int = 41_001
const HEIGHT_SALT: int = 41_002
const HUB_X_SALT: int = 41_003
const HUB_Y_SALT: int = 41_004
const PATH_BEND_SALT: int = 41_005
const LANDMARK_SALT: int = 41_100

static func generate(definition: SiteData) -> SiteLayoutDataType:
	if definition == null or definition.site_id.is_empty() or definition.site_seed == 0:
		return null
	var key: Vector2i = definition.global_region_cell
	var width: int = DeterministicHash.int_range(definition.site_seed, key, WIDTH_SALT, 560, 760)
	var height: int = DeterministicHash.int_range(definition.site_seed, key, HEIGHT_SALT, 440, 620)
	var layout: SiteLayoutDataType = SiteLayoutDataType.new()
	layout.site_id = definition.site_id
	layout.generation_version = GENERATION_VERSION
	layout.site_seed = definition.site_seed
	layout.entrance_local_meters = definition.entrance_local_meters
	layout.bounds_meters = Rect2i(
		Vector2i(-floori(float(width) * 0.5), -height + ENTRANCE_MARGIN_METERS),
		Vector2i(width, height)
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
			mini(-floori(float(height) / 3.0), maximum.y)
		)
	)
	var midpoint: Vector2i = Vector2i(
		floori(float(layout.entrance_local_meters.x + layout.hub_local_meters.x) * 0.5),
		floori(float(layout.entrance_local_meters.y + layout.hub_local_meters.y) * 0.5)
	)
	midpoint.x = clampi(
		midpoint.x + DeterministicHash.int_range(
			definition.site_seed, key, PATH_BEND_SALT, -80, 80
		),
		minimum.x,
		maximum.x
	)
	layout.primary_path_meters.append(layout.entrance_local_meters)
	layout.primary_path_meters.append(midpoint)
	layout.primary_path_meters.append(layout.hub_local_meters)
	_generate_landmarks(layout, definition, minimum, maximum)
	return layout

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
