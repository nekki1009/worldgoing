class_name SiteRuntime
extends RefCounted

const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const EquipmentDye = preload("res://scripts/ui/equipment_dye.gd")
const COMBAT_GRACE := 10.0
const CARRY_CAPACITY := 20
const ITEM_STORAGE_VERSION := 1
const EQUIPMENT_SLOTS := ["helmet", "outfit", "armor", "cape", "weapon", "shield", "boots"]
const ITEM_FIELDS := ["item_storage_version", "item_definitions", "item_records", "ground_loot", "next_loot", "next_item", "depot_items"]
const EXCHANGE_FIGHTING_POSITION_BONUS := 10.0
const RANGED_RECIPES := {
	"bow": {"name": "弓", "cost": {"wood": 4, "fiber": 2}, "duration": 120.0, "asset": "bow_01"},
	"crossbow": {"name": "弩", "cost": {"wood": 4, "iron": 2, "fiber": 1}, "duration": 180.0, "asset": "crossbow_01"},
	"arrow": {"name": "箭 ×10", "cost": {"wood": 1, "iron": 1}, "duration": 60.0, "output": {"arrow": 10}},
	"bolt": {"name": "弩矢 ×10", "cost": {"wood": 1, "iron": 1}, "duration": 60.0, "output": {"bolt": 10}},
}
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
	"palisade": {"name": "木柵障礙", "cost": {"wood": 4}, "work": 6.0, "solid": true, "water": 0.0},
	"fighting_position": {"name": "防禦陣地", "cost": {"wood": 3, "stone": 2}, "work": 8.0, "solid": false, "water": 0.0},
}
const ERRORS := {
	"NO_TARGET": "目標不存在", "EMPTY": "來源已耗盡／等待恢復", "SURVEY": "請先勘探鐵礦",
	"UNREACHABLE": "沒有可達工作格", "OCCUPIED": "占地或人員預約衝突", "MATERIALS": "缺少材料／工具",
	"STORAGE_FULL": "存放空間不足", "TERRAIN": "地勢或地基不合適", "WATER": "缺少對應水源／供水",
	"BUSY": "工作或戰鬥進行中", "INVALID": "無效命令", "BLOCKED": "作業位置被阻擋", "CAPACITY": "本分鐘來源能力已用盡",
	"STALE_SOURCE": "物品已變更",
}

static func fail(code: String, detail: String = "") -> Dictionary:
	return {"ok": false, "code": code, "message": str(ERRORS.get(code, code)) + ("：" + detail if not detail.is_empty() else "")}

static func ok(message: String = "完成", values: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "code": "OK", "message": message}
	result.merge(values, true)
	return result

static func now(data: TerrainData) -> float:
	return float(data.site.minute) + float(data.site.phase)

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
static func equipment_appearance(data: TerrainData, holder: Dictionary, original: Dictionary) -> Dictionary:
	if not HumanCharacter3DEditor.valid_appearance(original) or not _item_holder_shape(holder):
		return {}
	var appearance := original.duplicate(true)
	appearance.erase("equipment_dyes")
	for slot: String in EQUIPMENT_SLOTS:
		appearance.parts[slot] = "none"
	for slot: String in holder.equipped:
		if slot not in EQUIPMENT_SLOTS:
			return {}
		var record: Dictionary = data.site.get("item_records", {}).get(holder.equipped[slot], {})
		var definition: Dictionary = data.site.get("item_definitions", {}).get(str(record.get("definition", "")), {})
		if record.get("holder") != holder.holder or definition.get("slot") != slot:
			return {}
		appearance.parts[slot] = str(definition.asset)
		var dye := item_dye(record, definition)
		if not dye.is_empty():
			if not appearance.has("equipment_dyes"): appearance.equipment_dyes = {}
			appearance.equipment_dyes[slot] = dye
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
	if not valid_item_definition(definition_id, definition) or original_owner <= 0 or original_owner > 2147483647 or not _item_holder_shape(destination):
		return fail("INVALID", "物品定義／持有人")
	if not data.site.has("item_storage_version") or int(data.site.item_storage_version) != ITEM_STORAGE_VERSION:
		return fail("INVALID", "請先初始化物品資料")
	if not slot.is_empty() and (slot != str(definition.slot) or destination.equipped.has(slot)):
		return fail("OCCUPIED", "裝備槽")
	if data.site.item_definitions.has(definition_id) and data.site.item_definitions[definition_id] != definition:
		return fail("INVALID", "不能覆寫既有共用物品定義")
	var identity := str(int(data.site.next_item))
	if int(data.site.next_item) >= 2147483647 or data.site.item_records.has(identity):
		return fail("INVALID", "物品序號重複")
	data.site.next_item = int(data.site.next_item) + 1
	data.site.item_definitions[definition_id] = definition.duplicate(true)
	data.site.item_records[identity] = {"definition": definition_id, "original_owner": original_owner, "holder": str(destination.holder)}
	destination.item_ids.append(identity)
	if not slot.is_empty():
		destination.equipped[slot] = identity
	destination.version = int(destination.version) + 1
	return ok("已建立實際物品", {"item_id": identity})

