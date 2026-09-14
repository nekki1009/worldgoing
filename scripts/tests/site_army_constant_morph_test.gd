extends "res://scripts/tests/site_army_exact_seek_test.gd"
## --native: pure native Animation guards/interpolation, internal 23s/helper 25s.
## GPU --group=0/1: all-library preservation plus same-source full exact history,
## internal 53s/helper 55s. Initialization/key counts are not gameplay/FPS evidence.

var morph_deadline_usec := 0
var morph_report := {"guards": 0, "native_samples": 0, "exact_snapshots": 0}

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--group="):
			group = argument.trim_prefix("--group=").to_int()
	call_deferred("run")

func _deadline() -> void:
	assert(Time.get_ticks_usec() < morph_deadline_usec, "Constant morph bounded test deadline")

func run() -> void:
	var native_only := "--native" in OS.get_cmdline_user_args()
	var limit := 23.0 if native_only else 53.0
	morph_deadline_usec = Time.get_ticks_usec() + int(limit * 1000000.0)
	create_timer(limit).timeout.connect(func() -> void: quit(1))
	if native_only:
		_native_guards()
	else:
		assert(DisplayServer.get_name() != "headless" and group in [0, 1])
		await _source_history()
		if not bool(morph_report.get("history_completed", false)):
			quit(1) # A nested assertion must not fall through to a misleading PASS label.
			return
	_deadline()
	morph_report["mode"] = "native" if native_only else "gpu_group_%d" % group
	morph_report["source_sha256"] = FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_contact_source.gd")
	morph_report["scope"] = "Private exact +0 morph key compaction; all numeric value bits and all path/type metadata retained; excludes NodePath padding bytes; not FPS or atlas acceptance"
	var directory := "res://output/site_combat_performance_20260913/constant_morph/%s_%d" % [str(int(Time.get_unix_time_from_system())), Time.get_ticks_usec()]
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK)
	var file := FileAccess.open(directory + "/measurements.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(morph_report, "\t"))
	file.close()
	print("SITE ARMY CONSTANT MORPH PASS ", JSON.stringify(morph_report))
	quit(0)

func _bits(value: float) -> PackedByteArray:
	return PackedFloat64Array([value]).to_byte_array()

func _path_metadata(path: NodePath) -> Array:
	var names: Array[String] = []
	var subnames: Array[String] = []
	for index in range(path.get_name_count()):
		names.append(str(path.get_name(index)))
	for index in range(path.get_subname_count()):
		subnames.append(str(path.get_subname(index)))
	return [TYPE_NODE_PATH, str(path), path.is_absolute(), names, subnames]

func _array_metadata(value: Array) -> Array:
	return [value.is_typed(), value.get_typed_builtin(), value.get_typed_class_name(), value.get_typed_script()]

func _dictionary_metadata(value: Dictionary) -> Array:
	return [value.get_typed_key_builtin(), value.get_typed_key_class_name(), value.get_typed_key_script(),
		value.get_typed_value_builtin(), value.get_typed_value_class_name(), value.get_typed_value_script()]

func _digest_value(hash_state: HashingContext, value: Variant) -> void:
	assert(hash_state.update(var_to_bytes(typeof(value))) == OK)
	if value is NodePath:
		assert(hash_state.update(var_to_bytes(_path_metadata(value))) == OK)
	elif value is Dictionary:
		assert(hash_state.update(var_to_bytes([value.size(), _dictionary_metadata(value)])) == OK)
		for key: Variant in value:
			_digest_value(hash_state, key)
			_digest_value(hash_state, value[key])
	elif value is Array:
		assert(hash_state.update(var_to_bytes([value.size(), _array_metadata(value)])) == OK)
		for entry: Variant in value:
			_digest_value(hash_state, entry)
	else:
		assert(hash_state.update(_bits(value) if typeof(value) == TYPE_FLOAT else var_to_bytes(value)) == OK)

func _byte_record(expected: Variant, actual: Variant, path: String, reason: String) -> Dictionary:
	var before := _bits(expected) if typeof(expected) == TYPE_FLOAT else var_to_bytes(_path_metadata(expected) if expected is NodePath else expected)
	var after := _bits(actual) if typeof(actual) == TYPE_FLOAT else var_to_bytes(_path_metadata(actual) if actual is NodePath else actual)
	var offset := 0
	while offset < mini(before.size(), after.size()) and before[offset] == after[offset]:
		offset += 1
	return {"path": path, "reason": reason, "expected_type": type_string(typeof(expected)),
		"actual_type": type_string(typeof(actual)), "expected_value": str(expected).left(160), "actual_value": str(actual).left(160),
		"numeric_equal": typeof(expected) == typeof(actual) and expected == actual, "expected_size": before.size(), "actual_size": after.size(), "byte_offset": offset,
		"expected_hex": before.slice(maxi(0, offset - 8), offset + 16).hex_encode(),
		"actual_hex": after.slice(maxi(0, offset - 8), offset + 16).hex_encode()}

func _snapshot_byte_diff(expected: Variant, actual: Variant, path: String, differences: Array[Dictionary]) -> void:
	if differences.size() >= 24:
		return
	if typeof(expected) != typeof(actual):
		differences.append(_byte_record(expected, actual, path, "variant_type"))
		return
	if expected is NodePath:
		if _path_metadata(expected) != _path_metadata(actual):
			differences.append(_byte_record(expected, actual, path, "node_path_names_subnames_absolute_type"))
		return
	var container := expected is Dictionary or expected is Array
	if not container and (_bits(expected) == _bits(actual) if typeof(expected) == TYPE_FLOAT else var_to_bytes(expected) == var_to_bytes(actual)):
		return
	var found_before := differences.size()
	if expected is Dictionary:
		# Keep insertion order and typed metadata; compare path keys by actual
		# content, not the native encoder's uninitialized NodePath alignment bytes.
		if var_to_bytes(_dictionary_metadata(expected)) != var_to_bytes(_dictionary_metadata(actual)):
			differences.append(_byte_record(_dictionary_metadata(expected), _dictionary_metadata(actual), path, "dictionary_type_metadata"))
		var expected_keys: Array = expected.keys()
		var actual_keys: Array = actual.keys()
		for index in range(maxi(expected_keys.size(), actual_keys.size())):
			if differences.size() >= 24:
				return
			if index >= expected_keys.size() or index >= actual_keys.size():
				differences.append(_byte_record(expected_keys.size(), actual_keys.size(), path + ".keys.size", "dictionary_key_count"))
				break
			_snapshot_byte_diff(expected_keys[index], actual_keys[index], path + ".keys[%d]" % index, differences)
		for key: Variant in expected_keys:
			if actual.has(key):
				_snapshot_byte_diff(expected[key], actual[key], path + "[%s]" % str(key), differences)
	elif expected is Array:
		var expected_info := _array_metadata(expected)
		var actual_info := _array_metadata(actual)
		if var_to_bytes(expected_info) != var_to_bytes(actual_info):
			differences.append(_byte_record(expected_info, actual_info, path, "array_type_metadata"))
		if expected.size() != actual.size():
			differences.append(_byte_record(expected.size(), actual.size(), path + ".size", "array_size"))
		for index in range(mini(expected.size(), actual.size())):
			_snapshot_byte_diff(expected[index], actual[index], path + "[%d]" % index, differences)
	elif expected is PackedFloat32Array or expected is PackedFloat64Array or expected is PackedVector2Array or expected is PackedVector3Array or expected is PackedVector4Array:
		if expected.size() != actual.size():
			differences.append(_byte_record(expected.size(), actual.size(), path + ".size", "packed_size"))
		for index in range(mini(expected.size(), actual.size())):
			_snapshot_byte_diff(expected[index], actual[index], path + "[%d]" % index, differences)
	elif expected is Vector2:
		_snapshot_byte_diff(expected.x, actual.x, path + ".x", differences)
		_snapshot_byte_diff(expected.y, actual.y, path + ".y", differences)
	elif expected is Vector3:
		_snapshot_byte_diff(expected.x, actual.x, path + ".x", differences)
		_snapshot_byte_diff(expected.y, actual.y, path + ".y", differences)
		_snapshot_byte_diff(expected.z, actual.z, path + ".z", differences)
	elif expected is Vector4 or expected is Quaternion:
		for component: String in ["x", "y", "z", "w"]:
			_snapshot_byte_diff(expected[component], actual[component], path + "." + component, differences)
	elif expected is Basis:
		for axis: int in range(3):
			_snapshot_byte_diff(expected[axis], actual[axis], path + ".axis[%d]" % axis, differences)
	elif expected is Transform3D:
		_snapshot_byte_diff(expected.basis, actual.basis, path + ".basis", differences)
		_snapshot_byte_diff(expected.origin, actual.origin, path + ".origin", differences)
	elif expected is Transform2D:
		for column: int in range(3):
			_snapshot_byte_diff(expected[column], actual[column], path + ".column[%d]" % column, differences)
	elif expected is Rect2:
		_snapshot_byte_diff(expected.position, actual.position, path + ".position", differences)
		_snapshot_byte_diff(expected.size, actual.size, path + ".size", differences)
	if not container and differences.size() == found_before:
		differences.append(_byte_record(expected, actual, path, "scalar_bits_or_container_encoding"))

func _metadata(animation: Animation, track: int) -> Array:
	return [animation.track_get_type(track), animation.track_get_path(track), animation.track_is_enabled(track),
		animation.track_is_imported(track), animation.track_get_interpolation_type(track),
		animation.track_get_interpolation_loop_wrap(track), animation.track_is_compressed(track)]

func _digest(animation: Animation) -> String:
	# Native values, not JSON equality: retain -0/every key bit and full path
	# content. NodePath's native marshaler leaves alignment padding unwritten.
	var hash_state := HashingContext.new()
	assert(hash_state.start(HashingContext.HASH_SHA256) == OK)
	for property: Dictionary in animation.get_property_list():
		var property_name := str(property.name)
		if property_name.begins_with("tracks/") or property_name in ["length", "loop_mode", "step", "markers", "_compression"]:
			_digest_value(hash_state, [property_name, animation.get(property_name)])
	return hash_state.finish().hex_encode()

func _player_digest(player: AnimationPlayer) -> Dictionary:
	var result := {}
	for clip: StringName in player.get_animation_list():
		_deadline()
		result[clip] = _digest(player.get_animation(clip))
	return result

func _fixture() -> Animation:
	var animation := Animation.new()
	animation.length = 1.0
	animation.loop_mode = Animation.LOOP_LINEAR
	var track := animation.add_track(Animation.TYPE_BLEND_SHAPE)
	animation.track_set_path(track, NodePath("ActualOriginalMesh:OriginalMorph"))
	animation.track_set_enabled(track, false) # Hidden/disabled tracks are retained too.
	animation.track_set_imported(track, true)
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
	for time: float in [0.0, 0.375, 1.0]:
		animation.blend_shape_track_insert_key(track, time, 0.0)
	return animation

func _check_native(original: Animation, expected_count: int, interpolate: bool = true) -> Animation:
	_deadline()
	var original_digest := _digest(original)
	var candidate := original.duplicate(true) as Animation
	var source := Source.new()
	source.constant_morph_keys_enabled = false
	source._compact_constant_morph_keys(candidate)
	assert(_digest(original) == original_digest, "The native reference resource is never edited")
	assert(candidate.get_track_count() == original.get_track_count())
	assert(candidate.length == original.length and candidate.loop_mode == original.loop_mode and candidate.step == original.step)
	for track in range(original.get_track_count()):
		assert(_metadata(original, track) == _metadata(candidate, track))
	assert(candidate.track_get_key_count(0) == expected_count)
	if expected_count == original.track_get_key_count(0):
		assert(_digest(candidate) == original_digest, "Rejected curves preserve every original value bit and full path metadata")
	else:
		assert(candidate.track_get_key_time(0, 0) == original.track_get_key_time(0, 0))
		assert(candidate.track_get_key_transition(0, 0) == original.track_get_key_transition(0, 0))
		assert(_bits(candidate.track_get_key_value(0, 0)) == _bits(original.track_get_key_value(0, 0)))
	if interpolate:
		_native_samples(original, candidate, 0)
	morph_report.guards += 1
	return candidate

func _native_samples(original: Animation, candidate: Animation, track: int) -> void:
	# Includes original endpoints, non-key fractions, reverse lookup and loop edges.
	for time: float in [-0.001, 0.0, 0.000001, 0.137, 0.375, 0.719, 0.999999, 1.0, 1.001]:
		for backward: bool in [false, true]:
			var expected := original.blend_shape_track_interpolate(track, time * original.length, backward)
			var actual := candidate.blend_shape_track_interpolate(track, time * original.length, backward)
			assert(_bits(actual) == _bits(expected), "Native interpolation must be bitwise equal, including signed zero")
			morph_report.native_samples += 1

func _native_guards() -> void:
	_node_path_oracle()
	var negative_zero := PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128]).decode_double(0)
	assert(negative_zero == 0.0 and _bits(negative_zero) != _bits(0.0))
	for interpolation: int in [Animation.INTERPOLATION_LINEAR, Animation.INTERPOLATION_NEAREST]:
		for loop: int in [Animation.LOOP_NONE, Animation.LOOP_LINEAR, Animation.LOOP_PINGPONG]:
			for wrap: bool in [false, true]:
				var animation := _fixture()
				animation.loop_mode = loop
				animation.track_set_interpolation_type(0, interpolation)
				animation.track_set_interpolation_loop_wrap(0, wrap)
				_check_native(animation, 1)
	for rejected: float in [negative_zero, 0.0000001, -0.0000001, NAN, INF, -INF]:
		var animation := _fixture()
		animation.track_set_key_value(0, 1, rejected)
		assert(_bits(animation.track_get_key_value(0, 1)) != _bits(0.0))
		_check_native(animation, 3, false)
	for interpolation: int in [Animation.INTERPOLATION_CUBIC, Animation.INTERPOLATION_CUBIC_ANGLE, Animation.INTERPOLATION_LINEAR_ANGLE]:
		var animation := _fixture()
		animation.track_set_interpolation_type(0, interpolation)
		_check_native(animation, 3)
	for transition: float in [0.0, 0.5, 2.0, NAN, INF]:
		var animation := _fixture()
		animation.track_set_key_transition(0, 1, transition)
		_check_native(animation, 3, false)
	# The native storage setter can represent malformed order that insert_key
	# would sort/replace. It exercises the real reader, not an Animation mock.
	for times: Array in [[0.25, 0.5, 1.0], [0.0, 0.0, 1.0], [0.0, 0.75, 0.5],
		[0.0, 0.5, 1.5], [0.0, NAN, 1.0], [0.0, INF, 1.0]]:
		var animation := _fixture()
		animation.set("tracks/0/keys", PackedFloat32Array([times[0], 1.0, 0.0, times[1], 1.0, 0.0, times[2], 1.0, 0.0]))
		_check_native(animation, 3, false)
	var one := _fixture()
	one.track_remove_key(0, 2)
	one.track_remove_key(0, 1)
	_check_native(one, 1)
	one.track_remove_key(0, 0)
	_check_native(one, 0, false)
	var compressed := _fixture()
	compressed.compress()
	assert(compressed.track_is_compressed(0), "Use an actual native compressed track")
	_check_native(compressed, compressed.track_get_key_count(0), false)
	var mixed := _fixture()
	var position := mixed.add_track(Animation.TYPE_POSITION_3D)
	mixed.track_set_path(position, NodePath("Skeleton3D:Hips"))
	mixed.position_track_insert_key(position, 0.0, Vector3.ZERO)
	mixed.position_track_insert_key(position, 1.0, Vector3.ZERO)
	var candidate := _check_native(mixed, 1)
	assert(var_to_bytes(mixed.get("tracks/1/keys")) == var_to_bytes(candidate.get("tracks/1/keys")))
	_copy_flag_guard()

