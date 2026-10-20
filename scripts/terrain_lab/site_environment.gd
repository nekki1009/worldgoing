class_name SiteEnvironment
extends RefCounted

const VERSION := 1
const FIXED_RESOURCE_RULE := "osm_landcover_resources_v1"
enum Kind { TIMBER, STONE, CLAY, IRON, SALT, FOOD, HERB, FISH, WILDLIFE }
const NAMES := ["林木", "石料", "黏土", "鐵礦", "鹽源", "野生食物", "藥用植物", "漁業資源", "野生動物"]
const ITEMS := ["wood", "stone", "clay", "iron_ore", "brine", "wild_food", "herb", "fish", "meat"]
const ITEM_NAMES := {
	"wood": "木材", "stone": "石材", "clay": "黏土", "iron_ore": "鐵礦石", "brine": "鹵水", "salt": "食鹽",
	"wild_food": "採集食物", "herb": "藥材", "fish": "魚", "meat": "肉", "hide": "生皮", "tools": "工具",
	"seeds": "種子", "grain": "糧食", "fiber": "植物纖維", "fodder": "飼料", "charcoal": "木炭",
	"pottery": "陶器", "steel": "鋼料", "rope": "繩索",
	"brick": "磚瓦", "iron": "鐵料", "cloth": "布料", "leather": "皮革", "wool": "羊毛", "sheep": "羊", "horse": "馬匹",
	"arrow": "箭", "fire_arrow": "火箭", "bolt": "弩矢", "siege_bolt": "重弩矢", "siege_stone": "石彈", "camp_tent": "營帳包",
	"fire_pot": "火罐", "ballista_spares": "弩砲備件", "coin": "通用幣",
}
const WORK_MINUTES := [5.0, 4.0, 3.0, 6.0, 2.0, 2.0, 3.0, 4.0, 6.0]
const BATCH := [4, 3, 3, 2, 2, 3, 2, 2, 1]
# Deliberately compressed gameplay cycles, expressed in game minutes.
const RECOVERY := [10080, 0, 0, 0, 0, 720, 1440, 120, 1440]
const ECOLOGY_VERSION := 1
const ECOLOGY_MODES := ["sustainable", "protected", "general"]
const ECOLOGY_KINDS := [Kind.TIMBER, Kind.FOOD, Kind.HERB, Kind.FISH, Kind.WILDLIFE]
const RESTORABLE_KINDS := [Kind.TIMBER, Kind.FOOD, Kind.HERB]
const POPULATION_KINDS := [Kind.FISH, Kind.WILDLIFE]
const COLORS := [Color("386440"), Color("969b9b"), Color("cb7957"), Color("934b38"), Color("e7e7c8"), Color("d8b444"), Color("ba8cd9"), Color("57bed1"), Color("b78b62")]

const WILDLIFE_SPECIES := [["stag", "horse"], ["boar", "boar"], ["doe", "sheep"]]
const WILDLIFE_NAMES := {"stag": "有角鹿", "boar": "野豬", "doe": "無角鹿", "horse": "野馬", "sheep": "羊"}

static func wildlife_species(variant: int, source_cell: int) -> String:
	# Source identity is immutable; stock, animation and refresh never change species.
	return WILDLIFE_SPECIES[posmod(variant, 3)][posmod(source_cell, 2)]

static func _prepare_initialize(data: TerrainData) -> bool:
	var count := data.size.x * data.size.y
	var fixed_geography: bool = data.parameters.get("composition") == "fixed_geography" \
		and data.parameters.get("fixed_base") is Dictionary
	if fixed_geography:
		var base: Dictionary = data.parameters.fixed_base
		if base.has("land_condition_rule") != data.parameters.has("fixed_land_condition_rule") or base.get("land_condition_rule") != data.parameters.get("fixed_land_condition_rule") or base.has("land_condition_rule") and (not base.land_condition_rule is String or not data.parameters.fixed_land_condition_rule is String or base.land_condition_rule != "terrain_mapped_potential_v1"):
			push_error("Fixed source land-condition rule is invalid; original data retained")
			return false
	if fixed_geography and (data.water_kind.size() != count or data.water_body.size() != count):
		push_error("Fixed geography must supply its own water classification")
		return false
	if data.parameters.has("author_land_cells") and (not fixed_geography or not RegionTerrainAdapter.valid_author_identity(data.parameters.fixed_base, true)):
		push_error("Author land requires verified fixed author source; original data retained")
		return false
	if not author_land_valid(data.parameters.get("author_land_cells", {})):
		push_error("Invalid author land values; original candidate retained")
		return false
	if fixed_geography and not validate_resource_definitions(data, data.resource_base).ok:
		push_error("Invalid source resource definitions; original data retained")
		return false
	data.fertility.resize(count)
	data.moisture.resize(count)
	data.drainage.resize(count)
	data.foundation.resize(count)
	data.groundwater.resize(count)
	if not fixed_geography:
		data.water_kind.resize(count)
		data.water_kind.fill(0)
		data.water_body.resize(count)
		data.water_body.fill(-1)
	data.static_blocked.resize(count)
	data.static_blocked.fill(0)
	data.feature_at.resize(count)
	data.feature_at.fill(0)
	if not fixed_geography:
		data.resource_base.clear()
	data.resources_at.clear()
	return true

