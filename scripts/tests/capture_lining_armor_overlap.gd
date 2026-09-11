extends "res://scripts/tests/capture_all_model_audit.gd"

const INNER_TOPS := {
	&"armor_iron_01": ["Armor_Iron_01_UnderTunic"],
	&"armor_mingguang_01": ["Armor_Mingguang_01_UnderSleeves", "Armor_Mingguang_01_UnderTunic"],
}

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	sex = args[0]
	mode = args[1]
	audit_dir = "res://.visual_captures/lining_armor_overlap/" + mode
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(audit_dir))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	editor = load("res://scenes/ui/HumanCharacter3DEditor.tscn").instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	await settle(4)
	if mode in ["candidate","fit_probe","surface_probe"]:
		editor._load_body_model(1 if sex == "female" else 0,"res://assets/characters/human/q35/lining_armor_fit/candidate_%s.glb" % sex)
	else:
		editor._load_body_model(1 if sex == "female" else 0)
	await settle(8)
	editor.preview_viewport.size = Vector2i(1024,1024)
	editor.preview_viewport.msaa_3d = Viewport.MSAA_4X
	for slot in HumanCharacter3DEditor.PART_SLOTS:
		var value: StringName = &"none"
		if slot.id == &"face": value = &"face_standard_01"
		if slot.id == &"hair": value = &"hair_short_01"
		if slot.id == &"outfit": value = &"outfit_chinese_lining_01"
		assert(editor.select_part_by_id(slot.id,value))
	editor.set_process(false)
	if mode == "surface_probe":
		assert(editor.select_part_by_id(&"armor",&"armor_iron_01"))
		assert(editor.select_part_by_id(&"weapon",&"crossbow_01"))
		assert(editor.select_animation_by_id(&"attack_crossbow"))
		editor.set_playing(false)
		editor.animation_player.seek(0,true)
		editor.animation_player.advance(0)
		editor.set_preview_yaw_degrees(245)
		frame_upper_body()
		await capture(sex+"_surface_with_body")
		for node in editor.model_root.find_children("Body*","MeshInstance3D",true,false): node.visible = false
		await capture(sex+"_surface_without_body")
		for node in editor.model_root.find_children("Armor*","MeshInstance3D",true,false): node.visible = false
		await capture(sex+"_surface_shirt_only")
		print("LINING_SURFACE_PROBE_PASS ",sex)
		editor.queue_free()
		await settle(4)
		quit(0)
		return
	if mode == "fit_probe":
		await capture_fit_probe()
		editor.queue_free()
		await settle(4)
		quit(0)
		return
	if mode in ["final","candidate"]:
		await verify_final()
		editor.queue_free()
		await settle(4)
		quit(0)
		return
	for armor in INNER_TOPS:
		assert(editor.select_part_by_id(&"armor",armor))
		assert(editor.select_part_by_id(&"weapon",&"bow_01"))
		assert(editor.select_animation_by_id(&"attack_bow"))
		editor.set_playing(false)
		var animation := editor.animation_player.get_animation(editor.selected_animation)
		editor.animation_player.seek(animation.length * .5,true)
		editor.animation_player.advance(0)
		editor.set_preview_yaw_degrees(65)
		frame_upper_body()
		await capture("%s_%s_both" % [sex,armor])
		for node_name in INNER_TOPS[armor]:
			var inner := editor.model_root.find_child(node_name,true,false) as MeshInstance3D
			assert(inner != null)
			inner.visible = false
		await capture("%s_%s_lining_only" % [sex,armor])
		for node_name in INNER_TOPS[armor]:
			editor.model_root.find_child(node_name,true,false).visible = true
		for node in editor.model_root.find_children("Outfit_Chinese_Lining_01_*","MeshInstance3D",true,false):
			node.visible = false
		await capture("%s_%s_armor_cloth_only" % [sex,armor])
		assert(editor.select_part_by_id(&"outfit",&"outfit_chinese_lining_01"))
	print("LINING_OVERLAP_DIAGNOSTIC_PASS ",sex)
	editor.queue_free()
	await settle(4)
	quit(0)

func frame_upper_body() -> void:
	var center := Vector3(0,1.30 if sex == "male" else 1.19,0)
	editor.camera.size = 1.25
	editor.camera.position = center + Vector3(0,0,-5)
	editor.camera.look_at(center)

