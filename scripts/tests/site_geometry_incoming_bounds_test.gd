extends SceneTree
## Static warm-face Source bounds replace the rejected per-pose Geometry box.
## One original private Source; no extra Actor/rig. Monotonic 23s/helper 25s.
## The original proof includes 31.5px Army offset; remove only that term,
## retain its full 1px numerical padding and ceil outward. No FPS claim.
## --centered --group=0/1: ten admitted native clips, each 0/mid/length and
## four directions. Without --centered the prior20-pose origin84 mode remains.

const Source = preload("res://scripts/terrain_lab/terrain_army_contact_source.gd")
const Geometry = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")
const MANIFEST := "res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.json"
var began := 0
var failed := false
var directory := ""
var centered := false
var group := 0
var report := {"poses": 0, "vertices": 0, "guards": 0, "geometry_usec": 0, "bounds_usec": 0, "warm_no_seek_queries": 0,
	"matrix_centered_queries": 0, "matrix_origin84_queries": 0}

func _initialize() -> void:
	began = Time.get_ticks_usec()
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--centered":
			centered = true
		if argument.begins_with("--group="):
			group = argument.trim_prefix("--group=").to_int()
	directory = "res://output/site_combat_performance_20260913/static_incoming_bounds/%s/group%d/%d_%d" % ["centered" if centered else "origin84", group, int(Time.get_unix_time_from_system()), began]
	_run.call_deferred()

func _process(_delta: float) -> bool:
	_check_time()
	return false

func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	if not failed:
		failed = true
		report.merge({"status": "FAIL", "message": message, "elapsed_usec": Time.get_ticks_usec() - began}, true)
		_write()
		push_error("SITE_STATIC_INCOMING_BOUNDS_FAIL " + JSON.stringify(report))
		quit(1)
	return false

func _check_time() -> bool:
	return not failed and _check(Time.get_ticks_usec() - began < 23000000, "23-second monotonic wall deadline")

func _exact(a: Variant, b: Variant) -> bool:
	# Numeric/cache snapshots have no NodePath native serialization padding.
	return a == b and var_to_bytes(a) == var_to_bytes(b)

func _pose_state(source: Variant) -> Array:
	var bones: Array = []
	for index in range(source.skeleton.get_bone_count()):
		bones.append(source.skeleton.get_bone_pose(index))
	return [source._key.duplicate(true), bones, source.editor.selected_animation,
		source.editor.animation_player.assigned_animation, source.editor.animation_player.current_animation_position,
		source.editor.capture_appearance(), source.geometry._head_bounds.duplicate(true),
		source._poses.duplicate(true), source._terminal_poses.duplicate(true)]

