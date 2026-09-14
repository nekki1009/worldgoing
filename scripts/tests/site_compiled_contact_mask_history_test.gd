extends SceneTree
## Fixed ALL-view morph closure versus the unmasked pose owner. Synthetic data
## only: this is not a native AnimationPlayer, character or performance gate.

const Pose := preload("res://scripts/terrain_lab/compiled_contact_pose.cs")
const Batch := preload("res://scripts/terrain_lab/compiled_contact_batch.cs")
const Shapes := preload("res://scripts/terrain_lab/compiled_contact_shapes.cs")
var _pose: RefCounted
var _masked: RefCounted
var _batch: RefCounted
var _shapes: Array[RefCounted] = []
var _descriptor: Dictionary
var _digest := ""
var _finished := false
var _deadline := 0
var _checks := 0
var _errors: Array[String] = []
var _cases: Array[Dictionary] = []

func _initialize() -> void:
	_deadline = Time.get_ticks_msec() + 10000
	create_timer(10.0, true, false, true).timeout.connect(func() -> void:
		if not _finished:
			_errors.append("Internal 10-second mask history deadline")
			_finish(false))
	call_deferred("_run")

func _run() -> void:
	_pose = Pose.new() as RefCounted
	_masked = Pose.new() as RefCounted
	_batch = Batch.new() as RefCounted
	if not _check(_pose != null and _masked != null and _batch != null, "C# helpers did not instantiate"):
		_finish(false)
		return
	_descriptor = _pose_descriptor()
	_digest = _animations_digest()
	var view_a := _view_descriptor()
	var view_b := view_a.duplicate(true)
	view_b.used_morph_names = PackedStringArray()
	view_b.weapons = []
	var views := [view_a, view_b]
	var full: Dictionary = _pose.call("Compile", _descriptor)
	var batch: Dictionary = _batch.call("Compile", _descriptor, views)
	var masked_descriptor := _descriptor.duplicate()
	masked_descriptor.required_morph_indices = PackedInt32Array([0, 2])
	var masked: Dictionary = _masked.call("Compile", masked_descriptor)
	if not _check(bool(full.get("ok", false)) and bool(batch.get("ok", false)) and bool(masked.get("ok", false)), "Compile failed: %s / %s / %s" % [full, batch, masked]):
		_finish(false)
		return
	if not _check(not full.morph_masked and full.morph_union_count == 3 and masked.morph_masked and masked.morph_union_count == 2 and batch.morph_union_count == 2 and batch.tracks_raw == 10 and batch.tracks_original == 7 and batch.tracks_retained == 4 and not _descriptor.has("required_morph_indices"), "Fixed union, disabled/retained counts or caller descriptor changed: %s" % batch):
		_finish(false)
		return
	for view: Dictionary in views:
		var shapes := Shapes.new() as RefCounted
		_shapes.append(shapes)
		var compiled: Dictionary = shapes.call("Compile", view)
		if not _check(bool(compiled.get("ok", false)), "Shape reference rejected: %s" % compiled):
			_finish(false)
			return
	# Storage outside the declared mask is intentionally not a valid full pose.
	# The hidden animated value must differ; only union entries are compared.
	var full_probe: Dictionary = _pose.call("Sample", &"idle", 0.5)
	var masked_probe: Dictionary = _masked.call("Sample", &"idle", 0.5)
	if not _check(bool(full_probe.get("ok", false)) and bool(masked_probe.get("ok", false)), "Hidden-value probe failed"):
		_finish(false)
		return
	if not _check(_same(_used(full_probe), _used(masked_probe)) and not _same(full_probe.morphs[1], masked_probe.morphs[1]) and masked_probe.morphs[1] == 0.125 and _same(masked.required_morph_indices, PackedInt32Array([0, 2])), "Hidden storage was treated as a valid full-pose result, or used values diverged"):
		_finish(false)
		return
	var sequences := [
		{"name": "absent_manual_return_reject", "requests": [_request(0), _request(1, &"idle", 0.25, 0, 0.5), _request(0)], "used": [Vector2.ZERO, Vector2(0.5, 0), Vector2(0.5, 0)], "reject": 2},
		{"name": "absent_clip_reset_return_pass", "requests": [_request(0), _request(1, &"idle", 0.25, 0, 0.5), _request(1, &"reset", 0.25), _request(0, &"reset", 0.5)], "used": [Vector2.ZERO, Vector2(0.5, 0), Vector2.ZERO, Vector2.ZERO], "reject": -1},
		{"name": "absent_clear_return_pass", "requests": [_request(1, &"idle", 0.25, 0, 0.5), _request(1, &"idle", 0.5, 0, 0.0), _request(0)], "used": [Vector2(0.5, 0), Vector2.ZERO, Vector2.ZERO], "reject": -1},
		{"name": "update_before_clip_reset_pass", "requests": [_request(1, &"reset", 0.25, 0, 0.5), _request(0, &"reset", 0.5)], "used": [Vector2.ZERO, Vector2.ZERO], "reject": -1},
		{"name": "disabled_track_manual_return_reject", "requests": [_request(1, &"idle", 0.25, 2, 0.25), _request(1, &"reset", 0.5), _request(0, &"reset", 0.75)], "used": [Vector2(0, 0.25), Vector2(0, 0.25), Vector2(0, 0.25)], "reject": 2},
		{"name": "absent_animated_return_reject", "requests": [_request(1, &"animated", 0.5), _request(0, &"animated", 0.5)], "used": [Vector2(0.5, 0), Vector2(0.5, 0)], "reject": 1},
		{"name": "absent_animation_clears_return_pass", "requests": [_request(1, &"animated", 0.5), _request(1, &"animated", 0.0), _request(0, &"animated", 0.0)], "used": [Vector2(0.5, 0), Vector2.ZERO, Vector2.ZERO], "reject": -1},
	]
	for sequence: Dictionary in sequences:
		if not _sequence(sequence):
			_finish(false)
			return
	_finish(true)