func capture_fit_probe() -> void:
	assert(editor.select_part_by_id(&"armor",&"armor_iron_01"))
	assert(editor.select_part_by_id(&"weapon",&"hammer_01"))
	var shirt := editor.model_root.find_child("Outfit_Chinese_Lining_01_Shirt",true,false) as MeshInstance3D
	var fit_index := -1
	for index in shirt.get_blend_shape_count():
		if shirt.mesh.get_blend_shape_name(index) == &"UnderArmor": fit_index = index
		shirt.set_blend_shape_value(index,0.0)
	assert(fit_index >= 0)
	for pose in [[&"idle",4],[&"attack_hammer",7],[&"attack_hammer",11]]:
		assert(editor.select_animation_by_id(pose[0]))
		editor.set_playing(false)
		var animation := editor.animation_player.get_animation(editor.selected_animation)
		editor.animation_player.seek(animation.length*float(pose[1])/16.0,true)
		editor.animation_player.advance(0)
		editor.set_preview_yaw_degrees(65)
		frame_upper_body()
		for strength in [0.6,0.7,0.8,0.9,1.0]:
			shirt.set_blend_shape_value(fit_index,strength)
			await capture("%s_%s_%02d_fit_%02d" % [sex,pose[0],pose[1],roundi(strength*100)])
	print("LINING_ARMOR_FIT_PROBE_PASS ",sex)

func check_layers(armor: StringName, outfit: StringName) -> void:
	var under_top := editor.model_root.find_child("Outfit_Underlayer_01_Top",true,false) as MeshInstance3D
	if sex == "female":
		assert(under_top != null)
		assert(under_top.visible == (outfit == &"outfit_underlayer_01" and armor not in INNER_TOPS),"Ordinary top coverage stale")
	for owner_id in INNER_TOPS:
		for node_name in INNER_TOPS[owner_id]:
			var inner := editor.model_root.find_child(node_name,true,false) as MeshInstance3D
			assert(inner != null)
			assert(inner.visible == (armor == owner_id and outfit != &"outfit_chinese_lining_01"),node_name + " visibility stale")
	var shirt := editor.model_root.find_child("Outfit_Chinese_Lining_01_Shirt",true,false) as MeshInstance3D
	assert(shirt != null and shirt.visible == (outfit == &"outfit_chinese_lining_01"))
	var hard_fit_found := false
	for index in shirt.get_blend_shape_count():
		if shirt.mesh.get_blend_shape_name(index) == &"UnderArmor":
			var fit_strength := 1.0 if armor in [&"armor_light_leather_01",&"armor_chinese_leather_01"] else 0.0
			assert(is_equal_approx(shirt.get_blend_shape_value(index),fit_strength))
		elif shirt.mesh.get_blend_shape_name(index) == &"UnderHardArmor":
			hard_fit_found = true
			assert(is_equal_approx(shirt.get_blend_shape_value(index),1.0 if armor in INNER_TOPS else 0.0))
	assert(hard_fit_found,"Hard armor lining morph missing")
	var body_name := "Body_Standard_Female" if sex == "female" else "Body_Standard_Male"
	var body := editor.model_root.find_child(body_name,true,false) as MeshInstance3D
	var original := body.get_meta("lining_original_mesh") as ArrayMesh
	assert(original.get_blend_shape_count() == 0)
	if outfit == &"outfit_chinese_lining_01":
		assert(body.mesh == body.get_meta("lining_covered_mesh") and body.mesh != original)
		var old_faces := 0
		var visible_faces := 0
		for surface in original.get_surface_count(): old_faces += original.surface_get_array_index_len(surface)
		for surface in body.mesh.get_surface_count(): visible_faces += body.mesh.surface_get_array_index_len(surface)
		assert(visible_faces > 0 and visible_faces < old_faces)
	else:
		assert(body.mesh == original,"Undressing did not restore exact body mesh")

