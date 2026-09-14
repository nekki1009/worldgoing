extends "res://scripts/tests/weapon_refresh_preview.gd"

const Orders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
const AXES := {&"axe_01": "Weapon_Axe_01_", &"wood_axe_01": "Weapon_WoodAxe_01_"}
const AXE_PARTS := ["Blade", "Grip", "Grip_Wrap", "Haft", "Holstered_Blade", "Holstered_Haft"]

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var sex := args[0]
	if "--editor-ui" in args:
		await _run_editor_ui(sex)
		return
	var formal := "--formal" in args
	output = "res://output/weapon_refresh_20260913/" + ("formal_options" if formal else "candidate_options")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 60
	create_timer(45.0).timeout.connect(func() -> void: quit(1))
	editor = HumanCharacter3DEditor.new()
	root.add_child(editor)
	editor.open()
	editor._load_body_model(1 if sex == "female" else 0,
		"" if formal else "res://.godot-temp/weapon_refresh_20260913/candidate/%s.glb" % sex)
	editor.set_process(false)
	skeleton = editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	for pair in [[&"armor", &"armor_light_leather_01"], [&"outfit", &"outfit_underlayer_01"], [&"cape", &"none"], [&"helmet", &"none"]]:
		assert(editor.select_part_by_id(pair[0], pair[1]))
	for axe: StringName in AXES:
		assert(editor.select_part_by_id(&"weapon", axe))
		var saved: Dictionary = JSON.parse_string(JSON.stringify(editor.capture_appearance()))
		assert(HumanCharacter3DEditor.valid_appearance(saved))
		assert(Orders.valid_definition("weapon:" + str(axe), {"slot": "weapon", "asset": str(axe), "tint": [1.0, 1.0, 1.0, 1.0]}))
		assert(editor.select_part_by_id(&"weapon", &"none"))
		_check_visibility(&"none", false)
		assert(editor.restore_appearance(saved))
		assert(editor.capture_appearance().parts.weapon == str(axe))
		assert(editor.select_part_by_id(&"shield", &"none"))
		editor.combat_ready = true
		assert(editor.select_animation_by_id(&"attack"))
		assert(editor.selected_animation == &"attack_axe")
		editor.set_playing(false)
		editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for sample in range(13):
			editor.animation_player.seek(minf(editor._animation_length() * sample / 12.0, editor._animation_length() - .001), true)
			_check_visibility(axe, false)
			await capture("%s_%s_attack_%02d" % [sex, axe, sample], 35, 2.7)
		for pose: StringName in [&"idle", &"walk", &"run"]:
			for held: bool in [false, true]:
				editor.combat_ready = held
				assert(editor.select_animation_by_id(pose))
				editor._update_weapon_sheath_state()
				editor.animation_player.seek(.2, true)
				_check_visibility(axe, not held)
				await capture("%s_%s_%s_%s" % [sex, axe, pose, "held" if held else "holstered"], 35 if held else 150, 2.7)
		assert(editor.select_animation_by_id(&"guard"))
		assert(editor.selected_animation == &"guard_weapon", "Both axes must share the existing no-shield guard")
		assert(editor.select_part_by_id(&"shield", &"shield_heater_01"))
		assert(editor.select_animation_by_id(&"guard"))
		assert(editor.selected_animation == &"guard")
		editor.animation_player.seek(.2, true)
		await capture("%s_%s_guard" % [sex, axe], 35, 2.7)
		assert(editor.select_part_by_id(&"shield", &"none"))
		assert(editor.select_animation_by_id(&"T-Pose"))
		editor.animation_player.seek(0, true)
		for view in [["front", 0], ["back", 180], ["side", 90], ["three_quarter", 35]]:
			await capture("%s_%s_%s" % [sex, axe, view[0]], view[1], 2.7)
		editor.set_preview_yaw_degrees(110)
		var visibility := {}
		for node: Node3D in editor.model_root.find_children("*", "MeshInstance3D", true, false):
			visibility[node] = node.visible
			if not str(node.name).begins_with(AXES[axe]):
				node.hide()
		var center := (_center(AXES[axe] + "Haft") + _center(AXES[axe] + "Blade")) * .5
		editor.camera.size = 1.0
		editor.camera.position = center + Vector3(0, .04, -5)
		editor.camera.look_at(center)
		await process_frame
		await RenderingServer.frame_post_draw
		assert(editor.preview_viewport.get_texture().get_image().save_png(output + "/%s_%s_detail.png" % [sex, axe]) == OK)
		for node: Node3D in visibility:
			node.visible = visibility[node]
		assert(editor.restore_appearance(saved))
	_check_mesh_distinction()
	print("AXE_OPTIONS_PASS ", sex, " formal=", formal, "; distinct meshes; none/new/old switching; appearance JSON roundtrip; equipment definition; held/holstered idle/walk/run; shared attack and shield/no-shield guard")
	editor.queue_free()
	await process_frame
	await process_frame
	quit(0)

