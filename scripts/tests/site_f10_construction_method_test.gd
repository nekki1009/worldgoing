extends "res://scripts/tests/site_building_ui_test.gd"
## Authored initial personal F10 tests a real new construction choice. Direct
## Runtime work excludes whole collector/navigation/earned research acceptance.
const PersonalTechnology = preload("res://scripts/terrain_lab/site_technology.gd")

func _run() -> void:
	var data := _building_fixture()
	var options := {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	var geometry := Runtime.building_cells(data, "house", Vector2i(18, 14), Vector2i(3, 3), options)
	assert(geometry.ok)
	var started := Runtime.request_build(data, "house", geometry.cells, Callable(), options)
	assert(started.ok)
	var key := str(started.feature)
	var feature: Dictionary = data.site.features[key]
	var original_work := float(feature.work)
	var original_cost = feature.cost.duplicate()
	var lab := _building_lab(data)
	var requester := int(lab.controlled_person_id())
	var operator_id := int(lab.npc.person_id)
	var before := var_to_bytes([data.site, lab.npc.technology])
	assert(not Runtime.request_family_construction_method(data, key, requester, operator_id).ok)
	assert(var_to_bytes([data.site, lab.npc.technology]) == before, "Unlearned rejection changes no owner or progress")
	lab.npc.technology = PersonalTechnology.learned_candidate({}, "F10")
	before = var_to_bytes([data.site, lab.npc.technology])
	assert(Runtime.request_family_construction_method(data, key, requester, operator_id, true, true).ok)
	assert(var_to_bytes([data.site, lab.npc.technology]) == before, "Actual preview is byte-equivalent")
	assert(not Runtime.request_family_construction_method(data, key, operator_id, operator_id).ok)
	assert(var_to_bytes([data.site, lab.npc.technology]) == before, "A caller cannot impersonate the current controller")
	assert(Runtime.request_family_construction_method(data, key, requester, operator_id).ok)
	assert(Runtime.validate_family_construction_method_storage(data, feature).ok)
	var json: Dictionary = JSON.parse_string(JSON.stringify(feature))
	assert(Runtime.validate_family_construction_method_storage(data, json).ok, "Strict selection survives original cold JSON")
	json.construction_method.baseline_work = original_work * 0.5
	assert(not Runtime.validate_family_construction_method_storage(data, json).ok, "A packet cannot reduce the original work/refund baseline")
	assert(lab.npc.place(data.cell_from_index(int(feature.entrance)), true))
	Runtime.assign_task(data, Runtime.ok("", {"target": "feature:" + key, "action": "construct", "cell": int(feature.entrance)}))
	var task: Dictionary = data.site.worker
	task.cell = int(feature.entrance)
	task.mode = "work"
	var work := Runtime.work_preflight(data, task, lab.npc.ammo_inventory, Runtime.CARRY_CAPACITY, 1, operator_id)
	assert(work.ok and is_equal_approx(float(work.productivity), 1.0 / 0.9))
	before = var_to_bytes([data.site, lab.npc.technology])
	assert(not Runtime.request_family_construction_method(data, key, requester, operator_id, false).ok)
	assert(var_to_bytes([data.site, lab.npc.technology]) == before, "An occupied original job cannot be silently reselected")
	Runtime._feature_work(data, key, original_work * 0.9, Callable(), Callable(), task, lab.npc.ammo_inventory, Runtime.CARRY_CAPACITY, 1, operator_id)
	assert(feature.stage == "complete" and is_equal_approx(float(feature.work), original_work) \
		and is_equal_approx(float(feature.progress), original_work) and feature.cost == original_cost and not feature.has("construction_method"), "Actual 90percent work completes one original house; baseline cost/work and repairs remain intact")
	assert(Runtime.validate_feature_layout(data, feature, false).ok)
	lab.queue_free()
	print("F10_NEW_CONSTRUCTION_METHOD_PASS: true original choice/work/house/JSON/baselines; directwork, collector/UI/Native/research excluded")
	quit(0)
