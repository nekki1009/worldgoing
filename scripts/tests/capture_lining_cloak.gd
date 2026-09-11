extends "res://scripts/tests/capture_chinese_cloak_candidate.gd"

const OUTPUT := "res://.visual_captures/lining_cloak"
var stage := "before"

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()>0: sex=args[0]
	if args.size()>1: stage=args[1]
	DisplayServer.window_set_size(Vector2i(1600,900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	editor=load("res://scenes/ui/HumanCharacter3DEditor.tscn").instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	await settle(4)
	var index := 1 if sex=="female" else 0
	if stage=="before": editor._load_body_model(index,"res://.godot-temp/lining_cloak_baseline_20260910/standard_anime_%s_character_pack.glb" % sex)
	elif stage=="final": editor._load_body_model(index)
	else: editor._load_body_model(index,"res://assets/characters/human/q35/chinese_lining/candidate_%s.glb" % sex)
	await settle(6)
	editor.preview_viewport.size=Vector2i(1024,1280)
	editor.preview_viewport.msaa_3d=Viewport.MSAA_4X
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	select_parts()
	if stage=="shirt" or stage=="final":
		await capture_lining()
		select_parts()
	assert(editor.select_animation_by_id(&"run"))
	editor.set_playing(false)
	var animation := editor.animation_player.get_animation(&"run")
	if stage != "before": await check_cape_playback(animation.length)
	timing['cloak_run']={"duration":animation.length,"frames":25}
	for view in [["front",35.0],["side",90.0],["back",180.0]]:
		editor.set_preview_yaw_degrees(view[1])
		for i in 25:
			editor.animation_player.seek(animation.length*float(i)/24,true)
			editor.animation_player.advance(0)
			frame_camera()
			editor.camera.size=2.9
			await capture("%s_%s_run_%s_%02d" % [sex,stage,view[0],i])
	print("LINING_CLOAK_CAPTURE_PASS ",sex," ",stage)
	var manifest := FileAccess.open(OUTPUT+"/"+sex+"_timing.json",FileAccess.WRITE)
	manifest.store_string(JSON.stringify(timing,"  "));manifest.close()
	editor.queue_free()
	await settle(3)
	quit(0)

func capture_lining() -> void:
	for pair in [[&"cape",&"none"],[&"armor",&"none"],[&"boots",&"none"],[&"helmet",&"none"],[&"outfit",&"outfit_chinese_lining_01"]]:
		assert(editor.select_part_by_id(pair[0],pair[1]))
	var shirt := editor.model_root.find_child("Outfit_Chinese_Lining_01_Shirt",true,false) as MeshInstance3D
	assert(shirt!=null and shirt.visible)
	assert(editor.select_part_by_id(&"outfit",&"none"));assert(not shirt.visible)
	assert(editor.select_part_by_id(&"outfit",&"outfit_underlayer_01"));assert(not shirt.visible)
	assert(editor.select_part_by_id(&"outfit",&"outfit_chinese_lining_01"));assert(shirt.visible)
	var material := shirt.get_active_material(0) as BaseMaterial3D
	assert(material!=null and material.albedo_texture!=null,"Linen UV texture missing")
	editor.select_animation_by_id(&"T-Pose");editor.set_playing(false);editor.animation_player.pause()
	var skeleton := editor.model_root.find_child("Skeleton3D",true,false) as Skeleton3D
	skeleton.reset_bone_poses();skeleton.force_update_all_bone_transforms()
	for pair in [["L",-80.0],["R",80.0]]:
		var bone := skeleton.find_bone("J_Bip_"+str(pair[0])+"_UpperArm")
		var pose := skeleton.get_bone_global_rest(bone)
		pose.basis=Basis(Vector3(0,0,1),deg_to_rad(pair[1]))*pose.basis
		skeleton.set_bone_global_pose(bone,pose)
	skeleton.force_update_all_bone_transforms()
	for view in [["front",0.0],["side",90.0],["back",180.0],["threequarter",35.0]]:
		editor.set_preview_yaw_degrees(view[1]);frame_camera();await capture(sex+"_lining_"+view[0])
	editor.set_preview_yaw_degrees(0);frame_camera(true);await capture(sex+"_lining_collar_close")
	editor.set_preview_yaw_degrees(35);frame_camera()
	await settle(2)
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUTPUT+"/"+sex+"_lining_editor_selected.png")==OK)
	for clip in [&"idle",&"walk",&"run",&"attack_axe",&"attack_jump_heavy",&"ride_slash"]:
		editor.set_mount_enabled(str(clip).begins_with("ride_"))
		assert(editor.select_animation_by_id(clip));editor.set_playing(false)
		var animation := editor.animation_player.get_animation(clip)
		timing[str(clip)]={"duration":animation.length,"frames":16}
		for i in 16:
			editor.animation_player.seek(animation.length*float(i)/15,true)
			editor.animation_player.advance(0);editor.set_preview_yaw_degrees(35)
			frame_camera(false,str(clip).begins_with("ride_"));await capture("%s_lining_%s_%02d" % [sex,clip,i])
		print("LINING_CLIP_PASS ",sex," ",clip)
	editor.set_mount_enabled(false)
	for armor in [&"armor_light_leather_01",&"armor_chinese_leather_01",&"armor_iron_01",&"armor_mingguang_01"]:
		assert(editor.select_part_by_id(&"armor",armor))
		editor.select_animation_by_id(&"run");editor.set_playing(false);editor.animation_player.seek(.2,true)
		assert(shirt.get_blend_shape_count()==1 and is_equal_approx(shirt.get_blend_shape_value(0),1.0),"Under-armor fit not applied")
		for view in [35.0,145.0]:
			editor.set_preview_yaw_degrees(view);frame_camera();await capture("%s_lining_%s_%d" % [sex,armor,int(view)])
	assert(editor.select_part_by_id(&"armor",&"none"))
	assert(is_zero_approx(shirt.get_blend_shape_value(0)),"Standalone fit not restored")

func cape_values() -> PackedFloat32Array:
	var cape := editor.model_root.find_child("Cape_Chinese_01_Main",true,false) as MeshInstance3D
	var values := PackedFloat32Array()
	for index in cape.get_blend_shape_count(): values.append(cape.get_blend_shape_value(index))
	return values

func check_cape_playback(duration: float) -> void:
	editor._reset_animation()
	var start := cape_values()
	editor.set_playing(true)
	await create_timer(0.14).timeout
	editor.set_playing(false)
	var posed := cape_values()
	assert(start!=posed,"Cloak morphs did not change during live playback")
	await create_timer(0.08).timeout
	assert(posed==cape_values(),"Paused cloak continued changing")
	editor._reset_animation()
	assert(start==cape_values(),"Cloak reset did not restore initial run shape")
	editor.set_playing(true)
	editor.animation_player.seek(duration-0.03,true)
	editor.animation_player.advance(0.07)
	editor.set_playing(false)
	assert(editor.animation_player.current_animation_position<0.1,"Run did not loop")
	assert(editor.select_part_by_id(&"cape",&"none"))
	assert(not editor.model_root.find_child("Cape_Chinese_01_Main",true,false).visible)
	assert(editor.select_part_by_id(&"cape",&"cape_chinese_01"))
	assert(editor.model_root.find_child("Cape_Chinese_01_Main",true,false).visible)
	print("CLOAK_LIVE_PAUSE_RESET_LOOP_PASS ",sex)

func capture(filename: String) -> void:
	await settle(2)
	await RenderingServer.frame_post_draw
	assert(editor.preview_viewport.get_texture().get_image().save_png(OUTPUT+"/"+filename+".png")==OK)
