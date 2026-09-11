class_name SiteEnvironment
extends RefCounted

const VERSION := 1
enum Kind { TIMBER, STONE, CLAY, IRON, SALT, FOOD, HERB, FISH, WILDLIFE }
const NAMES := ["林木", "石料", "黏土", "鐵礦", "鹽源", "野生食物", "藥用植物", "漁業資源", "野生動物"]
const ITEMS := ["wood", "stone", "clay", "iron_ore", "brine", "wild_food", "herb", "fish", "meat"]
const ITEM_NAMES := {
	"wood": "木材", "stone": "石材", "clay": "黏土", "iron_ore": "鐵礦石", "brine": "鹵水", "salt": "食鹽",
	"wild_food": "採集食物", "herb": "藥材", "fish": "魚", "meat": "肉", "hide": "生皮", "tools": "工具",
	"seeds": "種子", "grain": "糧食", "fiber": "植物纖維", "fodder": "飼料", "charcoal": "木炭",
	"brick": "磚瓦", "iron": "鐵料", "cloth": "布料", "leather": "皮革", "wool": "羊毛", "sheep": "羊", "horse": "馬匹",
}
const WORK_MINUTES := [5.0, 4.0, 3.0, 6.0, 2.0, 2.0, 3.0, 4.0, 6.0]
const BATCH := [4, 3, 3, 2, 2, 3, 2, 2, 1]
# Deliberately compressed gameplay cycles, expressed in game minutes.
const RECOVERY := [10080, 0, 0, 0, 0, 720, 1440, 120, 1440]
const COLORS := [Color("386440"), Color("969b9b"), Color("cb7957"), Color("934b38"), Color("e7e7c8"), Color("d8b444"), Color("ba8cd9"), Color("57bed1"), Color("b78b62")]

static func initialize(data: TerrainData, site_id: String = "") -> void:
	var count := data.size.x * data.size.y
	data.fertility.resize(count)
	data.moisture.resize(count)
	data.drainage.resize(count)
	data.foundation.resize(count)
	data.groundwater.resize(count)
	data.water_kind.resize(count)
	data.water_kind.fill(0)
	data.water_body.resize(count)
	data.water_body.fill(-1)
	data.static_blocked.resize(count)
	data.static_blocked.fill(0)
	data.feature_at.resize(count)
	data.feature_at.fill(0)
	data.resource_base.clear()
	data.resources_at.clear()
	_generate_water(data)
	_generate_soil(data)
	_generate_resources(data)
	data.site = {
		"id": site_id if not site_id.is_empty() else "site-%d-%d" % [Time.get_ticks_usec(), randi()],
		"minute": 0, "phase": 0.0, "paused": false, "combat_left": 0.0,
		"changes": {}, "features": {}, "terrain_changes": {}, "zones": [], "next_feature": 1,
		"inventory": {"wood": 40, "stone": 30, "clay": 20, "tools": 4, "seeds": 12, "grain": 30, "fodder": 20, "sheep": 2, "horse": 2},
		"capacity": 800, "depot_cell": data.index(data.spawn_cell),
		"worker": {"zone": -1, "target": "", "mode": "idle", "progress": 0.0, "cargo": {}, "status": "待命", "cell": data.index(data.spawn_cell)},
		"manual": {"target": "", "progress": 0.0, "action": "harvest", "cargo": {}},
		"water_status": {}, "water_links": {}, "total_produced": 0, "notices": [],
	}
	rebuild_indexes(data)
	_preserve_connectivity(data)
	rebuild_indexes(data)

static func _generate_water(data: TerrainData) -> void:
	var sea := data.preset in [TerrainPreset.Kind.COASTAL_CLIFF, TerrainPreset.Kind.ISLAND]
	for i: int in range(data.surface_types.size()):
		if data.surface_types[i] != TerrainData.Surface.WATER or data.water_body[i] >= 0:
			continue
		var pending: Array[int] = [i]
		data.water_body[i] = i
		var head := 0
		while head < pending.size():
			var current := pending[head]
			head += 1
			data.water_kind[current] = 2 if sea else 1
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var next := data.cell_from_index(current) + direction
				if not data.contains(next):
					continue
				var j := data.index(next)
				if data.surface_types[j] == TerrainData.Surface.WATER and data.water_body[j] < 0:
					data.water_body[j] = i
					pending.append(j)

