extends SceneTree

const Collision = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")
var editor: HumanCharacter3DEditor
var skeleton: Skeleton3D
var geometry := Collision.new()
var output: String

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var sex := args[0]
	var stage := args[1]
	output = "res://output/weapon_refresh_20260913/" + stage
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 60
	editor = HumanCharacter3DEditor.new()
	root.add_child(editor)
	editor.open()
	editor._load_body_model(1 if sex == "female" else 0,
		args[2] if args.size() > 2 else ("res://.godot-temp/weapon_refresh_20260913/candidate/%s.glb" % sex if stage.begins_with("candidate") else ""))
	editor.combat_ready = true
	editor.set_process(false)
	skeleton = editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	for pair in [[&"armor", &"armor_light_leather_01"], [&"outfit", &"outfit_underlayer_01"], [&"cape", &"none"], [&"helmet", &"none"]]:
		assert(editor.select_part_by_id(pair[0], pair[1]))
	var rows := []
	var checks := []
	for entry in [[&"axe_01", &"T-Pose"], [&"axe_01", &"attack_axe"],
		[&"spear_01", &"attack_spear"], [&"longsword_01", &"guard"],
		[&"longsword_01", &"idle"], [&"longsword_01", &"walk"]]:
		assert(editor.select_part_by_id(&"weapon", entry[0]))
		assert(editor.select_part_by_id(&"shield", &"shield_heater_01"))
		assert(editor.select_animation_by_id(entry[1]))
		editor.set_playing(false)
		editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var length := editor._animation_length()
		if stage.ends_with("final") and entry[1] in [&"attack_spear", &"attack_axe"]:
			editor.set_preview_yaw_degrees(0)
			var initial_axis := Vector3.ZERO
			var initial_shield := Vector3.ZERO
			var max_axis := 0.0
			var max_shield := 0.0
			var shield_piercings := 0
			for tick in range(ceili(length * 120.0) + 1):
				editor.animation_player.seek(minf(tick / 120.0, length - .001), true)
				skeleton.force_update_all_bone_transforms()
				var front := (_center("Shield_Heater_01_Boss") - _center("Shield_Heater_01_Field")).normalized()
				if tick == 0:
					initial_shield = front
				max_shield = maxf(max_shield, rad_to_deg(initial_shield.angle_to(front)))
				if entry[0] == &"spear_01":
					var ends := _ends("Weapon_Spear_01_Shaft")
					var axis := (ends[1] - ends[0]).normalized()
					if tick == 0:
						initial_axis = axis
					max_axis = maxf(max_axis, rad_to_deg(initial_axis.angle_to(axis)))
					if tick % 4 == 0 and (_pierces_shield(ends[0], _center("Weapon_Spear_01_Head")) or _pierces_shield(_bone("J_Bip_R_LowerArm"), _bone("J_Bip_R_Hand"))):
						shield_piercings += 1
						if shield_piercings == 1:
							await capture(sex + "_failed_shield_clearance", 0, 2.7)
							editor.set_preview_yaw_degrees(0)
			checks.append({"clip": str(entry[1]), "samples": ceili(length * 120.0) + 1, "max_axis_degrees": max_axis, "max_shield_degrees": max_shield, "shield_centerline_piercings_30hz": shield_piercings})
			print("WEAPON_REFRESH_DENSE_MEASUREMENT ", checks.back())
			# Untouched source torso/clavicle tracks retain their original GLB
			# interpolation. Allow <2 degrees of accumulated shaft-axis variation
			# (under 7 cm at a 2 m tip), but no shield turn beyond one degree.
			if max_axis >= 2.0 or max_shield >= 1.0 or shield_piercings > 0:
				var diagnostic := FileAccess.open(output + "/" + sex + "_failed_motion.json", FileAccess.WRITE)
				diagnostic.store_string(JSON.stringify(checks,"\t"))
				diagnostic.close()
				push_error("Raw spear axis or shield front still spins: " + str(checks.back()))
				quit(1)
				return
			for tick in range(ceili(length * 12.0) + 1):
				editor.animation_player.seek(minf(tick / 12.0, length - .001), true)
				await capture("%s_%s_full_%03d" % [sex, entry[1], tick], 35, 3.4 if entry[0] == &"spear_01" else 2.7)
		for sample in range(13):
			editor.set_preview_yaw_degrees(0)
			editor.animation_player.seek(minf(length * sample / 12.0, length - .001), true)
			skeleton.force_update_all_bone_transforms()
			var row := {"clip": str(entry[1]), "frame": sample, "time": length * sample / 12.0,
				"right_wrist": vector(_bone("J_Bip_R_Hand")), "left_wrist": vector(_bone("J_Bip_L_Hand")),
				"shield_front": vector(_center("Shield_Heater_01_Boss") - _center("Shield_Heater_01_Field"))}
			if entry[0] == &"spear_01":
				var shaft := _ends("Weapon_Spear_01_Shaft")
				row["shaft_a"] = vector(shaft[0])
				row["shaft_b"] = vector(shaft[1])
				row["tip"] = vector(_center("Weapon_Spear_01_Head"))
			rows.append(row)
			await capture("%s_%s_%02d" % [sex, entry[1], sample], 35, 3.4 if entry[0] == &"spear_01" else 2.7)
			if sample == 6:
				for view in [["front", 0], ["back", 180], ["side", 90]]:
					await capture("%s_%s_%s" % [sex, entry[1], view[0]], view[1], 3.4 if entry[0] == &"spear_01" else 2.7)
	var file := FileAccess.open(output + "/" + sex + "_measurements.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "\t"))
	file.close()
	if stage.ends_with("final"):
		file = FileAccess.open(output + "/" + sex + "_motion_checks.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(checks,"\t"))
		file.close()
		editor.combat_ready = false
		assert(editor.select_part_by_id(&"weapon", &"axe_01"))
		assert(editor.select_part_by_id(&"shield", &"none"))
		assert(editor.select_animation_by_id(&"idle"))
		editor.animation_player.seek(.2,true)
		await capture(sex + "_axe_holstered", 150, 2.7)
		editor.combat_ready = true
		assert(editor.select_animation_by_id(&"T-Pose"))
		editor.animation_player.seek(0,true)
		editor.set_preview_yaw_degrees(110)
		for node: Node in editor.model_root.find_children("*", "MeshInstance3D", true, false):
			if not str(node.name).begins_with("Weapon_Axe_01_"):
				(node as Node3D).hide()
		var center := (_center("Weapon_Axe_01_Haft") + _center("Weapon_Axe_01_Blade")) * .5
		editor.camera.size = 1.0
		editor.camera.position = center + Vector3(0, .04, -5)
		editor.camera.look_at(center)
		await process_frame
		await RenderingServer.frame_post_draw
		assert(editor.preview_viewport.get_texture().get_image().save_png(output + "/" + sex + "_axe_detail.png") == OK)
		print("WEAPON_REFRESH_RAW_MOTION_PASS ", sex, " ", checks)
	print("WEAPON_REFRESH_PREVIEW_COMPLETE ", sex, " ", stage, "; diagnostic capture, not a correctness assertion")
	editor.queue_free()
	await process_frame
	await process_frame
	quit(0)

func vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _bone(label: String) -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(label)).origin

func _center(label: String) -> Vector3:
	var part := editor.model_root.find_child(label, true, false) as MeshInstance3D
	assert(part != null, label)
	var points: PackedVector3Array = geometry.posed_vertices(part, skeleton)
	var center := Vector3.ZERO
	for point in points:
		center += point
	return center / points.size()

func _ends(label: String) -> Array[Vector3]:
	var part := editor.model_root.find_child(label, true, false) as MeshInstance3D
	var points: PackedVector3Array = geometry.posed_vertices(part, skeleton)
	var originals: PackedVector3Array = part.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert(points.size() == originals.size())
	var bounds := part.mesh.get_aabb()
	var axis := bounds.size.max_axis_index()
	var sums: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var counts := [0, 0]
	for index in originals.size():
		var side := int(originals[index][axis] > bounds.get_center()[axis])
		sums[side] += points[index]
		counts[side] += 1
	return [sums[0] / counts[0], sums[1] / counts[1]]

func _pierces_shield(start: Vector3, end: Vector3) -> bool:
	var field := editor.model_root.find_child("Shield_Heater_01_Field", true, false) as MeshInstance3D
	var vertices := geometry.posed_vertices(field, skeleton)
	var offset := 0
	for surface in field.mesh.get_surface_count():
		var arrays := field.mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index in range(0, indices.size(), 3):
			if Geometry3D.segment_intersects_triangle(start, end, vertices[offset + indices[index]], vertices[offset + indices[index + 1]], vertices[offset + indices[index + 2]]) != null:
				return true
		offset += points.size()
	return false

func capture(label: String, yaw: float, size: float) -> void:
	editor.set_preview_yaw_degrees(yaw)
	editor.preview_viewport.size = Vector2i(1280, 1280)
	editor.preview_viewport.msaa_3d = Viewport.MSAA_4X
	editor.camera.size = size
	var center := Vector3(0, 1.3 if label.begins_with("attack_jump_heavy") else .85, 0)
	editor.camera.position = center + Vector3(0, .25, -6)
	editor.camera.look_at(center)
	await process_frame
	await RenderingServer.frame_post_draw
	assert(editor.preview_viewport.get_texture().get_image().save_png(output + "/" + label + ".png") == OK)
