extends "res://scripts/tests/site_army_query_bounds_test.gd"
## GPU --group=0 (real ordered queries/movement and warmed local timing)
## or --group=1 (promotion/value mutation/overflow/source replacement).
## Original four-row fixture; 53-second monotonic deadline / helper 55 seconds.
## No damage/clock/rig substitute. This candidate starts OFF in production.

var checks := 0
var measurements: Array = []

func _initialize() -> void:
	started_usec = Time.get_ticks_usec()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--group="):
			group = argument.trim_prefix("--group=").to_int()
	output_directory = "res://output/site_combat_performance_20260913/pose_result_reuse/group%d/%d_%d" % [group, int(Time.get_unix_time_from_system()), started_usec]
	run.call_deferred()

func _check_deadline() -> bool:
	return not failed and _check(Time.get_ticks_usec() - started_usec < 53000000, "53-second monotonic wall deadline")

func _begin_results(enabled: bool, inputs: bool = false) -> bool:
	fixture_lab._end_army_contact_inputs()
	fixture_lab._army_contact_geometry.clear()
	TerrainArmy.begin_contact_step()
	TerrainArmy._contact_source.same_batch_result_reuse_enabled = enabled
	fixture_lab.contact_input_reuse_enabled = inputs
	fixture_lab._sampling_army_contacts = true
	fixture_lab._begin_army_contact_inputs()
	if not _check((not primary._contact_batch_pose_results.is_empty()) == enabled and (not primary._contact_batch_inputs.is_empty()) == inputs,
		"Result and input switches independently bind the original Lab target slots"):
		return false
	if enabled:
		var slots: Array = fixture_lab._army_contact_geometry[["targets", primary.get_instance_id()]]
		if not _check(is_same(slots, primary._contact_batch_pose_results), "No second target cache owner"):
			return false
	return _check_deadline()

func _end_results() -> bool:
	fixture_lab._end_army_contact_inputs()
	fixture_lab._sampling_army_contacts = false
	fixture_lab._army_contact_geometry.clear()
	return _check(primary._contact_batch_pose_results.is_empty() and primary._contact_batch_inputs.is_empty(), "End detaches all borrowed references before resolution or mutation")

func _source_state() -> Dictionary:
	var source: Variant = TerrainArmy._contact_source
	var bones: Array = []
	for index: int in source.skeleton.get_bone_count():
		bones.append([source.skeleton.get_bone_pose_position(index), source.skeleton.get_bone_pose_rotation(index), source.skeleton.get_bone_pose_scale(index)])
	var morphs: Array = []
	for node: Node in source.editor._combat_mesh_nodes("*"):
		var mesh := node as MeshInstance3D
		var values: Array = []
		for index: int in mesh.get_blend_shape_count():
			values.append(mesh.get_blend_shape_value(index))
		morphs.append([str(mesh.name), mesh.visible, values])
	return {"key": source._key.duplicate(true), "bones": bones, "morphs": morphs, "rotation": source.editor.preview_pivot.rotation}

func _ordered_case(label: String, index: int) -> bool:
	probe_label = label
	var requests := _raw_requests(index)
	var before_state := _state()
	var expected := {}
	var profiles: Array = []
	for mode: int in 3: # Old, results alone, results plus separately approved inputs.
		_cold_geometry()
		if not _begin_results(mode > 0, mode == 2):
			return false
		var before := _profile()
		var ordered: Array = []
		for request: Array in requests:
			ordered.append(_ordered_values(_collect(request)))
			primary.combat_shapes(3, "body") # Original A -> B -> A interleave.
			primary.combat_bounds(index)
		var full := _full_geometry()
		var actual := {"ordered": ordered, "full": full, "heads": _head_fits(), "source": _source_state()}
		if mode == 0:
			expected = actual
		elif not _check(_exact(actual, expected), "Full ordered contacts, source history and numeric bits changed", {"mode": mode, "contacts": actual.ordered == expected.ordered, "geometry": actual.full == expected.full, "source": actual.source == expected.source}):
			return false
		profiles.append({"mode": mode, "before": before, "after": _profile()})
		if not _end_results() or not _check(_exact(_state(), before_state) and _owners_unchanged(), "Query must preserve the original rows, items and live female owner"):
			return false
		if not _check_deadline():
			return false
	measurements.append({"case": label, "profiles": profiles, "exact": true})
	checks += 1
	return true

