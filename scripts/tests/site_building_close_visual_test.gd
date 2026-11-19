extends "res://scripts/tests/site_cross_boundary_wall_test.gd"
## Original PackedScene, original row renderer and actual formal windows.
## Transport, production and cold-time contracts are verified separately.
const Housing = preload("res://scripts/terrain_lab/site_housing.gd")
const Stocks = preload("res://scripts/terrain_lab/site_stockpiles.gd")
var visual_output: String = ""
var visual_captures: Array[Dictionary] = []
var visual_lab: TerrainLab
var visual_phases: int = 0
var visual_finished: bool = false

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 150000
	_launch_visual.call_deferred()

func _launch_visual() -> void:
	await _run()
	if not visual_finished:
		push_error("SITE_BUILDING_CLOSE_VISUAL_FAILED: incomplete phase or assertion; captures=%d phases=%d" % [visual_captures.size(), visual_phases])
		quit(1)

func _new_visual_scene(data: TerrainData) -> TerrainLab:
	var scene: PackedScene = load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	assert(scene != null)
	var lab: TerrainLab = scene.instantiate() as TerrainLab
	lab.restore_only = true
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	assert(lab.terrain == null)
	lab.bind_terrain(data)
	lab.restore_only = false
	lab.show()
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.site_controller._auto_save_blocked = true
	lab.site_controller.release_worker()
	lab.character.faction_id = 1
	lab.npc.faction_id = 1
	assert(lab.character.place(Vector2i(10, 10), true))
	assert(lab.npc.place(Vector2i(10, 9), true))
	lab.get_node("SiteUI").hide()
	lab.site_controller.hide_tool_windows()
	return lab

func _capture_scene(name: String, feature: Dictionary, metadata: Dictionary = {}) -> bool:
	var data: TerrainData = visual_lab.terrain
	var view: SiteResourceView = visual_lab.site_controller.view
	visual_lab.character._process(0.0)
	view.refresh()
	var bounds: Rect2 = view.building_art_bounds(feature)
	if not bounds.has_area():
		var cells: Rect2i = Runtime._cell_bounds(data, feature.cells)
		bounds = Rect2(Vector2(cells.position) * 64.0, Vector2(cells.size) * 64.0)
	bounds = bounds.merge(Rect2(visual_lab.character.position - Vector2(64, 120), Vector2(128, 180)))
	visual_lab.camera.position = bounds.get_center()
	visual_lab.camera.zoom = Vector2.ONE * minf(2.0, minf(1100.0 / maxf(300.0, bounds.size.x + 180.0), 740.0 / maxf(240.0, bounds.size.y + 180.0)))
	visual_lab.camera.reset_smoothing()
	for frame: int in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	assert(not picture.is_empty() and picture.save_png(visual_output.path_join(name + ".png")) == OK)
	var feature_id: String = ""
	for key: String in data.site.features:
		if is_same(data.site.features[key], feature): feature_id = key; break
	assert(not feature_id.is_empty())
	metadata.merge({"file": name + ".png", "kind": str(feature.kind), "feature_id": feature_id,
		"person_id": visual_lab.character.person_id, "cell": [visual_lab.character.terrain_cell.x, visual_lab.character.terrain_cell.y],
		"surface_y": data.surface_visual_offset_at(visual_lab.character.position).y})
	visual_captures.append(metadata)
	assert(Time.get_ticks_msec() < deadline)
	return true

func _capture_window(dialog: Window, name: String, metadata: Dictionary = {}) -> bool:
	assert(is_instance_valid(dialog) and dialog.visible)
	for frame: int in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image = dialog.get_texture().get_image()
	assert(not picture.is_empty() and picture.save_png(visual_output.path_join(name + ".png")) == OK)
	metadata.merge({"file": name + ".png", "window_title": dialog.title})
	visual_captures.append(metadata)
	assert(Time.get_ticks_msec() < deadline)
	return true

func _step_original(actor: TerrainTestCharacter, target: Vector2i) -> bool:
	assert(actor.data.can_step(actor.terrain_cell, target))
	assert(actor.step(target - actor.terrain_cell))
	for tick: int in range(100):
		actor.advance_combat(0.025, false, 0.0)
		if not actor.is_moving(): break
	assert(not actor.is_moving() and actor.terrain_cell == target)
	assert(actor.position.is_equal_approx((Vector2(target) + Vector2.ONE * 0.5) * 64.0))
	return true

