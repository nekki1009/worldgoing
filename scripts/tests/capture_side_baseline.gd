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

	# Male Hair 01 with Helmet OFF from Side (85 deg) and 3/4 (35 deg)
	editor._load_body_model(0)
	editor.select_part_by_id(&"hair", &"hair_short_01")
	editor.select_part_by_id(&"helmet", &"none")
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	
	if editor.camera != null:
		editor.camera.size = 0.96
		editor.camera.position = Vector3(0.0, 1.58, -2.40)
		editor.camera.look_at_from_position(editor.camera.position, Vector3(0.0, 1.56, 0.0), Vector3.UP)

	editor.set_preview_yaw_degrees(85.0)
	await _settle(6)
	var img := root.get_texture().get_image()
	img.save_png(ARTIFACT_DIR + "/unmasked_male_h1_pure_side.png")

	editor.select_part_by_id(&"helmet", &"helmet_leather_01")
	editor.set_hair_mask_mode(&"off")
	await _settle(6)
	img = root.get_texture().get_image()
	img.save_png(ARTIFACT_DIR + "/leather_male_h1_mask_off_side.png")

	editor.queue_free()
	await _settle(4)
	quit(0)

func _settle(frames: int) -> void:
	for i in range(frames):
		await process_frame