# Only the original person-job owner commits this after its work/contact checks.
# Preview is read-only; completion rechecks current shared materials and capacity.
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
static func leave_ground_loot(data: TerrainData, source: Dictionary, source_cargo: Dictionary, original_owner: int, cell: Vector2i, kind: String, resources: Dictionary, item_ids: Array, expected_version: int, source_open: Dictionary = {}, open_amount: float = 0.0, preview: bool = false) -> Dictionary:
	resources = resources.duplicate()
	for resource: Variant in resources.keys():
		if resources[resource] is int and int(resources[resource]) == 0:
			resources.erase(resource) # Spent ammo may leave a zero stack on the original person.
	if not data.is_walkable(cell) or original_owner <= 0 or original_owner > 2147483647 or kind not in ["remains", "sealed", "cargo"]:
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
	container.merge({"kind": kind, "original_owner": original_owner, "cell": data.index(cell), "cargo": {}})
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
	var cell := int(container.cell)
	data.site.ground_loot.erase(identity)
	if data.ground_loot_at.has(cell):
		data.ground_loot_at[cell].erase(identity)
		if data.ground_loot_at[cell].is_empty():
			data.ground_loot_at.erase(cell)
	data.ground_loot_dirty_rows[data.cell_from_index(cell).y] = true
	return ok()

static func rebuild_loot_index(data: TerrainData) -> void:
	data.ground_loot_at.clear()
	data.ground_loot_dirty_rows.clear()
	for identity: String in data.site.get("ground_loot", {}):
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
		if not preview:
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
			if not preview:
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
	if kind in ["road", "palisade", "fighting_position"]:
		for item: String in cost:
			cost[item] = int(cost[item]) * cells.size()
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
	return float(FEATURES[kind].work) * (cell_count if kind.contains("farm") or kind in ["road", "level", "palisade", "fighting_position"] else 1)

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

static func choose_task(data: TerrainData, from: Vector2i, occupied: Callable = Callable(), worker_override: Variant = null, cargo_override: Variant = null, excluded_targets: Dictionary = {}) -> Dictionary:
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
		if str(zone.action) in ["construct", "operate"]:
			var key := str(zone.feature)
			if excluded_targets.has("feature:" + key):
				continue
			if not data.site.features.has(key):
				zone.active = false
				continue
			var feature: Dictionary = data.site.features[key]
			if str(zone.action) == "construct":
				if str(feature.stage) == "complete":
					zone.active = false
					continue
				var clearing_pending := false
				for source_key: String in feature.clearing:
					if bool(Env.resource(data, source_key).get("cleared", true)):
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
			if key == str(data.site.manual.target) or excluded_targets.has(key):
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

static func game_seconds(real_seconds: float, combat_left: float) -> float:
	var combat := minf(maxf(0.0, real_seconds), maxf(0.0, combat_left))
	return combat + maxf(0.0, real_seconds - combat) * 60.0

