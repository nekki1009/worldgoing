extends SceneTree
## One original Source, no Actor/copy rig. GPU --group=0 or --group=1.
## Each group: internal 23 seconds / unchanged canonical visual helper 25.
## Samples supplement the continuous native proof; they are not that proof.

const Source = preload("res://scripts/terrain_lab/terrain_army_contact_source.gd")
const Bounds = preload("res://scripts/terrain_lab/terrain_army_source_bounds.gd")
const Geometry = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")
const MANIFEST := "res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.json"
var started := 0
var cases := 0
var vertices_checked := 0
var maximum_sample_radius := 0.0
var fallback_reasons: Array[String] = []
var group := 0

func _initialize() -> void:
	started = Time.get_ticks_usec()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--group="):
			group = argument.trim_prefix("--group=").to_int()
	_run.call_deferred()

func _run() -> void:
	create_timer(23.0).timeout.connect(func() -> void: push_error("Native source bounds deadline"); quit(1))
	assert(DisplayServer.get_name() != "headless" and group in [0, 1])
	var fingerprint := _hashes()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var source := Source.new()
	assert(source.initialize(root, manifest.appearance))
	var player: AnimationPlayer = source.editor.animation_player
	var original_state := [player.assigned_animation, player.current_animation_position, player.is_playing(), source._key.duplicate(true)]
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var before_samples := int(source.query_profile.sample_calls)
	var bound := Bounds.build(source)
	if float(bound.radius) >= 256.0:
		push_error("Native bound unsupported: " + str(bound))
		source.dispose()
		quit(1)
		return
	assert(float(bound.radius) < 256.0 and float(bound.radius) > float(bound.continuous_pixels), str(bound))
	assert(float(bound.radius) == 128.0 and bound.position_keys == 1791, "Current actual native fixture, not the production constant")
	assert(bound.clips == Bounds.NONATTACK + Bounds.NATIVE_ATTACKS and bound.float_padding_pixels == 1.0)
	assert(bound.reason == "NATIVE_CONTINUOUS_UNAIMED_BODY_SHIELD")
	assert(bound.maximum_position_extrapolation_metres > 0.0 and bound.maximum_position_extrapolation_metres < 0.001)
	assert([player.assigned_animation, player.current_animation_position, player.is_playing(), source._key] == original_state)
	assert(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) == nodes and int(source.query_profile.sample_calls) == before_samples)
	assert(bound.clips.has(&"walk_slash") and bound.clips.has(&"attack_spear") and not bound.clips.has(&"ride_idle"))
	for clip: StringName in Bounds.CURVES:
		if str(clip).begins_with("guard"):
			assert(not bound.clips.has(clip), "Every guard/parry transition stays outside the body/all-shield contract")
	assert(not bound.clips.has(&"attack_unknown") and not bound.clips.has(&"attack_jump_heavy"))
	_check_time()
	if group == 0:
		_geometry_cases(source, manifest.appearance, bound)
		_fast_guards(source)
	else:
		_mutation_guards(source, bound)
	assert(_hashes() == fingerprint, "Source/test/geometry fixed during acceptance")
	var report := {"group": group, "bound": bound, "cases": cases, "vertices_checked": vertices_checked,
		"maximum_sample_radius_with_offset": maximum_sample_radius, "fallback_reasons": fallback_reasons,
		"elapsed_usec": Time.get_ticks_usec() - started, "source_hashes": fingerprint,
		"scope": "Actual original native continuous bound build, read-only ownership, selected real body/shield poses and explicit runtime contract fallbacks. Samples do not prove all times; no FPS or visual appearance claim."}
	var directory := "res://output/site_combat_performance_20260913/native_bounds/runtime_group%d/%d_%d" % [group, int(Time.get_unix_time_from_system()), started]
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK)
	var path := directory + "/measurements.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	_check_time()
	source.dispose()
	print("SITE_ARMY_SOURCE_BOUNDS_PASS ", JSON.stringify(report))
	quit(0)

