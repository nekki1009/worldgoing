extends "res://scripts/tests/capture_chinese_leather_mingguang.gd"

var CLOTH_OUT := "res://output/medieval_cloth_armor_20260916/final"
const STYLES := ["chinese", "japanese", "european"]
const Dye = preload("res://scripts/ui/equipment_dye.gd")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): sex = args[0]
	mode = args[1] if args.size() > 1 else "candidate"
	var probe := args.size() > 3 and args[3] == "--probe"
	if args.size() > 2:
		CLOTH_OUT = args[2].simplify_path()
		assert(CLOTH_OUT.begins_with("res://output/") and CLOTH_OUT.ends_with("/final"))
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.content_scale_size = Vector2i(2560, 1600)
	editor = load("res://scenes/ui/HumanCharacter3DEditor.tscn").instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	await settle(4)
	var gender := 1 if sex == "female" else 0
	if mode == "final": editor._load_body_model(gender)
	else: editor._load_body_model(gender, "res://assets/characters/human/q35/medieval_cloth/candidate_%s.glb" % sex)
	await settle(6)
	editor.preview_viewport.size = Vector2i(1024, 1280)
	editor.preview_viewport.msaa_3d = Viewport.MSAA_4X
	editor.preview_viewport.use_debanding = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CLOTH_OUT))
	for slot in [&"armor", &"helmet", &"boots", &"cape", &"weapon", &"shield"]:
		assert(editor.select_part_by_id(slot, &"none"))
	var body := editor.model_root.find_child("Body_Standard_Female" if gender == 1 else "Body_Standard_Male", true, false) as MeshInstance3D
	assert(editor.select_part_by_id(&"outfit", &"outfit_underlayer_01"))
	var original_body := body.mesh
	for style: String in (["japanese"] if probe else STYLES):
		var id := StringName("outfit_medieval_" + style + "_01")
		assert(editor.select_part_by_id(&"armor", id))
		assert(body.mesh != original_body, "Missing reversible clothing coverage")
		neutral()
		assert(editor.set_equipment_dyes({}))
		for view in [["front",0.0],["back",180.0],["left",-90.0],["right",90.0],["threequarter",35.0]]:
			editor.set_preview_yaw_degrees(view[1])
			frame_camera()
			await capture(sex+"_"+style+"_"+str(view[0]))
		var before_dye: PackedByteArray = editor.preview_viewport.get_texture().get_image().get_data()
		editor.set_preview_yaw_degrees(0)
		frame_camera("chest")
		await capture(sex+"_"+style+"_seams")
		for palette: String in ([] if probe else Dye.PRESETS.keys()):
			assert(editor.set_equipment_dyes({"armor": Dye.PRESETS[palette].colors.armor}))
			assert(editor.capture_appearance().equipment_dyes.armor == Dye.PRESETS[palette].colors.armor)
			var found := false
			for entry: Dictionary in editor._equipment_dye_surfaces:
				if entry.slot == "armor" and entry.node.is_visible_in_tree():
					found = true
					var shader := entry.node.get_active_material(entry.surface) as ShaderMaterial
					assert(shader != null and shader.get_shader_parameter("has_texture"))
			assert(found, "New outfit has no real dye surface")
			frame_camera()
			await capture(sex+"_"+style+"_palette_"+palette)
		assert(editor.set_equipment_dyes({"armor": "27ab83ff"}))
		assert(HumanCharacter3DEditor.valid_appearance(editor.capture_appearance()))
		# JSON round trip through the same appearance contract; do not reload
		# the formal pack when this capture is testing an unpublished candidate.
		var saved := editor.capture_appearance()
		assert(JSON.parse_string(JSON.stringify(saved)).equipment_dyes.armor == "27ab83ff")
		editor.set_preview_yaw_degrees(35)
		frame_camera()
		await capture(sex+"_"+style+"_custom")
		assert(before_dye != editor.preview_viewport.get_texture().get_image().get_data(), "Custom dye did not change actual pixels")
		assert(editor.set_equipment_dyes({}))
		await capture(sex+"_"+style+"_reset")
		assert(before_dye == editor.preview_viewport.get_texture().get_image().get_data(), "Dye reset did not restore exact original pixels")
		for clip in ([&"run", &"attack_crossbow"] if probe else [&"idle", &"walk", &"run", &"guard", &"attack_sword", &"attack_bow", &"attack_crossbow", &"attack_jump_heavy"]):
			assert(editor.select_animation_by_id(clip))
			editor.set_playing(false)
			var animation := editor.animation_player.get_animation(editor.selected_animation)
			var prefix := "Outfit_Medieval_" + style.capitalize() + "_01_"
			var skirt := editor.model_root.find_child(prefix + ("Skirt" if gender == 1 else "TunicSkirt"), true, false) as MeshInstance3D
			assert(skirt != null and skirt.get_blend_shape_count() > 100)
			var varying: Array[float] = []
			# The editor deliberately aliases attack_sword to walk_slash.
			var key := skirt.find_blend_shape_by_name("Cloth_"+str(editor.selected_animation)+"_00")
			assert(key >= 0)
			for sample in range(25):
				editor.animation_player.seek(animation.length * float(sample)/24.0, true)
				editor.animation_player.advance(0)
				varying.append(skirt.get_blend_shape_value(key))
				editor.set_preview_yaw_degrees(35)
				frame_camera()
				await capture("%s_%s_%s_%02d" % [sex,style,clip,sample])
			assert(varying.max()-varying.min() > .5, "Cloth morph not synchronized: "+str(clip))
		for armor in [&"armor_light_leather_01", &"armor_chinese_leather_01", &"armor_western_iron_01"]:
			assert(editor.select_part_by_id(&"armor", armor))
			assert(editor.select_part_by_id(&"boots", &"boots_leather_01"))
			var cloth_prefix := "Outfit_Medieval_" + style.capitalize() + "_01_"
			var cloth_skirt := editor.model_root.find_child(cloth_prefix + ("Skirt" if gender == 1 else "TunicSkirt"), true, false) as MeshInstance3D
			var fitted_skirt := editor.model_root.find_child(str(cloth_skirt.name) + "Armored", true, false) as MeshInstance3D
			assert(not cloth_skirt.visible and (fitted_skirt == null or not fitted_skirt.visible), "Armor and skirts must be exclusive")
			var pants_name := "Armor_Light_Leather_01_Pants" if armor == &"armor_light_leather_01" else "Armor_Western_Iron_01_UnderPants"
			var inner_pants := editor.model_root.find_child(pants_name, true, false) as MeshInstance3D
			if armor != &"armor_chinese_leather_01":
				assert(inner_pants != null and inner_pants.visible, "Original armor trousers did not restore")
			for cloth in editor.model_root.find_children("Outfit_Medieval_*", "MeshInstance3D", true, false):
				assert(not cloth.visible, "Cloth armor overlaps another armor selection")
			neutral()
			for yaw in [35.0,145.0]:
				editor.set_preview_yaw_degrees(yaw)
				frame_camera()
				await capture("%s_%s_%s_neutral_%d" % [sex,style,armor,int(yaw)])
			for clip in ([&"idle", &"run"] if probe else [&"idle", &"walk", &"run", &"attack_crossbow"]):
				assert(editor.select_animation_by_id(clip))
				editor.set_playing(false)
				var duration := editor.animation_player.get_animation(editor.selected_animation).length
				for sample in range(1 if probe or clip == &"idle" else 14):
					editor.animation_player.seek(.3 if sample == 0 else duration*float(sample-1)/12.0, true)
					assert(not cloth_skirt.visible and (fitted_skirt == null or not fitted_skirt.visible), "Animation re-enabled an incompatible skirt")
					for yaw in [35.0,145.0]:
						editor.set_preview_yaw_degrees(yaw)
						frame_camera()
						await capture("%s_%s_%s_%s_%d_%02d" % [sex,style,armor,clip,int(yaw),sample])
		assert(editor.select_part_by_id(&"armor", &"none"))
		assert(editor.select_part_by_id(&"boots", &"none"))
		for original in [&"outfit_underlayer_01", &"outfit_chinese_lining_01", &"none"]:
			assert(editor.select_part_by_id(&"outfit", original))
			for node in editor.model_root.find_children("Outfit_Medieval_*", "MeshInstance3D", true, false): assert(not node.visible)
			if original != &"outfit_chinese_lining_01": assert(body.mesh == original_body, "Undressing did not restore exact body")
		assert(editor.select_part_by_id(&"outfit", &"outfit_underlayer_01"))
		assert(editor.select_part_by_id(&"armor", id))
		assert(editor.select_animation_by_id(&"idle"))
		editor.set_playing(false)
		editor.animation_player.seek(0, true)
		editor._update_preview_framing()
		await capture(sex+"_"+style+"_gameplay_scale")
		frame_camera()
		await settle(3)
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(CLOTH_OUT+"/"+sex+"_"+style+"_editor.png") == OK)
		print("MEDIEVAL_CLOTH_STYLE_PASS ", sex, " ", style)
	editor.queue_free()
	await settle(3)
	print("MEDIEVAL_CLOTH_PROBE_PASS " if probe else "MEDIEVAL_CLOTH_EDITOR_PASS ",sex," ",mode)
	quit(0)

func frame_camera(detail: String = "") -> void:
	super.frame_camera(detail)
	if detail.is_empty() and editor.selected_animation != &"attack_jump_heavy":
		var center := Vector3(0, .84 if sex == "female" else .91, 0)
		editor.camera.size = 1.95 if sex == "female" else 2.05
		editor.camera.position = center + Vector3(0, 0, -5)
		editor.camera.look_at(center)

func capture(filename: String) -> void:
	await settle(2)
	await RenderingServer.frame_post_draw
	assert(editor.preview_viewport.get_texture().get_image().save_png(CLOTH_OUT+"/"+filename+".png") == OK)
