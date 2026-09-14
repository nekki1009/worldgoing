extends "res://scripts/tests/site_army_constant_morph_test.gd"
## GPU --body=0/1; one original Actor/player/model, internal 45s/helper 50s.
## --raw-repeat runs AAAA with the identical complete histories before trusting
## any reduced-library comparison; it is not a compaction acceptance result.
## --copy-only keeps ABBA but B is duplicate(true) with every key untouched.
## --in-place-test uses AABB on the same raw instance resources: no Animation
## duplicate or library replacement. Only this disposable test Actor is mutated.
## Reuses only the existing pure compactor and exact native-value test oracles.
## The Source RefCounted below is never initialized and creates no query rig.

var actor_body := 0
var raw_repeat_only := false
var copy_only := false
var in_place_test := false
var test_actor: TerrainTestCharacter
var test_skeleton: Skeleton3D
var test_meshes: Array[MeshInstance3D] = []
var raw_libraries: Dictionary = {}
var reduced_libraries: Dictionary = {}
var raw_loops: Dictionary = {}
var native_report := {"exact_pairs": 0, "geometry_pairs": 0, "passes": [], "timings": []}
var started_usec := 0

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--body="):
			actor_body = argument.trim_prefix("--body=").to_int()
		elif argument == "--raw-repeat":
			raw_repeat_only = true
		elif argument == "--copy-only":
			copy_only = true
		elif argument == "--in-place-test":
			in_place_test = true
	call_deferred("run")

