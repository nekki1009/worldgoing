extends "res://scripts/tests/site_building_ui_test.gd"
## 考試學校 E3 (reports/exam-and-school-plan.md §3, §4.5, §5.1–§5.3; ES-02, ES-10, ES-11). Checks:
## - the state academy is refused without a nation that knows N07 (TECH_REQUIRED);
## - a 國試 takes clerks with learning ≥ 60 only; a strong candidate passes to 文官; the controller pays the new 文官
##   +2 prestige and the host +1;
## - a literate clerk in a civil seat is promoted after 45 days, an illiterate one after 60.
## Output: SITE_SCHOOL_E3_PASS on success; quit(1) on failure.

const Schools = preload("res://scripts/terrain_lab/site_schools.gd")
const PersonSocial = preload("res://scripts/terrain_lab/person_social.gd")
const CivilPromotion = preload("res://scripts/terrain_lab/site_civil_promotion.gd")
const PersonPersonality = preload("res://scripts/terrain_lab/person_personality.gd")

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_SCHOOL_E3 OK ", checks, ": ", message)
		return true
	push_error("SITE_SCHOOL_E3_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _run() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	var team: TerrainArmy = lab.army
	team.roster_size = 4
	team.faction_id = 1
	var door := Vector2i(30, 30)
	if not _ok(team.deploy_at(data, null, null, [Vector2i(30, 31), Vector2i(36, 36), Vector2i(37, 36), Vector2i(38, 36)]) and team.enable_combat(false), "a four-person team deploys"): return
	team.set_process(false)
	team.settle_combat_command()
	var host := team.combat_identity(0)
	var strong := team.combat_identity(1)
	var weak := team.combat_identity(2)
	var plain := team.combat_identity(3)
	data.site["settlement"] = {"owner_faction": 1, "level": 4, "center_id": "", "offices": SiteOffices.default_offices("settlement", host, false)}
	var footprint: Array[int] = [data.index(Vector2i(40, 40))]
	var refused := Runtime.school_build_guard(data, "state_academy", footprint, 0)
	if not _ok(refused.code in ["REQUIREMENTS", "TECH_REQUIRED"], "the state academy is refused without N07 (or outside the jurisdiction)", refused): return
	for index: int in [1, 2]: PersonSocial.set_civil_role(team.combat_units[index], "clerk")
	PersonSocial.set_learning(team.combat_units[1], 100)
	PersonSocial.set_learning(team.combat_units[2], 50)
	team.combat_units[1]["command_abilities"] = {"tactics": 100.0, "leadership": 100.0, "coach": 100.0}
	team.combat_units[1]["personality"] = PersonPersonality.normalized(PersonPersonality.neutral().merged({"diligence": 100}, true))
	data.site.features["9303"] = {"kind": "state_academy", "stage": "complete", "owner_faction": 1, "entrance": data.index(door), "cells": [data.index(Vector2i(31, 31))]}
	data.site.inventory["grain"] = 30
	if not _ok(Schools.open_exam(data, "9303", "state", host, [actions._person(weak, false)]).code == "NOT_ELIGIBLE" and Schools.open_exam(data, "9303", "state", host, [actions._person(plain, false)]).code == "NOT_ELIGIBLE", "the 國試 refuses a clerk below 60 learning and a non-clerk"): return
	var opened := Schools.open_exam(data, "9303", "state", host, [actions._person(strong, false)])
	if not _ok(opened.ok and int(data.site.inventory.grain) == 15, "the 國試 opens and its 15 grain are paid", opened): return
	var prestige_strong := int(controller.reputation_of(strong).prestige)
	var prestige_host := int(controller.reputation_of(host).prestige)
	var results := Schools.advance(data, actions, 300.0)
	controller._school_results(results)
	if not _ok(PersonSocial.civil_role(team.combat_units[1]) == "official", "the strong clerk passes to 文官", results): return
	var gained_strong := int(controller.reputation_of(strong).prestige) - prestige_strong
	var gained_host := int(controller.reputation_of(host).prestige) - prestige_host
	if not _ok(gained_strong > 0 and gained_host > 0 and gained_strong > gained_host, "the new 文官 gains more prestige than the host", [gained_strong, gained_host]): return
	data.site.features.erase("9303")
	data.site.erase("schools")
	var offices: Dictionary = data.site.settlement.offices
	SiteOffices.position(offices, str(offices.duties["settlement.registry"])).holder = weak
	PersonSocial.set_learning(team.combat_units[2], 30)
	var promoted := {}
	for day: int in range(10, 80):
		data.site.minute = day * 1440 + 600
		promoted = CivilPromotion.daily(lab)
		if not promoted.promoted.is_empty(): break
	if not _ok(promoted.promoted == [weak] and int(data.site.minute) / 1440 == 55, "a literate clerk is promoted after 45 days", [promoted, int(data.site.minute) / 1440]): return
	if not _finish_workflow_body(): return
	print("SITE_SCHOOL_E3_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
