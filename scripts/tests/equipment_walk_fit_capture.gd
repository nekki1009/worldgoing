extends "res://scripts/tests/equipment_matrix_visual.gd"
## Focused native before/after sequences, not a claim of geometric clearance.
const TARGET := "res://output/equipment_walk_fix_20260919"
var folder := ""
var images: Array[String] = []

class CandidateEditor extends HumanCharacter3DEditor:
	var candidate_path := ""
	func _load_body_model(index: int, preview_model_path: String = "") -> void:
		super._load_body_model(index, candidate_path if not candidate_path.is_empty() else preview_model_path)

func shot(label: String, angle: float = 0.0, head: bool = false) -> Image:
	editor.set_preview_yaw_degrees(angle)
	var center := Vector3(0, 1.49 if head else .86, 0)
	editor.camera.size = .60 if head else 2.05
	editor.camera.position = center + Vector3(0, 0, -5)
	editor.camera.look_at(center)
	for step in 2: await process_frame
	await RenderingServer.frame_post_draw
	var picture := editor.preview_viewport.get_texture().get_image()
	var path := folder + "/" + label + ".png"
	assert(picture.save_png(path) == OK)
	images.append(path)
	return picture

func run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() >= 2 and args[0].is_valid_filename())
	var steel_batch := "--steel-mingguang" in args
	var capture_root := "res://output/steel_mingguang_walk_20260919" if steel_batch else TARGET
	sex = args[1]
	assert(sex in ["male", "female"] and DisplayServer.get_name() != "headless")
	folder = capture_root + "/" + args[0] + "/" + sex
	assert(not DirAccess.dir_exists_absolute(folder), "Never overwrite evidence")
	DirAccess.make_dir_recursive_absolute(folder)
	var body := int(sex == "female")
	editor = CandidateEditor.new()
	for argument in args:
		if argument.begins_with("--candidate="):
			var candidate := argument.trim_prefix("--candidate=")
			assert(candidate.begins_with(capture_root+"/") and FileAccess.file_exists(candidate))
			(editor as CandidateEditor).candidate_path = candidate
	editor.visual_state.body_index = body
	root.add_child(editor)
	editor.open()
	editor.preview_viewport.size = Vector2i(900, 1100)
	editor.preview_viewport.use_debanding = false
	assert(editor.restore_appearance(Editor.default_appearance(body)))
	for slot: StringName in [&"cape", &"shield", &"weapon", &"helmet"]: choose(slot, &"none")
	choose(&"outfit", &"outfit_underlayer_01")
	var cases: Array = [
			["western_armor", &"armor_western_iron_01", &"boots_leather_01"],
			["chinese_armor", &"armor_iron_01", &"boots_leather_01"],
			["japanese_iron_boot", &"armor_light_leather_01", &"boots_japanese_iron_01"],
			["western_iron_boot", &"armor_light_leather_01", &"boots_western_iron_01"],
			["japanese_steel_boot", &"armor_light_leather_01", &"boots_japanese_steel_01"],
			["western_steel_boot", &"armor_light_leather_01", &"boots_western_steel_01"],
		]
	if steel_batch:
		cases = [["chinese_steel", &"armor_chinese_steel_01", &"boots_leather_01"],
			["western_steel", &"armor_western_steel_01", &"boots_leather_01"],
			["mingguang", &"armor_mingguang_01", &"boots_leather_01"]]
	if not "--hair-only" in args and not "--low-pose-only" in args:
		for item in cases:
			if "--armor-only" in args and item[0] not in ["western_armor","chinese_armor"]: continue
			choose(&"armor", item[1]); choose(&"boots", item[2])
			var sheet := Image.create(1800, 1100, false, Image.FORMAT_RGBA8)
			for step in 24:
				pose(&"walk", float(step) / 24.0)
				var frame := await shot("%s_walk_%02d" % [item[0], step])
				if step % 3 == 0:
					frame.resize(450,550,Image.INTERPOLATE_LANCZOS)
					sheet.blit_rect(frame, Rect2i(0,0,450,550), Vector2i((step/3)%4, (step/3)/4)*Vector2i(450,550))
			assert(sheet.save_png(folder+"/"+item[0]+"_walk_sheet.png") == OK)
			for clip: StringName in [&"idle", &"run"]:
				for progress in [.25,.75]:
					pose(clip,progress)
					await shot("%s_%s_%d" % [item[0],clip,int(progress*100)])
			for clip: StringName in [&"attack_jump_heavy", &"attack_spear", &"knockback"]:
				for progress in [.25,.5,.75]:
					pose(clip,progress)
					await shot("%s_%s_%d" % [item[0],clip,int(progress*100)])
			for angle in [90.0,270.0]:
				for progress in [.25,.75]:
					pose(&"walk",progress)
					await shot("%s_walk_%d_side%d" % [item[0],int(progress*100),int(angle)],angle)
			choose(&"outfit", &"outfit_chinese_lining_01")
			for progress in [.25,.75]:
				pose(&"walk",progress)
				await shot("%s_lining_walk_%d" % [item[0],int(progress*100)])
			choose(&"outfit", &"outfit_underlayer_01")
			print("WALK_FIT_CAPTURE ", sex, " ", item[0])
	if "--low-pose-only" in args:
		choose(&"armor", &"armor_mingguang_01")
		choose(&"boots", &"boots_leather_01")
		for clip: StringName in [&"idle", &"down", &"unconscious", &"get_up", &"rescue"]:
			for progress in [.0, .25, .5, .75, .99]:
				# Exercise the real owner's walk-to-other-clip morph reset.
				pose(&"walk", .25)
				pose(clip, progress)
				for node in editor.model_root.find_children("Armor_Mingguang_01_*", "MeshInstance3D", true, false):
					var mesh := node as MeshInstance3D
					for index in mesh.get_blend_shape_count():
						if str(mesh.mesh.get_blend_shape_name(index)).begins_with("WalkClearance_"):
							assert(absf(mesh.get_blend_shape_value(index)) < .00001, "Walk morph leaked into " + clip)
				for angle in [0.0,90.0,180.0]:
					await shot("mingguang_%s_%d_side%d" % [clip,int(progress*100),int(angle)],angle)
	choose(&"armor", &"armor_light_leather_01")
	choose(&"boots", &"boots_leather_01")
	for hair in [1, 2, 6]:
		if "--no-hair" in args: break
		choose(&"hair", StringName("hair_%s_%02d" % [sex,hair]))
		for helmet: StringName in [&"helmet_leather_01", &"helmet_western_iron_01", &"helmet_western_steel_01", &"helmet_cloth_western_01", &"none"]:
			choose(&"helmet", helmet)
			pose(&"T-Pose", 0.0)
			for mode: StringName in [&"auto", &"off"]:
				editor.set_hair_mask_mode(mode)
				for angle in [0.0,90.0,180.0]: await shot("hair_%02d_%s_%s_%d" % [hair,helmet,mode,int(angle)],angle,true)
			editor.set_hair_mask_mode(&"auto")
	var result := {"status":"CAPTURE_COMPLETE", "sex":sex, "checks":checks, "images":images,
		"editor_md5": FileAccess.get_md5("res://scripts/ui/human_character_3d_editor.gd"),
		"candidate_path": (editor as CandidateEditor).candidate_path}
	if not (editor as CandidateEditor).candidate_path.is_empty():
		result.candidate_sha256 = FileAccess.get_sha256((editor as CandidateEditor).candidate_path)
	FileAccess.open(folder+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	editor.queue_free()
	await process_frame
	print("WALK_FIT_CAPTURE_COMPLETE ", images.size())
	quit(0)
