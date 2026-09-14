extends SceneTree
## Native GPU arithmetic/transfer gate; not an FPS or crowd acceptance test.
const Source = preload("res://scripts/terrain_lab/terrain_army_contact_source.gd")
const Skinner = preload("res://scripts/terrain_lab/terrain_gpu_skinner.gd")
var started := 0
var complete := false
var results: Array[Dictionary] = []
var timings: Array[Dictionary] = []
var mismatch_count := 0
var gpu: RefCounted
var mutation_cases: Array[Dictionary] = []

func _initialize() -> void:
	started = Time.get_ticks_usec()
	run.call_deferred()

func _compare(label: String, expected: PackedVector3Array, actual: PackedVector3Array) -> void:
	var differing := 0
	var maximum := 0.0
	var first := {}
	if expected.size() != actual.size():
		differing = maxi(expected.size(), actual.size())
	else:
		for index in expected.size():
			if var_to_bytes(expected[index]) != var_to_bytes(actual[index]):
				differing += 1
				maximum = maxf(maximum, expected[index].distance_to(actual[index]))
				if first.is_empty():
					first = {"index": index, "cpu": expected[index], "gpu": actual[index],
						"cpu_bits": var_to_bytes(expected[index]).hex_encode(), "gpu_bits": var_to_bytes(actual[index]).hex_encode()}
	mismatch_count += differing
	results.append({"label": label, "vertices": expected.size(), "different_vertices": differing, "maximum_error": maximum, "first": first})

func _palette(part: MeshInstance3D, skeleton: Skeleton3D) -> Array[Transform3D]:
	var palette: Array[Transform3D] = []
	for binding in part.skin.get_bind_count():
		var bone := part.skin.get_bind_bone(binding)
		if bone < 0:
			bone = skeleton.find_bone(part.skin.get_bind_name(binding))
		palette.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone) * part.skin.get_bind_pose(binding) if bone >= 0 else part.global_transform)
	return palette

func _cpu_batch(vertices: PackedVector3Array, bones: PackedInt32Array, weights: PackedFloat32Array, palettes: Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	var influences := int(float(bones.size()) / vertices.size())
	for palette: Array in palettes:
		for vertex in vertices.size():
			var point := Vector3.ZERO
			for slot in influences:
				var index := vertex * influences + slot
				point += (palette[bones[index]] * vertices[vertex]) * weights[index]
			result.append(point)
	return result

func _test_surface_mutations() -> bool:
	# Separate from the original 107 comparisons and timing/profile sample. The
	# same caller-owned arrays are changed in place, never replaced with copies.
	var key := "mutable_surface_regression"
	var vertices := PackedVector3Array([Vector3(1.0, 2.0, 3.0)])
	var bones := PackedInt32Array([0])
	var weights := PackedFloat32Array([1.0])
	var palette: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D(Basis.IDENTITY, Vector3(10.0, 20.0, 30.0))]
	if not gpu.register_surface(key, vertices, bones, weights):
		mutation_cases.append({"label": "initial_registration", "status": "FAIL", "reason": "initial registration failed"})
		return false
	for label: String in ["vertex", "bone_index", "weight", "grow", "shrink"]:
		var previous_vertices := vertices.to_byte_array()
		var previous_bones := bones.to_byte_array()
		var previous_weights := weights.to_byte_array()
		var entry: Dictionary = gpu.surfaces[key]
		var previous_maximum: int = entry.maximum_bone
		match label:
			"vertex": vertices[0] = Vector3(4.0, 5.0, 6.0)
			"bone_index": bones[0] = 1
			"weight": weights[0] = 0.5
			"grow":
				vertices.append(Vector3(7.0, 8.0, 9.0))
				bones.append(0)
				weights.append(1.0)
			"shrink":
				vertices.resize(1)
				bones.resize(1)
				weights.resize(1)
		var record := {"label": label, "status": "FAIL", "dispatches": 0,
			"resident_snapshot_unchanged": entry.vertices.to_byte_array() == previous_vertices
				and entry.bones.to_byte_array() == previous_bones
				and entry.weights.to_byte_array() == previous_weights
				and int(entry.maximum_bone) == previous_maximum}
		mutation_cases.append(record)
		if not record.resident_snapshot_unchanged:
			# Do not dispatch from contaminated metadata: grow/shrink could otherwise
			# use the new count against an old, differently sized GPU allocation.
			record.reason = "caller mutation changed resident metadata before registration; unsafe dispatch skipped"
			return false
		var upload_before: int = gpu.profile.surface_upload_bytes
		if not gpu.register_surface(key, vertices, bones, weights):
			record.reason = "changed surface registration failed"
			return false
		record.upload_bytes = int(gpu.profile.surface_upload_bytes) - upload_before
		var expected_upload := vertices.to_byte_array().size() + bones.to_byte_array().size() + weights.to_byte_array().size()
		if int(record.upload_bytes) != expected_upload:
			record.reason = "changed surface did not upload all new arrays; unsafe dispatch skipped"
			return false
		var before: Dictionary = gpu.profile.duplicate(true)
		var expected := _cpu_batch(vertices, bones, weights, [palette])
		var actual: PackedVector3Array = gpu.skin_batch(key, [palette])
		record.dispatches = int(gpu.profile.batches) - int(before.batches)
		record.gpu_vertices = int(gpu.profile.vertices) - int(before.vertices)
		record.exact_vertex_bits = expected.to_byte_array() == actual.to_byte_array()
		if int(record.dispatches) != 1 or int(record.gpu_vertices) != expected.size() or not record.exact_vertex_bits:
			record.reason = "re-registered GPU result or dispatch accounting differs from CPU"
			return false
		record.status = "PASS"
	return true

