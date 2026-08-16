class_name SiteLayoutGenerator
extends RefCounted

const SiteLayoutDataType = preload("res://scripts/data/site_layout_data.gd")
const SiteTransitionDataType = preload("res://scripts/data/site_transition_data.gd")

const GENERATION_VERSION: int = 8
const THUMBNAIL_GRID_SIZE: int = 8
const DETAIL_MARGIN_METERS: int = 8
const MIN_DETAIL_SEPARATION_METERS: int = 12
const PATH_BEND_LIMIT_METERS: int = 12
const HUB_X_SALT: int = 41_003
const HUB_Y_SALT: int = 41_004
const PATH_BEND_SALT: int = 41_005
const LANDMARK_SALT: int = 41_100
const CELL_BASE_SALT: int = 41_500
const SITE_SCENE_VARIANT_SALT: int = 41_517
const SITE_VISUAL_VARIANT_SALT: int = 41_518
const CELL_ROAD_FALLBACK_SALT: int = 41_501
const CELL_RIVER_FALLBACK_SALT: int = 41_502
const ROAD_HALF_WIDTH_METERS: float = 3.0
const RIVER_HALF_WIDTH_METERS: float = 4.0
const CROSSING_RADIUS_METERS: float = 12.0
const PATH_HALF_WIDTH_METERS: float = 2.5
const PASSAGE_HALF_WIDTH_METERS: float = 6.0
const LANDMARK_RADIUS_METERS: float = 5.0
const HUB_RADIUS_METERS: float = 5.0
const HEIGHT_WALL_LEVEL: int = 4

