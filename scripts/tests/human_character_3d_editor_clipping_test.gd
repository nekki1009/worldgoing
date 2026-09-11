extends SceneTree

const EDITOR_SCENE: String = "res://scenes/ui/HumanCharacter3DEditor.tscn"
const CAPTURE_DIR: String = "res://.visual_captures/human_character_3d_editor/clipping"
const CLOTHING_PARTS: Array[StringName] = [&"outfit", &"armor", &"cape", &"weapon", &"shield", &"boots"]

var editor: HumanCharacter3DEditor

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	OS.low_processor_usage_mode = false
	Engine.max_fps = 0

	var scene := load(EDITOR_SCENE) as PackedScene
	assert(scene != null, "3D character editor scene did not load")
	editor = scene.instantiate() as HumanCharacter3DEditor
	assert(editor != null, "3D character editor has the wrong root type")	
	root.add_child(editor)
	editor.open()
	await _settle(10)
	assert(editor.is_open(), "3D character editor did not open")

	await _capture_configuration("full_tpose", [&"outfit", &"armor", &"cape", &"weapon", &"shield", &"boots"], &"T-Pose", 0.0)
	await _capture_configuration("full_idle", [&"outfit", &"armor", &"cape", &"weapon", &"shield", &"boots"], &"idle", 0.5)
	await _capture_configuration("full_walk", [&"outfit", &"armor", &"cape", &"weapon", &"shield", &"boots"], &"walk", 0.25)
	await _capture_configuration("full_run", [&"outfit", &"armor", &"cape", &"weapon", &"shield", &"boots"], &"run", 0.20)
	await _capture_configuration("full_attack", [&"outfit", &"armor", &"cape", &"weapon", &"shield", &"boots"], &"walk_slash", 0.58)
	await _capture_configuration("full_guard", [&"outfit", &"armor", &"cape", &"weapon", &"shield", &"boots"], &"guard", 0.50)
	await _capture_configuration("full_hit", [&"outfit", &"armor", &"cape", &"weapon", &"shield", &"boots"], &"hit", 0.21)
	await _capture_configuration("full_knockback", [&"outfit", &"armor", &"cape", &"weapon", &"shield", &"boots"], &"knockback", 0.42)
	await _capture_configuration("full_down", [&"outfit", &"armor", &"cape", &"weapon", &"shield", &"boots"], &"down", 1.00)
	await _capture_configuration("outfit", [&"outfit"], &"T-Pose", 0.0)
	await _capture_configuration("outfit_walk", [&"outfit"], &"walk", 0.25)
	await _capture_configuration("outfit_armor", [&"outfit", &"armor"], &"T-Pose", 0.0)
	await _capture_configuration("outfit_cape", [&"outfit", &"cape"], &"T-Pose", 0.0)
	await _capture_configuration("outfit_boots", [&"outfit", &"boots"], &"T-Pose", 0.0)

	# Multi-Weapon & Multi-Attack visual captures
	for weapon_info: Array in [
		[&"spear_01", &"attack_spear", "weapon_spear_attack", 0.45],
		[&"axe_01", &"attack_axe", "weapon_axe_attack", 0.52],
		[&"hammer_01", &"attack_hammer", "weapon_hammer_attack", 0.52],
		[&"dagger_01", &"attack_dagger", "weapon_dagger_attack", 0.25],
		[&"bow_01", &"attack_bow", "weapon_bow_attack", 0.50],
		[&"crossbow_01", &"attack_crossbow", "weapon_crossbow_attack", 0.46],
	]:
		var weapon_id: StringName = weapon_info[0]
		var anim_id: StringName = weapon_info[1]
		var cfg_name: String = str(weapon_info[2])
		var anim_time: float = float(weapon_info[3])
		assert(editor.select_part_by_id(&"weapon", weapon_id), "Failed to select weapon %s" % weapon_id)
		assert(editor.select_animation_by_id(anim_id), "Failed to select animation %s" % anim_id)
		editor.set_playing(false)
		editor.animation_player.seek(anim_time, true)
		editor.animation_player.advance(0.0)
		editor.set_preview_yaw_degrees(0.0)
		await _settle(3)
		await _capture(cfg_name + "_front.png")
		editor.set_preview_yaw_degrees(35.0)
		await _settle(3)
		await _capture(cfg_name + "_three_quarter.png")

	await _capture_universal_jump_heavy_set("male")

	# Spear with Shield attack captures
	assert(editor.select_part_by_id(&"weapon", &"spear_01"), "Failed to select spear")
	assert(editor.select_part_by_id(&"shield", &"shield_heater_01"), "Failed to select shield")
	assert(editor.select_part_by_id(&"armor", &"armor_light_leather_01"), "Failed to select armor")
	assert(editor.select_animation_by_id(&"attack_spear"), "Failed to select attack_spear")
	for t_sample: float in [0.0, 0.3, 0.6, 0.9, 1.2, 1.5, 2.0]:
		editor.set_playing(false)
		editor.animation_player.seek(t_sample, true)
		editor.animation_player.advance(0.0)
		editor.set_preview_yaw_degrees(35.0)
		await _settle(3)
		await _capture("spear_shield_anim_t%.1f_34.png" % t_sample)
		editor.set_preview_yaw_degrees(-35.0)
		await _settle(3)
		await _capture("spear_shield_anim_t%.1f_fl.png" % t_sample)

	# Bow shooting captures (draw to cheek & arrow release)
	assert(editor.select_part_by_id(&"weapon", &"bow_01"), "Failed to select bow")
	assert(editor.select_part_by_id(&"shield", &"none"), "Failed to unselect shield")
	assert(editor.select_animation_by_id(&"attack_bow"), "Failed to select attack_bow")
	for bow_t: float in [1.5, 2.5, 3.8, 4.8]:
		editor.set_playing(false)
		editor.animation_player.seek(bow_t, true)
		editor.animation_player.advance(0.0)
		editor.set_preview_yaw_degrees(0.0)
		await _settle(3)
		await _capture("bow_shot_anim_t%.1f_front.png" % bow_t)
		editor.set_preview_yaw_degrees(35.0)
		await _settle(3)
		await _capture("bow_shot_anim_t%.1f_34.png" % bow_t)

	# Repeat the universal action on the female body pack.
	editor._load_body_model(1)
	await _settle(12)
	await _capture_universal_jump_heavy_set("female")

	print("HUMAN_CHARACTER_3D_EDITOR_CLIPPING_CAPTURE_PASS: basic_and_universal_attack_captures=true")
	editor.queue_free()
	await _settle(6)
	quit(0)