static func _initialize_atomic(data: TerrainData, site_id: String = "") -> void:
	if not _prepare_initialize(data): return
	var fixed_geography: bool = data.parameters.get("composition") == "fixed_geography" and data.parameters.get("fixed_base") is Dictionary
	if fixed_geography:
		# Keep resource_base supplied by the verified fixed-base loader. The
		# geography-only atlas leaves it empty; never generate deposits here.
		if data.parameters.get("fixed_land_condition_rule", "") == "terrain_mapped_potential_v1":
			_populate_soil_conditions(data, false) # Pinned game potential, never surveyed soil.
		else:
			data.fertility.fill(0)
			data.moisture.fill(0)
			data.drainage.fill(0)
			data.foundation.fill(0)
			data.groundwater.fill(0)
	else:
		_generate_water(data)
		_generate_soil(data)
		_generate_resources(data)
	restore_author_land(data)
	_initialize_state(data, site_id, fixed_geography)
	rebuild_indexes(data)
	if not fixed_geography:
		_preserve_connectivity(data)
		rebuild_indexes(data)

static func initialize(data: TerrainData, site_id: String = "") -> void:
	if data.parameters.get("composition") != "fixed_geography" or not data.parameters.get("fixed_base") is Dictionary:
		_initialize_atomic(data, site_id)
		return
	var job := begin_initialize(data, site_id)
	while not job.is_empty() and not bool(job.done):
		step_initialize(job, 0, 4096)

static func begin_initialize(data: TerrainData, site_id: String = "") -> Dictionary:
	if data.parameters.get("composition") != "fixed_geography" or not data.parameters.get("fixed_base") is Dictionary: return {}
	if not _prepare_initialize(data): return {}
	return {"data": data, "site_id": site_id, "stage": "soil", "soil": _begin_soil(data, false), "done": false}

static func step_initialize(job: Dictionary, budget_usec: int = 2000, max_units: int = 256) -> bool:
	if job.is_empty(): return false
	var started := Time.get_ticks_usec()
	for unit in range(maxi(1, max_units)):
		var data: TerrainData = job.data
		if job.stage == "soil":
			if data.parameters.get("fixed_land_condition_rule", "") != "terrain_mapped_potential_v1":
				data.fertility.fill(0); data.moisture.fill(0); data.drainage.fill(0)
				data.foundation.fill(0); data.groundwater.fill(0)
				job.stage = "state"
			elif _step_soil(data, job.soil): job.stage = "state"
		elif job.stage == "state":
			restore_author_land(data)
			_initialize_state(data, str(job.site_id), true)
			job.index = _begin_resource_index(data)
			job.stage = "index"
		elif job.stage == "index":
			if _step_resource_index(data, job.index):
				# Fresh initialization has no feature/vehicle geometry.
				_finish_index(data, job.index)
				job.done = true
				job.stage = "done"
		if bool(job.done): return true
		if budget_usec > 0 and Time.get_ticks_usec() - started >= budget_usec: break
	return false

static func _initialize_state(data: TerrainData, site_id: String, fixed_geography: bool) -> void:
	data.site = {
		"id": site_id if not site_id.is_empty() else "site-%d-%d" % [Time.get_ticks_usec(), randi()],
		"minute": 0, "phase": 0.0, "paused": false, "combat_left": 0.0, "ecology_version": ECOLOGY_VERSION,
		"changes": {}, "features": {}, "terrain_changes": {}, "zones": [], "next_feature": 1,
		"inventory": {} if fixed_geography else {"wood": 40, "stone": 30, "clay": 20, "tools": 4, "seeds": 12, "grain": 30, "fodder": 20, "sheep": 2, "horse": 2},
		"capacity": 800, "depot_cell": data.index(data.spawn_cell),
		"worker": {"zone": -1, "target": "", "mode": "idle", "progress": 0.0, "cargo": {}, "status": "待命", "cell": data.index(data.spawn_cell)},
		"manual": {"target": "", "progress": 0.0, "action": "harvest", "cargo": {}},
		"water_status": {}, "water_links": {}, "total_produced": 0, "notices": [],
	}

static func _begin_resource_index(data: TerrainData) -> Dictionary:
	var before := data.static_blocked.duplicate()
	var before_heights := data.walk_height_levels.duplicate()
	var before_ramps := data.walk_ramp_edges.duplicate()
	var before_facilities := data.facility_cells.duplicate()
	var before_bridge := data.bridge_walkable.duplicate()
	var count := data.size.x * data.size.y
	data.static_blocked.resize(count)
	data.static_blocked.fill(0)
	data.feature_at.resize(count)
	data.feature_at.fill(0)
	data.bridge_walkable.resize(count)
	data.bridge_walkable.fill(0)
	data.bridge_navigation_flags = PackedByteArray()
	data.walk_height_levels = data.height_levels.duplicate()
	data.walk_ramp_edges = data.ramp_edges.duplicate()
	data.has_raised_surfaces = false
	data.has_navigation_overrides = false
	data.facility_cells.resize(count)
	data.facility_cells.fill(0)
	data.resources_at.clear()
	return {"keys": data.resource_base.keys(), "key": 0, "cell": 0, "resource": {},
		"before": before, "before_heights": before_heights, "before_ramps": before_ramps,
		"before_facilities": before_facilities, "before_bridge": before_bridge}

static func _step_resource_index(data: TerrainData, job: Dictionary) -> bool:
	if int(job.key) >= job.keys.size(): return true
	var key: String = job.keys[int(job.key)]
	if job.resource.is_empty(): job.resource = resource(data, key)
	var r: Dictionary = job.resource
	if int(job.cell) < r.cells.size():
		var i := int(r.cells[int(job.cell)])
		if not data.resources_at.has(i): data.resources_at[i] = []
		data.resources_at[i].append(key)
		job.cell = int(job.cell) + 1
	else:
		if bool(r.blocks) and int(r.remaining) > 0 and not bool(r.cleared): data.static_blocked[int(r.cell)] = 1
		job.key = int(job.key) + 1; job.cell = 0; job.resource = {}
	return int(job.key) >= job.keys.size()

