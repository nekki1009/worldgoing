extends SceneTree

const EDITOR_SCENE: String = "res://scenes/ui/HumanCharacter3DEditor.tscn"
const ARTIFACT_DIR: String = "C:/Users/Nekki/.gemini/antigravity/brain/6751ce0d-7d56-4cae-8c5b-9f20717bdb83"
const LOCAL_DIR: String = "res://.visual_captures/steel_helmet_showcase"

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

	var set_top_cam = func(is_female: bool):
		if editor.camera == null:
			return
		var head_y := 1.50 if is_female else 1.60
		editor.camera.size = 0.95
		editor.camera.position = Vector3(0.0, head_y + 1.25, -1.80)
		editor.camera.look_at_from_position(editor.camera.position, Vector3(0.0, head_y, 0.0), Vector3.UP)

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
	# 1. Male - Chinese Steel Helmet All-Angle Showcase
	# =========================================================================
	editor._load_body_model(0)
	editor.set_mount_enabled(false)
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	editor.select_part_by_id(&"helmet", &"helmet_steel_01")
	editor.select_part_by_id(&"hair", &"hair_short_01")
	editor.set_hair_mask_mode(&"auto")
	set_portrait_cam.call(false)

	# 1A. Front View (Front Taotie Beast Mask, Arched Brow Band, Cross-Ridge, Hanging Red Tassels)
	editor.set_preview_yaw_degrees(0.0)
	await _settle(10)
	await _capture_dual("steel_helmet_male_front.png")

	# 1B. 3/4 Perspective View (Cross-Ridge, Lotus Finial, Side Medallion, Aventail & Tassels)
	editor.set_preview_yaw_degrees(35.0)
	await _settle(10)
	await _capture_dual("steel_helmet_male_three_quarter.png")

	# 1C. Side Profile View (Side Sunburst-Lotus Rosette Medallion, Chin Strap & Buckle, Plume, Cheek Tassels)
	editor.set_preview_yaw_degrees(85.0)
	await _settle(10)
	await _capture_dual("steel_helmet_male_side.png")

	# 1D. Rear View (Volumetric Flowing Crimson Plume, Back Neck 4 Tassel Columns)
	editor.set_preview_yaw_degrees(175.0)
	await _settle(10)
	await _capture_dual("steel_helmet_male_back.png")

	# 1E. Top/High Angle View (Distinct 4-Way Cross-Ridge Reinforcing Bronze Bands with Domed Rivets)
	set_top_cam.call(false)
	editor.set_preview_yaw_degrees(25.0)
	await _settle(10)
	await _capture_dual("steel_helmet_male_top.png")

	# =========================================================================
	# 2. Female - Chinese Steel Helmet Showcase & Anti-Clipping Verification
	# =========================================================================
	set_portrait_cam.call(true)
	editor._load_body_model(1)
	editor.set_mount_enabled(false)
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	editor.select_part_by_id(&"helmet", &"helmet_steel_01")
	editor.select_part_by_id(&"hair", &"hair_short_01") # Female Twintails
	editor.set_hair_mask_mode(&"auto")

	# 2A. Female Front View
	editor.set_preview_yaw_degrees(0.0)
	await _settle(10)
	await _capture_dual("steel_helmet_female_front.png")

	# 2B. Female 3/4 Perspective View
	editor.set_preview_yaw_degrees(35.0)
	await _settle(10)
	await _capture_dual("steel_helmet_female_three_quarter.png")

	# 2C. Female Hair 04 (Combat High Ponytail) - Zero Clipping Check
	editor.select_part_by_id(&"hair", &"hair_short_04")
	editor.set_preview_yaw_degrees(145.0)
	await _settle(10)
	await _capture_dual("steel_helmet_female_hair04_auto.png")

	# =========================================================================
	# 3. Full Body Action & Mounted Combat
	# =========================================================================
	# 3A. Male Sword Action with Steel Helmet
	set_full_body_cam.call()
	editor._load_body_model(0)
	editor.select_part_by_id(&"helmet", &"helmet_steel_01")
	editor.select_part_by_id(&"hair", &"hair_short_01")
	editor.select_part_by_id(&"weapon", &"longsword_01")
	editor.select_animation_by_id(&"walk_slash")
	editor.set_playing(false)
	if editor.animation_player:
		editor.animation_player.seek(0.35, true)
	editor.set_preview_yaw_degrees(32.0)
	await _settle(10)
	await _capture_dual("steel_helmet_male_sword_action.png")

	# 3B. Mounted Combat - Riding Spear Thrust with Steel Helmet
	set_riding_cam.call()
	editor.set_mount_enabled(true)
	editor.select_part_by_id(&"weapon", &"weapon_spear_01")
	editor.select_animation_by_id(&"ride_thrust")
	editor.set_playing(false)
	if editor.animation_player:
		editor.animation_player.seek(0.60, true)
	editor.set_preview_yaw_degrees(40.0)
	await _settle(12)
	await _capture_dual("steel_helmet_combat_horse_thrust.png")

	# 3C. Full UI Showcase
	editor.set_mount_enabled(false)
	editor.select_animation_by_id(&"idle")
	editor.select_part_by_id(&"weapon", &"weapon_longsword_01")
	editor.set_preview_yaw_degrees(20.0)
	set_full_body_cam.call()
	await _settle(10)
	await _capture_dual("steel_helmet_ui_showcase.png")

	print("STEEL_HELMET_SHOWCASE_CAPTURES_DONE")
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