static func generate(definition: SiteData) -> SiteLayoutDataType:
	if definition == null or definition.site_id.is_empty() or definition.site_seed == 0:
		return null
	var key: Vector2i = definition.global_region_cell
	var layout: SiteLayoutDataType = SiteLayoutDataType.new()
	layout.site_id = definition.site_id
	layout.layout_kind = definition.layout_kind
	layout.generation_version = GENERATION_VERSION
	layout.site_seed = definition.site_seed
	layout.global_region_cell = definition.global_region_cell
	layout.entrance_local_meters = definition.entrance_local_meters
	layout.terrain_type = definition.source_terrain_type
	layout.site_type = definition.site_type
	layout.site_landform = definition.site_landform
	layout.travel_exit_mask = definition.travel_exit_mask
	layout.elevation = definition.source_elevation
	layout.moisture = definition.source_moisture
	layout.river_strength = definition.source_river_strength \
		if definition.source_river_strength > 0.0 \
		else (1.0 if definition.source_river_nearby else 0.0)
	layout.details["native_surface_hint"] = definition.native_surface_hint
	layout.details["rock_ratio"] = definition.rock_ratio
	layout.details["river_width_class"] = definition.river_width_class
	layout.details["coast_mask"] = definition.coast_mask
	layout.details["resource_amounts"] = definition.resource_amounts.duplicate()
	var half_size: Vector2i = Vector2i(
		floori(float(SiteLayoutDataType.SIZE_METERS.x) * 0.5),
		floori(float(SiteLayoutDataType.SIZE_METERS.y) * 0.5)
	)
	layout.bounds_meters = Rect2i(
		-half_size,
		SiteLayoutDataType.SIZE_METERS
	)
	if layout.layout_kind == SiteLayoutDataType.LayoutKind.CELL_BASE:
		# Region strategic cells carry no source POI id.  Only those cells use
		# the natural Site archetype; authored CELL_BASE fixtures can still
		# request a specific scene for QA without changing their semantics.
		if definition.source_poi_id.is_empty():
			layout.details["site_visual_archetype"] = _site_visual_archetype(
				definition.site_seed,
				key
			)
			layout.details["site_visual_variant"] = _site_visual_variant(
				definition.site_seed,
				key
			)
		if definition.source_road:
			layout.road_connection_offsets = _normalized_offsets(
				definition.source_road_connection_offsets,
				definition.site_seed,
				key,
				CELL_ROAD_FALLBACK_SALT
			)
		if definition.source_river_nearby:
			layout.river_connection_offsets = _normalized_offsets(
				definition.source_river_connection_offsets,
				definition.site_seed,
				key,
				CELL_RIVER_FALLBACK_SALT
			)
		layout.river_crossing = definition.source_river_crossing
		_generate_height_and_surfaces(layout)
		_generate_navigation_flags(layout)
		_generate_visual_cells(layout)
		return layout
	# POI Sites can sit on the same Region travel cell as the 3x3 composite.
	# Preserve the explicit reciprocal river/road edges on those authored
	# layouts too; otherwise the POI branch would silently drop the direction
	# that Region and CELL_BASE Sites already use.
	if definition.source_road:
		layout.road_connection_offsets = _contract_offsets(
			definition.source_road_connection_offsets
		)
	if definition.source_river_nearby:
		layout.river_connection_offsets = _contract_offsets(
			definition.source_river_connection_offsets
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
	_append_orthogonal_path(layout.primary_path_meters, layout.entrance_local_meters, midpoint)
	_append_orthogonal_path(layout.primary_path_meters, midpoint, layout.hub_local_meters)
	_generate_landmarks(layout, definition, minimum, maximum)
	_generate_height_and_surfaces(layout)
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
	var result: PackedByteArray = PackedByteArray()
	if resolved_cell == null or not resolved_cell.has("global_region_cell") or thumbnail_size <= 0:
		return result
	# RegionMap only needs presentation codes. Sample the same connection
	# geometry directly instead of allocating a complete 50x50 Site per cell.
	var global_cell: Vector2i = resolved_cell["global_region_cell"] as Vector2i
	var terrain_type: int = int(resolved_cell.get("terrain_type", TerrainType.PLAINS))
	if not TerrainType.is_valid(terrain_type):
		terrain_type = TerrainType.PLAINS
	var site_seed: int = DeterministicHash.value(
		p_world_seed,
		global_cell,
		CELL_BASE_SALT + GENERATION_VERSION * 101
	)
	var has_road: bool = bool(resolved_cell.get("road", false))
	var has_river: bool = bool(resolved_cell.get("river", false))
	var has_crossing: bool = bool(resolved_cell.get("river_crossing", false))
	var road_offsets: Array[Vector2i] = _normalized_offsets(
		resolved_cell.get("road_connection_offsets", []) if has_road else [],
		site_seed,
		global_cell,
		CELL_ROAD_FALLBACK_SALT
	)
	var river_offsets: Array[Vector2i] = _normalized_offsets(
		resolved_cell.get("river_connection_offsets", []) if has_river else [],
		site_seed,
		global_cell,
		CELL_RIVER_FALLBACK_SALT
	)
	result.resize(thumbnail_size * thumbnail_size)
	for y: int in range(thumbnail_size):
		for x: int in range(thumbnail_size):
			var local_cell: Vector2i = _thumbnail_local_cell(Vector2i(x, y), thumbnail_size)
			var point: Vector2 = Vector2(
				-float(SiteLayoutDataType.SIZE_METERS.x) * 0.5 \
					+ float(local_cell.x * SiteLayoutDataType.CELL_SIZE_METERS) \
					+ float(SiteLayoutDataType.CELL_SIZE_METERS) * 0.5,
				-float(SiteLayoutDataType.SIZE_METERS.y) * 0.5 \
					+ float(local_cell.y * SiteLayoutDataType.CELL_SIZE_METERS) \
					+ float(SiteLayoutDataType.CELL_SIZE_METERS) * 0.5
			)
			var code: int = terrain_type & SiteLayoutDataType.VISUAL_TERRAIN_MASK
			if has_road and _near_segments(point, road_offsets, ROAD_HALF_WIDTH_METERS):
				code |= SiteLayoutDataType.VISUAL_ROAD
			if has_river and _near_segments(point, river_offsets, RIVER_HALF_WIDTH_METERS):
				code |= SiteLayoutDataType.VISUAL_RIVER
			if has_crossing and point.length() <= CROSSING_RADIUS_METERS:
				code |= SiteLayoutDataType.VISUAL_ROAD | SiteLayoutDataType.VISUAL_RIVER
			result[y * thumbnail_size + x] = code
	return result

static func generate_cell_base_visual_code(
		p_world_seed: int,
		resolved_cell: Dictionary,
		local_cell: Vector2i = Vector2i(25, 25)
	) -> int:
	if resolved_cell == null or not resolved_cell.has("global_region_cell"):
		return 0
	# World thumbnails only ask for a center-cell terrain/river code. Avoid
	# allocating and rasterizing a complete 50x50 Site for that hot path; the
	# full layout remains authoritative when roads or crossings are requested.
	var terrain_type: int = int(resolved_cell.get("terrain_type", TerrainType.PLAINS))
	if not TerrainType.is_valid(terrain_type):
		terrain_type = TerrainType.PLAINS
	var code: int = terrain_type & SiteLayoutDataType.VISUAL_TERRAIN_MASK
	var has_road: bool = bool(resolved_cell.get("road", false))
	var has_river: bool = bool(resolved_cell.get("river", false))
	var has_crossing: bool = bool(resolved_cell.get("river_crossing", false))
	if not has_road and not has_crossing:
		if not has_river:
			return code
		if not SiteLayoutDataType.is_valid_cell(local_cell):
			return 0
		var global_cell: Vector2i = resolved_cell["global_region_cell"] as Vector2i
		var site_seed: int = DeterministicHash.value(
			p_world_seed,
			global_cell,
			CELL_BASE_SALT + GENERATION_VERSION * 101
		)
		var river_offsets: Array[Vector2i] = _normalized_offsets(
			resolved_cell.get("river_connection_offsets", []),
			site_seed,
			global_cell,
			CELL_RIVER_FALLBACK_SALT
		)
		var point: Vector2 = Vector2(
			-float(SiteLayoutDataType.SIZE_METERS.x) * 0.5 \
				+ float(local_cell.x * SiteLayoutDataType.CELL_SIZE_METERS) \
				+ float(SiteLayoutDataType.CELL_SIZE_METERS) * 0.5,
			-float(SiteLayoutDataType.SIZE_METERS.y) * 0.5 \
				+ float(local_cell.y * SiteLayoutDataType.CELL_SIZE_METERS) \
				+ float(SiteLayoutDataType.CELL_SIZE_METERS) * 0.5
		)
		if _near_segments(point, river_offsets, RIVER_HALF_WIDTH_METERS):
			code |= SiteLayoutDataType.VISUAL_RIVER
		return code
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
	layout.site_type = int(resolved_cell.get("site_type", WorldPOIType.VILLAGE))
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
	layout.details["native_surface_hint"] = int(resolved_cell.get(
		"native_surface_hint",
		_surface_hint_for_terrain(layout.terrain_type)
	))
	layout.details["rock_ratio"] = float(resolved_cell.get(
		"rock_ratio",
		0.82 if layout.terrain_type == TerrainType.MOUNTAIN else 0.08
	))
	layout.details["river_width_class"] = int(resolved_cell.get("river_width_class", 0))
	layout.details["coast_mask"] = int(resolved_cell.get("coast_mask", 0))
	# Terrain is only the native surface.  Keep a deterministic Site-level
	# visual archetype so identical terrain types can still produce distinct
	# natural/resource compositions instead of one repeated painting.
	if str(resolved_cell.get("source_poi_id", "")).is_empty():
		layout.details["site_visual_archetype"] = _site_visual_archetype(
			site_seed,
			global_cell
		)
		layout.details["site_visual_variant"] = _site_visual_variant(
			site_seed,
			global_cell
		)
	var resource_amounts: Variant = resolved_cell.get("resource_amounts", PackedInt32Array())
	if resource_amounts is PackedInt32Array:
		layout.details["resource_amounts"] = (resource_amounts as PackedInt32Array).duplicate()
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
	_generate_height_and_surfaces(layout)
	return layout

static func _site_visual_archetype(seed_value: int, global_cell: Vector2i) -> String:
	var scene_variant: int = posmod(DeterministicHash.value(
		seed_value,
		global_cell,
		SITE_SCENE_VARIANT_SALT + GENERATION_VERSION
	), 3)
	return "natural" if scene_variant == 1 else "curated"

static func _site_visual_variant(seed_value: int, global_cell: Vector2i) -> int:
	return posmod(DeterministicHash.value(
		seed_value,
		global_cell,
		SITE_VISUAL_VARIANT_SALT + GENERATION_VERSION
	), 3)

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
	var surface: int = layout.surface_flags_at(local_cell)
	if not _passage_open_at(layout, point):
		flags |= SiteLayoutDataType.NAV_BLOCKED
	if (surface & SiteLayoutDataType.SURFACE_WALL) != 0 \
		or (SiteContentTypes.is_water_surface(layout.native_surface_at(local_cell)) \
		and (surface & (SiteLayoutDataType.SURFACE_BRIDGE | SiteLayoutDataType.SURFACE_DOCK)) == 0):
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

static func _generate_height_and_surfaces(layout: SiteLayoutDataType) -> void:
	if layout == null:
		return
	layout.elevation_levels.resize(SiteLayoutDataType.NAVIGATION_CELL_COUNT)
	layout.elevation_levels.fill(0)
	layout.surface_flags.resize(SiteLayoutDataType.NAVIGATION_CELL_COUNT)
	layout.surface_flags.fill(0)
	layout.height_edge_flags.resize(SiteLayoutDataType.NAVIGATION_CELL_COUNT)
	layout.height_edge_flags.fill(0)
	layout.native_surface_cells.resize(SiteLayoutDataType.NAVIGATION_CELL_COUNT)
	layout.native_surface_cells.fill(int(layout.details.get(
		"native_surface_hint",
		_surface_hint_for_terrain(layout.terrain_type)
	)))
	layout.resource_placements.clear()
	layout.facility_placements.clear()
	layout.wall_edges.clear()
	layout.transitions.clear()
	layout.details["scene_template"] = "TERRAIN"
	for y: int in range(SiteLayoutDataType.GRID_SIZE.y):
		for x: int in range(SiteLayoutDataType.GRID_SIZE.x):
			var cell: Vector2i = Vector2i(x, y)
			var point: Vector2 = layout.cell_center_meters(cell)
			if _is_water_cell(layout, point):
				_set_native_surface(
					layout,
					cell,
					SiteContentTypes.NativeSurface.SEA_WATER \
						if layout.terrain_type == TerrainType.OCEAN \
						else SiteContentTypes.NativeSurface.RIVER_WATER
				)
				_set_cell_surface(layout, cell, -1, SiteLayoutDataType.SURFACE_WATER)
			elif _rock_surface_at(layout, cell):
				_set_native_surface(layout, cell, SiteContentTypes.NativeSurface.ROCK)
	if layout.site_landform == SiteLayoutDataType.Landform.MOUNTAIN_PASS:
		for y: int in range(SiteLayoutDataType.GRID_SIZE.y):
			for x: int in range(SiteLayoutDataType.GRID_SIZE.x):
				var cell: Vector2i = Vector2i(x, y)
				if _passage_open_at(layout, layout.cell_center_meters(cell)):
					# A pass floor is an explicit local surface instead of the raw
					# mountain texture. This keeps the traversable corridor readable
					# against the raised cliff bands in the actual Site view.
					_set_cell_surface(layout, cell, 0, SiteLayoutDataType.SURFACE_PLATFORM)
					_set_native_surface(layout, cell, SiteContentTypes.NativeSurface.DIRT)
				else:
					_set_cell_surface(layout, cell, 2, SiteLayoutDataType.SURFACE_CLIFF)
					_set_native_surface(layout, cell, SiteContentTypes.NativeSurface.ROCK)
		_apply_mountain_pass_transitions(layout)
		if layout.layout_kind == SiteLayoutDataType.LayoutKind.POI:
			layout.details["scene_template"] = "MOUNTAIN_PASS"
	elif layout.terrain_type == TerrainType.MOUNTAIN:
		_apply_mountain_terraces(layout)
	if layout.layout_kind == SiteLayoutDataType.LayoutKind.POI:
		_apply_poi_height_template(layout)
	if layout.river_crossing:
		_apply_bridge_transition(layout)
	_generate_facilities(layout)
	_generate_resources(layout)
	_ensure_entrance_surface(layout)
	_derive_height_edges(layout)

static func _is_water_cell(layout: SiteLayoutDataType, point: Vector2) -> bool:
	if layout.terrain_type == TerrainType.WATER or layout.terrain_type == TerrainType.OCEAN:
		return true
	if not layout.river_connection_offsets.is_empty():
		return _near_segments(point, layout.river_connection_offsets, RIVER_HALF_WIDTH_METERS)
	# river_strength is a macro/Region confidence value, not permission to paint
	# water.  The reciprocal cardinal edge contract is the only source of a
	# generated river surface for both CELL_BASE and POI Sites.
	return false

static func _surface_hint_for_terrain(terrain_type: int) -> int:
	if terrain_type == TerrainType.OCEAN:
		return SiteContentTypes.NativeSurface.SEA_WATER
	if terrain_type == TerrainType.WATER:
		return SiteContentTypes.NativeSurface.RIVER_WATER
	if terrain_type == TerrainType.MOUNTAIN:
		return SiteContentTypes.NativeSurface.ROCK
	return SiteContentTypes.NativeSurface.DIRT

static func _rock_surface_at(layout: SiteLayoutDataType, cell: Vector2i) -> bool:
	var ratio: float = clampf(float(layout.details.get("rock_ratio", 0.0)), 0.0, 1.0)
	if ratio <= 0.0:
		return false
	if ratio >= 1.0:
		return true
	# Interpolate a deterministic low-frequency field so native rock forms
	# continuous outcrops instead of one-tile salt-and-pepper noise.
	var spacing: int = 7
	var coarse: Vector2i = Vector2i(floori(float(cell.x) / spacing), floori(float(cell.y) / spacing))
	var local: Vector2 = Vector2(
		float(posmod(cell.x, spacing)) / float(spacing),
		float(posmod(cell.y, spacing)) / float(spacing)
	)
	var top_left: float = DeterministicHash.normalized(layout.site_seed, coarse, 43_100)
	var top_right: float = DeterministicHash.normalized(layout.site_seed, coarse + Vector2i.RIGHT, 43_100)
	var bottom_left: float = DeterministicHash.normalized(layout.site_seed, coarse + Vector2i.DOWN, 43_100)
	var bottom_right: float = DeterministicHash.normalized(layout.site_seed, coarse + Vector2i.ONE, 43_100)
	var top: float = lerpf(top_left, top_right, smoothstep(0.0, 1.0, local.x))
	var bottom: float = lerpf(bottom_left, bottom_right, smoothstep(0.0, 1.0, local.x))
	var field: float = lerpf(top, bottom, smoothstep(0.0, 1.0, local.y))
	return field < ratio

static func _set_native_surface(
		layout: SiteLayoutDataType,
		cell: Vector2i,
		native_surface: int
	) -> void:
	if layout == null or not SiteLayoutDataType.is_valid_cell(cell):
		return
	layout.native_surface_cells[cell.y * SiteLayoutDataType.GRID_SIZE.x + cell.x] = native_surface

static func _apply_mountain_terraces(layout: SiteLayoutDataType) -> void:
	# A normal Mountain Site gets one continuous raised plateau.  The old
	# two-band strip pattern put two stairs on a mostly flat-looking horizontal
	# seam and left the final level-2 drop without a matching transition.  Build
	# the high ground first, then derive the stair endpoints from its actual
	# boundary so a stair can never float in level 0 terrain.
	var center: Vector2 = Vector2(
		float(SiteLayoutDataType.GRID_SIZE.x - 1) * 0.5,
		float(SiteLayoutDataType.GRID_SIZE.y - 1) * 0.5
	)
	var radius: Vector2 = Vector2(17.0, 12.0)
	var plateau_cells: Array[Vector2i] = []
	for y: int in range(SiteLayoutDataType.GRID_SIZE.y):
		for x: int in range(SiteLayoutDataType.GRID_SIZE.x):
			var normalized: Vector2 = Vector2(
				(float(x) - center.x) / radius.x,
				(float(y) - center.y) / radius.y
			)
			if normalized.length_squared() > 1.0:
				continue
			var cell := Vector2i(x, y)
			plateau_cells.append(cell)
			_set_cell_surface(layout, cell, 1, SiteLayoutDataType.SURFACE_PLATFORM)

	# Use the centre line to enter and leave the plateau.  Both transitions are
	# found from the generated level field rather than from a free-floating seed
	# coordinate, so they remain attached to a visible cliff edge.
	var stair_x: int = floori(center.x)
	var first_plateau_y: int = -1
	var last_plateau_y: int = -1
	for cell: Vector2i in plateau_cells:
		if cell.x != stair_x:
			continue
		if first_plateau_y < 0 or cell.y < first_plateau_y:
			first_plateau_y = cell.y
		if cell.y > last_plateau_y:
			last_plateau_y = cell.y
	if first_plateau_y > 0:
		_add_stair(
			layout,
			Vector2i(stair_x, first_plateau_y - 1),
			Vector2i(stair_x, first_plateau_y)
		)
	if last_plateau_y >= 0 and last_plateau_y < SiteLayoutDataType.GRID_SIZE.y - 1:
		_add_stair(
			layout,
			Vector2i(stair_x, last_plateau_y),
			Vector2i(stair_x, last_plateau_y + 1)
		)
	layout.details["mountain_plateau_cells"] = plateau_cells.duplicate()
	layout.details["scene_template"] = "MOUNTAIN_TERRACE"

static func _apply_poi_height_template(layout: SiteLayoutDataType) -> void:
	var center: Vector2i = _cell_from_meters(layout, layout.hub_local_meters)
	match layout.site_type:
		WorldPOIType.CASTLE:
			_apply_castle_courtyard(layout, center)
		WorldPOIType.RUINS:
			_apply_ruins_terrace(layout, center)
		WorldPOIType.CAVE:
			_apply_cave_entrance(layout, center)
		_:
			if not layout.river_connection_offsets.is_empty():
				layout.details["scene_template"] = "RIVER_DOCK"

static func _apply_castle_courtyard(layout: SiteLayoutDataType, center: Vector2i) -> void:
	var radius_x: int = 5
	var radius_y: int = 4
	for y: int in range(center.y - radius_y, center.y + radius_y + 1):
		for x: int in range(center.x - radius_x, center.x + radius_x + 1):
			var cell: Vector2i = Vector2i(x, y)
			if not SiteLayoutDataType.is_valid_cell(cell):
				continue
			var wall: bool = abs(x - center.x) == radius_x or abs(y - center.y) == radius_y
			_set_cell_surface(
				layout,
				cell,
				HEIGHT_WALL_LEVEL if wall else 2,
				SiteLayoutDataType.SURFACE_PLATFORM \
				| (SiteLayoutDataType.SURFACE_WALL if wall else 0)
			)
	var entrance: Vector2i = _cell_from_meters(layout, layout.entrance_local_meters)
	var direction: Vector2i = _cardinal_direction(center, entrance)
	var edge: Vector2i = center + Vector2i(direction.x * radius_x, direction.y * radius_y)
	var middle: Vector2i = edge + direction
	var lower: Vector2i = middle + direction
	_set_cell_surface(layout, edge, 2, SiteLayoutDataType.SURFACE_PLATFORM | SiteLayoutDataType.SURFACE_STAIR)
	_add_stair(layout, lower, middle)
	_add_stair(layout, middle, edge)
	layout.details["scene_template"] = "CASTLE_COURTYARD"
	layout.details["castle_center"] = center

static func _apply_ruins_terrace(layout: SiteLayoutDataType, center: Vector2i) -> void:
	for y: int in range(center.y - 3, center.y + 4):
		for x: int in range(center.x - 4, center.x + 5):
			var cell: Vector2i = Vector2i(x, y)
			if SiteLayoutDataType.is_valid_cell(cell):
				_set_cell_surface(layout, cell, 1, SiteLayoutDataType.SURFACE_PLATFORM)
	var lower: Vector2i = center + Vector2i.DOWN * 5
	var middle: Vector2i = center + Vector2i.DOWN * 4
	var upper: Vector2i = center + Vector2i.DOWN * 3
	_add_stair(layout, lower, middle)
	_add_stair(layout, middle, upper)
	layout.details["scene_template"] = "RUINS_TERRACE"

static func _apply_cave_entrance(layout: SiteLayoutDataType, center: Vector2i) -> void:
	for y: int in range(center.y - 2, center.y + 3):
		for x: int in range(center.x - 2, center.x + 3):
			var cell: Vector2i = Vector2i(x, y)
			if SiteLayoutDataType.is_valid_cell(cell):
				_set_cell_surface(layout, cell, 1, SiteLayoutDataType.SURFACE_PLATFORM)
	_add_stair(layout, center + Vector2i.DOWN * 4, center + Vector2i.DOWN * 3)
	_add_stair(layout, center + Vector2i.DOWN * 3, center + Vector2i.DOWN * 2)
	layout.details["scene_template"] = "CAVE_ENTRANCE"

static func _apply_mountain_pass_transitions(layout: SiteLayoutDataType) -> void:
	if layout == null:
		return
	var stair_count: int = 0
	var exits: Array[Vector2i] = SiteLayoutDataType.exit_offsets(layout.travel_exit_mask)
	# The pass is a pair of broad cliffs separated by one deliberate corridor.
	# Keep the corridor width stable so the full preview reads as a landform,
	# rather than a noisy collection of one-cell stair cuts.
	var corridor_axis: int = 0 if exits.size() >= 2 and exits[0].x != 0 else 1
	var corridor_center: int = 25
	if corridor_axis == 0:
		corridor_center = 25 + DeterministicHash.int_range(layout.site_seed, layout.global_region_cell, 46_950, -3, 3)
	else:
		corridor_center = 25 + DeterministicHash.int_range(layout.site_seed, layout.global_region_cell, 46_951, -3, 3)
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for y: int in range(SiteLayoutDataType.GRID_SIZE.y):
		for x: int in range(SiteLayoutDataType.GRID_SIZE.x):
			var corridor_cell: Vector2i = Vector2i(x, y)
			if not _passage_open_at(layout, layout.cell_center_meters(corridor_cell)):
				continue
			for direction: Vector2i in directions:
				var cliff_cell: Vector2i = corridor_cell + direction
				if not SiteLayoutDataType.is_valid_cell(cliff_cell) \
					or _passage_open_at(layout, layout.cell_center_meters(cliff_cell)):
					continue
				var route_point: Vector2 = layout.cell_center_meters(corridor_cell)
				var on_route: bool = _near_segments(
					route_point,
					exits,
					PASSAGE_HALF_WIDTH_METERS + 2.0
				)
				var corridor_aligned: bool = absi(corridor_cell.x - corridor_center) <= 3 if corridor_axis == 0 \
					else absi(corridor_cell.y - corridor_center) <= 3
				on_route = on_route and corridor_aligned
				if layout.layout_kind == SiteLayoutDataType.LayoutKind.POI:
					# A POI pass has one authored approach path.  Do not place a
					# staircase on every cell along the global exit ray; that turns
					# the mountain boundary into a row of repeated ladders.
					on_route = _near_polyline(
						route_point,
						layout.primary_path_meters,
						PATH_HALF_WIDTH_METERS + 3.0
					)
				if not on_route or posmod(corridor_cell.x + corridor_cell.y, 3) != 0:
					continue
				var cliff_surface: int = layout.surface_flags_at(cliff_cell)
				if (cliff_surface & SiteLayoutDataType.SURFACE_CLIFF) == 0:
					continue
				# Reserve the first raised cell as a walkable stair landing. The
				# next cell remains a level-2 cliff, giving the renderer a real
				# floor -> stair -> cliff sequence rather than a flat overlay.
				_set_cell_surface(
					layout,
					cliff_cell,
					1,
					SiteLayoutDataType.SURFACE_PLATFORM | SiteLayoutDataType.SURFACE_STAIR
				)
				var before_count: int = layout.transitions.size()
				_add_stair(layout, corridor_cell, cliff_cell)
				if layout.transitions.size() > before_count:
					stair_count += 1
	layout.details["pass_stair_count"] = stair_count

static func _apply_bridge_transition(layout: SiteLayoutDataType) -> void:
	var center: Vector2i = _cell_from_meters(layout, Vector2i.ZERO)
	# The bridge spans perpendicular to the river connection axis.
	var river_axis: int = 0
	for offset: Vector2i in layout.river_connection_offsets:
		if offset.x != 0:
			river_axis = 1
			break
	var bridge_step: Vector2i = Vector2i.DOWN if river_axis == 1 else Vector2i.RIGHT
	var bridge_cells: Array[Vector2i] = []
	for span: int in range(-2, 3):
		var cell: Vector2i = center + bridge_step * span
		if not SiteLayoutDataType.is_valid_cell(cell):
			continue
		_set_cell_surface(layout, cell, 0, SiteLayoutDataType.SURFACE_BRIDGE)
		bridge_cells.append(cell)
	for index: int in range(bridge_cells.size() - 1):
		layout.transitions.append(SiteTransitionDataType.new(
			bridge_cells[index],
			bridge_cells[index + 1],
			0,
			0,
			SiteTransitionDataType.Kind.BRIDGE
		))
	var bank_cells: Array[Vector2i] = []
	var bank_width_step: Vector2i = Vector2i.DOWN if bridge_step.x != 0 else Vector2i.RIGHT
	for span: int in [-3, 3]:
		var bank_cell: Vector2i = center + bridge_step * span
		var bridge_cell: Vector2i = center + bridge_step * (span - signi(span))
		if not SiteLayoutDataType.is_valid_cell(bank_cell) \
			or not SiteLayoutDataType.is_valid_cell(bridge_cell):
			continue
		for width_offset: int in range(-1, 2):
			var dock_cell: Vector2i = bank_cell + bank_width_step * width_offset
			if not SiteLayoutDataType.is_valid_cell(dock_cell):
				continue
			_set_cell_surface(
				layout,
				dock_cell,
				1,
				SiteLayoutDataType.SURFACE_PLATFORM | SiteLayoutDataType.SURFACE_DOCK
			)
			bank_cells.append(dock_cell)
		_set_cell_surface(
			layout,
			bank_cell,
			1,
			SiteLayoutDataType.SURFACE_PLATFORM | SiteLayoutDataType.SURFACE_DOCK | SiteLayoutDataType.SURFACE_STAIR
		)
		_add_stair(layout, bridge_cell, bank_cell)
	layout.details["bridge_cells"] = bridge_cells
	layout.details["bridge_bank_cells"] = bank_cells
	layout.details["scene_template"] = "RIVER_DOCK" if layout.layout_kind == SiteLayoutDataType.LayoutKind.POI else "BRIDGE"
	if not bridge_cells.is_empty():
		var minimum: Vector2i = bridge_cells[0]
		var maximum: Vector2i = bridge_cells[0]
		for cell: Vector2i in bridge_cells:
			minimum.x = mini(minimum.x, cell.x)
			minimum.y = mini(minimum.y, cell.y)
			maximum.x = maxi(maximum.x, cell.x)
			maximum.y = maxi(maximum.y, cell.y)
		layout.facility_placements.append(SiteContentTypes.make_facility(
			"generated:%s:bridge:0" % layout.site_id,
			SiteContentTypes.Facility.BRIDGE,
			minimum,
			maximum - minimum + Vector2i.ONE,
			SiteContentTypes.Orientation.HORIZONTAL if bridge_step.x != 0 \
				else SiteContentTypes.Orientation.VERTICAL
		))

static func _add_stair(layout: SiteLayoutDataType, from_cell: Vector2i, to_cell: Vector2i) -> void:
	if not SiteLayoutDataType.is_valid_cell(from_cell) or not SiteLayoutDataType.is_valid_cell(to_cell):
		return
	var from_level: int = layout.elevation_level_at(from_cell)
	var to_level: int = layout.elevation_level_at(to_cell)
	if from_level == to_level:
		# A stair is a height transition, never a decoration on a flat cell.
		return
	_set_cell_surface(layout, from_cell, from_level, layout.surface_flags_at(from_cell) | SiteLayoutDataType.SURFACE_STAIR)
	_set_cell_surface(layout, to_cell, to_level, layout.surface_flags_at(to_cell) | SiteLayoutDataType.SURFACE_STAIR)
	for existing: SiteTransitionData in layout.transitions:
		if existing != null and existing.connects(from_cell, to_cell):
			return
	layout.transitions.append(SiteTransitionDataType.new(
		from_cell,
		to_cell,
		from_level,
		to_level,
		SiteTransitionDataType.Kind.STAIR
	))
	var facility_type: int = SiteContentTypes.Facility.WOOD_STAIR \
		if layout.terrain_type in [TerrainType.FOREST, TerrainType.SWAMP] \
		else SiteContentTypes.Facility.STONE_STAIR
	layout.facility_placements.append(SiteContentTypes.make_facility(
		"generated:%s:stair:%d:%d:%d:%d" % [
			layout.site_id,
			from_cell.x,
			from_cell.y,
			to_cell.x,
			to_cell.y,
		],
		facility_type,
		from_cell,
		Vector2i.ONE,
		SiteContentTypes.Orientation.HORIZONTAL if from_cell.x != to_cell.x \
			else SiteContentTypes.Orientation.VERTICAL,
		to_cell
	))

static func _generate_facilities(layout: SiteLayoutDataType) -> void:
	if layout.layout_kind != SiteLayoutDataType.LayoutKind.POI:
		return
	if layout.site_type in [WorldPOIType.VILLAGE, WorldPOIType.TOWN] \
		and layout.site_landform == SiteLayoutDataType.Landform.NONE:
		_generate_rectangular_building(layout, SiteContentTypes.Facility.WOOD_WALL, "rectangular_wood_house")
		return
	if layout.site_type != WorldPOIType.CASTLE:
		return
	_generate_rectangular_building(layout, SiteContentTypes.Facility.STONE_WALL, "rectangular_stone_hall")

static func _generate_rectangular_building(
		layout: SiteLayoutDataType,
		wall_type: int,
		definition_id: String
	) -> void:
	var center_value: Variant = layout.details.get("castle_center", SiteLayoutDataType.ENTRANCE_CELL)
	if layout.site_type in [WorldPOIType.VILLAGE, WorldPOIType.TOWN]:
		center_value = _cell_from_meters(layout, layout.hub_local_meters)
	var center: Vector2i = center_value as Vector2i if center_value is Vector2i \
		else SiteLayoutDataType.ENTRANCE_CELL
	var size: Vector2i = Vector2i(9, 7) if wall_type == SiteContentTypes.Facility.STONE_WALL \
		else Vector2i(7, 5)
	var origin: Vector2i = Vector2i(
		clampi(center.x - floori(float(size.x) * 0.5), 1, SiteLayoutDataType.GRID_SIZE.x - size.x - 1),
		clampi(center.y - floori(float(size.y) * 0.5), 1, SiteLayoutDataType.GRID_SIZE.y - size.y - 1)
	)
	layout.facility_placements.append(SiteContentTypes.make_facility(
		"generated:%s:building:%s" % [layout.site_id, definition_id],
		SiteContentTypes.Facility.BUILDING,
		origin,
		size,
		SiteContentTypes.Orientation.HORIZONTAL,
		Vector2i(-1, -1),
		definition_id
	))
	var door_x: int = origin.x + floori(float(size.x) * 0.5)
	for x: int in range(origin.x, origin.x + size.x):
		_add_wall_edge(layout, Vector2i(x, origin.y), Vector2i(x, origin.y - 1), wall_type)
		if x != door_x:
			_add_wall_edge(layout, Vector2i(x, origin.y + size.y - 1), Vector2i(x, origin.y + size.y), wall_type)
	for y: int in range(origin.y, origin.y + size.y):
		_add_wall_edge(layout, Vector2i(origin.x, y), Vector2i(origin.x - 1, y), wall_type)
		_add_wall_edge(layout, Vector2i(origin.x + size.x - 1, y), Vector2i(origin.x + size.x, y), wall_type)

static func _add_wall_edge(
		layout: SiteLayoutDataType,
		from_cell: Vector2i,
		to_cell: Vector2i,
		facility_type: int
	) -> void:
	if not SiteLayoutDataType.is_valid_cell(from_cell) or not SiteLayoutDataType.is_valid_cell(to_cell):
		return
	layout.wall_edges.append({
		"id": "generated:%s:wall:%d:%d:%d:%d" % [
			layout.site_id,
			from_cell.x,
			from_cell.y,
			to_cell.x,
			to_cell.y,
		],
		"type": facility_type,
		"from": from_cell,
		"to": to_cell,
	})

static func _generate_resources(layout: SiteLayoutDataType) -> void:
	var amounts_value: Variant = layout.details.get("resource_amounts", PackedInt32Array())
	if not amounts_value is PackedInt32Array:
		return
	var amounts: PackedInt32Array = amounts_value as PackedInt32Array
	var occupied: Dictionary = {}
	for facility: Dictionary in layout.facility_placements:
		_mark_footprint(occupied, facility)
	for resource_type: int in range(mini(amounts.size(), SiteContentTypes.RESOURCE_COUNT)):
		var remaining: int = amounts[resource_type]
		if remaining <= 0:
			continue
		if resource_type == SiteContentTypes.RESOURCE_FOREST \
			and layout.terrain_type == TerrainType.FOREST:
			# A Forest Site is a wood-resource field, not one central grove. Use a
			# deterministic interior lattice so the authoritative placements cover
			# the Site while the renderer can leave only true terrain joins clear.
			var forest_unplaced: int = _generate_forest_resources(layout, remaining, occupied)
			layout.details["resource_unplaced_%d" % resource_type] = forest_unplaced
			continue
		var cluster_quantity: int = _resource_cluster_quantity(resource_type)
		var cluster_center: Vector2i = _resource_cluster_center(layout, resource_type)
		var candidates: Array[Dictionary] = []
		for y: int in range(1, SiteLayoutDataType.GRID_SIZE.y - 1):
			for x: int in range(1, SiteLayoutDataType.GRID_SIZE.x - 1):
				var cell: Vector2i = Vector2i(x, y)
				if not _resource_cell_valid(layout, cell, resource_type) or occupied.has(cell):
					continue
				candidates.append({
					"cell": cell,
					"score": _resource_habitat_score(layout, cell, resource_type),
					"distance": absi(cell.x - cluster_center.x) + absi(cell.y - cluster_center.y),
					"cluster": _resource_cluster_field(layout, cell, resource_type),
					"rank": DeterministicHash.value(
						layout.site_seed,
						layout.global_region_cell + cell,
						44_000 + resource_type
					),
				})
		candidates.sort_custom(Callable(SiteLayoutGenerator, "_resource_candidate_less"))
		var placement_index: int = 0
		while remaining > 0 and placement_index < candidates.size():
			var cell: Vector2i = candidates[placement_index]["cell"] as Vector2i
			placement_index += 1
			if occupied.has(cell):
				continue
			var quantity: int = mini(cluster_quantity, remaining)
			layout.resource_placements.append(SiteContentTypes.make_resource(
				"generated:%s:resource:%s:%d" % [
					layout.site_id,
					SiteContentTypes.resource_name(resource_type),
					layout.resource_placements.size(),
				],
				resource_type,
				cell,
				Vector2i.ONE,
				quantity
			))
			occupied[cell] = true
			remaining -= quantity
		layout.details["resource_unplaced_%d" % resource_type] = remaining

static func _generate_forest_resources(
		layout: SiteLayoutDataType,
		remaining: int,
		occupied: Dictionary
	) -> int:
	var candidates: Array[Dictionary] = []
	# Keep resource centres away from the Site frame itself.  The visual layer
	# may use the full edge when the neighbour is also Forest, but it can then
	# suppress only the side that actually joins another terrain.
	var margin: int = 3
	var step: int = 6
	for y: int in range(margin, SiteLayoutDataType.GRID_SIZE.y - margin, step):
		for x: int in range(margin, SiteLayoutDataType.GRID_SIZE.x - margin, step):
			var cell: Vector2i = Vector2i(
				clampi(x + DeterministicHash.int_range(layout.site_seed, Vector2i(x, y), 46_610, -1, 1), margin, SiteLayoutDataType.GRID_SIZE.x - margin - 1),
				clampi(y + DeterministicHash.int_range(layout.site_seed, Vector2i(x, y), 46_611, -1, 1), margin, SiteLayoutDataType.GRID_SIZE.y - margin - 1)
			)
			if occupied.has(cell) or not _resource_cell_valid(layout, cell, SiteContentTypes.RESOURCE_FOREST):
				continue
			candidates.append({
				"cell": cell,
				"rank": DeterministicHash.value(
					layout.site_seed,
					layout.global_region_cell + cell,
					46_612
				),
			})
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left["rank"]) < int(right["rank"])
	)
	for candidate: Dictionary in candidates:
		if remaining <= 0:
			break
		var cell: Vector2i = candidate["cell"] as Vector2i
		if occupied.has(cell):
			continue
		var quantity: int = mini(_resource_cluster_quantity(SiteContentTypes.RESOURCE_FOREST), remaining)
		layout.resource_placements.append(SiteContentTypes.make_resource(
			"generated:%s:resource:forest:%d" % [layout.site_id, layout.resource_placements.size()],
			SiteContentTypes.RESOURCE_FOREST,
			cell,
			Vector2i.ONE,
			quantity
		))
		occupied[cell] = true
		remaining -= quantity
	return remaining