func _run() -> void:
	if not _check(DisplayServer.get_name() != "headless" and (not centered or group in [0, 1]), "GPU and centered group0/1 required"):
		return
	var fingerprint := _hashes()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var source := Source.new()
	if not _check(source.initialize(root, manifest.appearance), "Original Source initialization"):
		return
	var original := Geometry.new()
	var proxy := {"editor": source.editor, "player_sprite": source.sprite}
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	source.cheap_query_bounds_enabled = true
	source.centered_query_bounds_enabled = centered
	source.clear_samples()
	source.geometry._head_bounds.clear()
	source._key.clear() # Test-only cold state, before either original first-fit.
	var cold_before: Dictionary = source.query_profile.duplicate()
	var cold := source.query_bounds(&"idle", 0.137, Vector2i.DOWN)
	var cold_full := source.sample(&"idle", 0.137, Vector2i.DOWN, Vector2.ZERO, 0.0, {}, false)
	var cold_body := original.body_shapes(proxy)
	if not _check(_exact(cold, cold_full.hurt_bounds) and _exact(cold_body, cold_full.body)
		and _exact(source.geometry._head_bounds, original._head_bounds), "Cold query must preserve exact original A-first-fit/body/bound"):
		return
	if not _check(int(source.query_profile.query_bounds_fills) == int(cold_before.query_bounds_fills) + 1
		and int(source.query_profile.query_bounds_hits) == int(cold_before.query_bounds_hits)
		and int(source.query_profile.true_pose_evaluations) == int(cold_before.true_pose_evaluations) + 1, "Cold face must really execute the original full native sample"):
		return
	report.guards += 1
	var proof: Dictionary = source._nonattack_bound.duplicate(true)
	if not _check(float(proof.get("radius", 256.0)) < 256.0, "Actual native proof required, never substitute a fixed 84"):
		return
	var radius := ceilf(float(proof.continuous_pixels) - 31.5 + 1.0)
	if not _check(radius == 84.0, "Current fixture derived native local radius"):
		return
	var bare: Dictionary = manifest.appearance.duplicate(true)
	bare.parts.shield = "none"
	bare.parts.weapon = "none"
	bare.parts.armor = "none"
	var requests: Array = [[&"idle", 0.137], [&"walk", 0.317], [&"down", 1.137], [&"get_up", 0.437], [&"walk_slash", 1.173]]
	var tested_clips: Array = []
	if centered:
		if not _check(proof.clips.size() == 20 and proof.centered_clips.size() == 18
			and not proof.centered_clips.has(&"attack_crossbow") and not proof.centered_clips.has(&"reload_crossbow"),
			"Current native data has18 centered clips; two crossbow clips lack enabled Hips position and must retain84"):
			return
		requests.clear()
		for clip_index: int in range(group * 10, group * 10 + 10):
			var clip: StringName = proof.clips[clip_index]
			var animation: Animation = source.editor.animation_player.get_animation(clip)
			if not _check(animation != null, "Original native clip required, including two intentional84 fallbacks"):
				return
			tested_clips.append(clip)
			for sample_time: float in [0.0, animation.length * 0.5, animation.length]:
				requests.append([clip, sample_time])
	for direction: Vector2i in TerrainData.DIRECTIONS:
		for request: Array in requests:
			if not _check_time():
				return
			var recipe: Dictionary = bare if report.poses % 3 == 2 else manifest.appearance
			source.begin_contact_step()
			source.cheap_query_bounds_enabled = false
			var started := Time.get_ticks_usec()
			var actual: Dictionary = source.sample(request[0], request[1], direction, Vector2.ZERO, 0.0, recipe, false).duplicate(true)
			var body := original.body_shapes(proxy)
			var shield := original.shield_shapes(proxy)
			report.geometry_usec += Time.get_ticks_usec() - started
			if not _check(_exact(actual.body, body) and _exact(actual.shield, shield)
				and _exact(source.geometry._head_bounds, original._head_bounds), "Original full numeric geometry/head history oracle"):
				return
			# B changes the original current pose. Warm A must not restore B
			# or invent a full/partial _poses entry.
			source.sample(&"rescue", 1.1137, Vector2i.UP, Vector2.ZERO, 0.0, manifest.appearance, false)
			var pose_before := _pose_state(source)
			var profile_before: Dictionary = source.query_profile.duplicate()
			source.cheap_query_bounds_enabled = true
			started = Time.get_ticks_usec()
			var query := source.query_bounds(request[0], request[1], direction, Vector2.ZERO, 0.0, recipe)
			report.bounds_usec += Time.get_ticks_usec() - started
			var uses_centered: bool = centered and proof.centered_clips.has(request[0])
			if not _check(_exact(query, _proven_rect(proof, request[0]))
				and _exact(_pose_state(source), pose_before)
				and int(source.query_profile.true_pose_evaluations) == int(profile_before.true_pose_evaluations)
				and int(source.query_profile.query_bounds_hits) == int(profile_before.query_bounds_hits) + 1
				and int(source.query_profile.centered_query_bounds_hits) == int(profile_before.centered_query_bounds_hits) + int(uses_centered), "Warm A must return proven bounds without seek, appearance or cache mutation"):
				return
			var full_again := source.sample(request[0], request[1], direction, Vector2.ZERO, 0.0, recipe, false)
			if not _check(_exact(full_again, actual), "Static query cannot change the original full A result"):
				return
			for ground: Vector2 in [Vector2.ZERO, Vector2(6400.375, 6399.8125), Vector2(-16300.0, 16300.0)]:
				for offset: Vector2 in [Vector2.ZERO, Vector2(direction) * 31.5]:
					var shifted: Rect2 = query
					shifted.position += ground + offset
					for shapes: Array in [Geometry.shifted(body, ground + offset), Geometry.shifted(shield, ground + offset)]:
						for polygon: PackedVector2Array in shapes:
							for vertex: Vector2 in polygon:
								if not _check(shifted.has_point(vertex), "Static bound excludes an original projected vertex after real map/offset additions"):
									return
								report.vertices += 1
			if report.poses % 5 == 0:
				var point: Vector2 = body[0][0]
				var protection := source.armor_at(request[0], request[1], direction, point, "slash", Vector2.ZERO, 0.0, recipe)
				if not _check(_exact(protection, original.armor_at(proxy, point, "slash")), "Armor retains its original restored-pose owner"):
					return
			report.poses += 1
			report.warm_no_seek_queries += 1
			report.matrix_centered_queries += int(uses_centered)
			report.matrix_origin84_queries += int(not uses_centered)
	if not _guards(source, manifest.appearance):
		return
	if not _check(report.poses == (120 if centered else 20) and report.vertices > 1000 and int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) == nodes
		and _hashes() == fingerprint, "Coverage/original owner/source fingerprints") or not _check_time():
		return
	report.merge({"status": "PASS", "centered": centered, "group": group, "tested_clips": tested_clips, "elapsed_usec": Time.get_ticks_usec() - began, "source_hashes": fingerprint,
		"internal_deadline_seconds": 23, "helper_timeout_seconds": 25, "proof": proof, "query_profile": source.query_profile.duplicate(),
		"scope": "Origin84:20poses; centered:10 actual native clips x 0/mid/length x four directions per group,18 centered clips plus two crossbow clips retaining84 across both groups. Actual equipment, all body-shield vertices, exact first-fit/bones/armor/full values, warm hidden-face A while Source remains B, cold/unsupported fallback. Sampling is regression, NOT proof by sampled extrema. Timings are local work, not FPS or rendered appearance acceptance."})
	_write()
	source.dispose()
	print("SITE_GEOMETRY_INCOMING_BOUNDS_PASS ", JSON.stringify(report))
	quit(0)

