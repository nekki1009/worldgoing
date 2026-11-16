extends "res://scripts/tests/site_building_ui_test.gd"
## 考試學校 E1 (reports/exam-and-school-plan.md §3–§4, §6, §9; ES-01, 03–05, 07, 12). A village school of faction 1 is
## injected as a completed feature (its art is still pending, so the real build is refused MISSING_ART). Checks:
## - the build guard: level 1 refuses, level 2 without art refuses MISSING_ART, the state academy needs N07;
## - learning: missing reads 0, 20 for a 文吏; validates, survives upgraded(), refuses out of range;
## - the 學正 duty (vacant, so the head acts) seats a qualified teacher and students and refuses others;
## - a teacher and students present for 300 effective seconds give each student +1; away, nothing; at the cap, nothing;
## - each teacher costs 1 grain a game day; with no grain he teaches nothing;
## - the school record saves and validates; a teacher listed twice is refused.
## Output: SITE_SCHOOL_E1_PASS on success; quit(1) on failure.

const Schools = preload("res://scripts/terrain_lab/site_schools.gd")
const PersonSocial = preload("res://scripts/terrain_lab/person_social.gd")

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_SCHOOL_E1 OK ", checks, ": ", message)
		return true
	push_error("SITE_SCHOOL_E1_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _run() -> void:
	var packet := {"version": 1, "capture_seq": 0, "learning": 55, "last_exam_day": -1}
	if not _ok(PersonSocial.valid(packet) and PersonSocial.upgraded(packet).learning == 55, "learning validates and survives upgraded()"): return
	packet.learning = 101
	if not _ok(not PersonSocial.valid(packet), "learning above 100 refused"): return
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	var team: TerrainArmy = lab.army
	team.roster_size = 4
	team.faction_id = 1
	var door := Vector2i(30, 30)
	var cells: Array[Vector2i] = [Vector2i(30, 31), Vector2i(31, 30), Vector2i(29, 30), Vector2i(36, 36)]
	if not _ok(team.deploy_at(data, null, null, cells) and team.enable_combat(false), "a four-person team deploys around the school door"): return
	team.set_process(false)
	team.settle_combat_command()
	var head := team.combat_identity(0)
	var teacher := team.combat_identity(1)
	var pupil := team.combat_identity(2)
	var far := team.combat_identity(3)
	if not _ok(PersonSocial.learning(team.combat_units[1]) == 0, "missing learning reads 0"): return
	PersonSocial.set_civil_role(team.combat_units[1], "clerk")
	if not _ok(PersonSocial.learning(team.combat_units[1]) == 20, "a 文吏 without learning reads 20 (literate)"): return
	data.site["settlement"] = {"owner_faction": 1, "level": 1, "center_id": "", "offices": SiteOffices.default_offices("settlement", head, false)}
	var footprint: Array[int] = [data.index(Vector2i(40, 40))]
	if not _ok(Runtime.school_build_guard(data, "village_school", footprint, 0).code in ["REQUIREMENTS"], "a level 1 settlement cannot build a 蒙學"): return
	data.site.settlement.level = 2
	var guard := Runtime.school_build_guard(data, "village_school", footprint, 0)
	if not _ok(guard.code in ["REQUIREMENTS", "MISSING_ART"], "level 2 passes the level rule; missing art (or a cell outside the jurisdiction) still refuses", guard): return
	if not _ok(Runtime.school_build_guard(data, "state_academy", footprint, 0).code in ["REQUIREMENTS", "TECH_REQUIRED"], "the state academy is refused"): return
	data.site.features["9301"] = {"kind": "village_school", "stage": "complete", "owner_faction": 1, "entrance": data.index(door), "cells": [data.index(Vector2i(31, 31))]}
	if not _ok(controller.school_seat("9301", teacher, "teacher", true, pupil).code == "NO_AUTHORITY", "only the 學正 (or the acting head) seats"): return
	if not _ok(Schools.set_seat(data, "9301", teacher, team.combat_units[1], "teacher", true).code == "NOT_ELIGIBLE" and Schools.set_seat(data, "9301", head, team.combat_units[0], "teacher", true).code == "NOT_ELIGIBLE", "a 文吏 with learning 20, or a non-文吏, cannot teach a 蒙學 (needs a 文吏 with 40)"): return
	PersonSocial.set_learning(team.combat_units[1], 45)
	var seated_teacher := Schools.set_seat(data, "9301", teacher, team.combat_units[1], "teacher", true)
	var seated_pupil := Schools.set_seat(data, "9301", pupil, team.combat_units[2], "student", true)
	var seated_far := Schools.set_seat(data, "9301", far, team.combat_units[3], "student", true)
	if not _ok(seated_teacher.ok and seated_pupil.ok and seated_far.ok and Schools.set_seat(data, "9301", far, team.combat_units[3], "teacher", true).code == "BUSY", "the teacher and two students take their seats; one person one seat", [seated_teacher, seated_pupil, seated_far]): return
	data.site.inventory["grain"] = 5
	var taught := Schools.advance(data, actions, 299.0)
	if not _ok(taught.is_empty() and int(data.site.inventory.grain) == 4, "a day's grain is paid; 299 seconds is not yet a lesson", taught): return
	taught = Schools.advance(data, actions, 1.0)
	if not _ok(taught.get(pupil, -1) == 1 and not taught.has(far) and PersonSocial.learning(team.combat_units[2]) == 1 and PersonSocial.learning(team.combat_units[3]) == 0, "a full lesson: the present student +1, the one away nothing", taught): return
	PersonSocial.set_learning(team.combat_units[2], 40)
	if not _ok(Schools.advance(data, actions, 300.0).is_empty(), "a student at the cap of 40 learns nothing more"): return
	PersonSocial.set_learning(team.combat_units[2], 10)
	data.site.minute = int(data.site.minute) + 1440
	data.site.inventory["grain"] = 0
	if not _ok(Schools.advance(data, actions, 300.0).is_empty() and data.site.schools["9301"].paid.is_empty(), "no grain: the teacher is unpaid and teaches nothing"): return
	var people := {}
	for index: int in team.combat_units.size(): people[team.combat_identity(index)] = true
	if not _ok(Schools.validate(data.site, people).ok, "the school record validates"): return
	var corrupt: Dictionary = data.site.duplicate(true)
	corrupt.schools["9301"].students.append(teacher)
	if not _ok(Schools.validate(corrupt, people).code == "CORRUPT_SAVE", "a person seated twice is refused"): return
	var wire: Variant = JSON.parse_string(JSON.stringify({"schools": data.site.schools, "features": data.site.features}))
	Schools.normalize(wire)
	if not _ok(Schools.validate(wire, people).ok and wire.schools["9301"].teachers == [teacher], "a JSON round trip normalizes back"): return
	if not _finish_workflow_body(): return
	print("SITE_SCHOOL_E1_PASS checks=", checks)
	data.site.features.erase("9301")
	data.site.erase("schools")
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