static func _resource_cell_valid(
		layout: SiteLayoutDataType,
		cell: Vector2i,
		resource_type: int
	) -> bool:
	var point: Vector2 = layout.cell_center_meters(cell)
	if (not layout.road_connection_offsets.is_empty() \
		and _near_segments(point, layout.road_connection_offsets, ROAD_HALF_WIDTH_METERS)) \
		or (layout.layout_kind == SiteLayoutDataType.LayoutKind.POI \
		and _near_polyline(point, layout.primary_path_meters, PATH_HALF_WIDTH_METERS)):
		return false
	if SiteContentTypes.is_water_surface(layout.native_surface_at(cell)):
		return false
	var surface: int = layout.native_surface_at(cell)
	if resource_type >= SiteContentTypes.RESOURCE_STONE_ORE:
		return surface == SiteContentTypes.NativeSurface.ROCK
	var terrain_type: int = layout.terrain_type
	if resource_type == SiteContentTypes.RESOURCE_FRUIT_TREE \
		and terrain_type not in [TerrainType.PLAINS, TerrainType.FOREST, TerrainType.SWAMP]:
		return false
	if resource_type == SiteContentTypes.RESOURCE_FOREST \
		and terrain_type not in [TerrainType.PLAINS, TerrainType.FOREST, TerrainType.SWAMP, TerrainType.SNOW]:
		return false
	return surface == SiteContentTypes.NativeSurface.DIRT

