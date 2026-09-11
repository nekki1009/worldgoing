class_name SiteRuntime
extends RefCounted

const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const COMBAT_GRACE := 10.0
const CARRY_CAPACITY := 20
const FEATURES := {
	"house": {"name": "住宅", "cost": {"wood": 8, "stone": 4}, "work": 15.0, "solid": true, "water": 0.02},
	"well": {"name": "水井", "cost": {"wood": 4, "stone": 6}, "work": 12.0, "solid": false, "water": 0.0},
	"intake": {"name": "取水站", "cost": {"wood": 4, "stone": 2}, "work": 8.0, "solid": false, "water": 0.0},
	"farm": {"name": "糧食農田", "cost": {}, "work": 6.0, "solid": false, "water": 0.04, "input": {"seeds": 1}, "output": {"grain": 8}, "cycle": 480.0},
	"fiber_farm": {"name": "纖維農田", "cost": {}, "work": 6.0, "solid": false, "water": 0.03, "input": {"seeds": 1}, "output": {"fiber": 5}, "cycle": 480.0},
	"fodder_farm": {"name": "飼料農田", "cost": {}, "work": 6.0, "solid": false, "water": 0.03, "input": {"seeds": 1}, "output": {"fodder": 10}, "cycle": 360.0},
	"pasture": {"name": "養羊牧區", "cost": {"wood": 4, "sheep": 1}, "work": 8.0, "solid": false, "water": 0.03, "input": {"fodder": 1}, "output": {"wool": 2}, "cycle": 240.0},
	"horse_ranch": {"name": "育馬場", "cost": {"wood": 8, "horse": 2}, "work": 15.0, "solid": false, "water": 0.06, "input": {"fodder": 3}, "output": {"horse": 1}, "cycle": 1440.0},
	"saltworks": {"name": "簡易鹽場", "cost": {"wood": 6, "stone": 4, "clay": 2}, "work": 12.0, "solid": true, "water": 0.0, "input": {"brine": 2, "wood": 1}, "output": {"salt": 2}, "cycle": 8.0},
	"kiln": {"name": "簡易磚瓦窯", "cost": {"stone": 6, "clay": 4, "wood": 2}, "work": 15.0, "solid": true, "water": 0.0, "input": {"clay": 3, "wood": 1}, "output": {"brick": 3}, "cycle": 12.0},
	"charcoal": {"name": "炭窯", "cost": {"stone": 2, "clay": 2}, "work": 8.0, "solid": true, "water": 0.0, "input": {"wood": 4}, "output": {"charcoal": 2}, "cycle": 10.0},
	"smelter": {"name": "冶煉作坊", "cost": {"stone": 8, "clay": 4, "wood": 4}, "work": 20.0, "solid": true, "water": 0.0, "input": {"iron_ore": 3, "charcoal": 2}, "output": {"iron": 2}, "cycle": 15.0},
	"smithy": {"name": "鐵匠鋪", "cost": {"wood": 8, "stone": 6}, "work": 18.0, "solid": true, "water": 0.0, "input": {"iron": 2, "charcoal": 1, "wood": 1}, "output": {"tools": 1}, "cycle": 12.0},
	"tannery": {"name": "製革作坊", "cost": {"wood": 6, "stone": 2}, "work": 10.0, "solid": true, "water": 0.02, "input": {"hide": 2}, "output": {"leather": 2}, "cycle": 15.0},
	"weaver": {"name": "織布作坊", "cost": {"wood": 6, "stone": 2}, "work": 10.0, "solid": true, "water": 0.0, "input": {"fiber": 3}, "output": {"cloth": 2}, "cycle": 12.0},
	"road": {"name": "土路", "cost": {"stone": 1}, "work": 3.0, "solid": false, "water": 0.0},
	"level": {"name": "整平一級地面", "cost": {}, "work": 10.0, "solid": false, "water": 0.0},
}
const ERRORS := {
	"NO_TARGET": "目標不存在", "EMPTY": "來源已耗盡／等待恢復", "SURVEY": "請先勘探鐵礦",
	"UNREACHABLE": "沒有可達工作格", "OCCUPIED": "占地或人員預約衝突", "MATERIALS": "缺少材料／工具",
	"STORAGE_FULL": "存放空間不足", "TERRAIN": "地勢或地基不合適", "WATER": "缺少對應水源／供水",
	"BUSY": "工作或戰鬥進行中", "INVALID": "無效命令", "BLOCKED": "作業位置被阻擋", "CAPACITY": "本分鐘來源能力已用盡",
}

static func fail(code: String, detail: String = "") -> Dictionary:
	return {"ok": false, "code": code, "message": str(ERRORS.get(code, code)) + ("：" + detail if not detail.is_empty() else "")}

static func ok(message: String = "完成", values: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "code": "OK", "message": message}
	result.merge(values, true)
	return result

