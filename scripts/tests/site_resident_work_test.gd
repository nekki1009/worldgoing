extends "res://scripts/tests/site_building_ui_test.gd"
## 平民行為 C2 (reports/civilian-site-behavior-plan.md §4.3; Nekki 11/15 Q2 A). Checks:
## - pure plan rules: food producers first, the least-loaded job next, valid jobs kept, one job per household, and the
##   choose_task exclusions name every other operate feature;
## - on a real Site with a settlement of faction 1: the 戶籍 duty (vacant, so the head acts) plans and sets household
##   jobs, and refuses anyone else or a feature that is not an open job;
## - the schedule hands a civilian with a household job to SiteWorkTeam in a work phase (never a soldier) and takes him
##   off the work in a home phase.
## Output: SITE_RESIDENT_WORK_PASS on success; quit(1) on failure.

const Schedule = preload("res://scripts/terrain_lab/site_resident_schedule.gd")
const ResidentWork = preload("res://scripts/terrain_lab/site_resident_work.gd")
const Households = preload("res://scripts/terrain_lab/site_households.gd")

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_RESIDENT_WORK OK ", checks, ": ", message)
		return true
	push_error("SITE_RESIDENT_WORK_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _operate(state: Dictionary, key: String, kind: String, faction: int, cells: Array = []) -> void:
	state.features[key] = {"kind": kind, "owner_faction": faction, "cells": cells}
	state.zones.append({"cells": cells.duplicate(), "kind": -1, "action": "operate", "feature": key, "active": true})

func _pure() -> bool:
	var state := {"minute": 0, "zones": [], "features": {"10": {"kind": "house", "owner_faction": 1}, "11": {"kind": "house", "owner_faction": 1}, "12": {"kind": "house", "owner_faction": 1}, "13": {"kind": "house", "owner_faction": 2}},
		"housing": {"1": {"version": 1, "house_id": "10", "cell": 1}, "2": {"version": 1, "house_id": "11", "cell": 2}, "3": {"version": 1, "house_id": "12", "cell": 3}, "4": {"version": 1, "house_id": "13", "cell": 4}}}
	_operate(state, "30", "smithy", 1)
	_operate(state, "40", "farm", 1)
	_operate(state, "50", "farm", 2)
	state.zones.append({"cells": [], "kind": -1, "action": "operate", "feature": "60", "active": false})
	state.features["60"] = {"kind": "farm", "owner_faction": 1}
	Households.normalize(state)
	if not _ok(ResidentWork.job_features(state, 1) == ["40", "30"], "food first, own faction, active zones only", ResidentWork.job_features(state, 1)): return false
	var planned := ResidentWork.plan(state, 1)
	if not _ok(planned == {"10": "40", "11": "30", "12": "40"}, "each household gets the least-loaded job, food first", planned): return false
	if not _ok(ResidentWork.apply(state, planned) == 3 and ResidentWork.plan(state, 1).is_empty(), "applied jobs are kept"): return false
	if not _ok(ResidentWork.job_of(state, 2) == "30" and ResidentWork.job_of(state, 4) == "" and ResidentWork.excluded_for(state, 1) == {"feature:30": true, "feature:50": true, "feature:60": true}, "job lookup and exclusions", ResidentWork.excluded_for(state, 1)): return false
	state.zones[1].active = false
	if not _ok(ResidentWork.job_of(state, 1) == "" and ResidentWork.plan(state, 1) == {"10": "30", "12": "30"}, "a stopped job is replanned"): return false
	return true

func _run() -> void:
	if not _pure(): return
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var house := _formal_feature(data, "house", Vector2i(28, 20), Vector2i.ONE, {"variant": "long"})
	var layout: Dictionary = Runtime.house_layout(data, house)
	if not _ok(layout.ok and layout.slots.size() >= 2, "the house has two door rest cells", layout): return
	var team: TerrainArmy = lab.army
	team.roster_size = 2
	team.faction_id = 1
	var deployed := team.deploy_at(data, null, null, [data.cell_from_index(int(layout.slots[0])), data.cell_from_index(int(layout.slots[1]))]) and team.enable_combat(false)
	if not _ok(deployed, "a two-person team deploys at the doors"): return
	team.set_process(false)
	team.settle_combat_command()
	team.formal_commander = -1
	team.acting_commander = -1
	team.current_commander = -1
	team.officer_order.clear()
	team.officer_service.clear()
	team.combat_order = TerrainArmy.CombatOrder.HOLD
	var civilian := team.combat_identity(0)
	var soldier := team.combat_identity(1)
	team.combat_units[0]["military_role"] = "civilian"
	team.combat_units[1]["military_role"] = "soldier"
	if not data.site.has("housing"): data.site["housing"] = {}
	data.site.housing[str(civilian)] = {"version": 1, "house_id": house, "cell": int(layout.slots[0])}
	data.site.housing[str(soldier)] = {"version": 1, "house_id": house, "cell": int(layout.slots[1])}
	Households.reconcile(data.site)
	var job_cells: Array = [data.index(Vector2i(34, 26))]
	_operate(data.site, "9001", "farm", 1, job_cells)
	_operate(data.site, "9002", "farm", 2, job_cells)
	data.site["settlement"] = {"owner_faction": 1, "offices": SiteOffices.default_offices("settlement", soldier, false)}
	if not _ok(controller.plan_household_jobs(civilian).code == "NO_AUTHORITY", "only the duty's decider plans"): return
	if not _ok(controller.assign_household_job(house, "9002", soldier).code == "NO_TARGET", "a feature of another faction is no job"): return
	var planned := controller.plan_household_jobs(soldier)
	if not _ok(planned.ok and int(planned.changed) == 1 and ResidentWork.job_of(data.site, civilian) == "9001", "the acting head plans the household's job", planned): return
	if not _ok(controller.assign_household_job(house, "", soldier).ok and ResidentWork.job_of(data.site, civilian) == "" and controller.assign_household_job(house, "9001", soldier).ok, "the decider clears and sets a job"): return
	data.site.minute = 2 * 1440 + 8 * 60
	controller.resident_schedule_tick()
	if not _ok(int(controller.last_resident_schedule.get("sent", -1)) == 1 and controller.work_team.is_assigned(civilian) and not controller.work_team.is_assigned(soldier), "a work phase sends the civilian to work, not the soldier", controller.last_resident_schedule): return
	data.site.minute = 2 * 1440 + 8 * 60 + 10
	controller.resident_schedule_tick()
	if not _ok(int(controller.last_resident_schedule.working) == 1 and int(controller.last_resident_schedule.sent) == 0, "the next check sees him working"): return
	data.site.minute = 2 * 1440 + 22 * 60 + 1
	controller.resident_schedule_tick()
	if not _ok(not controller.work_team.is_assigned(civilian), "a home phase takes him off the work"): return
	data.site.minute = 2 * 1440 + 22 * 60 + 11
	controller.resident_schedule_tick()
	if not _ok(int(controller.last_resident_schedule.home) == 1, "standing at his door he is home again", controller.last_resident_schedule): return
	print("SITE_RESIDENT_WORK_PASS checks=", checks)
	# The two job features are data-only stand-ins; take them out before the view draws a frame.
	for key: String in ["9001", "9002"]: data.site.features.erase(key)
	data.site.zones = data.site.zones.filter(func(zone: Dictionary) -> bool: return str(zone.get("feature", "")) not in ["9001", "9002"])
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
