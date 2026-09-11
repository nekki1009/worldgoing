extends "res://scripts/tests/capture_chinese_leather_mingguang.gd"

const UV_DIR := "res://.visual_captures/morph_uv_repair"
var phase := ""

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(UV_DIR))
	editor = load("res://scenes/ui/HumanCharacter3DEditor.tscn").instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	await settle(4)
	for current_sex in ["male", "female"]:
		sex = current_sex
		for current_phase in ["before", "after"]:
			phase = current_phase
			var source := "res://assets/characters/human/q35/standard_anime_%s_character_pack.glb" % sex
			var horse := "res://assets/mounts/horse/standard_horse_pack.glb"
			if phase == "before":
				source = source.replace("res://", "res://.godot-temp/morph_uv_repair/baseline/")
				horse = horse.replace("res://", "res://.godot-temp/morph_uv_repair/baseline/")
			editor.set_mount_enabled(false)
			editor._load_body_model(1 if sex == "female" else 0, source)
			editor.mount_horse.setup(horse)
			await settle(5)
			editor.preview_viewport.size = Vector2i(1024, 1280)
			editor.preview_viewport.msaa_3d = Viewport.MSAA_4X
			for pair in [[&"outfit", &"outfit_underlayer_01"], [&"armor", &"armor_chinese_leather_01"], [&"helmet", &"helmet_mingguang_01"], [&"cape", &"cape_travel_01"], [&"weapon", &"none"], [&"shield", &"none"], [&"boots", &"boots_leather_01"]]:
				assert(editor.select_part_by_id(pair[0], pair[1]))
			neutral()
			# T-Pose has no cape/plume tracks: clear the previous clip's morphs.
			for mesh in editor.model_root.find_children("*", "MeshInstance3D", true, false):
				for shape in mesh.get_blend_shape_count():
					mesh.set_blend_shape_value(shape, 0.0)
			for view in [["front", 0.0], ["side", 90.0], ["back", 180.0], ["threequarter", 35.0]]:
				editor.set_preview_yaw_degrees(float(view[1]))
				frame_camera()
				await capture(str(view[0]))
			for clip in [&"run", &"attack_bow", &"ride_idle"]:
				editor.set_mount_enabled(clip == &"ride_idle")
				assert(editor.select_part_by_id(&"weapon", &"bow_01" if clip == &"attack_bow" else &"none"))
				assert(editor.select_animation_by_id(clip))
				editor.set_playing(false)
				var animation := editor.animation_player.get_animation(editor.selected_animation)
				editor.animation_player.seek(animation.length * .5, true)
				editor.animation_player.advance(0)
				editor.set_preview_yaw_degrees(35)
				frame_camera()
				await capture(str(clip))
		print("MORPH_UV_VISUAL_CAPTURE_PASS ", sex)
	editor.queue_free()
	await settle(4)
	quit(0)

func capture(filename: String) -> void:
	await settle(3)
	await RenderingServer.frame_post_draw
	assert(editor.preview_viewport.get_texture().get_image().save_png(UV_DIR + "/%s_%s_%s.png" % [sex, phase, filename]) == OK)
