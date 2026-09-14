extends "res://scripts/tests/site_army_held_state_reuse_test.gd"
## GPU: original key construction versus the one immutable baseline value key.
## --appearance-validation: independent last-valid appearance A/B; baseline key stays enabled.
## --validated-key: existing full validation/copy stays enabled; only its immutable key switches A/B.
## Full existing bone/morph/armor/sample snapshots compare exactly. Not FPS.

func run() -> void:
	create_timer(23.0).timeout.connect(func() -> void: quit(1))
	assert(DisplayServer.get_name() != "headless" and TerrainArmy.load_combat_bake())
	var validated_key_mode := "--validated-key" in OS.get_cmdline_user_args()
	var validation_mode := validated_key_mode or "--appearance-validation" in OS.get_cmdline_user_args()
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
	assert(source._validated_appearance.is_empty() and source._validated_appearance_key.is_empty())
	assert(source._baseline_key.is_read_only())
	var retained: Array = source._baseline_key
	var expected_key := retained.duplicate()
	var reordered := _reverse_dictionary(baseline)
	reordered.parts = _reverse_dictionary(baseline.parts)
	assert(reordered == baseline and reordered.keys() != baseline.keys())
	var timing := _validation_checks(source, baseline) if validation_mode else _key_checks(source, baseline, reordered)
	var validated_key_timing: Array[Dictionary] = _validated_key_checks(source, baseline) if validated_key_mode else []
	var initial_morphs := _morphs(source.editor)
	var requests: Array = [
		[&"idle", 0.019, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline],
		[&"walk_slash", 0.537, Vector2i.DOWN, Vector2(21, -54), 0.5, reordered],
		[&"guard", 0.073, Vector2i.UP, Vector2.ZERO, 0.0, baseline],
		[&"rescue", 1.137, Vector2i.LEFT, Vector2.ZERO, 0.0, baseline],
		[&"walk_slash", 0.517, Vector2i.RIGHT, Vector2.ZERO, 0.0, baseline]]
	if validation_mode:
		# The real m25 visible loadout: original sword/outfit/boots, no shield/armor.
		requests.append([&"guard", 0.091, Vector2i.DOWN, Vector2.ZERO, 0.0, missing_recipe(baseline, 6)])
	if validated_key_mode:
		var appearance_a := missing_recipe(baseline, 6)
		var reordered_a := _reverse_dictionary(appearance_a)
		reordered_a.parts = _reverse_dictionary(appearance_a.parts)
		var appearance_b := appearance_a.duplicate(true)
		appearance_b.parts.weapon = "none"
		var extra := appearance_a.duplicate(true)
		extra["query_extension"] = {"values": [1, 2]}
		for recipe: Dictionary in [reordered_a, appearance_b, appearance_a, extra]:
			requests.append([&"guard", 0.091, Vector2i.DOWN, Vector2.ZERO, 0.0, recipe])
	var expected: Array[Dictionary] = []
	var passes: Array[Dictionary] = []
	for pass_index in range(2):
		source.baseline_key_reuse_enabled = validation_mode or pass_index == 1
		source.appearance_validation_reuse_enabled = validation_mode and (validated_key_mode or pass_index == 1)
		source.validated_key_reuse_enabled = validated_key_mode and pass_index == 1
		for path: NodePath in initial_morphs:
			var mesh := source.editor.model_root.get_node(path) as MeshInstance3D
			for shape in range(initial_morphs[path].size()):
				mesh.set_blend_shape_value(shape, initial_morphs[path][shape])
		source.clear_samples()
		source._key.clear()
		assert(not source.sample(&"walk", 0.011, Vector2i.LEFT, Vector2.ZERO, 0.0, baseline).is_empty())
		var started := Time.get_ticks_usec()
		var snapshots: Array[Dictionary] = []
		for request: Array in requests:
			snapshots.append(_key_snapshot(source, request))
		# The SAME caller Dictionary becomes B and then A, without clearing the
		# source's existing A entry. Reusing caller identity would fail this path.
		var mutable := baseline.duplicate(true)
		var request: Array = [&"guard", 0.083, Vector2i.DOWN, Vector2.ZERO, 0.0, mutable]
		snapshots.append(_key_snapshot(source, request))
		mutable.parts.shield = "none"
		snapshots.append(_key_snapshot(source, request))
		assert(snapshots[-1].sample.shield.is_empty() and not snapshots[-1].sample.parry.is_empty())
		mutable.parts.weapon = "none"
		snapshots.append(_key_snapshot(source, request))
		assert(snapshots[-1].sample.parry.is_empty())
		mutable.parts = baseline.parts.duplicate(true)
		snapshots.append(_key_snapshot(source, request))
		assert(snapshots[-1] == snapshots[requests.size()], "A remains unchanged after caller B and re-equipping")
		assert(source.sample(request[0], request[1], request[2]) == snapshots[-1].sample,
			"The empty appearance argument still means the initialization baseline")
		for index in range(snapshots.size()):
			if pass_index == 0:
				expected.append(snapshots[index])
			else:
				for field: String in expected[index]:
					assert(snapshots[index][field] == expected[index][field],
						"Canonical key changed exact snapshot %d / %s" % [index, field])
		passes.append({"reuse_enabled": source.baseline_key_reuse_enabled,
			"appearance_validation_reuse_enabled": source.appearance_validation_reuse_enabled,
			"validated_key_reuse_enabled": source.validated_key_reuse_enabled,
			"elapsed_usec": Time.get_ticks_usec() - started, "exact_snapshots": snapshots.size()})
	assert(source._baseline == baseline and retained == expected_key)
	var report := {"key_timing": timing, "geometry_passes": passes, "max_error": 0.0,
		"source_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_contact_source.gd"),
		"test_sha256": FileAccess.get_sha256("res://scripts/tests/site_army_baseline_key_test.gd"),
		"scope": "Single original source A/B; canonical key, complete six-field pose key, exact bones/morphs/armor/sample and protection; not FPS"}
	if validation_mode:
		report.scope = "Last fully validated appearance deep copy only; original complete validation on value changes. Same original source and complete geometry snapshots, malformed/caller mutation/lifecycle checks; not FPS or formal atlas admission."
		report["validation_timing"] = report.key_timing
		report.erase("key_timing")
	if validated_key_mode:
		report.scope = "One existing fully validated nonbaseline copy and its immutable canonical key; validation enabled in both geometry passes, exact sample/bones/morphs/armor/protection, caller mutation/reorder/A-B-A/allowed extra fields and original lifecycle; not FPS."
		report["validated_key_timing"] = validated_key_timing
	var validation_copy: Dictionary = source._validated_appearance
	var validation_before := validation_copy.duplicate(true)
	var validation_key: Array = source._validated_appearance_key
	var validation_key_before := validation_key.duplicate()
	if validated_key_mode:
		assert(validation_key.is_read_only() and not validation_key.is_empty())
	source.dispose()
	assert(source._baseline_key.is_empty() and source._recipe_key.is_empty() and source._validated_appearance.is_empty() and source._validated_appearance_key.is_empty())
	assert(retained == expected_key, "Dispose must not mutate keys already retained by a caller")
	assert(validation_key == validation_key_before)
	if validation_mode:
		assert(validation_copy == validation_before and not validation_copy.is_empty())
		assert(not source.supports_appearance(validation_copy), "A disposed model cannot reuse a previously valid appearance")
		await process_frame
		assert(source.initialize(root, baseline, actor.editor) and source._validated_appearance.is_empty() and source._validated_appearance_key.is_empty())
		assert(source.supports_appearance(validation_copy) and source._validated_appearance == validation_copy)
		if validated_key_mode:
			var reinitialized_key: Array = source._appearance_key(validation_copy)
			assert(reinitialized_key.is_read_only() and reinitialized_key == validation_key_before and not is_same(reinitialized_key, validation_key))
		source.dispose()
		assert(source._validated_appearance.is_empty() and source._validated_appearance_key.is_empty() and validation_copy == validation_before and validation_key == validation_key_before)
	var output_kind := "validated_key" if validated_key_mode else ("appearance_validation" if validation_mode else "baseline_key")
	var path := "res://output/site_combat_performance_20260913/%s/%d_%d/measurements.json" % [output_kind, int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	actor.queue_free()
	await process_frame
	print("SITE_ARMY_VALIDATED_KEY_PASS " if validated_key_mode else ("SITE_ARMY_APPEARANCE_VALIDATION_PASS " if validation_mode else "SITE_ARMY_BASELINE_KEY_PASS "), JSON.stringify(report))
	quit(0)

func _validated_key_checks(source: Variant, baseline: Dictionary) -> Array[Dictionary]:
	source.appearance_validation_reuse_enabled = true
	source.clear_samples()
	var appearance := missing_recipe(baseline, 6)
	var original := appearance.duplicate(true)
	assert(source.supports_appearance(appearance))
	source.validated_key_reuse_enabled = false
	var expected: Array = source._appearance_key(appearance)
	assert(not expected.is_read_only() and source._validated_appearance_key.is_empty())
	source.validated_key_reuse_enabled = true
	var retained: Array = source._appearance_key(appearance)
	assert(retained == expected and retained.is_read_only() and is_same(retained, source._validated_appearance_key))
	var retained_copy: Dictionary = source._validated_appearance
	var reordered := _reverse_dictionary(appearance)
	reordered.parts = _reverse_dictionary(appearance.parts)
	assert(source.supports_appearance(reordered) and is_same(source._validated_appearance, retained_copy))
	assert(is_same(source._appearance_key(reordered), retained), "Structural equality includes reordered dictionaries")
	source.begin_contact_step()
	assert(is_same(source._validated_appearance_key, retained))
	assert(source.supports_appearance() and is_same(source._appearance_key(baseline), source._baseline_key))
	assert(is_same(source._validated_appearance_key, retained), "Baseline queries do not replace the last validated copy/key")
	# Caller mutation cannot mutate a retained key or bypass original validation.
	appearance.parts.weapon = "__invalid_component"
	assert(not source.supports_appearance(appearance))
	assert(source.sample(&"guard", 0.091, Vector2i.DOWN, Vector2.ZERO, 0.0, appearance).is_empty())
	assert(retained == expected and is_same(source._validated_appearance_key, retained))
	appearance.parts.weapon = "none"
	assert(source.supports_appearance(appearance) and source._validated_appearance_key.is_empty())
	var key_b: Array = source._appearance_key(appearance)
	assert(key_b.is_read_only() and key_b != retained and retained == expected)
	appearance.parts.weapon = original.parts.weapon
	assert(source.supports_appearance(appearance) and source._validated_appearance_key.is_empty())
	var key_a_again: Array = source._appearance_key(appearance)
	assert(key_a_again == retained and key_a_again.is_read_only() and not is_same(key_a_again, retained))
	# The original validator admits extra top-level fields. A changed full value
	# replaces the validation owner even when the original canonical key is equal.
	var extra := appearance.duplicate(true)
	extra["query_extension"] = {"values": [1]}
	assert(HumanCharacter3DEditor.valid_appearance(extra) and source.supports_appearance(extra))
	assert(source._validated_appearance_key.is_empty())
	var extra_key: Array = source._appearance_key(extra)
	assert(extra_key == retained and extra_key.is_read_only() and not is_same(extra_key, key_a_again))
	extra.query_extension["values"].append(2)
	assert(source._validated_appearance.query_extension["values"] == [1])
	assert(source.supports_appearance(extra) and source._validated_appearance_key.is_empty())
	assert(source._appearance_key(extra) == extra_key and not is_same(source._validated_appearance_key, extra_key))
	assert(extra_key == expected and retained == expected)
	# A/B toggles change only key allocation, never the validated copy or values.
	source.validated_key_reuse_enabled = false
	var uncached: Array = source._appearance_key(extra)
	assert(uncached == extra_key and not uncached.is_read_only())
	source.validated_key_reuse_enabled = true
	assert(source._appearance_key(extra).is_read_only())
	source.clear_samples()
	assert(source._validated_appearance.is_empty() and source._validated_appearance_key.is_empty() and retained == expected)
	assert(source.supports_appearance(original) and source._appearance_key(original).is_read_only())
	source._copy_private_animations()
	assert(source._validated_appearance.is_empty() and source._validated_appearance_key.is_empty() and retained == expected,
		"The original raw-animation replacement invalidates both values through clear_samples")
	var passes: Array[Dictionary] = []
	for enabled: bool in [false, true]:
		source.validated_key_reuse_enabled = enabled
		source.clear_samples()
		assert(source.supports_appearance(original))
		var first_key: Array = source._appearance_key(original)
		assert(first_key == expected and first_key.is_read_only() == enabled)
		var started := Time.get_ticks_usec()
		var values := 0
		for index in range(41501):
			var recipe: Dictionary = original if index % 2 == 0 else reordered
			assert(source.supports_appearance(recipe))
			values += source._appearance_key(recipe).size()
		passes.append({"validated_key_reuse_enabled": enabled, "calls": 41501,
			"elapsed_usec": Time.get_ticks_usec() - started, "key_values": values,
			"retained_nonbaseline_keys": int(not source._validated_appearance_key.is_empty())})
	assert(passes[0].key_values == passes[1].key_values)
	source.clear_samples()
	return passes

func _validation_checks(source: Variant, baseline: Dictionary) -> Array[Dictionary]:
	var appearance := missing_recipe(baseline, 6)
	var expected_copy := appearance.duplicate(true)
	source.appearance_validation_reuse_enabled = true
	assert(source.supports_appearance(appearance))
	var retained: Dictionary = source._validated_appearance
	assert(not is_same(retained, appearance) and not is_same(retained.parts, appearance.parts))
	var reordered := _reverse_dictionary(appearance)
	reordered.parts = _reverse_dictionary(appearance.parts)
	assert(source.supports_appearance(reordered) and is_same(source._validated_appearance, retained))
	source.begin_contact_step()
	assert(is_same(source._validated_appearance, retained), "The fixed original model survives ordinary contact-step clears")
	assert(source.supports_appearance() and is_same(source._validated_appearance, retained), "Baseline does not replace the single nonbaseline copy")
	appearance.parts.weapon = "__invalid_component"
	assert(not source.supports_appearance(appearance) and retained == expected_copy)
	appearance.parts.weapon = "none"
	assert(source.supports_appearance(appearance) and source._validated_appearance == appearance and retained == expected_copy)
	appearance.parts.weapon = expected_copy.parts.weapon
	assert(source.supports_appearance(appearance) and source._validated_appearance == expected_copy and not is_same(source._validated_appearance, retained), "A to B to A replaces one entry, never retains a caller alias or multi-recipe table")
	# Unknown top-level fields are allowed by the ORIGINAL validator. They must
	# miss the previous exact copy, not be silently dropped or newly rejected.
	var extra := appearance.duplicate(true)
	extra["query_extension"] = {"values": [1]}
	assert(source.supports_appearance(extra) and source._validated_appearance == extra)
	extra.query_extension["values"].append(2)
	assert(source._validated_appearance.query_extension["values"] == [1])
	assert(source.supports_appearance(extra) and source._validated_appearance.query_extension["values"] == [1, 2])
	var malformed: Array[Dictionary] = []
	for field: String in appearance:
		var missing := appearance.duplicate(true)
		missing.erase(field)
		malformed.append(missing)
		var wrong := appearance.duplicate(true)
		wrong[field] = []
		malformed.append(wrong)
	for slot: String in appearance.parts:
		var missing := appearance.duplicate(true)
		missing.parts.erase(slot)
		malformed.append(missing)
		var wrong := appearance.duplicate(true)
		wrong.parts[slot] = "__invalid_component"
		malformed.append(wrong)
	var extra_part := appearance.duplicate(true)
	extra_part.parts["__extra_slot"] = "none"
	malformed.append(extra_part)
	var mounted := appearance.duplicate(true)
	mounted.mounted = true
	malformed.append(mounted)
	malformed.append(HumanCharacter3DEditor.default_appearance(1 - int(baseline.body)))
	for rejected: Dictionary in malformed:
		source.appearance_validation_reuse_enabled = false
		assert(not source.supports_appearance(rejected))
		source.appearance_validation_reuse_enabled = true
		assert(source.supports_appearance(appearance))
		var before: Dictionary = source._validated_appearance
		var pose_key: Array = source._key.duplicate(true)
		assert(not source.supports_appearance(rejected))
		assert(source.sample(&"idle", 0.019, Vector2i.DOWN, Vector2.ZERO, 0.0, rejected).is_empty())
		assert(source.armor_at(&"idle", 0.019, Vector2i.DOWN, Vector2.ZERO, "slash", Vector2.ZERO, 0.0, rejected) == Vector2.ZERO)
		assert(is_same(source._validated_appearance, before) and source._key == pose_key, "Rejected fields cannot reach key construction or alter the validated copy")
	source.clear_samples()
	assert(source._validated_appearance.is_empty() and retained == expected_copy)
	var passes: Array[Dictionary] = []
	for enabled: bool in [false, true]:
		source.appearance_validation_reuse_enabled = enabled
		source.clear_samples()
		var started := Time.get_ticks_usec()
		var accepted := 0
		for index in range(41501):
			accepted += int(source.supports_appearance(appearance if index % 2 == 0 else reordered))
		assert(accepted == 41501)
		passes.append({"appearance_validation_reuse_enabled": enabled, "calls": 41501,
			"elapsed_usec": Time.get_ticks_usec() - started, "accepted": accepted,
			"malformed_cases": malformed.size(), "retained_nonbaseline_copies": int(not source._validated_appearance.is_empty())})
	source.clear_samples()
	return passes

func _reverse_dictionary(original: Dictionary) -> Dictionary:
	var result := {}
	var keys := original.keys()
	keys.reverse()
	for key: Variant in keys:
		result[key] = original[key]
	return result

func _key_checks(source: Variant, baseline: Dictionary, reordered: Dictionary) -> Array[Dictionary]:
	var recipes: Array[Dictionary] = [baseline, baseline.duplicate(true), reordered]
	for mask in range(32):
		recipes.append(missing_recipe(baseline, mask))
	for field: String in ["body", "hair_mask", "hair_dye", "hair_dyed", "mounted", "coat", "tack"]:
		var changed := baseline.duplicate(true)
		if field == "body":
			changed[field] = 1 - int(changed[field])
		elif typeof(changed[field]) == TYPE_BOOL:
			changed[field] = not bool(changed[field])
		else:
			changed[field] = str(changed[field]) + "_changed"
		# Pure key checks, not admitting malformed recipes to the model owner.
		recipes.append(changed)
	for recipe: Dictionary in recipes:
		source.baseline_key_reuse_enabled = false
		var expected: Array = source._appearance_key(recipe)
		source.baseline_key_reuse_enabled = true
		var actual: Array = source._appearance_key(recipe)
		assert(actual == expected)
		assert(actual.is_read_only() == (recipe == baseline))
	var mutable := baseline.duplicate(true)
	var before: Array = source._appearance_key(mutable)
	mutable.parts.shield = "none"
	assert(source._appearance_key(mutable) != before and before == source._baseline_key)
	mutable.parts.shield = baseline.parts.shield
	assert(source._appearance_key(mutable) == before)
	var passes: Array[Dictionary] = []
	for reuse: bool in [false, true]:
		source.baseline_key_reuse_enabled = reuse
		var started := Time.get_ticks_usec()
		var total := 0
		for index in range(36826):
			var key: Array = source._appearance_key(baseline if index % 2 == 0 else reordered)
			total += key.size()
		passes.append({"reuse_enabled": reuse, "calls": 36826,
			"elapsed_usec": Time.get_ticks_usec() - started, "key_values": total})
	assert(passes[0].key_values == passes[1].key_values)
	return passes

func _key_snapshot(source: Variant, request: Array) -> Dictionary:
	var query: Dictionary = source.sample(request[0], request[1], request[2], request[3], request[4], request[5])
	assert(not query.is_empty())
	var key: Array = [request[0], request[1], request[2], request[3], request[4], source._appearance_key(request[5])]
	assert(key.size() == 6 and source._poses.has(key), "Retain all original exact pose inputs")
	# Sample cache hits intentionally leave the one editor at B. Restore A using
	# its original protection owner before reading live bones and scalar morphs.
	source.armor_at(request[0], request[1], request[2], centre(query.body[0]), "slash", request[3], request[4], request[5])
	var snapshot := _snapshot(source, request[5], request, query)
	snapshot.camera = [source.editor.camera.transform, source.editor.camera.size, source.sprite.transform]
	snapshot.appearance = source.editor.capture_appearance()
	return snapshot
