extends SceneTree

const DIR := "res://.visual_captures/chinese_cloak_remake"
var editor: HumanCharacter3DEditor
var sex := "male"
var mode := "review"
var timing := {}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): sex = args[0]
	if args.size() > 1: mode = args[1]
	if args.size() > 2 and FileAccess.file_exists(DIR + "/" + sex + "_timing.json"):
		timing = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/" + sex + "_timing.json"))
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	editor = load("res://scenes/ui/HumanCharacter3DEditor.tscn").instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	await settle(4)
	var index := 1 if sex == "female" else 0
	if mode != "final":
		editor._load_body_model(index, "res://assets/characters/human/q35/chinese_cloak/candidate_%s.glb" % sex)
	else:
		editor._load_body_model(index)
	await settle(8)
	editor.preview_viewport.size = Vector2i(1024,1280)
	editor.preview_viewport.msaa_3d = Viewport.MSAA_4X
	select_parts()
	assert(editor.select_part_by_id(&"cape", &"none"))
	assert(not editor.model_root.find_child("Cape_Chinese_01_Main", true, false).visible)
	assert(editor.select_part_by_id(&"cape", &"cape_travel_01"))
	assert(editor.select_part_by_id(&"cape", &"cape_chinese_01"))
	for node in editor.model_root.find_children("Cape_Chinese_01_*", "MeshInstance3D", true, false):
		assert(node.visible, "Cloak component not enabled")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	editor.animation_player.seek(0.0, true)
	for view in [["front",0.0],["threequarter",35.0],["side",90.0],["back",180.0]]:
		editor.set_preview_yaw_degrees(float(view[1]))
		frame_camera()
		await capture(sex + "_" + str(view[0]))
	editor.set_preview_yaw_degrees(0)
	frame_camera(true)
	await capture(sex + "_collar")
	await capture_neutral_views()
	await capture_combinations()
	var clips: Array[StringName] = [&"idle",&"walk",&"run",&"guard",&"attack_jump_heavy",&"ride_slash"]
	if mode == "full" or mode == "final":
		clips.clear()
		var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/human/q35/standard_anime_%s_character_pack.json" % sex))
		for clip in metadata.animations:
			if clip != "T-Pose": clips.append(StringName(clip))
	if args.size() > 2:
		clips.clear()
		if args[2] != "views":
			for clip in args[2].split(",",false): clips.append(StringName(clip))
	for clip in clips:
		editor.set_mount_enabled(str(clip).begins_with("ride_"))
		assert(editor.select_animation_by_id(clip), "Missing clip " + str(clip))
		editor.set_playing(false)
		var resolved := editor.selected_animation
		var animation := editor.animation_player.get_animation(resolved)
		var morph_count := 0
		for ti in animation.get_track_count():
			if animation.track_get_type(ti) == Animation.TYPE_BLEND_SHAPE: morph_count += 1
		assert(morph_count > 0, "Cloak shape tracks missing: " + str(clip))
		editor.set_preview_yaw_degrees(35.0 if not str(clip).begins_with("ride_") else 90.0)
		var steps := 16 if mode in ["full","final"] else 7
		timing[str(clip)] = {"duration":animation.length,"frames":steps,"resolved":str(resolved)}
		for si in steps:
			editor.animation_player.seek(animation.length * float(si)/float(steps-1),true)
			editor.animation_player.advance(0.0)
			frame_camera(false,str(clip).begins_with("ride_"))
			await capture("%s_%s_%02d" % [sex,clip,si])
		print("CLOAK_CAPTURE_CLIP ",sex," ",clip," frames=",steps," duration=",animation.length," morph_tracks=",morph_count," resolved=",resolved)
	editor.set_mount_enabled(false)
	editor.select_animation_by_id(&"idle")
	editor.set_playing(false)
	editor.animation_player.seek(0.0,true)
	editor.set_preview_yaw_degrees(35)
	editor._update_preview_framing()
	await capture(sex + "_gameplay_scale")
	frame_camera()
	await settle(3)
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(DIR + "/" + sex + "_editor_selected.png") == OK)
	print("CHINESE_CLOAK_EDITOR_CAPTURE_PASS ",sex," ",mode)
	var manifest := FileAccess.open(DIR + "/" + sex + "_timing.json",FileAccess.WRITE)
	manifest.store_string(JSON.stringify(timing,"  "))
	manifest.close()
	editor.queue_free()
	await settle(4)
	quit(0)

