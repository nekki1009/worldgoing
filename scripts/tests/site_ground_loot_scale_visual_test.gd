extends "res://scripts/tests/site_ground_loot_scale_test.gd"

const FRAMES := 90

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 23000
	_run.call_deferred()

func _statistics(samples: Array[float]) -> Dictionary:
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for sample: float in samples:
		total += sample
	var mean := total / samples.size()
	return {"samples": samples.size(), "mean_frame_ms": mean, "p95_frame_ms": sorted[ceili(samples.size() * 0.95) - 1],
		"maximum_frame_ms": sorted.back(), "mean_interval_fps": 1000.0 / mean}

func _measure(view: SiteResourceView, camera: Camera2D, center: Vector2, moving: bool) -> Dictionary:
	for index in range(12):
		view.animate(1.0 / 60.0)
		await process_frame
		await RenderingServer.frame_post_draw
	var frames: Array[float] = []
	for index in range(FRAMES):
		var start := Time.get_ticks_usec()
		if moving:
			var angle := TAU * index / float(FRAMES)
			camera.position = center + Vector2(sin(angle) * 900.0, cos(angle) * 700.0)
			camera.force_update_scroll()
		view.animate(1.0 / 60.0)
		await process_frame
		await RenderingServer.frame_post_draw
		frames.append((Time.get_ticks_usec() - start) / 1000.0)
	return _statistics(frames)

func _capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	assert(picture.save_png(OUTPUT + name + ".png") == OK)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("GPU display required for original row-marker frame measurements")
		quit(1)
		return
	var count := _count_argument()
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT)) == OK)
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var memory_before := OS.get_static_memory_usage()
	var setup := _fixture(count)
	var data: TerrainData = setup.data
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var renderer := TerrainRenderer.new()
	scene.add_child(renderer)
	renderer.display(data)
	var view := SiteResourceView.new()
	scene.add_child(view)
	view.display(data)
	view.animate(0.0)
	assert(view.rows.size() == data.size.y)
	var marks := 0
	for cells: Array in view.loot_cells_by_row.values():
		marks += cells.size()
	assert(marks == data.ground_loot_at.size() and marks < count)
	var nodes := get_node_count()
	var camera := Camera2D.new()
	scene.add_child(camera)
	var center := Vector2(data.size) * TerrainRenderer.CELL_PIXELS * 0.5
	camera.position = center
	var viewport := root.get_visible_rect().size
	var scale := minf(viewport.x / (data.size.x * TerrainRenderer.CELL_PIXELS), viewport.y / (data.size.y * TerrainRenderer.CELL_PIXELS)) * 0.9
	camera.zoom = Vector2.ONE * scale
	camera.make_current()
	camera.force_update_scroll()
	var report := {"scope": "Original terrain plus SiteResourceView sparse container marks only; NOT 9000 soldiers, AI, combat or corpse rigs",
		"count": count, "unique_mark_cells": marks, "row_nodes": view.rows.size(), "total_tree_nodes": nodes + 1,
		"nodes_added_for_containers": setup.nodes_added_for_containers, "vsync_disabled": true,
		"viewport": [viewport.x, viewport.y], "camera_zoom": scale, "generation_ms": setup.generation_ms, "drop_creation_ms": setup.drop_creation_ms,
		"static_memory_before_bytes": memory_before, "static_memory_scene_bytes": OS.get_static_memory_usage(),
		"memory_note": "Godot allocator and renderer monitors, not whole-process RSS; unsupported monitor may report zero",
		"frame_note": "Wall-clock intervals through frame_post_draw, not isolated hardware GPU timing"}
	report.stationary = await _measure(view, camera, center, false)
	await _capture("%d_overview" % count)
	report.camera_moving = await _measure(view, camera, center, true)
	assert(get_node_count() == nodes + 1 and view.rows.size() == 128, "Container count/camera travel must not allocate per-container nodes")
	report.static_memory_scene_bytes = OS.get_static_memory_usage()
	report.renderer_video_memory_reported_bytes = int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	report.renderer_texture_memory_reported_bytes = int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
	# A separate close capture verifies the original same-cell badge visually;
	# it is deliberately excluded from the overview frame measurements.
	camera.position = (Vector2(setup.shared_cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	camera.zoom = Vector2.ONE * 1.2
	camera.force_update_scroll()
	await _capture("%d_same_cell_close" % count)
	assert(Time.get_ticks_msec() < deadline)
	_write_report("%d_gpu" % count, report)
	print("SITE GROUND LOOT SCALE VISUAL PASS: ", JSON.stringify(report, "", true, true))
	scene.queue_free()
	await process_frame
	quit(0)
