extends "res://scripts/tests/capture_all_model_audit.gd"

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	sex = args[0]
	mode = args[1]
	audit_dir = "res://.visual_captures/body_joint_refinement/" + mode
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(audit_dir))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	editor = load("res://scenes/ui/HumanCharacter3DEditor.tscn").instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	await settle(4)
	if mode == "candidate":
		editor._load_body_model(1 if sex == "female" else 0,"res://assets/characters/human/q35/joint_refinement/candidate_%s.glb" % sex)
	else:
		editor._load_body_model(1 if sex == "female" else 0)
	await settle(8)
	editor.preview_viewport.size = Vector2i(1024,1024)
	editor.preview_viewport.msaa_3d = Viewport.MSAA_4X
	for slot in HumanCharacter3DEditor.PART_SLOTS:
		var value: StringName = &"none"
		if slot.id == &"face": value = &"face_standard_01"
		if slot.id == &"hair": value = &"hair_short_01"
		if slot.id == &"outfit": value = &"outfit_underlayer_01"
		assert(editor.select_part_by_id(slot.id,value))
	var skeleton := editor.model_root.find_child("Skeleton3D",true,false) as Skeleton3D
	editor.select_animation_by_id(&"T-Pose")
	editor.set_playing(false)
	editor.animation_player.pause()
	editor.set_process(false)
	for side in ["L","R"]:
		for joint in ["LowerArm","Hand"]:
			var bone := skeleton.find_bone("J_Bip_" + side + "_" + joint)
			for bend in ([0,45,90,135] if joint == "LowerArm" else [-55,0,55]):
				skeleton.reset_bone_poses()
				var pose := skeleton.get_bone_global_rest(bone)
				pose.basis = Basis(Vector3.FORWARD,deg_to_rad(float(bend) * (-1.0 if side == "L" else 1.0))) * pose.basis
				skeleton.set_bone_global_pose(bone,pose)
				skeleton.force_update_all_bone_transforms()
				editor.set_preview_yaw_degrees(0)
				var center := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
				editor.camera.size = 0.40 if joint == "LowerArm" else 0.24
				editor.camera.global_position = center + Vector3(0,0,-5)
				editor.camera.look_at(center)
				await capture("%s_%s_%s_%d" % [sex,side,joint,bend])
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
		await capture("%s_neutral_%s" % [sex,view[0]])
	# Find actual sampled joint extrema, not just evenly spaced presentation frames.
	for pair in [[&"run",&"none"],[&"guard",&"longsword_01"],[&"attack_bow",&"bow_01"],[&"attack_crossbow",&"crossbow_01"],[&"attack_spear",&"spear_01"],[&"attack_hammer",&"hammer_01"]]:
		assert(editor.select_part_by_id(&"weapon",pair[1]))
		assert(editor.select_animation_by_id(pair[0]))
		editor.set_playing(false)
		var animation := editor.animation_player.get_animation(editor.selected_animation)
		var peaks := {}
		for sample in 61:
			var time := animation.length * float(sample) / 60.0
			editor.animation_player.seek(time,true)
			editor.animation_player.advance(0)
			skeleton.force_update_all_bone_transforms()
			for side in ["L","R"]:
				for joint in ["LowerArm","Hand"]:
					var bone := skeleton.find_bone("J_Bip_" + side + "_" + joint)
					var previous := skeleton.find_bone("J_Bip_" + side + ("_UpperArm" if joint == "LowerArm" else "_LowerArm"))
					var following := skeleton.find_bone("J_Bip_" + side + ("_Hand" if joint == "LowerArm" else "_Middle1"))
					var origin := skeleton.get_bone_global_pose(bone).origin
					var angle := (origin-skeleton.get_bone_global_pose(previous).origin).angle_to(skeleton.get_bone_global_pose(following).origin-origin)
					var key: String = side + "_" + joint
					if not peaks.has(key) or angle > float(peaks[key].angle):
						peaks[key] = {"time":time,"angle":angle,"bone":bone}
			if sample % 4 == 0 and args.size() <= 2:
				editor.set_preview_yaw_degrees(65)
				var center := Vector3(0,1.30 if sex == "male" else 1.19,0)
				editor.camera.size = 1.35
				editor.camera.position = center + Vector3(0,0,-5)
				editor.camera.look_at(center)
				await capture("%s_cycle_%s_%02d" % [sex,pair[0],sample])
		# Diagnostic close-ups hide only head meshes so hair cannot obscure a raised wrist.
		var head_visibility := {}
		for node in editor.model_root.find_children("*","MeshInstance3D",true,false):
			if str(node.name).begins_with("Face_") or str(node.name).begins_with("Hair_"):
				head_visibility[node] = node.visible
				node.visible = false
		for key in peaks:
			var peak: Dictionary = peaks[key]
			editor.animation_player.seek(float(peak.time),true)
			editor.animation_player.advance(0)
			skeleton.force_update_all_bone_transforms()
			editor.set_preview_yaw_degrees(65)
			var center := skeleton.global_transform * skeleton.get_bone_global_pose(int(peak.bone)).origin
			editor.camera.size = .48 if str(key).ends_with("LowerArm") else .32
			editor.camera.global_position = center + Vector3(0,0,-5)
			editor.camera.look_at(center)
			# Changing yaw refreshes hair visibility; hide after that refresh.
			for node in head_visibility:
				node.visible = false
			await capture("%s_extreme_%s_%s" % [sex,pair[0],key])
			for node in head_visibility:
				assert(not node.visible,"Head mesh obscures joint diagnostic")
		for node in head_visibility:
			node.visible = head_visibility[node]
		print("BODY_JOINT_EXTREMA ",sex," ",pair[0]," ",JSON.stringify(peaks))
	if args.size() > 2:
		print("BODY_JOINT_EXTREMA_PASS ",sex," ",mode)
		editor.queue_free()
		await settle(4)
		quit(0)
		return
	if sex == "male":
		assert(editor.select_part_by_id(&"outfit",&"none"))
		var full_body := editor.model_root.find_child("Body_Standard_Male_Full",true,false) as MeshInstance3D
		assert(full_body != null and full_body.visible)
		assert(editor.select_part_by_id(&"outfit",&"outfit_underlayer_01"))
		assert(not full_body.visible)
	for outfit in [&"outfit_underlayer_01",&"outfit_chinese_lining_01"]:
		assert(editor.select_part_by_id(&"outfit",outfit))
		for armor in [&"none",&"armor_light_leather_01",&"armor_iron_01",&"armor_mingguang_01",&"armor_chinese_leather_01"]:
			assert(editor.select_part_by_id(&"armor",armor))
			for pair in [[&"run",&"none"],[&"guard",&"longsword_01"],[&"attack_bow",&"bow_01"],[&"attack_crossbow",&"crossbow_01"],[&"attack_spear",&"spear_01"],[&"attack_hammer",&"hammer_01"]]:
				assert(editor.select_part_by_id(&"weapon",pair[1]))
				assert(editor.select_animation_by_id(pair[0]))
				editor.set_playing(false)
				var animation := editor.animation_player.get_animation(editor.selected_animation)
				for sample in 3:
					editor.animation_player.seek(animation.length * (0.25 + .25 * sample),true)
					editor.animation_player.advance(0)
					editor.set_preview_yaw_degrees(65)
					var center := Vector3(0,1.30 if sex == "male" else 1.19,0)
					editor.camera.size = 1.25
					editor.camera.position = center + Vector3(0,0,-5)
					editor.camera.look_at(center)
					await capture("%s_%s_%s_%s_%d" % [sex,outfit,armor,pair[0],sample])
			print("BODY_JOINT_COMBO ",sex," ",outfit," ",armor)
	print("BODY_JOINT_CAPTURE_PASS ",sex," ",mode)
	editor.queue_free()
	await settle(4)
	quit(0)
