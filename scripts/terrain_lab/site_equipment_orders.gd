class_name SiteEquipmentOrders
extends RefCounted
## Pure national requirements plus one actual-holder transaction provider.
## SitePersonActions owns all timing, cancellation and post-contact submission.

const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Visual = preload("res://scripts/ui/human_character_3d_editor.gd")
const CULTURES := {"chinese": "中式", "japanese": "日式", "western": "西式"}

var lab: Variant
var _actions_ref: WeakRef
var actions: Variant:
	get: return _actions_ref.get_ref() if _actions_ref != null else null
	set(value): _actions_ref = weakref(value) if value != null else null
var equipment_apply_guard: Callable # (original person_id, final slot->item ID map), pure.
var equipment_team_apply_guard: Callable # (person_id, final slots) -> result with full appearance; pure.
var equipment_team_external_duty_guard: Callable # (person_id) -> bool; original work/delivery/vehicle owners.
var equipment_dye_guard: Callable # (person_id, requested dye changes), pure.

func init(owner: Variant, person_actions: RefCounted) -> void:
	lab = owner
	actions = person_actions
	actions.equipment_orders = self
	# No nation, membership, office or gear is created as a side effect.

func set_nation_culture(requester_id: int, nation_id: String, culture: String) -> Dictionary:
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if not _can_set_standard(requester_id, nation):
		return Runtime.fail("NO_AUTHORITY", "只有本國清醒自由的真實軍事首長可首次設定國家裝備文化")
	if not CULTURES.has(culture):
		return Runtime.fail("INVALID", "國家裝備文化須為中式、日式或西式")
	if nation.has("culture"):
		return Runtime.fail("NO_CHANGE" if nation.culture == culture else "CULTURE_FIXED", "本國裝備文化已固定；不更改現役裝備或持物")
	for standard: Dictionary in nation.standards.values():
		if not _slots_match_culture(standard.slots, lab.terrain.site.item_definitions, culture):
			return Runtime.fail("CULTURE_MISMATCH", "既有標準或替代物含其他文化；請先明確修訂標準，再固定國家文化，原物品未改")
	nation.culture = culture
	return Runtime.ok("本國裝備文化已固定為%s；材質可混搭，原持物及現役裝備未變" % CULTURES[culture])

func _can_set_standard(requester_id: int, nation: Dictionary) -> bool:
	var person: Dictionary = lab._combat_target(requester_id)
	if nation.is_empty() or int(nation.get("military_head", -1)) != requester_id or not _member(nation, requester_id) or person.is_empty() or float(person.hp) <= 0.0:
		return false
	return person.owner.combat_can_act(int(person.unit)) if int(person.unit) >= 0 else person.owner.can_act()

func set_standard(requester_id: int, nation_id: String, standard_id: String, display_name: String, slots: Dictionary, dyes: Variant = null) -> Dictionary:
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	if not _can_set_standard(requester_id, nation):
		return Runtime.fail("NO_AUTHORITY", "只有本國清醒自由的真實軍事首長可改標準；玩家或隊長不自動有權")
	var normalized := slots.duplicate(true)
	for slot: Variant in normalized:
		if normalized[slot] is Dictionary and not normalized[slot].has("alternatives"):
			normalized[slot]["alternatives"] = [] # Default means no substitution, never a random fallback.
	if not _valid_key(nation_id) or not _valid_key(standard_id) or display_name.is_empty() or display_name.length() > 128 or not _valid_slots(normalized, lab.terrain.site.item_definitions):
		return Runtime.fail("INVALID", "標準名称／同槽位物品定義或替代清單不合法")
	if nation.has("culture") and not _slots_match_culture(normalized, lab.terrain.site.item_definitions, str(nation.culture)):
		return Runtime.fail("CULTURE_MISMATCH", "主要裝備與全部替代物須符合本國固定文化；材質不受限制，原標準未改")
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
	if actions.is_busy(identity) or actions.is_busy(requester_id):
		return Runtime.fail("BUSY", "先完成或取消原人物換裝／作業")
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

func begin_team_issue(team: TerrainArmy, requester_id: int, representative_id: int, nation_id: String, standard_id: String, include_player: bool = false, selected_ids: Array[int] = [], simulate_npc_commander: bool = false) -> Dictionary:
	return actions.begin_team_equipment(team, requester_id, representative_id, nation_id, standard_id, include_player, selected_ids, simulate_npc_commander)

