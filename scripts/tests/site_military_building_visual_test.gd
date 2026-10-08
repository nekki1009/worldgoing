extends "res://scripts/tests/site_building_ui_test.gd"
## GPU-only original View/Actor capture; logistics jobs have a separate contract.
const MILITARY_OUTPUT := "res://output/site_military_buildings_20261003/visual/"
var military_lab: TerrainLab
var military_captures: Array[Dictionary] = []
var module_sizes := {}

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 90000
	_run.call_deferred()

func _flat_military() -> TerrainData:
	var data := _building_fixture()
	data.resource_base.clear()
	data.site.changes.clear()
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.ramp_edges.fill(0)
	data.surface_types.fill(TerrainData.Surface.GRASS)
	data.water_kind.fill(0)
	data.water_body.fill(-1)
	data.foundation.fill(80)
	Env.rebuild_indexes(data)
	Runtime.rebuild_terrain_edges(data)
	return data

func _reset_military() -> TerrainData:
	var data := _flat_military()
	military_lab.bind_terrain(data)
	military_lab.site_controller._auto_save_blocked = true
	military_lab.site_controller.release_worker()
	assert(military_lab.character.place(Vector2i(10, 10), true))
	assert(military_lab.npc.place(Vector2i(10, 9), true))
	military_lab.get_node("SiteUI").hide()
	military_lab.site_controller.hide_tool_windows()
	return data

func _military_capture(label: String, bounds: Rect2, details: Dictionary) -> void:
	var actor := military_lab.character
	actor._process(0.0)
	military_lab.site_controller.view.refresh()
	military_lab.camera.position = bounds.get_center()
	military_lab.camera.zoom = Vector2.ONE * minf(2.0, minf(1100.0 / maxf(320.0, bounds.size.x + 180.0), 740.0 / maxf(260.0, bounds.size.y + 180.0)))
	military_lab.camera.reset_smoothing()
	for _frame: int in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	assert(not picture.is_empty() and picture.save_png(MILITARY_OUTPUT + label + ".png") == OK)
	details.merge({"file": label + ".png", "person_id": actor.person_id, "cell": [actor.terrain_cell.x, actor.terrain_cell.y],
		"ground_position": [actor.position.x, actor.position.y]}, true)
	military_captures.append(details)
	assert(Time.get_ticks_msec() < deadline)

func _military_walk(destination: Vector2i) -> void:
	var actor := military_lab.character
	var route := actor.data.path_between(actor.terrain_cell, destination)
	assert(not route.is_empty() or actor.terrain_cell == destination)
	for cell: Vector2i in route:
		assert(actor.data.can_step(actor.terrain_cell, cell))
		assert(actor.step(cell - actor.terrain_cell), "Original Actor step must follow the shared physical geometry")
		for _tick: int in range(100):
			actor.advance_combat(0.025, false, 0.0)
			if not actor.is_moving(): break
		assert(not actor.is_moving() and actor.terrain_cell == cell)
	actor._process(0.0)

func _military_facility(kind: String, side: int, quarter: int) -> void:
	var data := _reset_military()
	var view: SiteResourceView = military_lab.site_controller.view
	var key := _formal_feature(data, kind, Vector2i(20, 20), Vector2i(side, side), {"quarter": quarter})
	var feature: Dictionary = data.site.features[key]
	var geometry := Runtime.feature_geometry(data, feature)
	var modules := Runtime.military_modules(data, feature)
	var standing := Runtime.military_walkable_cells(data, feature)
	var blocked := {}
	for module: Dictionary in modules:
		for index: int in module.cells:
			blocked[index] = true
			assert(geometry.blocked.has(index) and data.static_blocked[index] == 1)
	assert(blocked.size() == geometry.blocked.size() and standing.size() + blocked.size() == side * side)
	assert(Runtime.military_capacity(data, feature) == standing.size())
	for index: int in standing: assert(not blocked.has(index) and data.is_walkable(data.cell_from_index(index)))
	var draws := view.building_part_draws(feature)
	assert(draws.size() == side * side + modules.size(), "One approved ground tile per cell and one fixed sprite per physical module")
	for part: Dictionary in draws:
		if str(part.asset_key) == "road": continue
		var asset_key := str(part.asset_key)
		if module_sizes.has(asset_key): assert(Vector2(module_sizes[asset_key]).is_equal_approx(part.rect.size), "Growing the compound must never stretch its house or rack sprites")
		else: module_sizes[asset_key] = part.rect.size
	var actor := military_lab.character
	assert(actor.place(data.cell_from_index(int(feature.entrance)), true))
	var centre := Vector2i(20 + floori(side * 0.5), 20 + floori(side * 0.5))
	assert(standing.has(data.index(centre)))
	_military_walk(centre)
	var bounds := view.building_art_bounds(feature).merge(Rect2(Vector2(20, 20) * 64.0, Vector2(side, side) * 64.0))
	var details := {"kind": kind, "quarter": quarter, "side": side, "capacity": standing.size(), "blocked": blocked.size(),
		"modules": modules.size(), "case": "Original character walked through shared module geometry into the courtyard; sprites retain fixed physical size"}
	await _military_capture("%s_%d_q%d" % [kind, side, quarter], bounds, details)
	if side == 10 and quarter == 0:
		await _military_capture(kind + "_module_detail", Rect2((Vector2(20, 20) + Vector2(4, 3)) * 64.0 - Vector2(240, 210), Vector2(480, 420)), details.duplicate())

