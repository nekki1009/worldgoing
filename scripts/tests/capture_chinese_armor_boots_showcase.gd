extends SceneTree

const EDITOR_SCENE: String = "res://scenes/ui/HumanCharacter3DEditor.tscn"
const ARTIFACT_DIR: String = "C:/Users/Nekki/Dropbox/竹北社大/(01)102-103學員資料/share/worldgoing/.visual_captures/mingguang_armor_remake"
const LOCAL_DIR: String = "res://.visual_captures/mingguang_armor_remake"

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

	# Camera helper lambdas
	var set_full_body_cam = func():
		if editor.camera == null:
			return
		editor.camera.size = 2.20
		editor.camera.position = Vector3(0.0, 1.15, -4.65)
		editor.camera.look_at_from_position(editor.camera.position, Vector3(0.0, 0.90, 0.0), Vector3.UP)

	var set_torso_cam = func(is_female: bool):
		if editor.camera == null:
			return
		var cy := 1.18 if is_female else 1.25
		editor.camera.size = 1.15
		editor.camera.position = Vector3(0.0, cy, -2.80)
		editor.camera.look_at_from_position(editor.camera.position, Vector3(0.0, cy - 0.05, 0.0), Vector3.UP)

	var set_boots_cam = func():
		if editor.camera == null:
			return
		editor.camera.size = 0.95
		editor.camera.position = Vector3(0.0, 0.38, -2.35)
		editor.camera.look_at_from_position(editor.camera.position, Vector3(0.0, 0.32, 0.0), Vector3.UP)

	var set_pauldron_cam = func(is_female: bool):
		if editor.camera == null:
			return
		var py := 1.22 if is_female else 1.28
		editor.camera.size = 1.10
		editor.camera.position = Vector3(0.25, py, -2.10)
		editor.camera.look_at_from_position(editor.camera.position, Vector3(0.18, py - 0.05, 0.0), Vector3.UP)

	# =========================================================================
	# 1. MALE FULL SUIT: Chinese Iron Helmet + Mingguang Armor + Mingguang War Boots
	# =========================================================================
	editor.select_part_by_id(&"helmet", &"helmet_iron_01")
	editor.select_part_by_id(&"outfit", &"none")
	editor.select_part_by_id(&"armor", &"armor_mingguang_01")
	editor.select_part_by_id(&"cape", &"none")
	editor.select_part_by_id(&"boots", &"boots_mingguang_01")
	editor.select_part_by_id(&"weapon", &"longsword_01")
	editor.select_part_by_id(&"shield", &"none")
	editor.select_animation_by_id(&"idle")
	editor.animation_player.seek(0.5, true)
	editor.animation_player.advance(0.0)
	editor.set_playing(false)

	set_full_body_cam.call()

	# Front
	editor.set_preview_yaw_degrees(0.0)
	await _settle(6)
	await _capture_dual("male_mingguang_armor_front.png")

	# 3/4 Perspective
	editor.set_preview_yaw_degrees(35.0)
	await _settle(6)
	await _capture_dual("male_mingguang_armor_34.png")

	# Side
	editor.set_preview_yaw_degrees(90.0)
	await _settle(6)
	await _capture_dual("male_mingguang_armor_side.png")

	# Back
	editor.set_preview_yaw_degrees(180.0)
	await _settle(6)
	await _capture_dual("male_mingguang_armor_back.png")

	# =========================================================================
	# 2. DETAIL CLOSEUPS (MALE)
	# =========================================================================
	# Torso & Chest Beast Boss & Gorget & Belt
	set_torso_cam.call(false)
	editor.set_preview_yaw_degrees(20.0)
	await _settle(6)
	await _capture_dual("male_mingguang_armor_chest_close.png")

	# Pauldron with Lion Beast Cap & Tassels
	set_pauldron_cam.call(false)
	editor.set_preview_yaw_degrees(35.0)
	await _settle(6)
	await _capture_dual("male_mingguang_armor_pauldron_close.png")

	# Boots: Shin Guard, Shin Beast Boss, Straps, Instep Articulated Plates, Sole
	set_boots_cam.call()
	editor.set_preview_yaw_degrees(25.0)
	await _settle(6)
	await _capture_dual("male_mingguang_armor_greaves_34.png")

	editor.set_preview_yaw_degrees(75.0)
	await _settle(6)
	await _capture_dual("male_mingguang_armor_greaves_side.png")

	editor.set_preview_yaw_degrees(0.0)
	await _settle(6)
	await _capture_dual("male_mingguang_armor_greaves_front.png")

	# =========================================================================
	# 3. FEMALE FULL SUIT: Chinese Steel Helmet + Mingguang Armor + Mingguang War Boots
	# =========================================================================
	editor._load_body_model(1) # Switch to Female
	await _settle(12)

	editor.select_part_by_id(&"helmet", &"helmet_steel_01")
	editor.select_part_by_id(&"outfit", &"none")
	editor.select_part_by_id(&"armor", &"armor_mingguang_01")
	editor.select_part_by_id(&"cape", &"none")
	editor.select_part_by_id(&"boots", &"boots_mingguang_01")
	editor.select_part_by_id(&"weapon", &"spear_01")
	editor.select_part_by_id(&"shield", &"none")
	editor.set_playing(true)
	editor.select_animation_by_id(&"idle")
	await _settle(6)
	editor.animation_player.seek(0.5, true)
	editor.animation_player.advance(0.0)
	editor.set_playing(false)
	await _settle(4)

	set_full_body_cam.call()

	# Female Front
	editor.set_preview_yaw_degrees(0.0)
	await _settle(6)
	await _capture_dual("female_mingguang_armor_front.png")

	# Female 3/4
	editor.set_preview_yaw_degrees(35.0)
	await _settle(6)
	await _capture_dual("female_mingguang_armor_34.png")

	# Female Back
	editor.set_preview_yaw_degrees(180.0)
	await _settle(6)
	await _capture_dual("female_mingguang_armor_back.png")

	# Female Torso Close-up
	set_torso_cam.call(true)
	editor.set_preview_yaw_degrees(15.0)
	await _settle(6)
	await _capture_dual("female_mingguang_armor_chest_close.png")

	# Female Boots Close-up
	set_boots_cam.call()
	editor.set_preview_yaw_degrees(30.0)
	await _settle(6)
	await _capture_dual("female_mingguang_armor_greaves_close.png")

	# =========================================================================
	# 4. ACTION POSES & MOUNTED COMBAT
	# =========================================================================
	# Male Jump Heavy Attack with Mingguang Armor
	editor._load_body_model(0) # Switch back to Male
	await _settle(12)
	editor.select_part_by_id(&"helmet", &"helmet_iron_01")
	editor.select_part_by_id(&"outfit", &"none")
	editor.select_part_by_id(&"armor", &"armor_mingguang_01")
	editor.select_part_by_id(&"cape", &"none")
	editor.select_part_by_id(&"boots", &"boots_mingguang_01")
	editor.select_part_by_id(&"weapon", &"longsword_01")
	editor.select_animation_by_id(&"attack_jump_heavy")
	editor.set_playing(false)
	editor.animation_player.seek(0.55, true)
	editor.animation_player.advance(0.0)
	set_full_body_cam.call()
	editor.set_preview_yaw_degrees(40.0)
	await _settle(6)
	await _capture_dual("male_mingguang_armor_attack_jump.png")

	# Female Mounted Combat with Spear in Mingguang Armor
	editor._load_body_model(1)
	await _settle(12)
	editor.select_part_by_id(&"helmet", &"helmet_steel_01")
	editor.select_part_by_id(&"outfit", &"none")
	editor.select_part_by_id(&"armor", &"armor_mingguang_01")
	editor.select_part_by_id(&"cape", &"none")
	editor.select_part_by_id(&"boots", &"boots_mingguang_01")
	editor.select_part_by_id(&"weapon", &"spear_01")
	editor.set_mount_enabled(true)
	editor.set_mount_coat(&"black")
	editor.select_animation_by_id(&"ride_slash")
	editor.set_playing(false)
	editor.animation_player.seek(0.65, true)
	editor._sync_mount_animation()
	editor.camera.size = 3.10
	editor.camera.position = Vector3(0.0, 1.45, -5.80)
	editor.camera.look_at_from_position(editor.camera.position, Vector3(0.0, 1.10, 0.0), Vector3.UP)
	editor.set_preview_yaw_degrees(45.0)
	await _settle(6)
	await _capture_dual("female_mingguang_armor_mounted_combat.png")

	# Male Walk & Run
	editor.select_animation_by_id(&"walk")
	editor.set_playing(false)
	editor.animation_player.seek(0.35, true)
	editor.animation_player.advance(0.0)
	set_full_body_cam.call()
	editor.set_preview_yaw_degrees(35.0)
	await _settle(6)
	await _capture_dual("male_mingguang_armor_walk.png")

	editor.select_animation_by_id(&"run")
	editor.set_playing(false)
	editor.animation_player.seek(0.40, true)
	editor.animation_player.advance(0.0)
	editor.set_preview_yaw_degrees(40.0)
	await _settle(6)
	await _capture_dual("male_mingguang_armor_run.png")

	# 5. Full Editor UI showing the remade Mingguang Armor and separate boots
	editor.set_mount_enabled(false)
	editor.select_animation_by_id(&"idle")
	set_full_body_cam.call()
	editor.set_preview_yaw_degrees(25.0)
	await _settle(6)
	await _capture_dual("mingguang_armor_editor_ui.png")

	print("MINGGUANG_ARMOR_REMAKE_SHOWCASE_CAPTURES_DONE")
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