func begin_personal(identity: int, slot: String, item_id: String) -> Dictionary:
	return actions.begin_equipment(identity, {"mode": "personal", "slot": slot, "item_id": item_id})

func nation_grants_cape(identity: int) -> bool:
	for nation: Dictionary in lab.terrain.site.get("equipment_nations", {}).values():
		if int(nation.get("military_head", -1)) == identity and _member(nation, identity):
			return true
	return false

static func _team_grants_cape(team: TerrainArmy, index: int) -> bool:
	return team.combat_enabled and team.is_member(index) and not team.member_gone(index) and \
		rank_grants_cape(index, team.formal_commander, team.officer_service, team.officer_order)

static func rank_grants_cape(index: int, formal: int, service: Array, officers: Array) -> bool:
	# Temporary command authority is not an appointment or an end of service.
	return index >= 0 and (index == formal or service.has(index) or officers.has(index))

func cape_role_allowed(identity: int) -> bool:
	var person: Dictionary = actions._person(identity, false)
	if person.is_empty() or float(person.hp) <= 0.0:
		return false
	if nation_grants_cape(identity):
		return true
	if int(person.unit) >= 0:
		return _team_grants_cape(person.owner, int(person.unit))
	# Original actors can hold PLAYER_MEMBER in an Army. Control and remembered
	# command abilities themselves confer no office or clothing permission.
	for team: TerrainArmy in lab.combat_armies:
		if _team_grants_cape(team, team.index_for_identity(identity)):
			return true
	return false

func cape_wear_guard(identity: int, equipped: Dictionary) -> Dictionary:
	if equipped.has("cape") and not cape_role_allowed(identity):
		return Runtime.fail("CAPE_ROLE_RESTRICTED", "披風僅限在任幹部、正式隊長或本國軍事首長；臨時代理指揮、控制人物或歷史能力不授予職位")
	return Runtime.ok()

func retire_capes(identities: Array[int], preview: bool = false) -> Dictionary:
	# Explicit initialization/personnel reconciliation, not a clothing getter or
	# a player action. Keep every real item in the same original holder/backpack.
	var pending: Array[Dictionary] = []
	var seen := {}
	for identity: int in identities:
		if seen.has(identity): continue
		seen[identity] = true
		var person: Dictionary = actions._person(identity)
		if person.is_empty(): return Runtime.fail("NO_TARGET", "披風原持有人資料未就緒")
		if not person.holder.equipped.has("cape"): continue
		var planned: Dictionary = person.holder.equipped.duplicate()
		planned.erase("cape")
		var order := {"mode": "retire_cape", "person_id": identity, "person_version": int(person.holder.version),
			"before": person.holder.equipped.duplicate(), "planned": planned, "take": [], "return": []}
		var checked := check(order)
		if not checked.ok: return checked
		pending.append(order)
	if not preview:
		# No yields or transfers between preflight and commit; each order still
		# rechecks its original version, capacity and strict visual admission.
		for order: Dictionary in pending:
			var result := commit(order)
			assert(result.ok)
	return Runtime.ok("披風保留在本人行囊；原物品、所有權及染色未變")

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
	var cape_guard := cape_wear_guard(identity, planned)
	if not cape_guard.ok:
		return cape_guard
	if planned == before:
		return Runtime.fail("NO_CHANGE", "原實装已符合本次要求")
	var checked := check(order)
	if str(checked.get("code", "")) == "ATLAS_REQUIRED":
		checked.order = order # Same validated request; no new selection after preparation.
	return Runtime.ok("可執行原人物換裝", {"order": order}) if checked.ok else checked

