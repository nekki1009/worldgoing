extends "res://scripts/tests/capture_chinese_leather_mingguang.gd"

const OUT := "res://output/neutral_faces_20260918/"
var folder := ""
var captures := 0

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	sex = args[0]
	mode = args[1]
	var probe := "--probe" in args
	folder = OUT+mode+"/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	DisplayServer.window_set_size(Vector2i(1600,1000))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	editor = load("res://scenes/ui/HumanCharacter3DEditor.tscn").instantiate()
	root.add_child(editor)
	editor.open()
	await settle(3)
	var gender := 1 if sex == "female" else 0
	editor._load_body_model(gender,"" if mode == "final" else "res://assets/characters/human/q35/neutral_faces/candidate_%s.glb" % sex)
	await settle(5)
	editor.preview_viewport.size = Vector2i(1024,1024)
	editor.preview_viewport.msaa_3d = Viewport.MSAA_4X
	editor.preview_viewport.use_debanding = false
	for slot in [&"armor",&"helmet",&"cape",&"weapon",&"shield",&"hair"]: assert(editor.select_part_by_id(slot,&"none"))
	assert(editor.select_part_by_id(&"outfit",&"outfit_underlayer_01"))
	for number in [1,5,6,7,8]:
		var face := StringName("face_standard_%02d" % number)
		for choice in [face,&"face_standard_03",&"none",face]:
			assert(editor.select_part_by_id(&"face",choice))
			for node in editor.model_root.find_children("Face_Standard_*","MeshInstance3D",true,false):
				assert(node.visible == (str(node.name).to_lower().begins_with(str(choice)) and choice != &"none"))
		assert(editor.select_part_by_id(&"hair",&"none"))
		neutral()
		for view in [["front",0.0],["side",90.0],["back",180.0],["threequarter",35.0]]:
			editor.set_preview_yaw_degrees(view[1])
			face_camera()
			await capture("%s_%02d_bare_%s" % [sex,number,view[0]])
		assert(editor.select_part_by_id(&"hair",StringName("hair_%s_05" % sex)))
		editor.set_preview_yaw_degrees(0)
		face_camera()
		await capture("%s_%02d_styled" % [sex,number])
		if number == 1: continue
		var appearance := editor.capture_appearance()
		assert(HumanCharacter3DEditor.valid_appearance(appearance))
		assert(editor.select_part_by_id(&"face",&"face_standard_01"))
		assert(editor.restore_appearance(appearance))
		assert(editor.capture_appearance().parts.face == face)
		if not probe:
			for hair_index in range(1,9):
				assert(editor.select_part_by_id(&"hair",StringName("hair_%s_%02d" % [sex,hair_index])))
				for angle in [0.0,35.0]:
					editor.set_preview_yaw_degrees(angle)
					face_camera()
					await capture("%s_%02d_hair_%02d_%d" % [sex,number,hair_index,int(angle)])
			assert(editor.select_part_by_id(&"hair",StringName("hair_%s_05" % sex)))
			for helmet: Dictionary in editor.PART_SLOTS[2].options:
				assert(editor.select_part_by_id(&"helmet",helmet.id))
				neutral()
				editor.set_preview_yaw_degrees(35)
				face_camera(.65)
				await capture("%s_%02d_%s" % [sex,number,helmet.id])
			assert(editor.select_part_by_id(&"helmet",&"none"))
			for clip in [&"idle",&"walk",&"run",&"hit",&"attack_jump_heavy"]:
				assert(editor.select_animation_by_id(clip))
				editor.set_playing(false)
				var animation := editor.animation_player.get_animation(editor.selected_animation)
				for step in range(9):
					editor.animation_player.seek(animation.length*float(step)/8.0,true)
					editor.animation_player.advance(0)
					editor.set_preview_yaw_degrees(35)
					face_camera(.44)
					await capture("%s_%02d_%s_%02d" % [sex,number,clip,step])
		neutral()
		editor.set_preview_yaw_degrees(0)
		face_camera()
		await settle(3)
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(folder+"%s_%02d_editor.png" % [sex,number]) == OK)
		print("NEUTRAL_FACE_STYLE_PASS ",sex," ",face)
	var report := FileAccess.open(folder+sex+"_result.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"sex":sex,"mode":mode,"probe":probe,"captures":captures,"new_faces":4,"old_faces_preserved":4,"expression":"neutral"},"  "))
	report.close()
	editor.queue_free()
	await settle(3)
	print("NEUTRAL_FACES_EDITOR_PASS ",sex," ",mode," ",captures)
	quit(0)

func face_camera(size: float = .36) -> void:
	var skeleton := editor.model_root.find_child("Skeleton3D",true,false) as Skeleton3D
	skeleton.force_update_all_bone_transforms()
	var pose := skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("J_Bip_C_Head"))
	var rest := skeleton.get_bone_global_rest(skeleton.find_bone("J_Bip_C_Head"))
	var face_center := Vector3(0,1.611 if sex == "male" else 1.497,-.035)
	var center := pose*(rest.affine_inverse()*face_center)
	editor.camera.size = size
	editor.camera.position = center+Vector3(0,0,-5)
	editor.camera.look_at(center)

func capture(filename: String) -> void:
	await settle(3)
	await RenderingServer.frame_post_draw
	assert(editor.preview_viewport.get_texture().get_image().save_png(folder+filename+".png") == OK)
	captures += 1
