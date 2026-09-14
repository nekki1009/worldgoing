extends "res://scripts/tests/weapon_refresh_preview.gd"
## Original editor / raw GLB; pose snapshots are visual fixtures, not hits.
const LOWER := ["J_Bip_C_Hips", "J_Bip_L_UpperLeg", "J_Bip_L_LowerLeg", "J_Bip_L_Foot", "J_Bip_L_ToeBase", "J_Bip_R_UpperLeg", "J_Bip_R_LowerLeg", "J_Bip_R_Foot", "J_Bip_R_ToeBase"]
const UPPER := ["J_Bip_C_Chest", "J_Bip_C_Head", "J_Bip_L_Hand", "J_Bip_R_Hand"]

func run() -> void:
	create_timer(55.0).timeout.connect(func() -> void: quit(1))
	var args := OS.get_cmdline_user_args()
	var sex := args[0]
	var stage := args[1]
	output = "res://output/crossbow_stance_20260914/" + stage + "/" + sex
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	editor = HumanCharacter3DEditor.new()
	root.add_child(editor)
	editor.open()
	var original_upper := []
	if stage != "before":
		editor._load_body_model(1 if sex == "female" else 0, "res://.godot-temp/crossbow_stance_20260914/baseline/standard_anime_%s_character_pack.glb" % sex)
		skeleton = editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
		editor.combat_ready = true
		editor.set_process(false)
		assert(editor.select_part_by_id(&"weapon", &"crossbow_01"))
		_pose(&"attack_crossbow", 0.0)
		var old_duration := editor._animation_length()
		for sample in range(61):
			_pose(&"attack_crossbow", old_duration * sample / 60.0)
			original_upper.append(_upper_pose())
	editor._load_body_model(1 if sex == "female" else 0, args[2] if args.size() > 2 else "")
	editor.combat_ready = true
	editor.set_process(false)
	skeleton = editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	for pair in [[&"weapon", &"crossbow_01"], [&"armor", &"armor_light_leather_01"], [&"outfit", &"outfit_underlayer_01"], [&"helmet", &"none"], [&"cape", &"none"]]:
		assert(editor.select_part_by_id(pair[0], pair[1]))
	_pose(&"idle", 0.0)
	var reference := _lower_pose()
	var rows := [{"pose": "idle", "knees": _knees(), "lower": reference}]
	await capture("idle_reference", 90, 2.2)
	_pose(&"attack_crossbow", 0.0)
	var duration := editor._animation_length()
	var max_error := 0.0
	var upper_position_error := 0.0
	var upper_rotation_error := 0.0
	for sample in range(61):
		_pose(&"attack_crossbow", duration * sample / 60.0)
		var current := _lower_pose()
		for name: String in LOWER:
			for axis in range(3):
				max_error = maxf(max_error, absf(current[name][axis] - reference[name][axis]))
		if not original_upper.is_empty():
			var current_upper := _upper_pose()
			for name: String in UPPER:
				var old: Transform3D = original_upper[sample][name]
				var now: Transform3D = current_upper[name]
				upper_position_error = maxf(upper_position_error, old.origin.distance_to(now.origin))
				upper_rotation_error = maxf(upper_rotation_error, rad_to_deg(old.basis.get_rotation_quaternion().angle_to(now.basis.get_rotation_quaternion())))
				if sample in [0, 30, 60]:
					print("CROSSBOW_UPPER_SAMPLE ", sample, " ", name, " delta=", now.origin - old.origin)
		if sample in [0, 30, 60]:
			rows.append({"pose": "attack_crossbow", "sample": sample, "time": duration * sample / 60.0, "knees": _knees(), "lower": current})
			for view in [["front", 0], ["back", 180], ["side", 90], ["three_quarter", 35]]:
				await capture("crossbow_%02d_%s" % [sample, view[0]], view[1], 2.2)
		if stage != "before" and sample % 5 == 0:
			await capture("sequence_%02d" % sample, 35, 2.2)
	if stage != "before":
		print("CROSSBOW_UPPER_PRESERVATION position_m=", upper_position_error, " rotation_degrees=", upper_rotation_error)
		assert(max_error < 0.002, "Lower body must match the character's actual idle stance: " + str(max_error))
		if upper_position_error >= 0.002 or upper_rotation_error >= 0.25:
			push_error("Preserve upper-body aim/recoil relative to the pelvis")
			quit(1)
			return
		assert(editor.select_part_by_id(&"armor", &"armor_western_iron_01"))
		assert(editor.select_part_by_id(&"boots", &"boots_western_iron_01"))
		assert(editor.select_part_by_id(&"helmet", &"helmet_western_iron_01"))
		_pose(&"attack_crossbow", duration * 0.5)
		for view in [["front", 0], ["back", 180], ["side", 90], ["three_quarter", 35]]:
			await capture("iron_" + view[0], view[1], 2.2)
	var file := FileAccess.open(output + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"sex": sex, "stage": stage, "samples": 61, "duration": duration, "max_idle_lower_position_error_m": max_error, "max_upper_position_error_m": upper_position_error, "max_upper_rotation_error_degrees": upper_rotation_error, "poses": rows}, "\t"))
	file.close()
	print("CROSSBOW STANCE ", "BEFORE" if stage == "before" else "PASS", " ", sex, " lower_error_m=", max_error)
	editor.queue_free()
	await process_frame
	quit(0)

func _pose(clip: StringName, time: float) -> void:
	editor.set_preview_yaw_degrees(0.0)
	assert(editor.select_animation_by_id(clip))
	editor.set_playing(false)
	editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	editor.animation_player.seek(time, true)
	editor.animation_player.advance(0.0)
	editor._update_combat_props()
	editor._update_scabbard_pose()
	skeleton.force_update_all_bone_transforms()

func _lower_pose() -> Dictionary:
	var result := {}
	for name: String in LOWER:
		result[name] = vector(skeleton.get_bone_global_pose(skeleton.find_bone(name)).origin)
	return result

func _upper_pose() -> Dictionary:
	var result := {}
	var hips := skeleton.get_bone_global_pose(skeleton.find_bone("J_Bip_C_Hips")).origin
	for name: String in UPPER:
		var pose := skeleton.get_bone_global_pose(skeleton.find_bone(name))
		pose.origin -= hips
		result[name] = pose
	return result

func _knees() -> Array:
	var result := []
	for side: String in ["L", "R"]:
		var knee := _bone("J_Bip_" + side + "_LowerLeg")
		result.append(180.0 - rad_to_deg((_bone("J_Bip_" + side + "_UpperLeg") - knee).angle_to(_bone("J_Bip_" + side + "_Foot") - knee)))
	return result
