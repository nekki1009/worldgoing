extends SceneTree
## GPU/native oracle, internal 53s / canonical helper 55s. No gameplay claim.
## Requires the root-built Godot C# project; never builds or falls back to GDS.
const Source = preload("res://scripts/terrain_lab/terrain_army_contact_source.gd")
const Descriptor = preload("res://scripts/tests/helpers/site_compiled_contact_descriptor.gd")
const COMPILED_PATH := "res://scripts/terrain_lab/compiled_contact_pose.cs"

class ObservedSource extends Source:
	var binding: Dictionary = {}
	var appearance_events: Array[Dictionary] = []
	func _apply_appearance(appearance: Dictionary, recipe_key: Array) -> bool:
		if binding.is_empty() or _recipe_key == recipe_key:
			return super._apply_appearance(appearance, recipe_key)
		var before := Descriptor.morph_values(binding)
		var bones_before := []
		for bone in skeleton.get_bone_count():
			bones_before.append(skeleton.get_bone_pose(bone))
		var selected: StringName = editor.selected_animation
		var assigned: StringName = editor.animation_player.assigned_animation
		var ok := super._apply_appearance(appearance, recipe_key)
		var after := Descriptor.morph_values(binding)
		var indices := PackedInt32Array()
		var values := PackedFloat32Array()
		for index in range(before.size()):
			if PackedFloat32Array([before[index]]).to_byte_array() != PackedFloat32Array([after[index]]).to_byte_array():
				indices.append(index)
				values.append(after[index])
		var no_bone_change := true
		for bone in skeleton.get_bone_count():
			no_bone_change = no_bone_change and var_to_bytes(bones_before[bone]) == var_to_bytes(skeleton.get_bone_pose(bone))
		appearance_events.append({"indices": indices, "values": values, "admitted": no_bone_change and selected == editor.selected_animation and assigned == editor.animation_player.assigned_animation})
		return ok

