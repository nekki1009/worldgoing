extends SceneTree
## Same deterministic captures before/after an additive hat publication.
var OUT := "res://output/cloth_hats_20260918"
var samples := {}
var phase := "before"
var editor
var sex := "male"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	phase = args[0]
	sex = args[1]
	if "--neutral-faces" in args: OUT = "res://output/neutral_faces_20260918"
	var folder := OUT+"/regression/"+phase+"/"+sex
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	editor = load("res://scenes/ui/HumanCharacter3DEditor.tscn").instantiate()
	var old_version := phase == "before_fixed"
	if old_version:
		var original_script := GDScript.new()
		original_script.source_code = FileAccess.get_file_as_string(OUT+"/baseline/human_character_3d_editor.gd.txt").replace("class_name HumanCharacter3DEditor\n", "")
		assert(original_script.reload() == OK)
		editor.set_script(original_script)
	root.add_child(editor)
	editor.open()
	await settle(3)
	var gender := 1 if sex == "female" else 0
	editor._load_body_model(gender,OUT+"/baseline/standard_anime_%s_character_pack.glb" % sex if old_version else "")
	await settle(4)
	editor.preview_viewport.size = Vector2i(256,320)
	editor.preview_viewport.msaa_3d = Viewport.MSAA_DISABLED
	editor.preview_viewport.use_debanding = false
	var original := HumanCharacter3DEditor.default_appearance(gender)
	assert(editor.restore_appearance(original))
	if "--neutral-faces" in args:
		for face_number in range(1,5):
			assert(editor.select_part_by_id(&"face",StringName("face_standard_%02d" % face_number)))
			for angle in [0.0,35.0,90.0]:
				neutral()
				editor.set_preview_yaw_degrees(angle)
				frame_camera("head")
				await sample_image(folder,"old_face_%02d_%d" % [face_number,int(angle)])
		assert(editor.select_part_by_id(&"face",&"face_standard_01"))
		for style in ["chinese","japanese","western"]:
			assert(editor.select_part_by_id(&"helmet",StringName("helmet_cloth_"+style+"_01")))
			for angle in [0.0,35.0,90.0]:
				neutral()
				editor.set_preview_yaw_degrees(angle)
				frame_camera("head")
				await sample_image(folder,"cloth_hat_"+style+"_%d" % int(angle))
		assert(editor.restore_appearance(original))
	for choice in ["none","helmet_leather_01","helmet_iron_01","helmet_steel_01","helmet_mingguang_01","helmet_chinese_leather_01","helmet_western_iron_01"]:
		assert(editor.select_part_by_id(&"helmet",StringName(choice)))
		for angle in [0.0,90.0,180.0]:
			neutral()
			editor.set_preview_yaw_degrees(angle)
			frame_camera("head")
			await sample_image(folder,"head_%s_%d" % [choice,int(angle)])
	assert(editor.select_part_by_id(&"helmet",&"none"))
	assert(editor.select_part_by_id(&"shield",&"none"))
	for option: Dictionary in editor.WeaponMaterials.OPTIONS:
		if option.id == &"none": continue
		assert(editor.select_part_by_id(&"weapon",option.id))
		for clip in [&"run",editor.WeaponMaterials.ATTACKS[editor.WeaponMaterials.family(option.id)]]:
			assert(editor.select_animation_by_id(clip))
			editor.set_playing(false)
			editor.animation_player.seek(editor.animation_player.get_animation(editor.selected_animation).length*.6,true)
			editor.animation_player.advance(0)
			editor.set_preview_yaw_degrees(35)
			frame_camera()
			await sample_image(folder,"weapon_%s_%s" % [option.id,clip])
	assert(editor.restore_appearance(original))
	for style in ["chinese","japanese","european"]:
		assert(editor.select_part_by_id(&"armor",StringName("outfit_medieval_"+style+"_01")))
		assert(editor.select_part_by_id(&"boots",StringName("boots_medieval_"+style+"_01")))
		assert(editor.set_equipment_dyes({"armor":"396fbbff","boots":"29be89ff"}))
		neutral()
		editor.set_preview_yaw_degrees(35)
		frame_camera()
		await sample_image(folder,"cloth_"+style)
	assert(editor.restore_appearance(original))
	for hair: Dictionary in editor.HAIR_OPTIONS[gender]:
		if hair.id == &"none": continue
		assert(editor.select_part_by_id(&"hair",hair.id))
		neutral()
		editor.set_preview_yaw_degrees(145)
		frame_camera("head")
		await sample_image(folder,str(hair.id))
	var report := {"samples":samples,"phase":phase,"sex":sex,"count":samples.size(),"editor_md5":FileAccess.get_md5(OUT+"/baseline/human_character_3d_editor.gd.txt" if old_version else "res://scripts/ui/human_character_3d_editor.gd"),"dye_md5":FileAccess.get_md5("res://scripts/ui/equipment_dye.gd"),"glb_md5":FileAccess.get_md5(OUT+"/baseline/standard_anime_%s_character_pack.glb" % sex if old_version else (editor.FEMALE_MODEL_PATH if gender == 1 else editor.MALE_MODEL_PATH))}
	if phase == "after_fixed":
		var before: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT+"/regression/before_fixed/"+sex+"/result.json"))
		if before.samples != samples:
			push_error("Old equipment rendered differently; do not recertify atlases")
			quit(1)
			return
	var file := FileAccess.open(folder+"/result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("CLOTH_HATS_REGRESSION_PASS ",phase," ",sex," ",samples.size())
	editor.queue_free()
	await settle(3)
	quit(0)

func sample_image(folder: String,label: String) -> void:
	await settle(3)
	await RenderingServer.frame_post_draw
	var pixels: Image = editor.preview_viewport.get_texture().get_image()
	var hash := HashingContext.new()
	assert(hash.start(HashingContext.HASH_SHA256) == OK)
	assert(hash.update(pixels.get_data()) == OK)
	samples[label] = hash.finish().hex_encode()
	assert(pixels.save_png(folder+"/"+label+".png") == OK)

func settle(frames: int) -> void:
	for i in frames: await process_frame

func neutral() -> void:
	editor.select_animation_by_id(&"T-Pose")
	editor.set_playing(false)
	editor.animation_player.pause()
	# T-Pose predates the white-plume weight tracks. A skeleton reset alone
	# retains a wall-clock-dependent idle morph: explicitly set neutral weights.
	for node in editor.model_root.find_children("Helmet_Mingguang_*","MeshInstance3D",true,false):
		for i in node.get_blend_shape_count(): node.set_blend_shape_value(i,0.0)
	var sk := editor.model_root.find_child("Skeleton3D",true,false) as Skeleton3D
	sk.reset_bone_poses()
	sk.force_update_all_bone_transforms()
	for pair in [["L",-72.0],["R",72.0]]:
		var bone := sk.find_bone("J_Bip_"+str(pair[0])+"_UpperArm")
		var pose := sk.get_bone_global_rest(bone)
		pose.basis = Basis(Vector3(0,0,1),deg_to_rad(float(pair[1])))*pose.basis
		sk.set_bone_global_pose(bone,pose)
	sk.force_update_all_bone_transforms()

func frame_camera(detail: String = "") -> void:
	var center := Vector3(0,.99,0)
	editor.camera.size = 2.35
	if editor.selected_animation == &"attack_axe": editor.camera.size = 2.8
	if detail == "head":
		center.y = 1.69 if sex == "male" else 1.56
		editor.camera.size = .7
	editor.camera.position = center+Vector3(0,0,-5)
	editor.camera.look_at(center)
