extends SceneTree
## GPU exact vertex comparison; --group=synthetic|male|female, internal 23/helper 25 s.
const Frozen = preload("res://output/site_combat_performance_20260913/before/terrain_weapon_collision.gd")
const Current = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")
const FROZEN_PATH := "res://output/site_combat_performance_20260913/before/terrain_weapon_collision.gd"
const FROZEN_SHA256 := "151E950DAF13B63F536404146F42828B2D279C9FD6E7833EF462023A8089B782"
var group := "synthetic"
var began_us := 0
var frozen := Frozen.new()
var current := Current.new()
var checked := 0
var vertices := 0
var maximum_error := 0.0
var times := {"original_native": 0, "new_native": 0, "original_scalar": 0, "new_scalar": 0}
var failures: Array[String] = []
var rows: Array[Dictionary] = []

func _initialize() -> void:
	began_us = Time.get_ticks_usec()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--group="):
			group = argument.trim_prefix("--group=")
	run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_usec() - began_us >= 23000000:
		push_error("SITE_SKIN_PALETTE deadline: " + group)
		quit(1)
	return false

func run() -> void:
	assert(group in ["synthetic", "male", "female"])
	assert(DisplayServer.get_name() != "headless", "Active morph baking and original actors require the GPU verifier")
	assert(FileAccess.get_sha256(FROZEN_PATH).to_upper() == FROZEN_SHA256)
	if group == "synthetic":
		_synthetic()
	else:
		await _original_actor()
	_finish()

func _synthetic() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var rig := Skeleton3D.new()
	rig.name = "Skeleton3D"
	world.add_child(rig)
	for index in range(32):
		rig.add_bone("Bone%d" % index)
		rig.set_bone_rest(index, Transform3D(Basis.IDENTITY, Vector3(index * 0.017, 0.2, -0.03)))
		rig.set_bone_pose_position(index, Vector3(index * 0.013, 0.1, 0.02))
		rig.set_bone_pose_rotation(index, Quaternion.from_euler(Vector3(index * 0.009, -0.07, 0.03)))
	var specs: Array[Dictionary] = [
		{"name": "no_skin", "skin": "none", "surfaces": [-3]},
		{"name": "zero_binds", "skin": "empty", "surfaces": [-3]},
		{"name": "no_influences", "skin": "normal", "surfaces": [-3]},
		{"name": "rigid_many_unused_binds", "skin": "normal", "surfaces": [7]},
		{"name": "named_bind", "skin": "named", "surfaces": [7]},
		{"name": "multi_same_bind", "skin": "normal", "surfaces": [7, 7]},
		{"name": "multi_different_bind", "skin": "normal", "surfaces": [7, 23]},
		{"name": "rigid_then_nonrigid", "skin": "normal", "surfaces": [7, -1]},
		{"name": "nonrigid_then_rigid", "skin": "normal", "surfaces": [-1, 23]},
		{"name": "all_zero_weights", "skin": "normal", "surfaces": [-2]},
		{"name": "normalized_morph_rigid", "skin": "normal", "surfaces": [7], "morph": Mesh.BLEND_SHAPE_MODE_NORMALIZED},
		{"name": "relative_morph_nonrigid", "skin": "normal", "surfaces": [-1], "morph": Mesh.BLEND_SHAPE_MODE_RELATIVE},
		{"name": "morph_without_skin", "skin": "none", "surfaces": [-3], "morph": Mesh.BLEND_SHAPE_MODE_NORMALIZED},
	]
	var parts: Array[MeshInstance3D] = []
	for spec: Dictionary in specs:
		var part := MeshInstance3D.new()
		part.name = str(spec.name)
		var mesh := ArrayMesh.new()
		if spec.has("morph"):
			mesh.blend_shape_mode = int(spec.morph)
			mesh.add_blend_shape("OriginalMorph")
		for binding: int in spec.surfaces:
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(0, 2, 0)])
			if binding != -3:
				var bones := PackedInt32Array()
				var weights := PackedFloat32Array()
				for vertex in range(3):
					bones.append_array(PackedInt32Array([binding if binding >= 0 else 7, 23, 0, 0]))
					weights.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]) if binding >= 0 else (PackedFloat32Array([0.25, 0.75, 0.0, 0.0]) if binding == -1 else PackedFloat32Array([0.0, 0.0, 0.0, 0.0])))
				arrays[Mesh.ARRAY_BONES] = bones
				arrays[Mesh.ARRAY_WEIGHTS] = weights
			var morphs: Array[Array] = []
			if spec.has("morph"):
				var target: Array = []
				target.resize(Mesh.ARRAY_MAX)
				target[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 3, 0), Vector3(1, 3, 0), Vector3(0, 4, 0)]) if int(spec.morph) == Mesh.BLEND_SHAPE_MODE_NORMALIZED else PackedVector3Array([Vector3(0, 2, 0), Vector3(0, 2, 0), Vector3(0, 2, 0)])
				morphs.append(target)
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, morphs)
		part.mesh = mesh
		if str(spec.skin) != "none":
			var skin := Skin.new()
			if str(spec.skin) != "empty":
				for index in range(32):
					skin.add_bind(index, Transform3D(Basis.IDENTITY, Vector3(-index * 0.017, -0.2, 0.03)))
				if str(spec.skin) == "named":
					skin.set_bind_bone(7, -1)
					skin.set_bind_name(7, &"Bone7")
			part.skin = skin
			part.skeleton = NodePath("../Skeleton3D")
		world.add_child(part)
		part.transform = Transform3D(Basis.from_euler(Vector3(0.1, 0.2, 0.3)), Vector3(3, -2, 1))
		if spec.has("morph"):
			part.set_blend_shape_value(0, 0.5)
		parts.append(part)
	for phase in range(2):
		if phase == 1:
			# A new real pose/global transform must not reuse the previous palette.
			rig.set_bone_pose_rotation(7, Quaternion.from_euler(Vector3(-0.4, 0.7, 0.2)))
			rig.set_bone_pose_position(23, Vector3(0.9, -0.3, 0.4))
			world.transform = Transform3D(Basis.from_euler(Vector3(0.2, -0.3, 0.1)), Vector3(-4, 7, 2))
		rig.force_update_all_bone_transforms()
		for part: MeshInstance3D in parts:
			_compare(part, rig, "%s/pose%d" % [str(part.name), phase])
			if not failures.is_empty():
				break
		if not failures.is_empty():
			break
	world.free()

