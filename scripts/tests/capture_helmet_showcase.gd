extends SceneTree

const EDITOR_SCENE: String = "res://scenes/ui/HumanCharacter3DEditor.tscn"
const ARTIFACT_DIR: String = "C:/Users/Nekki/.gemini/antigravity/brain/6751ce0d-7d56-4cae-8c5b-9f20717bdb83"
const LOCAL_DIR: String = "res://.visual_captures/helmet_showcase"

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

	# Helper to switch camera to close-up portrait on head
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
	# PART A: MALE CHARACTER FIT & CLEARANCE
	# =========================================================================
	editor._load_body_model(0)
	editor.set_mount_enabled(false)
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	editor.select_part_by_id(&"helmet", &"helmet_leather_01")
	editor.select_part_by_id(&"armor", &"armor_light_leather_01")

	# 1. Male Bald (Hair: None) - Pure skull fit inspection from multiple angles
	editor.select_part_by_id(&"hair", &"none")
	set_portrait_cam.call(false)
	editor.set_preview_yaw_degrees(0.0)
	await _settle(6)
	await _capture_dual("male_helmet_bald_front.png")

	editor.set_preview_yaw_degrees(35.0)
	await _settle(6)
	await _capture_dual("male_helmet_bald_34.png")

	editor.set_preview_yaw_degrees(90.0)
	await _settle(6)
	await _capture_dual("male_helmet_bald_side.png")

	editor.set_preview_yaw_degrees(180.0)
	await _settle(6)
	await _capture_dual("male_helmet_bald_back.png")

	# 2. Male with Hair Styles 1-4
	editor.select_part_by_id(&"hair", &"hair_short_01")
	editor.set_preview_yaw_degrees(30.0)
	await _settle(6)
	await _capture_dual("male_helmet_hair01_34.png")

	editor.select_part_by_id(&"hair", &"hair_short_02")
	await _settle(6)
	await _capture_dual("male_helmet_hair02_34.png")

	editor.select_part_by_id(&"hair", &"hair_short_03")
	await _settle(6)
	await _capture_dual("male_helmet_hair03_34.png")

	editor.select_part_by_id(&"hair", &"hair_short_04")
	await _settle(6)
	await _capture_dual("male_helmet_hair04_34.png")

	# =========================================================================
	# PART B: FEMALE CHARACTER FIT & CLEARANCE
	# =========================================================================
	editor._load_body_model(1)
	editor.set_mount_enabled(false)
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	editor.select_part_by_id(&"helmet", &"helmet_leather_01")
	editor.select_part_by_id(&"armor", &"armor_light_leather_01")

	# 3. Female Bald (Hair: None) - Pure skull fit inspection from multiple angles
	editor.select_part_by_id(&"hair", &"none")
	set_portrait_cam.call(true)
	editor.set_preview_yaw_degrees(0.0)
	await _settle(6)
	await _capture_dual("female_helmet_bald_front.png")

	editor.set_preview_yaw_degrees(35.0)
	await _settle(6)
	await _capture_dual("female_helmet_bald_34.png")

	editor.set_preview_yaw_degrees(90.0)
	await _settle(6)
	await _capture_dual("female_helmet_bald_side.png")

	editor.set_preview_yaw_degrees(180.0)
	await _settle(6)
	await _capture_dual("female_helmet_bald_back.png")

	# 4. Female with Hair Styles 1-4
	editor.select_part_by_id(&"hair", &"hair_short_01")  # Twintails
	editor.set_preview_yaw_degrees(30.0)
	await _settle(6)
	await _capture_dual("female_helmet_hair01_twintails.png")

	editor.select_part_by_id(&"hair", &"hair_short_02")  # Flowing shoulder hair
	await _settle(6)
	await _capture_dual("female_helmet_hair02_flowing.png")

	editor.select_part_by_id(&"hair", &"hair_short_03")  # Bob short
	await _settle(6)
	await _capture_dual("female_helmet_hair03_bob.png")

	editor.select_part_by_id(&"hair", &"hair_short_04")  # Ponytail
	await _settle(6)
	await _capture_dual("female_helmet_hair04_ponytail.png")

	# =========================================================================
	# PART C: DYNAMIC COMBAT & MOUNTED GAMEPLAY WITH HELMET
	# =========================================================================
	# 5. Male Riding with Helmet + Sword Slash
	editor._load_body_model(0)
	editor.select_part_by_id(&"helmet", &"helmet_leather_01")
	editor.select_part_by_id(&"hair", &"hair_short_01")
	editor.select_part_by_id(&"armor", &"armor_light_leather_01")
	editor.select_part_by_id(&"weapon", &"longsword_01")
	editor.set_mount_enabled(true)
	editor.set_mount_coat(&"bay")
	editor.select_animation_by_id(&"ride_slash")
	editor.set_playing(false)
	editor.animation_player.seek(0.96, true)
	editor._sync_mount_animation()
	editor.set_preview_yaw_degrees(40.0)
	await _settle(6)
	await _capture_dual("male_helmet_ride_slash.png")

	# 6. Female Riding with Helmet + Spear Thrust
	editor._load_body_model(1)
	editor.select_part_by_id(&"helmet", &"helmet_leather_01")
	editor.select_part_by_id(&"hair", &"hair_short_02")
	editor.select_part_by_id(&"armor", &"armor_light_leather_01")
	editor.select_part_by_id(&"weapon", &"spear_01")
	editor.set_mount_enabled(true)
	editor.set_mount_coat(&"white")
	editor.select_animation_by_id(&"ride_thrust")
	editor.set_playing(false)
	editor.animation_player.seek(0.68, true)
	editor._sync_mount_animation()
	editor.set_preview_yaw_degrees(45.0)
	await _settle(6)
	await _capture_dual("female_helmet_ride_thrust.png")

	# 7. Full Character Editor UI showing Helmet slot and 10/10 parts
	set_full_body_cam.call()
	editor.set_mount_enabled(false)
	editor.select_animation_by_id(&"idle")
	editor.set_preview_yaw_degrees(25.0)
	await _settle(6)
	await _capture_dual("helmet_showcase_editor_ui.png")

	print("HELMET_SHOWCASE_CAPTURES_DONE")
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