func _node_path_oracle() -> void:
	# Godot 4.6.2 marshalls.cpp NodePath encoding advances across pad bytes
	# without writing them. Repeated same-value bytes may depend on allocator
	# history; this diagnostic does not require nondeterminism on every machine.
	var path := NodePath("Armature/Skeleton3D/Armor_Mingguang_01_Skirt_Rim_L:OriginalMorph")
	var expected := _path_metadata(path)
	var native_variants := {}
	var first := var_to_bytes(path)
	for index in range(64):
		var churn := PackedByteArray()
		churn.resize(first.size())
		churn.fill((index * 17) % 256)
		churn = PackedByteArray()
		var encoded := var_to_bytes(path)
		native_variants[encoded.hex_encode()] = true
		assert(_path_metadata(bytes_to_var(encoded)) == expected)
		var differences: Array[Dictionary] = []
		_snapshot_byte_diff(path, NodePath(str(path)), "$same_path", differences)
		assert(differences.is_empty())
	for changed: Variant in [str(path), NodePath("/" + str(path)), NodePath(str(path) + "B"), NodePath(str(path) + ":another")]:
		var differences: Array[Dictionary] = []
		_snapshot_byte_diff(path, changed, "$changed_path", differences)
		assert(not differences.is_empty(), "All path types/names/subnames/absolute flags remain exact")
	var negative_zero := PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128]).decode_double(0)
	for pair: Array in [[0.0, negative_zero], [Vector2(0.0, 1.0), Vector2(negative_zero, 1.0)],
		[PackedFloat64Array([0.0]), PackedFloat64Array([negative_zero])]]:
		var differences: Array[Dictionary] = []
		_snapshot_byte_diff({path: pair[0]}, {path: pair[1]}, "$signed_zero", differences)
		assert(not differences.is_empty(), "Ignoring only NodePath padding must not admit a single numeric sign-bit change")
	var animation := _fixture()
	var digest := _digest(animation)
	for index in range(16):
		assert(_digest(animation) == digest)
	morph_report.node_path_oracle = {"repeated_native_encodes": 64, "distinct_native_byte_sequences": native_variants.size(),
		"native_examples": native_variants.keys().slice(0, 3), "semantic_path_exact": true, "negative_zero_rejected": true}
	print("NODE PATH NATIVE PADDING DIAGNOSTIC ", JSON.stringify(morph_report.node_path_oracle))