static func now(data: TerrainData) -> float:
	return float(data.site.minute) + float(data.site.phase)

static func inventory_size(inventory: Dictionary) -> int:
	var total := 0
	for amount: Variant in inventory.values():
		total += int(amount)
	return total

static func can_pay(inventory: Dictionary, cost: Dictionary) -> bool:
	for key: String in cost:
		if int(inventory.get(key, 0)) < int(cost[key]):
			return false
	return true

static func add_items(inventory: Dictionary, items: Dictionary, sign_value: int = 1) -> void:
	for key: String in items:
		inventory[key] = int(inventory.get(key, 0)) + int(items[key]) * sign_value

static func harvest(data: TerrainData, key: String, actor_cell: Vector2i, cargo: Dictionary, action: String = "harvest") -> Dictionary:
	if action not in ["harvest", "survey", "clear"]:
		return fail("INVALID")
	var r := Env.resource(data, key)
	if r.is_empty():
		return fail("NO_TARGET")
	if not Env.work_cells(data, key).has(actor_cell):
		return fail("UNREACHABLE")
	if not can_pay(data.site.inventory, {"tools": 1}):
		return fail("MATERIALS", "工具")
	if action == "survey":
		Env.change(data, key, {"discovered": true})
		return ok("勘探完成")
	if not bool(r.discovered):
		return fail("SURVEY")
	if bool(r.cleared):
		return fail("EMPTY")
	var kind := int(r.kind)
	var taken := mini(int(r.remaining), int(Env.BATCH[kind]))
	if action == "clear":
		if kind not in [Env.Kind.TIMBER, Env.Kind.STONE, Env.Kind.FOOD, Env.Kind.HERB]:
			return fail("INVALID", "地下礦藏不能靠清地刪除")
		if int(r.remaining) > 0:
			# A clear job first harvests its material, then clears the exhausted object.
			action = "harvest"
		else:
			Env.change(data, key, {"cleared": true, "next_recovery": -1})
			Env.rebuild_indexes(data)
			rebuild_water(data)
			return ok("清理完成")
	if taken <= 0:
		return fail("EMPTY")
	if data.feature_at[int(r.cell)] != 0:
		var feature: Dictionary = data.site.features.get(str(data.feature_at[int(r.cell)]), {})
		if not feature.is_empty() and str(feature.stage) == "complete":
			return fail("OCCUPIED")
	if kind == Env.Kind.SALT:
		var used := float(r.get("used", 0.0)) if int(r.get("used_minute", -1)) == int(data.site.minute) else 0.0
		taken = mini(taken, floori(float(r.capacity) - used))
		if taken <= 0:
			return fail("CAPACITY")
	var output := {str(Env.ITEMS[kind]): taken}
	if kind == Env.Kind.WILDLIFE:
		output = {"meat": taken * (3 if int(r.variant) == 0 else 2), "hide": taken}
	if inventory_size(cargo) + inventory_size(output) > CARRY_CAPACITY:
		return fail("STORAGE_FULL")
	# Validate everything before changing either side of the transaction.
	var fields := {"remaining": int(r.remaining) - taken}
	if kind == Env.Kind.SALT:
		var used := float(r.get("used", 0.0)) if int(r.get("used_minute", -1)) == int(data.site.minute) else 0.0
		fields = {"used": used + taken, "used_minute": int(data.site.minute)}
	elif int(r.recover) > 0 and int(r.get("next_recovery", -1)) < 0:
		fields["next_recovery"] = ceili(now(data)) + int(r.recover)
	Env.change(data, key, fields)
	add_items(cargo, output)
	data.site.total_produced = int(data.site.total_produced) + inventory_size(output)
	Env.rebuild_indexes(data)
	rebuild_water(data)
	return ok("取得 " + items_text(output), {"items": output, "taken": taken})

static func items_text(items: Dictionary) -> String:
	var labels: Array[String] = []
	for key: String in items:
		labels.append("%s ×%d" % [str(Env.ITEM_NAMES.get(key, key)), int(items[key])])
	return "、".join(labels) if not labels.is_empty() else "無"

static func deposit(data: TerrainData, cargo: Dictionary, actor_cell: Vector2i) -> Dictionary:
	var depot := data.cell_from_index(int(data.site.depot_cell))
	if absi(actor_cell.x - depot.x) + absi(actor_cell.y - depot.y) > 1:
		return fail("UNREACHABLE", "請回營地箱旁交貨")
	if inventory_size(data.site.inventory) + inventory_size(cargo) > int(data.site.capacity):
		return fail("STORAGE_FULL")
	var text := items_text(cargo)
	add_items(data.site.inventory, cargo)
	cargo.clear()
	data.environment_revision += 1
	return ok("已入庫：" + text)

