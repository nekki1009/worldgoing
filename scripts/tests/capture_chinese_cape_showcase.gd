extends SceneTree

const EDITOR_SCENE: String = "res://scenes/ui/HumanCharacter3DEditor.tscn"
const LOCAL_DIR: String = "res://.visual_captures/chinese_cape_showcase"

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
	assert(scene != null, "Chinese cloak showcase could not load the editor scene")
	editor = scene.instantiate() as HumanCharacter3DEditor
	assert(editor != null, "Chinese cloak showcase got the wrong editor root type")
	root.add_child(editor)
	editor.open()
	await _settle(14)

	_capture_body(0, "male")
	await _settle(8)
	await _capture_pose_set("male")

	editor._load_body_model(1)
	await _settle(14)
	_capture_body(1, "female")
	await _settle(8)
	await _capture_pose_set("female")

	# Leave the editor on the requested new cloak option for the UI handoff image.
	editor.set_preview_yaw_degrees(35.0)
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	await _settle(4)
	await _capture("editor_chinese_cloak_selected.png")

	print("CHINESE_CAPE_SHOWCASE_CAPTURES_DONE")
	editor.queue_free()
	await _settle(4)
	quit(0)

func _capture_body(body_index: int, prefix: String) -> void:
	assert(editor.select_part_by_id(&"helmet", &"none"), "Helmet None selection failed")
	assert(editor.select_part_by_id(&"outfit", &"outfit_underlayer_01"), "Outfit selection failed")
	assert(editor.select_part_by_id(&"armor", &"armor_light_leather_01"), "Armor selection failed")
	assert(editor.select_part_by_id(&"cape", &"cape_chinese_01"), "Chinese Cloak selection failed")
	assert(editor.select_part_by_id(&"boots", &"boots_leather_01"), "Boots selection failed")
	assert(editor.select_part_by_id(&"weapon", &"none"), "Weapon None selection failed")
	assert(editor.select_part_by_id(&"shield", &"none"), "Shield None selection failed")
	assert(editor.select_animation_by_id(&"idle"), "Idle selection failed")
	editor.set_playing(false)
	editor.animation_player.seek(0.5, true)
	editor.animation_player.advance(0.0)
	editor.set_preview_yaw_degrees(0.0)

func _capture_pose_set(prefix: String) -> void:
	_set_full_body_camera()
	editor.set_preview_yaw_degrees(0.0)
	await _settle(5)
	await _capture(prefix + "_chinese_cloak_front.png")

	editor.set_preview_yaw_degrees(35.0)
	await _settle(5)
	await _capture(prefix + "_chinese_cloak_34.png")

	editor.set_preview_yaw_degrees(90.0)
	await _settle(5)
	await _capture(prefix + "_chinese_cloak_side.png")

	editor.set_preview_yaw_degrees(180.0)
	await _settle(5)
	await _capture(prefix + "_chinese_cloak_back.png")

	_set_torso_camera(prefix == "female")
	editor.set_preview_yaw_degrees(0.0)
	await _settle(5)
	await _capture(prefix + "_chinese_cloak_collar_close.png")

	editor.set_preview_yaw_degrees(35.0)
	await _settle(5)
	await _capture(prefix + "_chinese_cloak_lining_close.png")

	_set_full_body_camera()
	await _capture_animation(&"walk", 0.28, prefix + "_chinese_cloak_walk.png")
	await _capture_animation(&"run", 0.20, prefix + "_chinese_cloak_run.png")
	await _capture_animation(&"attack_jump_heavy", 0.36, prefix + "_chinese_cloak_jump_heavy.png")
	await _capture_animation(&"guard", 0.46, prefix + "_chinese_cloak_guard.png")

	if prefix == "female":
		editor.set_mount_enabled(true)
		await _settle(4)
		await _capture_animation(&"ride_slash", 0.45, prefix + "_chinese_cloak_mounted.png")
		editor.set_mount_enabled(false)
		await _settle(4)

func _capture_animation(animation_id: StringName, position: float, filename: String) -> void:
	assert(editor.select_animation_by_id(animation_id), "Animation selection failed: %s" % animation_id)
	editor.set_playing(false)
	editor.animation_player.seek(position, true)
	editor.animation_player.advance(0.0)
	await _settle(5)
	await _capture(filename)

func _set_full_body_camera() -> void:
	if editor.camera == null:
		return
	editor.camera.size = 2.05
	editor.camera.position = Vector3(0.0, 1.10, -4.55)
	editor.camera.look_at_from_position(editor.camera.position, Vector3(0.0, 0.88, 0.0), Vector3.UP)

func _set_torso_camera(is_female: bool) -> void:
	if editor.camera == null:
		return
	var center_y := 1.18 if is_female else 1.25
	editor.camera.size = 0.98
	editor.camera.position = Vector3(0.0, center_y, -2.75)
	editor.camera.look_at_from_position(editor.camera.position, Vector3(0.0, center_y - 0.03, 0.0), Vector3.UP)

func _capture(filename: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(LOCAL_DIR + "/" + filename)
	var dir_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	assert(dir_error == OK or dir_error == ERR_ALREADY_EXISTS, "Capture directory failed")
	var image := root.get_texture().get_image()
	assert(image != null and not image.is_empty(), "Chinese cloak capture was empty")
	if FileAccess.file_exists(absolute_path):
		assert(DirAccess.remove_absolute(absolute_path) == OK, "Old Chinese cloak capture could not be removed")
	assert(image.save_png(absolute_path) == OK, "Chinese cloak capture could not be saved")

func _settle(frames: int) -> void:
	for _index: int in range(frames):
		await process_frame