static func _generate_soil(data: TerrainData) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = int((data.seed_value + 19391) & 0x7fffffff)
	noise.frequency = 0.07
	var wet_distance := PackedInt32Array()
	wet_distance.resize(data.surface_types.size())
	wet_distance.fill(20)
	var pending: Array[int] = []
	for i: int in range(wet_distance.size()):
		if data.water_kind[i] != 0:
			wet_distance[i] = 0
			pending.append(i)
	var head := 0
	while head < pending.size():
		var current := pending[head]
		head += 1
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := data.cell_from_index(current) + direction
			if not data.contains(next):
				continue
			var j := data.index(next)
			if wet_distance[j] > wet_distance[current] + 1:
				wet_distance[j] = wet_distance[current] + 1
				pending.append(j)
	for i: int in range(data.surface_types.size()):
		var cell := data.cell_from_index(i)
		var variation := int(noise.get_noise_2d(cell.x, cell.y) * 35.0)
		var surface := int(data.surface_types[i])
		data.fertility[i] = clampi(62 + variation, 15, 95)
		data.moisture[i] = clampi(75 - wet_distance[i] * 2 + variation, 10, 95)
		data.drainage[i] = clampi(68 + variation, 25, 90)
		data.foundation[i] = clampi(75 + variation, 40, 95)
		data.groundwater[i] = clampi(65 - int(data.height_levels[i]) * 7 + variation, 10, 90)
		if surface == TerrainData.Surface.ROCK:
			data.fertility[i] = 10
			data.foundation[i] = 90
		elif surface == TerrainData.Surface.SAND:
			data.fertility[i] = 18
			data.foundation[i] = 32
			data.groundwater[i] = 15
		elif surface == TerrainData.Surface.WETLAND:
			data.moisture[i] = 95
			data.drainage[i] = 15
			data.foundation[i] = 15
		if surface == TerrainData.Surface.WATER:
			data.fertility[i] = 0
			data.foundation[i] = 0
			data.groundwater[i] = 0