static func add_zone(data: TerrainData, area: Rect2i, kind: int, action: String = "harvest") -> Dictionary:
	if action not in ["harvest", "clear", "survey"] or kind < -1 or kind >= Env.NAMES.size():
		return fail("INVALID")
	var bounded := area.intersection(Rect2i(Vector2i.ZERO, data.size))
	if not bounded.has_area() or bounded.get_area() > 1600:
		return fail("INVALID", "工作區限 1–1600 格")
	if Env.resources_in(data, bounded, kind).is_empty():
		return fail("NO_TARGET")
	var cells: Array[int] = []
	for y: int in range(bounded.position.y, bounded.end.y):
		for x: int in range(bounded.position.x, bounded.end.x):
			cells.append(data.index(Vector2i(x, y)))
	data.site.zones.append({"cells": cells, "kind": kind, "action": action, "active": true})
	data.environment_revision += 1
	return ok("工作區已指定", {"zone": data.site.zones.size() - 1})

static func preview_build(data: TerrainData, kind: String, cells: Array[int], occupied: Callable = Callable()) -> Dictionary:
	if not FEATURES.has(kind) or cells.is_empty() or cells.size() > 36:
		return fail("INVALID", "建設區限 1–36 格")
	var definition: Dictionary = FEATURES[kind]
	var first_height := -1
	var min_height := 255
	var max_height := 0
	var seen := {}
	var clearing: Array[String] = []
	for i: int in cells:
		if i < 0 or i >= data.surface_types.size() or seen.has(i):
			return fail("INVALID")
		seen[i] = true
		var cell := data.cell_from_index(i)
		if not data.is_terrain_walkable(cell):
			return fail("TERRAIN", "占地不能包含水面")
		if data.feature_at[i] != 0 or i == int(data.site.depot_cell) or (occupied.is_valid() and bool(occupied.call(cell))):
			return fail("OCCUPIED")
		if data.ramp_edges[i] != 0 and kind not in ["road", "level"]:
			return fail("TERRAIN", "保留現有坡口")
		var height := int(data.height_levels[i])
		min_height = mini(min_height, height)
		max_height = maxi(max_height, height)
		if first_height < 0:
			first_height = height
		if kind != "level" and height != first_height:
			return fail("TERRAIN", "占地跨越高差，請先整地")
		if kind not in ["farm", "fiber_farm", "fodder_farm", "pasture", "horse_ranch", "road", "level", "intake", "saltworks"] and data.foundation[i] < 35:
			return fail("TERRAIN", "地基不足")
		if (kind == "intake" and data.foundation[i] < 10) or (kind == "saltworks" and data.foundation[i] < 25):
			return fail("TERRAIN", "岸邊作業地基不足")
		if kind in ["farm", "fiber_farm", "fodder_farm"] and (data.fertility[i] < 30 or data.drainage[i] < 30):
			return fail("TERRAIN", "土壤或排水不適耕")
		if kind in ["pasture", "horse_ranch"] and Env.land(data, cell).pasture < 25:
			return fail("TERRAIN", "草地承載不足")
		for key: String in data.resources_at.get(i, []):
			var r := Env.resource(data, key)
			if int(r.cell) == i and not bool(r.cleared) and int(r.kind) in [Env.Kind.TIMBER, Env.Kind.STONE, Env.Kind.FOOD, Env.Kind.HERB] and not clearing.has(key):
				clearing.append(key)
	if max_height - min_height > 1:
		return fail("TERRAIN", "本期整地最多處理一級高差")
	var connected := {cells[0]: true}
	var pending: Array[int] = [cells[0]]
	var head := 0
	while head < pending.size():
		var current := pending[head]
		head += 1
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := data.cell_from_index(current) + direction
			if data.contains(next) and seen.has(data.index(next)) and not connected.has(data.index(next)):
				connected[data.index(next)] = true
				pending.append(data.index(next))
	if connected.size() != cells.size():
		return fail("INVALID", "占地必須相連")
	if kind == "well" and data.groundwater[cells[0]] < 35:
		return fail("WATER", "地下水潛力不足")
	if kind in ["pasture", "horse_ranch"] and grazing_capacity(data, cells) < (2 if kind == "horse_ranch" else 1):
		return fail("TERRAIN", "草地承載不足；擴大牧區或另選土地")
	var source := ""
	if kind == "intake":
		source = adjacent_water(data, cells, 1)
		if source.is_empty():
			return fail("WATER", "取水站需接鄰可取用的淡水")
	if kind == "saltworks":
		source = adjacent_water(data, cells, 2)
		if source.is_empty():
			for key: String in data.resource_base:
				var r := Env.resource(data, key)
				if int(r.kind) == Env.Kind.SALT and _near_cells(data, cells, int(r.cell), 4):
					source = key
					break
		if source.is_empty():
			return fail("WATER", "鹽場需位於海岸或鹵水點旁")
	var entrance := -1
	for i: int in cells:
		if kind == "level" and int(data.height_levels[i]) != min_height:
			continue
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var cell := data.cell_from_index(i) + direction
			if data.is_walkable(cell) and not seen.has(data.index(cell)) and data.can_terrain_step(cell, data.cell_from_index(i)):
				entrance = data.index(cell)
				break
		if entrance >= 0:
			break
	if entrance < 0:
		return fail("UNREACHABLE", "需保留可達入口")
	var cost: Dictionary = definition.cost.duplicate()
	if kind == "road":
		cost["stone"] = cells.size()
	if not can_pay(data.site.inventory, cost) or not can_pay(data.site.inventory, {"tools": 1}):
		return fail("MATERIALS", items_text(cost))
	return ok("可建設；清理 %d 處；%s" % [clearing.size(), items_text(cost)],
		{"cost": cost, "clearing": clearing, "entrance": entrance, "source": source, "level": min_height})