func _bridges() -> void:
	for quarter: int in range(4):
		for material: String in ["wood", "stone"]:
			var data: TerrainData = _bridge_fixture(quarter, 4, 1)
			visual_lab = _new_visual_scene(data)
			var result: Dictionary = Runtime.request_build(data, "bridge", _bridge_cells(data, quarter, 4, material), Callable(), _bridge_options(quarter, material))
			assert(result.ok, str(result))
			var feature: Dictionary = data.site.features[str(result.feature)]
			var geometry: Dictionary = Runtime.feature_geometry(data, feature)
			assert(visual_lab.character.place(data.cell_from_index(int(geometry.entry)), true))
			assert(await _capture_scene("bridge_%s_q%d_planned" % [material, quarter], feature, {"case": "paid original construction preview"}))
			_bridge_finish(data, str(result.feature))
			assert(feature.stage == "complete")
			geometry = Runtime.feature_geometry(data, feature)
			var axis: Vector2i = Vector2i.DOWN if quarter % 2 == 0 else Vector2i.RIGHT
			var near: Vector2i = Vector2i(20, 19) if quarter % 2 == 0 else Vector2i(19, 20)
			assert(visual_lab.character.place(near, true))
			for depth: int in range(1, 4): assert(_step_original(visual_lab.character, near + axis * depth))
			assert(is_equal_approx(data.surface_visual_offset_at(visual_lab.character.position).y, -48.0))
			assert(await _capture_scene("bridge_%s_q%d_actor_deck" % [material, quarter], feature, {"case": "original actor really traversed to raised deck; clearance zero"}))
			for depth: int in range(4, 6): assert(_step_original(visual_lab.character, near + axis * depth))
			assert(await _capture_scene("bridge_%s_q%d_far_bank" % [material, quarter], feature, {"case": "original actor really completed each legal bridge edge"}))
			visual_lab.free()
			await process_frame
	visual_phases += 1

func _housing() -> void:
	for quarter: int in range(4):
		var data: TerrainData = _building_fixture()
		visual_lab = _new_visual_scene(data)
		var key: String = _formal_feature(data, "house", Vector2i(25, 25), Vector2i.ONE, {"variant": "standard", "quarter": quarter})
		var identity: int = visual_lab.character.person_id
		var controller: SiteController = visual_lab.site_controller
		assert(Housing.assign(visual_lab, identity, key, identity).ok)
		assert(controller.person_actions.begin_housing_return(identity, identity).ok)
		for tick: int in range(12000):
			var previous: Vector2i = visual_lab.character.terrain_cell
			visual_lab._advance_action_time(TerrainLab.ACTION_STEP)
			assert(previous == visual_lab.character.terrain_cell or data.can_step(previous, visual_lab.character.terrain_cell))
			if not controller.person_actions.is_busy(identity): break
		assert(Housing._attends(visual_lab, identity))
		controller.feature_key = key
		assert(await _capture_scene("house_q%d_real_home" % quarter, data.site.features[key], {"case": "registered original ID, actual return to exterior rest slot, original solid house"}))
		controller._open_housing()
		var dialog: Window = controller._ui_dialogs.housing.dialog
		assert(await _capture_window(dialog, "house_q%d_home_list" % quarter, {"case": "actual formal home list; original food and no HP or KO recovery"}))
		visual_lab.free()
		await process_frame
	visual_phases += 1

func _storage_windows() -> void:
	var data: TerrainData = _building_fixture()
	visual_lab = _new_visual_scene(data)
	for kind: String in ["warehouse", "kiln"]:
		var controller: SiteController = visual_lab.site_controller
		var key: String = _formal_feature(data, kind, Vector2i(24, 24))
		var feature: Dictionary = data.site.features[key]
		assert(Stocks.ensure_storage(data, key, 1).ok)
		if kind == "kiln": assert(Stocks.set_local_supply(data, key, true, 1).ok)
		assert(visual_lab.character.place(data.cell_from_index(int(feature.entrance)), true))
		controller.feature_key = key
		controller._open_feature_storage()
		var dialog: Window = controller._ui_dialogs.feature_stock.dialog
		assert(await _capture_window(dialog, kind + "_original_storage", {"case": "actual separate holder/capacity/location; local workshop supply is explicit"}))
		dialog.queue_free()
		await process_frame
		assert(await _capture_scene(kind + "_original_scene", feature, {"case": "original art owner, actual legal entrance, original Actor"}))
		# Keep each building and holder, so the second view uses an independent site.
		visual_lab.free()
		await process_frame
		if kind == "warehouse":
			data = _building_fixture()
			visual_lab = _new_visual_scene(data)
	visual_phases += 1

func _saved_file_hashes(folder: String) -> Dictionary:
	var directory: DirAccess = DirAccess.open(folder)
	assert(directory != null, folder)
	var hashes: Dictionary = {}
	for file: String in directory.get_files():
		var path: String = folder.path_join(file)
		hashes[path] = FileAccess.get_sha256(path)
	for child: String in directory.get_directories():
		hashes.merge(_saved_file_hashes(folder.path_join(child)))
	return hashes

