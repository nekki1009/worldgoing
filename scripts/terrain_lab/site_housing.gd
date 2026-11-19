extends RefCounted
## Queries/transactions on Site housing references; no person, stock, or clock owner.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const CrowdOwner = preload("res://scripts/terrain_lab/crowd_person_owner.gd")
const Households = preload("res://scripts/terrain_lab/site_households.gd")
const MULTIPLIER := 1.25
## 平民 C1a: the requester id the resident daily schedule uses. It has authority only over a civilian of a commanderless
## team (the settlement's residents) who is not the controlled person.
const SCHEDULE_REQUESTER := -2

static func _integer(value: Variant, lower: int, upper: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= lower and float(value) <= upper and float(value) == floorf(float(value))

static func _identity(value: Variant) -> bool:
	return value is String and str(value).is_valid_int() and int(value) > 0 and int(value) < 2147483648 and str(int(value)) == value and int(value) != TerrainArmy.PLAYER_MEMBER

static func validate(data: TerrainData, state: Dictionary, people: Dictionary) -> Dictionary:
	var relations: Variant = state.get("housing", {})
	if not relations is Dictionary or relations.size() > people.size(): return Runtime.fail("CORRUPT_SAVE", "住宅原人物引用名單")
	var slots := {}
	var layouts := {}
	for identity: Variant in relations:
		var relation_value: Variant = relations[identity]
		if not _identity(identity) or not relation_value is Dictionary or relation_value.size() != 3 or not _integer(relation_value.get("version"), 1, 1) or not _identity(relation_value.get("house_id")) or not _integer(relation_value.get("cell"), 0, data.size.x * data.size.y - 1):
			return Runtime.fail("CORRUPT_SAVE", "住宅身分、版本或格位")
		var person: Dictionary = people.get(int(identity), {})
		if person.is_empty(): return Runtime.fail("CORRUPT_SAVE", "住宅須引用原人物")
		var house_id: String = relation_value.house_id
		var feature: Dictionary = state.get("features", {}).get(house_id, {})
		if str(feature.get("kind", "")) != "house" or str(feature.get("stage", "")) != "complete" or int(feature.get("layout_version", 0)) != Runtime.BUILDING_LAYOUT_VERSION or not _integer(feature.get("owner_faction"), 0, 100000000):
			return Runtime.fail("CORRUPT_SAVE", "住宅須引用已有管理方的完工住宅")
		if int(person.get("_housing_faction", person.get("faction_id", -1))) != int(feature.owner_faction): return Runtime.fail("CORRUPT_SAVE", "住宅與原住戶陣營不符")
		if not layouts.has(house_id): layouts[house_id] = Runtime.house_layout(data, house_id)
		var layout: Dictionary = layouts[house_id]
		if not layout.ok or not layout.slots.has(int(relation_value.cell)) or slots.has(int(relation_value.cell)): return Runtime.fail("CORRUPT_SAVE", "住宅須引用唯一合法門前休息格")
		if float(person.get("hp", 0.0)) <= 0.0 and bool(person.get("loot_settled", false)): return Runtime.fail("CORRUPT_SAVE", "已完成遺物結算者不能繼續占住房")
		slots[int(relation_value.cell)] = int(identity)
	return Runtime.ok()

static func relation(lab: Variant, identity: int) -> Dictionary:
	var value: Variant = lab.terrain.site.get("housing", {}).get(str(identity), {})
	return value if value is Dictionary else {}

static func _gd_team(lab: Variant, person: Dictionary) -> TerrainArmy:
	if person.owner is TerrainArmy: return person.owner
	for team: TerrainArmy in lab.combat_armies:
		if is_instance_valid(team.player_member) and team.player_member == person.owner: return team
	return null

static func _formation(lab: Variant, person: Dictionary) -> Dictionary:
	if person.owner is CrowdOwner:
		return person.owner.crowd_site.formation_state(int(person.owner.formation_index))
	var team := _gd_team(lab, person)
	if team != null:
		return {"order": int(team.combat_order), "garrisoned": not str(team.garrison_feature_id).is_empty(), "routed": bool(team.is_sustain_routed()), "current_person": team.combat_identity(team.current_commander) if team.command_eligible(team.current_commander) else -1}
	return {"order": int(TerrainArmy.CombatOrder.HOLD), "garrisoned": false, "routed": false, "current_person": int(person.person_id)}

static func _same_team_authority(lab: Variant, requester: Dictionary, person: Dictionary) -> bool:
	if requester.is_empty() or person.is_empty(): return false
	if int(requester.person_id) == int(person.person_id): return true
	if person.owner is CrowdOwner:
		if not requester.owner is CrowdOwner or int(requester.owner.formation_index) != int(person.owner.formation_index): return false
		return int(_formation(lab, person).get("current_person", -1)) == int(requester.person_id)
	var team := _gd_team(lab, person)
	return team != null and _gd_team(lab, requester) == team and team.command_eligible(team.current_commander) and team.combat_identity(team.current_commander) == int(requester.person_id)

static func schedule_authority(lab: Variant, person: Dictionary) -> bool:
	if person.is_empty() or int(person.person_id) == int(lab.controlled_person_id()): return false
	var body: Variant = person.get("body")
	var role: String = str(body.get("military_role", "soldier")) if body is Dictionary else (str(body.military_role) if body is Object and "military_role" in body else "soldier")
	if role != "civilian": return false
	var current := int(_formation(lab, person).get("current_person", -1))
	# A civilian alone in his own team captains it (no leaderless solo): he still keeps his own daily schedule.
	return current < 0 or current == int(person.person_id) and person.owner != null and "combat_units" in person.owner and person.owner.combat_units.size() == 1

static func _commands_current(lab: Variant, requester_id: int, person: Dictionary) -> bool:
	if requester_id != int(lab.controlled_person_id()): return false
	var requester: Dictionary = lab.site_controller.person_actions._person(requester_id)
	return not requester.is_empty() and lab.site_controller.person_actions._ready(requester) and _same_team_authority(lab, requester, person)

## `flee` (平民 C3): a civilian the schedule sends home from danger may start and keep walking during a fight or near an
## enemy; every other refusal stays.
static func context(lab: Variant, identity: int, house_id: String, requester_id: int, allow_moving: bool = false, flee: bool = false) -> Dictionary:
	if lab == null or lab.terrain == null or lab.site_controller == null: return Runtime.fail("NO_TARGET")
	if lab.get_tree().paused or bool(lab.terrain.site.get("paused", false)): return Runtime.fail("PAUSED")
	var actions: RefCounted = lab.site_controller.person_actions
	var person: Dictionary = actions._person(identity)
	var feature: Dictionary = lab.terrain.site.get("features", {}).get(house_id, {})
	var layout: Dictionary = Runtime.house_layout(lab.terrain, house_id)
	if not layout.ok or not bool(layout.get("complete", false)) or not Runtime.feature_usable(feature, "lodging") or int(feature.get("owner_faction", -1)) < 0: return Runtime.fail("NO_HOUSE", "須選取已有管理方的完工可用住宅")
	if person.is_empty() or float(person.hp) <= 0.0 or float(person.ko) > 0.0 or bool(person.captive) or bool(person.get("surrender_pending", false)): return Runtime.fail("BUSY", "原住戶須存活清醒自由")
	if int(person.faction) != int(feature.owner_faction): return Runtime.fail("NO_AUTHORITY")
	var scheduled := requester_id == SCHEDULE_REQUESTER and schedule_authority(lab, person)
	if not scheduled and not _commands_current(lab, requester_id, person) and not (allow_moving and requester_id == int(lab.controlled_person_id()) and (requester_id == identity or _same_team_authority(lab, actions._person(requester_id), person))): return Runtime.fail("NO_AUTHORITY", "須由本人或原當前隊長操作")
	var formation := _formation(lab, person)
	if int(formation.get("order", -1)) != int(TerrainArmy.CombatOrder.HOLD) or bool(formation.get("garrisoned", false)) or bool(formation.get("routed", false)): return Runtime.fail("BUSY", "原人物須保持 HOLD 且未駐營或潰退")
	var fleeing := flee and scheduled
	if not fleeing and float(lab.terrain.site.get("combat_left", 0.0)) > 0.0: return Runtime.fail("BUSY", "須先脫戰")
	if not bool(person.moving) and not actions._ready(person): return Runtime.fail("BUSY")
	if not allow_moving and not actions._prison_stopped(person): return Runtime.fail("BUSY")
	if person.body.get("site_exited") == true or person.body.get("departed") == true: return Runtime.fail("BUSY")
	if actions.is_guarding(identity) or lab.site_controller.vehicles.is_operator(identity) or lab.site_controller.vehicles.is_siege_crew(identity) or not lab.site_controller.vehicles.ship_for_person(identity).is_empty() or lab.site_controller._is_delivering_person(identity): return Runtime.fail("BUSY", "原人物仍有其他職務")
	if person.owner is TerrainArmy and not person.body.get("work_task", {}).is_empty(): return Runtime.fail("BUSY")
	if not fleeing and bool(actions._threat(person, {})): return Runtime.fail("THREAT")
	return Runtime.ok("", {"person": person, "layout": layout})

static func assign(lab: Variant, identity: int, house_id: String, requester_id: int, selected_cell: int = -1) -> Dictionary:
	var checked := context(lab, identity, house_id, requester_id)
	if not checked.ok: return checked
	if lab.site_controller.person_actions.is_busy(identity): return Runtime.fail("BUSY")
	if not relation(lab, identity).is_empty(): return Runtime.fail("ALREADY_HOUSED", "須先明確離住，原登記保留")
	var claimed := {}
	for registered: Dictionary in lab.terrain.site.get("housing", {}).values(): claimed[int(registered.cell)] = true
	var destination := -1
	var choices: Array = checked.layout.slots.duplicate()
	# Fill the outside end first; the original doorway remains a through route.
	choices.reverse()
	for index: int in choices:
		if selected_cell >= 0 and selected_cell != index or claimed.has(index): continue
		var cell: Vector2i = lab.terrain.cell_from_index(index)
		if lab.site_controller.person_actions.prison_blocked(cell, [identity]): continue
		if cell != checked.person.cell and lab.terrain.path_between(checked.person.cell, cell, func(step: Vector2i) -> bool: return lab.site_controller.person_actions.prison_blocked(step, [identity])).is_empty(): continue
		destination = index
		break
	if destination < 0: return Runtime.fail("CAPACITY", "沒有空閒可達的住宅門前休息格")
	if not lab.terrain.site.has("housing"): lab.terrain.site["housing"] = {}
	lab.terrain.site.housing[str(identity)] = {"version": 1, "house_id": house_id, "cell": destination}
	Households.reconcile(lab.terrain.site)
	return Runtime.ok("已分配原住宅；真正到家後才有休息收益", {"cell": destination, "house_id": house_id, "person_id": identity})

static func leave(lab: Variant, identity: int, requester_id: int) -> Dictionary:
	var registered := relation(lab, identity)
	if registered.is_empty(): return Runtime.fail("NO_TARGET")
	var person: Dictionary = lab.site_controller.person_actions._person(identity)
	if person.is_empty() or not _commands_current(lab, requester_id, person): return Runtime.fail("NO_AUTHORITY")
	if lab.get_tree().paused or bool(lab.terrain.site.get("paused", false)) or lab.site_controller.person_actions.is_busy(identity) or bool(person.moving) or not lab.site_controller.person_actions._prison_stopped(person): return Runtime.fail("BUSY", "須先取消返家並收束原步進")
	lab.terrain.site.housing.erase(str(identity))
	Households.reconcile(lab.terrain.site)
	return Runtime.ok("已離住；原人物、位置、物品與供養保留")

static func _attends(lab: Variant, identity: int, ignored_job: Dictionary = {}) -> bool:
	var actions: RefCounted = lab.site_controller.person_actions
	var person: Dictionary = actions._person(identity, false)
	var registered := relation(lab, identity)
	if person.is_empty() or registered.is_empty() or float(person.hp) <= 0.0: return false
	var layout: Dictionary = Runtime.house_layout(lab.terrain, str(registered.house_id))
	var feature: Dictionary = lab.terrain.site.features.get(str(registered.house_id), {})
	if not layout.ok or not bool(layout.complete) or not Runtime.feature_usable(feature, "lodging") or not layout.slots.has(int(registered.cell)) or int(feature.get("owner_faction", -1)) != int(person.faction) or lab.terrain.index(person.cell) != int(registered.cell): return false
	var formation := _formation(lab, person)
	if int(formation.get("order", -1)) != int(TerrainArmy.CombatOrder.HOLD) or bool(formation.get("garrisoned", false)) or bool(formation.get("routed", false)) or float(lab.terrain.site.get("combat_left", 0.0)) > 0.0: return false
	if person.body.get("site_exited") == true or person.body.get("departed") == true or lab.site_controller._is_delivering_person(identity): return false
	if not actions._ready(person) or not actions._prison_stopped(person) or bool(person.get("surrender_pending", false)) or actions.is_guarding(identity): return false
	var busy: Dictionary = actions._jobs.get(str(identity), {})
	if not busy.is_empty() and not is_same(busy, ignored_job): return false
	if lab.site_controller.vehicles.is_operator(identity) or lab.site_controller.vehicles.is_siege_crew(identity) or not lab.site_controller.vehicles.ship_for_person(identity).is_empty(): return false
	return true

static func attendance_input(lab: Variant) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for identity: String in lab.terrain.site.get("housing", {}):
		if not _attends(lab, int(identity)): continue
		var person: Dictionary = lab.site_controller.person_actions._person(int(identity), false)
		if person.owner is CrowdOwner: rows.append({"unit": int(person.unit), "cell": int(relation(lab, int(identity)).cell)})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.unit) < int(b.unit))
	return rows