func _timing() -> bool:
	# Same warmed workload in alternating order. Includes live input/value-copy
	# costs; excludes initialization. Local CPU diagnostic, never an FPS claim.
	_set_pose(1, "idle", 0.317)
	var runs: Array = []
	for enabled: bool in [false, true, true, false, false, true]:
		if not _begin_results(enabled):
			return false
		var expected := primary._continuous_pose(1, false).duplicate(true)
		var source: Variant = TerrainArmy._contact_source
		var before: int = source.query_profile.sample_calls
		var ticks := Time.get_ticks_usec()
		var result := {}
		for index: int in 1000:
			result = primary._continuous_pose(1, false)
		var elapsed := Time.get_ticks_usec() - ticks
		var calls: int = int(source.query_profile.sample_calls) - before
		if not _check(_exact(result, expected) and calls == (0 if enabled else 1000), "Warmed same-batch calls must actually bypass Source only in candidate mode"):
			return false
		runs.append({"enabled": enabled, "calls": 1000, "source_calls": calls, "elapsed_usec": elapsed})
		if not _end_results() or not _check_deadline():
			return false
	measurements.append({"case": "warmed_same_batch_1000_calls", "runs": runs, "scope": "Local existing Army wrapper/Source call cost, no renderer/FPS prediction"})
	return true

func _promotion_and_mutation() -> bool:
	probe_label = "partial_full_history_mutation"
	var expected: Array = []
	for enabled: bool in [false, true]:
		_set_pose(1, "idle", 0.317)
		_set_pose(3, "rescue", 1.137)
		_cold_geometry()
		if not _begin_results(enabled):
			return false
		var source: Variant = TerrainArmy._contact_source
		var samples: Array = []
		var partial := primary._continuous_pose(1, false)
		if not _check(not partial.has("weapon"), "Original inactive bound-only request must omit weapon"):
			return false
		samples.append(partial.duplicate(true))
		primary._continuous_pose(3, false)
		var before: int = source.query_profile.sample_calls
		var full := primary._continuous_pose(1, true)
		if not _check(full.has("weapon") and not full.weapon.is_empty() and int(source.query_profile.sample_calls) == before + 1, "A partial -> B -> full A must restore the original source and fill real weapon"):
			return false
		samples.append(full.duplicate(true))
		samples.append(_source_state())
		primary.combat_units[1].age = 0.411 # Actual live value change, with inputs independently OFF.
		before = source.query_profile.sample_calls
		samples.append(primary._continuous_pose(1, false).duplicate(true))
		if not _check(int(source.query_profile.sample_calls) == before + 1, "Changed sample cannot reuse old row result"):
			return false
		# Override only the original appearance provider's returned fixture value;
		# mutate that same Dictionary to prove retained keys are value copies.
		var original_query: Callable = primary.equipment_appearance_query
		var appearance := primary.equipment_appearance(1)
		primary.equipment_appearance_query = func(_identity: int) -> Dictionary: return appearance
		primary._continuous_pose(1, true)
		appearance.parts.weapon = "none"
		before = source.query_profile.sample_calls
		var unarmed := primary._continuous_pose(1, true)
		primary.equipment_appearance_query = original_query
		if not _check(int(source.query_profile.sample_calls) == before + 1 and not _exact(unarmed.weapon, full.weapon), "In-place caller recipe mutation must not retain the original sword"):
			return false
		samples.append(unarmed.duplicate(true))
		# Eligibility stays live: same pose values but blocked status changed.
		_set_pose(1, "walk_slash", 1.4, true)
		primary.facing[1] = Vector2i.UP
		primary.combat_units[1].blocked = true
		var blocked := primary._continuous_pose(1, false)
		if not _check(not blocked.has("weapon"), "Blocked attacker initially requests only original hurt geometry"):
			return false
		primary.combat_units[1].blocked = false
		before = source.query_profile.sample_calls
		var active := primary._continuous_pose(1, false)
		if not _check(active.has("weapon") and int(source.query_profile.sample_calls) == before + 1, "Do not retain mutable weapon eligibility"):
			return false
		samples.append(active.duplicate(true))
		if not enabled:
			expected = samples
		elif not _check(_exact(samples, expected), "Promotion/mutation full original geometry bits differ"):
			return false
		if not _end_results() or not _check_deadline():
			return false
	checks += 1
	return true