static func _generate_resources(data: TerrainData) -> void:
	for kind: int in range(NAMES.size()):
		var rng := RandomNumberGenerator.new()
		rng.seed = data.seed_value + 104729 * (kind + 1)
		var mineral_site := kind != Kind.IRON or posmod(data.seed_value + data.preset, 3) != 0
		var inland_salt := kind == Kind.SALT and posmod(data.seed_value + data.preset, 5) == 0
		for y: int in range(1, data.size.y - 1):
			for x: int in range(1, data.size.x - 1):
				var cell := Vector2i(x, y)
				var roll := rng.randf()
				var i := data.index(cell)
				var surface := int(data.surface_types[i])
				var chance := 0.0
				match kind:
					Kind.TIMBER:
						chance = 0.11 if surface == TerrainData.Surface.FOREST_GROUND else (0.018 if surface == TerrainData.Surface.GRASS else 0.0)
					Kind.STONE:
						chance = 0.018 if surface == TerrainData.Surface.ROCK else (0.0016 if data.is_terrain_walkable(cell) else 0.0)
					Kind.CLAY:
						chance = 0.012 if surface == TerrainData.Surface.WETLAND else (0.0009 if surface in [TerrainData.Surface.GRASS, TerrainData.Surface.DIRT] else 0.0)
					Kind.IRON:
						chance = (0.007 if surface == TerrainData.Surface.ROCK else 0.00045) if mineral_site and data.is_terrain_walkable(cell) else 0.0
					Kind.SALT:
						chance = 0.008 if data.water_kind[i] == 2 and _shore_work_cell(data, cell) != -1 else (0.00045 if inland_salt and data.is_terrain_walkable(cell) else 0.0)
					Kind.FOOD:
						chance = 0.012 if data.fertility[i] > 45 and data.is_terrain_walkable(cell) else 0.0
					Kind.HERB:
						chance = 0.006 if data.moisture[i] > 42 and data.is_terrain_walkable(cell) else 0.0
					Kind.FISH:
						chance = 0.02 if data.water_kind[i] in [1, 2] and _shore_work_cell(data, cell) != -1 else 0.0
					Kind.WILDLIFE:
						chance = 0.0014 if surface in [TerrainData.Surface.FOREST_GROUND, TerrainData.Surface.GRASS] else 0.0
				if roll >= chance:
					continue
				if kind in [Kind.TIMBER, Kind.STONE] and _protected_cell(data, cell):
					continue
				var capacity := rng.randi_range(20, 48)
				if kind in [Kind.STONE, Kind.CLAY, Kind.IRON]:
					capacity = rng.randi_range(90, 320)
				elif kind == Kind.WILDLIFE:
					capacity = rng.randi_range(2, 5)
				elif kind == Kind.FISH:
					capacity = rng.randi_range(10, 24)
				elif kind == Kind.SALT:
					capacity = 3
				_add_resource(data, kind, i, capacity, rng.randi_range(0, 2))
	# A tiny deterministic starter patch is part of generation, never a load-time refill.
	for kind: int in [Kind.TIMBER, Kind.STONE, Kind.FOOD, Kind.HERB]:
		var rng := RandomNumberGenerator.new()
		rng.seed = data.seed_value + 73013 + kind
		for _attempt: int in range(64):
			var cell := data.spawn_cell + Vector2i(rng.randi_range(-12, 12), rng.randi_range(-12, 12))
			if not data.is_terrain_walkable(cell) or _protected_cell(data, cell):
				continue
			if data.path_between(data.spawn_cell, cell).is_empty():
				continue
			_add_resource(data, kind, data.index(cell), 24 if kind != Kind.STONE else 120, 0)
			break

static func _add_resource(data: TerrainData, kind: int, cell_index: int, capacity: int, variant: int) -> void:
	var key := "%d:%d" % [kind, cell_index]
	if kind == Kind.SALT and data.water_kind[cell_index] == 0:
		data.water_kind[cell_index] = 3
		data.groundwater[cell_index] = 0
	# Multi-cell deposits use an area for display/work selection and one shared stock.
	var cells: Array[int] = [cell_index]
	if kind in [Kind.CLAY, Kind.IRON, Kind.FISH, Kind.WILDLIFE]:
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var candidate := data.cell_from_index(cell_index) + direction
			if data.contains(candidate):
				var j := data.index(candidate)
				if (kind == Kind.FISH and data.water_body[j] == data.water_body[cell_index]) \
					or (kind != Kind.FISH and data.is_terrain_walkable(candidate)):
					cells.append(j)
	data.resource_base[key] = {"kind": kind, "cell": cell_index, "cells": cells, "capacity": capacity, "variant": variant,
		"water": int(data.water_body[cell_index]), "blocks": kind in [Kind.TIMBER, Kind.STONE], "recover": int(RECOVERY[kind])}

