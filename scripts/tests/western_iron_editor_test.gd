extends "res://scripts/tests/weapon_axe_options_test.gd"

const IRON := {
	&"armor": [&"armor_western_iron_01", "Armor_Western_Iron_01_"],
	&"helmet": [&"helmet_western_iron_01", "Helmet_Western_Iron_01_"],
	&"boots": [&"boots_western_iron_01", "Boots_Western_Iron_01_"],
}
const Rules = preload("res://scripts/terrain_lab/site_combat_rules.gd")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var sex := args[0]
	var stage := args[1]
	output = "res://output/western_plate_20260913/" + stage + "/" + sex
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(2560, 1440)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 60
	create_timer(65.0).timeout.connect(func() -> void: quit(1))
	editor = load("res://scenes/ui/HumanCharacter3DEditor.tscn").instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	current_scene = editor
	await process_frame
	await process_frame
	var body := 1 if sex == "female" else 0
	editor.body_option.select(body)
	editor.body_option.item_selected.emit(body)
	if stage in ["candidate", "probe"]:
		editor._load_body_model(body, "res://.godot-temp/western_plate_20260913/candidate/%s.glb" % sex)
	skeleton = editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	assert(editor.is_open() and not editor.part_selection_request.is_valid())
	for slot: StringName in [&"cape", &"shield", &"weapon"]:
		_ui_select(editor.part_options[slot], &"none")
	for slot: StringName in IRON:
		_ui_select(editor.part_options[slot], IRON[slot][0])
		assert(Rules.armor_profile(IRON[slot][0]) == Rules.armor_profile("armor_iron_01"))
		assert(Rules.armor_profile(IRON[slot][0]) != Rules.armor_profile("helmet_steel_01"))
		assert(Orders.valid_definition(str(slot) + ":" + str(IRON[slot][0]), {"slot": str(slot), "asset": str(IRON[slot][0]), "tint": [1.0, 1.0, 1.0, 1.0]}))
	if stage == "probe":
		await _probe_shield()
		quit(0)
		return
	var saved: Dictionary = JSON.parse_string(JSON.stringify(editor.capture_appearance()))
	assert(HumanCharacter3DEditor.valid_appearance(saved))
	for slot: StringName in IRON:
		_ui_select(editor.part_options[slot], &"none")
		for node: Node3D in editor.model_root.find_children(IRON[slot][1] + "*", "MeshInstance3D", true, false):
			assert(not node.visible)
		_ui_select(editor.part_options[slot], IRON[slot][0])
		assert(editor.capture_appearance().parts[str(slot)] == str(IRON[slot][0]))
	assert(editor.restore_appearance(saved))
	_ui_select(editor.animation_option, &"idle")
	editor.set_playing(true)
	var before := editor.animation_player.current_animation_position
	await create_timer(.2).timeout
	assert(editor.animation_player.current_animation_position > before)
	editor.set_playing(false)
	editor.set_process(false)
	editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	assert(editor.select_animation_by_id(&"T-Pose"))
	editor.animation_player.seek(0, true)
	for view in [["front", 0], ["back", 180], ["side", 90], ["three_quarter", 35]]:
		await capture("neutral_" + view[0], view[1], 2.05)
	for outfit: StringName in [&"outfit_chinese_lining_01", &"none", &"outfit_underlayer_01"]:
		_ui_select(editor.part_options[&"outfit"], outfit)
		await capture("layer_" + str(outfit), 35, 2.05)
	for selected_slot: StringName in IRON:
		for slot: StringName in IRON:
			_ui_select(editor.part_options[slot], IRON[slot][0] if slot == selected_slot else &"none")
		assert(editor.select_animation_by_id(&"T-Pose"))
		editor.animation_player.seek(0,true)
		await capture("single_" + str(selected_slot), 35, 2.05)
	for slot: StringName in IRON:
		_ui_select(editor.part_options[slot], IRON[slot][0])
	_ui_select(editor.part_options[&"weapon"], &"longsword_01")
	_ui_select(editor.part_options[&"shield"], &"shield_heater_01")
	editor.combat_ready = true
	for clip: StringName in [&"idle", &"walk", &"run", &"guard", &"walk_slash", &"attack_spear", &"attack_axe", &"attack_jump_heavy", &"rescue", &"get_up"]:
		if clip == &"attack_spear":
			_ui_select(editor.part_options[&"weapon"], &"spear_01")
		elif clip == &"attack_axe":
			_ui_select(editor.part_options[&"weapon"], &"wood_axe_01")
		elif clip == &"attack_jump_heavy":
			_ui_select(editor.part_options[&"weapon"], &"longsword_01")
		assert(editor.select_animation_by_id(clip))
		var length := editor._animation_length()
		for tick in range(9):
			editor.animation_player.seek(minf(length * tick / 8.0, length - .001), true)
			skeleton.force_update_all_bone_transforms()
			for bone in skeleton.get_bone_count():
				assert(skeleton.get_bone_global_pose(bone).is_finite())
			await capture("%s_%02d" % [clip, tick], 35, 3.1 if clip == &"attack_jump_heavy" else (3.4 if clip == &"attack_spear" else 2.05))
		if clip in [&"walk", &"run"]:
			for tick in range(ceili(length * 12.0)):
				editor.animation_player.seek(tick / 12.0, true)
				await capture("%s_full_%03d" % [clip, tick], 35, 2.05)
	_ui_select(editor.part_options[&"weapon"], &"none")
	_ui_select(editor.part_options[&"shield"], &"none")
	assert(editor.select_animation_by_id(&"idle"))
	editor.animation_player.seek(.2,true)
	editor.set_preview_yaw_degrees(15)
	editor.set_preview_zoom(3.0)
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output + "/editor_ui.png") == OK)
	assert(editor.restore_appearance(saved))
	editor.close()
	editor.open()
	var reopened: Dictionary = JSON.parse_string(JSON.stringify(editor.capture_appearance()))
	if reopened != saved:
		push_error("Western iron appearance round trip changed: " + JSON.stringify({"saved": saved, "reopened": reopened}))
		quit(1)
		return
	print("WESTERN_IRON_EDITOR_PASS ", sex, " ", stage, "; three real options, none/restoration, UI signals/playback, appearance JSON; IRON profile distinct from STEEL; captures require visual review; no inventory grant")
	editor.queue_free()
	await process_frame
	await process_frame
	quit(0)

