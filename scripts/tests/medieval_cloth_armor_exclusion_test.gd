extends "res://scripts/tests/capture_medieval_cloth.gd"

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	sex = args[0] if not args.is_empty() else "female"
	CLOTH_OUT = "res://output/medieval_cloth_armor_20260916/final"
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	editor = load("res://scenes/ui/HumanCharacter3DEditor.tscn").instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	await settle(4)
	var gender := 1 if sex == "female" else 0
	editor._load_body_model(gender) # Formal pack, never the unfinished fitting candidate.
	await settle(6)
	editor.preview_viewport.size = Vector2i(1024, 1280)
	editor.preview_viewport.msaa_3d = Viewport.MSAA_4X
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CLOTH_OUT))
	for slot in [&"armor", &"helmet", &"boots", &"cape", &"weapon", &"shield"]:
		assert(editor.select_part_by_id(slot, &"none"))
	assert(editor.select_part_by_id(&"outfit", &"outfit_underlayer_01"))
	var body := editor.model_root.find_child("Body_Standard_Female" if gender == 1 else "Body_Standard_Male", true, false) as MeshInstance3D
	var original_body := body.mesh
	var under_bottom := editor.model_root.find_child("Outfit_Underlayer_01_UnderwearBottom", true, false) as MeshInstance3D
	assert(under_bottom != null)
	for style: String in STYLES:
		var outfit_id := StringName("outfit_medieval_" + style + "_01")
		assert(not editor.select_part_by_id(&"outfit", outfit_id), "Cloth armor remains in underwear slot")
		assert(editor._component_definition(&"armor", outfit_id).category == &"cloth")
		assert(editor.select_part_by_id(&"armor", outfit_id))
		var prefix := "Outfit_Medieval_" + style.capitalize() + "_01_"
		var skirt := editor.model_root.find_child(prefix + ("Skirt" if gender == 1 else "TunicSkirt"), true, false) as MeshInstance3D
		var shirt := editor.model_root.find_child(prefix + "Shirt", true, false) as MeshInstance3D
		assert(skirt != null and skirt.visible and shirt.visible and not under_bottom.visible)
		var skirt_body := body.mesh
		for palette: String in Dye.PRESETS:
			assert(editor.set_equipment_dyes({"armor": Dye.PRESETS[palette].colors.armor}))
			assert(editor.capture_appearance().equipment_dyes.armor == Dye.PRESETS[palette].colors.armor)
		assert(editor.set_equipment_dyes({"armor": "27ab83ff"}))
		neutral()
		editor.set_preview_yaw_degrees(35)
		frame_camera()
		await capture(sex + "_" + style + "_before")
		var before := editor.preview_viewport.get_texture().get_image().get_data()
		var armor_materials: Array[ShaderMaterial] = []
		for entry: Dictionary in editor._equipment_dye_surfaces:
			if str(entry.node.name).begins_with(prefix):
				assert(entry.slot == "armor")
				armor_materials.append(entry.node.get_active_material(entry.surface) as ShaderMaterial)
		assert(not armor_materials.is_empty())
		var armor_color: Variant = armor_materials[0].get_shader_parameter("equipment_dye_color")
		assert(editor.set_equipment_dyes({"armor": "27ab83ff", "outfit": "e43a29ff"}))
		for material in armor_materials: assert(material.get_shader_parameter("equipment_dye_color") == armor_color, "Underwear dye leaked into cloth armor")
		assert(editor.set_equipment_dyes({"armor": "27ab83ff"}))
		var saved_cloth := editor.capture_appearance()
		assert(saved_cloth.parts.armor == str(outfit_id) and saved_cloth.parts.outfit == "outfit_underlayer_01")
		assert(editor.restore_appearance(JSON.parse_string(JSON.stringify(saved_cloth))))
		assert(skirt.visible and shirt.visible and editor.capture_appearance() == saved_cloth)
		for inner: StringName in [&"outfit_underlayer_01", &"outfit_chinese_lining_01", &"none"]:
			assert(editor.select_part_by_id(&"outfit", inner))
			assert(skirt.visible and shirt.visible and editor.capture_appearance().parts.armor == str(outfit_id))
			assert(editor.select_part_by_id(&"armor", &"none"))
			assert(not skirt.visible and not shirt.visible)
			if inner == &"outfit_chinese_lining_01":
				assert((editor.model_root.find_child("Outfit_Chinese_Lining_01_Shirt", true, false) as MeshInstance3D).visible)
			else: assert(body.mesh == original_body)
			assert(editor.select_part_by_id(&"armor", outfit_id))
		assert(editor.select_part_by_id(&"outfit", &"outfit_underlayer_01"))
		assert(editor.set_equipment_dyes({"armor": "27ab83ff"}))
		for armor: StringName in [&"armor_light_leather_01", &"armor_iron_01", &"armor_mingguang_01", &"armor_chinese_leather_01", &"armor_western_iron_01"]:
			assert(editor.select_part_by_id(&"armor", armor))
			for node in editor.model_root.find_children("Outfit_Medieval_*", "MeshInstance3D", true, false): assert(not node.visible)
			assert(under_bottom.visible and body.mesh == original_body)
			# Outfit-after-armor and armor-after-outfit use the same shared rule.
			assert(editor.select_part_by_id(&"outfit", &"none"))
			assert(body.mesh == original_body and not under_bottom.visible)
			assert(editor.select_part_by_id(&"outfit", &"outfit_underlayer_01"))
			assert(editor.set_equipment_dyes({"armor": "27ab83ff"}))
			assert(not skirt.visible and not shirt.visible and under_bottom.visible)
			var saved := editor.capture_appearance()
			assert(editor.restore_appearance(JSON.parse_string(JSON.stringify(saved))))
			assert(not skirt.visible and not shirt.visible and editor.capture_appearance() == saved)
			for clip: StringName in [&"idle", &"run", &"attack_crossbow"]:
				assert(editor.select_animation_by_id(clip))
				editor.set_playing(false)
				var duration := editor.animation_player.get_animation(editor.selected_animation).length
				for fraction in [.25, .75]:
					editor.animation_player.seek(duration * fraction, true)
					assert(not skirt.visible and not shirt.visible)
					for yaw in [35.0, 145.0]:
						editor.set_preview_yaw_degrees(yaw)
						frame_camera()
						await capture("%s_%s_%s_%s_%d_%d" % [sex, style, armor, clip, int(fraction*100), int(yaw)])
			assert(editor.select_part_by_id(&"armor", &"none"))
			assert(not skirt.visible and not shirt.visible and body.mesh == original_body)
			assert(editor.select_part_by_id(&"armor", outfit_id))
			assert(editor.set_equipment_dyes({"armor": "27ab83ff"}))
			assert(skirt.visible and shirt.visible and not under_bottom.visible and body.mesh == skirt_body)
		neutral()
		editor.set_preview_yaw_degrees(35)
		frame_camera()
		await capture(sex + "_" + style + "_restored")
		assert(before == editor.preview_viewport.get_texture().get_image().get_data(), "Removing armor did not restore exact cloth pixels")
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(CLOTH_OUT+"/"+sex+"_"+style+"_editor.png") == OK)
		assert(editor.select_part_by_id(&"armor", &"none"))
		for original: StringName in [&"outfit_underlayer_01", &"outfit_chinese_lining_01", &"none"]:
			assert(editor.select_part_by_id(&"outfit", original))
			assert(under_bottom.visible == (original == &"outfit_underlayer_01"))
			for node in editor.model_root.find_children("Outfit_Medieval_*", "MeshInstance3D", true, false):
				assert(not node.visible)
			if original != &"outfit_chinese_lining_01": assert(body.mesh == original_body)
		assert(editor.select_part_by_id(&"outfit", &"outfit_underlayer_01"))
		print("CLOTH_ARMOR_STYLE_PASS ", sex, " ", style, " five exclusive armors; independent underwear; save-load; 16 armor presets; exact restore")
	editor.queue_free()
	await settle(3)
	print("MEDIEVAL_CLOTH_ARMOR_SLOT_PASS ", sex)
	quit(0)