static func _finish_index(data: TerrainData, job: Dictionary) -> void:
	var before = job.before
	var before_heights = job.before_heights
	var before_ramps = job.before_ramps
	var before_facilities = job.before_facilities
	var before_bridge = job.before_bridge
	if before != data.static_blocked or before_heights != data.walk_height_levels or before_ramps != data.walk_ramp_edges or before_facilities != data.facility_cells or before_bridge != data.bridge_walkable:
		data.navigation_revision += 1
	data.environment_revision += 1


static func initialize_marine(data: TerrainData, site_id: String) -> Dictionary:
	if data == null or data.spawn_cell != Vector2i(-1, -1) or data.parameters.get("composition") != "fixed_geography" or not data.parameters.get("fixed_base") is Dictionary:
		return {"ok": false, "code": "NO_TARGET", "message": "海域候選須來自固定地理且沒有陸地落腳點"}
	var navigable := false
	for index in range(data.size.x * data.size.y):
		if data.can_navigate_water(data.cell_from_index(index)): navigable = true; break
	if not navigable: return {"ok": false, "code": "WATER", "message": "海域沒有明示可航許可"}
	initialize(data, site_id)
	data.site.marine = {"version": 1}
	data.site.actor_presence_version = 1
	data.site.actors = {}
	data.site.player_cell = -1
	data.site.depot_cell = -1
	data.site.worker.cell = -1
	data.site.worker_enabled = false
	return {"ok": true, "code": "OK", "message": "原固定海域 Site 已建立，沒有假陸地人物"}

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
	# Explicit game permission for this generated water rule, not inferred depth.
	# Callers may supply a narrower known rule; never broaden it on reinitialization.
	if not data.parameters.has("navigable_water_version"):
		var bodies: Array[int] = []
		for value: int in data.water_body:
			if value >= 0 and not bodies.has(value): bodies.append(value)
		bodies.sort()
		data.parameters.navigable_water_version = 1
		data.parameters.navigable_water_bodies = bodies
		data.parameters.navigable_water_source = "preset-water-rule-v1"

static func _generate_soil(data: TerrainData) -> void:
	_populate_soil_conditions(data, true)

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

static func populate_fixed_resources(data: TerrainData, cover: PackedByteArray, site_coord: Vector2i, absolute_height: PackedFloat32Array) -> void:
	# Mapped habitat controls eligibility; positions and stock are game rules,
	# not surveyed trees, wildlife counts, mineral reserves or starter supplies.
	assert(data.size == Vector2i(100, 100) and cover.size() == 100 and data.site.is_empty())
	assert(absolute_height.size() == 10000)
	data.resource_base.clear()
	data.static_blocked.resize(10000)
	data.feature_at.resize(10000)
	for y: int in range(100):
		for x: int in range(100):
			var cell := Vector2i(x, y)
			var i := data.index(cell)
			var habitat := int(cover[floori(float(y) / 10.0) * 10 + floori(float(x) / 10.0)])
			var global_cell := Vector2i(site_coord.x * 100 + x, site_coord.y * 100 + 99 - y)
			var chances: Dictionary = {}
			if data.water_kind[i] in [1, 2] and _shore_work_cell(data, cell) != -1:
				chances[Kind.FISH] = 180
				if data.water_kind[i] == 2:
					chances[Kind.SALT] = 60
			elif data.is_terrain_walkable(cell):
				match habitat:
					1: # Forest.
						chances = {Kind.TIMBER: 450, Kind.FOOD: 40, Kind.HERB: 45, Kind.WILDLIFE: 4}
					2: # Grass / meadow.
						chances = {Kind.FOOD: 60, Kind.HERB: 35, Kind.WILDLIFE: 2}
					3: # Scrub / heath.
						chances = {Kind.FOOD: 50, Kind.HERB: 50, Kind.WILDLIFE: 3}
					5: # Orchard: source indicates cultivated trees, no crop species.
						chances = {Kind.TIMBER: 180, Kind.FOOD: 80}
				# Taiwan alpine vegetation bands; see resource-manifest rule evidence.
				# Broad OSM forest polygons must not put timber trees on Yushan's summit.
				if habitat in [1, 2, 3, 5] and is_finite(absolute_height[i]):
					if absolute_height[i] >= 3850.0:
						chances = {Kind.FOOD: 10, Kind.HERB: 15}
					elif absolute_height[i] >= 3600.0:
						chances = {Kind.FOOD: 25, Kind.HERB: 35, Kind.WILDLIFE: 1}
			# Unknown, built-up, ordinary farmland and untyped quarries have no
			# invented wild deposits. A quarry label alone is not mineral evidence.
			for kind: int in chances:
				var roll := _fixed_resource_hash(global_cell, kind)
				if roll % 10000 >= int(chances[kind]):
					continue
				if kind == Kind.TIMBER and _protected_cell(data, cell):
					continue
				var stock_roll := floori(float(roll) / 10000.0)
				var capacity := 20 + stock_roll % 29
				if kind == Kind.WILDLIFE:
					capacity = 2 + stock_roll % 4
				elif kind == Kind.FISH:
					capacity = 10 + stock_roll % 15
				elif kind == Kind.SALT:
					capacity = 3
				_add_resource(data, kind, i, capacity, roll % 3)
	# Reuse the existing connectivity repair before publishing the immutable base.
	# No mutable Site, inventory or persons are created for a map preview.
	rebuild_indexes(data)
	if data.static_blocked.has(1):
		var generated_count := data.resource_base.size()
		_preserve_connectivity(data)
		if data.resource_base.size() != generated_count:
			rebuild_indexes(data)

static func _fixed_resource_hash(cell: Vector2i, kind: int) -> int:
	var value := ((cell.x * 73856093) ^ (cell.y * 19349663) ^ ((kind + 1) * 83492791)) & 0x7fffffff
	return ((value ^ (value >> 13)) * 1274126177) & 0x7fffffff

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

