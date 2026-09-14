class_name SiteEquipmentOrders
extends RefCounted
## Pure national requirements plus one actual-holder transaction provider.
## SitePersonActions owns all timing, cancellation and post-contact submission.

const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Visual = preload("res://scripts/ui/human_character_3d_editor.gd")

var lab: Variant
var _actions_ref: WeakRef
var actions: Variant:
	get: return _actions_ref.get_ref() if _actions_ref != null else null
	set(value): _actions_ref = weakref(value) if value != null else null
var equipment_apply_guard: Callable # (original person_id, final slot->item ID map), pure.
var equipment_dye_guard: Callable # (person_id, requested dye changes), pure.

func init(owner: Variant, person_actions: RefCounted) -> void:
	lab = owner
	actions = person_actions
	actions.equipment_orders = self
	# No nation, membership, office or gear is created as a side effect.

func set_standard(requester_id: int, nation_id: String, standard_id: String, display_name: String, slots: Dictionary, dyes: Variant = null) -> Dictionary:
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	var person: Dictionary = lab._combat_target(requester_id)
	if nation.is_empty() or int(nation.get("military_head", -1)) != requester_id or not _member(nation, requester_id) or person.is_empty() or float(person.hp) <= 0.0:
		return Runtime.fail("NO_AUTHORITY", "只有本國真實軍事首長可改標準；玩家或隊長不自動有權")
	var capable: bool = person.owner.combat_can_act(int(person.unit)) if int(person.unit) >= 0 else person.owner.can_act()
	if not capable:
		return Runtime.fail("NO_AUTHORITY", "原軍事首長須清醒自由且可行動；被俘或失能不繞過原資格")
	var normalized := slots.duplicate(true)
	for slot: Variant in normalized:
		if normalized[slot] is Dictionary and not normalized[slot].has("alternatives"):
			normalized[slot]["alternatives"] = [] # Default means no substitution, never a random fallback.
	if not _valid_key(nation_id) or not _valid_key(standard_id) or display_name.is_empty() or display_name.length() > 128 or not _valid_slots(normalized, lab.terrain.site.item_definitions):
		return Runtime.fail("INVALID", "標準名称／同槽位物品定義或替代清單不合法")
	var previous: Dictionary = nation.standards.get(standard_id, {})
	var palette: Variant = previous.get("equipment_dyes", {}) if dyes == null else dyes
	var player_head: bool = bool(actions._person(requester_id, false).get("player", false))
	# NPC choice happens once when authoring a new standard, never on load/control change.
	if dyes == null and previous.is_empty() and not player_head:
		palette = npc_palette_id(nation_id.hash())
	if palette is String:
		if not Runtime.EquipmentDye.PRESETS.has(palette):
			return Runtime.fail("INVALID", "未知的十六組配色")
		palette = Runtime.EquipmentDye.PRESETS[palette].colors
	if not Runtime.EquipmentDye.valid_dyes(palette):
		return Runtime.fail("INVALID", "國別五部位配色")
	if dyes != null and not player_head and not _is_preset(palette):
		return Runtime.fail("INVALID", "NPC 首長從十六組配色選用；玩家首長可自由配色")
	var revision := int(previous.get("revision", 0)) + 1
	if revision >= 2147483647:
		return Runtime.fail("INVALID", "標準提交版本已達上限")
	nation.standards[standard_id] = {"name": display_name, "revision": revision, "slots": normalized}
	if not palette.is_empty():
		nation.standards[standard_id].equipment_dyes = palette.duplicate()
	return Runtime.ok("已更新未來領裝需求；現役實装未變")

func dye_person(requester_id: int, identity: int, changes: Dictionary) -> Dictionary:
	var person: Dictionary = actions._person(identity)
	var ready := _ready(person)
	if not ready.ok:
		return ready
	var requester: Dictionary = actions._person(requester_id)
	if not _ready(requester).ok:
		return Runtime.fail("NO_AUTHORITY", "染色操作者須可行動")
	var authorized := requester_id == identity and bool(person.player)
	for nation: Dictionary in lab.terrain.site.get("equipment_nations", {}).values():
		if int(nation.military_head) == requester_id and _member(nation, requester_id) and _member(nation, identity):
			authorized = true
	if not authorized:
		return Runtime.fail("NO_AUTHORITY", "限原玩家本人，或本國軍事首長套用本國人物配色")
	if not bool(requester.player) and not _npc_dyes_allowed(requester_id, person, changes):
		return Runtime.fail("INVALID", "NPC 須套用完整預設或本國已保存的標準配色")
	var version := int(person.holder.version)
	var checked := Runtime.dye_equipment(lab.terrain, person.holder, changes, version, true)
	if not checked.ok:
		return checked
	if not equipment_dye_guard.is_valid() or not actions.equipment_changed.is_valid():
		return Runtime.fail("UNSUPPORTED", "染色呈現尚未接入")
	checked = equipment_dye_guard.call(identity, changes)
	if not checked.ok:
		return checked
	var result := Runtime.dye_equipment(lab.terrain, person.holder, changes, version)
	if result.ok:
		actions.equipment_changed.call(identity)
	return result