var _source: Variant
var _actor: TerrainTestCharacter
var _sampler: RefCounted
var _binding: Dictionary = {}
var _deadline_usec := 0
var _finished := false
var _report := {"cases": [], "errors": [], "exact": true, "native_usec": 0, "compiled_usec": 0,
	"admission_checks": 0, "recipe_events": 0, "recipe_updated_morphs": 0,
	"scope": "Original private AnimationPlayer oracle versus ordered compiled native-track/mixer/FK sampling; original recipe owner and Geometry remain CPU. No standalone compiled collision, authoritative combat, FPS or full-scene acceptance."}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	_deadline_usec = Time.get_ticks_usec() + 53000000
	create_timer(53.0, true, false, true).timeout.connect(func() -> void:
		if not _finished:
			_error("DEADLINE", "53-second native comparison deadline")
			_finish(false))
	if DisplayServer.get_name() == "headless":
		_error("GPU_REQUIRED", "Original morph/mesh geometry must use the visual verifier; headless --check-only is parse-only")
		await _finish(false)
		return
	if not ResourceLoader.exists(COMPILED_PATH):
		_error("COMPILED_MISSING", "Root must build/import the explicit C# experiment first")
		await _finish(false)
		return
	var script: Script = load(COMPILED_PATH)
	if script == null or not script.can_instantiate():
		_error("COMPILED_UNAVAILABLE", "The C# script did not instantiate; no fallback sampler")
		await _finish(false)
		return
	_sampler = script.new() as RefCounted
	if _sampler == null or not _sampler.has_method("Compile") or not _sampler.has_method("Sample") or not _sampler.has_method("ApplyMorphUpdates"):
		_error("COMPILED_API", "Required compiled methods are absent")
		await _finish(false)
		return
	if not TerrainArmy.load_combat_bake():
		_error("BASELINE", "Original army appearance manifest unavailable")
		await _finish(false)
		return
	var baseline: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
	_actor = TerrainTestCharacter.new()
	root.add_child(_actor)
	_actor.set_process(false)
	_actor.initialize_visual()
	if _actor.editor == null or not _actor.editor.restore_appearance(baseline):
		_error("ORIGINAL_ACTOR", "Original raw same-body animation donor unavailable")
		await _finish(false)
		return
	_actor.editor.set_process(false)
	_actor.editor.set_playing(false)
	_source = ObservedSource.new()
	if not _source.initialize(root, baseline, _actor.editor):
		_error("ORIGINAL_SOURCE", "Original Source failed initialization")
		await _finish(false)
		return
	_source.terminal_cache_enabled = false
	# The original selection owner establishes each clip's native loop metadata
	# before Compile snapshots it. No test-assigned alternate loop/animation.
	for clip: StringName in [&"walk_slash", &"idle"]:
		if _source.sample(clip, 0.0, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline).is_empty():
			_error("PRELUDE", "Original clip selection failed")
			await _finish(false)
			return
	_binding = Descriptor.build(_source)
	if not bool(_binding.get("ok", false)):
		_error("DESCRIPTOR_NOT_ADMITTED", _binding)
		await _finish(false)
		return
	_source.binding = _binding
	_report["descriptor"] = _binding.counts
	_report["initial_clip"] = str(_binding.descriptor.initial_clip)
	_report["mixer_deterministic"] = _binding.descriptor.mixer_deterministic
	_report["compiled_path"] = _sampler.get_script().resource_path
	var native_digest := _animations_digest(_binding.descriptor)
	var compiled: Dictionary = _sampler.call("Compile", _binding.descriptor)
	if not bool(compiled.get("ok", false)):
		_error("COMPILE_NOT_ADMITTED", compiled)
		await _finish(false)
		return
	if not _negative_checks():
		await _finish(false)
		return
	var stripped := baseline.duplicate(true)
	stripped.parts.shield = "none"
	stripped.parts.armor = "none"
	if not _source.supports_appearance(stripped):
		_error("RECIPE_NOT_ADMITTED", "The original source cannot represent the requested missing shield/armor")
		await _finish(false)
		return
	var slash_length: float = _source.editor.animation_player.get_animation(&"walk_slash").length
	var idle_length: float = _source.editor.animation_player.get_animation(&"idle").length
	# Reverse seeks, active sword time, endpoint -> other clip -> endpoint, and
	# same-clip original recipe transitions. All use real native source times.
	var requests: Array = [
		[&"idle", 0.031, Vector2i.RIGHT, baseline, "idle_early"],
		[&"idle", 0.317, Vector2i.UP, baseline, "idle_forward"],
		[&"idle", 0.013, Vector2i.LEFT, baseline, "idle_reverse"],
		[&"walk_slash", 0.837, Vector2i.RIGHT, baseline, "slash_active"],
		[&"walk_slash", 0.913, Vector2i.UP, stripped, "same_clip_remove_shield_armor"],
		[&"walk_slash", slash_length, Vector2i.DOWN, baseline, "same_clip_restore_endpoint"],
		[&"idle", minf(0.137, idle_length), Vector2i.RIGHT, stripped, "clip_and_recipe_change"],
		[&"walk_slash", slash_length, Vector2i.LEFT, baseline, "endpoint_after_other_clip"],
		[&"walk_slash", slash_length - 0.000001, Vector2i.RIGHT, baseline, "native_near_endpoint_snap"],
		[&"walk_slash", slash_length + 0.000001, Vector2i.RIGHT, baseline, "native_above_endpoint_snap"],
		[&"walk_slash", slash_length - 0.0001, Vector2i.RIGHT, baseline, "before_native_snap_tolerance"],
		[&"walk_slash", -0.000001, Vector2i.RIGHT, baseline, "native_near_zero_seek"],
		[&"walk_slash", -0.0001, Vector2i.RIGHT, baseline, "native_negative_seek_clamp"],
	]
	for request: Array in requests:
		if not _within_deadline() or not _case(request):
			await _finish(false)
			return
		await process_frame
		if _finished:
			return
	_report["native_animation_digest_before"] = native_digest
	_report["native_animation_digest_after"] = _animations_digest(_binding.descriptor)
	if native_digest != _report.native_animation_digest_after:
		_error("NATIVE_RESOURCE_MUTATED", "Compiled sampling changed an original animation resource")
	if _report.cases.size() != requests.size():
		_error("CASE_COUNT", "A partial matrix cannot pass")
	await _finish(_report.errors.is_empty() and bool(_report.exact) and _within_deadline())