static func _resource_habitat_score(
		layout: SiteLayoutDataType,
		cell: Vector2i,
		resource_type: int
	) -> int:
	var terrain_type: int = layout.terrain_type
	var score: int = 0
	match resource_type:
		SiteContentTypes.RESOURCE_GRASS:
			score += 34 if terrain_type == TerrainType.PLAINS else 24
			if terrain_type == TerrainType.FOREST:
				score += 10
			elif terrain_type == TerrainType.SWAMP:
				score += 8
			elif terrain_type in [TerrainType.SAND, TerrainType.SNOW]:
				score -= 8
			score += roundi(clampf(layout.moisture, 0.0, 1.0) * 24.0)
		SiteContentTypes.RESOURCE_FRUIT_TREE:
			score += 38 if terrain_type == TerrainType.FOREST else 30
			if terrain_type == TerrainType.SWAMP:
				score += 8
			score += roundi(clampf(layout.moisture, 0.0, 1.0) * 20.0)
		SiteContentTypes.RESOURCE_FOREST:
			score += 56 if terrain_type == TerrainType.FOREST else 26
			if terrain_type == TerrainType.SWAMP:
				score += 14
			elif terrain_type == TerrainType.SNOW:
				score += 8
			score += roundi(clampf(layout.moisture, 0.0, 1.0) * 18.0)
		_:
			# Ore already has the hard ROCK requirement.  Prefer cells next to
			# continuous outcrops so a vein reads as a vein instead of salt-and-
			# pepper dots.
			score += 42 if terrain_type == TerrainType.MOUNTAIN else 16
			if terrain_type == TerrainType.SNOW:
				score += 12
			score += roundi(clampf(layout.elevation, 0.0, 1.0) * 30.0)
			for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				if layout.native_surface_at(cell + direction) == SiteContentTypes.NativeSurface.ROCK:
					score += 8
	var cluster_center: Vector2i = _resource_cluster_center(layout, resource_type)
	var cluster_distance: int = absi(cell.x - cluster_center.x) + absi(cell.y - cluster_center.y)
	# Resources are scene elements, not evenly scattered counters. Keep valid
	# candidates close to one deterministic centre so a forest, orchard or ore
	# seam reads as a visible group in the full Site preview.
	score += maxi(0, 180 - cluster_distance * 12)
	return score