static func recovery_multiplier(lab: Variant, rows: Array) -> float:
	if lab == null or lab.terrain == null or lab.site_controller == null or lab.terrain.site.get("housing", {}).is_empty(): return 1.0
	var living := 0
	var seen := {}
	for body: Variant in rows:
		var identity := int(body.get("person_id"))
		if seen.has(identity): return 1.0
		seen[identity] = true
		var person: Dictionary = lab.site_controller.person_actions._person(identity, false)
		if person.is_empty(): return 1.0
		if float(person.hp) <= 0.0: continue
		living += 1
		if not _attends(lab, identity): return 1.0
	return MULTIPLIER if living > 0 else 1.0

static func shared_multiplier(lab: Variant, team: TerrainArmy) -> float:
	var rows: Array = []
	for row: Dictionary in team.combat_units:
		if is_same(PersonFatigue.pool(row), team.team_fatigue): rows.append(row)
	if is_instance_valid(team.player_member) and is_same(team.player_member._fatigue_pool, team.team_fatigue): rows.append(team.player_member)
	return recovery_multiplier(lab, rows)

static func query(lab: Variant, house_id: String) -> Dictionary:
	var layout: Dictionary = Runtime.house_layout(lab.terrain, house_id)
	if not layout.ok: return layout
	var occupants: Array[Dictionary] = []
	var at_home := 0
	var captured := 0
	var dead := 0
	for key: String in lab.terrain.site.get("housing", {}):
		var registered: Dictionary = lab.terrain.site.housing[key]
		if str(registered.house_id) != house_id: continue
		var person: Dictionary = lab.site_controller.person_actions._person(int(key), false)
		var status := "人物引用失效"
		if not person.is_empty():
			if float(person.hp) <= 0.0: status = "等待原遺物結算"; dead += 1
			elif bool(person.captive): status = "被俘"; captured += 1
			elif _attends(lab, int(key)): status = "在家"; at_home += 1
			elif lab.site_controller.person_actions.job_for(int(key)).get("kind", "") == "housing_return": status = "返家中"
			else: status = "營外／不能休息"
		occupants.append({"person_id": int(key), "cell": int(registered.cell), "status": status})
	return Runtime.ok("住宅門前休息", {"capacity": int(layout.capacity), "registered": occupants.size(), "at_home": at_home, "captive": captured, "dead": dead, "occupants": occupants, "layout": layout})
