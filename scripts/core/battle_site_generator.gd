class_name BattleSiteGenerator
extends RefCounted

const FOREST_TREE_COUNT: int = 16
const FOREST_BUSH_COUNT: int = 6
const PLAINS_GRASS_COUNT: int = 10
const MOUNTAIN_ROCK_COUNT: int = 10
const CLEARING_SALT: int = 61_001
const TREE_SALT: int = 61_101
const BUSH_SALT: int = 61_201
const GRASS_SALT: int = 61_301
const ROCK_SALT: int = 61_401
const CORRIDOR_SALT: int = 61_501

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
	for resolved_cell: Dictionary in resolved_cells:
		var generated_cell: Dictionary = _generate_cell(context, resolved_cell)
		if generated_cell.is_empty():
			return {}
		cells.append(generated_cell)
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
	var terrain_representation: String = _terrain_representation(cells)
	var preview_representation: String = _preview_representation(
		context,
		attacker_deployment,
		defender_deployment
	)
	return {
		"context": context,
		"footprint_cells": cells,
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
	var local_origin: Vector2 = battle_local_origin_for(
		global_cell,
		context.center_global_region_cell
	)
	var road_offsets: Array[Vector2i] = _copy_offsets(
		resolved_cell.get("road_connection_offsets", []) as Array
	)
	if has_road and road_offsets.is_empty():
		_append_fallback_corridor(road_offsets, context, global_cell, CORRIDOR_SALT)
	var river_offsets: Array[Vector2i] = _copy_offsets(
		resolved_cell.get("river_connection_offsets", []) as Array
	)
	if has_river and river_offsets.is_empty():
		_append_fallback_corridor(river_offsets, context, global_cell, CORRIDOR_SALT + 1)
	return {
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
		"details": _generate_details(
			context,
			global_cell,
			local_origin,
			terrain_type,
			has_road or has_river
		),
	}

func _copy_offsets(source: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for value: Variant in source:
		if value is Vector2i:
			_append_unique_offset(result, value as Vector2i)
	result.sort_custom(Callable(self, "_offset_less"))
	return result

func _append_unique_offset(result: Array[Vector2i], delta: Vector2i) -> void:
	var offset: Vector2i = Vector2i(
		clampi(delta.x, -1, 1),
		clampi(delta.y, -1, 1)
	)
	if offset != Vector2i.ZERO and not result.has(offset):
		result.append(offset)

func _append_fallback_corridor(
		result: Array[Vector2i],
		context: BattleSiteContext,
		global_cell: Vector2i,
		salt: int
	) -> void:
	if DeterministicHash.value(context.battle_seed, global_cell, salt) % 2 == 0:
		result.append(Vector2i(-1, 0))
		result.append(Vector2i(1, 0))
	else:
		result.append(Vector2i(0, -1))
		result.append(Vector2i(0, 1))

func _generate_details(
		context: BattleSiteContext,
		global_cell: Vector2i,
		local_origin: Vector2,
		terrain_type: int,
		has_corridor: bool
	) -> Dictionary:
	var details: Dictionary = {}
	match terrain_type:
		TerrainType.FOREST:
			var clearing_local: Vector2 = _detail_point(context, global_cell, CLEARING_SALT, 0)
			details["clearing_center_meters"] = local_origin + clearing_local
			details["trees"] = _detail_points(
				context, global_cell, local_origin, TREE_SALT, FOREST_TREE_COUNT,
				clearing_local, 18.0, has_corridor
			)
			details["bushes"] = _detail_points(
				context, global_cell, local_origin, BUSH_SALT, FOREST_BUSH_COUNT,
				clearing_local, 13.0, has_corridor
			)
		TerrainType.PLAINS:
			details["grass"] = _detail_points(
				context, global_cell, local_origin, GRASS_SALT, PLAINS_GRASS_COUNT,
				Vector2(-1000.0, -1000.0), 0.0, has_corridor
			)
		TerrainType.MOUNTAIN:
			details["rocks"] = _detail_points(
				context, global_cell, local_origin, ROCK_SALT, MOUNTAIN_ROCK_COUNT,
				Vector2(-1000.0, -1000.0), 0.0, has_corridor
			)
	return details

func _detail_points(
		context: BattleSiteContext,
		global_cell: Vector2i,
		local_origin: Vector2,
		salt: int,
		count: int,
		clearing_local: Vector2,
		clearing_radius: float,
		has_corridor: bool
	) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for attempt: int in range(count * 3):
		var local_point: Vector2 = _detail_point(context, global_cell, salt, attempt)
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
		salt: int,
		index: int
	) -> Vector2:
	var feature_seed: int = DeterministicHash.value(
		context.world_seed,
		global_cell,
		context.battle_seed + salt
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
	return "%s|a%d,%d,%s|d%d,%d,%s" % [
		context.battle_id,
		int(attacker_deployment["initial_deployed_personnel"]),
		int(attacker_deployment["reserve_personnel"]),
		_detail_representation(attacker_deployment["marker_positions_meters"]),
		int(defender_deployment["initial_deployed_personnel"]),
		int(defender_deployment["reserve_personnel"]),
		_detail_representation(defender_deployment["marker_positions_meters"]),
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

func _offset_less(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
