extends "res://scripts/tests/site_building_ui_test.gd"
## 考試學校 E4 (reports/exam-and-school-plan.md §7, §8; ES-14). A level 3 settlement of faction 1 with duty AI on; its
## head is an NPC (not the controlled person) and the 學正 seat is vacant, so he acts. A district school and the
## settlement center are injected (art pending). Checks:
## - round 1: the NPC seats the most learned qualified teacher; round 2: he fills the student seats, lowest learning
##   first; round 3: with 3 literate candidates and 20 grain he opens a 鄉試;
## - the school page opens from the building panel and lists the seats.
## Output: SITE_SCHOOL_E4_PASS on success; quit(1) on failure.

const Schools = preload("res://scripts/terrain_lab/site_schools.gd")
const PersonSocial = preload("res://scripts/terrain_lab/person_social.gd")
const DutyAI = preload("res://scripts/terrain_lab/site_duty_ai.gd")

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_SCHOOL_E4 OK ", checks, ": ", message)
		return true
	push_error("SITE_SCHOOL_E4_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _run() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var team: TerrainArmy = lab.army
	team.roster_size = 6
	team.faction_id = 1
	var positions: Array[Vector2i] = [Vector2i(30, 31), Vector2i(33, 33), Vector2i(34, 33), Vector2i(35, 33), Vector2i(36, 33), Vector2i(37, 33)]
	if not _ok(team.deploy_at(data, null, null, positions) and team.enable_combat(false), "a six-person team deploys"): return
	team.set_process(false)
	team.settle_combat_command()
	var head := team.combat_identity(0)
	var master := team.combat_identity(1)
	PersonSocial.set_civil_role(team.combat_units[1], "clerk")
	PersonSocial.set_learning(team.combat_units[1], 75)
	for index: int in [2, 3, 4, 5]: PersonSocial.set_learning(team.combat_units[index], 20 + index)
	data.site.features["9310"] = {"kind": "settlement_center", "stage": "complete", "owner_faction": 1, "entrance": data.index(Vector2i(32, 33)), "cells": [data.index(Vector2i(32, 32))]}
	data.site["settlement"] = {"owner_faction": 1, "level": 3, "center_id": "9310", "offices": SiteOffices.default_offices("settlement", head, true)}
	data.site.features["9311"] = {"kind": "district_school", "stage": "complete", "owner_faction": 1, "entrance": data.index(Vector2i(30, 30)), "cells": [data.index(Vector2i(31, 31))]}
	data.site.inventory["grain"] = 25
	DutyAI._school_filled_day.clear()
	var first := DutyAI.review_schools(lab, int(lab.controlled_person_id()))
	var record: Dictionary = Schools.records(data).get("9311", {})
	if not _ok(first.get("ok", false) and record.get("teachers", []) == [master], "round 1: the NPC 學正 seats the qualified teacher", [first, record]): return
	var second := DutyAI.review_schools(lab, int(lab.controlled_person_id()))
	record = Schools.records(data)["9311"]
	var learned: Array = []
	for identity: int in record.students: learned.append(PersonSocial.learning(controller.person_actions._person(identity, false).body))
	var ascending: Array = learned.duplicate()
	ascending.sort()
	if not _ok(second.get("ok", false) and record.students.size() >= 3 and learned == ascending, "round 2: he fills the student seats, lowest learning first", [second, record.students, learned]): return
	var third := DutyAI.review_schools(lab, int(lab.controlled_person_id()))
	record = Schools.records(data)["9311"]
	if not _ok(third.get("ok", false) and not record.exam.is_empty() and record.exam.candidates.size() >= 3 and int(data.site.inventory.grain) == 20, "round 3: he opens a 鄉試 for the literate candidates", [third, record.exam]): return
	controller.feature_key = "9311"
	controller._open_school()
	if not _ok(lab.find_child("SchoolSeats", true, false) != null and controller._ui_dialogs.has("school"), "the school page opens and lists the seats"): return
	# ES-01 with the published art (CC-20261116-194): a level 3 settlement builds a 蒙學 inside its jurisdiction.
	var footprint: Array[int] = [data.index(Vector2i(36, 28))]
	var guard := Runtime.school_build_guard(data, "village_school", footprint, 0)
	if not _ok(guard.code == "LIMIT" or guard.ok, "with its art the 蒙學 passes the build guard (one per settlement)", guard): return
	var built := _formal_feature(data, "village_school", Vector2i(36, 26))
	if not _ok(str(data.site.features[built].kind) == "village_school" and str(data.site.features[built].stage) == "complete", "a real 蒙學 is built and completed", built): return
	data.site.features.erase(built)
	if not _finish_workflow_body(): return
	print("SITE_SCHOOL_E4_PASS checks=", checks)
	controller.invalidate_ui_context()
	data.site.features.erase("9310")
	data.site.features.erase("9311")
	data.site.erase("schools")
	data.site.erase("settlement")
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
