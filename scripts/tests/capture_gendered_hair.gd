extends "res://scripts/tests/capture_all_model_audit.gd"

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	sex = args[0] if not args.is_empty() else "male"
	var final_assets := args.size() > 1 and args[1] == "final"
	var quick := args.has("quick")
	audit_dir = "res://.visual_captures/hair_gendered/" + ("final" if final_assets else "candidate")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(audit_dir))
	DisplayServer.window_set_size(Vector2i(1600,1000))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 60
	editor = load("res://scenes/ui/HumanCharacter3DEditor.tscn").instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	await settle(3)
	_load_gender(sex,final_assets)
	await settle(4)
	editor.preview_viewport.size = Vector2i(768,960)
	editor.preview_viewport.msaa_3d = Viewport.MSAA_4X
	for slot in HumanCharacter3DEditor.PART_SLOTS:
		var value: StringName = &"face_standard_01" if slot.id == &"face" else &"outfit_underlayer_01" if slot.id == &"outfit" else &"none"
		assert(editor.select_part_by_id(slot.id,value))
	var options := editor.part_options[&"hair"] as OptionButton
	assert(options.item_count == 9,"Eight actual styles plus None")
	for i in options.item_count: assert(not options.is_item_disabled(i),"Missing hairstyle geometry")
	assert(not editor.select_part_by_id(&"hair",StringName("hair_%s_01" % ("male" if sex == "female" else "female"))),"Other gender ID must be rejected")
	var unchanged := _non_hair_materials()
	var colors := [Color("b9c7e6"),Color("963dcc")]
	for i in range(1,9):
		var hair_id := StringName("hair_%s_%02d" % [sex,i])
		assert(editor.select_part_by_id(&"hair",hair_id))
		_assert_only_hair(hair_id)
		editor.reset_hair_dye()
		_neutral()
		for view in [["front",0.0],["side",90.0],["back",180.0],["threequarter",35.0]]:
			editor.set_preview_yaw_degrees(view[1])
			_hair_camera()
			await capture("%s_%02d_%s" % [sex,i,view[0]])
		editor.set_preview_yaw_degrees(0)
		_hair_camera()
		for color_index in colors.size():
			editor.set_hair_dye(colors[color_index])
			_assert_dye(true,colors[color_index])
			assert(_non_hair_materials() == unchanged,"Dye must not alter face, skin, clothes or equipment")
			await capture("%s_%02d_dye%d" % [sex,i,color_index])
		# The actual picker callback and programmatic path use the same setter.
		editor.hair_dye_button.color_changed.emit(colors[0])
		_assert_dye(true,colors[0])
		assert(editor.select_part_by_id(&"hair",&"none"))
		for mesh in editor.model_root.find_children("Hair_*","MeshInstance3D",true,false): assert(not mesh.visible,"None left a hair fragment")
		assert(editor.select_part_by_id(&"hair",hair_id))
		_assert_dye(true,colors[0])
		editor.reset_hair_dye()
		_assert_dye(false,colors[0])
		print("GENDERED_HAIR_STYLE_PASS ",hair_id)
	if not quick:
		for helmet_id in [&"helmet_leather_01",&"helmet_iron_01",&"helmet_steel_01",&"helmet_mingguang_01",&"helmet_chinese_leather_01"]:
			assert(editor.select_part_by_id(&"helmet",helmet_id))
			for i in range(1,9):
				assert(editor.select_part_by_id(&"hair",StringName("hair_%s_%02d" % [sex,i])))
				for mask_mode in [&"off",&"hide",&"auto"]:
					editor.set_hair_mask_mode(mask_mode)
					for mesh in _hair_nodes():
						assert(mesh.visible == (mask_mode != &"hide"))
						for surface in mesh.mesh.get_surface_count():
							assert(bool(mesh.get_active_material(surface).get_shader_parameter("mask_enabled")) == (mask_mode == &"auto"))
				for yaw in [35,145]:
					editor.set_preview_yaw_degrees(yaw)
					_hair_camera()
					await capture("%s_%02d_%s_%d" % [sex,i,helmet_id,yaw])
		assert(editor.select_part_by_id(&"helmet",&"none"))
		for i in range(1,9):
			assert(editor.select_part_by_id(&"hair",StringName("hair_%s_%02d" % [sex,i])))
			for mesh in _hair_nodes():
				assert(mesh.visible and not mesh.get_active_material(0).get_shader_parameter("mask_enabled"),"Unequipping restores hair")
			for clip in [&"idle",&"walk",&"run",&"attack_jump_heavy"]:
				assert(editor.select_animation_by_id(clip))
				editor.set_playing(false)
				var animation := editor.animation_player.get_animation(editor.selected_animation)
				for sample in 6:
					editor._on_timeline_changed(animation.length*float(sample)/6.0)
					editor.animation_player.advance(0)
					editor.set_preview_yaw_degrees(35 if sample%2 == 0 else 145)
					_hair_camera()
					await capture("%s_%02d_%s_%d" % [sex,i,clip,sample])
		# Fixed-view complete run cycles for the new silhouettes and long ends.
		for i in range(5,9):
			assert(editor.select_part_by_id(&"hair",StringName("hair_%s_%02d" % [sex,i])))
			assert(editor.select_animation_by_id(&"run"))
			editor.set_playing(false)
			editor.set_preview_yaw_degrees(145)
			var run_length := editor.animation_player.get_animation(&"run").length
			for sample in 24:
				editor._on_timeline_changed(run_length*float(sample)/24.0)
				editor.animation_player.advance(0)
				_hair_camera()
				await capture("%s_%02d_cycle_run_%02d" % [sex,i,sample])
		# Focused complete-equipment checks for the new long styles.
		for pair in [[&"outfit",&"outfit_chinese_lining_01"],[&"armor",&"armor_chinese_leather_01"],[&"cape",&"cape_chinese_01"]]:
			assert(editor.select_part_by_id(pair[0],pair[1]))
		for i in [7,8]:
			assert(editor.select_part_by_id(&"hair",StringName("hair_%s_%02d" % [sex,i])))
			for clip in [&"idle",&"run"]:
				assert(editor.select_animation_by_id(clip))
				editor.set_playing(false)
				for sample in 6:
					editor._on_timeline_changed(editor.animation_player.get_animation(clip).length*float(sample)/6.0)
					editor.animation_player.advance(0)
					editor.set_preview_yaw_degrees(35 if sample%2 == 0 else 145)
					_hair_camera()
					await capture("%s_%02d_equipped_%s_%d" % [sex,i,clip,sample])
	# Remember independent gender choices while keeping the current dye.
	assert(editor.select_part_by_id(&"hair",StringName("hair_%s_07" % sex)))
	editor.set_hair_dye(colors[1])
	var other := "male" if sex == "female" else "female"
	_load_gender(other,final_assets)
	assert(editor.select_part_by_id(&"hair",StringName("hair_%s_06" % other)))
	_assert_dye(true,colors[1])
	_load_gender(sex,final_assets)
	assert(editor.part_options[&"hair"].get_item_metadata(editor.part_options[&"hair"].selected) == StringName("hair_%s_07" % sex))
	_assert_dye(true,colors[1])
	for slot_id in [&"helmet",&"weapon",&"shield",&"cape"]:
		assert(editor.select_part_by_id(slot_id,&"none"))
	_neutral()
	editor.set_preview_yaw_degrees(35)
	_hair_camera()
	await capture(sex+"_selection_restored")
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(audit_dir+"/"+sex+"_editor_ui.png") == OK)
	print("GENDERED_HAIR_EDITOR_PASS ",sex," quick=",quick)
	editor.queue_free()
	await settle(4)
	quit(0)

