extends "res://scripts/tests/capture_all_model_audit.gd"

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	sex = args[0] if not args.is_empty() else "male"
	audit_dir = "res://.visual_captures/all_model_repaired/weapon_cycles"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(audit_dir))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	editor = load("res://scenes/ui/HumanCharacter3DEditor.tscn").instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	await settle(4)
	if args.size() > 1 and args[1] == "candidate":
		editor._load_body_model(1 if sex == "female" else 0,"res://assets/characters/human/q35/audit_repair/candidate_%s.glb" % sex)
	else:
		editor._load_body_model(1 if sex == "female" else 0)
	await settle(4)
	editor.preview_viewport.size = Vector2i(1024,1280)
	var timing := {}
	for pair in [[&"outfit",&"outfit_underlayer_01"],[&"armor",&"armor_light_leather_01"],[&"helmet",&"none"],[&"cape",&"none"],[&"boots",&"boots_leather_01"],[&"shield",&"none"]]:
		assert(editor.select_part_by_id(pair[0],pair[1]))
	for weapon in [&"longsword_01",&"spear_01",&"axe_01",&"hammer_01",&"dagger_01",&"bow_01",&"crossbow_01"]:
		assert(editor.select_part_by_id(&"weapon",weapon))
		assert(editor.select_animation_by_id(HumanCharacter3DEditor.WEAPON_ATTACK_MAP[weapon]))
		editor.set_playing(false)
		var animation := editor.animation_player.get_animation(editor.selected_animation)
		timing[String(weapon)] = animation.length
		for sample in 24:
			editor.animation_player.seek(animation.length*float(sample)/24.0,true)
			editor.animation_player.advance(0.0)
			editor.set_preview_yaw_degrees(35)
			editor.camera.size = 3.6 if weapon == &"spear_01" else 2.9
			editor.camera.position = Vector3(0,1.1,-5)
			editor.camera.look_at(Vector3(0,1.1,0))
			await capture("%s_%s_%02d" % [sex,weapon,sample])
	var timing_file := FileAccess.open(audit_dir + "/%s_timing.json" % sex,FileAccess.WRITE)
	timing_file.store_string(JSON.stringify(timing,"  "))
	timing_file.close()
	print("REPAIRED_WEAPON_CYCLES_DONE ",sex)
	editor.queue_free()
	await settle(4)
	quit(0)