static func _resource_cluster_center(layout: SiteLayoutDataType, resource_type: int) -> Vector2i:
	return Vector2i(
		DeterministicHash.int_range(
			layout.site_seed,
			layout.global_region_cell,
			46_800 + resource_type * 2,
			6,
			SiteLayoutDataType.GRID_SIZE.x - 7
		),
		DeterministicHash.int_range(
			layout.site_seed,
			layout.global_region_cell,
			46_801 + resource_type * 2,
			6,
			SiteLayoutDataType.GRID_SIZE.y - 7
		)
	)

static func _resource_cluster_field(
	layout: SiteLayoutDataType,
	cell: Vector2i,
	resource_type: int
) -> int:
	# A coarse deterministic field gives neighbouring cells the same priority,
	# producing readable grass/forest/mineral bands without storing extra state.
	var coarse: Vector2i = Vector2i(floori(float(cell.x) / 4.0), floori(float(cell.y) / 4.0))
	return roundi(DeterministicHash.normalized(
		layout.site_seed,
		coarse,
		45_000 + resource_type
	) * 100.0)

static func _resource_cluster_quantity(resource_type: int) -> int:
	if resource_type == SiteContentTypes.RESOURCE_GRASS:
		return 6
	if resource_type == SiteContentTypes.RESOURCE_FOREST:
		return 4
	if resource_type >= SiteContentTypes.RESOURCE_STONE_ORE:
		return 5
	return 1

