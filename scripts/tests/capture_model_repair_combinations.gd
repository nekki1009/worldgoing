extends "res://scripts/tests/capture_all_model_audit.gd"

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	sex = args[0] if not args.is_empty() else "male"
	var final_assets := args.size() > 1 and args[1] == "final"
	var fit_only := args.size() > 2 and args[2] == "fit"
	audit_dir = "res://.visual_captures/all_model_repaired/combinations"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(audit_dir))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	editor = load("res://scenes/ui/HumanCharacter3DEditor.tscn").instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	await settle(4)
	editor._load_body_model(1 if sex == "female" else 0,"" if final_assets else "res://assets/characters/human/q35/audit_repair/candidate_%s.glb" % sex)
	if not final_assets: editor.mount_horse.setup("res://assets/characters/human/q35/audit_repair/candidate_horse.glb")
	await settle(6)
	editor.preview_viewport.size = Vector2i(1024,1280)
	var looks := [
		[&"armor_light_leather_01",&"helmet_leather_01",&"boots_leather_01",&"cape_travel_01"],
		[&"armor_iron_01",&"helmet_iron_01",&"boots_iron_01",&"cape_travel_01"],
		[&"armor_mingguang_01",&"helmet_mingguang_01",&"boots_mingguang_01",&"cape_chinese_01"],
		[&"armor_chinese_leather_01",&"helmet_chinese_leather_01",&"boots_chinese_leather_01",&"cape_chinese_01"],
	]
	for index in looks.size():
		if fit_only and index != 3: continue
		for pair in [[&"face",&"face_standard_01"],[&"hair",&"hair_short_01"],[&"armor",looks[index][0]],[&"helmet",looks[index][1]],[&"boots",looks[index][2]],[&"cape",looks[index][3]],[&"weapon",&"none"],[&"shield",&"none"]]:
			assert(editor.select_part_by_id(pair[0],pair[1]))
		for lining in [&"outfit_underlayer_01",&"outfit_chinese_lining_01"]:
			assert(editor.select_part_by_id(&"outfit",lining))
			for clip in [&"idle",&"walk",&"run",&"guard",&"hit",&"knockback",&"attack_jump_heavy",&"ride_run",&"ride_slash"]:
				if fit_only and clip != &"idle": continue
				editor.set_mount_enabled(str(clip).begins_with("ride_"))
				assert(editor.select_animation_by_id(clip))
				editor.set_playing(false)
				var animation := editor.animation_player.get_animation(editor.selected_animation)
				for sample in 8:
					editor._on_timeline_changed(animation.length*float(sample)/8.0)
					editor.animation_player.advance(0.0)
					editor.set_preview_yaw_degrees(35 if sample%2 == 0 else 145)
					frame_camera(false,editor.is_mounted)
					if not editor.is_mounted: editor.camera.size = 2.65
					await capture("%s_set%d_%s_%s_%d" % [sex,index,lining,clip,sample])
					if editor.is_mounted: assert(editor.mount_horse.contact_error < 0.001)
		print("REPAIR_COMBINATIONS_SET_DONE ",sex," ",index)
	editor.set_mount_enabled(false)
	for helmet in [&"helmet_leather_01",&"helmet_iron_01",&"helmet_steel_01",&"helmet_mingguang_01",&"helmet_chinese_leather_01"]:
		assert(editor.select_part_by_id(&"helmet",helmet))
		for hair in [&"hair_short_01",&"hair_short_02",&"hair_short_03",&"hair_short_04"]:
			assert(editor.select_part_by_id(&"hair",hair))
			assert(editor.select_animation_by_id(&"idle"))
			editor.set_playing(false)
			for yaw in [35,145]:
				editor.set_preview_yaw_degrees(yaw)
				audit_camera("helmet")
				await capture("%s_fit_%s_%s_%d" % [sex,helmet,hair,yaw])
	for mode in [&"off",&"hide",&"auto"]:
		editor.set_hair_mask_mode(mode)
		for hair_node in editor._find_component_nodes(editor._component_definition(&"hair",&"hair_short_04").get("prefixes",[])):
			if not hair_node is MeshInstance3D: continue
			assert(hair_node.visible == (mode != &"hide"),"Hair visibility mode")
			for surface in hair_node.mesh.get_surface_count():
				var material := hair_node.get_active_material(surface) as ShaderMaterial
				assert(material != null and bool(material.get_shader_parameter("mask_enabled")) == (mode == &"auto"),"Hair clipping mode")
	assert(editor.select_part_by_id(&"helmet",&"none"))
	for hair_node in editor._find_component_nodes(editor._component_definition(&"hair",&"hair_short_04").get("prefixes",[])):
		if hair_node is MeshInstance3D:
			assert(hair_node.visible and not hair_node.get_active_material(0).get_shader_parameter("mask_enabled"),"Unequip restores complete hair")
	print("MODEL_REPAIR_COMBINATIONS_DONE ",sex)
	editor.queue_free()
	await settle(4)
	quit(0)
