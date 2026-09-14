extends SceneTree

var editor: HumanCharacter3DEditor
var output := "res://.visual_captures/site_combat_assets/baseline"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var sex := args[0] if not args.is_empty() else "male"
	var stage := args[1] if args.size() > 1 else "baseline"
	output = "res://.visual_captures/site_combat_assets/" + stage
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	DisplayServer.window_set_size(Vector2i(1200, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 60
	editor = HumanCharacter3DEditor.new()
	root.add_child(editor)
	editor.open()
	editor._load_body_model(1 if sex == "female" else 0,
		"res://.godot-temp/site_combat_assets/candidate/%s.glb" % sex if stage in ["candidate", "matrix"] else "")
	if stage in ["candidate", "matrix"]:
		editor._load_combat_props("res://.godot-temp/site_combat_assets/candidate/combat_props.glb")
	await process_frame
	editor.preview_viewport.size = Vector2i(1024, 1280)
	editor.preview_viewport.msaa_3d = Viewport.MSAA_4X
	for pair in [[&"armor", &"armor_light_leather_01"], [&"outfit", &"outfit_underlayer_01"],
		[&"helmet", &"none"], [&"cape", &"none"], [&"weapon", &"longsword_01"], [&"shield", &"shield_heater_01"]]:
		assert(editor.select_part_by_id(pair[0], pair[1]))
	if stage == "matrix":
		for armor: StringName in [&"armor_light_leather_01", &"armor_iron_01", &"armor_mingguang_01", &"armor_chinese_leather_01"]:
			assert(editor.select_part_by_id(&"armor", armor))
			for clip: StringName in [&"guard_break", &"get_up", &"rescue"]:
				assert(editor.select_animation_by_id(clip))
				editor.set_playing(false)
				editor.animation_player.seek(editor._animation_length() * .6, true)
				editor.set_preview_yaw_degrees(40)
				_camera(clip)
				await _capture("%s_%s_%s" % [sex, armor, clip])
		for cape: StringName in [&"cape_travel_01", &"cape_chinese_01"]:
			assert(editor.select_part_by_id(&"cape", cape))
			for clip: StringName in [&"unconscious", &"get_up", &"rescue"]:
				assert(editor.select_animation_by_id(clip))
				editor.set_playing(false)
				editor.animation_player.seek(editor._animation_length() * .6, true)
				editor.set_preview_yaw_degrees(140)
				_camera(clip)
				await _capture("%s_%s_%s" % [sex, cape, clip])
		print("SITE_COMBAT_MATRIX_CAPTURE_PASS ", sex)
		editor.queue_free()
		await process_frame
		quit(0)
		return
	var clips: Array[StringName] = [&"idle", &"guard", &"down", &"hit_back", &"attack_bow", &"attack_crossbow"]
	if stage != "baseline":
		clips = [&"guard_raise", &"guard_lower", &"guard_break", &"unconscious", &"get_up", &"rescue", &"reload_bow", &"reload_crossbow"]
		for prefix in ["guard_weapon", "guard_polearm"]:
			for suffix in ["", "_raise", "_lower", "_break"]:
				clips.append(StringName(prefix + suffix))
	if stage == "timing":
		clips = [&"attack_sword", &"attack_spear", &"attack_axe", &"attack_hammer", &"attack_dagger", &"attack_unarmed", &"attack_bow", &"attack_crossbow", &"walk_slash", &"attack_jump_heavy", &"ride_slash", &"ride_thrust"]
	if args.size() > 2:
		assert(StringName(args[2]) in clips)
		clips = [StringName(args[2])]
	for clip in clips:
		var weapon: StringName = &"bow_01" if "bow" in str(clip) and not "crossbow" in str(clip) else &"crossbow_01" if "crossbow" in str(clip) else &"longsword_01"
		if str(clip).begins_with("guard_polearm"):
			weapon = &"spear_01"
		assert(editor.select_part_by_id(&"shield", &"none" if str(clip).begins_with("guard_weapon") or str(clip).begins_with("guard_polearm") else &"shield_heater_01"))
		for pair in [[&"attack_spear", &"spear_01"], [&"ride_thrust", &"spear_01"], [&"attack_axe", &"axe_01"], [&"attack_hammer", &"hammer_01"], [&"attack_dagger", &"dagger_01"], [&"attack_unarmed", &"none"]]:
			if clip == pair[0]:
				weapon = pair[1]
		assert(editor.select_part_by_id(&"weapon", weapon))
		editor.set_mount_enabled(str(clip).begins_with("ride_"))
		assert(editor.select_animation_by_id(clip), "Missing clip: " + str(clip))
		editor.set_playing(false)
		editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var animation := editor.animation_player.get_animation(editor.selected_animation)
		print("COMBAT_ASSET_CLIP ", sex, " ", clip, " length=", animation.length)
		if stage == "timing":
			var strip := Image.create(256 * 13, 320, false, Image.FORMAT_RGB8)
			for index in range(13):
				editor.animation_player.seek(animation.length * index / 12.0, true)
				editor.set_preview_yaw_degrees(75)
				_camera(clip)
				await process_frame
				await RenderingServer.frame_post_draw
				var frame := editor.preview_viewport.get_texture().get_image()
				frame.resize(256, 320)
				frame.convert(Image.FORMAT_RGB8)
				strip.blit_rect(frame, Rect2i(0, 0, 256, 320), Vector2i(index * 256, 0))
			assert(strip.save_png(output + "/" + sex + "_" + str(clip) + "_strip.png") == OK)
			continue
		if stage == "motion":
			for sample in range(ceili(animation.length * 12.0) + 1):
				editor.animation_player.seek(minf(float(sample) / 12.0, animation.length - .001), true)
				editor.set_preview_yaw_degrees(35)
				_camera(clip)
				await _capture("%s_%s_%03d" % [sex, clip, sample])
			continue
		for sample in range(5):
			var time := animation.length * float(sample) / 4.0
			editor.animation_player.seek(minf(time, animation.length - 0.001), true)
			editor.animation_player.advance(0.0)
			editor.set_preview_yaw_degrees(35)
			_camera(clip)
			await _capture("%s_%s_%02d" % [sex, clip, sample])
			if sample == 2 and stage != "baseline":
				for view in [["front", 0.0], ["back", 180.0], ["side", 90.0]]:
					editor.set_preview_yaw_degrees(view[1])
					_camera(clip)
					await _capture("%s_%s_%s" % [sex, clip, view[0]])
	print("SITE_COMBAT_ASSET_CAPTURE_PASS ", sex, " ", stage)
	editor.queue_free()
	await process_frame
	await process_frame
	quit(0)

func _camera(clip: StringName) -> void:
	editor.preview_viewport.size = Vector2i(1536, 1280) if "polearm" in str(clip) or clip == &"attack_spear" else Vector2i(1024, 1280)
	var center := Vector3(0, 0.8, 0)
	editor.camera.size = 2.8
	if clip == &"guard_polearm_break":
		editor.camera.size = 3.8
	if clip in [&"down", &"unconscious", &"get_up", &"rescue"]:
		center = Vector3(0, 0.65, 0)
		editor.camera.size = 3.2
	editor.camera.position = center + Vector3(0, 0.15, -6)
	editor.camera.look_at(center)

func _capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	assert(editor.preview_viewport.get_texture().get_image().save_png(output + "/" + label + ".png") == OK)