func _copy_flag_guard() -> void:
	var source := Source.new()
	source.constant_morph_keys_enabled = false
	source.editor = Source.ComponentQueryEditor.new()
	source.editor.animation_player = AnimationPlayer.new()
	source.editor.add_child(source.editor.animation_player)
	assert(source.editor.animation_player.add_animation_library(&"", AnimationLibrary.new()) == OK)
	var reference := AnimationPlayer.new()
	var library := AnimationLibrary.new()
	var animation := _fixture()
	assert(library.add_animation(&"probe", animation) == OK)
	assert(reference.add_animation_library(&"", library) == OK)
	var before := _digest(animation)
	source._copy_private_animations(reference)
	assert(_digest(source.editor.animation_player.get_animation(&"probe")) == before)
	source.constant_morph_keys_enabled = true
	source._copy_private_animations(reference)
	assert(source.editor.animation_player.get_animation(&"probe").track_get_key_count(0) == 1)
	assert(_digest(animation) == before)
	source.editor.free()
	source.editor = null
	reference.free()
	morph_report.guards += 1

func _audit_library(reference: AnimationPlayer, player: AnimationPlayer, compact: bool) -> Dictionary:
	var counts := {"clips": 0, "tracks": 0, "original_keys": 0, "private_keys": 0, "compacted_tracks": 0}
	assert(reference.get_animation_list() == player.get_animation_list())
	for clip: StringName in reference.get_animation_list():
		_deadline()
		var original := reference.get_animation(clip)
		var candidate := player.get_animation(clip)
		assert(original != candidate and original.get_track_count() == candidate.get_track_count())
		assert(original.length == candidate.length and original.loop_mode == candidate.loop_mode and original.step == candidate.step)
		counts.clips += 1
		for track in range(original.get_track_count()):
			assert(_metadata(original, track) == _metadata(candidate, track), "Every track/path/enabled/loop/interpolation remains original")
			var original_count := original.track_get_key_count(track)
			var private_count := candidate.track_get_key_count(track)
			counts.tracks += 1
			counts.original_keys += original_count
			counts.private_keys += private_count
			if original.track_is_compressed(track):
				assert(original_count == private_count)
				assert(var_to_bytes(original.get("_compression")) == var_to_bytes(candidate.get("_compression")))
				assert(original.get("tracks/%d/compressed_track" % track) == candidate.get("tracks/%d/compressed_track" % track))
			elif original_count == private_count:
				assert(var_to_bytes(original.get("tracks/%d/keys" % track)) == var_to_bytes(candidate.get("tracks/%d/keys" % track)))
			else:
				assert(compact and private_count == 1 and original_count > 1 and original.track_get_type(track) == Animation.TYPE_BLEND_SHAPE)
				assert(candidate.track_get_key_time(track, 0) == original.track_get_key_time(track, 0))
				assert(candidate.track_get_key_transition(track, 0) == original.track_get_key_transition(track, 0))
				assert(_bits(candidate.track_get_key_value(track, 0)) == _bits(original.track_get_key_value(track, 0)))
				_native_samples(original, candidate, track)
				counts.compacted_tracks += 1
	return counts

