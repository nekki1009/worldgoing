extends "res://scripts/tests/capture_chinese_leather_mingguang.gd"
## Offline CA-02 review through the original editor. Captures are not atlas admission or FPS proof.
var destination: String = ""
var phase: String = ""
var images: Array[String] = []
var checks: int = 0
const STRAW_DYES = preload("res://scripts/ui/equipment_dye.gd")

func natural_straw_colors() -> Dictionary:
	var result: Dictionary = {}
	for node: Node in editor.model_root.find_children("*Civilian_Straw_01_*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		for index: int in mesh_node.mesh.get_surface_count():
			var material := mesh_node.get_active_material(index) as BaseMaterial3D
			if material != null and material.resource_name.begins_with("CivilianStraw_") and material.resource_name != "CivilianStraw_Band":
				result[str(node.name) + ":" + str(index)] = material.albedo_color
	return result

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		push_error("CIV_STRAW_FAIL " + label)
		quit(1)
		assert(ok, label)

func camera_at(target: Vector3, size: float) -> void:
	editor.camera.size = size
	editor.camera.position = target + Vector3(0, 0, -5)
	editor.camera.look_at(target)

func snap(name: String, detail: String = "full") -> void:
	print("CIV_STRAW_PHASE capture ", name)
	if detail == "head": camera_at(Vector3(0, 1.71 if sex == "male" else 1.58, 0), 0.85)
	elif detail == "head_motion":
		var skeleton := editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
		var head: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("J_Bip_C_Head"))
		camera_at(head.origin + Vector3.UP * 0.15, 0.95)
	elif detail == "gait": camera_at(Vector3(0, 0.30, 0), 1.60)
	elif detail == "feet": camera_at(Vector3(0, 0.13, 0), 0.52)
	else: camera_at(Vector3(0, 0.98 if sex == "male" else 0.91, 0), 2.45 if sex == "male" else 2.30)
	await settle(3)
	await RenderingServer.frame_post_draw
	var path: String = destination + "/" + name + ".png"
	check(editor.preview_viewport.get_texture().get_image().save_png(path) == OK, "PNG " + name)
	images.append(path)

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	sex = args[0]
	phase = args[1]
	destination = args[2]
	check(destination.begins_with("res://output/") and not DirAccess.dir_exists_absolute(destination), "fresh isolated output")
	check(DirAccess.make_dir_recursive_absolute(destination) == OK, "create output")
	create_timer(180).timeout.connect(func() -> void: push_error("CIV_STRAW_FAIL deadline"); quit(1))
	DisplayServer.window_set_size(Vector2i(1280, 1000))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	print("CIV_STRAW_PHASE instantiate_editor")
	editor = load("res://scenes/ui/HumanCharacter3DEditor.tscn").instantiate() as HumanCharacter3DEditor
	print("CIV_STRAW_PHASE add_editor")
	editor.use_imported_model = false
	root.add_child(editor)
	print("CIV_STRAW_PHASE open_editor")
	editor.open()
	await settle(6)
	print("CIV_STRAW_PHASE load_body ", sex)
	editor._load_body_model(1 if sex == "female" else 0)
	print("CIV_STRAW_PHASE body_loaded")
	await settle(6)
	editor.preview_viewport.size = Vector2i(1024, 1280)
	editor.preview_viewport.msaa_3d = Viewport.MSAA_4X
	editor.preview_viewport.use_debanding = false
	for pair: Array in [[&"weapon", &"none"], [&"shield", &"none"], [&"cape", &"none"], [&"helmet", &"none"], [&"outfit", &"outfit_underlayer_01"], [&"armor", &"outfit_medieval_chinese_01"]]:
		check(editor.select_part_by_id(pair[0], pair[1]), "original clothes selection")
	for entry: Array in [[&"boots", &"boots_civilian_straw_01", &"boots_leather_01", "Boots_Civilian_Straw_01_"], [&"helmet", &"helmet_civilian_straw_01", &"helmet_leather_01", "Helmet_Civilian_Straw_01_"]]:
		for choice: StringName in [entry[1], &"none", entry[2], entry[1]]:
			check(editor.select_part_by_id(entry[0], choice), "new/none/old/new selection")
			var nodes: Array[Node] = editor.model_root.find_children(str(entry[3]) + "*", "MeshInstance3D", true, false)
			check(not nodes.is_empty(), "new component has actual meshes")
			for node: MeshInstance3D in nodes: check(node.visible == (choice == entry[1]), "selection visibility restored")
	for hatted: bool in ([true] if phase == "gray" else [false, true]):
		check(editor.select_part_by_id(&"helmet", &"helmet_civilian_straw_01" if hatted else &"none"), "look hat choice")
		check(editor.set_equipment_dyes({"armor": "825438ff" if hatted else "396fbbff", "outfit": "84966aff" if hatted else "d8dce3ff"}), "original civilian preset colors")
		neutral()
		for view: Array in [["front", 0.0], ["side", 90.0], ["back", 180.0], ["threequarter", 35.0]]:
			editor.set_preview_yaw_degrees(float(view[1]))
			await snap(("F" if sex == "female" else "M") + ("02_" if hatted else "01_") + str(view[0]))
	check(editor.select_part_by_id(&"helmet", &"helmet_civilian_straw_01"), "hat for details")
	neutral()
	for detail: String in ["head", "feet"]:
		var detail_views: Array = [["front", 0.0], ["side", 90.0], ["threequarter", 35.0]]
		if sex == "female" and detail == "head": detail_views.append_array([["left", -90.0], ["back", 180.0]])
		for view: Array in detail_views:
			editor.set_preview_yaw_degrees(float(view[1]))
			await snap(detail + "_" + str(view[0]), detail)
	if phase != "gray":
		var hair: Array = editor._active_hair_nodes(&"hair_male_01" if sex == "male" else &"hair_female_01")
		for node: MeshInstance3D in hair:
			check(node.visible, "open hat keeps forehead hair presenter")
			var material: ShaderMaterial = node.get_surface_override_material(0) as ShaderMaterial
			check(material != null and material.get_shader_parameter("cloth_hat_mask") == true, "open crown mask")
		check(editor.select_part_by_id(&"helmet", &"none"), "remove hat")
		for node: MeshInstance3D in hair:
			var material: ShaderMaterial = node.get_surface_override_material(0) as ShaderMaterial
			check(node.visible and material.get_shader_parameter("mask_enabled") == false, "removing hat restores full hair")
		editor.set_preview_yaw_degrees(35)
		await snap("hair_restored", "head")
		check(editor.select_part_by_id(&"helmet", &"helmet_civilian_straw_01"), "restore hat")
		if sex == "female":
			var natural_colors: Dictionary = natural_straw_colors()
			check(not natural_colors.is_empty(), "natural straw surfaces exist")
			var saved_dyes: Dictionary = editor.capture_appearance().get("equipment_dyes", {}).duplicate()
			for palette: String in ["ivory", "slate"]:
				var colors: Dictionary = {}
				for slot: String in ["helmet", "armor", "boots", "outfit"]: colors[slot] = STRAW_DYES.PRESETS[palette]["colors"][slot]
				check(editor.set_equipment_dyes(colors), "cross palette " + palette)
				check(natural_straw_colors() == natural_colors, "straw and soles retain natural color " + palette)
				for band: Array in [["helmet", "Helmet_Civilian_Straw_01_InnerBand"], ["boots", "Boots_Civilian_Straw_01_PlaitedStrap2_L"]]:
					var band_node := editor.model_root.find_child(band[1], true, false) as MeshInstance3D
					check(band_node != null, "actual dyeable straw band")
					var dye_material := band_node.get_active_material(0) as ShaderMaterial
					check(dye_material != null and dye_material.get_shader_parameter("equipment_dye_color") == Color.from_string(colors[band[0]], Color.WHITE), "only band follows requested palette")
				neutral()
				editor.set_preview_yaw_degrees(35)
				await snap("palette_" + palette)
			check(editor.set_equipment_dyes(saved_dyes), "restore brown dyes after cross palettes")
			check(natural_straw_colors() == natural_colors, "natural straw after dye restore")
		for clip: StringName in [&"walk", &"run"]:
			check(editor.select_animation_by_id(clip), "actual native animation")
			editor.set_playing(false)
			var animation: Animation = editor.animation_player.get_animation(clip)
			for fraction: float in [0.25, 0.75]:
				editor.animation_player.seek(animation.length * fraction, true)
				editor.animation_player.advance(0)
				editor._process(0)
				editor.set_preview_yaw_degrees(35)
				await snap(str(clip) + "_feet_" + str(int(fraction * 100)), "gait")
				if sex == "female": await snap(str(clip) + "_head_" + str(int(fraction * 100)), "head_motion")
		if sex == "female":
			check(editor.select_part_by_id(&"armor", &"none"), "remove original skirt to inspect occluded running foot")
			for fraction: float in [0.25, 0.75]:
				var run_animation: Animation = editor.animation_player.get_animation(&"run")
				editor.animation_player.seek(run_animation.length * fraction, true)
				editor.animation_player.advance(0)
				editor._process(0)
				editor.set_preview_yaw_degrees(35)
				await snap("run_feet_clear_" + str(int(fraction * 100)), "gait")
			check(editor.select_part_by_id(&"armor", &"outfit_medieval_chinese_01"), "restore original skirt")
	var file: FileAccess = FileAccess.open(destination + "/result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"status": "PASS", "sex": sex, "phase": phase, "checks": checks, "images": images,
		"scope": "actual original editor selection, raw formal-path GLB, four-view and deformation captures; manual review required separately"}, "\t"))
	file.close()
	print("CIV_STRAW_CAPTURE_PASS ", sex, " ", phase, " checks=", checks)
	editor.queue_free()
	await settle(3)
	quit(0)