func _geometry_cases(source: Variant, baseline: Dictionary, bound: Dictionary) -> void:
	var unequipped := baseline.duplicate(true)
	unequipped.parts.shield = "none"
	unequipped.parts.weapon = "none"
	var requests: Array = [[&"idle", 0.137], [&"walk", 0.317], [&"run", 0.219], [&"down", 0.713],
		[&"unconscious", 0.317], [&"get_up", 0.437], [&"hit", 0.137], [&"rescue", 1.137], [&"reload_bow", 0.173]]
	# The original eight native attacks, all four directions, real body/shield
	# vertices and both original world/31.5-pixel offset paths below. No IK is
	# requested here; the actual Army integration test covers its exclusion.
	for clip: StringName in Bounds.NATIVE_ATTACKS:
		var animation: Animation = source.editor.animation_player.get_animation(clip)
		requests.append([clip, animation.length * 0.4])
	var grounds: Array[Vector2] = [Vector2.ZERO, Vector2(6400.375, 6399.8125), Vector2(-8192.0, 8192.0)]
	for direction: Vector2i in TerrainData.DIRECTIONS:
		for request: Array in requests:
			var recipe: Dictionary = unequipped if cases % 2 == 1 else baseline
			source.begin_contact_step()
			var sample: Dictionary = source.sample(request[0], request[1], direction, Vector2.ZERO, 0.0, recipe, false)
			assert(not sample.is_empty() and sample.parry.is_empty() and bound.clips.has(request[0]))
			for key: String in ["body", "shield"]:
				for polygon: PackedVector2Array in sample[key]:
					for vertex: Vector2 in polygon:
						maximum_sample_radius = maxf(maximum_sample_radius, vertex.length() + 31.5)
						assert(vertex.length() + 31.5 < float(bound.radius))
						vertices_checked += 1
			for ground: Vector2 in grounds:
				for offset: Vector2 in [Vector2.ZERO, Vector2(direction) * 31.5]:
					var shifted: Rect2 = sample.hurt_bounds
					shifted.position += ground + offset # Original Army's local-rect shift.
					for corner: Vector2 in [shifted.position, shifted.position + shifted.size]:
						assert(absf(corner.x - ground.x) < float(bound.radius) and absf(corner.y - ground.y) < float(bound.radius))
					# Positive interior and far edge queries share the original exact
					# geometry; a tighter gate can only remove the disjoint cases.
					var bodies: Array = Geometry.shifted(sample.body, ground + offset)
					var shields: Array = Geometry.shifted(sample.shield, ground + offset)
					var touching: Array[PackedVector2Array] = [bodies[0]]
					var original := Geometry.person_contact(touching, touching, bodies, shields)
					assert(not original.is_empty())
					var query_bounds := Geometry.polygon_bounds(touching[0])
					assert(query_bounds.grow(float(bound.radius)).has_point(ground))
					for delta: float in [-0.001, 0.0, 0.001]:
						var far := Rect2(ground + Vector2(float(bound.radius) + delta, 0.0), Vector2(0.0001, 0.0001))
						assert(not far.intersects(shifted, true), "Outward padding covers half-open has_point boundary and real world additions")
			cases += 1
			_check_time()
	assert(vertices_checked > 1000)
	# Native loop-mode changes do not change key curves or permanently revoke
	# this Source's numeric contract. Owner may clear/rebuild its cached value.
	var idle: Animation = source.editor.animation_player.get_animation(&"idle")
	var mode := idle.loop_mode
	idle.loop_mode = Animation.LOOP_NONE if mode != Animation.LOOP_NONE else Animation.LOOP_LINEAR
	var after_loop := Bounds.build(source)
	assert(after_loop.radius == bound.radius and after_loop.position_keys == bound.position_keys)
	idle.loop_mode = mode
	_check_time()

