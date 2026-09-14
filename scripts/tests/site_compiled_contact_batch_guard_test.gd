extends SceneTree
## Pure-data admission/history guards only. No native character, gameplay or
## performance claim; root runs the already-built C# code via the verifier.

const Batch := preload("res://scripts/terrain_lab/compiled_contact_batch.cs")
var _batch: RefCounted
var _finished := false
var _deadline := 0
var _checks := 0
var _errors: Array[String] = []

func _initialize() -> void:
	_deadline = Time.get_ticks_msec() + 10000
	create_timer(10.0, true, false, true).timeout.connect(func() -> void:
		if not _finished:
			_errors.append("Internal 10-second batch guard deadline")
			_finish(false))
	call_deferred("_run")

func _run() -> void:
	_batch = Batch.new() as RefCounted
	if not _check(_batch != null, "C# batch did not instantiate"):
		_finish(false)
		return
	var pose := _pose_descriptor()
	var view := _view_descriptor()
	var unknown := view.duplicate(true)
	unknown.used_morph_names = PackedStringArray(["TestMesh:MissingMorph"])
	var rejected: Dictionary = _batch.call("Compile", pose, [unknown])
	if not _check(not bool(rejected.get("ok", true)) and rejected.get("code") == "batch_descriptor_rejected" and "unknown_view_morph" in str(rejected.get("error", "")), "Unknown used_morph_names was not explicitly rejected: %s" % rejected):
		_finish(false)
		return
	var compiled: Dictionary = _batch.call("Compile", pose, [view])
	if not _check(bool(compiled.get("ok", false)), "Valid minimal descriptors rejected: %s" % compiled):
		_finish(false)
		return
	var valid := {"view": 0, "clip": &"idle", "time": 0.25, "include_weapon": true,
		"armor_queries": [{"point": Vector2.ZERO, "kind": "slash"}]}
	var baseline: Dictionary = _batch.call("SampleBatch", [valid])
	if not _check(bool(baseline.get("ok", false)) and baseline.get("results", []).size() == 1, "Baseline request failed: %s" % baseline):
		_finish(false)
		return
	var baseline_bits := var_to_bytes(baseline.results)
	var before_failure := valid.duplicate(true)
	before_failure.time = 0.5
	var nonzero := valid.duplicate(true)
	nonzero.time = 0.75
	nonzero.morph_indices = PackedInt32Array([0])
	nonzero.morph_values = PackedFloat32Array([0.5])
	var failed: Dictionary = _batch.call("SampleBatch", [before_failure, nonzero])
	if not _check(not bool(failed.get("ok", true)) and failed.get("code") == "unsupported_geometry_morph" and int(failed.get("failed_index", -1)) == 1 and bool(failed.get("requires_reset", false)) and not failed.has("results"), "Partial batch failure leaked results or missed used-morph guard: %s" % failed):
		_finish(false)
		return
	var locked: Dictionary = _batch.call("SampleBatch", [valid])
	if not _check(not bool(locked.get("ok", true)) and locked.get("code") == "batch_poisoned" and not locked.has("results"), "Failed history was allowed to continue: %s" % locked):
		_finish(false)
		return
	var reset: Dictionary = _batch.call("Reset")
	if not _check(bool(reset.get("ok", false)), "Reset failed: %s" % reset):
		_finish(false)
		return
	var replay: Dictionary = _batch.call("SampleBatch", [valid])
	if not _check(bool(replay.get("ok", false)) and replay.has("results") and var_to_bytes(replay.results) == baseline_bits, "Reset did not restore exact baseline geometry/history: %s" % replay):
		_finish(false)
		return
	_finish(true)