func select_parts() -> void:
	for pair in [[&"helmet",&"none"],[&"armor",&"armor_light_leather_01"],[&"cape",&"cape_chinese_01"],[&"boots",&"boots_leather_01"],[&"weapon",&"none"],[&"shield",&"none"],[&"outfit",&"outfit_underlayer_01"]]:
		assert(editor.select_part_by_id(pair[0],pair[1]))

func capture_neutral_views() -> void:
	editor.select_animation_by_id(&"T-Pose")
	editor.set_playing(false)
	editor.animation_player.pause()
	var skeleton := editor.model_root.find_child("Skeleton3D",true,false) as Skeleton3D
	assert(skeleton != null)
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	for pair in [["L",-80.0],["R",80.0]]:
		var bone := skeleton.find_bone("J_Bip_" + str(pair[0]) + "_UpperArm")
		var pose := skeleton.get_bone_global_rest(bone)
		pose.basis = Basis(Vector3(0,0,1),deg_to_rad(float(pair[1]))) * pose.basis
		skeleton.set_bone_global_pose(bone,pose)
	skeleton.force_update_all_bone_transforms()
	for node in editor.model_root.find_children("Cape_Chinese_01_*","MeshInstance3D",true,false):
		var mesh := node as MeshInstance3D
		for shape in mesh.get_blend_shape_count(): mesh.set_blend_shape_value(shape,0.0)
	for view in [["front",0.0],["threequarter",35.0],["right",90.0],["left",-90.0],["back",180.0]]:
		editor.set_preview_yaw_degrees(float(view[1]))
		frame_camera()
		await capture(sex + "_neutral_" + str(view[0]))
	var visibility := {}
	editor.set_preview_yaw_degrees(35)
	frame_camera()
	editor.set_process(false)
	for node in editor.model_root.find_children("*","MeshInstance3D",true,false):
		visibility[node] = node.visible
		if not str(node.name).begins_with("Cape_Chinese_01_"): node.visible = false
	await capture(sex + "_cloak_only")
	for node in visibility:
		if not str(node.name).begins_with("Cape_Chinese_01_"):
			assert(not node.visible, "Non-cloak mesh reappeared during isolated capture")
	for node in visibility: node.visible = visibility[node]
	editor.set_process(true)

func capture_combinations() -> void:
	for outfit in [["underlayer",&"none",&"none",&"none"],["leather",&"armor_light_leather_01",&"boots_leather_01",&"helmet_leather_01"],["iron",&"armor_iron_01",&"boots_iron_01",&"helmet_iron_01"],["mingguang",&"armor_mingguang_01",&"boots_mingguang_01",&"helmet_steel_01"]]:
		assert(editor.select_part_by_id(&"armor",outfit[1]))
		assert(editor.select_part_by_id(&"boots",outfit[2]))
		assert(editor.select_part_by_id(&"helmet",outfit[3]))
		assert(editor.select_part_by_id(&"weapon",&"none" if outfit[0] == "underlayer" else &"longsword_01"))
		assert(editor.select_part_by_id(&"shield",&"none" if outfit[0] == "underlayer" else &"shield_heater_01"))
		for clip in [&"idle",&"run",&"guard"]:
			assert(editor.select_animation_by_id(clip))
			editor.set_playing(false)
			editor.animation_player.seek(editor.animation_player.get_animation(clip).length * 0.6,true)
			editor.set_preview_yaw_degrees(35)
			frame_camera()
			await capture("%s_combo_%s_%s" % [sex,outfit[0],clip])
	select_parts()

func frame_camera(close: bool = false, mounted: bool = false) -> void:
	var center := Vector3(0,0.87,0)
	editor.camera.size = 2.05
	if editor._selected_animation == &"attack_jump_heavy":
		center.y = 1.35
		editor.camera.size = 3.1
	elif editor._selected_animation == &"down":
		center.y = 0.65
		editor.camera.size = 3.25
	elif editor._selected_animation == &"guard":
		editor.camera.size = 2.6
	elif editor._selected_animation in [&"hit", &"hit_back", &"attack_axe", &"attack_hammer"]:
		editor.camera.size = 2.9
	if close:
		center.y = 1.35 if sex == "male" else 1.24
		editor.camera.size = 0.62
	if mounted:
		center.y = 1.25
		editor.camera.size = 4.0
	editor.camera.position = center + Vector3(0,0.05,-5)
	editor.camera.look_at(center)

func capture(filename: String) -> void:
	await settle(3)
	await RenderingServer.frame_post_draw
	var picture := editor.preview_viewport.get_texture().get_image()
	assert(picture != null and not picture.is_empty())
	assert(picture.save_png(DIR + "/" + filename + ".png") == OK)

func settle(frames: int) -> void:
	for i in frames: await process_frame