static func _protected_cell(data: TerrainData, cell: Vector2i) -> bool:
	if Vector2(cell - data.spawn_cell).length() < 6.0:
		return true
	for direction: Vector2i in [Vector2i.ZERO, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var neighbor := cell + direction
		if data.contains(neighbor) and data.ramp_edges[data.index(neighbor)] != 0:
			return true
	return false

static func _shore_work_cell(data: TerrainData, cell: Vector2i) -> int:
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var shore := cell + direction
		if data.is_terrain_walkable(shore) and data.height_levels[data.index(shore)] == data.height_levels[data.index(cell)]:
			return data.index(shore)
	return -1

static func resource(data: TerrainData, key: String) -> Dictionary:
	if not data.resource_base.has(key):
		return {}
	var result: Dictionary = data.resource_base[key].duplicate()
	result["remaining"] = int(result.capacity)
	result["discovered"] = int(result.kind) != Kind.IRON
	result["cleared"] = false
	result["next_recovery"] = -1
	result.merge(data.site.get("changes", {}).get(key, {}), true)
	result["id"] = key
	return result

static func change(data: TerrainData, key: String, fields: Dictionary) -> void:
	if not data.resource_base.has(key):
		return
	if not data.site.changes.has(key):
		data.site.changes[key] = {}
	data.site.changes[key].merge(fields, true)
	data.environment_revision += 1

static func resources_in(data: TerrainData, area: Rect2i, kind: int = -1) -> Array[String]:
	var found: Array[String] = []
	var bounded := area.intersection(Rect2i(Vector2i.ZERO, data.size))
	for y: int in range(bounded.position.y, bounded.end.y):
		for x: int in range(bounded.position.x, bounded.end.x):
			for key: String in data.resources_at.get(data.index(Vector2i(x, y)), []):
				if not found.has(key) and (kind < 0 or int(data.resource_base[key].kind) == kind):
					found.append(key)
	found.sort()
	return found

static func rebuild_indexes(data: TerrainData) -> void:
	var before := data.static_blocked.duplicate()
	data.static_blocked.fill(0)
	data.feature_at.fill(0)
	data.resources_at.clear()
	for key: String in data.resource_base:
		var r := resource(data, key)
		for i: int in r.cells:
			if not data.resources_at.has(i):
				data.resources_at[i] = []
			data.resources_at[i].append(key)
		if bool(r.blocks) and int(r.remaining) > 0 and not bool(r.cleared):
			data.static_blocked[int(r.cell)] = 1
	for key: String in data.site.get("features", {}):
		var feature: Dictionary = data.site.features[key]
		for i: int in feature.cells:
			data.feature_at[i] = int(key)
			if bool(feature.get("solid", false)) and str(feature.stage) == "complete":
				data.static_blocked[i] = 1
	if before != data.static_blocked:
		data.navigation_revision += 1
	data.environment_revision += 1

static func _preserve_connectivity(data: TerrainData) -> void:
	# Remove only blocking generated objects that split an originally connected platform.
	var labels := PackedInt32Array()
	labels.resize(data.surface_types.size())
	labels.fill(-1)
	for start: int in range(labels.size()):
		if labels[start] >= 0 or not data.is_terrain_walkable(data.cell_from_index(start)):
			continue
		var component: Array[int] = [start]
		labels[start] = start
		var head := 0
		while head < component.size():
			var current := component[head]
			head += 1
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var next := data.cell_from_index(current) + direction
				if data.can_terrain_step(data.cell_from_index(current), next) and labels[data.index(next)] < 0:
					labels[data.index(next)] = start
					component.append(data.index(next))
		var origin := -1
		for i: int in component:
			if data.static_blocked[i] == 0:
				origin = i
				break
		if origin < 0:
			continue
		var reached := {origin: true}
		var queue: Array[int] = [origin]
		var barriers: Array[int] = []
		head = 0
		while true:
			while head < queue.size():
				var current := queue[head]
				head += 1
				for direction: Vector2i in TerrainData.DIRECTIONS:
					var next := data.cell_from_index(current) + direction
					if not data.can_terrain_step(data.cell_from_index(current), next):
						continue
					var j := data.index(next)
					if reached.has(j):
						continue
					if data.static_blocked[j] != 0:
						if not barriers.has(j):
							barriers.append(j)
						continue
					reached[j] = true
					queue.append(j)
			var missing := false
			for i: int in component:
				if data.static_blocked[i] == 0 and not reached.has(i):
					missing = true
					break
			if not missing or barriers.is_empty():
				break
			var opening: int = barriers.pop_front()
			for key: String in data.resources_at.get(opening, []):
				if bool(data.resource_base[key].blocks) and int(data.resource_base[key].cell) == opening:
					data.resource_base.erase(key)
			data.static_blocked[opening] = 0
			reached[opening] = true
			queue.append(opening)

static func work_cells(data: TerrainData, key: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var r := resource(data, key)
	if r.is_empty():
		return result
	for i: int in r.cells:
		var target := data.cell_from_index(i)
		for direction: Vector2i in [Vector2i.ZERO, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var cell := target + direction
			if not data.is_walkable(cell) or data.feature_at[data.index(cell)] != 0:
				continue
			if direction != Vector2i.ZERO and data.is_terrain_walkable(target) and not data.can_terrain_step(cell, target):
				continue
			if data.water_kind[i] != 0 and data.height_levels[data.index(cell)] != data.height_levels[i]:
				continue
			if not result.has(cell):
				result.append(cell)
	return result

static func land(data: TerrainData, cell: Vector2i) -> Dictionary:
	if not data.contains(cell) or data.fertility.is_empty():
		return {"farm": 0, "pasture": 0, "water": 0, "build": 0, "reasons": ["地圖外"], "potential_farm": 0}
	var i := data.index(cell)
	var reasons: Array[String] = []
	var farm := mini(int(data.fertility[i]), int(data.drainage[i]) + 25)
	var pasture := mini(int(data.fertility[i]) + 10, int(data.moisture[i]) + 20)
	var build := int(data.foundation[i])
	var potential := farm
	if not data.is_terrain_walkable(cell):
		farm = 0
		pasture = 0
		build = 0
		potential = 0
		reasons.append("水面，不是一般建築用地")
	if data.drainage[i] < 30 and data.is_terrain_walkable(cell):
		farm = 0
		potential = 0
		reasons.append("排水不良")
	if data.ramp_edges[i] != 0:
		build = 0
		reasons.append("保留坡口；僅接受道路／整地")
	if data.feature_at[i] != 0 or i == int(data.site.depot_cell):
		farm = 0
		pasture = 0
		build = 0
		reasons.append("營地使用" if i == int(data.site.depot_cell) else "人工用地已占用")
	for key: String in data.resources_at.get(i, []):
		var r := resource(data, key)
		if int(r.cell) == i and not bool(r.cleared) and int(r.kind) in [Kind.TIMBER, Kind.STONE]:
			farm = 0
			pasture = maxi(0, pasture - 40)
			reasons.append("需清除樹根／石塊" if int(r.remaining) == 0 else "需採伐／清理")
	var supplied := 0.0
	for source_key: String in data.site.get("water_links", {}):
		if data.site.water_links[source_key].has(i):
			supplied += 1.0
	if supplied == 0.0 and data.is_terrain_walkable(cell):
		reasons.append("尚無取水服務")
	return {"farm": farm, "potential_farm": potential, "pasture": pasture, "water": 100 if supplied > 0 else 0,
		"build": build, "reasons": reasons, "groundwater": int(data.groundwater[i]), "fertility": int(data.fertility[i]),
		"moisture": int(data.moisture[i]), "foundation": int(data.foundation[i])}

static func habitat_capacity(data: TerrainData, key: String) -> int:
	var r := resource(data, key)
	if r.is_empty():
		return 0
	var usable := 0
	for i: int in r.cells:
		if data.feature_at[i] == 0:
			usable += 1
	return floori(float(r.capacity) * float(usable) / float(r.cells.size()))

static func land_summary(data: TerrainData, area: Rect2i) -> Dictionary:
	var bounded := area.intersection(Rect2i(Vector2i.ZERO, data.size))
	var result := {"cells": bounded.get_area(), "farm_cells": 0, "pasture_capacity": 0, "water_cells": 0, "build_cells": 0}
	for y: int in range(bounded.position.y, bounded.end.y):
		for x: int in range(bounded.position.x, bounded.end.x):
			var condition := land(data, Vector2i(x, y))
			result.farm_cells += int(int(condition.farm) >= 30)
			result.pasture_capacity += floori(float(condition.pasture) / 30.0)
			result.water_cells += int(int(condition.water) > 0)
			result.build_cells += int(int(condition.build) >= 35)
	return result
