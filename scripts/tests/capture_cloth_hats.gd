extends "res://scripts/tests/capture_chinese_leather_mingguang.gd"

const HAT_OUT := "res://output/cloth_hats_20260918"
const STYLES := ["chinese","japanese","western"]
const Dye = preload("res://scripts/ui/equipment_dye.gd")
var destination := ""
var captured := 0

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	sex = args[0]
	mode = args[1]
	var probe := "--probe" in args
	destination = HAT_OUT+"/"+mode
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination))
	DisplayServer.window_set_size(Vector2i(1600,1000))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.content_scale_size = Vector2i(2560,1600)
	editor = load("res://scenes/ui/HumanCharacter3DEditor.tscn").instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	await settle(3)
	var gender := 1 if sex == "female" else 0
	if mode == "final": editor._load_body_model(gender)
	else: editor._load_body_model(gender,"res://assets/characters/human/q35/cloth_hats/candidate_%s.glb" % sex)
	await settle(5)
	editor.preview_viewport.size = Vector2i(1024,1024)
	editor.preview_viewport.msaa_3d = Viewport.MSAA_4X
	editor.preview_viewport.use_debanding = false
	for slot in [&"armor",&"helmet",&"cape",&"weapon",&"shield"]: assert(editor.select_part_by_id(slot,&"none"))
	assert(editor.select_part_by_id(&"outfit",&"outfit_underlayer_01"))
	for style: String in STYLES:
		var id := StringName("helmet_cloth_"+style+"_01")
		var prefix := "Helmet_Cloth_"+style.capitalize()+"_01_"
		var cloth_style := "european" if style == "western" else style
		assert(editor.select_part_by_id(&"armor",StringName("outfit_medieval_"+cloth_style+"_01")))
		assert(editor.select_part_by_id(&"boots",StringName("boots_medieval_"+cloth_style+"_01")))
		for choice in [id,&"none",&"helmet_leather_01",&"helmet_iron_01",&"helmet_steel_01",id]:
			assert(editor.select_part_by_id(&"helmet",choice))
			for node in editor.model_root.find_children("Helmet_Cloth_*","MeshInstance3D",true,false):
				assert(node.visible == (choice == id and str(node.name).begins_with(prefix)))
		var crown := editor.model_root.find_child(prefix+"Crown",true,false) as MeshInstance3D
		assert(crown != null)
		var fabric := crown.get_active_material(0) as BaseMaterial3D
		assert(fabric != null and fabric.metallic == 0.0 and fabric.roughness > .85 and fabric.albedo_texture != null,"Need real matte woven cloth in engine")
		assert(editor.select_part_by_id(&"hair",StringName("hair_female_03" if gender == 1 else "hair_male_01")))
		editor.set_hair_mask_mode(&"auto")
		neutral()
		assert(editor.set_equipment_dyes({}))
		for view in [["front",0.0],["side",90.0],["back",180.0],["threequarter",35.0]]:
			editor.set_preview_yaw_degrees(view[1])
			hat_camera()
			await capture(sex+"_"+style+"_"+view[0])
		var before := editor.preview_viewport.get_texture().get_image().get_data()
		for palette: String in (["red"] if probe else Dye.PRESETS.keys()):
			assert(editor.set_equipment_dyes({"helmet":Dye.PRESETS[palette].colors.helmet}))
			assert(editor.capture_appearance().equipment_dyes == {"helmet":Dye.PRESETS[palette].colors.helmet})
			await capture(sex+"_"+style+"_palette_"+palette)
		assert(editor.set_equipment_dyes({"helmet":"29be89ff"}))
		await capture(sex+"_"+style+"_custom")
		assert(before != editor.preview_viewport.get_texture().get_image().get_data())
		assert(editor.set_equipment_dyes({}))
		await capture(sex+"_"+style+"_reset")
		assert(before == editor.preview_viewport.get_texture().get_image().get_data(),"Dye reset must restore exact pixels")
		for hi in range(1,9):
			var hair := StringName("hair_%s_%02d" % [sex,hi])
			assert(editor.select_part_by_id(&"hair",hair))
			assert(editor.select_part_by_id(&"helmet",&"none"))
			neutral()
			editor.set_preview_yaw_degrees(35)
			hat_camera()
			await settle(3)
			await RenderingServer.frame_post_draw
			var original := editor.preview_viewport.get_texture().get_image().get_data()
			assert(editor.select_part_by_id(&"helmet",id))
			for view in [["front",35.0],["back",180.0]]:
				editor.set_preview_yaw_degrees(view[1])
				hat_camera()
				await capture("%s_%s_hair_%02d_%s" % [sex,style,hi,view[0]])
			assert(editor.select_part_by_id(&"helmet",&"none"))
			editor.set_preview_yaw_degrees(35)
			hat_camera()
			await settle(3)
			await RenderingServer.frame_post_draw
			assert(original == editor.preview_viewport.get_texture().get_image().get_data(),"Removing cap did not restore hair: "+str(hair))
		assert(editor.select_part_by_id(&"helmet",id))
		assert(editor.select_part_by_id(&"hair",StringName("hair_female_03" if gender == 1 else "hair_male_01")))
		neutral()
		editor.set_preview_yaw_degrees(35)
		frame_camera()
		await capture(sex+"_"+style+"_outfit")
		for clip in ([&"run"] if probe else [&"idle",&"walk",&"run",&"attack_axe",&"attack_crossbow",&"attack_jump_heavy"]):
			assert(editor.select_animation_by_id(clip))
			editor.set_playing(false)
			var animation := editor.animation_player.get_animation(editor.selected_animation)
			for sample in range(9):
				editor.animation_player.seek(animation.length*float(sample)/8.0,true)
				editor.animation_player.advance(0)
				editor.set_preview_yaw_degrees(35)
				hat_camera()
				await capture("%s_%s_%s_%02d" % [sex,style,clip,sample])
		# Original armor and cape combinations, without touching their material state.
		for armor in [&"armor_light_leather_01",&"armor_iron_01",&"armor_western_iron_01"]:
			assert(editor.select_part_by_id(&"armor",armor))
			assert(editor.select_part_by_id(&"cape",&"cape_chinese_01"))
			neutral()
			editor.set_preview_yaw_degrees(35)
			frame_camera()
			await capture("%s_%s_combo_%s" % [sex,style,armor])
		assert(editor.select_part_by_id(&"cape",&"none"))
		assert(editor.select_part_by_id(&"armor",StringName("outfit_medieval_"+cloth_style+"_01")))
		neutral()
		editor.set_preview_yaw_degrees(35)
		frame_camera()
		await settle(3)
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(destination+"/"+sex+"_"+style+"_editor.png") == OK)
		print("CLOTH_HATS_STYLE_PASS ",sex," ",style)
	var file := FileAccess.open(destination+"/"+sex+"_result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"sex":sex,"mode":mode,"probe":probe,"captures":captured,"styles":STYLES,"hair_options_each":8,"hair_restore":true,"material":"cloth","palettes":1 if probe else 16,"custom_and_reset":true},"  "))
	file.close()
	editor.queue_free()
	await settle(3)
	print("CLOTH_HATS_EDITOR_PASS ",sex," ",mode," ",captured)
	quit(0)

func hat_camera() -> void:
	var sk := editor.model_root.find_child("Skeleton3D",true,false) as Skeleton3D
	sk.force_update_all_bone_transforms()
	var center := (sk.global_transform*sk.get_bone_global_pose(sk.find_bone("J_Bip_C_Head"))).origin+Vector3(0,.12,0)
	editor.camera.size = .66
	editor.camera.position = center+Vector3(0,.035,-5)
	editor.camera.look_at(center)

func capture(filename: String) -> void:
	await settle(3)
	await RenderingServer.frame_post_draw
	assert(editor.preview_viewport.get_texture().get_image().save_png(destination+"/"+filename+".png") == OK)
	captured += 1