func _overflow() -> bool:
	probe_label = "128_original_cache_overflow"
	var expected: Array = []
	for enabled: bool in [false, true]:
		_set_pose(1, "idle", 0.317)
		_cold_geometry()
		if not _begin_results(enabled):
			return false
		var source: Variant = TerrainArmy._contact_source
		var start_generation: int = source.pose_cache_generation
		var original := primary._continuous_pose(1, false).duplicate(true)
		var samples: Array = []
		var clip := StringName(str(primary.contact_sample(1)[0]))
		var duration: float = source.editor.animation_player.get_animation(clip).length
		for index: int in 128:
			# Real distinct native times, not fabricated cache entries.
			samples.append(source.sample(clip, duration * float(index + 1) / 256.0, Vector2i.RIGHT, Vector2.ZERO, 0.0, {}, false).duplicate(true))
			if not _check_deadline():
				return false
		if not _check(source.pose_cache_generation == start_generation + 1 and source._poses.size() == 1, "129 actual keys must perform the original single 128-entry full clear"):
			return false
		var before: int = source.query_profile.sample_calls
		var restored := primary._continuous_pose(1, false)
		if not _check(int(source.query_profile.sample_calls) == before + 1 and _exact(restored, original), "Old borrowed result must not bypass the post-eviction re-seek"):
			return false
		samples.append(_source_state())
		if not enabled:
			expected = samples
		elif not _check(_exact(samples, expected), "Overflow sequence changed original full geometry or pose history"):
			return false
		if not _end_results():
			return false
	checks += 1
	return true

func _boundaries() -> bool:
	probe_label = "terminal_nextstep_and_nonbatch"
	_set_pose(1, "down", 10.0)
	_cold_geometry()
	if not _begin_results(true):
		return false
	var source: Variant = TerrainArmy._contact_source
	var original := primary._continuous_pose(1, false).duplicate(true)
	primary._continuous_pose(3, false)
	var key: Array = source._key.duplicate(true)
	var before: int = source.query_profile.sample_calls
	if not _check(_exact(primary._continuous_pose(1, false), original) and source.query_profile.sample_calls == before and _exact(source._key, key), "Terminal result reuse must not pretend current B changed back to A"):
		return false
	var generation: int = source.pose_cache_generation
	source.begin_contact_step()
	if not _check(source.pose_cache_generation == generation + 1, "Every begin_contact_step invalidates borrowed results"):
		return false
	before = source.query_profile.sample_calls
	if not _check(_exact(primary._continuous_pose(1, false), original) and source.query_profile.sample_calls == before + 1, "Next generation must call the original terminal path"):
		return false
	if not _end_results():
		return false
	fixture_lab._begin_army_contact_inputs() # Outside actual sampling cannot bind.
	before = source.query_profile.sample_calls
	primary._continuous_pose(1, false)
	primary._continuous_pose(1, false)
	if not _check(primary._contact_batch_pose_results.is_empty() and int(source.query_profile.sample_calls) == before + 2, "Direct nonbatch queries keep the original public Source path"):
		return false
	var terminal_sample: Array = primary.contact_sample(1)
	var first: Dictionary = source.sample(terminal_sample[0], terminal_sample[1], terminal_sample[2], terminal_sample[3], terminal_sample[4], primary.equipment_appearance(1), false)
	var second: Dictionary = source.sample(terminal_sample[0], terminal_sample[1], terminal_sample[2], terminal_sample[3], terminal_sample[4], primary.equipment_appearance(1), false)
	if not _check(not is_same(first, second) and _exact(first, second), "Public Source terminal calls still return separate exact result copies"):
		return false
	checks += 1
	return _check_deadline()

