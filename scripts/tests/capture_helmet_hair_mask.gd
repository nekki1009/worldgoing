extends "res://scripts/tests/capture_gendered_hair.gd"

const HELMETS := [&"helmet_leather_01", &"helmet_iron_01", &"helmet_steel_01", &"helmet_mingguang_01", &"helmet_chinese_leather_01"]

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	sex = args[0] if not args.is_empty() else "male"
	var stage := args[1] if args.size() > 1 else "scalp_retained"
	audit_dir = "res://.visual_captures/helmet_hair_mask/" + stage
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(audit_dir))
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 60
	editor = load("res://scenes/ui/HumanCharacter3DEditor.tscn").instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	await settle(3)
	_load_gender(sex, true)
	await settle(4)
	editor.preview_viewport.size = Vector2i(768, 960)
	editor.preview_viewport.msaa_3d = Viewport.MSAA_4X
	for slot in HumanCharacter3DEditor.PART_SLOTS:
		var value: StringName = &"face_standard_01" if slot.id == &"face" else &"outfit_underlayer_01" if slot.id == &"outfit" else &"none"
		assert(editor.select_part_by_id(slot.id, value))
	_neutral()
	var unchanged := _non_hair_materials()
	for helmet_id in HELMETS:
		assert(editor.select_part_by_id(&"helmet", helmet_id))
		for i in range(1, 9):
			assert(editor.select_part_by_id(&"hair", StringName("hair_%s_%02d" % [sex, i])))
			for mode in [&"off", &"hide", &"auto"]:
				editor.set_hair_mask_mode(mode)
				for mesh in _hair_nodes():
					assert(mesh.visible == (mode != &"hide"))
					assert(bool(mesh.get_active_material(0).get_shader_parameter("mask_enabled")) == (mode == &"auto"))
			for yaw in [0, 35, 90, 145, 180]:
				editor.set_preview_yaw_degrees(yaw)
				_hair_camera()
				await capture("%s_%02d_%s_%d" % [sex, i, helmet_id, yaw])
			if stage != "before":
				# Reference without hair: require scalp coverage behind open guards,
				# but reject detached ends below the neck and hair above the crown.
				editor.set_hair_mask_mode(&"hide")
				await capture("%s_%02d_%s_back_hidden" % [sex, i, helmet_id])
				editor.set_preview_yaw_degrees(0)
				_hair_camera()
				await capture("%s_%02d_%s_front_hidden" % [sex, i, helmet_id])
				editor.set_hair_mask_mode(&"auto")
			print("HELMET_HAIR_STYLE_PASS ", sex, " ", i, " ", helmet_id)
		if stage == "before":
			editor.set_preview_yaw_degrees(0)
			var sk := editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
			var inv_head := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("J_Bip_C_Head"))).affine_inverse()
			for node in editor._find_component_nodes(editor._component_definition(&"helmet", helmet_id).prefixes):
				if str(node.name).containsn("brow") or str(node.name).containsn("dome") or str(node.name).containsn("band") or str(node.name).containsn("shell"):
					print("HELMET_BOUNDS ", sex, " ", node.name, " ", inv_head * node.global_transform * node.get_aabb())
	if stage != "before" and not args.has("static"):
		for helmet_id in [HELMETS[0], HELMETS[3]]:
			assert(editor.select_part_by_id(&"helmet", helmet_id))
			for i in range(1, 9):
				assert(editor.select_part_by_id(&"hair", StringName("hair_%s_%02d" % [sex, i])))
				editor.set_hair_dye(Color("b9c7e6"))
				_assert_dye(true, Color("b9c7e6"))
				for clip in [&"run", &"attack_jump_heavy"]:
					assert(editor.select_animation_by_id(clip))
					editor.set_playing(false)
					for sample in 6:
						editor._on_timeline_changed(editor.animation_player.get_animation(clip).length * float(sample) / 6.0)
						editor.animation_player.advance(0)
						editor.set_preview_yaw_degrees(35 if sample % 2 == 0 else 145)
						_hair_camera()
						await capture("%s_%02d_%s_%s_%d" % [sex, i, helmet_id, clip, sample])
			editor.reset_hair_dye()
		_neutral()
		for i in range(1, 9):
			assert(editor.select_part_by_id(&"hair", StringName("hair_%s_%02d" % [sex, i])))
			editor.set_hair_dye(Color("963dcc"))
			assert(editor.select_part_by_id(&"helmet", &"none"))
			for mesh in _hair_nodes():
				assert(mesh.visible and not mesh.get_active_material(0).get_shader_parameter("mask_enabled"))
			_assert_dye(true, Color("963dcc"))
			assert(_non_hair_materials() == unchanged)
			editor.set_preview_yaw_degrees(145)
			_hair_camera()
			await capture("%s_%02d_restored" % [sex, i])
			assert(editor.select_part_by_id(&"helmet", HELMETS[0]))
	print("HELMET_HAIR_MASK_CAPTURE_PASS ", sex, " ", stage)
	editor.queue_free()
	await settle(4)
	quit(0)