func _summary_windows() -> void:
	var data: TerrainData = _flat_site(Vector2i.ZERO)
	var geography: PinnedGeography = PinnedGeography.new()
	geography.manifest_hash = "b".repeat(64)
	geography.manifest = {"atlas_id": RegionGrid.ATLAS_ID, "grid_contract_version": 1, "base_revision": "bridge_contract_v1",
		"summary": {"site_origin": [0, 0], "size": [1, 1]}}
	geography._summary = PackedByteArray([2])
	geography._content_scope = PackedByteArray([1])
	geography.bases[Vector2i.ZERO] = _bridge_base(data)
	var slot: RegionSaveSlot = RegionSaveSlot.new()
	slot.source = geography
	slot.folder = visual_output.path_join("summary-slot")
	slot.pin = {"format": 1, "world_instance_id": "building_visual", "slot_id": "summary",
		"atlas_id": RegionGrid.ATLAS_ID, "grid_contract_version": 1, "base_revision": "bridge_contract_v1",
		"manifest_sha256": geography.manifest_hash, "ramp_rule_revision": RegionTerrainAdapter.RAMP_RULE_REVISION}
	assert(slot._recover_control().ok)
	visual_lab = _new_visual_scene(data)
	_formal_feature(data, "warehouse", Vector2i(24, 24))
	var captured: Dictionary = visual_lab.site_controller._capture_for_save()
	assert(captured.ok, "Original capture failed: " + str(captured))
	var attached: Dictionary = slot.attach_active_site(data)
	assert(attached.ok, "Original slot attach failed: " + str(attached))
	var saved_site: Dictionary = slot.save_site(data)
	assert(saved_site.ok, "Original slot save/readback failed: " + str(saved_site))
	# Saving validates the original fixed source through make_terrain_data.
	# Begin pure-read checks after that preparation, before any summary read.
	var original_created: TerrainData = geography.last_created
	var saved: Dictionary = slot.building_summary(Vector2i.ZERO)
	assert(saved.ok and saved.visited and saved.counts.warehouse.complete == 1, str(saved))
	var known: Dictionary = slot.known_saved_sites()
	assert(known.ok and known.sites == [Vector2i.ZERO], str(known))
	assert(is_same(geography.last_created, original_created), "Summary created another Site after original save/readback")
	var original_site: String = JSON.stringify(data.site, "", true, true)
	var original_slot: String = JSON.stringify([slot._marker, slot.control], "", true, true)
	var original_files: Dictionary = _saved_file_hashes(slot.folder)
	assert(not original_files.is_empty())
	visual_lab.site_controller.region_slot = slot
	visual_lab.site_controller._open_region_building_summary()
	var dialog: Window = visual_lab.site_controller._ui_dialogs.region_buildings.dialog
	var label: Label = dialog.find_child("BuildingSummaryResult", true, false) as Label
	assert(label != null)
	var expected_counts: String = visual_lab.site_controller._building_summary_counts(saved.counts)
	for scope: String in ["Site", "Region", "World"]:
		_press(visual_lab, "Read%sBuildingSummary" % scope)
		for frame: int in range(20): await process_frame
		assert(label.text.contains(expected_counts), label.text)
		if scope == "Site":
			assert(label.text.begins_with(str(saved.site_id)) and label.text.contains("已造訪／已保存"), label.text)
		else:
			assert(label.text.begins_with("%s · 已保存地點 1" % ["本區域" if scope == "Region" else "本世界"]), label.text)
		assert(await _capture_window(dialog, "saved_%s_summary" % scope.to_lower(), {
			"case": "actual original saved-marker summary; pure read does not create another Site",
			"counts": saved.counts, "source_checksum": saved.source_checksum, "generation": known.generation}))
		assert(JSON.stringify(data.site, "", true, true) == original_site)
		assert(JSON.stringify([slot._marker, slot.control], "", true, true) == original_slot)
		assert(_saved_file_hashes(slot.folder) == original_files)
		assert(is_same(geography.last_created, original_created), "Summary created another Site after original save/readback")
	visual_lab.free()
	await process_frame
	visual_phases += 1

func _run() -> void:
	assert(DisplayServer.get_name() != "headless", "Use canonical GPU visual verification")
	visual_output = "res://output/site_building_close_20261004/close_visual/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(visual_output)) == OK)
	root.size = Vector2i(1440, 960)
	root.content_scale_size = root.size
	await _bridges()
	await _housing()
	await _storage_windows()
	await _summary_windows()
	assert(visual_captures.size() == 39 and visual_phases == 4, "%d captures, %d phases" % [visual_captures.size(), visual_phases])
	var report: FileAccess = FileAccess.open(visual_output.path_join("manifest.json"), FileAccess.WRITE)
	assert(report != null)
	report.store_string(JSON.stringify({"captures": visual_captures, "scope": "Original PackedScene bridge traversal, exterior home return, original formal home/storage/Site/Region/World summary windows; no performance, Native housing or production claim."}, "\t", true, true))
	report.close()
	TerrainArmy.release_contact_source()
	visual_finished = true
	print("SITE_BUILDING_CLOSE_VISUAL_PASS: ", visual_captures.size(), " captures; source=", visual_output)
	quit(0)
