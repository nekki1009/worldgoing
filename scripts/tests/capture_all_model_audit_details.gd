extends "res://scripts/tests/capture_all_model_audit.gd"

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): sex = args[0]
	if args.size() > 1: audit_dir = "res://.visual_captures/all_model_repaired"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(audit_dir))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	editor = load("res://scenes/ui/HumanCharacter3DEditor.tscn").instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	await settle(4)
	if args.size() > 1 and args[1] != "final":
		editor._load_body_model(1 if sex == "female" else 0,"res://assets/characters/human/q35/audit_repair/candidate_%s.glb" % sex)
		if FileAccess.file_exists("res://assets/characters/human/q35/audit_repair/candidate_horse.glb"):
			editor.mount_horse.setup("res://assets/characters/human/q35/audit_repair/candidate_horse.glb")
	else:
		editor._load_body_model(1 if sex == "female" else 0)
	await settle(8)
	editor.preview_viewport.size = Vector2i(1024,1280)
	for slot in HumanCharacter3DEditor.PART_SLOTS:
		var value: StringName = &"none"
		if slot.id == &"face": value = &"face_standard_01"
		if slot.id == &"hair": value = &"hair_short_01"
		if slot.id == &"outfit": value = &"outfit_underlayer_01"
		assert(editor.select_part_by_id(slot.id,value))
	for weapon in [&"longsword_01",&"spear_01",&"axe_01",&"hammer_01",&"dagger_01",&"bow_01",&"crossbow_01",&"none"]:
		assert(editor.select_part_by_id(&"weapon",weapon))
		assert(editor.select_part_by_id(&"shield",&"shield_heater_01" if weapon == &"none" else &"none"))
		var clip: StringName = &"guard" if weapon == &"none" else HumanCharacter3DEditor.WEAPON_ATTACK_MAP[weapon]
		assert(editor.select_animation_by_id(clip))
		editor.set_playing(false)
		var animation := editor.animation_player.get_animation(editor.selected_animation)
		for sample in 3:
			editor.animation_player.seek(animation.length * (0.25 + 0.25*sample),true)
			editor.animation_player.advance(0.0)
			editor.set_preview_yaw_degrees(65)
			var center := Vector3(0,1.25,0)
			editor.camera.size = 2.0 if weapon == &"spear_01" else 1.5
			editor.camera.position = center + Vector3(0,0,-5)
			editor.camera.look_at(center)
			await capture("%s_detail_%s_%d" % [sex,weapon,sample])
	assert(editor.select_part_by_id(&"weapon",&"none"))
	assert(editor.select_part_by_id(&"shield",&"none"))
	editor.set_mount_enabled(true)
	for coat in [&"bay",&"chestnut",&"black",&"white"]:
		editor.set_mount_coat(coat)
		for tack in [true,false]:
			editor.set_mount_tack_enabled(tack)
			assert(editor.select_animation_by_id(&"ride_run"))
			editor.set_playing(false)
			for sample in 3:
				editor._on_timeline_changed(0.15+float(sample)*0.2)
				editor.animation_player.advance(0.0)
				editor.set_preview_yaw_degrees(90.0 if sample == 0 else (35.0 if sample == 1 else 180.0))
				frame_camera(false,true)
				await capture("%s_mount_%s_%s_%d" % [sex,coat,str(tack),sample])
	print("AUDIT_DETAILS_DONE ",sex)
	editor.queue_free()
	await settle(4)
	quit(0)
