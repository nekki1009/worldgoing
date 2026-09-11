extends SceneTree

const EDITOR_SCENE: String = "res://scenes/ui/HumanCharacter3DEditor.tscn"
const ARTIFACT_DIR: String = "C:/Users/Nekki/.gemini/antigravity/brain/6751ce0d-7d56-4cae-8c5b-9f20717bdb83"
const LOCAL_DIR: String = "res://.visual_captures/mount_showcase"

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
	await _settle(12)

	# 1. Male on Bay horse, ride_walk, 35 deg angle
	editor._load_body_model(0)
	editor.set_mount_enabled(true)
	editor.set_mount_coat(&"bay")
	editor.set_mount_tack_enabled(true)
	editor.select_animation_by_id(&"ride_walk")
	editor.set_playing(false)
	editor.animation_player.seek(0.35, true)
	editor._sync_mount_animation()
	editor.set_preview_yaw_degrees(35.0)
	await _settle(6)
	await _capture_dual("mount_showcase_male_bay_walk_34.png")

	# 2. Male on Bay horse, ride_run (10x rapid stride), 90 deg side angle
	editor.select_animation_by_id(&"ride_run")
	editor.animation_player.seek(0.15, true)
	editor._sync_mount_animation()
	editor.set_preview_yaw_degrees(90.0)
	await _settle(6)
	await _capture_dual("mount_showcase_male_run_side.png")

	# 3. Male on Bay horse, ride_run (10x rapid stride), 35 deg 3/4 angle
	editor.set_preview_yaw_degrees(35.0)
	await _settle(6)
	await _capture_dual("mount_showcase_male_run_34.png")

	# 4. Male on Chestnut horse, ride_slash (Wind-up chamber high over shoulder)
	editor.set_mount_coat(&"chestnut")
	editor.select_part_by_id(&"weapon", &"longsword_01")
	editor.select_animation_by_id(&"ride_slash")
	editor.animation_player.seek(0.58, true)  # Frame 14: Cocked high over right shoulder
	editor._sync_mount_animation()
	editor.set_preview_yaw_degrees(25.0)
	await _settle(6)
	await _capture_dual("mount_showcase_male_attack_cocked.png")

	# 5. Male on Chestnut horse, ride_slash (Downward cleave along right flank)
	editor.animation_player.seek(0.96, true)  # Frame 23: Downward cleave impact
	editor._sync_mount_animation()
	editor.set_preview_yaw_degrees(45.0)
	await _settle(6)
	await _capture_dual("mount_showcase_male_attack_impact.png")

	# 5b. Male on Chestnut horse, ride_slash (Full follow-through "做完")
	editor.animation_player.seek(1.17, true)  # Frame 28: Follow-through swept past knee
	editor._sync_mount_animation()
	editor.set_preview_yaw_degrees(45.0)
	await _settle(6)
	await _capture_dual("mount_showcase_male_attack_followthrough.png")

	# 6. Female on White horse, ride_run (10x rapid stride), 35 deg angle
	editor._load_body_model(1)
	editor.set_mount_enabled(true)
	editor.set_mount_coat(&"white")
	editor.set_mount_tack_enabled(true)
	editor.select_animation_by_id(&"ride_run")
	editor.set_playing(false)
	editor.animation_player.seek(0.15, true)
	editor._sync_mount_animation()
	editor.set_preview_yaw_degrees(35.0)
	await _settle(6)
	await _capture_dual("mount_showcase_female_run_34.png")

	# 7. Female on Black horse, ride_slash (Downward cleave along right flank)
	editor.set_mount_coat(&"black")
	editor.select_part_by_id(&"weapon", &"longsword_01")
	editor.select_animation_by_id(&"ride_slash")
	editor.animation_player.seek(0.96, true)
	editor._sync_mount_animation()
	editor.set_preview_yaw_degrees(45.0)
	await _settle(6)
	await _capture_dual("mount_showcase_female_attack_impact.png")

	# 7b. Female on Black horse, ride_slash (Full follow-through "做完")
	editor.animation_player.seek(1.17, true)
	editor._sync_mount_animation()
	editor.set_preview_yaw_degrees(45.0)
	await _settle(6)
	await _capture_dual("mount_showcase_female_attack_followthrough.png")

	# 7c. Male on Bay horse, ride_thrust with spear (Chamber pull-back)
	editor._load_body_model(0)
	editor.set_mount_enabled(true)
	editor.set_mount_coat(&"bay")
	editor.select_part_by_id(&"weapon", &"spear_01")
	editor.select_animation_by_id(&"ride_thrust")
	editor.animation_player.seek(0.58, true)
	editor._sync_mount_animation()
	editor.set_preview_yaw_degrees(35.0)
	await _settle(6)
	await _capture_dual("mount_showcase_male_spear_chamber.png")

	# 7d. Male on Bay horse, ride_thrust with spear (Explosive thrust forward)
	editor.animation_player.seek(0.96, true)
	editor._sync_mount_animation()
	editor.set_preview_yaw_degrees(35.0)
	await _settle(6)
	await _capture_dual("mount_showcase_male_spear_thrust.png")

	# 7e. Female on Black horse, ride_thrust with spear (Explosive thrust forward)
	editor._load_body_model(1)
	editor.set_mount_enabled(true)
	editor.set_mount_coat(&"black")
	editor.select_part_by_id(&"weapon", &"spear_01")
	editor.select_animation_by_id(&"ride_thrust")
	editor.animation_player.seek(0.96, true)
	editor._sync_mount_animation()
	editor.set_preview_yaw_degrees(35.0)
	await _settle(6)
	await _capture_dual("mount_showcase_female_spear_thrust.png")

	# 8. Male on foot, walk_slash (Standing Melee Combo Ver. 3 Strike 1)
	editor._load_body_model(0)
	editor.select_part_by_id(&"weapon", &"longsword_01")
	editor.select_animation_by_id(&"walk_slash")
	editor.set_playing(false)
	editor.animation_player.seek(0.80, true)
	editor.set_preview_yaw_degrees(35.0)
	await _settle(6)
	await _capture_dual("walk_slash_male_strike1.png")

	# 9. Male on foot, walk_slash (Standing Melee Combo Ver. 3 Strike 2)
	editor.animation_player.seek(1.80, true)
	editor.set_preview_yaw_degrees(30.0)
	await _settle(6)
	await _capture_dual("walk_slash_male_strike2.png")

	# 10. Female on foot, walk_slash (Standing Melee Combo Ver. 3 Strike 1)
	editor._load_body_model(1)
	editor.select_part_by_id(&"weapon", &"longsword_01")
	editor.select_animation_by_id(&"walk_slash")
	editor.set_playing(false)
	editor.animation_player.seek(0.80, true)
	editor.set_preview_yaw_degrees(35.0)
	await _settle(6)
	await _capture_dual("walk_slash_female_strike1.png")

	# 11. Entire UI with ride_slash & mount controls active
	editor.set_mount_enabled(true)
	editor.select_animation_by_id(&"ride_slash")
	editor.animation_player.seek(0.96, true)
	editor._sync_mount_animation()
	editor.set_preview_yaw_degrees(40.0)
	await _settle(6)
	await _capture_dual("mount_showcase_editor_ui.png")

	print("MOUNT_SHOWCASE_CAPTURES_DONE")
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