func run() -> void:
	started_usec = Time.get_ticks_usec()
	morph_deadline_usec = started_usec + 45000000
	create_timer(45.0).timeout.connect(func() -> void: quit(1))
	assert(DisplayServer.get_name() != "headless" and actor_body in [0, 1])
	assert(int(raw_repeat_only) + int(copy_only) + int(in_place_test) <= 1, "Choose one isolated diagnostic")
	test_actor = TerrainTestCharacter.new()
	test_actor.visual_state.body_index = actor_body
	test_actor.combat_driven_by_lab = true
	root.add_child(test_actor)
	test_actor.set_process(false)
	test_actor.initialize_visual()
	assert(test_actor.editor != null and test_actor.editor._body_index == actor_body and not test_actor.editor.use_imported_model)
	test_actor.editor.set_process(false)
	test_actor.editor.set_playing(false)
	test_actor.editor.combat_ready = true
	test_actor.editor.visual_state.combat_ready = true
	test_actor.editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if test_actor.editor.mount_horse != null:
		test_actor.editor.mount_horse.set_process(false)
		test_actor.editor.mount_horse.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	test_skeleton = test_actor.editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	assert(test_skeleton != null)
	for node: Node in test_actor.editor.model_root.find_children("*", "MeshInstance3D", true, false):
		test_meshes.append(node as MeshInstance3D)
	var player := test_actor.editor.animation_player
	var original_ids := [test_actor.get_instance_id(), test_actor.editor.get_instance_id(), player.get_instance_id(), test_skeleton.get_instance_id()]
	var raw_hashes := _player_digest(player)
	var raw_path := str(HumanCharacter3DEditor.BODY_MODELS[actor_body].path)
	var raw_file_hash := FileAccess.get_sha256(raw_path) if in_place_test else ""
	var animation_ids: Dictionary = {}
	for library_name: StringName in player.get_animation_library_list():
		raw_libraries[library_name] = player.get_animation_library(library_name)
	for clip: StringName in player.get_animation_list():
		raw_loops[clip] = player.get_animation(clip).loop_mode
		animation_ids[clip] = player.get_animation(clip).get_instance_id()
		if in_place_test:
			assert(player.get_animation(clip).resource_path.is_empty(), "In-place probe only admits raw GLTF-generated, non-file-backed Animation resources")
	if in_place_test:
		for library: AnimationLibrary in raw_libraries.values():
			assert(library.resource_path.is_empty(), "Never mutate a loaded shared asset library")
	var compactor := Source.new() # No initialize(), editor, skeleton or Source caches.
	var copy_started := Time.get_ticks_usec()
	for library_name: StringName in raw_libraries:
		if in_place_test:
			continue
		var original: AnimationLibrary = raw_libraries[library_name]
		var candidate := AnimationLibrary.new()
		for clip: StringName in original.get_animation_list():
			_deadline()
			var animation := original.get_animation(clip).duplicate(true) as Animation
			if not copy_only:
				compactor._compact_constant_morph_keys(animation)
			assert(candidate.add_animation(clip, animation) == OK)
		reduced_libraries[library_name] = candidate
	native_report.copy_compact_usec = Time.get_ticks_usec() - copy_started
	assert(compactor.editor == null and compactor.skeleton == null)
	# A temporary AnimationPlayer is deliberately unnecessary: audit native
	# resources directly through the original library list, preserving all tracks.
	var audit := {} if in_place_test else _audit_copies()
	var valid_compaction: bool = in_place_test or (not audit.is_empty() and (int(audit.compacted_tracks) == 0 if copy_only else int(audit.compacted_tracks) > 0))
	if not valid_compaction:
		push_error("Actor native copy audit incomplete or unexpected key changes for the selected mode")
		quit(1)
		return
	native_report.library_audit = audit
	var cases := _cases()
	var expected: Array[Dictionary] = []
	for pass_index in range(4):
		_deadline()
		var use_copy := not raw_repeat_only and not in_place_test and pass_index in [1, 2] # AAAA, ABBA, or same-resource AABB.
		var compact := (use_copy and not copy_only) or (in_place_test and pass_index >= 2)
		_install(reduced_libraries if use_copy else raw_libraries)
		if in_place_test and pass_index == 2:
			assert(_player_digest(player) == raw_hashes, "Two raw histories leave every original track/key unchanged before compaction")
			var compact_started := Time.get_ticks_usec()
			audit = _compact_in_place(compactor)
			assert(int(audit.compacted_tracks) > 0)
			native_report.library_audit = audit
			native_report.in_place_compact_usec = Time.get_ticks_usec() - compact_started
		_reset_history()
		var reset_bones := _first_bone_components()
		print("ACTOR MORPH HISTORY RESET ", JSON.stringify({"pass": pass_index, "compact": compact, "raw_repeat": raw_repeat_only, "copy_only": copy_only, "use_copy": use_copy, "bones": reset_bones}))
		for index in range(cases.size()):
			_deadline()
			if not _pose_case(cases[index]):
				push_error("Original Actor fixture unavailable: " + str(cases[index]))
				quit(1)
				return
			var geometry_case := index in [5, 9, 12]
			var snapshot := _actor_snapshot(geometry_case)
			if index == 0:
				print("ACTOR MORPH FIRST SEEK ", JSON.stringify({"pass": pass_index, "compact": compact, "raw_repeat": raw_repeat_only, "copy_only": copy_only, "use_copy": use_copy, "bones": _first_bone_components()}))
			if pass_index == 0:
				expected.append(snapshot)
			else:
				var differences: Array[Dictionary] = []
				_snapshot_byte_diff(expected[index], snapshot, "$actor", differences)
				if not differences.is_empty():
					print("ACTOR CONSTANT MORPH DIFFERENCE ", JSON.stringify({"pass": pass_index, "case": index, "raw_repeat": raw_repeat_only, "copy_only": copy_only, "differences": differences}))
					var failure := "Actor original/duplicate numeric value bits differ" if copy_only else "Actor original/reduced numeric value bits differ"
					if in_place_test:
						failure = "Actor same-resource in-place compaction numeric value bits differ"
					push_error("Actor raw-to-raw history is not bitwise repeatable" if raw_repeat_only else failure)
					quit(1)
					return
				native_report.exact_pairs += 1
				native_report.geometry_pairs += int(geometry_case)
		for round_index in range(2):
			_time_seeks(pass_index, round_index, compact, false)
			_time_seeks(pass_index, round_index, compact, true)
		native_report.passes.append({"pass": pass_index, "compact": compact, "use_copy": use_copy, "cases": cases.size()})
		assert(original_ids == [test_actor.get_instance_id(), test_actor.editor.get_instance_id(), player.get_instance_id(), test_skeleton.get_instance_id()])
		if in_place_test:
			assert(player.get_animation_list().size() == animation_ids.size())
			for clip: StringName in animation_ids:
				assert(player.get_animation(clip).get_instance_id() == int(animation_ids[clip]))
			for library_name: StringName in raw_libraries:
				assert(player.get_animation_library(library_name) == raw_libraries[library_name])
	# UI select_animation legitimately writes loop_mode. Restore those exact
	# recorded values before checking the untouched original track/key resources.
	_install(raw_libraries)
	if in_place_test:
		assert(FileAccess.get_sha256(raw_path) == raw_file_hash, "Only disposable in-memory Actor resources changed; original GLB bytes are untouched")
	else:
		assert(_player_digest(player) == raw_hashes, "Original complete native libraries/keys/track metadata remain unchanged")
	_deadline()
	native_report.body = actor_body
	native_report.sequence = "AABB" if in_place_test else ("AAAA" if raw_repeat_only else "ABBA")
	native_report.candidate_evaluated = not raw_repeat_only and not copy_only
	native_report.copy_only = copy_only
	native_report.in_place_test = in_place_test
	native_report.same_animation_and_library_instances = in_place_test
	native_report.raw_file_sha256 = raw_file_hash
	native_report.elapsed_usec = Time.get_ticks_usec() - started_usec
	native_report.maximum_numeric_error = 0.0
	native_report.original_resources_unchanged = not in_place_test
	native_report.original_asset_files_unchanged = true
	native_report.original_actor_player_skeleton_retained = true
	native_report.compactor_created_rig = false
	native_report.scope = "Single original Actor/native player %s; all bones and every visible/hidden morph numeric bits, small original body/shield/weapon geometry subset; unchanged camera/projection. No disabled tracks, no cape omission, no FPS claim. Raw-repeat checks original history; copy-only checks unchanged duplicate resources; neither is compaction acceptance." % native_report.sequence
	if in_place_test:
		native_report.scope += " In-place mode compacts only this raw-generated Actor's same Animation resources after two raw passes. No duplicate Animation, library removal/addition, Source rig or saved asset writes. Raw resources intentionally change in memory, but all non-compacted keys and every track metadata remain exact."
	native_report.source_borrow_boundary = "Production Source may borrow Actor animations; any future Actor default must leave original-reference fixtures explicitly uncompressed. This test does not initialize Source."
	native_report.source_sha256 = FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_contact_source.gd")
	native_report.actor_sha256 = FileAccess.get_sha256("res://scripts/terrain_lab/terrain_test_character.gd")
	var directory := "res://output/site_combat_performance_20260913/actor_constant_morph/%d_%d_body%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec(), actor_body]
	if in_place_test:
		directory += "_in_place_test"
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK)
	var file := FileAccess.open(directory + "/measurements.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(native_report, "\t"))
	file.close()
	var marker := "SITE ACTOR CONSTANT MORPH COPY ONLY PASS " if copy_only else "SITE ACTOR CONSTANT MORPH PASS "
	if in_place_test:
		marker = "SITE ACTOR CONSTANT MORPH IN PLACE PASS "
	print("SITE ACTOR CONSTANT MORPH RAW REPEAT PASS " if raw_repeat_only else marker, JSON.stringify(native_report))
	test_actor.queue_free()
	await process_frame
	quit(0)

func _compact_in_place(compactor: RefCounted) -> Dictionary:
	var counts := {"clips": 0, "tracks": 0, "original_keys": 0, "private_keys": 0, "compacted_tracks": 0}
	for library: AnimationLibrary in raw_libraries.values():
		for clip: StringName in library.get_animation_list():
			_deadline()
			var animation := library.get_animation(clip)
			assert(animation.resource_path.is_empty())
			var identity := animation.get_instance_id()
			var properties := var_to_bytes([animation.length, animation.loop_mode, animation.step])
			var tracks: Array[Dictionary] = []
			for track in animation.get_track_count():
				var count := animation.track_get_key_count(track)
				tracks.append({"metadata": _metadata(animation, track), "count": count,
					"keys": var_to_bytes(animation.get("tracks/%d/keys" % track)),
					"first": var_to_bytes([animation.track_get_key_time(track, 0), animation.track_get_key_transition(track, 0), animation.track_get_key_value(track, 0)]) if count > 0 else PackedByteArray()})
			compactor._compact_constant_morph_keys(animation)
			assert(animation.get_instance_id() == identity and animation.get_track_count() == tracks.size())
			assert(var_to_bytes([animation.length, animation.loop_mode, animation.step]) == properties)
			counts.clips += 1
			for track in animation.get_track_count():
				var before: Dictionary = tracks[track]
				assert(_metadata(animation, track) == before.metadata)
				var count := animation.track_get_key_count(track)
				counts.tracks += 1
				counts.original_keys += int(before.count)
				counts.private_keys += count
				if count == int(before.count):
					assert(var_to_bytes(animation.get("tracks/%d/keys" % track)) == before.keys)
				else:
					assert(animation.track_get_type(track) == Animation.TYPE_BLEND_SHAPE and count == 1 and int(before.count) > 1)
					assert(var_to_bytes([animation.track_get_key_time(track, 0), animation.track_get_key_transition(track, 0), animation.track_get_key_value(track, 0)]) == before.first)
					counts.compacted_tracks += 1
	return counts

func _audit_copies() -> Dictionary:
	var counts := {"clips": 0, "tracks": 0, "original_keys": 0, "private_keys": 0, "compacted_tracks": 0}
	for library_name: StringName in raw_libraries:
		var original_library: AnimationLibrary = raw_libraries[library_name]
		var candidate_library: AnimationLibrary = reduced_libraries[library_name]
		assert(original_library.get_animation_list() == candidate_library.get_animation_list())
		for clip: StringName in original_library.get_animation_list():
			_deadline()
			var original := original_library.get_animation(clip)
			var candidate := candidate_library.get_animation(clip)
			assert(original != candidate and original.get_track_count() == candidate.get_track_count())
			assert(original.length == candidate.length and original.loop_mode == candidate.loop_mode and original.step == candidate.step)
			counts.clips += 1
			for track in range(original.get_track_count()):
				assert(_metadata(original, track) == _metadata(candidate, track))
				var original_count := original.track_get_key_count(track)
				var candidate_count := candidate.track_get_key_count(track)
				counts.tracks += 1
				counts.original_keys += original_count
				counts.private_keys += candidate_count
				if candidate_count == original_count:
					assert(var_to_bytes(original.get("tracks/%d/keys" % track)) == var_to_bytes(candidate.get("tracks/%d/keys" % track)))
				else:
					assert(original.track_get_type(track) == Animation.TYPE_BLEND_SHAPE and candidate_count == 1 and original_count > 1)
					assert(candidate.track_get_key_time(track, 0) == original.track_get_key_time(track, 0))
					assert(candidate.track_get_key_transition(track, 0) == original.track_get_key_transition(track, 0))
					assert(_bits(candidate.track_get_key_value(track, 0)) == _bits(original.track_get_key_value(track, 0)))
					counts.compacted_tracks += 1
	return counts

func _install(libraries: Dictionary) -> void:
	test_actor.editor.set_mount_enabled(false)
	var player := test_actor.editor.animation_player
	player.stop()
	if not in_place_test:
		for library_name: StringName in player.get_animation_library_list():
			player.remove_animation_library(library_name)
		for library_name: StringName in libraries:
			assert(player.add_animation_library(library_name, libraries[library_name]) == OK)
	for clip: StringName in player.get_animation_list():
		player.get_animation(clip).loop_mode = raw_loops[clip]
	test_actor.editor._selected_animation = &""
	test_actor.editor.set_playing(false)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

func _reset_history() -> void:
	seed(180632)
	test_skeleton.reset_bone_poses()
	for mesh: MeshInstance3D in test_meshes:
		for shape in mesh.get_blend_shape_count():
			mesh.set_blend_shape_value(shape, 0.0)
	test_actor._geometry._head_bounds.clear() # Identical original first-fit pose each pass.
	test_actor.visual_state.animation_time = 0.0
	test_actor.position = Vector2.ZERO
	test_actor.editor.set_preview_yaw_degrees(0.0)

func _first_bone_components() -> Array[Dictionary]:
	# Read raw local channels, not a forced global-pose update or a substitute
	# reset. This distinguishes a native rotation change from Basis rebuilding.
	var result: Array[Dictionary] = []
	for index in range(mini(4, test_skeleton.get_bone_count())):
		var position := test_skeleton.get_bone_pose_position(index)
		var rotation := test_skeleton.get_bone_pose_rotation(index)
		var scale := test_skeleton.get_bone_pose_scale(index)
		result.append({"bone": index, "name": test_skeleton.get_bone_name(index),
			"position": [position.x, position.y, position.z], "rotation": [rotation.x, rotation.y, rotation.z, rotation.w],
			"scale": [scale.x, scale.y, scale.z], "local_channel_bits": var_to_bytes([position, rotation, scale]).hex_encode(),
			"rest_bits": var_to_bytes(test_skeleton.get_bone_rest(index)).hex_encode()})
	return result

func _cases() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entry: Array in [[&"idle", .137], [&"idle", .999999], [&"idle", .000001], [&"walk", .319],
		[&"down", .337], [&"down", -1.0], [&"unconscious", .173], [&"get_up", .537],
		[&"idle", .219], [&"guard", .073], [&"attack_bow", .417], [&"reload_bow", .173],
		[&"ride_slash", .417], [&"ride_idle", .173], [&"idle", .437]]:
		var appearance := HumanCharacter3DEditor.default_appearance(actor_body)
		appearance.parts.merge({"armor": "armor_mingguang_01", "helmet": "helmet_mingguang_01", "outfit": "outfit_chinese_lining_01",
			"boots": "boots_mingguang_01", "weapon": "longsword_01", "shield": "shield_heater_01", "cape": "cape_chinese_01"}, true)
		if rows.size() == 8:
			appearance.parts.cape = "none"
		elif rows.size() == 9:
			appearance.parts.cape = "cape_travel_01"
		if entry[0] in [&"attack_bow", &"reload_bow"]:
			appearance.parts.weapon = "bow_01"
			appearance.parts.shield = "none"
		appearance.mounted = str(entry[0]).begins_with("ride_")
		rows.append({"clip": entry[0], "time": entry[1], "appearance": appearance, "yaw": [0.0, 180.0, -90.0, 90.0][rows.size() % 4]})
	return rows

func _pose_case(request: Dictionary) -> bool:
	var editor := test_actor.editor
	if not editor.restore_appearance(request.appearance) or not editor.select_animation_by_id(request.clip):
		return false
	editor.set_preview_yaw_degrees(float(request.yaw))
	var animation := editor.animation_player.get_animation(editor.selected_animation)
	var at := animation.length if float(request.time) < 0.0 else float(request.time)
	editor.animation_player.seek(at, true)
	test_actor.visual_state.animation_time = at
	if editor.is_mounted:
		editor._sync_mount_animation()
	editor._update_combat_props()
	editor._update_scabbard_pose()
	editor._update_combat_cloth()
	editor._update_hair_mask()
	test_actor._sync_render_projection()
	return true

func _actor_snapshot(with_geometry: bool) -> Dictionary:
	var editor := test_actor.editor
	var result := {"bones": [], "morphs": {}, "meshes": {}, "clip": editor.selected_animation,
		"time": editor.animation_player.current_animation_position, "camera": editor.camera.global_transform,
		"camera_size": editor.camera.size, "sprite": test_actor.player_sprite.global_transform, "model": editor.model_root.global_transform}
	for index in test_skeleton.get_bone_count():
		result.bones.append([test_skeleton.get_bone_pose(index), test_skeleton.get_bone_global_pose(index)])
	for mesh: MeshInstance3D in test_meshes:
		var key := str(editor.model_root.get_path_to(mesh))
		var values: Array[float] = []
		for shape in mesh.get_blend_shape_count():
			values.append(mesh.get_blend_shape_value(shape))
		result.morphs[key] = values # All, including hidden and unworn Cape/armor.
		result.meshes[key] = [mesh.is_visible_in_tree(), mesh.global_transform]
	if with_geometry:
		result.body = test_actor._geometry.body_shapes(test_actor)
		result.shield = test_actor._geometry.shield_shapes(test_actor)
		result.weapon = test_actor._geometry.weapon_shapes(test_actor, editor._resolve_weapon_attack_animation())
	return result

func _time_seeks(pass_index: int, round_index: int, compact: bool, mixed: bool) -> void:
	_deadline()
	var editor := test_actor.editor
	editor.set_mount_enabled(false)
	assert(editor.select_animation_by_id(&"idle"))
	var player := editor.animation_player
	for index in range(8):
		player.seek(.013 + float(index) / 120.0, true)
	var seek_usec := 0
	var select_usec := 0
	var clip_changes := 0
	var began := Time.get_ticks_usec()
	for index in range(200):
		var clip: StringName = &"walk" if mixed and index % 4 >= 2 else &"idle"
		if editor.selected_animation != clip:
			var select_started := Time.get_ticks_usec()
			assert(editor.select_animation_by_id(clip))
			select_usec += Time.get_ticks_usec() - select_started
			clip_changes += 1
		var seek_started := Time.get_ticks_usec()
		player.seek(.013 + float((index * 17) % 113) / 120.0, true)
		seek_usec += Time.get_ticks_usec() - seek_started
	native_report.timings.append({"pass": pass_index, "round": round_index, "compact": compact,
		"use_copy": not raw_repeat_only and not in_place_test and pass_index in [1, 2], "copy_only": copy_only, "in_place_test": in_place_test,
		"mode": "mixed_clip" if mixed else "same_idle", "calls": 200, "clip_changes": clip_changes,
		"seek_usec": seek_usec, "select_usec": select_usec, "whole_usec": Time.get_ticks_usec() - began})
	_deadline()