static func ecology_active(data: TerrainData) -> bool:
	return data != null and data.site.get("ecology_version", 0) == ECOLOGY_VERSION

static func ecology_resting(remaining: int, capacity: int, previous: Variant = null) -> bool:
	if capacity <= 1: return true
	var reserve := maxi(1, ceili(float(capacity) * 0.2))
	var resume := mini(capacity, maxi(reserve + 1, ceili(float(capacity) * 0.5)))
	if remaining <= reserve: return true
	if remaining >= resume: return false
	return bool(previous) if previous is bool else true

static func ecology_cell_usable(data: TerrainData, resource_value: Dictionary, index: int) -> bool:
	if index < 0 or index >= data.feature_at.size() or data.feature_at[index] != 0: return false
	if int(resource_value.kind) == Kind.FISH:
		return data.water_kind[index] in [1, 2] and data.water_body[index] == int(resource_value.water)
	return data.is_terrain_walkable(data.cell_from_index(index))

static func ecology_info(data: TerrainData, key: String) -> Dictionary:
	if data == null: return {}
	var r := resource(data, key)
	if r.is_empty(): return {}
	var kind := int(r.kind)
	var admitted := ecology_active(data)
	var biological: bool = kind in ECOLOGY_KINDS
	var renewable: bool = biological and int(r.recover) > 0
	var population := kind in POPULATION_KINDS
	var potential_capacity := habitat_capacity(data, key)
	var capacity := 0 if bool(r.cleared) and kind in RESTORABLE_KINDS else potential_capacity
	var remaining := int(r.remaining)
	var mode: String = str(r.get("eco_mode", "sustainable")) if admitted and biological else "general"
	var reserve := maxi(1, ceili(float(capacity) * 0.2)) if population else 0
	var resume := mini(capacity, maxi(reserve + 1, ceili(float(capacity) * 0.5))) if population else capacity
	var resting := bool(r.eco_resting) if r.get("eco_resting") is bool else ecology_resting(remaining, capacity)
	var reason := ""
	if bool(r.cleared): reason = "CLEARED"
	elif not biological: reason = "FINITE" if kind != Kind.SALT else "SUPPLY"
	elif capacity <= 0: reason = "NO_HABITAT"
	elif (not admitted or not population) and data.feature_at[int(r.cell)] != 0: reason = "OCCUPIED"
	elif admitted and population and work_cells(data, key).is_empty(): reason = "NO_WORK_CELL"
	elif kind == Kind.TIMBER and SiteRuntime._fire_regeneration_blocked(data, key): reason = "FIRE_HOT"
	elif not renewable: reason = "FINITE"
	var takeable := remaining
	if bool(r.cleared) or (biological and reason in ["NO_HABITAT", "OCCUPIED", "NO_WORK_CELL"]): takeable = 0
	if admitted and biological:
		if mode == "protected": takeable = 0
		elif population and mode == "sustainable": takeable = 0 if resting or capacity <= 1 else maxi(0, takeable - reserve)
	var at := float(data.site.get("minute", 0)) + float(data.site.get("phase", 0.0))
	var deadline := int(r.next_recovery)
	return {"key": key, "kind": kind, "admitted": admitted, "renewable": renewable, "population": population,
		"mode": mode, "resting": resting if admitted and population else false, "remaining": remaining,
		"capacity": capacity, "base_capacity": int(r.capacity), "potential_capacity": potential_capacity, "reserve": reserve, "resume": resume,
		"takeable": takeable, "batch_takeable": mini(int(BATCH[kind]), takeable), "cleared": bool(r.cleared),
		"recoverable": renewable and reason.is_empty(), "recovery_blocked": reason,
		"recovery_minutes": int(r.recover), "next_recovery": deadline,
		"wait_minutes": maxf(0.0, float(deadline) - at) if deadline >= 0 else -1.0,
		"recovery_amount": (1 if population else maxi(0, capacity - remaining)) if renewable else 0,
		"restorable": admitted and renewable and kind in RESTORABLE_KINDS and bool(r.cleared) and remaining == 0 and ecology_cell_usable(data, r, int(r.cell))
			and SiteRuntime._fire_resource_restored(data, key, true).ok}