static func request_build(data: TerrainData, kind: String, cells: Array[int], occupied: Callable = Callable()) -> Dictionary:
	var preview := preview_build(data, kind, cells, occupied)
	if not preview.ok:
		return preview
	var key := str(data.site.next_feature)
	data.site.next_feature = int(data.site.next_feature) + 1
	var definition: Dictionary = FEATURES[kind]
	add_items(data.site.inventory, preview.cost, -1)
	data.site.features[key] = {"kind": kind, "cells": cells.duplicate(), "entrance": int(preview.entrance), "source": str(preview.source),
		"stage": "planned", "progress": 0.0, "solid": bool(definition.solid), "cost": preview.cost,
		"work": build_work(kind, cells.size()),
		"clearing": preview.clearing, "level": int(preview.level), "production": 0.0, "batch_paid": false, "status": "待施工"}
	if kind in ["pasture", "horse_ranch"]:
		data.site.features[key].species = "horse" if kind == "horse_ranch" else "sheep"
		data.site.features[key].residents = 2 if kind == "horse_ranch" else 1
	data.site.zones.append({"cells": cells.duplicate(), "kind": -1, "action": "construct", "feature": key, "active": true})
	Env.rebuild_indexes(data)
	return ok("已預留材料並排入施工：" + str(definition.name), {"feature": key})

static func build_work(kind: String, cell_count: int) -> float:
	return float(FEATURES[kind].work) * (cell_count if kind.contains("farm") or kind in ["road", "level"] else 1)

static func water_demand(feature: Dictionary) -> float:
	return float(FEATURES[str(feature.kind)].water) * (feature.cells.size() if str(feature.kind).contains("farm") else 1)

static func cancel_feature(data: TerrainData, key: String) -> Dictionary:
	if not data.site.features.has(key):
		return fail("NO_TARGET")
	var feature: Dictionary = data.site.features[key]
	var refund := {}
	if str(feature.stage) != "complete":
		var fraction := clampf(1.0 - float(feature.progress) / float(feature.work), 0.0, 1.0)
		for item: String in feature.cost:
			refund[item] = floori(int(feature.cost[item]) * fraction)
	# The breeding stock remains live property, including during construction.
	if feature.has("species"):
		refund[str(feature.species)] = int(feature.residents)
	if inventory_size(data.site.inventory) + inventory_size(refund) > int(data.site.capacity):
		return fail("STORAGE_FULL")
	add_items(data.site.inventory, refund)
	data.site.features.erase(key)
	for zone_index: int in range(data.site.zones.size()):
		var zone: Dictionary = data.site.zones[zone_index]
		if str(zone.get("feature", "")) == key:
			zone.active = false
			if int(data.site.worker.zone) == zone_index:
				data.site.worker.target = ""
				data.site.worker.progress = 0.0
				data.site.worker.mode = "idle"
	if str(data.site.worker.target) == "feature:" + key:
		data.site.worker.target = ""
		data.site.worker.progress = 0.0
	Env.rebuild_indexes(data)
	rebuild_water(data)
	return ok("已拆除／取消；已採集與整地的結果保留")

static func operate_feature(data: TerrainData, key: String) -> Dictionary:
	if not data.site.features.has(key):
		return fail("NO_TARGET")
	var feature: Dictionary = data.site.features[key]
	if str(feature.stage) != "complete" or not FEATURES[str(feature.kind)].has("cycle"):
		return fail("INVALID", "此設施無需派工運作或尚未完成")
	for zone: Dictionary in data.site.zones:
		if str(zone.get("feature", "")) == key and str(zone.action) == "operate":
			zone.active = true
			return ok("已啟用設施工作")
	data.site.zones.append({"cells": feature.cells.duplicate(), "kind": -1, "action": "operate", "feature": key, "active": true})
	return ok("已派工；需持續提供原料與供水")

