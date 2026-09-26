extends SceneTree
const Batch = preload("res://scripts/terrain_lab/terrain_army_batch_view.gd")
const RESULT := "res://output/site_army_5k_hot_close_20260926/retained_batch_smoke.json"
var comparisons := 0
var mismatches := 0
var assertions := {}
var counter_samples := {}

func _check(name: String, value: bool) -> void:
	assertions[name] = value
	if not value: push_error("Retained batch check failed: " + name)

func _write_result(status: String) -> void:
	var paths := {"presenter": "res://scripts/terrain_lab/terrain_army_batch_view.gd",
		"army": "res://scripts/terrain_lab/terrain_army.gd",
		"native_source": "res://native/army_idle/army_idle.cpp",
		"native_dll": "res://native/army_idle/bin/army_idle.windows.x86_64.dll",
		"fixture": "res://scripts/tests/site_army_retained_batch_test.gd"}
	var hashes := {}
	for key: String in paths: hashes[key] = FileAccess.get_sha256(paths[key])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RESULT.get_base_dir()))
	var output := FileAccess.open(RESULT, FileAccess.WRITE)
	if output == null:
		push_error("Cannot write retained batch smoke result")
		return
	output.store_string(JSON.stringify({"status": status, "engine": Engine.get_version_info().string,
		"sources": hashes, "comparisons": comparisons, "mismatches": mismatches,
		"assertions": assertions, "counters": counter_samples}, "\t"))

func _initialize() -> void:
	_run.call_deferred()

func _state(view: Node2D) -> PackedByteArray:
	var rows := {}
	var row_keys: Array = view._rows.keys()
	row_keys.sort()
	for row: int in row_keys: rows[row] = view._rows[row]
	var runs := {}
	var keys: Array = view._batches.keys()
	keys.sort()
	for key: Vector2i in keys:
		var node: MultiMeshInstance2D = view._batches[key]
		if node.visible:
			runs[key] = [node.multimesh.buffer, node.multimesh.custom_aabb]
	return var_to_bytes([view._positions, view._sequence, view._frames, view._page,
		view._palette, rows, runs, view.rendered_count, view.active_batches])

func _fresh(army: TerrainArmy, grounds: Array, appearances: Array, clips: Array,
		directions: Array, times: PackedFloat64Array, sprites: Dictionary) -> Node2D:
	var view := Batch.new()
	root.add_child(view)
	view.setup(army, grounds.size())
	view.begin()
	for index in range(grounds.size()):
		if sprites.has(index):
			var sprite := Sprite2D.new()
			root.add_child(sprite)
			view.submit_sprite(index, grounds[index], sprite)
		else:
			assert(view.submit(index, grounds[index], appearances[index], clips[index], directions[index], times[index]))
	view.flush()
	return view

func _same_as_fresh(view: Node2D, army: TerrainArmy, grounds: Array, appearances: Array,
		clips: Array, directions: Array, times: PackedFloat64Array, sprites: Dictionary, stage: String) -> void:
	var expected := _fresh(army, grounds, appearances, clips, directions, times, sprites)
	comparisons += 1
	var same := _state(view) == _state(expected)
	assertions["exact_" + stage] = same
	if not same:
		mismatches += 1
		print("RETAINED_MISMATCH_CHECK=", comparisons)
		for field: String in ["_positions", "_sequence", "_frames", "_page", "_palette", "_rows", "rendered_count", "active_batches"]:
			if view.get(field) != expected.get(field): print("RETAINED_MISMATCH_FIELD=", field, " got=", view.get(field), " expected=", expected.get(field))
		for key: Vector2i in view._batches:
			var left: MultiMeshInstance2D = view._batches[key]
			var right: MultiMeshInstance2D = expected._batches.get(key)
			if right == null or left.visible != right.visible or left.multimesh.buffer != right.multimesh.buffer or left.multimesh.custom_aabb != right.multimesh.custom_aabb:
				print("RETAINED_MISMATCH_RUN=", key, " visible=", left.visible, " expected_visible=", right.visible if right != null else null)
	expected.free()

