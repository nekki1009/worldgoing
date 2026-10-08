class_name SiteRuntime
extends RefCounted

const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Ships = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
const EquipmentDye = preload("res://scripts/ui/equipment_dye.gd")
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const TechnologyPolicy = preload("res://scripts/terrain_lab/site_technology_policy.gd")
const TechnologyCatalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")
const COMBAT_GRACE := 10.0
const CARRY_CAPACITY := 20
const ITEM_STORAGE_VERSION := 1
const EQUIPMENT_SLOTS := ["helmet", "outfit", "armor", "cape", "weapon", "shield", "boots"]
const ITEM_FIELDS := ["item_storage_version", "item_definitions", "item_records", "ground_loot", "next_loot", "next_item", "depot_items"]
const EXCHANGE_FIGHTING_POSITION_BONUS := 10.0
const RANGED_RECIPES := {
	"siege_bolt": {"name": "重弩矢", "cost": {"wood": 2, "iron": 1}, "duration": 60.0, "output": {"siege_bolt": 1}},
	"siege_stone": {"name": "石彈", "cost": {"stone": 2}, "duration": 30.0, "output": {"siege_stone": 1}},
	"bow": {"name": "弓", "cost": {"wood": 4, "fiber": 2}, "duration": 120.0, "asset": "bow_01"},
	"crossbow": {"name": "弩", "cost": {"wood": 4, "iron": 2, "fiber": 1}, "duration": 180.0, "asset": "crossbow_01"},
	"arrow": {"name": "箭 ×10", "cost": {"wood": 1, "iron": 1}, "duration": 60.0, "output": {"arrow": 10}},
	"fire_arrow": {"name": "火箭 ×5", "cost": {"arrow": 5, "cloth": 1, "charcoal": 1}, "duration": 60.0, "output": {"fire_arrow": 5}},
	"bolt": {"name": "弩矢 ×10", "cost": {"wood": 1, "iron": 1}, "duration": 60.0, "output": {"bolt": 10}},
	"camp_tent": {"name": "營帳包", "cost": {"cloth": 4, "wood": 2, "fiber": 2}, "duration": 120.0, "output": {"camp_tent": 1}},
}
const SIEGE_DEFINITIONS := {
	"ballista": {"name": "固定重弩", "size": Vector2i(2, 3), "max_hp": 140.0, "capacity": 20,
		"min_crew": 1, "standard_crew": 2, "ammo": "siege_bolt", "move_speed": 0.0, "turn_seconds": 3.0, "turn_radius": 3,
		"crew_offsets": [Vector2i(0, -1), Vector2i(1, -1)], "turn_offsets": [Vector2i(0, -4), Vector2i(1, -4)],
		"cost": {"wood": 24, "iron": 12, "fiber": 10}, "work_seconds": 5400.0},
	"ram": {"name": "衝車", "size": Vector2i(2, 3), "max_hp": 300.0, "capacity": 0,
		"min_crew": 2, "standard_crew": 4, "ammo": "", "move_speed": 0.5, "turn_seconds": 4.0, "turn_radius": 3,
		"crew_offsets": [Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(2, 1)],
		"turn_offsets": [Vector2i(0, -4), Vector2i(1, -4), Vector2i(-1, -4), Vector2i(2, -4)],
		"cost": {"wood": 40, "iron": 8, "fiber": 8, "cloth": 8}, "work_seconds": 7200.0},
	"traction_trebuchet": {"name": "牽引投石機", "size": Vector2i(3, 4), "max_hp": 200.0, "capacity": 12,
		"min_crew": 4, "standard_crew": 8, "ammo": "siege_stone", "move_speed": 0.0, "turn_seconds": 6.0, "turn_radius": 5,
		"crew_offsets": [Vector2i(-1, 0), Vector2i(3, 0), Vector2i(-1, 1), Vector2i(3, 1), Vector2i(-1, 2), Vector2i(3, 2), Vector2i(-1, 3), Vector2i(3, 3)],
		"turn_offsets": [Vector2i(-2, -6), Vector2i(-1, -6), Vector2i(0, -6), Vector2i(1, -6), Vector2i(2, -6), Vector2i(3, -6), Vector2i(4, -6), Vector2i(5, -6)],
		"cost": {"wood": 60, "iron": 12, "fiber": 20}, "work_seconds": 10800.0},
	"counterweight_trebuchet": {"name": "配重投石機", "size": Vector2i(4, 6), "max_hp": 320.0, "capacity": 8,
		"min_crew": 4, "standard_crew": 8, "ammo": "siege_stone", "move_speed": 0.0, "turn_seconds": 10.0, "turn_radius": 7,
		"crew_offsets": [Vector2i(-1, 0), Vector2i(4, 0), Vector2i(-1, 1), Vector2i(4, 1), Vector2i(-1, 3), Vector2i(4, 3), Vector2i(-1, 4), Vector2i(4, 4)],
		"turn_offsets": [Vector2i(-2, -8), Vector2i(-1, -8), Vector2i(0, -8), Vector2i(1, -8), Vector2i(2, -8), Vector2i(3, -8), Vector2i(4, -8), Vector2i(5, -8)],
		"cost": {"wood": 100, "iron": 24, "fiber": 30, "stone": 80}, "work_seconds": 21600.0},
	"siege_tower": {"name": "攻城塔", "size": Vector2i(3, 4), "max_hp": 450.0, "capacity": 0,
		"min_crew": 4, "standard_crew": 8, "ammo": "", "move_speed": 0.25, "turn_seconds": 8.0, "turn_radius": 5,
		"crew_offsets": [Vector2i(-1, 0), Vector2i(3, 0), Vector2i(-1, 1), Vector2i(3, 1), Vector2i(-1, 2), Vector2i(3, 2), Vector2i(-1, 3), Vector2i(3, 3)],
		"turn_offsets": [Vector2i(-2, -6), Vector2i(-1, -6), Vector2i(0, -6), Vector2i(1, -6), Vector2i(2, -6), Vector2i(3, -6), Vector2i(4, -6), Vector2i(5, -6)],
		"cost": {"wood": 120, "iron": 24, "fiber": 24, "cloth": 20}, "work_seconds": 28800.0},
}
const FEATURES := {
	"house": {"placement": "fixed", "size": Vector2i(3, 3), "name": "住宅", "cost": {"wood": 8, "stone": 4}, "work": 15.0, "solid": true, "water": 0.02},
	"warehouse": {"placement": "fixed", "size": Vector2i(3, 2), "name": "倉庫（露天堆棧）", "cost": {"wood": 12, "stone": 4, "rope": 2}, "work": 20.0, "solid": true, "water": 0.0},
	"well": {"placement": "fixed", "size": Vector2i(1, 1), "name": "水井", "cost": {"wood": 4, "stone": 6}, "work": 12.0, "solid": false, "water": 0.0},
	"intake": {"placement": "fixed", "size": Vector2i(2, 1), "name": "取水站", "cost": {"wood": 4, "stone": 2}, "work": 8.0, "solid": false, "water": 0.0},
	"farm": {"placement": "rect", "min_size": Vector2i(2, 2), "max_size": Vector2i(50, 50), "name": "糧食農田", "cost": {}, "work": 6.0, "solid": false, "water": 0.04, "input": {"seeds": 1}, "output": {"grain": 8}, "cycle": 480.0},
	"fiber_farm": {"placement": "rect", "min_size": Vector2i(2, 2), "max_size": Vector2i(50, 50), "name": "纖維農田", "cost": {}, "work": 6.0, "solid": false, "water": 0.03, "input": {"seeds": 1}, "output": {"fiber": 5}, "cycle": 480.0},
	"fodder_farm": {"placement": "rect", "min_size": Vector2i(2, 2), "max_size": Vector2i(50, 50), "name": "飼料農田", "cost": {}, "work": 6.0, "solid": false, "water": 0.03, "input": {"seeds": 1}, "output": {"fodder": 10}, "cycle": 360.0},
	"pasture": {"placement": "rect", "min_size": Vector2i(3, 3), "max_size": Vector2i(50, 50), "name": "養羊牧區", "cost": {"wood": 4, "sheep": 1}, "work": 8.0, "solid": false, "water": 0.03, "input": {"fodder": 1}, "output": {"wool": 2}, "cycle": 240.0},
	"horse_ranch": {"placement": "rect", "min_size": Vector2i(4, 4), "max_size": Vector2i(50, 50), "name": "育馬場", "cost": {"wood": 8, "horse": 2}, "work": 15.0, "solid": false, "water": 0.06, "input": {"fodder": 3}, "output": {"horse": 1}, "cycle": 1440.0},
	"saltworks": {"placement": "fixed", "size": Vector2i(4, 4), "name": "簡易鹽場", "cost": {"wood": 6, "stone": 4, "clay": 2}, "work": 12.0, "solid": true, "water": 0.0, "input": {"brine": 2, "wood": 1}, "output": {"salt": 2}, "cycle": 8.0},
	"kiln": {"placement": "fixed", "size": Vector2i(3, 3), "name": "簡易磚瓦窯", "cost": {"stone": 6, "clay": 4, "wood": 2}, "work": 15.0, "solid": true, "water": 0.0, "input": {"clay": 3, "wood": 1}, "output": {"brick": 3}, "cycle": 12.0},
	"charcoal": {"placement": "fixed", "size": Vector2i(2, 2), "name": "炭窯", "cost": {"stone": 2, "clay": 2}, "work": 8.0, "solid": true, "water": 0.0, "input": {"wood": 4}, "output": {"charcoal": 2}, "cycle": 10.0},
	"smelter": {"placement": "fixed", "size": Vector2i(4, 3), "name": "冶煉作坊", "cost": {"stone": 8, "clay": 4, "wood": 4}, "work": 20.0, "solid": true, "water": 0.0, "input": {"iron_ore": 3, "charcoal": 2}, "output": {"iron": 2}, "cycle": 15.0},
	"smithy": {"placement": "fixed", "size": Vector2i(3, 3), "name": "鐵匠鋪", "cost": {"wood": 8, "stone": 6}, "work": 18.0, "solid": true, "water": 0.0, "input": {"iron": 2, "charcoal": 1, "wood": 1}, "output": {"tools": 1}, "cycle": 12.0},
	"tannery": {"placement": "fixed", "size": Vector2i(4, 3), "name": "製革作坊", "cost": {"wood": 6, "stone": 2}, "work": 10.0, "solid": true, "water": 0.02, "input": {"hide": 2}, "output": {"leather": 2}, "cycle": 15.0},
	"weaver": {"placement": "fixed", "size": Vector2i(3, 3), "name": "織布作坊", "cost": {"wood": 6, "stone": 2}, "work": 10.0, "solid": true, "water": 0.0, "input": {"fiber": 3}, "output": {"cloth": 2}, "cycle": 12.0},
	"road": {"placement": "cells", "name": "土路", "cost": {"stone": 1}, "work": 3.0, "solid": false, "water": 0.0},
	"level": {"placement": "cells", "name": "整平一級地面", "cost": {}, "work": 10.0, "solid": false, "water": 0.0},
	"palisade": {"placement": "cells", "name": "木柵障礙", "cost": {"wood": 4}, "work": 6.0, "solid": true, "water": 0.0},
	"fighting_position": {"placement": "cells", "name": "防禦陣地", "cost": {"wood": 3, "stone": 2}, "work": 8.0, "solid": false, "water": 0.0},
	"stone_wall": {"placement": "cells", "name": "石牆", "cost": {"stone": 6}, "work": 12.0, "solid": true, "water": 0.0},
	"wall_stairs": {"placement": "fixed", "size": Vector2i(1, 2), "name": "上牆樓梯", "cost": {"wood": 8}, "work": 12.0, "solid": false, "water": 0.0},
	"siege_ladder": {"placement": "fixed", "size": Vector2i(1, 2), "name": "攻城梯段", "cost": {"wood": 12, "fiber": 6}, "work": 30.0, "solid": false, "water": 0.0},
	"gate": {"placement": "fixed", "size": Vector2i(4, 3), "name": "城門", "cost": {"wood": 24}, "work": 30.0, "solid": true, "water": 0.0},
	"prison": {"placement": "rect", "min_size": Vector2i(1, 1), "max_size": Vector2i(6, 6), "name": "戰俘營", "cost": {"wood": 4}, "work": 10.0, "solid": false, "water": 0.0},
	# First-version military construction terms are per occupied square, in game minutes.
	"barracks": {"placement": "rect", "min_size": Vector2i(10, 10), "max_size": Vector2i(50, 50), "name": "軍營", "cost": {"wood": 1, "stone": 1}, "work": 2.0, "solid": false, "water": 0.0},
	"training_ground": {"placement": "rect", "min_size": Vector2i(10, 10), "max_size": Vector2i(50, 50), "name": "校場", "cost": {"wood": 1}, "work": 0.5, "solid": false, "water": 0.0},
	"dock": {"placement": "fixed", "size": Vector2i(2, 2), "name": "岸上碼頭", "cost": {"wood": 12, "stone": 4}, "work": 20.0, "solid": false, "water": 0.0},
	"shipyard": {"placement": "fixed", "size": Vector2i(4, 3), "name": "岸上船塢", "cost": {"wood": 24, "stone": 12, "iron": 4}, "work": 60.0, "solid": false, "water": 0.0},
	"bridge": {"placement": "rect", "min_size": Vector2i(1, 2), "max_size": Vector2i(1, 12), "name": "橋梁", "cost": {"wood": 6}, "work": 10.0, "solid": false, "water": 0.0},
	"tent": {"placement": "fixed", "size": Vector2i(3, 3), "name": "營帳", "cost": {"camp_tent": 1}, "work": 2.0, "solid": false, "water": 0.0},
	"settlement_center": {"placement": "fixed", "size": Vector2i(5, 5), "name": "聚落中心", "cost": {"wood": 30, "stone": 20}, "work": 60.0, "solid": true, "water": 0.0},
}
# Alternate recipes share the original feature, paid batch and worker pipeline.
const FEATURE_RECIPES := {
	"kiln": {"pottery": {"name": "陶器", "input": {"clay": 2, "wood": 1}, "output": {"pottery": 2}, "cycle": 10.0, "water": 0.02}},
	"smelter": {"steel": {"name": "煉鋼", "input": {"iron": 2, "charcoal": 2}, "output": {"steel": 1}, "cycle": 20.0, "water": 0.02}},
	"weaver": {
		"rope": {"name": "繩索", "input": {"fiber": 2}, "output": {"rope": 2}, "cycle": 8.0, "water": 0.0},
		"wool_cloth": {"name": "羊毛織布", "input": {"wool": 3}, "output": {"cloth": 2}, "cycle": 15.0, "water": 0.01},
	},
	"smithy": {"steel_tools": {"name": "鋼製工具", "input": {"steel": 1, "charcoal": 1, "wood": 1}, "output": {"tools": 2}, "cycle": 12.0, "water": 0.0}},
}
const CIVIL_KINDS := ["house", "well", "intake", "saltworks", "kiln", "charcoal", "smelter", "smithy", "tannery", "weaver", "warehouse", "dock", "shipyard"]
const CIVIL_VERSION := 1
const CIVIL_MAX_GRADE := 3
# The settlement center shares the civil body/repair contract but is never a
# grade-upgradable civil building; its levels belong to site.settlement.
const BODY_KINDS := CIVIL_KINDS + ["settlement_center"]
const SETTLEMENT_MAX_LEVEL := 3
const SETTLEMENT_LEVEL_TERMS := {
	2: {"cost": {"wood": 20, "stone": 12, "pottery": 4, "rope": 4}, "work": 40.0},
	3: {"cost": {"wood": 30, "stone": 30, "brick": 20, "rope": 8}, "work": 80.0},
}
const BUILDING_LAYOUT_VERSION := 1
const BARRACKS_LAYOUT_VERSION := 2
const BARRACKS_TYPES := {
	"standard": {"name": "西式軍營", "description": "已編成隊伍可在院內訓練，訓練速度提高25%", "training_multiplier": 1.25, "recovery_multiplier": 1.0},
	"chinese": {"name": "中式軍營", "description": "合格駐營者疲勞恢復提高25%", "training_multiplier": 1.0, "recovery_multiplier": 1.25},
}
const FARM_KINDS := ["farm", "fiber_farm", "fodder_farm"]
const PASTURE_KINDS := ["pasture", "horse_ranch"]
const MILITARY_KINDS := ["barracks", "training_ground"]
const WATERFRONT_KINDS := ["dock", "shipyard"]
const STRUCTURE_KINDS := ["palisade", "stone_wall", "wall_stairs", "siege_ladder", "gate"]
const FARM_WORK_SIDE := 6
const LEGACY_LIVESTOCK_LIMIT := 36
const WALL_RISE := 2
const WOOD_PART_HP := 100.0
const STONE_PART_HP := 300.0
const GATE_SECONDS := 3.0
const HOUSE_VARIANTS := {
	"small": {"size": Vector2i(2, 2), "cost": {"wood": 4, "stone": 2}, "work": 10.0, "water": 0.01},
	"standard": {"size": Vector2i(3, 3), "cost": {"wood": 8, "stone": 4}, "work": 15.0, "water": 0.02},
	"long": {"size": Vector2i(4, 3), "cost": {"wood": 12, "stone": 6}, "work": 22.0, "water": 0.03},
	"large": {"size": Vector2i(5, 4), "cost": {"wood": 18, "stone": 10}, "work": 30.0, "water": 0.04},
}
const ERRORS := {
	"NO_TARGET": "目標不存在", "EMPTY": "來源已耗盡／等待恢復", "SURVEY": "請先勘探鐵礦",
	"UNREACHABLE": "沒有可達工作格", "OCCUPIED": "占地或人員預約衝突", "MATERIALS": "缺少材料／工具",
	"STORAGE_FULL": "存放空間不足", "TERRAIN": "地勢或地基不合適", "WATER": "缺少對應水源／供水",
	"BUSY": "工作或戰鬥進行中", "INVALID": "無效命令", "BLOCKED": "作業位置被阻擋", "CAPACITY": "本分鐘來源能力已用盡",
	"STALE_SOURCE": "物品已變更",
	"WAIT_OCCUPANCY": "通道或門扇範圍仍有原人物／已承諾步進",
}

static func fail(code: String, detail: String = "") -> Dictionary:
	return {"ok": false, "code": code, "message": str(ERRORS.get(code, code)) + ("：" + detail if not detail.is_empty() else "")}

static func ok(message: String = "完成", values: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "code": "OK", "message": message}
	result.merge(values, true)
	return result

static func now(data: TerrainData) -> float:
	return float(data.site.minute) + float(data.site.phase)

static func resource_work_minutes(kind: int, action: String) -> float:
	if kind < 0 or kind >= Env.NAMES.size(): return -1.0
	if action == "restore": return 60.0 if kind in Env.RESTORABLE_KINDS else -1.0
	if action in ["survey", "clear"]: return 3.0
	return float(Env.WORK_MINUTES[kind]) if action in ["harvest", "capture"] else -1.0

static func ecology_reconcile(data: TerrainData, keys: Array[String] = []) -> Dictionary:
	if data == null or data.site.is_empty(): return fail("NO_TARGET")
	if not Env.ecology_active(data): return fail("ECOLOGY_PENDING", "原生態候選尚未准入")
	var selected: Array[String] = []
	if keys.is_empty(): selected.assign(data.resource_base.keys())
	else: selected.assign(keys)
	selected.sort()
	var plans := {}
	for key: String in selected:
		if plans.has(key): continue
		var r := Env.resource(data, key)
		if r.is_empty(): return fail("NO_TARGET", key)
		var fields := {}
		if int(r.kind) in Env.ECOLOGY_KINDS:
			var capacity := Env.habitat_capacity(data, key)
			if int(r.kind) in Env.POPULATION_KINDS and (not keys.is_empty() or data.site.changes.has(key) or capacity != int(r.capacity)):
				fields["eco_resting"] = Env.ecology_resting(int(r.remaining), capacity, r.get("eco_resting"))
			if not bool(r.cleared) and int(r.recover) > 0 and int(r.remaining) < capacity and int(r.next_recovery) < 0:
				fields["next_recovery"] = ceili(now(data)) + int(r.recover)
		plans[key] = fields
	var changed := 0
	for key: String in plans:
		var fields: Dictionary = plans[key]
		if fields.is_empty(): continue
		var current := Env.resource(data, key)
		var different := false
		for field: String in fields:
			if not current.has(field) or current[field] != fields[field]: different = true
		if different:
			Env.change(data, key, fields)
			changed += 1
	return ok("原生態來源已對齊", {"changed": changed})

# Internal commit after the original settlement/person command owner authorizes every key.
static func ecology_set_modes(data: TerrainData, keys: Array[String], mode: String) -> Dictionary:
	if data == null or data.site.is_empty(): return fail("NO_TARGET")
	if not Env.ecology_active(data): return fail("ECOLOGY_PENDING", "原生態候選尚未准入")
	if mode not in Env.ECOLOGY_MODES or keys.is_empty(): return fail("INVALID")
	var selected: Array[String] = []
	for key: String in keys:
		var r := Env.resource(data, key)
		if r.is_empty() or int(r.kind) not in Env.ECOLOGY_KINDS: return fail("INVALID", "只管理原有可更新來源")
		if not selected.has(key): selected.append(key)
	selected.sort()
	for key: String in selected: Env.change(data, key, {"eco_mode": mode})
	return ok("已設定原來源生態政策", {"sources": selected.size(), "mode": mode})

static func ecology_action_guard(data: TerrainData, key: String, action: String) -> Dictionary:
	var r := Env.resource(data, key)
	if r.is_empty(): return fail("NO_TARGET")
	var admitted := Env.ecology_active(data)
	if data.site.has("ecology_version") and not admitted: return fail("ECOLOGY_PENDING", "不支援的原生態合同")
	if action == "restore":
		if not admitted: return fail("ECOLOGY_PENDING", "復育須先完成原生態候選准入")
		if int(r.kind) not in Env.RESTORABLE_KINDS or not bool(r.cleared) or int(r.remaining) != 0:
			return fail("INVALID", "只能復育原已清除且零量的植物來源")
		if data.feature_at[int(r.cell)] != 0: return fail("OCCUPIED", "原復育地仍有人工占用")
		if not Env.ecology_cell_usable(data, r, int(r.cell)): return fail("TERRAIN", "原位置不適合自然更新")
		return _fire_resource_restored(data, key, true)
	if not admitted or int(r.kind) not in Env.ECOLOGY_KINDS or action == "survey": return ok()
	var info := Env.ecology_info(data, key)
	if str(info.mode) == "protected": return fail("ECOLOGY_PROTECTED", "原來源休養保護中")
	if int(r.kind) in Env.POPULATION_KINDS and action in ["harvest", "capture"]:
		if int(info.capacity) <= 0 or str(info.recovery_blocked) == "NO_WORK_CELL": return fail("ECOLOGY_HABITAT", "原棲地沒有可作業空間")
		if str(info.mode) == "sustainable" and (bool(info.resting) or int(info.capacity) <= 1 or int(info.takeable) <= 0):
			return fail("ECOLOGY_RESTING", "原来源休採，等待恢復至 %d" % int(info.resume))
	return ok()

# Only explicit original-person/team relationships grant corps authority.
# The lookup is supplied by the live owner; saved Army snapshots are not live people.
static func authorize_corps_reposition(data: TerrainData, requester_id: int, target_team: TerrainArmy, person_query: Callable) -> Dictionary:
	if data == null or not is_instance_valid(target_team) or target_team.data != data or not target_team.combat_enabled:
		return fail("NO_TARGET", "轉進隊伍不在目前地圖")
	var corps: Variant = data.site.get("corps", {})
	if not _valid_corps_shape(corps):
		return fail("CORRUPT_STATE", "軍團關係欄位非法")
	var corps_id := ""
	for key: String in corps:
		var relation: Dictionary = corps[key]
		if int(relation.commander_person_id) == requester_id and target_team.team_id in relation.team_ids:
			corps_id = key
			break
	if corps_id.is_empty() or not person_query.is_valid():
		return fail("NO_AUTHORITY", "只有明確任命的軍團長可命令所屬隊伍轉進")
	var person: Variant = person_query.call(requester_id)
	if not person is Dictionary or not person.get("owner") is Object or not is_instance_valid(person.owner) or not person.get("unit") is int:
		return fail("NO_AUTHORITY", "原軍團長不在目前地圖")
	var owner: Object = person.owner
	var unit: int = person.unit
	var eligible := false
	if owner is TerrainArmy:
		eligible = owner.data == data and owner.combat_enabled and owner.faction_id == target_team.faction_id \
			and unit >= 0 and unit < owner.combat_units.size() and owner.combat_identity(unit) == requester_id and owner.combat_can_act(unit)
	elif owner is TerrainTestCharacter:
		eligible = unit == -1 and owner.data == data and owner.faction_id == target_team.faction_id \
			and owner.combat_identity() == requester_id and owner.can_act()
	if not eligible:
		return fail("NO_AUTHORITY", "軍團長須為同陣營、在場且清醒自由的原人物")
	return ok("軍團長轉進權限已確認", {"corps_id": corps_id})

# Both reference maps contain stable original ID -> faction ID, never new people.
static func valid_corps(value: Variant, people: Dictionary, teams: Dictionary) -> bool:
	if not _valid_corps_shape(value):
		return false
	for relation: Dictionary in value.values():
		var commander := int(relation.commander_person_id)
		if not people.has(commander):
			return false
		for identity: Variant in relation.team_ids:
			if not teams.has(int(identity)) or int(teams[int(identity)]) != int(people[commander]):
				return false
	return true

static func _valid_corps_shape(value: Variant) -> bool:
	if not value is Dictionary or value.size() > 3:
		return false
	var assigned := {}
	for key: Variant in value:
		if not key is String or key.is_empty() or key.length() > 32:
			return false
		for character: String in key:
			if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
				return false
		var relation: Variant = value[key]
		if not relation is Dictionary or relation.size() != 3 or not _corps_identity(relation.get("version")) or int(relation.version) != 1 \
			or not _corps_identity(relation.get("commander_person_id")) or not relation.get("team_ids") is Array \
			or relation.team_ids.is_empty() or relation.team_ids.size() > 3:
			return false
		for identity: Variant in relation.team_ids:
			if not _corps_identity(identity) or assigned.has(int(identity)):
				return false
			assigned[int(identity)] = true
	return true

static func _corps_identity(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) \
		and float(value) >= 1.0 and float(value) <= 2147483647.0

static func exchange_facility_bonus(data: TerrainData, cell: Vector2i) -> float:
	# Read the existing derived cell index, never scan all buildings per exchange.
	# The current occupant benefits; this first rule does not invent faction ownership.
	if data == null or data.site.is_empty() or not data.contains(cell) or data.feature_at.is_empty():
		return 0.0
	var identity := data.feature_at[data.index(cell)]
	if identity == 0:
		return 0.0
	var feature: Dictionary = data.site.features.get(str(identity), {})
	return EXCHANGE_FIGHTING_POSITION_BONUS if str(feature.get("kind", "")) == "fighting_position" and str(feature.get("stage", "")) == "complete" else 0.0

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

# Called only at initialization / explicit legacy migration, never to refill equipment.
static func initialize_item_storage(state: Dictionary) -> Dictionary:
	if state.has("item_storage_version"):
		if state.item_storage_version != ITEM_STORAGE_VERSION:
			return fail("SAVE_VERSION", "物品資料版本")
		for field: String in ITEM_FIELDS:
			if not state.has(field):
				return fail("CORRUPT_SAVE", "物品資料欄位缺失")
		return ok()
	for field: String in ITEM_FIELDS:
		if state.has(field):
			return fail("CORRUPT_SAVE", "物品資料缺少版本")
	state.merge({"item_storage_version": ITEM_STORAGE_VERSION, "item_definitions": {}, "item_records": {},
		"ground_loot": {}, "next_loot": 1, "next_item": 1, "depot_items": new_item_state("depot")})
	return ok()

static func new_item_state(holder: String) -> Dictionary:
	return {"holder": holder, "version": 0, "item_ids": [], "equipped": {}}

# Explicit legacy/new-person migration. An initialized empty holder stays empty.
# Preflight the complete recipe before allocating any globally unique item.
static func seed_person_equipment(data: TerrainData, holder: Dictionary, person_id: int, appearance: Dictionary) -> Dictionary:
	if not holder.is_empty():
		return ok() if _item_holder_shape(holder) and holder.holder == "person:%d" % person_id else fail("INVALID", "人物物品持有人")
	if not HumanCharacter3DEditor.valid_appearance(appearance) or person_id <= 0 or person_id > 2147483647:
		return fail("INVALID", "原人物配裝")
	var initialized := initialize_item_storage(data.site)
	if not initialized.ok:
		return initialized
	var definitions := {}
	for slot: String in EQUIPMENT_SLOTS:
		var asset := str(appearance.parts[slot])
		if asset == "none":
			continue
		var key := slot + ":" + asset
		var definition := {"slot": slot, "asset": asset, "tint": [1.0, 1.0, 1.0, 1.0]}
		if data.site.item_definitions.has(key) and data.site.item_definitions[key] != definition:
			return fail("INVALID", "既有裝備定義衝突")
		definitions[key] = definition
	if int(data.site.next_item) + definitions.size() >= 2147483647:
		return fail("INVALID", "物品序號已用盡")
	for offset in range(definitions.size()):
		if data.site.item_records.has(str(int(data.site.next_item) + offset)):
			return fail("INVALID", "物品序號重複")
	holder.merge(new_item_state("person:%d" % person_id))
	for key: String in definitions:
		var created := create_equipment(data, holder, key, definitions[key], person_id, str(definitions[key].slot))
		assert(created.ok) # Complete preflight above; no callbacks/yields in commit.
		var slot := str(definitions[key].slot)
		if appearance.get("equipment_dyes", {}).has(slot):
			data.site.item_records[created.item_id].dye_color = appearance.equipment_dyes[slot]
	return ok("原有配裝已登記為實物")

# Read-only projection. Body/face/hair remain the original person's appearance;
# every removable slot is reconstructed solely from its current actual holder.
static func equipment_appearance(data: TerrainData, holder: Dictionary, original: Dictionary, saved_state: Dictionary = {}) -> Dictionary:
	if not HumanCharacter3DEditor.valid_appearance(original) or not _item_holder_shape(holder):
		return {}
	var appearance := original.duplicate(true)
	# Private snapshots cannot be changed by item coercion callbacks.
	var validated_parts: Dictionary = appearance.parts.duplicate()
	var validated_dyes: Dictionary = appearance.get("equipment_dyes", {}).duplicate()
	var state := data.site if saved_state.is_empty() else saved_state
	appearance.erase("equipment_dyes")
	for slot: String in EQUIPMENT_SLOTS:
		appearance.parts[slot] = "none"
	for slot: String in holder.equipped:
		if slot not in EQUIPMENT_SLOTS:
			return {}
		var record: Dictionary = state.get("item_records", {}).get(holder.equipped[slot], {})
		var definition: Dictionary = state.get("item_definitions", {}).get(str(record.get("definition", "")), {})
		if record.get("holder") != holder.holder or definition.get("slot") != slot:
			return {}
		appearance.parts[slot] = str(definition.asset)
		var dye := item_dye(record, definition)
		if not dye.is_empty():
			if not appearance.has("equipment_dyes"): appearance.equipment_dyes = {}
			appearance.equipment_dyes[slot] = dye
	if appearance.parts == validated_parts and appearance.get("equipment_dyes", {}) == validated_dyes:
		return appearance
	return appearance if HumanCharacter3DEditor.valid_appearance(appearance) else {}

static func item_dye(record: Dictionary, definition: Dictionary) -> String:
	if record.has("dye_color"):
		return str(record.dye_color)
	var tint: Array = definition.get("tint", [1.0, 1.0, 1.0, 1.0])
	return "" if tint == [1.0, 1.0, 1.0, 1.0] else Color(tint[0], tint[1], tint[2], tint[3]).to_html()

# Atomic cosmetic edit on the existing real holder; the scene owner checks
# authority/readiness and renderer admission before requesting this commit.
static func dye_equipment(data: TerrainData, holder: Dictionary, changes: Dictionary, expected_version: int, preview: bool = false) -> Dictionary:
	if not _item_holder_shape(holder) or not EquipmentDye.valid_dyes(changes, {}, true) or changes.is_empty():
		return fail("INVALID", "五部位染色資料")
	if int(holder.version) != expected_version or expected_version >= 2147483646:
		return fail("STALE_SOURCE")
	for slot: String in changes:
		var identity := str(holder.equipped.get(slot, ""))
		var record: Dictionary = data.site.item_records.get(identity, {})
		var definition: Dictionary = data.site.item_definitions.get(str(record.get("definition", "")), {})
		if not holder.item_ids.has(identity) or record.get("holder") != holder.holder or definition.get("slot") != slot:
			return fail("NO_TARGET", "只能染本人實際穿戴的裝備")
	if preview:
		return ok()
	for slot: String in changes:
		var record: Dictionary = data.site.item_records[holder.equipped[slot]]
		if changes[slot] == "": record.erase("dye_color")
		else: record.dye_color = str(changes[slot]).to_lower()
	holder.version = expected_version + 1
	return ok("已保存實際裝備染色；轉手後仍保留")

static func carried_size(cargo: Dictionary, item_state: Dictionary) -> int:
	return inventory_size(cargo) + item_state.item_ids.size() - item_state.equipped.size()

static func opened_food(state: Dictionary, item_state: Dictionary) -> float:
	var holder := str(item_state.get("holder", ""))
	return float(state.get("person_supply", {}).get(holder.trim_prefix("person:"), {}).get("open_rations", 0.0)) if holder.begins_with("person:") else float(item_state.get("open_rations", 0.0))

static func carried_load(state: Dictionary, cargo: Dictionary, item_state: Dictionary) -> float:
	return float(carried_size(cargo, item_state)) + opened_food(state, item_state)

# Explicit real-item creation for initialization/production, not an appearance getter.
static func create_equipment(data: TerrainData, destination: Dictionary, definition_id: String, definition: Dictionary, original_owner: int, slot: String = "") -> Dictionary:
	var prepared := prepare_equipment_creation(data, destination, [{"definition_id": definition_id, "definition": definition, "slot": slot}], original_owner)
	if not prepared.ok: return prepared
	_publish_equipment_creation(data, prepared)
	return ok("已建立實際物品", {"item_id": str(prepared.item_ids[0])})

static func ranged_craft(data: TerrainData, recipe_id: String, original_owner: int, preview: bool = false) -> Dictionary:
	if data == null or not RANGED_RECIPES.has(recipe_id) or original_owner <= 0 or original_owner > 2147483647:
		return fail("INVALID", "遠程手作配方／原人物")
	var state: Dictionary = data.site
	if int(state.get("item_storage_version", -1)) != ITEM_STORAGE_VERSION or not state.get("inventory") is Dictionary \
		or not state.get("depot_items") is Dictionary or not _item_holder_shape(state.depot_items) \
		or str(state.depot_items.holder) != "depot" or not _resource_stack(state.inventory):
		return fail("INVALID", "原營地實物資料未就緒")
	var stock: Dictionary = state.inventory
	var depot: Dictionary = state.depot_items
	var recipe: Dictionary = RANGED_RECIPES[recipe_id]
	if int(stock.get("tools", 0)) < 1 or not can_pay(stock, recipe.cost):
		return fail("MATERIALS", "營地須保有工具 1（不消耗）及 " + items_text(recipe.cost))
	var output: Dictionary = recipe.get("output", {})
	var equipment := recipe.has("asset")
	var final_load := carried_load(state, stock, depot) - inventory_size(recipe.cost) + (1 if equipment else inventory_size(output))
	if final_load > float(state.get("capacity", 0)):
		return fail("STORAGE_FULL", "材料消耗後仍須容納完整製品")
	if int(depot.version) >= 2147483646:
		return fail("STALE_SOURCE", "營地提交版本已用盡")
	var definition := {}
	var definition_id := ""
	if equipment:
		definition_id = "weapon:" + str(recipe.asset)
		definition = {"slot": "weapon", "asset": str(recipe.asset), "tint": [1.0, 1.0, 1.0, 1.0]}
		if not state.get("item_definitions") is Dictionary or not state.get("item_records") is Dictionary:
			return fail("INVALID", "原裝備登記未就緒")
		if state.item_definitions.has(definition_id) and state.item_definitions[definition_id] != definition:
			return fail("INVALID", "不能覆寫既有共用物品定義")
		if int(state.get("next_item", 0)) <= 0 or int(state.next_item) >= 2147483647 or state.item_records.has(str(int(state.next_item))):
			return fail("INVALID", "物品序號無效或重複")
	else:
		for resource: String in output:
			if int(stock.get(resource, 0)) + int(output[resource]) > 1000000:
				return fail("STORAGE_FULL", "原資源堆疊已達上限")
	if preview:
		return ok("可開始營地手作", {"seconds": float(recipe.duration)})
	# No callback/yield in this commit. Original creation can reject before any
	# mutation; after successful allocation all remaining dictionary updates are infallible.
	var result := create_equipment(data, depot, definition_id, definition, original_owner) if equipment else ok()
	if not result.ok:
		return result
	add_items(stock, recipe.cost, -1)
	for resource: String in recipe.cost:
		if int(stock[resource]) == 0:
			stock.erase(resource)
	if not equipment:
		add_items(stock, output)
		depot.version = int(depot.version) + 1
	data.environment_revision += 1
	result.message = "已手作並存入原營地：" + str(recipe.name)
	return result

# The caller owns action/KO/distance/authority checks and supplies the ORIGINAL
# holder and cargo dictionaries. Preserve their identity: ammo uses the same cargo.
static func transfer_items(data: TerrainData, source: Dictionary, source_cargo: Dictionary, destination: Dictionary, destination_cargo: Dictionary, resources: Dictionary, item_ids: Array, expected_source_version: int, expected_destination_version: int, capacity: int = CARRY_CAPACITY, preserve_slots: bool = false, preview: bool = false) -> Dictionary:
	resources = resources.duplicate() # "Take all" may pass the source cargo itself.
	if not _item_holder_shape(source) or not _item_holder_shape(destination) or str(source.holder) == str(destination.holder) or is_same(source_cargo, destination_cargo):
		return fail("INVALID", "物品持有人")
	if int(source.version) != expected_source_version or int(destination.version) != expected_destination_version:
		return fail("STALE_SOURCE", "物品來源或接收方已改變，請重新選擇")
	if int(source.version) >= 2147483646 or int(destination.version) >= 2147483646:
		return fail("STALE_SOURCE", "物品提交版本已用盡，未轉移")
	if not _resource_stack(resources, false) or not _resource_stack(source_cargo) or not _resource_stack(destination_cargo):
		return fail("INVALID", "資源數量")
	if resources.is_empty() and item_ids.is_empty():
		return fail("EMPTY")
	if not can_pay(source_cargo, resources):
		return fail("EMPTY", "來源數量已不足")
	var selected := {}
	var retained_slots := {}
	for identity: Variant in item_ids:
		if not identity is String or selected.has(identity) or not source.item_ids.has(identity) or destination.item_ids.has(identity):
			return fail("INVALID", "物品不存在或重複")
		var record: Dictionary = data.site.get("item_records", {}).get(identity, {})
		if str(record.get("holder", "")) != str(source.holder) or not data.site.item_definitions.has(str(record.get("definition", ""))):
			return fail("STALE_SOURCE", "物品已不在原持有人處")
		selected[identity] = true
	for slot: String in source.equipped:
		if selected.has(source.equipped[slot]):
			retained_slots[slot] = source.equipped[slot]
	if preserve_slots:
		for slot: String in retained_slots:
			if destination.equipped.has(slot):
				return fail("OCCUPIED", "接收裝備槽")
	var added_size := inventory_size(resources) + item_ids.size() - (retained_slots.size() if preserve_slots else 0)
	if capacity < 0 or carried_load(data.site, destination_cargo, destination) + added_size > capacity:
		return fail("STORAGE_FULL")
	if data.item_transfer_guard.is_valid():
		var guard: Dictionary = data.item_transfer_guard.call(source, destination, resources, item_ids)
		if not guard.ok: return guard
	if preview:
		return ok()
	# No callbacks/yields after this point: both resource and equipment ownership commit once.
	add_items(source_cargo, resources, -1)
	for resource: String in source_cargo.keys():
		if int(source_cargo[resource]) == 0:
			source_cargo.erase(resource)
	add_items(destination_cargo, resources)
	for identity: String in selected:
		source.item_ids.erase(identity)
		destination.item_ids.append(identity)
		data.site.item_records[identity].holder = str(destination.holder)
	for slot: String in retained_slots:
		source.equipped.erase(slot)
		if preserve_slots:
			destination.equipped[slot] = retained_slots[slot]
	source.version = int(source.version) + 1
	destination.version = int(destination.version) + 1
	# Item ownership does not rebuild terrain/resource heatmaps on every loot step.
	return ok("物品已轉移", {"source_version": source.version, "destination_version": destination.version})

# One corpse/bag is one sparse container. Empty sources never create another drop.
static func leave_ground_loot(data: TerrainData, source: Dictionary, source_cargo: Dictionary, original_owner: int, cell: Vector2i, kind: String, resources: Dictionary, item_ids: Array, expected_version: int, source_open: Dictionary = {}, open_amount: float = 0.0, preview: bool = false, ship_location: Dictionary = {}) -> Dictionary:
	resources = resources.duplicate()
	for resource: Variant in resources.keys():
		if resources[resource] is int and int(resources[resource]) == 0:
			resources.erase(resource) # Spent ammo may leave a zero stack on the original person.
	if (not data.is_walkable(cell) if ship_location.is_empty() else not valid_ship_loot_location(data, ship_location)) or original_owner <= 0 or original_owner > 2147483647 or kind not in ["remains", "sealed", "cargo"]:
		return fail("INVALID", "遺留物位置／物主")
	if not data.site.has("ground_loot"):
		return fail("INVALID", "請先初始化物品資料")
	if not is_finite(open_amount) or open_amount < 0.0 or open_amount > 1000000.0:
		return fail("INVALID", "開封口糧數量")
	if open_amount > 0.0:
		var available: Variant = source_open.get("open_rations")
		if not (available is int or available is float) or not is_finite(float(available)) or float(available) < open_amount or float(available) > 1000000.0:
			return fail("EMPTY", "原開封口糧不足或無效")
		if not _item_holder_shape(source) or not _resource_stack(source_cargo) or int(source.version) != expected_version:
			return fail("STALE_SOURCE", "原搬運者或共有口糧已變更")
		if int(source.version) >= 2147483646:
			return fail("STALE_SOURCE", "物品提交版本已用盡，未轉移")
		if not _resource_stack(resources, false) or float(inventory_size(resources) + item_ids.size()) + open_amount > 1000000.0:
			return fail("STORAGE_FULL", "現場口糧容器超量")
	var identity := str(int(data.site.next_loot))
	if int(data.site.next_loot) >= 2147483647 or data.site.ground_loot.has(identity):
		return fail("INVALID", "遺留物序號重複")
	var container := new_item_state("ground:" + identity)
	container.merge({"kind": kind, "original_owner": original_owner, "cargo": {}})
	if ship_location.is_empty(): container.cell = data.index(cell)
	else: container.merge(ship_location.duplicate(true))
	if open_amount > 0.0 and data.item_transfer_guard.is_valid():
		var guard: Dictionary = data.item_transfer_guard.call(source, container, resources, item_ids, open_amount)
		if not guard.ok: return guard
	if resources.is_empty() and item_ids.is_empty() and open_amount > 0.0:
		# Pure opened food still has the original supply pool; do not manufacture
		# an integer grain item or silently round a fraction out of existence.
		if not preview:
			source.version = int(source.version) + 1
			container.version = 1
	else:
		var result := transfer_items(data, source, source_cargo, container, container.cargo, resources, item_ids, expected_version, 0, 1000000, kind == "remains", preview)
		if not result.ok:
			return result
	if preview:
		return ok()
	if open_amount > 0.0:
		source_open.open_rations = float(source_open.open_rations) - open_amount
		container["open_rations"] = open_amount
	data.site.next_loot = int(data.site.next_loot) + 1
	data.site.ground_loot[identity] = container
	if ship_location.is_empty():
		if not data.ground_loot_at.has(int(container.cell)):
			data.ground_loot_at[int(container.cell)] = []
		data.ground_loot_at[int(container.cell)].append(identity)
		data.ground_loot_dirty_rows[cell.y] = true
	return ok("物品留在現場", {"container_id": identity})

# Format-3 compatibility after Store has validated and normalized the original
# snapshots. Earlier settled deaths could leave opened food in their private
# pool. Plan ALL people before modifying any original holder, pool or container.
static func migrate_settled_opened_food(data: TerrainData) -> Dictionary:
	var people: Array[Dictionary] = []
	for key: String in data.site.get("actors", {}):
		people.append({"body": data.site.actors[key], "cargo": data.site.manual.cargo if key == "player" else data.site.worker.cargo})
	for team: Dictionary in data.site.get("armies", []):
		for row: Dictionary in team.units:
			people.append({"body": row, "cargo": row.get("cargo", {})})
	var plans: Array[Dictionary] = []
	var new_containers := 0
	for person: Dictionary in people:
		var body: Dictionary = person.body
		if float(body.hp) > 0.0 or not bool(body.get("loot_settled", false)):
			continue
		var pool: Dictionary = data.site.get("person_supply", {}).get(str(int(body.person_id)), {})
		var amount := float(pool.get("open_rations", 0.0))
		if amount == 0.0:
			continue
		if not is_finite(amount) or amount < 0.0 or amount > 1000000.0 or not _item_holder_shape(body.item_state) or int(body.item_state.version) >= 2147483646 or not body.item_state.item_ids.is_empty() or inventory_size(person.cargo) != 0:
			return fail("CORRUPT_SAVE", "原死者開封餐份／已結算持物無效")
		var cell := Vector2i(int(body.cell[0]), int(body.cell[1]))
		var container: Dictionary = data.site.ground_loot.get(str(body.get("remains_id", "")), {})
		if not container.is_empty():
			var previous := float(container.get("open_rations", 0.0))
			if not _item_holder_shape(container) or int(container.version) >= 2147483646 or container.kind != "remains" or int(container.original_owner) != int(body.person_id) or not is_finite(previous) or previous < 0.0 or float(carried_size(container.cargo, container)) + previous + amount > 1000000.0:
				return fail("CORRUPT_SAVE", "原死者餘糧無法併回同一遺物")
		else:
			var checked := leave_ground_loot(data, body.item_state, person.cargo, int(body.person_id), cell, "remains", {}, [], int(body.item_state.version), pool, amount, true)
			if not checked.ok:
				return checked
			new_containers += 1
		plans.append({"body": body, "cargo": person.cargo, "pool": pool, "amount": amount, "cell": cell, "container": container})
	if int(data.site.next_loot) + new_containers > 2147483647:
		return fail("CORRUPT_SAVE", "舊遺物餘糧所需容器序號不足")
	for offset: int in range(new_containers):
		if data.site.ground_loot.has(str(int(data.site.next_loot) + offset)):
			return fail("CORRUPT_SAVE", "舊遺物餘糧容器序號衝突")
	# No callbacks or yields: this commits only the already validated plan.
	for plan: Dictionary in plans:
		if plan.container.is_empty():
			var dropped := leave_ground_loot(data, plan.body.item_state, plan.cargo, int(plan.body.person_id), plan.cell, "remains", {}, [], int(plan.body.item_state.version), plan.pool, float(plan.amount))
			assert(dropped.ok)
			plan.body.remains_id = str(dropped.container_id)
		else:
			plan.container["open_rations"] = float(plan.container.get("open_rations", 0.0)) + float(plan.amount)
			plan.container.version = int(plan.container.version) + 1
			plan.body.item_state.version = int(plan.body.item_state.version) + 1
			plan.pool.open_rations = 0.0
			data.ground_loot_dirty_rows[data.cell_from_index(int(plan.container.cell)).y] = true
	return ok("原死者餘糧已併回實際遺物", {"migrated": plans.size()})

static func clear_empty_ground_loot(data: TerrainData, identity: String) -> Dictionary:
	var container: Dictionary = data.site.get("ground_loot", {}).get(identity, {})
	if container.is_empty():
		return fail("NO_TARGET")
	if inventory_size(container.cargo) > 0 or not container.item_ids.is_empty() or float(container.get("open_rations", 0.0)) > 0.0:
		return fail("BUSY", "不能刪除尚有物品的遺留物")
	data.site.ground_loot.erase(identity)
	if container.has("cell"):
		var cell := int(container.cell)
		if data.ground_loot_at.has(cell):
			data.ground_loot_at[cell].erase(identity)
			if data.ground_loot_at[cell].is_empty(): data.ground_loot_at.erase(cell)
		data.ground_loot_dirty_rows[data.cell_from_index(cell).y] = true
	for team: Dictionary in data.site.get("armies", []):
		for person: Dictionary in team.get("units", []):
			if str(person.get("remains_id", "")) == identity: person.remains_id = ""
	for person: Dictionary in data.site.get("actors", {}).values():
		if str(person.get("remains_id", "")) == identity: person.remains_id = ""
	if data.ground_loot_removed.is_valid(): data.ground_loot_removed.call(identity)
	return ok()

static func rebuild_loot_index(data: TerrainData) -> void:
	data.ground_loot_at.clear()
	data.ground_loot_dirty_rows.clear()
	for identity: String in data.site.get("ground_loot", {}):
		if data.site.ground_loot[identity].has("vehicle_id"): continue
		var cell := int(data.site.ground_loot[identity].cell)
		if not data.ground_loot_at.has(cell):
			data.ground_loot_at[cell] = []
		data.ground_loot_at[cell].append(identity)
		data.ground_loot_dirty_rows[data.cell_from_index(cell).y] = true

static func valid_item_definition(identity: Variant, value: Variant) -> bool:
	if not identity is String or identity.is_empty() or identity.length() > 128 or not value is Dictionary:
		return false
	if value.size() != 3 or not value.get("slot") is String or value.slot.is_empty() or value.slot.length() > 64 or not value.get("asset") is String or value.asset.is_empty() or value.asset.length() > 256:
		return false
	if not value.get("tint") is Array or value.tint.size() != 4:
		return false
	for component: Variant in value.tint:
		if not (component is int or component is float) or not is_finite(float(component)) or float(component) < 0.0 or float(component) > 1.0:
			return false
	return true

static func _item_holder_shape(value: Dictionary) -> bool:
	if not value.get("holder") is String or value.holder.is_empty() or not value.get("version") is int or int(value.version) < 0 or int(value.version) >= 2147483647 or not value.get("item_ids") is Array or not value.get("equipped") is Dictionary:
		return false
	var ids := {}
	var worn := {}
	for identity: Variant in value.item_ids:
		if not identity is String or ids.has(identity):
			return false
		ids[identity] = true
	for slot: Variant in value.equipped:
		var identity: Variant = value.equipped[slot]
		if not slot is String or not identity is String or not ids.has(identity) or worn.has(identity):
			return false
		worn[identity] = true
	return true

static func _resource_stack(value: Dictionary, allow_zero: bool = true) -> bool:
	for key: Variant in value:
		if not (key is String or key is StringName) or not Env.ITEM_NAMES.has(str(key)) or not value[key] is int or int(value[key]) < (0 if allow_zero else 1) or int(value[key]) > 1000000:
			return false
	return true

static func harvest(data: TerrainData, key: String, actor_cell: Vector2i, cargo: Dictionary, action: String = "harvest", preview: bool = false, carry_limit: int = CARRY_CAPACITY) -> Dictionary:
	if action not in ["harvest", "survey", "clear", "capture", "restore"]:
		return fail("INVALID")
	var r := Env.resource(data, key)
	if r.is_empty():
		return fail("NO_TARGET")
	var captured_species := capturable_species(r) if action == "capture" else ""
	if action == "capture" and captured_species.is_empty():
		return fail("INVALID", "只有野馬與羊可活捉")
	if not Env.work_cells(data, key).has(actor_cell):
		return fail("UNREACHABLE")
	if not can_pay(data.site.inventory, {"tools": 1}):
		return fail("MATERIALS", "工具")
	if action == "survey":
		if not preview:
			Env.change(data, key, {"discovered": true})
		return ok("勘探完成")
	if not bool(r.discovered):
		return fail("SURVEY")
	var ecological := ecology_action_guard(data, key, action)
	if not ecological.ok: return ecological
	if action == "restore":
		if not preview:
			var original_fire := _fire_resource_restored(data, key)
			if not original_fire.ok: return original_fire
			Env.change(data, key, {"cleared": false, "remaining": 0, "next_recovery": ceili(now(data)) + int(r.recover)})
			Env.rebuild_indexes(data)
			rebuild_water(data)
		return ok("復育作業完成，等待自然生長", {"restored": true, "items": {}, "taken": 0})
	if bool(r.cleared):
		return fail("EMPTY")
	var kind := int(r.kind)
	var taken := mini(int(r.remaining), int(Env.BATCH[kind]))
	if Env.ecology_active(data) and kind in Env.POPULATION_KINDS and str(r.get("eco_mode", "sustainable")) == "sustainable":
		taken = mini(taken, int(Env.ecology_info(data, key).takeable))
	if action == "clear":
		if kind not in [Env.Kind.TIMBER, Env.Kind.STONE, Env.Kind.FOOD, Env.Kind.HERB]:
			return fail("INVALID", "地下礦藏不能靠清地刪除")
		if int(r.remaining) > 0:
			# A clear job first harvests its material, then clears the exhausted object.
			action = "harvest"
		else:
			if not preview:
				Env.change(data, key, {"cleared": true, "next_recovery": -1})
				_fire_resource_cleared(data, key)
				Env.rebuild_indexes(data)
				rebuild_water(data)
			return ok("清理完成")
	if taken <= 0:
		return fail("EMPTY")
	if data.feature_at[int(r.cell)] != 0 and not (Env.ecology_active(data) and kind in Env.POPULATION_KINDS):
		var feature: Dictionary = data.site.features.get(str(data.feature_at[int(r.cell)]), {})
		if not feature.is_empty() and str(feature.stage) == "complete":
			var expansion: Dictionary = feature.get("pending_build", {})
			if not expansion.get("added_cells", []).has(int(r.cell)) or not expansion.get("clearing", []).has(key):
				return fail("OCCUPIED")
	if kind == Env.Kind.SALT:
		var used := float(r.get("used", 0.0)) if int(r.get("used_minute", -1)) == int(data.site.minute) else 0.0
		taken = mini(taken, floori(float(r.capacity) - used))
		if taken <= 0:
			return fail("CAPACITY")
	var output := {str(Env.ITEMS[kind]): taken}
	if kind == Env.Kind.WILDLIFE:
		output = {captured_species: taken} if action == "capture" else {"meat": taken * (3 if int(r.variant) == 0 else 2), "hide": taken}
	if carry_limit < 0 or inventory_size(cargo) + inventory_size(output) > carry_limit:
		return fail("STORAGE_FULL")
	if preview:
		return ok()
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

static func capturable_species(resource: Dictionary) -> String:
	if int(resource.get("kind", -1)) != Env.Kind.WILDLIFE:
		return ""
	var species := Env.wildlife_species(int(resource.variant), int(resource.cell))
	return species if species in ["horse", "sheep"] else ""

static func items_text(items: Dictionary) -> String:
	var labels: Array[String] = []
	for key: String in items:
		labels.append("%s ×%d" % [str(Env.ITEM_NAMES.get(key, key)), int(items[key])])
	return "、".join(labels) if not labels.is_empty() else "無"

static func deposit(data: TerrainData, cargo: Dictionary, actor_cell: Vector2i) -> Dictionary:
	var depot := data.cell_from_index(int(data.site.depot_cell))
	if absi(actor_cell.x - depot.x) + absi(actor_cell.y - depot.y) > 1:
		return fail("UNREACHABLE", "請回營地箱旁交貨")
	var depot_items: Dictionary = data.site.get("depot_items", {})
	var loose_items: int = depot_items.get("item_ids", []).size() - depot_items.get("equipped", {}).size()
	if inventory_size(data.site.inventory) + loose_items + inventory_size(cargo) > int(data.site.capacity):
		return fail("STORAGE_FULL")
	var text := items_text(cargo)
	add_items(data.site.inventory, cargo)
	cargo.clear()
	data.environment_revision += 1
	return ok("已入庫：" + text)

static func add_zone(data: TerrainData, area: Rect2i, kind: int, action: String = "harvest") -> Dictionary:
	if _ship_runtime_pending(data): return fail("BUSY", "原固定目標仍待補算或交接；暫不能接受新設施操作")
	if action not in ["harvest", "clear", "survey", "capture", "restore"] or kind < -1 or kind >= Env.NAMES.size() or (action == "capture" and kind not in [-1, Env.Kind.WILDLIFE]):
		return fail("INVALID")
	var bounded := area.intersection(Rect2i(Vector2i.ZERO, data.size))
	if not bounded.has_area() or bounded.get_area() > 1600:
		return fail("INVALID", "工作區限 1–1600 格")
	var sources := Env.resources_in(data, bounded, kind)
	if action == "capture":
		sources = sources.filter(func(key: String) -> bool: return not capturable_species(data.resource_base[key]).is_empty())
	if action == "restore":
		if not Env.ecology_active(data): return fail("ECOLOGY_PENDING", "原生態候選尚未准入")
		sources = sources.filter(func(key: String) -> bool: return int(data.resource_base[key].kind) in Env.RESTORABLE_KINDS and bool(Env.resource(data, key).cleared))
	if sources.is_empty():
		return fail("NO_TARGET")
	var cells: Array[int] = []
	for y: int in range(bounded.position.y, bounded.end.y):
		for x: int in range(bounded.position.x, bounded.end.x):
			cells.append(data.index(Vector2i(x, y)))
	data.site.zones.append({"cells": cells, "kind": kind, "action": action, "active": true})
	data.environment_revision += 1
	return ok("工作區已指定", {"zone": data.site.zones.size() - 1})

# Siege records borrow the original Site vehicle collection. Live command authority
# and native handoff belong to the caller; this owner commits materials and HP.
static func siege_cells(data: TerrainData, vehicle: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if data == null or not SIEGE_DEFINITIONS.has(str(vehicle.get("kind", ""))): return result
	var direction: Array = vehicle.get("facing", [])
	if direction.size() != 2: return result
	var facing := Vector2i(int(direction[0]), int(direction[1]))
	if not TerrainData.DIRECTIONS.has(facing): return result
	var anchor := data.cell_from_index(int(vehicle.get("cell", -1)))
	var side := Vector2i(-facing.y, facing.x)
	var size: Vector2i = SIEGE_DEFINITIONS[str(vehicle.kind)].size
	for forward in range(size.y):
		for across in range(size.x): result.append(anchor + facing * forward + side * across)
	return result

static func siege_crew_offsets(kind: String, turning: bool = false) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var definition: Dictionary = SIEGE_DEFINITIONS.get(kind, {})
	result.assign(definition.get("turn_offsets" if turning else "crew_offsets", []))
	return result

static func siege_crew_cell(data: TerrainData, vehicle: Dictionary, slot: Variant, turning: bool = false) -> Vector2i:
	var key := str(slot)
	var offsets := siege_crew_offsets(str(vehicle.get("kind", "")), turning)
	if data == null or not key.is_valid_int() or int(key) < 0 or int(key) >= offsets.size(): return Vector2i(-1, -1)
	var values: Array = vehicle.get("facing", [])
	if values.size() != 2: return Vector2i(-1, -1)
	var facing := Vector2i(int(values[0]), int(values[1]))
	if not TerrainData.DIRECTIONS.has(facing): return Vector2i(-1, -1)
	var offset: Vector2i = offsets[int(key)]
	return data.cell_from_index(int(vehicle.cell)) + Vector2i(-facing.y, facing.x) * offset.x + facing * offset.y

static func siege_turn_sweep(data: TerrainData, vehicle: Dictionary, new_facing: Vector2i) -> Array[int]:
	var result: Array[int] = []
	var definition: Dictionary = SIEGE_DEFINITIONS.get(str(vehicle.get("kind", "")), {})
	if data == null or definition.is_empty() or not TerrainData.DIRECTIONS.has(new_facing): return result
	var anchor := data.cell_from_index(int(vehicle.cell))
	var radius := int(definition.turn_radius)
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			var cell := anchor + Vector2i(x, y)
			if not data.contains(cell): return []
			result.append(data.index(cell))
	return result

static func siege_turn_contacts(data: TerrainData, vehicle: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var definition: Dictionary = SIEGE_DEFINITIONS.get(str(vehicle.get("kind", "")), {})
	if data == null or definition.is_empty(): return result
	var facing := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
	var side := Vector2i(-facing.y, facing.x)
	var anchor := Vector2(data.cell_from_index(int(vehicle.cell)))
	var offsets := siege_crew_offsets(str(vehicle.kind), true)
	for slot in offsets.size():
		var station := siege_crew_cell(data, vehicle, slot, true)
		# Each real rope joins the far turning station to a fitting on the rear
		# beam. Geometry and presenter use these same endpoints.
		var attachment := anchor + Vector2.ONE * 0.5 + Vector2(side) * clampf(float(offsets[slot].x), 0.0, float(definition.size.x) - 1.0)
		result.append({"slot": slot, "station": station, "attachment": attachment})
	return result

static func siege_work_slots(data: TerrainData, vehicle: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if siege_cells(data, vehicle).is_empty(): return result
	var anchor := data.cell_from_index(int(vehicle.cell))
	var facing := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
	var side := Vector2i(-facing.y, facing.x)
	var definition: Dictionary = SIEGE_DEFINITIONS[str(vehicle.kind)]
	var size: Vector2i = definition.size
	# Four original construction stations; operators cannot work concurrently.
	for offset: Vector2i in [Vector2i(-1, 0), Vector2i(size.x, 0), Vector2i(-1, size.y - 1), Vector2i(size.x, size.y - 1)]:
		var cell := anchor + side * offset.x + facing * offset.y
		if data.contains(cell): result.append({"slot": result.size(), "cell": data.index(cell)})
	return result

static func _siege_vehicle_claims(data: TerrainData, cell: Vector2i, excluded: String = "") -> bool:
	for key: String in data.site.get("vehicles", {}):
		if key == excluded: continue
		var vehicle: Dictionary = data.site.vehicles[key]
		if str(vehicle.get("kind", "")) == "siege_tower":
			if siege_tower_physical_cells(data, vehicle).has(cell): return true
		elif SIEGE_DEFINITIONS.has(str(vehicle.get("kind", ""))):
			if siege_cells(data, vehicle).has(cell): return true
		elif str(vehicle.get("kind", "")) == "ship":
			var ship = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
			var facing := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
			if ship.footprint(str(vehicle.ship_type), data.cell_from_index(int(vehicle.cell)), facing).has(cell): return true
		else:
			var anchor := data.cell_from_index(int(vehicle.cell))
			var facing := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
			for distance in range(3 if str(vehicle.kind) == "wagon" else 1):
				if anchor + facing * distance == cell: return true
		if vehicle.get("move", {}).get("sweep", []).has(data.index(cell)): return true
		if str(vehicle.get("action", {}).get("stage", "")) == "rotate" and vehicle.action.get("sweep", []).has(data.index(cell)): return true
	return false

static func _siege_depot_ready(data: TerrainData) -> bool:
	return data != null and data.site.get("inventory") is Dictionary and data.site.get("depot_items") is Dictionary \
		and _item_holder_shape(data.site.depot_items) and str(data.site.depot_items.holder) == "depot" \
		and int(data.site.depot_items.version) < 2147483646

static func _refresh_siege_work_refs(data: TerrainData) -> void:
	if not data.has_meta(&"site_work_team"): return
	var ref_value: Variant = data.get_meta(&"site_work_team")
	if ref_value is WeakRef:
		var workers: Variant = ref_value.get_ref()
		if workers != null: workers.refresh_vehicle_tasks()

static func begin_siege_build(data: TerrainData, kind: String, anchor: Vector2i, facing: Vector2i,
		team_id: int, requester_id: int, occupied: Callable = Callable(), preview: bool = false) -> Dictionary:
	if not _siege_depot_ready(data) or not SIEGE_DEFINITIONS.has(kind) or team_id <= 0 or requester_id <= 0 \
		or not data.contains(anchor) or not TerrainData.DIRECTIONS.has(facing): return fail("INVALID")
	if bool(data.site.get("paused", false)): return fail("BUSY")
	var next := int(data.site.get("next_vehicle", 1))
	if next <= 0 or next >= 2147483647 or data.site.get("vehicles", {}).has(str(next)): return fail("STALE_SOURCE")
	var definition: Dictionary = SIEGE_DEFINITIONS[kind]
	var candidate := {"kind": kind, "cell": data.index(anchor), "facing": [facing.x, facing.y]}
	var cells := siege_cells(data, candidate)
	var stations := siege_work_slots(data, candidate)
	if stations.size() != 4: return fail("TERRAIN", "施工四個工位必須留在本 Site")
	var checked := cells.duplicate()
	for station: Dictionary in stations: checked.append(data.cell_from_index(int(station.cell)))
	for slot in range(int(definition.standard_crew)): checked.append(siege_crew_cell(data, candidate, slot))
	var base := data.effective_height(anchor)
	for cell: Vector2i in checked:
		if not data.contains(cell) or not data.is_walkable(cell) or data.effective_height(cell) != base \
			or data.effective_height(cell) != int(data.height_levels[data.index(cell)]) \
			or int(data.surface_types[data.index(cell)]) in [TerrainData.Surface.WATER, TerrainData.Surface.WETLAND] \
			or int(data.feature_at[data.index(cell)]) != 0: return fail("TERRAIN", "器具及工位需要平整乾燥且無建築的原地面")
		if _siege_vehicle_claims(data, cell) or occupied.is_valid() and bool(occupied.call(cell)): return fail("OCCUPIED")
	if not can_pay(data.site.inventory, definition.cost) or not can_pay(data.site.inventory, {"tools": 1}): return fail("MATERIALS")
	if preview: return ok("可建造" + str(definition.name), {"cells": cells, "work_slots": stations, "cost": definition.cost.duplicate(), "work_seconds": definition.work_seconds})
	var identity := str(next)
	candidate.merge({"id": identity, "vehicle_version": 3, "technology_capture": {}, "definition_version": 1, "team_id": team_id,
		"operator_id": 0, "holder": new_item_state("vehicle:" + identity), "cargo": {}, "move": {}, "stop_pending": false,
		"hp": float(definition.max_hp), "ever_hp_damaged": false, "phase": "building", "crew_slots": {},
		"build": {"paid_cost": definition.cost.duplicate(), "total_work": float(definition.work_seconds), "progress": 0.0},
		"repair": {}, "command": {}, "action": {}, "next_attack_seq": 1, "rng_state": maxi(1, (int(data.seed_value) + next * 104729) & 0x7fffffff)})
	if kind == "siege_tower": candidate.deployed_pose = {}
	add_items(data.site.inventory, definition.cost, -1)
	data.site.depot_items.version = int(data.site.depot_items.version) + 1
	if not data.site.has("vehicles"): data.site.vehicles = {}
	data.site.vehicles[identity] = candidate
	data.site.next_vehicle = next + 1
	data.environment_revision += 1
	return ok("已備料，原工作者可到工位施工", {"vehicle": identity})

static func siege_repair_terms(vehicle: Dictionary, amount: float) -> Dictionary:
	var definition: Dictionary = SIEGE_DEFINITIONS.get(str(vehicle.get("kind", "")), {})
	if definition.is_empty() or not is_finite(amount) or amount <= 0.0 or amount > float(definition.max_hp): return {}
	var ratio := amount / float(definition.max_hp)
	var cost := {}
	for material: String in definition.cost: cost[material] = ceili(float(definition.cost[material]) * 0.4 * ratio)
	return {"paid_cost": cost, "total_work": float(definition.work_seconds) * 0.25 * ratio,
		"progress": 0.0, "amount": amount, "applied": 0.0}

# CANDIDATE ONLY. Insert beside the original siege work APIs; do not replace them.
# Seven-field receipt is a reservation description over the original ship cargo.
# Work consumes floor cumulative quantities. Cancellation/wreck release rounds
# cumulative use up, leaving floor remaining quantities physically in that cargo.
static func ship_repair_terms(vehicle: Dictionary, amount: float) -> Dictionary:
	var kind: String = str(vehicle.get("ship_type", ""))
	var full_hp: float = Ships.hull_hp(kind)
	if not Ships.is_kind(kind) or not is_finite(amount) or amount <= 0.0 or amount > full_hp: return {}
	var ratio: float = amount / full_hp
	var cost: Dictionary = {}
	for resource: String in Ships.build_cost(kind):
		cost[resource] = ceili(float(Ships.build_cost(kind)[resource]) * ratio * 0.5)
	return {"version": 1, "feature_id": "", "paid_cost": cost,
		"total_work": Ships.build_work_seconds(kind) * ratio * 0.25,
		"progress": 0.0, "amount": amount, "applied": 0.0}

static func reserved_ship_repair_resources(vehicle: Dictionary) -> Dictionary:
	var job: Dictionary = vehicle.get("naval", {}).get("repair", {})
	if job.is_empty(): return {}
	var reserved: Dictionary = {}
	var ratio: float = clampf(float(job.progress) / float(job.total_work), 0.0, 1.0)
	for resource: String in job.paid_cost:
		var quantity: int = int(job.paid_cost[resource]) - floori(float(job.paid_cost[resource]) * ratio)
		if quantity > 0: reserved[resource] = quantity
	return reserved

static func ship_repair_uses_team(data: TerrainData, team_id: int) -> bool:
	for vehicle: Dictionary in data.site.get("vehicles", {}).values():
		if str(vehicle.get("kind", "")) == "ship" and int(vehicle.get("team_id", 0)) == team_id and not vehicle.get("naval", {}).get("repair", {}).is_empty(): return true
	return false

static func ship_repair_uses_feature(data: TerrainData, feature_id: String) -> bool:
	for vehicle: Dictionary in data.site.get("vehicles", {}).values():
		if str(vehicle.get("kind", "")) == "ship" and str(vehicle.get("naval", {}).get("repair", {}).get("feature_id", "")) == feature_id: return true
	return false

static func ship_repair_work_slots(data: TerrainData, vehicle: Dictionary, state: Dictionary = {}, check_access: bool = true) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var owner: Dictionary = data.site if state.is_empty() else state
	var job: Dictionary = vehicle.get("naval", {}).get("repair", {})
	var feature: Dictionary = owner.get("features", {}).get(str(job.get("feature_id", "")), {})
	if str(vehicle.get("kind", "")) != "ship" or not Ships.is_kind(str(vehicle.get("ship_type", ""))) or str(feature.get("kind", "")) not in WATERFRONT_KINDS or str(feature.get("stage", "")) != "complete" or not feature_usable(feature): return result
	if not _building_integer(vehicle.get("cell"), 0, data.size.x * data.size.y - 1) or not vehicle.get("facing") is Array or vehicle.facing.size() != 2: return result
	var facing: Vector2i = Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
	if not Ships.valid_facing(facing): return result
	var anchor: Vector2i = data.cell_from_index(int(vehicle.cell))
	var contacts: Array[Vector2i] = Ships.boarding_cells(str(vehicle.ship_type), anchor, facing)
	var cells: Array = feature.get("cells", []).duplicate()
	cells.sort()
	var station_number: int = 0
	for index: int in cells:
		if not _building_integer(index, 0, data.size.x * data.size.y - 1): return []
		var cell: Vector2i = data.cell_from_index(index)
		if not contacts.has(cell): continue
		var station: int = station_number
		station_number += 1
		if check_access and (not data.is_walkable(cell) or absi(data.effective_height(cell) - data.effective_height(anchor)) > 1 or _siege_vehicle_claims(data, cell, str(vehicle.id))): continue
		result.append({"slot": station, "cell": index})
	return result

static func validate_ship_repair(data: TerrainData, vehicle: Dictionary, state: Dictionary = {}, allow_nonafloat: bool = false) -> Dictionary:
	var naval: Variant = vehicle.get("naval", {})
	if not naval is Dictionary: return fail("CORRUPT_SAVE", "船體修理耐久 owner 格式非法")
	var job: Variant = naval.get("repair", {})
	if not job is Dictionary: return fail("CORRUPT_SAVE", "船體修理作業格式非法")
	if job.is_empty(): return ok()
	if str(vehicle.get("kind", "")) != "ship" or not Ships.is_kind(str(vehicle.get("ship_type", ""))) or job.size() != 7 or not _building_integer(job.get("version"), 1, 1) or not job.get("feature_id") is String or job.feature_id.is_empty(): return fail("CORRUPT_SAVE", "船體修理收據欄位非法")
	# Store validates raw JSON before normalization. Keep the original strict
	# runtime holder/resource helpers; admit only integral numbers in this pure
	# receipt validator using local copies, without mutating saved owner state.
	var holder: Variant = vehicle.get("holder", {})
	if not holder is Dictionary or not _building_integer(holder.get("version"), 0, 2147483646): return fail("CORRUPT_SAVE", "原修理收據須保留一次材料結算版本")
	var checked_holder: Dictionary = holder.duplicate()
	checked_holder.version = int(holder.version)
	if not _item_holder_shape(checked_holder): return fail("CORRUPT_SAVE", "原修理收據須保留一次材料結算版本")
	var full_hp: float = Ships.hull_hp(str(vehicle.ship_type))
	if not _building_number(naval.get("hp"), 0.0, full_hp) or not naval.get("state") is String: return fail("CORRUPT_SAVE", "船體修理耐久非法")
	if str(naval.state) != "afloat":
		if not allow_nonafloat or str(naval.state) not in ["sinking", "wrecked"] or float(naval.hp) != 0.0: return fail("CORRUPT_SAVE", "只有浮航船體可保留修理作業")
	elif float(naval.hp) <= 0.0: return fail("CORRUPT_SAVE", "浮航修理船體必須存活")
	if not _building_number(job.get("amount"), 0.0, full_hp) or float(job.amount) <= 0.0: return fail("CORRUPT_SAVE", "船體修理額度非法")
	var terms: Dictionary = ship_repair_terms(vehicle, float(job.amount))
	if not job.get("paid_cost") is Dictionary or job.paid_cost.size() != terms.paid_cost.size() or not _building_number(job.get("total_work"), float(terms.total_work), float(terms.total_work)) or not _building_number(job.get("progress"), 0.0, float(terms.total_work)) or not _building_number(job.get("applied"), 0.0, float(job.amount)): return fail("CORRUPT_SAVE", "船體修理成本／工時非法")
	for resource: String in terms.paid_cost:
		if not _building_integer(job.paid_cost.get(resource), int(terms.paid_cost[resource]), int(terms.paid_cost[resource])): return fail("CORRUPT_SAVE", "船體修理成本與原配方不符")
	if absf(float(job.applied) - float(job.amount) * float(job.progress) / float(job.total_work)) > 0.000001: return fail("CORRUPT_SAVE", "船體修理已施作額度不符")
	if float(job.progress) >= float(job.total_work): return fail("CORRUPT_SAVE", "完成的船體修理必须清除原收據")
	if float(naval.hp) > full_hp - float(job.amount) + float(job.applied) + 0.000001: return fail("CORRUPT_SAVE", "船體耐久超過原已付修理額度")
	if not vehicle.get("cargo") is Dictionary: return fail("CORRUPT_SAVE", "本船艙缺少原修理預留材料")
	var checked_cargo: Dictionary = {}
	for resource: Variant in vehicle.cargo:
		if not _building_integer(vehicle.cargo[resource], 0, 1000000): return fail("CORRUPT_SAVE", "本船艙缺少原修理預留材料")
		checked_cargo[resource] = int(vehicle.cargo[resource])
	if not _resource_stack(checked_cargo) or not can_pay(checked_cargo, reserved_ship_repair_resources(vehicle)): return fail("CORRUPT_SAVE", "本船艙缺少原修理預留材料")
	if ship_repair_work_slots(data, vehicle, state, false).is_empty(): return fail("CORRUPT_SAVE", "船體修理沒有原岸上設施工位")
	return ok()

static func _ship_repair_q(data: TerrainData, identity: String, query: Callable) -> Dictionary:
	if not query.is_valid() and data.has_meta(&"ship_q_query"):
		var value: Variant = data.get_meta(&"ship_q_query")
		if value is Callable: query = value
	if not query.is_valid(): return fail("CAPACITY_QUERY", "須由原船乘載 owner 預驗全船物品")
	var result: Variant = query.call(identity)
	if not result is Dictionary or result.get("ok", false) != true or not _building_number(result.get("load"), 0.0, 100000000.0) or not _building_number(result.get("capacity"), 0.0, 100000000.0): return fail("CAPACITY_QUERY")
	return result

static func request_ship_repair(data: TerrainData, identity: String, feature_id: String, team_id: int, preview: bool = false, ship_q_query: Callable = Callable()) -> Dictionary:
	if _ship_runtime_pending(data) or _ship_runtime_vehicle_journey(data, identity):
		return fail("BUSY", "原船仍在旅程或固定目標交接；不能修改歷史船體修理")
	if not _siege_depot_ready(data): return fail("INVALID")
	var vehicle: Dictionary = data.site.get("vehicles", {}).get(identity, {})
	var feature: Dictionary = data.site.get("features", {}).get(feature_id, {})
	if str(vehicle.get("kind", "")) != "ship" or int(vehicle.get("team_id", 0)) != team_id or team_id <= 0: return fail("NO_AUTHORITY")
	var kind: String = str(vehicle.get("ship_type", ""))
	var naval: Dictionary = vehicle.get("naval", {"version": 1, "hp": Ships.hull_hp(kind), "state": "afloat", "repair": {}})
	if str(naval.get("state", "")) != "afloat" or float(naval.get("hp", 0.0)) <= 0.0: return fail("NO_TARGET", "沉船不可恢復")
	if bool(data.site.get("paused", false)) or not vehicle.get("move", {}).is_empty() or not vehicle.get("command", {}).is_empty() or bool(vehicle.get("stop_pending", false)) or not naval.get("repair", {}).is_empty(): return fail("BUSY")
	if str(feature.get("kind", "")) not in WATERFRONT_KINDS or str(feature.get("stage", "")) != "complete" or feature.has("pending_build") or feature.has("repair") or not feature_usable(feature): return fail("NO_TARGET", "須使用原已完成碼頭或船塢")
	if not _item_holder_shape(vehicle.get("holder", {})) or int(vehicle.holder.version) >= 2147483646 or not vehicle.get("cargo") is Dictionary or not _resource_stack(vehicle.cargo): return fail("STALE_SOURCE")
	var terms: Dictionary = ship_repair_terms(vehicle, Ships.hull_hp(kind) - float(naval.hp))
	if terms.is_empty(): return fail("INVALID", "完整船體無須修理")
	terms.feature_id = feature_id
	var candidate: Dictionary = vehicle.duplicate(true)
	candidate.naval = naval.duplicate(true)
	candidate.naval.repair = terms
	var stations: Array[Dictionary] = ship_repair_work_slots(data, candidate)
	if stations.is_empty(): return fail("UNREACHABLE", "本船須停在原水岸設施的真實接觸處")
	if not can_pay(data.site.inventory, terms.paid_cost) or not can_pay(data.site.inventory, {"tools": 1}): return fail("MATERIALS")
	var q: Dictionary = _ship_repair_q(data, identity, ship_q_query)
	if not bool(q.ok): return q
	if float(q.load) + float(inventory_size(terms.paid_cost)) > minf(float(q.capacity), float(Ships.definition(kind).capacity)) + 0.000001: return fail("CAPACITY", "修理原料須實際容納於本船艙")
	var loaded: Dictionary = vehicle.cargo.duplicate()
	add_items(loaded, terms.paid_cost)
	if not _resource_stack(loaded): return fail("INVALID", "修理備料不能溢出原資源堆疊")
	if preview: return ok("可由原岸上工位修理；原料移到本船艙", {"repair": terms.duplicate(true), "work_slots": stations})
	add_items(data.site.inventory, terms.paid_cost, -1)
	add_items(vehicle.cargo, terms.paid_cost)
	data.site.depot_items.version = int(data.site.depot_items.version) + 1
	vehicle.holder.version = int(vehicle.holder.version) + 1
	if not vehicle.has("naval"): vehicle.naval = naval
	vehicle.naval.repair = terms
	vehicle.revision = int(vehicle.revision) + 1
	data.environment_revision += 1
	return ok("修理備料已放入原船艙，等待本隊原工人", {"vehicle": identity, "repair": terms.duplicate(true)})

static func advance_ship_repair_work(data: TerrainData, identity: String, seconds: float, worker_cell: Vector2i, slot: int, team_id: int, preview: bool = false) -> Dictionary:
	var vehicle: Dictionary = data.site.get("vehicles", {}).get(identity, {})
	if str(vehicle.get("kind", "")) != "ship" or int(vehicle.get("team_id", 0)) != team_id or team_id <= 0: return fail("NO_AUTHORITY")
	var naval: Dictionary = vehicle.get("naval", {})
	if str(naval.get("state", "")) != "afloat" or float(naval.get("hp", 0.0)) <= 0.0 or naval.get("repair", {}).is_empty(): return fail("NO_TARGET")
	if bool(data.site.get("paused", false)) or not is_finite(seconds) or seconds <= 0.0 or not vehicle.move.is_empty() or not vehicle.command.is_empty() or int(vehicle.holder.version) >= 2147483646: return fail("BUSY")
	var checked: Dictionary = validate_ship_repair(data, vehicle)
	if not checked.ok: return checked
	var stations: Array[Dictionary] = ship_repair_work_slots(data, vehicle)
	var actual_station: bool = false
	for station: Dictionary in stations:
		if int(station.slot) == slot and data.cell_from_index(int(station.cell)) == worker_cell: actual_station = true; break
	if not actual_station: return fail("UNREACHABLE")
	if not can_pay(data.site.inventory, {"tools": 1}): return fail("MATERIALS")
	var job: Dictionary = naval.repair
	var progress: float = minf(float(job.total_work), float(job.progress) + seconds)
	var ratio: float = progress / float(job.total_work)
	var prior_ratio: float = float(job.progress) / float(job.total_work)
	var consumed: Dictionary = {}
	for resource: String in job.paid_cost:
		consumed[resource] = floori(float(job.paid_cost[resource]) * ratio) - floori(float(job.paid_cost[resource]) * prior_ratio)
	if not can_pay(vehicle.cargo, consumed): return fail("MATERIALS")
	var applied: float = float(job.amount) * ratio
	if preview: return ok("原岸工位可施作", {"consumed": consumed, "progress": progress, "applied": applied})
	add_items(vehicle.cargo, consumed, -1)
	naval.hp = minf(Ships.hull_hp(str(vehicle.ship_type)), float(naval.hp) + maxf(0.0, applied - float(job.applied)))
	job.progress = progress
	job.applied = applied
	var complete: bool = progress >= float(job.total_work)
	if complete: naval.repair = {}
	vehicle.holder.version = int(vehicle.holder.version) + 1
	vehicle.revision = int(vehicle.revision) + 1
	data.environment_revision += 1
	if complete: _refresh_siege_work_refs(data)
	return ok("船體修理完成" if complete else "原岸上工人正在修理", {"vehicle": identity, "complete": complete, "consumed": consumed})

static func _release_ship_repair(data: TerrainData, vehicle: Dictionary, preview: bool, allow_nonafloat: bool = false) -> Dictionary:
	var checked: Dictionary = validate_ship_repair(data, vehicle, {}, allow_nonafloat)
	if not checked.ok: return checked
	var job: Dictionary = vehicle.get("naval", {}).get("repair", {})
	if job.is_empty(): return fail("NO_TARGET")
	if int(vehicle.holder.version) >= 2147483647: return fail("STALE_SOURCE")
	var ratio: float = clampf(float(job.progress) / float(job.total_work), 0.0, 1.0)
	var charge: Dictionary = {}
	var returned: Dictionary = {}
	for resource: String in job.paid_cost:
		var used: float = float(job.paid_cost[resource]) * ratio
		charge[resource] = ceili(used) - floori(used)
		var remainder: int = int(job.paid_cost[resource]) - ceili(used)
		if remainder > 0: returned[resource] = remainder
	if not can_pay(vehicle.cargo, charge): return fail("MATERIALS")
	if preview: return ok("取消補扣已施作的不足整份，未用材料留在本船艙", {"consume_resources": charge, "return_resources": returned})
	_commit_ship_repair_release(data, vehicle, charge)
	_refresh_siege_work_refs(data)
	return ok("修理已結束，未用原料仍在原船艙", {"consume_resources": charge, "return_resources": returned})

# Private same-call commit after original receipt/material/version preflight.
# No refund, inventory copy or delayed receipt owner is created.
static func _commit_ship_repair_release(data: TerrainData, vehicle: Dictionary, charge: Dictionary) -> void:
	add_items(vehicle.cargo, charge, -1)
	vehicle.naval.repair = {}
	vehicle.holder.version = int(vehicle.holder.version) + 1
	vehicle.revision = int(vehicle.revision) + 1
	data.environment_revision += 1

static func _settle_ship_repair_feature_damage(data: TerrainData, feature_id: String) -> Dictionary:
	var prepared: Array[Dictionary] = []
	var keys: Array = data.site.get("vehicles", {}).keys()
	keys.sort()
	for identity: String in keys:
		var vehicle: Dictionary = data.site.vehicles[identity]
		if str(vehicle.get("kind", "")) != "ship" or str(vehicle.get("naval", {}).get("repair", {}).get("feature_id", "")) != feature_id: continue
		var checked: Dictionary = _release_ship_repair(data, vehicle, true)
		if not checked.ok: return checked
		prepared.append({"vehicle": vehicle, "charge": checked.consume_resources})
	# Synchronous original-owner operation: no await or external callback can
	# change cargo between the all-receipt preflight and the following commits.
	for entry: Dictionary in prepared:
		_commit_ship_repair_release(data, entry.vehicle, entry.charge)
	if not prepared.is_empty(): _refresh_siege_work_refs(data)
	return ok()

static func cancel_ship_repair(data: TerrainData, identity: String, team_id: int, preview: bool = false) -> Dictionary:
	if _ship_runtime_pending(data) or _ship_runtime_vehicle_journey(data, identity):
		return fail("BUSY", "原船仍在旅程或固定目標交接；不能修改歷史船體修理")
	var vehicle: Dictionary = data.site.get("vehicles", {}).get(identity, {})
	if str(vehicle.get("kind", "")) != "ship" or int(vehicle.get("team_id", 0)) != team_id or team_id <= 0: return fail("NO_AUTHORITY")
	if bool(data.site.get("paused", false)) or not vehicle.move.is_empty() or str(vehicle.get("naval", {}).get("state", "")) != "afloat": return fail("BUSY")
	return _release_ship_repair(data, vehicle, preview)

# Internal original wreck-settlement caller only. No HP restoration, relocation,
# depot refund or control authority. Leaves remaining cargo on the original hull.
static func settle_ship_repair_damage(data: TerrainData, identity: String) -> Dictionary:
	var vehicle: Dictionary = data.site.get("vehicles", {}).get(identity, {})
	if str(vehicle.get("kind", "")) != "ship" or str(vehicle.get("naval", {}).get("state", "")) not in ["sinking", "wrecked"] or float(vehicle.naval.get("hp", 1.0)) != 0.0: return fail("NO_TARGET")
	if vehicle.naval.get("repair", {}).is_empty(): return ok()
	return _release_ship_repair(data, vehicle, false, true)

static func request_siege_repair(data: TerrainData, identity: String, team_id: int, preview: bool = false) -> Dictionary:
	if not _siege_depot_ready(data): return fail("INVALID")
	var vehicle: Dictionary = data.site.get("vehicles", {}).get(identity, {})
	if not SIEGE_DEFINITIONS.has(str(vehicle.get("kind", ""))) or int(vehicle.get("team_id", 0)) != team_id or team_id <= 0: return fail("NO_AUTHORITY")
	if bool(data.site.get("paused", false)) or str(vehicle.phase) not in ["idle", "ready", "disabled"] \
		or not vehicle.action.is_empty() or str(vehicle.command.get("type", "")) not in ["", "stop"] or not vehicle.move.is_empty() \
		or not vehicle.crew_slots.is_empty() or not vehicle.build.is_empty() or not vehicle.repair.is_empty(): return fail("BUSY")
	var terms := siege_repair_terms(vehicle, float(SIEGE_DEFINITIONS[str(vehicle.kind)].max_hp) - float(vehicle.hp))
	if float(vehicle.hp) <= 0.0 or terms.is_empty(): return fail("INVALID", "殘骸不可修理，完整器具無須修理")
	if not can_pay(data.site.inventory, terms.paid_cost) or not can_pay(data.site.inventory, {"tools": 1}): return fail("MATERIALS")
	if preview: return ok("可修理", terms)
	add_items(data.site.inventory, terms.paid_cost, -1)
	data.site.depot_items.version = int(data.site.depot_items.version) + 1
	vehicle.repair = terms
	vehicle.phase = "idle"
	vehicle.command = {}
	data.environment_revision += 1
	return ok("已備料，等待原工作者修理", {"vehicle": identity})

static func advance_siege_work(data: TerrainData, identity: String, action: String, seconds: float,
		worker_cell: Vector2i, slot: int, team_id: int, original_task: Dictionary = {}, original_identity: int = 0) -> Dictionary:
	var vehicle: Dictionary = data.site.get("vehicles", {}).get(identity, {})
	if not SIEGE_DEFINITIONS.has(str(vehicle.get("kind", ""))) or int(vehicle.get("team_id", 0)) != team_id or team_id <= 0: return fail("NO_AUTHORITY")
	if bool(data.site.get("paused", false)) or not is_finite(seconds) or seconds < 0.0 or float(vehicle.hp) <= 0.0: return fail("BUSY")
	var field := "build" if action == "construct" else "repair"
	if action not in ["construct", "repair"] or vehicle.get(field, {}).is_empty(): return fail("NO_TARGET")
	if not vehicle.action.is_empty() or not vehicle.move.is_empty() or not vehicle.crew_slots.is_empty(): return fail("BUSY")
	var slots := siege_work_slots(data, vehicle)
	if slot < 0 or slot >= slots.size() or worker_cell != data.cell_from_index(int(slots[slot].cell)) or not data.is_walkable(worker_cell): return fail("UNREACHABLE")
	if not can_pay(data.site.inventory, {"tools": 1}): return fail("MATERIALS")
	var job: Dictionary = vehicle[field]
	if seconds <= 0.0 and float(job.progress) + 0.000000001 < float(job.total_work): return fail("BUSY")
	var technology_guard := technology_geometry_operator_guard(data, vehicle, original_task, original_identity) if field == "build" else ok()
	if not technology_guard.ok: return technology_guard
	if field == "build": technology_record_work(vehicle, seconds / 60.0, int(technology_guard.get("operator_id", 0)))
	job.progress = minf(float(job.total_work), float(job.progress) + seconds)
	if field == "repair":
		var applied := float(job.amount) * float(job.progress) / float(job.total_work)
		vehicle.hp = minf(float(SIEGE_DEFINITIONS[str(vehicle.kind)].max_hp), float(vehicle.hp) + maxf(0.0, applied - float(job.applied)))
		job.applied = applied
	var complete := float(job.progress) + 0.000000001 >= float(job.total_work)
	if complete:
		var technology_completed := prepare_technology_geometry_completion(data, vehicle, "vehicle:" + identity) if field == "build" else ok("", {"phase": {}, "event": {}})
		if not technology_completed.ok: return technology_completed
		vehicle[field] = {}
		vehicle.phase = "idle"
		publish_technology_geometry_completion(technology_completed)
		_refresh_siege_work_refs(data)
	data.environment_revision += 1
	return ok("器具施工完成" if complete else "原工作者施工中", {"complete": complete, "vehicle": identity})

static func damage_siege_vehicle(data: TerrainData, identity: String, damage: float) -> Dictionary:
	var vehicle: Dictionary = data.site.get("vehicles", {}).get(identity, {})
	if not SIEGE_DEFINITIONS.has(str(vehicle.get("kind", ""))) or not is_finite(damage) or damage <= 0.0 or float(vehicle.get("hp", 0.0)) <= 0.0: return fail("NO_TARGET")
	var old_hp := float(vehicle.hp)
	vehicle.hp = maxf(0.0, old_hp - damage)
	vehicle.ever_hp_damaged = true
	if float(vehicle.hp) <= 0.0:
		vehicle.phase = "wrecked"
		vehicle.command = {}
		vehicle.build = {}
		vehicle.repair = {}
		# Transport retains committed turn participants until their original step
		# settles; cargo, holder and already released projectiles remain intact.
		_refresh_siege_work_refs(data)
	if str(vehicle.kind) == "siege_tower": Env.rebuild_indexes(data)
	data.environment_revision += 1
	return ok("器具已成殘骸" if float(vehicle.hp) <= 0.0 else "器具受損", {"vehicle": identity, "old_hp": old_hp, "new_hp": float(vehicle.hp)})

static func damage_ship_vehicle(data: TerrainData, identity: String, damage: float) -> Dictionary:
	var vehicle: Dictionary = data.site.get("vehicles", {}).get(identity, {})
	if str(vehicle.get("kind", "")) != "ship" or not Ships.is_kind(str(vehicle.get("ship_type", ""))) or not is_finite(damage) or damage <= 0.0:
		return fail("NO_TARGET")
	if not vehicle.has("naval"):
		vehicle.naval = {"version": 1, "hp": Ships.hull_hp(str(vehicle.ship_type)), "state": "afloat", "repair": {}}
	var naval: Dictionary = vehicle.naval
	if str(naval.state) != "afloat" or float(naval.hp) <= 0.0: return fail("NO_TARGET")
	var old_hp := float(naval.hp)
	# Settle the existing receipt before fatal HP/state mutation. The
	# same call is immediately saveable; committed movement stays intact.
	if damage >= old_hp and not naval.get("repair", {}).is_empty():
		var repair_result: Dictionary = _release_ship_repair(data, vehicle, false)
		if not repair_result.ok: return repair_result
	naval.hp = maxf(0.0, old_hp - damage)
	if float(naval.hp) <= 0.0:
		naval.state = "sinking"
		# Receipt was settled above; all unused material stays in this cargo.
		vehicle.command = {}
		vehicle.stop_pending = not vehicle.move.is_empty()
	vehicle.revision = int(vehicle.revision) + 1
	data.environment_revision += 1
	return ok("船體正在沉沒，原船步完成後撤離" if float(naval.hp) <= 0.0 else "船體受損", {"vehicle": identity, "old_hp": old_hp, "new_hp": float(naval.hp)})

static func release_siege_ammo(data: TerrainData, identity: String, expected_version: int, expected_rng: int = -1) -> Dictionary:
	if data == null: return fail("NO_TARGET")
	var vehicle: Dictionary = data.site.get("vehicles", {}).get(identity, {})
	var definition: Dictionary = SIEGE_DEFINITIONS.get(str(vehicle.get("kind", "")), {})
	var ammo := str(definition.get("ammo", ""))
	if ammo.is_empty() or float(vehicle.get("hp", 0.0)) <= 0.0 \
		or not vehicle.get("build", {}).is_empty() or not vehicle.get("repair", {}).is_empty(): return fail("NO_TARGET")
	var holder: Dictionary = vehicle.get("holder", {})
	var sequence: Variant = vehicle.get("next_attack_seq")
	var rng: Variant = vehicle.get("rng_state")
	if not _item_holder_shape(holder) or str(holder.holder) != "vehicle:" + identity \
		or expected_version < 0 or expected_version >= 2147483646 or int(holder.version) != expected_version \
		or not _building_integer(sequence, 1, 2147483646) or not _building_integer(rng, 0, 2147483647) \
		or expected_rng >= 0 and int(rng) != expected_rng: return fail("STALE_SOURCE")
	if bool(data.site.get("paused", false)) or int(vehicle.cargo.get(ammo, 0)) < 1: return fail("MATERIALS", "原器具沒有可發射的實物彈藥")
	var scatter := Vector2.ZERO
	var next_rng := int(rng)
	if ammo == "siege_stone":
		next_rng = (next_rng * 1103515245 + 12345) & 0x7fffffff
		var radius := sqrt(float(next_rng) / 2147483648.0)
		next_rng = (next_rng * 1103515245 + 12345) & 0x7fffffff
		scatter = Vector2.from_angle(float(next_rng) / 2147483648.0 * TAU) * radius
	var attack_id := str(data.site.id) + "|" + identity + "|" + str(int(sequence))
	add_items(vehicle.cargo, {ammo: 1}, -1)
	if int(vehicle.cargo[ammo]) == 0: vehicle.cargo.erase(ammo)
	holder.version = expected_version + 1
	vehicle.next_attack_seq = int(sequence) + 1
	vehicle.rng_state = next_rng
	return ok("已發射原實物彈藥", {"attack_id": attack_id, "seq": int(sequence), "scatter_unit": scatter, "rng_state": next_rng})

static func release_siege_bolt(data: TerrainData, identity: String, expected_version: int) -> Dictionary:
	if data == null or str(data.site.get("vehicles", {}).get(identity, {}).get("kind", "")) != "ballista": return fail("NO_TARGET")
	return release_siege_ammo(data, identity, expected_version)

static func commit_siege_impact(data: TerrainData, identity: String, expected_sequence: int) -> Dictionary:
	if data == null: return fail("NO_TARGET")
	var vehicle: Dictionary = data.site.get("vehicles", {}).get(identity, {})
	if str(vehicle.get("kind", "")) != "ram" or float(vehicle.get("hp", 0.0)) <= 0.0 \
		or not vehicle.get("build", {}).is_empty() or not vehicle.get("repair", {}).is_empty() or bool(data.site.get("paused", false)): return fail("NO_TARGET")
	if expected_sequence < 1 or expected_sequence >= 2147483647 or int(vehicle.get("next_attack_seq", 0)) != expected_sequence: return fail("STALE_SOURCE")
	var attack_id := str(data.site.id) + "|" + identity + "|" + str(expected_sequence)
	vehicle.next_attack_seq = expected_sequence + 1
	return ok("原衝頭已發生接觸", {"attack_id": attack_id, "seq": expected_sequence})

static func takeover_siege(data: TerrainData, identity: String, expected: Dictionary, new_team: int) -> Dictionary:
	if data == null or bool(data.site.get("paused", false)) or new_team <= 0: return fail("NO_AUTHORITY")
	var vehicle: Dictionary = data.site.get("vehicles", {}).get(identity, {})
	if not SIEGE_DEFINITIONS.has(str(vehicle.get("kind", ""))) or float(vehicle.get("hp", 0.0)) <= 0.0: return fail("NO_TARGET")
	var holder: Dictionary = vehicle.get("holder", {})
	if not _item_holder_shape(holder) or str(holder.holder) != "vehicle:" + identity or int(holder.version) >= 2147483646: return fail("STALE_SOURCE")
	var current := {"old_team": int(vehicle.get("team_id", 0)), "cell": vehicle.get("cell"), "facing": vehicle.get("facing"),
		"hp": vehicle.get("hp"), "ever_hp_damaged": vehicle.get("ever_hp_damaged"), "holder_version": holder.version,
		"next_attack_seq": vehicle.get("next_attack_seq"), "rng_state": vehicle.get("rng_state")}
	if expected != current: return fail("STALE_SOURCE")
	if not vehicle.get("crew_slots", {}).is_empty() or not vehicle.get("move", {}).is_empty() or not vehicle.get("action", {}).is_empty() \
		or not vehicle.get("build", {}).is_empty() or not vehicle.get("repair", {}).is_empty() or bool(vehicle.get("stop_pending", false)) \
		or str(vehicle.get("command", {}).get("type", "")) not in ["", "stop"]: return fail("BUSY")
	var team_exists := false
	var has_live_context := data.has_meta(&"site_garrison_lab")
	var ref_value: Variant = data.get_meta(&"site_garrison_lab") if has_live_context else null
	var live_lab: Variant = ref_value.get_ref() if ref_value is WeakRef else null
	if has_live_context and live_lab == null: return fail("NO_AUTHORITY")
	if live_lab != null:
		if live_lab.terrain != data: return fail("NO_AUTHORITY")
		if live_lab.crowd_site != null and live_lab.crowd_site.active:
			var owner: Variant = live_lab.crowd_site.siege_team_owner(new_team)
			team_exists = owner != null and owner.has_army()
		else:
			for army: Variant in live_lab.combat_armies:
				if army.combat_enabled and army.has_army() and int(army.team_id) == new_team: team_exists = true
	for team: Variant in data.site.get("armies", []):
		if live_lab == null and team is Dictionary and int(team.get("team_id", 0)) == new_team: team_exists = true
	if not team_exists: return fail("NO_AUTHORITY")
	var technology_capture := _technology_takeover_capture(data, identity, expected, new_team, live_lab)
	vehicle.vehicle_version = 3
	if not vehicle.has("technology_capture"): vehicle.technology_capture = {}
	if not technology_capture.is_empty(): vehicle.technology_capture = technology_capture
	vehicle.team_id = new_team
	holder.version = int(holder.version) + 1
	data.environment_revision += 1
	return ok("原器具已完成易主；人物、彈藥與貨物保留", {"vehicle": identity, "team_id": new_team})

static func cancel_siege_job(data: TerrainData, identity: String, team_id: int, occupied: Callable = Callable()) -> Dictionary:
	if not _siege_depot_ready(data): return fail("INVALID")
	var vehicle: Dictionary = data.site.get("vehicles", {}).get(identity, {})
	if not SIEGE_DEFINITIONS.has(str(vehicle.get("kind", ""))) or team_id <= 0 or int(vehicle.get("team_id", 0)) != team_id: return fail("NO_AUTHORITY")
	if bool(data.site.get("paused", false)) or not vehicle.action.is_empty() or not vehicle.move.is_empty() or not vehicle.crew_slots.is_empty(): return fail("BUSY")
	var field := "build" if not vehicle.build.is_empty() else "repair"
	var job: Dictionary = vehicle[field]
	if job.is_empty(): return fail("NO_TARGET")
	if field == "build":
		if inventory_size(vehicle.cargo) > 0 or not vehicle.holder.item_ids.is_empty(): return fail("BUSY", "先取回原物資")
		for cell: Vector2i in siege_cells(data, vehicle):
			if occupied.is_valid() and bool(occupied.call(cell)): return fail("OCCUPIED")
	var refund := {}
	for material: String in job.paid_cost:
		refund[material] = 0 if bool(vehicle.ever_hp_damaged) else floori(float(job.paid_cost[material]) * maxf(0.0, 1.0 - float(job.progress) / float(job.total_work)))
	if not _depot_can_receive(data, refund): return fail("STORAGE_FULL")
	add_items(data.site.inventory, refund)
	data.site.depot_items.version = int(data.site.depot_items.version) + 1
	if field == "build": data.site.vehicles.erase(identity)
	else: vehicle.repair = {}
	_refresh_siege_work_refs(data)
	data.environment_revision += 1
	return ok("已取消；受損器具不退建材", {"vehicle": identity, "refund": refund})

static func remove_siege_vehicle(data: TerrainData, identity: String, team_id: int, occupied: Callable = Callable(), preview: bool = false) -> Dictionary:
	var vehicle: Dictionary = data.site.get("vehicles", {}).get(identity, {})
	if not SIEGE_DEFINITIONS.has(str(vehicle.get("kind", ""))) or team_id <= 0 or int(vehicle.get("team_id", 0)) != team_id: return fail("NO_AUTHORITY")
	if bool(data.site.get("paused", false)) or bool(vehicle.get("stop_pending", false)) or not vehicle.action.is_empty() or str(vehicle.command.get("type", "")) not in ["", "stop"] or not vehicle.move.is_empty() \
		or not vehicle.crew_slots.is_empty() or not vehicle.build.is_empty() or not vehicle.repair.is_empty(): return fail("BUSY")
	if inventory_size(vehicle.cargo) > 0 or not vehicle.holder.item_ids.is_empty(): return fail("BUSY", "先卸空原器具貨物")
	var physical := siege_tower_physical_cells(data, vehicle) if str(vehicle.kind) == "siege_tower" else siege_cells(data, vehicle)
	for cell: Vector2i in physical:
		if occupied.is_valid() and bool(occupied.call(cell)): return fail("OCCUPIED")
	if preview: return ok("原器具可依法清除")
	data.site.vehicles.erase(identity)
	if str(vehicle.kind) == "siege_tower": Env.rebuild_indexes(data)
	_refresh_siege_work_refs(data)
	data.environment_revision += 1
	return ok("已清除原器具；已耗建材不退款")

static func clear_siege_wreck(data: TerrainData, identity: String, worker_cell: Vector2i, occupied: Callable = Callable()) -> Dictionary:
	var vehicle: Dictionary = data.site.get("vehicles", {}).get(identity, {})
	if not SIEGE_DEFINITIONS.has(str(vehicle.get("kind", ""))) or str(vehicle.get("phase", "")) != "wrecked" \
		or float(vehicle.get("hp", -1.0)) != 0.0 or not bool(vehicle.get("ever_hp_damaged", false)): return fail("NO_TARGET")
	if bool(data.site.get("paused", false)) or not vehicle.crew_slots.is_empty() or not vehicle.build.is_empty() \
		or not vehicle.repair.is_empty() or not vehicle.action.is_empty() or not vehicle.move.is_empty() or bool(vehicle.stop_pending): return fail("BUSY")
	if inventory_size(vehicle.cargo) != 0 or not vehicle.holder.item_ids.is_empty() or not vehicle.holder.equipped.is_empty(): return fail("BUSY", "先取出殘骸全部原物資")
	var cells := siege_tower_physical_cells(data, vehicle) if str(vehicle.kind) == "siege_tower" else siege_cells(data, vehicle)
	if not data.contains(worker_cell) or not data.is_walkable(worker_cell) or cells.has(worker_cell): return fail("UNREACHABLE")
	var contact := false
	for cell: Vector2i in cells:
		if not data.contains(cell) or occupied.is_valid() and bool(occupied.call(cell)): return fail("OCCUPIED")
		if absi(cell.x - worker_cell.x) + absi(cell.y - worker_cell.y) == 1 \
			and data.effective_height(cell) == data.effective_height(worker_cell) and data.can_step(worker_cell, cell): contact = true
	if not contact: return fail("UNREACHABLE", "原本人須到殘骸外緣合法相鄰格")
	data.site.vehicles.erase(identity)
	if str(vehicle.kind) == "siege_tower": Env.rebuild_indexes(data)
	_refresh_siege_work_refs(data)
	data.environment_revision += 1
	return ok("原殘骸已清除；無建材退款")

# Missing fields retain the old building and its original recipe; reads never upgrade it.
static func building_grade(feature: Dictionary) -> int:
	return int(feature.get("building_grade", 1))

static func building_productivity(feature: Dictionary) -> float:
	return 1.0 + 0.25 * float(building_grade(feature) - 1) if int(feature.get("civil_version", 0)) == CIVIL_VERSION else 1.0

static func civil_max_hp(feature: Dictionary) -> float:
	return 100.0 + 50.0 * float(building_grade(feature) - 1)

static func feature_usable(feature: Dictionary, service: String = "") -> bool:
	return feature_function_state(feature, service) in ["OPERATIONAL", "DEGRADED"]

static func feature_recipe(feature: Dictionary) -> Dictionary:
	var kind := str(feature.get("kind", ""))
	if not FEATURES.has(kind): return {}
	var definition: Dictionary = FEATURES[kind].duplicate(true)
	var recipe := str(feature.get("recipe_id", ""))
	if not recipe.is_empty():
		if not FEATURE_RECIPES.get(kind, {}).has(recipe): return {}
		definition.merge(FEATURE_RECIPES[kind][recipe], true)
		definition["recipe_name"] = str(definition.name)
		definition.name = str(FEATURES[kind].name)
	return definition

static func _feature_operation_active(data: TerrainData, key: String) -> bool:
	for zone: Dictionary in data.site.zones:
		if str(zone.get("feature", "")) == key and str(zone.get("action", "")) == "operate" and bool(zone.get("active", false)): return true
	return false

static func request_feature_recipe(data: TerrainData, key: String, recipe_id: String, requester_faction: int = -1) -> Dictionary:
	if _ship_runtime_pending(data): return fail("BUSY", "原固定目標仍待補算或交接；暫不能接受新設施操作")
	var feature: Dictionary = data.site.get("features", {}).get(key, {})
	var kind := str(feature.get("kind", ""))
	if str(feature.get("stage", "")) != "complete" or int(feature.get("layout_version", 0)) != BUILDING_LAYOUT_VERSION or not FEATURE_RECIPES.has(kind): return fail("NO_TARGET")
	if int(feature.get("owner_faction", -1)) >= 0 and requester_faction != int(feature.owner_faction): return fail("NO_AUTHORITY")
	if not recipe_id.is_empty() and not FEATURE_RECIPES[kind].has(recipe_id): return fail("INVALID", "此作坊不支援該配方")
	if feature.has("pending_build") or feature.has("repair") or bool(feature.batch_paid) or float(feature.production) > 0.0 or _feature_has_work(data, key) or _feature_operation_active(data, key): return fail("BUSY", "先停工並完成原已付批次、交貨與在途工作")
	if recipe_id.is_empty(): feature.erase("recipe_id")
	else: feature["recipe_id"] = recipe_id
	feature.status = "已切換配方；等待派工"
	data.environment_revision += 1
	rebuild_water(data)
	return ok(str(feature.status), {"feature": key, "recipe_id": recipe_id})

static func _civil_upgrade_terms(data: TerrainData, feature: Dictionary, target_grade: int) -> Dictionary:
	var factor := 0.5 if target_grade == 2 else 1.0
	var cost := {}
	var base_cost := _building_cost(data, str(feature.kind), feature.cells, _feature_options(feature))
	for item: String in base_cost:
		if int(base_cost[item]) > 0: cost[item] = ceili(float(base_cost[item]) * factor)
	add_items(cost, {"pottery": 2, "rope": 2} if target_grade == 2 else {"brick": 4, "steel": 2})
	return {"cost": cost, "work": maxf(0.5, _building_work(data, str(feature.kind), feature.cells, _feature_options(feature)) * factor)}

static func _civil_upgrade_candidate(feature: Dictionary, target_grade: int) -> Dictionary:
	var candidate := feature.duplicate(true)
	var fraction := float(feature.parts.body.hp) / civil_max_hp(feature) if int(feature.get("civil_version", 0)) == CIVIL_VERSION else 1.0
	candidate["civil_version"] = CIVIL_VERSION
	candidate["building_grade"] = target_grade
	candidate["parts"] = {"body": {"hp": civil_max_hp(candidate) * fraction}}
	if int(feature.get("fire_layout_version", 0)) == FIRE_LAYOUT_VERSION:
		for part_id: String in _fire_layout_parts(feature):
			candidate.parts[part_id] = {"hp": _fire_part_max_hp(candidate, part_id) * float(feature.parts[part_id].hp) / _fire_part_max_hp(feature, part_id)}
	return candidate

static func request_upgrade(data: TerrainData, key: String, requester_faction: int, occupied: Callable = Callable(), preview: bool = false) -> Dictionary:
	if _ship_runtime_pending(data): return fail("BUSY", "原固定目標仍待補算或交接；暫不能接受新設施操作")
	var feature: Dictionary = data.site.get("features", {}).get(key, {})
	if str(feature.get("kind", "")) not in CIVIL_KINDS or str(feature.get("stage", "")) != "complete" or int(feature.get("layout_version", 0)) != BUILDING_LAYOUT_VERSION: return fail("NO_TARGET", "升級只適用原新版普通建物")
	if int(feature.get("owner_faction", -1)) < 0 or requester_faction != int(feature.owner_faction): return fail("NO_AUTHORITY")
	if feature.has("pending_build") or feature.has("repair") or bool(feature.batch_paid) or float(feature.production) > 0.0 or _feature_has_work(data, key) or _feature_operation_active(data, key): return fail("BUSY", "先完成原作業、已付批次、交貨與在途工作")
	if not feature_usable(feature): return fail("BUSY", "先修復毀壞建物，升級不能取代維修")
	var target_grade := building_grade(feature) + 1
	if target_grade > CIVIL_MAX_GRADE: return fail("INVALID", "建物已達三級")
	var grade_cap := settlement_grade_cap(data, feature)
	if target_grade > grade_cap: return fail("SETTLEMENT_LEVEL", "已建制聚落目前只允許普通建物升到 %d 級；聚落 %d 級且生效後才可升 %d 級" % [grade_cap, target_grade, target_grade])
	var terms := _civil_upgrade_terms(data, feature, target_grade)
	if not can_pay(data.site.inventory, terms.cost) or not can_pay(data.site.inventory, {"tools": 1}): return fail("MATERIALS", items_text(terms.cost))
	var candidate := _civil_upgrade_candidate(feature, target_grade)
	# Only UI previews may skip the full Site projection when the original
	# pure geometry is equal. Real transactions retain every existing guard.
	var guard: Dictionary
	if preview:
		var before_geometry := feature_geometry(data, feature)
		var after_geometry := feature_geometry(data, candidate)
		before_geometry.erase("parts")
		after_geometry.erase("parts")
		guard = _ship_water_geometry_guard(data, key, candidate) if before_geometry == after_geometry else structure_change_guard(data, key, candidate, occupied, "upgrade")
		if guard.ok and before_geometry == after_geometry:
			guard = housing_geometry_guard(data, data)
	else:
		guard = structure_change_guard(data, key, candidate, occupied, "upgrade")
	if not guard.ok: return guard
	if preview: return ok("可升級；占地、原人物與存貨保持", {"feature": key, "target_grade": target_grade, "cost": terms.cost, "work": terms.work})
	add_items(data.site.inventory, terms.cost, -1)
	feature["pending_build"] = {"cells": feature.cells.duplicate(), "added_cells": [], "cost": terms.cost, "clearing": [],
		"entrance": int(feature.entrance), "work": float(terms.work), "progress": 0.0, "target_grade": target_grade}
	data.site.zones.append({"cells": feature.cells.duplicate(), "kind": -1, "action": "construct", "feature": key, "active": true})
	feature.status = "升級至 %d 級；原建物與人物保持" % target_grade
	data.environment_revision += 1
	return ok(str(feature.status), {"feature": key, "target_grade": target_grade})

# Physical half of a settlement level upgrade: the same in-place paid
# pending_build as civil grades. SiteSettlement owns the people/building terms.
static func request_settlement_level(data: TerrainData, key: String, target_level: int, requester_faction: int, occupied: Callable = Callable(), preview: bool = false) -> Dictionary:
	if _ship_runtime_pending(data): return fail("BUSY", "原固定目標仍待補算或交接；暫不能接受新設施操作")
	var feature: Dictionary = data.site.get("features", {}).get(key, {})
	if str(feature.get("kind", "")) != "settlement_center" or str(feature.get("stage", "")) != "complete" or int(feature.get("layout_version", 0)) != BUILDING_LAYOUT_VERSION: return fail("NO_TARGET", "須選取已完工的聚落中心")
	if int(feature.get("owner_faction", -1)) < 0 or requester_faction != int(feature.owner_faction): return fail("NO_AUTHORITY")
	if feature.has("pending_build") or feature.has("repair") or _feature_has_work(data, key) or _feature_operation_active(data, key): return fail("BUSY", "中心已有施工或修理")
	if not feature_usable(feature): return fail("BUSY", "先修復受損的聚落中心")
	if target_level != settlement_center_invested_level(data, feature) + 1 or target_level < 2 or target_level > SETTLEMENT_MAX_LEVEL: return fail("INVALID", "聚落只能逐級升級；P0 最高 %d 級" % SETTLEMENT_MAX_LEVEL)
	var terms := settlement_level_terms(target_level)
	if not can_pay(data.site.inventory, terms.cost): return fail("MATERIALS", items_text(terms.cost))
	var guard := _ship_water_geometry_guard(data, key, feature) if preview else structure_change_guard(data, key, feature.duplicate(true), occupied, "upgrade")
	if not guard.ok: return guard
	if preview: return ok("可升級；占地、入口、方向與 ID 不變", {"feature": key, "target_level": target_level, "cost": terms.cost, "work": terms.work})
	add_items(data.site.inventory, terms.cost, -1)
	feature["pending_build"] = {"cells": feature.cells.duplicate(), "added_cells": [], "cost": terms.cost, "clearing": [],
		"entrance": int(feature.entrance), "work": float(terms.work), "progress": 0.0, "target_level": target_level}
	data.site.zones.append({"cells": feature.cells.duplicate(), "kind": -1, "action": "construct", "feature": key, "active": true})
	feature.status = "升級為 %d 級%s；中心照常運作" % [target_level, str(SETTLEMENT_LEVEL_NAMES[target_level])]
	data.environment_revision += 1
	return ok(str(feature.status), {"feature": key, "target_level": target_level})

static func _validate_feature_processing(feature: Dictionary) -> Dictionary:
	var kind := str(feature.get("kind", ""))
	if feature.has("recipe_id") and (not _building_integer(feature.get("layout_version"), BUILDING_LAYOUT_VERSION, BUILDING_LAYOUT_VERSION) or not feature.recipe_id is String or str(feature.recipe_id).is_empty() or not FEATURE_RECIPES.get(kind, {}).has(str(feature.recipe_id))): return fail("CORRUPT_SAVE", "作坊配方與原種類不符")
	if feature.has("civil_version") or feature.has("building_grade"):
		if kind not in BODY_KINDS or not _building_integer(feature.get("layout_version"), BUILDING_LAYOUT_VERSION, BUILDING_LAYOUT_VERSION) or not _building_integer(feature.get("civil_version"), CIVIL_VERSION, CIVIL_VERSION) or not _building_integer(feature.get("building_grade"), 1, 1 if kind == "settlement_center" else CIVIL_MAX_GRADE) or not feature.get("parts") is Dictionary: return fail("CORRUPT_SAVE", "普通建物耐久版本／等級")
	elif kind == "settlement_center": return fail("CORRUPT_SAVE", "聚落中心缺少本體耐久版本")
	# Ship construction owns its already-paid production clock and validator.
	if kind == "shipyard": return ok()
	var definition := feature_recipe(feature)
	var production: Variant = feature.get("production", 0.0)
	if not _building_number(production, 0.0, float(definition.get("cycle", 0.0))): return fail("CORRUPT_SAVE", "生產進度超出原配方週期")
	if (not bool(feature.get("batch_paid", false)) and float(production) > 0.0) or (bool(feature.get("batch_paid", false)) and (not definition.has("cycle") or str(feature.get("stage", "")) != "complete")): return fail("CORRUPT_SAVE", "未付批次進度或未完工設施保留付費批次")
	return ok()

static func civil_investment_terms(data: TerrainData, feature: Dictionary, center_level: int = 1) -> Dictionary:
	var expected_cost := _building_cost(data, str(feature.kind), feature.cells, _feature_options(feature))
	var expected_work := _building_work(data, str(feature.kind), feature.cells, _feature_options(feature))
	if str(feature.kind) == "settlement_center":
		for level: int in range(2, center_level + 1):
			var level_terms := settlement_level_terms(level)
			add_items(expected_cost, level_terms.cost)
			expected_work += float(level_terms.work)
		return {"cost": expected_cost, "work": expected_work}
	for grade: int in range(2, building_grade(feature) + 1):
		var terms := _civil_upgrade_terms(data, feature, grade)
		add_items(expected_cost, terms.cost)
		expected_work += float(terms.work)
	return {"cost": expected_cost, "work": expected_work}

# Settlement levels (SETTLEMENT_CENTER_LEVELS_PLAN). Level 1 is the center's
# own build cost; each later level is one in-place paid pending_build.
const SETTLEMENT_LEVEL_NAMES := {1: "聚落", 2: "村", 3: "鄉", 4: "鎮", 5: "城"}
const SETTLEMENT_HEAD_NAMES := {1: "聚落長", 2: "村長", 3: "鄉長", 4: "鎮長", 5: "城主"}

static func _settlement_center_count(data: TerrainData) -> int:
	var count := 0
	for feature: Dictionary in data.site.get("features", {}).values(): count += int(str(feature.get("kind", "")) == "settlement_center")
	return count

# Only the finished center switches the settlement level; an unchanged default
# head title follows the level, a renamed one is kept.
static func _settlement_center_completed(data: TerrainData, key: String, level: int) -> void:
	var settlement: Variant = data.site.get("settlement", {})
	if not settlement is Dictionary or str(settlement.get("center_id", "")) != key: return
	var previous := int(settlement.level)
	settlement.level = clampi(maxi(previous, level), 1, SETTLEMENT_MAX_LEVEL)
	for seat: Dictionary in settlement.get("offices", {}).get("positions", []):
		if bool(seat.head) and str(seat.name) == str(SETTLEMENT_HEAD_NAMES.get(maxi(1, previous), "")) and previous != int(settlement.level):
			seat.name = str(SETTLEMENT_HEAD_NAMES[int(settlement.level)])
			settlement.offices.revision = mini(2147483646, int(settlement.offices.revision) + 1)
	data.site.notices.append("%s已成為 %d 級%s" % [str(settlement.name), int(settlement.level), str(SETTLEMENT_LEVEL_NAMES[int(settlement.level)])])

static func settlement_level_terms(level: int) -> Dictionary:
	return SETTLEMENT_LEVEL_TERMS.get(level, {"cost": {}, "work": 0.0}).duplicate(true)

# The completed level the center's saved investment pays for, or -1. Store
# cross-checks it against site.settlement.level without trusting either alone.
static func settlement_center_invested_level(data: TerrainData, feature: Dictionary) -> int:
	if str(feature.get("kind", "")) != "settlement_center" or not feature.get("cost") is Dictionary: return -1
	for level: int in range(1, SETTLEMENT_MAX_LEVEL + 1):
		var terms := civil_investment_terms(data, feature, level)
		if feature.cost.size() != terms.cost.size() or not _building_number(feature.get("work"), float(terms.work), float(terms.work)): continue
		var matches := true
		for item: String in terms.cost:
			matches = matches and _building_integer(feature.cost.get(item), int(terms.cost[item]), int(terms.cost[item]))
		if matches: return level
	return -1

# Grade cap for new civil upgrades. Un-founded Sites keep the original rule.
# The live controller installs a population-aware query; the fallback reads the
# saved level and center body only.
static func settlement_grade_cap(data: TerrainData, feature: Dictionary) -> int:
	var query: Variant = data.get_meta(&"settlement_grade_cap", Callable()) if data != null else Callable()
	if query is Callable and query.is_valid(): return int(query.call(feature))
	var settlement: Variant = data.site.get("settlement", {}) if data != null else {}
	if not settlement is Dictionary or settlement.is_empty() or int(feature.get("owner_faction", -1)) != int(settlement.get("owner_faction", -2)): return CIVIL_MAX_GRADE
	var center: Dictionary = data.site.get("features", {}).get(str(settlement.get("center_id", "")), {})
	if str(center.get("stage", "")) != "complete" or not feature_usable(center): return 1
	return clampi(int(settlement.get("level", 1)), 1, CIVIL_MAX_GRADE)

static func _validate_civil_investment(data: TerrainData, feature: Dictionary) -> Dictionary:
	if str(feature.get("kind", "")) == "settlement_center":
		var invested := settlement_center_invested_level(data, feature)
		if invested < 0: return fail("CORRUPT_SAVE", "聚落中心等級投入／工時不符")
		if str(feature.stage) == "complete" and not is_equal_approx(float(feature.get("progress", 0.0)), float(feature.work)): return fail("CORRUPT_SAVE", "聚落中心原施工尚未完成")
		return ok()
	var terms := civil_investment_terms(data, feature)
	var expected_cost: Dictionary = terms.cost
	var expected_work := float(terms.work)
	if not feature.get("cost") is Dictionary or feature.cost.size() != expected_cost.size() or not _building_number(feature.get("work"), expected_work, expected_work): return fail("CORRUPT_SAVE", "普通建物等級投入／工時不符")
	for item: String in expected_cost:
		if not _building_integer(feature.cost.get(item), int(expected_cost[item]), int(expected_cost[item])): return fail("CORRUPT_SAVE", "普通建物等級建材不符")
	if str(feature.stage) == "complete" and not is_equal_approx(float(feature.get("progress", 0.0)), expected_work): return fail("CORRUPT_SAVE", "普通建物原施工尚未完成")
	return ok()

static func barracks_type(feature: Dictionary) -> String:
	var value: Variant = feature.get("camp_type", "standard")
	return str(value) if value is String and BARRACKS_TYPES.has(value) else ""

static func barracks_type_name(feature: Dictionary) -> String:
	return str(BARRACKS_TYPES.get(barracks_type(feature), {}).get("name", "無效軍營"))

static func barracks_type_description(feature: Dictionary) -> String:
	return str(BARRACKS_TYPES.get(barracks_type(feature), {}).get("description", "軍營型式無效"))

static func is_training_facility(feature: Dictionary) -> bool:
	var kind := str(feature.get("kind", ""))
	return (kind == "training_ground" and not feature.has("camp_type")) or (kind == "barracks" and barracks_type(feature) == "standard")

static func training_multiplier(feature: Dictionary) -> float:
	return float(BARRACKS_TYPES[barracks_type(feature)].training_multiplier) if str(feature.get("kind", "")) == "barracks" and is_training_facility(feature) else 1.0

static func feature_input_inventory(data: TerrainData, feature: Dictionary, key: String) -> Dictionary:
	if str(feature.get("supply_mode", "")) == "local":
		return data.site.get("stockpiles", {}).get(key, {}).get("cargo", {})
	return data.site.inventory

static func pay_feature_inputs(data: TerrainData, feature: Dictionary, key: String, inputs: Dictionary, task: Dictionary = {}, original_identity: int = 0) -> Dictionary:
	var source := _technology_payment_source(data, feature, key)
	if source.is_empty() or int(source.holder.version) >= 2147483646 or not Technology.material_stack(inputs) or not can_pay(source.cargo, inputs): return fail("NO_MATERIAL", "原完整投入／原來源版本不足；保留批次")
	if feature.has("tech_batch"): return fail("DUPLICATE", "同原批次已付款")
	var actions: Variant = _technology_actions(data)
	var person: Dictionary = actions._technology_operator_for_task(task, original_identity) if actions != null else {}
	var token: Dictionary = feature.get("tech_trial", {})
	if not token.is_empty() and (person.is_empty() or int(person.person_id) != int(token.person.person_id)): return fail("NO_AUTHORITY", "具名原試作者必須實際到本工位")
	var output: Dictionary = feature.get("technology_output", {"version": 1, "next_seq": 1, "receipts": []})
	if not valid_technology_output_state(output, data, key): return fail("STALE_SOURCE")
	var next := int(output.next_seq)
	if next >= 2147483647: return fail("STALE_SOURCE")
	var payment_id := str(data.site.id) + "|feature:" + key + "|" + str(next)
	var prepared := {}
	if not token.is_empty():
		if actions == null or not actions.has_method("technology_phase_payment_candidate") or not actions.has_method("publish_phase_payment"): return fail("UNSUPPORTED")
		prepared = actions.technology_phase_payment_candidate(token, inputs)
		if not prepared.ok: return prepared
		payment_id = str(prepared.payment_id)
	var ledger := {"version": 1, "id": next, "site_id": str(data.site.id), "feature_id": key,
		"operator_id": int(person.get("person_id", 0)), "recipe_id": str(feature.get("recipe_id", "")), "materials": inputs.duplicate(true),
		"source_holder": str(source.holder.holder), "source_version": int(source.holder.version), "work_seconds": 0.0,
		"token": token.duplicate(true), "payment_id": payment_id}
	# Source, feature paid ledger and scope budget are one original synchronous tail.
	add_items(source.cargo, inputs, -1)
	source.holder.version = int(source.holder.version) + 1
	feature.tech_batch = ledger
	feature.batch_paid = true
	if not prepared.is_empty(): actions.publish_phase_payment(prepared)
	return ok("已從原來源支付本次完整材料", {"payment_id": payment_id})

static func building_spec(kind: String, options: Dictionary = {}) -> Dictionary:
	if not FEATURES.has(kind) or int(options.get("layout_version", 1)) != BUILDING_LAYOUT_VERSION:
		return fail("INVALID", "建築種類或布局版本")
	if options.has("camp_type") and (kind != "barracks" or not options.camp_type is String or not BARRACKS_TYPES.has(options.camp_type)):
		return fail("INVALID", "軍營型式必須是受支援的字串")
	if options.has("barracks_layout_version") and (kind != "barracks" or not options.barracks_layout_version is int or options.barracks_layout_version < 1 or options.barracks_layout_version > BARRACKS_LAYOUT_VERSION):
		return fail("INVALID", "軍營布局版本必須是受支援的整數")
	if (options.has("waterfront_version") or options.has("launch_cell")) and kind not in WATERFRONT_KINDS:
		return fail("INVALID", "非水岸設施含泊位")
	if kind in WATERFRONT_KINDS and (not _building_integer(options.get("waterfront_version", 1), 1, 1) or not _building_integer(options.get("launch_cell", -1), -1, 2147483646)):
		return fail("INVALID", "水岸版本／泊位格非法")
	if (options.has("bridge_version") or options.has("bridge_clearance")) and kind != "bridge":
		return fail("INVALID", "非橋梁含橋面欄位")
	if kind == "bridge" and (not _building_integer(options.get("bridge_version", 1), 1, 1) or not _building_integer(options.get("bridge_clearance", 0), 0, 0)):
		return fail("INVALID", "首版橋梁只允許單一橋面，橋下淨空為零")
	var quarter := int(options.get("quarter", 0))
	if quarter < 0 or quarter > 3:
		return fail("INVALID", "建築方向")
	var variant := str(options.get("variant", "standard")) if kind == "house" else ""
	if kind == "house" and not HOUSE_VARIANTS.has(variant):
		return fail("INVALID", "住宅版型")
	var material := str(options.get("material", "wood")) if kind in ["wall_stairs", "gate", "bridge", "warehouse"] else ("stone" if kind == "stone_wall" else "wood")
	if material not in ["wood", "stone"]:
		return fail("INVALID", "建築材質")
	var result: Dictionary = FEATURES[kind].duplicate(true)
	if kind == "house":
		result.merge(HOUSE_VARIANTS[variant], true)
	if material == "stone" and kind == "warehouse":
		result.cost = {"stone": 24, "wood": 8}
		result.work = 30.0
	elif material == "stone" and kind == "wall_stairs":
		result.cost = {"stone": 12}
		result.work = 24.0
	elif material == "stone" and kind == "bridge":
		result.cost = {"stone": 8, "wood": 2}
		result.work = 18.0
	elif material == "stone" and kind == "gate":
		result.cost = {"stone": 24, "wood": 8}
		result.work = 45.0
	var base_size: Vector2i = result.get("size", result.get("min_size", Vector2i.ONE))
	result["base_size"] = base_size
	result["size"] = Vector2i(base_size.y, base_size.x) if quarter % 2 else base_size
	result["min_size"] = result.get("min_size", base_size)
	result["max_size"] = result.get("max_size", base_size if str(result.placement) == "fixed" else Vector2i(36, 36))
	if kind == "bridge" and quarter % 2:
		result.min_size = Vector2i(result.min_size.y, result.min_size.x)
		result.max_size = Vector2i(result.max_size.y, result.max_size.x)
	result["max_cells"] = 2500 if kind in FARM_KINDS + PASTURE_KINDS + MILITARY_KINDS else 36
	result["variants"] = HOUSE_VARIANTS.keys() if kind == "house" else []
	result["materials"] = ["wood", "stone"] if kind in ["wall_stairs", "gate", "bridge", "warehouse"] else [material]
	result["rotatable"] = true
	result["options"] = {"layout_version": BUILDING_LAYOUT_VERSION, "variant": variant, "quarter": quarter, "material": material,
		"owner_faction": int(options.get("owner_faction", -1))}
	if kind == "bridge":
		result.options["bridge_version"] = 1
		result.options["bridge_clearance"] = 0
	if kind in WATERFRONT_KINDS:
		result.options["waterfront_version"] = 1
		result.options["launch_cell"] = int(options.get("launch_cell", -1))
	if kind == "barracks":
		result.options["barracks_layout_version"] = options.get("barracks_layout_version", BARRACKS_LAYOUT_VERSION)
		result.options["camp_type"] = options.get("camp_type", "standard")
	result["ok"] = true
	return result

static func _feature_options(feature: Dictionary) -> Dictionary:
	var options := {"layout_version": int(feature.get("layout_version", 1)), "variant": str(feature.get("variant", "standard")),
		"quarter": int(feature.get("quarter", 0)), "material": str(feature.get("material", "wood")),
		"owner_faction": int(feature.get("owner_faction", -1))}
	if str(feature.get("kind", "")) == "barracks" or feature.has("barracks_layout_version"):
		var version: Variant = feature.get("barracks_layout_version", 1)
		# Saved JSON numbers are floats until Store normalizes validated state.
		# A missing field always keeps the original sparse layout, including resize.
		options["barracks_layout_version"] = int(version) if _building_integer(version, 1, BARRACKS_LAYOUT_VERSION) else version
	if feature.has("camp_type"): options["camp_type"] = feature.camp_type
	if str(feature.get("kind", "")) == "bridge":
		options["bridge_version"] = feature.get("bridge_version", 0)
		options["bridge_clearance"] = feature.get("bridge_clearance", -1)
	if str(feature.get("kind", "")) in WATERFRONT_KINDS:
		options["waterfront_version"] = feature.get("waterfront_version", 0)
		options["launch_cell"] = feature.get("launch_cell", -1)
	return options

static func _cell_bounds(data: TerrainData, cells: Array) -> Rect2i:
	if cells.is_empty():
		return Rect2i()
	var lo := data.cell_from_index(int(cells[0]))
	var hi := lo
	for index: int in cells:
		var cell := data.cell_from_index(index)
		lo = lo.min(cell)
		hi = hi.max(cell)
	return Rect2i(lo, hi - lo + Vector2i.ONE)

static func building_cells(data: TerrainData, kind: String, anchor: Vector2i, requested_size: Vector2i, options: Dictionary = {}) -> Dictionary:
	var spec := building_spec(kind, options)
	if not spec.ok:
		return spec
	var extent: Vector2i = spec.size if str(spec.placement) == "fixed" else requested_size
	if extent.x < 1 or extent.y < 1 or extent.x > 50 or extent.y > 50:
		return fail("INVALID", "寬深需在此類建築的尺寸內")
	var cells: Array[int] = []
	for y: int in range(extent.y):
		for x: int in range(extent.x):
			var cell := anchor + Vector2i(x, y)
			if not data.contains(cell):
				return fail("INVALID", "建築超出地圖")
			cells.append(data.index(cell))
	var layout := validate_building_layout(data, kind, cells, spec.options)
	if not layout.ok:
		return layout
	return ok("布局", {"cells": cells, "options": spec.options, "bounds": layout.bounds})

static func validate_building_layout(data: TerrainData, kind: String, cells: Array, options: Dictionary = {}) -> Dictionary:
	var spec := building_spec(kind, options)
	if not spec.ok or cells.is_empty() or cells.size() > int(spec.get("max_cells", 0)):
		return fail("INVALID", "建築占地超出種類上限")
	var seen := {}
	for value: Variant in cells:
		if not (value is int or value is float) or float(value) != float(int(value)) or int(value) < 0 or int(value) >= data.size.x * data.size.y or seen.has(int(value)):
			return fail("INVALID", "占地含重複或非法格")
		seen[int(value)] = true
	var bounds := _cell_bounds(data, cells)
	if str(spec.placement) != "cells":
		if bounds.get_area() != cells.size():
			return fail("INVALID", "建築必須是沒有缺格的完整矩形")
		if str(spec.placement) == "fixed" and bounds.size != spec.size:
			return fail("INVALID", "固定建築尺寸應為 %d×%d" % [spec.size.x, spec.size.y])
		var low: Vector2i = spec.min_size
		var high: Vector2i = spec.max_size
		if str(spec.placement) == "rect" and (bounds.size.x < low.x or bounds.size.y < low.y or bounds.size.x > high.x or bounds.size.y > high.y):
			return fail("INVALID", "寬深不符此類建築上下限")
	var queue: Array[int] = [int(cells[0])]
	var visited := {int(cells[0]): true}
	var head := 0
	while head < queue.size():
		var cell := data.cell_from_index(queue[head])
		head += 1
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cell + direction
			if data.contains(next) and seen.has(data.index(next)) and not visited.has(data.index(next)):
				visited[data.index(next)] = true
				queue.append(data.index(next))
	if visited.size() != cells.size():
		return fail("INVALID", "占地必須相連")
	return ok("合法布局", {"bounds": bounds, "options": spec.options})

static func _layout_cell(local: Vector2i, base_size: Vector2i, quarter: int, origin: Vector2i) -> Vector2i:
	match quarter:
		1: return origin + Vector2i(base_size.y - 1 - local.y, local.x)
		2: return origin + Vector2i(base_size.x - 1 - local.x, base_size.y - 1 - local.y)
		3: return origin + Vector2i(local.y, base_size.x - 1 - local.x)
	return origin + local

static func _building_integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == float(int(value)) and int(value) >= low and int(value) <= high

static func _building_number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

# Store calls this after its general feature type checks. No materials, live
# actor or current feature_at query participates in validating a saved layout.
static func validate_feature_layout(data: TerrainData, feature: Dictionary, check_navigation: bool = true) -> Dictionary:
	var ladder_validation := validate_siege_ladder(feature)
	if not ladder_validation.ok: return ladder_validation
	if feature.has("camp_type") and (str(feature.get("kind", "")) != "barracks" or not feature.camp_type is String or not BARRACKS_TYPES.has(feature.camp_type)):
		return fail("CORRUPT_SAVE", "不支援的軍營型式")
	if feature.has("barracks_layout_version") and (str(feature.get("kind", "")) != "barracks" or not _building_integer(feature.barracks_layout_version, 1, BARRACKS_LAYOUT_VERSION)):
		return fail("CORRUPT_SAVE", "不支援的軍營布局版本")
	if feature.has("fire_layout_version") and (not _building_integer(feature.fire_layout_version, FIRE_LAYOUT_VERSION, FIRE_LAYOUT_VERSION) or str(feature.get("kind", "")) not in FIRE_LAYOUT_KINDS or not _building_integer(feature.get("layout_version"), BUILDING_LAYOUT_VERSION, BUILDING_LAYOUT_VERSION)):
		return fail("CORRUPT_SAVE", "原火災多部件布局版本或種類非法")
	var processing := _validate_feature_processing(feature)
	if not processing.ok: return processing
	if (feature.has("bridge_version") or feature.has("bridge_clearance")) and str(feature.get("kind", "")) != "bridge":
		return fail("CORRUPT_SAVE", "非橋梁含橋面欄位")
	if not feature.has("layout_version"):
		if str(feature.get("kind", "")) in ["stone_wall", "wall_stairs", "siege_ladder", "gate", "prison", "tent", "bridge"] + MILITARY_KINDS + WATERFRONT_KINDS:
			return fail("CORRUPT_SAVE", "新增建築種類缺少布局版本")
		return ok("保留舊布局")
	if not _building_integer(feature.layout_version, BUILDING_LAYOUT_VERSION, BUILDING_LAYOUT_VERSION):
		return fail("CORRUPT_SAVE", "不支援的建築布局版本")
	if not _building_integer(feature.get("quarter"), 0, 3) or not _building_integer(feature.get("owner_faction"), -1, 100000000):
		return fail("CORRUPT_SAVE", "建築方向／管理方")
	for field: String in ["variant", "material"]:
		if not feature.get(field) is String:
			return fail("CORRUPT_SAVE", "建築版型／材質")
	var kind := str(feature.kind)
	if kind in WATERFRONT_KINDS or feature.has("waterfront_version") or feature.has("launch_cell"):
		var waterfront := validate_waterfront(data, feature, check_navigation)
		if not waterfront.ok: return fail("CORRUPT_SAVE", str(waterfront.message))
	var ship_job := validate_ship_build(data, feature)
	if not ship_job.ok: return ship_job
	var spec := building_spec(kind, _feature_options(feature))
	if not spec.ok or str(spec.options.variant) != str(feature.variant) or str(spec.options.material) != str(feature.material):
		return fail("CORRUPT_SAVE", "建築版型／材質與種類不同")
	var layout := validate_building_layout(data, kind, feature.cells, _feature_options(feature))
	if not layout.ok:
		return fail("CORRUPT_SAVE", str(layout.message))
	# Only already-validated integer cells enter this local projection. JSON
	# floats must compare as cell identities before Store normalizes the save.
	var checked_cells: Array[int] = []
	var current_members := {}
	for value: Variant in feature.cells:
		checked_cells.append(int(value))
		current_members[int(value)] = true
	feature = feature.duplicate()
	feature.cells = checked_cells
	if not _building_integer(feature.get("level"), 0, 5):
		return fail("CORRUPT_SAVE", "建築基底高度")
	if kind not in ["level", "bridge"]:
		for index: int in feature.cells:
			if int(data.height_levels[index]) != int(feature.level):
				return fail("CORRUPT_SAVE", "建築基底高度與原地形不同")
	if kind == "bridge" or feature.has("bridge_version") or feature.has("bridge_clearance"):
		var bridge_check := validate_bridge(data, feature, check_navigation)
		if not bridge_check.ok: return fail("CORRUPT_SAVE", str(bridge_check.message))
	if kind in PASTURE_KINDS and not _building_integer(feature.get("residents"), 0, livestock_capacity(data, feature)):
		return fail("CORRUPT_SAVE", "真實種畜超過原牧地承載")
	if kind == "tent":
		if str(feature.get("stage", "")) != "complete" or feature.has("pending_build") or feature.has("repair") or feature.get("cost", {}).size() != 1 or not _building_integer(feature.get("cost", {}).get("camp_tent"), 1, 1) \
			or not _building_number(feature.get("work"), 2.0, 2.0) or not _building_number(feature.get("progress"), 2.0, 2.0) or int(feature.get("owner_faction", -1)) < 0 \
			or not feature.get("clearing", []).is_empty() or bool(feature.get("batch_paid", false)) or float(feature.get("production", 0.0)) != 0.0:
			return fail("CORRUPT_SAVE", "營帳必須保存一個已搭設的原營帳包")
	if feature.cells.has(int(feature.entrance)):
		return fail("CORRUPT_SAVE", "入口不能在本建築占地內")
	var entrance_found := false
	for entry: Dictionary in _building_entrances(data, feature.cells, int(feature.quarter)):
		entrance_found = entrance_found or data.index(entry.cell) == int(feature.entrance)
	if not entrance_found:
		return fail("CORRUPT_SAVE", "入口與保存方向不符")
	if kind in MILITARY_KINDS:
		var required_cost := _building_cost(data, kind, feature.cells, _feature_options(feature))
		var required_work := _building_work(data, kind, feature.cells, _feature_options(feature))
		if feature.get("cost", {}).size() != required_cost.size() or not _building_number(feature.get("work"), required_work, 1000000.0):
			return fail("CORRUPT_SAVE", "軍事設施投入／工時低於原占地規格")
		for item: String in required_cost:
			if not _building_integer(feature.cost.get(item), int(required_cost[item]), 1000000 if str(feature.stage) == "complete" else int(required_cost[item])):
				return fail("CORRUPT_SAVE", "軍事設施投入數量與原占地不符")
		if str(feature.stage) != "complete" and not is_equal_approx(float(feature.work), required_work):
			return fail("CORRUPT_SAVE", "未完成軍事設施投入必須等於占地規格")
		if str(feature.stage) == "complete" and not is_equal_approx(float(feature.get("progress", 0.0)), float(feature.work)):
			return fail("CORRUPT_SAVE", "軍事設施尚未完成原施工工時")
		var standing := military_walkable_cells(data, feature)
		var courtyard_entry := false
		for entry: Dictionary in _building_entrances(data, feature.cells, int(feature.quarter)):
			if data.index(entry.cell) == int(feature.entrance) and standing.has(data.index(entry.inner)):
				courtyard_entry = true
		if not courtyard_entry:
			return fail("CORRUPT_SAVE", "軍事設施入口被原屋舍／靶架占用")
	if int(feature.get("civil_version", 0)) == CIVIL_VERSION:
		var investment := _validate_civil_investment(data, feature)
		if not investment.ok: return investment
	if kind in STRUCTURE_KINDS or int(feature.get("civil_version", 0)) == CIVIL_VERSION or int(feature.get("fire_layout_version", 0)) == FIRE_LAYOUT_VERSION:
		if not feature.get("parts") is Dictionary:
			return fail("CORRUPT_SAVE", "缺少原結構耐久")
		for id: Variant in feature.parts:
			var part: Variant = feature.parts[id]
			if not id is String or not part is Dictionary or part.size() != 1 or not _building_number(part.get("hp"), 0.0, STONE_PART_HP):
				return fail("CORRUPT_SAVE", "結構耐久格式")
		var geometry := feature_geometry(data, feature)
		if geometry.parts.size() != feature.parts.size():
			return fail("CORRUPT_SAVE", "部件數與占地不符")
		for id: String in geometry.parts:
			if not feature.parts.has(id) or float(feature.parts[id].hp) > float(geometry.parts[id].max_hp):
				return fail("CORRUPT_SAVE", "部件鍵或最大耐久不符")
		if int(feature.get("fire_layout_version", 0)) == FIRE_LAYOUT_VERSION and float(feature.parts.body.hp) <= 0.0:
			for roof: String in _fire_supported_parts(feature, "body"):
				if float(feature.parts[roof].hp) > 0.0: return fail("CORRUPT_SAVE", "屋頂失去原本體支撐")
	elif feature.has("parts"):
		return fail("CORRUPT_SAVE", "非結構含有耐久部件")
	if kind == "gate":
		var gate: Variant = feature.get("gate")
		if not gate is Dictionary or gate.size() != 4 or not gate.get("open") is bool or gate.get("pending") not in ["", "open", "close"] or not _building_number(gate.get("progress"), 0.0, GATE_SECONDS) or not _building_integer(gate.get("operator_id"), -1, 2147483647):
			return fail("CORRUPT_SAVE", "門操作狀態")
		if str(gate.pending).is_empty():
			if float(gate.progress) != 0.0 or int(gate.operator_id) != -1:
				return fail("CORRUPT_SAVE", "沒有門作業卻保留進度／操作者")
		elif int(gate.operator_id) < 1 or (str(gate.pending) == "open") == bool(gate.open):
			return fail("CORRUPT_SAVE", "門作業方向或操作者")
		for side: String in ["left", "right"]:
			if float(feature.parts["frame:" + side].hp) <= 0.0 and float(feature.parts["leaf:" + side].hp) > 0.0:
				return fail("CORRUPT_SAVE", "倒塌門框仍托住門扇")
			if str(gate.pending) == "close" and float(feature.parts["leaf:" + side].hp) <= 0.0:
				return fail("CORRUPT_SAVE", "破損城門不能進行關門")
	elif feature.has("gate"):
		return fail("CORRUPT_SAVE", "非城門含門操作")
	if feature.has("pending_build"):
		var pending: Variant = feature.pending_build
		if not pending is Dictionary: return fail("CORRUPT_SAVE", "擴建資料")
		var leveling: bool = pending.has("target_level")
		var upgrading: bool = pending.has("target_grade") or leveling
		if pending.size() != (8 if upgrading else 7) or leveling and pending.has("target_grade") or not pending.get("cells") is Array or not pending.get("added_cells") is Array or not pending.get("cost") is Dictionary or not pending.get("clearing") is Array:
			return fail("CORRUPT_SAVE", "擴建資料")
		if str(feature.stage) != "complete" or (kind not in (["settlement_center"] if leveling else CIVIL_KINDS) if upgrading else kind not in FARM_KINDS + PASTURE_KINDS + MILITARY_KINDS + ["palisade", "stone_wall", "prison"]) or not _building_number(pending.get("work"), 0.000001, 1000000.0) or not _building_number(pending.get("progress"), 0.0, float(pending.work)):
			return fail("CORRUPT_SAVE", "擴建進度／種類")
		# Strictly validate JSON cell identities before comparing a private int projection.
		var pending_layout := validate_building_layout(data, kind, pending.cells, _feature_options(feature))
		if not pending_layout.ok: return fail("CORRUPT_SAVE", "擴建尺寸")
		var checked_pending_cells: Array[int] = []
		for value: Variant in pending.cells: checked_pending_cells.append(int(value))
		pending = pending.duplicate()
		pending.cells = checked_pending_cells
		var next_level := settlement_center_invested_level(data, feature) + 1 if leveling else 0
		var bad_target: bool = (not _building_integer(pending.target_level, next_level, mini(SETTLEMENT_MAX_LEVEL, next_level)) or next_level < 2) if leveling else upgrading and not _building_integer(pending.target_grade, building_grade(feature) + 1, mini(CIVIL_MAX_GRADE, building_grade(feature) + 1))
		if upgrading and (bad_target or pending.cells != feature.cells or not pending.added_cells.is_empty() or not pending.clearing.is_empty() or not _building_integer(pending.get("entrance"), int(feature.entrance), int(feature.entrance)) or bool(feature.get("batch_paid", false)) or float(feature.get("production", 0.0)) > 0.0): return fail("CORRUPT_SAVE", "升級不能搬屋、跨級或覆蓋已付批次")
		if (pending.cells != feature.cells if upgrading else pending.cells.size() <= feature.cells.size()):
			return fail("CORRUPT_SAVE", "擴建尺寸")
		var added: Array[int] = []
		var pending_members := {}
		for index: int in pending.cells:
			pending_members[index] = true
			if int(data.height_levels[index]) != int(feature.level):
				return fail("CORRUPT_SAVE", "擴建基底高度與原建築不同")
			if not current_members.has(index):
				added.append(index)
		for index: int in feature.cells:
			if not pending_members.has(index):
				return fail("CORRUPT_SAVE", "擴建不能搬移原建築")
		var actual: Array[int] = []
		for value: Variant in pending.added_cells:
			if not _building_integer(value, 0, data.size.x * data.size.y - 1):
				return fail("CORRUPT_SAVE", "擴建增量格")
			actual.append(int(value))
		added.sort()
		actual.sort()
		if added != actual:
			return fail("CORRUPT_SAVE", "擴建增量／投入")
		var before_cost := _building_cost(data, kind, feature.cells, _feature_options(feature))
		var after_cost := _building_cost(data, kind, pending.cells, _feature_options(feature))
		var expected_cost := {}
		for item: String in after_cost:
			if item not in ["sheep", "horse"]:
				var difference := int(after_cost[item]) - int(before_cost.get(item, 0))
				if difference > 0:
					expected_cost[item] = difference
		var expected_work := maxf(0.5, _building_work(data, kind, pending.cells, _feature_options(feature)) - _building_work(data, kind, feature.cells, _feature_options(feature)))
		if upgrading:
			var upgrade_terms := settlement_level_terms(int(pending.target_level)) if leveling else _civil_upgrade_terms(data, feature, int(pending.target_grade))
			expected_cost = upgrade_terms.cost
			expected_work = float(upgrade_terms.work)
		if pending.cost.size() != expected_cost.size() or not is_equal_approx(float(pending.work), expected_work):
			return fail("CORRUPT_SAVE", "擴建投入／工時與原占地差額不同")
		for item: String in expected_cost:
			if not _building_integer(pending.cost.get(item), int(expected_cost[item]), int(expected_cost[item])):
				return fail("CORRUPT_SAVE", "擴建投入不是原差額的整數數量")
		if not _building_integer(pending.get("entrance"), 0, data.size.x * data.size.y - 1):
			return fail("CORRUPT_SAVE", "擴建入口")
		var pending_entry_found := false
		for entry: Dictionary in _building_entrances(data, pending.cells, int(feature.quarter)):
			pending_entry_found = pending_entry_found or data.index(entry.cell) == int(pending.entrance)
		if not pending_entry_found:
			return fail("CORRUPT_SAVE", "擴建入口與方向不符")
		var seen_sources := {}
		for source: Variant in pending.clearing:
			if not source is String or not data.resource_base.has(source) or seen_sources.has(source):
				return fail("CORRUPT_SAVE", "擴建清理來源")
			seen_sources[source] = true
	if feature.has("repair"):
		var repair: Variant = feature.repair
		if str(feature.stage) != "complete" or feature.has("pending_build") or (kind not in STRUCTURE_KINDS and int(feature.get("civil_version", 0)) != CIVIL_VERSION and int(feature.get("fire_layout_version", 0)) != FIRE_LAYOUT_VERSION) or not repair is Dictionary or repair.size() != 6 or not repair.get("part") is String or not feature.parts.has(repair.part) or not repair.get("cost") is Dictionary:
			return fail("CORRUPT_SAVE", "修理部件／投入")
		if not _building_number(repair.get("amount"), 0.000001, STONE_PART_HP) or not _building_number(repair.get("work"), 0.000001, 1000000.0) or not _building_number(repair.get("progress"), 0.0, float(repair.work)) or not _building_integer(repair.get("work_cell"), 0, data.size.x * data.size.y - 1):
			return fail("CORRUPT_SAVE", "修理工時／接觸格")
		var part: Dictionary = feature_geometry(data, feature).parts[str(repair.part)]
		if float(repair.amount) > float(part.max_hp) or not _near_cells(data, part.cells, int(repair.work_cell), 1) or part.cells.has(int(repair.work_cell)):
			return fail("CORRUPT_SAVE", "修理額度／相鄰接觸格")
		var terms := _repair_terms(feature, part, float(repair.amount))
		if repair.cost.size() != terms.cost.size() or not is_equal_approx(float(repair.work), float(terms.work)):
			return fail("CORRUPT_SAVE", "修理投入／工時與已付額度不同")
		for item: String in terms.cost:
			if not _building_integer(repair.cost.get(item), int(terms.cost[item]), int(terms.cost[item])):
				return fail("CORRUPT_SAVE", "修理投入不是原額度的整數數量")
		if check_navigation and not _repair_contact(data, feature, part, data.cell_from_index(int(repair.work_cell))):
			return fail("CORRUPT_SAVE", "修理額度／實際接觸")
	return ok("建築保存布局")

# Every voluntary surface change shares this guard. Enemy hits never call it.
# Original Controller metadata queries only; no saved state or clock owner.
static func _ship_runtime_pending(data: TerrainData) -> bool:
	if data == null: return false
	var query: Variant = data.get_meta(&"region_operation_pending", Callable())
	return query is Callable and query.is_valid() and bool(query.call())

static func _ship_runtime_journey_active(data: TerrainData) -> bool:
	if data == null: return false
	if _ship_runtime_pending(data): return true
	var query: Variant = data.get_meta(&"ship_journey_active", Callable())
	return query is Callable and query.is_valid() and bool(query.call())

static func _ship_runtime_vehicle_journey(data: TerrainData, identity: String) -> bool:
	if data == null: return false
	var query: Variant = data.get_meta(&"ship_vehicle_in_journey", Callable())
	return query is Callable and query.is_valid() and bool(query.call(identity))

static func _ship_feature_water_contact(data: TerrainData, feature: Dictionary, adjacent: bool = false) -> bool:
	for value: Variant in feature.get("cells", []):
		var index: int = int(value)
		if index < 0 or index >= data.surface_types.size(): continue
		if int(data.surface_types[index]) == TerrainData.Surface.WATER: return true
		if not adjacent: continue
		var cell: Vector2i = data.cell_from_index(index)
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next: Vector2i = cell + direction
			if data.contains(next) and int(data.surface_types[data.index(next)]) == TerrainData.Surface.WATER: return true
	return false

static func _ship_water_geometry_guard(data: TerrainData, key: String, candidate: Dictionary) -> Dictionary:
	if not _ship_runtime_journey_active(data): return ok()
	var original: Dictionary = data.site.get("features", {}).get(key, {})
	# Preserve launch/shore references too, even if the facility itself is dry.
	# Natural water footprint stays frozen even where permission is UNKNOWN.
	for feature: Dictionary in [original, candidate]:
		if str(feature.get("kind", "")) in WATERFRONT_KINDS or _ship_feature_water_contact(data, feature) \
				or str(feature.get("kind", "")) == "level" and _ship_feature_water_contact(data, feature, true):
			return fail("BUSY", "原船隊旅程／補算期間水域、泊位與岸口幾何凍結")
	# Reuse the original detached navigation projection. A valid future feature
	# ID is essential: an empty key would become feature_at=0 in Environment.
	var preview_key: String = key
	if preview_key.is_empty():
		preview_key = str(int(data.site.get("next_feature", 1)))
		if preview_key == "0" or data.site.get("features", {}).has(preview_key): return fail("INVALID", "候選建物編號非法")
	var after: TerrainData = Env.preview_navigation(data, preview_key, candidate)
	if after == null: return fail("INVALID", "候選水域導航不可用")
	if str(candidate.get("kind", "")) == "level" and str(candidate.get("stage", "")) == "complete":
		for index: int in candidate.cells: after.height_levels[index] = int(candidate.level)
		after.site.features.erase(preview_key)
		rebuild_terrain_edges(after)
		Env.rebuild_indexes(after)
	for index: int in range(data.size.x * data.size.y):
		if int(data.surface_types[index]) != TerrainData.Surface.WATER and int(after.surface_types[index]) != TerrainData.Surface.WATER: continue
		var cell: Vector2i = data.cell_from_index(index)
		if data.can_navigate_water(cell) != after.can_navigate_water(cell): return fail("BUSY", "原船隊旅程期間可航水格凍結")
		for direction: Vector2i in TerrainData.DIRECTIONS:
			if data.can_water_step(cell, cell + direction) != after.can_water_step(cell, cell + direction):
				return fail("BUSY", "原船隊旅程期間可航水邊凍結")
	return ok()

static func structure_change_guard(data: TerrainData, key: String, candidate: Dictionary, occupied: Callable, _reason: String = "") -> Dictionary:
	var water_guard: Dictionary = _ship_water_geometry_guard(data, key, candidate)
	if not water_guard.ok: return water_guard
	var original: Dictionary = data.site.features.get(key, {})
	# Registration can be added after an expansion was queued. Protect saved
	# return slots at commit too, even when every registered person is outside.
	if str(original.get("kind", "")) == "barracks" and int(original.get("barracks_layout_version", 1)) == BARRACKS_LAYOUT_VERSION and original.get("cells", []) != candidate.get("cells", []) and _barracks_in_use(data, key):
		return fail("BUSY", "尚有人員登記，無法調整密集軍營布局")
	if not data.site.get("housing", {}).is_empty():
		var housing_after := Env.preview_navigation(data, key, candidate)
		if housing_after == null: return fail("INVALID", "候選住宅導航不可用")
		if str(candidate.get("kind", "")) == "level" and str(candidate.get("stage", "")) == "complete":
			for index: int in candidate.cells: housing_after.height_levels[index] = int(candidate.level)
			housing_after.site.features.erase(key)
			rebuild_terrain_edges(housing_after)
			Env.rebuild_indexes(housing_after)
		var housing_guard := housing_geometry_guard(data, housing_after)
		if not housing_guard.ok: return housing_guard
	if not occupied.is_valid():
		return ok()
	if str(original.get("kind", "")) in MILITARY_KINDS + ["tent"]:
		for index: int in original.get("cells", []):
			if index not in candidate.get("cells", []) and bool(occupied.call(data.cell_from_index(index))):
				return fail("OCCUPIED", "原營地占地仍有人或已預約步進")
	var after: TerrainData = Env.preview_navigation(data, key, candidate)
	if after == null:
		return fail("INVALID", "候選導航不可用")
	if str(candidate.get("kind", "")) == "level" and str(candidate.get("stage", "")) == "complete":
		# Test the actual natural-ground edit before spending the finished job.
		# Packed arrays detach on write; source ground and flags remain untouched.
		for index: int in candidate.cells:
			after.height_levels[index] = int(candidate.level)
		after.site.features.erase(key)
		rebuild_terrain_edges(after)
		Env.rebuild_indexes(after)
	var before_heights := data.navigation_heights()
	var after_heights := after.navigation_heights()
	var checked_before := {}
	var checked_after := {}
	for index: int in range(data.size.x * data.size.y):
		var cell := data.cell_from_index(index)
		var changed := before_heights[index] != after_heights[index] or (data.is_walkable(cell) != after.is_walkable(cell))
		var elevated := int(before_heights[index]) > int(data.height_levels[index]) and data.is_walkable(cell)
		if not changed and not elevated:
			continue
		if not bool(occupied.call(cell)):
			continue
		if changed:
			return fail("OCCUPIED", "有效站位或已承諾步進仍有人")
		if elevated:
			if _component_reaches_ground(data, cell, checked_before) and not _component_reaches_ground(after, cell, checked_after):
				return fail("UNREACHABLE", "不能拆除原人物唯一的下牆路")
	return ok()

static func _component_reaches_ground(data: TerrainData, start: Vector2i, cache: Dictionary) -> bool:
	if cache.has(data.index(start)):
		return bool(cache[data.index(start)])
	var queue: Array[Vector2i] = [start]
	var visited := {data.index(start): true}
	var head := 0
	var reaches := false
	var heights := data.navigation_heights()
	while head < queue.size():
		var cell := queue[head]
		head += 1
		if (data.flags[data.index(cell)] & TerrainData.Flag.WALKABLE) != 0 and int(heights[data.index(cell)]) == int(data.height_levels[data.index(cell)]) and _siege_component_cell_open(data, cell):
			reaches = true
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cell + direction
			if data.contains(next) and not visited.has(data.index(next)) and data.can_step(cell, next) and _siege_component_cell_open(data, next):
				visited[data.index(next)] = true
				queue.append(next)
	for index: int in visited:
		cache[index] = reaches
	return reaches

static func _geometry_edge(data: TerrainData, masks: Dictionary, a: Vector2i, b: Vector2i) -> void:
	var direction := TerrainData.DIRECTIONS.find(b - a)
	if direction < 0:
		return
	# Retain each original in-Site half-edge. Its neighbour must independently
	# supply the reciprocal half before RegionSaveSlot admits a crossing.
	if data.contains(a):
		var ai := data.index(a)
		masks[ai] = int(masks.get(ai, 0)) | (1 << direction)
	if data.contains(b):
		var bi := data.index(b)
		masks[bi] = int(masks.get(bi, 0)) | (1 << ((direction + 2) % 4))

static func _geometry_part(feature: Dictionary, part_id: String, cells: Array[int], role: String, height: int, maximum: float) -> Dictionary:
	var hp := clampf(float(feature.get("parts", {}).get(part_id, {}).get("hp", maximum)), 0.0, maximum)
	return {"cells": cells, "role": role, "height": height, "max_hp": maximum, "hp": hp,
		"state": "destroyed" if hp <= 0.0 else ("damaged" if hp < maximum else "intact")}

# Pure projection used by Environment, Store and rendering. No surface list is saved.
static func feature_geometry(data: TerrainData, feature: Dictionary) -> Dictionary:
	var result := {"heights": {}, "blocked": [], "ramps": {}, "edge_blocks": {}, "parts": {},
		"entry": int(feature.get("entrance", -1)), "operation": [], "sweep": [], "prison_slots": []}
	var cells: Array = feature.get("cells", [])
	if cells.is_empty():
		return result
	var complete := str(feature.get("stage", "")) == "complete"
	if int(feature.get("layout_version", 0)) == 0:
		if complete and bool(feature.get("solid", false)):
			result.blocked = cells.duplicate()
		return result
	var kind := str(feature.get("kind", ""))
	if kind == "siege_ladder" and feature.has("ladder"):
		complete = complete and str(feature.ladder.phase) == "deployed"
	var bounds := _cell_bounds(data, cells)
	var quarter := int(feature.get("quarter", 0))
	var _base_size := Vector2i(bounds.size.y, bounds.size.x) if quarter % 2 else bounds.size
	var base := int(feature.get("level", 0))
	var maximum := STONE_PART_HP if str(feature.get("material", "wood")) == "stone" else WOOD_PART_HP
	if kind == "siege_ladder": maximum = 80.0
	if int(feature.get("civil_version", 0)) == CIVIL_VERSION and kind in BODY_KINDS:
		var body_cells: Array[int] = []
		body_cells.assign(cells)
		result.parts["body"] = _geometry_part(feature, "body", body_cells, "building", base, civil_max_hp(feature))
		if complete and bool(feature.get("solid", false)) and float(result.parts.body.hp) > 0.0: result.blocked = cells.duplicate()
	elif kind == "bridge":
		var bridge := bridge_layout(data, cells, quarter, false)
		result["bridge_walkable"] = []
		if bridge.ok:
			result["bridge_banks"] = [bridge.entrance, bridge.exit]
			if complete and int(feature.get("bridge_clearance", -1)) == 0 and base == int(bridge.level):
				for index: int in cells:
					result.heights[index] = base
					result.bridge_walkable.append(index)
					var cell := data.cell_from_index(index)
					for direction: Vector2i in TerrainData.DIRECTIONS:
						if direction != bridge.axis and direction != -bridge.axis:
							_geometry_edge(data, result.edge_blocks, cell, cell + direction)
	elif kind in ["palisade", "stone_wall"]:
		for index: int in cells:
			var id := "c:%d" % index
			result.parts[id] = _geometry_part(feature, id, [index], "wall", base + WALL_RISE, maximum)
			if complete and float(result.parts[id].hp) > 0.0:
				result.heights[index] = base + WALL_RISE
	elif kind in ["wall_stairs", "siege_ladder"]:
		var lower := _layout_cell(Vector2i(0, 1), Vector2i(1, 2), quarter, bounds.position)
		var upper := _layout_cell(Vector2i.ZERO, Vector2i(1, 2), quarter, bounds.position)
		var external_lower := _layout_cell(Vector2i(0, 2), Vector2i(1, 2), quarter, bounds.position)
		var external_upper := _layout_cell(Vector2i(0, -1), Vector2i(1, 2), quarter, bounds.position)
		result["stair_lower"] = {"cell": lower, "height": base + 1}
		result["stair_upper"] = {"cell": upper, "height": base + 2}
		result["external_lower"] = {"cell": external_lower, "height": base}
		result["external_upper"] = {"cell": external_upper, "height": base + 2}
		result.operation = [data.index(external_lower)] if data.contains(external_lower) else []
		for cell: Vector2i in [lower, upper]:
			if not data.contains(cell):
				continue
			var index := data.index(cell)
			var id := "c:%d" % index
			var height := base + (1 if cell == lower else 2)
			result.parts[id] = _geometry_part(feature, id, [index], "stairs", height, maximum)
			if not complete or float(result.parts[id].hp) <= 0.0:
				continue
			result.heights[index] = height
			var axis := upper - lower
			for direction: Vector2i in TerrainData.DIRECTIONS:
				if direction != axis and direction != -axis:
					_geometry_edge(data, result.edge_blocks, cell, cell + direction)
		if complete:
			if result.heights.has(data.index(lower)):
				_geometry_edge(data, result.ramps, external_lower, lower)
			if result.heights.has(data.index(lower)) and result.heights.has(data.index(upper)):
				_geometry_edge(data, result.ramps, lower, upper)
	elif kind == "gate":
		for side: int in range(2):
			var suffix := "left" if side == 0 else "right"
			var frame_cells: Array[int] = []
			for y: int in range(3):
				frame_cells.append(data.index(_layout_cell(Vector2i(0 if side == 0 else 3, y), Vector2i(4, 3), quarter, bounds.position)))
			var frame_id := "frame:" + suffix
			result.parts[frame_id] = _geometry_part(feature, frame_id, frame_cells, "frame", base, maximum)
			var leaf_cell := _layout_cell(Vector2i(side + 1, 1), Vector2i(4, 3), quarter, bounds.position)
			var leaf_id := "leaf:" + suffix
			result.parts[leaf_id] = _geometry_part(feature, leaf_id, [data.index(leaf_cell)], "leaf", base, WOOD_PART_HP)
			var operation := _layout_cell(Vector2i(side + 1, 3), Vector2i(4, 3), quarter, bounds.position)
			if data.contains(operation):
				result.operation.append(data.index(operation))
			result.sweep.append(data.index(_layout_cell(Vector2i(side + 1, 2), Vector2i(4, 3), quarter, bounds.position)))
			if complete and float(result.parts[frame_id].hp) > 0.0:
				result.blocked.append_array(frame_cells)
			if complete and float(result.parts[frame_id].hp) > 0.0 and float(result.parts[leaf_id].hp) > 0.0 and not bool(feature.get("gate", {}).get("open", false)):
				result.blocked.append(data.index(leaf_cell))
			if complete and str(feature.get("gate", {}).get("pending", "")) == "close":
				for y: int in [0, 2]:
					var inside := _layout_cell(Vector2i(side + 1, y), Vector2i(4, 3), quarter, bounds.position)
					var outside := _layout_cell(Vector2i(side + 1, -1 if y == 0 else 3), Vector2i(4, 3), quarter, bounds.position)
					_geometry_edge(data, result.edge_blocks, inside, outside)
	elif kind in MILITARY_KINDS:
		if complete:
			for module: Dictionary in military_modules(data, feature):
				result.blocked.append_array(module.cells)
	elif kind == "prison":
		var prison := _prison_geometry(data, feature)
		result["prison"] = prison
		result.prison_slots = prison.slots.map(func(slot: Dictionary) -> int: return data.index(slot.cell))
		if complete:
			var member := {}
			for index: int in cells:
				member[index] = true
			for index: int in cells:
				var cell := data.cell_from_index(index)
				for direction: Vector2i in TerrainData.DIRECTIONS:
					var next := cell + direction
					if not data.contains(next) or member.has(data.index(next)) or (cell == prison.gate_cell and next == prison.entry):
						continue
					_geometry_edge(data, result.edge_blocks, cell, next)
	elif complete and bool(feature.get("solid", false)):
		result.blocked = cells.duplicate()
	_fire_layout_geometry(data, feature, result)
	return result

static func _prison_geometry(data: TerrainData, feature: Dictionary) -> Dictionary:
	var bounds := _cell_bounds(data, feature.cells)
	var quarter := int(feature.get("quarter", 0))
	var size := Vector2i(bounds.size.y, bounds.size.x) if quarter % 2 else bounds.size
	var middle := floori(float(size.x - 1) / 2.0)
	var gate := _layout_cell(Vector2i(middle, size.y - 1), size, quarter, bounds.position)
	var entry := _layout_cell(Vector2i(middle, size.y), size, quarter, bounds.position)
	var slots: Array[Dictionary] = []
	var corridor: Array[Vector2i] = []
	var pairs: Array = []
	if size == Vector2i.ONE:
		pairs.append([gate, entry])
	elif size.x == 1 or size.y == 1:
		var length := maxi(size.x, size.y)
		for n: int in range(length - 1):
			var local := Vector2i(0, size.y - 1 - n) if size.x == 1 else Vector2i(n, 0)
			corridor.append(_layout_cell(local, size, quarter, bounds.position))
		var last := Vector2i(0, 0) if size.x == 1 else Vector2i(size.x - 1, 0)
		pairs.append([_layout_cell(last, size, quarter, bounds.position), corridor.back()])
	else:
		for x: int in range(size.x):
			corridor.append(_layout_cell(Vector2i(x, size.y - 1), size, quarter, bounds.position))
		for depth: int in range(1, size.y):
			var contact := _layout_cell(Vector2i(middle, size.y - 1 - depth), size, quarter, bounds.position)
			corridor.append(contact)
			for side: int in [-1, 1]:
				if middle + side >= 0 and middle + side < size.x:
					pairs.append([_layout_cell(Vector2i(middle + side, size.y - 1 - depth), size, quarter, bounds.position), contact])
	if data.contains(entry) and data.is_terrain_walkable(entry) and data.can_terrain_step(gate, entry):
		for pair: Array in pairs:
			if data.can_terrain_step(pair[0], pair[1]):
				slots.append({"cell": pair[0], "contact_cell": pair[1], "exit_cell": entry})
	return {"entry": entry, "gate_cell": gate, "slots": slots, "corridor": corridor}

static func prison_layout(data: TerrainData, key: String) -> Dictionary:
	var feature: Dictionary = data.site.get("features", {}).get(key, {})
	if str(feature.get("kind", "")) != "prison" or int(feature.get("layout_version", 0)) != BUILDING_LAYOUT_VERSION:
		return fail("NO_TARGET", "戰俘營不存在")
	var result := _prison_geometry(data, feature)
	return ok("拘押布局", {"id": key, "complete": str(feature.stage) == "complete", "entry": result.entry,
		"gate_cell": result.gate_cell, "slots": result.slots, "corridor": result.corridor, "capacity": result.slots.size()})

static func preview_build(data: TerrainData, kind: String, cells: Array[int], occupied: Callable = Callable(), options: Dictionary = {}) -> Dictionary:
	if kind == "tent":
		return fail("INVALID", "營帳須由後勤人物攜帶營帳包搭設")
	if kind == "settlement_center" and (data.site.has("settlement") or _settlement_center_count(data) > 0):
		return fail("INVALID", "每個 Site 最多一座聚落中心")
	return _preview_build(data, kind, cells, occupied, options)

static func ecology_build_guard(data: TerrainData, cells: Array, existing_key: String = "") -> Dictionary:
	if not Env.ecology_active(data): return ok()
	var existing: Array = data.site.get("features", {}).get(existing_key, {}).get("cells", []) if not existing_key.is_empty() else []
	for value: Variant in cells:
		if not _building_integer(value, 0, data.size.x * data.size.y - 1): return fail("INVALID")
		var index := int(value)
		if existing.has(index): continue
		for source: String in data.resources_at.get(index, []):
			var resource := Env.resource(data, source)
			if int(resource.kind) in Env.ECOLOGY_KINDS and str(resource.get("eco_mode", "sustainable")) == "protected":
				return fail("ECOLOGY_PROTECTED", "休養保護中的來源格禁止新增占地；已付工程與進度保留")
	return ok()

static func ecology_feature_work_guard(data: TerrainData, feature: Dictionary, action: String) -> Dictionary:
	if str(feature.get("stage", "")) != "complete": return ecology_build_guard(data, feature.get("cells", []))
	if action == "construct" and feature.has("pending_build"): return ecology_build_guard(data, feature.pending_build.get("added_cells", []))
	return ok()

# Geometry is projected from the original feature. It never stores people or teams.
static func military_modules(data: TerrainData, feature: Dictionary) -> Array[Dictionary]:
	var modules: Array[Dictionary] = []
	var kind := str(feature.get("kind", ""))
	if kind not in MILITARY_KINDS or feature.get("cells", []).is_empty():
		return modules
	var bounds := _cell_bounds(data, feature.cells)
	var quarter := int(feature.get("quarter", 0))
	if kind == "training_ground":
		# These fixed 2x1 racks face south; their physical cells match the bitmap.
		for y: int in [bounds.position.y, bounds.end.y - 1]:
			for x: int in range(bounds.position.x + 1, bounds.end.x - 2, 4):
				modules.append({"kind": "training_station", "variant": "", "quarter": 0,
					"cells": [data.index(Vector2i(x, y)), data.index(Vector2i(x + 1, y))]})
		return modules
	var base_size := Vector2i(bounds.size.y, bounds.size.x) if quarter % 2 else bounds.size
	var templates: Array[Dictionary] = []
	var version: Variant = feature.get("barracks_layout_version", 1)
	if not _building_integer(version, 1, BARRACKS_LAYOUT_VERSION):
		return modules
	if int(version) == 1:
		for y: int in range(1, base_size.y - 4, 5):
			templates.append({"origin": Vector2i(0, y), "size": Vector2i(3, 4), "variant": "long", "quarter": 3})
			templates.append({"origin": Vector2i(base_size.x - 3, y), "size": Vector2i(3, 4), "variant": "long", "quarter": 1})
	else:
		# Fixed 3x2 dormitories face the compound entrance; cross lanes and at least
		# four central columns join every row to the south entrance and HQ.
		var side_width := floori(float(base_size.x - 4) / 2.0)
		for y: int in range(1, base_size.y - 2, 3):
			for x: int in range(0, side_width - 2, 4):
				templates.append({"kind": "barracks_dormitory", "origin": Vector2i(x, y), "size": Vector2i(3, 2), "variant": "", "quarter": 0})
				templates.append({"kind": "barracks_dormitory", "origin": Vector2i(base_size.x - 3 - x, y), "size": Vector2i(3, 2), "variant": "", "quarter": 0})
	templates.append({"origin": Vector2i(floori(float(base_size.x - 2) / 2.0), 0), "size": Vector2i(2, 2), "variant": "small", "quarter": 0})
	for template: Dictionary in templates:
		var cells: Array[int] = []
		for y: int in range(template.origin.y, template.origin.y + template.size.y):
			for x: int in range(template.origin.x, template.origin.x + template.size.x):
				cells.append(data.index(_layout_cell(Vector2i(x, y), base_size, quarter, bounds.position)))
		var module := {"kind": str(template.get("kind", "house")), "variant": str(template.variant), "quarter": (int(template.quarter) + quarter) % 4, "cells": cells}
		if str(module.kind) == "barracks_dormitory":
			module["base_size"] = Vector2i(3, 2) # South-facing size before its own rotation.
			module["base_origin"] = template.origin # Unrotated compound-local position.
		modules.append(module)
	return modules

static func military_walkable_cells(data: TerrainData, feature: Dictionary) -> Array[int]:
	var result: Array[int] = []
	if str(feature.get("kind", "")) not in MILITARY_KINDS:
		return result
	var blocked := {}
	for module: Dictionary in military_modules(data, feature):
		for index: int in module.cells:
			blocked[index] = true
	for index: int in feature.get("cells", []):
		if not blocked.has(index) and data.is_terrain_walkable(data.cell_from_index(index)):
			result.append(index)
	return result

static func military_capacity(data: TerrainData, feature: Dictionary) -> int:
	return military_walkable_cells(data, feature).size()

static func military_layout(data: TerrainData, key: String) -> Dictionary:
	var feature: Dictionary = data.site.get("features", {}).get(key, {})
	if str(feature.get("kind", "")) not in MILITARY_KINDS or int(feature.get("layout_version", 0)) != BUILDING_LAYOUT_VERSION:
		return fail("NO_TARGET")
	var standing := military_walkable_cells(data, feature)
	return ok("軍事設施布局", {"id": key, "kind": str(feature.kind), "complete": str(feature.stage) == "complete",
		"owner_faction": int(feature.owner_faction), "bounds": _cell_bounds(data, feature.cells), "cells": feature.cells.duplicate(),
		"capacity": standing.size(), "walkable_cells": standing,
		"modules": military_modules(data, feature), "entry": data.cell_from_index(int(feature.entrance))})

static func preview_deploy_tent(data: TerrainData, cells: Array[int], actor_cell: Vector2i, owner_faction: int, occupied: Callable = Callable(), quarter: int = 0) -> Dictionary:
	if data == null or data.site.is_empty() or owner_faction < 0 or owner_faction > 100000000 or not data.contains(actor_cell):
		return fail("INVALID")
	var preview := _preview_build(data, "tent", cells, occupied, {"owner_faction": owner_faction, "quarter": quarter}, "", false)
	if not preview.ok:
		return preview
	if not _tent_contact(data, cells, actor_cell):
		return fail("TOO_FAR", "後勤人物須在營帳占地外側相鄰格搭設")
	if not preview.clearing.is_empty():
		return fail("OCCUPIED", "營帳須搭在已清理的合法空地")
	return preview

static func deploy_tent(data: TerrainData, cells: Array[int], cargo: Dictionary, holder: Dictionary, expected_version: int, actor_cell: Vector2i, owner_faction: int, occupied: Callable = Callable(), quarter: int = 0) -> Dictionary:
	var preview := preview_deploy_tent(data, cells, actor_cell, owner_faction, occupied, quarter)
	if not preview.ok:
		return preview
	if not _item_holder_shape(holder) or not str(holder.holder).begins_with("person:") or not _resource_stack(cargo):
		return fail("INVALID", "須使用原後勤人物的行囊")
	if int(holder.version) != expected_version or expected_version >= 2147483646:
		return fail("STALE_SOURCE")
	if not can_pay(cargo, {"camp_tent": 1}):
		return fail("EMPTY", "原行囊沒有營帳包")
	if not _building_integer(data.site.get("next_feature"), 1, 2147483646) or data.site.features.has(str(int(data.site.next_feature))):
		return fail("INVALID", "營帳建築身分序號失效，未扣物")
	# All callbacks finished. Cargo and the completed original feature commit once.
	var key := str(data.site.next_feature)
	var feature := {"kind": "tent", "cells": cells.duplicate(), "entrance": int(preview.entrance), "source": "",
		"stage": "complete", "progress": 2.0, "solid": false, "cost": {"camp_tent": 1}, "work": 2.0,
		"clearing": [], "level": int(preview.level), "production": 0.0, "batch_paid": false, "status": "已搭設"}
	feature.merge(preview.options, true)
	add_items(cargo, {"camp_tent": 1}, -1)
	if int(cargo.camp_tent) == 0:
		cargo.erase("camp_tent")
	holder.version = expected_version + 1
	data.site.next_feature = int(data.site.next_feature) + 1
	data.site.features[key] = feature
	Env.rebuild_indexes(data)
	if Env.ecology_active(data): ecology_reconcile(data)
	return ok("已由原行囊搭設營帳", {"feature": key})

static func preview_pack_tent(data: TerrainData, key: String, cargo: Dictionary, holder: Dictionary, actor_cell: Vector2i, owner_faction: int, occupied: Callable = Callable(), capacity: int = CARRY_CAPACITY) -> Dictionary:
	if _ship_runtime_pending(data): return fail("BUSY", "原固定目標仍待補算或交接；暫不能接受新設施操作")
	if data == null or data.site.is_empty() or not data.contains(actor_cell):
		return fail("INVALID")
	var feature: Dictionary = data.site.features.get(key, {})
	if str(feature.get("kind", "")) != "tent" or str(feature.get("stage", "")) != "complete":
		return fail("NO_TARGET")
	if owner_faction < 0 or owner_faction != int(feature.get("owner_faction", -1)):
		return fail("NO_AUTHORITY")
	if not _tent_contact(data, feature.cells, actor_cell):
		return fail("TOO_FAR", "後勤人物須在營帳外側相鄰格收納")
	if not _item_holder_shape(holder) or not str(holder.holder).begins_with("person:") or not _resource_stack(cargo):
		return fail("INVALID", "須使用原後勤人物的行囊")
	if capacity < 0 or carried_load(data.site, cargo, holder) + 1 > capacity:
		return fail("STORAGE_FULL")
	if _feature_has_work(data, key):
		return fail("BUSY")
	return structure_change_guard(data, key, {}, occupied, "pack")

static func pack_tent(data: TerrainData, key: String, cargo: Dictionary, holder: Dictionary, expected_version: int, actor_cell: Vector2i, owner_faction: int, occupied: Callable = Callable(), capacity: int = CARRY_CAPACITY) -> Dictionary:
	var preview := preview_pack_tent(data, key, cargo, holder, actor_cell, owner_faction, occupied, capacity)
	if not preview.ok:
		return preview
	if not _item_holder_shape(holder) or not _resource_stack(cargo) or int(holder.version) != expected_version or expected_version >= 2147483646:
		return fail("STALE_SOURCE")
	if carried_load(data.site, cargo, holder) + 1 > capacity:
		return fail("STORAGE_FULL")
	data.site.features.erase(key)
	add_items(cargo, {"camp_tent": 1})
	holder.version = expected_version + 1
	Env.rebuild_indexes(data)
	if Env.ecology_active(data): ecology_reconcile(data)
	return ok("營帳已收回原行囊", {"feature": key})

static func _tent_contact(data: TerrainData, cells: Array[int], actor_cell: Vector2i) -> bool:
	if not data.is_walkable(actor_cell) or cells.has(data.index(actor_cell)):
		return false
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var inside := actor_cell + direction
		if data.contains(inside) and cells.has(data.index(inside)) and data.can_step(actor_cell, inside):
			return true
	return false

static func _preview_build(data: TerrainData, kind: String, cells: Array[int], occupied: Callable, options: Dictionary, existing_key: String = "", depot_payment: bool = true) -> Dictionary:
	if _ship_runtime_pending(data): return fail("BUSY", "原固定目標仍待補算或交接；暫不能接受新設施操作")
	var layout := validate_building_layout(data, kind, cells, options)
	if not layout.ok:
		return layout
	var ecology_guard := ecology_build_guard(data, cells, existing_key)
	if not ecology_guard.ok: return ecology_guard
	var spec := building_spec(kind, options)
	var definition: Dictionary = FEATURES[kind]
	if kind == "bridge":
		return _preview_bridge(data, cells, occupied, spec, layout.bounds, existing_key, depot_payment)
	if kind not in ["road", "fighting_position"]:
		for other: Dictionary in data.site.features.values():
			if str(other.kind) != "bridge": continue
			var bridge := bridge_layout(data, other.cells, int(other.quarter), false)
			if bridge.ok and (cells.has(int(bridge.entrance)) or cells.has(int(bridge.exit))):
				return fail("UNREACHABLE", "需保留橋梁兩岸的原落腳格")
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
		if (data.feature_at[i] != 0 and str(data.feature_at[i]) != existing_key) or i == int(data.site.depot_cell) or _siege_vehicle_claims(data, cell) or (occupied.is_valid() and bool(occupied.call(cell))):
			return fail("OCCUPIED")
		if bool(definition.solid) or kind in ["wall_stairs", "siege_ladder"]:
			for other_key: String in data.site.features:
				var other: Dictionary = data.site.features[other_key]
				# A completed wall has no permanent operating doorway. A stair
				# must be allowed to meet its former construction-side cell.
				var retired_wall_entry := str(other.kind) in ["palisade", "stone_wall"] and str(other.stage) == "complete" and not other.has("pending_build") and not other.has("repair")
				if other_key != existing_key and not retired_wall_entry and int(other.entrance) == i:
					return fail("UNREACHABLE", "需保留既有建築工作入口")
		if data.ramp_edges[i] != 0 and kind not in ["road", "level"]:
			return fail("TERRAIN", "保留現有坡口")
		var height := int(data.height_levels[i])
		min_height = mini(min_height, height)
		max_height = maxi(max_height, height)
		if first_height < 0:
			first_height = height
		if kind != "level" and height != first_height:
			return fail("TERRAIN", "占地跨越高差，請先整地")
		if kind not in ["farm", "fiber_farm", "fodder_farm", "pasture", "horse_ranch", "road", "level", "intake", "saltworks"] and kind not in WATERFRONT_KINDS and data.foundation[i] < 35:
			return fail("TERRAIN", "地基不足")
		if (kind == "intake" and data.foundation[i] < 10) or ((kind == "saltworks" or kind in WATERFRONT_KINDS) and data.foundation[i] < 25):
			return fail("TERRAIN", "岸邊作業地基不足")
		if kind in ["farm", "fiber_farm", "fodder_farm"] and (data.fertility[i] < 30 or data.drainage[i] < 30):
			return fail("TERRAIN", "土壤或排水不適耕")
		if kind in PASTURE_KINDS and Env.land(data, cell, int(existing_key) if existing_key.is_valid_int() else 0).pasture < 25:
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
	for candidate: Dictionary in _building_entrances(data, cells, int(spec.options.quarter)):
		var cell: Vector2i = candidate.cell
		var inner: Vector2i = candidate.inner
		if kind == "level" and int(data.height_levels[data.index(inner)]) != min_height:
			continue
		if data.is_walkable(cell) and data.can_terrain_step(cell, inner):
			entrance = data.index(cell)
			break
	if entrance < 0:
		return fail("UNREACHABLE", "此方向需保留可達的外部入口")
	var candidate_feature := {"kind": kind, "cells": cells, "stage": "complete", "solid": bool(definition.solid),
		"level": min_height, "entrance": entrance}
	candidate_feature.merge(spec.options, true)
	var geometry := feature_geometry(data, candidate_feature)
	if kind in MILITARY_KINDS:
		entrance = -1
		for candidate: Dictionary in _building_entrances(data, cells, int(spec.options.quarter)):
			if not geometry.blocked.has(data.index(candidate.inner)) and data.is_walkable(candidate.cell) and data.can_terrain_step(candidate.cell, candidate.inner):
				entrance = data.index(candidate.cell)
				break
		if entrance < 0:
			return fail("UNREACHABLE", "軍事設施沒有可進入中庭的外部入口")
		candidate_feature.entrance = entrance
		geometry.entry = entrance
	if kind in ["wall_stairs", "siege_ladder"]:
		var lower: Vector2i = geometry.external_lower.cell
		var upper: Vector2i = geometry.external_upper.cell
		if not data.is_walkable(lower) or not data.is_walkable(upper) or data.effective_height(lower) != min_height or data.effective_height(upper) != min_height + WALL_RISE:
			return fail("UNREACHABLE", "梯底須接地面，梯頂須接同高牆頂或天然平台")
		entrance = data.index(lower)
		candidate_feature.entrance = entrance
		geometry.entry = entrance
	if kind == "prison":
		var prison := _prison_geometry(data, candidate_feature)
		if prison.slots.is_empty() or not data.is_walkable(prison.entry):
			return fail("UNREACHABLE", "入口、接觸與合法拘押位置不足")
		entrance = data.index(prison.entry)
		candidate_feature.entrance = entrance
		geometry.entry = entrance
	if kind in WATERFRONT_KINDS:
		var waterfront := validate_waterfront(data, candidate_feature)
		if not waterfront.ok: return waterfront
	if not data.site.get("housing", {}).is_empty():
		var after := Env.preview_navigation(data, existing_key, candidate_feature)
		if after == null: return fail("INVALID")
		var housing_guard := housing_geometry_guard(data, after)
		if not housing_guard.ok: return housing_guard
	var water_guard: Dictionary = _ship_water_geometry_guard(data, existing_key, candidate_feature)
	if not water_guard.ok: return water_guard
	var cost := _building_cost(data, kind, cells, spec.options)
	if depot_payment and existing_key.is_empty() and (not can_pay(data.site.inventory, cost) or not can_pay(data.site.inventory, {"tools": 1})):
		return fail("MATERIALS", items_text(cost))
	return ok("可建設；清理 %d 處；%s" % [clearing.size(), items_text(cost)],
		{"cost": cost, "clearing": clearing, "entrance": entrance, "source": source, "level": min_height,
		"cells": cells.duplicate(), "options": spec.options, "bounds": layout.bounds, "geometry": geometry,
		"work": _building_work(data, kind, cells, spec.options)})

# A bridge is one width-one surface. Its banks and deck derive from the original
# feature cells; water/ground flags remain immutable and no lower lane is created.
static func bridge_layout(data: TerrainData, cells: Array, quarter: int, check_navigation: bool = true) -> Dictionary:
	if cells.size() < 2 or cells.size() > 12 or quarter < 0 or quarter > 3:
		return fail("INVALID", "橋面須為一格寬、二至十二格長")
	var members := {}
	for value: Variant in cells:
		if not _building_integer(value, 0, data.size.x * data.size.y - 1) or members.has(int(value)):
			return fail("INVALID", "橋面格位非法")
		members[int(value)] = true
	var bounds := _cell_bounds(data, cells)
	var vertical := quarter % 2 == 0
	if (vertical and bounds.size != Vector2i(1, cells.size())) or (not vertical and bounds.size != Vector2i(cells.size(), 1)):
		return fail("INVALID", "橋面必須沿入口方向連續，不能轉彎或缺格")
	var axis := Vector2i.DOWN if vertical else Vector2i.RIGHT
	var low := bounds.position - axis
	var high := bounds.end - Vector2i.ONE + axis
	if not data.contains(low) or not data.contains(high):
		return fail("UNREACHABLE", "橋梁兩岸都須在目前 Site 內")
	for bank: Vector2i in [low, high]:
		var index := data.index(bank)
		if data.surface_types[index] == TerrainData.Surface.WATER or (data.flags[index] & TerrainData.Flag.WALKABLE) == 0:
			return fail("TERRAIN", "橋梁必須真正連接兩岸陸地")
		if check_navigation and (not data.is_walkable(bank) or data.effective_height(bank) != int(data.height_levels[index])):
			return fail("UNREACHABLE", "橋岸必須是可站立的原地面")
	var deck := int(data.height_levels[data.index(low)])
	if deck != int(data.height_levels[data.index(high)]):
		return fail("TERRAIN", "首版橋梁兩岸需同高")
	for index: int in cells:
		if data.surface_types[index] != TerrainData.Surface.WATER or (data.flags[index] & TerrainData.Flag.WALKABLE) != 0 or int(data.height_levels[index]) > deck:
			return fail("TERRAIN", "整段橋面必須跨越低於或等於橋岸的連續水面")
	if check_navigation:
		var direction := TerrainData.DIRECTIONS.find(axis)
		var ramps := data.navigation_ramps()
		if (ramps[data.index(low)] & (1 << (direction + 4))) != 0 or (ramps[data.index(high)] & (1 << (((direction + 2) % 4) + 4))) != 0:
			return fail("UNREACHABLE", "原橋岸連接邊被阻擋")
	var entry := high if quarter in [0, 3] else low
	var exit_bank := low if quarter in [0, 3] else high
	return ok("兩岸橋面", {"entrance": data.index(entry), "exit": data.index(exit_bank), "level": deck, "axis": axis, "bounds": bounds})

static func validate_bridge(data: TerrainData, feature: Dictionary, check_navigation: bool = true) -> Dictionary:
	if str(feature.get("kind", "")) != "bridge" or not _building_integer(feature.get("bridge_version"), 1, 1) or not _building_integer(feature.get("bridge_clearance"), 0, 0):
		return fail("INVALID", "橋梁版本／零淨空合同非法")
	if feature.has("parts") or feature.has("repair") or feature.has("pending_build"):
		return fail("INVALID", "首版橋梁沒有戰鬥部件、修理或改變兩岸的擴建")
	var bridge := bridge_layout(data, feature.cells, int(feature.quarter), check_navigation)
	if not bridge.ok: return bridge
	if not _building_integer(feature.get("level"), int(bridge.level), int(bridge.level)) or not _building_integer(feature.get("entrance"), int(bridge.entrance), int(bridge.entrance)):
		return fail("INVALID", "橋面高度／入口與原兩岸不同")
	var cost := _building_cost(data, "bridge", feature.cells, _feature_options(feature))
	var work := _building_work(data, "bridge", feature.cells, _feature_options(feature))
	if not feature.get("cost") is Dictionary or feature.cost.size() != cost.size() or not _building_number(feature.get("work"), work, work):
		return fail("INVALID", "橋梁材料／工時與原跨度不同")
	for item: String in cost:
		if not _building_integer(feature.cost.get(item), int(cost[item]), int(cost[item])):
			return fail("INVALID", "橋梁投入不是原跨度所需材料")
	if str(feature.stage) == "complete" and not _building_number(feature.get("progress"), work, work):
		return fail("INVALID", "橋梁尚未完成原施工工時")
	return ok()

static func _preview_bridge(data: TerrainData, cells: Array[int], occupied: Callable, spec: Dictionary, bounds: Rect2i, existing_key: String, depot_payment: bool) -> Dictionary:
	var bridge := bridge_layout(data, cells, int(spec.options.quarter))
	if not bridge.ok: return bridge
	for index: int in cells:
		if (data.feature_at[index] != 0 and str(data.feature_at[index]) != existing_key) or index == int(data.site.depot_cell) or (occupied.is_valid() and bool(occupied.call(data.cell_from_index(index)))):
			return fail("OCCUPIED", "橋面水域已有原人物、船體或已預約步進")
	var cost := _building_cost(data, "bridge", cells, spec.options)
	if depot_payment and existing_key.is_empty() and (not can_pay(data.site.inventory, cost) or not can_pay(data.site.inventory, {"tools": 1})):
		return fail("MATERIALS", items_text(cost))
	var feature := {"kind": "bridge", "cells": cells, "stage": "complete", "solid": false, "level": int(bridge.level), "entrance": int(bridge.entrance)}
	feature.merge(spec.options, true)
	var water_guard: Dictionary = _ship_water_geometry_guard(data, existing_key, feature)
	if not water_guard.ok: return water_guard
	return ok("可架橋；橋下不通船；" + items_text(cost), {"cost": cost, "clearing": [], "entrance": int(bridge.entrance),
		"source": "", "level": int(bridge.level), "cells": cells.duplicate(), "options": spec.options, "bounds": bounds,
		"geometry": feature_geometry(data, feature), "work": _building_work(data, "bridge", cells, spec.options)})

static func _building_entrances(data: TerrainData, cells: Array, quarter: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var members := {}
	for index: int in cells:
		members[index] = true
	var direction: Vector2i = [Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT][quarter]
	var centre := Vector2(_cell_bounds(data, cells).get_center())
	for index: int in cells:
		var inner := data.cell_from_index(index)
		var cell := inner + direction
		if data.contains(cell) and not members.has(data.index(cell)):
			result.append({"cell": cell, "inner": inner})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := Vector2(a.cell).distance_squared_to(centre)
		var db := Vector2(b.cell).distance_squared_to(centre)
		return data.index(a.cell) < data.index(b.cell) if is_equal_approx(da, db) else da < db)
	return result

static func _perimeter(data: TerrainData, cells: Array) -> int:
	var members := {}
	for index: int in cells:
		members[index] = true
	var count := 0
	for index: int in cells:
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := data.cell_from_index(index) + direction
			if not data.contains(next) or not members.has(data.index(next)):
				count += 1
	return count

static func _building_cost(data: TerrainData, kind: String, cells: Array, options: Dictionary) -> Dictionary:
	var spec := building_spec(kind, options)
	var cost: Dictionary = spec.cost.duplicate()
	if kind in MILITARY_KINDS + ["road", "palisade", "stone_wall", "fighting_position", "bridge"]:
		for item: String in cost:
			cost[item] = int(cost[item]) * cells.size()
	elif kind in PASTURE_KINDS:
		cost.wood = int(cost.wood) + maxi(0, _perimeter(data, cells) - (16 if kind == "horse_ranch" else 12))
	elif kind == "prison":
		cost.wood = _perimeter(data, cells)
	return cost

static func _building_work(data: TerrainData, kind: String, cells: Array, options: Dictionary) -> float:
	var work := float(building_spec(kind, options).work)
	if kind in FARM_KINDS + MILITARY_KINDS or kind in ["road", "level", "palisade", "stone_wall", "fighting_position", "bridge"]:
		return work * cells.size()
	if kind in PASTURE_KINDS:
		return work + maxi(0, _perimeter(data, cells) - (16 if kind == "horse_ranch" else 12)) * 0.5
	if kind == "prison":
		return 2.0 + _perimeter(data, cells) * 2.0
	return work

static func request_build(data: TerrainData, kind: String, cells: Array[int], occupied: Callable = Callable(), options: Dictionary = {}) -> Dictionary:
	var preview := preview_build(data, kind, cells, occupied, options)
	if not preview.ok:
		return preview
	# Founding writes site.settlement in the same transaction (SiteSettlement.found).
	if kind == "settlement_center" and options.get("settlement_found") != true:
		return fail("NO_AUTHORITY", "聚落中心須由首長在場經「建立聚落」安排")
	var key := str(data.site.next_feature)
	data.site.next_feature = int(data.site.next_feature) + 1
	var definition: Dictionary = FEATURES[kind]
	add_items(data.site.inventory, preview.cost, -1)
	data.site.features[key] = {"kind": kind, "cells": cells.duplicate(), "entrance": int(preview.entrance), "source": str(preview.source),
		"stage": "planned", "progress": 0.0, "solid": bool(definition.solid), "cost": preview.cost,
		"work": float(preview.work),
		"clearing": preview.clearing, "level": int(preview.level), "production": 0.0, "batch_paid": false, "status": "待施工"}
	data.site.features[key].merge(preview.options, true)
	if kind in BODY_KINDS:
		data.site.features[key]["civil_version"] = CIVIL_VERSION
		data.site.features[key]["building_grade"] = 1
		data.site.features[key]["parts"] = {"body": {"hp": civil_max_hp(data.site.features[key])}}
	_fire_layout_initialize(data.site.features[key])
	if kind in STRUCTURE_KINDS:
		data.site.features[key]["parts"] = {}
		for part: String in preview.geometry.parts:
			data.site.features[key].parts[part] = {"hp": float(preview.geometry.parts[part].max_hp)}
	if kind == "siege_ladder":
		data.site.features[key]["ladder"] = {"version": 1, "phase": "folded", "pending": "", "progress": 0.0, "workers": []}
	if kind == "gate":
		data.site.features[key]["gate"] = {"open": false, "pending": "", "progress": 0.0, "operator_id": -1}
	if kind in ["pasture", "horse_ranch"]:
		data.site.features[key].species = "horse" if kind == "horse_ranch" else "sheep"
		data.site.features[key].residents = 2 if kind == "horse_ranch" else 1
	data.site.zones.append({"cells": cells.duplicate(), "kind": -1, "action": "construct", "feature": key, "active": true})
	Env.rebuild_indexes(data)
	if Env.ecology_active(data): ecology_reconcile(data)
	return ok("已預留材料並排入施工：" + str(definition.name), {"feature": key})

# Shore facilities retain one original paid production batch until launching.
static func waterfront_facing(feature: Dictionary) -> Vector2i:
	var quarter := int(feature.get("quarter", -1))
	return TerrainData.DIRECTIONS[quarter] if quarter >= 0 and quarter < 4 else Vector2i.ZERO

static func validate_waterfront(data: TerrainData, feature: Dictionary, check_navigation: bool = true) -> Dictionary:
	if str(feature.get("kind", "")) not in WATERFRONT_KINDS:
		return fail("CORRUPT_SAVE", "非水岸設施含有水岸欄位")
	if not _building_integer(feature.get("waterfront_version"), 1, 1) or not _building_integer(feature.get("launch_cell"), 0, data.size.x * data.size.y - 1):
		return fail("CORRUPT_SAVE", "水岸版本／泊位格非法")
	var facing := waterfront_facing(feature)
	var anchor := data.cell_from_index(int(feature.launch_cell))
	var shore := anchor - facing
	# Saved JSON cells are integral floats until the original Store boundary
	# normalizes them. Compare the validated numeric value, not Variant type.
	var shore_in_feature := false
	for value: Variant in feature.get("cells", []):
		if _building_integer(value, 0, data.size.x * data.size.y - 1) and int(value) == data.index(shore):
			shore_in_feature = true
			break
	if not data.contains(shore) or not shore_in_feature:
		return fail("WATER", "泊位需接鄰本設施朝向水面的岸格")
	if check_navigation and (not data.is_terrain_walkable(shore) or not data.can_navigate_water(anchor) or not data.can_water_step(anchor, anchor + facing) or absi(data.effective_height(shore) - data.effective_height(anchor)) > 1):
		return fail("WATER", "岸上工作面、泊位或出水邊不合法")
	return ok("合法水岸")

static func validate_ship_build(_data: TerrainData, feature: Dictionary) -> Dictionary:
	if not feature.has("ship_build"):
		if str(feature.get("kind", "")) in WATERFRONT_KINDS and (bool(feature.get("batch_paid", false)) or float(feature.get("production", 0.0)) != 0.0):
			return fail("CORRUPT_SAVE", "水岸設施沒有原造船投入批次")
		return ok()
	var job: Variant = feature.ship_build
	if str(feature.get("kind", "")) != "shipyard" or str(feature.get("stage", "")) != "complete" or feature.has("pending_build") or feature.has("repair") or not bool(feature.get("batch_paid", false)):
		return fail("CORRUPT_SAVE", "造船批次必須在已完成的原船塢")
	if not job is Dictionary or job.size() != 6 or not _building_integer(job.get("version"), 1, 1) or not _building_integer(job.get("recipe_version"), 1, 1) or not job.get("ship_type") is String or not Ships.is_kind(job.ship_type) or not _building_integer(job.get("team_id"), 1, 100000000):
		return fail("CORRUPT_SAVE", "造船批次格式非法")
	var cost: Dictionary = Ships.build_cost(str(job.ship_type))
	var work := Ships.build_work_seconds(str(job.ship_type))
	if not job.get("paid_cost") is Dictionary or job.paid_cost.size() != cost.size() or not _building_number(job.get("total_work"), work, work) or work <= 0.0 or not _building_number(feature.get("production"), 0.0, work / 60.0):
		return fail("CORRUPT_SAVE", "造船已付原料／工時非法")
	for resource: String in cost:
		if not _building_integer(job.paid_cost.get(resource), int(cost[resource]), int(cost[resource])):
			return fail("CORRUPT_SAVE", "造船投入與原配方不符")
	return ok()

static func ship_build_uses_team(data: TerrainData, team_id: int) -> bool:
	for feature: Dictionary in data.site.get("features", {}).values():
		if int(feature.get("ship_build", {}).get("team_id", 0)) == team_id: return true
	return false

static func _ship_launch_query(data: TerrainData, feature: Dictionary, ship_type: String, occupied: Callable = Callable()) -> Dictionary:
	var journey: Variant = data.get_meta(&"ship_journey_active", Callable())
	if journey is Callable and journey.is_valid() and bool(journey.call()): return fail("BUSY", "原船隊旅程期間來源水域凍結，原已付造船批次保留等待下水")
	var waterfront := validate_waterfront(data, feature)
	if not waterfront.ok: return waterfront
	var facing := waterfront_facing(feature)
	var anchor := data.cell_from_index(int(feature.launch_cell))
	var cells: Array[Vector2i] = Ships.footprint(ship_type, anchor, facing)
	var next_cells: Array[Vector2i] = Ships.footprint(ship_type, anchor + facing, facing)
	if cells.is_empty() or not data.can_place_water_vehicle(cells) or not data.can_place_water_vehicle(next_cells):
		return fail("WATER", "完整船體泊位或出水道不足")
	for cell: Vector2i in cells:
		if not data.can_water_step(cell, cell + facing): return fail("WATER", "出水邊不合法")
		if _siege_vehicle_claims(data, cell) or occupied.is_valid() and bool(occupied.call(cell)):
			return fail("OCCUPIED", "泊位被原人船或已承諾預約占用")
	var next: Variant = data.site.get("next_vehicle", 1)
	if not _building_integer(next, 1, 2147483646) or data.site.get("vehicles", {}).has(str(int(next))):
		return fail("INVALID", "載具序號不可用")
	return ok("可下水", {"identity": str(int(next)), "cell": int(feature.launch_cell), "facing": facing})

static func begin_ship_build(data: TerrainData, key: String, ship_type: String, team_id: int, requester_faction: int = -1, occupied: Callable = Callable(), preview: bool = false) -> Dictionary:
	if _ship_runtime_pending(data): return fail("BUSY", "原固定目標仍待補算或交接；暫不能接受新設施操作")
	if not _siege_depot_ready(data) or not Ships.is_kind(ship_type) or team_id <= 0: return fail("INVALID")
	var feature: Dictionary = data.site.get("features", {}).get(key, {})
	if str(feature.get("kind", "")) != "shipyard": return fail("NO_TARGET")
	if requester_faction < 0 or int(feature.get("owner_faction", -1)) != requester_faction: return fail("NO_AUTHORITY")
	if bool(data.site.get("paused", false)) or str(feature.stage) != "complete" or feature.has("pending_build") or feature.has("repair") or feature.has("ship_build") or bool(feature.batch_paid) or float(feature.production) != 0.0: return fail("BUSY")
	var cost: Dictionary = Ships.build_cost(ship_type)
	var work := Ships.build_work_seconds(ship_type)
	if cost.is_empty() or not is_finite(work) or work <= 0.0: return fail("INVALID")
	if not can_pay(data.site.inventory, cost) or not can_pay(data.site.inventory, {"tools": 1}): return fail("MATERIALS", items_text(cost))
	var launch := _ship_launch_query(data, feature, ship_type, occupied)
	if not launch.ok: return launch
	if preview: return ok("可投入造船", {"cost": cost.duplicate(), "work_seconds": work})
	add_items(data.site.inventory, cost, -1)
	data.site.depot_items.version = int(data.site.depot_items.version) + 1
	feature.ship_build = {"version": 1, "recipe_version": 1, "ship_type": ship_type, "team_id": team_id, "paid_cost": cost.duplicate(), "total_work": work}
	feature.production = 0.0
	feature.batch_paid = true
	feature.status = "已付原料，等待原工人造船"
	_enable_ship_zone(data, key)
	return ok("已投入原料並排入造船", {"feature": key})

static func _enable_ship_zone(data: TerrainData, key: String) -> void:
	for zone: Dictionary in data.site.zones:
		if str(zone.get("feature", "")) == key and str(zone.get("action", "")) == "operate":
			zone.active = true
			return
	data.site.zones.append({"cells": data.site.features[key].cells.duplicate(), "kind": -1, "action": "operate", "feature": key, "active": true})

static func cancel_ship_build(data: TerrainData, key: String, requester_faction: int = -1, preview: bool = false) -> Dictionary:
	if _ship_runtime_pending(data): return fail("BUSY", "原固定目標仍待補算或交接；暫不能接受新設施操作")
	if not _siege_depot_ready(data): return fail("INVALID")
	var feature: Dictionary = data.site.get("features", {}).get(key, {})
	if not feature.has("ship_build"): return fail("NO_TARGET")
	if requester_faction < 0 or int(feature.get("owner_faction", -1)) != requester_faction: return fail("NO_AUTHORITY")
	if bool(data.site.get("paused", false)): return fail("BUSY")
	var checked := validate_ship_build(data, feature)
	if not checked.ok: return checked
	var job: Dictionary = feature.ship_build
	var refund := {}
	var unused := maxf(0.0, 1.0 - float(feature.production) * 60.0 / float(job.total_work))
	for resource: String in job.paid_cost: refund[resource] = floori(float(job.paid_cost[resource]) * unused)
	if not _depot_can_receive(data, refund): return fail("STORAGE_FULL")
	if preview: return ok("可取消造船", {"refund": refund})
	add_items(data.site.inventory, refund)
	data.site.depot_items.version = int(data.site.depot_items.version) + 1
	_finish_ship_build(data, key, feature, "已取消造船並退回未使用原料")
	return ok(str(feature.status), {"refund": refund})

static func _finish_ship_build(data: TerrainData, key: String, feature: Dictionary, status: String) -> void:
	feature.erase("ship_build")
	feature.production = 0.0
	feature.batch_paid = false
	feature.status = status
	_stop_feature_zones(data, key, "operate")
	var worker: Dictionary = data.site.get("worker", {})
	if str(worker.get("target", "")) == "feature:" + key:
		worker.target = ""
		worker.mode = "idle"
	if data.has_meta(&"site_work_team"):
		var ref_value: Variant = data.get_meta(&"site_work_team")
		if ref_value is WeakRef:
			var workers: Variant = ref_value.get_ref()
			if workers != null: workers.refresh_ship_tasks()
	data.environment_revision += 1

static func _launch_ship_build(data: TerrainData, key: String, feature: Dictionary, occupied: Callable) -> Dictionary:
	var checked := validate_ship_build(data, feature)
	if not checked.ok: return checked
	if not feature.has("ship_build") or float(feature.production) * 60.0 + 0.00000001 < float(feature.ship_build.total_work): return fail("BUSY")
	var job: Dictionary = feature.ship_build
	var launch := _ship_launch_query(data, feature, str(job.ship_type), occupied)
	if not launch.ok:
		feature.status = "造船已完成，等待下水：" + str(launch.message)
		return launch
	var record: Dictionary = Ships.make_record(str(launch.identity), int(job.team_id), str(job.ship_type), int(launch.cell), launch.facing)
	if record.is_empty(): return fail("INVALID")
	var technology_completed := prepare_technology_geometry_completion(data, feature, "feature:" + key, "vehicle:" + str(launch.identity))
	if not technology_completed.ok: return technology_completed
	if not data.site.has("vehicles"): data.site.vehicles = {}
	data.site.vehicles[str(launch.identity)] = record
	data.site.next_vehicle = int(launch.identity) + 1
	publish_technology_geometry_completion(technology_completed)
	_finish_ship_build(data, key, feature, "已完成下水")
	return ok("原船已下水", {"vehicle_id": str(launch.identity)})

static func advance_ship_builds(data: TerrainData, occupied: Callable = Callable()) -> void:
	if data == null or bool(data.site.get("paused", false)): return
	var keys: Array = data.site.get("features", {}).keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for key: String in keys:
		var feature: Dictionary = data.site.features[key]
		if feature.has("ship_build") and float(feature.get("production", 0.0)) * 60.0 + 0.00000001 >= float(feature.ship_build.get("total_work", INF)):
			_launch_ship_build(data, key, feature, occupied)

static func _ship_feature_work(data: TerrainData, key: String, feature: Dictionary, worker: Dictionary, minutes: float, occupied: Callable, work_time: Callable, original_identity: int = 0) -> void:
	var checked := validate_ship_build(data, feature)
	if not checked.ok or not feature.has("ship_build"):
		worker.target = ""
		worker.mode = "idle"
		return
	var total_minutes := float(feature.ship_build.total_work) / 60.0
	if float(feature.production) + 0.00000001 >= total_minutes:
		_launch_ship_build(data, key, feature, occupied)
		worker.status = str(feature.status)
		return
	if not can_pay(data.site.inventory, {"tools": 1}):
		worker.status = "缺少造船工具"
		return
	var technology_guard := technology_geometry_operator_guard(data, feature, worker, original_identity)
	if not technology_guard.ok:
		worker.status = str(technology_guard.message)
		return
	minutes = minf(minutes, total_minutes - float(feature.production))
	if work_time.is_valid(): minutes = float(work_time.call(false, minutes))
	technology_record_work(feature, minutes, int(technology_guard.get("operator_id", 0)))
	feature.production = minf(total_minutes, float(feature.production) + minutes)
	feature.status = "造船 %.1f / %.1f 分" % [float(feature.production), total_minutes]
	worker.status = str(feature.status)
	if float(feature.production) + 0.00000001 >= total_minutes: _launch_ship_build(data, key, feature, occupied)


static func build_work(kind: String, cell_count: int) -> float:
	return float(FEATURES[kind].work) * (cell_count if kind.contains("farm") or kind in MILITARY_KINDS + ["road", "level", "palisade", "stone_wall", "fighting_position"] else 1)

static func water_demand(feature: Dictionary) -> float:
	var kind := str(feature.kind)
	if not feature_usable(feature): return 0.0
	var recipe_water := float(feature_recipe(feature).get("water", 0.0))
	if int(feature.get("layout_version", 0)) == 0:
		return recipe_water * (feature.cells.size() if kind in FARM_KINDS else 1)
	var spec := building_spec(kind, _feature_options(feature))
	if kind in FARM_KINDS:
		return recipe_water * mini(feature.cells.size(), FARM_WORK_SIDE * FARM_WORK_SIDE)
	return recipe_water * building_productivity(feature) if FEATURES[kind].has("cycle") else float(spec.water)

static func cancel_feature(data: TerrainData, key: String, occupied: Callable = Callable(), requester_faction: int = -1) -> Dictionary:
	if _ship_runtime_pending(data): return fail("BUSY", "原固定目標仍待補算或交接；暫不能接受新設施操作")
	if not data.site.features.has(key):
		return fail("NO_TARGET")
	var feature: Dictionary = data.site.features[key]
	if int(feature.get("owner_faction", -1)) >= 0 and requester_faction != int(feature.owner_faction):
		return fail("NO_AUTHORITY", "只有建築管理方可取消／拆除")
	if str(feature.kind) == "siege_ladder" and not str(feature.get("ladder", {}).get("pending", "")).is_empty(): return fail("BUSY", "先收束兩人架梯／收梯")
	if ship_repair_uses_feature(data, key): return fail("BUSY", "先結束本設施原船體修理作業")
	if str(feature.kind) == "tent":
		return fail("INVALID", "營帳須由後勤人物收納，不能拆除吞掉營帳包")
	if str(feature.kind) == "settlement_center" and str(feature.stage) == "complete" and not feature.has("pending_build") and not feature.has("repair"):
		return fail("INVALID", "已建制聚落的中心不能拆除；受損只會停效")
	if bool(feature.get("batch_paid", false)) or float(feature.get("production", 0.0)) > 0.0:
		return fail("BUSY", "已付批次或待領貨須先完成，不能拆除吞掉物資")
	if _prison_in_use(data, key):
		return fail("BUSY", "仍有原囚犯或在途入監作業")
	if str(feature.kind) == "barracks" and _barracks_in_use(data, key) and not feature.has("pending_build"):
		return fail("BUSY", "軍營仍有原駐營人物，須先出營")
	if _housing_in_use(data, key) and not feature.has("pending_build") and not feature.has("repair"):
		return fail("BUSY", "住宅仍有原住戶登記，須先明確離住")
	if feature.has("pending_build") or feature.has("repair"):
		var field := "pending_build" if feature.has("pending_build") else "repair"
		var job: Dictionary = feature[field]
		var candidate: Dictionary = feature.duplicate(true)
		candidate.erase(field)
		var water_guard: Dictionary = _ship_water_geometry_guard(data, key, candidate)
		if not water_guard.ok: return water_guard
		var unused := clampf(1.0 - float(job.progress) / float(job.work), 0.0, 1.0)
		var refund_job := {}
		for item: String in job.cost:
			refund_job[item] = floori(int(job.cost[item]) * unused)
		if not _depot_can_receive(data, refund_job):
			return fail("STORAGE_FULL")
		add_items(data.site.inventory, refund_job)
		feature.erase(field)
		if field == "repair": data.site.get("fire", {}).get("repair_generations", {}).erase(_fire_unit_key("feature", key, str(job.part)))
		if job.has("target_grade") or job.has("target_level"): feature.status = "已取消升級，原建物與已使用材料保留"
		_stop_feature_zones(data, key, "construct" if field == "pending_build" else "repair")
		Env.rebuild_indexes(data)
		if Env.ecology_active(data): ecology_reconcile(data)
		rebuild_water(data)
		return ok("已取消未完成作業，原建築與已使用材料保留")
	var stock: Dictionary = data.site.get("stockpiles", {}).get(key, {})
	if not stock.is_empty() and (inventory_size(stock.get("cargo", {})) != 0 or not stock.get("holder", {}).get("item_ids", []).is_empty()):
		return fail("BUSY", "先沿原裝卸入口取出設施全部原物資")
	if _fire_feature_hot(data, key): return fail("BUSY", "原建物仍熱；不能拆除丟失剩餘火勢與燃料")
	var guard := structure_change_guard(data, key, {}, occupied, "remove")
	if not guard.ok:
		return guard
	var refund := {}
	if str(feature.stage) != "complete":
		var fraction := clampf(1.0 - float(feature.progress) / float(feature.work), 0.0, 1.0)
		for item: String in feature.cost:
			refund[item] = floori(int(feature.cost[item]) * fraction)
	# The breeding stock remains live property, including during construction.
	if feature.has("species"):
		refund[str(feature.species)] = int(feature.residents)
	if not _depot_can_receive(data, refund):
		return fail("STORAGE_FULL")
	add_items(data.site.inventory, refund)
	if is_training_facility(feature):
		for supply: Dictionary in data.site.get("team_supply", {}).values():
			if str(supply.get("training_feature_id", "")) == key:
				supply.training_order = false
				supply.training_requester = -1
				supply.training_feature_id = ""
	data.site.features.erase(key)
	if str(feature.kind) == "settlement_center" and str(data.site.get("settlement", {}).get("center_id", "")) == key: data.site.erase("settlement")
	_fire_feature_removed(data, key)
	data.site.get("stockpiles", {}).erase(key)
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
	if Env.ecology_active(data): ecology_reconcile(data)
	rebuild_water(data)
	return ok("已拆除／取消；已採集與整地的結果保留")

static func _depot_can_receive(data: TerrainData, added: Dictionary) -> bool:
	return carried_load(data.site, data.site.inventory, data.site.get("depot_items", new_item_state("depot"))) + inventory_size(added) <= float(data.site.capacity)

static func _stop_feature_zones(data: TerrainData, key: String, action: String = "") -> void:
	for zone: Dictionary in data.site.zones:
		if str(zone.get("feature", "")) == key and (action.is_empty() or str(zone.action) == action):
			zone.active = false
	for worker: Dictionary in [data.site.worker, data.site.manual]:
		if str(worker.get("target", "")) == "feature:" + key and (action.is_empty() or str(worker.get("action", "")) == action):
			worker.target = ""
			worker.mode = "idle"
			worker.progress = 0.0

static func _prison_in_use(data: TerrainData, key: String) -> bool:
	for relation: Dictionary in data.site.get("captivity", {}).values():
		if str(relation.get("prison_id", "")) == key:
			return true
	for order: Dictionary in data.site.get("escort_orders", {}).values():
		if str(order.get("prison_id", "")) == key:
			return true
	return false

static func _feature_has_work(data: TerrainData, key: String) -> bool:
	for worker: Dictionary in [data.site.worker, data.site.manual]:
		if str(worker.get("target", "")) == "feature:" + key:
			return true
	if data.has_meta(&"site_work_team"):
		var ref_value: WeakRef = data.get_meta(&"site_work_team")
		var team: Variant = ref_value.get_ref()
		if team != null and team.feature_in_use(key):
			return true
	return false

static func _barracks_in_use(data: TerrainData, key: String) -> bool:
	if data.has_meta(&"site_garrison_lab"):
		var ref_value: Variant = data.get_meta(&"site_garrison_lab")
		if not ref_value is WeakRef: return true
		var lab: Variant = ref_value.get_ref()
		if lab == null or lab.terrain != data: return true
		if lab != null:
			if lab.get("crowd_site") != null and lab.crowd_site.active:
				for roster: Dictionary in lab.crowd_site.rosters:
					if str(roster.get("garrison_feature_id", "")) == key and (not roster.get("units", []).is_empty() or not roster.get("player_member", {}).is_empty()):
						return true
			for army: TerrainArmy in lab.combat_armies:
				if army.garrison_feature_id == key and (not army.combat_units.is_empty() or is_instance_valid(army.player_member)):
					return true
			return false
	for army: Dictionary in data.site.get("armies", []):
		if str(army.get("garrison_feature_id", "")) == key and (not army.get("units", []).is_empty() or not army.get("player_member", {}).is_empty()):
			return true
	return false

static func preview_resize(data: TerrainData, key: String, new_cells: Array[int], occupied: Callable = Callable()) -> Dictionary:
	if _ship_runtime_pending(data): return fail("BUSY", "原固定目標仍待補算或交接；暫不能接受新設施操作")
	var feature: Dictionary = data.site.get("features", {}).get(key, {})
	if feature.is_empty() or int(feature.get("layout_version", 0)) != BUILDING_LAYOUT_VERSION:
		return fail("NO_TARGET", "舊布局保留原樣；僅新版設施可改界")
	var kind := str(feature.kind)
	if _fire_feature_hot(data, key): return fail("BUSY", "原部件仍熱；改界保留原火勢與有限燃料")
	if int(feature.get("fire_layout_version", 0)) == FIRE_LAYOUT_VERSION:
		for original: Dictionary in feature.parts.values():
			if float(original.hp) <= 0.0: return fail("BUSY", "先沿原付費修理補回倒塌部件，再改界")
	if kind not in FARM_KINDS + PASTURE_KINDS + MILITARY_KINDS + ["palisade", "stone_wall", "prison"] or str(feature.stage) != "complete":
		return fail("INVALID", "此種類或施工狀態不能改界")
	if feature.has("pending_build") or feature.has("repair") or bool(feature.batch_paid) or float(feature.production) > 0.0 or _feature_has_work(data, key):
		return fail("BUSY", "先完成已付批次、交貨與在途工作")
	if kind == "barracks" and int(feature.get("barracks_layout_version", 1)) == BARRACKS_LAYOUT_VERSION and _barracks_in_use(data, key):
		return fail("BUSY", "尚有人員登記，無法調整密集軍營布局")
	if is_training_facility(feature):
		for supply: Dictionary in data.site.get("team_supply", {}).values():
			if bool(supply.get("training_order", false)) and str(supply.get("training_feature_id", "")) == key:
				return fail("BUSY", "須先停止此設施的訓練命令再改界")
	if _prison_in_use(data, key):
		return fail("BUSY", "先完成在途押送或解放原囚犯")
	for zone: Dictionary in data.site.zones:
		if str(zone.get("feature", "")) == key and str(zone.action) == "operate" and bool(zone.active):
			return fail("BUSY", "先停用此設施運作工作區")
	var preview := _preview_build(data, kind, new_cells, occupied, _feature_options(feature), key)
	if not preview.ok:
		return preview
	if int(preview.level) != int(feature.level):
		return fail("TERRAIN", "改界不能改變原地基高度")
	var added: Array[int] = []
	var removed: Array[int] = []
	for index: int in new_cells:
		if not feature.cells.has(index):
			added.append(index)
	for index: int in feature.cells:
		if not new_cells.has(index):
			removed.append(index)
	if added.is_empty() and removed.is_empty():
		return fail("INVALID", "占地沒有變化")
	if not added.is_empty() and not removed.is_empty():
		return fail("INVALID", "一次只擴大或縮小，不能搬移原建築")
	if kind == "barracks" and not removed.is_empty() and _barracks_in_use(data, key):
		return fail("BUSY", "軍營仍有原駐營人物，不能縮小占地")
	if kind in PASTURE_KINDS and grazing_capacity(data, new_cells) < int(feature.residents):
		return fail("CAPACITY", "縮地不能丟失原種畜")
	var current_cost := _building_cost(data, kind, feature.cells, _feature_options(feature))
	var cost := {}
	var refund := {}
	for item: String in preview.cost:
		if item in ["sheep", "horse"]:
			continue # Existing residents are never charged or refunded by land size.
		var difference := int(preview.cost[item]) - int(current_cost.get(item, 0))
		if difference > 0:
			cost[item] = difference
		# Finished construction has already consumed these materials, just like
		# completed demolition. Shrinking a ruined part cannot fund a new one.
	if not can_pay(data.site.inventory, cost) or not can_pay(data.site.inventory, {"tools": 1}):
		return fail("MATERIALS", items_text(cost))
	if not _depot_can_receive(data, refund):
		return fail("STORAGE_FULL")
	var candidate := feature.duplicate(true)
	candidate.cells = new_cells.duplicate()
	candidate.entrance = int(preview.entrance)
	if candidate.has("parts"):
		for part: String in candidate.parts.keys():
			if part.begins_with("c:") and not new_cells.has(int(part.trim_prefix("c:"))):
				candidate.parts.erase(part)
	var guard := structure_change_guard(data, key, candidate, occupied, "resize")
	if not guard.ok:
		return guard
	var work := maxf(0.0, _building_work(data, kind, new_cells, _feature_options(feature)) - _building_work(data, kind, feature.cells, _feature_options(feature)))
	preview.merge({"cost": cost, "refund": refund, "added_cells": added, "removed_cells": removed,
		"work": maxf(0.5, work) if not added.is_empty() else 0.0, "candidate": candidate}, true)
	return preview

static func request_resize(data: TerrainData, key: String, new_cells: Array[int], occupied: Callable = Callable(), requester_faction: int = -1) -> Dictionary:
	var preview := preview_resize(data, key, new_cells, occupied)
	if not preview.ok:
		return preview
	var feature: Dictionary = data.site.features[key]
	if int(feature.get("owner_faction", -1)) >= 0 and requester_faction != int(feature.owner_faction):
		return fail("NO_AUTHORITY")
	if not preview.added_cells.is_empty():
		add_items(data.site.inventory, preview.cost, -1)
		feature["pending_build"] = {"cells": new_cells.duplicate(), "added_cells": preview.added_cells,
			"cost": preview.cost, "clearing": preview.clearing, "entrance": int(preview.entrance), "work": float(preview.work), "progress": 0.0}
		data.site.zones.append({"cells": preview.added_cells.duplicate(), "kind": -1, "action": "construct", "feature": key, "active": true})
		feature.status = "擴建中；原範圍仍可使用"
	else:
		add_items(data.site.inventory, preview.refund)
		feature.cells = new_cells.duplicate()
		feature.entrance = int(preview.entrance)
		if feature.has("parts"):
			feature.parts = preview.candidate.parts
			_fire_feature_removed(data, key, feature.parts)
		for zone: Dictionary in data.site.zones:
			if str(zone.get("feature", "")) == key:
				zone.cells = new_cells.duplicate()
		feature.status = "已縮小；原人物、畜種與物資保留"
	Env.rebuild_indexes(data)
	if Env.ecology_active(data): ecology_reconcile(data)
	rebuild_water(data)
	return ok(str(feature.status), {"feature": key, "added_cells": preview.added_cells, "removed_cells": preview.removed_cells})

static func request_repair(data: TerrainData, key: String, part_id: String, requester_faction: int, occupied: Callable = Callable()) -> Dictionary:
	if _ship_runtime_pending(data): return fail("BUSY", "原固定目標仍待補算或交接；暫不能接受新設施操作")
	var feature: Dictionary = data.site.get("features", {}).get(key, {})
	if str(feature.get("stage", "")) != "complete" or int(feature.get("layout_version", 0)) != BUILDING_LAYOUT_VERSION or not feature.get("parts", {}).has(part_id):
		return fail("NO_TARGET", "可修理的原部件不存在")
	if int(feature.get("owner_faction", -1)) < 0 or requester_faction != int(feature.owner_faction):
		return fail("NO_AUTHORITY")
	if feature.has("repair") or feature.has("pending_build") or _feature_has_work(data, key) or not str(feature.get("gate", {}).get("pending", "")).is_empty():
		return fail("BUSY")
	var geometry := feature_geometry(data, feature)
	var part: Dictionary = geometry.parts[part_id]
	var fire_guard := _fire_repair_guard(data, key, part_id)
	if not fire_guard.ok: return fire_guard
	var amount := float(part.max_hp) - float(part.hp)
	if amount <= 0.0:
		return fail("INVALID", "部件耐久完整")
	if str(part.role) == "roof" and float(feature.parts.body.hp) <= 0.0: return fail("BUSY", "先修復支撐屋頂的原本體")
	if str(part.role) == "leaf" and float(part.hp) <= 0.0 and not bool(feature.gate.open):
		return fail("BUSY", "請原操作者先開門，再安裝新門扇；修復後仍須正常關門")
	if str(part.role) == "leaf" and float(feature.parts[part_id.replace("leaf:", "frame:")].hp) <= 0.0:
		return fail("BUSY", "先修复承托這片門扇的原門框")
	var work_cell := -1
	for index: int in part.cells:
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var cell := data.cell_from_index(index) + direction
			if _repair_contact(data, feature, part, cell) and (not occupied.is_valid() or not bool(occupied.call(cell))):
				work_cell = data.index(cell)
				break
		if work_cell >= 0:
			break
	if work_cell < 0:
		return fail("UNREACHABLE", "部件旁沒有安全修理位置")
	var candidate: Dictionary = feature.duplicate(true)
	candidate.parts[part_id].hp = float(part.max_hp)
	var water_guard: Dictionary = _ship_water_geometry_guard(data, key, candidate)
	if not water_guard.ok: return water_guard
	var terms := _repair_terms(feature, part, amount)
	var cost: Dictionary = terms.cost
	if not can_pay(data.site.inventory, cost) or not can_pay(data.site.inventory, {"tools": 1}):
		return fail("MATERIALS", items_text(cost))
	add_items(data.site.inventory, cost, -1)
	feature["repair"] = {"part": part_id, "amount": amount, "cost": cost,
		"work": float(terms.work), "progress": 0.0, "work_cell": work_cell}
	_fire_repair_started(data, key, part_id)
	data.site.zones.append({"cells": feature.cells.duplicate(), "kind": -1, "action": "repair", "feature": key, "active": true})
	feature.status = "已備料，等待原工作者修理"
	return ok(str(feature.status), {"feature": key, "part": part_id})

static func _repair_terms(feature: Dictionary, part: Dictionary, amount: float) -> Dictionary:
	if int(feature.get("fire_layout_version", 0)) == FIRE_LAYOUT_VERSION:
		var cost := {}
		for resource: String in part.get("investment", {}):
			var invested := int(part.investment[resource])
			if invested > 0: cost[resource] = maxi(1, ceili(invested * 0.25 * amount / float(part.max_hp)))
		return {"cost": cost, "work": maxf(1.0, float(feature.work) * float(part.work_share) * 0.25 * amount / float(part.max_hp))}
	if str(part.role) == "building":
		var cost := {}
		for item: String in feature.cost:
			if int(feature.cost[item]) > 0: cost[item] = maxi(1, ceili(float(feature.cost[item]) * 0.25 * amount / float(part.max_hp)))
		return {"cost": cost, "work": maxf(1.0, float(feature.work) * 0.25 * amount / float(part.max_hp))}
	var material := "wood" if str(part.role) == "leaf" else str(feature.material)
	return {"cost": {material: maxi(1, ceili(amount / float(part.max_hp) * (6.0 if material == "stone" else 4.0)))},
		"work": maxf(1.0, amount / float(part.max_hp) * (12.0 if material == "stone" else 6.0))}

static func _repair_contact(data: TerrainData, feature: Dictionary, part: Dictionary, cell: Vector2i) -> bool:
	if not data.is_walkable(cell) or part.cells.has(data.index(cell)):
		return false
	var height := int(data.navigation_heights()[data.index(cell)])
	if height < int(feature.level) or height > maxi(int(feature.level), int(part.height)):
		return false
	for index: int in part.cells:
		var offset := data.cell_from_index(index) - cell
		if absi(offset.x) + absi(offset.y) == 1:
			return true
	return false

static func _gate_operator(data: TerrainData, feature: Dictionary, identity: int, person_query: Callable) -> Dictionary:
	if identity < 1 or not person_query.is_valid():
		return fail("NO_AUTHORITY")
	var person: Variant = person_query.call(identity)
	if not person is Dictionary or person.is_empty() or not person.get("cell") is Vector2i or float(person.get("hp", 0.0)) <= 0.0 or float(person.get("ko", 0.0)) > 0.0 or bool(person.get("captive", false)) or bool(person.get("moving", false)) or not bool(person.get("ready", true)):
		return fail("BUSY", "操作者須清醒、停止並可行動")
	if int(feature.get("owner_faction", -1)) < 0 or int(person.get("faction", person.get("faction_id", -1))) != int(feature.owner_faction):
		return fail("NO_AUTHORITY", "只有城門管理方可操作")
	if not feature_geometry(data, feature).operation.has(data.index(person.cell)):
		return fail("UNREACHABLE", "請本人到門內操作位置")
	return ok()

static func _gate_occupied(data: TerrainData, feature: Dictionary, occupied: Callable) -> bool:
	if not occupied.is_valid():
		return false
	var geometry := feature_geometry(data, feature)
	for index: int in feature.cells:
		var frame: bool = geometry.parts["frame:left"].cells.has(index) or geometry.parts["frame:right"].cells.has(index)
		if not frame and bool(occupied.call(data.cell_from_index(index))):
			return true
	return false

static func request_gate(data: TerrainData, key: String, want_open: bool, operator_id: int, person_query: Callable, occupied: Callable = Callable()) -> Dictionary:
	if _ship_runtime_pending(data): return fail("BUSY", "原固定目標仍待補算或交接；暫不能接受新設施操作")
	var feature: Dictionary = data.site.get("features", {}).get(key, {})
	if str(feature.get("kind", "")) != "gate" or str(feature.get("stage", "")) != "complete" or not feature.get("gate") is Dictionary:
		return fail("NO_TARGET")
	var ready := _gate_operator(data, feature, operator_id, person_query)
	if not ready.ok:
		return ready
	if not str(feature.gate.pending).is_empty() or feature.has("repair"):
		return fail("BUSY")
	if bool(feature.gate.open) == want_open:
		return fail("INVALID", "門已在此位置")
	if not want_open and (float(feature.parts["leaf:left"].hp) <= 0.0 or float(feature.parts["leaf:right"].hp) <= 0.0 or float(feature.parts["frame:left"].hp) <= 0.0 or float(feature.parts["frame:right"].hp) <= 0.0):
		return fail("INVALID", "門扇已破壞，須先修復")
	if _gate_occupied(data, feature, occupied):
		return fail("WAIT_OCCUPANCY")
	var candidate := feature.duplicate(true)
	candidate.gate.open = want_open
	var guard := structure_change_guard(data, key, candidate, occupied, "gate")
	if not guard.ok:
		return guard
	feature.gate.pending = "open" if want_open else "close"
	feature.gate.progress = 0.0
	feature.gate.operator_id = operator_id
	Env.rebuild_indexes(data)
	return ok("本人開始開門" if want_open else "本人開始關門；通道已清空")

static func _clear_gate_operation(feature: Dictionary) -> void:
	feature.gate.pending = ""
	feature.gate.progress = 0.0
	feature.gate.operator_id = -1

static func advance_gate_operations(data: TerrainData, seconds: float, person_query: Callable, occupied: Callable = Callable()) -> void:
	var point_consumer: Variant = data.get_meta(&"region_point_consuming", Callable())
	var consuming: bool = point_consumer is Callable and point_consumer.is_valid() and bool(point_consumer.call())
	if seconds < 0.0 or seconds == 0.0 and not consuming or not is_finite(seconds) or bool(data.site.get("paused", false)):
		return
	for key: String in data.site.features:
		var feature: Dictionary = data.site.features[key]
		if str(feature.get("gate", {}).get("pending", "")).is_empty():
			continue
		var check := _gate_operator(data, feature, int(feature.gate.operator_id), person_query)
		if not check.ok or _gate_occupied(data, feature, occupied):
			_clear_gate_operation(feature)
			feature.status = str(check.message) if not check.ok else "通道重新占用，已取消門操作"
			Env.rebuild_indexes(data)
			continue
		feature.gate.progress = minf(GATE_SECONDS, float(feature.gate.progress) + seconds)
		if float(feature.gate.progress) + 0.000000001 < GATE_SECONDS:
			continue
		var point_guard: Variant = data.get_meta(&"region_point_deferring", Callable())
		if point_guard is Callable and point_guard.is_valid() and bool(point_guard.call()): continue
		var candidate := feature.duplicate(true)
		candidate.gate.open = str(feature.gate.pending) == "open"
		_clear_gate_operation(candidate)
		var guard := structure_change_guard(data, key, candidate, occupied, "gate")
		if not guard.ok:
			_clear_gate_operation(feature)
			feature.status = str(guard.message)
		else:
			feature.gate = candidate.gate
			feature.status = "已開門" if bool(feature.gate.open) else "已關門"
		Env.rebuild_indexes(data)
		rebuild_water(data)

# Combat owns legality, timing and hit identity. This only commits the original
# feature's HP and returns lost surfaces for the caller's same-step body response.
static func damage_structure_part(data: TerrainData, key: String, part_id: String, damage: float) -> Dictionary:
	var feature: Dictionary = data.site.get("features", {}).get(key, {})
	if str(feature.get("stage", "")) != "complete" or not feature.get("parts", {}).has(part_id) or not is_finite(damage) or damage <= 0.0:
		return fail("NO_TARGET")
	var old_hp := float(feature.parts[part_id].hp)
	if old_hp <= 0.0:
		return fail("NO_TARGET", "原部件已毀壞")
	var geometry := feature_geometry(data, feature)
	var part: Dictionary = geometry.parts[part_id]
	var new_hp := maxf(0.0, old_hp - damage)
	if new_hp <= 0.0:
		var candidate: Dictionary = feature.duplicate(true)
		candidate.parts[part_id].hp = new_hp
		for supported: String in _fire_supported_parts(feature, part_id): candidate.parts[supported].hp = 0.0
		if candidate.has("gate"): _clear_gate_operation(candidate)
		var water_guard: Dictionary = _ship_water_geometry_guard(data, key, candidate)
		if not water_guard.ok: return water_guard
	var lost := {}
	var affected: Array = part.cells.duplicate()
	var consequential: Array[String] = []
	if new_hp <= 0.0:
		for index: int in part.cells:
			if geometry.heights.has(index):
				lost[index] = int(geometry.heights[index])
	# The original waterfront is still valid throughout every preflight.
	# All its ship receipts commit together before its body is destroyed.
	if new_hp <= 0.0 and str(feature.get("kind", "")) in WATERFRONT_KINDS:
		var repair_result: Dictionary = _settle_ship_repair_feature_damage(data, key)
		if not repair_result.ok: return repair_result
	feature.parts[part_id].hp = new_hp
	if new_hp <= 0.0 and str(feature.get("kind", "")) == "siege_ladder": cancel_siege_ladder_action(data, key)
	if new_hp <= 0.0:
		for supported: String in _fire_supported_parts(feature, part_id):
			if float(feature.parts[supported].hp) <= 0.0: continue
			feature.parts[supported].hp = 0.0
			consequential.append(supported)
			affected.append_array(geometry.parts[supported].cells)
	if new_hp <= 0.0 and feature.has("gate"):
		_clear_gate_operation(feature)
	feature.status = "部件毀壞" if new_hp <= 0.0 else "部件受損"
	if new_hp <= 0.0:
		Env.rebuild_indexes(data)
		rebuild_water(data)
	else:
		data.environment_revision += 1
	return ok(str(feature.status), {"feature": key, "part": part_id, "old_hp": old_hp, "new_hp": new_hp,
		"affected_cells": affected, "consequential_parts": consequential, "lost_surfaces": lost})

static func operate_feature(data: TerrainData, key: String) -> Dictionary:
	if _ship_runtime_pending(data): return fail("BUSY", "原固定目標仍待補算或交接；暫不能接受新設施操作")
	if not data.site.features.has(key):
		return fail("NO_TARGET")
	var feature: Dictionary = data.site.features[key]
	if not feature_usable(feature): return fail("BUSY", "建物已毀壞，先修復")
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

static func livestock_capacity(data: TerrainData, feature: Dictionary) -> int:
	var capacity := grazing_capacity(data, feature.cells)
	return capacity if int(feature.get("layout_version", 0)) == BUILDING_LAYOUT_VERSION else mini(LEGACY_LIVESTOCK_LIMIT, capacity)

# Original carried livestock enters the existing resident count in one commit.
static func stock_pasture(data: TerrainData, feature_key: String, cargo: Dictionary, actor_cell: Vector2i) -> Dictionary:
	if data == null or not data.site.get("features", {}).has(feature_key):
		return fail("NO_TARGET")
	var feature: Dictionary = data.site.features[feature_key]
	var kind := str(feature.get("kind", ""))
	var species := "horse" if kind == "horse_ranch" else "sheep"
	if kind not in ["pasture", "horse_ranch"] or str(feature.get("stage", "")) != "complete" or str(feature.get("species", "")) != species:
		return fail("INVALID", "需已完成且畜種相符的牧場")
	var minimum := 0 if int(feature.get("layout_version", 0)) == BUILDING_LAYOUT_VERSION else 1
	var capacity := livestock_capacity(data, feature)
	if not _resource_stack(cargo) or not feature.get("residents") is int or int(feature.residents) < minimum or int(feature.residents) > capacity:
		return fail("INVALID", "攜帶牲畜／牧場居民資料")
	if bool(feature.get("batch_paid", false)) or float(feature.get("production", 0.0)) > 0.0 or feature.has("pending_build"):
		return fail("BUSY", "先完成原生產批次或擴建，再轉入種畜")
	var entrance := data.cell_from_index(int(feature.entrance))
	if not data.is_walkable(actor_cell) or not data.is_walkable(entrance) or (actor_cell != entrance and not data.can_step(actor_cell, entrance)):
		return fail("UNREACHABLE", "請帶牲畜到牧場入口旁")
	var held := int(cargo.get(species, 0))
	if held <= 0:
		return fail("MATERIALS", "身上沒有 " + str(Env.ITEM_NAMES[species]))
	var available := capacity - int(feature.residents)
	if available <= 0:
		return fail("STORAGE_FULL", "牧地承載已滿")
	var transferred := mini(held, available)
	# Cost and production batches remain the original construction/production record.
	cargo[species] = held - transferred
	if int(cargo[species]) == 0:
		cargo.erase(species)
	feature.residents = int(feature.residents) + transferred
	data.environment_revision += 1
	return ok("已送入" + str(FEATURES[kind].name) + "：" + items_text({species: transferred}), {"species": species, "transferred": transferred})

static func unstock_pasture(data: TerrainData, feature_key: String, cargo: Dictionary, actor_cell: Vector2i, count: int, carry_limit: int = CARRY_CAPACITY) -> Dictionary:
	var feature: Dictionary = data.site.get("features", {}).get(feature_key, {})
	if str(feature.get("kind", "")) not in PASTURE_KINDS or str(feature.get("stage", "")) != "complete" or not _resource_stack(cargo) or count < 1:
		return fail("INVALID", "已完成牧场和實際帶走數量")
	if bool(feature.get("batch_paid", false)) or float(feature.get("production", 0.0)) > 0.0 or feature.has("pending_build") or _feature_has_work(data, feature_key):
		return fail("BUSY", "先完成原批次、交貨與工作，再轉出種畜")
	var minimum := 0 if int(feature.get("layout_version", 0)) == BUILDING_LAYOUT_VERSION else (2 if str(feature.kind) == "horse_ranch" else 1)
	if int(feature.get("residents", 0)) - count < minimum:
		return fail("CAPACITY", "不能轉出不存在的牲畜或舊布局必要種畜")
	var entrance := data.cell_from_index(int(feature.entrance))
	if not data.is_walkable(actor_cell) or not data.is_walkable(entrance) or (actor_cell != entrance and not data.can_step(actor_cell, entrance)):
		return fail("UNREACHABLE", "請本人到牧場入口旁")
	if carry_limit < 0 or inventory_size(cargo) + count > carry_limit:
		return fail("STORAGE_FULL", "原人物的實際攜帶空間不足")
	var species := str(feature.species)
	feature.residents = int(feature.residents) - count
	cargo[species] = int(cargo.get(species, 0)) + count
	data.environment_revision += 1
	return ok("已從原牧場帶走 " + items_text({species: count}), {"species": species, "transferred": count})

static func _near_cells(data: TerrainData, cells: Array[int], target: int, distance: int) -> bool:
	for i: int in cells:
		var offset := data.cell_from_index(i) - data.cell_from_index(target)
		if absi(offset.x) + absi(offset.y) <= distance:
			return true
	return false

static func feature_work_slots(data: TerrainData, feature: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if int(feature.get("layout_version", 0)) != BUILDING_LAYOUT_VERSION or str(feature.kind) not in FARM_KINDS + PASTURE_KINDS:
		result.append({"slot": -1, "cell": int(feature.entrance), "service_cells": feature.cells.duplicate()})
		return result
	var bounds := _cell_bounds(data, feature.cells)
	for top: int in range(bounds.position.y, bounds.end.y, FARM_WORK_SIDE):
		for left: int in range(bounds.position.x, bounds.end.x, FARM_WORK_SIDE):
			var extent := Vector2i(mini(FARM_WORK_SIDE, bounds.end.x - left), mini(FARM_WORK_SIDE, bounds.end.y - top))
			var service: Array[int] = []
			for y: int in range(top, top + extent.y):
				for x: int in range(left, left + extent.x):
					service.append(data.index(Vector2i(x, y)))
			var cell := Vector2i(left + floori(float(extent.x - 1) / 2.0), top + floori(float(extent.y - 1) / 2.0))
			result.append({"slot": result.size(), "cell": data.index(cell), "service_cells": service})
	return result

static func work_claim_key(task: Dictionary) -> String:
	var target := str(task.get("target", ""))
	var slot := int(task.get("work_slot", -1))
	var shared_slots := target.begins_with("vehicle:") and str(task.get("action", "")) in ["construct", "repair"] \
		or target.begins_with("feature:") and str(task.get("action", "")) in ["operate", "ladder_deploy", "ladder_retract"]
	return "%s@%d" % [target, slot] if shared_slots and slot >= 0 else target

# A disposable projection of workers already at their original work positions.
# The worker owner replaces it each simulation slice; it is never in Site saves.
static func set_operating_slots(data: TerrainData, jobs: Array) -> void:
	var by_feature := {}
	var all_jobs := jobs.duplicate()
	var camp_task: Dictionary = data.get_meta(&"site_camp_operating_task", {})
	if not camp_task.is_empty() and not str(camp_task.get("target", "")).is_empty():
		all_jobs.append({"task": camp_task})
	for job: Dictionary in all_jobs:
		var task: Dictionary = job.task
		var key := str(task.target).trim_prefix("feature:")
		if not by_feature.has(key):
			by_feature[key] = {}
		by_feature[key][int(task.get("work_slot", -1))] = true
	if data.get_meta(&"site_operating_slots", {}) == by_feature and int(data.get_meta(&"site_operating_water_revision", -1)) == data.environment_revision:
		return
	data.set_meta(&"site_operating_slots", by_feature)
	allocate_water(data)
	data.set_meta(&"site_operating_water_revision", data.environment_revision)

static func _operating_slots(data: TerrainData, key: String, feature: Dictionary) -> Array[Dictionary]:
	var assigned: Dictionary = data.get_meta(&"site_operating_slots", {}).get(key, {})
	var result: Array[Dictionary] = []
	var slots := feature_work_slots(data, feature)
	for slot: Dictionary in slots:
		if assigned.has(int(slot.slot)):
			result.append(slot)
	return result

static func _pasture_scale(data: TerrainData, feature: Dictionary, service_count: int) -> float:
	var minimum := 16.0 if str(feature.kind) == "horse_ranch" else 9.0
	var stock_minimum := 2.0 if str(feature.kind) == "horse_ranch" else 1.0
	if int(feature.get("residents", 0)) < int(stock_minimum):
		return 0.0
	return minf(minf(float(feature.cells.size()) / minimum, float(feature.residents) / stock_minimum),
		minf(float(grazing_capacity(data, feature.cells)) / stock_minimum, float(service_count) / minimum))

static func feature_production_info(data: TerrainData, key: String) -> Dictionary:
	var feature: Dictionary = data.site.get("features", {}).get(key, {})
	if feature.is_empty():
		return {}
	var slots := _operating_slots(data, key, feature)
	var served := 0
	for slot: Dictionary in slots:
		served += slot.service_cells.size()
	var kind := str(feature.kind)
	var scale := float(served) if kind in FARM_KINDS else (_pasture_scale(data, feature, served) if kind in PASTURE_KINDS else 1.0)
	var output := {"land_cells": feature.cells.size(), "workers": slots.size(), "served_cells": served, "scale": scale,
		"residents": int(feature.get("residents", 0)), "grazing_capacity": grazing_capacity(data, feature.cells) if kind in PASTURE_KINDS else 0,
		"livestock_capacity": livestock_capacity(data, feature) if kind in PASTURE_KINDS else 0,
		"water_demand": float(FEATURES[kind].water) * scale}
	if kind in WATERFRONT_KINDS:
		output["launch_cell"] = int(feature.launch_cell)
		output["ship_build"] = feature.get("ship_build", {}).duplicate(true)
		output["work_seconds"] = float(feature.production) * 60.0
	return output

static func choose_task(data: TerrainData, from: Vector2i, occupied: Callable = Callable(), worker_override: Variant = null, cargo_override: Variant = null, excluded_targets: Dictionary = {}, worker_faction: int = -1) -> Dictionary:
	var worker: Dictionary = data.site.worker if worker_override == null else worker_override
	var cargo: Dictionary = worker.cargo if cargo_override == null else cargo_override
	if inventory_size(cargo) > 0:
		if excluded_targets.has("depot"):
			return fail("BUSY", "前一位搬運者正交庫，保留本人貨物等待")
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
		if str(zone.action) in ["construct", "operate", "repair"]:
			var key := str(zone.feature)
			if excluded_targets.has("feature:" + key):
				continue
			if not data.site.features.has(key):
				zone.active = false
				continue
			var feature: Dictionary = data.site.features[key]
			if int(feature.get("owner_faction", -1)) >= 0 and int(feature.owner_faction) != worker_faction:
				continue
			if not ecology_feature_work_guard(data, feature, str(zone.action)).ok:
				continue
			if str(zone.action) == "construct":
				if str(feature.stage) == "complete" and not feature.has("pending_build"):
					zone.active = false
					continue
				var clearing_pending := false
				for source_key: String in feature.get("pending_build", feature).clearing:
					if bool(Env.resource(data, source_key).get("cleared", true)):
						continue
					if not ecology_action_guard(data, source_key, "clear").ok:
						clearing_pending = true
						continue
					clearing_pending = true
					if excluded_targets.has(source_key):
						continue
					var clear_cell := _reachable_work(data, from, Env.work_cells(data, source_key), occupied)
					if clear_cell.x >= 0:
						return ok("施工前清理", {"target": source_key, "action": "clear", "cell": data.index(clear_cell), "zone": zone_index})
					return fail("UNREACHABLE", "施工前清理")
				if clearing_pending:
					continue # Another original worker still owns the uncleared source.
			elif str(zone.action) == "repair":
				if not feature.has("repair"):
					zone.active = false
					continue
			else:
				if str(feature.stage) != "complete" or feature.has("pending_build") or feature.has("repair"):
					continue
				if not feature_usable(feature) and not (bool(feature.batch_paid) and float(feature.production) >= float(feature_recipe(feature).get("cycle", INF))): continue
				var definition: Dictionary = feature_recipe(feature)
				if str(feature.kind) == "shipyard":
					if not feature.has("ship_build"): continue
				elif not definition.has("input"):
					continue
				if str(feature.kind) != "shipyard" and not bool(feature.batch_paid) and not can_pay(feature_input_inventory(data, feature, key), definition.input):
					feature.status = "缺投入：" + items_text(definition.input)
					continue
			var work_slots: Array[Dictionary] = []
			if str(zone.action) == "operate":
				work_slots = feature_work_slots(data, feature)
			else:
				work_slots.append({"slot": -1,
					"cell": int(feature.repair.work_cell) if str(zone.action) == "repair" else int(feature.get("pending_build", feature).entrance)})
			for slot: Dictionary in work_slots:
				var claim := {"target": "feature:" + key, "action": str(zone.action), "work_slot": int(slot.slot)}
				if excluded_targets.has(work_claim_key(claim)):
					continue
				var destination := _reachable_work(data, from, [data.cell_from_index(int(slot.cell))], occupied)
				if destination.x >= 0:
					return ok("前往" + str(FEATURES[str(feature.kind)].name), {"target": "feature:" + key,
						"action": str(zone.action), "cell": data.index(destination), "zone": zone_index, "work_slot": int(slot.slot)})
			continue
		var candidates: Array[String] = []
		for i: int in zone.cells:
			for key: String in data.resources_at.get(i, []):
				if not candidates.has(key):
					candidates.append(key)
		candidates.sort_custom(func(a: String, b: String) -> bool:
			return data.cell_from_index(int(data.resource_base[a].cell)).distance_squared_to(from) < data.cell_from_index(int(data.resource_base[b].cell)).distance_squared_to(from))
		for key: String in candidates:
			if key == str(data.site.manual.target) or excluded_targets.has(key):
				continue
			var r := Env.resource(data, key)
			if (bool(r.cleared) and str(zone.action) != "restore") or (int(zone.kind) >= 0 and int(r.kind) != int(zone.kind)):
				continue
			if not ecology_action_guard(data, key, str(zone.action)).ok:
				continue
			if str(zone.action) == "survey" and bool(r.discovered):
				continue
			if str(zone.action) == "capture" and capturable_species(r).is_empty():
				continue
			if str(zone.action) == "clear" and int(r.kind) not in [Env.Kind.TIMBER, Env.Kind.STONE, Env.Kind.FOOD, Env.Kind.HERB]:
				continue
			if int(r.remaining) == 0 and str(zone.action) not in ["clear", "restore"]:
				continue
			if data.feature_at[int(r.cell)] != 0 and not (Env.ecology_active(data) and int(r.kind) in Env.POPULATION_KINDS):
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

static func assign_task(data: TerrainData, task: Dictionary, worker_override: Variant = null) -> void:
	var worker: Dictionary = data.site.worker if worker_override == null else worker_override
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
	if task.has("work_slot") or int(worker.get("version", 0)) == 2:
		worker["work_slot"] = int(task.get("work_slot", -1))
		if worker.has("version"):
			worker.version = 2

static func begin_manual(data: TerrainData, key: String, cell: Vector2i, action: String = "harvest") -> Dictionary:
	if action not in ["harvest", "survey", "clear", "capture", "restore"]:
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
	if action == "capture":
		if capturable_species(r).is_empty():
			return fail("INVALID", "只有野馬與羊可活捉")
	if action in ["capture", "restore"] or Env.ecology_active(data):
		var ready := harvest(data, key, cell, data.site.manual.cargo, action if bool(r.discovered) else "survey", true)
		if not ready.ok:
			return ready
	data.site.manual.target = key
	data.site.manual.progress = 0.0
	data.site.manual.action = "survey" if not bool(r.discovered) else action
	data.site.manual.cell = data.index(cell)
	return ok("開始手動作業；移動或交戰將中斷")

static func mark_combat(data: TerrainData, duration: float = COMBAT_GRACE, preserve_manual: bool = false) -> void:
	if data.site.is_empty():
		return
	data.site.combat_left = maxf(float(data.site.combat_left), duration)
	if not preserve_manual:
		data.site.manual.target = ""
		data.site.manual.progress = 0.0

static func game_seconds(real_seconds: float, combat_left: float) -> float:
	var combat := minf(maxf(0.0, real_seconds), maxf(0.0, combat_left))
	return combat + maxf(0.0, real_seconds - combat) * 60.0

static func advance(data: TerrainData, real_seconds: float, worker_ready: bool = false, manual_ready: bool = false, occupied: Callable = Callable(), work_time: Callable = Callable(), crew_work: Callable = Callable(), worker_limit: int = CARRY_CAPACITY, manual_limit: int = CARRY_CAPACITY, time_multiplier: float = 1.0, worker_faction: int = -1, accepted_game_seconds: float = -1.0, shared_operating_projection: bool = false) -> void:
	if data.site.is_empty() or bool(data.site.paused) or real_seconds <= 0.0 or not is_finite(real_seconds) or time_multiplier <= 0.0 or not is_finite(time_multiplier):
		return
	# Integrate the combat-to-peace boundary exactly, including long frames.
	if not is_finite(accepted_game_seconds) or accepted_game_seconds < -1.0: return
	var minutes := (accepted_game_seconds if accepted_game_seconds >= 0.0 else game_seconds(real_seconds, float(data.site.combat_left)) * time_multiplier) / 60.0
	var combat_seconds := minf(real_seconds, float(data.site.combat_left))
	data.site.combat_left = maxf(0.0, float(data.site.combat_left) - combat_seconds)
	while minutes > 0.00000001:
		var slice := minf(minutes, 1.0 - float(data.site.phase))
		data.site.phase = float(data.site.phase) + slice
		_work(data, slice, worker_ready, manual_ready, occupied, work_time, null, null, worker_limit, manual_limit, worker_faction, shared_operating_projection)
		if crew_work.is_valid():
			crew_work.call(slice * 60.0) # Same phase/resource budget, before minute rollover.
		advance_ship_builds(data, occupied)
		minutes -= slice
		if float(data.site.phase) >= 0.99999999:
			data.site.phase = 0.0
			data.site.minute = int(data.site.minute) + 1
			_regenerate(data, occupied)
			allocate_water(data)

static func _work(data: TerrainData, minutes: float, worker_ready: bool, manual_ready: bool, occupied: Callable, work_time: Callable = Callable(), worker_override: Variant = null, cargo_override: Variant = null, carry_limit: int = CARRY_CAPACITY, manual_limit: int = CARRY_CAPACITY, worker_faction: int = -1, shared_operating_projection: bool = false, original_identity: int = 0) -> void:
	var worker: Dictionary = data.site.worker if worker_override == null else worker_override
	var cargo: Dictionary = worker.cargo if cargo_override == null else cargo_override
	if worker_override == null and not shared_operating_projection:
		# The original optional camp worker participates only from its real slot.
		var original_at_work := worker_ready and str(worker.mode) == "work" and str(worker.get("action", "")) == "operate" and int(worker.get("work_slot", -1)) >= 0 and int(worker.cell) == int(worker.get("work_cell", -1))
		data.set_meta(&"site_camp_operating_task", worker if original_at_work else {})
		if not data.has_meta(&"site_work_team"):
			set_operating_slots(data, [])
	if worker_ready and str(worker.mode) == "work" and str(worker.target) != "" and not _fire_work_pending(data, worker):
		var target := str(worker.target)
		var cell := data.cell_from_index(int(worker.cell))
		if target.begins_with("feature:"):
			_feature_work(data, target.trim_prefix("feature:"), minutes, occupied, work_time, worker, cargo, carry_limit, worker_faction, original_identity)
		elif target == "depot":
			var result := deposit(data, cargo, cell)
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
			var ready := harvest(data, target, cell, cargo, str(worker.action), true, carry_limit)
			if not ready.ok:
				worker.status = str(ready.message)
				worker.target = ""
				worker.mode = "idle"
			else:
				worker.progress = float(worker.progress) + (float(work_time.call(false, minutes)) if work_time.is_valid() else minutes)
				var required := resource_work_minutes(int(r.kind), str(worker.action))
				worker.status = "%s %.1f / %.1f 分" % ["清理" if str(worker.action) == "clear" else "作業", float(worker.progress), required]
				if float(worker.progress) + 0.00000001 >= required:
					if _fire_defer_resource_completion(data, worker, cargo, target, cell, str(worker.action), carry_limit, false):
						worker.progress = required
						worker.status = "原作業已完成工時，等待本輪燃燒後重驗採集"
					else:
						var result := harvest(data, target, cell, cargo, str(worker.action), false, carry_limit)
						worker.status = str(result.message)
						worker.progress = 0.0
						worker.target = ""
						worker.mode = "idle"
	var manual: Dictionary = data.site.manual
	if manual_ready and str(manual.target) != "" and not _fire_work_pending(data, manual):
		var r := Env.resource(data, str(manual.target))
		var ready := harvest(data, str(manual.target), data.cell_from_index(int(manual.cell)), manual.cargo, str(manual.action), true, manual_limit)
		if not ready.ok:
			data.site.notices.append(str(ready.message))
			manual.target = ""
			return
		manual.progress = float(manual.progress) + (float(work_time.call(true, minutes)) if work_time.is_valid() else minutes)
		var required := resource_work_minutes(int(r.kind), str(manual.action))
		if float(manual.progress) + 0.00000001 >= required:
			if _fire_defer_resource_completion(data, manual, manual.cargo, str(manual.target), data.cell_from_index(int(manual.cell)), str(manual.action), manual_limit, true):
				manual.progress = required
			else:
				var result := harvest(data, str(manual.target), data.cell_from_index(int(manual.cell)), manual.cargo, str(manual.action), false, manual_limit)
				data.site.notices.append(str(result.message))
				manual.target = ""
				manual.progress = 0.0

static func _feature_work(data: TerrainData, key: String, minutes: float, occupied: Callable, work_time: Callable = Callable(), worker_override: Variant = null, cargo_override: Variant = null, carry_limit: int = CARRY_CAPACITY, worker_faction: int = -1, original_identity: int = 0) -> void:
	var worker: Dictionary = data.site.worker if worker_override == null else worker_override
	var cargo: Dictionary = worker.cargo if cargo_override == null else cargo_override
	if not data.site.features.has(key):
		worker.mode = "idle"
		worker.target = ""
		return
	var feature: Dictionary = data.site.features[key]
	if int(feature.get("owner_faction", -1)) >= 0 and int(feature.owner_faction) != worker_faction:
		worker.status = "不是此設施的管理方工作者"
		worker.target = ""
		worker.mode = "idle"
		return
	var action := str(worker.get("action", "construct" if str(feature.stage) != "complete" else "operate"))
	var ecology_guard := ecology_feature_work_guard(data, feature, action)
	if not ecology_guard.ok:
		worker.status = str(ecology_guard.message)
		return
	var kind := str(feature.kind)
	var definition: Dictionary = feature_recipe(feature)
	var job: Dictionary = feature.repair if action == "repair" and feature.has("repair") else (feature.pending_build if action == "construct" and feature.has("pending_build") else feature)
	var expected_cell := int(job.work_cell) if action == "repair" and job.has("work_cell") else int(job.get("entrance", feature.entrance))
	var service: Array[int] = []
	var slot_id := int(worker.get("work_slot", -1))
	if action == "operate" and int(feature.get("layout_version", 0)) == BUILDING_LAYOUT_VERSION and kind in FARM_KINDS + PASTURE_KINDS:
		var slots := feature_work_slots(data, feature)
		if slot_id < 0 or slot_id >= slots.size():
			worker.target = ""
			worker.mode = "idle"
			return
		expected_cell = int(slots[slot_id].cell)
		service.assign(slots[slot_id].service_cells)
	if int(worker.cell) != expected_cell:
		return
	if action == "operate" and kind == "shipyard" and str(feature.stage) == "complete":
		_ship_feature_work(data, key, feature, worker, minutes, occupied, work_time, original_identity)
		return
	# A finished paid batch remains deliverable even if water/tools later stop.
	if action == "operate" and str(feature.stage) == "complete" and definition.has("cycle") and bool(feature.batch_paid) and float(feature.production) + 0.00000001 >= float(definition.cycle):
		_deliver_feature_batch(data, feature, worker, cargo, carry_limit, original_identity)
		return
	if action != "repair" and str(feature.stage) == "complete" and not feature_usable(feature):
		worker.status = "建物已毀壞，先取消升級或修復；原已付物資保留"
		return
	if not can_pay(data.site.inventory, {"tools": 1}):
		worker.status = "缺少工具"
		return
	if action == "repair":
		if not feature.has("repair"):
			worker.target = ""
			worker.mode = "idle"
			return
		var fire_guard := _fire_repair_guard(data, key, str(job.part), true)
		if not fire_guard.ok:
			worker.status = str(fire_guard.message)
			return
		if not _repair_contact(data, feature, feature_geometry(data, feature).parts[str(job.part)], data.cell_from_index(int(worker.cell))):
			worker.status = "原修理接觸格已失效"
			return
		if work_time.is_valid():
			minutes = float(work_time.call(false, minutes))
		job.progress = minf(float(job.work), float(job.progress) + minutes)
		worker.status = "修理 %.1f / %.1f 分" % [float(job.progress), float(job.work)]
		if float(job.progress) + 0.00000001 < float(job.work):
			return
		if _fire_defer_feature_completion(data, worker, cargo, key, job, occupied, carry_limit, worker_faction): return
		var candidate := feature.duplicate(true)
		var maximum := float(feature_geometry(data, feature).parts[str(job.part)].max_hp)
		candidate.parts[str(job.part)].hp = minf(maximum, float(candidate.parts[str(job.part)].hp) + float(job.amount))
		candidate.erase("repair")
		var guard := structure_change_guard(data, key, candidate, occupied, "repair")
		if not guard.ok:
			worker.status = str(guard.message)
			return
		# Only the existing successful structure transaction restores material.
		var fire_old_hp := float(feature.parts[str(job.part)].hp)
		var fire_full_cost: Dictionary = _repair_terms(feature, feature_geometry(data, feature).parts[str(job.part)], maximum).cost
		feature.parts[str(job.part)].hp = float(candidate.parts[str(job.part)].hp)
		_fire_repair_finished(data, key, str(job.part), fire_old_hp, float(feature.parts[str(job.part)].hp), maximum, job.cost, fire_full_cost)
		feature.erase("repair")
		feature.status = "修理完成"
		_stop_feature_zones(data, key, "repair")
		worker.target = ""
		worker.mode = "idle"
		Env.rebuild_indexes(data)
		rebuild_water(data)
		return
	if str(feature.stage) != "complete" or action == "construct" and feature.has("pending_build"):
		if feature.has("pending_build") and _fire_feature_hot(data, key):
			worker.status = "原部件仍熱；升級／擴建保留已付款與進度"
			return
		for source: String in job.clearing:
			if not bool(Env.resource(data, source).get("cleared", true)):
				worker.status = "施工來源尚未清理，返回原工作派發"
				worker.target = ""
				worker.mode = "idle"
				return
		var construction_cells: Array = job.get("added_cells", feature.cells)
		for index: int in construction_cells:
			if occupied.is_valid() and bool(occupied.call(data.cell_from_index(index))):
				worker.status = "施工占地有人／已預約，等待移開"
				return
		var trial_guard := technology_geometry_operator_guard(data, feature, worker, original_identity)
		if not trial_guard.ok:
			worker.status = str(trial_guard.message)
			return
		if not feature.has("pending_build"):
			feature.stage = "building"
		if work_time.is_valid():
			minutes = float(work_time.call(false, minutes))
		technology_record_work(feature, minutes, int(trial_guard.get("operator_id", 0)))
		job.progress = minf(float(job.work), float(job.progress) + minutes)
		worker.status = "施工 %.1f / %.1f 分" % [float(job.progress), float(job.work)]
		if float(job.progress) + 0.00000001 < float(job.work):
			return
		if _fire_defer_feature_completion(data, worker, cargo, key, job, occupied, carry_limit, worker_faction): return
		ecology_guard = ecology_feature_work_guard(data, feature, action)
		if not ecology_guard.ok:
			worker.status = str(ecology_guard.message)
			return
		var fire_previous := feature.duplicate(true) if str(feature.stage) == "complete" else {}
		var fire_paid: Dictionary = job.get("cost", {}).duplicate(true)
		var candidate := feature.duplicate(true)
		candidate.stage = "complete"
		if feature.has("pending_build"):
			candidate.cells = job.cells.duplicate()
			candidate.entrance = int(job.entrance)
			if job.has("target_grade"): candidate = _civil_upgrade_candidate(candidate, int(job.target_grade))
			candidate.erase("pending_build")
		var guard := structure_change_guard(data, key, candidate, occupied, "complete")
		if not guard.ok:
			worker.status = str(guard.message)
			return
		var technology_completed := prepare_technology_geometry_completion(data, feature, "feature:" + key)
		if not technology_completed.ok:
			worker.status = str(technology_completed.message)
			return
		if feature.has("pending_build"):
			if job.has("target_grade"):
				feature["civil_version"] = CIVIL_VERSION
				feature["building_grade"] = int(job.target_grade)
				feature["parts"] = candidate.parts
			feature.cells = job.cells.duplicate()
			feature.entrance = int(job.entrance)
			feature.work = float(feature.work) + float(job.work)
			feature.progress = float(feature.work)
			add_items(feature.cost, job.cost)
			for source: String in job.clearing:
				if not feature.clearing.has(source):
					feature.clearing.append(source)
			feature.erase("pending_build")
			if feature.has("parts"):
				var new_parts: Dictionary = feature_geometry(data, feature).parts
				for part_id: String in new_parts:
					if not feature.parts.has(part_id):
						feature.parts[part_id] = {"hp": float(new_parts[part_id].max_hp)}
			for zone: Dictionary in data.site.zones:
				if str(zone.get("feature", "")) == key:
					zone.cells = feature.cells.duplicate()
		feature.stage = "complete"
		_fire_feature_completed(data, key, fire_previous, fire_paid)
		publish_technology_geometry_completion(technology_completed)
		feature.status = "已完成"
		if kind == "settlement_center": _settlement_center_completed(data, key, int(job.get("target_level", 1)))
		if kind == "level":
			for index: int in feature.cells:
				data.height_levels[index] = int(feature.level)
				data.site.terrain_changes[str(index)] = int(feature.level)
			rebuild_terrain_edges(data)
			data.site.features.erase(key)
		worker.mode = "idle"
		worker.target = ""
		_stop_feature_zones(data, key, "construct")
		Env.rebuild_indexes(data)
		if Env.ecology_active(data): ecology_reconcile(data)
		rebuild_water(data)
		data.site.notices.append(str(definition.name) + "已完成")
		return
	if not definition.has("cycle"):
		worker.mode = "idle"
		worker.target = ""
		return
	if action != "operate" or feature.has("pending_build") or feature.has("repair"):
		return
	if feature.has("species") and (int(feature.residents) > grazing_capacity(data, feature.cells) or int(feature.residents) < (2 if str(feature.species) == "horse" else 1)):
		worker.status = "牧地承載或種畜數量不足"
		return
	var technology_guard := technology_batch_operator_guard(data, key, feature, worker, original_identity)
	if not technology_guard.ok:
		worker.status = str(technology_guard.message)
		return
	if not bool(feature.batch_paid):
		if not can_pay(feature_input_inventory(data, feature, key), definition.input):
			feature.status = "缺投入：" + items_text(definition.input)
			worker.status = feature.status
			worker.mode = "idle"
			worker.target = ""
			return
		# ponytail: the original one camp store supplies a shared batch once.
		var payment := pay_feature_inputs(data, feature, key, definition.input, worker, original_identity)
		if not payment.ok:
			worker.status = str(payment.message)
			return
		feature.batch_paid = true
	var water: Dictionary = data.site.water_status.get(key, {})
	if not service.is_empty():
		water = water.get("slots", {}).get(str(slot_id), {})
	var demand := float(water.get("demand", water_demand(feature)))
	var water_ratio := 1.0
	if demand > 0.0:
		water_ratio = clampf(float(water.get("supplied", 0.0)) / demand, 0.0, 1.0)
	if water_ratio <= 0.0:
		feature.status = "缺水，暫停運作"
		worker.status = feature.status
		return
	var productivity := 1.0
	if kind in FARM_KINDS:
		var fertility_total := 0.0
		var served: Array = feature.cells if service.is_empty() else service
		for index: int in served:
			fertility_total += float(data.fertility[index])
		productivity = clampf(fertility_total / float(served.size()) / 60.0, 0.25, 1.5) * float(served.size())
	elif kind in PASTURE_KINDS and not service.is_empty():
		var total_service := 0
		for slot: Dictionary in _operating_slots(data, key, feature):
			total_service += slot.service_cells.size()
		productivity = _pasture_scale(data, feature, total_service) * float(service.size()) / maxf(1.0, total_service)
	productivity *= building_productivity(feature)
	if productivity <= 0.0:
		worker.status = "沒有到位的照料工作量"
		return
	if work_time.is_valid() and float(feature.production) < float(definition.cycle):
		minutes = float(work_time.call(false, minutes))
	technology_record_work(feature, minutes, int(technology_guard.get("operator_id", 0)))
	feature.production = minf(float(definition.cycle), float(feature.production) + minutes * water_ratio * productivity)
	feature.status = "生產 %.1f / %.1f 分" % [float(feature.production), float(definition.cycle)]
	worker.status = feature.status
	if float(feature.production) + 0.00000001 >= float(definition.cycle):
		_deliver_feature_batch(data, feature, worker, cargo, carry_limit, original_identity)

static func _deliver_feature_batch(data: TerrainData, feature: Dictionary, worker: Dictionary, cargo: Dictionary, carry_limit: int, original_identity: int = 0) -> void:
	var checked := prepare_feature_output(data, feature, worker, cargo, carry_limit, original_identity)
	if not checked.ok:
		worker.status = str(checked.get("message", checked.code))
		return
	publish_feature_output(data, checked)

static func _regenerate(data: TerrainData, occupied: Callable) -> void:
	var rebuild := false
	var admitted := Env.ecology_active(data)
	var keys: Array = data.site.changes.keys()
	keys.sort()
	for key: String in keys:
		var r := Env.resource(data, key)
		if r.is_empty() or bool(r.cleared) or int(r.next_recovery) < 0 or int(r.next_recovery) > int(data.site.minute): continue
		if int(r.kind) == Env.Kind.TIMBER and _fire_regeneration_blocked(data, key):
			Env.change(data, key, {"next_recovery": int(data.site.minute) + maxi(1, int(r.recover))})
			continue
		var capacity := Env.habitat_capacity(data, key)
		var population := int(r.kind) in Env.POPULATION_KINDS
		var blocked := data.feature_at[int(r.cell)] != 0
		if admitted and population: blocked = capacity <= 0 or Env.work_cells(data, key).is_empty()
		if bool(r.blocks) and occupied.is_valid() and bool(occupied.call(data.cell_from_index(int(r.cell)))): blocked = true
		if blocked or capacity <= int(r.remaining):
			var fields := {"next_recovery": int(data.site.minute) + maxi(1, int(r.recover))}
			if admitted and population: fields["eco_resting"] = Env.ecology_resting(int(r.remaining), capacity, r.get("eco_resting"))
			Env.change(data, key, fields)
			continue
		var remaining := capacity if int(r.kind) in [Env.Kind.TIMBER, Env.Kind.FOOD, Env.Kind.HERB] else mini(capacity, int(r.remaining) + 1)
		if int(r.kind) == Env.Kind.TIMBER: remaining = _fire_resource_regenerated(data, key, int(r.remaining), remaining, capacity)
		Env.change(data, key, {"remaining": remaining, "next_recovery": int(data.site.minute) + int(r.recover) if remaining < capacity else -1})
		rebuild = true
	if rebuild:
		Env.rebuild_indexes(data)
		rebuild_water(data)

static func rebuild_terrain_edges(data: TerrainData) -> void:
	var fixed_ramps: Variant = data.parameters.get("fixed_ramp_edges")
	if data.parameters.get("composition") == "fixed_geography" and fixed_ramps is PackedByteArray \
			and fixed_ramps.size() == data.ramp_edges.size():
		data.ramp_edges = fixed_ramps.duplicate()
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
		if str(feature.stage) != "complete" or str(feature.kind) not in ["well", "intake"] or not feature_usable(feature):
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
		if not data.site.features.has(key):
			continue
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
		var requests: Array[Dictionary] = []
		if key == "camp":
			requests.append({"slot": -1, "target": int(data.site.depot_cell), "demand": 0.02})
		else:
			var feature: Dictionary = data.site.features[key]
			if str(feature.stage) != "complete":
				continue
			var kind := str(feature.kind)
			if int(feature.get("layout_version", 0)) == BUILDING_LAYOUT_VERSION and kind in FARM_KINDS + PASTURE_KINDS:
				var slots := _operating_slots(data, key, feature)
				var served := 0
				for slot: Dictionary in slots:
					served += slot.service_cells.size()
				var scale := float(served) if kind in FARM_KINDS else _pasture_scale(data, feature, served)
				for slot: Dictionary in slots:
					var portion := float(slot.service_cells.size()) / maxf(1.0, served)
					requests.append({"slot": int(slot.slot), "target": int(slot.cell), "demand": float(FEATURES[kind].water) * scale * portion})
			else:
				requests.append({"slot": -1, "target": int(feature.entrance), "demand": water_demand(feature)})
		var status := {"demand": 0.0, "supplied": 0.0, "slots": {}}
		for request: Dictionary in requests:
			var demand := float(request.demand)
			var supplied := 0.0
			for pump_key: String in pump_sources:
				# A remote field worker needs a real water route to that work
				# position; a wet entrance does not irrigate an entire hectare.
				if not data.site.water_links[pump_key].has(int(request.target)):
					continue
				var source := str(pump_sources[pump_key])
				var portion := minf(demand - supplied, float(budgets[source]))
				supplied += portion
				budgets[source] = float(budgets[source]) - portion
				if supplied >= demand:
					break
			status.demand = float(status.demand) + demand
			status.supplied = float(status.supplied) + supplied
			if int(request.slot) >= 0:
				status.slots[str(request.slot)] = {"demand": demand, "supplied": supplied}
		data.site.water_status[key] = status

static func date_text(data: TerrainData) -> String:
	var minute := int(data.site.get("minute", 0))
	return "第 %d 日  %02d:%02d" % [floori(float(minute) / 1440.0) + 1, floori(float(minute % 1440) / 60.0), minute % 60]


# Ship-relative ground_loot stays in the original item container collection.
static func valid_ship_loot_location(data: TerrainData, location: Dictionary) -> bool:
	if location.size() != 2 or not location.get("vehicle_id") is String or not location.get("local_position") is Array: return false
	var vehicle: Dictionary = data.site.get("vehicles", {}).get(str(location.vehicle_id), {})
	if str(vehicle.get("kind", "")) != "ship" or int(vehicle.get("ship_version", 0)) != 1 or int(vehicle.get("definition_version", 0)) != 1: return false
	var local: Array = location.local_position
	if local.size() != 2 or not (local[0] is float or local[0] is int) or not (local[1] is float or local[1] is int): return false
	var ship = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
	var spec: Dictionary = ship.definition(str(vehicle.get("ship_type", "")))
	return not spec.is_empty() and is_finite(float(local[0])) and is_finite(float(local[1])) and float(local[0]) >= -0.5 and float(local[0]) < float(spec.width) - 0.5 and float(local[1]) >= -0.5 and float(local[1]) < float(spec.length) - 0.5

# Merge these pure queries into the original SiteRuntime. No derived geometry is saved.
static func siege_tower_pose(data: TerrainData, vehicle: Dictionary) -> Dictionary:
	if str(vehicle.get("kind", "")) != "siege_tower" or not _building_integer(vehicle.get("cell"), 0, data.size.x * data.size.y - 1): return {}
	var facing: Variant = vehicle.get("facing")
	if not _siege_tower_facing(facing): return {}
	return {"version": 1, "cell": int(vehicle.cell), "facing": [int(facing[0]), int(facing[1])], "level": int(data.height_levels[int(vehicle.cell)])}

static func _siege_tower_facing(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _building_integer(value[0], -1, 1) and _building_integer(value[1], -1, 1) and absi(int(value[0])) + absi(int(value[1])) == 1

# The prepass runs before candidate navigation consumes any tower record.
# Full vehicle/holder/crew schema remains in the original Store validator.
static func validate_siege_tower_pose(data: TerrainData, vehicle: Dictionary) -> Dictionary:
	if str(vehicle.get("kind", "")) != "siege_tower":
		return fail("CORRUPT_SAVE", "非塔器具含部署位姿") if vehicle.has("deployed_pose") else ok()
	if not _building_integer(vehicle.get("cell"), 0, data.size.x * data.size.y - 1) or not _siege_tower_facing(vehicle.get("facing")):
		return fail("CORRUPT_SAVE", "攻城塔原位姿非法")
	if not vehicle.get("phase") is String or str(vehicle.phase) not in ["building", "idle", "ready", "moving", "turning", "deploying", "deployed", "disabled", "wrecked"]:
		return fail("CORRUPT_SAVE", "攻城塔狀態非法")
	if not (vehicle.get("hp") is int or vehicle.get("hp") is float) or not is_finite(float(vehicle.hp)) or float(vehicle.hp) < 0.0 or not vehicle.get("deployed_pose") is Dictionary:
		return fail("CORRUPT_SAVE", "攻城塔耐久／部署位姿非法")
	var pose: Dictionary = vehicle.deployed_pose
	if pose.is_empty(): return fail("CORRUPT_SAVE", "部署塔缺少原位姿") if str(vehicle.phase) == "deployed" else ok()
	if pose.size() != 4 or not _building_integer(pose.get("version"), 1, 1) or not _building_integer(pose.get("cell"), int(vehicle.cell), int(vehicle.cell)) or not _siege_tower_facing(pose.get("facing")) or not _building_integer(pose.get("level"), 0, 5):
		return fail("CORRUPT_SAVE", "攻城塔部署位姿欄位非法")
	if int(pose.facing[0]) != int(vehicle.facing[0]) or int(pose.facing[1]) != int(vehicle.facing[1]) or str(vehicle.phase) not in ["deployed", "deploying", "disabled", "wrecked"]:
		return fail("CORRUPT_SAVE", "攻城塔部署位姿與原車體不同")
	return ok()

static func _siege_tower_cell(data: TerrainData, vehicle: Dictionary, forward: int, side: int) -> Vector2i:
	var facing := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
	return data.cell_from_index(int(vehicle.cell)) + facing * forward + Vector2i(-facing.y, facing.x) * side

static func siege_tower_physical_cells(data: TerrainData, vehicle: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if str(vehicle.get("kind", "")) != "siege_tower" or not validate_siege_tower_pose(data, vehicle).ok: return cells
	for forward: int in range(4):
		for side: int in range(3): cells.append(_siege_tower_cell(data, vehicle, forward, side))
	if not vehicle.deployed_pose.is_empty():
		cells.append(_siege_tower_cell(data, vehicle, -2, 1))
		cells.append(_siege_tower_cell(data, vehicle, -1, 1))
		for side: int in range(3): cells.append(_siege_tower_cell(data, vehicle, 4, side))
	return cells

# Read only the natural/feature underlay. A tower cannot support its own roof,
# another tower, or a stale merged navigation cache.
static func _siege_tower_underlay_height(data: TerrainData, cell: Vector2i) -> int:
	if not data.contains(cell): return -1
	var index := data.index(cell)
	var height := int(data.height_levels[index])
	var feature_id := int(data.feature_at[index]) if data.feature_at.size() == data.height_levels.size() else 0
	if feature_id != 0:
		var feature: Dictionary = data.site.get("features", {}).get(str(feature_id), {})
		if str(feature.get("stage", "")) == "complete":
			var geometry := feature_geometry(data, feature)
			height = int(geometry.get("heights", {}).get(index, height))
	return height

static func siege_tower_geometry(data: TerrainData, vehicle: Dictionary) -> Dictionary:
	var result := {"heights": {}, "blocked": [], "ramps": {}, "edge_blocks": {}, "active": false, "support_valid": false, "reason": "尚未部署", "physical": [], "top": [], "entry": [], "bridge": [], "supports": []}
	if str(vehicle.get("kind", "")) != "siege_tower" or not validate_siege_tower_pose(data, vehicle).ok: return result
	result.physical = siege_tower_physical_cells(data, vehicle)
	if vehicle.deployed_pose.is_empty(): return result
	var pose: Dictionary = vehicle.deployed_pose
	var base := int(pose.level)
	for forward: int in range(4):
		for side: int in range(3): result.top.append(_siege_tower_cell(data, vehicle, forward, side))
	result.entry = [_siege_tower_cell(data, vehicle, -2, 1), _siege_tower_cell(data, vehicle, -1, 1)]
	for side: int in range(3):
		result.bridge.append(_siege_tower_cell(data, vehicle, 4, side))
		result.supports.append(_siege_tower_cell(data, vehicle, 5, side))
	var approach := _siege_tower_cell(data, vehicle, -3, 1)
	# All physical appendages are outside feature cells; bridge endpoint cells
	# may be the completed wall surface, but never become owned by this tower.
	for cell: Vector2i in result.physical:
		if not data.contains(cell) or not data.is_walkable(cell):
			result.reason = "塔體／附屬結構地面受阻"; return result
		var index := data.index(cell)
		if int(data.height_levels[index]) != base or int(data.feature_at[index]) != 0 or int(data.surface_types[index]) in [TerrainData.Surface.WATER, TerrainData.Surface.WETLAND]:
			result.reason = "塔體／附屬結構需平整乾燥且無其他建築"; return result
	if not data.contains(approach) or not data.is_walkable(approach) or _siege_tower_underlay_height(data, approach) != base:
		result.reason = "塔後入口地面不相容"; return result
	if _siege_vehicle_claims(data, approach, str(vehicle.get("id", ""))):
		result.reason = "塔後入口被其他車具／掃掠占用"; return result
	for cell: Vector2i in result.supports:
		if not data.contains(cell) or not data.is_walkable(cell) or _siege_tower_underlay_height(data, cell) != base + WALL_RISE:
			result.reason = "塔橋須接三格同高有效牆頂／平台"; return result
		if _siege_vehicle_claims(data, cell, str(vehicle.get("id", ""))):
			result.reason = "塔橋對接端被其他車具／掃掠占用"; return result
	# Cross-collection/vehicle collisions are checked against complete physical
	# footprints, including every other tower's appendages, independent of order.
	for cell: Vector2i in result.physical:
		if _siege_vehicle_claims(data, cell, str(vehicle.get("id", ""))):
			result.reason = "塔與其他原車具占地／掃掠重疊"; return result
	result.support_valid = true
	result.reason = "支承合法"
	if float(vehicle.hp) <= 0.0 or str(vehicle.phase) != "deployed": return result
	result.active = true
	for cell: Vector2i in result.top + result.bridge: result.heights[data.index(cell)] = base + WALL_RISE
	result.heights[data.index(result.entry[0])] = base + 1
	result.heights[data.index(result.entry[1])] = base + WALL_RISE
	_geometry_edge(data, result.ramps, approach, result.entry[0])
	_geometry_edge(data, result.ramps, result.entry[0], result.entry[1])
	# Rail every boundary except the rear approach and the three wall exits.
	# Internal equal-height cells need no slope flags; all vertical access is
	# through the original two reciprocal one-level navigation ramps.
	var allowed_edges := {}
	allowed_edges["%d:%d" % [data.index(result.entry[0]), data.index(approach)]] = true
	for side: int in range(3): allowed_edges["%d:%d" % [data.index(result.bridge[side]), data.index(result.supports[side])]] = true
	for value: Variant in result.heights:
		var cell := data.cell_from_index(int(value))
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cell + direction
			if not data.contains(next) or result.heights.has(data.index(next)): continue
			if not allowed_edges.has("%d:%d" % [int(value), data.index(next)]): _geometry_edge(data, result.edge_blocks, cell, next)
	return result

# Person route callers pass the original current person cell separately from
# their speculative route node and keep the same final goal for the search.
static func siege_person_step_allowed(data: TerrainData, vehicle: Dictionary, origin: Vector2i, from: Vector2i, to: Vector2i, goal: Vector2i) -> bool:
	if str(vehicle.get("kind", "")) != "siege_tower": return false
	var geometry := siege_tower_geometry(data, vehicle)
	var physical: Array = geometry.physical
	if not physical.has(to): return true
	if bool(geometry.active): return geometry.heights.has(data.index(to)) and data.can_step(from, to)
	# Preserve a fallen original source inside this same invalid footprint.
	# Outsiders cannot enter it; an exit route cannot re-enter after leaving.
	if vehicle.get("deployed_pose", {}).is_empty() or not (float(vehicle.get("hp", 0.0)) <= 0.0 or str(vehicle.get("phase", "")) == "disabled" or not bool(geometry.support_valid)): return false
	return physical.has(origin) and physical.has(from) and not physical.has(goal) and data.is_walkable(goal) and data.can_step(from, to)

# Existing unique-exit preservation must use the same physical/person split,
# otherwise a stationary cart could be mistaken for a legal way off a wall.
static func _siege_component_cell_open(data: TerrainData, cell: Vector2i) -> bool:
	if not _siege_vehicle_claims(data, cell): return true
	for vehicle: Dictionary in data.site.get("vehicles", {}).values():
		if str(vehicle.get("kind", "")) != "siege_tower": continue
		var geometry := siege_tower_geometry(data, vehicle)
		if bool(geometry.active) and geometry.heights.has(data.index(cell)): return true
	return false

static func siege_tower_surface_guard(data: TerrainData, vehicle: Dictionary, occupied: Callable) -> Dictionary:
	if str(vehicle.get("kind", "")) != "siege_tower" or not validate_siege_tower_pose(data, vehicle).ok: return fail("INVALID", "攻城塔部署位姿非法")
	if not occupied.is_valid(): return fail("INVALID", "塔撤除表面須提供原人物及承諾步預約查詢")
	for cell: Vector2i in siege_tower_physical_cells(data, vehicle):
		if bool(occupied.call(cell)): return fail("OCCUPIED", "先清空塔頂、入口、橋及進出承諾步／預約")
	return ok()

# The combat batch invokes this transaction after all original damage commits,
# before its single navigation diff/fall settlement. Env itself remains pure.
static func invalidate_siege_tower_supports(data: TerrainData) -> Array[String]:
	var invalidated: Array[String] = []
	for key: String in data.site.get("vehicles", {}):
		var vehicle: Dictionary = data.site.vehicles[key]
		if str(vehicle.get("kind", "")) != "siege_tower" or str(vehicle.get("phase", "")) != "deployed": continue
		if not bool(siege_tower_geometry(data, vehicle).support_valid):
			vehicle.phase = "disabled"
			vehicle.command = {}
			invalidated.append(key)
	if not invalidated.is_empty(): Env.rebuild_indexes(data)
	return invalidated

# A stable saved person may occupy the active roof, or retain the original
# settled cell after its surface vanished. This never mutates HP or cells.
static func siege_tower_saved_person_allowed(data: TerrainData, vehicle: Dictionary, body: Dictionary, claim: Vector2i) -> bool:
	var geometry := siege_tower_geometry(data, vehicle)
	if not geometry.physical.has(claim): return false
	if bool(geometry.active): return geometry.heights.has(data.index(claim)) and data.is_walkable(claim)
	if vehicle.get("deployed_pose", {}).is_empty() or not (float(vehicle.get("hp", 0.0)) <= 0.0 or str(vehicle.get("phase", "")) == "disabled" or not bool(geometry.support_valid)): return false
	var source: Variant = body.get("cell")
	var destination: Variant = body.get("destination", [-1, -1])
	if not source is Array or source.size() != 2 or not destination is Array or destination.size() != 2: return false
	if not _building_integer(source[0], 0, data.size.x - 1) or not _building_integer(source[1], 0, data.size.y - 1) or not _building_integer(destination[0], -1, -1) or not _building_integer(destination[1], -1, -1): return false
	if not _building_number(body.get("movement_left", 0.0), 0.0, 0.0): return false
	return claim == Vector2i(int(source[0]), int(source[1])) and data.is_walkable(claim)

static func validate_siege_ladder(feature: Dictionary) -> Dictionary:
	if str(feature.get("kind", "")) != "siege_ladder": return fail("CORRUPT_SAVE", "非攻城梯含架設狀態") if feature.has("ladder") else ok()
	var value: Variant = feature.get("ladder")
	if not value is Dictionary or value.size() != 5 or not _building_integer(value.get("version"), 1, 1) or value.get("phase") not in ["folded", "deployed"] or value.get("pending") not in ["", "deploy", "retract"] or not value.get("workers") is Array:
		return fail("CORRUPT_SAVE", "攻城梯架設狀態非法")
	var duration := 12.0 if str(value.pending) == "deploy" else 8.0
	if not _building_number(value.get("progress"), 0.0, duration): return fail("CORRUPT_SAVE", "攻城梯架設進度非法")
	if str(value.pending).is_empty():
		if float(value.progress) != 0.0 or not value.workers.is_empty(): return fail("CORRUPT_SAVE", "無梯作業仍保留進度／人員")
	else:
		if str(feature.get("stage", "")) != "complete" or value.workers.size() != 2 or not _building_integer(value.workers[0], 1, 2147483647) or not _building_integer(value.workers[1], 1, 2147483647) or int(value.workers[0]) == int(value.workers[1]): return fail("CORRUPT_SAVE", "攻城梯作業須兩名不同原人")
		if (str(value.pending) == "deploy") != (str(value.phase) == "folded"): return fail("CORRUPT_SAVE", "攻城梯作業方向不符")
	if str(feature.get("stage", "")) != "complete" and str(value.phase) != "folded": return fail("CORRUPT_SAVE", "未完成攻城梯不可登城")
	return ok()

static func siege_ladder_work_slots(data: TerrainData, feature: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if str(feature.get("kind", "")) != "siege_ladder": return result
	var geometry := feature_geometry(data, feature)
	if not geometry.has("stair_lower") or not geometry.has("external_lower"): return result
	var lower: Vector2i = geometry.stair_lower.cell
	var axis: Vector2i = geometry.stair_upper.cell - lower
	var side := Vector2i(-axis.y, axis.x)
	for cell: Vector2i in [geometry.external_lower.cell, lower - side]:
		if not data.contains(cell) or not data.is_walkable(cell) or data.effective_height(cell) != int(feature.level): return []
		result.append({"slot": result.size(), "cell": data.index(cell)})
	return result

static func request_siege_ladder_action(data: TerrainData, key: String, action: String, identities: Array[int], requester_faction: int, occupied: Callable, preview: bool = false) -> Dictionary:
	if _ship_runtime_pending(data): return fail("BUSY", "原固定目標仍待補算或交接；暫不能接受新設施操作")
	var feature: Dictionary = data.site.get("features", {}).get(key, {})
	if str(feature.get("kind", "")) != "siege_ladder" or not validate_siege_ladder(feature).ok: return fail("NO_TARGET")
	if int(feature.get("owner_faction", -1)) != requester_faction or requester_faction < 0: return fail("NO_AUTHORITY")
	if not occupied.is_valid(): return fail("INVALID", "梯具部署須查原人物／預約")
	if bool(data.site.get("paused", false)) or str(feature.stage) != "complete" or feature.has("repair") or feature.has("pending_build") or not str(feature.ladder.pending).is_empty(): return fail("BUSY")
	if action not in ["deploy", "retract"] or identities.size() != 2 or identities[0] == identities[1] or identities[0] < 1 or identities[1] < 1: return fail("INVALID", "須兩名不同原隊員")
	if (action == "deploy") != (str(feature.ladder.phase) == "folded"): return fail("INVALID", "梯具已處於所選狀態")
	if action == "deploy":
		for part: Dictionary in feature.parts.values():
			if float(part.hp) <= 0.0: return fail("BROKEN", "兩段梯具須先修復")
	if siege_ladder_work_slots(data, feature).size() != 2: return fail("UNREACHABLE", "兩個外側梯工位受阻")
	var candidate := feature.duplicate(true)
	candidate.ladder.phase = "deployed" if action == "deploy" else "folded"
	var guard := structure_change_guard(data, key, candidate, occupied, "ladder_" + action)
	if not guard.ok: return guard
	var geometry := feature_geometry(data, candidate)
	if action == "deploy" and (not data.is_walkable(geometry.external_upper.cell) or data.effective_height(geometry.external_upper.cell) != int(feature.level) + WALL_RISE): return fail("UNREACHABLE", "梯頂須接同高有效牆頂／平台")
	if not preview:
		feature.ladder.pending = action
		feature.ladder.progress = 0.0
		feature.ladder.workers = identities.duplicate()
		feature.status = "等候兩名原隊員就位架梯" if action == "deploy" else "等候兩名原隊員就位收梯"
	return ok("兩人到外側工位後開始", {"seconds": 12.0 if action == "deploy" else 8.0, "slots": siege_ladder_work_slots(data, feature)})

static func cancel_siege_ladder_action(data: TerrainData, key: String) -> Dictionary:
	var feature: Dictionary = data.site.get("features", {}).get(key, {})
	if str(feature.get("kind", "")) != "siege_ladder" or not validate_siege_ladder(feature).ok: return fail("NO_TARGET")
	feature.ladder.pending = ""
	feature.ladder.progress = 0.0
	feature.ladder.workers = []
	_refresh_siege_ladder_tasks(data, key)
	return ok("已停止梯具作業；保持原部署與耐久")

static func _refresh_siege_ladder_tasks(data: TerrainData, key: String) -> void:
	if not data.has_meta(&"site_work_team"): return
	var ref_value: Variant = data.get_meta(&"site_work_team", null)
	if ref_value is WeakRef:
		var owner: Variant = ref_value.get_ref()
		if owner != null: owner._clear_ladder_tasks(key)

static func advance_siege_ladder_action(data: TerrainData, key: String, seconds: float, workers: Array[Dictionary], occupied: Callable) -> Dictionary:
	var feature: Dictionary = data.site.get("features", {}).get(key, {})
	if str(feature.get("kind", "")) != "siege_ladder" or not validate_siege_ladder(feature).ok or str(feature.ladder.pending).is_empty(): return fail("NO_TARGET")
	var point_consumer: Variant = data.get_meta(&"region_point_consuming", Callable())
	var consuming: bool = point_consumer is Callable and point_consumer.is_valid() and bool(point_consumer.call())
	if not is_finite(seconds) or seconds < 0.0 or seconds == 0.0 and not consuming or bool(data.site.get("paused", false)): return fail("INVALID")
	var slots := siege_ladder_work_slots(data, feature)
	if workers.size() != 2 or slots.size() != 2: return fail("CREW", "須兩名原隊員同時到位")
	for index: int in range(2):
		if int(workers[index].get("person_id", -1)) != int(feature.ladder.workers[index]) or workers[index].get("cell") != data.cell_from_index(int(slots[index].cell)): return fail("CREW", "原工位／人員引用不同")
	if str(feature.ladder.pending) == "deploy":
		for part: Dictionary in feature.parts.values():
			if float(part.hp) <= 0.0: return fail("BROKEN", "兩段梯具須先修復")
	var duration := 12.0 if str(feature.ladder.pending) == "deploy" else 8.0
	var next_progress := minf(duration, float(feature.ladder.progress) + seconds)
	if next_progress + 0.00000001 < duration:
		feature.ladder.progress = next_progress
		return ok("架梯／收梯中", {"complete": false})
	var point_guard: Variant = data.get_meta(&"region_point_deferring", Callable())
	if point_guard is Callable and point_guard.is_valid() and bool(point_guard.call()):
		feature.ladder.progress = next_progress
		return ok("", {"complete": false, "pending": true})
	var candidate := feature.duplicate(true)
	candidate.ladder.phase = "deployed" if str(feature.ladder.pending) == "deploy" else "folded"
	candidate.ladder.pending = ""
	candidate.ladder.progress = 0.0
	candidate.ladder.workers = []
	var guard := structure_change_guard(data, key, candidate, occupied, "ladder_complete")
	if not guard.ok: return guard
	var geometry := feature_geometry(data, candidate)
	if str(candidate.ladder.phase) == "deployed" and (not data.is_walkable(geometry.external_upper.cell) or data.effective_height(geometry.external_upper.cell) != int(feature.level) + WALL_RISE): return fail("UNREACHABLE", "原梯頂支承已失效")
	feature.ladder = candidate.ladder
	feature.status = "梯具已架設" if str(feature.ladder.phase) == "deployed" else "梯具已原地收起"
	_refresh_siege_ladder_tasks(data, key)
	Env.rebuild_indexes(data)
	return ok(str(feature.status), {"complete": true})

# Append to SiteRuntime. Structural callers must use housing_geometry_guard
# before their existing optional occupied callback short circuit.
static func house_layout(data: TerrainData, key: String) -> Dictionary:
	var feature: Dictionary = data.site.get("features", {}).get(key, {})
	if str(feature.get("kind", "")) != "house" or int(feature.get("layout_version", 0)) != BUILDING_LAYOUT_VERSION:
		return fail("NO_HOUSE", "需已知住宅布局")
	var entrance := int(feature.get("entrance", -1))
	var candidates := {}
	for pair: Dictionary in _building_entrances(data, feature.cells, int(feature.quarter)):
		var cell: Vector2i = pair.cell
		var index := data.index(cell)
		if not data.is_walkable(cell) or data.effective_height(cell) != int(feature.level) or int(data.feature_at[index]) != 0 or index == int(data.site.depot_cell): continue
		var occupied_entry := false
		for other_key: String in data.site.features:
			if other_key != key and int(data.site.features[other_key].get("entrance", -1)) == index: occupied_entry = true; break
		if not occupied_entry: candidates[index] = true
	var connected := {}
	var pending: Array[int] = []
	if candidates.has(entrance): connected[entrance] = true; pending.append(entrance)
	var head := 0
	while head < pending.size():
		var current := data.cell_from_index(pending[head])
		head += 1
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := current + direction
			if not data.contains(next): continue
			var index := data.index(next)
			if not candidates.has(index) or connected.has(index) or not data.can_step(current, next): continue
			connected[index] = true
			pending.append(index)
	var slots: Array[int] = []
	for pair: Dictionary in _building_entrances(data, feature.cells, int(feature.quarter)):
		var index := data.index(pair.cell)
		if index != entrance and connected.has(index): slots.append(index)
	return ok("住宅門前休息布局", {"id": key, "complete": str(feature.get("stage", "")) == "complete", "entry": data.cell_from_index(entrance), "slots": slots, "capacity": slots.size()})

static func _housing_in_use(data: TerrainData, key: String) -> bool:
	for registered: Dictionary in data.site.get("housing", {}).values():
		if str(registered.get("house_id", "")) == key: return true
	return false

static func housing_geometry_guard(before: TerrainData, after: TerrainData) -> Dictionary:
	var layouts := {}
	for registered: Dictionary in before.site.get("housing", {}).values():
		var key := str(registered.get("house_id", ""))
		if not layouts.has(key): layouts[key] = house_layout(after, key)
		var layout: Dictionary = layouts[key]
		if not layout.ok or not bool(layout.get("complete", false)) or not layout.slots.has(int(registered.get("cell", -1))): return fail("BUSY", "須保留原住戶住宅、門口通路與休息格")
	return ok()

# P2 candidate: append to the original SiteRuntime, never load as a second owner.
const FIRE_VERSION := 1
const FIRE_CONFIG_VERSION := "site_fire_v1"
const FIRE_HZ := 5
const FIRE_MAX_STEP := 2147483647
const FIRE_Q := 1024
const FIRE_EPS := 0.000000001

static func _fire_time_valid(action_time: float) -> bool:
	return is_finite(action_time) and action_time >= 0.0 and action_time * FIRE_HZ <= float(FIRE_MAX_STEP)

static func _fire_state(data: TerrainData, at: float) -> Dictionary:
	if not data.site.has("fire"):
		var completed := float(data.get_meta(&"fire_completed_action_end", at))
		data.site.fire = {"version": FIRE_VERSION, "config_version": FIRE_CONFIG_VERSION,
			"site_id": str(data.site.id), "step_index": floori(minf(at, completed) * FIRE_HZ + FIRE_EPS),
			"observed_action_end": completed, "receipt_floor": 0, "receipt_ids": {},
			"units": {}, "active": {}, "contacts": {}, "repair_generations": {}, "dirty": false}
	return data.site.fire

static func _fire_state_valid(data: TerrainData) -> bool:
	var state: Variant = data.site.get("fire")
	return state is Dictionary and int(state.get("version", 0)) == FIRE_VERSION \
		and str(state.get("config_version", "")) == FIRE_CONFIG_VERSION and str(state.get("site_id", "")) == str(data.site.id)

static func fire_save_guard(data: TerrainData) -> Dictionary:
	if data == null: return ok()
	if not data.get_meta(&"fire_boundary", {}).is_empty() or data.has_meta(&"fire_structure_step"):
		return fail("BUSY", "原火攻接觸／結構步進尚未完成")
	var raw: Variant = data.site.get("fire", {})
	if not raw is Dictionary: return fail("CORRUPT_FIRE_SNAPSHOT")
	if not raw.is_empty():
		var cursor: Variant = data.get_meta(&"fire_completed_action_end", raw.get("observed_action_end", -1.0))
		if not _fire_time_valid(cursor): return fail("INVALID_FIRE_BARRIER")
		var checked := capture_fire_snapshot(data, float(cursor))
		if checked.ok: return ok()
		var saved_check := validate_fire_snapshot(data, raw, float(cursor))
		if not saved_check.ok: return checked
	return ok()

static func _fire_unit_key(kind: String, original: String, part: String = "") -> String:
	return "resource:" + original if kind == "resource" else "feature:" + original + ":" + part

static func fire_generation(data: TerrainData, unit_key: String) -> int:
	return int(data.site.get("fire", {}).get("units", {}).get(unit_key, {}).get("generation", 1))

static func _fire_resource_descriptor(data: TerrainData, key: String, include_residue: bool = false) -> Dictionary:
	var resource := Env.resource(data, key)
	if resource.is_empty() or int(resource.kind) != Env.Kind.TIMBER or bool(resource.cleared) and not include_residue: return {}
	var cell := data.cell_from_index(int(resource.cell))
	if data.water_kind[int(resource.cell)] != 0: return {}
	return {"key": _fire_unit_key("resource", key), "kind": "resource", "resource": key,
		"profile": "TIMBER", "surface_id": "ground", "height": float(data.height_levels[int(resource.cell)]),
		"cells": resource.cells.duplicate(), "hazard_cells": [int(resource.cell)], "cell": cell,
		"fuel_max_q": int(resource.capacity) * FIRE_Q, "moisture": float(data.moisture[int(resource.cell)]) / 100.0,
		"rain_exposure": fire_point_rain_exposure(data, Vector3(cell.x + 0.5, cell.y + 0.5, float(data.height_levels[int(resource.cell)]) + 0.05)), "smoke_outdoor": true}

static func _fire_feature_descriptor(data: TerrainData, feature_id: String, part_id: String) -> Dictionary:
	var feature: Dictionary = data.site.get("features", {}).get(feature_id, {})
	if str(feature.get("stage", "")) != "complete" or int(feature.get("layout_version", 0)) != BUILDING_LAYOUT_VERSION \
		or not feature.get("parts", {}).has(part_id): return {}
	var geometry := feature_geometry(data, feature)
	var part: Dictionary = geometry.parts.get(part_id, {})
	if part.is_empty(): return {}
	var kind := str(feature.kind)
	var maximum := 0
	if int(feature.get("fire_layout_version", 0)) == FIRE_LAYOUT_VERSION:
		maximum = int(part.get("fuel_max_q", 0))
	elif kind == "house" and str(feature.get("variant", "standard")) == "standard" and part_id == "body":
		maximum = int(feature.get("cost", {}).get("wood", 0)) * FIRE_Q
	elif kind == "gate" and str(part.role) == "leaf": maximum = 4 * FIRE_Q
	elif kind in ["palisade", "wall_stairs"] and str(feature.get("material", "wood")) == "wood": maximum = 4 * FIRE_Q
	if maximum <= 0: return {} # Stone and unadmitted original assets never receive fuel.
	var hazard_cells: Array = part.cells.duplicate() if str(part.role) != "building" else [int(feature.entrance)]
	return {"key": _fire_unit_key("feature", feature_id, part_id), "kind": "feature", "feature": feature_id, "part": part_id,
		"profile": "WOOD_COMPONENT", "surface_id": "feature:" + feature_id + ":" + part_id,
		"height": float(part.height), "cells": part.cells.duplicate(), "hazard_cells": hazard_cells,
		"cell": data.cell_from_index(int(part.cells[0])), "fuel_max_q": maximum, "moisture": 0.0,
		"lower": float(part.get("lower", feature.level)), "upper": float(part.get("upper", part.height)),
		"rain_exposure": float(part.get("rain_exposure", 1.0)), "smoke_outdoor": bool(part.get("smoke_outdoor", true))}

static func _fire_descriptor(data: TerrainData, unit: Dictionary) -> Dictionary:
	if int(unit.get("debris_version", 0)) == FIRE_COLLAPSE_VERSION: return _fire_debris_descriptor(data, unit)
	return _fire_resource_descriptor(data, str(unit.resource), true) if str(unit.kind) == "resource" else \
		_fire_feature_descriptor(data, str(unit.feature), str(unit.part))

static func _fire_new_unit(descriptor: Dictionary) -> Dictionary:
	var unit := {"generation": 1, "kind": str(descriptor.kind), "profile": str(descriptor.profile),
		"surface_id": str(descriptor.surface_id), "height": float(descriptor.height), "heat": 0.0,
		"state": "DORMANT", "intensity": 0.0, "moisture": float(descriptor.moisture), "moisture_action": 0.0,
		"scorch": 0.0, "burn_remainder_q": 0.0, "fuel_remainder_q": 0, "residue_q": 0}
	if str(descriptor.kind) == "resource": unit.resource = str(descriptor.resource)
	else:
		unit.feature = str(descriptor.feature)
		unit.part = str(descriptor.part)
		unit.fuel_max_q = int(descriptor.fuel_max_q)
		unit.fuel_q = int(descriptor.fuel_max_q)
	return unit

static func _fire_unit(_data: TerrainData, state: Dictionary, descriptor: Dictionary) -> Dictionary:
	var key := str(descriptor.key)
	if not state.units.has(key): state.units[key] = _fire_new_unit(descriptor)
	return state.units[key]

static func _fire_fuel_q(data: TerrainData, unit: Dictionary) -> int:
	if str(unit.kind) == "feature": return int(unit.fuel_q)
	var resource := Env.resource(data, str(unit.resource))
	if resource.is_empty(): return 0
	return int(unit.get("residue_q", 0)) if bool(resource.cleared) else int(resource.remaining) * FIRE_Q + int(unit.fuel_remainder_q)

static func _fire_impact_descriptor(data: TerrainData, payload: Dictionary) -> Dictionary:
	if str(payload.type) == "structure":
		return _fire_feature_descriptor(data, str(payload.get("feature", "")), str(payload.get("part", "")))
	if str(payload.type) != "ground" or not payload.get("cell") is Vector2i or not data.contains(payload.cell): return {}
	var index := data.index(payload.cell)
	if data.water_kind[index] != 0: return {}
	var keys: Array = data.resources_at.get(index, []).duplicate()
	keys.sort()
	for key: String in keys:
		var descriptor := _fire_resource_descriptor(data, key)
		if not descriptor.is_empty(): return descriptor
	return {}

static func fire_receive_impact(data: TerrainData, payload: Dictionary) -> Dictionary:
	if data == null or data.site.is_empty() or str(payload.get("site_id", "")) != str(data.site.get("id", "")):
		return fail("STALE_SITE", "火箭接觸不屬於此原 Site")
	if not _building_integer(payload.get("projectile_id"), 1, 2147483647): return fail("INVALID_FIRE_EVENT")
	var sequence := int(payload.projectile_id)
	if str(payload.get("event_id", "")) != "arrow:%d" % sequence or not payload.get("type") is String:
		return fail("INVALID_FIRE_EVENT")
	for field: String in ["action_time", "remaining_heat_budget", "heat_rate", "max_seconds", "heat_transfer", "contact_scale"]:
		var value: Variant = payload.get(field)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0.0: return fail("INVALID_FIRE_EVENT")
	if float(payload.heat_transfer) > 1.0 or float(payload.contact_scale) > 1.0: return fail("INVALID_FIRE_EVENT")
	if not _fire_time_valid(float(payload.action_time)) or not _fire_time_valid(float(payload.action_time) + float(payload.max_seconds)): return fail("INVALID_FIRE_EVENT")
	if data.site.has("fire") and not _fire_state_valid(data): return fail("FIRE_VERSION")
	var state := _fire_state(data, float(payload.action_time))
	if sequence <= int(state.receipt_floor) or state.receipt_ids.has(sequence): return ok("重送已忽略", {"accepted": false, "duplicate": true})
	if float(payload.action_time) + FIRE_EPS < float(state.observed_action_end): return fail("STALE_FIRE_EVENT", "事件晚於其已提交動作區間")
	state.receipt_ids[sequence] = true
	var descriptor := _fire_impact_descriptor(data, payload)
	var amount := float(payload.remaining_heat_budget) * float(payload.heat_transfer) * float(payload.contact_scale)
	if descriptor.is_empty() or amount <= 0.0 or float(payload.heat_rate) <= 0.0 or float(payload.max_seconds) <= 0.0:
		return ok("原終止收據已消費；實際接觸沒有准入可燃物或可用熱量", {"accepted": false, "duplicate": false})
	var key := str(descriptor.key)
	if payload.has("target_generation") and int(payload.target_generation) != fire_generation(data, key):
		return ok("舊實體世代接觸已失效", {"accepted": false, "duplicate": false})
	var unit := _fire_unit(data, state, descriptor)
	if _fire_fuel_q(data, unit) <= 0: return ok("原燃料已耗盡", {"accepted": false, "duplicate": false})
	var event_id := str(payload.event_id)
	state.contacts[event_id] = {"event_id": event_id, "projectile_id": sequence, "unit_key": key,
		"generation": int(unit.generation), "start_action": float(payload.action_time),
		"end_action": float(payload.action_time) + float(payload.max_seconds), "budget": amount,
		"rate": float(payload.heat_rate) * float(payload.heat_transfer) * float(payload.contact_scale)}
	state.active[key] = true
	state.dirty = true
	return ok("原有限接觸待火勢邊界結算", {"accepted": true, "contact_id": event_id, "unit_key": key, "generation": int(unit.generation)})

static func _fire_has_contact(state: Dictionary, key: String) -> bool:
	for contact: Dictionary in state.contacts.values():
		if str(contact.unit_key) == key and float(contact.budget) > FIRE_EPS: return true
	return false

static func fire_unit_hot(data: TerrainData, key: String) -> bool:
	var state: Dictionary = data.site.get("fire", {})
	var unit: Dictionary = state.get("units", {}).get(key, {})
	return not unit.is_empty() and (float(unit.heat) > FIRE_EPS or _fire_has_contact(state, key))

static func _fire_pending_projectile(data: TerrainData, key: String) -> bool:
	if not data.has_meta(&"fire_pending_projectile_query"): return false
	var query: Variant = data.get_meta(&"fire_pending_projectile_query", Callable())
	if not query is Callable or not query.is_valid(): return true
	return bool(query.call(key))

static func fire_active(data: TerrainData) -> bool:
	var state: Dictionary = data.site.get("fire", {}) if data != null else {}
	return not state.get("contacts", {}).is_empty() or not state.get("active", {}).is_empty() or not state.get("smoke", {}).is_empty() or not state.get("collapse_warnings", {}).is_empty() or not state.get("structure_pending", {}).is_empty() or not state.get("inventory_pending", {}).is_empty()

static func fire_boundary_due(data: TerrainData, completed_action_end: float) -> bool:
	if data == null or not _fire_time_valid(completed_action_end): return false
	var previous := float(data.get_meta(&"fire_completed_action_end", data.site.get("fire", {}).get("observed_action_end", 0.0)))
	if not _fire_time_valid(previous): return false
	return floori(completed_action_end * FIRE_HZ + FIRE_EPS) > floori(previous * FIRE_HZ + FIRE_EPS)

static func fire_begin_boundary(data: TerrainData, completed_action_end: float, force_original_point: bool = false) -> Dictionary:
	if data == null or not _fire_time_valid(completed_action_end): return fail("INVALID_TIME")
	if not data.get_meta(&"fire_boundary", {}).is_empty(): return fail("BUSY", "原火勢完成屏障仍未提交")
	if not fire_boundary_due(data, completed_action_end) and not force_original_point: return ok()
	data.set_meta(&"fire_boundary", {"site_id": str(data.site.id), "action_end": completed_action_end, "resources": [], "features": [], "flushing": false})
	return ok()

static func _fire_work_pending(data: TerrainData, worker: Dictionary) -> bool:
	for completion: Dictionary in data.get_meta(&"fire_boundary", {}).get("resources", []):
		if is_same(completion.worker, worker): return true
	for completion: Dictionary in data.get_meta(&"fire_boundary", {}).get("features", []):
		if is_same(completion.worker, worker): return true
	return false

static func _fire_defer_resource_completion(data: TerrainData, worker: Dictionary, cargo: Dictionary, key: String,
		cell: Vector2i, action: String, carry_limit: int, manual: bool) -> bool:
	var boundary: Dictionary = data.get_meta(&"fire_boundary", {})
	var resource := Env.resource(data, key)
	var region_point: Variant = data.get_meta(&"region_point_deferring", Callable())
	var point_pending: bool = region_point is Callable and region_point.is_valid() and bool(region_point.call())
	if boundary.is_empty() or resource.is_empty() or (not point_pending and (int(resource.kind) != Env.Kind.TIMBER or action not in ["harvest", "clear", "restore"])): return false
	if _fire_work_pending(data, worker): return true
	boundary.resources.append({"worker": worker, "cargo": cargo, "key": key, "cell": cell, "action": action,
		"carry_limit": carry_limit, "manual": manual, "generation": fire_generation(data, _fire_unit_key("resource", key))})
	return true

static func _fire_defer_feature_completion(data: TerrainData, worker: Dictionary, cargo: Dictionary, key: String,
		job: Dictionary, occupied: Callable, carry_limit: int, worker_faction: int) -> bool:
	var boundary: Dictionary = data.get_meta(&"fire_boundary", {})
	if boundary.is_empty() or bool(boundary.flushing): return false
	if _fire_work_pending(data, worker): return true
	boundary.features.append({"worker": worker, "cargo": cargo, "key": key, "job": job,
		"target": str(worker.target), "action": str(worker.action), "cell": data.cell_from_index(int(worker.cell)),
		"occupied": occupied, "carry_limit": carry_limit, "worker_faction": worker_faction})
	return true

static func fire_finish_boundary(data: TerrainData, completed_action_end: float, closed_projectile_prefix: int,
		damage_sink: Callable = Callable(), resource_owner_guard: Callable = Callable()) -> Dictionary:
	var boundary: Dictionary = data.get_meta(&"fire_boundary", {})
	if not boundary.is_empty() and (str(boundary.site_id) != str(data.site.id) or absf(float(boundary.action_end) - completed_action_end) > FIRE_EPS):
		return fail("STALE_FIRE_BOUNDARY")
	if (not boundary.get("resources", []).is_empty() or not boundary.get("features", []).is_empty()) and not resource_owner_guard.is_valid():
		return fail("BUSY", "原採集完成屏障缺少本人／持有者重驗")
	var advanced := fire_advance(data, completed_action_end, closed_projectile_prefix, damage_sink)
	if not advanced.ok: return advanced
	boundary["flushing"] = true
	var results: Array[Dictionary] = []
	for completion: Dictionary in boundary.get("resources", []):
		var worker: Dictionary = completion.worker
		if str(worker.get("target", "")) != str(completion.key) or str(worker.get("action", "")) != str(completion.action) \
			or fire_generation(data, _fire_unit_key("resource", str(completion.key))) != int(completion.generation) \
			or not bool(resource_owner_guard.call(worker, completion.cargo, completion.cell, bool(completion.manual))):
			results.append(fail("STALE_WORK", "原人物、工作或來源已變；沒有向舊 cargo 寫入物資"))
			continue
		var result := harvest(data, str(completion.key), completion.cell, completion.cargo, str(completion.action), false, int(completion.carry_limit))
		results.append(result)
		if bool(completion.manual): data.site.notices.append(str(result.message))
		else: worker.status = str(result.message)
		if result.ok:
			worker.progress = 0.0
			worker.target = ""
			if not bool(completion.manual): worker.mode = "idle"
	for completion: Dictionary in boundary.get("features", []):
		var worker: Dictionary = completion.worker
		var feature: Dictionary = data.site.features.get(str(completion.key), {})
		var job: Dictionary = feature.get("repair", {}) if str(completion.action) == "repair" else feature.get("pending_build", feature)
		if not is_same(job, completion.job) or str(worker.get("target", "")) != str(completion.target) \
			or str(worker.get("action", "")) != str(completion.action) \
			or not bool(resource_owner_guard.call(worker, completion.cargo, completion.cell, false)):
			continue
		# The original transaction repeats its cold/generation/structure guards.
		# Zero work time cannot charge or earn the same labor a second time.
		_feature_work(data, str(completion.key), 0.0, completion.occupied, Callable(), worker, completion.cargo,
			int(completion.carry_limit), int(completion.worker_faction))
	data.remove_meta(&"fire_boundary")
	data.set_meta(&"fire_completed_action_end", completed_action_end)
	advanced["resource_completions"] = results
	return advanced

static func _fire_resource_edges(data: TerrainData, descriptor: Dictionary) -> Array[Dictionary]:
	var edges: Array[Dictionary] = []
	if str(descriptor.kind) != "resource": return edges
	if bool(Env.resource(data, str(descriptor.resource)).get("cleared", true)): return edges
	var from: Vector2i = descriptor.cell
	var from_index := data.index(from)
	if data.feature_at[from_index] != 0 or data.water_kind[from_index] != 0: return edges
	var ramps := data.navigation_ramps()
	for direction in range(TerrainData.DIRECTIONS.size()):
		var to := from + TerrainData.DIRECTIONS[direction]
		if not data.contains(to): continue
		var index := data.index(to)
		if data.height_levels[from_index] != data.height_levels[index] or data.feature_at[index] != 0 or data.water_kind[index] != 0: continue
		if (ramps[from_index] & (1 << (direction + 4))) != 0 or (ramps[index] & (1 << (((direction + 2) % 4) + 4))) != 0: continue
		var keys: Array = data.resources_at.get(index, []).duplicate()
		keys.sort()
		for key: String in keys:
			var other := _fire_resource_descriptor(data, key)
			if not other.is_empty() and str(other.key) != str(descriptor.key) and int(Env.resource(data, key).cell) == index:
				edges.append(other)
	return edges

static func fire_hazard_at(data: TerrainData, cell: Vector2i, surface_id: String = "ground") -> float:
	if data == null or not data.contains(cell): return 0.0
	var snapshot := fire_hazard_snapshot(data)
	var risk := 0.0
	for entry: Dictionary in snapshot.cells.get(data.index(cell), []):
		if surface_id == "ground" or surface_id == str(entry.surface_id): risk += float(entry.risk)
	return risk

static func fire_advance(data: TerrainData, completed_action_end: float, closed_projectile_prefix: int,
		damage_sink: Callable = Callable()) -> Dictionary:
	if data == null or not _fire_time_valid(completed_action_end) or closed_projectile_prefix < 0 or closed_projectile_prefix > 2147483647: return fail("INVALID_TIME")
	if bool(data.site.get("paused", false)): return fail("PAUSED_SITE")
	if not data.site.has("fire"):
		data.set_meta(&"fire_completed_action_end", completed_action_end)
		return ok("沒有原火勢", {"boundaries": 0})
	if not _fire_state_valid(data): return fail("FIRE_VERSION")
	var state: Dictionary = data.site.fire
	if completed_action_end + FIRE_EPS < float(state.observed_action_end) or closed_projectile_prefix < int(state.receipt_floor): return fail("STALE_FIRE_BOUNDARY")
	var target_step := floori(completed_action_end * FIRE_HZ + FIRE_EPS)
	var steps := 0
	while int(state.step_index) < target_step:
		var stepped := _fire_step(data, state, int(state.step_index) + 1, damage_sink)
		if not stepped.ok: return stepped
		steps += 1
	state.observed_action_end = completed_action_end
	state.receipt_floor = closed_projectile_prefix
	for sequence: int in state.receipt_ids.keys():
		if sequence <= closed_projectile_prefix: state.receipt_ids.erase(sequence)
	data.set_meta(&"fire_completed_action_end", completed_action_end)
	return ok("原火勢邊界完成", {"boundaries": steps, "step_index": int(state.step_index), "active": state.active.size()})

static func _fire_step(data: TerrainData, state: Dictionary, step_index: int, damage_sink: Callable) -> Dictionary:
	var dt := 1.0 / FIRE_HZ
	var begin := float(step_index - 1) / FIRE_HZ
	var end := float(step_index) / FIRE_HZ
	var old := {}
	var descriptors := {}
	var incoming := {}
	var outgoing := {}
	var contacts: Dictionary = state.contacts.duplicate(true)
	var suppression := _fire_suppression_inputs(data, state, begin, end)
	var ids: Array = contacts.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return int(contacts[a].projectile_id) < int(contacts[b].projectile_id))
	var keys: Array = state.active.keys()
	keys.sort()
	for key: String in keys:
		old[key] = state.units[key].duplicate(true)
		descriptors[key] = _fire_descriptor(data, old[key])
	for event_id: String in ids:
		var contact: Dictionary = contacts[event_id]
		var key := str(contact.unit_key)
		var unit: Dictionary = state.units.get(key, {})
		if unit.is_empty() or int(unit.generation) != int(contact.generation) or _fire_fuel_q(data, unit) <= 0 \
			or _fire_descriptor(data, unit).is_empty():
			contacts.erase(event_id)
			continue
		var overlap := maxf(0.0, minf(end, float(contact.end_action)) - maxf(begin, float(contact.start_action)))
		var dose := minf(float(contact.budget), float(contact.rate) * overlap)
		contact.budget = maxf(0.0, float(contact.budget) - dose)
		incoming[key] = float(incoming.get(key, 0.0)) + dose
		if end + FIRE_EPS >= float(contact.end_action) or float(contact.budget) <= FIRE_EPS: contacts.erase(event_id)
	# Only old burning units distribute heat. A newly reached neighbor is read
	# as its original dormant state; it cannot become a second source this step.
	for key: String in keys:
		var unit: Dictionary = old[key]
		var descriptor: Dictionary = descriptors[key]
		if float(unit.intensity) <= 0.0 or descriptor.is_empty(): continue
		var profile := SiteCombatRules.fire_profile(str(unit.profile))
		var edges: Array[Dictionary] = []
		for proposed: Dictionary in _fire_resource_edges(data, descriptor) + _fire_feature_edges(data, descriptor):
			var existing: Dictionary = state.units.get(str(proposed.key), {})
			if _fire_fuel_q(data, existing if not existing.is_empty() else _fire_new_unit(proposed)) > 0:
				edges.append(proposed)
		if edges.is_empty(): continue
		var amount := minf(float(unit.heat), float(profile.spread_rate) * float(unit.intensity) * dt)
		outgoing[key] = amount
		var edge_weights := {}
		var weight_sum := 0.0
		for other: Dictionary in edges:
			var weight := fire_wind_weight(data, descriptor.cell, other.cell, begin, end)
			edge_weights[str(other.key)] = weight
			weight_sum += weight
		for other: Dictionary in edges:
			var destination := str(other.key)
			if not old.has(destination):
				var registered: Dictionary = state.units.get(destination, _fire_new_unit(other))
				old[destination] = registered.duplicate(true)
				descriptors[destination] = other
			incoming[destination] = float(incoming.get(destination, 0.0)) + amount * float(edge_weights[destination]) / weight_sum
	keys = old.keys()
	keys.sort()
	var next := {}
	var resource_changes := {}
	var damage := _fire_pending_damage(data, state)
	for key: String in keys:
		var previous: Dictionary = old[key]
		var unit: Dictionary = previous.duplicate(true)
		var descriptor: Dictionary = descriptors[key]
		var profile := SiteCombatRules.fire_profile(str(unit.profile))
		if profile.is_empty(): return fail("FIRE_PROFILE")
		var fuel := _fire_fuel_q(data, previous)
		var demand := float(profile.burn_rate_q) * float(previous.intensity) * dt + float(previous.burn_remainder_q)
		var burned := mini(fuel, floori(demand + FIRE_EPS))
		unit.burn_remainder_q = maxf(0.0, demand - floorf(demand + FIRE_EPS)) if fuel > burned else 0.0
		var remaining := fuel - burned
		if str(unit.kind) == "resource":
			var resource := Env.resource(data, str(unit.resource))
			if resource.is_empty(): return fail("STALE_FIRE_OWNER")
			if bool(resource.cleared): unit.residue_q = remaining
			else:
				unit.fuel_remainder_q = remaining % FIRE_Q
				var whole := floori(float(remaining) / FIRE_Q)
				if whole != int(resource.remaining):
					var fields := {"remaining": whole}
					if int(resource.recover) > 0 and int(resource.next_recovery) < 0: fields.next_recovery = ceili(now(data)) + int(resource.recover)
					resource_changes[str(unit.resource)] = fields
		else: unit.fuel_q = remaining
		unit.moisture = fire_unit_moisture(data, previous, descriptor, begin)
		var cooling := float(profile.cooling_rate) * (1.0 + float(profile.moisture_cooling) * float(unit.moisture)) * dt
		cooling += fire_rain_integral(data, begin, end) * clampf(float(descriptor.get("rain_exposure", 1.0)), 0.0, 1.0) * float(SiteCombatRules.fire_environment_profile().rain_cooling_per_second)
		unit.heat = clampf(float(previous.heat) + float(incoming.get(key, 0.0)) + burned * float(profile.heat_per_q)
			- float(outgoing.get(key, 0.0)) - cooling - float(suppression.cooling.get(key, 0.0)) + float(suppression.heating.get(key, 0.0)), 0.0, float(profile.heat_limit))
		unit.moisture = clampf(fire_unit_moisture(data, previous, descriptor, end)
			+ float(suppression.moisture.get(key, 0.0)), 0.0, 1.0)
		unit.moisture_action = end
		var ignition := float(profile.ignition_heat) * (1.0 + float(profile.moisture_ignition) * float(unit.moisture))
		var sustain := float(profile.sustain_heat)
		unit.intensity = 0.0
		if remaining > 0 and (float(unit.heat) + FIRE_EPS >= ignition or str(previous.state) == "BURNING" and float(unit.heat) + FIRE_EPS >= sustain):
			unit.state = "BURNING"
			unit.intensity = clampf((float(unit.heat) - sustain) / maxf(FIRE_EPS, ignition - sustain), 0.25, 1.0)
		elif float(unit.heat) > FIRE_EPS:
			unit.state = "EMBERS" if remaining > 0 and str(previous.state) in ["BURNING", "EMBERS"] else ("COOLING" if remaining == 0 else "HEATING")
			if str(unit.state) == "EMBERS": unit.intensity = float(profile.ember_intensity)
		else:
			unit.heat = 0.0
			unit.state = "DORMANT"
		var maximum := int(descriptor.get("fuel_max_q", previous.get("fuel_max_q", FIRE_Q)))
		unit.scorch = clampf(float(previous.scorch) + float(burned) / maxi(1, maximum), 0.0, 1.0)
		if str(unit.kind) == "feature" and burned > 0 and float(profile.damage_per_q) > 0.0 and not descriptor.is_empty():
			var feature: Dictionary = data.site.features.get(str(unit.feature), {})
			if float(feature.get("parts", {}).get(str(unit.part), {}).get("hp", 0.0)) > 0.0:
				_fire_add_structure_damage(data, damage, str(unit.feature), str(unit.part), burned * float(profile.damage_per_q), burned * float(profile.damage_per_q))
		next[key] = unit
	var inventory_preview := _fire_inventory_preview(data, state, old, step_index)
	_fire_due_collapses(data, state, step_index, damage)
	var queued: Dictionary = {}
	var smoke := _fire_smoke_preview(data, state, old, descriptors, begin, end)
	if not smoke.ok: return smoke
	if not damage.is_empty():
		if not damage_sink.is_valid(): return fail("BUSY", "火傷須經原結構批次提交")
		data.set_meta(&"fire_structure_step", step_index)
		var reply: Variant = damage_sink.call(damage, {}, 0)
		data.remove_meta(&"fire_structure_step")
		if not reply is Dictionary or not bool(reply.get("ok", false)): return fail("FIRE_DAMAGE_REJECTED", "原結構批次未接受，火勢邊界保留")
		queued = reply
	var rebuild := false
	var resource_keys: Array = resource_changes.keys()
	resource_keys.sort()
	for key: String in resource_keys:
		Env.change(data, key, resource_changes[key])
		rebuild = true
	for key: String in keys:
		state.units[key] = next[key]
		if float(next[key].heat) > FIRE_EPS or _fire_has_contact({"contacts": contacts}, key): state.active[key] = true
		else: state.active.erase(key)
	state.contacts = contacts
	if state.has("suppression_pending"): state.suppression_pending = suppression.pending
	state.smoke = smoke.smoke
	state.step_index = step_index
	if not damage.is_empty() or state.has("structure_pending"): state.structure_pending = damage.duplicate(true)
	var inventory_results := _fire_commit_inventory_preview(data, state, inventory_preview)
	data.set_meta(&"fire_inventory_results", inventory_results)
	for part_key: String in queued.get("results", {}):
		if damage.has(part_key): fire_structure_outcome(data, damage[part_key], queued.results[part_key])
	fire_hazard_invalidate(data)
	if not keys.is_empty() or not state.get("smoke", {}).is_empty() or not smoke.smoke.is_empty(): state.dirty = true
	if rebuild:
		Env.rebuild_indexes(data)
		rebuild_water(data)
	return ok()

static func _fire_resource_cleared(data: TerrainData, resource_key: String) -> void:
	fire_hazard_invalidate(data)
	var state: Dictionary = data.site.get("fire", {})
	var key := _fire_unit_key("resource", resource_key)
	var unit: Dictionary = state.get("units", {}).get(key, {})
	if unit.is_empty(): return
	# Original clear is only legal once original remaining is zero. The sole
	# fractional remainder moves to this original resource's finite residue.
	unit.residue_q = int(unit.get("residue_q", 0)) + int(unit.fuel_remainder_q)
	unit.fuel_remainder_q = 0
	unit.generation = int(unit.generation) + 1
	var supplied := _fire_has_contact(state, key)
	for event_id: String in state.contacts.keys():
		if str(state.contacts[event_id].unit_key) != key: continue
		# Transfer this already-consumed receipt to the finite residue. Replayed
		# old events cannot create another contact or refill its finite budget.
		if int(unit.residue_q) > 0: state.contacts[event_id].generation = int(unit.generation)
		else: state.contacts.erase(event_id)
	state.dirty = true
	if float(unit.heat) <= FIRE_EPS and not supplied:
		unit.residue_q = 0 # Cold discarded fractional material is never usable wood.
		state.active.erase(key)

## Reclassify the same cold fractional fuel when its original cleared source is restored.
## Preview is read-only; a whole residue quantum cannot become free usable biomass.
static func _fire_resource_restored(data: TerrainData, resource_key: String, preview: bool = false) -> Dictionary:
	var resource := Env.resource(data, resource_key)
	if resource.is_empty() or not bool(resource.cleared) or int(resource.remaining) != 0:
		return fail("INVALID", "原復育來源須已清除且零量")
	if _fire_regeneration_blocked(data, resource_key): return fail("FIRE_HOT", "原來源仍熱或有待解決火箭")
	var state: Dictionary = data.site.get("fire", {})
	var unit: Dictionary = state.get("units", {}).get(_fire_unit_key("resource", resource_key), {})
	if unit.is_empty(): return ok()
	var residue := int(unit.get("residue_q", 0))
	if residue < 0 or residue >= FIRE_Q or int(unit.get("fuel_remainder_q", 0)) != 0:
		return fail("INVALID_FIRE_FUEL", "原冷餘料不能轉成完整可採生物量")
	if not preview and residue > 0:
		unit.fuel_remainder_q = residue
		unit.residue_q = 0
		state.dirty = true
	return ok()

static func _fire_regeneration_blocked(data: TerrainData, resource_key: String) -> bool:
	var key := _fire_unit_key("resource", resource_key)
	return fire_unit_hot(data, key) or _fire_pending_projectile(data, key)

static func _fire_resource_regenerated(data: TerrainData, resource_key: String, old_remaining: int, target_remaining: int, capacity: int) -> int:
	var state: Dictionary = data.site.get("fire", {})
	var unit: Dictionary = state.get("units", {}).get(_fire_unit_key("resource", resource_key), {})
	if unit.is_empty(): return target_remaining
	var old_fuel := old_remaining * FIRE_Q + int(unit.fuel_remainder_q)
	var new_fuel := mini(capacity * FIRE_Q, old_fuel + maxi(0, target_remaining - old_remaining) * FIRE_Q)
	unit.fuel_remainder_q = new_fuel % FIRE_Q
	if old_fuel == 0 and new_fuel > 0: unit.generation = int(unit.generation) + 1
	unit.residue_q = 0
	state.dirty = true
	return floori(float(new_fuel) / FIRE_Q)

static func _fire_feature_hot(data: TerrainData, feature_id: String) -> bool:
	var feature: Dictionary = data.site.get("features", {}).get(feature_id, {})
	for part_id: String in feature.get("parts", {}):
		if _fire_pending_projectile(data, _fire_unit_key("feature", feature_id, part_id)): return true
	var state: Dictionary = data.site.get("fire", {})
	for key: String in state.get("units", {}):
		var unit: Dictionary = state.units[key]
		if str(unit.kind) == "feature" and str(unit.feature) == feature_id and (fire_unit_hot(data, key) or state.get("collapse_warnings", {}).has(key) or state.get("structure_pending", {}).has(feature_id + "|" + str(unit.part))): return true
	return false

static func _fire_repair_guard(data: TerrainData, feature_id: String, part_id: String, completion: bool = false) -> Dictionary:
	var key := _fire_unit_key("feature", feature_id, part_id)
	if fire_unit_hot(data, key) or _fire_pending_projectile(data, key) or data.site.get("fire", {}).get("collapse_warnings", {}).has(key): return fail("BUSY", "原部件仍熱、接觸供熱、有在途火箭或待倒塌；已備料與進度保留")
	var state: Dictionary = data.site.get("fire", {})
	if completion and int(state.get("repair_generations", {}).get(key, 1)) != fire_generation(data, key):
		return fail("STALE_REPAIR", "原已付修理的部件世代已改變")
	return ok()

static func _fire_repair_started(data: TerrainData, feature_id: String, part_id: String) -> void:
	var descriptor := _fire_feature_descriptor(data, feature_id, part_id)
	if descriptor.is_empty() or not data.site.has("fire"): return
	var state: Dictionary = data.site.fire
	var unit := _fire_unit(data, state, descriptor)
	state.repair_generations[str(descriptor.key)] = int(unit.generation)

static func _fire_repair_finished(data: TerrainData, feature_id: String, part_id: String, old_hp: float,
		new_hp: float, maximum_hp: float, paid: Dictionary, full_cost: Dictionary) -> void:
	fire_hazard_invalidate(data)
	var state: Dictionary = data.site.get("fire", {})
	var key := _fire_unit_key("feature", feature_id, part_id)
	var unit: Dictionary = state.get("units", {}).get(key, {})
	if unit.is_empty(): return
	var full_wood := int(full_cost.get("wood", 0))
	var delta := 0
	if full_wood > 0 and maximum_hp > 0.0:
		delta = mini(int(unit.fuel_max_q) - int(unit.fuel_q), mini(floori(int(unit.fuel_max_q) * maxf(0.0, new_hp - old_hp) / maximum_hp),
			floori(float(unit.fuel_max_q) * int(paid.get("wood", 0)) / full_wood)))
	unit.fuel_q = int(unit.fuel_q) + maxi(0, delta)
	if old_hp <= 0.0 and new_hp > 0.0:
		_fire_retire_collapse_reference(state, key)
		unit.erase("debris_version")
		unit.erase("standing_generation")
		var descriptor := _fire_feature_descriptor(data, feature_id, part_id)
		unit.surface_id = str(descriptor.surface_id)
		unit.height = float(descriptor.height)
		unit.generation = int(unit.generation) + 1
		for event_id: String in state.contacts.keys():
			if str(state.contacts[event_id].unit_key) == key: state.contacts.erase(event_id)
	state.repair_generations.erase(key)
	state.dirty = true

static func _fire_feature_removed(data: TerrainData, feature_id: String, retained_parts: Dictionary = {}) -> void:
	fire_hazard_invalidate(data)
	var state: Dictionary = data.site.get("fire", {})
	for key: String in state.get("units", {}):
		var unit: Dictionary = state.units[key]
		if str(unit.kind) != "feature" or str(unit.feature) != feature_id: continue
		if retained_parts.has(str(unit.part)): continue
		_fire_retire_collapse_reference(state, key)
		unit.erase("debris_version")
		unit.erase("standing_generation")
		unit.generation = int(unit.generation) + 1
		unit.fuel_q = 0
		unit.heat = 0.0
		unit.intensity = 0.0
		unit.state = "DORMANT"
		state.active.erase(key)
		state.repair_generations.erase(key)
		for event_id: String in state.contacts.keys():
			if str(state.contacts[event_id].unit_key) == key: state.contacts.erase(event_id)
		state.dirty = true

static func _fire_feature_completed(data: TerrainData, feature_id: String, previous: Dictionary, paid: Dictionary) -> void:
	fire_hazard_invalidate(data)
	if not data.site.has("fire"): return
	var state: Dictionary = data.site.fire
	var feature: Dictionary = data.site.features[feature_id]
	var paid_by_part := _fire_part_allocation(feature, maxi(0, int(paid.get("wood", 0))) * FIRE_Q) if int(feature.get("fire_layout_version", 0)) == FIRE_LAYOUT_VERSION else {}
	for part_id: String in feature.get("parts", {}):
		var descriptor := _fire_feature_descriptor(data, feature_id, part_id)
		if descriptor.is_empty(): continue
		var key := str(descriptor.key)
		if not state.units.has(key):
			_fire_unit(data, state, descriptor)
			continue
		var unit: Dictionary = state.units[key]
		var new_maximum := int(descriptor.fuel_max_q)
		if previous.is_empty() or not previous.get("parts", {}).has(part_id):
			var rebuilt := _fire_new_unit(descriptor)
			rebuilt.generation = int(unit.generation) + 1
			rebuilt.fuel_q = mini(new_maximum, int(paid_by_part.get(part_id, maxi(0, int(paid.get("wood", 0))) * FIRE_Q)))
			state.units[key] = rebuilt
			state.dirty = true
			continue
		var added := mini(maxi(0, new_maximum - int(unit.fuel_max_q)), int(paid_by_part.get(part_id, maxi(0, int(paid.get("wood", 0))) * FIRE_Q)))
		unit.fuel_max_q = new_maximum
		unit.fuel_q = mini(new_maximum, int(unit.fuel_q) + added)
		if building_grade(previous) != building_grade(feature) or previous.get("cells", []) != feature.cells or previous.get("parts", {}).get(part_id, {}) != feature.parts[part_id]:
			unit.generation = int(unit.generation) + 1
		state.dirty = true


# P3-A disposable projection. No fuel/HP/save authority and no time advancement.
static func fire_hazard_invalidate(data: TerrainData) -> void:
	if data != null: data.remove_meta(&"fire_hazard_projection")

static func fire_hazard_snapshot(data: TerrainData) -> Dictionary:
	if data == null: return {"cells": {}, "chunks": {}, "revision": 0}
	var state: Dictionary = data.site.get("fire", {})
	var cached: Dictionary = data.get_meta(&"fire_hazard_projection", {})
	var step := int(state.get("step_index", -1))
	if not cached.is_empty() and is_same(cached.state, state) and int(cached.step) == step \
		and int(cached.environment) == data.environment_revision and int(cached.navigation) == data.navigation_revision:
		return cached.snapshot
	var cells := {}
	var chunks := {}
	var signatures := {}
	var keys: Array = state.get("active", {}).keys()
	for key: String in state.get("collapse_warnings", {}):
		if not keys.has(key): keys.append(key)
	keys.sort()
	for key: String in keys:
		var unit: Dictionary = state.units[key]
		var descriptor := _fire_descriptor(data, unit)
		if descriptor.is_empty() and str(unit.kind) == "resource":
			var resource := Env.resource(data, str(unit.resource))
			if not resource.is_empty(): descriptor = {"hazard_cells": [int(resource.cell)], "height": float(data.height_levels[int(resource.cell)])}
		if descriptor.is_empty(): continue
		var risk := maxf(float(unit.intensity), minf(0.2, float(unit.heat) / 500.0))
		var thermal_risk := risk
		if state.get("collapse_warnings", {}).has(key): risk = maxf(risk, 0.75)
		if risk <= FIRE_EPS: continue
		var lower := float(descriptor.height)
		if str(unit.kind) == "feature": lower = float(descriptor.get("lower", data.site.features.get(str(unit.feature), {}).get("level", lower)))
		var upper := maxf(lower, float(descriptor.get("upper", descriptor.height))) + float(SiteCombatRules.FIRE_BODY.plume_height)
		var thermal_lower := lower
		if state.get("collapse_warnings", {}).has(key): lower = float(data.site.features.get(str(unit.get("feature", "")), {}).get("level", lower))
		for value: int in descriptor.hazard_cells:
			if not cells.has(value): cells[value] = []
			cells[value].append({"key": key, "surface_id": str(unit.surface_id), "risk": risk, "thermal_risk": thermal_risk, "thermal_lower": thermal_lower, "thermal_upper": upper, "lower": lower, "upper": upper, "ground": str(unit.kind) == "resource" or int(unit.get("debris_version", 0)) == FIRE_COLLAPSE_VERSION})
			var cell := data.cell_from_index(value)
			# One-cell motion admission padding, expressed as occupied chunk keys.
			for y in range(floori(float(cell.y - 1) / 16.0), floori(float(cell.y + 1) / 16.0) + 1):
				for x in range(floori(float(cell.x - 1) / 16.0), floori(float(cell.x + 1) / 16.0) + 1): chunks[Vector2i(x, y)] = true
	for value: int in cells:
		var entries: Array = cells[value]
		var heights: Array[float] = []
		var surfaces := {}
		var total := 0.0
		for entry: Dictionary in entries:
			heights.append(float(entry.lower)); heights.append(float(entry.upper))
			total += float(entry.risk)
			surfaces[str(entry.surface_id)] = float(surfaces.get(str(entry.surface_id), 0.0)) + float(entry.risk)
		signatures[str(value) + ":ground"] = SiteCombatRules.fire_risk_band(total)
		for surface: String in surfaces: signatures[str(value) + ":" + surface] = SiteCombatRules.fire_risk_band(float(surfaces[surface]))
		heights.sort()
		for index in range(heights.size() - 1):
			if heights[index + 1] <= heights[index]: continue
			var height := (heights[index] + heights[index + 1]) * 0.5
			var risk := 0.0
			for entry: Dictionary in entries:
				if height >= float(entry.lower) and height <= float(entry.upper): risk += float(entry.risk)
			signatures["%d:%.6f:%.6f" % [value, heights[index], heights[index + 1]]] = SiteCombatRules.fire_risk_band(risk)
	var previous: Dictionary = data.get_meta(&"fire_hazard_bands", {})
	var revision := int(data.get_meta(&"fire_hazard_revision", 0))
	if previous != signatures:
		revision += 1
		data.set_meta(&"fire_hazard_bands", signatures)
		data.set_meta(&"fire_hazard_revision", revision)
	var snapshot := {"cells": cells, "chunks": chunks, "revision": revision, "width": data.size.x,
		"completed_action_end": float(step) / float(FIRE_HZ) if step >= 0 else 0.0}
	data.set_meta(&"fire_hazard_projection", {"state": state, "step": step, "environment": data.environment_revision,
		"navigation": data.navigation_revision, "snapshot": snapshot})
	return snapshot

static func fire_hazard_revision(data: TerrainData) -> int:
	return int(fire_hazard_snapshot(data).revision)

static func fire_exposure_at(snapshot: Dictionary, cell: Vector2i, height: float, ground_offset: float = 0.0) -> float:
	var value := cell.y * int(snapshot.get("width", 0)) + cell.x
	var risk := 0.0
	for entry: Dictionary in snapshot.cells.get(value, []):
		# Navigation asks at the cell centre (offset0). Motion supplies the exact
		# original natural slope offset, keeping ground fire attached to that
		# slope while an independent bridge/roof height remains isolated.
		var shift := ground_offset if bool(entry.get("ground", false)) else 0.0
		if height >= float(entry.get("thermal_lower", entry.lower)) + shift - FIRE_EPS and height <= float(entry.get("thermal_upper", entry.upper)) + shift + FIRE_EPS: risk += float(entry.get("thermal_risk", entry.risk))
	return risk

# P4: extend the same Runtime finite work transaction with IGNITE. This remains
# one original holder debit and one bounded input queue on the original fire state.

static func fire_work_target(data: TerrainData, key: String, mode: String = "SUPPRESS", generation: int = -1) -> Dictionary:
	if data == null or data.site.is_empty() or mode not in ["SUPPRESS", "IGNITE"]: return fail("NO_TARGET")
	if data.site.has("fire") and not _fire_state_valid(data): return fail("FIRE_VERSION")
	var state: Dictionary = data.site.get("fire", {})
	var unit: Dictionary = state.get("units", {}).get(key, {})
	var descriptor := {}
	if not unit.is_empty(): descriptor = _fire_descriptor(data, unit)
	elif mode == "IGNITE":
		if key.begins_with("resource:"): descriptor = _fire_resource_descriptor(data, key.trim_prefix("resource:"))
		elif key.begins_with("feature:"):
			var parts := key.split(":", true, 2)
			if parts.size() == 3: descriptor = _fire_feature_descriptor(data, parts[1], parts[2])
	if descriptor.is_empty(): return fail("TARGET_INVALIDATED")
	var current_generation := int(unit.get("generation", 1))
	if generation >= 0 and current_generation != generation: return fail("TARGET_INVALIDATED")
	var original: Dictionary = unit if not unit.is_empty() else _fire_new_unit(descriptor)
	var fuel := _fire_fuel_q(data, original)
	if mode == "IGNITE" and fuel <= 0: return fail("NO_FUEL")
	var reserved := 0.0
	for input: Dictionary in state.get("suppression_pending", []):
		if str(input.key) == key and int(input.generation) == current_generation and str(input.get("mode", "SUPPRESS")) == mode:
			reserved += float(input.remaining_q) * float(input.get("heating_per_q", 0.0) if mode == "IGNITE" else input.cooling_per_q)
	var available := maxf(0.0, float(original.heat) - reserved)
	if mode == "SUPPRESS" and float(original.intensity) > 0.0 and fuel > 0:
		# Original old-buffer fuel burns before cooling at the next 5Hz boundary.
		# Reserve its finite self-heat too, or wooden embers never reach zero.
		var profile := SiteCombatRules.fire_profile(str(original.profile))
		if profile.is_empty(): return fail("FIRE_PROFILE")
		var burned := mini(fuel, floori(float(profile.burn_rate_q) * float(original.intensity) / FIRE_HZ + float(original.burn_remainder_q) + FIRE_EPS))
		available = maxf(0.0, float(original.heat) + burned * float(profile.heat_per_q) - reserved)
	var complete := float(original.heat) <= FIRE_EPS and not _fire_has_contact({"contacts": state.get("contacts", {})}, key)
	if mode == "IGNITE":
		var profile := SiteCombatRules.fire_profile(str(original.profile))
		if profile.is_empty(): return fail("FIRE_PROFILE")
		var observed := float(state.get("observed_action_end", data.get_meta(&"fire_completed_action_end", 0.0)))
		var moisture := fire_unit_moisture(data, original, descriptor, observed)
		var weather := fire_weather_at(data, observed)
		var threshold := float(profile.ignition_heat) * (1.0 + float(profile.moisture_ignition) * moisture)
		# Work is received at the next original5Hz boundary, which also cools.
		# Include that known passive loss or finite input would hover just below
		# ignition forever while repeatedly paying only the pre-cooling deficit.
		var boundary_loss := float(profile.cooling_rate) * (1.0 + float(profile.moisture_cooling) * moisture) / FIRE_HZ
		boundary_loss += float(weather.rain) * clampf(float(descriptor.get("rain_exposure", 1.0)), 0.0, 1.0) * float(SiteCombatRules.fire_environment_profile().rain_cooling_per_second) / FIRE_HZ
		available = maxf(0.0, threshold + boundary_loss - float(original.heat) - reserved)
		complete = str(original.state) == "BURNING"
	return ok("", {"key": key, "generation": current_generation, "unit": unit, "descriptor": descriptor,
		"available_heat": available, "complete": complete, "pending_cooling": reserved if mode == "SUPPRESS" else 0.0,
		"pending_heating": reserved if mode == "IGNITE" else 0.0})

static func fire_suppression_target(data: TerrainData, key: String, generation: int = -1) -> Dictionary:
	return fire_work_target(data, key, "SUPPRESS", generation)

static func fire_prepare_suppression(data: TerrainData, key: String, generation: int, action_begin: float,
		action_end: float, requested_q: int, holder: Dictionary, expected_holder_version: int, mode: String = "SUPPRESS") -> Dictionary:
	if data == null or not _fire_time_valid(action_begin) or not _fire_time_valid(action_end): return fail("INVALID_TIME")
	if bool(data.site.get("paused", false)): return fail("PAUSED_SITE")
	if mode not in ["SUPPRESS", "IGNITE"]: return fail("INVALID_WORK")
	var profile := SiteCombatRules.fire_work_profile(mode)
	var duration := action_end - action_begin
	if duration <= 0.0 or duration > float(profile.maximum_action_slice) + FIRE_EPS or requested_q < 1 \
		or requested_q > ceili(duration * int(profile.supply_q_per_second) + FIRE_EPS): return fail("INVALID_WORK")
	var target := fire_work_target(data, key, mode, generation)
	if not target.ok: return target
	var state: Dictionary = data.site.get("fire", {})
	var observed := float(state.get("observed_action_end", data.get_meta(&"fire_completed_action_end", action_begin)))
	if absf(action_begin - observed) > FIRE_EPS: return fail("STALE_FIRE_INTERVAL")
	var supply_field := str(profile.supply_field)
	if not _item_holder_shape(holder) or int(holder.version) != expected_holder_version \
		or expected_holder_version >= 2147483646 or not holder.get(supply_field) is int \
		or int(holder[supply_field]) < 0 or int(holder[supply_field]) > int(profile.supply_cap_q): return fail("STALE_SOURCE")
	if bool(target.complete): return ok("原目標工作已完成", {"complete": true, "paid_q": 0})
	if float(target.available_heat) <= FIRE_EPS: return ok("已付輸入等待原火勢邊界", {"waiting": true, "paid_q": 0})
	if int(holder[supply_field]) <= 0: return fail("NO_SUPPRESSION_SUPPLY" if mode == "SUPPRESS" else "NO_IGNITION_SUPPLY")
	if state.get("suppression_pending", []).size() >= int(profile.pending_cap): return fail("CAPACITY_DEFERRED")
	var sequence := int(state.get("suppression_sequence", 0))
	if sequence >= 2147483646: return fail("SUPPRESSION_SEQUENCE_EXHAUSTED")
	var cooling_per_q := float(profile.cooling_per_second) / int(profile.supply_q_per_second)
	var heating_per_q := float(profile.heating_per_second) / int(profile.supply_q_per_second)
	var paid := mini(requested_q, mini(int(holder[supply_field]), ceili(float(target.available_heat) / (heating_per_q if mode == "IGNITE" else cooling_per_q))))
	return ok("原人物有限工作輸入已預驗", {"state_owner": data.site.get("fire"), "site_owner": data.site,
		"unit_owner": target.unit, "descriptor": target.descriptor.duplicate(true), "holder_owner": holder,
		"expected_holder_version": expected_holder_version, "expected_supply_q": int(holder[supply_field]), "mode": mode, "supply_field": supply_field,
		"key": key, "generation": generation, "expected_step": int(state.get("step_index", floori(observed * FIRE_HZ + FIRE_EPS))), "sequence": sequence + 1,
		"action_begin": action_begin, "action_end": action_end, "paid_q": paid, "requested_q": requested_q,
		"cooling_per_q": cooling_per_q, "heating_per_q": heating_per_q,
		"moisture_per_q": float(profile.moisture_per_second) / int(profile.supply_q_per_second)})

static func fire_commit_suppression(data: TerrainData, prepared: Dictionary) -> Dictionary:
	if not prepared.get("ok", false) or not prepared.has("state_owner") or int(prepared.get("paid_q", 0)) <= 0: return fail("INVALID_WORK")
	if data == null or not is_same(data.site, prepared.site_owner): return fail("STALE_SITE")
	var current: Dictionary = data.site.get("fire", {})
	if int(prepared.sequence) <= int(current.get("suppression_sequence", 0)): return ok("重送工作未再扣補給", {"duplicate": true, "paid_q": 0})
	if not is_same(data.site.get("fire"), prepared.state_owner): return fail("STALE_SITE")
	var holder: Dictionary = prepared.holder_owner
	var mode := str(prepared.mode)
	var check := fire_prepare_suppression(data, str(prepared.key), int(prepared.generation), float(prepared.action_begin),
		float(prepared.action_end), int(prepared.requested_q), holder, int(prepared.expected_holder_version), mode)
	if not check.ok: return check
	var same_unit: bool = check.get("unit_owner", {}).is_empty() and prepared.unit_owner.is_empty() \
		or is_same(check.get("unit_owner"), prepared.unit_owner)
	if int(check.get("paid_q", 0)) != int(prepared.paid_q) or not check.has("unit_owner") or not same_unit \
		or check.descriptor != prepared.descriptor or str(check.supply_field) != str(prepared.supply_field) \
		or int(check.sequence) != int(prepared.sequence) or int(check.expected_step) != int(prepared.expected_step) \
		or int(holder[check.supply_field]) != int(prepared.expected_supply_q) \
		or float(prepared.cooling_per_q) != float(check.cooling_per_q) or float(prepared.heating_per_q) != float(check.heating_per_q) \
		or float(prepared.moisture_per_q) != float(check.moisture_per_q): return fail("STALE_WORK")
	# No callbacks, yields or fallible work below. The first IGNITE input creates
	# only the existing original fire state/unit, after actual holder admission.
	var state := _fire_state(data, float(prepared.action_begin))
	var unit := _fire_unit(data, state, check.descriptor)
	holder[check.supply_field] = int(holder[check.supply_field]) - int(prepared.paid_q)
	holder.version = int(holder.version) + 1
	if not state.has("suppression_pending"): state.suppression_pending = []
	state.suppression_pending.append({"sequence": int(prepared.sequence), "key": str(prepared.key), "generation": int(unit.generation), "mode": mode,
		"begin": float(prepared.action_begin), "end": float(prepared.action_end), "total_q": int(prepared.paid_q),
		"remaining_q": float(prepared.paid_q), "cooling_per_q": float(check.cooling_per_q), "heating_per_q": float(check.heating_per_q),
		"moisture_per_q": float(check.moisture_per_q)})
	state.active[str(prepared.key)] = true
	state.suppression_sequence = int(prepared.sequence)
	state.dirty = true
	return ok("原人物有限工作已原子提交", {"paid_q": int(prepared.paid_q), "sequence": int(prepared.sequence),
		"remaining_q": int(holder[check.supply_field]), "holder_version": int(holder.version)})

static func _fire_suppression_inputs(data: TerrainData, state: Dictionary, begin: float, end: float) -> Dictionary:
	var pending: Array = state.get("suppression_pending", []).duplicate(true)
	var kept: Array[Dictionary] = []
	var cooling := {}
	var heating := {}
	var moisture := {}
	pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.sequence) < int(b.sequence))
	for input: Dictionary in pending:
		var key := str(input.key)
		var unit: Dictionary = state.units.get(key, {})
		if unit.is_empty() or int(unit.generation) != int(input.generation) or _fire_descriptor(data, unit).is_empty(): continue
		var overlap := maxf(0.0, minf(end, float(input.end)) - maxf(begin, float(input.begin)))
		var work := minf(float(input.remaining_q), float(input.total_q) * overlap / (float(input.end) - float(input.begin)))
		if overlap > 0.0 and end + FIRE_EPS >= float(input.end): work = float(input.remaining_q)
		cooling[key] = float(cooling.get(key, 0.0)) + work * float(input.cooling_per_q)
		heating[key] = float(heating.get(key, 0.0)) + work * float(input.get("heating_per_q", 0.0))
		moisture[key] = float(moisture.get(key, 0.0)) + work * float(input.moisture_per_q)
		input.remaining_q = maxf(0.0, float(input.remaining_q) - work)
		if float(input.remaining_q) > FIRE_EPS and end + FIRE_EPS < float(input.end): kept.append(input)
	return {"cooling": cooling, "heating": heating, "moisture": moisture, "pending": kept}

# P4 original feature.parts extension. Stored parts remain exactly {hp}.
const FIRE_LAYOUT_VERSION := 1
const FIRE_ROOF_KINDS := ["house", "warehouse", "saltworks", "kiln", "charcoal", "smelter", "smithy", "tannery", "weaver"]
const FIRE_LAYOUT_KINDS := FIRE_ROOF_KINDS + ["well", "intake", "barracks", "training_ground"]

static func _fire_layout_parts(feature: Dictionary) -> Array[String]:
	var kind := str(feature.get("kind", ""))
	if kind in FIRE_ROOF_KINDS: return ["body", "roof"]
	if kind == "barracks": return ["body", "roof:quarters", "roof:hq"]
	if kind in ["well", "intake", "training_ground"]: return ["body"]
	return []

static func _fire_part_max_hp(feature: Dictionary, part_id: String) -> float:
	var body := civil_max_hp(feature) if str(feature.get("kind", "")) in CIVIL_KINDS else WOOD_PART_HP
	return body * 0.5 if part_id.begins_with("roof") else body

# Integer shares partition one original paid cost. Stable last-part remainders
# avoid creating wood when a legal paid upgrade contains odd quantities.
static func _fire_part_shares(feature: Dictionary) -> Dictionary:
	var kind := str(feature.get("kind", ""))
	if kind == "barracks": return {"body": 1, "roof:quarters": 2, "roof:hq": 1}
	if kind == "warehouse": return {"body": 0 if str(feature.get("material", "wood")) == "stone" else 1, "roof": 1 if str(feature.get("material", "wood")) == "stone" else 2}
	if kind in FIRE_ROOF_KINDS: return {"body": 1, "roof": 3}
	return {"body": 1}

static func _fire_part_allocation(feature: Dictionary, total: int, resource: String = "wood") -> Dictionary:
	var shares := _fire_part_shares(feature)
	if str(feature.get("kind", "")) == "warehouse" and str(feature.get("material", "wood")) == "stone" and resource != "wood": shares = {"body": 1, "roof": 0}
	var denominator := 0
	for share: int in shares.values(): denominator += share
	var allocation := {}
	var remainder := maxi(0, total)
	var parts := _fire_layout_parts(feature)
	for index: int in range(parts.size()):
		var key := parts[index]
		var amount := remainder if index == parts.size() - 1 else floori(float(maxi(0, total)) * int(shares[key]) / denominator)
		allocation[key] = amount
		remainder -= amount
	return allocation

static func _fire_layout_initialize(feature: Dictionary) -> void:
	if str(feature.get("kind", "")) not in FIRE_LAYOUT_KINDS or feature.has("fire_layout_version"): return
	var fraction := clampf(float(feature.get("parts", {}).get("body", {}).get("hp", _fire_part_max_hp(feature, "body"))) / _fire_part_max_hp(feature, "body"), 0.0, 1.0)
	feature["fire_layout_version"] = FIRE_LAYOUT_VERSION
	if not feature.has("parts"): feature["parts"] = {}
	for key: String in _fire_layout_parts(feature):
		if not feature.parts.has(key): feature.parts[key] = {"hp": _fire_part_max_hp(feature, key) * fraction}

# Explicit admission migration over the same original feature. Reads never
# initialize parts. A P2 body retains all old heat/contact, and its finite fuel
# is partitioned once; a roof receives no copied contact or heat budget.
static func fire_expand_feature(data: TerrainData, feature_id: String) -> Dictionary:
	var feature: Dictionary = data.site.get("features", {}).get(feature_id, {})
	if str(feature.get("kind", "")) not in FIRE_LAYOUT_KINDS or int(feature.get("layout_version", 0)) != BUILDING_LAYOUT_VERSION: return fail("UNSUPPORTED_FIRE_LAYOUT")
	if feature.has("fire_layout_version"): return ok("原多部件布局已存在") if int(feature.fire_layout_version) == FIRE_LAYOUT_VERSION else fail("FIRE_LAYOUT_VERSION")
	if str(feature.get("stage", "")) != "complete" or feature.has("repair") or feature.has("pending_build"): return fail("BUSY", "原建物施工或修理尚未完成")
	for key: String in feature.get("parts", {}):
		if _fire_pending_projectile(data, _fire_unit_key("feature", feature_id, key)): return fail("BUSY", "原在途接觸仍引用舊部件幾何")
	var candidate := feature.duplicate(true)
	_fire_layout_initialize(candidate)
	var state: Dictionary = data.site.get("fire", {})
	var body_key := _fire_unit_key("feature", feature_id, "body")
	var old: Dictionary = state.get("units", {}).get(body_key, {})
	var old_fuel := int(old.get("fuel_q", 0))
	var allocations := _fire_part_allocation(candidate, old_fuel)
	feature.fire_layout_version = candidate.fire_layout_version
	feature.parts = candidate.parts
	if not old.is_empty():
		for part_id: String in _fire_layout_parts(feature):
			var descriptor := _fire_feature_descriptor(data, feature_id, part_id)
			if descriptor.is_empty(): continue
			var unit := old if part_id == "body" else _fire_new_unit(descriptor)
			unit.fuel_max_q = int(descriptor.fuel_max_q)
			unit.fuel_q = int(allocations[part_id])
			unit.surface_id = str(descriptor.surface_id)
			unit.height = float(descriptor.height)
			state.units[str(descriptor.key)] = unit
		state.dirty = true
	data.environment_revision += 1
	fire_hazard_invalidate(data)
	return ok("原建物已一次分區", {"feature": feature_id, "preserved_fuel_q": old_fuel})

static func feature_service_dependencies(feature: Dictionary, service: String = "") -> Array[String]:
	var kind := str(feature.get("kind", ""))
	if int(feature.get("fire_layout_version", 0)) != FIRE_LAYOUT_VERSION:
		if int(feature.get("civil_version", 0)) == CIVIL_VERSION: return ["body"]
		return []
	if kind == "barracks":
		if service == "training": return ["body", "roof:hq"]
		if service in ["garrison", "return", "recovery"]: return ["body", "roof:quarters"]
		return ["body", "roof:quarters", "roof:hq"]
	return _fire_layout_parts(feature)

static func feature_function_state(feature: Dictionary, service: String = "") -> String:
	var parts: Dictionary = feature.get("parts", {})
	if parts.has("body") and float(parts.body.hp) <= 0.0: return "DESTROYED"
	var required := feature_service_dependencies(feature, service)
	var missing := false
	for key: String in required:
		if float(parts.get(key, {}).get("hp", 0.0)) <= 0.0: missing = true
	if not missing: return "OPERATIONAL"
	if str(feature.get("kind", "")) == "barracks" and service.is_empty():
		if float(parts.get("roof:quarters", {}).get("hp", 0.0)) > 0.0 or float(parts.get("roof:hq", {}).get("hp", 0.0)) > 0.0: return "DEGRADED"
	return "DISABLED"

static func _fire_layout_geometry(data: TerrainData, feature: Dictionary, geometry: Dictionary) -> void:
	if int(feature.get("fire_layout_version", 0)) != FIRE_LAYOUT_VERSION: return
	var kind := str(feature.kind)
	var base := float(feature.level)
	var by_part := {}
	var all_cells: Array[int] = []
	all_cells.assign(feature.cells)
	if kind in MILITARY_KINDS:
		var modules := military_modules(data, feature)
		var quarters: Array[int] = []
		var headquarters: Array[int] = []
		all_cells.clear()
		for index: int in range(modules.size()):
			var module: Dictionary = modules[index]
			all_cells.append_array(module.cells)
			if kind == "barracks":
				if index == modules.size() - 1: headquarters.append_array(module.cells)
				else: quarters.append_array(module.cells)
		by_part = {"body": all_cells, "roof:quarters": quarters, "roof:hq": headquarters} if kind == "barracks" else {"body": all_cells}
	else:
		for key: String in _fire_layout_parts(feature): by_part[key] = all_cells
	geometry.parts.clear()
	var investment: Dictionary = {}
	for resource: String in feature.get("cost", {}):
		investment[resource] = _fire_part_allocation(feature, int(feature.cost[resource]), resource)
	var fuel := _fire_part_allocation(feature, int(feature.get("cost", {}).get("wood", 0)) * FIRE_Q)
	for key: String in _fire_layout_parts(feature):
		var part_cells: Array[int] = []
		part_cells.assign(by_part.get(key, []))
		if part_cells.is_empty(): continue
		var roof := key.begins_with("roof")
		var lower := base + (1.25 if roof else 0.0)
		var upper := base + (2.0 if roof else (1.25 if kind in FIRE_ROOF_KINDS + ["barracks"] else 2.0))
		var part := _geometry_part(feature, key, part_cells, "roof" if roof else "building", ceili(upper), _fire_part_max_hp(feature, key))
		var cost := {}
		for resource: String in investment:
			var amount := int(investment[resource][key])
			if amount > 0: cost[resource] = amount
		var weights := _fire_part_shares(feature)
		if kind == "warehouse" and str(feature.get("material", "wood")) == "stone": weights = {"body": 1, "roof": 1}
		var denominator := 0
		for weight: int in weights.values(): denominator += weight
		var first := data.cell_from_index(part_cells[0])
		var covered := false
		if not roof:
			for roof_id: String in _fire_layout_parts(feature):
				if roof_id.begins_with("roof") and float(feature.parts[roof_id].hp) > 0.0: covered = true
		part.merge({"lower": lower, "upper": upper, "aim_point": Vector3(first.x + 0.5, first.y + 0.5, (lower + upper) * 0.5),
			"material": "wood" if roof else str(feature.get("material", "wood")), "investment": cost,
			"work_share": float(weights[key]) / denominator, "fuel_max_q": int(fuel[key]),
			"rain_exposure": 1.0 if roof or not covered else 0.0, "smoke_outdoor": true})
		geometry.parts[key] = part
	if kind in MILITARY_KINDS:
		geometry.blocked = all_cells.duplicate() if str(feature.stage) == "complete" and float(feature.parts.body.hp) > 0.0 else []

static func _fire_supported_parts(feature: Dictionary, part_id: String) -> Array[String]:
	var result: Array[String] = []
	if part_id.begins_with("frame:"): result.append(part_id.replace("frame:", "leaf:"))
	if int(feature.get("fire_layout_version", 0)) == FIRE_LAYOUT_VERSION and part_id == "body":
		for key: String in _fire_layout_parts(feature):
			if key.begins_with("roof"): result.append(key)
	return result

# Authored body-to-roof links plus actual shared/cardinal surface contact.
# Only original descriptors are returned; no candidate owns material or HP.
static func _fire_feature_edges(data: TerrainData, descriptor: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen := {}
	var sources: Dictionary = {}
	for index: int in descriptor.get("cells", []):
		sources[index] = true
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var neighbor := data.cell_from_index(index) + direction
			if data.contains(neighbor): sources[data.index(neighbor)] = true
	var candidate_ids := {}
	for index: int in sources:
		var id := str(data.feature_at[index])
		if not id.is_empty(): candidate_ids[id] = true
	if str(descriptor.kind) == "feature": candidate_ids[str(descriptor.feature)] = true
	var ids: Array = candidate_ids.keys()
	ids.sort()
	for id: String in ids:
		var feature: Dictionary = data.site.get("features", {}).get(id, {})
		var parts: Array = feature.get("parts", {}).keys()
		parts.sort()
		for part_id: String in parts:
			var other := _fire_feature_descriptor(data, id, part_id)
			if other.is_empty() or str(other.key) == str(descriptor.key) or seen.has(str(other.key)) or float(feature.parts[part_id].hp) <= 0.0: continue
			var linked := str(descriptor.get("feature", "")) == id and (str(descriptor.get("part", "")) == "body" or part_id == "body")
			if not linked:
				if float(descriptor.get("upper", descriptor.height)) + 0.25 < float(other.get("lower", other.height)) or float(other.get("upper", other.height)) + 0.25 < float(descriptor.get("lower", descriptor.height)): continue
				for index: int in other.cells:
					if sources.has(index): linked = true; break
			if linked: seen[str(other.key)] = true; result.append(other)
	if str(descriptor.kind) == "feature":
		for index: int in sources:
			if data.water_kind[index] != 0 or float(data.height_levels[index]) + 0.25 < float(descriptor.get("lower", descriptor.height)): continue
			var resource_ids: Array = data.resources_at.get(index, []).duplicate()
			resource_ids.sort()
			for id: String in resource_ids:
				var other := _fire_resource_descriptor(data, id)
				if not other.is_empty() and not seen.has(str(other.key)):
					seen[str(other.key)] = true
					result.append(other)
	return result

# P4 collapse receipts live in the original Site fire record. They own neither
# structure HP nor a new clock. A warning survives extinguishing and nonfatal hits.
const FIRE_COLLAPSE_VERSION := 1
const FIRE_COLLAPSE_DELAY_STEPS := 10
const FIRE_COLLAPSE_HP_FRACTION := 0.25

static func _fire_collapse_state(state: Dictionary) -> void:
	if not state.has("collapse_warnings"): state.collapse_warnings = {}
	if not state.has("collapse_receipts"): state.collapse_receipts = {}
	if not state.has("collapse_next_sequence"): state.collapse_next_sequence = 1
	if not state.has("structure_pending"): state.structure_pending = {}

static func _fire_pending_damage(data: TerrainData, state: Dictionary) -> Dictionary:
	var result := {}
	for key: String in state.get("structure_pending", {}):
		var request: Dictionary = state.structure_pending[key]
		var unit_key := _fire_unit_key("feature", str(request.feature), str(request.part))
		var feature: Dictionary = data.site.get("features", {}).get(str(request.feature), {})
		var hp := float(feature.get("parts", {}).get(str(request.part), {}).get("hp", 0.0))
		if hp <= 0.0 or int(request.generation) != fire_generation(data, unit_key): continue
		result[key] = request.duplicate(true)
		result[key].damage = minf(hp, float(request.damage))
		result[key].fire_damage = minf(float(result[key].damage), float(request.fire_damage))
	return result

static func _fire_add_structure_damage(data: TerrainData, damage: Dictionary, feature_id: String, part_id: String,
		amount: float, fire_amount: float, collapse_generation: int = 0) -> void:
	var feature: Dictionary = data.site.get("features", {}).get(feature_id, {})
	var hp := float(feature.get("parts", {}).get(part_id, {}).get("hp", 0.0))
	if hp <= 0.0 or amount <= 0.0: return
	var key := feature_id + "|" + part_id
	if not damage.has(key): damage[key] = {"feature": feature_id, "part": part_id, "generation": fire_generation(data, _fire_unit_key("feature", feature_id, part_id)), "damage": 0.0, "fire_damage": 0.0, "collapse_generation": 0}
	damage[key].damage = minf(hp, float(damage[key].damage) + amount)
	damage[key].fire_damage = minf(hp, float(damage[key].fire_damage) + fire_amount)
	if collapse_generation > 0: damage[key].collapse_generation = collapse_generation

static func _fire_due_collapses(data: TerrainData, state: Dictionary, step: int, damage: Dictionary) -> void:
	var keys: Array = state.get("collapse_warnings", {}).keys()
	keys.sort()
	for key: String in keys:
		var warning: Dictionary = state.collapse_warnings[key]
		var unit: Dictionary = state.get("units", {}).get(key, {})
		if unit.is_empty() or int(unit.generation) != int(warning.generation) or step < int(warning.due_step): continue
		var feature: Dictionary = data.site.features.get(str(unit.feature), {})
		var hp := float(feature.get("parts", {}).get(str(unit.part), {}).get("hp", 0.0))
		_fire_add_structure_damage(data, damage, str(unit.feature), str(unit.part), hp, 0.0, int(warning.generation))

static func fire_structure_request_guard(data: TerrainData, request: Dictionary) -> Dictionary:
	var key := _fire_unit_key("feature", str(request.feature), str(request.part))
	var state: Dictionary = data.site.get("fire", {})
	if request.has("generation") and int(request.generation) != fire_generation(data, key): return fail("STALE_FIRE_STRUCTURE", "原部件已更換世代")
	if int(request.get("collapse_generation", 0)) > 0:
		var warning: Dictionary = state.get("collapse_warnings", {}).get(key, {})
		if warning.is_empty() or int(warning.generation) != int(request.collapse_generation) or maxi(int(state.get("step_index", 0)), int(data.get_meta(&"fire_structure_step", 0))) < int(warning.due_step): return fail("STALE_COLLAPSE")
	var feature: Dictionary = data.site.get("features", {}).get(str(request.feature), {})
	var hp := float(feature.get("parts", {}).get(str(request.part), {}).get("hp", 0.0))
	if hp > 0.0 and float(request.damage) >= hp:
		var removed: Array[String] = [str(request.part)]
		removed.append_array(_fire_supported_parts(feature, str(request.part)))
		for part_id: String in removed:
			if fire_generation(data, _fire_unit_key("feature", str(request.feature), part_id)) >= 2147483647: return fail("FIRE_GENERATION_LIMIT")
	if hp > 0.0 and float(request.get("fire_damage", 0.0)) > 0.0 and not state.get("collapse_warnings", {}).has(key):
		var maximum := float(feature_geometry(data, feature).parts.get(str(request.part), {}).get("max_hp", INF))
		if hp - float(request.damage) > 0.0 and hp - float(request.damage) <= maximum * FIRE_COLLAPSE_HP_FRACTION:
			if int(state.get("collapse_next_sequence", 1)) >= 2147483647 or int(state.get("step_index", 0)) > FIRE_MAX_STEP - FIRE_COLLAPSE_DELAY_STEPS: return fail("FIRE_COLLAPSE_ID_LIMIT")
	return ok()

static func fire_structure_outcome(data: TerrainData, request: Dictionary, result: Dictionary) -> void:
	if data.has_meta(&"fire_structure_step"): return # Immediate sink: Runtime commits next first, then consumes its actual result.
	if not bool(result.get("ok", false)): return
	var state: Dictionary = data.site.get("fire", {})
	var feature_id := str(result.get("feature", request.get("feature", "")))
	var part_id := str(result.get("part", request.get("part", "")))
	var feature: Dictionary = data.site.get("features", {}).get(feature_id, {})
	var key := _fire_unit_key("feature", feature_id, part_id)
	# Ordinary historical damage without any admitted fire history stays on its
	# original path. New multipart construction is an admitted original layout.
	if state.is_empty() and int(feature.get("fire_layout_version", 0)) != FIRE_LAYOUT_VERSION: return
	if state.is_empty(): state = _fire_state(data, float(data.get_meta(&"fire_completed_action_end", 0.0)))
	_fire_collapse_state(state)
	state.structure_pending.erase(feature_id + "|" + part_id)
	var descriptor := _fire_feature_descriptor(data, feature_id, part_id)
	var unit: Dictionary = state.units.get(key, {})
	if unit.is_empty() and not descriptor.is_empty(): unit = _fire_unit(data, state, descriptor)
	if float(result.get("old_hp", 0.0)) > 0.0 and float(result.get("new_hp", 1.0)) <= 0.0:
		_fire_commit_collapse(data, state, feature_id, part_id)
		for supported: String in result.get("consequential_parts", []): _fire_commit_collapse(data, state, feature_id, supported)
	elif not unit.is_empty() and float(request.get("fire_damage", 0.0)) > 0.0 and not state.collapse_warnings.has(key):
		var maximum := float(feature_geometry(data, feature).parts[part_id].max_hp)
		if float(result.new_hp) <= maximum * FIRE_COLLAPSE_HP_FRACTION:
			state.collapse_warnings[key] = {"version": FIRE_COLLAPSE_VERSION, "generation": int(unit.generation),
				"sequence": int(state.collapse_next_sequence), "due_step": int(state.step_index) + FIRE_COLLAPSE_DELAY_STEPS}
			state.collapse_next_sequence = int(state.collapse_next_sequence) + 1
			state.dirty = true
			fire_hazard_invalidate(data)

static func _fire_commit_collapse(data: TerrainData, state: Dictionary, feature_id: String, part_id: String) -> void:
	var feature: Dictionary = data.site.get("features", {}).get(feature_id, {})
	if float(feature.get("parts", {}).get(part_id, {}).get("hp", 1.0)) > 0.0: return
	var key := _fire_unit_key("feature", feature_id, part_id)
	var unit: Dictionary = state.units.get(key, {})
	if unit.is_empty():
		var descriptor := _fire_feature_descriptor(data, feature_id, part_id)
		if descriptor.is_empty(): return # Original stone body has no burning material to transfer.
		unit = _fire_unit(data, state, descriptor)
	if int(unit.get("debris_version", 0)) == FIRE_COLLAPSE_VERSION: return
	var generation := int(unit.generation)
	var receipt_id := key + "@" + str(generation)
	if state.collapse_receipts.has(receipt_id): return
	var warning: Dictionary = state.collapse_warnings.get(key, {})
	state.collapse_receipts[receipt_id] = {"version": FIRE_COLLAPSE_VERSION, "generation": generation,
		"sequence": int(warning.get("sequence", 0)), "step": int(state.step_index)}
	unit["debris_version"] = FIRE_COLLAPSE_VERSION
	unit["standing_generation"] = generation
	unit.generation = generation + 1
	unit.surface_id = "ground"
	unit.height = float(feature.level)
	for contact: Dictionary in state.contacts.values():
		if str(contact.unit_key) == key and int(contact.generation) == generation: contact.generation = int(unit.generation)
	state.collapse_warnings.erase(key)
	state.structure_pending.erase(feature_id + "|" + part_id)
	state.repair_generations.erase(key)
	state.dirty = true
	fire_hazard_invalidate(data)

static func _fire_debris_descriptor(data: TerrainData, unit: Dictionary) -> Dictionary:
	var descriptor := _fire_feature_descriptor(data, str(unit.feature), str(unit.part))
	if descriptor.is_empty(): return {}
	var feature: Dictionary = data.site.features[str(unit.feature)]
	descriptor.surface_id = "ground"
	descriptor.height = float(feature.level)
	descriptor.lower = float(feature.level)
	descriptor.upper = float(feature.level)
	descriptor.hazard_cells = descriptor.cells.duplicate()
	descriptor.rain_exposure = 1.0
	descriptor.smoke_outdoor = true
	return descriptor

static func _fire_retire_collapse_reference(state: Dictionary, key: String) -> void:
	state.get("collapse_warnings", {}).erase(key)
	var unit: Dictionary = state.get("units", {}).get(key, {})
	if not unit.is_empty(): state.get("structure_pending", {}).erase(str(unit.feature) + "|" + str(unit.part))

static func fire_path_hazard_at(snapshot: Dictionary, cell: Vector2i, height: float, ground_offset: float = 0.0) -> float:
	var value := cell.y * int(snapshot.get("width", 0)) + cell.x
	var risk := 0.0
	for entry: Dictionary in snapshot.cells.get(value, []):
		var shift := ground_offset if bool(entry.get("ground", false)) else 0.0
		if height >= float(entry.lower) + shift - FIRE_EPS and height <= float(entry.upper) + shift + FIRE_EPS: risk += float(entry.risk)
	return risk

# Versioned engineering profile: exposed stock loses at most one combustible
# item per action second at full old-snapshot intensity. It creates no new fuel.
const FIRE_INVENTORY_VERSION := 1
const FIRE_INVENTORY_LOSS_RATE := 1.0
const FIRE_COMBUSTIBLE_STACKS := ["wood", "wild_food", "herb", "fish", "meat", "hide", "seeds", "grain", "fiber", "fodder", "charcoal", "rope", "cloth", "leather", "wool", "arrow", "fire_arrow", "bolt", "siege_bolt", "camp_tent"]

static func _fire_item_combustible(definition: Dictionary) -> bool:
	var slot := str(definition.get("slot", ""))
	if slot in ["outfit", "cape", "boots"]: return true
	if slot != "weapon": return false
	var asset := StringName(str(definition.get("asset", "")))
	return SiteCombatRules.WeaponMaterials.material(asset) == "wood" or SiteCombatRules.WeaponMaterials.is_ranged(asset)

static func apply_inventory_loss(data: TerrainData, request: Dictionary) -> Dictionary:
	if data == null or not _fire_state_valid(data): return fail("NO_TARGET")
	var state: Dictionary = data.site.fire
	var names := ["version", "event_id", "site_id", "feature_id", "source_unit_key", "source_generation", "step", "holder_id", "expected_version", "resources", "item_ids"]
	if request.size() != names.size(): return fail("INVALID_INVENTORY_LOSS")
	for name: String in names:
		if not request.has(name): return fail("INVALID_INVENTORY_LOSS")
	if not _building_integer(request.version, 1, 1) or not _building_integer(request.source_generation, 1, 2147483647) or not _building_integer(request.step, 0, int(state.step_index)) or not _building_integer(request.expected_version, 0, 2147483645): return fail("INVALID_INVENTORY_LOSS")
	for field: String in ["event_id", "site_id", "feature_id", "source_unit_key", "holder_id"]:
		if not request[field] is String: return fail("INVALID_INVENTORY_LOSS")
	var event_id := "contents:%d:%s@%d" % [int(request.step), str(request.source_unit_key), int(request.source_generation)]
	if str(request.event_id) != event_id or str(request.site_id) != str(data.site.id): return fail("INVALID_INVENTORY_LOSS")
	if state.get("inventory_receipts", {}).has(event_id): return ok("原庫存損失收據已提交", {"duplicate": true, "receipt": state.inventory_receipts[event_id].duplicate(true)})
	var unit: Dictionary = state.units.get(str(request.source_unit_key), {})
	if str(unit.get("kind", "")) != "feature" or str(unit.get("feature", "")) != str(request.feature_id) or int(unit.get("generation", 0)) != int(request.source_generation): return fail("TARGET_INVALIDATED")
	var feature: Dictionary = data.site.features.get(str(request.feature_id), {})
	if int(feature.get("fire_layout_version", 0)) != FIRE_LAYOUT_VERSION or not feature.get("parts", {}).has("roof") or float(feature.parts.roof.hp) > 0.0: return fail("CONTENTS_PROTECTED")
	var stock: Dictionary = data.site.get("stockpiles", {}).get(str(request.feature_id), {})
	var holder: Dictionary = stock.get("holder", {})
	var cargo: Dictionary = stock.get("cargo", {})
	if not _item_holder_shape(holder) or not _resource_stack(cargo) or str(holder.holder) != "feature:" + str(request.feature_id) or str(request.holder_id) != str(holder.holder) or int(holder.version) != int(request.expected_version): return fail("STALE_SOURCE")
	if not request.resources is Dictionary or not _resource_stack(request.resources) or not request.item_ids is Array: return fail("INVALID_INVENTORY_LOSS")
	if inventory_size(request.resources) + request.item_ids.size() > 1: return fail("INVALID_INVENTORY_LOSS", "單一固定步原暴露額度最多一件")
	var resources := {}
	var items: Array[String] = []
	var seen := {}
	for resource: String in request.resources:
		if resource not in FIRE_COMBUSTIBLE_STACKS: return fail("INVALID_INVENTORY_LOSS")
		var amount := mini(int(cargo.get(resource, 0)), int(request.resources[resource]))
		if amount > 0: resources[resource] = amount
	for value: Variant in request.item_ids:
		if not value is String or not str(value).is_valid_int() or str(int(value)) != value or int(value) <= 0 or seen.has(value): return fail("INVALID_INVENTORY_LOSS")
		seen[value] = true
		if not holder.item_ids.has(value): continue # Moved/retired IDs are never destroyed elsewhere.
		var record: Dictionary = data.site.item_records.get(value, {})
		var definition: Dictionary = data.site.item_definitions.get(str(record.get("definition", "")), {})
		if str(record.get("holder", "")) != str(holder.holder) or definition.is_empty(): return fail("STALE_SOURCE")
		if not _fire_item_combustible(definition): return fail("INVALID_INVENTORY_LOSS")
		items.append(value)
	# Every check precedes mutation. Shared definitions, next_item, the original
	# holder object, paid batches and all unrelated holders remain untouched.
	add_items(cargo, resources, -1)
	for resource: String in cargo.keys():
		if int(cargo[resource]) == 0: cargo.erase(resource)
	for identity: String in items:
		holder.item_ids.erase(identity)
		for slot: String in holder.equipped.keys():
			if str(holder.equipped[slot]) == identity: holder.equipped.erase(slot)
		data.site.item_records.erase(identity)
	holder.version = int(holder.version) + 1
	var receipt := {"version": FIRE_INVENTORY_VERSION, "feature_id": str(request.feature_id), "source_unit_key": str(request.source_unit_key),
		"source_generation": int(request.source_generation), "step": int(request.step), "holder_id": str(holder.holder),
		"holder_version": int(holder.version), "resources": resources, "item_ids": items}
	if not state.has("inventory_receipts"): state.inventory_receipts = {}
	state.inventory_receipts[event_id] = receipt
	state.dirty = true
	return ok("原倉庫已一次提交有限火損", {"duplicate": false, "receipt": receipt.duplicate(true)})

static func _fire_inventory_selection(data: TerrainData, stock: Dictionary, budget: int) -> Dictionary:
	var resources := {}
	var items: Array[String] = []
	var names: Array = stock.cargo.keys()
	names.sort()
	for resource: String in names:
		if resource not in FIRE_COMBUSTIBLE_STACKS: continue
		var amount := mini(budget, int(stock.cargo[resource]))
		if amount > 0: resources[resource] = amount; budget -= amount
		if budget == 0: break
	if budget > 0:
		var identities: Array = stock.holder.item_ids.duplicate()
		identities.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
		for identity: String in identities:
			var record: Dictionary = data.site.item_records.get(identity, {})
			if not _fire_item_combustible(data.site.item_definitions.get(str(record.get("definition", "")), {})): continue
			items.append(identity)
			budget -= 1
			if budget == 0: break
	return {"resources": resources, "item_ids": items}

static func _fire_inventory_preview(data: TerrainData, state: Dictionary, old: Dictionary, step: int) -> Dictionary:
	var remainder: Dictionary = state.get("contents_remainders", {}).duplicate(true)
	var requests: Dictionary = state.get("inventory_pending", {}).duplicate(true)
	var exposures := {}
	var keys: Array = old.keys()
	keys.sort()
	for key: String in keys:
		var unit: Dictionary = old[key]
		if str(unit.kind) != "feature" or float(unit.heat) <= FIRE_EPS: continue
		var feature_id := str(unit.feature)
		var feature: Dictionary = data.site.features.get(feature_id, {})
		var stock: Dictionary = data.site.get("stockpiles", {}).get(feature_id, {})
		# This reads BEFORE the current structure sink. The first roof hit/collapse
		# cannot charge contents in that same interval.
		if stock.is_empty() or int(feature.get("fire_layout_version", 0)) != FIRE_LAYOUT_VERSION or not feature.get("parts", {}).has("roof") or float(feature.parts.roof.hp) > 0.0: continue
		var risk := maxf(float(unit.intensity), minf(0.2, float(unit.heat) / 500.0))
		if not exposures.has(feature_id): exposures[feature_id] = {"risk": 0.0, "key": key, "generation": int(unit.generation)}
		exposures[feature_id].risk = minf(1.0, float(exposures[feature_id].risk) + risk)
	for feature_id: String in exposures:
		var exposure: Dictionary = exposures[feature_id]
		var demand := float(remainder.get(feature_id, 0.0)) + FIRE_INVENTORY_LOSS_RATE * float(exposure.risk) / FIRE_HZ
		var amount := floori(demand + FIRE_EPS)
		remainder[feature_id] = maxf(0.0, demand - amount)
		if amount <= 0: continue
		var stock: Dictionary = data.site.stockpiles[feature_id]
		var selection := _fire_inventory_selection(data, stock, amount)
		var event_id := "contents:%d:%s@%d" % [step, str(exposure.key), int(exposure.generation)]
		requests[event_id] = {"version": FIRE_INVENTORY_VERSION, "event_id": event_id, "site_id": str(data.site.id),
			"feature_id": feature_id, "source_unit_key": str(exposure.key), "source_generation": int(exposure.generation), "step": step,
			"holder_id": str(stock.holder.holder), "expected_version": int(stock.holder.version), "resources": selection.resources, "item_ids": selection.item_ids}
	return {"remainders": remainder, "requests": requests}

static func _fire_commit_inventory_preview(data: TerrainData, state: Dictionary, preview: Dictionary) -> Array[Dictionary]:
	var pending := {}
	var results: Array[Dictionary] = []
	var keys: Array = preview.requests.keys()
	keys.sort()
	for key: String in keys:
		var request: Dictionary = preview.requests[key]
		var result := apply_inventory_loss(data, request)
		if not result.ok and str(result.code) == "STALE_SOURCE":
			var stock: Dictionary = data.site.get("stockpiles", {}).get(str(request.feature_id), {})
			if not stock.is_empty():
				request.expected_version = int(stock.holder.version)
				result = apply_inventory_loss(data, request) # Same event ID; clamp current stock once.
		if not result.ok and str(result.code) not in ["TARGET_INVALIDATED", "CONTENTS_PROTECTED"]: pending[key] = request
		results.append(result)
	if not preview.remainders.is_empty() or state.has("contents_remainders"): state.contents_remainders = preview.remainders
	if not pending.is_empty() or state.has("inventory_pending"): state.inventory_pending = pending
	return results

# Original Runtime owns weather input history and sparse outdoor smoke alongside
# heat. Queries never run a second clock and never create fuel/people/geometry.

static func fire_set_weather(data: TerrainData, action_time: float, wind: Vector2, rain: float, drying: float = 0.02) -> Dictionary:
	if data == null or not _fire_time_valid(action_time) or not is_finite(wind.x) or not is_finite(wind.y) \
		or wind.length_squared() > 1.0 + FIRE_EPS or not is_finite(rain) or rain < 0.0 or rain > 1.0 \
		or not is_finite(drying) or drying < 0.0 or drying > 1.0: return fail("INVALID_WEATHER")
	if bool(data.site.get("paused", false)): return fail("PAUSED_SITE")
	if data.site.has("fire") and not _fire_state_valid(data): return fail("FIRE_VERSION")
	var previous: Dictionary = data.site.get("fire", {})
	var completed := float(previous.get("observed_action_end", data.get_meta(&"fire_completed_action_end", 0.0)))
	if absf(action_time - completed) > FIRE_EPS: return fail("STALE_WEATHER_INTERVAL")
	var old: Dictionary = previous.get("weather", {})
	if int(old.get("sequence", 0)) >= 2147483646: return fail("WEATHER_SEQUENCE_EXHAUSTED")
	var history: Array = old.get("history", [])
	var input := {"action_time": action_time, "wind_x": wind.x, "wind_y": wind.y, "rain": rain, "drying": drying}
	if not history.is_empty() and history.back() == input: return ok("相同天氣输入未重送", {"duplicate": true})
	var profile := SiteCombatRules.fire_environment_profile()
	if history.size() >= int(profile.weather_history_cap): return fail("WEATHER_HISTORY_CAPACITY")
	# All validation precedes this original state mutation. History is retained
	# because cold unmaterialized fuel must not assume today's rain in the past.
	var state := _fire_state(data, action_time)
	if old.is_empty():
		state.weather = {"config_version": str(profile.config_version), "sequence": 0, "history": []}
		if action_time > 0.0: state.weather.history.append({"action_time": 0.0, "wind_x": 0.0, "wind_y": 0.0, "rain": 0.0, "drying": 0.02})
	state.weather.history.append(input)
	state.weather.sequence = int(state.weather.sequence) + 1
	state.dirty = true
	return ok("原Site天氣區間已記錄", {"sequence": int(state.weather.sequence)})

static func _fire_weather_index(history: Array, action_time: float) -> int:
	var low := 0
	var high := history.size()
	while low < high:
		var middle := low + ((high - low) >> 1)
		if float(history[middle].action_time) <= action_time + FIRE_EPS: low = middle + 1
		else: high = middle
	return low - 1

static func fire_weather_at(data: TerrainData, action_time: float) -> Dictionary:
	var history: Array = data.site.get("fire", {}).get("weather", {}).get("history", []) if data != null else []
	var index := _fire_weather_index(history, action_time)
	return history[index].duplicate(true) if index >= 0 else {"action_time": 0.0, "wind_x": 0.0, "wind_y": 0.0, "rain": 0.0, "drying": 0.02}

static func _fire_weather_intervals(data: TerrainData, begin: float, end: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if end <= begin: return result
	var history: Array = data.site.get("fire", {}).get("weather", {}).get("history", [])
	var index := _fire_weather_index(history, begin)
	var cursor := begin
	var weather := fire_weather_at(data, begin)
	while cursor < end - FIRE_EPS:
		var next := end
		if index + 1 < history.size(): next = minf(end, float(history[index + 1].action_time))
		if next > cursor:
			var interval: Dictionary = weather.duplicate(true)
			interval["seconds"] = next - cursor
			result.append(interval)
		cursor = next
		if index + 1 >= history.size() or cursor >= end - FIRE_EPS: break
		index += 1
		weather = history[index]
	return result

static func fire_unit_moisture(data: TerrainData, unit: Dictionary, descriptor: Dictionary, action_time: float) -> float:
	var baseline := clampf(float(descriptor.get("moisture", 0.0)), 0.0, 1.0)
	var value := clampf(float(unit.get("moisture", baseline)), baseline, 1.0)
	var begin := float(unit.get("moisture_action", 0.0))
	var exposure := clampf(float(descriptor.get("rain_exposure", 1.0)), 0.0, 1.0)
	var profile := SiteCombatRules.fire_environment_profile()
	for interval: Dictionary in _fire_weather_intervals(data, begin, action_time):
		var rate := float(interval.rain) * exposure * float(profile.rain_wetting_per_second) - float(interval.drying)
		value = clampf(value + rate * float(interval.seconds), baseline, 1.0)
	return value

static func fire_rain_integral(data: TerrainData, begin: float, end: float) -> float:
	var total := 0.0
	for interval: Dictionary in _fire_weather_intervals(data, begin, end): total += float(interval.rain) * float(interval.seconds)
	return total

static func fire_wind_weight(data: TerrainData, source: Vector2i, destination: Vector2i, begin: float, end: float) -> float:
	if end <= begin: return 1.0
	var direction := Vector2(destination - source).normalized()
	var strength := float(SiteCombatRules.fire_environment_profile().wind_weight)
	var total := 0.0
	for interval: Dictionary in _fire_weather_intervals(data, begin, end):
		var wind := Vector2(float(interval.wind_x), float(interval.wind_y))
		total += clampf(1.0 + strength * wind.dot(direction), 0.1, 2.0) * float(interval.seconds)
	return total / (end - begin)

static func _fire_air_column_open(data: TerrainData, cell: Vector2i, height: float) -> bool:
	if not data.contains(cell): return false
	var value := data.index(cell)
	if height <= float(data.height_levels[value]) + FIRE_EPS: return false
	var feature: Dictionary = data.site.get("features", {}).get(str(data.feature_at[value]), {})
	if not feature.is_empty() and str(feature.get("stage", "")) == "complete":
		var geometry := feature_geometry(data, feature)
		if geometry.parts.is_empty() and geometry.blocked.has(value) and height <= float(feature.get("level", 0)) + 2.0: return false
		for part: Dictionary in geometry.parts.values():
			if not part.cells.has(value) or float(part.hp) <= 0.0 or str(part.role) == "leaf" and bool(feature.get("gate", {}).get("open", false)): continue
			var lower := float(part.get("collision_lower", feature.get("level", 0)))
			var upper := float(part.get("collision_upper", maxf(float(feature.get("level", 0)) + 0.5, float(part.height)) if str(part.role) in ["wall", "stairs"] else float(feature.get("level", 0)) + 2.0))
			if height >= lower - FIRE_EPS and height <= upper + FIRE_EPS: return false
	elif data.static_blocked[value] != 0 and height <= float(data.height_levels[value]) + 2.0:
		return false
	return true

static func fire_point_rain_exposure(data: TerrainData, point: Vector3) -> float:
	var cell := Vector2i(floori(point.x), floori(point.y))
	if not data.contains(cell): return 1.0
	var feature: Dictionary = data.site.get("features", {}).get(str(data.feature_at[data.index(cell)]), {})
	if feature.is_empty() or str(feature.get("stage", "")) != "complete": return 1.0
	var geometry := feature_geometry(data, feature)
	for part: Dictionary in geometry.parts.values():
		if not part.cells.has(data.index(cell)) or float(part.hp) <= 0.0: continue
		if bool(part.get("rain_shelter", str(part.role) in ["building", "roof"])) \
			and point.z < float(part.get("collision_upper", maxf(float(part.height), float(feature.get("level", 0)) + 2.0))): return 0.0
	return 1.0

static func _fire_smoke_key(cell: int, layer: int) -> String:
	return "%d:%d" % [cell, layer]

static func _fire_smoke_add(values: Dictionary, cell: int, layer: int, amount: float) -> void:
	if amount <= 0.0: return
	var key := _fire_smoke_key(cell, layer)
	if not values.has(key): values[key] = {"cell": cell, "layer": layer, "density": 0.0}
	values[key].density = float(values[key].density) + amount

static func _fire_smoke_preview(data: TerrainData, state: Dictionary, old: Dictionary, descriptors: Dictionary, begin: float, end: float) -> Dictionary:
	var profile := SiteCombatRules.fire_environment_profile()
	var dt := end - begin
	var previous: Dictionary = state.get("smoke", {})
	var next := {}
	var keys: Array = previous.keys()
	keys.sort()
	for key: String in keys:
		var entry: Dictionary = previous[key]
		var source := data.cell_from_index(int(entry.cell))
		var layer := int(entry.layer)
		var density := float(entry.density)
		var neighbours: Array[Dictionary] = []
		var weights := 0.0
		var height := float(layer) + float(profile.smoke_vertical_span) * 0.5
		if _fire_air_column_open(data, source, height):
			for direction: Vector2i in TerrainData.DIRECTIONS:
				var cell := source + direction
				if not _fire_air_column_open(data, cell, height): continue
				# Original cliff/structure prisms reject this edge before wind weights.
				var weight := fire_wind_weight(data, source, cell, begin, end)
				neighbours.append({"cell": data.index(cell), "weight": weight})
				weights += weight
		var moved := minf(density, density * float(profile.smoke_transfer_per_second) * dt) if weights > 0.0 else 0.0
		_fire_smoke_add(next, int(entry.cell), layer, density - moved)
		for neighbour: Dictionary in neighbours: _fire_smoke_add(next, int(neighbour.cell), layer, moved * float(neighbour.weight) / weights)
	keys = old.keys()
	keys.sort()
	for key: String in keys:
		var unit: Dictionary = old[key]
		var descriptor: Dictionary = descriptors.get(key, {})
		if float(unit.intensity) <= 0.0 or descriptor.is_empty() or not bool(descriptor.get("smoke_outdoor", true)): continue
		var cells: Array = descriptor.get("smoke_cells", descriptor.hazard_cells)
		if cells.is_empty(): continue
		var burn := SiteCombatRules.fire_profile(str(unit.profile))
		var emitted := float(burn.get("smoke_per_second", profile.smoke_source_per_second)) * float(unit.intensity) * dt
		var layer := floori(float(descriptor.get("smoke_height", descriptor.height)))
		for value: int in cells: _fire_smoke_add(next, value, layer, emitted / cells.size())
	var decay := exp(-float(profile.smoke_decay_per_second) * dt)
	for key: String in next.keys():
		next[key].density = float(next[key].density) * decay
		if float(next[key].density) < float(profile.smoke_min_density): next.erase(key)
	if next.size() > int(profile.smoke_field_cap): return fail("SMOKE_FIELD_CAPACITY")
	return ok("", {"smoke": next})

static func _fire_smoke_columns(data: TerrainData) -> Dictionary:
	if data == null: return {}
	var state: Dictionary = data.site.get("fire", {})
	var saved: Dictionary = data.get_meta(&"fire_smoke_columns", {})
	if not saved.is_empty() and is_same(saved.owner, state) and int(saved.step) == int(state.get("step_index", -1)): return saved.cells
	var cells := {}
	var keys: Array = state.get("smoke", {}).keys()
	keys.sort()
	for key: String in keys:
		var entry: Dictionary = state.smoke[key]
		if not cells.has(int(entry.cell)): cells[int(entry.cell)] = []
		cells[int(entry.cell)].append(entry)
	data.set_meta(&"fire_smoke_columns", {"owner": state, "step": int(state.get("step_index", -1)), "cells": cells})
	return cells

static func fire_smoke_optical_depth(data: TerrainData, from: Vector3, to: Vector3) -> float:
	if data == null or not is_finite(from.x) or not is_finite(from.y) or not is_finite(from.z) \
		or not is_finite(to.x) or not is_finite(to.y) or not is_finite(to.z): return 0.0
	var distance := from.distance_to(to)
	if distance <= FIRE_EPS: return 0.0
	var columns := _fire_smoke_columns(data)
	if columns.is_empty(): return 0.0
	var knots: Array[float] = [0.0, 1.0]
	for axis in range(2):
		if absf(to[axis] - from[axis]) <= FIRE_EPS: continue
		for boundary in range(floori(minf(from[axis], to[axis])) + 1, ceili(maxf(from[axis], to[axis]))):
			knots.append((float(boundary) - from[axis]) / (to[axis] - from[axis]))
	knots.sort()
	var depth := 0.0
	var span := float(SiteCombatRules.fire_environment_profile().smoke_vertical_span)
	for index in range(knots.size() - 1):
		var begin := knots[index]
		var end := knots[index + 1]
		if end <= begin: continue
		var point := from.lerp(to, (begin + end) * 0.5)
		var cell := Vector2i(floori(point.x), floori(point.y))
		if not data.contains(cell): continue
		for entry: Dictionary in columns.get(data.index(cell), []):
			var low := float(entry.layer)
			var high := low + span
			var entered := begin
			var exited := end
			if absf(to.z - from.z) <= FIRE_EPS:
				if from.z < low or from.z > high: continue
			else:
				var a := (low - from.z) / (to.z - from.z)
				var b := (high - from.z) / (to.z - from.z)
				entered = maxf(entered, minf(a, b))
				exited = minf(exited, maxf(a, b))
			depth += maxf(0.0, exited - entered) * distance * float(entry.density)
	return depth

static func fire_smoke_scatter_scale(data: TerrainData, from: Vector3, to: Vector3) -> float:
	var profile := SiteCombatRules.fire_environment_profile()
	return clampf(1.0 + fire_smoke_optical_depth(data, from, to) * float(profile.smoke_scatter_per_depth), 1.0, float(profile.smoke_scatter_max))

static func fire_smoke_visible(data: TerrainData, source: Vector2i, target: Vector2i) -> bool:
	if data == null or not data.contains(source) or not data.contains(target): return false
	var from := Vector3(source.x + 0.5, source.y + 0.5, float(data.effective_height(source)) + 1.0)
	var to := Vector3(target.x + 0.5, target.y + 0.5, float(data.effective_height(target)) + 1.0)
	return fire_smoke_optical_depth(data, from, to) < float(SiteCombatRules.fire_environment_profile().smoke_visibility_depth)

# P5 pure JSON validation for the EXISTING SiteRuntime fire owner.
# This does not admit hot saves: the original all-owner barrier remains required.
static func _fire_snapshot_keys(value: Variant, required: Array, optional: Array = []) -> bool:
	if not value is Dictionary: return false
	for key: Variant in value:
		if not key is String or key not in required and key not in optional: return false
	for key: String in required:
		if not value.has(key): return false
	return true

static func _fire_snapshot_json(value: Variant, depth: int = 0) -> bool:
	if depth > 12: return false
	if value == null or value is bool or value is String: return true
	if value is int or value is float: return is_finite(float(value))
	if value is Array:
		for child: Variant in value:
			if not _fire_snapshot_json(child, depth + 1): return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not _fire_snapshot_json(value[key], depth + 1): return false
		return true
	return false

static func _fire_snapshot_json_copy(value: Variant) -> Variant:
	if value is StringName: return str(value)
	if value is Dictionary:
		var copy := {}
		for key: Variant in value:
			if not key is String and not key is StringName: return NAN
			var normalized_key := str(key)
			if copy.has(normalized_key): return NAN
			copy[normalized_key] = _fire_snapshot_json_copy(value[key])
		return copy
	if value is Array:
		var copy: Array = []
		for child: Variant in value: copy.append(_fire_snapshot_json_copy(child))
		return copy
	return value

static func _fire_snapshot_id(value: Variant, low: int = 0) -> bool:
	return value is String and str(value).is_valid_int() and str(int(value)) == value and _building_integer(int(value), low, 2147483647)

static func validate_fire_snapshot(data: TerrainData, raw: Variant, action_cursor: float) -> Dictionary:
	if data == null or not _fire_time_valid(action_cursor) or not raw is Dictionary or not _fire_snapshot_json(raw): return fail("INVALID_FIRE_SNAPSHOT")
	if raw.is_empty(): return ok("", {"state": {}})
	if not _fire_snapshot_keys(raw, ["version", "config_version", "site_id", "step_index", "observed_action_end", "receipt_floor", "receipt_ids", "units", "active", "contacts", "repair_generations", "dirty"],
		["suppression_sequence", "suppression_pending", "weather", "smoke", "collapse_next_sequence", "collapse_warnings", "collapse_receipts", "structure_pending", "contents_remainders", "inventory_pending", "inventory_receipts"]): return fail("INVALID_FIRE_FIELDS")
	if not _building_integer(raw.version, FIRE_VERSION, FIRE_VERSION) or raw.config_version != FIRE_CONFIG_VERSION \
		or raw.site_id != str(data.site.get("id", "")) or not raw.dirty is bool \
		or not _building_integer(raw.step_index, 0, FIRE_MAX_STEP) or not _building_integer(raw.receipt_floor, 0, 2147483647) \
		or not _building_number(raw.observed_action_end, 0.0, float(FIRE_MAX_STEP) / FIRE_HZ) \
		or absf(float(raw.observed_action_end) - action_cursor) > FIRE_EPS \
		or int(raw.step_index) != floori(action_cursor * FIRE_HZ + FIRE_EPS): return fail("INVALID_FIRE_BARRIER")
	for field: String in ["receipt_ids", "units", "active", "contacts", "repair_generations"]:
		if not raw[field] is Dictionary or raw[field].size() > 65536: return fail("INVALID_FIRE_COLLECTION")
	var state: Dictionary = raw.duplicate(true)
	for field: String in ["version", "step_index", "receipt_floor"]: state[field] = int(raw[field])
	state.receipt_ids = {}
	for key: String in raw.receipt_ids:
		if not _fire_snapshot_id(key, 1) or int(key) <= int(raw.receipt_floor) or not raw.receipt_ids[key] is bool or raw.receipt_ids[key] != true: return fail("INVALID_FIRE_RECEIPT")
		state.receipt_ids[int(key)] = true
	for key: String in raw.units:
		var checked := _validate_fire_unit_snapshot(data, key, raw.units[key], action_cursor)
		if not checked.ok: return checked
		state.units[key] = checked.unit
	for key: String in raw.active:
		if not raw.active[key] is bool or raw.active[key] != true or not state.units.has(key): return fail("INVALID_FIRE_ACTIVE")
	for key: String in raw.contacts:
		var value: Variant = raw.contacts[key]
		if not _fire_snapshot_keys(value, ["event_id", "projectile_id", "unit_key", "generation", "start_action", "end_action", "budget", "rate"]): return fail("INVALID_FIRE_CONTACT")
		var contact: Dictionary = value
		if not _building_integer(contact.projectile_id, 1, 2147483647) or key != "arrow:%d" % int(contact.projectile_id) or contact.event_id != key \
			or not contact.unit_key is String or not state.units.has(contact.unit_key) or not _building_integer(contact.generation, 1, 2147483647) \
			or int(contact.generation) != int(state.units[contact.unit_key].generation) \
			or not _building_number(contact.start_action, 0.0, action_cursor) or not _building_number(contact.end_action, 0.0, float(FIRE_MAX_STEP) / FIRE_HZ) \
			or float(contact.end_action) <= maxf(float(contact.start_action), float(state.step_index) / FIRE_HZ) \
			or not _building_number(contact.budget, FIRE_EPS, 1.0e12) or not _building_number(contact.rate, FIRE_EPS, 1.0e12) \
			or not state.active.has(contact.unit_key) \
			or int(contact.projectile_id) > int(state.receipt_floor) and not state.receipt_ids.has(int(contact.projectile_id)):
			return fail("INVALID_FIRE_CONTACT")
		state.contacts[key].projectile_id = int(contact.projectile_id)
		state.contacts[key].generation = int(contact.generation)
	for key: String in raw.repair_generations:
		if not state.units.has(key) or str(state.units[key].kind) != "feature" or not _building_integer(raw.repair_generations[key], 1, int(state.units[key].generation)):
			return fail("INVALID_FIRE_REPAIR")
		state.repair_generations[key] = int(raw.repair_generations[key])
	var work := _validate_fire_inputs_snapshot(state, action_cursor)
	if not work.ok: return work
	if state.has("weather"):
		var weather := _validate_fire_weather_snapshot(state.weather, action_cursor)
		if not weather.ok: return weather
		state.weather = weather.weather
	if state.has("smoke"):
		var smoke := _validate_fire_smoke_snapshot(data, state.smoke)
		if not smoke.ok: return smoke
		state.smoke = smoke.smoke
	var structures := _validate_fire_structure_snapshot(data, state)
	if not structures.ok: return structures
	var contents := _validate_fire_inventory_snapshot(data, state)
	if not contents.ok: return contents
	for key: String in state.units:
		if float(state.units[key].heat) > FIRE_EPS and not state.active.has(key): return fail("INVALID_FIRE_ACTIVE")
	return ok("", {"state": state})

static func _validate_fire_unit_snapshot(data: TerrainData, key: String, raw: Variant, action_cursor: float) -> Dictionary:
	var common := ["generation", "kind", "profile", "surface_id", "height", "heat", "state", "intensity", "moisture", "scorch", "burn_remainder_q", "fuel_remainder_q", "residue_q"]
	if not raw is Dictionary or raw.get("kind") not in ["resource", "feature"]: return fail("INVALID_FIRE_UNIT")
	var kind := str(raw.kind)
	common.append_array(["resource"] if kind == "resource" else ["feature", "part", "fuel_max_q", "fuel_q"])
	if not _fire_snapshot_keys(raw, common, ["moisture_action", "debris_version", "standing_generation"]): return fail("INVALID_FIRE_UNIT_FIELDS")
	if not _building_integer(raw.generation, 1, 2147483647) or raw.profile not in ["TIMBER", "WOOD_COMPONENT"] or not raw.surface_id is String \
		or not _building_number(raw.height, -1000000.0, 1000000.0) or not _building_number(raw.moisture, 0.0, 1.0) \
		or not _building_number(raw.scorch, 0.0, 1.0) or not _building_number(raw.intensity, 0.0, 1.0) \
		or not _building_number(raw.burn_remainder_q, 0.0, 1.0) or float(raw.burn_remainder_q) >= 1.0 \
		or not _building_integer(raw.fuel_remainder_q, 0, FIRE_Q - 1) or not _building_integer(raw.residue_q, 0, 2147483647) \
		or raw.state not in ["DORMANT", "HEATING", "BURNING", "EMBERS", "COOLING"] \
		or raw.has("moisture_action") and not _building_number(raw.moisture_action, 0.0, action_cursor): return fail("INVALID_FIRE_UNIT")
	if kind == "resource":
		if not raw.resource is String or key != _fire_unit_key(kind, raw.resource): return fail("INVALID_FIRE_UNIT_OWNER")
	else:
		if not raw.feature is String or not raw.part is String or key != _fire_unit_key(kind, raw.feature, raw.part) \
			or not _building_integer(raw.fuel_max_q, 1, 2147483647) or not _building_integer(raw.fuel_q, 0, int(raw.fuel_max_q)) \
			or int(raw.fuel_remainder_q) != 0 or int(raw.residue_q) != 0: return fail("INVALID_FIRE_UNIT_OWNER")
	if raw.has("debris_version") != raw.has("standing_generation"): return fail("INVALID_FIRE_DEBRIS")
	if raw.has("debris_version"):
		if kind != "feature" or not _building_integer(raw.debris_version, 1, 1) or not _building_integer(raw.standing_generation, 1, 2147483646) \
			or int(raw.generation) != int(raw.standing_generation) + 1 \
			or float(data.site.get("features", {}).get(str(raw.feature), {}).get("parts", {}).get(str(raw.part), {}).get("hp", 1.0)) != 0.0:
			return fail("INVALID_FIRE_DEBRIS")
	var profile := SiteCombatRules.fire_profile(str(raw.profile))
	if profile.is_empty() or not _building_number(raw.heat, 0.0, float(profile.heat_limit)): return fail("INVALID_FIRE_PROFILE")
	var descriptor := _fire_descriptor(data, raw)
	if descriptor.is_empty():
		# Original removal retains a cold, empty generation tombstone for receipts.
		if kind != "feature" or int(raw.generation) < 2 or int(raw.fuel_q) != 0 or float(raw.heat) != 0.0: return fail("STALE_FIRE_UNIT_OWNER")
	elif str(raw.profile) != str(descriptor.profile) or str(raw.surface_id) != str(descriptor.surface_id) \
		or absf(float(raw.height) - float(descriptor.height)) > FIRE_EPS \
		or kind == "feature" and int(raw.fuel_max_q) != int(descriptor.fuel_max_q): return fail("INVALID_FIRE_UNIT_DESCRIPTOR")
	if kind == "resource":
		var resource := Env.resource(data, raw.resource)
		if int(raw.residue_q) > int(resource.capacity) * FIRE_Q or bool(resource.cleared) and int(raw.fuel_remainder_q) != 0 \
			or not bool(resource.cleared) and int(raw.residue_q) != 0 \
			or int(resource.remaining) * FIRE_Q + int(raw.fuel_remainder_q) > int(resource.capacity) * FIRE_Q: return fail("INVALID_FIRE_FUEL")
	if str(raw.state) == "DORMANT" and (float(raw.heat) != 0.0 or float(raw.intensity) != 0.0) \
		or str(raw.state) == "BURNING" and (_fire_fuel_q(data, raw) <= 0 or float(raw.heat) <= 0.0 or float(raw.intensity) <= 0.0) \
		or str(raw.state) in ["HEATING", "COOLING"] and float(raw.intensity) != 0.0: return fail("INVALID_FIRE_PHASE")
	var unit: Dictionary = raw.duplicate(true)
	for field: String in ["generation", "fuel_remainder_q", "residue_q"]: unit[field] = int(raw[field])
	if kind == "feature": unit.fuel_q = int(raw.fuel_q); unit.fuel_max_q = int(raw.fuel_max_q)
	if raw.has("debris_version"): unit.debris_version = 1; unit.standing_generation = int(raw.standing_generation)
	return ok("", {"unit": unit})

static func _validate_fire_inputs_snapshot(state: Dictionary, action_cursor: float) -> Dictionary:
	if state.has("suppression_sequence") != state.has("suppression_pending"): return fail("INVALID_FIRE_WORK_INPUT")
	if not state.has("suppression_pending"): return ok()
	if not _building_integer(state.suppression_sequence, 1, 2147483646) or not state.suppression_pending is Array \
		or state.suppression_pending.size() > int(SiteCombatRules.fire_work_profile().pending_cap): return fail("INVALID_FIRE_WORK_INPUT")
	state.suppression_sequence = int(state.suppression_sequence)
	var last_sequence := 0
	for raw: Variant in state.suppression_pending:
		if not _fire_snapshot_keys(raw, ["sequence", "key", "generation", "mode", "begin", "end", "total_q", "remaining_q", "cooling_per_q", "heating_per_q", "moisture_per_q"]): return fail("INVALID_FIRE_WORK_INPUT")
		if raw.mode not in ["SUPPRESS", "IGNITE"] or not raw.key is String or not _building_integer(raw.sequence, last_sequence + 1, int(state.suppression_sequence)) \
			or not _building_integer(raw.generation, 1, 2147483647) or not _building_number(raw.begin, 0.0, action_cursor) \
			or not _building_number(raw.end, 0.0, action_cursor) or float(raw.end) <= maxf(float(raw.begin), float(state.step_index) / FIRE_HZ): return fail("INVALID_FIRE_WORK_INPUT")
		var profile := SiteCombatRules.fire_work_profile(str(raw.mode))
		if not _building_integer(raw.total_q, 1, int(profile.supply_cap_q)) or not _building_number(raw.remaining_q, FIRE_EPS, float(raw.total_q)): return fail("INVALID_FIRE_WORK_INPUT")
		var duration := float(raw.end) - float(raw.begin)
		var expected_remaining := float(raw.total_q) * (float(raw.end) - maxf(float(raw.begin), float(state.step_index) / FIRE_HZ)) / duration
		if int(raw.total_q) > ceili(duration * int(profile.supply_q_per_second) + FIRE_EPS) + 1 \
			or absf(float(raw.remaining_q) - expected_remaining) > 0.000001: return fail("INVALID_FIRE_WORK_AMOUNT")
		for field: String in ["cooling", "heating", "moisture"]:
			var name := field + "_per_q"
			var expected := float(profile[field + "_per_second"]) / int(profile.supply_q_per_second)
			if not _building_number(raw[name], 0.0, 1.0e12) or absf(float(raw[name]) - expected) > FIRE_EPS: return fail("INVALID_FIRE_WORK_COEFFICIENT")
		# A paid stale generation remains inert until the same original next step.
		# Never refund it or attach it to a replacement generation on load.
		if not state.units.has(raw.key) or int(raw.generation) > int(state.units[raw.key].generation): return fail("INVALID_FIRE_WORK_GENERATION")
		last_sequence = int(raw.sequence)
		for field: String in ["sequence", "generation", "total_q"]: raw[field] = int(raw[field])
	return ok()

static func _validate_fire_weather_snapshot(raw: Variant, action_cursor: float) -> Dictionary:
	var profile := SiteCombatRules.fire_environment_profile()
	if not _fire_snapshot_keys(raw, ["config_version", "sequence", "history"]) or raw.config_version != profile.config_version \
		or not _building_integer(raw.sequence, 1, 2147483646) or not raw.history is Array or raw.history.is_empty() \
		or raw.history.size() > int(profile.weather_history_cap) + 1 \
		or raw.history.size() < int(raw.sequence) or raw.history.size() > int(raw.sequence) + 1: return fail("INVALID_FIRE_WEATHER")
	var last := -1.0
	for row: Variant in raw.history:
		if not _fire_snapshot_keys(row, ["action_time", "wind_x", "wind_y", "rain", "drying"]) \
			or not _building_number(row.action_time, 0.0, action_cursor) or float(row.action_time) < last \
			or not _building_number(row.wind_x, -1.0, 1.0) or not _building_number(row.wind_y, -1.0, 1.0) \
			or float(row.wind_x) * float(row.wind_x) + float(row.wind_y) * float(row.wind_y) > 1.0 + FIRE_EPS \
			or not _building_number(row.rain, 0.0, 1.0) or not _building_number(row.drying, 0.0, 1.0): return fail("INVALID_FIRE_WEATHER")
		last = float(row.action_time)
	if float(raw.history[0].action_time) != 0.0: return fail("INVALID_FIRE_WEATHER_GENESIS")
	if raw.history.size() == int(raw.sequence) + 1:
		var genesis: Dictionary = raw.history[0]
		if float(genesis.wind_x) != 0.0 or float(genesis.wind_y) != 0.0 or float(genesis.rain) != 0.0 \
			or absf(float(genesis.drying) - 0.02) > FIRE_EPS or float(raw.history[1].action_time) <= 0.0:
			return fail("INVALID_FIRE_WEATHER_GENESIS")
	var weather: Dictionary = raw.duplicate(true)
	weather.sequence = int(raw.sequence)
	return ok("", {"weather": weather})

static func _validate_fire_smoke_snapshot(data: TerrainData, raw: Variant) -> Dictionary:
	var profile := SiteCombatRules.fire_environment_profile()
	if not raw is Dictionary or raw.size() > int(profile.smoke_field_cap): return fail("INVALID_FIRE_SMOKE")
	var smoke := {}
	for key: String in raw:
		var row: Variant = raw[key]
		if not _fire_snapshot_keys(row, ["cell", "layer", "density"]) or not _building_integer(row.cell, 0, data.size.x * data.size.y - 1) \
			or not _building_integer(row.layer, -1000000, 1000000) or key != _fire_smoke_key(int(row.cell), int(row.layer)) \
			or not _building_number(row.density, float(profile.smoke_min_density), 1.0e12): return fail("INVALID_FIRE_SMOKE")
		smoke[key] = {"cell": int(row.cell), "layer": int(row.layer), "density": float(row.density)}
	return ok("", {"smoke": smoke})

static func capture_fire_snapshot(data: TerrainData, action_cursor: float) -> Dictionary:
	if data == null or not data.get_meta(&"fire_boundary", {}).is_empty() or data.has_meta(&"fire_structure_step"): return fail("BUSY", "原接觸／結構邊界未完成")
	if data.site.has("fire") and not data.site.fire is Dictionary: return fail("INVALID_FIRE_SNAPSHOT")
	var raw: Dictionary = data.site.get("fire", {}).duplicate(true)
	if not raw.is_empty():
		if not raw.get("receipt_ids") is Dictionary: return fail("INVALID_FIRE_RECEIPT")
		var receipts := {}
		for identity: Variant in raw.get("receipt_ids", {}):
			if not identity is int: return fail("INVALID_FIRE_RECEIPT")
			receipts[str(identity)] = raw.receipt_ids[identity]
		raw.receipt_ids = receipts
	var normalized: Variant = _fire_snapshot_json_copy(raw)
	if not normalized is Dictionary or not _fire_snapshot_json(normalized): return fail("INVALID_FIRE_SNAPSHOT")
	raw = normalized
	var check := validate_fire_snapshot(data, raw, action_cursor)
	if not check.ok: return check
	return ok("", {"state": raw})

static func _validate_fire_structure_snapshot(data: TerrainData, state: Dictionary) -> Dictionary:
	var has_collapse := state.has("collapse_next_sequence") or state.has("collapse_warnings") or state.has("collapse_receipts")
	var sequences := {}
	if has_collapse:
		if not _building_integer(state.get("collapse_next_sequence"), 1, 2147483647) or not state.get("collapse_warnings") is Dictionary \
			or not state.get("collapse_receipts") is Dictionary or state.collapse_warnings.size() > 65536 or state.collapse_receipts.size() > 65536:
			return fail("INVALID_FIRE_COLLAPSE")
		state.collapse_next_sequence = int(state.collapse_next_sequence)
		for key: String in state.collapse_warnings:
			var row: Variant = state.collapse_warnings[key]
			var unit: Dictionary = state.units.get(key, {})
			if not _fire_snapshot_keys(row, ["version", "generation", "sequence", "due_step"]) or unit.is_empty() or str(unit.kind) != "feature" \
				or unit.has("debris_version") or not _building_integer(row.version, 1, 1) \
				or not _building_integer(row.generation, int(unit.generation), int(unit.generation)) \
				or not _building_integer(row.sequence, 1, int(state.collapse_next_sequence) - 1) \
				or not _building_integer(row.due_step, 0, mini(FIRE_MAX_STEP, int(state.step_index) + 10)) or sequences.has(int(row.sequence)):
				return fail("INVALID_FIRE_COLLAPSE_WARNING")
			var feature: Dictionary = data.site.get("features", {}).get(str(unit.feature), {})
			if feature.is_empty() or not feature.get("parts", {}).has(str(unit.part)): return fail("INVALID_FIRE_COLLAPSE_OWNER")
			var hp := float(feature.get("parts", {}).get(str(unit.part), {}).get("hp", 0.0))
			var maximum := float(feature_geometry(data, feature).get("parts", {}).get(str(unit.part), {}).get("max_hp", 0.0))
			if hp <= 0.0 or maximum <= 0.0 or hp > maximum * 0.25 + FIRE_EPS: return fail("INVALID_FIRE_COLLAPSE_OWNER")
			sequences[int(row.sequence)] = true
			for field: String in ["version", "generation", "sequence", "due_step"]: row[field] = int(row[field])
		for receipt_id: String in state.collapse_receipts:
			var row: Variant = state.collapse_receipts[receipt_id]
			var boundary := receipt_id.rfind("@")
			if boundary <= 0: return fail("INVALID_FIRE_COLLAPSE_RECEIPT")
			var key := receipt_id.left(boundary)
			var unit: Dictionary = state.units.get(key, {})
			if not _fire_snapshot_keys(row, ["version", "generation", "sequence", "step"]) or unit.is_empty() or str(unit.kind) != "feature" \
				or not _building_integer(row.version, 1, 1) or not _building_integer(row.generation, 1, int(unit.generation) - 1) \
				or receipt_id != key + "@" + str(int(row.generation)) or not _building_integer(row.sequence, 0, int(state.collapse_next_sequence) - 1) \
				or not _building_integer(row.step, 0, int(state.step_index)) or int(row.sequence) > 0 and sequences.has(int(row.sequence)):
				return fail("INVALID_FIRE_COLLAPSE_RECEIPT")
			if int(row.sequence) > 0: sequences[int(row.sequence)] = true
			for field: String in ["version", "generation", "sequence", "step"]: row[field] = int(row[field])
	for key: String in state.units:
		var unit: Dictionary = state.units[key]
		if unit.has("debris_version") and not state.get("collapse_receipts", {}).has(key + "@" + str(unit.standing_generation)):
			return fail("MISSING_FIRE_DEBRIS_RECEIPT")
	if not state.has("structure_pending"): return ok()
	if not state.structure_pending is Dictionary or state.structure_pending.size() > 65536: return fail("INVALID_FIRE_STRUCTURE_PENDING")
	for key: String in state.structure_pending:
		var row: Variant = state.structure_pending[key]
		if not _fire_snapshot_keys(row, ["feature", "part", "generation", "damage", "fire_damage", "collapse_generation"]) \
			or not row.feature is String or not row.part is String or key != str(row.feature) + "|" + str(row.part): return fail("INVALID_FIRE_STRUCTURE_PENDING")
		var unit_key := _fire_unit_key("feature", str(row.feature), str(row.part))
		var unit: Dictionary = state.units.get(unit_key, {})
		var feature: Dictionary = data.site.get("features", {}).get(str(row.feature), {})
		if feature.is_empty() or not feature.get("parts", {}).has(str(row.part)): return fail("INVALID_FIRE_STRUCTURE_PENDING")
		var maximum := float(feature_geometry(data, feature).get("parts", {}).get(str(row.part), {}).get("max_hp", 0.0))
		if unit.is_empty() or str(unit.kind) != "feature" or maximum <= 0.0 \
			or not _building_integer(row.generation, int(unit.generation), int(unit.generation)) \
			or not _building_number(row.damage, FIRE_EPS, maximum) or not _building_number(row.fire_damage, 0.0, float(row.damage)) \
			or not _building_integer(row.collapse_generation, 0, int(unit.generation)): return fail("INVALID_FIRE_STRUCTURE_PENDING")
		if int(row.collapse_generation) > 0:
			var warning: Dictionary = state.get("collapse_warnings", {}).get(unit_key, {})
			if warning.is_empty() or int(row.collapse_generation) != int(warning.generation) \
				or int(warning.due_step) > int(state.step_index): return fail("INVALID_FIRE_STRUCTURE_PENDING_COLLAPSE")
		for field: String in ["generation", "collapse_generation"]: row[field] = int(row[field])
	return ok()

# P5 extension to the EXISTING Runtime validator for A's inventory adapter.
# Normalizes only the already-private candidate state; never consumes stock.
static func _validate_fire_inventory_snapshot(data: TerrainData, state: Dictionary) -> Dictionary:
	for field: String in ["contents_remainders", "inventory_pending", "inventory_receipts"]:
		if state.has(field) and (not state[field] is Dictionary or state[field].size() > 65536): return fail("INVALID_FIRE_INVENTORY_FIELDS")
	for feature_id: String in state.get("contents_remainders", {}):
		if not _fire_snapshot_id(feature_id, 1) or int(feature_id) >= int(data.site.get("next_feature", 1)) \
			or not _building_number(state.contents_remainders[feature_id], 0.0, 1.0) or float(state.contents_remainders[feature_id]) >= 1.0:
			return fail("INVALID_FIRE_CONTENTS_REMAINDER")
		# Original exposure retains this fraction after cooling or feature removal.
		# It is not converted to fuel, stock or a new running damage event on load.
		state.contents_remainders[feature_id] = float(state.contents_remainders[feature_id])
	var consumed_items := {}
	for event_id: String in state.get("inventory_receipts", {}):
		var checked := _validate_fire_inventory_record(data, state, event_id, state.inventory_receipts[event_id], false)
		if not checked.ok: return checked
		for identity: String in checked.record.item_ids:
			if consumed_items.has(identity) or data.site.get("item_records", {}).has(identity): return fail("INVALID_FIRE_INVENTORY_RECEIPT_ITEM")
			consumed_items[identity] = true
		state.inventory_receipts[event_id] = checked.record
	for event_id: String in state.get("inventory_pending", {}):
		if state.get("inventory_receipts", {}).has(event_id): return fail("DUPLICATE_FIRE_INVENTORY_EVENT")
		var checked := _validate_fire_inventory_record(data, state, event_id, state.inventory_pending[event_id], true)
		if not checked.ok: return checked
		state.inventory_pending[event_id] = checked.record
	return ok()

static func _validate_fire_inventory_record(data: TerrainData, state: Dictionary, event_id: String, raw: Variant, pending: bool) -> Dictionary:
	var fields := ["version", "feature_id", "source_unit_key", "source_generation", "step", "holder_id", "resources", "item_ids"]
	fields.append_array(["event_id", "site_id", "expected_version"] if pending else ["holder_version"])
	if not _fire_snapshot_keys(raw, fields) or not _building_integer(raw.version, 1, 1) \
		or not _fire_snapshot_id(raw.feature_id, 1) or int(raw.feature_id) >= int(data.site.get("next_feature", 1)) \
		or not raw.source_unit_key is String or str(raw.source_unit_key).length() > 512 \
		or not str(raw.source_unit_key).begins_with("feature:" + str(raw.feature_id) + ":") \
		or str(raw.source_unit_key).length() <= ("feature:" + str(raw.feature_id) + ":").length() \
		or not _building_integer(raw.source_generation, 1, 2147483647) or not _building_integer(raw.step, 0, int(state.step_index)) \
		or raw.holder_id != "feature:" + str(raw.feature_id) or not raw.resources is Dictionary or raw.resources.size() > FIRE_COMBUSTIBLE_STACKS.size() \
		or not raw.item_ids is Array or raw.item_ids.size() > 1: return fail("INVALID_FIRE_INVENTORY_RECORD")
	if event_id != "contents:%d:%s@%d" % [int(raw.step), str(raw.source_unit_key), int(raw.source_generation)]: return fail("INVALID_FIRE_INVENTORY_EVENT")
	if pending:
		if raw.event_id != event_id or raw.site_id != str(data.site.id) or not _building_integer(raw.expected_version, 0, 2147483645): return fail("INVALID_FIRE_INVENTORY_REQUEST")
	elif not _building_integer(raw.holder_version, 1, 2147483646): return fail("INVALID_FIRE_INVENTORY_RECEIPT")
	var record: Dictionary = raw.duplicate(true)
	var amount: int = raw.item_ids.size()
	for resource: String in raw.resources:
		if resource not in FIRE_COMBUSTIBLE_STACKS or not _building_integer(raw.resources[resource], 0 if pending else 1, 1): return fail("INVALID_FIRE_INVENTORY_QUANTITY")
		amount += int(raw.resources[resource])
		record.resources[resource] = int(raw.resources[resource])
	if amount > 1: return fail("INVALID_FIRE_INVENTORY_QUANTITY")
	for identity: Variant in raw.item_ids:
		if not _fire_snapshot_id(identity, 1) or int(identity) >= int(data.site.get("next_item", 1)): return fail("INVALID_FIRE_INVENTORY_ITEM")
	var unit: Dictionary = state.units.get(str(raw.source_unit_key), {})
	if not unit.is_empty() and (str(unit.kind) != "feature" or str(unit.feature) != str(raw.feature_id) or int(raw.source_generation) > int(unit.generation)):
		return fail("INVALID_FIRE_INVENTORY_SOURCE")
	if pending:
		if unit.is_empty() or int(raw.source_generation) != int(unit.generation): return fail("INVALID_FIRE_INVENTORY_SOURCE")
		var feature: Dictionary = data.site.get("features", {}).get(str(raw.feature_id), {})
		if int(feature.get("fire_layout_version", 0)) != FIRE_LAYOUT_VERSION or not feature.get("parts", {}).has("roof") \
			or not _building_number(feature.parts.roof.get("hp"), 0.0, 0.0): return fail("INVALID_FIRE_INVENTORY_EXPOSURE")
		var stock: Dictionary = data.site.get("stockpiles", {}).get(str(raw.feature_id), {})
		if not stock.get("holder") is Dictionary or not stock.get("cargo") is Dictionary \
			or not _item_holder_shape(stock.holder) or not _resource_stack(stock.cargo) or stock.holder.holder != raw.holder_id \
			or int(raw.expected_version) > int(stock.holder.version): return fail("INVALID_FIRE_INVENTORY_HOLDER")
		# A later original stock transfer can leave an older finite request at the
		# same completed barrier. Preserve that version; the existing adapter alone
		# performs its ordinary one-time revalidation/clamp on the next 5 Hz step.
		for identity: String in raw.item_ids:
			if not stock.holder.item_ids.has(identity): continue
			var item: Dictionary = data.site.get("item_records", {}).get(identity, {})
			var definition: Dictionary = data.site.get("item_definitions", {}).get(str(item.get("definition", "")), {})
			if item.get("holder") != raw.holder_id or definition.is_empty() or not _fire_item_combustible(definition): return fail("INVALID_FIRE_INVENTORY_ITEM")
	for field: String in ["version", "source_generation", "step"]: record[field] = int(raw[field])
	var version_field := "expected_version" if pending else "holder_version"
	record[version_field] = int(raw[version_field])
	return ok("", {"record": record})


# Merge into ORIGINAL SiteRuntime, with existing Technology/TechnologyPolicy
# preloads. This is a pure query of the exact task consumed by original _work.
static func _technology_actions(data: TerrainData) -> Variant:
	if data == null or not data.has_meta(&"site_person_actions"): return null
	var ref_value: Variant = data.get_meta(&"site_person_actions", null)
	if not ref_value is WeakRef: return null
	var actions: Variant = ref_value.get_ref()
	return actions if actions != null and actions.has_method("_technology_operator_for_task") and is_same(actions.lab.terrain, data) else null

static func _technology_policy(data: TerrainData) -> Dictionary:
	if not data.site.has("world_pin"): return TechnologyPolicy.new_policy()
	var pin: Variant = data.site.world_pin
	if not pin is Dictionary or not Technology.integer(pin.get("format"), 1, 2): return fail("INVALID_TECH_POLICY", "原固定世界政策容器失效")
	return TechnologyPolicy.candidate(pin, int(pin.format) == 1)

static func work_preflight(data: TerrainData, task: Dictionary, cargo: Dictionary, carry_limit: int, worker_faction: int, original_identity: int = 0, occupied: Callable = Callable()) -> Dictionary:
	if data == null or data.site.is_empty() or bool(data.site.get("paused", false)) or task.is_empty() or _fire_work_pending(data, task): return fail("BUSY")
	if str(task.get("mode", "")) != "work" or str(task.get("target", "")).is_empty() or int(task.get("cell", -1)) != int(task.get("work_cell", task.get("cell", -1))): return fail("WAITING", "原人尚未到原工位")
	var target := str(task.target)
	var action := str(task.get("action", "harvest"))
	var cell := data.cell_from_index(int(task.cell))
	var actions: Variant = _technology_actions(data)
	var person: Dictionary = actions._technology_operator_for_task(task, original_identity) if actions != null else {}
	var base := {"remaining": 0.0, "productivity": 1.0, "payment": {}, "payment_source": {}, "payment_key": "", "required_skill": "", "eligible_master": false}
	if target == "depot":
		var depot := data.cell_from_index(int(data.site.depot_cell))
		if absi(cell.x - depot.x) + absi(cell.y - depot.y) > 1 or cell != depot and not data.can_step(cell, depot): return fail("UNREACHABLE")
		var holder: Dictionary = data.site.get("depot_items", {})
		if inventory_size(data.site.inventory) + holder.get("item_ids", []).size() - holder.get("equipped", {}).size() + inventory_size(cargo) > int(data.site.capacity): return fail("STORAGE_FULL")
		return ok("原零工時交庫端點", base)
	if target.begins_with("vehicle:"):
		var key := target.trim_prefix("vehicle:")
		var vehicle: Dictionary = data.site.get("vehicles", {}).get(key, {})
		var ship := str(vehicle.get("kind", "")) == "ship"
		var field := "build" if action == "construct" else "repair"
		var job: Dictionary = vehicle.get("naval", {}).get("repair", {}) if ship else vehicle.get(field, {})
		if vehicle.is_empty() or job.is_empty() or action not in ["construct", "repair"] or float(vehicle.get("hp", 0.0)) <= 0.0: return fail("NO_TARGET")
		if not can_pay(data.site.inventory, {"tools": 1}): return fail("MATERIALS")
		if not person.is_empty() and int(vehicle.get("team_id", -1)) != int(person.owner.team_id): return fail("NO_AUTHORITY")
		var slot := int(task.get("work_slot", -1))
		if ship:
			var checked := advance_ship_repair_work(data, key, 0.00000001, cell, slot, int(vehicle.team_id), true)
			if not checked.ok: return checked
		else:
			if not SIEGE_DEFINITIONS.has(str(vehicle.get("kind", ""))) or not vehicle.get("action", {}).is_empty() or not vehicle.get("move", {}).is_empty() or not vehicle.get("crew_slots", {}).is_empty(): return fail("BUSY")
			var slots := siege_work_slots(data, vehicle)
			if slot < 0 or slot >= slots.size() or cell != data.cell_from_index(int(slots[slot].cell)) or not data.is_walkable(cell): return fail("UNREACHABLE")
			var policy := _technology_policy(data)
			if not policy.ok: return policy
			var category := TechnologyPolicy.siege_category(str(vehicle.kind), action)
			var trial_facts := technology_trial_work_facts(data, vehicle, task, original_identity) if action == "construct" else ok("", {"required_skill": "", "eligible_master": false})
			if not trial_facts.ok: return trial_facts
			if not category.is_empty() and policy.policy.categories.has(category) and str(trial_facts.get("policy_exception", "")) != category:
				base.required_skill = category
				base.eligible_master = not person.is_empty() and Technology.learned(actions._body_get(person, "technology"), category)
			if not str(trial_facts.required_skill).is_empty():
				if not str(base.required_skill).is_empty():
					var original_master: Dictionary = actions._person(int(vehicle.tech_trial.person.person_id))
					if original_master.is_empty() or not Technology.learned(actions._body_get(original_master, "technology"), category): return fail("NO_TECHNOLOGY")
				base.required_skill = str(trial_facts.required_skill)
				base.eligible_master = bool(trial_facts.eligible_master)
		base.remaining = maxf(0.0, float(job.total_work) - float(job.progress))
		return ok("原器具共同工單預檢", base)
	if not target.begins_with("feature:"):
		var resource := Env.resource(data, target)
		var ready := harvest(data, target, cell, cargo, action, true, carry_limit)
		if not ready.ok: return ready
		var required := resource_work_minutes(int(resource.kind), action)
		base.remaining = maxf(0.0, required - float(task.get("progress", 0.0))) * 60.0
		return ok("原資源工作預檢", base)
	var key := target.trim_prefix("feature:")
	var feature: Dictionary = data.site.get("features", {}).get(key, {})
	if feature.is_empty(): return fail("NO_TARGET")
	if int(feature.get("owner_faction", -1)) >= 0 and int(feature.owner_faction) != worker_faction: return fail("NO_AUTHORITY")
	var ecology_ready := ecology_feature_work_guard(data, feature, action)
	if not ecology_ready.ok: return ecology_ready
	var definition := feature_recipe(feature)
	var kind := str(feature.kind)
	var job: Dictionary = feature.repair if action == "repair" and feature.has("repair") else feature.get("pending_build", feature) if action == "construct" else feature
	var expected := int(job.get("work_cell", job.get("entrance", feature.entrance))) if action == "repair" else int(job.get("entrance", feature.entrance))
	var service: Array = []
	var slot := int(task.get("work_slot", -1))
	if action == "operate" and int(feature.get("layout_version", 0)) == BUILDING_LAYOUT_VERSION and kind in FARM_KINDS + PASTURE_KINDS:
		var slots := feature_work_slots(data, feature)
		if slot < 0 or slot >= slots.size(): return fail("UNREACHABLE")
		expected = int(slots[slot].cell)
		service = slots[slot].service_cells
	if int(task.cell) != expected: return fail("UNREACHABLE")
	if action == "operate" and str(feature.stage) == "complete" and definition.has("cycle") and bool(feature.get("batch_paid", false)) and float(feature.production) + 0.00000001 >= float(definition.cycle):
		# Paid completed goods are an original zero-work endpoint. Skills/tools
		# and new source costs apply only to future batches, never to pickup.
		var output_candidate := prepare_feature_output(data, feature, task, cargo, carry_limit, original_identity)
		if not output_candidate.ok: return output_candidate
		return ok("原已付完成品端點", base)
	if action == "operate" and str(feature.stage) == "complete" and kind == "shipyard":
		var checked := validate_ship_build(data, feature)
		if not checked.ok or not feature.has("ship_build"): return fail("NO_TARGET")
		base.remaining = maxf(0.0, float(feature.ship_build.total_work) - float(feature.production) * 60.0)
		if float(base.remaining) > 0.0 and not can_pay(data.site.inventory, {"tools": 1}): return fail("MATERIALS")
		var trial_facts := technology_trial_work_facts(data, feature, task, original_identity)
		if not trial_facts.ok: return trial_facts
		base.required_skill = str(trial_facts.required_skill)
		base.eligible_master = bool(trial_facts.eligible_master)
		return ok("原造船共同工作預檢", base)
	if action != "repair" and str(feature.stage) == "complete" and not feature_usable(feature): return fail("DESTROYED")
	if not can_pay(data.site.inventory, {"tools": 1}): return fail("MATERIALS")
	if action == "repair":
		if not feature.has("repair"): return fail("NO_TARGET")
		var fire_guard := _fire_repair_guard(data, key, str(job.part), true)
		if not fire_guard.ok: return fire_guard
		if not _repair_contact(data, feature, feature_geometry(data, feature).parts[str(job.part)], cell): return fail("UNREACHABLE")
		base.remaining = maxf(0.0, float(job.work) - float(job.progress)) * 60.0
		return ok("原修理工作預檢", base)
	if str(feature.stage) != "complete" or action == "construct" and feature.has("pending_build"):
		if feature.has("pending_build") and _fire_feature_hot(data, key): return fail("FIRE_HOT")
		for source: String in job.clearing:
			if not bool(Env.resource(data, source).get("cleared", true)): return fail("CLEARING")
		for index: int in job.get("added_cells", feature.cells):
			if occupied.is_valid() and bool(occupied.call(data.cell_from_index(index))): return fail("OCCUPIED")
		base.remaining = maxf(0.0, float(job.work) - float(job.progress)) * 60.0
		var trial_facts := technology_trial_work_facts(data, feature, task, original_identity)
		if not trial_facts.ok: return trial_facts
		base.required_skill = str(trial_facts.required_skill)
		base.eligible_master = bool(trial_facts.eligible_master)
		return ok("原施工工作預檢", base)
	if action != "operate" or feature.has("pending_build") or feature.has("repair"): return fail("BUSY")
	if not definition.has("cycle"): return fail("NO_TARGET")
	if feature.has("species") and (int(feature.residents) > grazing_capacity(data, feature.cells) or int(feature.residents) < (2 if str(feature.species) == "horse" else 1)): return fail("NO_RESIDENTS")
	var recipe_guard := technology_batch_operator_guard(data, key, feature, task, original_identity)
	if not recipe_guard.ok: return recipe_guard
	var water: Dictionary = data.site.get("water_status", {}).get(key, {})
	if not service.is_empty(): water = water.get("slots", {}).get(str(slot), {})
	var demand := float(water.get("demand", water_demand(feature)))
	var ratio := clampf(float(water.get("supplied", 0.0)) / demand, 0.0, 1.0) if demand > 0.0 else 1.0
	if ratio <= 0.0: return fail("NO_WATER")
	var productivity := 1.0
	if kind in FARM_KINDS:
		var fertility := 0.0
		var served: Array = feature.cells if service.is_empty() else service
		if served.is_empty(): return fail("NO_WORK_CELLS")
		for index: int in served: fertility += float(data.fertility[index])
		productivity = clampf(fertility / float(served.size()) / 60.0, 0.25, 1.5) * float(served.size())
	elif kind in PASTURE_KINDS and not service.is_empty():
		var total_service := 0
		for original_slot: Dictionary in _operating_slots(data, key, feature): total_service += original_slot.service_cells.size()
		productivity = _pasture_scale(data, feature, total_service) * float(service.size()) / maxf(1.0, float(total_service))
	productivity *= ratio * building_productivity(feature)
	if productivity <= 0.0: return fail("NO_WORK_CELLS")
	if inventory_size(cargo) + inventory_size(definition.get("output", {})) > carry_limit: return fail("STORAGE_FULL")
	if not bool(feature.get("batch_paid", false)):
		var stock := feature_input_inventory(data, feature, key)
		if not can_pay(stock, definition.input): return fail("MATERIALS")
		if str(feature.get("supply_mode", "")) == "local":
			var local: Dictionary = data.site.get("stockpiles", {}).get(key, {})
			if not _item_holder_shape(local.get("holder", {})) or int(local.holder.get("version", 2147483646)) >= 2147483646: return fail("INVALID")
		base.payment = definition.input.duplicate(true)
		base.payment_source = stock
		base.payment_key = "feature:" + key
	base.productivity = productivity
	var shared := slot >= 0 and kind in FARM_KINDS + PASTURE_KINDS
	base.remaining = maxf(0.0, float(definition.cycle) - float(feature.production)) * 60.0 / (1.0 if shared else productivity)
	return ok("原現場生產預檢", base)


static func technology_capture_valid(raw: Variant, allow_empty: bool = true) -> bool:
	if not raw is Dictionary: return false
	if raw.is_empty(): return allow_empty
	const FIELDS := ["version", "vehicle", "capture_id", "source_team_id", "source_faction", "recipient_team_id", "recipient_faction"]
	if raw.size() != FIELDS.size(): return false
	for field: String in FIELDS:
		if not raw.has(field): return false
	if not _building_integer(raw.version, 1, 1) or not raw.vehicle is Dictionary or raw.vehicle.size() != 2 \
		or not raw.vehicle.get("site_id") is String or raw.vehicle.site_id.is_empty() \
		or not raw.vehicle.get("vehicle_id") is String or raw.vehicle.vehicle_id.is_empty() \
		or not raw.capture_id is String or raw.capture_id.is_empty(): return false
	if not _building_integer(raw.source_team_id, 1, 999999) or not _building_integer(raw.recipient_team_id, 1, 999999) \
		or not _building_integer(raw.source_faction, 0, 999999) or not _building_integer(raw.recipient_faction, 0, 999999) \
		or int(raw.source_team_id) == int(raw.recipient_team_id) or int(raw.source_faction) == int(raw.recipient_faction): return false
	# Canonical tuple retains original source identity through Site ID rebasing.
	var tuple: Variant = JSON.parse_string(raw.capture_id)
	return tuple is Array and tuple.size() == 3 and tuple[0] == raw.vehicle.site_id and tuple[1] == raw.vehicle.vehicle_id \
		and _building_integer(tuple[2], 1, 2147483646) and JSON.stringify([tuple[0], tuple[1], int(tuple[2])]) == raw.capture_id

static func _technology_takeover_capture(data: TerrainData, identity: String, expected: Dictionary, new_team: int, live_lab: Variant) -> Dictionary:
	# No live original PA/completed ten-action-second job => no evidence. The
	# ordinary takeover remains legal when provenance cannot be confirmed.
	if live_lab == null or live_lab.terrain != data or live_lab.site_controller == null: return {}
	var actions: Variant = live_lab.site_controller.person_actions
	if actions == null or not actions.has_method("technology_capture_for_submit"): return {}
	var candidate: Dictionary = actions.technology_capture_for_submit(identity, expected, new_team)
	if not technology_capture_valid(candidate, false): return {}
	var vehicle: Dictionary = data.site.vehicles.get(identity, {})
	var recipient: Variant = null
	if live_lab.crowd_site != null and live_lab.crowd_site.active:
		recipient = live_lab.crowd_site.siege_team_owner(new_team)
	else:
		for team: TerrainArmy in live_lab.combat_armies:
			if int(team.team_id) == new_team and team.has_army(): recipient = team
	var source: Variant = live_lab.site_controller.vehicles._siege_team(vehicle)
	if source == null or recipient == null or candidate.vehicle != {"site_id": str(data.site.id), "vehicle_id": identity} \
		or int(candidate.source_team_id) != int(source.team_id) or int(candidate.source_faction) != int(source.faction_id) \
		or int(candidate.recipient_team_id) != new_team or int(candidate.recipient_faction) != int(recipient.faction_id) \
		or candidate.capture_id != JSON.stringify([str(data.site.id), identity, int(vehicle.holder.version) + 1]): return {}
	return candidate

const TECHNOLOGY_OUTPUT_FIELDS := ["id", "site_id", "feature_id", "operator_id", "recipe_id", "resources", "item_ids", "work_seconds"]


const TECHNOLOGY_TRIAL_FIELDS := ["scope", "scope_id", "project_id", "epoch", "purpose", "tech_id", "phase_id", "attempt", "person", "binding", "target_id", "materials"]


const TECHNOLOGY_BATCH_FIELDS := ["version", "id", "site_id", "feature_id", "operator_id", "recipe_id", "materials", "source_holder", "source_version", "work_seconds", "token", "payment_id"]


const TECHNOLOGY_FEATURE_BINDINGS := {
	"farm_grain": ["farm", ""], "retain_seed": ["farm", "retain_seed"],
	"charcoal": ["charcoal", ""], "charcoal_method": ["charcoal", "controlled_fire"],
	"iron": ["smelter", ""], "steel": ["smelter", "steel"], "steel_tools": ["smithy", "steel_tools"],
	"tools": ["smithy", ""], "rope": ["weaver", "rope"], "fiber_process": ["weaver", "prepared_rope"],
	"plant_cloth": ["weaver", ""], "wool_cloth": ["weaver", "wool_cloth"],
	"leather": ["tannery", ""], "leather_method": ["tannery", "careful_tan"],
	"workshop_bow": ["smithy", "bow"], "workshop_crossbow": ["smithy", "crossbow"],
	"leather_armor": ["tannery", "leather_armor"], "iron_armor": ["smithy", "iron_armor"],
}

# Candidate creation is used by the ORIGINAL create_equipment and batch endpoint.
# It allocates from original next_item and invokes the original item admission
# before any resource, definition, record, holder, feature or scope mutation.


static func prepare_equipment_creation(data: TerrainData, destination: Dictionary, products: Array, original_owner: int) -> Dictionary:
	if data == null or products.is_empty() or not _item_holder_shape(destination) or not Technology.integer(original_owner, 1): return fail("INVALID", "原物品產出人物／持有人")
	var state: Dictionary = data.site
	if int(state.get("item_storage_version", -1)) != ITEM_STORAGE_VERSION or not state.get("item_definitions") is Dictionary or not state.get("item_records") is Dictionary \
		or not Technology.integer(state.get("next_item"), 1, 2147483646) or int(destination.version) >= 2147483646: return fail("INVALID", "原實物帳本／版本失效")
	var next := int(state.next_item)
	if next + products.size() > 2147483647: return fail("STALE_SOURCE", "原物品序號已用盡")
	var definitions := {}
	var records := {}
	var ids: Array[String] = []
	var candidate: Dictionary = destination.duplicate(true)
	for product: Variant in products:
		if not Technology.keys(product, ["definition_id", "definition", "slot"]) or not product.definition_id is String or not product.definition is Dictionary or not product.slot is String: return fail("INVALID", "原製品格式")
		var definition_id := str(product.definition_id)
		var definition: Dictionary = product.definition
		var slot := str(product.slot)
		if not valid_item_definition(definition_id, definition): return fail("INVALID", "原物品定義")
		if state.item_definitions.has(definition_id) and state.item_definitions[definition_id] != definition or definitions.has(definition_id) and definitions[definition_id] != definition: return fail("INVALID", "不能覆寫既有共用物品定義")
		if not slot.is_empty() and (slot != str(definition.slot) or candidate.equipped.has(slot)): return fail("OCCUPIED", "原裝備槽")
		var identity := str(next + ids.size())
		if state.item_records.has(identity) or candidate.item_ids.has(identity): return fail("STALE_SOURCE", "原物品序號重複")
		ids.append(identity)
		definitions[definition_id] = definition.duplicate(true)
		records[identity] = {"definition": definition_id, "original_owner": original_owner, "holder": str(destination.holder)}
		candidate.item_ids.append(identity)
		if not slot.is_empty(): candidate.equipped[slot] = identity
	var before: Dictionary = destination.duplicate(true)
	if data.item_transfer_guard.is_valid():
		var checked: Dictionary = data.item_transfer_guard.call({}, destination, {}, ids)
		if not checked.ok: return checked
	if not is_same(state, data.site) or int(state.next_item) != next or destination != before: return fail("STALE_SOURCE")
	candidate.version = int(destination.version) + 1
	return ok("", {"state_ref": state, "destination_ref": destination, "destination_before": before, "destination_candidate": candidate,
		"expected_next_item": next, "next_item": next + ids.size(), "definitions": definitions, "records": records, "item_ids": ids})


static func _publish_equipment_creation(data: TerrainData, prepared: Dictionary) -> void:
	assert(prepared.ok and is_same(data.site, prepared.state_ref) and int(data.site.next_item) == int(prepared.expected_next_item) and prepared.destination_ref == prepared.destination_before)
	data.site.item_definitions.merge(prepared.definitions, true)
	data.site.item_records.merge(prepared.records, false)
	data.site.next_item = int(prepared.next_item)
	prepared.destination_ref.clear()
	prepared.destination_ref.merge(prepared.destination_candidate, true)

# REPLACE original create_equipment with this body; its existing signature stays.


static func _technology_trial_shape(raw: Variant, data: TerrainData) -> bool:
	if not Technology.keys(raw, TECHNOLOGY_TRIAL_FIELDS) or raw.scope not in ["family", "settlement", "nation"] or not raw.scope_id is String or raw.scope_id.is_empty() \
		or not Technology.integer(raw.project_id, 1) or not Technology.integer(raw.epoch, 1) or not raw.purpose is String or raw.purpose.is_empty() \
		or not raw.tech_id is String or not raw.phase_id is String or raw.phase_id.is_empty() or not Technology.integer(raw.attempt, 1) \
		or not Technology.valid_ref(raw.person) or str(raw.person.site_id) != str(data.site.get("id", "")) \
		or not raw.binding is String or not raw.target_id is String or raw.target_id.is_empty() or not Technology.material_stack(raw.materials): return false
	var node := TechnologyCatalog.get_node(str(raw.tech_id))
	return not node.is_empty() and str(node.scope) == str(raw.scope)

# Scope/task authority lives in the actual PA. No UI booleans, forged person
# snapshots, helper eligibility or runtime faction are sufficient for binding.


static func begin_technology_operation(data: TerrainData, token: Dictionary, preview: bool = false, work_target: Dictionary = {}) -> Dictionary:
	if data == null or not _technology_trial_shape(token, data): return fail("INVALID_TECHNOLOGY")
	var actions: Variant = _technology_actions(data)
	if actions == null or not actions.has_method("technology_phase_binding_candidate") or not actions.has_method("publish_phase_binding"): return fail("UNSUPPORTED", "原研習作業接線尚未發布")
	var resumed := _resume_technology_operation(data, token)
	if resumed.code != "NO_TARGET": return resumed
	if not work_target.is_empty(): return _begin_technology_geometry(data, token, work_target, preview)
	if not TECHNOLOGY_FEATURE_BINDINGS.has(str(token.binding)) or not str(token.target_id).begins_with("feature:"): return fail("NO_TARGET", "此操作須明示原幾何或原手作工作目標")
	var key := str(token.target_id).trim_prefix("feature:")
	var feature: Dictionary = data.site.get("features", {}).get(key, {})
	var binding: Array = TECHNOLOGY_FEATURE_BINDINGS[str(token.binding)]
	if feature.is_empty() or str(feature.get("kind", "")) != str(binding[0]) or str(feature.get("stage", "")) != "complete" or int(feature.get("layout_version", 0)) != BUILDING_LAYOUT_VERSION: return fail("NO_TARGET")
	var person: Dictionary = actions._person(int(token.person.person_id))
	if person.is_empty() or int(feature.get("owner_faction", -1)) >= 0 and int(feature.owner_faction) != int(person.faction): return fail("NO_AUTHORITY")
	if feature.has("tech_trial") or feature.has("tech_batch") or feature.has("pending_build") or feature.has("repair") or bool(feature.get("batch_paid", false)) \
		or float(feature.get("production", 0.0)) > 0.0 or _feature_has_work(data, key) or _feature_operation_active(data, key): return fail("BUSY", "先停止原工區並領完既已付款批次")
	var candidate: Dictionary = feature.duplicate(true)
	if str(binding[1]).is_empty(): candidate.erase("recipe_id")
	else: candidate.recipe_id = str(binding[1])
	var definition := feature_recipe(candidate)
	if definition.is_empty() or not definition.has("cycle"): return fail("INVALID_MATERIALS", "原操作完整單批材料與本階段不符")
	token = token.duplicate(true)
	token.materials = definition.get("input", {}).duplicate(true)
	var authority: Dictionary = actions.technology_phase_binding_candidate(token)
	if not authority.ok: return authority
	var checked := technology_recipe_guard(data, key, candidate, int(token.person.person_id), token)
	if not checked.ok: return checked
	if preview: return ok("原項目可綁定此設施批次", {"target_id": str(token.target_id), "materials": definition.input.duplicate(true), "work_seconds": float(definition.cycle) * 60.0})
	# All candidates are ready. Original feature + original scope attempt publish
	# synchronously; neither publication invokes a fallible transaction.
	if str(binding[1]).is_empty(): feature.erase("recipe_id")
	else: feature.recipe_id = str(binding[1])
	feature.tech_trial = token.duplicate(true)
	feature.status = "已綁本次原項目；等待具名人物到原工位"
	actions.publish_phase_binding(authority)
	data.environment_revision += 1
	rebuild_water(data)
	return ok(str(feature.status), {"target_id": str(token.target_id), "token": token.duplicate(true), "resumed": false})


static func _resume_technology_operation(data: TerrainData, proposed: Dictionary) -> Dictionary:
	var target: Dictionary = {}
	var key := str(proposed.target_id).get_slice(":", 1)
	if str(proposed.target_id).begins_with("feature:"): target = data.site.get("features", {}).get(key, {})
	elif str(proposed.target_id).begins_with("vehicle:"): target = data.site.get("vehicles", {}).get(key, {})
	var original: Dictionary = target.get("tech_trial", {})
	if original.is_empty(): return fail("NO_TARGET")
	if not _technology_trial_shape(original, data): return fail("CORRUPT_STATE")
	for field: String in ["scope", "scope_id", "project_id", "epoch", "purpose", "tech_id", "phase_id", "person", "binding", "target_id"]:
		if original[field] != proposed[field]: return fail("BUSY", "此付費原試作仍屬原目的與具名人物；不可改成本人的收據")
	var actions: Variant = _technology_actions(data)
	if actions == null or not actions.has_method("technology_phase_active_guard"): return fail("UNSUPPORTED")
	var valid: Dictionary = actions.technology_phase_active_guard(original)
	if not valid.ok: return valid
	# Read-only resume: original token/attempt/payment/work/cycle all survive.
	# PA rebinds the original person to its existing original physical task.
	return ok("恢復同一原付費試作", {"target_id": str(original.target_id), "token": original.duplicate(true), "resumed": true})


static func release_technology_operation(data: TerrainData, token: Dictionary) -> Dictionary:
	if data == null or not _technology_trial_shape(token, data): return fail("INVALID_TECHNOLOGY")
	var target: Dictionary = data.site.get("features" if str(token.target_id).begins_with("feature:") else "vehicles", {}).get(str(token.target_id).get_slice(":", 1), {})
	if target.is_empty() or target.get("tech_trial", {}) != token: return fail("STALE_SOURCE")
	# Stopping the PA task does not revoke the paid source's original purpose.
	# It remains parked and may resume only through the same true project/person.
	return ok("原具名工作已停止；原付費token／進度保留供同目的恢復")


static func technology_recipe_guard(data: TerrainData, key: String, feature: Dictionary, operator_id: int, token: Dictionary = {}) -> Dictionary:
	var actions: Variant = _technology_actions(data)
	var definition := feature_recipe(feature)
	if definition.is_empty(): return fail("INVALID")
	var kind := str(feature.kind)
	var recipe := str(feature.get("recipe_id", ""))
	var policy := _technology_policy(data)
	if not policy.ok: return policy
	var person: Dictionary = actions._person(operator_id) if actions != null and operator_id > 0 else {}
	if not token.is_empty() and (not _technology_trial_shape(token, data) or str(token.target_id) != "feature:" + key or int(token.person.person_id) != operator_id): return fail("STALE_PROJECT")
	var category := TechnologyPolicy.recipe_category(kind, recipe)
	var exception := ""
	if not token.is_empty():
		var owner: Dictionary = actions._technology_scope_owner(str(token.scope), str(token.scope_id))
		var record: Dictionary = owner.get("technology", {})
		var phase := Technology.scope_next_phase(Technology.active_project(record), token.person, record.get("person_links", []))
		if phase.is_empty() or str(phase.id) != str(token.phase_id) or str(phase.binding) != str(token.binding): return fail("STALE_PHASE")
		exception = str(phase.get("policy_exception", ""))
	if not category.is_empty() and policy.policy.categories.has(category) and exception != category \
		and (person.is_empty() or not Technology.learned(actions._body_get(person, "technology"), category)): return fail("NO_TECHNOLOGY", "原實際操作者須學會本世界固定准入技藝")
	var required := str(definition.get("technology", ""))
	if not required.is_empty() and (token.is_empty() or str(token.tech_id) != required):
		if actions == null or not actions.has_method("_technology_scope_owner"): return fail("NO_TECHNOLOGY")
		var scope := str(TechnologyCatalog.get_node(required).get("scope", ""))
		var scope_id := str(data.site.get("family", {}).get("family_id", "")) if scope == "family" else str(data.site.get("settlement", {}).get("settlement_id", ""))
		var owner: Dictionary = actions._technology_scope_owner(scope, scope_id)
		if not Technology.scope_known(owner.get("technology", {}), required): return fail("NO_TECHNOLOGY", "當前原持有人尚未掌握此新工序")
		if scope == "family" and (person.is_empty() or not Technology.learned(actions._body_get(person, "technology"), required)): return fail("NO_TECHNOLOGY", "改良工序須由真正學會的原人物實際操作")
	var skill := str(definition.get("operator_skill", ""))
	if not skill.is_empty() and (person.is_empty() or not Technology.learned(actions._body_get(person, "technology"), skill)): return fail("NO_TECHNOLOGY", "須由學會該技藝的原人物實際操作")
	return ok()


static func _technology_payment_source(data: TerrainData, feature: Dictionary, key: String) -> Dictionary:
	if str(feature.get("supply_mode", "")) == "local":
		var stock: Dictionary = data.site.get("stockpiles", {}).get(key, {})
		if stock.is_empty() or not stock.get("holder") is Dictionary or not _item_holder_shape(stock.holder) or str(stock.holder.holder) != "feature:" + key: return {}
		return {"cargo": stock.cargo, "holder": stock.holder}
	if not data.site.get("inventory") is Dictionary or not data.site.get("depot_items") is Dictionary or not _item_holder_shape(data.site.depot_items): return {}
	return {"cargo": data.site.inventory, "holder": data.site.depot_items}

# REPLACE pay_feature_inputs body; the optional task argument preserves callers.


static func technology_batch_operator_guard(data: TerrainData, key: String, feature: Dictionary, task: Dictionary, original_identity: int = 0) -> Dictionary:
	var token: Dictionary = feature.get("tech_trial", {})
	var actions: Variant = _technology_actions(data)
	var person: Dictionary = actions._technology_operator_for_task(task, original_identity) if actions != null else {}
	if not token.is_empty():
		if person.is_empty() or int(person.person_id) != int(token.person.person_id) or feature.get("tech_batch", {}).get("token", token) != token: return fail("WAITING", "原具名試作者未在本工位；本項目整批暫停")
		if actions == null or not actions.has_method("technology_phase_active_guard"): return fail("UNSUPPORTED")
		var active: Dictionary = actions.technology_phase_active_guard(token)
		if not active.ok: return active
	var checked := technology_recipe_guard(data, key, feature, int(person.get("person_id", 0)), token)
	if checked.ok: checked.operator_id = int(person.get("person_id", 0))
	return checked

# Call immediately AFTER the actual existing work_time callback and BEFORE its
# original feature.progress update. Water/fertility/grade remain original math.


static func technology_record_work(feature: Dictionary, actual_minutes: float, actual_identity: int) -> void:
	if feature.has("tech_batch") and int(feature.tech_batch.operator_id) == actual_identity and is_finite(actual_minutes) and actual_minutes > 0.0:
		feature.tech_batch.work_seconds = float(feature.tech_batch.work_seconds) + actual_minutes * 60.0


static func _technology_output_products(definition: Dictionary) -> Array:
	var products: Array = []
	for identity: Variant in definition.get("output_items", []):
		if not identity is String or str(identity).split(":").size() != 2: return []
		var bits := str(identity).split(":")
		products.append({"definition_id": str(identity), "definition": {"slot": str(bits[0]), "asset": str(bits[1]), "tint": [1.0, 1.0, 1.0, 1.0]}, "slot": ""})
	return products

# REPLACE _deliver_feature_batch body. Signature may gain optional identity;
# original manual/Army callers supply the actual original identity when known.


static func prepare_feature_output(data: TerrainData, feature: Dictionary, worker: Dictionary, cargo: Dictionary, carry_limit: int, original_identity: int = 0) -> Dictionary:
	var key := ""
	for candidate: String in data.site.get("features", {}):
		if is_same(feature, data.site.features[candidate]): key = candidate; break
	if key.is_empty() or not bool(feature.get("batch_paid", false)): return fail("STALE_SOURCE")
	var definition := feature_recipe(feature)
	if definition.is_empty() or not definition.has("cycle") or float(feature.get("production", 0.0)) + 0.00000001 < float(definition.cycle): return fail("WAITING")
	var output: Dictionary = definition.get("output", {})
	var products := _technology_output_products(definition)
	if products.size() != definition.get("output_items", []).size(): return fail("INVALID", "原製品定義非法；已付批次保留")
	var ledger: Dictionary = feature.get("tech_batch", {})
	if not ledger.is_empty() and (not valid_technology_batch(ledger, data, key) or ledger.recipe_id != str(feature.get("recipe_id", "")) or not Technology.material_equal(ledger.materials, definition.get("input", {}))): return fail("STALE_SOURCE")
	var actions: Variant = _technology_actions(data)
	var person: Dictionary = actions._technology_operator_for_task(worker, original_identity) if actions != null else {}
	var holder: Dictionary = person.get("holder", {})
	if not products.is_empty() and (person.is_empty() or not is_same(person.get("cargo"), cargo) or ledger.is_empty()): return fail("NO_AUTHORITY", "須由原人物領取原實物批次")
	var load := inventory_size(cargo) + products.size() + inventory_size(output)
	if not holder.is_empty(): load += holder.item_ids.size() - holder.equipped.size()
	if carry_limit < 0 or load > carry_limit: return fail("STORAGE_FULL", "原已付完成品保留，請先騰出本人實際容量")
	if not holder.is_empty() and int(holder.version) >= 2147483646: return fail("STALE_SOURCE", "原持物提交版本已用盡")
	var item_prepared := {}
	if not products.is_empty():
		item_prepared = prepare_equipment_creation(data, holder, products, int(ledger.operator_id))
		if not item_prepared.ok: return item_prepared
	var ids: Array = item_prepared.get("item_ids", [])
	var receipt := {}
	if not ledger.is_empty() and int(ledger.operator_id) > 0 and float(ledger.work_seconds) > 0.0:
		receipt = {"id": int(ledger.id), "site_id": str(data.site.id), "feature_id": key, "operator_id": int(ledger.operator_id),
			"recipe_id": str(ledger.recipe_id), "resources": output.duplicate(true), "item_ids": ids.duplicate(), "work_seconds": float(ledger.work_seconds)}
	var phase_prepared := {}
	var nation_prepared := {}
	var token: Dictionary = feature.get("tech_trial", {})
	if not token.is_empty():
		if ledger.is_empty() or ledger.token != token or receipt.is_empty() or person.is_empty() or int(person.person_id) != int(token.person.person_id): return fail("STALE_PROJECT")
		if actions == null or not actions.has_method("technology_phase_receipt_candidate") or not actions.has_method("publish_phase_receipt"): return fail("UNSUPPORTED")
		var event := {"id": str(ledger.payment_id), "site_id": str(data.site.id), "target_id": "feature:" + key, "operator_id": int(ledger.operator_id),
			"binding": str(token.binding), "work_seconds": float(ledger.work_seconds), "item_ids": ids.duplicate(), "outputs": output.duplicate(true), "materials": ledger.materials.duplicate(true)}
		phase_prepared = actions.technology_phase_receipt_candidate(token, event)
		if not phase_prepared.ok: return phase_prepared
		nation_prepared = actions.lab.site_controller.prepare_nation_technology_output(token, event)
		if not nation_prepared.ok: return nation_prepared
	return ok("", {"state_ref": data.site, "feature_ref": feature, "feature_before": feature.duplicate(true), "worker_ref": worker,
		"cargo_ref": cargo, "cargo_before": cargo.duplicate(true), "output": output.duplicate(true), "products": item_prepared,
		"holder_ref": holder, "holder_before": holder.duplicate(true), "receipt": receipt, "phase": phase_prepared, "actions": actions, "nation": nation_prepared})


static func publish_feature_output(data: TerrainData, prepared: Dictionary) -> void:
	assert(prepared.ok and is_same(data.site, prepared.state_ref) and prepared.feature_ref == prepared.feature_before and prepared.cargo_ref == prepared.cargo_before)
	assert(prepared.holder_ref.is_empty() or prepared.holder_ref == prepared.holder_before)
	if not prepared.products.is_empty(): _publish_equipment_creation(data, prepared.products)
	add_items(prepared.cargo_ref, prepared.output)
	if prepared.products.is_empty() and not prepared.holder_ref.is_empty(): prepared.holder_ref.version = int(prepared.holder_before.version) + 1
	prepared.feature_ref.production = 0.0
	prepared.feature_ref.batch_paid = false
	prepared.feature_ref.erase("tech_batch")
	prepared.feature_ref.erase("tech_trial")
	if not prepared.receipt.is_empty():
		# One current immutable output, with a finite monotonic original sequence.
		# Accepted Scope/Nation receipts retain their own strict historical evidence.
		prepared.feature_ref.technology_output = {"version": 1, "next_seq": int(prepared.receipt.id) + 1, "receipts": [prepared.receipt.duplicate(true)]}
	prepared.worker_ref.target = ""
	prepared.worker_ref.mode = "idle"
	data.site.total_produced = int(data.site.total_produced) + inventory_size(prepared.output) + prepared.products.get("item_ids", []).size()
	if not prepared.phase.is_empty(): prepared.actions.publish_phase_receipt(prepared.phase)
	if not prepared.nation.is_empty(): prepared.actions.lab.site_controller.publish_nation_technology_output(prepared.nation)
	data.environment_revision += 1


static func valid_technology_batch(raw: Variant, data: TerrainData, key: String, target_kind: String = "feature") -> bool:
	if not Technology.keys(raw, TECHNOLOGY_BATCH_FIELDS) or not Technology.integer(raw.version, 1, 1) or not Technology.integer(raw.id, 1) \
		or raw.site_id != str(data.site.get("id", "")) or raw.feature_id != key or not Technology.integer(raw.operator_id, 0) \
		or not raw.recipe_id is String or not Technology.material_stack(raw.materials) or not raw.source_holder is String or raw.source_holder.is_empty() \
		or not Technology.integer(raw.source_version, 0, 2147483645) or not Technology.finite_number(raw.work_seconds) or not raw.payment_id is String or raw.payment_id.is_empty() or not raw.token is Dictionary: return false
	return target_kind in ["feature", "vehicle"] and (raw.token.is_empty() or _technology_trial_shape(raw.token, data) and str(raw.token.target_id) == target_kind + ":" + key and int(raw.token.person.person_id) == int(raw.operator_id) and Technology.material_equal(raw.token.materials, raw.materials))


static func valid_technology_output(raw: Variant, data: TerrainData, key: String) -> bool:
	if not Technology.keys(raw, TECHNOLOGY_OUTPUT_FIELDS) or not Technology.integer(raw.id, 1) or raw.site_id != str(data.site.get("id", "")) or raw.feature_id != key \
		or not Technology.integer(raw.operator_id, 1) or not raw.recipe_id is String or not Technology.material_stack(raw.resources) \
		or not raw.item_ids is Array or not Technology.finite_number(raw.work_seconds, 0.000000001): return false
	var seen := {}
	for identity: Variant in raw.item_ids:
		if not identity is String or not identity.is_valid_int() or str(int(identity)) != identity or not Technology.integer(int(identity), 1, 2147483646) or seen.has(identity): return false
		seen[identity] = true
	return not raw.resources.is_empty() or not raw.item_ids.is_empty()


static func valid_technology_output_state(raw: Variant, data: TerrainData, key: String) -> bool:
	if not Technology.keys(raw, ["version", "next_seq", "receipts"]) or not Technology.integer(raw.version, 1, 1) \
		or not Technology.integer(raw.next_seq, 1) or not raw.receipts is Array or raw.receipts.size() > 1: return false
	if raw.receipts.is_empty(): return int(raw.next_seq) == 1
	return valid_technology_output(raw.receipts[0], data, key) and int(raw.receipts[0].id) == int(raw.next_seq) - 1

# Original prospective endpoint proof for PA/Nation candidate validation.
# Query only: no item, resource, seq, body, scope or knowledge mutation. Actual
# publish remains the original synchronous item/feature/scope transaction tail.


static func technology_output_candidate(data: TerrainData, token: Dictionary, event: Dictionary) -> Dictionary:
	if data == null or not _technology_trial_shape(token, data) or not Technology.keys(event, ["id", "site_id", "target_id", "operator_id", "binding", "work_seconds", "item_ids", "outputs", "materials"]) \
		or not event.id is String or event.id.is_empty() or event.site_id != str(data.site.get("id", "")) or event.target_id != token.target_id \
		or not Technology.integer(event.operator_id, int(token.person.person_id), int(token.person.person_id)) or event.binding != token.binding \
		or not Technology.finite_number(event.work_seconds, 0.000000001) or not event.item_ids is Array or not Technology.material_stack(event.outputs) \
		or not Technology.material_equal(event.materials, token.materials): return fail("INVALID_RECEIPT")
	var actions: Variant = _technology_actions(data)
	if actions == null: return fail("NO_AUTHORITY")
	var person: Dictionary = actions._person(int(token.person.person_id))
	if person.is_empty() or float(person.hp) <= 0.0 or float(person.ko) > 0.0 or bool(person.captive): return fail("NO_AUTHORITY")
	var source_kind := "features" if str(token.target_id).begins_with("feature:") else "vehicles" if str(token.target_id).begins_with("vehicle:") else ""
	if source_kind.is_empty(): return fail("NO_TARGET")
	var key := str(token.target_id).get_slice(":", 1)
	var target: Dictionary = data.site.get(source_kind, {}).get(key, {})
	var ledger: Dictionary = target.get("tech_batch", {})
	if target.get("tech_trial", {}) != token or not Technology.keys(ledger, TECHNOLOGY_BATCH_FIELDS) or ledger.get("token", {}) != token \
		or str(ledger.get("payment_id", "")) != str(event.id) or int(ledger.get("operator_id", 0)) != int(event.operator_id) \
		or not Technology.material_equal(ledger.get("materials", {}), event.materials) or not is_equal_approx(float(ledger.get("work_seconds", -1.0)), float(event.work_seconds)): return fail("STALE_SOURCE")
	if source_kind == "vehicles":
		var job: Dictionary = target.get("build", {})
		if job.is_empty() or not SIEGE_DEFINITIONS.has(str(target.get("kind", ""))) or float(target.get("hp", 0.0)) <= 0.0 \
			or float(job.get("total_work", 0.0)) <= 0.0 or float(job.get("progress", -1.0)) + 0.000000001 < float(job.total_work) \
			or not Technology.material_equal(job.get("paid_cost", {}), event.materials) or not event.item_ids.is_empty() or not event.outputs.is_empty(): return fail("WAITING")
		if str(TECHNOLOGY_SIEGE_BINDINGS.get(str(token.binding), "")) != str(target.kind): return fail("INVALID_RECEIPT")
		return ok("原器械完整材料與具名實作完成端點")
	if target.has("ship_build"):
		var job: Dictionary = target.ship_build
		if str(target.get("kind", "")) != "shipyard" or str(token.binding) != "ferry_build" or str(job.get("ship_type", "")) != "ferry" \
			or float(target.get("production", 0.0)) * 60.0 + 0.000000001 < float(job.get("total_work", 1.0)) \
			or not Technology.material_equal(job.get("paid_cost", {}), event.materials) or not event.outputs.is_empty() or not event.item_ids.is_empty(): return fail("WAITING")
		return _ship_launch_query(data, target, str(job.ship_type), actions.lab.site_controller.reserves_cell)
	if str(target.get("stage", "")) != "complete":
		if float(target.get("work", 0.0)) <= 0.0 or float(target.get("progress", -1.0)) + 0.000000001 < float(target.work) \
			or not Technology.material_equal(target.get("cost", {}), event.materials) or not event.outputs.is_empty() or not event.item_ids.is_empty() \
			or str(TECHNOLOGY_BUILD_BINDINGS.get(str(token.binding), "")) != str(target.get("kind", "")): return fail("WAITING")
		return ok("原完整施工材料與具名實作完成端點")
	var definition := feature_recipe(target)
	if definition.is_empty() or not definition.has("cycle") or not bool(target.get("batch_paid", false)) \
		or float(target.get("production", -1.0)) + 0.00000001 < float(definition.cycle) \
		or not Technology.material_equal(definition.get("input", {}), event.materials) or not Technology.material_equal(definition.get("output", {}), event.outputs): return fail("WAITING")
	var products := _technology_output_products(definition)
	if event.item_ids.size() != products.size(): return fail("INVALID_RECEIPT")
	for index: int in event.item_ids.size():
		var identity := str(int(data.site.get("next_item", 0)) + index)
		if event.item_ids[index] != identity or data.site.get("item_records", {}).has(identity): return fail("STALE_SOURCE")
	var binding: Array = TECHNOLOGY_FEATURE_BINDINGS.get(str(token.binding), [])
	if binding.size() != 2 or str(binding[0]) != str(target.kind) or str(binding[1]) != str(target.get("recipe_id", "")): return fail("INVALID_RECEIPT")
	return ok("原已付完整周期／具名本人工作／原序號的真產出候選")


const TECHNOLOGY_BUILD_BINDINGS := {"house_build": "house", "wall_build": "stone_wall", "stairs_build": "wall_stairs", "road_build": "road", "survey": "survey_stakes", "irrigation": "irrigation_channel"}


const TECHNOLOGY_SIEGE_BINDINGS := {"ballista_build": "ballista", "ram_build": "ram", "traction_build": "traction_trebuchet", "counterweight_build": "counterweight_trebuchet", "tower_build": "siege_tower"}


static func _technology_geometry_payment(data: TerrainData, token: Dictionary, cost: Dictionary, preview: bool) -> Dictionary:
	var actions: Variant = _technology_actions(data)
	var candidate: Dictionary = token.duplicate(true)
	candidate.materials = cost.duplicate(true)
	var binding: Dictionary = actions.technology_phase_binding_candidate(candidate)
	if not binding.ok: return binding
	var payment: Dictionary = actions.technology_phase_payment_candidate(candidate, cost, binding)
	if not payment.ok: return payment
	return ok("", {"token": candidate, "binding": binding, "payment": payment, "preview": preview})


static func _technology_geometry_ledger(data: TerrainData, token: Dictionary, payment: Dictionary, recipe: String) -> Dictionary:
	return {"version": 1, "id": 1, "site_id": str(data.site.id), "feature_id": str(token.target_id).get_slice(":", 1),
		"operator_id": int(token.person.person_id), "recipe_id": recipe, "materials": token.materials.duplicate(true),
		"source_holder": "depot", "source_version": int(data.site.depot_items.version) - 1, "work_seconds": 0.0,
		"token": token.duplicate(true), "payment_id": str(payment.payment_id)}


static func _begin_technology_geometry(data: TerrainData, token: Dictionary, work_target: Dictionary, preview: bool) -> Dictionary:
	var actions: Variant = _technology_actions(data)
	var person: Dictionary = actions._person(int(token.person.person_id))
	if person.is_empty() or not _siege_depot_ready(data) or bool(data.site.get("paused", false)): return fail("BUSY")
	var binding := str(token.binding)
	if TECHNOLOGY_BUILD_BINDINGS.has(binding):
		if not Technology.keys(work_target, ["cells", "options"]) or not work_target.cells is Array or not work_target.options is Dictionary: return fail("INVALID")
		var cells: Array[int] = []
		for value: Variant in work_target.cells:
			if not Technology.integer(value, 0, data.size.x * data.size.y - 1) or cells.has(int(value)): return fail("INVALID")
			cells.append(int(value))
		var options: Dictionary = work_target.options.duplicate(true)
		options.owner_faction = int(person.faction)
		options.layout_version = BUILDING_LAYOUT_VERSION
		var kind := str(TECHNOLOGY_BUILD_BINDINGS[binding])
		var checked := preview_build(data, kind, cells, actions.lab.site_controller.reserves_cell, options)
		if not checked.ok: return checked
		if str(token.target_id) != "feature:" + str(int(data.site.next_feature)): return fail("STALE_SOURCE")
		if kind == "survey_stakes":
			if cells.size() != 2 or not options.get("survey_plan") is Dictionary: return fail("INVALID", "需兩個真樁與完整原幾何方案")
			var plan: Dictionary = options.survey_plan
			if not Technology.keys(plan, ["kind", "cells", "options"]) or not plan.cells is Array or not plan.options is Dictionary: return fail("INVALID")
			var plan_cells: Array[int] = []
			for value: Variant in plan.cells:
				if not Technology.integer(value, 0, data.size.x * data.size.y - 1): return fail("INVALID")
				plan_cells.append(int(value))
			var geometry := preview_build(data, str(plan.kind), plan_cells, actions.lab.site_controller.reserves_cell, plan.options)
			if not geometry.ok: return geometry
		if kind == "irrigation_channel":
			var connection := technology_irrigation_connection(data, cells)
			if not connection.ok: return connection
		var prepared := _technology_geometry_payment(data, token, checked.cost, preview)
		if not prepared.ok: return prepared
		if preview: return ok("可開始原幾何試作", {"target_id": token.target_id, "cost": checked.cost, "work_seconds": float(checked.work) * 60.0})
		# request_build uses the same original full preflight, cells, resources,
		# next_feature, clearing, navigation, structure and water guards again.
		var result := request_build(data, kind, cells, actions.lab.site_controller.reserves_cell, options)
		if not result.ok: return result
		data.site.depot_items.version = int(data.site.depot_items.version) + 1
		var feature: Dictionary = data.site.features[str(result.feature)]
		feature.tech_trial = prepared.token
		feature.tech_batch = _technology_geometry_ledger(data, prepared.token, prepared.payment, "construct:" + kind)
		actions.publish_phase_payment(prepared.payment)
		return ok("原材料與具名項目已綁同一施工", {"target_id": str(token.target_id), "token": prepared.token.duplicate(true), "resumed": false})
	if TECHNOLOGY_SIEGE_BINDINGS.has(binding):
		if not Technology.keys(work_target, ["anchor", "facing", "team_id"]) or not work_target.anchor is Vector2i or not work_target.facing is Vector2i or not Technology.integer(work_target.team_id, 1): return fail("INVALID")
		var team: Variant = actions._technology_team(person)
		if team == null or int(team.team_id) != int(work_target.team_id): return fail("NO_AUTHORITY", "試作者須屬本原施工隊")
		if str(token.target_id) != "vehicle:" + str(int(data.site.get("next_vehicle", 1))): return fail("STALE_SOURCE")
		var kind := str(TECHNOLOGY_SIEGE_BINDINGS[binding])
		var checked := begin_siege_build(data, kind, work_target.anchor, work_target.facing, int(team.team_id), int(token.person.person_id), actions.lab.site_controller.reserves_cell, true)
		if not checked.ok: return checked
		var prepared := _technology_geometry_payment(data, token, checked.cost, preview)
		if not prepared.ok: return prepared
		if preview: return ok("可開始原器械試作", {"target_id": token.target_id, "cost": checked.cost, "work_seconds": checked.work_seconds})
		var result := begin_siege_build(data, kind, work_target.anchor, work_target.facing, int(team.team_id), int(token.person.person_id), actions.lab.site_controller.reserves_cell)
		if not result.ok: return result
		var vehicle: Dictionary = data.site.vehicles[str(result.vehicle)]
		vehicle.tech_trial = prepared.token
		vehicle.tech_batch = _technology_geometry_ledger(data, prepared.token, prepared.payment, "construct:" + kind)
		actions.publish_phase_payment(prepared.payment)
		return ok("原器械材料與本具名項目已綁同一次交易", {"target_id": str(token.target_id), "token": prepared.token.duplicate(true), "resumed": false})
	if binding == "ferry_build":
		if not Technology.keys(work_target, ["team_id"]) or not Technology.integer(work_target.team_id, 1) or not str(token.target_id).begins_with("feature:"): return fail("INVALID")
		var team: Variant = actions._technology_team(person)
		if team == null or int(team.team_id) != int(work_target.team_id): return fail("NO_AUTHORITY")
		var key := str(token.target_id).trim_prefix("feature:")
		var checked := begin_ship_build(data, key, "ferry", int(team.team_id), int(person.faction), actions.lab.site_controller.reserves_cell, true)
		if not checked.ok: return checked
		var prepared := _technology_geometry_payment(data, token, checked.cost, preview)
		if not prepared.ok: return prepared
		if preview: return ok("可開始原船塢試作", {"target_id": token.target_id, "cost": checked.cost, "work_seconds": checked.work_seconds})
		var result := begin_ship_build(data, key, "ferry", int(team.team_id), int(person.faction), actions.lab.site_controller.reserves_cell)
		if not result.ok: return result
		var feature: Dictionary = data.site.features[key]
		feature.tech_trial = prepared.token
		feature.tech_batch = _technology_geometry_ledger(data, prepared.token, prepared.payment, "ship:ferry")
		actions.publish_phase_payment(prepared.payment)
		return ok("原船塢材料與本具名項目已綁同一造船", {"target_id": str(token.target_id), "token": prepared.token.duplicate(true), "resumed": false})
	return fail("INVALID", "此原幾何入口不匹配本階段binding")

# A real channel follows the original terrain, connected original pump route
# and bounded cells. It never creates water or a new terrain/navigation owner.


static func technology_irrigation_connection(data: TerrainData, cells: Array[int]) -> Dictionary:
	if cells.is_empty() or cells.size() > 36: return fail("INVALID")
	var members := {}
	for index: int in cells:
		if not Technology.integer(index, 0, data.size.x * data.size.y - 1) or members.has(index) or not data.is_terrain_walkable(data.cell_from_index(index)): return fail("TERRAIN")
		members[index] = true
	var seen := {cells[0]: true}
	var pending: Array[int] = [cells[0]]
	var head := 0
	var connected := false
	while head < pending.size():
		var index := pending[head]
		head += 1
		for pump_key: String in data.site.get("water_links", {}):
			var pump: Dictionary = data.site.features.get(pump_key, {})
			if str(pump.get("kind", "")) in ["well", "intake"] and str(pump.get("stage", "")) == "complete" and feature_usable(pump) and data.site.water_links[pump_key].has(index): connected = true
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var current := data.cell_from_index(index)
			var next := current + direction
			if data.contains(next) and members.has(data.index(next)) and not seen.has(data.index(next)) and data.can_step(current, next):
				seen[data.index(next)] = true
				pending.append(data.index(next))
	if seen.size() != cells.size() or not connected: return fail("WATER", "原渠道必須逐格連通並接原合法水源服務路線")
	return ok()

# Call before ANY interval progress for a bound feature/vehicle construction.
# The actual original WorkTeam/PA supplies task identity, not a learned witness.


static func technology_geometry_operator_guard(data: TerrainData, target: Dictionary, task: Dictionary, identity: int) -> Dictionary:
	var token: Dictionary = target.get("tech_trial", {})
	var actions: Variant = _technology_actions(data)
	var person: Dictionary = actions._technology_operator_for_task(task, identity) if actions != null else {}
	if token.is_empty(): return ok("", {"operator_id": int(person.get("person_id", 0))})
	if person.is_empty() or target.get("tech_batch", {}).get("token", {}) != token: return fail("WAITING", "本具名原試作者未在原工位；試作整批停止")
	var active: Dictionary = actions.technology_phase_active_guard(token)
	if not active.ok: return active
	if int(person.person_id) != int(token.person.person_id):
		if not data.has_meta(&"site_work_team"): return fail("WAITING", "原共同工作段尚未接線")
		var ref_value: Variant = data.get_meta(&"site_work_team", null)
		var workers: Variant = ref_value.get_ref() if ref_value is WeakRef else null
		if workers == null or not workers.has_method("accepted_interval_participant"): return fail("WAITING", "原共同工作段尚無實際參與的具名試作者")
		var accepted: Dictionary = workers.accepted_interval_participant(task, int(token.person.person_id))
		if accepted.is_empty() or float(accepted.get("actual_seconds", 0.0)) <= 0.0 or float(accepted.get("productive", 0.0)) <= 0.0: return fail("WAITING", "原具名試作者本工作段未實際作業；助手整批停止")
	return ok("", {"operator_id": int(person.person_id), "named_operator": int(token.person.person_id)})

# Pure preflight facts for ORIGINAL WorkTeam's existing required_any_ids prefix.
# This marks eligibility only. It does not authorize helpers to advance before
# the original collector has actually accepted the named participant interval.


static func technology_trial_work_facts(data: TerrainData, target: Dictionary, task: Dictionary, identity: int) -> Dictionary:
	var token: Dictionary = target.get("tech_trial", {})
	if token.is_empty(): return ok("", {"required_skill": "", "eligible_master": false})
	if not _technology_trial_shape(token, data): return fail("CORRUPT_STATE")
	var actions: Variant = _technology_actions(data)
	var person: Dictionary = actions._technology_operator_for_task(task, identity) if actions != null else {}
	if person.is_empty() or str(task.get("target", "")) != str(token.target_id): return fail("WAITING")
	var active: Dictionary = actions.technology_phase_active_guard(token)
	if not active.ok: return active
	var owner: Dictionary = actions._technology_scope_owner(str(token.scope), str(token.scope_id))
	var record: Dictionary = owner.get("technology", {})
	var phase := Technology.scope_next_phase(Technology.active_project(record), token.person, record.get("person_links", []))
	if phase.is_empty() or phase.id != token.phase_id or phase.binding != token.binding: return fail("STALE_PHASE")
	return ok("", {"required_skill": "trial:" + str(token.scope) + ":" + str(token.scope_id) + ":" + str(token.project_id) + ":" + str(token.attempt),
		"eligible_master": int(person.person_id) == int(token.person.person_id), "policy_exception": str(phase.get("policy_exception", ""))})

# Candidate source for the final original geometry tail. It runs after all
# original completion/collision/fire/launch guards, before committing the target.


static func prepare_technology_geometry_completion(data: TerrainData, target: Dictionary, target_id: String, actual_product_id: String = "") -> Dictionary:
	var token: Dictionary = target.get("tech_trial", {})
	if token.is_empty(): return ok("", {"phase": {}, "event": {}})
	var ledger: Dictionary = target.get("tech_batch", {})
	if ledger.is_empty() or ledger.get("token", {}) != token or str(token.target_id) != target_id or float(ledger.get("work_seconds", 0.0)) <= 0.0: return fail("STALE_PROJECT")
	var actions: Variant = _technology_actions(data)
	if actions == null or not actions.has_method("technology_phase_receipt_candidate"): return fail("UNSUPPORTED")
	var event := {"id": str(ledger.payment_id), "site_id": str(data.site.id), "target_id": target_id, "operator_id": int(ledger.operator_id),
		"binding": str(token.binding), "work_seconds": float(ledger.work_seconds), "item_ids": [], "outputs": {}, "materials": ledger.materials.duplicate(true)}
	var prepared: Dictionary = actions.technology_phase_receipt_candidate(token, event)
	if not prepared.ok: return prepared
	var nation: Dictionary = actions.lab.site_controller.prepare_nation_technology_output(token, event)
	if not nation.ok: return nation
	return ok("", {"phase": prepared, "event": event, "actions": actions, "target_ref": target, "actual_product_id": actual_product_id, "nation": nation})


static func publish_technology_geometry_completion(prepared: Dictionary) -> void:
	assert(prepared.ok)
	if prepared.phase.is_empty(): return
	prepared.target_ref.technology_construction = prepared.event.duplicate(true)
	# Actual feature or vehicle ID stays an original product reference; no copy.
	if not str(prepared.actual_product_id).is_empty(): prepared.target_ref.technology_product_id = str(prepared.actual_product_id)
	prepared.target_ref.erase("tech_trial")
	prepared.target_ref.erase("tech_batch")
	prepared.actions.publish_phase_receipt(prepared.phase)
	prepared.actions.lab.site_controller.publish_nation_technology_output(prepared.nation)

# T6 reads true current target ratios. It never creates a receipt, changes a
# worker, credits another person, or writes progress. Baselines stay Catalog.


static func technology_remaining_work(data: TerrainData, project: Dictionary, reference: Dictionary) -> Dictionary:
	if data == null or not Technology.valid_ref(reference) or not Technology.integer(project.get("id"), 1) or not project.get("purpose") is String: return fail("INVALID_TECHNOLOGY")
	var route := Technology.scope_route(str(project.get("tech_id", "")), str(project.get("route_id", "default")))
	if route.is_empty() or TechnologyCatalog.get_node(str(project.tech_id)).get("scope", "") != "family": return fail("INVALID_TECHNOLOGY")
	var family: Dictionary = data.site.get("family", {})
	var links: Array = family.get("technology", {}).get("person_links", [])
	var remaining := 0.0
	var outstanding := {}
	for phase: Dictionary in route.get("phases", []):
		var count := 0
		for receipt: Variant in project.get("receipts", []):
			if receipt is Dictionary and str(receipt.get("phase_id", "")) == str(phase.id) and Technology.same_person_ref({"site_id": str(receipt.get("site_id", "")), "person_id": int(receipt.get("person_id", 0))}, reference, links): count += 1
		var left := maxi(0, int(phase.repeat) - count)
		remaining += float(phase.seconds) * left
		if left > 0: outstanding[str(phase.id)] = phase
	var pending_phase := ""
	var reduction := 0.0
	for owner_kind: String in ["features", "vehicles"]:
		for key: String in data.site.get(owner_kind, {}):
			var target: Dictionary = data.site[owner_kind][key]
			var token: Dictionary = target.get("tech_trial", {})
			if token.is_empty() or not _technology_trial_shape(token, data) or str(token.scope) != "family" or str(token.scope_id) != str(family.get("family_id", "")) \
				or int(token.project_id) != int(project.id) or str(token.purpose) != str(project.purpose) or str(token.tech_id) != str(project.tech_id) \
				or not Technology.same_person_ref(token.person, reference, links) or not outstanding.has(str(token.phase_id)): continue
			var expected := ("feature:" if owner_kind == "features" else "vehicle:") + key
			var ledger: Dictionary = target.get("tech_batch", {})
			if token.target_id != expected or ledger.get("token", {}) != token or not Technology.material_equal(ledger.get("materials", {}), token.materials): return fail("STALE_PROJECT")
			if not pending_phase.is_empty(): return fail("CORRUPT_STATE", "同一原人／項目不得同時綁兩個物理試作")
			pending_phase = str(token.phase_id)
			var fraction := 0.0
			if owner_kind == "vehicles":
				var job: Dictionary = target.get("build", {})
				if not job.is_empty() and float(job.get("total_work", 0.0)) > 0.0: fraction = float(job.get("progress", 0.0)) / float(job.total_work)
			elif target.has("ship_build"):
				if float(target.ship_build.get("total_work", 0.0)) > 0.0: fraction = float(target.get("production", 0.0)) * 60.0 / float(target.ship_build.total_work)
			elif str(target.get("stage", "")) != "complete":
				if float(target.get("work", 0.0)) > 0.0: fraction = float(target.get("progress", 0.0)) / float(target.work)
			else:
				var definition := feature_recipe(target)
				if bool(target.get("batch_paid", false)) and float(definition.get("cycle", 0.0)) > 0.0: fraction = float(target.get("production", 0.0)) / float(definition.cycle)
			if not is_finite(fraction): return fail("CORRUPT_STATE")
			reduction = float(outstanding[pending_phase].seconds) * clampf(fraction, 0.0, 1.0)
	return ok("", {"remaining_baseline": maxf(0.0, remaining - reduction)})

