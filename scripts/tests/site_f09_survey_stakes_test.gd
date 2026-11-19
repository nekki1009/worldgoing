extends "res://scripts/tests/site_building_ui_test.gd"
## True physical original feature and revalidated original building plan.
## Authored initial learned skill, direct work; rendering/Scope/Native NOT_RUN.
const PersonalTechnology = preload("res://scripts/terrain_lab/site_technology.gd")

func _run() -> void:
	var data := _building_fixture()
	var plan_cells: Array[int] = []
	for y: int in range(14, 17):
		for x: int in range(18, 21): plan_cells.append(data.index(Vector2i(x, y)))
	var plan := {"kind": "house", "cells": plan_cells, "options": {"layout_version": 1, "quarter": 0, "owner_faction": 1}}
	var marks: Array[int] = [data.index(Vector2i(18, 13)), data.index(Vector2i(19, 13))]
	var lab := _building_lab(data)
	var requester := int(lab.controlled_person_id())
	var operator_id := int(lab.npc.person_id)
	var before := var_to_bytes([data.site, lab.npc.technology, data.feature_at, data.static_blocked])
	assert(not Runtime.request_survey_plan(data, requester, operator_id, marks, plan).ok)
	assert(var_to_bytes([data.site, lab.npc.technology, data.feature_at, data.static_blocked]) == before)
	lab.npc.technology = PersonalTechnology.learned_candidate({}, "F09")
	data.site.erase("family")
	before = var_to_bytes([data.site, lab.npc.technology, data.feature_at, data.static_blocked])
	assert(Runtime.request_survey_plan(data, requester, operator_id, marks, plan, Callable(), true).ok)
	assert(var_to_bytes([data.site, lab.npc.technology, data.feature_at, data.static_blocked]) == before, "Original previews are byte-equivalent")
	var overlap: Array[int] = [plan_cells[0], plan_cells[1]]
	assert(not Runtime.request_survey_plan(data, requester, operator_id, overlap, plan).ok)
	assert(var_to_bytes([data.site, lab.npc.technology, data.feature_at, data.static_blocked]) == before, "A marker cannot consume its plan footprint")
	var wood_before := int(data.site.inventory.wood)
	var tools_before := int(data.site.inventory.tools)
	var built := Runtime.request_survey_plan(data, requester, operator_id, marks, plan)
	assert(built.ok, str(built))
	var key := str(built.feature)
	var feature: Dictionary = data.site.features[key]
	assert(feature.kind == "survey_stakes" and feature.cells == marks and float(feature.work) == 2.0 and feature.cost == {"wood": 2})
	assert(int(data.site.inventory.wood) == wood_before - 2 and int(data.site.inventory.tools) == tools_before)
	assert(Runtime.validate_survey_stakes_storage(data, feature).ok)
	var cold: Dictionary = JSON.parse_string(JSON.stringify(feature))
	assert(Runtime.validate_survey_stakes_storage(data, cold).ok and Runtime.validate_feature_layout(data, cold, false).ok)
	cold.survey_plan.options.quarter = {"fake": true}
	assert(not Runtime.validate_survey_stakes_storage(data, cold).ok, "Malformed optional plan fails without casting an invalid type")
	assert(lab.npc.place(data.cell_from_index(int(feature.entrance)), true))
	Runtime.assign_task(data, Runtime.ok("", {"target": "feature:" + key, "action": "construct", "cell": int(feature.entrance)}))
	var task: Dictionary = data.site.worker
	task.cell = int(feature.entrance)
	task.mode = "work"
	var checked := Runtime.work_preflight(data, task, lab.npc.ammo_inventory, Runtime.CARRY_CAPACITY, 1, operator_id)
	assert(checked.ok and float(checked.remaining) == 120.0, str(checked))
	Runtime._feature_work(data, key, 2.0, Callable(), Callable(), task, lab.npc.ammo_inventory, Runtime.CARRY_CAPACITY, 1, operator_id)
	assert(feature.stage == "complete" and float(feature.progress) == 2.0 and str(task.target).is_empty())
	for index: int in marks: assert(data.is_walkable(data.cell_from_index(index)), "Physical markers do not alter navigation or map scale")
	assert(Runtime.survey_plan_preview(data, key, requester).ok, "The saved full original draft remains independently useful")
	var conflicting := Runtime.request_build(data, "house", plan_cells, Callable(), plan.options)
	assert(conflicting.ok)
	before = var_to_bytes([data.site, data.feature_at, data.static_blocked])
	assert(not Runtime.survey_plan_preview(data, key, requester).ok, "Later real geometry change is rechecked, not grandfathered")
	assert(var_to_bytes([data.site, data.feature_at, data.static_blocked]) == before, "Rejected reuse retains the real markers and original plan")
	lab.queue_free()
	print("F09_TRUE_SURVEY_STAKES_PASS: original two markers/work/cost/strict JSON/plan revalidation; rendering/collector/Scope/Native excluded")
	quit(0)
