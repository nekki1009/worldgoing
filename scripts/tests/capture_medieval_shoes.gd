extends "res://scripts/tests/capture_chinese_leather_mingguang.gd"

const SHOE_OUT := "res://output/medieval_shoes_20260916"
const STYLES := ["chinese", "japanese", "european"]
const Dye = preload("res://scripts/ui/equipment_dye.gd")
var destination: String

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): sex = args[0]
	mode = args[1] if args.size() > 1 else "candidate"
	var probe := args.size() > 2 and args[2] == "--probe"
	destination = SHOE_OUT + "/" + mode
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination))
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.content_scale_size = Vector2i(2560, 1600)
	editor = load("res://scenes/ui/HumanCharacter3DEditor.tscn").instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	await settle(3)
	var gender := 1 if sex == "female" else 0
	if mode == "final": editor._load_body_model(gender)
	else: editor._load_body_model(gender, "res://assets/characters/human/q35/medieval_shoes/candidate_%s.glb" % sex)
	await settle(5)
	editor.preview_viewport.size = Vector2i(1024, 1024)
	editor.preview_viewport.msaa_3d = Viewport.MSAA_4X
	editor.preview_viewport.use_debanding = false
	for slot in [&"armor", &"helmet", &"boots", &"cape", &"weapon", &"shield"]:
		assert(editor.select_part_by_id(slot, &"none"))
	assert(editor.select_part_by_id(&"outfit", &"outfit_underlayer_01"))
	var body := editor.model_root.find_child("Body_Standard_Female" if gender == 1 else "Body_Standard_Male", true, false) as MeshInstance3D
	var original_body := body.mesh
	for style: String in STYLES:
		var id := StringName("boots_medieval_"+style+"_01")
		var prefix := "Boots_Medieval_"+style.capitalize()+"_01_"
		for choice in [id, &"none", &"boots_leather_01", &"boots_iron_01", id]:
			assert(editor.select_part_by_id(&"boots", choice))
			for node in editor.model_root.find_children("Boots_Medieval_*", "MeshInstance3D", true, false):
				assert(node.visible == (choice == id and str(node.name).begins_with(prefix)))
		neutral()
		assert(body.mesh != original_body)
		assert(editor.set_equipment_dyes({}))
		for view in [["front",0.0],["back",180.0],["side",90.0],["threequarter",35.0]]:
			editor.set_preview_yaw_degrees(view[1])
			shoe_camera()
			await capture(sex+"_"+style+"_"+str(view[0]))
		var before := editor.preview_viewport.get_texture().get_image().get_data()
		var sole := editor.model_root.find_child(prefix+"Sole_L",true,false) as MeshInstance3D
		var original_sole := sole.get_active_material(0)
		for palette: String in (["red"] if probe else Dye.PRESETS.keys()):
			assert(editor.set_equipment_dyes({"boots":Dye.PRESETS[palette].colors.boots}))
			assert(editor.capture_appearance().equipment_dyes.boots == Dye.PRESETS[palette].colors.boots)
			assert(sole.get_active_material(0) == original_sole, "Sole must not be dyed")
			await capture(sex+"_"+style+"_palette_"+palette)
		assert(editor.set_equipment_dyes({"boots":"29be89ff"}))
		await capture(sex+"_"+style+"_custom")
		assert(before != editor.preview_viewport.get_texture().get_image().get_data(),"No shoe color pixel change")
		assert(editor.set_equipment_dyes({}))
		await capture(sex+"_"+style+"_reset")
		assert(before == editor.preview_viewport.get_texture().get_image().get_data(),"Shoe dye reset changed original pixels")
		assert(editor.select_part_by_id(&"armor",StringName("outfit_medieval_"+style+"_01")))
		for node in editor.model_root.find_children("Outfit_Medieval_*","MeshInstance3D",true,false):
			if not node.visible: continue
			var index: int = node.find_blend_shape_by_name("BootTuck")
			if index >= 0: assert(node.get_blend_shape_value(index) == 0.0,"Low shoes cannot force tall boot tuck")
		neutral()
		editor.set_preview_yaw_degrees(35)
		frame_camera()
		await capture(sex+"_"+style+"_outfit")
		for clip in ([&"run"] if probe else [&"idle", &"walk", &"run", &"attack_crossbow", &"attack_jump_heavy"]):
			assert(editor.select_animation_by_id(clip))
			editor.set_playing(false)
			var animation := editor.animation_player.get_animation(editor.selected_animation)
			var steps := 5 if probe else 17
			for sample in range(steps):
				editor.animation_player.seek(animation.length*float(sample)/float(steps-1),true)
				editor.animation_player.advance(0)
				editor.set_preview_yaw_degrees(35)
				shoe_camera(true)
				await capture("%s_%s_%s_%02d" % [sex,style,clip,sample])
		assert(editor.select_part_by_id(&"armor", &"none"))
		assert(editor.select_part_by_id(&"boots", &"none"))
		assert(body.mesh == original_body,"Unshoe did not restore original foot mesh")
		assert(editor.select_part_by_id(&"boots",id))
		assert(editor.select_part_by_id(&"armor",StringName("outfit_medieval_"+style+"_01")))
		neutral()
		editor.set_preview_yaw_degrees(35)
		frame_camera()
		await settle(3)
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(destination+"/"+sex+"_"+style+"_editor.png") == OK)
		assert(editor.select_part_by_id(&"armor", &"none"))
		print("MEDIEVAL_SHOES_STYLE_PASS ",sex," ",style)
	editor.queue_free()
	await settle(3)
	print("MEDIEVAL_SHOES_EDITOR_PASS ",sex," ",mode)
	quit(0)

func shoe_camera(animated: bool = false) -> void:
	var center := Vector3(0,.13,0)
	editor.camera.size = .59
	if animated:
		var sk := editor.model_root.find_child("Skeleton3D",true,false) as Skeleton3D
		sk.force_update_all_bone_transforms()
		var left := sk.global_transform*sk.get_bone_global_pose(sk.find_bone("J_Bip_L_Foot")).origin
		var right := sk.global_transform*sk.get_bone_global_pose(sk.find_bone("J_Bip_R_Foot")).origin
		center = (left+right)*.5
		editor.camera.size = maxf(.72,left.distance_to(right)+.45)
	editor.camera.position = center+Vector3(0,1.3,-5)
	editor.camera.look_at(center)

func capture(filename: String) -> void:
	await settle(2)
	await RenderingServer.frame_post_draw
	assert(editor.preview_viewport.get_texture().get_image().save_png(destination+"/"+filename+".png") == OK)