func _load_gender(value: String, final_assets: bool) -> void:
	editor._load_body_model(1 if value == "female" else 0,"" if final_assets else "res://assets/characters/human/q35/hair_gendered/candidate_%s.glb" % value)

func _hair_camera() -> void:
	# A fixed world-height camera loses the head at the jump apex. Follow only
	# for these diagnostic crops; never change the editor/map render contract.
	var skeleton := editor.model_root.find_child("Skeleton3D",true,false) as Skeleton3D
	skeleton.force_update_all_bone_transforms()
	var center: Vector3 = (skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("J_Bip_C_Head"))).origin
	editor.camera.size = .72
	editor.camera.position = center+Vector3(0,.02,-5)
	editor.camera.look_at(center)

func _neutral() -> void:
	assert(editor.select_animation_by_id(&"T-Pose"))
	editor.set_playing(false)
	var skeleton := editor.model_root.find_child("Skeleton3D",true,false) as Skeleton3D
	skeleton.reset_bone_poses()
	for pair in [["L",-75.0],["R",75.0]]:
		var bone := skeleton.find_bone("J_Bip_"+str(pair[0])+"_UpperArm")
		var pose := skeleton.get_bone_global_rest(bone)
		pose.basis = Basis(Vector3(0,0,1),deg_to_rad(pair[1]))*pose.basis
		skeleton.set_bone_global_pose(bone,pose)
	skeleton.force_update_all_bone_transforms()

func _hair_nodes() -> Array:
	var option := editor.part_options[&"hair"] as OptionButton
	return editor._find_component_nodes(editor._component_definition(&"hair",option.get_item_metadata(option.selected)).get("prefixes",[]))

func _assert_only_hair(hair_id: StringName) -> void:
	var active := editor._find_component_nodes(editor._component_definition(&"hair",hair_id).prefixes)
	assert(not active.is_empty())
	for mesh in editor.model_root.find_children("Hair_*","MeshInstance3D",true,false):
		assert(mesh.visible == active.has(mesh),"Hair switch left another style visible: "+str(mesh.name))

func _assert_dye(enabled: bool, color: Color) -> void:
	for node in _hair_nodes():
		var mesh := node as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var mat := mesh.get_active_material(surface) as ShaderMaterial
			assert(mat != null and mat.shader.code == HumanCharacter3DEditor.HAIR_CLIP_MASK_SHADER)
			assert(bool(mat.get_shader_parameter("dye_enabled")) == (enabled and not str(mesh.name).ends_with("_Band")))
			if enabled: assert((mat.get_shader_parameter("dye_color") as Color).is_equal_approx(color))

func _non_hair_materials() -> Array:
	var result := []
	for node in editor.model_root.find_children("*","MeshInstance3D",true,false):
		if str(node.name).begins_with("Hair_"): continue
		for surface in node.mesh.get_surface_count(): result.append(node.get_active_material(surface))
	return result