func _terminal_overflow() -> bool:
	probe_label = "65_terminal_keys_without_step_overflow"
	var expected: Array = []
	for enabled: bool in [false, true]:
		_set_pose(1, "down", 10.0)
		_cold_geometry()
		var source: Variant = TerrainArmy._contact_source
		var original := primary._continuous_pose(1, false).duplicate(true)
		if not _check(source._terminal_poses.size() == 1, "Previous step must retain original terminal A") or not _begin_results(enabled):
			return false
		var generation: int = source.pose_cache_generation
		var before_hits: int = source.query_profile.terminal_hits
		if not _check(_exact(primary._continuous_pose(1, false), original) and source.query_profile.terminal_hits == before_hits + 1 and source._poses.is_empty(),
			"Next-batch A must come from terminal copy without entering the step cache"):
			return false
		var sample: Array = primary.contact_sample(1)
		var appearance := primary.equipment_appearance(1)
		var snapshots: Array = []
		for index: int in 65:
			# Numerical API probe: distinct finite local aim keys at exact weight
			# zero do not alter the original pose/IK, but legitimately fill all
			# terminal slots. No fabricated entries or altered production limit.
			var result: Dictionary = source.sample(sample[0], sample[1], sample[2], Vector2(float(index + 1), 0.0), 0.0, appearance, false)
			snapshots.append(result.duplicate(true))
			if not _check_deadline():
				return false
		if not _check(source._poses.size() == 65 and source._terminal_poses.size() == 2 and source.pose_cache_generation == generation + 1,
			"Only the 64-entry terminal cache must overflow; step cache stays below 128"):
			return false
		snapshots.append(_source_state())
		var key_before: Array = source._key.duplicate(true)
		var calls: int = source.query_profile.sample_calls
		var poses: int = source.query_profile.true_pose_evaluations
		var restored := primary._continuous_pose(1, false)
		if not _check(source.query_profile.sample_calls == calls + 1 and source.query_profile.true_pose_evaluations == poses + 1 and source._key != key_before and _exact(restored, original),
			"Evicted terminal A must use the original Source call and actual pose restore, not borrowed B history"):
			return false
		snapshots.append(restored.duplicate(true))
		snapshots.append(_source_state())
		if not enabled:
			expected = snapshots
		elif not _check(_exact(snapshots, expected), "Terminal overflow changed original source key, bones, morphs or full geometry bits"):
			return false
		if not _end_results():
			return false
	checks += 1
	return _check_deadline()

func _replace_source() -> bool:
	probe_label = "actual_source_dispose_reinitialize"
	_set_pose(1, "idle", 0.317)
	_cold_geometry() # Same real idle pose performs the first head fit on both sources.
	if not _begin_results(true):
		return false
	var old_source: Variant = TerrainArmy._contact_source
	var original := primary._continuous_pose(1, false).duplicate(true)
	var retained: Dictionary = primary._contact_batch_pose_results[1].pose_result
	var old_id: int = old_source.get_instance_id()
	var generation: int = old_source.pose_cache_generation
	TerrainArmy.release_contact_source()
	if not _check(old_source.pose_cache_generation == generation + 1, "Dispose full clear increments generation"):
		return false
	await process_frame # The old queued viewport/editor is gone before creating its replacement.
	if not _check(TerrainArmy.load_contact_source(), "Original source recreation"):
		return false
	var replacement: Variant = TerrainArmy._contact_source
	replacement.same_batch_result_reuse_enabled = true
	# Deliberately match only the cache metadata generation; identity must
	# independently reject a stale result from a different actual source.
	retained.generation = replacement.pose_cache_generation
	var before: int = replacement.query_profile.sample_calls
	var actual := primary._continuous_pose(1, false)
	if not _check(replacement.get_instance_id() != old_id and int(replacement.query_profile.sample_calls) == before + 1 and _exact(actual, original), "Source identity independently guards real reinitialization"):
		return false
	checks += 1
	return _end_results() and _check_deadline()