func _negative_checks() -> bool:
	var missing := Descriptor.build(_source, [&"__compiled_missing_clip__"])
	if bool(missing.get("ok", true)) or missing.get("code") != "CLIP":
		return _error("ADMISSION", "Missing original clip was not explicitly rejected")
	_report.admission_checks += 1
	for request: Array in [[&"__compiled_missing_clip__", 0.0], [&"idle", NAN], [&"idle", INF]]:
		var result: Dictionary = _sampler.call("Sample", request[0], request[1])
		if bool(result.get("ok", true)):
			return _error("ADMISSION", "Unsupported compiled request was accepted: " + str(request))
		_report.admission_checks += 1
	return true

func _case(request: Array) -> bool:
	var clip: StringName = request[0]
	var time: float = request[1]
	var appearance: Dictionary = request[3]
	_source.clear_samples() # Native actual editor/history intentionally retained.
	_source.appearance_events.clear()
	var head_before: Dictionary = _source.geometry._head_bounds.duplicate(true)
	if _report.cases.is_empty():
		head_before.clear() # Both branches must fit the same actual cold face.
	_source.geometry._head_bounds = head_before.duplicate(true)
	var began := Time.get_ticks_usec()
	var query: Dictionary = _source.sample(clip, time, request[2], Vector2.ZERO, 0.0, appearance)
	var native_usec := Time.get_ticks_usec() - began
	if query.is_empty():
		return _error("NATIVE_QUERY", "Original query failed: " + str(request[4]))
	var native := _state()
	var native_effective_time: float = _source.editor.animation_player.current_animation_position
	var points: Array[Vector2] = []
	for limb: int in [0, 3, 7, 9]:
		var center := Vector2.ZERO
		for point: Vector2 in query.body[limb]:
			center += point
		points.append(center / query.body[limb].size())
	var original_geometry := _geometry(appearance, points)
	var original_head: Dictionary = _source.geometry._head_bounds.duplicate(true)
	for event: Dictionary in _source.appearance_events:
		if not event.admitted:
			return _error("RECIPE_HISTORY_NOT_ADMITTED", "Original selection changed a bone/clip before the pose; this needs an explicit event replay, not a final-recipe assumption")
		var update: Dictionary = _sampler.call("ApplyMorphUpdates", event.indices, event.values)
		if not bool(update.get("ok", false)):
			return _error("RECIPE_UPDATE", update)
		_report.recipe_events += 1
		_report.recipe_updated_morphs += event.indices.size()
	began = Time.get_ticks_usec()
	var sampled: Dictionary = _sampler.call("Sample", clip, time)
	var compiled_usec := Time.get_ticks_usec() - began
	if not bool(sampled.get("ok", false)):
		return _error("COMPILED_SAMPLE", sampled)
	for key: String in ["positions", "rotations", "scales", "local", "global", "morphs"]:
		if not sampled.has(key) or sampled[key].size() != native[key].size():
			return _error("COMPILED_SHAPE", "Missing/wrong-sized compiled field " + key)
	var differences: Array[Dictionary] = []
	_compare(native_effective_time, sampled.effective_time, "effective_time", differences)
	for key: String in ["positions", "rotations", "scales", "local", "global", "morphs"]:
		_compare(native[key], sampled[key], key, differences)
	var geometry_differences: Array[Dictionary] = []
	# Same original body, meshes, skin bindings, camera and projection. The
	# candidate may only replace the returned sampled pose/morph values here.
	_apply_state(sampled)
	_source.geometry._head_bounds = head_before.duplicate(true)
	var candidate_geometry := _geometry(appearance, points)
	_compare(original_geometry, candidate_geometry, "geometry", geometry_differences)
	_apply_state(native)
	_source.geometry._head_bounds = original_head
	_compare(native, _state(), "native_restore", differences)
	var record := {"label": request[4], "clip": str(clip), "time": time, "effective_time": sampled.effective_time, "native_effective_time": native_effective_time, "direction": str(request[2]),
		"recipe": appearance.parts.duplicate(true), "native_usec": native_usec, "compiled_usec": compiled_usec,
		"exact": differences.is_empty() and geometry_differences.is_empty(), "differences": differences, "geometry_differences": geometry_differences}
	_report.cases.append(record)
	_report.native_usec += native_usec
	_report.compiled_usec += compiled_usec
	_report.exact = bool(_report.exact) and bool(record.exact)
	print("COMPILED CONTACT POSE CASE ", JSON.stringify(record))
	return _within_deadline()

