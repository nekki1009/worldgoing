extends "res://scripts/tests/site_army_exact_seek_test.gd"
## GPU --group=0: exact keys, original pose restoration, owner invalidation.
## GPU --group=1: 129 actual armor queries exercise the independent 128 cap.
## Original raw meshes/AnimationPlayer, 23-second internal / helper 25 seconds.

var armor_exact_cases := 0
var armor_original_usec := 0
var armor_repeated_usec := 0

func run() -> void:
	create_timer(23.0).timeout.connect(func() -> void: quit(1))
	assert(DisplayServer.get_name() != "headless", "Original armor morph queries require the GPU verifier")
	assert(group in [0, 1] and TerrainArmy.load_combat_bake())
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
	var source := Source.new()
	assert(source.initialize(root, baseline, actor.editor))
	var editor_id := source.editor.get_instance_id()
	var skeleton_id := source.skeleton.get_instance_id()
	var recipe := baseline.duplicate(true)
	if group == 0:
		recipe.parts.armor = "armor_mingguang_01"
		recipe.parts.helmet = "helmet_mingguang_01"
		recipe.parts.outfit = "outfit_chinese_lining_01"
		recipe.parts.boots = "boots_mingguang_01"
	var sample: Dictionary = source.sample(&"walk_slash", 0.517, Vector2i.RIGHT, Vector2.ZERO, 0.0, recipe)
	assert(not sample.is_empty())
	var request: Array = [&"walk_slash", 0.517, Vector2i.RIGHT, Vector2.ZERO, 0.0,
		recipe, centre(sample.body[3]), "slash"]
	if group == 0:
		_contract(source, baseline, request, sample)
	else:
		_limit(source, request)
	assert(source.editor.get_instance_id() == editor_id and source.skeleton.get_instance_id() == skeleton_id)
	assert(source._armor_queries.size() <= 128)
	var report := {"group": group, "exact_cases": armor_exact_cases, "max_error": 0.0,
		"original_query_usec": armor_original_usec, "repeated_query_usec": armor_repeated_usec,
		"query_profile": source.query_profile.duplicate(),
		"source_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_contact_source.gd"),
		"test_sha256": FileAccess.get_sha256("res://scripts/tests/site_army_armor_query_reuse_test.gd"),
		"scope": "Same-step exact armor result reuse after original pose restoration; no triangle, precision, time or person changes; not FPS"}
	var path := "res://output/site_combat_performance_20260913/armor_query_reuse/group_%d.json" % group
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	source.dispose()
	assert(source._armor_queries.is_empty())
	actor.queue_free()
	await process_frame
	print("SITE_ARMY_ARMOR_QUERY_REUSE_PASS ", JSON.stringify(report))
	quit(0)

func _armor(source: Variant, request: Array) -> Vector2:
	return source.armor_at(request[0], request[1], request[2], request[6], request[7], request[3], request[4], request[5])

func _miss_then_hit(source: Variant, request: Array) -> Vector2:
	# Disabled is the unchanged original Geometry.armor_at call, never a cache.
	source.armor_query_reuse_enabled = false
	var hits: int = source.query_profile.armor_hits
	var calls: int = source.query_profile.armor_calls
	var started := Time.get_ticks_usec()
	var expected := _armor(source, request)
	armor_original_usec += Time.get_ticks_usec() - started
	assert(int(source.query_profile.armor_hits) == hits and int(source.query_profile.armor_calls) == calls + 1)
	source.armor_query_reuse_enabled = true
	assert(_armor(source, request) == expected)
	assert(int(source.query_profile.armor_hits) == hits, "A distinct exact key or cleared step must miss")
	var geometry_usec: int = source.query_profile.armor_geometry_usec
	started = Time.get_ticks_usec()
	assert(_armor(source, request) == expected)
	armor_repeated_usec += Time.get_ticks_usec() - started
	assert(int(source.query_profile.armor_hits) == hits + 1)
	assert(int(source.query_profile.armor_geometry_usec) == geometry_usec, "A hit performs no armor triangle query")
	assert(int(source.query_profile.armor_calls) == calls + 3)
	armor_exact_cases += 1
	return expected