func prepare_team_issue(team: TerrainArmy, requester_id: int, representative_id: int, nation_id: String, standard_id: String, include_player: bool = false, selected_ids: Array[int] = [], simulate_npc_commander: bool = false) -> Dictionary:
	if simulate_npc_commander and not nation_id.begins_with("trial_team_"):
		return Runtime.fail("NO_AUTHORITY", "NPC 指揮模擬僅限明示的測試國別")
	var context := _team_issue_context(team, requester_id, representative_id, include_player, selected_ids, {}, simulate_npc_commander)
	if not context.ok: return context
	var target_ids: Array[int] = context.target_ids
	var standard := _standard(target_ids[0], nation_id, standard_id)
	if standard.is_empty(): return Runtime.fail("NO_AUTHORITY", "目標未全數屬於本國，或該國沒有正式標準")
	var nation: Dictionary = lab.terrain.site.equipment_nations[nation_id]
	var culture := str(nation.get("culture", ""))
	if not _slots_match_culture(standard.slots, lab.terrain.site.item_definitions, culture):
		return Runtime.fail("CULTURE_REQUIRED" if culture.is_empty() else "CULTURE_MISMATCH", "先由原軍事首長設定本國裝備文化")
	var depot: Dictionary = lab.terrain.site.depot_items
	if not Runtime._item_holder_shape(depot) or str(depot.holder) != "depot":
		return Runtime.fail("INVALID", "原補給點持物資料不合法")
	var representative: Dictionary = actions._person(representative_id)
	var requester: Dictionary = actions._person(requester_id)
	var order := {"mode": "team_issue", "terrain": lab.terrain, "site_state": lab.terrain.site,
		"team": team, "team_id": int(team.team_id), "requester_id": requester_id,
		"controlled_id": int(lab.controlled_person_id()),
		"requester_owner": requester.owner, "requester_body": requester.body,
		"requester_cell": lab.terrain.index(requester.cell), "requester_hit": int(requester.hit),
		"representative_id": representative_id, "include_player": include_player,
		"simulate_npc_commander": simulate_npc_commander,
		"representative_owner": representative.owner, "representative_body": representative.body,
		"representative_holder": representative.holder, "representative_cargo": representative.cargo,
		"representative_cell": lab.terrain.index(representative.cell), "representative_hit": int(representative.hit),
		"representative_version": int(representative.holder.version),
		"roster_ids": context.roster_ids, "target_ids": target_ids.duplicate(),
		"nation_id": nation_id, "nation_ref": nation, "standard_id": standard_id,
		"standard_ref": standard, "standard_revision": int(standard.revision),
		"standard_slots": standard.slots.duplicate(true), "culture": culture,
		"depot_holder": depot, "depot_stock": lab.terrain.site.inventory,
		"depot_stock_before": lab.terrain.site.inventory.duplicate(true),
		"records_owner": lab.terrain.site.item_records, "definitions_owner": lab.terrain.site.item_definitions,
		"depot_version": int(depot.version), "depot_ids": depot.item_ids.duplicate(),
		"entries": [], "take": [], "return": [], "records": {}}
	var assigned := {}
	var missing: Array[Dictionary] = []
	for identity: int in target_ids:
		var person: Dictionary = actions._person(identity)
		var before: Dictionary = person.holder.equipped.duplicate()
		var entry := {"person_id": identity, "owner": person.owner, "body": person.body,
			"holder": person.holder, "cargo": person.cargo, "holder_version": int(person.holder.version),
			"holder_ids": person.holder.item_ids.duplicate(), "cargo_before": person.cargo.duplicate(true),
			"cell": lab.terrain.index(person.cell), "hit": int(person.hit),
			"before": before, "planned": before.duplicate(), "take": [], "return": []}
		order.entries.append(entry)
		for slot: String in standard.slots:
			var requirement: Dictionary = standard.slots[slot]
			var candidates: Array = [str(requirement.definition)] + requirement.alternatives
			var current := str(before.get(slot, ""))
			var current_definition := _held_definition(current, str(person.holder.holder)) if not current.is_empty() else {}
			if not current_definition.is_empty() and str(current_definition.slot) == slot and candidates.has(str(lab.terrain.site.item_records[current].definition)):
				if assigned.has(current): return Runtime.fail("INVALID", "同一原物品被兩人重複穿戴")
				assigned[current] = true
			else:
				missing.append({"entry": entry, "slot": slot, "candidates": candidates})
	# Reserve all already compliant real equipment before assigning any depot item.
	var shortages: Array[String] = []
	for needed: Dictionary in missing:
		var chosen := ""
		for definition_id: String in needed.candidates:
			for item_id: String in depot.item_ids:
				if assigned.has(item_id): continue
				var definition := _held_definition(item_id, "depot")
				if not definition.is_empty() and str(lab.terrain.site.item_records[item_id].definition) == definition_id:
					chosen = item_id
					break
			if not chosen.is_empty(): break
		if chosen.is_empty():
			shortages.append("#%d %s" % [int(needed.entry.person_id), str(needed.slot)])
			continue
		assigned[chosen] = true
		needed.entry.planned[needed.slot] = chosen
		needed.entry.take.append(chosen)
		order.take.append(chosen)
		if needed.entry.before.has(needed.slot):
			var old_id := str(needed.entry.before[needed.slot])
			needed.entry["return"].append(old_id)
			order["return"].append(old_id)
	if not shortages.is_empty():
		var missing_result := Runtime.fail("MATERIALS", "缺少原實物：%s；全隊原裝保留" % ", ".join(shortages))
		missing_result.missing = shortages
		return missing_result
	var changed_ids: Array[int] = []
	for entry: Dictionary in order.entries:
		if entry.planned != entry.before: changed_ids.append(int(entry.person_id))
	if changed_ids.is_empty(): return Runtime.fail("NO_CHANGE", "全隊原實裝已符合本次標準")
	for entry: Dictionary in order.entries:
		for item_id: String in entry.before.values() + entry.planned.values():
			order.records[item_id] = lab.terrain.site.item_records.get(item_id, {}).duplicate(true)
	var checked := check_team_issue(order)
	if not checked.ok and str(checked.get("code", "")) != "ATLAS_REQUIRED": return checked
	checked.order = order
	checked.target_ids = target_ids.duplicate()
	checked.changed_ids = changed_ids
	checked.take_count = order.take.size()
	checked.return_count = order["return"].size()
	return checked

