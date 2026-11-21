extends "res://scripts/tests/site_building_ui_test.gd"
## 平民 C3c 鄉勇 (civilian plan §4.5; command centre 11/17 option A). A level 2 settlement of faction 1 headed by an NPC
## soldier (the 營務 seat is vacant, so the head decides); two civilian residents registered to a house. Checks:
## - without danger the draft is refused; with an armed enemy of faction 2 on the Site the NPC decider drafts both
##   residents at the next schedule check: they are soldiers, the Site remembers them, the schedule leaves them be;
## - during a fight a draft is refused ("已開戰"), and so is a release while the danger lasts;
## - after the danger and the 30-minute alarm the NPC decider releases them: civilians again, the record cleared;
## - a controlled head is never drafted for: the automatic draft waits for him; he drafts by hand;
## - malformed records are refused by the save rules.
## Output: SITE_MILITIA_PASS on success; quit(1) on failure.

const Militia = preload("res://scripts/terrain_lab/site_militia.gd")
const Schedule = preload("res://scripts/terrain_lab/site_resident_schedule.gd")
const Housing = preload("res://scripts/terrain_lab/site_housing.gd")

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_MILITIA OK ", checks, ": ", message)
		return true
	push_error("SITE_MILITIA_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _role(actions: SitePersonActions, identity: int) -> String:
	return Militia._role(actions._person(identity, false))

func _run() -> void:
	var data := _building_fixture()
	var center := _formal_feature(data, "warehouse", Vector2i(14, 14))
	var house := _formal_feature(data, "house", Vector2i(28, 20), Vector2i.ONE, {"variant": "long"})
	var layout: Dictionary = Runtime.house_layout(data, house)
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	var team: TerrainArmy = lab.army
	team.roster_size = 3
	team.faction_id = 1
	if not _ok(layout.ok and layout.slots.size() >= 2 and team.deploy_at(data, null, null, [Vector2i(34, 26), Vector2i(35, 26), Vector2i(36, 26)]) and team.enable_combat(false), "a three-person team deploys"): return
	team.set_process(false)
	team.settle_combat_command()
	team.formal_commander = -1
	team.acting_commander = -1
	team.current_commander = -1
	team.officer_order.clear()
	team.officer_service.clear()
	team.combat_order = TerrainArmy.CombatOrder.HOLD
	var head := team.combat_identity(0)
	var first := team.combat_identity(1)
	var second := team.combat_identity(2)
	team.combat_units[0]["military_role"] = "soldier"
	team.combat_units[1]["military_role"] = "civilian"
	team.combat_units[2]["military_role"] = "civilian"
	data.site["settlement"] = {"settlement_id": "s1", "owner_faction": 1, "level": 2, "center_id": center, "offices": SiteOffices.default_offices("settlement", head, false)}
	data.site["housing"] = {str(first): {"version": 1, "house_id": house, "cell": int(layout.slots[0])}, str(second): {"version": 1, "house_id": house, "cell": int(layout.slots[1])}}
	var allowed := Militia.authority(lab, -1)
	if not _ok(allowed.ok and int(allowed.decider) == head, "the head decides for the vacant 營務 seat", allowed): return
	var quiet := Militia.draft(lab, head)
	if not _ok(not quiet.ok and str(quiet.code) == "NO_THREAT" and _role(actions, first) == "civilian", "without danger there is no draft", quiet): return

	lab._ensure_army_slots(2)
	var enemy: TerrainArmy = null
	for candidate: TerrainArmy in lab.combat_armies:
		if candidate != team and not candidate.has_army() and not candidate.combat_enabled and candidate.combat_units.is_empty(): enemy = candidate
	enemy.team_id = lab._next_army_identity()
	enemy.faction_id = 2
	enemy.roster_size = 1
	if not _ok(enemy.deploy_at(data, null, null, [Vector2i(70, 70)]) and enemy.enable_combat(false), "an armed enemy stands on the Site"): return
	enemy.set_process(false)
	data.site.minute = 3 * 1440 + 8 * 60
	controller.resident_schedule_tick()
	var record: Dictionary = data.site.get(Militia.SECTION, {})
	if not _ok(_role(actions, first) == "soldier" and _role(actions, second) == "soldier" and record.get("drafted", []) == [mini(first, second), maxi(first, second)] and _role(actions, head) == "soldier", "the NPC decider drafts both residents", record): return
	if not _ok(int(controller.last_resident_schedule.get("started", -1)) == 0 and not Housing.schedule_authority(lab, actions._person(first)), "the schedule leaves the drafted be", controller.last_resident_schedule): return
	if not _ok(Militia.validate(data.site).ok, "the record passes the save rules"): return

	data.site.combat_left = 5.0
	var fighting := Militia.draft(lab, head)
	var early := Militia.release(lab, head)
	if not _ok(not fighting.ok and str(fighting.message).contains("已開戰") and not early.ok and str(early.code) == "BUSY", "no draft in a fight, no release while the danger lasts", [fighting, early]): return
	data.site.combat_left = 0.0

	enemy.combat_enabled = false # the enemy leaves
	data.site.minute = 3 * 1440 + 8 * 60 + 10
	controller.resident_schedule_tick()
	if not _ok(_role(actions, first) == "soldier", "while the alarm holds they stay drafted"): return
	data.site.minute = 3 * 1440 + 9 * 60
	controller.resident_schedule_tick()
	if not _ok(_role(actions, first) == "civilian" and _role(actions, second) == "civilian" and not data.site.has(Militia.SECTION) and _role(actions, head) == "soldier", "after the alarm the NPC decider releases them", data.site.get(Militia.SECTION)): return

	# A controlled head decides himself.
	var me := int(lab.controlled_person_id())
	data.site.settlement.offices = SiteOffices.default_offices("settlement", me, false)
	enemy.combat_enabled = true
	data.site.minute = 3 * 1440 + 9 * 60 + 10
	controller.resident_schedule_tick()
	if not _ok(_role(actions, first) == "civilian", "a controlled decider is not drafted for"): return
	var mine := Militia.draft(lab, me)
	var refused := Militia.draft(lab, head)
	if not _ok(mine.ok and _role(actions, first) == "soldier" and not refused.ok and str(refused.code) == "NO_AUTHORITY", "he drafts by hand; nobody else may", [mine, refused]): return

	for bad: Variant in [{"drafted": [1.5], "at": 0}, {"drafted": [], "at": 0, "x": 1}, {"drafted": "1", "at": 0}, []]:
		if not _ok(not Militia.validate({Militia.SECTION: bad}).ok, "a malformed record is refused", bad): return
	print("SITE_MILITIA_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
