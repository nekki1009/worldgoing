extends SceneTree

const DIR := "res://.visual_captures/chinese_leather_mingguang"
var editor: HumanCharacter3DEditor
var sex := "male"
var mode := "probe"
var timing := {}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()>0: sex=args[0]
	if args.size()>1: mode=args[1]
	DisplayServer.window_set_size(Vector2i(1600,900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	editor=load("res://scenes/ui/HumanCharacter3DEditor.tscn").instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	await settle(4)
	var index := 1 if sex=="female" else 0
	if mode=="final": editor._load_body_model(index)
	else: editor._load_body_model(index,"res://assets/characters/human/q35/chinese_leather_mingguang/candidate_%s.glb" % sex)
	await settle(6)
	editor.preview_viewport.size=Vector2i(1024,1280)
	editor.preview_viewport.msaa_3d=Viewport.MSAA_4X
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	for pair in [[&"cape",&"none"],[&"boots",&"none"],[&"weapon",&"none"],[&"shield",&"none"],[&"outfit",&"outfit_underlayer_01"]]:
		assert(editor.select_part_by_id(pair[0],pair[1]))
	for part in [[&"armor",&"armor_chinese_leather_01","Armor_Chinese_Leather_01_",&"armor_light_leather_01"],[&"helmet",&"helmet_mingguang_01","Helmet_Mingguang_01_",&"helmet_steel_01"]]:
		for choice in [part[1],&"none",part[3],part[1]]:
			assert(editor.select_part_by_id(part[0],choice))
			var nodes := editor.model_root.find_children(str(part[2])+"*","MeshInstance3D",true,false)
			assert(not nodes.is_empty())
			for mesh in nodes:
				assert(mesh.visible == (choice==part[1]))
				if choice==part[1]:
					assert(mesh.get_active_material(0) is StandardMaterial3D,"PBR route not preserved")
	var sample := editor.model_root.find_child("Armor_Chinese_Leather_01_ChestPanel_Front",true,false) as MeshInstance3D
	assert(sample.get_active_material(0).albedo_texture != null,"UV sample missing in engine")
	var plume := editor.model_root.find_child("Helmet_Mingguang_01_WhitePlume_Fittings",true,false) as MeshInstance3D
	if mode!="probe": assert(plume.get_blend_shape_count()==2)
	neutral()
	for view in [["front",0.0],["threequarter",35.0],["right",90.0],["left",-90.0],["back",180.0]]:
		editor.set_preview_yaw_degrees(float(view[1]))
		frame_camera()
		await capture(sex+"_neutral_"+str(view[0]))
	for view in [["front",0.0],["side",90.0],["back",180.0]]:
		editor.set_preview_yaw_degrees(float(view[1]))
		frame_camera("head")
		await capture(sex+"_helmet_"+str(view[0]))
	editor.set_preview_yaw_degrees(0)
	frame_camera("chest")
	await capture(sex+"_armor_detail")
	var clips: Array[StringName] = [&"idle",&"walk",&"run",&"guard",&"attack_axe",&"attack_jump_heavy",&"ride_slash"]
	if mode=="probe": clips=[&"walk"]
	for clip in clips:
		editor.set_mount_enabled(str(clip).begins_with("ride_"))
		assert(editor.select_animation_by_id(clip))
		editor.set_playing(false)
		var animation := editor.animation_player.get_animation(editor.selected_animation)
		var steps := 16 if mode!="probe" else 4
		timing[str(clip)]={"duration":animation.length,"frames":steps}
		var plume_values: Array[float] = []
		editor.set_preview_yaw_degrees(35.0)
		for si in steps:
			editor.animation_player.seek(animation.length*float(si)/float(steps-1),true)
			editor.animation_player.advance(0)
			if mode!="probe": plume_values.append(plume.get_blend_shape_value(0))
			frame_camera()
			await capture("%s_%s_%02d" % [sex,clip,si])
		if mode!="probe": assert(plume_values.max()-plume_values.min()>.05,"Missing live plume motion: "+str(clip))
		print("CHINESE_GEAR_CLIP ",sex," ",clip," ",steps)
	editor.set_mount_enabled(false)
	if mode!="probe": await combinations()
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	editor.animation_player.seek(0,true)
	editor._update_preview_framing()
	await capture(sex+"_gameplay_scale")
	frame_camera()
	await settle(3)
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(DIR+"/"+sex+"_editor_selected.png")==OK)
	var file := FileAccess.open(DIR+"/"+sex+"_timing.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(timing,"  "))
	file.close()
	print("CHINESE_GEAR_EDITOR_CAPTURE_PASS ",sex," ",mode)
	editor.queue_free()
	await settle(4)
	quit(0)

func neutral() -> void:
	editor.select_animation_by_id(&"T-Pose")
	editor.set_playing(false)
	editor.animation_player.pause()
	var sk := editor.model_root.find_child("Skeleton3D",true,false) as Skeleton3D
	assert(sk!=null)
	sk.reset_bone_poses()
	sk.force_update_all_bone_transforms()
	for pair in [["L",-72.0],["R",72.0]]:
		var bone := sk.find_bone("J_Bip_"+str(pair[0])+"_UpperArm")
		var pose := sk.get_bone_global_rest(bone)
		pose.basis=Basis(Vector3(0,0,1),deg_to_rad(float(pair[1])))*pose.basis
		sk.set_bone_global_pose(bone,pose)
	sk.force_update_all_bone_transforms()

func combinations() -> void:
	for hi in range(1,5):
		assert(editor.select_part_by_id(&"hair",StringName("hair_short_0%d" % hi)))
		neutral()
		editor.set_preview_yaw_degrees(35)
		frame_camera("head")
		await capture("%s_hair_%d" % [sex,hi])
	assert(editor.select_part_by_id(&"helmet",&"none"))
	frame_camera("head")
	await capture(sex+"_hair_restored")
	assert(editor.select_part_by_id(&"hair",&"hair_short_01"))
	assert(editor.select_part_by_id(&"armor",&"armor_chinese_leather_01"))
	neutral()
	editor.set_preview_yaw_degrees(35)
	frame_camera()
	await capture(sex+"_armor_only")
	assert(editor.select_part_by_id(&"helmet",&"helmet_mingguang_01"))
	assert(editor.select_part_by_id(&"armor",&"none"))
	frame_camera()
	await capture(sex+"_helmet_only")
	for pair in [[&"armor",&"armor_chinese_leather_01"],[&"boots",&"boots_leather_01"],[&"cape",&"cape_chinese_01"],[&"weapon",&"longsword_01"],[&"shield",&"shield_heater_01"]]:
		assert(editor.select_part_by_id(pair[0],pair[1]))
	for clip in [&"idle",&"run",&"guard"]:
		assert(editor.select_animation_by_id(clip))
		editor.set_playing(false)
		editor.animation_player.seek(editor.animation_player.get_animation(clip).length*.6,true)
		for angle in [35.0,145.0]:
			editor.set_preview_yaw_degrees(angle)
			frame_camera()
			await capture("%s_full_%s_%d" % [sex,clip,int(angle)])
	for pair in [[&"cape",&"none"],[&"weapon",&"none"],[&"shield",&"none"],[&"boots",&"none"]]:
		assert(editor.select_part_by_id(pair[0],pair[1]))

func frame_camera(detail: String="") -> void:
	var center := Vector3(0,.99,0)
	editor.camera.size=2.35
	if editor.selected_animation==&"attack_jump_heavy":
		center.y=1.35
		editor.camera.size=3.35
	elif editor.selected_animation==&"attack_axe": editor.camera.size=2.8
	elif str(editor.selected_animation).begins_with("ride_"):
		center.y=1.30
		editor.camera.size=4.0
	if detail=="head":
		center.y=1.69 if sex=="male" else 1.56
		editor.camera.size=.7
	elif detail=="chest":
		center.y=1.26 if sex=="male" else 1.17
		editor.camera.size=.7
	editor.camera.position=center+Vector3(0,0,-5)
	editor.camera.look_at(center)

func capture(filename: String) -> void:
	await settle(3)
	await RenderingServer.frame_post_draw
	assert(editor.preview_viewport.get_texture().get_image().save_png(DIR+"/"+filename+".png")==OK)

func settle(frames: int) -> void:
	for i in frames: await process_frame