func _team_issue_context(team: TerrainArmy, requester_id: int, representative_id: int, include_player: bool, selected_ids: Array[int], order: Dictionary = {}, simulate_npc_commander: bool = false) -> Dictionary:
	if not is_instance_valid(lab) or team == null or not is_instance_valid(team) or not lab.combat_armies.has(team) or not team.combat_enabled or not is_same(team.data, lab.terrain):
		return Runtime.fail("NO_TARGET", "原隊伍或 Site 已失效")
	if bool(lab.terrain.site.get("paused", false)) or lab is Node and lab.is_inside_tree() and lab.get_tree().paused or float(lab.terrain.site.get("combat_left", 0.0)) > 0.0:
		return Runtime.fail("BUSY", "暫停或交戰中不能整隊領裝")
	if team.combat_order != TerrainArmy.CombatOrder.HOLD or team.moving_member_count() > 0 or lab is TerrainLab and is_instance_valid(lab.site_controller) and not lab.site_controller._team_stopped(team):
		return Runtime.fail("BUSY", "原隊伍須 HOLD 並全員停止")
	var requester_index := team.index_for_identity(requester_id)
	var npc_trial: bool = simulate_npc_commander and requester_id != lab.controlled_person_id() and not actions._person(requester_id, false).is_empty()
	if (requester_id != lab.controlled_person_id() and not npc_trial) or requester_index != team.current_commander or not team.command_eligible(requester_index):
		return Runtime.fail("NO_AUTHORITY", "只有目前受控的原隊合格指揮者可下整隊領裝令")
	var representative_index := team.index_for_identity(representative_id)
	var representative: Dictionary = actions._person(representative_id)
	if not team.is_member(representative_index) or representative.is_empty() or not _team_person_present(team, representative_index, representative) or not _ready(representative).ok or not _at_depot(representative):
		return Runtime.fail("UNREACHABLE", "領裝代表須是原隊可行動成員，停止於營地相鄰可達格")
	if not equipment_team_external_duty_guard.is_valid() or not equipment_team_apply_guard.is_valid():
		return Runtime.fail("UNSUPPORTED", "整隊外部職務／實裝預檢尚未接入")
	var requester: Dictionary = actions._person(requester_id)
	if requester.is_empty() or not _ready(requester).ok or equipment_team_external_duty_guard.call(requester_id) or actions.equipment_conflict(requester_id, order):
		return Runtime.fail("BUSY", "原指揮者須清醒自由、停止且無其他作業")
	var roster_ids: Array[int] = []
	for index: int in team.command_members(): roster_ids.append(team.combat_identity(index))
	if not order.is_empty() and (roster_ids != order.roster_ids or int(team.team_id) != int(order.team_id)):
		return Runtime.fail("STALE_SOURCE", "原隊名冊或隊伍已改變")
	var target_ids: Array[int] = []
	if selected_ids.is_empty():
		for index: int in team.command_members():
			var identity := team.combat_identity(index)
			if identity != lab.controlled_person_id() or include_player:
				target_ids.append(identity)
	else:
		target_ids = selected_ids.duplicate()
	if target_ids.is_empty(): return Runtime.fail("NO_TARGET", "請選原隊伍成員")
	var seen := {}
	for identity: int in target_ids:
		var index := team.index_for_identity(identity)
		if seen.has(identity) or not roster_ids.has(identity) or not team.is_member(index) or team.member_gone(index) or identity == lab.controlled_person_id() and not include_player:
			return Runtime.fail("INVALID_MEMBER", "重複、已離隊或未明確納入的原人物")
		seen[identity] = true
		var person: Dictionary = actions._person(identity)
		if person.is_empty() or int(person.faction) != team.faction_id or not is_same(person.owner.data, lab.terrain) or not _team_person_present(team, index, person) or not _ready(person).ok:
			return Runtime.fail("BUSY", "#%d 不在原指揮在場範圍，或已移動、失能、受擊、工作" % identity)
		if equipment_team_external_duty_guard.call(identity) or actions.equipment_conflict(identity, order):
			return Runtime.fail("BUSY", "#%d 已有採集、交糧、車輛或其他人物作業" % identity)
	if equipment_team_external_duty_guard.call(representative_id) or actions.equipment_conflict(representative_id, order):
		return Runtime.fail("BUSY", "領裝代表已有其他原人物作業")
	return Runtime.ok("原隊伍與代表有效", {"target_ids": target_ids, "roster_ids": roster_ids})

