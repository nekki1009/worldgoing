extends "res://scripts/tests/site_building_ui_test.gd"
## Genuine original Lab/Actor/feature/item owners. Local Runtime transactions
## are tested here; the formal common-clock/fatigue/whole40 close is separate.

func _run() -> void:
	deadline = Time.get_ticks_msec() + 90000
	_check_item_candidates()
	await _check_paid_original_feature()
	print("SITE_TECHNOLOGY_FEATURE_OUTPUT_PASS: original item candidate atomicity; actual original charcoal work/payment/source version; completed paid pickup and sequence; no full clock, scope research or whole40 claim")
	quit(0)

func _product(definition_id: String) -> Dictionary:
	var bits := definition_id.split(":")
	return {"definition_id": definition_id, "definition": {"slot": bits[0], "asset": bits[1], "tint": [1.0, 1.0, 1.0, 1.0]}, "slot": ""}

func _check_item_candidates() -> void:
	var data := _building_fixture()
	assert(Runtime.initialize_item_storage(data.site).ok)
	var destination: Dictionary = data.site.depot_items
	var before := var_to_bytes(data.site)
	var products := [_product("weapon:bow_01"), _product("armor:armor_iron_01")]
	var prepared := Runtime.prepare_equipment_creation(data, destination, products, 1)
	assert(prepared.ok, str(prepared))
	assert(var_to_bytes(data.site) == before, "Two real definition candidates never allocate or mutate")
	var first := int(data.site.next_item)
	assert(prepared.item_ids == [str(first), str(first + 1)], "Only original item sequence allocates")
	Runtime._publish_equipment_creation(data, prepared)
	assert(int(data.site.next_item) == first + 2 and int(destination.version) == int(prepared.destination_before.version) + 1)
	for item_id: String in prepared.item_ids:
		assert(destination.item_ids.has(item_id) and data.site.item_records[item_id].holder == "depot" and int(data.site.item_records[item_id].original_owner) == 1)
	assert(data.site.item_definitions[data.site.item_records[str(first + 1)].definition].asset == "armor_iron_01", "Actual original armor definition, not a standard or appearance reward")
	before = var_to_bytes(data.site)
	var guard_calls := [0]
	data.item_transfer_guard = func(_source: Dictionary, original_destination: Dictionary, _resources: Dictionary, ids: Array) -> Dictionary:
		guard_calls[0] += 1
		assert(is_same(original_destination, destination) and ids.size() == 2)
		return Runtime.fail("UNSUPPORTED", "真原物品守衛拒絕整批")
	assert(not Runtime.prepare_equipment_creation(data, destination, products, 1).ok)
	assert(guard_calls[0] == 1 and var_to_bytes(data.site) == before, "Whole batch guard failure changes no sequence, definitions, records or holder")
	data.item_transfer_guard = Callable()
	var bad := products.duplicate(true)
	bad[1].definition.asset = "missing_original_armor"
	assert(not Runtime.prepare_equipment_creation(data, destination, bad, 1).ok and var_to_bytes(data.site) == before)
	bad = products.duplicate(true)
	bad[0].definition.tint = [0.0, 0.0, 0.0, 1.0]
	assert(not Runtime.prepare_equipment_creation(data, destination, bad, 1).ok and var_to_bytes(data.site) == before, "Existing shared definition cannot be replaced")
	destination.version = 2147483646
	before = var_to_bytes(data.site)
	assert(not Runtime.prepare_equipment_creation(data, destination, products, 1).ok and var_to_bytes(data.site) == before)

func _manual_feature_task(lab: TerrainLab, key: String) -> Dictionary:
	var feature: Dictionary = lab.terrain.site.features[key]
	assert(lab.character.place(lab.terrain.cell_from_index(int(feature.entrance)), true))
	var task: Dictionary = lab.terrain.site.manual
	Runtime.assign_task(lab.terrain, Runtime.ok("真原人工設施工位", {"target": "feature:" + key, "action": "operate", "cell": int(feature.entrance)}), task)
	task.cell = int(feature.entrance)
	task.mode = "work"
	lab.terrain.set_meta(&"site_person_actions", weakref(lab.site_controller.person_actions))
	assert(not lab.site_controller.person_actions._technology_operator_for_task(task).is_empty(), "Actual original controlled body and exact manual task")
	return task

