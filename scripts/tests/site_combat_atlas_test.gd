extends SceneTree

const DIRECTORY := "res://assets/characters/terrain_lab_army/standard_soldier/"
const Collision = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")
const OUTPUT := "res://.visual_captures/site_combat_assets/atlas"
var directory := DIRECTORY

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--bundle="):
			directory = argument.trim_prefix("--bundle=").simplify_path().trim_suffix("/") + "/"
			assert(directory.begins_with("res://output/"), "Alternative bundle must be a staged output")
	call_deferred("run")

func run() -> void:
	create_timer(23.0).timeout.connect(func() -> void: quit(1))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory + "standard_soldier_atlas.json"))
	assert(manifest.schema_version == 2 and manifest.frames.size() == 1080 and manifest.clips.size() == 35)
	var file := FileAccess.open_compressed(directory + "standard_soldier_collision.bin", FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	assert(file != null)
	var poses: Array = file.get_var(false)
	file.close()
	assert(poses.size() == manifest.frames.size())
	var keys := {}
	for frame: Dictionary in manifest.frames:
		var key := "%s|%s|%d" % [frame.clip, frame.direction, int(frame.frame)]
		assert(not keys.has(key))
		keys[key] = frame
		var pose: Dictionary = poses[int(frame.collision_index)]
		assert(pose.body.size() == 10 and not pose.armor.is_empty())
		assert(int(frame.rect.x) >= 0 and int(frame.rect.y) >= 0)
		assert(int(frame.rect.x + frame.rect.w) <= int(manifest.atlas.width))
		assert(int(frame.rect.y + frame.rect.h) <= int(manifest.atlas.height))
		for kind in ["body", "weapon", "parry", "shield"]:
			for polygon: PackedVector2Array in pose[kind]:
				assert(polygon.size() >= 3)
				for point in polygon:
					assert(point.is_finite())
		for item: Dictionary in pose.armor:
			assert(not item.surfaces.is_empty())
	if DisplayServer.get_name() == "headless":
		print("SITE_COMBAT_ATLAS_DATA_PASS: 1080 unique frame/collision pairs, indexed armor surfaces, finite shapes, bounded atlas rectangles")
		quit(0)
		return
	var actor := TerrainTestCharacter.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.initialize_visual()
	actor.editor.set_process(false)
	assert(actor.editor.restore_appearance(manifest.appearance))
	actor.editor.preview_viewport.size = Vector2i(int(manifest.source_viewport.width), int(manifest.source_viewport.height))
	actor._sync_render_projection()
	var geometry := Collision.new()
	# The production cache fits the head in the baker's first idle frame, not
	# the middle frame. Use the same pose/projection before comparing hulls.
	actor.play_pose(&"idle")
	actor.editor.set_playing(false)
	actor.editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	actor.editor.set_preview_yaw_degrees(0.0)
	actor.editor.animation_player.seek(0.0, true)
	actor.editor.animation_player.advance(0.0)
	actor.editor._update_combat_props()
	actor.editor._update_scabbard_pose()
	geometry.pose_snapshot(actor, &"walk_slash")
	var atlas := Image.load_from_file(ProjectSettings.globalize_path(directory + "standard_soldier_atlas.png"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var checked := 0
	for clip: Dictionary in manifest.clips:
		if str(clip.id) not in ["idle", "combat_idle", "walk_slash", "attack_spear", "attack_axe", "attack_crossbow", "guard", "guard_unshielded", "guard_spear", "guard_weapon_raise", "guard_polearm_break", "guard_break", "down", "get_up", "rescue"]:
			continue
		actor.editor.combat_ready = bool(clip.get("combat_ready", false))
		actor.editor.select_part_by_id(&"weapon", StringName(str(clip.get("weapon", "longsword_01"))))
		actor.editor.select_part_by_id(&"shield", StringName(str(clip.get("shield", "shield_heater_01"))))
		var pose_id := StringName(str(clip.get("pose", clip.id)))
		actor.play_pose(pose_id)
		actor.editor.set_playing(false)
		actor.editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for direction: Dictionary in manifest.directions:
			var frame: Dictionary = keys["%s|%s|%d" % [clip.id, direction.id, floori(float(clip.samples) * .5)]]
			actor.editor.set_preview_yaw_degrees(float(direction.yaw))
			actor.editor.animation_player.seek(float(frame.sample_time), true)
			actor.editor.animation_player.advance(0.0)
			actor.editor._update_combat_props()
			actor.editor._update_scabbard_pose()
			actor.editor._update_combat_cloth()
			var weapon_id := StringName(str(clip.get("weapon", "longsword_01")))
			var live := geometry.pose_snapshot(actor, HumanCharacter3DEditor.WEAPON_ATTACK_MAP.get(weapon_id, &"attack_unarmed"))
			var baked: Dictionary = poses[int(frame.collision_index)]
			for kind in ["body", "weapon", "parry", "shield"]:
				assert(live[kind].size() == baked[kind].size(), "%s %s count" % [clip.id, kind])
				for index in range(live[kind].size()):
					var one: PackedVector2Array = live[kind][index]
					var two: PackedVector2Array = baked[kind][index]
					assert(one.size() == two.size(), "%s %s %s polygon %d vertex count live=%d baked=%d" % [clip.id, direction.id, kind, index, one.size(), two.size()])
					for vertex in range(one.size()):
						assert(one[vertex].distance_to(two[vertex]) < .005, "%s %s %s projection drift" % [clip.id, direction.id, kind])
			for body_index in [0, 1, 3, 6]:
				var point := Vector2.ZERO
				for vertex: Vector2 in live.body[body_index]:
					point += vertex
				point /= live.body[body_index].size()
				assert(geometry.armor_at(actor, point, "cut").is_equal_approx(Collision.snapshot_armor_at(baked, point, "cut")), "Armor coverage disagrees with live geometry")
			if str(direction.id) == "right":
				await process_frame
				await RenderingServer.frame_post_draw
				var rendered := actor.editor.preview_viewport.get_texture().get_image()
				var source := rendered.get_region(rendered.get_used_rect())
				var r: Dictionary = frame.rect
				var baked_image := atlas.get_region(Rect2i(int(r.x), int(r.y), int(r.w), int(r.h)))
				var board := Image.create(640, 400, false, Image.FORMAT_RGBA8)
				board.fill(Color("293039"))
				_stamp(board, source, 0)
				_stamp(board, baked_image, 320)
				assert(board.save_png(OUTPUT + "/" + str(clip.id) + ".png") == OK)
			checked += 1
	print("SITE_COMBAT_ATLAS_VISUAL_CONTRACT_PASS: ", checked, " poses; live/baked body, weapon, shield and armor coverage agree; no soldier Skeleton3D")
	poses.clear()
	actor.queue_free()
	await process_frame
	await process_frame
	quit(0)

func _stamp(board: Image, source: Image, offset: int) -> void:
	var scale := minf(280.0 / source.get_width(), 350.0 / source.get_height())
	source.resize(roundi(source.get_width() * scale), roundi(source.get_height() * scale), Image.INTERPOLATE_NEAREST)
	board.blend_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), Vector2i(offset + floori((320.0 - source.get_width()) * .5), 390 - source.get_height()))