static func change(data: TerrainData, key: String, fields: Dictionary) -> void:
	if not data.resource_base.has(key): return
	var committed := fields.duplicate()
	if ecology_active(data) and int(data.resource_base[key].kind) in POPULATION_KINDS and (fields.has("remaining") or fields.has("eco_mode") or fields.has("next_recovery") or fields.has("cleared")):
		var before := resource(data, key)
		var capacity := habitat_capacity(data, key)
		var previous: Variant = before.get("eco_resting", ecology_resting(int(before.remaining), capacity))
		committed["eco_resting"] = ecology_resting(int(fields.get("remaining", before.remaining)), capacity, previous)
	if not data.site.changes.has(key): data.site.changes[key] = {}
	data.site.changes[key].merge(committed, true)
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
	var index_job := _begin_resource_index(data)
	while not _step_resource_index(data, index_job): pass
	var count := data.size.x * data.size.y
	var geometries: Array[Dictionary] = []
	for key: String in data.site.get("features", {}):
		var feature: Dictionary = data.site.features[key]
		for i: int in feature.cells:
			data.feature_at[i] = int(key)
			if int(feature.get("layout_version", 0)) == 0 and bool(feature.get("solid", false)) and str(feature.stage) == "complete":
				data.static_blocked[i] = 1
		for i: int in feature.get("pending_build", {}).get("added_cells", []):
			data.feature_at[i] = int(key)
		if str(feature.stage) != "complete": continue
		if str(feature.kind) == "fighting_position":
			for i: int in feature.cells: data.facility_cells[i] = 1
		if int(feature.get("layout_version", 0)) == 0: continue
		var geometry: Dictionary = SiteRuntime.feature_geometry(data, feature)
		geometries.append(geometry)
		for i: int in geometry.get("bridge_walkable", []): data.bridge_walkable[i] = 1
		for i: int in geometry.get("blocked", []): data.static_blocked[i] = 1
		for key_index: Variant in geometry.get("heights", {}):
			var i := int(key_index)
			data.walk_height_levels[i] = int(geometry.heights[key_index])
			data.has_raised_surfaces = data.has_raised_surfaces or data.walk_height_levels[i] != data.height_levels[i]
			data.walk_ramp_edges[i] = 0
	# The same original vehicle owns tower durability and deployed pose. Append
	# its rebuildable surfaces after all feature heights, before any connections.
	for vehicle: Dictionary in data.site.get("vehicles", {}).values():
		if str(vehicle.get("kind", "")) != "siege_tower": continue
		var geometry := SiteRuntime.siege_tower_geometry(data, vehicle)
		if not bool(geometry.active): continue
		geometries.append(geometry)
		for key_index: Variant in geometry.heights:
			var index := int(key_index)
			data.walk_height_levels[index] = int(geometry.heights[key_index])
			data.walk_ramp_edges[index] = 0
			data.has_raised_surfaces = true
	# Apply every surface before its connections; feature dictionary order cannot
	# decide whether a stair reaches a neighbouring wall or natural plateau.
	for geometry: Dictionary in geometries:
		for key_index: Variant in geometry.get("ramps", {}):
			var i := int(key_index)
			var mask := int(geometry.ramps[key_index]) & 15
			for direction in range(4):
				if (mask & (1 << direction)) == 0: continue
				var neighbour := data.cell_from_index(i) + TerrainData.DIRECTIONS[direction]
				if not data.contains(neighbour):
					# Only the local half-edge; RegionSaveSlot checks the other Site.
					data.walk_ramp_edges[i] |= 1 << direction
					continue
				var j := data.index(neighbour)
				if absi(int(data.walk_height_levels[i]) - int(data.walk_height_levels[j])) > 1: continue
				data.walk_ramp_edges[i] |= 1 << direction
				data.walk_ramp_edges[j] |= 1 << ((direction + 2) % 4)
		for key_index: Variant in geometry.get("edge_blocks", {}):
			var i := int(key_index)
			var mask := int(geometry.edge_blocks[key_index]) & 15
			data.walk_ramp_edges[i] |= mask << 4
			for direction in range(4):
				if (mask & (1 << direction)) == 0: continue
				var neighbour := data.cell_from_index(i) + TerrainData.DIRECTIONS[direction]
				if data.contains(neighbour): data.walk_ramp_edges[data.index(neighbour)] |= 1 << (((direction + 2) % 4) + 4)
	if data.bridge_walkable.has(1):
		data.bridge_navigation_flags = data.flags.duplicate()
		for i: int in range(count):
			if data.bridge_walkable[i] != 0:
				data.bridge_navigation_flags[i] = (data.bridge_navigation_flags[i] | TerrainData.Flag.WALKABLE) & ~TerrainData.Flag.BLOCKED
	data.has_navigation_overrides = data.has_raised_surfaces or data.walk_ramp_edges != data.ramp_edges or not data.bridge_navigation_flags.is_empty()
	_finish_index(data, index_job)

static func preview_navigation(data: TerrainData, key: String, candidate_feature: Dictionary) -> TerrainData:
	var state := data.site.duplicate()
	state.features = data.site.features.duplicate()
	if candidate_feature.is_empty(): state.features.erase(key)
	else: state.features[key] = candidate_feature
	return navigation_for_state(data, state)

static func navigation_for_state(data: TerrainData, state: Dictionary) -> TerrainData:
	# Detached derived indexes only. Natural ground, people and items stay with
	# their original owners, and rebuilding this candidate does not modify them.
	var candidate := TerrainData.new()
	for field: String in ["size", "height_levels", "surface_types", "flags", "cliff_drops", "ramp_edges", "detail_variation", "spawn_cell", "preset", "seed_value", "parameters", "fertility", "moisture", "drainage", "foundation", "groundwater", "water_kind", "water_body", "resource_base"]:
		candidate.set(field, data.get(field))
	candidate.site = state
	if data.has_meta(&"world_person_allocator"): candidate.set_meta(&"world_person_allocator", data.get_meta(&"world_person_allocator"))
	rebuild_indexes(candidate)
	return candidate

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
			var component_cell := data.cell_from_index(current)
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var next := component_cell + direction
				if data.contains(next) and labels[data.index(next)] < 0 and data.can_terrain_step(component_cell, next):
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
				var reachable_cell := data.cell_from_index(current)
				for direction: Vector2i in TerrainData.DIRECTIONS:
					var next := reachable_cell + direction
					if not data.contains(next):
						continue
					var j := data.index(next)
					if reached.has(j) or not data.can_terrain_step(reachable_cell, next):
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
		if ecology_active(data) and int(r.kind) in POPULATION_KINDS and not ecology_cell_usable(data, r, i): continue
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

static func land(data: TerrainData, cell: Vector2i, ignored_feature: int = 0) -> Dictionary:
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
	if (data.feature_at[i] != 0 and data.feature_at[i] != ignored_feature) or i == int(data.site.depot_cell):
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
	if r.is_empty(): return 0
	var usable := 0
	var admitted := ecology_active(data)
	for i: int in r.cells:
		if (ecology_cell_usable(data, r, i) if admitted else data.feature_at[i] == 0):
			usable += 1
	var capacity := floori(float(r.capacity) * float(usable) / float(r.cells.size()))
	if admitted and int(r.kind) == Kind.WILDLIFE and int(r.capacity) >= 2 and ecology_cell_usable(data, r, int(r.cell)):
		capacity = mini(int(r.capacity), maxi(2, capacity))
	return capacity

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