func _pose_descriptor() -> Dictionary:
	var animation := Animation.new()
	animation.length = 1.0
	var position_track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(position_track, NodePath("Skeleton:Root"))
	animation.position_track_insert_key(position_track, 0.0, Vector3.ZERO)
	animation.position_track_insert_key(position_track, 1.0, Vector3(2, 0, 0))
	# GuardMorph has no track/reset channel: manual writes must survive same-clip
	# seeks. DecorativeMorph is animated but excluded from this fixed view union.
	var unused_track := animation.add_track(Animation.TYPE_BLEND_SHAPE)
	animation.track_set_path(unused_track, NodePath("TestMesh:blend_shapes/DecorativeMorph"))
	animation.blend_shape_track_insert_key(unused_track, 0.0, 0.2)
	animation.blend_shape_track_insert_key(unused_track, 1.0, 0.7)
	return {"schema_version": 1, "bone_names": PackedStringArray(["Root"]),
		"parents": PackedInt32Array([-1]), "rest": [Transform3D.IDENTITY],
		"initial_positions": PackedVector3Array([Vector3.ZERO]), "initial_rotations": [Quaternion.IDENTITY],
		"initial_scales": PackedVector3Array([Vector3.ONE]), "initial_clip": &"idle",
		"morph_names": PackedStringArray(["TestMesh:GuardMorph", "TestMesh:DecorativeMorph"]),
		"initial_morphs": PackedFloat32Array([0.0, 0.0]),
		"mixer_positions": PackedVector3Array([Vector3.ZERO]), "mixer_rotations": [Quaternion.IDENTITY],
		"mixer_scales": PackedVector3Array([Vector3.ONE]), "mixer_morphs": PackedFloat32Array([0.0, 0.0]),
		"mixer_morph_channels": PackedInt32Array([1]), "mixer_channels": PackedInt32Array([1]),
		"reset_morphs": PackedInt32Array(), "motion_scale": 1.0, "mixer_deterministic": false,
		"clips": {&"idle": {"animation": animation, "track_bones": PackedInt32Array([0, -1]),
			"track_morphs": PackedInt32Array([-1, 1]), "ignore_tracks": PackedInt32Array()}}}

func _view_descriptor() -> Dictionary:
	var ring := PackedVector2Array()
	for index in range(12):
		ring.append(Vector2.from_angle(TAU * float(index) / 12.0))
	var part := {"nonzero_morph": false, "world": Transform3D.IDENTITY,
		"bind_bones": PackedInt32Array([0]), "bind_poses": [Transform3D.IDENTITY],
		"surfaces": [{"vertices": PackedVector3Array([Vector3.ZERO, Vector3(0.5, 0, 0), Vector3(0, 0.5, 0)]),
			"bones": PackedInt32Array([0, 0, 0]), "weights": PackedFloat32Array([1, 1, 1]),
			"indices": PackedInt32Array([0, 1, 2])}]}
	return {"schema": 1, "aim_weight": 0.0, "skeleton_world": Transform3D.IDENTITY,
		"camera_world": Transform3D.IDENTITY, "mesh_projection": Transform3D.IDENTITY,
		"sprite": Transform2D.IDENTITY, "projection": Projection(), "viewport": Vector2(100, 100),
		"camera_right": Vector3.RIGHT, "capsule_ring": ring, "limbs": [[0, 0, 0.16]],
		"head": -1, "shoulder": 0, "knee": -1, "foot": -1, "has_head": false,
		"head_bounds": AABB(), "weapon_clip": "attack_sword", "parrying": false,
		"weapons": [part], "shields": [], "parry": [], "armor": [],
		"used_morph_names": PackedStringArray(["TestMesh:GuardMorph"])}

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
	if _batch != null:
		_batch.call("Clear")
		_batch = null
	var report := {"checks": _checks, "errors": _errors, "success": success,
		"scope": "synthetic pure-data batch admission, poisoning and exact reset only; no native-character or performance acceptance"}
	print("SITE_COMPILED_CONTACT_BATCH_GUARD_", "PASS " if success else "FAIL ", JSON.stringify(report))
	if not success:
		push_error("Compiled batch guard test failed: %s" % _errors)
	quit(0 if success else 1)