func _probe_shield() -> void:
	_ui_select(editor.part_options[&"weapon"], &"wood_axe_01")
	_ui_select(editor.part_options[&"shield"], &"shield_heater_01")
	editor.combat_ready = true
	editor.set_playing(false)
	editor.set_process(false)
	editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	assert(editor.select_animation_by_id(&"attack_axe"))
	editor.animation_player.seek(editor._animation_length() * .5, true)
	var colors := {"UnderShirt": Color.ORANGE, "Cuirass": Color.RED, "Rerebrace": Color.PURPLE, "Vambrace": Color.GREEN, "Pauldron": Color.YELLOW, "Couter": Color.CYAN}
	for node: MeshInstance3D in editor.model_root.find_children("Armor_Western_Iron_01_*", "MeshInstance3D", true, false):
		for token: String in colors:
			if str(node.name).contains(token):
				var diagnostic := StandardMaterial3D.new()
				diagnostic.albedo_color = colors[token]
				diagnostic.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				node.material_override = diagnostic
	await capture("shield_part_colors", 35, 2.05)
	_ui_select(editor.part_options[&"armor"], &"none")
	assert(editor.select_animation_by_id(&"attack_axe"))
	editor.animation_player.seek(editor._animation_length() * .5, true)
	await capture("baseline_body_shield", 35, 2.05)