func _source_history() -> void:
	assert(TerrainArmy.load_combat_bake())
	var baseline: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
	var actor := TerrainTestCharacter.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.initialize_visual()
	assert(actor.editor != null and actor.editor.restore_appearance(baseline))
	actor.editor.set_process(false)
	actor.editor.combat_ready = true
	actor.editor.visual_state.combat_ready = true
	actor.editor.set_playing(false)
	var original_hashes := _player_digest(actor.editor.animation_player)
	var source := Source.new()
	source.constant_morph_keys_enabled = false
	var started := Time.get_ticks_usec()
	assert(source.initialize(root, baseline, actor.editor) and not source.constant_morph_keys_enabled)
	morph_report.initialize_usec = Time.get_ticks_usec() - started
	source.terminal_cache_enabled = false
	var original_editor_id := source.editor.get_instance_id()
	var original_skeleton_id := source.skeleton.get_instance_id()
	var down_end: float = source.editor.animation_player.get_animation(&"down").length
	var metal := baseline.duplicate(true)
	metal.parts.armor = "armor_mingguang_01"
	metal.parts.helmet = "helmet_mingguang_01"
	metal.parts.outfit = "outfit_chinese_lining_01"
	metal.parts.boots = "boots_mingguang_01"
	var requests: Array = [[metal, &"down", down_end, Vector2i.RIGHT],
		[missing_recipe(baseline, 31), &"walk_slash", 0.537, Vector2i.UP],
		[metal, &"down", down_end, Vector2i.RIGHT], [metal, &"down", 0.319, Vector2i.LEFT],
		[metal, &"get_up", 0.337, Vector2i.DOWN], [baseline, &"unconscious", 0.173, Vector2i.RIGHT],
		[missing_recipe(baseline, 2), &"guard", 0.073, Vector2i.LEFT], [baseline, &"walk_slash", 0.613, Vector2i.RIGHT]]
	if group == 1:
		requests.clear()
		for weapon: String in ["longsword_01", "spear_01", "bow_01", "crossbow_01", "none"]:
			var appearance := metal.duplicate(true)
			appearance.parts.weapon = weapon
			appearance.parts.shield = "none"
			assert(source.supports_appearance(appearance))
			requests.append([appearance, &"attack", 0.537, Vector2i.RIGHT])
			requests.append([appearance, &"guard", 0.093, Vector2i.LEFT])
	var expected: Array[Dictionary] = []
	for pass_index in range(2):
		_deadline()
		if pass_index == 1:
			source.constant_morph_keys_enabled = true
			started = Time.get_ticks_usec()
			source._copy_private_animations(actor.editor.animation_player)
			morph_report.compact_copy_usec = Time.get_ticks_usec() - started
		var counts := _audit_library(actor.editor.animation_player, source.editor.animation_player, pass_index == 1)
		assert(counts.compacted_tracks > 0 if pass_index == 1 else counts.compacted_tracks == 0)
		morph_report["private_compact" if pass_index == 1 else "private_original"] = counts
		# Same original owner, initial clip/reset and random seed for both passes;
		# only private Animation keys differ. Preserve every intervening request.
		seed(581)
		source.editor._selected_animation = &""
		assert(source.editor.select_animation_by_id(&"idle"))
		source.skeleton.reset_bone_poses()
		source.clear_samples()
		assert(not source.sample(&"idle", 0.019, Vector2i.DOWN, Vector2.ZERO, 0.0, baseline).is_empty())
		for index in range(requests.size()):
			_deadline()
			var request: Array = requests[index]
			var appearance: Dictionary = request[0]
			var aim := Vector2(1.0, -0.17) if index == requests.size() - 1 else Vector2.ZERO
			var weight := 0.25 if aim != Vector2.ZERO else 0.0
			source.clear_samples() # Result caches cannot conceal native evaluation.
			var sample := source.sample(request[1], request[2], request[3], aim, weight, appearance)
			assert(not sample.is_empty())
			var snapshot := _snapshot(source, appearance, [request[1], request[2], request[3], aim, weight], sample)
			if pass_index == 0:
				expected.append(snapshot)
			else:
				assert(snapshot == expected[index], "Every exact local/global bone, all authored morphs, worn armor vertices, sample field and protection result must match")
				var differences: Array[Dictionary] = []
				_snapshot_byte_diff(expected[index], snapshot, "$", differences)
				if not differences.is_empty():
					print("CONSTANT MORPH SNAPSHOT VALUE DIFFERENCE ", JSON.stringify({"group": group, "request_index": index,
						"clip": request[1], "time": request[2], "direction": str(request[3]), "parts": appearance.parts,
						"first_differences": differences}))
				assert(differences.is_empty(), "All numeric value bits including signed zero and all path/type metadata must match")
				morph_report.exact_snapshots += 1
	assert(source.editor.get_instance_id() == original_editor_id and source.skeleton.get_instance_id() == original_skeleton_id)
	assert(_player_digest(actor.editor.animation_player) == original_hashes, "Original native animation library value bits and full path metadata must remain exact after all copies/poses")
	source.dispose()
	actor.queue_free()
	morph_report.history_completed = true
	await process_frame