func verify_final() -> void:
	# Exercise both slot-change orders, restoration, unrelated slot refreshes,
	# and every armor choice. No unselected built-in cloth may reappear.
	for armor in [&"armor_iron_01",&"armor_mingguang_01",&"armor_light_leather_01",&"armor_chinese_leather_01",&"none"]:
		assert(editor.select_part_by_id(&"armor",armor))
		for outfit in [&"outfit_chinese_lining_01",&"outfit_underlayer_01",&"none",&"outfit_chinese_lining_01"]:
			assert(editor.select_part_by_id(&"outfit",outfit))
			check_layers(armor,outfit)
			assert(editor.select_part_by_id(&"weapon",&"bow_01"))
			check_layers(armor,outfit)
			for previous in INNER_TOPS:
				assert(editor.select_part_by_id(&"armor",previous))
				check_layers(previous,outfit)
			assert(editor.select_part_by_id(&"armor",armor))
			check_layers(armor,outfit)
	var skeleton := editor.model_root.find_child("Skeleton3D",true,false) as Skeleton3D
	var clips := [[&"idle",&"none"],[&"walk",&"none"],[&"run",&"none"],[&"guard",&"longsword_01"],[&"attack_bow",&"bow_01"],[&"attack_crossbow",&"crossbow_01"],[&"attack_spear",&"spear_01"],[&"attack_hammer",&"hammer_01"]]
	var durations := {}
	for armor in INNER_TOPS:
		assert(editor.select_part_by_id(&"armor",armor))
		assert(editor.select_part_by_id(&"outfit",&"outfit_chinese_lining_01"))
		assert(editor.select_part_by_id(&"weapon",&"none"))
		assert(editor.select_animation_by_id(&"T-Pose"))
		editor.set_playing(false)
		editor.animation_player.pause()
		skeleton.reset_bone_poses()
		for side in ["L","R"]:
			var bone := skeleton.find_bone("J_Bip_" + side + "_UpperArm")
			var pose := skeleton.get_bone_global_rest(bone)
			pose.basis = Basis(Vector3.BACK,deg_to_rad(-75.0 if side == "L" else 75.0)) * pose.basis
			skeleton.set_bone_global_pose(bone,pose)
		skeleton.force_update_all_bone_transforms()
		for view in [["front",0.0],["side",90.0],["back",180.0],["threequarter",35.0]]:
			editor.set_preview_yaw_degrees(view[1])
			audit_camera("body")
			await capture("%s_%s_neutral_%s" % [sex,armor,view[0]])
		for pair in clips:
			assert(editor.select_part_by_id(&"weapon",pair[1]))
			assert(editor.select_animation_by_id(pair[0]))
			editor.set_playing(false)
			var animation := editor.animation_player.get_animation(editor.selected_animation)
			durations[pair[0]] = animation.length
			for sample in 17:
				editor.animation_player.seek(animation.length * float(sample) / 16.0,true)
				editor.animation_player.advance(0)
				editor.set_preview_yaw_degrees(65)
				frame_upper_body()
				check_layers(armor,&"outfit_chinese_lining_01")
				await capture("%s_%s_%s_%02d" % [sex,armor,pair[0],sample])
			await capture_elbow_extrema(armor,pair[0],skeleton,animation)
			print("LINING_ARMOR_CYCLE ",sex," ",armor," ",pair[0])
		# Standalone/restored outfit views expose disappearing pieces or stale masks.
		assert(editor.select_part_by_id(&"weapon",&"bow_01"))
		for outfit in [&"outfit_underlayer_01",&"outfit_chinese_lining_01"]:
			assert(editor.select_part_by_id(&"outfit",outfit))
			assert(editor.select_animation_by_id(&"attack_bow"))
			editor.set_playing(false)
			var animation := editor.animation_player.get_animation(editor.selected_animation)
			editor.animation_player.seek(animation.length * .5,true)
			editor.animation_player.advance(0)
			editor.set_preview_yaw_degrees(65)
			frame_upper_body()
			await capture("%s_%s_restore_%s" % [sex,armor,outfit])
	assert(editor.select_part_by_id(&"armor",&"none"))
	check_layers(&"none",&"outfit_chinese_lining_01")
	await capture(sex + "_lining_no_armor")
	var file := FileAccess.open(audit_dir + "/" + sex + "_durations.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(durations,"  "))
	file.close()
	print("LINING_ARMOR_OVERLAP_PASS ",sex)

func capture_elbow_extrema(armor: StringName, clip: StringName, skeleton: Skeleton3D, animation: Animation) -> void:
	var peaks := {}
	for sample in 61:
		var time := animation.length * float(sample) / 60.0
		editor.animation_player.seek(time,true)
		editor.animation_player.advance(0)
		skeleton.force_update_all_bone_transforms()
		for side in ["L","R"]:
			var shoulder := skeleton.find_bone("J_Bip_"+side+"_UpperArm")
			var elbow := skeleton.find_bone("J_Bip_"+side+"_LowerArm")
			var hand := skeleton.find_bone("J_Bip_"+side+"_Hand")
			var a := skeleton.get_bone_global_pose(shoulder).origin
			var b := skeleton.get_bone_global_pose(elbow).origin
			var c := skeleton.get_bone_global_pose(hand).origin
			var angle := (b-a).angle_to(c-b)
			if not peaks.has(side) or angle > float(peaks[side].angle):
				peaks[side] = {"time":time,"angle":angle,"elbow":elbow,"hand":hand}
	var head_visibility := {}
	for node in editor.model_root.find_children("*","MeshInstance3D",true,false):
		if str(node.name).begins_with("Face_") or str(node.name).begins_with("Hair_"):
			head_visibility[node] = node.visible
	for side in peaks:
		var peak: Dictionary = peaks[side]
		editor.animation_player.seek(float(peak.time),true)
		editor.animation_player.advance(0)
		skeleton.force_update_all_bone_transforms()
		for yaw in [65,245]:
			editor.set_preview_yaw_degrees(yaw)
			var local_center := (skeleton.get_bone_global_pose(peak.elbow).origin+skeleton.get_bone_global_pose(peak.hand).origin)*.5
			var center := skeleton.global_transform * local_center
			editor.camera.size = .48
			editor.camera.global_position = center+Vector3(0,0,-5)
			editor.camera.look_at(center)
			for node in head_visibility:
				node.visible = false
			check_layers(armor,&"outfit_chinese_lining_01")
			await capture("%s_%s_extreme_%s_%s_%d" % [sex,armor,clip,side,yaw])
	for node in head_visibility:
		node.visible = head_visibility[node]
	print("LINING_ARMOR_ELBOW_EXTREMA ",sex," ",armor," ",clip," ",JSON.stringify(peaks))
