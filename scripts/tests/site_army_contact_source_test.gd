extends SceneTree

const Source = preload("res://scripts/terrain_lab/terrain_army_contact_source.gd")
const Geometry = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(23.0).timeout.connect(func() -> void: quit(1))
	assert(TerrainArmy.load_combat_bake())
	var source := Source.new()
	assert(source.initialize(root, TerrainArmy._combat_bake.manifest.appearance))
	for clip: StringName in [&"idle", &"walk_slash"]:
		var animation := source.editor.animation_player.get_animation(clip)
		var types := {}
		var other: Array[String] = []
		for track in range(animation.get_track_count()):
			var type := animation.track_get_type(track)
			types[type] = int(types.get(type, 0)) + 1
			if not str(animation.track_get_path(track)).contains("Skeleton3D:") and other.size() < 8:
				other.append(str(animation.track_get_path(track)))
		print("CONTACT SOURCE TRACKS: ", clip, " count=", animation.get_track_count(), " types=", types, " other=", other)
	var frames: Dictionary = TerrainArmy._combat_bake.frames
	var poses := load_reference_poses()
	var checked := 0
	var max_error := 0.0
	var began := Time.get_ticks_usec()
	for clip: StringName in [&"combat_idle", &"combat_walk", &"combat_run", &"walk_slash", &"guard"]:
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var frame: Dictionary = frames["%s|%s|%d" % [clip, TerrainArmy.SOLDIER_DIRECTION_NAMES[direction], 0]]
			var pose := StringName(str(TerrainArmy._combat_bake.clips[clip].get("pose", clip)))
			var sample := source.sample(pose, float(frame.sample_time), direction)
			var expected: Dictionary = poses[int(frame.collision_index)]
			for kind: String in ["body", "weapon", "shield"]:
				max_error = maxf(max_error, shape_error(sample[kind], expected[kind]))
			checked += 1
	print("CONTACT SOURCE BASELINE: poses=", checked, " max_error=", max_error, " query_us=", Time.get_ticks_usec() - began)
	assert(max_error < 0.01)
	var skeleton := source.editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var vertex_count := 0
	var vertex_error := 0.0
	var projection_error := 0.0
	var proxy := {"editor": source.editor, "player_sprite": source.sprite}
	for node: Node in source.editor.model_root.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if not part.is_visible_in_tree() or part.mesh == null:
			continue
		var original := source.geometry.posed_vertices(part, skeleton, false)
		var native := source.geometry.posed_vertices(part, skeleton)
		var projected := source.geometry.posed_points(proxy, part, skeleton)
		assert(original.size() == native.size() and original.size() == projected.size())
		for vertex in range(original.size()):
			vertex_error = maxf(vertex_error, original[vertex].distance_to(native[vertex]))
			projection_error = maxf(projection_error, source.geometry.project(proxy, original[vertex]).distance_to(projected[vertex]))
		vertex_count += original.size()
	assert(vertex_error < 0.00001 and projection_error < 0.001)
	print("CONTACT SOURCE NATIVE GEOMETRY: vertices=", vertex_count, " vertex_error=", vertex_error, " projection_error=", projection_error)
	var first := source.sample(&"walk_slash", 0.513, Vector2i.RIGHT)
	var next := source.sample(&"walk_slash", 0.517, Vector2i.RIGHT)
	assert(shape_error(first.weapon, next.weapon) > 0.01, "Source must not freeze between atlas times")
	assert(source.sample(&"walk_slash", 0.513, Vector2i.RIGHT) == first)
	source.clear_samples()
	assert(source.sample(&"walk_slash", 0.513, Vector2i.RIGHT) == first)
	if "--benchmark" in OS.get_cmdline_user_args():
		began = Time.get_ticks_usec()
		for tick in range(120):
			source.clear_samples()
			for index in range(200):
				var pose: StringName = &"walk_slash" if index < 20 else &"idle"
				var direction := Vector2i.LEFT if index % 2 else Vector2i.RIGHT
				assert(source.sample(pose, float(tick) / 120.0, direction).body.size() == 10)
		print("CONTACT SOURCE QUERY BENCHMARK: 200 rows x 120 steps / 4 distinct exact poses per step; elapsed_us=", Time.get_ticks_usec() - began, "; profile including baseline=", source.profile_usec, "; excludes startup, contacts, armor, rendering and aiming; not FPS")
	source.dispose()
	await process_frame
	print("SITE ARMY CONTACT SOURCE PASS: shared original rig, authored baseline and non-atlas clock, exact cache keys; standalone query experiment, not runtime integration")
	quit(0)

func shape_error(a: Array, b: Array) -> float:
	if a.size() != b.size():
		return 10000.0
	var error := 0.0
	for index in range(a.size()):
		for pair: Array in [[a[index], b[index]], [b[index], a[index]]]:
			for point: Vector2 in pair[0]:
				var nearest := INF
				for edge in range(pair[1].size()):
					nearest = minf(nearest, point.distance_to(Geometry2D.get_closest_point_to_segment(point, pair[1][edge], pair[1][(edge + 1) % pair[1].size()])))
				error = maxf(error, nearest)
	return error

static func load_reference_poses() -> Array:
	assert(TerrainArmy.load_combat_bake())
	var manifest: Dictionary = TerrainArmy._combat_bake.manifest
	var file := FileAccess.open_compressed(str(manifest.collision.path), FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	assert(file != null)
	var poses: Array = file.get_var(false)
	file.close()
	assert(poses.size() == manifest.frames.size())
	for pose: Dictionary in poses:
		var points := PackedVector2Array()
		for kind: String in ["body", "shield"]:
			for shape: PackedVector2Array in pose[kind]:
				points.append_array(shape)
		pose["hurt_bounds"] = TerrainArmy.CombatGeometry.polygon_bounds(points)
	return poses