static func _resource_candidate_less(left: Dictionary, right: Dictionary) -> bool:
	var left_score: int = int(left["score"])
	var right_score: int = int(right["score"])
	if left_score != right_score:
		return left_score > right_score
	var left_distance: int = int(left["distance"])
	var right_distance: int = int(right["distance"])
	if left_distance != right_distance:
		return left_distance < right_distance
	var left_cluster: int = int(left["cluster"])
	var right_cluster: int = int(right["cluster"])
	if left_cluster != right_cluster:
		return left_cluster > right_cluster
	return int(left["rank"]) < int(right["rank"])

static func _mark_footprint(occupied: Dictionary, placement: Dictionary) -> void:
	var origin_value: Variant = placement.get("origin", Vector2i.ZERO)
	var size_value: Variant = placement.get("size", Vector2i.ONE)
	if not origin_value is Vector2i or not size_value is Vector2i:
		return
	var origin: Vector2i = origin_value as Vector2i
	var size: Vector2i = size_value as Vector2i
	for y: int in range(size.y):
		for x: int in range(size.x):
			occupied[origin + Vector2i(x, y)] = true

static func _set_cell_surface(
		layout: SiteLayoutDataType,
		cell: Vector2i,
		level: int,
		flags: int
	) -> void:
	if layout == null or not SiteLayoutDataType.is_valid_cell(cell):
		return
	var index: int = cell.y * SiteLayoutDataType.GRID_SIZE.x + cell.x
	layout.elevation_levels[index] = level
	layout.surface_flags[index] = flags