func _team_person_present(team: TerrainArmy, index: int, person: Dictionary) -> bool:
	return team.command_reference_valid and team.command_eligible(index) and team.command_reference.distance_to(Vector2(person.cell)) <= team.command_radius + 2.0

func check_team_issue(order: Dictionary) -> Dictionary:
	if str(order.get("mode", "")) != "team_issue" or not is_instance_valid(lab) or not is_same(lab.terrain, order.get("terrain")) or not is_same(lab.terrain.site, order.get("site_state")):
		return Runtime.fail("STALE_SOURCE", "原 Site 已離開；整隊原裝未改")
	if bool(order.get("simulate_npc_commander", false)) and not str(order.get("nation_id", "")).begins_with("trial_team_"):
		return Runtime.fail("NO_AUTHORITY", "NPC 指揮模擬僅限明示的測試國別")
	if actions.has_active_issue(order): return Runtime.fail("BUSY", "同一營地已有另一份未完成領裝作業")
	if int(order.get("controlled_id", -1)) != int(lab.controlled_person_id()):
		return Runtime.fail("STALE_SOURCE", "控制人物已切換；整隊原裝保留")
	var team: TerrainArmy = order.team
	var context := _team_issue_context(team, int(order.requester_id), int(order.representative_id), bool(order.include_player), order.target_ids, order, bool(order.get("simulate_npc_commander", false)))
	if not context.ok: return context
	if context.target_ids.size() != order.entries.size() or context.target_ids != order.target_ids:
		return Runtime.fail("STALE_SOURCE", "整隊原目標已變更")
	var requester: Dictionary = actions._person(int(order.requester_id))
	if not is_same(requester.owner, order.requester_owner) or not is_same(requester.body, order.requester_body) or lab.terrain.index(requester.cell) != int(order.requester_cell) or int(requester.hit) != int(order.requester_hit):
		return Runtime.fail("INTERRUPTED", "原指揮者受擊、移動或已替換")
	var representative: Dictionary = actions._person(int(order.representative_id))
	if not is_same(representative.owner, order.representative_owner) or not is_same(representative.body, order.representative_body) or not is_same(representative.holder, order.representative_holder) or not is_same(representative.cargo, order.representative_cargo) or lab.terrain.index(representative.cell) != int(order.representative_cell) or int(representative.hit) != int(order.representative_hit) or int(representative.holder.version) != int(order.representative_version):
		return Runtime.fail("STALE_SOURCE", "原領裝代表已改變")
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(str(order.nation_id), {})
	var standard: Dictionary = _standard(int(order.target_ids[0]), str(order.nation_id), str(order.standard_id))
	if nation.is_empty() or not is_same(nation, order.nation_ref) or standard.is_empty() or not is_same(standard, order.standard_ref) or int(standard.revision) != int(order.standard_revision) or standard.slots != order.standard_slots or str(nation.get("culture", "")) != str(order.culture):
		return Runtime.fail("STALE_SOURCE", "原國別或標準已變更；請重新預覽")
	if not _slots_match_culture(standard.slots, lab.terrain.site.item_definitions, str(order.culture)):
		return Runtime.fail("CULTURE_MISMATCH", "原國別文化與標準不符")
	var depot: Dictionary = lab.terrain.site.depot_items
	if not Runtime._item_holder_shape(depot) or str(depot.holder) != "depot":
		return Runtime.fail("INVALID", "原補給點持物資料不合法")
	if not is_same(depot, order.depot_holder) or not is_same(lab.terrain.site.inventory, order.depot_stock) or lab.terrain.site.inventory != order.depot_stock_before or not is_same(lab.terrain.site.item_records, order.records_owner) or not is_same(lab.terrain.site.item_definitions, order.definitions_owner) or int(depot.version) != int(order.depot_version) or depot.item_ids != order.depot_ids or int(depot.version) >= 2147483646:
		return Runtime.fail("STALE_SOURCE", "原補給點持物或版本已變更")
	if not actions.equipment_changed.is_valid(): return Runtime.fail("UNSUPPORTED", "原裝備呈現刷新尚未接入")
	var all_take: Array = []
	var all_return: Array = []
	var seen_equipped := {}
	var proposed := {}
	var recipes := {}
	var missing_recipes := {}
	var appearances: Array[Dictionary] = []
	for entry: Dictionary in order.entries:
		var identity := int(entry.person_id)
		if not context.target_ids.has(identity) or _standard(identity, str(order.nation_id), str(order.standard_id)).is_empty():
			return Runtime.fail("NO_AUTHORITY", "原人物國籍或名冊已變更")
		var person: Dictionary = actions._person(identity)
		if person.is_empty() or not is_same(person.owner, entry.owner) or not is_same(person.body, entry.body) or not is_same(person.holder, entry.holder) or not is_same(person.cargo, entry.cargo) or lab.terrain.index(person.cell) != int(entry.cell) or int(person.hit) != int(entry.hit):
			return Runtime.fail("INTERRUPTED", "#%d 原人物受擊、移動或持物已替換" % identity)
		if int(person.holder.version) != int(entry.holder_version) or person.holder.item_ids != entry.holder_ids or person.holder.equipped != entry.before or person.cargo != entry.cargo_before or int(person.holder.version) >= 2147483646:
			return Runtime.fail("STALE_SOURCE", "#%d 原人物持物或貨物已變更" % identity)
		for slot: String in standard.slots:
			var chosen := str(entry.planned.get(slot, ""))
			var record: Dictionary = lab.terrain.site.item_records.get(chosen, {})
			var requirements: Dictionary = standard.slots[slot]
			if chosen.is_empty() or str(record.get("definition", "")) not in [str(requirements.definition)] + requirements.alternatives:
				return Runtime.fail("INVALID", "#%d 的標準槽位無合法原實物" % identity)
		for slot: String in entry.planned:
			var item_id := str(entry.planned[slot])
			var owner_key := "depot" if entry.take.has(item_id) else str(person.holder.holder)
			var definition := _held_definition(item_id, owner_key)
			if seen_equipped.has(item_id) or definition.is_empty() or str(definition.slot) != slot:
				return Runtime.fail("INVALID", "全隊同件重號或同槽位原物品失效")
			if standard.slots.has(slot):
				var actual_culture := definition_culture(definition)
				if not actual_culture.is_empty() and actual_culture != str(order.culture):
					return Runtime.fail("CULTURE_MISMATCH", "#%d 實物文化與國別不同" % identity)
			elif entry.before.get(slot) != item_id:
				return Runtime.fail("INVALID", "非標準槽位不得在領裝時更改")
			if entry.before.get(slot) != item_id and not entry.take.has(item_id):
				return Runtime.fail("INVALID", "新裝未列入原庫存分配")
			seen_equipped[item_id] = true
		for slot: String in entry.before:
			if entry.before[slot] != entry.planned.get(slot, "") and not entry["return"].has(str(entry.before[slot])):
				return Runtime.fail("INVALID", "舊裝未列入原退庫分配")
		for item_id: String in entry.take:
			if all_take.has(item_id) or not depot.item_ids.has(item_id) or _held_definition(item_id, "depot").is_empty():
				return Runtime.fail("MATERIALS", "原庫存實物已失效或重複領取")
			all_take.append(item_id)
		for item_id: String in entry["return"]:
			if all_return.has(item_id) or not person.holder.item_ids.has(item_id) or _held_definition(item_id, str(person.holder.holder)).is_empty():
				return Runtime.fail("STALE_SOURCE", "原退庫實物已失效或重複")
			all_return.append(item_id)
		var held_count: int = person.holder.item_ids.size() - entry["return"].size() + entry.take.size()
		if Runtime.inventory_size(person.cargo) + held_count - entry.planned.size() + Runtime.opened_food(lab.terrain.site, person.holder) > Runtime.CARRY_CAPACITY:
			return Runtime.fail("STORAGE_FULL", "#%d 換裝後行囊超過容量" % identity)
		var cape_guard := cape_wear_guard(identity, entry.planned)
		if not cape_guard.ok: return cape_guard
		if entry.planned != entry.before:
			var admission: Dictionary = equipment_team_apply_guard.call(identity, entry.planned)
			if not admission.ok and str(admission.get("code", "")) != "ATLAS_REQUIRED": return admission
			var appearance: Dictionary = admission.get("appearance", {})
			if appearance.is_empty(): return Runtime.fail("UNSUPPORTED", "整隊預檢未提供完整原人物外觀")
			proposed[identity] = appearance
			var recipe_key := TerrainArmy.EquipmentAtlas._mixed_key(appearance)
			if recipe_key.is_empty(): return Runtime.fail("UNSUPPORTED", "整隊原人物幾何配方不可用")
			recipes[recipe_key] = true
			if str(admission.get("code", "")) == "ATLAS_REQUIRED":
				var plan := TerrainArmy.EquipmentAtlas.mixed_plan(appearance)
				if plan.is_empty(): return Runtime.fail("UNSUPPORTED", "整隊完整圖集配方不可用")
				if not missing_recipes.has(str(plan.key)):
					missing_recipes[str(plan.key)] = true
					appearances.append(appearance)
	if all_take != order.take or all_return != order["return"]:
		return Runtime.fail("INVALID", "整隊原物品分配已改變")
	for item_id: String in order.records:
		if lab.terrain.site.item_records.get(item_id, {}) != order.records[item_id]:
			return Runtime.fail("STALE_SOURCE", "原實物定義、染色或持有人已變更")
	var after_size: int = Runtime.carried_size(lab.terrain.site.inventory, depot) + all_return.size() - all_take.size()
	if after_size > int(lab.terrain.site.capacity):
		return Runtime.fail("STORAGE_FULL", "原補給點無法容納整批退裝")
	var troop_guard := team.team_troop_equipment_guard(proposed)
	if not troop_guard.ok: return troop_guard
	if not appearances.is_empty():
		var pending := Runtime.fail("ATLAS_REQUIRED", "整隊須先準備共用圖集")
		pending.merge({"appearances": appearances, "recipe_count": recipes.size()})
		return pending
	return Runtime.ok("整隊全部原實物與最終兵種可提交", {"appearances": [], "recipe_count": recipes.size()})