func _state() -> Dictionary:
	var result := {"positions": PackedVector3Array(), "rotations": [], "scales": PackedVector3Array(), "local": [], "global": [], "morphs": Descriptor.morph_values(_binding)}
	for bone in range(_source.skeleton.get_bone_count()):
		result.positions.append(_source.skeleton.get_bone_pose_position(bone))
		result.rotations.append(_source.skeleton.get_bone_pose_rotation(bone))
		result.scales.append(_source.skeleton.get_bone_pose_scale(bone))
		result.local.append(_source.skeleton.get_bone_pose(bone))
		result.global.append(_source.skeleton.get_bone_global_pose(bone))
	return result

func _apply_state(state: Dictionary) -> void:
	for bone in range(_source.skeleton.get_bone_count()):
		_source.skeleton.set_bone_pose_position(bone, state.positions[bone])
		_source.skeleton.set_bone_pose_rotation(bone, state.rotations[bone])
		_source.skeleton.set_bone_pose_scale(bone, state.scales[bone])
	for index in range(_binding.morph_nodes.size()):
		(_binding.morph_nodes[index] as MeshInstance3D).set_blend_shape_value(_binding.morph_slots[index], state.morphs[index])

func _geometry(appearance: Dictionary, points: Array[Vector2]) -> Dictionary:
	var proxy := {"editor": _source.editor, "player_sprite": _source.sprite}
	var geometry: Variant = _source.geometry
	var result := {"body": geometry.body_shapes(proxy), "weapon": geometry.weapon_shapes(proxy, _source.editor._resolve_weapon_attack_animation()),
		"shield": geometry.shield_shapes(proxy), "armor": [], "protection": [], "head_fit": {}}
	for slot: StringName in [&"helmet", &"armor", &"outfit", &"boots"]:
		var id := StringName(str(appearance.parts[str(slot)]))
		if id == &"none":
			continue
		var component: Dictionary = _source.editor._component_definition(slot, id)
		for node: Node in _source.editor._find_component_nodes(component.get("prefixes", [])):
			var mesh := node as MeshInstance3D
			if mesh != null and mesh.is_visible_in_tree() and mesh.mesh != null:
				result.armor.append([str(_source.editor.model_root.get_path_to(mesh)), geometry.posed_points(proxy, mesh, _source.skeleton)])
	for point: Vector2 in points:
		result.protection.append(geometry.armor_at(proxy, point, "slash"))
	result.head_fit = geometry._head_bounds.duplicate(true)
	return result