func apply_standard_dyes(requester_id: int, identity: int, nation_id: String, standard_id: String) -> Dictionary:
	var standard := _standard(identity, nation_id, standard_id)
	if standard.is_empty() or not standard.has("equipment_dyes"):
		return Runtime.fail("NO_TARGET", "沒有此國別配色")
	var person: Dictionary = actions._person(identity)
	if person.is_empty():
		return Runtime.fail("NO_TARGET")
	return dye_person(requester_id, identity, _equipped_dyes(person, standard.equipment_dyes))

static func npc_palette_id(selection: int) -> String:
	return str(Runtime.EquipmentDye.PRESETS.keys()[posmod(selection, Runtime.EquipmentDye.PRESETS.size())])

static func _is_preset(colors: Dictionary) -> bool:
	for preset: Dictionary in Runtime.EquipmentDye.PRESETS.values():
		if colors == preset.colors: return true
	return false

func _npc_dyes_allowed(requester_id: int, person: Dictionary, changes: Dictionary) -> bool:
	for preset: Dictionary in Runtime.EquipmentDye.PRESETS.values():
		if changes == _equipped_dyes(person, preset.colors): return true
	# Retain player-authored standards after succession; this is application, not new authorship.
	for nation: Dictionary in lab.terrain.site.get("equipment_nations", {}).values():
		if int(nation.military_head) == requester_id and _member(nation, int(person.person_id)):
			for standard: Dictionary in nation.standards.values():
				if standard.has("equipment_dyes") and changes == _equipped_dyes(person, standard.equipment_dyes): return true
	return false

static func _equipped_dyes(person: Dictionary, colors: Dictionary) -> Dictionary:
	var changes := {}
	for slot: String in colors:
		if person.holder.equipped.has(slot): changes[slot] = colors[slot]
	return changes

func begin_issue(identity: int, nation_id: String, standard_id: String) -> Dictionary:
	return actions.begin_equipment(identity, {"mode": "issue", "nation_id": nation_id, "standard_id": standard_id})

func begin_personal(identity: int, slot: String, item_id: String) -> Dictionary:
	return actions.begin_equipment(identity, {"mode": "personal", "slot": slot, "item_id": item_id})

func prepare(identity: int, request: Dictionary) -> Dictionary:
	var person: Dictionary = actions._person(identity)
	var ready := _ready(person)
	if not ready.ok:
		return ready
	var mode := str(request.get("mode", ""))
	var before: Dictionary = person.holder.equipped.duplicate()
	var planned := before.duplicate()
	var order := {"mode": mode, "person_id": identity, "person_version": int(person.holder.version),
		"before": before, "planned": planned, "take": [], "return": []}
	if mode == "personal":
		if not bool(person.player):
			return Runtime.fail("NO_AUTHORITY", "個人自由換装只接受原玩家本人合法持物")
		var slot := str(request.get("slot", ""))
		var identity_to_wear := str(request.get("item_id", ""))
		if slot.is_empty() or slot.length() > 64:
			return Runtime.fail("INVALID", "裝備槽")
		if not identity_to_wear.is_empty():
			if not person.holder.item_ids.has(identity_to_wear) or person.holder.equipped.values().has(identity_to_wear):
				return Runtime.fail("NO_TARGET", "只能穿戴本人實際持有且尚未穿戴的物品")
			var definition := _held_definition(identity_to_wear, str(person.holder.holder))
			if definition.is_empty() or str(definition.slot) != slot:
				return Runtime.fail("INVALID", "物品不屬於本人或槽位不合")
		planned.erase(slot)
		if not identity_to_wear.is_empty():
			planned[slot] = identity_to_wear
	elif mode == "issue":
		var nation_id := str(request.get("nation_id", ""))
		var standard_id := str(request.get("standard_id", ""))
		var standard := _standard(identity, nation_id, standard_id)
		if standard.is_empty():
			return Runtime.fail("NO_AUTHORITY", "缺少本人真實國別或該國正式標準")
		if not _at_depot(person):
			return Runtime.fail("UNREACHABLE", "本人須停止於原補給點相鄰可達格")
		var depot: Dictionary = lab.terrain.site.depot_items
		order.merge({"nation_id": nation_id, "standard_id": standard_id,
			"standard_revision": int(standard.revision), "depot_version": int(depot.version)})
		for slot: String in standard.slots:
			var requirement: Dictionary = standard.slots[slot]
			var candidates: Array = [str(requirement.definition)] + requirement.alternatives
			var selected := ""
			for definition_id: String in candidates:
				var current_id := str(before.get(slot, ""))
				if not current_id.is_empty() and str(lab.terrain.site.item_records.get(current_id, {}).get("definition", "")) == definition_id:
					selected = current_id
					break
				for item_id: String in depot.item_ids:
					var record: Dictionary = lab.terrain.site.item_records.get(item_id, {})
					if str(record.get("definition", "")) == definition_id and str(record.get("holder", "")) == "depot" and not order.take.has(item_id):
						selected = item_id
						break
				if not selected.is_empty():
					break
			if selected.is_empty():
				return Runtime.fail("MATERIALS", "缺少標準槽位 %s；原裝全部保留，不發模板物品" % slot)
			if selected != str(before.get(slot, "")):
				order.take.append(selected)
				if before.has(slot):
					order["return"].append(str(before[slot]))
				planned[slot] = selected
	else:
		return Runtime.fail("INVALID", "領裝模式")
	if planned == before:
		return Runtime.fail("NO_CHANGE", "原實装已符合本次要求")
	var checked := check(order)
	return Runtime.ok("可執行原人物換裝", {"order": order}) if checked.ok else checked