func _proven_rect(proof: Dictionary, clip: StringName) -> Rect2:
	# Consume the original continuous proof; never derive an enclosure from the
	# geometry sample or expand it until the sampled vertices happen to fit.
	var center := Vector2.ZERO
	var radius := ceilf(float(proof.continuous_pixels) - 31.5 + 1.0)
	if centered and proof.get("centered_clips", {}).has(clip):
		center = proof.centered_clips[clip].center
		radius = float(proof.centered_clips[clip].radius)
	return Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)

func _guards(source: Variant, baseline: Dictionary) -> bool:
	# Resolve A by the original component, never current B visibility.
	var a_component: Dictionary = source.editor._component_definition(&"face", StringName(str(baseline.parts.face)))
	var a_nodes: Array = source.editor._find_component_nodes(a_component.prefixes)
	if not _check(a_nodes.size() == 1 and source.geometry._head_bounds.has(a_nodes[0].get_instance_id()), "Actual warm face A fixture"):
		return false
	var other_face := baseline.duplicate(true)
	other_face.parts.face = "face_standard_02"
	if not _check(source.supports_appearance(other_face), "Actual face B must exist in the same original model"):
		return false
	source.sample(&"rescue", 1.3137, Vector2i.LEFT, Vector2.ZERO, 0.0, other_face, false)
	if not _check(not a_nodes[0].is_visible_in_tree(), "Target A must really be hidden while B is current"):
		return false
	var before := _pose_state(source)
	var hits_before: int = source.query_profile.query_bounds_hits
	var count_before: int = source.query_profile.true_pose_evaluations
	var box: Rect2 = source.query_bounds(&"idle", 0.2731, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline)
	if not _check(box.has_area() and _exact(_pose_state(source), before) and int(source.query_profile.query_bounds_hits) == hits_before + 1
		and int(source.query_profile.true_pose_evaluations) == count_before, "Warm requested A must ignore current B visibility without changing B"):
		return false
	report.guards += 1
	if centered and not _yaw_fallback(source, baseline):
		return false
	var none := baseline.duplicate(true)
	none.parts.face = "none"
	var unknown := baseline.duplicate(true)
	unknown.parts.face = "unknown_face_fixture"
	for recipe: Dictionary in [none, unknown]:
		if not _fallback(source, &"idle", 0.237, Vector2.ZERO, 0.0, recipe):
			return false
	if not _fallback(source, &"guard", 0.173, Vector2.ZERO, 0.0, baseline) or not _fallback(source, &"walk_slash", 1.173, Vector2(40.0, -20.0), 0.4, baseline):
		return false
	# Framing mutations are explicit diagnostic full-clear/rebuild operations,
	# not an expectation of arbitrary unannounced external model mutation.
	var camera: Camera3D = source.editor.camera
	var projection := camera.projection
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	var camera_ok := _fallback(source, &"idle", 0.237, Vector2.ZERO, 0.0, baseline)
	camera.projection = projection
	source.clear_samples()
	if not camera_ok:
		return false
	var transform: Transform2D = source.sprite.transform
	source.sprite.position = Vector2(17000.0, 0.0)
	var world_ok := _fallback(source, &"idle", 0.237, Vector2.ZERO, 0.0, baseline)
	source.sprite.transform = transform
	source.clear_samples()
	return world_ok and _check_time()