func _contract(source: Variant, baseline: Dictionary, request: Array, sample: Dictionary) -> void:
	source.begin_contact_step()
	var requests: Array[Array] = [request.duplicate(true)]
	var nearby: Array = request.duplicate(true)
	nearby[6] = Vector2(_next_float32(request[6].x), request[6].y)
	assert(nearby[6] != request[6], "The nearby point must really differ by one stored float32 ULP")
	requests.append(nearby)
	var kind: Array = request.duplicate(true)
	kind[7] = "stab"
	requests.append(kind)
	var changed_recipe: Array = request.duplicate(true)
	changed_recipe[5] = missing_recipe(baseline, 31)
	changed_recipe[5].parts.helmet = "none"
	requests.append(changed_recipe)
	var time: Array = request.duplicate(true)
	time[1] = _next_float64(request[1])
	assert(time[1] != request[1])
	requests.append(time)
	var direction: Array = request.duplicate(true)
	direction[2] = Vector2i.LEFT
	requests.append(direction)
	var aim: Array = request.duplicate(true)
	aim[3] = Vector2(1.0, 0.0) # Still a distinct exact key even at weight zero.
	requests.append(aim)
	var weight: Array = request.duplicate(true)
	weight[3] = Vector2(21.0, -54.0)
	weight[4] = 0.5
	requests.append(weight)
	var clip: Array = request.duplicate(true)
	clip[0] = &"guard"
	requests.append(clip)
	for entry: Array in requests:
		_miss_then_hit(source, entry)
	# The original branch provides the complete live A reference. Keep its
	# existing memo entry while collecting the reference with reuse disabled.
	source.armor_query_reuse_enabled = false
	_armor(source, request)
	var expected := _snapshot(source, request[5], request, sample)
	source.armor_query_reuse_enabled = true
	assert(not source.sample(&"get_up", 0.337, Vector2i.DOWN, Vector2.ZERO, 0.0, changed_recipe[5]).is_empty())
	var prior_key: Array = source._key.duplicate(true)
	var evaluations: int = source.query_profile.true_pose_evaluations
	var hits: int = source.query_profile.armor_hits
	var geometry_usec: int = source.query_profile.armor_geometry_usec
	assert(_armor(source, request) == expected.protection[1]) # Arm index 3.
	assert(int(source.query_profile.armor_hits) == hits + 1)
	assert(int(source.query_profile.armor_geometry_usec) == geometry_usec)
	assert(int(source.query_profile.true_pose_evaluations) == evaluations + 1 and source._key != prior_key,
		"Cached armor A must still restore the original live model from B")
	assert(_snapshot(source, request[5], request, sample) == expected,
		"Cached armor restores every original bone, scalar morph, armor vertex and protection exactly")
	armor_exact_cases += 1
	source.begin_contact_step()
	assert(source._armor_queries.is_empty())
	_miss_then_hit(source, request)
	source.clear_samples() # The canonical equipment-change invalidation owner.
	assert(source._armor_queries.is_empty())
	_miss_then_hit(source, request)
	# A caller mutating its original recipe cannot alter retained value keys.
	source.begin_contact_step()
	var mutable: Array = request.duplicate(true)
	var original_helmet: String = mutable[5].parts.helmet
	var original := _miss_then_hit(source, mutable)
	mutable[5].parts.helmet = "none"
	_miss_then_hit(source, mutable)
	mutable[5].parts.helmet = original_helmet
	hits = int(source.query_profile.armor_hits)
	assert(_armor(source, mutable) == original and int(source.query_profile.armor_hits) == hits + 1)
	var malformed: Array = request.duplicate(true)
	malformed[5].parts.erase("boots")
	var entries: int = source._armor_queries.size()
	hits = int(source.query_profile.armor_hits)
	assert(_armor(source, malformed) == Vector2.ZERO)
	assert(source._armor_queries.size() == entries and int(source.query_profile.armor_hits) == hits)
	# The existing raw-generation replacement calls the same full clear. Do not
	# invent another model/animation mutation path just to invalidate this memo.
	source._copy_private_animations()
	assert(source._armor_queries.is_empty() and source._key.is_empty())

func _limit(source: Variant, request: Array) -> void:
	source.begin_contact_step()
	for index in range(129):
		var entry: Array = request.duplicate(true)
		entry[6] = request[6] + Vector2(float(index) * 0.125, 0.0)
		_miss_then_hit(source, entry)
		assert(source._armor_queries.size() == (index + 1 if index < 128 else 1))
	# The overflow retained only query 129; a genuinely old point recomputes.
	_miss_then_hit(source, request)
	assert(source._armor_queries.size() == 2)

func _next_float32(value: float) -> float:
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes.encode_float(0, value)
	var bits := bytes.decode_u32(0)
	bytes.encode_u32(0, bits + (1 if value >= 0.0 else -1))
	return bytes.decode_float(0)

func _next_float64(value: float) -> float:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	bytes.encode_u64(0, bytes.decode_u64(0) + 1)
	return bytes.decode_double(0)
