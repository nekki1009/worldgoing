extends "res://scripts/tests/site_building_ui_test.gd"
## True bounded original crop/payment/output; authored initial learned F01.
## Direct Runtime work is not whole collector/UI/Native/research acceptance.
const PersonalTechnology = preload("res://scripts/terrain_lab/site_technology.gd")

func _run() -> void:
	var data := _building_fixture()
	var plots := [_formal_feature(data, "farm", Vector2i(18, 14), Vector2i(2, 2)), _formal_feature(data, "fiber_farm", Vector2i(24, 14), Vector2i(2, 2))]
	_formal_feature(data, "well", Vector2i(17, 14))
	_formal_feature(data, "well", Vector2i(23, 14))
	var lab := _building_lab(data)
	var requester := int(lab.controlled_person_id())
	var operator_id := int(lab.npc.person_id)
	var selections: Array = []
	for key: String in plots: selections.append({"feature_id": key, "work_slot": 0, "recipe_id": ""})
	var before := var_to_bytes([data.site, lab.npc.technology])
	assert(not Runtime.request_farm_trial_protocol(data, requester, operator_id, selections).ok)
	assert(var_to_bytes([data.site, lab.npc.technology]) == before)
	lab.npc.technology = PersonalTechnology.learned_candidate({}, "F01")
	data.site.erase("family")
	before = var_to_bytes([data.site, lab.npc.technology])
	assert(Runtime.request_farm_trial_protocol(data, requester, operator_id, selections, true).ok)
	assert(var_to_bytes([data.site, lab.npc.technology]) == before, "Preview does not reserve, pay or dispatch")
	assert(not Runtime.request_farm_trial_protocol(data, requester, operator_id, [selections[0], selections[0]]).ok)
	assert(var_to_bytes([data.site, lab.npc.technology]) == before, "Duplicate plot rejection changes no owner")
	assert(Runtime.request_farm_trial_protocol(data, requester, operator_id, selections).ok)
	for key: String in plots:
		var feature: Dictionary = data.site.features[key]
		var packet: Dictionary = feature.farm_trial_protocol
		assert(packet.state == "pending" and packet.result.is_empty())
		assert(Runtime.validate_farm_trial_protocol_storage(data, key, feature).ok)
		var cold: Dictionary = JSON.parse_string(JSON.stringify(feature))
		assert(Runtime.validate_farm_trial_protocol_storage(data, key, cold).ok)
		cold.farm_trial_protocol.extra_approval = true
		assert(not Runtime.validate_farm_trial_protocol_storage(data, key, cold).ok, "Present malformed packet fails")
		var slot: Dictionary = Runtime.feature_work_slots(data, feature)[0]
		assert(lab.npc.place(data.cell_from_index(int(slot.cell)), true))
		Runtime.assign_task(data, Runtime.ok("", {"target": "feature:" + key, "action": "operate", "cell": int(slot.cell), "work_slot": int(slot.slot)}))
		var task: Dictionary = data.site.worker
		task.cell = int(slot.cell)
		task.mode = "work"
		Runtime.set_operating_slots(data, [{"task": task}])
		var checked := Runtime.work_preflight(data, task, lab.npc.ammo_inventory, Runtime.CARRY_CAPACITY, 1, operator_id)
		assert(checked.ok, str(checked))
		var seed_before := int(data.site.inventory.seeds)
		var output: Dictionary = Runtime.feature_recipe(feature).output
		Runtime._feature_work(data, key, float(checked.remaining) / 60.0 + 0.00001, Callable(), Callable(), task, lab.npc.ammo_inventory, Runtime.CARRY_CAPACITY, 1, operator_id)
		assert(int(data.site.inventory.seeds) == seed_before - 1 and feature.farm_trial_protocol.state == "complete")
		assert(feature.farm_trial_protocol.result == feature.technology_output.receipts[0] and feature.farm_trial_protocol.result.resources == output)
		assert(float(feature.farm_trial_protocol.conditions.water_ratio) > 0.0, "Conditions capture the original actual first paid station")
		for resource: String in output: assert(int(lab.npc.ammo_inventory.get(resource, 0)) == int(output[resource]))
		for zone: Dictionary in data.site.zones:
			if str(zone.get("feature", "")) == key and str(zone.action) == "operate": assert(not bool(zone.active))
		lab.npc.ammo_inventory.clear()
		Runtime.assign_task(data, Runtime.ok("", {"target": "feature:" + key, "action": "operate", "cell": int(slot.cell), "work_slot": int(slot.slot)}))
		task = data.site.worker
		task.cell = int(slot.cell)
		task.mode = "work"
		before = var_to_bytes([data.site, lab.npc.ammo_inventory])
		assert(not Runtime.work_preflight(data, task, lab.npc.ammo_inventory, Runtime.CARRY_CAPACITY, 1, operator_id).ok)
		assert(var_to_bytes([data.site, lab.npc.ammo_inventory]) == before, "Completed bound blocks a second payment")
		task.target = ""
		task.mode = "idle"
		Runtime.set_operating_slots(data, [])
		assert(Runtime.cancel_farm_trial_protocol(data, key, requester).ok)
		assert(not feature.has("farm_trial_protocol") and not bool(feature.batch_paid) and is_zero_approx(float(feature.production)))
	lab.queue_free()
	print("F01_BOUNDED_FARM_PROTOCOL_PASS: two original crops/slots, once payment/output, strict JSON, cap/reset; directwork only")
	quit(0)
