extends "res://scripts/tests/capture_chinese_cloak_candidate.gd"

const OUTPUT := "res://.visual_captures/chinese_leather_boots"

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()>0: sex=args[0]
	if args.size()>1: mode=args[1]
	DisplayServer.window_set_size(Vector2i(1600,900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	editor=load("res://scenes/ui/HumanCharacter3DEditor.tscn").instantiate() as HumanCharacter3DEditor
	root.add_child(editor);editor.open();await settle(4)
	var index := 1 if sex=="female" else 0
	if mode=="final": editor._load_body_model(index)
	else: editor._load_body_model(index,"res://assets/characters/human/q35/chinese_leather_boots/candidate_%s.glb" % sex)
	await settle(6)
	editor.preview_viewport.size=Vector2i(1024,1280)
	editor.preview_viewport.msaa_3d=Viewport.MSAA_4X
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for slot in [&"armor",&"cape",&"weapon",&"shield",&"helmet"]: assert(editor.select_part_by_id(slot,&"none"))
	assert(editor.select_part_by_id(&"outfit",&"outfit_chinese_lining_01"))
	assert(editor.select_part_by_id(&"boots",&"boots_chinese_leather_01"))
	var boot := editor.model_root.find_child("Boots_Chinese_Leather_01_Main_L",true,false) as MeshInstance3D
	assert(boot!=null and boot.visible)
	assert(editor.select_part_by_id(&"boots",&"none"));assert(not boot.visible)
	assert(editor.select_part_by_id(&"boots",&"boots_leather_01"));assert(not boot.visible)
	assert(editor.select_part_by_id(&"boots",&"boots_chinese_leather_01"));assert(boot.visible)
	assert(editor.model_root.find_children("Boots_Chinese_Leather_01_*","MeshInstance3D",true,false).size()==32)
	var mat := boot.get_active_material(0) as BaseMaterial3D
	assert(mat!=null and mat.albedo_texture!=null,"Boot leather texture missing")
	editor.select_animation_by_id(&"T-Pose");editor.set_playing(false);editor.animation_player.pause()
	var skeleton := editor.model_root.find_child("Skeleton3D",true,false) as Skeleton3D
	skeleton.reset_bone_poses();skeleton.force_update_all_bone_transforms()
	for view in [["front",0.0],["side",90.0],["back",180.0],["threequarter",35.0]]:
		editor.set_preview_yaw_degrees(view[1]);boot_camera();await capture(sex+"_"+view[0])
	editor.set_preview_yaw_degrees(35);frame_camera();await capture(sex+"_full_body")
	for clip in [&"idle",&"walk",&"run",&"attack_axe",&"attack_jump_heavy",&"ride_slash"]:
		editor.set_mount_enabled(str(clip).begins_with("ride_"))
		assert(editor.select_animation_by_id(clip));editor.set_playing(false)
		var animation := editor.animation_player.get_animation(clip)
		timing[str(clip)]={"duration":animation.length,"frames":16}
		for i in 16:
			editor.animation_player.seek(animation.length*float(i)/15,true);editor.animation_player.advance(0)
			editor.set_preview_yaw_degrees(90);frame_camera(false,str(clip).begins_with("ride_"))
			if clip in [&"idle",&"walk",&"run"]: boot_camera(true)
			await capture("%s_%s_%02d" % [sex,clip,i])
		print("BOOTS_CLIP_CAPTURE ",sex," ",clip)
	editor.set_mount_enabled(false)
	for armor in [&"armor_light_leather_01",&"armor_chinese_leather_01"]:
		assert(editor.select_part_by_id(&"armor",armor))
		editor.select_animation_by_id(&"run");editor.set_playing(false);editor.animation_player.seek(.22,true)
		for angle in [35.0,145.0]:
			editor.set_preview_yaw_degrees(angle);frame_camera();await capture("%s_%s_%d" % [sex,armor,int(angle)])
	var file := FileAccess.open(OUTPUT+"/"+sex+"_timing.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(timing,"  "));file.close()
	print("CHINESE_LEATHER_BOOTS_CAPTURE_PASS ",sex," ",mode)
	editor.queue_free();await settle(3);quit(0)

func boot_camera(moving: bool=false) -> void:
	var center := Vector3(0,.40 if moving else .34,0)
	editor.camera.size=2.4 if moving else .75
	editor.camera.position=center+Vector3(0,.04,-5);editor.camera.look_at(center)

func capture(filename: String) -> void:
	await settle(2);await RenderingServer.frame_post_draw
	assert(editor.preview_viewport.get_texture().get_image().save_png(OUTPUT+"/"+filename+".png")==OK)
