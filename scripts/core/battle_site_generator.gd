class_name BattleSiteGenerator
extends RefCounted

const SiteLayoutGeneratorType = preload("res://scripts/core/site_layout_generator.gd")
const SiteLayoutDataType = preload("res://scripts/data/site_layout_data.gd")
const BattleFormationDataType = preload("res://scripts/data/battle_formation_data.gd")
const MapArtCatalogType = preload("res://scripts/data/map_art_catalog.gd")

const FOREST_TREE_COUNT: int = 16
const FOREST_BUSH_COUNT: int = 6
const PLAINS_GRASS_COUNT: int = 10
const MOUNTAIN_ROCK_COUNT: int = 10
const CLEARING_SALT: int = 61_001
const TREE_SALT: int = 61_101
const BUSH_SALT: int = 61_201
const GRASS_SALT: int = 61_301
const ROCK_SALT: int = 61_401

static func footprint_global_cells(center_global_region_cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset_y: int in range(-1, 2):
		for offset_x: int in range(-1, 2):
			result.append(center_global_region_cell + Vector2i(offset_x, offset_y))
	return result

static func battle_local_origin_for(
		global_region_cell: Vector2i,
		center_global_region_cell: Vector2i
	) -> Vector2:
	var offset: Vector2i = global_region_cell - center_global_region_cell + Vector2i.ONE
	return Vector2(
		float(offset.x * WorldCoordinates.REGION_CELL_SIZE_METERS),
		float(offset.y * WorldCoordinates.REGION_CELL_SIZE_METERS)
	)

func generate(
		context: BattleSiteContext,
		resolved_cells: Array[Dictionary]
	) -> Dictionary:
	if context == null or context.attacker == null or context.defender == null \
			or resolved_cells.size() != 9:
		return {}
	var size_meters: Vector2 = Vector2(
		float(context.footprint_size.x * WorldCoordinates.REGION_CELL_SIZE_METERS),
		float(context.footprint_size.y * WorldCoordinates.REGION_CELL_SIZE_METERS)
	)
	var cells: Array[Dictionary] = []
	var site_layouts: Array[SiteLayoutData] = []
	for resolved_cell: Dictionary in resolved_cells:
		var generated_cell: Dictionary = _generate_cell(context, resolved_cell)
		if generated_cell.is_empty():
			return {}
		cells.append(generated_cell)
		site_layouts.append(generated_cell["site_layout"] as SiteLayoutData)
	var center_cell: Dictionary = cells[4]
	var center_terrain: int = int(center_cell["terrain_type"])
	var attacker_deployment: Dictionary = BattleRules.deployment_preview(
		context.attacker,
		center_terrain,
		size_meters,
		context.attacker_entry_direction
	)
	var defender_deployment: Dictionary = BattleRules.deployment_preview(
		context.defender,
		center_terrain,
		size_meters,
		context.defender_entry_direction
	)
	attacker_deployment = _filter_deployment_to_passable_cells(
		attacker_deployment,
		cells
	)
	defender_deployment = _filter_deployment_to_passable_cells(
		defender_deployment,
		cells
	)
	var terrain_representation: String = _terrain_representation(cells)
	var preview_representation: String = _preview_representation(
		context,
		attacker_deployment,
		defender_deployment
	)
	return {
		"context": context,
		"footprint_cells": cells,
		"site_layouts": site_layouts,
		"size_meters": size_meters,
		"bounds_meters": Rect2(Vector2.ZERO, size_meters),
		"center_cell": center_cell,
		"center_terrain": center_terrain,
		"attacker_deployment": attacker_deployment,
		"defender_deployment": defender_deployment,
		"terrain_debug_representation": terrain_representation,
		"terrain_hash": terrain_representation.sha256_text(),
		"preview_hash": preview_representation.sha256_text(),
	}

static func _filter_deployment_to_passable_cells(
		deployment: Dictionary,
		cells: Array[Dictionary]
	) -> Dictionary:
	var result: Dictionary = deployment.duplicate(true)
	var original_positions: Array = deployment.get("marker_positions_meters", []) as Array
	var filtered_positions: Array[Vector2] = []
	var marker_personnel: Array[int] = []
	var original_personnel: int = int(deployment.get("initial_deployed_personnel", 0))
	var kept_personnel: int = 0
	var facing: Vector2 = deployment.get("facing", Vector2.DOWN) as Vector2
	var deployment_zone: Rect2 = deployment.get("zone_meters", Rect2()) as Rect2
	for index: int in range(original_positions.size()):
		var value: Variant = original_positions[index]
		var personnel: int = mini(
			BattleFormationDataType.DEFAULT_PERSONNEL,
			maxi(original_personnel - index * BattleFormationDataType.DEFAULT_PERSONNEL, 0)
		)
		if not value is Vector2 or personnel <= 0:
			continue
		var candidate: Vector2 = value as Vector2
		var placed_personnel: int = personnel
		if not _deployment_formation_is_passable(candidate, placed_personnel, facing, cells):
			candidate = _nearest_passable_deployment_position(
				candidate,
				placed_personnel,
				facing,
				cells,
				deployment_zone
			)
		if candidate == Vector2.INF:
			# A narrow entry can touch a Formation's outer rank without making
			# the whole army disappear. Keep the largest smaller rank that fits;
			# the remainder stays in reserve and every deployed soldier is still
			# checked against the same blocked/elevated/water cells.
			placed_personnel = personnel
			while candidate == Vector2.INF and placed_personnel > 1:
				placed_personnel = maxi(
					placed_personnel - BattleFormationDataType.FORMATION_COLUMNS,
					1
				)
				candidate = _nearest_passable_deployment_position(
					value as Vector2,
					placed_personnel,
					facing,
					cells,
					deployment_zone
				)
		if candidate == Vector2.INF:
			# This formation has no valid place in its deployment zone; the
			# remaining personnel stay in reserve.
			continue
		filtered_positions.append(candidate)
		marker_personnel.append(placed_personnel)
		kept_personnel += placed_personnel
	result["marker_positions_meters"] = filtered_positions
	result["marker_count"] = filtered_positions.size()
	result["marker_personnel"] = marker_personnel
	result["initial_deployed_personnel"] = kept_personnel
	result["reserve_personnel"] = int(deployment.get("total_personnel", 0)) \
		- int(result["initial_deployed_personnel"])
	return result

static func _nearest_passable_deployment_position(
	origin: Vector2,
	personnel: int,
	facing: Vector2,
	cells: Array[Dictionary],
	zone: Rect2
	) -> Vector2:
	if zone.has_point(origin) and _deployment_formation_is_passable(
			origin,
			personnel,
			facing,
			cells
		):
		return origin
	var max_radius: int = 45
	for radius: int in range(1, max_radius + 1):
		for offset_y: int in range(-radius, radius + 1):
			for offset_x: int in range(-radius, radius + 1):
				if absi(offset_x) != radius and absi(offset_y) != radius:
					continue
				var candidate: Vector2 = origin + Vector2(offset_x, offset_y) \
					* float(SiteLayoutDataType.CELL_SIZE_METERS)
				if zone.has_point(candidate) and _deployment_formation_is_passable(
						candidate, personnel, facing, cells):
					return candidate
	return Vector2.INF

static func _deployment_formation_is_passable(
		position_m: Vector2,
		personnel: int,
		facing: Vector2,
		cells: Array[Dictionary]
	) -> bool:
	var formation_size: Vector2 = BattleFormationDataType.formation_size_for_personnel(personnel)
	# Test the same soldier centers that BattleSiteMap renders. A formation may
	# approach a boundary; only soldiers actually standing on blocked cells are
	# rejected, not the empty space between or outside the ranks.
	for index: int in range(personnel):
		var local_slot: Vector2 = BattleFormationDataType.formation_slot_local(
			index,
			personnel,
			formation_size.x,
			formation_size.y
		)
		var soldier_position: Vector2 = BattleFormationDataType.formation_world_position(
			position_m,
			facing,
			local_slot
		)
		if not _deployment_position_is_passable(soldier_position, cells, facing):
			return false
	return true

static func _deployment_position_is_passable(
	position_m: Vector2,
	cells: Array[Dictionary],
	facing: Vector2 = Vector2.DOWN
	) -> bool:
	if position_m.x < 0.0 or position_m.y < 0.0 \
			or position_m.x >= 150.0 * SiteLayoutDataType.CELL_SIZE_METERS \
			or position_m.y >= 150.0 * SiteLayoutDataType.CELL_SIZE_METERS:
		return false
	var local_cell: Vector2i = Vector2i(
		floori(position_m.x / float(SiteLayoutDataType.CELL_SIZE_METERS)),
		floori(position_m.y / float(SiteLayoutDataType.CELL_SIZE_METERS))
	)
	var tile_x: int = floori(float(local_cell.x) / float(SiteLayoutDataType.GRID_SIZE.x))
	var tile_y: int = floori(float(local_cell.y) / float(SiteLayoutDataType.GRID_SIZE.y))
	var tile_index: int = tile_y * 3 + tile_x
	if tile_index < 0 or tile_index >= cells.size():
		return false
	var layout: SiteLayoutDataType = cells[tile_index].get("site_layout", null) as SiteLayoutDataType
	if layout == null or not layout.has_navigation_base():
		return false
	var site_cell: Vector2i = Vector2i(
		posmod(local_cell.x, SiteLayoutDataType.GRID_SIZE.x),
		posmod(local_cell.y, SiteLayoutDataType.GRID_SIZE.y)
	)
	var flags: int = layout.navigation_flags_at(site_cell)
	if (flags & SiteLayoutDataType.NAV_BLOCKED) != 0:
		return false
	var surface: int = layout.surface_flags_at(site_cell)
	# A terrace can be traversable for tactical movement, but it is not a
	# valid deployment floor. Keep initial formations on the ground-level
	# approach instead of placing them on the visible cliff top.
	if layout.elevation_level_at(site_cell) != 0 \
			or (surface & (SiteLayoutDataType.SURFACE_CLIFF | SiteLayoutDataType.SURFACE_WALL)) != 0:
		return false
	if not _scene_art_deployment_lane_is_passable(layout, site_cell, facing):
		return false
	var native_surface: int = layout.native_surface_at(site_cell)
	return not SiteContentTypes.is_water_surface(native_surface) \
		or (surface & (SiteLayoutDataType.SURFACE_BRIDGE | SiteLayoutDataType.SURFACE_DOCK)) != 0

static func _scene_art_deployment_lane_is_passable(
	layout: SiteLayoutDataType,
	site_cell: Vector2i,
	facing: Vector2
	) -> bool:
	var scene_kind: String = MapArtCatalogType.site_scene_kind(layout)
	var local_meters: Vector2 = Vector2(site_cell) * float(SiteLayoutDataType.CELL_SIZE_METERS) \
		+ Vector2.ONE
	if scene_kind == "river_bridge_vertical":
		# The authored scene has a broad vertical river; the generated 2m
		# navigation band is narrower than the painting. Only the banks and the
		# horizontal bridge deck are valid initial deployment surfaces.
		if absf(local_meters.x - 50.0) <= 16.0:
			return absf(local_meters.y - 50.0) <= 8.0
		return true
	if scene_kind == "river_bridge":
		if absf(local_meters.y - 50.0) <= 16.0:
			return absf(local_meters.x - 50.0) <= 8.0
		return true
	if scene_kind not in ["mountain_mine", "mountain_pass", "snow_ore_shelf"]:
		return true
	var facing_unit: Vector2 = facing.normalized()
	if facing_unit == Vector2.ZERO:
		facing_unit = Vector2.DOWN
	var vertical_entry: bool = absf(facing_unit.y) >= absf(facing_unit.x)
	if vertical_entry:
		if absf(local_meters.x - 50.0) > 22.0:
			return false
		if facing_unit.y > 0.0 and local_meters.y < 30.0:
			return false
		if facing_unit.y < 0.0 and local_meters.y > 70.0:
			return false
	else:
		if absf(local_meters.y - 50.0) > 22.0:
			return false
		if facing_unit.x > 0.0 and local_meters.x < 30.0:
			return false
		if facing_unit.x < 0.0 and local_meters.x > 70.0:
			return false
	return true

func _generate_cell(
		context: BattleSiteContext,
		resolved_cell: Dictionary
	) -> Dictionary:
	for key: String in [
		"global_region_cell", "world_cell", "region_cell", "terrain_type",
		"elevation", "moisture", "river_strength", "river", "road",
		"river_crossing"
	]:
		if not resolved_cell.has(key):
			return {}
	var global_cell: Vector2i = resolved_cell["global_region_cell"] as Vector2i
	var terrain_type: int = int(resolved_cell["terrain_type"])
	var has_road: bool = bool(resolved_cell["road"])
	var has_river: bool = bool(resolved_cell["river"])
	var site_layout: SiteLayoutData = SiteLayoutGeneratorType.generate_cell_base(
		context.world_seed,
		resolved_cell
	)
	if site_layout == null or not site_layout.has_navigation_base():
		return {}
	var local_origin: Vector2 = battle_local_origin_for(
		global_cell,
		context.center_global_region_cell
	)
	var road_offsets: Array[Vector2i] = site_layout.road_connection_offsets.duplicate()
	var river_offsets: Array[Vector2i] = site_layout.river_connection_offsets.duplicate()
	var details: Dictionary = _generate_details(
		context,
		global_cell,
		local_origin,
		terrain_type,
		has_road or has_river,
		site_layout.site_seed
	)
	site_layout.details = details
	return {
		"site_layout": site_layout,
		"global_region_cell": global_cell,
		"world_cell": resolved_cell["world_cell"] as Vector2i,
		"region_cell": resolved_cell["region_cell"] as Vector2i,
		"offset_from_center": global_cell - context.center_global_region_cell,
		"local_origin_meters": local_origin,
		"terrain_type": terrain_type,
		"elevation": float(resolved_cell["elevation"]),
		"moisture": float(resolved_cell["moisture"]),
		"river_strength": float(resolved_cell["river_strength"]),
		"river": has_river,
		"road": has_road,
		"river_crossing": bool(resolved_cell["river_crossing"]),
		"road_connection_offsets": road_offsets,
		"river_connection_offsets": river_offsets,
		"details": details,
	}

func _generate_details(
		context: BattleSiteContext,
		global_cell: Vector2i,
		local_origin: Vector2,
		terrain_type: int,
		has_corridor: bool,
		site_seed: int
	) -> Dictionary:
	var details: Dictionary = {}
	match terrain_type:
		TerrainType.FOREST:
			var clearing_local: Vector2 = _detail_point(
				context, global_cell, site_seed, CLEARING_SALT, 0
			)
			details["clearing_center_meters"] = local_origin + clearing_local
			details["trees"] = _detail_points(
				context, global_cell, site_seed, local_origin, TREE_SALT, FOREST_TREE_COUNT,
				clearing_local, 18.0, has_corridor
			)
			details["bushes"] = _detail_points(
				context, global_cell, site_seed, local_origin, BUSH_SALT, FOREST_BUSH_COUNT,
				clearing_local, 13.0, has_corridor
			)
		TerrainType.PLAINS:
			details["grass"] = _detail_points(
				context, global_cell, site_seed, local_origin, GRASS_SALT, PLAINS_GRASS_COUNT,
				Vector2(-1000.0, -1000.0), 0.0, has_corridor
			)
		TerrainType.MOUNTAIN:
			details["rocks"] = _detail_points(
				context, global_cell, site_seed, local_origin, ROCK_SALT, MOUNTAIN_ROCK_COUNT,
				Vector2(-1000.0, -1000.0), 0.0, has_corridor
			)
	return details

func _detail_points(
		context: BattleSiteContext,
		global_cell: Vector2i,
		site_seed: int,
		local_origin: Vector2,
		salt: int,
		count: int,
		clearing_local: Vector2,
		clearing_radius: float,
		has_corridor: bool
	) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for attempt: int in range(count * 3):
		var local_point: Vector2 = _detail_point(
			context, global_cell, site_seed, salt, attempt
		)
		if clearing_radius > 0.0 and local_point.distance_to(clearing_local) < clearing_radius:
			continue
		if has_corridor and (absf(local_point.x - 50.0) < 11.0 or absf(local_point.y - 50.0) < 11.0):
			continue
		result.append(local_origin + local_point)
		if result.size() == count:
			break
	return result

func _detail_point(
		context: BattleSiteContext,
		global_cell: Vector2i,
		site_seed: int,
		salt: int,
		index: int
	) -> Vector2:
	var feature_seed: int = DeterministicHash.value(
		context.world_seed,
		global_cell,
		site_seed + salt
	)
	return Vector2(
		float(DeterministicHash.int_range(feature_seed, global_cell, salt + index * 2, 8, 92)),
		float(DeterministicHash.int_range(feature_seed, global_cell, salt + index * 2 + 1, 8, 92))
	)

func _terrain_representation(cells: Array[Dictionary]) -> String:
	var rows: Array[String] = []
	for cell: Dictionary in cells:
		var row: String = "%d,%d|t%d|e%d|m%d|rv%d|rd%d|x%d" % [
			(cell["global_region_cell"] as Vector2i).x,
			(cell["global_region_cell"] as Vector2i).y,
			int(cell["terrain_type"]),
			roundi(float(cell["elevation"]) * 10_000.0),
			roundi(float(cell["moisture"]) * 10_000.0),
			roundi(float(cell["river_strength"]) * 10_000.0),
			1 if bool(cell["road"]) else 0,
			1 if bool(cell["river_crossing"]) else 0,
		]
		row += "|ro%s|ri%s" % [
			_offset_representation(cell["road_connection_offsets"] as Array),
			_offset_representation(cell["river_connection_offsets"] as Array),
		]
		var details: Dictionary = cell["details"] as Dictionary
		for key: String in ["clearing_center_meters", "trees", "bushes", "grass", "rocks"]:
			if details.has(key):
				row += "|%s=%s" % [key, _detail_representation(details[key])]
		rows.append(row)
	return "\n".join(rows)

func _preview_representation(
		context: BattleSiteContext,
		attacker_deployment: Dictionary,
		defender_deployment: Dictionary
	) -> String:
	return "%s|a%d,%d,%s,%s|d%d,%d,%s,%s" % [
		context.battle_id,
		int(attacker_deployment["initial_deployed_personnel"]),
		int(attacker_deployment["reserve_personnel"]),
		_detail_representation(attacker_deployment["marker_positions_meters"]),
		_detail_representation(attacker_deployment.get("marker_personnel", [])),
		int(defender_deployment["initial_deployed_personnel"]),
		int(defender_deployment["reserve_personnel"]),
		_detail_representation(defender_deployment["marker_positions_meters"]),
		_detail_representation(defender_deployment.get("marker_personnel", [])),
	]

func _offset_representation(offsets: Array) -> String:
	var values: Array[String] = []
	for value: Variant in offsets:
		if value is Vector2i:
			var offset: Vector2i = value as Vector2i
			values.append("%d,%d" % [offset.x, offset.y])
	return ";".join(values)

func _detail_representation(value: Variant) -> String:
	if value is Vector2 or value is Vector2i:
		var point: Vector2 = Vector2(value)
		return "%d,%d" % [roundi(point.x), roundi(point.y)]
	if value is Array:
		var values: Array[String] = []
		for item: Variant in value:
			values.append(_detail_representation(item))
		return ";".join(values)
	return str(value)