static func adjacent_water(data: TerrainData, cells: Array[int], kind: int) -> String:
	for i: int in cells:
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var neighbor := data.cell_from_index(i) + direction
			if data.contains(neighbor):
				var j := data.index(neighbor)
				if data.water_kind[j] == kind and data.height_levels[j] == data.height_levels[i]:
					return "water:%d" % int(data.water_body[j])
	return ""

static func grazing_capacity(data: TerrainData, cells: Array[int]) -> int:
	var capacity := 0
	for i: int in cells:
		if data.is_terrain_walkable(data.cell_from_index(i)):
			capacity += floori(float(mini(int(data.fertility[i]) + 10, int(data.moisture[i]) + 20)) / 30.0)
	return capacity

static func _near_cells(data: TerrainData, cells: Array[int], target: int, distance: int) -> bool:
	for i: int in cells:
		var offset := data.cell_from_index(i) - data.cell_from_index(target)
		if absi(offset.x) + absi(offset.y) <= distance:
			return true
	return false

static func choose_task(data: TerrainData, from: Vector2i, occupied: Callable = Callable()) -> Dictionary:
	var worker: Dictionary = data.site.worker
	if inventory_size(worker.cargo) > 0:
		var depot := data.cell_from_index(int(data.site.depot_cell))
		var candidates: Array[Vector2i] = [depot]
		for direction: Vector2i in TerrainData.DIRECTIONS:
			candidates.append(depot + direction)
		var destination := _reachable_work(data, from, candidates, occupied)
		if destination.x < 0:
			return fail("UNREACHABLE", "回營地路線受阻")
		return ok("運回營地", {"target": "depot", "action": "deposit", "cell": data.index(destination)})
	for zone_index: int in range(data.site.zones.size()):
		var zone: Dictionary = data.site.zones[zone_index]
		if not bool(zone.active):
			continue
		if str(zone.action) in ["construct", "operate"]:
			var key := str(zone.feature)
			if not data.site.features.has(key):
				zone.active = false
				continue
			var feature: Dictionary = data.site.features[key]
			if str(zone.action) == "construct":
				if str(feature.stage) == "complete":
					zone.active = false
					continue
				for source_key: String in feature.clearing:
					if bool(Env.resource(data, source_key).get("cleared", true)):
						continue
					var clear_cell := _reachable_work(data, from, Env.work_cells(data, source_key), occupied)
					if clear_cell.x >= 0:
						return ok("施工前清理", {"target": source_key, "action": "clear", "cell": data.index(clear_cell), "zone": zone_index})
					return fail("UNREACHABLE", "施工前清理")
			else:
				var definition: Dictionary = FEATURES[str(feature.kind)]
				if not bool(feature.batch_paid) and not can_pay(data.site.inventory, definition.input):
					feature.status = "缺投入：" + items_text(definition.input)
					continue
			var entrance := data.cell_from_index(int(feature.entrance))
			var destination := _reachable_work(data, from, [entrance], occupied)
			if destination.x >= 0:
				return ok("前往" + str(FEATURES[str(feature.kind)].name), {"target": "feature:" + key,
					"action": str(zone.action), "cell": data.index(destination), "zone": zone_index})
			continue
		var candidates: Array[String] = []
		for i: int in zone.cells:
			for key: String in data.resources_at.get(i, []):
				if not candidates.has(key):
					candidates.append(key)
		candidates.sort_custom(func(a: String, b: String) -> bool:
			return data.cell_from_index(int(data.resource_base[a].cell)).distance_squared_to(from) < data.cell_from_index(int(data.resource_base[b].cell)).distance_squared_to(from))
		for key: String in candidates:
			if key == str(data.site.manual.target):
				continue
			var r := Env.resource(data, key)
			if bool(r.cleared) or (int(zone.kind) >= 0 and int(r.kind) != int(zone.kind)):
				continue
			if str(zone.action) == "survey" and bool(r.discovered):
				continue
			if str(zone.action) == "clear" and int(r.kind) not in [Env.Kind.TIMBER, Env.Kind.STONE, Env.Kind.FOOD, Env.Kind.HERB]:
				continue
			if int(r.remaining) == 0 and str(zone.action) != "clear":
				continue
			if data.feature_at[int(r.cell)] != 0:
				continue
			var destination := _reachable_work(data, from, Env.work_cells(data, key), occupied)
			if destination.x >= 0:
				return ok("前往" + str(Env.NAMES[int(r.kind)]), {"target": key, "action": "survey" if not bool(r.discovered) else str(zone.action),
					"cell": data.index(destination), "zone": zone_index})
	return fail("NO_TARGET", "無可用工作／等待資源恢復")

