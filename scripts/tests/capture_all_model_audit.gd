extends "res://scripts/tests/capture_chinese_cloak_candidate.gd"

const AUDIT_DIR := "res://.visual_captures/all_model_audit"
var audit_dir := AUDIT_DIR

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): sex = args[0]
	if args.size() > 1: audit_dir = "res://.visual_captures/all_model_repaired"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	editor = load("res://scenes/ui/HumanCharacter3DEditor.tscn").instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	await settle(4)
	if args.size() > 1 and args[1] != "final":
		editor._load_body_model(1 if sex == "female" else 0,"res://assets/characters/human/q35/audit_repair/candidate_%s.glb" % sex)
	else:
		editor._load_body_model(1 if sex == "female" else 0)
	await settle(8)
	editor.preview_viewport.size = Vector2i(1024,1280)
	editor.preview_viewport.msaa_3d = Viewport.MSAA_4X
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(audit_dir))
	for slot in HumanCharacter3DEditor.PART_SLOTS:
		if args.size() > 2 and str(slot.id) != args[2]: continue
		for option in editor._part_definition(slot.id).options:
			if option.id == &"none": continue
			for reset in HumanCharacter3DEditor.PART_SLOTS:
				var baseline: StringName = &"none"
				if reset.id == &"face": baseline = &"face_standard_01"
				if reset.id == &"hair": baseline = &"hair_short_01"
				if reset.id == &"outfit": baseline = &"outfit_underlayer_01"
				assert(editor.select_part_by_id(reset.id,baseline))
			assert(editor.select_part_by_id(slot.id,option.id))
			if slot.id == &"hair":
				for hair_node in editor._find_component_nodes(editor._component_definition(&"hair",option.id).get("prefixes",[])):
					if not hair_node is MeshInstance3D: continue
					for surface in hair_node.mesh.get_surface_count():
						var material := hair_node.get_active_material(surface) as ShaderMaterial
						assert(material != null and material.shader.code == HumanCharacter3DEditor.HAIR_CLIP_MASK_SHADER)
						assert(not material.get_shader_parameter("mask_enabled"),"Unequipped hair must not stay clipped")
			editor.select_animation_by_id(&"T-Pose")
			editor.set_playing(false)
			editor.animation_player.pause()
			var skeleton := editor.model_root.find_child("Skeleton3D",true,false) as Skeleton3D
			skeleton.reset_bone_poses()
			for pair in [["L",-75.0],["R",75.0]]:
				var bone := skeleton.find_bone("J_Bip_" + str(pair[0]) + "_UpperArm")
				var pose := skeleton.get_bone_global_rest(bone)
				pose.basis = Basis(Vector3(0,0,1),deg_to_rad(float(pair[1]))) * pose.basis
				skeleton.set_bone_global_pose(bone,pose)
			skeleton.force_update_all_bone_transforms()
			for view in [["front",0.0],["side",90.0],["back",180.0]]:
				editor.set_preview_yaw_degrees(float(view[1]))
				audit_camera(str(slot.id))
				await capture("%s_%s_%s" % [sex,option.id,view[0]])
			var clip: StringName = &"run"
			if slot.id == &"weapon": clip = HumanCharacter3DEditor.WEAPON_ATTACK_MAP[option.id]
			assert(editor.select_animation_by_id(clip))
			editor.set_playing(false)
			var animation := editor.animation_player.get_animation(editor.selected_animation)
			for sample in 4:
				editor.animation_player.seek(animation.length * (float(sample)+0.5)/4.0,true)
				editor.animation_player.advance(0.0)
				editor.set_preview_yaw_degrees(35)
				audit_camera(str(slot.id))
				await capture("%s_%s_motion%d" % [sex,option.id,sample])
			print("MODEL_AUDIT_CAPTURE ",sex," ",option.id," ",clip)
	print("ALL_MODEL_AUDIT_CAPTURE_DONE ",sex)
	editor.queue_free()
	await settle(4)
	quit(0)

func audit_camera(slot: String) -> void:
	var center := Vector3(0,0.85,0)
	editor.camera.size = 2.05
	if slot in ["face","hair","helmet"]:
		center.y = 1.53 if sex == "male" else 1.41
		editor.camera.size = 0.72
	elif slot == "boots":
		center.y = 0.40
		editor.camera.size = 1.05
	elif slot in ["weapon","shield"]:
		editor.camera.size = 3.4
		center.y = 0.80
	editor.camera.position = center + Vector3(0,0.02,-5)
	editor.camera.look_at(center)

func capture(filename: String) -> void:
	await settle(2)
	await RenderingServer.frame_post_draw
	assert(editor.preview_viewport.get_texture().get_image().save_png(audit_dir + "/" + filename + ".png") == OK)
