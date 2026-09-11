extends SceneTree

const EDITOR_SCENE: String = "res://scenes/ui/HumanCharacter3DEditor.tscn"
const ARTIFACT_DIR: String = "C:/Users/Nekki/.gemini/antigravity/brain/6751ce0d-7d56-4cae-8c5b-9f20717bdb83"
const LOCAL_DIR: String = "res://.visual_captures/leather_helmet_hair_inspect"

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

	# Test Leather Helmet with all hairs:
	# Male: Hair 1, 2, 3, 4 (Front, 3/4, Side, Back)
	editor._load_body_model(0)
	editor.select_part_by_id(&"helmet", &"helmet_leather_01")
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	editor.set_hair_mask_mode(&"auto")
	set_portrait_cam.call(false)

	for h in [&"hair_short_01", &"hair_short_02", &"hair_short_03", &"hair_short_04"]:
		editor.select_part_by_id(&"hair", h)
		editor.set_preview_yaw_degrees(0.0) # Front
		await _settle(6)
		await _capture_dual("male_leather_%s_front.png" % h)
		editor.set_preview_yaw_degrees(35.0) # 3/4
		await _settle(6)
		await _capture_dual("male_leather_%s_three_quarter.png" % h)
		editor.set_preview_yaw_degrees(85.0) # Side
		await _settle(6)
		await _capture_dual("male_leather_%s_side.png" % h)
		editor.set_preview_yaw_degrees(175.0) # Back
		await _settle(6)
		await _capture_dual("male_leather_%s_back.png" % h)

	# Female: Hair 1, 2, 3, 4 (Front, 3/4, Side, Back)
	editor._load_body_model(1)
	editor.select_part_by_id(&"helmet", &"helmet_leather_01")
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	editor.set_hair_mask_mode(&"auto")
	set_portrait_cam.call(true)

	for h in [&"hair_short_01", &"hair_short_02", &"hair_short_03", &"hair_short_04"]:
		editor.select_part_by_id(&"hair", h)
		editor.set_preview_yaw_degrees(0.0) # Front
		await _settle(6)
		await _capture_dual("female_leather_%s_front.png" % h)
		editor.set_preview_yaw_degrees(35.0) # 3/4
		await _settle(6)
		await _capture_dual("female_leather_%s_three_quarter.png" % h)
		editor.set_preview_yaw_degrees(85.0) # Side
		await _settle(6)
		await _capture_dual("female_leather_%s_side.png" % h)
		editor.set_preview_yaw_degrees(175.0) # Back
		await _settle(6)
		await _capture_dual("female_leather_%s_back.png" % h)

	print("LEATHER_HELMET_HAIR_INSPECT_DONE")
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
