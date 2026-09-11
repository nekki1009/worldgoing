extends SceneTree

const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const OUTPUT := "res://.visual_captures/site_resources/"
var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 25000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("SITE VISUAL did not complete")
		quit(1)
	return false

func _capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	assert(picture.save_png(OUTPUT + label + ".png") == OK)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("GPU display required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false # Capture automation does not simulate application focus.
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.npc.set_process(false)
	var controller: Node = lab.site_controller
	if "--props" in OS.get_cmdline_user_args():
		await _prop_views(lab)
		lab.queue_free()
		await process_frame
		quit(0)
		return
	if "--water" in OS.get_cmdline_user_args():
		await _water_views(lab)
		lab.queue_free()
		await process_frame
		quit(0)
		return
	controller.focus_camp()
	await _capture("01_camp")
	controller.view.view_mode = 1
	lab.find_child("LandView", true, false).select(1)
	controller.update_ui()
	controller.view.refresh()
	lab.camera.zoom = Vector2.ONE * 0.5
	await _capture("02_resources")
	for mode: int in range(2, 6):
		controller.view.view_mode = mode
		lab.find_child("LandView", true, false).select(mode)
		controller.update_ui()
		controller.view.refresh()
		await _capture("0%d_%s" % [mode + 1, ["farm", "pasture", "water", "building"][mode - 2]])
	controller.view.view_mode = 0
	lab.find_child("LandView", true, false).select(0)
	var counts := {}
	for key: String in lab.terrain.resource_base:
		var kind := int(lab.terrain.resource_base[key].kind)
		if kind not in [Env.Kind.WILDLIFE, Env.Kind.FISH] or counts.has(kind):
			continue
		counts[kind] = true
		controller.select_cell(lab.terrain.cell_from_index(int(lab.terrain.resource_base[key].cell)))
		lab.camera.zoom = Vector2.ONE * 1.5
		lab.camera.position = (Vector2(controller.selected) + Vector2.ONE * 0.5) * 64 + Vector2(controller.PANEL_SPACE * 0.5 / 1.5, 0)
		lab.camera.force_update_scroll()
		controller.view.animate(1.0)
		await _capture("animal_%d_a" % kind)
		controller.view.animate(2.0)
		await _capture("animal_%d_b" % kind)
	# Complete real commands on a suitable generated plot for feature art.
	var placed := 0
	var plots: Array[int] = []
	for i: int in range(lab.terrain.surface_types.size()):
		plots.append(i)
	plots.sort_custom(func(a: int, b: int) -> bool: return lab.terrain.cell_from_index(a).distance_squared_to(lab.terrain.spawn_cell) < lab.terrain.cell_from_index(b).distance_squared_to(lab.terrain.spawn_cell))
	for i: int in plots:
		if placed >= 3:
			break
		var kind: String = ["house", "well", "farm"][placed]
		var plot: Array[int] = [i]
		var preview := Runtime.preview_build(lab.terrain, kind, plot, controller.reserves_cell)
		if not preview.ok or not preview.clearing.is_empty():
			continue
		var result := Runtime.request_build(lab.terrain, kind, plot, controller.reserves_cell)
		assert(result.ok)
		var feature: Dictionary = lab.terrain.site.features[str(result.feature)]
		Runtime.assign_task(lab.terrain, {"ok": true, "target": "feature:" + str(result.feature), "action": "construct", "cell": feature.entrance, "message": ""})
		lab.terrain.site.worker.cell = feature.entrance
		lab.terrain.site.worker.mode = "work"
		Runtime.advance(lab.terrain, float(feature.work), true)
		assert(str(feature.stage) == "complete")
		controller.view.refresh()
		controller.select_cell(lab.terrain.cell_from_index(i))
		lab.camera.zoom = Vector2.ONE * 2
		lab.camera.position = (Vector2(controller.selected) + Vector2.ONE * 0.5) * 64 + Vector2(controller.PANEL_SPACE * 0.5 / 2.0, 0)
		lab.camera.force_update_scroll()
		await _capture("feature_" + kind)
		placed += 1
	assert(placed == 3)
	controller.modes.select(5)
	controller.buildings.select(0)
	for i: int in plots:
		var preview_cells: Array[int] = [i]
		if not Runtime.preview_build(lab.terrain, "house", preview_cells, controller.reserves_cell).ok:
			continue
		controller.build_cells = preview_cells
		controller.view.selection = Rect2i(lab.terrain.cell_from_index(i), Vector2i.ONE)
		controller.update_ui()
		assert(controller.view.selection_valid and controller.view.preview_entrance.x >= 0)
		await _capture("preview_valid")
		break
	controller.build_cells = [int(lab.terrain.site.depot_cell)] as Array[int]
	controller.view.selection = Rect2i(lab.terrain.spawn_cell, Vector2i.ONE)
	controller.update_ui()
	assert(not controller.view.selection_valid)
	await _capture("preview_rejected")
	var frame_ms: Array[float] = []
	for n: int in range(20):
		var start := Time.get_ticks_usec()
		await process_frame
		frame_ms.append(float(Time.get_ticks_usec() - start) / 1000.0)
	frame_ms.sort()
	var report := {"surface": "1600x1000 GPU preview, stationary scene after captures, 20 frames; not a battle benchmark", "resource_rows": controller.view.rows.size(), "generated_sources": lab.terrain.resource_base.size(), "frame_ms_median": frame_ms[10], "frame_ms_max": frame_ms.back(), "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT)}
	var report_file := FileAccess.open(OUTPUT + "preview_metrics.json", FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report, "\t"))
	report_file.close()
	print("SITE GPU CAPTURES PASS: camp, resources, four land views, fauna motion, house/well/farm; inspect PNGs")
	lab.queue_free()
	await process_frame
	quit(0)

func _water_views(lab: TerrainLab) -> void:
	var controller: Node = lab.site_controller
	var captured := {}
	for preset: int in [TerrainPreset.Kind.COASTAL_CLIFF, TerrainPreset.Kind.ISLAND]:
		var data := TerrainGenerator.generate(preset, 71)
		Env.initialize(data)
		lab.bind_terrain(data)
		for key: String in data.resource_base:
			var kind := int(data.resource_base[key].kind)
			if kind not in [Env.Kind.FISH, Env.Kind.SALT] or captured.has(kind):
				continue
			captured[kind] = true
			controller.select_cell(data.cell_from_index(int(data.resource_base[key].cell)))
			lab.camera.zoom = Vector2.ONE * 1.5
			lab.camera.position = (Vector2(controller.selected) + Vector2.ONE * 0.5) * 64 + Vector2(controller.PANEL_SPACE * 0.5 / 1.5, 0)
			lab.camera.force_update_scroll()
			controller.view.animate(1.0)
			await _capture("water_resource_%d_a" % kind)
			controller.view.animate(2.0)
			await _capture("water_resource_%d_b" % kind)
		if captured.size() == 2:
			break
	assert(captured.size() == 2, "Coastal visual fixtures lack fish or salt")
	var fresh := TerrainGenerator.generate(TerrainPreset.Kind.RIVER_VALLEY, 71)
	Env.initialize(fresh)
	lab.bind_terrain(fresh)
	var intake := ""
	for i: int in range(fresh.surface_types.size()):
		var footprint: Array[int] = [i]
		var preview := Runtime.preview_build(fresh, "intake", footprint, controller.reserves_cell)
		if not preview.ok or not preview.clearing.is_empty():
			continue
		var result := Runtime.request_build(fresh, "intake", footprint, controller.reserves_cell)
		assert(result.ok)
		intake = str(result.feature)
		var feature: Dictionary = fresh.site.features[intake]
		Runtime.assign_task(fresh, {"ok": true, "target": "feature:" + intake, "action": "construct", "cell": feature.entrance, "message": ""})
		fresh.site.worker.cell = feature.entrance
		fresh.site.worker.mode = "work"
		Runtime.advance(fresh, float(feature.work), true)
		assert(str(feature.stage) == "complete" and not fresh.site.water_links[intake].is_empty())
		controller.view.view_mode = 4
		lab.find_child("LandView", true, false).select(4)
		controller.select_cell(fresh.cell_from_index(i))
		controller.view.refresh()
		lab.camera.zoom = Vector2.ONE
		lab.camera.position = (Vector2(controller.selected) + Vector2.ONE * 0.5) * 64 + Vector2(controller.PANEL_SPACE * 0.5, 200)
		lab.camera.force_update_scroll()
		await _capture("water_intake_service")
		break
	assert(not intake.is_empty(), "No usable freshwater bank intake")
	print("SITE WATER GPU PASS: naturally generated sea salt, fish motion, legal river intake and service range; inspect PNGs")

func _prop_views(lab: TerrainLab) -> void:
	var controller: Node = lab.site_controller
	var data: TerrainData = lab.terrain
	var candidates: Array[int] = []
	for i: int in range(data.surface_types.size()):
		candidates.append(i)
	candidates.sort_custom(func(a: int, b: int) -> bool: return data.cell_from_index(a).distance_squared_to(data.spawn_cell) < data.cell_from_index(b).distance_squared_to(data.spawn_cell))
	var built: Dictionary = {}
	for kind: String in ["house", "well", "farm"]:
		# Keep the sample well outside the roof silhouette so all four props can be inspected.
		var preferred := data.spawn_cell
		if kind == "well":
			preferred += Vector2i(-1, 2)
		elif kind == "farm":
			preferred += Vector2i(-3, 0)
		candidates.sort_custom(func(a: int, b: int) -> bool: return data.cell_from_index(a).distance_squared_to(preferred) < data.cell_from_index(b).distance_squared_to(preferred))
		var footprint_size := Vector2i(3, 3) if kind == "house" else (Vector2i(2, 2) if kind == "farm" else Vector2i.ONE)
		for i: int in candidates:
			var origin := data.cell_from_index(i)
			if kind == "well":
				var house_cell := data.cell_from_index(int(built.house.cells[0]))
				if Rect2i(house_cell - Vector2i(1, 2), Vector2i(5, 5)).has_point(origin):
					continue
			if not data.contains(origin + footprint_size - Vector2i.ONE):
				continue
			var footprint: Array[int] = []
			for y: int in range(footprint_size.y):
				for x: int in range(footprint_size.x):
					footprint.append(data.index(origin + Vector2i(x, y)))
			var preview := Runtime.preview_build(data, kind, footprint, controller.reserves_cell)
			if not preview.ok or not preview.clearing.is_empty():
				continue
			var result := Runtime.request_build(data, kind, footprint, controller.reserves_cell)
			assert(result.ok)
			var feature: Dictionary = data.site.features[str(result.feature)]
			Runtime.assign_task(data, {"ok": true, "target": "feature:" + str(result.feature), "action": "construct", "cell": feature.entrance, "message": ""})
			data.site.worker.cell = feature.entrance
			data.site.worker.mode = "work"
			Runtime.advance(data, float(feature.work), true)
			assert(str(feature.stage) == "complete")
			built[kind] = feature
			break
		assert(built.has(kind), "No valid prop plot for " + kind)
	controller.view.refresh()
	controller.select_cell(data.cell_from_index(int(built.house.cells[0])))
	var minimum := data.spawn_cell
	var maximum := minimum
	for feature: Dictionary in built.values():
		for i: int in feature.cells:
			minimum = minimum.min(data.cell_from_index(i))
			maximum = maximum.max(data.cell_from_index(i))
	var center := Vector2(minimum + maximum + Vector2i.ONE) * 32.0
	lab.camera.zoom = Vector2.ONE * 1.8
	lab.camera.position = center + Vector2(controller.PANEL_SPACE * 0.5 / 1.8, -40)
	lab.camera.force_update_scroll()
	var house_origin := data.cell_from_index(int(built.house.cells[0]))
	var house_front := house_origin + Vector2i(1, 3)
	assert(lab.character.place(house_front, true))
	await _capture("props_overview")
	# Only new environment art changes: both actors still use their canonical 3D viewports.
	for actor: TerrainTestCharacter in [lab.character, lab.npc]:
		assert(actor.editor != null and actor.player_sprite.texture == actor.editor.preview_viewport.get_texture())
	assert(lab.renderer.get_child_count() == 4 and controller.view.rows.size() == data.size.y)
	assert(not lab.character.place(house_origin, true), "House artwork changed its collision footprint")
	# Exercise the near and far sides of the existing row-sorting contract.
	for side: int in [-1, 3]:
		var target := house_origin + Vector2i(1, side)
		if not lab.character.can_enter_cell(target):
			continue
		assert(lab.character.place(target, true))
		await _capture("props_house_" + ("back" if side < 0 else "front"))
	var farm_cell := data.cell_from_index(int(built.farm.cells[0]))
	assert(lab.character.place(farm_cell, true), "Crop artwork blocked walkable soil")
	await _capture("props_farmland")
	assert(lab.character.toggle_mount())
	await _capture("props_original_rider")
	assert(not lab.character.toggle_mount())
	var well_cell := data.cell_from_index(int(built.well.cells[0]))
	controller.select_cell(well_cell)
	lab.camera.zoom = Vector2.ONE * 3
	lab.camera.position = (Vector2(well_cell) + Vector2.ONE * 0.5) * 64 + Vector2(controller.PANEL_SPACE / 6, -32)
	lab.camera.force_update_scroll()
	await _capture("props_well_detail")
	lab.camera.zoom = Vector2.ONE * 0.75
	lab.camera.position = center + Vector2(controller.PANEL_SPACE * 0.5 / 0.75, 0)
	lab.camera.force_update_scroll()
	await _capture("props_zoom_out")
	var screenshot := root.get_texture().get_image()
	var magenta_pixels := 0
	for y: int in range(0, screenshot.get_height(), 2):
		for x: int in range(0, screenshot.get_width(), 2):
			var pixel := screenshot.get_pixel(x, y)
			if pixel.r > 0.8 and pixel.b > 0.8 and pixel.g < 0.15:
				magenta_pixels += 1
	assert(magenta_pixels == 0, "Chroma backdrop leaked into actual gameplay")
	print("SITE PROP GPU PASS: original viewport humans and rider, legal construction and crop access, four terrain layers, 100 resource rows, no magenta background; inspect front/back/crop PNGs")
