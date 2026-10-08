extends "res://scripts/tests/site_workflow_test.gd"

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 90000
	_run.call_deferred()

func _building_fixture() -> TerrainData:
	var data := _fixture()
	for y: int in range(8, 52):
		for x: int in range(8, 52):
			var index := data.index(Vector2i(x, y))
			data.height_levels[index] = 0
			data.flags[index] = TerrainData.Flag.WALKABLE
			data.ramp_edges[index] = 0
			data.surface_types[index] = TerrainData.Surface.GRASS
			data.groundwater[index] = 80
			data.foundation[index] = 80
			data.fertility[index] = 60
			data.drainage[index] = 70
			data.moisture[index] = 70
			for key: String in data.resources_at.get(index, []): Env.change(data, key, {"cleared": true, "remaining": 0})
	data.site.depot_cell = data.index(Vector2i(9, 9))
	data.site.worker.cell = data.index(Vector2i(10, 9))
	data.site.manual.cell = data.index(Vector2i(10, 10))
	for item: String in Env.ITEM_NAMES: data.site.inventory[item] = 10000
	data.site.capacity = 1000000
	Env.rebuild_indexes(data)
	Runtime.rebuild_terrain_edges(data)
	return data

func _building_lab(data: TerrainData) -> TerrainLab:
	var lab := TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.site_controller._auto_save_blocked = true
	lab.bind_terrain(data)
	lab.character.faction_id = 1
	lab.npc.faction_id = 1
	assert(lab.character.place(Vector2i(10, 10), true))
	assert(lab.npc.place(Vector2i(10, 9), true))
	lab.site_controller.release_worker()
	return lab

func _complete_key(data: TerrainData, key: String) -> void:
	var feature: Dictionary = data.site.features[key]
	Runtime.assign_task(data, Runtime.ok("", {"target": "feature:" + key, "action": "construct", "cell": feature.entrance}))
	data.site.worker.cell = feature.entrance
	data.site.worker.mode = "work"
	Runtime.advance(data, float(feature.get("pending_build", feature).work) + 1.0, true, false, Callable(), Callable(), Callable(), Runtime.CARRY_CAPACITY, Runtime.CARRY_CAPACITY, 1.0, 1)
	assert(str(feature.stage) == "complete" and not feature.has("pending_build"), str(feature))
	data.site.worker.cell = data.index(Vector2i(10, 9))
	data.site.worker.mode = "idle"