static func _reachable_work(data: TerrainData, from: Vector2i, candidates: Array[Vector2i], occupied: Callable) -> Vector2i:
	var sorted := candidates.duplicate()
	sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.distance_squared_to(from) < b.distance_squared_to(from))
	for candidate: Vector2i in sorted:
		if not data.is_walkable(candidate) or (occupied.is_valid() and bool(occupied.call(candidate))):
			continue
		if candidate == from or not data.path_between(from, candidate, occupied).is_empty():
			return candidate
	return Vector2i(-1, -1)

static func assign_task(data: TerrainData, task: Dictionary) -> void:
	var worker: Dictionary = data.site.worker
	if not bool(task.get("ok", false)):
		worker.mode = "idle"
		worker.status = str(task.get("message", "待命"))
		return
	if str(worker.target) != str(task.target) or str(worker.get("action", "")) != str(task.action):
		worker.progress = 0.0
	worker.target = str(task.target)
	worker.action = str(task.action)
	worker.work_cell = int(task.cell)
	worker.zone = int(task.get("zone", -1))
	worker.mode = "travel"
	worker.status = str(task.message)

static func begin_manual(data: TerrainData, key: String, cell: Vector2i, action: String = "harvest") -> Dictionary:
	if action not in ["harvest", "survey", "clear"]:
		return fail("INVALID")
	if str(data.site.manual.target) != "":
		return fail("BUSY")
	if str(data.site.worker.target) == key:
		return fail("BUSY", "工人正在處理此來源")
	var r := Env.resource(data, key)
	if r.is_empty():
		return fail("NO_TARGET")
	if not Env.work_cells(data, key).has(cell):
		return fail("UNREACHABLE", "請走到來源旁")
	data.site.manual.target = key
	data.site.manual.progress = 0.0
	data.site.manual.action = "survey" if not bool(r.discovered) else action
	data.site.manual.cell = data.index(cell)
	return ok("開始手動作業；移動或交戰將中斷")

static func mark_combat(data: TerrainData, duration: float = COMBAT_GRACE) -> void:
	if data.site.is_empty():
		return
	data.site.combat_left = maxf(float(data.site.combat_left), duration)
	data.site.manual.target = ""
	data.site.manual.progress = 0.0

static func advance(data: TerrainData, real_seconds: float, worker_ready: bool = false, manual_ready: bool = false, occupied: Callable = Callable()) -> void:
	if data.site.is_empty() or bool(data.site.paused) or real_seconds <= 0.0 or not is_finite(real_seconds):
		return
	# Integrate the combat-to-peace boundary exactly, including long frames.
	var combat_seconds := minf(real_seconds, float(data.site.combat_left))
	data.site.combat_left = maxf(0.0, float(data.site.combat_left) - combat_seconds)
	var minutes := combat_seconds / 60.0 + real_seconds - combat_seconds
	while minutes > 0.00000001:
		var slice := minf(minutes, 1.0 - float(data.site.phase))
		data.site.phase = float(data.site.phase) + slice
		_work(data, slice, worker_ready, manual_ready, occupied)
		minutes -= slice
		if float(data.site.phase) >= 0.99999999:
			data.site.phase = 0.0
			data.site.minute = int(data.site.minute) + 1
			_regenerate(data, occupied)
			allocate_water(data)

static func _work(data: TerrainData, minutes: float, worker_ready: bool, manual_ready: bool, occupied: Callable) -> void:
	var worker: Dictionary = data.site.worker
	if worker_ready and str(worker.mode) == "work" and str(worker.target) != "":
		var target := str(worker.target)
		var cell := data.cell_from_index(int(worker.cell))
		if target.begins_with("feature:"):
			_feature_work(data, target.trim_prefix("feature:"), minutes, occupied)
		elif target == "depot":
			var result := deposit(data, worker.cargo, cell)
			worker.status = str(result.message)
			if result.ok:
				worker.target = ""
				worker.mode = "idle"
		else:
			if str(data.site.manual.target) == target:
				worker.target = ""
				worker.mode = "idle"
				return
			var r := Env.resource(data, target)
			if r.is_empty() or not Env.work_cells(data, target).has(cell):
				worker.target = ""
				worker.mode = "idle"
			else:
				worker.progress = float(worker.progress) + minutes
				var required := 3.0 if str(worker.action) in ["survey", "clear"] else float(Env.WORK_MINUTES[int(r.kind)])
				worker.status = "%s %.1f / %.1f 分" % ["清理" if str(worker.action) == "clear" else "作業", float(worker.progress), required]
				if float(worker.progress) + 0.00000001 >= required:
					var result := harvest(data, target, cell, worker.cargo, str(worker.action))
					worker.status = str(result.message)
					worker.progress = 0.0
					worker.target = ""
					worker.mode = "idle"
	var manual: Dictionary = data.site.manual
	if manual_ready and str(manual.target) != "":
		var r := Env.resource(data, str(manual.target))
		if r.is_empty():
			manual.target = ""
			return
		manual.progress = float(manual.progress) + minutes
		var required := 3.0 if str(manual.action) in ["survey", "clear"] else float(Env.WORK_MINUTES[int(r.kind)])
		if float(manual.progress) + 0.00000001 >= required:
			var result := harvest(data, str(manual.target), data.cell_from_index(int(manual.cell)), manual.cargo, str(manual.action))
			data.site.notices.append(str(result.message))
			manual.target = ""
			manual.progress = 0.0

