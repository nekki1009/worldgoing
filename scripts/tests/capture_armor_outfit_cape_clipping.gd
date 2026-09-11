extends SceneTree

const EDITOR_SCENE: String = "res://scenes/ui/HumanCharacter3DEditor.tscn"
const ARTIFACT_DIR: String = "C:/Users/Nekki/.gemini/antigravity/brain/6751ce0d-7d56-4cae-8c5b-9f20717bdb83"
const LOCAL_DIR: String = "res://.visual_captures/outfit_cape_clipping"

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

	# =========================================================================
	# 1. Male with Outfit + Armor Iron + Cape Travel
	# =========================================================================
	editor._load_body_model(0) # Male
	await _settle(10)
	editor.select_part_by_id(&"helmet", &"none")
	editor.select_part_by_id(&"outfit", &"outfit_underlayer_01")
	editor.select_part_by_id(&"armor", &"armor_iron_01")
	editor.select_part_by_id(&"cape", &"cape_travel_01")
	editor.select_part_by_id(&"boots", &"boots_iron_01")
	editor.select_part_by_id(&"weapon", &"none")
	editor.select_part_by_id(&"shield", &"none")
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	editor.animation_player.seek(0.5, true)
	editor.animation_player.advance(0.0)

	# Male Front
	set_full_body_cam.call()
	editor.set_preview_yaw_degrees(0.0)
	await _settle(6)
	await _capture_dual("male_outfit_armor_cape_front.png")

	# Male Back
	editor.set_preview_yaw_degrees(180.0)
	await _settle(6)
	await _capture_dual("male_outfit_armor_cape_back.png")

	# Male 3/4
	editor.set_preview_yaw_degrees(35.0)
	await _settle(6)
	await _capture_dual("male_outfit_armor_cape_34.png")

	# Male Torso Front Close-up
	set_torso_cam.call(false)
	editor.set_preview_yaw_degrees(0.0)
	await _settle(6)
	await _capture_dual("male_torso_front_outfit_cape.png")

	# Male Torso Back Close-up
	editor.set_preview_yaw_degrees(180.0)
	await _settle(6)
	await _capture_dual("male_torso_back_outfit_cape.png")

	# =========================================================================
	# 2. Female with Outfit + Armor Iron + Cape Travel
	# =========================================================================
	editor._load_body_model(1) # Female
	await _settle(10)
	editor.select_part_by_id(&"helmet", &"none")
	editor.select_part_by_id(&"outfit", &"outfit_underlayer_01")
	editor.select_part_by_id(&"armor", &"armor_iron_01")
	editor.select_part_by_id(&"cape", &"cape_travel_01")
	editor.select_part_by_id(&"boots", &"boots_iron_01")
	editor.select_part_by_id(&"weapon", &"none")
	editor.select_part_by_id(&"shield", &"none")
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	editor.animation_player.seek(0.5, true)
	editor.animation_player.advance(0.0)

	# Female Front
	set_full_body_cam.call()
	editor.set_preview_yaw_degrees(0.0)
	await _settle(6)
	await _capture_dual("female_outfit_armor_cape_front.png")

	# Female Back
	editor.set_preview_yaw_degrees(180.0)
	await _settle(6)
	await _capture_dual("female_outfit_armor_cape_back.png")

	# Female Torso Front Close-up
	set_torso_cam.call(true)
	editor.set_preview_yaw_degrees(0.0)
	await _settle(6)
	await _capture_dual("female_torso_front_outfit_cape.png")

	# Female Torso Back Close-up
	editor.set_preview_yaw_degrees(180.0)
	await _settle(6)
	await _capture_dual("female_torso_back_outfit_cape.png")

	print("OUTFIT_CAPE_CLIPPING_CAPTURES_DONE")
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
