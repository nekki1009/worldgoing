extends "res://scripts/tests/site_building_ui_test.gd"
## Actual formal controls, Runtime operations and the original View runs.
const OUTPUT := "res://output/site_building_close_20261004/economy_ui_visual/"
var captures: Array[Dictionary] = []

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 120000
	_run.call_deferred()

func _select_recipe(controller: SiteController, recipe: String) -> void:
	for index: int in controller.building_recipe.item_count:
		if controller.building_recipe.get_item_metadata(index) == recipe:
			controller.building_recipe.select(index)
			return
	assert(false, "Actual formal recipe choice absent: " + recipe)

func _capture_window(lab: TerrainLab, label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	assert(DisplayServer.get_name() != "headless")
	assert(DirAccess.make_dir_recursive_absolute(OUTPUT) == OK)
	var controller := lab.site_controller
	controller.open_window("construction")
	var scroll := controller._formal_columns.construction.get_parent().get_parent() as ScrollContainer
	assert(scroll != null)
	for _frame: int in range(3): await process_frame
	scroll.ensure_control_visible(controller.building_actions.repair)
	for _frame: int in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = controller.formal_windows.construction.get_texture().get_image()
	assert(not image.is_empty() and image.save_png(OUTPUT + label + ".png") == OK)
	captures.append({"file": label + ".png", "case": "actual formal construction controls", "feature": controller.feature_key})

func _capture_scene(lab: TerrainLab, feature: Dictionary, label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	assert(DisplayServer.get_name() != "headless")
	assert(DirAccess.make_dir_recursive_absolute(OUTPUT) == OK)
	lab.site_controller.hide_tool_windows()
	lab.get_node("SiteUI").hide()
	var bounds: Rect2 = lab.site_controller.view.building_art_bounds(feature)
	if not bounds.has_area(): bounds = Rect2(Vector2(Runtime._cell_bounds(lab.terrain, feature.cells).position) * 64.0, Vector2(Runtime._cell_bounds(lab.terrain, feature.cells).size) * 64.0)
	lab.camera.position = bounds.get_center()
	lab.camera.zoom = Vector2.ONE * minf(2.0, minf(1100.0 / maxf(300.0, bounds.size.x + 200.0), 740.0 / maxf(240.0, bounds.size.y + 200.0)))
	lab.camera.reset_smoothing()
	for _frame: int in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	assert(not image.is_empty() and image.save_png(OUTPUT + label + ".png") == OK)
	captures.append({"file": label + ".png", "case": "original PNG, door or ground rubble with original Actor", "quarter": feature.quarter,
		"hp": feature.parts.body.hp, "grade": Runtime.building_grade(feature), "actor_cell": [lab.character.terrain_cell.x, lab.character.terrain_cell.y]})
	lab.get_node("SiteUI").show()

func _run() -> void:
	await _recipe_controls()
	await _grade_and_repair_controls()
	await _civil_art_and_ground()
	TerrainArmy.release_contact_source()
	if "--capture" in OS.get_cmdline_user_args():
		assert(captures.size() == 14, "Every agreed civil/UI preview must have an actual capture")
		var report := FileAccess.open(OUTPUT + "manifest.json", FileAccess.WRITE)
		assert(report != null)
		report.store_string(JSON.stringify({"status": "SITE_BUILDING_ECONOMY_UI_PASS", "captures": captures,
			"scope": "Actual formal recipe/grade/repair controls, old context refusal, original standing PNG/door rects in four directions, original ground rubble and Actor entering its former body, original south-well props. Manual PNG review and broader performance are separate."}, "\t", true, true))
		report.close()
	print("SITE_BUILDING_ECONOMY_UI_PASS: original formal recipe selector/apply and feature_recipe defaults; actual recipe/paid/active-zone/stale-context refusal; same-feature grade costs/current damage and original repair controls; four directional original PNG/door registration preserved under tint; destroyed body only original ground draws before actors, original Actor steps into former body; south-well chroma prop tint/rubble. Capture count=", captures.size(), "; no active Native transport, OS interaction or performance claim")
	quit(0)

func _recipe_controls() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller := lab.site_controller
	var key := _formal_feature(data, "kiln", Vector2i(16, 16))
	var other := _formal_feature(data, "kiln", Vector2i(24, 16))
	_formal_feature(data, "well", Vector2i(18, 12))
	controller.feature_key = key
	controller.update_ui()
	var feature: Dictionary = data.site.features[key]
	var before := JSON.stringify(data.site, "", true, true)
	_select_recipe(controller, "pottery")
	controller.update_ui()
	assert(controller.building_recipe.get_item_metadata(controller.building_recipe.selected) == "pottery", "Routine refresh discarded the user's uncommitted original recipe selection")
	assert(JSON.stringify(data.site, "", true, true) == before, "Selecting a displayed recipe must wait for the formal apply button")
	_press(lab, "ChangeFeatureRecipe")
	assert(feature.recipe_id == "pottery" and controller.details.text.contains("陶器"))
	assert(controller.building_selection.text.contains("配方：陶器") and controller.building_selection.text.contains("原營地"))
	var definition := Runtime.feature_recipe(feature)
	assert(controller.details.text.contains(Runtime.items_text(definition.input)) and controller.details.text.contains(Runtime.items_text(definition.output)))
	await _capture_window(lab, "01_recipe_pottery_formal")
	assert(Runtime.operate_feature(data, key).ok)
	before = JSON.stringify(data.site, "", true, true)
	controller.building_actions.recipe.pressed.emit() # Old enabled input still reaches the Runtime guard.
	assert(JSON.stringify(data.site, "", true, true) == before and controller.building_actions.recipe.disabled)
	Runtime._stop_feature_zones(data, key, "operate")
	controller.update_ui()
	var task := {"target": "feature:" + key, "action": "operate", "cell": feature.entrance, "mode": "work", "status": "", "progress": 0.0}
	var output := {}
	Runtime._feature_work(data, key, 1.0, Callable(), Callable(), task, output, 20, 1)
	assert(feature.batch_paid and float(feature.production) == 1.0)
	before = JSON.stringify(data.site, "", true, true)
	controller.building_actions.recipe.pressed.emit()
	assert(JSON.stringify(data.site, "", true, true) == before and controller.message.text.contains("批次"))
	Runtime._feature_work(data, key, float(definition.cycle) - 1.0, Callable(), Callable(), task, output, 20, 1)
	assert(output == definition.output and not feature.batch_paid)
	controller.update_ui()
	_select_recipe(controller, "")
	_press(lab, "ChangeFeatureRecipe")
	assert(not feature.has("recipe_id") and controller.details.text.contains(Runtime.items_text(Runtime.feature_recipe(feature).output)))
	_select_recipe(controller, "pottery")
	controller.feature_key = other
	before = JSON.stringify(data.site, "", true, true)
	controller.building_actions.recipe.pressed.emit()
	assert(JSON.stringify(data.site, "", true, true) == before and controller.message.text.contains("原設施或控制人物已變更"))
	controller.feature_key = key
	controller.update_ui()
	_select_recipe(controller, "pottery")
	data.site.features[key] = feature.duplicate(true)
	before = JSON.stringify(data.site, "", true, true)
	controller.building_actions.recipe.pressed.emit()
	assert(JSON.stringify(data.site, "", true, true) == before, "A replaced original feature dictionary must reject an old callback")
	await _capture_window(lab, "02_recipe_default_and_stale_guard")
	lab.free()
	await process_frame

func _grade_and_repair_controls() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller := lab.site_controller
	var key := _formal_feature(data, "house", Vector2i(24, 24), Vector2i.ONE, {"variant": "small"})
	var feature: Dictionary = data.site.features[key]
	assert(Runtime.damage_structure_part(data, key, "body", 40.0).ok)
	controller.feature_key = key
	controller.update_ui()
	assert(controller.building_parts.get_item_metadata(0) == "body" and controller.building_parts.get_item_text(0).contains("建物本體"))
	assert(controller.building_selection.text.contains("等級 1／3") and controller.building_selection.text.contains("60／100"))
	var terms := Runtime.request_upgrade(data, key, 1, Callable(), true)
	assert(terms.ok)
	var previous: Dictionary = data.site.inventory.duplicate(true)
	var cells: Array = feature.cells.duplicate()
	var entrance := int(feature.entrance)
	_press(lab, "UpgradeFeatureGrade")
	assert(int(feature.pending_build.target_grade) == 2 and feature.cells == cells and int(feature.entrance) == entrance)
	for item: String in terms.cost: assert(int(data.site.inventory[item]) == int(previous[item]) - int(terms.cost[item]))
	assert(controller.building_actions.upgrade.disabled and controller.building_actions.repair.disabled)
	_complete_key(data, key)
	controller.update_ui()
	assert(int(feature.building_grade) == 2 and float(feature.parts.body.hp) == 90.0)
	assert(controller.building_selection.text.contains("90／150") and not controller.building_actions.repair.disabled)
	await _capture_window(lab, "03_grade2_keeps_damage_and_footprint")
	_press(lab, "RepairFeaturePart")
	assert(feature.has("repair") and str(feature.repair.part) == "body")
	Runtime.assign_task(data, Runtime.ok("", {"target": "feature:" + key, "action": "repair", "cell": feature.repair.work_cell}))
	data.site.worker.cell = feature.repair.work_cell
	data.site.worker.mode = "work"
	Runtime._feature_work(data, key, float(feature.repair.work), Callable(), Callable(), data.site.worker, data.site.worker.cargo, 20, 1)
	assert(not feature.has("repair") and float(feature.parts.body.hp) == 150.0)
	controller.update_ui()
	assert(controller.building_actions.repair.disabled and controller.building_selection.text.contains("150／150"))
	await _capture_window(lab, "04_original_repair_finished")
	previous = data.site.inventory.duplicate(true)
	data.site.features[key].owner_faction = 2
	controller.update_ui()
	controller.building_actions.upgrade.pressed.emit()
	assert(data.site.inventory == previous and not feature.has("pending_build"))
	lab.free()
	await process_frame

func _civil_art_and_ground() -> void:
	for quarter: int in range(4):
		var data := _building_fixture()
		var lab := _building_lab(data)
		var view: SiteResourceView = lab.site_controller.view
		var key := _formal_feature(data, "house", Vector2i(24, 24), Vector2i.ONE, {"variant": "standard", "quarter": quarter})
		var feature: Dictionary = data.site.features[key]
		view.refresh()
		var original := view.building_part_draws(feature)
		assert(original.size() == 1 and original[0].part_id == "body" and original[0].color == Color.WHITE)
		var art := view._building_asset(view.building_art_key(feature))
		var base: Vector2i = Runtime.building_spec("house", Runtime._feature_options(feature)).base_size
		var door: Vector2 = original[0].rect.position + original[0].rect.size * Vector2(float(art.door_sill_anchor[0]), float(art.door_sill_anchor[1]))
		assert(door.is_equal_approx(view._building_local_point(feature, Vector2(float(base.x) * 0.5, float(base.y)))))
		assert(Runtime.damage_structure_part(data, key, "body", 50.0).ok)
		view.refresh()
		var damaged := view.building_part_draws(feature)
		assert(damaged.size() == 1 and damaged[0].rect == original[0].rect and damaged[0].file == original[0].file)
		assert(damaged[0].color != Color.WHITE and damaged[0].state == "damaged")
		var entrance: Vector2i = data.cell_from_index(int(feature.entrance))
		assert(lab.character.place(entrance, true))
		await _capture_scene(lab, feature, "house_q%d_damaged_registered_door" % quarter)
		assert(Runtime.damage_structure_part(data, key, "body", 50.0).ok)
		view.refresh()
		var rubble := view.building_part_draws(feature)
		assert(rubble.size() == feature.cells.size())
		for part: Dictionary in rubble:
			assert(part.row == -1 and not part.foreground and part.part_id == "body" and part.state == "destroyed")
			assert(part.file == original[0].file and part.rect.size.y <= 18.0)
			assert(not part.rect.has_point((Vector2(entrance) + Vector2.ONE * 0.5) * 64.0), "Ground rubble obscured the original outside entrance")
		var ground := view.get_node("BuildingGround")
		assert(ground.get("row") == -1 and not bool(ground.get("foreground")))
		var cached := 0
		for part: Dictionary in view.building_draws_by_row.get(-1, []):
			if str(part.get("feature_key", "")) == key: cached += 1
		assert(cached == rubble.size(), "The actual renderer retained an upright collapsed body")
		var stepped := false
		for index: int in feature.cells:
			var next := data.cell_from_index(index)
			if data.can_step(entrance, next):
				assert(lab.character.step(next - entrance))
				for _tick: int in range(60): lab.character.advance_combat(0.025, false, 0.0)
				assert(not lab.character.is_moving() and lab.character.terrain_cell == next)
				stepped = true
				break
		assert(stepped, "Original Actor could not enter the former body after collapse")
		await _capture_scene(lab, feature, "house_q%d_ground_rubble_actor_inside" % quarter)
		# South-well props keep the chroma owner instead of gaining a new bitmap.
		if quarter == 0:
			var well_key := _formal_feature(data, "well", Vector2i(34, 24))
			var well: Dictionary = data.site.features[well_key]
			assert(not view._building_uses_art(well))
			assert(Runtime.damage_structure_part(data, well_key, "body", 50.0).ok)
			assert(lab.character.place(data.cell_from_index(int(well.entrance)), true))
			view.refresh()
			await _capture_scene(lab, well, "south_well_damaged_original_chroma_prop")
			assert(Runtime.damage_structure_part(data, well_key, "body", 50.0).ok and not Runtime.feature_usable(well))
			view.refresh()
			assert(view.building_part_draws(well).is_empty(), "A collapsed south-well entered the upright art run")
			assert(data.site.water_links.get(well_key, []).is_empty())
			await _capture_scene(lab, well, "south_well_ground_rubble_original_chroma_prop")
		lab.free()
		await process_frame