static func _feature_work(data: TerrainData, key: String, minutes: float, occupied: Callable) -> void:
	var worker: Dictionary = data.site.worker
	if not data.site.features.has(key):
		worker.mode = "idle"
		worker.target = ""
		return
	var feature: Dictionary = data.site.features[key]
	if int(worker.cell) != int(feature.entrance):
		return
	var definition: Dictionary = FEATURES[str(feature.kind)]
	if not can_pay(data.site.inventory, {"tools": 1}):
		worker.status = "缺少工具"
		return
	if str(feature.stage) != "complete":
		for i: int in feature.cells:
			if occupied.is_valid() and bool(occupied.call(data.cell_from_index(i))):
				worker.status = "施工占地有人／已預約，等待移開"
				return
		feature.stage = "building"
		feature.progress = minf(float(feature.work), float(feature.progress) + minutes)
		worker.status = "施工 %.1f / %.1f 分" % [float(feature.progress), float(feature.work)]
		if float(feature.progress) + 0.00000001 < float(feature.work):
			return
		feature.stage = "complete"
		feature.status = "已完成"
		if str(feature.kind) == "level":
			for i: int in feature.cells:
				data.height_levels[i] = int(feature.level)
				data.site.terrain_changes[str(i)] = int(feature.level)
			rebuild_terrain_edges(data)
			data.site.features.erase(key)
		worker.mode = "idle"
		worker.target = ""
		Env.rebuild_indexes(data)
		rebuild_water(data)
		data.site.notices.append(str(definition.name) + "已完成")
		return
	if not definition.has("cycle"):
		worker.mode = "idle"
		worker.target = ""
		return
	if feature.has("species") and (int(feature.residents) > grazing_capacity(data, feature.cells) or int(feature.residents) < (2 if str(feature.species) == "horse" else 1)):
		worker.status = "牧地承載或種畜數量不足"
		return
	if not bool(feature.batch_paid):
		if not can_pay(data.site.inventory, definition.input):
			feature.status = "缺投入：" + items_text(definition.input)
			worker.status = feature.status
			worker.mode = "idle"
			worker.target = ""
			return
		# Workshop inputs are supplied by the single camp store in this first Site.
		# ponytail: one depot; add explicit input hauling when multiple stores exist.
		add_items(data.site.inventory, definition.input, -1)
		feature.batch_paid = true
	var demand := water_demand(feature)
	var water_ratio := 1.0
	if demand > 0.0:
		water_ratio = clampf(float(data.site.water_status.get(key, {}).get("supplied", 0.0)) / demand, 0.0, 1.0)
	if water_ratio <= 0.0:
		feature.status = "缺水，暫停運作"
		worker.status = feature.status
		return
	var productivity := 1.0
	if str(feature.kind) in ["farm", "fiber_farm", "fodder_farm"]:
		var fertility_total := 0.0
		for i: int in feature.cells:
			fertility_total += float(data.fertility[i])
		productivity = clampf(fertility_total / float(feature.cells.size()) / 60.0, 0.25, 1.5)
		# More worked land grows more; keep a batch small enough to carry home.
		productivity *= float(feature.cells.size())
	feature.production = minf(float(definition.cycle), float(feature.production) + minutes * water_ratio * productivity)
	feature.status = "生產 %.1f / %.1f 分" % [float(feature.production), float(definition.cycle)]
	worker.status = feature.status
	if float(feature.production) + 0.00000001 >= float(definition.cycle):
		if inventory_size(worker.cargo) + inventory_size(definition.output) > CARRY_CAPACITY:
			worker.status = "攜帶空間不足"
			return
		add_items(worker.cargo, definition.output)
		feature.production = 0.0
		feature.batch_paid = false
		worker.target = ""
		worker.mode = "idle"
		data.site.total_produced = int(data.site.total_produced) + inventory_size(definition.output)
		data.environment_revision += 1

