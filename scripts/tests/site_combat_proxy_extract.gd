extends SceneTree
## Offline, test-only coarse collision profile. AABBs deliberately replace
## authored silhouettes; this is not an exact native collision replacement.

const MANIFEST := "res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.json"
const COLLISIONS := "res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_collision.bin"
const OUTPUT := "res://output/site_combat_proxy_20260914/profile.bin"
const LIMIT_USEC := 55000000
var _started_usec := 0
var output := OUTPUT


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=").simplify_path()
			assert(output.begins_with("res://output/") and output != "res://output/", "Profile staging must stay in one named output path")
	call_deferred("run")


func run() -> void:
	_started_usec = Time.get_ticks_usec()
	create_timer(55.0).timeout.connect(func() -> void:
		push_error("PROFILE_EXTRACT_TIMEOUT")
		quit(1))
	assert(DisplayServer.get_name() == "headless", "Extraction needs no renderer")
	if FileAccess.file_exists(output):
		push_error("PROFILE_EXTRACT_REFUSES_OVERWRITE: " + output)
		quit(1)
		return
	var sources := _source_hashes()
	if not _within_deadline():
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var expected_frames := 0
	for clip: Dictionary in manifest.clips:
		expected_frames += int(clip.samples) * manifest.directions.size()
	assert(int(manifest.schema_version) == 2 and manifest.frames.size() == expected_frames)
	assert(manifest.directions.size() == 4)
	var file := FileAccess.open_compressed(COLLISIONS, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	assert(file != null, "Could not open original collision data")
	var poses: Array = file.get_var(false)
	file.close()
	assert(poses.size() == manifest.frames.size())
	if not _within_deadline():
		return
	var tracks := {}
	var clip_samples := {}
	var direction_ids := {}
	for direction: Dictionary in manifest.directions:
		var direction_id := str(direction.id)
		assert(not direction_ids.has(direction_id))
		direction_ids[direction_id] = true
	for clip: Dictionary in manifest.clips:
		var clip_id := str(clip.id) # Keep combat-ready and equipment aliases distinct.
		assert(not clip_samples.has(clip_id) and int(clip.samples) > 0)
		clip_samples[clip_id] = int(clip.samples)
		for direction_id: String in direction_ids:
			var frames: Array[Dictionary] = []
			tracks[clip_id + "|" + direction_id] = {"duration": 0.0, "loop": false,
				"times": PackedFloat64Array(), "frames": frames}
	var seen_indices := {}
	var seen_frames := {}
	var jump_directions := {}
	for descriptor: Dictionary in manifest.frames:
		if not _within_deadline():
			return
		var clip_id := str(descriptor.clip)
		var track_key := clip_id + "|" + str(descriptor.direction)
		assert(tracks.has(track_key))
		var collision_index := int(descriptor.collision_index)
		assert(float(collision_index) == float(descriptor.collision_index))
		assert(collision_index >= 0 and collision_index < poses.size() and not seen_indices.has(collision_index))
		seen_indices[collision_index] = true
		var track: Dictionary = tracks[track_key]
		var frame_index := int(descriptor.frame)
		var frame_key := track_key + "|" + str(frame_index)
		assert(float(frame_index) == float(descriptor.frame) and frame_index == track.frames.size())
		assert(not seen_frames.has(frame_key))
		seen_frames[frame_key] = true
		if clip_id == "attack_jump_heavy":
			jump_directions[descriptor.direction] = int(jump_directions.get(descriptor.direction, 0)) + 1
		var sample_time := float(descriptor.sample_time)
		var duration := float(descriptor.duration)
		assert(is_finite(sample_time) and is_finite(duration) and duration > 0.0)
		assert(sample_time >= 0.0 and sample_time <= duration)
		var times: PackedFloat64Array = track.times
		if times.is_empty():
			assert(sample_time == 0.0)
			track.duration = duration
		else:
			assert(duration == float(track.duration) and sample_time > times[times.size() - 1])
		times.append(sample_time)
		track.times = times
		var pose: Dictionary = poses[collision_index]
		assert(pose.body.size() == 10)
		var bodies: Array[PackedVector2Array] = []
		for polygon: PackedVector2Array in pose.body:
			bodies.append(_rectangle(_polygon_bounds(polygon)))
		var frame := {"body": bodies, "weapon": _merged_shape(pose.weapon),
			"shield": _merged_shape(pose.shield), "parry": _merged_shape(pose.parry)}
		var hurt_points := PackedVector2Array()
		for kind: String in ["body", "shield", "parry"]:
			for polygon: PackedVector2Array in frame[kind]:
				hurt_points.append_array(polygon)
		frame["hurt_bounds"] = _polygon_bounds(hurt_points)
		track.frames.append(frame)
		poses[collision_index] = {} # Release processed armor; preserve the original typed Dictionary array.
	assert(seen_indices.size() == expected_frames and seen_frames.size() == expected_frames)
	assert(tracks.size() == manifest.clips.size() * manifest.directions.size())
	assert(jump_directions.size() == 4)
	for direction: Dictionary in manifest.directions:
		assert(jump_directions.get(direction.id, 0) == 12)
	for track_key: String in tracks:
		var track: Dictionary = tracks[track_key]
		var times: PackedFloat64Array = track.times
		assert(times.size() == int(clip_samples[track_key.get_slice("|", 0)]) and times.size() == track.frames.size())
		track.loop = times[times.size() - 1] < float(track.duration) - 0.000001
	var final_sources := _source_hashes()
	if sources != final_sources:
		push_error("PROFILE_EXTRACT_SOURCE_CHANGED")
		quit(1)
		return
	if not _within_deadline():
		return
	var profile := {"schema": 1, "test_only": true, "sources": sources,
		"appearance": manifest.appearance.duplicate(true), "tracks": tracks}
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	assert(directory_error == OK)
	if FileAccess.file_exists(output):
		push_error("PROFILE_EXTRACT_REFUSES_OVERWRITE: " + output)
		quit(1)
		return
	var output_file := FileAccess.open_compressed(output, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	assert(output_file != null)
	output_file.store_var(profile, false)
	output_file.close()
	if not _within_deadline():
		return
	var saved_file := FileAccess.open(output, FileAccess.READ)
	assert(saved_file != null)
	var saved_bytes := saved_file.get_length()
	saved_file.close()
	assert(saved_bytes > 0)
	print("PROFILE_EXTRACT_PASS frames=", seen_frames.size(), " tracks=", tracks.size(), " bytes=", saved_bytes)
	quit(0)


func _source_hashes() -> Dictionary:
	var hashes := {}
	for path: String in [MANIFEST, COLLISIONS]:
		var digest := FileAccess.get_sha256(path)
		assert(digest.length() == 64, "Could not hash source: " + path)
		hashes[path] = digest
	return hashes


func _within_deadline() -> bool:
	if Time.get_ticks_usec() - _started_usec > LIMIT_USEC:
		push_error("PROFILE_EXTRACT_MONOTONIC_TIMEOUT")
		quit(1)
		return false
	return true


func _polygon_bounds(points: PackedVector2Array) -> Rect2:
	assert(points.size() >= 3)
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		assert(point.is_finite(), "Nonfinite source shape")
		bounds = bounds.expand(point)
	assert(bounds.position.is_finite() and bounds.end.is_finite())
	return bounds


func _rectangle(bounds: Rect2) -> PackedVector2Array:
	return PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y),
		bounds.end, Vector2(bounds.position.x, bounds.end.y)])


func _merged_shape(shapes: Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if shapes.is_empty():
		return result
	var points := PackedVector2Array()
	for polygon: PackedVector2Array in shapes:
		assert(polygon.size() >= 3)
		points.append_array(polygon)
	result.append(_rectangle(_polygon_bounds(points)))
	return result