func _check_paid_original_feature() -> void:
	var data := _building_fixture()
	var key := _formal_feature(data, "charcoal", Vector2i(18, 18))
	var lab := _building_lab(data)
	var feature: Dictionary = data.site.features[key]
	var task := _manual_feature_task(lab, key)
	var cargo: Dictionary = data.site.manual.cargo
	var stock: Dictionary = data.site.inventory
	var depot: Dictionary = data.site.depot_items
	var wood := int(stock.wood)
	var version := int(depot.version)
	var calls := [0]
	var actual_work := func(_heavy: bool, requested: float) -> float:
		calls[0] += 1
		return requested
	Runtime._feature_work(data, key, 6.0, lab.site_controller.reserves_cell, actual_work, task, cargo, 20, 1)
	assert(bool(feature.batch_paid) and int(stock.wood) == wood - 4 and int(depot.version) == version + 1 and cargo.is_empty())
	assert(feature.tech_batch.operator_id == int(lab.character.person_id) and feature.tech_batch.source_holder == "depot" and feature.tech_batch.materials == {"wood": 4})
	assert(is_equal_approx(float(feature.tech_batch.work_seconds), 360.0) and is_equal_approx(float(feature.production), 6.0))
	assert(not feature.has("technology_output"), "Partial true work is not a completion receipt")
	# Original output capacity can deny pickup while keeping the same paid goods.
	Runtime._feature_work(data, key, 4.0, lab.site_controller.reserves_cell, actual_work, task, cargo, 0, 1)
	assert(bool(feature.batch_paid) and is_equal_approx(float(feature.production), 10.0) and cargo.is_empty())
	assert(int(stock.wood) == wood - 4 and not feature.has("technology_output"))
	var before := var_to_bytes(data.site)
	var denied := Runtime.prepare_feature_output(data, feature, task, cargo, 0)
	assert(not denied.ok and denied.code == "STORAGE_FULL" and var_to_bytes(data.site) == before)
	# Paid endpoint works without future tools/water; the original producing person
	# and actual completed paid ledger provide provenance, not the pickup witness.
	stock.tools = 0
	before = var_to_bytes(data.site)
	var output := Runtime.prepare_feature_output(data, feature, task, cargo, 20)
	assert(output.ok and var_to_bytes(data.site) == before, str(output))
	var original_holder: Dictionary = lab.character.item_state
	var holder_version := int(original_holder.version)
	Runtime.publish_feature_output(data, output)
	assert(cargo == {"charcoal": 2} and int(original_holder.version) == holder_version + 1 and not feature.batch_paid and float(feature.production) == 0.0)
	assert(not feature.has("tech_batch") and not feature.has("tech_trial"))
	assert(Runtime.valid_technology_output_state(feature.technology_output, data, key))
	var receipt: Dictionary = feature.technology_output.receipts[0]
	assert(receipt.id == 1 and receipt.resources == {"charcoal": 2} and receipt.item_ids.is_empty() and float(receipt.work_seconds) == 600.0)
	assert(not Runtime.prepare_feature_output(data, feature, task, cargo, 20).ok, "The completed source cannot mint or count twice")
	stock.tools = 1
	cargo.clear()
	task = _manual_feature_task(lab, key)
	Runtime._feature_work(data, key, 10.0, lab.site_controller.reserves_cell, actual_work, task, cargo, 20, 1)
	assert(int(stock.wood) == wood - 8 and cargo == {"charcoal": 2})
	assert(feature.technology_output.receipts.size() == 1 and int(feature.technology_output.receipts[0].id) == 2 and int(feature.technology_output.next_seq) == 3, "Bounded latest receipt, same original finite sequence")
	var person_before := var_to_bytes(lab.character.capture_state())
	var state_before := var_to_bytes(data.site)
	var corrupt: Dictionary = receipt.duplicate(true)
	corrupt.work_seconds = -1.0
	assert(not Runtime.valid_technology_output(corrupt, data, key))
	corrupt = receipt.duplicate(true)
	corrupt.item_ids = ["999", "999"]
	assert(not Runtime.valid_technology_output(corrupt, data, key))
	assert(var_to_bytes(data.site) == state_before and var_to_bytes(lab.character.capture_state()) == person_before, "Read validators never teach or alter owners")
	lab.queue_free()
	await process_frame
