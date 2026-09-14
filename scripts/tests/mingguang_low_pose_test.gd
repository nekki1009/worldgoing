extends SceneTree

const Collision = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")
var editor: HumanCharacter3DEditor
var output := "res://.visual_captures/mingguang_low_pose"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var sex := args[0] if not args.is_empty() else "male"
	var stage := args[1] if args.size() > 1 else "candidate"
	var full := args.size() > 2 and args[2] == "full"
	output += "/" + stage
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 60
	editor = HumanCharacter3DEditor.new()
	root.add_child(editor)
	editor.open()
	editor._load_body_model(1 if sex == "female" else 0,
		"res://.godot-temp/mingguang_low_pose_20260912/candidate/%s.glb" % sex if stage.begins_with("candidate") else "")
	await process_frame
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(5, 5)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.13, .16, .18)
	material.roughness = 1.0
	ground.material_override = material
	editor.preview_world.add_child(ground)
	ground.global_position = editor.preview_pivot.global_position
	for pair in [[&"armor", &"armor_mingguang_01"], [&"outfit", &"outfit_underlayer_01"],
		[&"cape", &"none"], [&"helmet", &"none"], [&"weapon", &"none"], [&"shield", &"none"]]:
		assert(editor.select_part_by_id(pair[0], pair[1]))
	var collision := Collision.new()
	_test_morph_vertices(collision)
	var skeleton := editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var parts: Array[MeshInstance3D] = []
	var boots: Array[MeshInstance3D] = []
	for node in editor.model_root.find_children("Armor_Mingguang_01_*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.get_blend_shape_count() > 0:
			parts.append(mesh)
	assert(parts.size() == 10)
	for node in editor.model_root.find_children("Boots_Leather_01*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.is_visible_in_tree():
			boots.append(mesh)
	assert(not boots.is_empty())
	for clip: StringName in [&"T-Pose", &"down", &"unconscious", &"get_up", &"rescue", &"idle"]:
		assert(editor.select_animation_by_id(clip))
		editor.set_playing(false)
		editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var length := editor._animation_length()
		var low_pose := clip in [&"down", &"unconscious", &"get_up", &"rescue"]
		var rate := 96.0 if clip == &"get_up" else 48.0
		var capture_every := 8 if clip == &"get_up" else 4
		var count := ceili(length * rate) + 1 if full and low_pose else 5
		var lowest := INF
		var foot_lowest := INF
		for sample in range(count):
			var time := minf(length * sample / maxf(count - 1, 1), length - .001)
			editor.animation_player.seek(time, true)
			skeleton.force_update_all_bone_transforms()
			if clip == &"get_up":
				for boot in boots:
					for point in collision.posed_vertices(boot, skeleton):
						foot_lowest = minf(foot_lowest, point.y - editor.preview_pivot.global_position.y)
			for part in parts:
				var part_low := INF
				for point in collision.posed_vertices(part, skeleton):
					lowest = minf(lowest, point.y - editor.preview_pivot.global_position.y)
					part_low = minf(part_low, point.y - editor.preview_pivot.global_position.y)
				if part_low < -.004:
					print("MINGGUANG_FLOOR_FAILURE ", part.name, " time=", time, " low=", part_low)
				if not low_pose:
					for shape in part.get_blend_shape_count():
						assert(is_zero_approx(part.get_blend_shape_value(shape)), "Stale low-pose morph " + str(clip))
			if full and low_pose and sample % capture_every == 0:
				await _capture("%s_%s_motion_%03d" % [sex, clip, floori(float(sample) / capture_every)], 35)
			if sample in [0, int(count * .25), int(count * .5), int(count * .75), count - 1]:
				await _capture("%s_%s_key_%03d" % [sex, clip, sample], 35)
		print("MINGGUANG_POSE_MIN_Y ", sex, " ", clip, " ", lowest, " samples=", count)
		if clip == &"get_up":
			print("GET_UP_BOOTS_MIN_Y ", sex, " ", foot_lowest)
		if lowest < -.004 or foot_lowest < -.008:
			printerr("Low pose penetrates the floor: ", clip, " skirt=", lowest, " boots=", foot_lowest)
			editor.queue_free()
			await process_frame
			quit(1)
			return
		editor.animation_player.seek(length * .5, true)
		for view in [["front", 0], ["back", 180], ["side", 90]]:
			await _capture("%s_%s_%s" % [sex, clip, view[0]], view[1])
	# Exercise the same outfit/animation switches as the editor, including a
	# hidden skirt receiving a low-pose track before it becomes visible again.
	assert(editor.select_animation_by_id(&"rescue"))
	editor.animation_player.seek(2.0, true)
	for armor: StringName in [&"none", &"armor_light_leather_01", &"armor_mingguang_01"]:
		assert(editor.select_part_by_id(&"armor", armor))
		assert(editor.select_animation_by_id(&"idle"))
		editor.animation_player.seek(.2, true)
		for part in parts:
			for shape in part.get_blend_shape_count():
				assert(is_zero_approx(part.get_blend_shape_value(shape)), "Outfit switch retained a low-pose morph")
		assert(editor.select_animation_by_id(&"rescue"))
		editor.animation_player.seek(2.0, true)
	assert(editor.select_animation_by_id(&"idle"))
	print("MINGGUANG_OUTFIT_RESET_PASS ", sex)
	print("MINGGUANG_LOW_POSE_TEST_PASS ", sex, " ", stage)
	editor.queue_free()
	await process_frame
	await process_frame
	quit(0)

func _capture(label: String, yaw: float) -> void:
	editor.set_preview_yaw_degrees(yaw)
	editor.preview_viewport.size = Vector2i(1024, 1280)
	editor.preview_viewport.msaa_3d = Viewport.MSAA_4X
	editor.camera.size = 2.7
	var center := Vector3(0, .7, 0)
	editor.camera.position = center + Vector3(0, .5, -6)
	editor.camera.look_at(center)
	await process_frame
	await RenderingServer.frame_post_draw
	assert(editor.preview_viewport.get_texture().get_image().save_png(output + "/" + label + ".png") == OK)

func _test_morph_vertices(collision: RefCounted) -> void:
	for mode in [Mesh.BLEND_SHAPE_MODE_NORMALIZED, Mesh.BLEND_SHAPE_MODE_RELATIVE]:
		var mesh := ArrayMesh.new()
		mesh.set_blend_shape_mode(mode)
		mesh.add_blend_shape("test")
		var base := []
		base.resize(Mesh.ARRAY_MAX)
		base[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(0, 2, 0)])
		var target := []
		target.resize(Mesh.ARRAY_MAX)
		target[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 3, 0), Vector3(1, 3, 0), Vector3(0, 4, 0)]) if mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED else PackedVector3Array([Vector3(0, 2, 0), Vector3(0, 2, 0), Vector3(0, 2, 0)])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, base, [target])
		var part := MeshInstance3D.new()
		part.mesh = mesh
		root.add_child(part)
		part.set_blend_shape_value(0, .5)
		var points: PackedVector3Array = collision.posed_vertices(part, null)
		assert(points[0].is_equal_approx(Vector3(0, 2, 0)))
		part.free()