func _fast_guards(source: Variant) -> void:
	var skeleton: Skeleton3D = source.skeleton
	var simulators := skeleton.find_children("*", "PhysicalBoneSimulator3D", true, false)
	assert(simulators.size() == 1, "Actual native internal compatibility simulator, not an added fixture Node")
	var simulator := simulators[0] as PhysicalBoneSimulator3D
	assert(not simulator.is_simulating_physics() and simulator.get_child_count(true) == 0)
	simulator.physical_bones_start_simulation()
	_expect_fallback(source, "SKELETON_MODIFIER_OR_MOTION_SCALE")
	simulator.physical_bones_stop_simulation()
	skeleton.set_motion_scale(2.0)
	_expect_fallback(source, "SKELETON_MODIFIER_OR_MOTION_SCALE")
	skeleton.set_motion_scale(1.0)
	var camera: Camera3D = source.editor.camera
	var projection := camera.projection
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_expect_fallback(source, "ORTHOGRAPHIC_VIEWPORT_CONTRACT")
	camera.projection = projection
	camera.h_offset = 0.125
	_expect_fallback(source, "FOOT_CAMERA_CONTRACT")
	camera.h_offset = 0.0
	var pivot: Node3D = source.editor.preview_pivot
	pivot.scale = Vector3.ONE * 1.01
	_expect_fallback(source, "MODEL_ROOT_TRANSFORM")
	pivot.scale = Vector3.ONE
	var player: AnimationPlayer = source.editor.animation_player
	player.set_default_blend_time(0.25)
	_expect_fallback(source, "NATIVE_SINGLE_CLIP_CONTRACT")
	player.set_default_blend_time(0.0)
	var body: Variant = source._baseline.body
	source._baseline.body = 1
	_expect_fallback(source, "NOT_ORIGINAL_ORDINARY_FOOT_MODEL")
	source._baseline.body = body

func _mutation_guards(source: Variant, original_bound: Dictionary) -> void:
	var player: AnimationPlayer = source.editor.animation_player
	var idle := player.get_animation(&"idle")
	var track := -1
	for index in range(idle.get_track_count()):
		if idle.track_get_type(index) == Animation.TYPE_POSITION_3D:
			track = index
			break
	assert(track >= 0)
	idle.track_set_key_transition(track, 0, 0.5)
	_expect_fallback(source, "NATIVE_KEY_TIME_OR_TRANSITION")
	idle.track_set_key_transition(track, 0, 1.0)
	var interpolation := idle.track_get_interpolation_type(track)
	idle.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
	_expect_fallback(source, "UNPROVEN_NATIVE_TRACK")
	idle.track_set_interpolation_type(track, interpolation)
	var second_time := idle.track_get_key_time(track, 1)
	idle.track_set_key_time(track, 1, 0.0001)
	_expect_fallback(source, "NATIVE_POSITION_TIME_ENVELOPE")
	idle.track_set_key_time(track, 1, second_time)
	idle.track_set_key_time(track, 0, 0.001)
	_expect_fallback(source, "NATIVE_POSITION_TIME_ENVELOPE")
	idle.track_set_key_time(track, 0, 0.0)
	# A genuine native translation change is recomputed, not admitted from
	# the old raw hash, a fixed 115, or a finite collection of pose samples.
	var original: Vector3 = idle.track_get_key_value(track, 0)
	idle.track_set_key_value(track, 0, Vector3(0.0, 1.09, 0.0))
	var changed := Bounds.build(source)
	assert(changed.radius < 256.0 and changed.continuous_pixels > original_bound.continuous_pixels)
	idle.track_set_key_value(track, 0, Vector3(0.0, 2.0, 0.0))
	_expect_fallback(source, "CHAIN_NUMERIC_ENVELOPE")
	idle.track_set_key_value(track, 0, original)
	var face := source.editor.model_root.find_child("Face_Standard_01", true, false) as MeshInstance3D
	assert(face != null)
	var skin := face.skin
	face.skin = null
	_expect_fallback(source, "ORIGINAL_COLLIDER_MESH_OR_SKIN")
	face.skin = skin
	var restored := Bounds.build(source)
	assert(restored.radius == original_bound.radius and restored.continuous_pixels == original_bound.continuous_pixels)
	# Same face ID can retain an original Geometry head fit after a caller's
	# explicit asset clear. Never silently reuse a smaller new bound over it.
	source.geometry._head_bounds[face.get_instance_id()] = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	_expect_fallback(source, "RETAINED_HEAD_FIT_ENVELOPE")
	source.geometry._head_bounds.erase(face.get_instance_id())
	cases += 2
	_key_edge_cases(source, original_bound)
	_check_time()