func run() -> void:
	if not _check(DisplayServer.get_name() != "headless" and group in [0, 1], "GPU group 0/1 required"):
		return
	if not _check(not Geometry.strict_contact_order_enabled and not Geometry.melee_hit_cull_enabled, "Original comparator/packet order remains unchanged"):
		return
	var data := TerrainGenerator.generate(0, 581, {"size": Vector2i(48, 48)})
	SiteEnvironment.initialize(data, "pose-result-original-four-row-fixture")
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	if not _check(Runtime.initialize_item_storage(data.site).ok, "Original item registry"):
		return
	fixture_lab = TerrainLab.new()
	fixture_lab.terrain = data
	primary = _make_team(data, 1, [Vector2i(10, 10), Vector2i(20, 20), Vector2i(5, 5), Vector2i(35, 35)])
	if failed:
		return
	fixture_lab.combat_armies.assign([primary])
	primary.contact_query = fixture_lab._collect_unit_contacts
	source_identity = primary.combat_identity(2)
	initial_item_count = data.site.item_records.size()
	_set_pose(3, "rescue", 1.137)
	TerrainArmy._contact_source.cheap_query_bounds_enabled = false
	if group == 0:
		_set_pose(1, "idle", 0.317)
		if not _ordered_case("ordinary_idle_A_B_A", 1):
			return
		_set_pose(0, "guard", 0.073)
		if not _ordered_case("original_live_female_guard", 0):
			return
		_set_pose(1, "walk_slash", 1.4, true, true)
		if not _ordered_case("original_aimed_attack", 1):
			return
		_set_pose(1, "guard", 0.073)
		_remove(primary, 1, "shield")
		if failed or not _ordered_case("actual_removed_shield_parry", 1):
			return
		_set_pose(1, "idle", 0.0)
		if not _check(primary._reserve_combat_step(1, primary.cells[1] + Vector2i.RIGHT), "Original movement reservation"):
			return
		primary.prepare_combat(1.0 / 120.0)
		if not _ordered_case("actual_committed_movement", 1):
			return
		primary.prepare_combat(1.0 / 120.0)
		if not _ordered_case("actual_next_movement_step", 1) or not _timing():
			return
	else:
		if not _promotion_and_mutation() or not _overflow() or not _boundaries() or not _terminal_overflow():
			return
		if not await _replace_source():
			return
	if not _check_deadline() or not _owners_unchanged():
		return
	var report := {"status": "PASS", "group": group, "checks": checks, "measurements": measurements,
		"profile": _profile(), "rows": original_rows.size(), "items": initial_item_count,
		"elapsed_usec": Time.get_ticks_usec() - started_usec,
		"scope": "Same original batch result-reference reuse. Exact ordered contacts/geometry/native source bone and morph values; independent inputs switch, current eligibility, caller mutation, promotion, 128-entry overflow, terminal, source recreation and real movement. Local warmed timing only, not sustained damage/FPS acceptance.",
		"test_sha256": FileAccess.get_sha256("res://scripts/tests/site_army_pose_result_reuse_test.gd"), "source_fingerprints": _fingerprints()}
	_write_report(report)
	primary.free()
	fixture_lab.combat_armies.clear()
	fixture_lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_ARMY_POSE_RESULT_REUSE_PASS ", JSON.stringify(report))
	quit(0)
