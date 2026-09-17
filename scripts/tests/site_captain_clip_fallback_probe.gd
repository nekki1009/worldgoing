extends "res://scripts/tests/site_captain_timeline_replay_test.gd"
## Fresh original private presenters: old/old control, then resident + fallback.
var texture_signatures := {}

func _snapshot_value(value: Variant) -> Variant:
	if value is Texture2D:
		var identity: int = value.get_instance_id()
		if not texture_signatures.has(identity):
			var texture_image: Image = value.get_image()
			var digest := HashingContext.new()
			assert(digest.start(HashingContext.HASH_SHA256) == OK)
			assert(digest.update(texture_image.get_data()) == OK)
			texture_signatures[identity] = [value.get_class(), value.resource_name, value.resource_path, texture_image.get_size(), texture_image.get_format(), texture_image.has_mipmaps(), digest.finish().hex_encode()]
		return texture_signatures[identity]
	assert(not value is Resource, "Unhandled fresh-instance uniform Resource")
	if value is Array:
		var snapshot := []
		for child: Variant in value: snapshot.append(_snapshot_value(child))
		return snapshot
	return value

func _state() -> Array:
	# Same pixels/content, not Resource pointer identity across fresh raw imports.
	var result: Array = _snapshot_value(super._state())
	# Fresh raw GLTF instances receive process-global generated simulator IDs.
	# Compare the full path/type/order, every transform/bone/morph and exact RGBA;
	# only that non-authored numeric name suffix differs in old-vs-old control.
	var generated := RegEx.new()
	assert(generated.compile("@PhysicalBoneSimulator3D@[0-9]+") == OK)
	for record: Array in result:
		if record[0] is String: record[0] = generated.sub(record[0], "@PhysicalBoneSimulator3D@instance", true)
	return result

func _run() -> void:
	create_timer(170.0).timeout.connect(func() -> void: push_error("Clip fallback deadline"); quit(1))
	assert(DisplayServer.get_name() != "headless")
	preload("res://scripts/tests/fixtures/captain_clip_safe_install.gd").install()
	out = "res://output/site_captain_clip_safe_20260917/fallback_%d" % int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var data := TerrainData.new()
	data.allocate(Vector2i(24, 24))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(data, "clip-safe-fallback")
	data.static_blocked.fill(0)
	paused = true
	var rows := []
	var boundaries := ["open", "equipment", "appearance", "mount", "body", "queue", "blend", "chain"]
	if "--public-boundaries-only" in OS.get_cmdline_user_args():
		# Queue/blend/chain also have a same-presenter continuous replay suite;
		# fresh imports are still required for model/mount lifetime boundaries.
		boundaries = ["open", "equipment", "appearance", "mount", "body"]
	for boundary: String in boundaries:
		var expected := []
		var pixels := PackedByteArray()
		for variant in range(3):
			army = TerrainArmy.new()
			army.name = "FallbackArmy"
			army.roster_size = 1
			root.add_child(army)
			army.set_process(false)
			assert(army.deploy_at(data, null, null, [Vector2i(10, 10)]) and army.enable_combat(false))
			editor = army._unit_editor(0)
			editor.set_process(false)
			var player := editor.animation_player
			player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			assert(editor.select_animation_by_id(&"idle"))
			editor.set_playing(true)
			var library := player.get_animation_library(&"")
			var originals := {}
			for clip: StringName in player.get_animation_list(): originals[clip] = library.get_animation(clip)
			if variant == 2:
				editor.set_meta(&"clip_safe_enabled", true)
				editor.call("_clip_safe_prepare", &"idle")
				assert(bool(editor.get_meta(&"clip_safe_enabled")) and int(editor.get_meta(&"clip_safe_tracks")) > 0)
				assert(library.get_animation(&"attack_bow").get_track_count() == 0)
			for pose: StringName in [&"guard", &"walk_slash", &"idle"]:
				assert(editor.select_animation_by_id(pose))
				player.seek(player.get_animation(pose).length, true)
				editor._process(0.0)
			# Complete fresh-model GPU uploads before the tested boundary. Keep
			# its FIRST rendered result below (do not settle away a boundary bug).
			for initial_frame in range(2):
				await process_frame
				await RenderingServer.frame_post_draw
			var owner := var_to_bytes([army.combat_units, army.cells, army.command_rng.state, army.combat_slots, army._reserved_cells])
			match boundary:
				"open": editor.open()
				"equipment": assert(editor.select_part_by_id(&"weapon", &"bow_01"))
				"appearance":
					var appearance := editor.capture_appearance()
					appearance.parts.cape = "cape_chinese_01"
					assert(editor.restore_appearance(appearance))
				"mount": editor.set_mount_enabled(true)
				"body": editor._on_body_selected(0)
				"queue":
					player.queue(&"down")
					assert(editor.select_animation_by_id(&"guard"))
				"blend":
					player.playback_default_blend_time = .1
					assert(editor.select_animation_by_id(&"guard"))
				"chain":
					player.animation_set_next(&"idle", &"down")
					# Explicit first activation with unsupported chain must stay full.
					if variant == 2:
						editor.call("_clip_safe_restore", "test_chain_setup")
						if editor.has_meta(&"clip_safe_full"): editor.remove_meta(&"clip_safe_full")
						editor.set_meta(&"clip_safe_enabled", true)
					assert(editor.select_animation_by_id(&"guard"))
			if variant == 2:
				assert(not bool(editor.get_meta(&"clip_safe_enabled")), "Boundary must restore full: " + boundary)
				for clip: StringName in originals: assert(library.get_animation(clip) == originals[clip])
			player = editor.animation_player
			player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			player.seek(.173, true)
			editor._process(0.0)
			var immediate := _state()
			await process_frame
			await RenderingServer.frame_post_draw
			var picture := editor.preview_viewport.get_texture().get_image()
			assert(picture.get_used_rect().has_area())
			assert(owner == var_to_bytes([army.combat_units, army.cells, army.command_rng.state, army.combat_slots, army._reserved_cells]))
			var observation: Array = [immediate, _state(), editor.capture_appearance()]
			var row := {"boundary": boundary, "variant": variant, "state_equal": true, "rgba_equal": true}
			if variant == 0:
				expected = observation
				pixels = picture.get_data()
				assert(picture.save_png(out + "/" + boundary + "_original.png") == OK)
			else:
				row.state_equal = observation == expected
				row.rgba_equal = picture.get_data() == pixels
				row.difference = _difference(expected, observation)
			rows.append(row)
			var file := FileAccess.open(out + "/measurements.json", FileAccess.WRITE)
			file.store_string(JSON.stringify({"rows": rows, "complete": false, "candidate_adopted": false}, "\t"))
			file.close()
			if not row.state_equal or not row.rgba_equal:
				assert(picture.save_png(out + "/" + boundary + "_mismatch.png") == OK)
				push_error("Boundary/control mismatch: " + str(row))
				army.free()
				quit(1)
				return
			if variant == 2 and boundary in ["equipment", "mount", "body"]: assert(picture.save_png(out + "/" + boundary + ".png") == OK)
			assert(editor.select_animation_by_id(&"idle"))
			if variant == 2: assert(not bool(editor.get_meta(&"clip_safe_enabled")), "Fallback must remain full")
			army.free()
			await process_frame
	var file := FileAccess.open(out + "/measurements.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows": rows, "complete": true, "candidate_adopted": false}, "\t"))
	file.close()
	print("CLIP_FALLBACK_PASS boundaries=", boundaries.size(), " controls=", boundaries.size(), " candidate_pairs=", boundaries.size(), " output=", out)
	quit(0)
