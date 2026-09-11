extends SceneTree

const EDITOR_SCENE: String = "res://scenes/ui/HumanCharacter3DEditor.tscn"
const ARTIFACT_DIR: String = "C:/Users/Nekki/.gemini/antigravity/brain/6751ce0d-7d56-4cae-8c5b-9f20717bdb83"
const LOCAL_DIR: String = "res://.visual_captures/iron_helmet_showcase"

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

	var set_portrait_cam = func(is_female: bool, dist_offset: float = 0.0):
		if editor.camera == null:
			return
		var head_y := 1.48 if is_female else 1.58
		editor.camera.size = 0.96
		editor.camera.position = Vector3(0.0, head_y, -2.40 + dist_offset)
		editor.camera.look_at_from_position(editor.camera.position, Vector3(0.0, head_y - 0.02, 0.0), Vector3.UP)

	var set_full_body_cam = func():
		if editor.camera == null:
			return
		editor.camera.size = 2.25
		editor.camera.position = Vector3(0.0, 1.22, -4.75)
		editor.camera.look_at_from_position(editor.camera.position, Vector3(0.0, 0.88, 0.0), Vector3.UP)

	var set_riding_cam = func():
		if editor.camera == null:
			return
		editor.camera.size = 2.65
		editor.camera.position = Vector3(0.0, 1.45, -5.20)
		editor.camera.look_at_from_position(editor.camera.position, Vector3(0.0, 1.10, 0.0), Vector3.UP)

	# =========================================================================
	# 1. Male - Chinese Iron Helmet All-Angle Showcase
	# =========================================================================
	editor._load_body_model(0)
	editor.set_mount_enabled(false)
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	editor.select_part_by_id(&"helmet", &"helmet_iron_01")
	editor.select_part_by_id(&"hair", &"hair_short_01")
	editor.set_hair_mask_mode(&"auto")
	set_portrait_cam.call(false)

	# 1A. Front View (Front Taotie Beast Mask, Arched Brow Band, Lobed Dome, Red Plume Peak)
	editor.set_preview_yaw_degrees(0.0)
	await _settle(10)
	await _capture_dual("iron_helmet_male_front.png")

	# 1B. 3/4 Perspective View (Fluted Dome, Lotus Finial, Beast Mask Relief, Aventail Flaps)
	editor.set_preview_yaw_degrees(35.0)
	await _settle(10)
	await _capture_dual("iron_helmet_male_three_quarter.png")

	# 1C. Side Profile View (Curving Brow, Cheek Guard, Chin Strap & Buckle, Cascading Plume)
	editor.set_preview_yaw_degrees(85.0)
	await _settle(10)
	await _capture_dual("iron_helmet_male_side.png")

	# 1D. Rear View (Volumetric Flowing Crimson Plume, Back Nape Lamellar Flap)
	editor.set_preview_yaw_degrees(175.0)
	await _settle(10)
	await _capture_dual("iron_helmet_male_back.png")

	# =========================================================================
	# 2. Female Hair 01 (Twintails) - Zero Clipping Verification (Off vs Auto)
	# =========================================================================
	editor._load_body_model(1)
	editor.set_mount_enabled(false)
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	editor.select_part_by_id(&"helmet", &"helmet_iron_01")
	editor.select_part_by_id(&"hair", &"hair_short_01") # Female Twintails
	set_portrait_cam.call(true)
	editor.set_preview_yaw_degrees(32.0)

	# 2A. Mask OFF: Twintails piercing through sides of helmet and cheek guards
	editor.set_hair_mask_mode(&"off")
	await _settle(10)
	await _capture_dual("female_iron_helmet_hair01_off.png")

	# 2B. Mask AUTO: 3-Zone mask culls lateral twintail bursts while keeping front bangs clean!
	editor.set_hair_mask_mode(&"auto")
	await _settle(10)
	await _capture_dual("female_iron_helmet_hair01_auto.png")

	# =========================================================================
	# 3. Female Hair 04 (Combat High Ponytail) - Rear Bun Clipping Verification
	# =========================================================================
	editor.select_part_by_id(&"hair", &"hair_short_04") # Female High Ponytail
	editor.set_preview_yaw_degrees(145.0) # Look at back-side where ponytail knot was bursting

	# 3A. Mask OFF: Ponytail knot bursting through back of aventail
	editor.set_hair_mask_mode(&"off")
	await _settle(10)
	await _capture_dual("female_iron_helmet_hair04_off.png")

	# 3B. Mask AUTO: Occipital bun zone cleanly clipped, zero back penetration!
	editor.set_hair_mask_mode(&"auto")
	await _settle(10)
	await _capture_dual("female_iron_helmet_hair04_auto.png")

	# 3C. Side Profile View: zero penetration through dome or aventail
	editor.set_preview_yaw_degrees(90.0)
	await _settle(10)
	await _capture_dual("female_iron_helmet_hair04_side.png")

	# 3D. Front Angle: verifies front bangs are preserved beautifully!
	editor.set_preview_yaw_degrees(25.0)
	await _settle(10)
	await _capture_dual("female_iron_helmet_hair04_front.png")

	# 3E. Leather Helmet comparison:
	editor.select_part_by_id(&"helmet", &"helmet_leather_01")
	editor.set_preview_yaw_degrees(145.0)
	editor.set_hair_mask_mode(&"off")
	await _settle(10)
	await _capture_dual("female_leather_helmet_hair04_off.png")
	editor.set_hair_mask_mode(&"auto")
	await _settle(10)
	await _capture_dual("female_leather_helmet_hair04_auto.png")

	# 3F. Dynamic Animation Pose (Run clip): verifies dynamic per-frame bone head mask!
	editor.select_part_by_id(&"helmet", &"helmet_iron_01")
	editor.select_animation_by_id(&"run")
	editor.set_playing(false)
	if editor.animation_player:
		editor.animation_player.seek(0.35, true)
	editor.set_preview_yaw_degrees(140.0)
	await _settle(10)
	await _capture_dual("female_iron_helmet_hair04_anim_run.png")

	# Restore idle for next tests
	editor.select_animation_by_id(&"idle")

	# =========================================================================
	# 4. Female Hair 02 (Flowing Shoulder Locks) - Natural Bangs & Draping
	# =========================================================================
	editor.select_part_by_id(&"hair", &"hair_short_02")
	editor.set_preview_yaw_degrees(30.0)
	editor.set_hair_mask_mode(&"auto")
	await _settle(10)
	await _capture_dual("female_iron_helmet_hair02_auto.png")

	# =========================================================================
	# 5. Full Body Combat & Riding Showcase
	# =========================================================================
	# 5A. Male Sword Action with Iron Helmet & Full Armor
	set_full_body_cam.call()
	editor._load_body_model(0)
	editor.select_part_by_id(&"helmet", &"helmet_iron_01")
	editor.select_part_by_id(&"hair", &"hair_short_01")
	editor.set_hair_mask_mode(&"auto")
	editor.select_part_by_id(&"weapon", &"longsword_01")
	editor.select_animation_by_id(&"walk_slash")
	editor.set_playing(false)
	if editor.animation_player:
		editor.animation_player.seek(0.35, true)
	editor.set_preview_yaw_degrees(32.0)
	await _settle(10)
	await _capture_dual("iron_helmet_male_sword_action.png")

	# 5B. Mounted Combat - Riding Spear Thrust with Iron Helmet & Tassel
	set_riding_cam.call()
	editor.set_mount_enabled(true)
	editor.select_part_by_id(&"weapon", &"weapon_spear_01")
	editor.select_animation_by_id(&"ride_thrust")
	editor.set_playing(false)
	if editor.animation_player:
		editor.animation_player.seek(0.60, true)
	editor.set_preview_yaw_degrees(40.0)
	await _settle(12)
	await _capture_dual("iron_helmet_combat_horse_thrust.png")

	# 5C. Full UI Showcase
	editor.set_mount_enabled(false)
	editor.select_animation_by_id(&"idle")
	editor.select_part_by_id(&"weapon", &"weapon_longsword_01")
	editor.set_preview_yaw_degrees(20.0)
	set_full_body_cam.call()
	await _settle(10)
	await _capture_dual("iron_helmet_ui_showcase.png")

	print("IRON_HELMET_SHOWCASE_CAPTURES_DONE")
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