func _military_tent(quarter: int) -> void:
	var data := _reset_military()
	var controller: SiteController = military_lab.site_controller
	var view: SiteResourceView = controller.view
	var actor := military_lab.character
	var exterior: Array[Vector2i] = [Vector2i(21, 23), Vector2i(19, 21), Vector2i(21, 19), Vector2i(23, 21)]
	assert(actor.place(exterior[quarter], true))
	var layout := Runtime.building_cells(data, "tent", Vector2i(20, 20), Vector2i(3, 3), {"quarter": quarter})
	assert(layout.ok)
	var cells: Array[int] = []
	cells.assign(layout.cells)
	# Explicit paid-inventory fixture; production crafting/deploy job tested separately.
	data.site.manual.cargo.camp_tent = 1
	var built := Runtime.deploy_tent(data, cells, data.site.manual.cargo, actor.item_state, int(actor.item_state.version), actor.terrain_cell, 1, controller.reserves_cell, quarter)
	assert(built.ok, str(built))
	var feature: Dictionary = data.site.features[str(built.feature)]
	var draws := view.building_part_draws(feature)
	assert(draws.size() == 1 and str(draws[0].asset_key) == "tent" + ["", "_west", "_north", "_east"][quarter])
	var art := view._building_asset(str(draws[0].asset_key))
	var anchor := Vector2(float(art.door_sill_anchor[0]), float(art.door_sill_anchor[1]))
	var door: Vector2 = draws[0].rect.position + draws[0].rect.size * anchor
	assert(door.is_equal_approx(view._building_local_point(feature, Vector2(1.5, 3.0))), "Tent doorway must use original footprint rotation, not sprite rotation")
	var bounds := view.building_art_bounds(feature).merge(Rect2(Vector2(19, 19) * 64.0, Vector2(5, 5) * 64.0))
	await _military_capture("tent_q%d_outside" % quarter, bounds, {"case": "Original person at real directional entrance", "quarter": quarter, "door": [door.x, door.y]})
	_military_walk(Vector2i(21, 21))
	assert(cells.has(data.index(actor.terrain_cell)))
	assert(not Runtime.preview_pack_tent(data, str(built.feature), data.site.manual.cargo, actor.item_state, exterior[quarter], 1, controller.reserves_cell).ok,
		"A real person inside the tent prevents packing")
	await _military_capture("tent_q%d_inside" % quarter, bounds, {"case": "Original person physically walked inside; cloth uses original row occlusion", "quarter": quarter})

func _run() -> void:
	assert(DisplayServer.get_name() != "headless", "This fixture requires the original GPU renderer")
	assert(DirAccess.make_dir_recursive_absolute(MILITARY_OUTPUT) == OK)
	military_lab = _building_lab(_flat_military())
	military_lab.get_node("SiteUI").hide()
	for kind: String in ["barracks", "training_ground"]:
		for side: int in [10, 50]:
			for quarter: int in range(4): await _military_facility(kind, side, quarter)
	for quarter: int in range(4): await _military_tent(quarter)
	assert(military_captures.size() == 26)
	var report := FileAccess.open(MILITARY_OUTPUT + "captures.json", FileAccess.WRITE)
	assert(report != null)
	report.store_string(JSON.stringify({"status": "SITE_MILITARY_BUILDING_VISUAL_PASS", "captures": military_captures,
		"scope": "26 GPU viewport captures: fixed house/rack modules, shared blocked/standing geometry, 10/50-cell military plots in four orientations, original Actor routes and four tent doorway/inside registrations. Manual image review remains separate."}, "\t"))
	report.close()
	military_lab.free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE_MILITARY_BUILDING_VISUAL_PASS: 26 captures; shared physical module footprints, unchanged sprite size, real courtyard/tent walks and original row occlusion")
	quit(0)