func _sequence(sequence: Dictionary) -> bool:
	for helper: RefCounted in [_pose, _masked, _batch]:
		var reset: Dictionary = helper.call("Reset")
		if not _check(bool(reset.get("ok", false)), "%s: reset rejected" % sequence.name):
			return false
	var expected: Array = []
	var expected_rejection := -1
	for index in range(sequence.requests.size()):
		var request: Dictionary = sequence.requests[index]
		if request.has("morph_indices"):
			for helper: RefCounted in [_pose, _masked]:
				var update: Dictionary = helper.call("ApplyMorphUpdates", request.morph_indices, request.morph_values)
				if not _check(bool(update.get("ok", false)), "%s: pose update rejected" % sequence.name):
					return false
		var frame: Dictionary = _pose.call("Sample", request.clip, request.time)
		var masked_frame: Dictionary = _masked.call("Sample", request.clip, request.time)
		if not _check(bool(frame.get("ok", false)) and bool(masked_frame.get("ok", false)), "%s: pose sample rejected" % sequence.name):
			return false
		var used := _used(frame)
		if not _check(_same(used, sequence.used[index]) and _same(used, _used(masked_frame)), "%s: expected/full/masked used morphs differ at %d: %s" % [sequence.name, index, used]):
			return false
		if request.view == 0 and (absf(used.x) > 0.0001 or absf(used.y) > 0.0001):
			expected_rejection = index
			break
		var geometry: Dictionary = _shapes[request.view].call("Evaluate", frame.global, true)
		if not _check(bool(geometry.get("ok", false)), "%s: full-pose geometry rejected" % sequence.name):
			return false
		geometry.effective_time = frame.effective_time
		expected.append(geometry)
	if not _check(expected_rejection == int(sequence.reject), "%s: full-pose admission differs from explicit expectation" % sequence.name):
		return false
	var actual: Dictionary = _batch.call("SampleBatch", sequence.requests)
	if expected_rejection >= 0:
		if not _check(not bool(actual.get("ok", true)) and actual.get("code") == "unsupported_geometry_morph" and int(actual.get("failed_index", -1)) == expected_rejection and bool(actual.get("requires_reset", false)) and not actual.has("results"), "%s: absent-view history guard did not reject atomically: %s" % [sequence.name, actual]):
			return false
		var poisoned: Dictionary = _batch.call("SampleBatch", [_request(1)])
		if not _check(poisoned.get("code") == "batch_poisoned" and not bool(poisoned.get("ok", true)) and not poisoned.has("results"), "%s: rejected history remained usable" % sequence.name):
			return false
	else:
		if not _check(bool(actual.get("ok", false)) and actual.has("results") and _same(expected, actual.results), "%s: admitted geometry/effective-time bits differ: %s" % [sequence.name, actual.get("code", "value_mismatch")]):
			return false
		for result: Dictionary in actual.results:
			if not _check(not result.has("morphs") and not result.has("global") and not result.has("local"), "%s: batch exposed masked hidden state as a full pose" % sequence.name):
				return false
	_cases.append({"name": sequence.name, "requests": sequence.requests.size(), "rejected_index": expected_rejection, "geometry_exact": expected_rejection < 0, "success": true})
	return _check(_animations_digest() == _digest, "%s: original animation digest changed" % sequence.name)

