extends SceneTree

const EDITOR_SCENE: String = "res://scenes/ui/HumanCharacter3DEditor.tscn"
const ARTIFACT_DIR: String = "C:/Users/Nekki/.gemini/antigravity/brain/6751ce0d-7d56-4cae-8c5b-9f20717bdb83"
const LOCAL_DIR: String = "res://.visual_captures/face_spot_investigation"

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
	editor = scene.instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	await _settle(12)

	if editor.camera != null:
		editor.camera.size = 0.42
		editor.camera.position = Vector3(0.0, 1.58, -1.15)
		editor.camera.look_at_from_position(editor.camera.position, Vector3(0.0, 1.58, 0.0), Vector3.UP)

	editor._load_body_model(0) # Male
	editor.set_mount_enabled(false)
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	editor.set_preview_yaw_degrees(0.0)
	editor.select_part_by_id(&"face", &"face_standard_01")
	editor.select_part_by_id(&"hair", &"hair_short_01")

	# 1. Helmet None
	editor.select_part_by_id(&"helmet", &"none")
	await _settle(6)
	await _capture_dual("male_hair01_helmet_none.png")

	# 2. Leather Helmet Auto
	editor.select_part_by_id(&"helmet", &"helmet_leather_01")
	editor.set_hair_mask_mode(&"auto")
	await _settle(6)
	await _capture_dual("male_hair01_leather_auto.png")

	# 3. Iron Helmet Auto
	editor.select_part_by_id(&"helmet", &"helmet_iron_01")
	editor.set_hair_mask_mode(&"auto")
	await _settle(6)
	await _capture_dual("male_hair01_iron_auto.png")

	# 4. Iron Helmet Off
	editor.set_hair_mask_mode(&"off")
	await _settle(6)
	await _capture_dual("male_hair01_iron_off.png")

	# 5. Iron Helmet Hide
	editor.set_hair_mask_mode(&"hide")
	await _settle(6)
	await _capture_dual("male_hair01_iron_hide.png")

	# 6. Hair None + Iron Helmet
	editor.select_part_by_id(&"hair", &"none")
	await _settle(6)
	await _capture_dual("male_hair_none_iron.png")

	print("MALE_HAIR01_COMPARISON_DONE")
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