static func advance(data: TerrainData, real_seconds: float, worker_ready: bool = false, manual_ready: bool = false, occupied: Callable = Callable(), work_time: Callable = Callable(), crew_work: Callable = Callable(), worker_limit: int = CARRY_CAPACITY, manual_limit: int = CARRY_CAPACITY) -> void:
	if data.site.is_empty() or bool(data.site.paused) or real_seconds <= 0.0 or not is_finite(real_seconds):
		return
	# Integrate the combat-to-peace boundary exactly, including long frames.
	var minutes := game_seconds(real_seconds, float(data.site.combat_left)) / 60.0
	var combat_seconds := minf(real_seconds, float(data.site.combat_left))
	data.site.combat_left = maxf(0.0, float(data.site.combat_left) - combat_seconds)
	while minutes > 0.00000001:
		var slice := minf(minutes, 1.0 - float(data.site.phase))
		data.site.phase = float(data.site.phase) + slice
		_work(data, slice, worker_ready, manual_ready, occupied, work_time, null, null, worker_limit, manual_limit)
		if crew_work.is_valid():
			crew_work.call(slice * 60.0) # Same phase/resource budget, before minute rollover.
		minutes -= slice
		if float(data.site.phase) >= 0.99999999:
			data.site.phase = 0.0
			data.site.minute = int(data.site.minute) + 1
			_regenerate(data, occupied)
			allocate_water(data)

static func _work(data: TerrainData, minutes: float, worker_ready: bool, manual_ready: bool, occupied: Callable, work_time: Callable = Callable(), worker_override: Variant = null, cargo_override: Variant = null, carry_limit: int = CARRY_CAPACITY, manual_limit: int = CARRY_CAPACITY) -> void:
	var worker: Dictionary = data.site.worker if worker_override == null else worker_override
	var cargo: Dictionary = worker.cargo if cargo_override == null else cargo_override
	if worker_ready and str(worker.mode) == "work" and str(worker.target) != "":
		var target := str(worker.target)
		var cell := data.cell_from_index(int(worker.cell))
		if target.begins_with("feature:"):
			_feature_work(data, target.trim_prefix("feature:"), minutes, occupied, work_time, worker, cargo, carry_limit)
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
				var required := 3.0 if str(worker.action) in ["survey", "clear"] else float(Env.WORK_MINUTES[int(r.kind)])
				worker.status = "%s %.1f / %.1f 分" % ["清理" if str(worker.action) == "clear" else "作業", float(worker.progress), required]
				if float(worker.progress) + 0.00000001 >= required:
					var result := harvest(data, target, cell, cargo, str(worker.action), false, carry_limit)
					worker.status = str(result.message)
					worker.progress = 0.0
					worker.target = ""
					worker.mode = "idle"
	var manual: Dictionary = data.site.manual
	if manual_ready and str(manual.target) != "":
		var r := Env.resource(data, str(manual.target))
		var ready := harvest(data, str(manual.target), data.cell_from_index(int(manual.cell)), manual.cargo, str(manual.action), true, manual_limit)
		if not ready.ok:
			data.site.notices.append(str(ready.message))
			manual.target = ""
			return
		manual.progress = float(manual.progress) + (float(work_time.call(true, minutes)) if work_time.is_valid() else minutes)
		var required := 3.0 if str(manual.action) in ["survey", "clear"] else float(Env.WORK_MINUTES[int(r.kind)])
		if float(manual.progress) + 0.00000001 >= required:
			var result := harvest(data, str(manual.target), data.cell_from_index(int(manual.cell)), manual.cargo, str(manual.action), false, manual_limit)
			data.site.notices.append(str(result.message))
			manual.target = ""
			manual.progress = 0.0

static func _feature_work(data: TerrainData, key: String, minutes: float, occupied: Callable, work_time: Callable = Callable(), worker_override: Variant = null, cargo_override: Variant = null, carry_limit: int = CARRY_CAPACITY) -> void:
	var worker: Dictionary = data.site.worker if worker_override == null else worker_override
	var cargo: Dictionary = worker.cargo if cargo_override == null else cargo_override
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
		if work_time.is_valid():
			minutes = float(work_time.call(false, minutes))
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
	if work_time.is_valid() and float(feature.production) < float(definition.cycle):
		minutes = float(work_time.call(false, minutes))
	feature.production = minf(float(definition.cycle), float(feature.production) + minutes * water_ratio * productivity)
	feature.status = "生產 %.1f / %.1f 分" % [float(feature.production), float(definition.cycle)]
	worker.status = feature.status
	if float(feature.production) + 0.00000001 >= float(definition.cycle):
		if carry_limit < 0 or inventory_size(cargo) + inventory_size(definition.output) > carry_limit:
			worker.status = "攜帶空間不足"
			return
		add_items(cargo, definition.output)
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