func _request(view: int, clip: StringName = &"idle", time: float = 0.5, morph: int = -1, value: float = 0.0) -> Dictionary:
	var result := {"view": view, "clip": clip, "time": time, "include_weapon": true}
	if morph >= 0:
		result.morph_indices = PackedInt32Array([morph])
		result.morph_values = PackedFloat32Array([value])
	return result

func _used(frame: Dictionary) -> Vector2:
	return Vector2(frame.morphs[0], frame.morphs[2])

func _pose_descriptor() -> Dictionary:
	var animation := Animation.new()
	animation.length = 1.0
	var position := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(position, NodePath("Skeleton:Root"))
	animation.position_track_insert_key(position, 0.0, Vector3.ZERO)
	animation.position_track_insert_key(position, 1.0, Vector3(2, 0, 0))
	var hidden := animation.add_track(Animation.TYPE_BLEND_SHAPE)
	animation.track_set_path(hidden, NodePath("TestMesh:blend_shapes/Hidden"))
	animation.blend_shape_track_insert_key(hidden, 0.0, 0.2)
	animation.blend_shape_track_insert_key(hidden, 1.0, 0.7)
	var disabled := animation.add_track(Animation.TYPE_BLEND_SHAPE)
	animation.track_set_path(disabled, NodePath("TestMesh:blend_shapes/Disabled"))
	animation.blend_shape_track_insert_key(disabled, 0.0, 0.9)
	animation.track_set_enabled(disabled, false)
	var animated := animation.duplicate(true) as Animation
	var used := animated.add_track(Animation.TYPE_BLEND_SHAPE)
	animated.track_set_path(used, NodePath("TestMesh:blend_shapes/Guard"))
	animated.blend_shape_track_insert_key(used, 0.0, 0.0)
	animated.blend_shape_track_insert_key(used, 0.5, 0.5)
	animated.blend_shape_track_insert_key(used, 1.0, 0.0)
	var clip := {"animation": animation, "track_bones": PackedInt32Array([0, -1, -1]), "track_morphs": PackedInt32Array([-1, 1, 2]), "ignore_tracks": PackedInt32Array()}
	var reset_clip := clip.duplicate(true)
	reset_clip.animation = animation.duplicate(true)
	return {"schema_version": 1, "bone_names": PackedStringArray(["Root"]),
		"parents": PackedInt32Array([-1]), "rest": [Transform3D.IDENTITY],
		"initial_positions": PackedVector3Array([Vector3.ZERO]), "initial_rotations": [Quaternion.IDENTITY],
		"initial_scales": PackedVector3Array([Vector3.ONE]), "initial_clip": &"idle",
		"morph_names": PackedStringArray(["TestMesh:Guard", "TestMesh:Hidden", "TestMesh:Disabled"]),
		"initial_morphs": PackedFloat32Array([0.0, 0.125, 0.0]),
		"mixer_positions": PackedVector3Array([Vector3.ZERO]), "mixer_rotations": [Quaternion.IDENTITY],
		"mixer_scales": PackedVector3Array([Vector3.ONE]), "mixer_morphs": PackedFloat32Array([0.0, 0.0, 0.0]),
		"mixer_morph_channels": PackedInt32Array([0, 1]), "mixer_channels": PackedInt32Array([1]),
		"reset_morphs": PackedInt32Array([0]), "motion_scale": 1.0, "mixer_deterministic": false,
		"clips": {&"idle": clip, &"reset": reset_clip, &"animated": {"animation": animated,
			"track_bones": PackedInt32Array([0, -1, -1, -1]), "track_morphs": PackedInt32Array([-1, 1, 2, 0]), "ignore_tracks": PackedInt32Array()}}}

