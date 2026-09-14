extends SceneTree

const SOURCE := "res://assets/characters/terrain_lab_army/standard_soldier"
const ORIGINAL := "res://output/site_combat_idle_20260912_2210/original"
const STAGE := "res://output/site_combat_idle_stage"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(18.0).timeout.connect(func() -> void: quit(1))
	var old_dir := ORIGINAL
	var candidate_dir := SOURCE
	var captures := STAGE
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--original="):
			old_dir = argument.trim_prefix("--original=")
		elif argument.begins_with("--candidate="):
			candidate_dir = argument.trim_prefix("--candidate=")
		elif argument.begins_with("--captures="):
			captures = argument.trim_prefix("--captures=")
	assert(captures.simplify_path().begins_with("res://output/"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(captures))
	var before: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(old_dir + "/standard_soldier_atlas.json"))
	var after: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(candidate_dir + "/standard_soldier_atlas.json"))
	var original_count: int = before.frames.size()
	assert(original_count > 0 and after.frames.size() > original_count)
	assert(after.frames.slice(0, original_count) == before.frames and after.clips.slice(0, before.clips.size()) == before.clips)
	for field: String in before:
		if field not in ["frames", "clips", "atlas"]:
			assert(before[field] == after[field], "Existing manifest field changed: " + field)
	var old_image := Image.load_from_file(old_dir + "/standard_soldier_atlas.png")
	var new_image := Image.load_from_file(candidate_dir + "/standard_soldier_atlas.png")
	assert(old_image.get_width() == new_image.get_width() and old_image.get_height() < new_image.get_height())
	assert(new_image.get_region(Rect2i(Vector2i.ZERO, old_image.get_size())).get_data() == old_image.get_data(), "Existing atlas pixels changed")
	var texture := load(candidate_dir + "/standard_soldier_atlas.res") as Texture2D
	assert(texture.get_image().get_data() == new_image.get_data(), "PNG and runtime texture differ")
	var old_file := FileAccess.open_compressed(old_dir + "/standard_soldier_collision.bin", FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	var old_poses: Array = old_file.get_var(false)
	old_file.close()
	var new_file := FileAccess.open_compressed(candidate_dir + "/standard_soldier_collision.bin", FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	var new_poses: Array = new_file.get_var(false)
	new_file.close()
	assert(new_poses.size() == after.frames.size() and new_poses.slice(0, original_count) == old_poses, "Existing collision polygons/armor triangles changed")
	var added := {}
	var expected := original_count
	for clip: Dictionary in after.clips.slice(before.clips.size()):
		assert(str(clip.id) in ["combat_idle", "combat_walk", "combat_run"])
		assert(clip.pose == str(clip.id).trim_prefix("combat_") and bool(clip.combat_ready))
		assert(int(clip.samples) == (4 if clip.id == "combat_idle" else 8))
		assert(not added.has(clip.id))
		added[clip.id] = clip
		expected += int(clip.samples) * 4
	assert(after.frames.size() == expected, "Unexpected or missing appended frames")
	var seen := {}
	var boards := {}
	for index in range(original_count, expected):
		var frame: Dictionary = after.frames[index]
		assert(added.has(frame.clip) and int(frame.collision_index) == index and int(frame.frame) in range(int(added[frame.clip].samples)))
		assert(str(frame.direction) in ["down", "left", "up", "right"])
		var key := "%s_%s_%d" % [frame.clip, frame.direction, int(frame.frame)]
		assert(not seen.has(key))
		seen[key] = true
		var pose: Dictionary = new_poses[index]
		assert(pose.body.size() == 10 and not pose.weapon.is_empty() and not pose.shield.is_empty() and not pose.armor.is_empty())
		for original: Dictionary in before.frames:
			if original.clip == added[frame.clip].pose and original.direction == frame.direction and int(original.frame) == int(frame.frame):
				assert(is_equal_approx(float(original.duration), float(frame.duration)) and is_equal_approx(float(original.sample_time), float(frame.sample_time)), "Held locomotion must preserve the source animation clock")
		var rect := Rect2i(frame.rect.x, frame.rect.y, frame.rect.w, frame.rect.h)
		assert(rect.position.y >= old_image.get_height() and Rect2i(Vector2i.ZERO, new_image.get_size()).encloses(rect))
		assert(new_image.get_region(rect).save_png(captures + "/" + key + ".png") == OK)
		if not boards.has(frame.clip):
			var board := Image.create(int(added[frame.clip].samples) * 160, 880, false, Image.FORMAT_RGBA8)
			board.fill(Color("293039"))
			boards[frame.clip] = board
		var tile := new_image.get_region(rect)
		var scale := minf(144.0 / tile.get_width(), 200.0 / tile.get_height())
		tile.resize(roundi(tile.get_width() * scale), roundi(tile.get_height() * scale), Image.INTERPOLATE_NEAREST)
		var row := ["down", "left", "up", "right"].find(frame.direction)
		boards[frame.clip].blend_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(int(frame.frame) * 160 + floori(float(160 - tile.get_width()) / 2.0), row * 220 + 210 - tile.get_height()))
	for clip: String in boards:
		assert(boards[clip].save_png(captures + "/" + clip + "_board.png") == OK)
	print("SITE COMBAT APPEND PASS: ", original_count, " original frames/clips/collision/armor/pixels unchanged; added=", expected - original_count, " held-weapon frames; runtime texture equals PNG")
	quit(0)