static func _populate_soil_conditions(data: TerrainData, generated_variation: bool) -> void:
	var job := _begin_soil(data, generated_variation)
	while not _step_soil(data, job): pass

static func _begin_soil(data: TerrainData, generated_variation: bool) -> Dictionary:
	# Reference array avoids copying a packed distance buffer on every cursor update.
	var noise := FastNoiseLite.new()
	noise.seed = int((data.seed_value + 19391) & 0x7fffffff)
	noise.frequency = 0.07
	var wet_distance: Array[int] = []
	wet_distance.resize(data.surface_types.size())
	wet_distance.fill(20)
	var pending: Array[int] = []
	return {"noise": noise, "distance": wet_distance, "pending": pending, "cursor": 0, "head": 0, "stage": "seed", "variation": generated_variation}

static func _step_soil(data: TerrainData, job: Dictionary) -> bool:
	var pending: Array[int] = job.pending
	if job.stage == "seed":
		var i := int(job.cursor)
		if i < job.distance.size():
			if data.water_kind[i] != 0: job.distance[i] = 0; pending.append(i)
			job.cursor = i + 1
		else: job.stage = "bfs"
	elif job.stage == "bfs":
		if int(job.head) < pending.size():
			var current := pending[int(job.head)]
			job.head = int(job.head) + 1
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var next := data.cell_from_index(current) + direction
				if not data.contains(next): continue
				var j := data.index(next)
				if job.distance[j] > job.distance[current] + 1:
					job.distance[j] = job.distance[current] + 1
					pending.append(j)
		else: job.stage = "cells"; job.cursor = 0
	elif job.stage == "cells":
		var i := int(job.cursor)
		if i < data.surface_types.size():
			_apply_soil_cell(data, i, job.noise, bool(job.variation), job.distance)
			job.cursor = i + 1
		else: job.stage = "done"
	return job.stage == "done"

static func _apply_soil_cell(data: TerrainData, i: int, noise: FastNoiseLite, generated_variation: bool, wet_distance: Array[int]) -> void:
	var cell := data.cell_from_index(i)
	var variation := int(noise.get_noise_2d(cell.x, cell.y) * 35.0) if generated_variation else 0
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

static func author_land_valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() > 10000: return false
	for key: Variant in value:
		if not key is String or not key.is_valid_int() or str(int(key)) != key or int(key) < 0 or int(key) >= 10000: return false
		var row: Variant = value[key]
		if not row is Dictionary or row.is_empty(): return false
		for field: Variant in row:
			if field not in ["fertility", "moisture", "drainage", "foundation", "groundwater"] or not RegionTerrainAdapter.author_integer(row[field], 0, 100): return false
	return true

static func restore_author_land(data: TerrainData) -> void:
	var values: Variant = data.parameters.get("author_land_cells", {})
	if not author_land_valid(values): return
	for field: String in ["fertility", "moisture", "drainage", "foundation", "groundwater"]:
		var array: PackedByteArray = data.get(field)
		if array.size() != 10000: return
	for key: String in values:
		for field: String in values[key]:
			var array: PackedByteArray = data.get(field)
			array[int(key)] = int(values[key][field])
			data.set(field, array)

# Author definitions enter the same resource_base used by gameplay and persistence.

static func resource_species(value: Dictionary) -> String:
	if int(value.get("kind", -1)) != Kind.WILDLIFE: return ""
	return wildlife_species(int(value.variant), int(value.get("identity_cell", value.cell)))


static func resource_integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum


static func resource_key_valid(key: Variant) -> bool:
	if not key is String: return false
	var parts: PackedStringArray = key.split(":")
	if parts.size() != 2 or not parts[1].is_valid_int() or str(int(parts[1])) != parts[1]: return false
	if parts[0] == "author_resource": return int(parts[1]) >= 1 and int(parts[1]) <= 2147483646
	return parts[0].is_valid_int() and str(int(parts[0])) == parts[0] and int(parts[0]) >= 0 and int(parts[0]) < NAMES.size() and int(parts[1]) >= 0 and int(parts[1]) <= 2147483646


static func validate_resource_definitions(data: TerrainData, definitions: Variant, strict_keys: Array[String] = []) -> Dictionary:
	if data == null or not definitions is Dictionary: return SiteRuntime.fail("INVALID_RESOURCE", "來源表或數量非法")
	var count: int = data.size.x * data.size.y
	if data.water_body.size() != count or data.water_kind.size() != count or data.surface_types.size() != count: return SiteRuntime.fail("INVALID_RESOURCE", "來源缺少原水域分類")
	for key: Variant in definitions:
		if not resource_key_valid(key) or not definitions[key] is Dictionary: return SiteRuntime.fail("INVALID_RESOURCE", "來源key非法")
		var row: Dictionary = definitions[key]
		if not resource_definition_shape(row, count, str(key) in strict_keys or str(key).begins_with("author_resource:")): return SiteRuntime.fail("INVALID_RESOURCE", "來源欄位非法")
		if int(str(key).get_slice(":", 1)) >= count and not str(key).begins_with("author_resource:"): return SiteRuntime.fail("INVALID_RESOURCE", "原來源身分格越界")
		var authored: bool = str(key) in strict_keys or str(key).begins_with("author_resource:")
		if not str(key).begins_with("author_resource:") and int(str(key).get_slice(":", 0)) != int(row.kind): return SiteRuntime.fail("INVALID_RESOURCE", "原來源key種類不符")
		if str(key).begins_with("author_resource:") and int(row.kind) == Kind.WILDLIFE and not row.has("identity_cell"): return SiteRuntime.fail("INVALID_RESOURCE", "新增野生來源須有明示身分")
		# Existing natural sources keep their original habitat rules; authored rows are stricter.
		if authored:
			if int(row.water) != data.water_body[int(row.cell)]: return SiteRuntime.fail("WATER", "來源水體不符")
			for index: int in row.cells:
				if int(row.kind) == Kind.FISH:
					if data.water_kind[index] not in [1, 2] or data.water_body[index] != int(row.water) or data.surface_types[index] != TerrainData.Surface.WATER: return SiteRuntime.fail("WATER", "魚點須在同一真水體")
				elif int(row.kind) == Kind.SALT:
					if data.water_kind[index] not in [2, 3] or int(row.recover) != 0: return SiteRuntime.fail("WATER", "鹽源沿分鐘配額且須海水或原鹵水")
				elif data.water_kind[index] != 0 or data.surface_types[index] == TerrainData.Surface.WATER: return SiteRuntime.fail("WATER", "陸地來源不可放入水中")
	return SiteRuntime.ok()