func commit_team_issue(order: Dictionary) -> Dictionary:
	var checked := check_team_issue(order)
	if not checked.ok: return checked
	var depot: Dictionary = lab.terrain.site.depot_items
	var changed_ids: Array[int] = []
	# All fallible checks precede this synchronous exchange. No callback can read a half-equipped team.
	for entry: Dictionary in order.entries:
		if entry.planned == entry.before: continue
		var holder: Dictionary = entry.holder
		for item_id: String in entry["return"]:
			holder.item_ids.erase(item_id)
			depot.item_ids.append(item_id)
			lab.terrain.site.item_records[item_id].holder = "depot"
		for item_id: String in entry.take:
			depot.item_ids.erase(item_id)
			holder.item_ids.append(item_id)
			lab.terrain.site.item_records[item_id].holder = str(holder.holder)
		holder.equipped.clear()
		holder.equipped.merge(entry.planned)
		holder.version = int(holder.version) + 1
		changed_ids.append(int(entry.person_id))
	depot.version = int(depot.version) + 1
	for identity: int in changed_ids: actions.equipment_changed.call(identity)
	return Runtime.ok("整隊原實物已一次換裝；未生成物品", {"target_ids": order.target_ids.duplicate(), "changed_ids": changed_ids})

func check(order: Dictionary) -> Dictionary:
	var person: Dictionary = actions._person(int(order.person_id))
	var retirement := str(order.mode) == "retire_cape"
	var ready := Runtime.ok() if retirement and not person.is_empty() else _ready(person)
	if not ready.ok:
		return ready
	if int(person.holder.version) != int(order.person_version) or person.holder.equipped != order.before:
		return Runtime.fail("STALE_SOURCE", "本人的實際裝備已變更")
	if int(person.holder.version) >= 2147483646:
		return Runtime.fail("INVALID", "人物物品提交版本已用盡")
	if str(order.mode) not in ["issue", "personal", "retire_cape"] or str(order.mode) == "personal" and not bool(person.player):
		return Runtime.fail("NO_AUTHORITY", "個人換裝僅限原玩家本人")
	if retirement:
		var uncaped: Dictionary = order.before.duplicate()
		uncaped.erase("cape")
		if not order.before.has("cape") or order.planned != uncaped or not order.take.is_empty() or not order["return"].is_empty():
			return Runtime.fail("INVALID", "職務卸裝只可將原披風收回本人行囊")
	var cape_guard := cape_wear_guard(int(order.person_id), order.planned)
	if not cape_guard.ok:
		return cape_guard
	if not equipment_apply_guard.is_valid() or not actions.equipment_changed.is_valid():
		return Runtime.fail("UNSUPPORTED", "尚未接好該實裝組合的外觀／命中預檢")
	var issue_culture := ""
	var issue_slots := {}
	if str(order.mode) == "issue":
		var standard := _standard(int(order.person_id), str(order.nation_id), str(order.standard_id))
		if standard.is_empty() or int(standard.revision) != int(order.standard_revision):
			return Runtime.fail("NO_AUTHORITY", "國別或本次標準版本已改變，請重新領裝")
		var culture := str(lab.terrain.site.equipment_nations[str(order.nation_id)].get("culture", ""))
		if not _slots_match_culture(standard.slots, lab.terrain.site.item_definitions, culture):
			return Runtime.fail("CULTURE_REQUIRED" if culture.is_empty() else "CULTURE_MISMATCH", "領裝標準須符合本國固定文化；未設定時請由原軍事首長明確選擇，原裝與持物保留")
		issue_culture = culture
		issue_slots = standard.slots
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
		if issue_slots.has(slot):
			var actual_culture := definition_culture(definition)
			if not actual_culture.is_empty() and actual_culture != issue_culture:
				return Runtime.fail("CULTURE_MISMATCH", "本次領取的原實物文化已不符合國別；原裝與持物保留")
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

