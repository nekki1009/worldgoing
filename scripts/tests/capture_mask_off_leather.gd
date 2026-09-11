extends SceneTree

const EDITOR_SCENE: String = "res://scenes/ui/HumanCharacter3DEditor.tscn"
const ARTIFACT_DIR: String = "C:/Users/Nekki/.gemini/antigravity/brain/6751ce0d-7d56-4cae-8c5b-9f20717bdb83"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	OS.low_processor_usage_mode = false
	Engine.max_fps = 0

	var scene := load(EDITOR_SCENE) as PackedScene
	var editor := scene.instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	await _settle(15)

	var set_portrait_cam = func(is_female: bool):
		var head_y := 1.48 if is_female else 1.58
		editor.camera.size = 0.96
		editor.camera.position = Vector3(0.0, head_y, -2.40)
		editor.camera.look_at_from_position(editor.camera.position, Vector3(0.0, head_y - 0.02, 0.0), Vector3.UP)

	# Test Female Hair 01, 02, 03, 04 with Mask OFF
	editor._load_body_model(1)
	editor.select_part_by_id(&"helmet", &"helmet_leather_01")
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	editor.set_hair_mask_mode(&"off")
	set_portrait_cam.call(true)

	for h in [1, 2, 3, 4]:
		var hair_id := StringName("hair_short_0%d" % h)
		editor.select_part_by_id(&"hair", hair_id)
		editor.set_preview_yaw_degrees(0.0)
		await _settle(4)
		_save_capture("off_f_h%d_front.png" % h)
		editor.set_preview_yaw_degrees(85.0)
		await _settle(4)
		_save_capture("off_f_h%d_side.png" % h)
		editor.set_preview_yaw_degrees(175.0)
		await _settle(4)
		_save_capture("off_f_h%d_back.png" % h)

	# Test Male Hair 01, 02, 03, 04 with Mask OFF
	editor._load_body_model(0)
	editor.select_part_by_id(&"helmet", &"helmet_leather_01")
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	editor.set_hair_mask_mode(&"off")
	set_portrait_cam.call(false)

	for h in [1, 2, 3, 4]:
		var hair_id := StringName("hair_short_0%d" % h)
		editor.select_part_by_id(&"hair", hair_id)
		editor.set_preview_yaw_degrees(0.0)
		await _settle(4)
		_save_capture("off_m_h%d_front.png" % h)
		editor.set_preview_yaw_degrees(85.0)
		await _settle(4)
		_save_capture("off_m_h%d_side.png" % h)
		editor.set_preview_yaw_degrees(175.0)
		await _settle(4)
		_save_capture("off_m_h%d_back.png" % h)

	print("OFF_CAPTURES_DONE")
	editor.queue_free()
	await _settle(4)
	quit(0)

func _save_capture(filename: String) -> void:
	var path := ARTIFACT_DIR + "/" + filename
	var image := root.get_texture().get_image()
	image.save_png(path)

func _settle(frames: int) -> void:
	for i in range(frames):
		await process_frame
