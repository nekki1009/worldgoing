extends "res://scripts/tests/capture_medieval_shoes.gd"
## Supplement skirt-occluded frames with the same shoes on exposed ankles.

func _run() -> void:
	sex = OS.get_cmdline_user_args()[0]
	destination = SHOE_OUT+"/ankles"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination))
	DisplayServer.window_set_size(Vector2i(1280,900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	editor = load("res://scenes/ui/HumanCharacter3DEditor.tscn").instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	await settle(3)
	editor._load_body_model(1 if sex=="female" else 0)
	await settle(3)
	editor.preview_viewport.size = Vector2i(1024,1024)
	editor.preview_viewport.msaa_3d = Viewport.MSAA_4X
	for slot in [&"armor",&"helmet",&"cape",&"weapon",&"shield"]:
		assert(editor.select_part_by_id(slot,&"none"))
	for style: String in STYLES:
		assert(editor.select_part_by_id(&"boots",StringName("boots_medieval_"+style+"_01")))
		for clip in [&"run", &"attack_jump_heavy"]:
			assert(editor.select_animation_by_id(clip))
			editor.set_playing(false)
			var animation := editor.animation_player.get_animation(editor.selected_animation)
			for sample in range(17):
				editor.animation_player.seek(animation.length*float(sample)/16.0,true)
				editor.animation_player.advance(0)
				editor.set_preview_yaw_degrees(35)
				shoe_camera(true)
				await capture("%s_%s_%s_%02d" % [sex,style,clip,sample])
	editor.queue_free()
	await settle(3)
	print("MEDIEVAL_SHOE_ANKLES_PASS ",sex)
	quit(0)