static func _regenerate(data: TerrainData, occupied: Callable) -> void:
	var rebuild := false
	var keys: Array = data.site.changes.keys()
	keys.sort()
	for key: String in keys:
		var r := Env.resource(data, key)
		if r.is_empty() or bool(r.cleared) or int(r.next_recovery) < 0 or int(r.next_recovery) > int(data.site.minute):
			continue
		var capacity := Env.habitat_capacity(data, key)
		var blocked := data.feature_at[int(r.cell)] != 0
		if bool(r.blocks) and occupied.is_valid() and bool(occupied.call(data.cell_from_index(int(r.cell)))):
			blocked = true
		if blocked or capacity <= int(r.remaining):
			Env.change(data, key, {"next_recovery": int(data.site.minute) + maxi(1, int(r.recover))})
			continue
		var remaining := capacity if int(r.kind) in [Env.Kind.TIMBER, Env.Kind.FOOD, Env.Kind.HERB] else mini(capacity, int(r.remaining) + 1)
		Env.change(data, key, {"remaining": remaining, "next_recovery": int(data.site.minute) + int(r.recover) if remaining < capacity else -1})
		rebuild = true
	if rebuild:
		Env.rebuild_indexes(data)
		rebuild_water(data)

static func rebuild_terrain_edges(data: TerrainData) -> void:
	data.cliff_drops.fill(0)
	for i: int in range(data.flags.size()):
		data.flags[i] &= ~(TerrainData.Flag.CLIFF | TerrainData.Flag.RAMP | TerrainData.Flag.SHORE)
	for i: int in range(data.flags.size()):
		var cell := data.cell_from_index(i)
		for d: int in range(4):
			var next := cell + TerrainData.DIRECTIONS[d]
			if not data.contains(next):
				data.ramp_edges[i] &= ~(1 << d)
				continue
			var j := data.index(next)
			var difference := int(data.height_levels[i]) - int(data.height_levels[j])
			data.cliff_drops[i * 4 + d] = maxi(0, difference)
			if difference > 0:
				data.flags[i] |= TerrainData.Flag.CLIFF
			if absi(difference) != 1 or not data.is_terrain_walkable(cell) or not data.is_terrain_walkable(next):
				data.ramp_edges[i] &= ~(1 << d)
				data.ramp_edges[j] &= ~(1 << ((d + 2) % 4))
			if data.water_kind[j] != 0 and data.water_kind[i] == 0:
				data.flags[i] |= TerrainData.Flag.SHORE
		if data.ramp_edges[i] != 0:
			data.flags[i] |= TerrainData.Flag.RAMP
	data.navigation_revision += 1
	data.environment_revision += 1

static func rebuild_water(data: TerrainData) -> void:
	data.site.water_links = {}
	for key: String in data.site.features:
		var feature: Dictionary = data.site.features[key]
		if str(feature.stage) != "complete" or str(feature.kind) not in ["well", "intake"]:
			continue
		var origin: int = feature.cells[0]
		var visited := {origin: 0}
		var pending: Array[int] = [origin]
		var head := 0
		while head < pending.size():
			var current := pending[head]
			head += 1
			if int(visited[current]) >= 14:
				continue
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var next := data.cell_from_index(current) + direction
				if data.can_step(data.cell_from_index(current), next) and not visited.has(data.index(next)):
					visited[data.index(next)] = int(visited[current]) + 1
					pending.append(data.index(next))
		data.site.water_links[key] = pending
	allocate_water(data)

static func allocate_water(data: TerrainData) -> void:
	var budgets := {}
	var pump_sources := {}
	var keys: Array = data.site.features.keys()
	keys.sort()
	for key: String in data.site.water_links:
		var feature: Dictionary = data.site.features[key]
		var source := str(feature.source)
		if str(feature.kind) == "well":
			var cell := data.cell_from_index(int(feature.cells[0]))
			source = "ground:%d:%d" % [floori(float(cell.x) / 16.0), floori(float(cell.y) / 16.0)]
		pump_sources[key] = source
		budgets[source] = 2.0 if str(feature.kind) == "well" else 6.0
	var consumers: Array[String] = ["camp"]
	for key: String in keys:
		if str(data.site.features[key].kind) == "house":
			consumers.append(key)
	for key: String in keys:
		if str(data.site.features[key].kind) != "house":
			consumers.append(key)
	data.site.water_status = {}
	for key: String in consumers:
		var demand := 0.02
		var target := int(data.site.depot_cell)
		if key != "camp":
			var feature: Dictionary = data.site.features[key]
			if str(feature.stage) != "complete":
				continue
			demand = water_demand(feature)
			target = int(feature.entrance)
		var supplied := 0.0
		for pump_key: String in pump_sources:
			if not data.site.water_links[pump_key].has(target):
				continue
			var source := str(pump_sources[pump_key])
			var portion := minf(demand - supplied, float(budgets[source]))
			supplied += portion
			budgets[source] = float(budgets[source]) - portion
			if supplied >= demand:
				break
		data.site.water_status[key] = {"demand": demand, "supplied": supplied}

static func date_text(data: TerrainData) -> String:
	var minute := int(data.site.get("minute", 0))
	return "第 %d 日  %02d:%02d" % [floori(float(minute) / 1440.0) + 1, floori(float(minute % 1440) / 60.0), minute % 60]