func _check_visibility(axe: StringName, sheathed: bool) -> void:
	for key: StringName in AXES:
		for part: String in AXE_PARTS:
			var mesh := editor.model_root.find_child(AXES[key] + part, true, false) as MeshInstance3D
			assert(mesh != null, AXES[key] + part)
			assert(mesh.visible == (key == axe and part.begins_with("Holstered_") == sheathed), str(mesh.name))

func _check_mesh_distinction() -> void:
	var battle := editor.model_root.find_child("Weapon_Axe_01_Blade", true, false) as MeshInstance3D
	var logging := editor.model_root.find_child("Weapon_WoodAxe_01_Blade", true, false) as MeshInstance3D
	assert(battle.mesh.get_rid() != logging.mesh.get_rid())
	assert(battle.mesh.surface_get_array_len(0) != logging.mesh.surface_get_array_len(0))

func _run_editor_ui(sex: String) -> void:
	# Exercise the actual standalone scene and UI signals, not a candidate path
	# or programmatic selection that bypasses the gameplay ownership callback.
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(2560, 1440)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 60
	create_timer(35.0).timeout.connect(func() -> void: quit(1))
	output = "res://output/weapon_refresh_20260913/editor_ui"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	editor = load("res://scenes/ui/HumanCharacter3DEditor.tscn").instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	current_scene = editor
	await process_frame
	await process_frame
	assert(editor.is_open(), "Standalone scene must open through its normal entry")
	assert(not editor.part_selection_request.is_valid(), "Standalone editing must not grant or require inventory")
	var body := 1 if sex == "female" else 0
	editor.body_option.select(body)
	editor.body_option.item_selected.emit(body)
	assert(editor._body_index == body)
	for slot: StringName in [&"helmet", &"cape", &"shield"]:
		_ui_select(editor.part_options[slot], &"none")
	for axe: StringName in AXES:
		_ui_select(editor.part_options[&"weapon"], axe)
		assert(editor.capture_appearance().parts.weapon == str(axe))
		_ui_select(editor.animation_option, &"attack")
		assert(editor.selected_animation == &"attack_axe")
		editor.set_playing(true)
		var before := editor.animation_player.current_animation_position
		await create_timer(.18).timeout
		assert(editor.animation_player.current_animation_position > before)
		editor.set_playing(false)
		_check_visibility(axe, false)
		editor.set_preview_yaw_degrees(65)
		editor.set_preview_zoom(3.0)
		await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(output + "/%s_%s_selected.png" % [sex, axe]) == OK)
		_ui_select(editor.part_options[&"weapon"], &"none")
		_check_visibility(&"none", false)
	_ui_select(editor.part_options[&"weapon"], &"wood_axe_01")
	editor.close()
	editor.open()
	assert(editor.capture_appearance().parts.weapon == "wood_axe_01")
	print("AXE_EDITOR_UI_PASS ", sex, "; actual scene, enabled menu, UI signals, real playback, axe/none switching, reopen preserves selection; no inventory mutation")
	editor.queue_free()
	await process_frame
	await process_frame
	quit(0)

func _ui_select(option: OptionButton, id: StringName) -> void:
	for index in range(option.item_count):
		if StringName(str(option.get_item_metadata(index))) == id:
			assert(not option.disabled and not option.is_item_disabled(index), str(id))
			option.select(index)
			option.item_selected.emit(index)
			return
	assert(false, "Missing UI item: " + str(id))
