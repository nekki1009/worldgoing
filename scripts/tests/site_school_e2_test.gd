extends "res://scripts/tests/site_building_ui_test.gd"
## 考試學校 E2 (reports/exam-and-school-plan.md §5; ES-08, ES-09). A district school of faction 1 is injected as a
## completed feature (art pending). Checks:
## - candidates: literate, no civil role; at most twice the student seats; the fee is paid at the start;
## - the host must stand at the door for 300 effective seconds; away, the exam waits;
## - learning 100 always passes (→ 文吏), learning 20 never does; everyone examined gets last_exam_day;
## - the school cooldown of 60 days and the person cooldown of 30 days;
## - a host who is gone cancels the exam and the fee comes back; the record with a running exam validates.
## Output: SITE_SCHOOL_E2_PASS on success; quit(1) on failure.

const Schools = preload("res://scripts/terrain_lab/site_schools.gd")
const PersonSocial = preload("res://scripts/terrain_lab/person_social.gd")

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_SCHOOL_E2 OK ", checks, ": ", message)
		return true
	push_error("SITE_SCHOOL_E2_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _run() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var actions: SitePersonActions = lab.site_controller.person_actions
	var team: TerrainArmy = lab.army
	team.roster_size = 4
	team.faction_id = 1
	var door := Vector2i(30, 30)
	if not _ok(team.deploy_at(data, null, null, [Vector2i(30, 31), Vector2i(36, 36), Vector2i(37, 36), Vector2i(38, 36)]) and team.enable_combat(false), "a four-person team deploys"): return
	team.set_process(false)
	team.settle_combat_command()
	var host := team.combat_identity(0)
	var scholar := team.combat_identity(1)
	var novice := team.combat_identity(2)
	var clerk := team.combat_identity(3)
	PersonSocial.set_learning(team.combat_units[1], 100)
	PersonSocial.set_learning(team.combat_units[2], 20)
	PersonSocial.set_civil_role(team.combat_units[3], "clerk")
	data.site.features["9302"] = {"kind": "district_school", "stage": "complete", "owner_faction": 1, "entrance": data.index(door), "cells": [data.index(Vector2i(31, 31))]}
	data.site.inventory["grain"] = 7
	var people: Array = [actions._person(scholar, false), actions._person(novice, false)]
	if not _ok(Schools.open_exam(data, "9302", "district", host, [actions._person(clerk, false)]).code == "NOT_ELIGIBLE", "a 文吏 cannot sit the 鄉試"): return
	var opened := Schools.open_exam(data, "9302", "district", host, people)
	if not _ok(opened.ok and int(data.site.inventory.grain) == 2, "the 鄉試 opens and its 5 grain are paid", opened): return
	if not _ok(Schools.open_exam(data, "9302", "district", host, people).code == "BUSY", "one exam at a time"): return
	var results := Schools.advance(data, actions, 299.0)
	if not _ok(not results.has("exams") and float(data.site.schools["9302"].exam.elapsed) == 299.0, "299 seconds at the door is not yet the end"): return
	var wire_people := {}
	for index: int in team.combat_units.size(): wire_people[team.combat_identity(index)] = true
	if not _ok(Schools.validate(data.site, wire_people).ok, "the record with a running exam validates"): return
	results = Schools.advance(data, actions, 1.0)
	var exams: Array = results.get("exams", [])
	if not _ok(exams.size() == 2 and PersonSocial.civil_role(team.combat_units[1]) == "clerk" and PersonSocial.civil_role(team.combat_units[2]) == "none", "learning 100 passes to 文吏, learning 20 fails", exams): return
	var day := int(int(data.site.minute) / 1440)
	if not _ok(int(PersonSocial.read(team.combat_units[2]).last_exam_day) == day and int(data.site.schools["9302"].last_exam_day) == day and data.site.schools["9302"].exam.is_empty(), "both examined carry the exam day; the school too"): return
	data.site.inventory["grain"] = 20
	data.site.minute = int(data.site.minute) + 20 * 1440
	if not _ok(Schools.open_exam(data, "9302", "district", host, [actions._person(novice, false)]).code == "COOLDOWN", "the school waits 60 days"): return
	data.site.minute = int(data.site.minute) + 41 * 1440
	PersonSocial.set_learning(team.combat_units[2], 60)
	var reopened := Schools.open_exam(data, "9302", "district", host, [actions._person(novice, false)])
	if not _ok(reopened.ok, "61 days later the next exam opens for the novice (his own 30 days have passed)", reopened): return
	var grain := int(data.site.inventory.grain)
	team.combat_hot_set(0, &"hp", 0.0)
	Schools.advance(data, actions, 10.0)
	if not _ok(data.site.schools["9302"].exam.is_empty() and int(data.site.inventory.grain) == grain + 5, "a host who is gone cancels the exam and refunds the fee"): return
	var away: Dictionary = actions._person(novice, false)
	var packet := PersonSocial.read(away.body).duplicate(true)
	packet["last_exam_day"] = int(data.site.minute) / 1440 - 5
	away.body.social_state = packet
	if not _ok(Schools.candidate_refusal("district", away.body, int(data.site.minute) / 1440) != "", "a person examined 5 days ago must wait"): return
	if not _finish_workflow_body(): return
	print("SITE_SCHOOL_E2_PASS checks=", checks)
	data.site.features.erase("9302")
	data.site.erase("schools")
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
