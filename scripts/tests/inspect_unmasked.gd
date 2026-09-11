extends SceneTree

const EDITOR_SCENE: String = "res://scenes/ui/HumanCharacter3DEditor.tscn"
const ARTIFACT_DIR: String = "C:/Users/Nekki/.gemini/antigravity/brain/6751ce0d-7d56-4cae-8c5b-9f20717bdb83"
const LOCAL_DIR: String = "res://.visual_captures/leather_unmasked"

var editor: HumanCharacter3DEditor

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
	assert(scene != null, "Failed to load editor scene")
	editor = scene.instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	await _settle(15)

	var set_portrait_cam = func(is_female: bool):
		if editor.camera == null:
			return
		var head_y := 1.48 if is_female else 1.58
		editor.camera.size = 0.96
		editor.camera.position = Vector3(0.0, head_y, -2.40)
		editor.camera.look_at_from_position(editor.camera.position, Vector3(0.0, head_y - 0.02, 0.0), Vector3.UP)

	# Male unmasked with leather helmet
	editor._load_body_model(0)
	editor.select_part_by_id(&"helmet", &"helmet_leather_01")
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	editor.set_hair_mask_mode(&"off")
	set_portrait_cam.call(false)

	for h in [&"hair_short_01", &"hair_short_02", &"hair_short_03", &"hair_short_04"]:
		editor.select_part_by_id(&"hair", h)
		editor.set_preview_yaw_degrees(35.0)
		await _settle(5)
		await _capture_dual("unmasked_male_%s_34.png" % h)
		editor.set_preview_yaw_degrees(145.0)
		await _settle(5)
		await _capture_dual("unmasked_male_%s_back.png" % h)

	# Female unmasked with leather helmet
	editor._load_body_model(1)
	editor.select_part_by_id(&"helmet", &"helmet_leather_01")
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	editor.set_hair_mask_mode(&"off")
	set_portrait_cam.call(true)

	for h in [&"hair_short_01", &"hair_short_02", &"hair_short_03", &"hair_short_04"]:
		editor.select_part_by_id(&"hair", h)
		editor.set_preview_yaw_degrees(35.0)
		await _settle(5)
		await _capture_dual("unmasked_female_%s_34.png" % h)
		editor.set_preview_yaw_degrees(145.0)
		await _settle(5)
		await _capture_dual("unmasked_female_%s_back.png" % h)

	print("UNMASKED_CAPTURES_DONE")
	editor.queue_free()
	await _settle(4)
	quit(0)

func _capture_dual(filename: String) -> void:
	var local_path := ProjectSettings.globalize_path(LOCAL_DIR + "/" + filename)
	var artifact_path := ARTIFACT_DIR + "/" + filename
	DirAccess.make_dir_recursive_absolute(local_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(artifact_path.get_base_dir())

	var image := root.get_texture().get_image()
	assert(image != null and not image.is_empty(), "Image capture failed")
	image.save_png(local_path)
	image.save_png(artifact_path)

func _settle(frames: int) -> void:
	for i in range(frames):
		await process_frame
