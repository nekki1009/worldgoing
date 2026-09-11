extends SceneTree

func _init() -> void:
	call_deferred("_capture")

func _capture() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await process_frame
	await process_frame
	var image: Image = get_root().get_viewport().get_texture().get_image()
	image.save_png("res://.visual_captures/blank_viewport.png")
	quit(0)
