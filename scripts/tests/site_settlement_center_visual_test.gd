extends "res://scripts/tests/site_building_close_visual_test.gd"
## GPU capture of the formal settlement center art in the original PackedScene
## and row renderer: levels 1-3 x four directions, planned and destroyed body,
## plus the formal settlement page. Levels 2/3 are a presentation-only fixture
## write of site.settlement.level; the upgrade contract is in the headless test.

const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const OUT := "res://output/settlement_center_p0_20261007/visual"
const ANCHOR := Vector2i(16, 14)

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 170000
	_launch_visual.call_deferred()

func _center(quarter: int) -> Dictionary:
	var data := _building_fixture()
	visual_lab = _new_visual_scene(data)
	var options := {"layout_version": 1, "quarter": quarter, "owner_faction": 1}
	var placement := Runtime.building_cells(data, "settlement_center", ANCHOR, Vector2i(5, 5), options)
	assert(placement.ok, str(placement))
	var cells: Array[int] = []
	cells.assign(placement.cells)
	var view: SiteResourceView = visual_lab.site_controller.view
	assert(view.building_art_available({"kind": "settlement_center", "layout_version": 1, "quarter": quarter}))
	var founded := Settlement.found(visual_lab, int(visual_lab.character.person_id), cells, {"layout_version": 1, "quarter": quarter})
	assert(founded.ok, str(founded))
	return {"data": data, "key": str(founded.feature)}

func _run() -> void:
	assert(DisplayServer.get_name() != "headless", "Use canonical GPU visual verification")
	visual_output = OUT
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(visual_output)) == OK)
	root.size = Vector2i(1440, 960)
	root.content_scale_size = root.size
	var directions := ["south", "west", "north", "east"]
	for quarter: int in range(4):
		var built := _center(quarter)
		var data: TerrainData = built.data
		var key: String = built.key
		var feature: Dictionary = data.site.features[key]
		var view: SiteResourceView = visual_lab.site_controller.view
		if quarter == 0:
			assert(await _capture_scene("center_planned_south", feature, {"case": "paid planned center, translucent formal art", "art": view.building_art_key(feature)}))
		_complete_key(data, key)
		assert(int(data.site.settlement.level) == 1)
		assert(visual_lab.character.place(data.cell_from_index(int(feature.entrance)), true))
		for level: int in range(1, 4):
			data.site.settlement.level = level
			data.environment_revision += 1
			var art := view.building_art_key(feature)
			assert(art == "settlement_center_l%d_%s" % [level, directions[quarter]], art)
			var draws := view.building_part_draws(feature)
			assert(not draws.is_empty() and str(draws[0].asset_key) == art, str(draws))
			assert(await _capture_scene("center_l%d_%s" % [level, directions[quarter]], feature, {"level": level, "quarter": quarter, "art": art, "entrance": [data.cell_from_index(int(feature.entrance)).x, data.cell_from_index(int(feature.entrance)).y]}))
		if quarter == 0:
			data.site.settlement.level = 1
			assert(Runtime.damage_structure_part(data, key, "body", float(feature.parts.body.hp)).ok)
			assert(await _capture_scene("center_l1_south_destroyed", feature, {"case": "body 0: suspended, low rubble from the same formal art"}))
			visual_lab.site_controller._open_settlement()
			assert(visual_lab.site_controller._ui_dialogs.has("settlement"))
			var dialog: Window = visual_lab.site_controller._ui_dialogs.settlement.dialog
			assert(await _capture_window(dialog, "settlement_page_suspended", {"case": "formal settlement page, destroyed center suspension reason"}))
		visual_lab.free()
		await process_frame
	# Formal build-window path: choose the center, footprint preview, arrange construction.
	var ui_data := _building_fixture()
	visual_lab = _new_visual_scene(ui_data)
	var controller: SiteController = visual_lab.site_controller
	_choose(controller, "settlement_center", ANCHOR, Vector2i(5, 5))
	controller.update_ui()
	assert(controller.view.selection_valid and not controller.view.building_preview.is_empty(), "Formal art present: the build window previews the center")
	controller.build_selected()
	assert(ui_data.site.has("settlement") and int(ui_data.site.settlement.level) == 0, str(controller.message.text))
	assert(await _capture_scene("center_build_window_planned", ui_data.site.features[str(ui_data.site.settlement.center_id)], {"case": "construction window 安排施工 founds the settlement"}))
	visual_lab.free()
	await process_frame
	assert(visual_captures.size() == 16, "%d captures" % visual_captures.size())
	var report: FileAccess = FileAccess.open(visual_output.path_join("manifest.json"), FileAccess.WRITE)
	assert(report != null)
	report.store_string(JSON.stringify({"captures": visual_captures, "scope": "Original PackedScene + row renderer for settlement_center formal art; levels 2/3 set directly for presentation."}, "\t", true, true))
	report.close()
	TerrainArmy.release_contact_source()
	visual_finished = true
	print("SITE_SETTLEMENT_CENTER_VISUAL_PASS: ", visual_captures.size(), " captures; source=", visual_output)
	quit(0)