static func _cell_from_meters(layout: SiteLayoutDataType, point: Vector2i) -> Vector2i:
	var local: Vector2 = (Vector2(point) - Vector2(layout.bounds_meters.position)) \
		/ float(SiteLayoutDataType.CELL_SIZE_METERS)
	return Vector2i(
		clampi(floori(local.x), 0, SiteLayoutDataType.GRID_SIZE.x - 1),
		clampi(floori(local.y), 0, SiteLayoutDataType.GRID_SIZE.y - 1)
	)

static func _cardinal_direction(from_cell: Vector2i, to_cell: Vector2i) -> Vector2i:
	var delta: Vector2i = to_cell - from_cell
	if absi(delta.x) >= absi(delta.y) and delta.x != 0:
		return Vector2i(signi(delta.x), 0)
	if delta.y != 0:
		return Vector2i(0, signi(delta.y))
	return Vector2i.DOWN

static func _ensure_entrance_surface(layout: SiteLayoutDataType) -> void:
	var entrance: Vector2i = SiteLayoutDataType.ENTRANCE_CELL
	if not SiteLayoutDataType.is_valid_cell(entrance):
		return
	var surface: int = layout.surface_flags_at(entrance)
	if (surface & SiteLayoutDataType.SURFACE_WATER) != 0 \
		and (surface & SiteLayoutDataType.SURFACE_BRIDGE) == 0:
		_set_native_surface(layout, entrance, SiteContentTypes.NativeSurface.DIRT)
		_set_cell_surface(layout, entrance, 0, 0)