static func definition_culture(definition: Dictionary) -> String:
	# Editor metadata is authoritative; materials, labels and asset names are not culture.
	# Existing untagged weapons/underlayers have no cultural constraint here.
	for slot: Dictionary in Visual.PART_SLOTS:
		if str(slot.id) == str(definition.get("slot", "")):
			for option: Dictionary in slot.options:
				if str(option.id) == str(definition.get("asset", "")):
					return str(option.get("culture", ""))
	return ""

static func _slots_match_culture(slots: Dictionary, definitions: Dictionary, culture: String) -> bool:
	if not culture.is_empty() and not CULTURES.has(culture): return false
	for requirement: Dictionary in slots.values():
		for identity: String in [str(requirement.definition)] + requirement.alternatives:
			var actual := definition_culture(definitions.get(identity, {}))
			if not actual.is_empty() and actual != culture: return false
	return true

static func valid_nations(value: Variant, definitions: Dictionary, known_people: Dictionary) -> bool:
	if not value is Dictionary:
		return false
	var assigned := {}
	for nation_id: Variant in value:
		var nation: Variant = value[nation_id]
		if not nation_id is String or not _valid_key(nation_id) or not nation is Dictionary or nation.size() != 3 + int(nation.has("culture")) or not _integer(nation.get("military_head")) or not nation.get("members") is Array or not nation.get("standards") is Dictionary:
			return false
		if nation.has("culture") and (not nation.culture is String or not CULTURES.has(nation.culture)):
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
			if nation.has("culture") and not _slots_match_culture(standard.slots, definitions, nation.culture):
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