static func normalize_resource_definition(row: Dictionary) -> Dictionary:
	var value: Dictionary = row.duplicate(true)
	for field: String in ["kind", "cell", "capacity", "variant", "water", "recover", "identity_cell"]:
		if value.has(field): value[field] = int(value[field])
	var cells: Array[int] = []
	for index: Variant in value.cells: cells.append(int(index))
	value.cells = cells
	return value


static func prepare_author_resource_source(data: TerrainData, edits: Variant) -> Dictionary:
	if data == null or not data.site.is_empty() or not edits is Dictionary: return SiteRuntime.fail("AUTHOR_ONLY", "只准原純來源的隔離作者候選")
	var original: Dictionary = validate_resource_definitions(data, data.resource_base)
	if not original.ok: return original
	var definitions: Dictionary = data.resource_base.duplicate(true)
	var strict: Array[String] = []
	for key: Variant in edits:
		if not resource_key_valid(key) or (not definitions.has(key) and not str(key).begins_with("author_resource:")): return SiteRuntime.fail("INVALID_RESOURCE", "新來源須使用作者命名空間")
		if edits[key] == null:
			if not definitions.has(key): return SiteRuntime.fail("INVALID_RESOURCE", "移除不存在的來源")
			definitions.erase(key)
			continue
		if not edits[key] is Dictionary: return SiteRuntime.fail("INVALID_RESOURCE", "來源定義非法")
		var row: Dictionary = edits[key].duplicate(true)
		var previous: Dictionary = definitions.get(key, {})
		if not previous.is_empty():
			if not resource_integer(row.get("kind"), 0, NAMES.size() - 1) or int(row.kind) != int(previous.kind): return SiteRuntime.fail("INVALID_RESOURCE", "既有key不可換種類")
			if int(previous.kind) == Kind.WILDLIFE:
				var identity: int = int(previous.get("identity_cell", previous.cell))
				if row.has("identity_cell") and (not resource_integer(row.identity_cell, 0, data.size.x * data.size.y - 1) or int(row.identity_cell) != identity): return SiteRuntime.fail("INVALID_RESOURCE", "物種身分不可改")
				row.identity_cell = identity
		definitions[key] = row
		strict.append(str(key))
	var checked: Dictionary = validate_resource_definitions(data, definitions, strict)
	if not checked.ok: return checked
	for key: String in definitions: definitions[key] = normalize_resource_definition(definitions[key])
	var candidate: TerrainData = navigation_for_state(data, {})
	candidate.resource_base = definitions
	candidate.parameters = data.parameters.duplicate(true)
	rebuild_indexes(candidate)
	candidate.environment_revision = data.environment_revision + 1
	return SiteRuntime.ok("", {"data": candidate})


static func author_resource_state_guard(data: TerrainData, state: Dictionary) -> Dictionary:
	# No native handoff, live owner capture, clock advancement or Fire history erasure here.
	if state.has("crowd") or state.has("world_pin") or state.has("region_snapshot") or state.has("initial_scenario") or state.has("travel_identity"): return SiteRuntime.fail("AUTHOR_IMPORT_UNSUPPORTED", "活動世界須由原owner完成安全副本交接")
	if not state.get("fire", {}) is Dictionary or not state.get("vehicles", {}) is Dictionary or not state.get("armies", []) is Array or not state.get("actors", {}) is Dictionary: return SiteRuntime.fail("INVALID_RESOURCE", "來源活動格式非法")
	var family: Variant = state.get("family", {})
	if not family is Dictionary: return SiteRuntime.fail("INVALID_RESOURCE", "家族引用格式非法")
	if family.has("members") and not family.members is Array: return SiteRuntime.fail("INVALID_RESOURCE", "家族名冊格式非法")
	if SiteTechnology.is_holder_reference(family.get("technology")): return SiteRuntime.fail("AUTHOR_IMPORT_UNSUPPORTED", "外部科技holder須原owner完成閉包")
	var combat: Variant = state.get("combat_left", 0.0)
	if not (combat is int or combat is float) or not is_finite(float(combat)) or combat != 0.0: return SiteRuntime.fail("BUSY", "戰鬥須原owner收束")
	if not state.get("fire", {}).is_empty() or not state.get("vehicles", {}).is_empty(): return SiteRuntime.fail("BUSY", "Fire、車船、戰鬥保留原世界")
	for name: String in ["worker", "manual"]:
		var worker: Variant = state.get(name, {})
		if not worker is Dictionary or not worker.get("target", "") is String or not str(worker.get("target", "")).is_empty() or not resource_integer(worker.get("progress", 0), 0, 0): return SiteRuntime.fail("BUSY", "先沿原作業owner收束")
	return SiteRuntime.ok()


