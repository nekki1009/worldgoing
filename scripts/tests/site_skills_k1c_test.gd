extends "res://scripts/tests/site_building_ui_test.gd"
## 技能系統 K1c (reports/skill-k1-implementation.md; spec reports/skill-system-plan.md V0.7 §5.5). Checks:
## - initial(): the trade's line is worked half a full-time year a year from 15 through the §5.3 curve: aptitude 50
##   gives about 40 at 20, 67 at 30, 77 at 40, then 80 at 45 and two yearly rolls by 50 (spec §5.5 said about 82; the
##   rolls give 80–90, about 85); a soldier's building and gathering at a quarter year a
##   year; every other work line starts at 30; a line he already has is kept; the packet is marked `start`;
## - on a real Site with skills_start on, the day's settlement seeds a civilian by his household job (farming) and a
##   soldier (building, gathering), an officer by his main weapon (技能 K5; as a 文吏 also 學業 from 7), never the
##   controlled person, and only once; with the switch off
##   (old saves) nobody is seeded and everyone stays at 50.
## Output: SITE_SKILLS_K1C_PASS on success; quit(1) on failure.

const Skills = preload("res://scripts/terrain_lab/person_skills.gd")
const PersonSocial = preload("res://scripts/terrain_lab/person_social.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const Households = preload("res://scripts/terrain_lab/site_households.gd")
const ResidentWork = preload("res://scripts/terrain_lab/site_resident_work.gd")

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_SKILLS_K1C OK ", checks, ": ", message)
		return true
	push_error("SITE_SKILLS_K1C_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _at(age: int, line: String = "farming", rate: float = 0.5, talent: int = 50) -> float:
	var start := Skills.initial({"version": 1, "aptitude": {"body": talent, "mind": talent}}, age, [line], rate, 11, 7)
	return Skills.level(start, line)

func _pure() -> bool:
	var ages := [_at(20), _at(30), _at(40), _at(50)]
	if not _ok(absf(ages[0] - 40.0) < 1.0 and absf(ages[1] - 67.0) < 1.5 and absf(ages[2] - 77.0) < 1.5 and ages[3] >= 80.0 and ages[3] <= 90.0, "aptitude 50: about 40 at 20, 67 at 30, 77 at 40, and from 80 by yearly rolls at 50", ages): return false
	if not _ok(_at(15) == 0.0 and _at(20, "farming", 0.5, 100) > _at(20) and _at(20, "farming", 0.5, 0) < _at(20), "nothing worked by 15; aptitude speeds the start", [_at(15), _at(20, "farming", 0.5, 100), _at(20, "farming", 0.5, 0)]): return false
	var soldier := Skills.initial({"version": 1, "aptitude": {"body": 50, "mind": 50}}, 35, ["building", "gathering"], Skills.SOLDIER_RATE, 11, 7)
	if not _ok(absf(Skills.level(soldier, "building") - 57.1) < 1.0 and absf(Skills.level(soldier, "gathering") - 57.1) < 1.0 and Skills.level(soldier, "farming") == 30.0 and Skills.level(soldier, "craft") == 30.0, "a soldier of 35: building and gathering about 57, farming and craft 30", soldier): return false
	if not _ok(int(soldier.get("start", 0)) == 1 and Skills.valid(soldier) and Skills.level(soldier, "medicine") == 50.0, "the start packet is marked, valid, and leaves the non-work lines at 50", soldier): return false
	var kept := Skills.initial({"version": 1, "lines": {"craft": 91000}}, 40, ["craft"], 0.5, 11, 7)
	if not _ok(Skills.level_milli(kept, "craft") == 91000 and Skills.level(kept, "farming") == 30.0, "a line he already has is kept", kept): return false
	if not _ok(not Skills.valid({"version": 1, "start": 2}) and not Skills.valid({"version": 1, "start": true}), "a malformed start marker is refused"): return false
	return true

func _run() -> void:
	if not _pure(): return
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var house := _formal_feature(data, "house", Vector2i(28, 20), Vector2i.ONE, {"variant": "long"})
	var layout: Dictionary = Runtime.house_layout(data, house)
	var team: TerrainArmy = lab.army
	team.roster_size = 3
	team.faction_id = 1
	var deployed := team.deploy_at(data, null, null, [data.cell_from_index(int(layout.slots[0])), data.cell_from_index(int(layout.slots[1])), Vector2i(34, 30)]) and team.enable_combat(false)
	if not _ok(layout.ok and deployed, "a three-person team deploys"): return
	team.set_process(false)
	var civilian := team.combat_identity(0)
	var soldier := team.combat_identity(1)
	var officer := team.combat_identity(2)
	team.combat_units[0]["military_role"] = "civilian"
	team.combat_units[1]["military_role"] = "soldier"
	team.combat_units[2]["military_role"] = "officer"
	PersonSocial.set_civil_role(team.combat_units[2], "clerk") # 技能 K5: 文武兼備, so he has studied from 7
	if not data.site.has("housing"): data.site["housing"] = {}
	data.site.housing[str(civilian)] = {"version": 1, "house_id": house, "cell": int(layout.slots[0])}
	Households.reconcile(data.site)
	data.site.features["9001"] = {"kind": "farm", "owner_faction": 1, "cells": []}
	data.site.zones.append({"cells": [], "kind": -1, "action": "operate", "feature": "9001", "active": true})
	Households.set_job(data.site, house, "9001")
	if not _ok(ResidentWork.job_of(data.site, civilian) == "9001", "the civilian's household works the farm"): return
	# Switch off (an old save): nobody is seeded.
	data.site.minute = Calendar.day_start_minute(2) + 60
	var off: Dictionary = controller.skills_day()
	if not _ok(int(off.get("seeded", -1)) == 0 and Skills.of(team.combat_units[0]).is_empty() and Skills.of(lab.character).is_empty(), "with the switch off nobody is seeded", off): return
	# Switch on: the next day seeds the civilian and the soldier only.
	data.site["skills_start"] = true
	data.site.minute = Calendar.day_start_minute(3) + 60
	var on: Dictionary = controller.skills_day()
	var civ := Skills.of(team.combat_units[0])
	var sol := Skills.of(team.combat_units[1])
	if not _ok(int(on.get("seeded", 0)) >= 2 and int(civ.get("start", 0)) == 1 and int(sol.get("start", 0)) == 1, "the civilian and the soldier are seeded", [on, civ, sol]): return
	if not _ok(Skills.level(civ, "farming") > 30.0 and Skills.level(civ, "craft") == 30.0 and Skills.level(civ, "building") == 30.0, "the civilian's farming comes from his years on the household's farm, the rest start at 30", civ): return
	if not _ok(Skills.level(sol, "building") > 30.0 and Skills.level(sol, "gathering") > 30.0 and Skills.level(sol, "farming") == 30.0, "the soldier's building and gathering come from his years in the field", sol): return
	var off_packet := Skills.of(team.combat_units[2])
	var line := Skills.martial_line(team.combat_units[2])
	if not _ok(int(off_packet.get("start", 0)) == 1 and Skills.level(off_packet, "farming") == 30.0 and off_packet.get("lines", {}).has(line), "技能 K5: the officer is seeded by his main weapon's line (%s), the work lines at 30" % line, off_packet): return
	if not _ok(PersonSocial.learning(team.combat_units[2]) > PersonSocial.LITERATE and int(off_packet.get("study", 0)) >= PersonSocial.learning(team.combat_units[2]) * 1000, "技能 K5: as a 文吏 he has studied from 7", [PersonSocial.read(team.combat_units[2]), off_packet]): return
	if not _ok(Skills.of(lab.character).is_empty(), "the controlled person keeps his start template"): return
	var before := Skills.of(team.combat_units[0])
	data.site.minute = Calendar.day_start_minute(4) + 60
	controller.skills_day()
	if not _ok(Skills.of(team.combat_units[0]) == before, "a seeded person is not seeded again"): return
	# The farm is a data-only stand-in; take it out before the view draws a frame.
	data.site.features.erase("9001")
	data.site.zones = data.site.zones.filter(func(zone: Dictionary) -> bool: return str(zone.get("feature", "")) != "9001")
	if not _finish_workflow_body(): return
	print("SITE_SKILLS_K1C_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