func check(order: Dictionary) -> Dictionary:
	var person: Dictionary = actions._person(int(order.person_id))
	var ready := _ready(person)
	if not ready.ok:
		return ready
	if int(person.holder.version) != int(order.person_version) or person.holder.equipped != order.before:
		return Runtime.fail("STALE_SOURCE", "本人的實際裝備已變更")
	if int(person.holder.version) >= 2147483646:
		return Runtime.fail("INVALID", "人物物品提交版本已用盡")
	if str(order.mode) not in ["issue", "personal"] or str(order.mode) == "personal" and not bool(person.player):
		return Runtime.fail("NO_AUTHORITY", "個人換裝僅限原玩家本人")
	if not equipment_apply_guard.is_valid() or not actions.equipment_changed.is_valid():
		return Runtime.fail("UNSUPPORTED", "尚未接好該實裝組合的外觀／命中預檢")
	if str(order.mode) == "issue":
		var standard := _standard(int(order.person_id), str(order.nation_id), str(order.standard_id))
		if standard.is_empty() or int(standard.revision) != int(order.standard_revision):
			return Runtime.fail("NO_AUTHORITY", "國別或本次標準版本已改變，請重新領裝")
		if not _at_depot(person):
			return Runtime.fail("UNREACHABLE")
		var depot: Dictionary = lab.terrain.site.depot_items
		if int(depot.version) != int(order.depot_version):
			return Runtime.fail("STALE_SOURCE", "原庫存物品已變更")
		if int(depot.version) >= 2147483646:
			return Runtime.fail("INVALID", "原庫存提交版本已用盡")
		for identity: String in order.take:
			if not depot.item_ids.has(identity) or _held_definition(identity, "depot").is_empty():
				return Runtime.fail("MATERIALS", "本次原實物已不在補給點")
		for identity: String in order["return"]:
			if not person.holder.item_ids.has(identity) or _held_definition(identity, str(person.holder.holder)).is_empty():
				return Runtime.fail("STALE_SOURCE", "退庫原物不再屬於本人")
		var after_size: int = Runtime.carried_size(lab.terrain.site.inventory, depot) + order["return"].size() - order.take.size()
		if after_size > int(lab.terrain.site.capacity):
			return Runtime.fail("STORAGE_FULL", "原補給點無法容納整批退裝")
	var seen := {}
	for slot: String in order.planned:
		var identity := str(order.planned[slot])
		var expected_owner := "depot" if order.take.has(identity) else str(person.holder.holder)
		var definition := _held_definition(identity, expected_owner)
		if seen.has(identity) or definition.is_empty() or str(definition.slot) != slot:
			return Runtime.fail("INVALID", "裝備唯一所有權／同槽位引用失效")
		seen[identity] = true
	var held_count: int = person.holder.item_ids.size() - order["return"].size() + order.take.size()
	if Runtime.inventory_size(person.cargo) + held_count - order.planned.size() + Runtime.opened_food(lab.terrain.site, person.holder) > Runtime.CARRY_CAPACITY:
		return Runtime.fail("STORAGE_FULL", "卸下後超過本人的二十件行囊")
	return equipment_apply_guard.call(int(order.person_id), order.planned)