func _view_descriptor() -> Dictionary:
	var ring := PackedVector2Array()
	for index in range(12):
		ring.append(Vector2.from_angle(TAU * float(index) / 12.0))
	var part := {"nonzero_morph": false, "world": Transform3D.IDENTITY,
		"bind_bones": PackedInt32Array([0]), "bind_poses": [Transform3D.IDENTITY],
		"surfaces": [{"vertices": PackedVector3Array([Vector3.ZERO, Vector3(0.5, 0, 0), Vector3(0, 0.5, 0)]),
			"bones": PackedInt32Array([0, 0, 0]), "weights": PackedFloat32Array([1, 1, 1]), "indices": PackedInt32Array([0, 1, 2])}]}
	return {"schema": 1, "aim_weight": 0.0, "skeleton_world": Transform3D.IDENTITY,
		"camera_world": Transform3D.IDENTITY, "mesh_projection": Transform3D.IDENTITY,
		"sprite": Transform2D.IDENTITY, "projection": Projection(), "viewport": Vector2(100, 100),
		"camera_right": Vector3.RIGHT, "capsule_ring": ring, "limbs": [[0, 0, 0.16]],
		"head": -1, "shoulder": 0, "knee": -1, "foot": -1, "has_head": false, "head_bounds": AABB(),
		"weapon_clip": "attack_sword", "parrying": false, "weapons": [part], "shields": [], "parry": [], "armor": [],
		"used_morph_names": PackedStringArray(["TestMesh:Guard", "TestMesh:Disabled"])}

func _same(expected: Variant, actual: Variant) -> bool:
	if typeof(expected) != typeof(actual):
		return false
	if expected is Array:
		if expected.size() != actual.size():
			return false
		for index in range(expected.size()):
			if not _same(expected[index], actual[index]):
				return false
		return true
	if expected is Dictionary:
		if expected.size() != actual.size():
			return false
		for key: Variant in expected:
			if not actual.has(key) or not _same(expected[key], actual[key]):
				return false
		return true
	if typeof(expected) == TYPE_FLOAT:
		return PackedFloat64Array([expected]).to_byte_array() == PackedFloat64Array([actual]).to_byte_array()
	return var_to_bytes(expected) == var_to_bytes(actual)

func _animations_digest() -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	for name: StringName in _descriptor.clips:
		var animation: Animation = _descriptor.clips[name].animation
		hashing.update(var_to_bytes([str(name), animation.length, animation.loop_mode, animation.get_track_count()]))
		for track in range(animation.get_track_count()):
			hashing.update(var_to_bytes([animation.track_get_type(track), str(animation.track_get_path(track)), animation.track_is_enabled(track), animation.track_get_interpolation_type(track), animation.track_get_interpolation_loop_wrap(track), animation.track_get_key_count(track)]))
			for key in range(animation.track_get_key_count(track)):
				hashing.update(var_to_bytes([animation.track_get_key_time(track, key), animation.track_get_key_value(track, key), animation.track_get_key_transition(track, key)]))
	return hashing.finish().hex_encode()

func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if Time.get_ticks_msec() >= _deadline:
		_errors.append("Synchronous work exceeded internal 10-second deadline")
		return false
	if not condition:
		_errors.append(message)
	return condition

func _finish(success: bool) -> void:
	if _finished:
		return
	_finished = true
	for helper: RefCounted in [_pose, _masked, _batch]:
		if helper != null:
			helper.call("Clear")
	_pose = null
	_masked = null
	_batch = null
	_shapes.clear()
	if not _descriptor.is_empty() and not _check(_animations_digest() == _digest, "Cleanup changed original animations"):
		success = false
	var report := {"checks": _checks, "cases": _cases, "errors": _errors, "success": success,
		"animation_digest": _digest, "view_count": 2, "morph_count": 3, "morph_union_count": 2,
		"scope": "synthetic fixed-union history, full-pose used morphs, exact admitted geometry; not hidden-pose equivalence, native rig or performance acceptance"}
	print("SITE_COMPILED_CONTACT_MASK_HISTORY_", "PASS " if success else "FAIL ", JSON.stringify(report))
	if not success:
		push_error("Compiled mask history test failed: %s" % _errors)
	quit(0 if success else 1)