func _native_retained_check(army: TerrainArmy) -> void:
	var site := SiteController.new()
	root.add_child(site)
	army._soldier_baked_ready = true
	army.equipment_appearance_query = site.person_appearance
	army.equipment_appearance_batch_query = site.person_appearance_batch
	var appearance: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
	SiteController._freeze_appearance(appearance)
	var grounds := []
	var appearances := []
	var clips := []
	var directions := []
	var times := PackedFloat64Array()
	var view := Batch.new()
	root.add_child(view)
	view.setup(army, 6)
	view.retained_enabled = true
	view.mechanism_enabled = true
	for index in range(6):
		army.combat_units.append({"person_id": index + 1, "age": 0.0, "pose": "idle", "visual_role": "male_atlas"})
		army.cells.append(Vector2i(index + 10, 10))
		army.moving_to.append(TerrainArmy.INVALID_CELL)
		army.facing.append(Vector2i.DOWN)
		army._sprites.append(null)
		site._equipment_appearances[index + 1] = appearance
		grounds.append((Vector2(army.cells[index]) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS)
		appearances.append(appearance)
		clips.append("combat_idle")
		directions.append("down")
		times.append(0.0)
		assert(view.submit(index, grounds[index], appearance, "combat_idle", "down", 0.0))
	view.begin()
	view.prepare_idle()
	_check("native_initial_admission", view._native_mask == PackedByteArray([1, 1, 1, 1, 1, 1]))
	view.finish_prepared_groups()
	view.flush()
	var full_counters: Dictionary = view.mechanism_stats()
	counter_samples["full_reference"] = full_counters
	_check("full_reference_observed", full_counters.static_observations > 0 and full_counters.ground_projections > 0)
	_same_as_fresh(view, army, grounds, appearances, clips, directions, times, {}, "native_initial")
	var page: Dictionary = view._pages[view._page[0]]
	var samples: Array = page.samples[view._sequence[0]]
	assert(samples.size() > 1)
	times.fill(float(samples[1].sample_time))
	_check("native_begin_retained", view.begin_retained())
	_check("native_frame_changed_six", view.sample_retained_animations(times) == 6)
	view.flush_retained()
	var native_counters: Dictionary = view.mechanism_stats()
	counter_samples["native_frame"] = native_counters
	_check("native_frame_no_static", native_counters.static_observations == 0 and native_counters.ground_projections == 0)
	_same_as_fresh(view, army, grounds, appearances, clips, directions, times, {}, "native_frame")
	view.free()
	site.free()

func _run() -> void:
	_write_result("RUNNING")
	var army := TerrainArmy.new()
	root.add_child(army)
	army.set_process(false)
	assert(TerrainArmy.load_combat_bake() and army._load_baked_soldier())
	var view := Batch.new()
	root.add_child(view)
	view.setup(army, 6)
	view.retained_enabled = true
	view.mechanism_enabled = true
	var base: Dictionary = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
	var bow: Dictionary = base.duplicate(true)
	bow.parts.weapon = "bow_01"
	bow.parts.shield = "none"
	var grounds: Array = []
	var appearances: Array = []
	var clips: Array = []
	var directions: Array = []
	var times := PackedFloat64Array()
	var sprites := {3: true}
	view.begin()
	for index in range(6):
		grounds.append(Vector2(320 + index * 8, 352))
		appearances.append(base)
		clips.append("combat_walk" if index == 5 else "combat_idle")
		directions.append("down")
		times.append(0.0)
		if sprites.has(index):
			var sprite := Sprite2D.new()
			root.add_child(sprite)
			view.submit_sprite(index, grounds[index], sprite)
		else: assert(view.submit(index, grounds[index], appearances[index], clips[index], directions[index], 0.0))
	view.flush()
	_check("initial_batch_count", view.rendered_count == 5 and view.active_batches == 2)
	_same_as_fresh(view, army, grounds, appearances, clips, directions, times, sprites, "initial")
	var original := _state(view)
	for idle_tick in 2:
		_check("unchanged_begin_%d" % idle_tick, view.begin_retained())
		_check("unchanged_animation_%d" % idle_tick, view.sample_retained_animations(times) == 0)
		view.flush_retained()
		var counters: Dictionary = view.mechanism_stats()
		counter_samples["unchanged_%d" % idle_tick] = counters
		_check("unchanged_no_static_%d" % idle_tick, counters.static_observations == 0 and counters.ground_projections == 0)
		_check("unchanged_no_regroup_%d" % idle_tick, counters.row_rebuilds == 0 and counters.run_rebuilds == 0)
		_check("unchanged_no_upload_%d" % idle_tick, counters.packed_instances == 0 and counters.packed_bytes == 0 and counters.multimesh_bytes == 0 and counters.gpu_dispatches == 0)
		_check("unchanged_exact_%d" % idle_tick, _state(view) == original)
	grounds[1].x += 1.0
	_check("single_begin", view.begin_retained())
	assert(view.submit(1, grounds[1], appearances[1], clips[1], directions[1], times[1]))
	view.flush_retained()
	counter_samples["single_ground"] = view.mechanism_stats()
	_check("single_ground_one_run", view.mechanism_stats().row_rebuilds == 0 and view.mechanism_stats().packed_instances > 0)
	_same_as_fresh(view, army, grounds, appearances, clips, directions, times, sprites, "single_ground")
	grounds[2].y += 64.0
	_check("cross_row_begin", view.begin_retained())
	assert(view.submit(2, grounds[2], appearances[2], clips[2], directions[2], times[2]))
	view.flush_retained()
	counter_samples["cross_row"] = view.mechanism_stats()
	_check("cross_row_two_rebuilds", view.mechanism_stats().row_rebuilds == 2)
	_same_as_fresh(view, army, grounds, appearances, clips, directions, times, sprites, "cross_row")
	appearances[4] = bow
	_check("page_begin", view.begin_retained())
	assert(view.submit(4, grounds[4], appearances[4], clips[4], directions[4], times[4]))
	view.flush_retained()
	counter_samples["page"] = view.mechanism_stats()
	_check("page_changed", view._page[4] != view._page[0])
	_same_as_fresh(view, army, grounds, appearances, clips, directions, times, sprites, "page")
	sprites[1] = true
	_check("sprite_begin", view.begin_retained())
	var inserted_sprite := Sprite2D.new()
	root.add_child(inserted_sprite)
	view.submit_sprite(1, grounds[1], inserted_sprite)
	view.flush_retained()
	counter_samples["sprite"] = view.mechanism_stats()
	_same_as_fresh(view, army, grounds, appearances, clips, directions, times, sprites, "sprite")
	var one_page: Dictionary = view._pages[view._page[0]]
	var one_samples: Array = one_page.samples[view._sequence[0]]
	assert(one_samples.size() > 1)
	times[0] = float(one_samples[1].sample_time)
	var eligible := PackedByteArray()
	eligible.resize(6)
	eligible[0] = 1
	_check("filtered_begin", view.begin_retained())
	_check("filtered_one_frame", view.sample_retained_animations(times, eligible) == 1)
	view.flush_retained()
	counter_samples["filtered_frame"] = view.mechanism_stats()
	_check("filtered_one_sample", view.mechanism_stats().animation_samples == 1 and view.mechanism_stats().static_observations == 0)
	_same_as_fresh(view, army, grounds, appearances, clips, directions, times, sprites, "filtered_frame")
	for index in range(6):
		if sprites.has(index): continue
		var page: Dictionary = view._pages[view._page[index]]
		var samples: Array = page.samples[view._sequence[index]]
		assert(samples.size() > 1)
		times[index] = float(samples[1].sample_time)
	_check("frame_begin", view.begin_retained())
	_check("frame_changed", view.sample_retained_animations(times) > 0)
	view.flush_retained()
	counter_samples["frame"] = view.mechanism_stats()
	_check("frame_no_static_or_regroup", view.mechanism_stats().static_observations == 0 and view.mechanism_stats().ground_projections == 0 and view.mechanism_stats().row_rebuilds == 0)
	_same_as_fresh(view, army, grounds, appearances, clips, directions, times, sprites, "frame")
	_native_retained_check(army)
	var failed := mismatches > 0
	for value: bool in assertions.values():
		if not value: failed = true
	_write_result("FAIL" if failed else "PASS")
	if failed:
		push_error("Retained batch checks failed in %d of %d exact comparisons" % [mismatches, comparisons])
		quit(1)
		return
	print("ARMY_RETAINED_BATCH_PASS unchanged/static/single-row/cross-row/page/Sprite/frame-anchor")
	view.free()
	army.free()
	quit()
