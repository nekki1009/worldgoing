extends SceneTree

const EDITOR_SCENE: String = "res://scenes/ui/HumanCharacter3DEditor.tscn"
const ARTIFACT_DIR: String = "C:/Users/Nekki/.gemini/antigravity/brain/6751ce0d-7d56-4cae-8c5b-9f20717bdb83"
const LOCAL_DIR: String = "res://.visual_captures/diag_female_shield"

var editor: HumanCharacter3DEditor

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var scene := load(EDITOR_SCENE) as PackedScene
	assert(scene != null, "Failed to load editor scene")
	editor = scene.instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	await _settle(14)

	var set_cam = func(pos: Vector3, look_tgt: Vector3, size: float):
		if editor.camera == null:
			return
		editor.camera.size = size
		editor.camera.position = pos
		editor.camera.look_at_from_position(pos, look_tgt, Vector3.UP)

	# =========================================================================
	# TEST A: Shield on Back vs Cape (Male and Female)
	# =========================================================================
	print("TEST A: Shield on back vs Cape")
	# Male: Cape + Shield (Holstered during Walk/Idle)
	editor._load_body_model(0) # Male
	await _settle(10)
	editor.select_part_by_id(&"helmet", &"none")
	editor.select_part_by_id(&"outfit", &"outfit_underlayer_01")
	editor.select_part_by_id(&"armor", &"armor_iron_01")
	editor.select_part_by_id(&"cape", &"cape_travel_01")
	editor.select_part_by_id(&"boots", &"boots_iron_01")
	editor.select_part_by_id(&"weapon", &"none")
	editor.select_part_by_id(&"shield", &"shield_heater_01")
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	editor.animation_player.seek(0.5, true)
	editor.animation_player.advance(0.0)

	# Male Back with Cape + Shield
	set_cam.call(Vector3(0.0, 1.25, -2.80), Vector3(0.0, 1.20, 0.0), 1.15)
	editor.set_preview_yaw_degrees(180.0)
	await _settle(6)
	await _capture_dual("diag_male_back_shield_cape.png")

	editor.set_preview_yaw_degrees(150.0)
	await _settle(6)
	await _capture_dual("diag_male_back_shield_cape_angle.png")

	# Male Walk with Cape + Shield
	editor.select_animation_by_id(&"walk")
	editor.set_playing(false)
	editor.animation_player.seek(0.25, true)
	editor.animation_player.advance(0.0)
	await _settle(6)
	await _capture_dual("diag_male_back_shield_cape_walk.png")

	# Male Run with Cape + Shield
	editor.select_animation_by_id(&"run")
	editor.set_playing(false)
	editor.animation_player.seek(0.30, true)
	editor.animation_player.advance(0.0)
	await _settle(6)
	await _capture_dual("diag_male_back_shield_cape_run.png")

	# Male Mingguang Armor (No Cape, No Shield)
	editor.select_part_by_id(&"cape", &"none")
	editor.select_part_by_id(&"shield", &"none")
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	editor.animation_player.seek(0.5, true)
	editor.animation_player.advance(0.0)

	# Male Full Body Front
	set_cam.call(Vector3(0.0, 1.10, -4.50), Vector3(0.0, 0.85, 0.0), 2.20)
	editor.set_preview_yaw_degrees(0.0)
	await _settle(6)
	await _capture_dual("diag_male_iron_front_nocape.png")

	# Male Torso Close-up Front
	set_cam.call(Vector3(0.0, 1.20, -2.60), Vector3(0.0, 1.15, 0.0), 1.10)
	editor.set_preview_yaw_degrees(0.0)
	await _settle(6)
	await _capture_dual("diag_male_torso_front.png")

	# Male Mingguang Armor 01
	editor.select_part_by_id(&"armor", &"armor_mingguang_01")
	await _settle(6)

	# Male Mingguang Full Body Front
	set_cam.call(Vector3(0.0, 1.10, -4.50), Vector3(0.0, 0.85, 0.0), 2.20)
	editor.set_preview_yaw_degrees(0.0)
	await _settle(6)
	await _capture_dual("diag_male_mingguang_front.png")

	# Male Mingguang Torso Front Close-up
	set_cam.call(Vector3(0.0, 1.20, -2.60), Vector3(0.0, 1.15, 0.0), 1.10)
	editor.set_preview_yaw_degrees(0.0)
	await _settle(6)
	await _capture_dual("diag_male_mingguang_torso.png")

	# Male Mingguang 3/4 Front Angle
	editor.set_preview_yaw_degrees(35.0)
	await _settle(6)
	await _capture_dual("diag_male_mingguang_angle.png")

	# Male Mingguang Back
	editor.set_preview_yaw_degrees(180.0)
	await _settle(6)
	await _capture_dual("diag_male_mingguang_back.png")

	# =========================================================================
	# TEST B: Female Chinese Iron Armor from multiple angles & animations
	# =========================================================================
	print("TEST B: Female Chinese Iron Armor")
	editor._load_body_model(1) # Female
	await _settle(10)
	editor.select_part_by_id(&"helmet", &"none")
	editor.select_part_by_id(&"outfit", &"outfit_underlayer_01")
	editor.select_part_by_id(&"armor", &"armor_iron_01")
	editor.select_part_by_id(&"cape", &"none")
	editor.select_part_by_id(&"boots", &"boots_iron_01")
	editor.select_part_by_id(&"weapon", &"none")
	editor.select_part_by_id(&"shield", &"none")
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	editor.animation_player.seek(0.5, true)
	editor.animation_player.advance(0.0)

	# Female Full Body Front (No Cape)
	set_cam.call(Vector3(0.0, 1.10, -4.50), Vector3(0.0, 0.85, 0.0), 2.20)
	editor.set_preview_yaw_degrees(0.0)
	await _settle(6)
	await _capture_dual("diag_female_iron_front_nocape.png")

	# Female Full Body Back (No Cape)
	editor.set_preview_yaw_degrees(180.0)
	await _settle(6)
	await _capture_dual("diag_female_iron_back_nocape.png")

	# Female Full Body Side Left & Right (No Cape)
	editor.set_preview_yaw_degrees(90.0)
	await _settle(6)
	await _capture_dual("diag_female_iron_left_nocape.png")

	editor.set_preview_yaw_degrees(270.0)
	await _settle(6)
	await _capture_dual("diag_female_iron_right_nocape.png")

	# Female Torso Close-up Front, Side, Back (No Cape)
	set_cam.call(Vector3(0.0, 1.15, -2.60), Vector3(0.0, 1.10, 0.0), 1.10)
	editor.set_preview_yaw_degrees(0.0)
	await _settle(6)
	await _capture_dual("diag_female_torso_front.png")

	editor.set_preview_yaw_degrees(90.0)
	await _settle(6)
	await _capture_dual("diag_female_torso_side.png")

	editor.set_preview_yaw_degrees(180.0)
	await _settle(6)
	await _capture_dual("diag_female_torso_back.png")

	# Female Pelvis / Crotch / Thigh Close-up (Front & Back)
	set_cam.call(Vector3(0.0, 0.75, -2.20), Vector3(0.0, 0.75, 0.0), 0.90)
	editor.set_preview_yaw_degrees(0.0)
	await _settle(6)
	await _capture_dual("diag_female_pelvis_front.png")

	editor.set_preview_yaw_degrees(180.0)
	await _settle(6)
	await _capture_dual("diag_female_pelvis_back.png")

	# Female Mingguang Armor 01
	editor.select_part_by_id(&"armor", &"armor_mingguang_01")
	await _settle(6)

	# Female Mingguang Full Body Front
	set_cam.call(Vector3(0.0, 1.10, -4.50), Vector3(0.0, 0.85, 0.0), 2.20)
	editor.set_preview_yaw_degrees(0.0)
	await _settle(6)
	await _capture_dual("diag_female_mingguang_front.png")

	# Female Mingguang Torso Front
	set_cam.call(Vector3(0.0, 1.15, -2.60), Vector3(0.0, 1.10, 0.0), 1.10)
	editor.set_preview_yaw_degrees(0.0)
	await _settle(6)
	await _capture_dual("diag_female_mingguang_torso.png")

	# Female Mingguang Torso Side
	editor.set_preview_yaw_degrees(90.0)
	await _settle(6)
	await _capture_dual("diag_female_mingguang_side.png")

	# Female Mingguang Torso Back
	editor.set_preview_yaw_degrees(180.0)
	await _settle(6)
	await _capture_dual("diag_female_mingguang_back.png")

	# Female Mingguang 3/4 Angle
	editor.set_preview_yaw_degrees(35.0)
	await _settle(6)
	await _capture_dual("diag_female_mingguang_angle.png")

	# Female Walk Animation (seek 0.25 & 0.75)
	set_cam.call(Vector3(0.0, 1.10, -4.50), Vector3(0.0, 0.85, 0.0), 2.20)
	editor.select_animation_by_id(&"walk")
	editor.set_playing(false)
	editor.animation_player.seek(0.25, true)
	editor.animation_player.advance(0.0)
	editor.set_preview_yaw_degrees(45.0)
	await _settle(6)
	await _capture_dual("diag_female_walk_45.png")

	editor.set_preview_yaw_degrees(135.0)
	await _settle(6)
	await _capture_dual("diag_female_walk_135.png")

	# Female Run Animation (seek 0.3)
	editor.select_animation_by_id(&"run")
	editor.set_playing(false)
	editor.animation_player.seek(0.30, true)
	editor.animation_player.advance(0.0)
	editor.set_preview_yaw_degrees(45.0)
	await _settle(6)
	await _capture_dual("diag_female_run_45.png")

	# Female with Shield and Cape
	editor.select_part_by_id(&"cape", &"cape_travel_01")
	editor.select_part_by_id(&"shield", &"none")
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	editor.animation_player.seek(0.5, true)
	editor.animation_player.advance(0.0)

	# Female Front with Cape + Iron Armor
	set_cam.call(Vector3(0.0, 1.15, -2.60), Vector3(0.0, 1.10, 0.0), 1.10)
	editor.set_preview_yaw_degrees(0.0)
	await _settle(6)
	await _capture_dual("diag_female_cape_iron_front.png")

	# Female Back with Cape + Iron Armor
	editor.set_preview_yaw_degrees(180.0)
	await _settle(6)
	await _capture_dual("diag_female_cape_iron_back.png")

	# Female with Shield and Cape Back
	editor.select_part_by_id(&"shield", &"shield_heater_01")
	set_cam.call(Vector3(0.0, 1.15, -2.80), Vector3(0.0, 1.10, 0.0), 1.15)
	editor.set_preview_yaw_degrees(180.0)
	await _settle(6)
	await _capture_dual("diag_female_back_shield_cape.png")

	editor.set_preview_yaw_degrees(150.0)
	await _settle(6)
	await _capture_dual("diag_female_back_shield_cape_angle.png")

	# Female Walk with Cape + Shield
	editor.select_animation_by_id(&"walk")
	editor.set_playing(false)
	editor.animation_player.seek(0.25, true)
	editor.animation_player.advance(0.0)
	await _settle(6)
	await _capture_dual("diag_female_back_shield_cape_walk.png")

	# Female Run with Cape + Shield
	editor.select_animation_by_id(&"run")
	editor.set_playing(false)
	editor.animation_player.seek(0.30, true)
	editor.animation_player.advance(0.0)
	await _settle(6)
	await _capture_dual("diag_female_back_shield_cape_run.png")

	print("DIAGNOSTIC_CAPTURES_COMPLETED")
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
