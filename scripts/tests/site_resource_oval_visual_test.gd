extends SceneTree

const Reference = preload("res://scripts/tests/fixtures/site_resource_view_phase25.gd")

class OvalCanvas extends Node2D:
	var candidate: SiteResourceView
	var reference: SiteResourceView
	var use_reference := false
	var point := Vector2.ZERO
	var radius := Vector2(32, 13)
	func _draw() -> void:
		var view := reference if use_reference else candidate
		view._oval(self, point, radius, Color(0.37, 0.64, 0.23, 0.3))
		view._oval(self, point + Vector2(1.37, -0.61), radius * 0.7, Color(0.81, 0.23, 0.51, 0.85))

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(DisplayServer.get_name() != "headless")
	var output := "res://output/site_army_scale_phase26_20260915/oval_pixels_%d" % int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var canvas := OvalCanvas.new()
	canvas.candidate = SiteResourceView.new()
	canvas.reference = Reference.new()
	var material := ShaderMaterial.new()
	material.shader = SiteResourceView.PROP_SHADER
	canvas.material = material
	root.add_child(canvas)
	var results := []
	var cases := [
		[Vector2.ZERO, Vector2(32, 13), 4.0],
		[Vector2(6400.37, 3200.61), Vector2(7, 3), 8.0],
		[Vector2(8192, 8192), Vector2(3, 3), 16.0],
		[Vector2(-8192, -8192), Vector2(256, 3), 1.0],
		[Vector2(-4617.021, 3106.801), Vector2(0.006523, 88.46561), 512.0],
		[Vector2(-16384, -16384), Vector2(32, 13), 4.0],
		[Vector2(9000.37, 9200.61), Vector2(22, 9), 4.0],
		[Vector2(3200.37, 1600.61), Vector2(-32, 13), 4.0],
		[Vector2(3200.37, 1600.61), Vector2(32, -13), 4.0],
		[Vector2(6400, 6400), Vector2(512, 128), 0.5],
	]
	for test: Array in cases:
		canvas.point = test[0]
		canvas.radius = test[1]
		canvas.scale = Vector2.ONE * float(test[2])
		canvas.position = root.get_visible_rect().size * 0.5 - canvas.point * float(test[2])
		var images: Array[Image] = []
		for reference: bool in [true, false]:
			canvas.use_reference = reference
			canvas.queue_redraw()
			for frame in range(2):
				await process_frame
				await RenderingServer.frame_post_draw
			images.append(root.get_texture().get_image())
		var same := images[0].get_data() == images[1].get_data()
		var has_ink := images[0].get_pixelv(images[0].get_size() / 2) != images[0].get_pixel(0, 0)
		var label := "oval_%02d" % results.size()
		results.append({"point": str(test[0]), "radius": str(test[1]), "zoom": test[2], "exact_rgba": same, "visible_reference_ink": has_ink})
		assert(images[0].save_png(output + "/" + label + "_reference.png") == OK)
		assert(images[1].save_png(output + "/" + label + "_candidate.png") == OK)
		var file := FileAccess.open(output + "/results.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(results, "\t"))
		file.close()
		if not same or not has_ink:
			push_error("Oval full RGBA/visible reference coverage failed: " + label)
			canvas.candidate.free()
			canvas.reference.free()
			canvas.queue_free()
			await process_frame
			quit(1)
			return
	canvas.candidate.free()
	canvas.reference.free()
	canvas.queue_free()
	await process_frame
	print("OVAL_VISUAL_PASS 10 exact full RGBA cases, includes thin/far/negative/oversized fallbacks, original shader and overlapping alpha output=", output)
	quit(0)