func commit(order: Dictionary) -> Dictionary:
	var checked := check(order)
	if not checked.ok:
		return checked
	var person: Dictionary = actions._person(int(order.person_id))
	var holder: Dictionary = person.holder
	# One synchronous prevalidated exchange, never two individually fallible transfers.
	# These are the original holders/registry; cargo dictionaries are not replaced.
	if str(order.mode) == "issue":
		var depot: Dictionary = lab.terrain.site.depot_items
		for identity: String in order["return"]:
			holder.item_ids.erase(identity)
			depot.item_ids.append(identity)
			lab.terrain.site.item_records[identity].holder = "depot"
		for identity: String in order.take:
			depot.item_ids.erase(identity)
			holder.item_ids.append(identity)
			lab.terrain.site.item_records[identity].holder = str(holder.holder)
		depot.version = int(depot.version) + 1
	holder.equipped.clear()
	holder.equipped.merge(order.planned)
	holder.version = int(holder.version) + 1
	actions.equipment_changed.call(int(order.person_id))
	return Runtime.ok("原裝退回、新裝實際領取；沒有發放不存在的物品")

func _ready(person: Dictionary) -> Dictionary:
	if person.is_empty() or not actions._ready(person) or float(lab.terrain.site.get("combat_left", 0.0)) > 0.0:
		return Runtime.fail("BUSY", "換装須原人物清醒自由、停止、無其他作業且已脫戰")
	return Runtime.ok()

func _at_depot(person: Dictionary) -> bool:
	return lab.terrain.site.has("depot_cell") and actions._adjacent(person.cell, lab.terrain.cell_from_index(int(lab.terrain.site.depot_cell)))

func _standard(identity: int, nation_id: String, standard_id: String) -> Dictionary:
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if nation.is_empty() or not _member(nation, identity):
		return {}
	return nation.get("standards", {}).get(standard_id, {})

func _held_definition(identity: String, owner_key: String) -> Dictionary:
	var record: Dictionary = lab.terrain.site.item_records.get(identity, {})
	var definition_id := str(record.get("definition", ""))
	var definition: Dictionary = lab.terrain.site.item_definitions.get(definition_id, {})
	return definition if str(record.get("holder", "")) == owner_key and valid_definition(definition_id, definition) else {}

static func _member(nation: Dictionary, identity: int) -> bool:
	for member_id: Variant in nation.get("members", []):
		if int(member_id) == identity:
			return true
	return false

static func _valid_slots(slots: Dictionary, definitions: Dictionary) -> bool:
	if slots.is_empty() or slots.size() > Runtime.EQUIPMENT_SLOTS.size():
		return false
	for slot: Variant in slots:
		var requirement: Variant = slots[slot]
		if not (slot is String or slot is StringName) or str(slot) not in Runtime.EQUIPMENT_SLOTS or not requirement is Dictionary or requirement.size() != 2 or not requirement.get("definition") is String or not requirement.get("alternatives") is Array:
			return false
		var seen := {}
		for definition_id: Variant in [requirement.definition] + requirement.alternatives:
			if not definition_id is String or seen.has(definition_id) or not definitions.has(definition_id) or not valid_definition(definition_id, definitions[definition_id]) or str(definitions[definition_id].slot) != str(slot):
				return false
			seen[definition_id] = true
	return true

static func valid_nations(value: Variant, definitions: Dictionary, known_people: Dictionary) -> bool:
	if not value is Dictionary:
		return false
	var assigned := {}
	for nation_id: Variant in value:
		var nation: Variant = value[nation_id]
		if not nation_id is String or not _valid_key(nation_id) or not nation is Dictionary or nation.size() != 3 or not _integer(nation.get("military_head")) or not nation.get("members") is Array or not nation.get("standards") is Dictionary:
			return false
		if int(nation.military_head) == 1000000000 or not _member(nation, int(nation.military_head)):
			return false
		for identity: Variant in nation.members:
			if not _integer(identity) or int(identity) == 1000000000 or not known_people.has(int(identity)) or assigned.has(int(identity)):
				return false
			assigned[int(identity)] = nation_id
		for standard_id: Variant in nation.standards:
			var standard: Variant = nation.standards[standard_id]
			if not standard_id is String or not _valid_key(standard_id) or not standard is Dictionary or standard.size() != 3 + int(standard.has("equipment_dyes")) or not standard.get("name") is String or standard.name.is_empty() or standard.name.length() > 128 or not _integer(standard.get("revision")) or not standard.get("slots") is Dictionary or not _valid_slots(standard.slots, definitions) or not Runtime.EquipmentDye.valid_dyes(standard.get("equipment_dyes", {})):
				return false
	return true

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= 1.0 and float(value) < 2147483647.0

static func _valid_key(value: String) -> bool:
	if value.is_empty() or value.length() > 32:
		return false
	for character: String in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return false
	return true

static func valid_definition(identity: String, definition: Variant) -> bool:
	if not Runtime.valid_item_definition(identity, definition) or str(definition.slot) not in Runtime.EQUIPMENT_SLOTS or str(definition.asset) == "none":
		return false
	for slot: Dictionary in Visual.PART_SLOTS:
		if str(slot.id) == str(definition.slot):
			for option: Dictionary in slot.options:
				if str(option.id) == str(definition.asset):
					return true
	return false