func _key_edge_cases(source: Variant, bound: Dictionary) -> void:
	# Exercise the original native approximate-find branch just before a
	# real down key, not an invented interpolator or an altered animation.
	var down: Animation = source.editor.animation_player.get_animation(&"down")
	var track := -1
	for index in range(down.get_track_count()):
		if down.track_get_type(index) == Animation.TYPE_POSITION_3D:
			track = index
			break
	assert(track >= 0)
	var selected := -1
	var largest_slope := 0.0
	for index in range(1, down.track_get_key_count(track) - 1):
		var a: Vector3 = down.track_get_key_value(track, index)
		var b: Vector3 = down.track_get_key_value(track, index + 1)
		var delta := down.track_get_key_time(track, index + 1) - down.track_get_key_time(track, index)
		var slope := Bounds._distance(a, b) / delta
		if slope > largest_slope:
			largest_slope = slope
			selected = index
	assert(selected > 0 and largest_slope > 0.0)
	var key_time := down.track_get_key_time(track, selected)
	var epsilon := 1e-5 * maxf(1.0, key_time) * 0.25
	var at: Vector3 = down.track_get_key_value(track, selected)
	var following: Vector3 = down.track_get_key_value(track, selected + 1)
	var before: Vector3 = down.position_track_interpolate(track, key_time - epsilon)
	assert((before - at).dot(following - at) < 0.0, "Actual native approximate-find extrapolates before this key")
	assert(Bounds._distance(before, at) < float(bound.maximum_position_extrapolation_metres) + 1e-5)
	for time: float in [key_time - epsilon, key_time, key_time + epsilon]:
		source.begin_contact_step()
		var sample: Dictionary = source.sample(&"down", time, Vector2i.DOWN, Vector2.ZERO, 0.0, source._baseline, false)
		assert(not sample.is_empty())
		for key: String in ["body", "shield"]:
			for polygon: PackedVector2Array in sample[key]:
				for vertex: Vector2 in polygon:
					assert(vertex.length() + 31.5 < float(bound.radius))
					maximum_sample_radius = maxf(maximum_sample_radius, vertex.length() + 31.5)
					vertices_checked += 1
		cases += 1
		_check_time()

func _expect_fallback(source: Variant, reason: String) -> void:
	var value := Bounds.build(source)
	assert(value.radius == 256.0 and value.clips.is_empty() and value.reason == reason, str(value))
	fallback_reasons.append(reason)
	cases += 1
	_check_time()

func _check_time() -> void:
	assert(Time.get_ticks_usec() - started < 23000000, "Native bounds test internal deadline")

func _hashes() -> Dictionary:
	var result := {}
	for path: String in ["res://scripts/terrain_lab/terrain_army_source_bounds.gd", "res://scripts/tests/site_army_source_bounds_test.gd",
		"res://scripts/terrain_lab/terrain_army_contact_source.gd", "res://scripts/terrain_lab/terrain_weapon_collision.gd",
		HumanCharacter3DEditor.MALE_MODEL_PATH, MANIFEST]:
		result[path] = FileAccess.get_sha256(path)
	return result