static func validate_resource_deltas(data: TerrainData, state: Dictionary) -> Dictionary:
	if data == null: return SiteRuntime.fail("NO_TARGET")
	if not state.get("changes") is Dictionary or not resource_integer(state.get("minute"), 0, 1000000000): return SiteRuntime.fail("INVALID_RESOURCE", "來源差異或時鐘非法")
	for key: Variant in state.changes:
		if not key is String or not data.resource_base.has(key) or not state.changes[key] is Dictionary: return SiteRuntime.fail("INVALID_RESOURCE", "來源引用非法")
		var row: Dictionary = data.resource_base[key]
		var delta: Dictionary = state.changes[key]
		var remaining: Variant = delta.get("remaining", row.capacity)
		var deadline: Variant = delta.get("next_recovery", -1)
		if not resource_integer(remaining, 0, int(row.capacity)) or not resource_integer(deadline, -1, 1100000000): return SiteRuntime.fail("INVALID_RESOURCE", "存量或排程非法")
		if (int(row.recover) == 0 or delta.get("cleared", false) == true) and int(deadline) != -1: return SiteRuntime.fail("INVALID_RESOURCE", "不恢復或清除來源不得保留排程")
		if delta.has("used") or delta.has("used_minute"):
			if int(row.kind) != Kind.SALT or not (delta.get("used") is int or delta.get("used") is float) or not is_finite(float(delta.get("used", -1))) or float(delta.get("used", -1)) < 0.0 or float(delta.get("used", -1)) > float(row.capacity) or not resource_integer(delta.get("used_minute"), 0, int(state.minute)): return SiteRuntime.fail("INVALID_RESOURCE", "鹽源分鐘配額或時鐘非法")
	return SiteRuntime.ok()


static func prepare_author_resource_state(data: TerrainData, state: Dictionary, reset_key: String = "") -> Dictionary:
	if data == null: return SiteRuntime.fail("NO_TARGET")
	var definitions: Dictionary = validate_resource_definitions(data, data.resource_base)
	if not definitions.ok: return definitions
	if data.has_meta(&"site_garrison_lab") or data.has_meta(&"siege_event_guard") or data.has_meta(&"fire_event_guard"): return SiteRuntime.fail("AUTHOR_IMPORT_UNSUPPORTED", "活動owner只能沿原安全副本入口")
	var guard: Dictionary = author_resource_state_guard(data, state)
	if not guard.ok: return guard
	var candidate: TerrainData = navigation_for_state(data, state.duplicate(true))
	var heights: Variant = candidate.site.get("terrain_changes")
	if not heights is Dictionary: return SiteRuntime.fail("INVALID_RESOURCE", "初始高度差異非法")
	if not heights.is_empty():
		for field: String in ["height_levels", "flags", "cliff_drops", "ramp_edges"]: candidate.set(field, candidate.get(field).duplicate())
		for key: Variant in heights:
			if not key is String or not key.is_valid_int() or str(int(key)) != key or not resource_integer(int(key), 0, candidate.size.x * candidate.size.y - 1) or not resource_integer(heights[key], 0, 5): return SiteRuntime.fail("INVALID_RESOURCE", "初始高度差異非法")
			candidate.height_levels[int(key)] = int(heights[key])
		SiteRuntime.rebuild_terrain_edges(candidate)
		rebuild_indexes(candidate)
	if not reset_key.is_empty():
		if not candidate.resource_base.has(reset_key): return SiteRuntime.fail("NO_TARGET")
		# Reset stock, never ecology admission, modes, duties, earned technology or minute quota.
		change(candidate, reset_key, {"remaining": int(candidate.resource_base[reset_key].capacity), "cleared": false, "next_recovery": -1})
	var valid: Dictionary = validate_resource_deltas(candidate, candidate.site)
	if not valid.ok: return valid
	var checked_state: Dictionary = candidate.site.duplicate(true)
	var base: Variant = candidate.parameters.get("fixed_base")
	if RegionTerrainAdapter.has_author_identity(base): checked_state.world_pin = RegionData.author_projection_pin(base)
	var checked: Dictionary = SiteStore._validate_state(candidate, checked_state)
	if not checked.ok: return checked
	SiteStore._normalize_state(candidate.site)
	# Match the original Store load boundary for validated integral Site fields.
	for field: String in ["minute", "next_feature", "depot_cell", "capacity"]:
		candidate.site[field] = int(candidate.site[field])
	rebuild_indexes(candidate)
	return SiteRuntime.ok("", {"data": candidate, "state": candidate.site})


static func resource_definition_shape(row: Variant, count: int, authored: bool) -> bool:
	if not row is Dictionary or row.size() < 8 or row.size() > 9: return false
	for field: Variant in row:
		if field not in ["kind", "cell", "cells", "capacity", "variant", "water", "blocks", "recover", "identity_cell"]: return false
	if not resource_integer(row.get("kind"), 0, 8) or not resource_integer(row.get("cell"), 0, count - 1): return false
	if not resource_integer(row.get("capacity"), 1, 1000000 if authored else 2147483646) or not resource_integer(row.get("recover"), 0, 1000000 if authored else 1100000000): return false
	if not resource_integer(row.get("variant"), 0, 2) or not resource_integer(row.get("water"), -1, 2147483646): return false
	if not row.get("blocks") is bool or row.blocks != (int(row.kind) in [Kind.TIMBER, Kind.STONE]): return false
	if row.has("identity_cell") and (int(row.kind) != Kind.WILDLIFE or not resource_integer(row.identity_cell, 0, count - 1)): return false
	if not row.get("cells") is Array or row.cells.is_empty() or row.cells.size() > count: return false
	var seen: Dictionary = {}
	for index: Variant in row.cells:
		if not resource_integer(index, 0, count - 1) or seen.has(int(index)): return false
		seen[int(index)] = true
	return seen.has(int(row.cell))