func _capture_universal_jump_heavy_set(body_prefix: String) -> void:
	for weapon_info: Array in [
		[&"longsword_01", "jump_heavy_longsword"],
		[&"spear_01", "jump_heavy_spear"],
		[&"axe_01", "jump_heavy_axe"],
		[&"hammer_01", "jump_heavy_hammer"],
		[&"dagger_01", "jump_heavy_dagger"],
		[&"bow_01", "jump_heavy_bow"],
		[&"crossbow_01", "jump_heavy_crossbow"],
		[&"none", "jump_heavy_unarmed"],
	]:
		var weapon_id: StringName = weapon_info[0]
		var cfg_name: String = "%s_%s" % [body_prefix, weapon_info[1]]
		assert(editor.select_part_by_id(&"weapon", weapon_id), "Failed to select weapon %s for universal jump heavy" % weapon_id)
		assert(editor.select_animation_by_id(&"attack_jump_heavy"), "Failed to select universal jump heavy attack for %s" % weapon_id)
		assert(editor.selected_animation == &"attack_jump_heavy", "Weapon %s changed universal jump heavy selection" % weapon_id)
		editor.set_playing(false)
		editor.animation_player.seek(0.45, true)
		editor.animation_player.advance(0.0)
		editor.set_preview_yaw_degrees(0.0)
		await _settle(3)
		await _capture(cfg_name + "_front.png")
		editor.set_preview_yaw_degrees(35.0)
		await _settle(3)
		await _capture(cfg_name + "_three_quarter.png")

func _capture_configuration(
	configuration_name: String,
	enabled_parts: Array[StringName],
	animation_id: StringName,
	animation_time: float,
) -> void:
	for part_id in CLOTHING_PARTS:
		assert(editor.select_part_by_id(part_id, &"none"), "%s None selection failed" % part_id)
	for part_id in enabled_parts:
		var option := editor.part_options[part_id] as OptionButton
		assert(option != null and option.item_count >= 2, "%s has no real option" % part_id)
		var selected_id := StringName(str(option.get_item_metadata(0)))
		assert(selected_id != &"none", "%s first option is unexpectedly None" % part_id)
		assert(editor.select_part_by_id(part_id, selected_id), "%s selection failed" % part_id)
	assert(editor.select_animation_by_id(animation_id), "%s animation selection failed" % animation_id)
	editor.set_playing(false)
	editor.animation_player.seek(animation_time, true)
	editor.animation_player.advance(0.0)
	editor.set_preview_yaw_degrees(0.0)
	await _settle(3)
	await _capture(configuration_name + "_front.png")
	editor.set_preview_yaw_degrees(35.0)
	await _settle(3)
	await _capture(configuration_name + "_three_quarter.png")

func _capture(file_name: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(CAPTURE_DIR + "/" + file_name)
	var dir_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	assert(dir_error == OK or dir_error == ERR_ALREADY_EXISTS, "Capture directory failed")
	var image := root.get_texture().get_image()
	assert(image != null and not image.is_empty(), "Editor viewport capture is empty")
	assert(image.save_png(absolute_path) == OK, "Capture could not be saved: %s" % file_name)

func _settle(frame_count: int) -> void:
	for _index: int in range(frame_count):
		await process_frame