func _compare(expected: Variant, actual: Variant, path: String, differences: Array[Dictionary]) -> void:
	if differences.size() >= 24:
		return
	# C# marshalling can expose the same ordered numeric values through typed,
	# untyped or packed arrays. Compare each native element, not container metadata.
	var expected_array: bool = expected is Array or expected is PackedVector3Array or expected is PackedVector2Array or expected is PackedFloat32Array
	var actual_array: bool = actual is Array or actual is PackedVector3Array or actual is PackedVector2Array or actual is PackedFloat32Array
	if expected_array and actual_array:
		if expected.size() != actual.size():
			differences.append({"path": path, "reason": "size", "expected": expected.size(), "actual": actual.size()})
			return
		for index in range(expected.size()):
			_compare(expected[index], actual[index], path + "[%d]" % index, differences)
		return
	if typeof(expected) != typeof(actual):
		differences.append({"path": path, "reason": "type", "expected": type_string(typeof(expected)), "actual": type_string(typeof(actual))})
		return
	if expected is Dictionary:
		if expected.keys() != actual.keys():
			differences.append({"path": path, "reason": "ordered_keys"})
			return
		for key: Variant in expected:
			_compare(expected[key], actual[key], path + "." + str(key), differences)
	else:
		var before: PackedByteArray = PackedFloat64Array([expected]).to_byte_array() if typeof(expected) == TYPE_FLOAT else var_to_bytes(expected)
		var after: PackedByteArray = PackedFloat64Array([actual]).to_byte_array() if typeof(actual) == TYPE_FLOAT else var_to_bytes(actual)
		if before != after:
			differences.append({"path": path, "reason": "native_value_bits", "expected": str(expected), "actual": str(actual),
				"expected_hex": before.hex_encode(), "actual_hex": after.hex_encode(), "numeric_equal": expected == actual})

func _animations_digest(descriptor: Dictionary) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	for name: StringName in descriptor.clips:
		var animation: Animation = descriptor.clips[name].animation
		hashing.update(var_to_bytes([str(name), animation.length, animation.loop_mode, animation.get_track_count()]))
		for track in range(animation.get_track_count()):
			hashing.update(var_to_bytes([animation.track_get_type(track), str(animation.track_get_path(track)), animation.track_is_enabled(track), animation.track_get_interpolation_type(track), animation.track_get_interpolation_loop_wrap(track), animation.track_get_key_count(track)]))
			for key in range(animation.track_get_key_count(track)):
				hashing.update(var_to_bytes([animation.track_get_key_time(track, key), animation.track_get_key_value(track, key), animation.track_get_key_transition(track, key)]))
	return hashing.finish().hex_encode()

func _within_deadline() -> bool:
	return not _finished and (Time.get_ticks_usec() < _deadline_usec or _error("DEADLINE", "Synchronous native work exceeded the 53-second deadline"))

func _error(code: String, detail: Variant) -> bool:
	# Cleanup releases the original binding Dictionary; preserve the refusal
	# evidence rather than leaving the report aliased to that mutable owner.
	_report.errors.append({"code": code, "detail": detail.duplicate(true) if detail is Dictionary or detail is Array else detail})
	return false

func _finish(success: bool) -> void:
	if _finished:
		return
	_finished = true
	_report["success"] = success
	_report["source_sha256"] = FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_contact_source.gd")
	_report["compiled_sha256"] = FileAccess.get_sha256(COMPILED_PATH) if FileAccess.file_exists(COMPILED_PATH) else ""
	_report["test_sha256"] = FileAccess.get_sha256("res://scripts/tests/site_compiled_contact_pose_test.gd")
	_report["descriptor_sha256"] = FileAccess.get_sha256("res://scripts/tests/helpers/site_compiled_contact_descriptor.gd")
	if _source != null:
		_source.dispose()
		_source = null
	if is_instance_valid(_actor):
		_actor.queue_free()
	_actor = null
	_sampler = null
	_binding.clear()
	await process_frame
	var folder := "res://output/site_combat_compiled/pose/%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	var made := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var file := FileAccess.open(folder + "/measurements.json", FileAccess.WRITE) if made == OK else null
	if file == null:
		push_error("COMPILED CONTACT POSE report could not be written")
		quit(1)
		return
	file.store_string(JSON.stringify(_report, "\t", false, true))
	file.close()
	print("SITE COMPILED CONTACT POSE ", "PASS" if success else "FAIL", " ", JSON.stringify(_report), " report=", folder + "/measurements.json")
	quit(0 if success else 1)