func _original_actor() -> void:
	var actor := TerrainTestCharacter.new()
	actor.visual_state.body_index = 1 if group == "female" else 0
	actor.combat_driven_by_lab = true
	root.add_child(actor)
	actor.set_process(false)
	actor.initialize_visual()
	assert(actor.editor != null and not actor.editor.use_imported_model)
	actor.editor.set_process(false)
	actor.editor.set_playing(false)
	actor.editor.combat_ready = true
	actor.editor.visual_state.combat_ready = true
	for selection: Array in [[&"shield", &"shield_heater_01"], [&"helmet", &"helmet_mingguang_01"],
		[&"armor", &"armor_mingguang_01"], [&"outfit", &"outfit_chinese_lining_01"], [&"boots", &"boots_mingguang_01"]]:
		assert(actor.editor.select_part_by_id(selection[0], selection[1]))
	var rig := actor.editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	assert(rig != null)
	for sample: Array in [[&"longsword_01", &"walk_slash", 0.517], [&"spear_01", &"attack_spear", 0.537],
		[&"longsword_01", &"down", 1.137], [&"longsword_01", &"get_up", 0.337]]:
		assert(actor.editor.select_part_by_id(&"weapon", sample[0]))
		actor.play_pose(sample[1])
		actor.editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		actor.editor._on_timeline_changed(float(sample[2]))
		actor.editor.animation_player.advance(0.0)
		rig.force_update_all_bone_transforms()
		for node: Node in actor.editor.model_root.find_children("*", "MeshInstance3D", true, false):
			var part := node as MeshInstance3D
			var label := str(part.name)
			if not part.is_visible_in_tree() or part.mesh == null:
				continue
			if label.begins_with("Weapon_") or label.begins_with("Shield_") or label.begins_with("Armor_") or label.begins_with("Helmet_") or label.begins_with("Outfit_") or label.begins_with("Boots_"):
				_compare(part, rig, "%s/%s/%s" % [group, sample[1], label])
			if not failures.is_empty():
				break
		if not failures.is_empty():
			break
		await process_frame
	actor.free()

func _compare(part: MeshInstance3D, rig: Skeleton3D, label: String) -> void:
	if Time.get_ticks_usec() - began_us >= 23000000:
		failures.append("Bounded test deadline")
		return
	var part_id := part.get_instance_id()
	var mesh_id := part.mesh.get_instance_id()
	for native: bool in [true, false]:
		var suffix := "native" if native else "scalar"
		var stamp := Time.get_ticks_usec()
		var expected := frozen.posed_vertices(part, rig, native)
		times["original_" + suffix] += Time.get_ticks_usec() - stamp
		stamp = Time.get_ticks_usec()
		var actual := current.posed_vertices(part, rig, native)
		times["new_" + suffix] += Time.get_ticks_usec() - stamp
		var error := 0.0
		if expected.size() != actual.size():
			error = INF
		else:
			for index in range(expected.size()):
				error = maxf(error, expected[index].distance_to(actual[index]))
		maximum_error = maxf(maximum_error, error)
		if expected != actual or current.posed_vertices(part, rig, native) != expected:
			failures.append("Exact %s vertices differ: %s, error=%s" % [suffix, label, error])
		vertices += expected.size()
		checked += 1
		rows.append({"case": label, "native_rigid": native, "vertices": expected.size(), "maximum_error": error,
			"binds": part.skin.get_bind_count() if part.skin != null else 0, "surfaces": part.mesh.get_surface_count(), "morphs": part.get_blend_shape_count()})
	if part.get_instance_id() != part_id or part.mesh.get_instance_id() != mesh_id:
		failures.append("Query replaced the original mesh/person component")

func _finish() -> void:
	var passed := failures.is_empty() and checked > 0 and maximum_error == 0.0
	if group == "synthetic":
		passed = passed and checked == 52
	var report := {"pass": passed, "group": group, "comparisons": checked, "vertices": vertices, "maximum_error": maximum_error,
		"times_usec": times, "wall_ms": (Time.get_ticks_usec() - began_us) / 1000.0, "rows": rows, "failures": failures,
		"frozen_source_sha256": FROZEN_SHA256,
		"current_source_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_weapon_collision.gd").to_upper(),
		"scope": "Frozen versus current separately for native_rigid=true and unchanged scalar=false. Exact per-vertex equality, original morph mix, multi-surface/pose changes. Timings are vertex calls only, not FPS."}
	var path := "res://output/site_combat_performance_20260913/skin_palette/%s.json" % group
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	if passed:
		print("SITE_SKIN_PALETTE_PASS ", JSON.stringify(report))
	else:
		push_error("SITE_SKIN_PALETTE_FAIL ", JSON.stringify(report))
	quit(0 if passed else 1)
