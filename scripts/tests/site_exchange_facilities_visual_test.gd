extends "res://scripts/tests/site_workflow_test.gd"
## Reuse the original paid construction fixture and its 15-second deadline.
const CAPTURE := "res://output/site_exchange_20260914/facilities.png"

func _run() -> void:
	assert(DisplayServer.get_name() != "headless", "Facilities capture requires a GPU window")
	root.size = Vector2i(1400, 900)
	root.content_scale_size = root.size
	var data := _fixture()
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	for row in range(2):
		var kind: String = ["palisade", "fighting_position"][row]
		var cell := Vector2i(22, 20 + row * 4)
		var key := _build(data, kind, cell)
		assert(str(data.site.features[key].stage) == "complete")
		var planned := Runtime.request_build(data, kind, [data.index(cell + Vector2i(4, 0))])
		assert(planned.ok and str(data.site.features[str(planned.feature)].stage) == "planned")
	assert(data.site.features.size() == 4)
	var renderer := TerrainRenderer.new()
	scene.add_child(renderer)
	renderer.display(data)
	var view := SiteResourceView.new()
	scene.add_child(view)
	view.display(data)
	assert(renderer.layers.size() == 4 and view.rows.size() == data.size.y)
	assert(view.get_child_count() == data.size.y, "Features stay in row batches, not per-cell scene nodes")
	var camera := Camera2D.new()
	scene.add_child(camera)
	camera.position = Vector2(24.5, 22.5) * TerrainRenderer.CELL_PIXELS
	camera.zoom = Vector2.ONE * 2.0
	camera.force_update_scroll()
	var overlay := CanvasLayer.new()
	scene.add_child(overlay)
	var caption := Label.new()
	overlay.add_child(caption)
	caption.position = Vector2(30, 24)
	caption.add_theme_font_size_override("font_size", 26)
	caption.text = "左：已完工　　右：已付款、尚未施工\n木柵阻擋通行／攻擊；防禦陣地可站立，交鋒能力 +10"
	await process_frame
	await RenderingServer.frame_post_draw
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE.get_base_dir())) == OK)
	assert(root.get_texture().get_image().save_png(CAPTURE) == OK)
	print("SITE EXCHANGE FACILITIES VISUAL CAPTURE: ", CAPTURE)
	scene.queue_free()
	await process_frame
	quit(0)