func _formal_feature(data: TerrainData, kind: String, anchor: Vector2i, extent: Vector2i = Vector2i.ONE, options: Dictionary = {}) -> String:
	var settings := {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	# Historical military/Garrison fixtures keep their original physical cells.
	# Dense barracks tests explicitly request v2; the real UI uses Runtime's default.
	if kind == "barracks": settings["barracks_layout_version"] = 1
	settings.merge(options, true)
	var placement := Runtime.building_cells(data, kind, anchor, extent, settings)
	assert(placement.ok, str(placement))
	var result := Runtime.request_build(data, kind, placement.cells, Callable(), settings)
	assert(result.ok, str(result))
	_complete_key(data, str(result.feature))
	return str(result.feature)

func _press(lab: TerrainLab, name: String) -> void:
	var button := lab.find_child(name, true, false) as Button
	assert(button != null and not button.disabled, name)
	button.pressed.emit()

func _choose(controller: SiteController, kind: String, anchor: Vector2i, extent: Vector2i, camp_type: String = "standard") -> void:
	var choice := controller._building_choice(kind, camp_type)
	assert(choice >= 0, "Formal building choice is unavailable: %s/%s" % [kind, camp_type])
	controller.buildings.select(choice)
	controller.buildings.item_selected.emit(controller.buildings.selected)
	controller.selected = anchor
	controller.modes.select(5)
	controller._set_building_footprint(anchor, extent)

func _assert_native_worker_unavailable(lab: TerrainLab, identity: int) -> void:
	var controller: SiteController = lab.site_controller
	var person := controller.person_actions._person(identity)
	assert(not person.is_empty() and person.owner is CrowdPersonOwner)
	var original_selection := lab.selected_army_target
	var original_executor := controller.person_executor_id
	var original_workers := controller.work_team.active_ids()
	var original_task: Dictionary = person.body.get("work_task", {}).duplicate(true)
	lab.selected_army_target = identity
	controller.update_ui()
	assert(controller.assign_worker_button.disabled and controller.assign_worker_button.tooltip_text.contains("原生群眾"))
	var check := controller._selected_worker_assignment()
	assert(not check.ok and check.code == "CROWD_ACTIVE")
	controller.assign_worker_button.pressed.emit() # Stale input must also respect the real owner type.
	assert(controller.message.text.contains("原生群眾"))
	assert(controller.work_team.active_ids() == original_workers and person.body.get("work_task", {}) == original_task)
	lab.selected_army_target = original_selection
	controller.person_executor_id = original_executor
	controller.update_ui()

func _assert_building_options_visible(controller: SiteController, choices: Array[OptionButton]) -> void:
	controller.open_window("construction")
	for _frame: int in range(3): await process_frame
	for choice: OptionButton in choices:
		var text_width := choice.get_theme_font("font").get_string_size(choice.get_item_text(choice.selected), HORIZONTAL_ALIGNMENT_LEFT, -1, choice.get_theme_font_size("font_size")).x
		assert(choice.is_visible_in_tree() and choice.size.x >= text_width + 32.0, "Building option text is clipped to its arrow")
	controller.hide_tool_windows()

func _assert_gate_parts_stay_aligned(data: TerrainData, view: SiteResourceView) -> void:
	for quarter: int in [1, 3]:
		var key := _formal_feature(data, "gate", Vector2i(40, 28 if quarter == 1 else 33), Vector2i.ONE, {"quarter": quarter})
		var feature: Dictionary = data.site.features[key]
		var original := {}
		for part: Dictionary in view.building_part_draws(feature):
			if str(part.part_id) in ["leaf:right", "frame:right"]: original[str(part.part_id)] = part.rect
		assert(Runtime.damage_structure_part(data, key, "frame:left", Runtime.WOOD_PART_HP).ok)
		var rubble := Rect2()
		var survivor := Rect2()
		for part: Dictionary in view.building_part_draws(feature):
			if str(part.part_id) in original: assert(part.rect == original[str(part.part_id)], "Damage displaced the surviving original frame")
			if str(part.part_id) == "leaf:left": rubble = part.rect
			if str(part.part_id) == "leaf:right": survivor = part.rect
		assert(rubble.has_area() and survivor.has_area() and is_equal_approx(rubble.end.x, survivor.position.x), "Side gate damage opened an artificial split between registered parts")

func _run() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var view: SiteResourceView = controller.view
	_choose(controller, "house", Vector2i(16, 16), Vector2i.ONE)
	controller.building_variant.select(2) # Long house, 4 x 3.
	controller.building_variant.item_selected.emit(2)
	controller.building_direction.select(1)
	controller.building_direction.item_selected.emit(1)
	await _assert_building_options_visible(controller, [controller.building_variant, controller.building_direction])
	assert(Runtime._cell_bounds(data, controller.build_cells).size == Vector2i(3, 4))
	assert(not controller.building_width.editable and not view.building_preview.is_empty())
	var expected := Runtime.preview_build(data, "house", controller.build_cells, controller.reserves_cell, controller._building_options())
	assert(expected.ok and int(expected.options.quarter) == 1)
	var wood := int(data.site.inventory.wood)
	_press(lab, "BuildFeature")
	var house_key := controller.feature_key
	assert(not house_key.is_empty() and int(data.site.inventory.wood) == wood - int(expected.cost.wood))
	var house: Dictionary = data.site.features[house_key]
	assert(str(house.variant) == "long" and int(house.quarter) == 1 and house.cells == expected.cells)
	assert(view.building_preview.is_empty())
	_complete_key(data, house_key)
	assert(view.building_art_key(house) == "house_long_west")
	assert(not view.building_part_draws(house).is_empty())
	_choose(controller, "farm", Vector2i(24, 16), Vector2i(3, 3))
	_press(lab, "BuildFeature")
	var farm_key := controller.feature_key
	_complete_key(data, farm_key)
	controller.update_ui()
	_press(lab, "ResizeFeature")
	assert(controller.building_resize and controller.feature_key == farm_key)
	controller._set_building_footprint(Vector2i(24, 16), Vector2i(4, 3))
	_press(lab, "BuildFeature")
	assert(controller.feature_key == farm_key and data.site.features[farm_key].cells.size() == 9)
	assert(data.site.features[farm_key].pending_build.cells.size() == 12)
	_complete_key(data, farm_key)
	assert(data.site.features[farm_key].cells.size() == 12)
	var pasture_key := _formal_feature(data, "pasture", Vector2i(32, 16), Vector2i(6, 4))
	var pasture: Dictionary = data.site.features[pasture_key]
	assert(lab.character.place(data.cell_from_index(int(pasture.entrance)), true))
	controller.feature_key = pasture_key
	controller.update_ui()
	assert(Runtime.livestock_capacity(data, pasture) > 36)
	assert(controller.details.text.contains("牧場容量 %d 頭" % Runtime.livestock_capacity(data, pasture)))
	var unstock_quantity := lab.find_child("UnstockLivestockCount", true, false) as SpinBox
	assert(unstock_quantity != null and int(unstock_quantity.max_value) == Runtime.CARRY_CAPACITY)
	var residents := int(pasture.residents)
	var sheep := int(data.site.manual.cargo.get("sheep", 0))
	_press(lab, "UnstockPasture")
	assert(int(pasture.residents) == residents - 1 and int(data.site.manual.cargo.sheep) == sheep + 1)
	_press(lab, "StockPasture")
	assert(int(pasture.residents) == residents and int(data.site.manual.cargo.get("sheep", 0)) == sheep)
	var gate_key := _formal_feature(data, "gate", Vector2i(22, 28), Vector2i.ONE, {"material": "stone"})
	var gate: Dictionary = data.site.features[gate_key]
	var geometry := Runtime.feature_geometry(data, gate)
	assert(lab.character.place(data.cell_from_index(int(geometry.operation[0])), true))
	controller.feature_key = gate_key
	controller.update_ui()
	_press(lab, "OpenGate")
	assert(str(gate.gate.pending) == "open" and not bool(gate.gate.open))
	data.site.paused = true
	lab._advance_action_time(Runtime.GATE_SECONDS)
	assert(float(gate.gate.progress) == 0.0 and not bool(gate.gate.open))
	data.site.paused = false
	lab._advance_action_time(Runtime.GATE_SECONDS * 0.5)
	assert(float(gate.gate.progress) > 0.0 and not bool(gate.gate.open))
	lab._advance_action_time(Runtime.GATE_SECONDS * 0.5 + TerrainLab.ACTION_STEP)
	assert(bool(gate.gate.open) and str(gate.gate.pending).is_empty(), str(gate.gate))
	_press(lab, "CloseGate")
	lab._advance_action_time(Runtime.GATE_SECONDS + TerrainLab.ACTION_STEP)
	assert(not bool(gate.gate.open))
	var prison_key := _formal_feature(data, "prison", Vector2i(32, 28), Vector2i(3, 3))
	controller.feature_key = prison_key
	controller.update_ui()
	_press(lab, "ManagePrison")
	assert(controller._ui_dialogs.has("prison"))
	var original_dialog: Window = controller._ui_dialogs.prison.dialog
	controller._open_prison()
	assert(controller._ui_dialogs.prison.dialog == original_dialog)
	controller.invalidate_ui_context()
	assert(not controller._ui_dialogs.has("prison"))
	var repair_key := _formal_feature(data, "palisade", Vector2i(43, 38))
	var repair_part := "c:%d" % data.index(Vector2i(43, 38))
	assert(Runtime.damage_structure_part(data, repair_key, repair_part, 40.0).ok)
	controller.release_worker()
	assert(not bool(data.site.worker_enabled))
	controller.feature_key = repair_key
	controller.update_ui()
	var repair_wood := int(data.site.inventory.wood)
	_press(lab, "RepairFeaturePart")
	assert(data.site.features[repair_key].has("repair") and bool(data.site.worker_enabled))
	assert(controller._work_elapsed == 1.0 and int(data.site.inventory.wood) < repair_wood)
	_choose(controller, "palisade", Vector2i(40, 20), Vector2i(3, 2))
	assert(not view.building_preview.is_empty())
	_press(lab, "CancelBuildingDraft")
	assert(controller.build_cells.is_empty() and view.building_preview.is_empty() and not controller.building_resize)
	_assert_gate_parts_stay_aligned(data, view)
	_choose(controller, "gate", Vector2i(45, 44), Vector2i.ONE)
	await _assert_building_options_visible(controller, [controller.building_material, controller.building_direction])
	controller._cancel_building_draft()
	print("SITE_BUILDING_UI_PASS formal buttons, rotation/cost, same-ID resize, livestock transfer, timed gate, scoped prison dialog, stopped worker repair, cancel draft")
	lab.free()
	quit()