func run() -> void:
	create_timer(54.0).timeout.connect(func() -> void: push_error("GPU skinning test watchdog"); quit(1))
	gpu = Skinner.new()
	assert(gpu.initialize(), gpu.last_error)
	assert(TerrainArmy.load_combat_bake())
	var body := 1 if "--body=female" in OS.get_cmdline_user_args() else 0
	var appearance: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
	appearance.body = body
	appearance.parts.hair = HumanCharacter3DEditor.default_appearance(body).parts.hair
	var source := Source.new()
	assert(source.initialize(root, appearance))
	source.geometry.skinning_profile_enabled = true
	var palettes: Array = []
	var batch_arrays: Array = []
	for direction_index in 4:
		assert(Time.get_ticks_usec() - started < 51000000)
		var direction: Vector2i = [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT][direction_index]
		var pose := source.sample(&"walk_slash", 0.317 + direction_index * 0.041, direction, Vector2.ZERO, 0.0, appearance)
		assert(not pose.is_empty())
		var skeleton: Skeleton3D = source.skeleton
		for node: Node in source.editor.model_root.find_children("*", "MeshInstance3D", true, false):
			var part := node as MeshInstance3D
			if not part.is_visible_in_tree() or part.mesh == null or part.skin == null:
				continue
			if not str(part.name).begins_with("Face_Standard") and not str(part.name).begins_with("Shield_") and not str(part.name).begins_with("Weapon_"):
				continue
			source.geometry.gpu_skinner = null
			var expected: PackedVector3Array = source.geometry.posed_vertices(part, skeleton, false)
			assert(not expected.is_empty())
			var before: Dictionary = gpu.profile.duplicate(true)
			var fallbacks_before: int = source.geometry.skinning_profile.gpu_fallbacks
			source.geometry.gpu_skinner = gpu
			var actual: PackedVector3Array = source.geometry.posed_vertices(part, skeleton, false)
			source.geometry.gpu_skinner = null
			_compare("%s/d%d" % [part.name, direction_index], expected, actual)
			var dispatched: int = int(gpu.profile.batches) - int(before.batches)
			var dispatched_vertices: int = int(gpu.profile.vertices) - int(before.vertices)
			results[-1].merge({"native_rigid": false, "dispatches": dispatched, "gpu_vertices": dispatched_vertices, "cpu_rigid_vertices": 0})
			assert(dispatched > 0 and dispatched_vertices == expected.size(), "Forced scalar comparison must really dispatch every vertex")
			assert(int(source.geometry.skinning_profile.gpu_fallbacks) == fallbacks_before)
			# Also compare the real default route. Rigid native surfaces intentionally
			# stay on CPU; they are explicitly counted, never labelled GPU coverage.
			var native_expected: PackedVector3Array = source.geometry.posed_vertices(part, skeleton, true)
			before = gpu.profile.duplicate(true)
			var geometry_before: Dictionary = source.geometry.skinning_profile.duplicate(true)
			source.geometry.gpu_skinner = gpu
			var native_actual: PackedVector3Array = source.geometry.posed_vertices(part, skeleton, true)
			source.geometry.gpu_skinner = null
			_compare("%s/d%d/native_rigid" % [part.name, direction_index], native_expected, native_actual)
			dispatched = int(gpu.profile.batches) - int(before.batches)
			dispatched_vertices = int(gpu.profile.vertices) - int(before.vertices)
			var rigid_vertices: int = int(source.geometry.skinning_profile.rigid_vertices) - int(geometry_before.rigid_vertices)
			results[-1].merge({"native_rigid": true, "dispatches": dispatched, "gpu_vertices": dispatched_vertices,
				"cpu_rigid_vertices": rigid_vertices, "route": "CPU_NATIVE_ONLY" if dispatched == 0 else "GPU_WITH_NATIVE_RIGID"})
			assert(not native_expected.is_empty() and dispatched_vertices + rigid_vertices == native_expected.size())
			assert((dispatched > 0) == (dispatched_vertices > 0))
			assert(int(source.geometry.skinning_profile.gpu_fallbacks) == int(geometry_before.gpu_fallbacks))
			assert(int(source.geometry.skinning_profile.scalar_vertices) == int(geometry_before.scalar_vertices))
			if str(part.name).begins_with("Face_Standard"):
				if batch_arrays.is_empty():
					for surface in part.mesh.get_surface_count():
						var candidate: Array = part.mesh.surface_get_arrays(surface)
						if batch_arrays.is_empty() or candidate[Mesh.ARRAY_VERTEX].size() > batch_arrays[Mesh.ARRAY_VERTEX].size():
							batch_arrays = candidate
				palettes.append(_palette(part, skeleton))
	assert(not results.is_empty() and palettes.size() == 4)
	var vertices: PackedVector3Array = batch_arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = batch_arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = batch_arrays[Mesh.ARRAY_WEIGHTS]
	assert(gpu.register_surface("batch_face", vertices, bones, weights))
	for count: int in [1, 8, 32]:
		var batch: Array = []
		for index in count:
			batch.append(palettes[index % palettes.size()])
		var expected := _cpu_batch(vertices, bones, weights, batch)
		var before: Dictionary = gpu.profile.duplicate(true)
		var actual: PackedVector3Array = gpu.skin_batch("batch_face", batch)
		_compare("batch_face_%d" % count, expected, actual)
		assert(not expected.is_empty() and int(gpu.profile.batches) == int(before.batches) + 1)
		assert(int(gpu.profile.vertices) == int(before.vertices) + expected.size())
		results[-1].merge({"dispatches": 1, "gpu_vertices": actual.size(), "cpu_rigid_vertices": 0})
		var passes: Array[Dictionary] = []
		for enabled: bool in [false, true, true, false]:
			assert(Time.get_ticks_usec() - started < 51000000)
			var begin := Time.get_ticks_usec()
			var checksum := 0
			for repeat_index in 2:
				var calculated: PackedVector3Array = gpu.skin_batch("batch_face", batch) if enabled else _cpu_batch(vertices, bones, weights, batch)
				checksum += calculated.size()
			passes.append({"gpu": enabled, "usec": Time.get_ticks_usec() - begin, "checksum": checksum})
			assert(checksum == vertices.size() * count * 2)
		timings.append({"batch_size": count, "vertices_per_job": vertices.size(), "passes": passes})
	# Exact-size/binding limits must fail closed without dispatch or OOB reads.
	var batches_before: int = gpu.profile.batches
	var vertices_before: int = gpu.profile.vertices
	assert(gpu.skin_batch("missing", palettes).is_empty())
	assert(gpu.skin_batch("batch_face", [[]]).is_empty())
	var one_vertex := PackedVector3Array([Vector3(1.0, 2.0, 3.0)])
	var one_bone := PackedInt32Array([0])
	var one_weight := PackedFloat32Array([1.0])
	var one_palette: Array[Transform3D] = [Transform3D.IDENTITY]
	assert(not gpu.register_surface("negative_index", one_vertex, PackedInt32Array([-1]), one_weight))
	assert(gpu.register_surface("guard", one_vertex, one_bone, one_weight))
	# Correctly sized input, but binding 1 is outside this one-bone palette.
	assert(gpu.register_surface("outside_palette", one_vertex, PackedInt32Array([1]), PackedFloat32Array([0.0])))
	assert(gpu.skin_batch("outside_palette", [one_palette]).is_empty())
	var jobs: Array = []
	jobs.resize(257)
	jobs.fill(one_palette)
	assert(gpu.skin_batch("guard", jobs).is_empty())
	var two_bones: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY]
	assert(gpu.skin_batch("guard", [one_palette, two_bones]).is_empty())
	for invalid: float in [NAN, INF, -INF]:
		assert(not gpu.register_surface("nonfinite_vertex", PackedVector3Array([Vector3(invalid, 0.0, 0.0)]), one_bone, one_weight))
		assert(not gpu.register_surface("nonfinite_weight", one_vertex, one_bone, PackedFloat32Array([invalid])))
		var invalid_palette: Array[Transform3D] = [Transform3D(Basis.IDENTITY, Vector3(invalid, 0.0, 0.0))]
		assert(gpu.skin_batch("guard", [invalid_palette]).is_empty())
	var oversized_palette: Array[Transform3D] = []
	oversized_palette.resize(Skinner.MAX_MATRICES + 1)
	oversized_palette.fill(Transform3D.IDENTITY)
	assert(gpu.skin_batch("guard", [oversized_palette]).is_empty())
	# 4,097 vertices x 256 legal jobs exceeds the output bound, without a giant
	# input allocation or an unsafe dispatch. These are typed numerical probes.
	var output_vertices := PackedVector3Array()
	output_vertices.resize(int(float(Skinner.MAX_VERTICES) / 256.0) + 1)
	var output_bones := PackedInt32Array()
	output_bones.resize(output_vertices.size())
	var output_weights := PackedFloat32Array()
	output_weights.resize(output_vertices.size())
	output_weights.fill(1.0)
	assert(gpu.register_surface("output_limit", output_vertices, output_bones, output_weights))
	jobs.resize(256)
	assert(gpu.skin_batch("output_limit", jobs).is_empty())
	assert(int(gpu.profile.batches) == batches_before)
	assert(int(gpu.profile.vertices) == vertices_before)
	assert(Time.get_ticks_usec() - started < 51000000)
	var final_profile: Dictionary = gpu.profile.duplicate(true)
	var final_geometry_profile: Dictionary = source.geometry.skinning_profile.duplicate(true)
	source.dispose()
	var mutations_passed := _test_surface_mutations()
	var mutation_profile := {}
	for field: String in gpu.profile:
		mutation_profile[field] = int(gpu.profile[field]) - int(final_profile[field])
	var surface_sets: Array[RID] = []
	for entry: Dictionary in gpu.surfaces.values():
		surface_sets.append(entry.uniform_set)
	gpu.clear_surfaces()
	assert(gpu.surfaces.is_empty())
	for uniform_set: RID in surface_sets:
		assert(not gpu.rd.uniform_set_is_valid(uniform_set))
	var old_device: RenderingDevice = gpu.rd
	gpu.dispose()
	gpu.dispose() # Idempotent cleanup, including all per-surface RIDs.
	assert(gpu.surfaces.is_empty() and gpu.rd == null and not is_instance_valid(old_device))
	assert(not gpu.shader.is_valid() and not gpu.pipeline.is_valid())
	assert(not gpu.matrix_buffer.is_valid() and not gpu.output_buffer.is_valid())
	assert(gpu.skin_batch("guard", [one_palette]).is_empty())
	await process_frame
	var report := {"status": "PASS" if mismatch_count == 0 and mutations_passed else "FAIL", "body": body,
		"different_vertices": mismatch_count, "results": results, "timings": timings,
		"profile": final_profile, "geometry_profile": final_geometry_profile, "elapsed_usec": Time.get_ticks_usec() - started,
		"mutation_cases": mutation_cases, "mutation_profile": mutation_profile, "mutations_passed": mutations_passed,
		"mutation_scope": "Separate same-key, same-array vertex/bone/weight/grow/shrink regression after the original profile snapshot. Contaminated resident metadata or a missing re-upload aborts this regression before any unsafe dispatch; overall status remains FAIL after cleanup.",
		"guard_cases": ["missing_surface", "empty_palette", "negative_index", "valid_size_outside_palette_zero_weight", "257_jobs", "different_palette_lengths", "NaN_Inf_vertex_weight_palette", "matrix_limit_plus_one", "output_limit_exceeded"],
		"cleanup": {"surface_entries": 0, "former_uniform_sets_invalid": surface_sets.size(), "owner_rids_invalid": true, "device_null_and_freed": true, "dispose_twice": true},
		"gpu_name": RenderingServer.get_video_adapter_name(), "driver": RenderingServer.get_current_rendering_driver_name(),
		"geometry_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_weapon_collision.gd"),
		"skinner_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_gpu_skinner.gd"),
		"scope": "Original visible face/shield/weapon, four original CPU bone palettes, exact vertex bits. Every forced GPU case verifies dispatch and vertex counters; native_rigid=true also compares the actual route and labels CPU rigid skips. Typed numerical limits are rejection-only probes, not arbitrary Variant validation. Repeated palettes model batch transfer break-even only, not 200-person combat or frame timing. Native morph remains CPU. Candidate disabled in production. PASS is recorded only after cleanup assertions."}
	var path := "res://output/site_combat_gpu/skinning/body%d_%d_%d/measurements.json" % [body, int(Time.get_unix_time_from_system()), started]
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) == OK)
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	complete = mismatch_count == 0 and mutations_passed
	print("SITE_GPU_SKINNING_", report.status, " ", path)
	quit(0 if complete else 1)