static func _derive_height_edges(layout: SiteLayoutDataType) -> void:
	var neighbors: Array[Array] = [
		[Vector2i.UP, SiteLayoutDataType.EDGE_NORTH],
		[Vector2i.RIGHT, SiteLayoutDataType.EDGE_EAST],
		[Vector2i.DOWN, SiteLayoutDataType.EDGE_SOUTH],
		[Vector2i.LEFT, SiteLayoutDataType.EDGE_WEST],
	]
	for y: int in range(SiteLayoutDataType.GRID_SIZE.y):
		for x: int in range(SiteLayoutDataType.GRID_SIZE.x):
			var cell: Vector2i = Vector2i(x, y)
			var level: int = layout.elevation_level_at(cell)
			var edge: int = 0
			for item: Array in neighbors:
				var neighbor: Vector2i = cell + (item[0] as Vector2i)
				if SiteLayoutDataType.is_valid_cell(neighbor) \
					and layout.elevation_level_at(neighbor) != level:
					edge |= int(item[1])
			layout.height_edge_flags[y * SiteLayoutDataType.GRID_SIZE.x + x] = edge

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
	if not layout.river_connection_offsets.is_empty() \
		and _near_segments(point, layout.river_connection_offsets, RIVER_HALF_WIDTH_METERS):
		code |= SiteLayoutDataType.VISUAL_RIVER
	return code

static func _passage_open_at(layout: SiteLayoutDataType, point: Vector2) -> bool:
	if layout.site_landform != SiteLayoutDataType.Landform.MOUNTAIN_PASS:
		return true
	# A generated stair/landing is an intentional exception to the raw pass
	# corridor mask; otherwise navigation would mark the visual stair cell
	# blocked before SiteLayoutData.can_traverse() can use its transition.
	if layout.has_height_base():
		var local_cell: Vector2i = _cell_from_meters(
			layout,
			Vector2i(floori(point.x), floori(point.y))
		)
		if (layout.surface_flags_at(local_cell) & (SiteLayoutDataType.SURFACE_STAIR | SiteLayoutDataType.SURFACE_RAMP)) != 0:
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

static func _contract_offsets(source: Variant) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if source is Array:
		for value: Variant in source as Array:
			if value is Vector2i:
				_append_unique_offset(result, value as Vector2i)
	result.sort_custom(Callable(SiteLayoutGenerator, "_offset_less"))
	return result

static func _append_unique_offset(result: Array[Vector2i], delta: Vector2i) -> void:
	if absi(delta.x) + absi(delta.y) != 1:
		return
	if not result.has(delta):
		result.append(delta)

static func _append_orthogonal_path(
		points: Array[Vector2i],
		from_point: Vector2i,
		to_point: Vector2i
	) -> void:
	if points.is_empty():
		points.append(from_point)
	if from_point == to_point:
		return
	# Authored Site roads follow tile edges. The deterministic horizontal-first
	# bend keeps every rendered segment orthogonal; A* owns actual movement.
	var bend: Vector2i = Vector2i(to_point.x, from_point.y)
	if bend != from_point and bend != to_point:
		points.append(bend)
	if points.is_empty() or points[-1] != to_point:
		points.append(to_point)

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
