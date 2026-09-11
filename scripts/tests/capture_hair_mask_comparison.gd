extends SceneTree

const EDITOR_SCENE: String = "res://scenes/ui/HumanCharacter3DEditor.tscn"
const ARTIFACT_DIR: String = "C:/Users/Nekki/.gemini/antigravity/brain/6751ce0d-7d56-4cae-8c5b-9f20717bdb83"
const LOCAL_DIR: String = "res://.visual_captures/hair_mask_comparison"

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
	await _settle(14)

	var set_portrait_cam = func(is_female: bool):
		if editor.camera == null:
			return
		var head_y := 1.48 if is_female else 1.58
		editor.camera.size = 0.92
		editor.camera.position = Vector3(0.0, head_y, -2.40)
		editor.camera.look_at_from_position(editor.camera.position, Vector3(0.0, head_y - 0.02, 0.0), Vector3.UP)

	var set_full_body_cam = func():
		if editor.camera == null:
			return
		editor.camera.size = 2.18
		editor.camera.position = Vector3(0.0, 1.20, -4.65)
		editor.camera.look_at_from_position(editor.camera.position, Vector3(0.0, 0.87, 0.0), Vector3.UP)

	# =========================================================================
	# 1. Male Hair 01 (Spiky anime hair) - 3 Modes Comparison
	# =========================================================================
	editor._load_body_model(0)
	editor.set_mount_enabled(false)
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	editor.select_part_by_id(&"helmet", &"helmet_leather_01")
	editor.select_part_by_id(&"hair", &"hair_short_01")
	set_portrait_cam.call(false)
	editor.set_preview_yaw_degrees(32.0)

	# 1A. Mode: Off (Raw unmasked piercing)
	editor.set_hair_mask_mode(&"off")
	await _settle(8)
	await _capture_dual("male_helmet_hair01_mask_off.png")

	# 1B. Mode: Auto (Smart Spatial Clip Shader - Keeps Bangs, Clips Top Spikes)
	editor.set_hair_mask_mode(&"auto")
	await _settle(8)
	await _capture_dual("male_helmet_hair01_mask_auto.png")

	# 1C. Mode: Hide (Full Occlusion / Arming Cap)
	editor.set_hair_mask_mode(&"hide")
	await _settle(8)
	await _capture_dual("male_helmet_hair01_mask_hide.png")

	# =========================================================================
	# 2. Female Hair 04 (High Combat Ponytail) - 3 Modes Comparison
	# =========================================================================
	editor._load_body_model(1)
	editor.set_mount_enabled(false)
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	editor.select_part_by_id(&"helmet", &"helmet_leather_01")
	editor.select_part_by_id(&"hair", &"hair_short_04")
	set_portrait_cam.call(true)
	editor.set_preview_yaw_degrees(32.0)

	# 2A. Mode: Off
	editor.set_hair_mask_mode(&"off")
	await _settle(8)
	await _capture_dual("female_helmet_hair04_mask_off.png")

	# 2B. Mode: Auto (Smart Clip)
	editor.set_hair_mask_mode(&"auto")
	await _settle(8)
	await _capture_dual("female_helmet_hair04_mask_auto.png")

	# 2C. Mode: Hide
	editor.set_hair_mask_mode(&"hide")
	await _settle(8)
	await _capture_dual("female_helmet_hair04_mask_hide.png")

	# =========================================================================
	# 3. Female Hair 02 (Flowing Shoulder Hair) - 3 Modes Comparison
	# =========================================================================
	editor.select_part_by_id(&"hair", &"hair_short_02")
	editor.set_preview_yaw_degrees(30.0)

	# 3A. Mode: Off
	editor.set_hair_mask_mode(&"off")
	await _settle(8)
	await _capture_dual("female_helmet_hair02_mask_off.png")

	# 3B. Mode: Auto (Smart Clip)
	editor.set_hair_mask_mode(&"auto")
	await _settle(8)
	await _capture_dual("female_helmet_hair02_mask_auto.png")

	# 3C. Mode: Hide
	editor.set_hair_mask_mode(&"hide")
	await _settle(8)
	await _capture_dual("female_helmet_hair02_mask_hide.png")

	# =========================================================================
	# 4. Full Character Editor UI showing the new "Hair Mask / 髮型遮罩" control
	# =========================================================================
	set_full_body_cam.call()
	editor._load_body_model(0)
	editor.select_part_by_id(&"helmet", &"helmet_leather_01")
	editor.select_part_by_id(&"hair", &"hair_short_01")
	editor.set_hair_mask_mode(&"auto")
	editor.set_preview_yaw_degrees(20.0)
	await _settle(8)
	await _capture_dual("helmet_hair_mask_ui.png")

	print("HAIR_MASK_COMPARISON_CAPTURES_DONE")
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