func _yaw_fallback(source: Variant, baseline: Dictionary) -> bool:
	# A small world-pivot tilt is inside the original arbitrary-rotation84
	# proof but outside centered pure yaw. Do not alter the Root bone pose/rest.
	var saved: Vector3 = source.editor.preview_pivot.rotation
	source.editor.preview_pivot.rotation = saved + Vector3(0.001, 0.0, 0.0)
	var tilted: Vector3 = source.editor.preview_pivot.rotation
	source.clear_samples()
	var before := _pose_state(source)
	var pose_count: int = source.query_profile.true_pose_evaluations
	var centered_hits: int = source.query_profile.centered_query_bounds_hits
	var query: Rect2 = source.query_bounds(&"idle", 0.237, Vector2i.DOWN, Vector2.ZERO, 0.0, baseline)
	var proof: Dictionary = source._nonattack_bound
	var valid := _check(float(proof.get("radius", 256.0)) < 256.0 and proof.get("centered_clips", {}).is_empty()
		and proof.get("centered_reason", "") == "NOT_PURE_WORLD_YAW", "Non-yaw must retain original84 proof and omit centered proof")
	if valid:
		valid = _check(_exact(query, _proven_rect(proof, &"idle")) and _exact(_pose_state(source), before)
			and source.editor.preview_pivot.rotation == tilted and int(source.query_profile.true_pose_evaluations) == pose_count
			and int(source.query_profile.centered_query_bounds_hits) == centered_hits, "Non-yaw warm query must fall back to original84 without seek or Root mutation")
	source.editor.preview_pivot.rotation = saved
	source.clear_samples()
	if valid:
		report.guards += 1
	return valid and _check_time()

func _fallback(source: Variant, clip: StringName, time: float, aim: Vector2, weight: float, appearance: Dictionary) -> bool:
	source.clear_samples()
	source.cheap_query_bounds_enabled = false
	var expected: Dictionary = source.sample(clip, time, Vector2i.DOWN, aim, weight, appearance, false)
	var expected_bound: Rect2 = expected.get("hurt_bounds", Rect2())
	source.clear_samples()
	source.cheap_query_bounds_enabled = true
	var before: Dictionary = source.query_profile.duplicate()
	var actual: Rect2 = source.query_bounds(clip, time, Vector2i.DOWN, aim, weight, appearance)
	if not _check(_exact(actual, expected_bound) and int(source.query_profile.query_bounds_fills) == int(before.query_bounds_fills) + 1
		and int(source.query_profile.query_bounds_hits) == int(before.query_bounds_hits), "Unsupported input must retain the exact original full query"):
		return false
	report.guards += 1
	return _check_time()

func _write() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file := FileAccess.open(directory + "/measurements.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()

func _hashes() -> Dictionary:
	var result := {}
	for path: String in ["res://scripts/terrain_lab/terrain_weapon_collision.gd", "res://scripts/terrain_lab/terrain_army_contact_source.gd",
		"res://scripts/terrain_lab/terrain_army_source_bounds.gd", "res://scripts/tests/site_geometry_incoming_bounds_test.gd", MANIFEST]:
		result[path] = FileAccess.get_sha256(path)
	return result
