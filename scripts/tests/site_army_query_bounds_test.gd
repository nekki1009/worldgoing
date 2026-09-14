extends "res://scripts/tests/site_army_nonattack_bounds_integration_test.gd"
## Original four-row query fixture only. GPU --group=0 / --group=1;
## internal monotonic 28 seconds / unchanged canonical helper 30 seconds.
## This is NOT the rejected strict-sort/hit-cull candidate. The old sorter and
## every original contact field remain unchanged, including approximate ties.
## Replaces the rejected per-pose dynamic enclosure with the warm-face static
## native proof. Cold first-fit still goes through the original full sample.
## --centered selects the optional native Hips-centered proof; omitted keeps84.
## --inputs also compares the original batch's transient Army input reuse.

var centered := false
var reuse_inputs := false
var input_checks := 0

func _initialize() -> void:
	started_usec = Time.get_ticks_usec()
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--centered":
			centered = true
		if argument == "--inputs":
			reuse_inputs = true
		if argument.begins_with("--group="):
			group = argument.trim_prefix("--group=").to_int()
	output_directory = "res://output/site_combat_performance_20260913/query_bounds/%s%s/group%d/%d_%d" % ["centered" if centered else "origin84", "_inputs" if reuse_inputs else "", group, int(Time.get_unix_time_from_system()), started_usec]
	run.call_deferred()

func _check_deadline() -> bool:
	return not failed and _check(Time.get_ticks_usec() - started_usec < 28000000, "28-second monotonic wall deadline")

func _cold_geometry() -> void:
	# Only test A/B reset: discard the original caches before the first query.
	# Do not pre-fit a neutral/known head; the tested original first pose owns it.
	fixture_lab._end_army_contact_inputs()
	TerrainArmy.clear_contact_samples()
	TerrainArmy._contact_source.geometry._head_bounds.clear()
	for team: TerrainArmy in fixture_lab.combat_armies:
		team._combat_pose_cache.clear()
		team._combat_geometry._head_bounds.clear()
	fixture_lab._army_contact_geometry.clear()
	fixture_lab._sampling_army_contacts = false

func _head_fits() -> Dictionary:
	return {"ordinary": TerrainArmy._contact_source.geometry._head_bounds.duplicate(true),
		"live": primary._combat_geometry._head_bounds.duplicate(true)}

func _full_geometry() -> Array:
	var result: Array = []
	for index: int in primary.combat_units.size():
		result.append(primary.incoming_geometry(index))
		# A -> B -> A must still return this person's full original geometry;
		# a static bound must not masquerade as a complete pose-cache entry.
		result.append(primary.combat_shapes(index, "weapon"))
	return result

func _raw_requests(index: int) -> Array:
	var geometry := primary.incoming_geometry(index)
	var current: Array[PackedVector2Array] = [geometry.body[0], geometry.body[1]]
	for kind: String in ["shield", "parry"]:
		if not geometry[kind].is_empty():
			current.append(geometry[kind][0])
	var previous := Geometry.shifted(current, Vector2(-20.0, 0.0))
	var far_base: Array[PackedVector2Array] = [geometry.body[0]]
	var far: Array[PackedVector2Array] = Geometry.shifted(far_base, Vector2(200.0, 0.0))
	return [[far, far, "far"], [previous, current, "positive"], [previous, current, "repeat_positive"]]

func _collect(request: Array) -> Array[Dictionary]:
	var index := primary.index_for_identity(source_identity)
	return fixture_lab._collect_army_contacts(request[0], request[1], primary.cells[index], primary.combat_ground(index), primary, index)

func _profile() -> Dictionary:
	var source: Variant = TerrainArmy._contact_source
	return {"source": source.query_profile.duplicate(), "source_stages": source.profile_usec.duplicate(),
		"army": primary.combat_geometry_profile.duplicate()}

func _set_pose(index: int, pose: String, age: float, attacking: bool = false, aimed: bool = false) -> void:
	var row: Dictionary = primary.combat_units[index]
	row.pose = pose
	row.age = age
	row.attack = attacking
	row.blocked = false
	row.attack_reduction = 0.0
	row.attack_fatigue = 0.0
	row.aim = []
	if aimed:
		var ground := primary.combat_ground(index)
		row.aim = [ground.x + 24.0, ground.y + 64.0]
	primary.facing[index] = Vector2i.DOWN

func _remove(team: TerrainArmy, index: int, slot: String) -> void:
	var row: Dictionary = team.combat_units[index]
	var identity := str(row.item_state.equipped[slot])
	if not _check(Runtime.transfer_items(team.data, row.item_state, row.cargo, team.data.site.depot_items, team.data.site.inventory,
		{}, [identity], int(row.item_state.version), int(team.data.site.depot_items.version), int(team.data.site.capacity)).ok, "Original fixture item transfer"):
		return
	_check(not row.item_state.item_ids.has(identity) and team.data.site.depot_items.item_ids.has(identity), "Item ownership must really change")
	if reuse_inputs:
		_check(team._contact_batch_inputs.is_empty() and str(team._contact_inputs(index).appearance.parts[slot]) == "none",
			"After a batch, an actual removed item must change the live input recipe immediately")

func _exact(a: Variant, b: Variant) -> bool:
	# These snapshots contain initialized numeric/array/string values only, no
	# NodePath native padding or object serialization. Preserve +/-0 float bits.
	return a == b and var_to_bytes(a) == var_to_bytes(b)

func _ordered_values(hits: Array[Dictionary]) -> Array:
	var values: Array = []
	for hit: Dictionary in hits:
		var value := hit.duplicate(true)
		value.target = hit.target.get_instance_id()
		values.append(value)
	return values

func _inputs_lifecycle() -> bool:
	# No alternate pose/clock owner: change the existing spare row only between
	# batches, then compare the original public readers with the transient input.
	var row: Dictionary = primary.combat_units[3]
	var saved_age: float = row.age
	var saved_direction: Vector2i = primary.facing[3]
	fixture_lab.contact_input_reuse_enabled = true
	fixture_lab._sampling_army_contacts = false
	fixture_lab._begin_army_contact_inputs()
	if not _check(primary._contact_batch_inputs.is_empty(), "Input binding requires the actual sampling batch"):
		return false
	var old: Dictionary = primary._contact_inputs(3)
	row.age = saved_age + 0.125
	primary.facing[3] = Vector2i.RIGHT
	var live: Dictionary = primary._contact_inputs(3)
	if not _check(not is_same(old, live) and old.sample != live.sample and _exact(live.sample, primary.contact_sample(3)) and primary._contact_batch_inputs.is_empty(),
		"Outside-batch age/direction mutation must be read immediately, without retaining inputs"):
		return false
	fixture_lab._sampling_army_contacts = true
	fixture_lab._begin_army_contact_inputs()
	var slots: Array = fixture_lab._army_contact_geometry[["targets", primary.get_instance_id()]]
	var first: Dictionary = primary._contact_inputs(3)
	var again: Dictionary = primary._contact_inputs(3)
	if not _check(is_same(slots, primary._contact_batch_inputs) and is_same(first, again) and is_same(first, slots[3].inputs) and _exact(first, live),
		"Next batch must lazily retain the new original inputs in the exact same Lab target slot"):
		return false
	fixture_lab._end_army_contact_inputs()
	fixture_lab._sampling_army_contacts = false
	fixture_lab._army_contact_geometry.clear()
	row.age = saved_age
	primary.facing[3] = saved_direction
	if not _check(primary._contact_batch_inputs.is_empty() and _exact(primary._contact_inputs(3), old), "Ending the batch must detach old inputs before a subsequent original mutation"):
		return false
	input_checks += 1
	return _check_deadline()

func _case(index: int, label: String, must_static: bool = false) -> bool:
	probe_label = label
	if not _check_deadline():
		return false
	# Derive inputs from real raw polygons, THEN discard every head fit below.
	# These diagnostic inputs cannot prewarm the tested A-first-fit sequence.
	var requests := _raw_requests(index)
	var source: Variant = TerrainArmy._contact_source
	var before_state := _state()
	var expected: Array = []
	var expected_full: Array = []
	var expected_heads := {}
	var profiles: Array = []
	for mode: int in (6 if reuse_inputs else 4):
		var enabled := mode >= 2
		var batched := mode in [1, 2, 4]
		source.cheap_query_bounds_enabled = enabled
		_cold_geometry()
		fixture_lab.contact_input_reuse_enabled = mode >= 4
		fixture_lab._sampling_army_contacts = batched
		fixture_lab._begin_army_contact_inputs()
		var before := _profile()
		var results: Array = []
		var heads := {}
		var far_profile := {}
		var warm_profile := {}
		for request_index: int in requests.size():
			var found := _collect(requests[request_index])
			results.append(_ordered_values(found))
			if request_index == 0:
				if not _check(found.is_empty(), "Actual translated far sweep must be a genuine original miss"):
					return false
				heads = _head_fits()
				far_profile = _profile()
				# Pose B belongs to another existing row. This changes only the
				# shared editor's current pose, not anybody's same-batch state.
				primary.combat_shapes(3, "body")
				var pose_key: Array = source._key.duplicate(true)
				var pose_count: int = source.query_profile.true_pose_evaluations
				primary.combat_query_bounds(index)
				warm_profile = _profile()
				if enabled and must_static and not _check(source._key == pose_key and int(source.query_profile.true_pose_evaluations) == pose_count,
					"Warm static A must not seek or replace the original current B pose"):
					return false
			else:
				var identities: Array[int] = []
				for hit: Dictionary in found:
					identities.append(int(hit.identity))
				if not _check(identities.has(primary.combat_identity(index)), "Positive sweep must reach its real target", {"identities": identities}):
					return false
			if not _check_deadline():
				return false
		var full := _full_geometry()
		if mode == 4:
			var slots: Array = fixture_lab._army_contact_geometry[["targets", primary.get_instance_id()]]
			var inputs: Dictionary = primary._contact_inputs(index)
			if not _check(is_same(slots, primary._contact_batch_inputs) and is_same(inputs, slots[index].inputs) and _exact(inputs.sample, primary.contact_sample(index)) and _exact(inputs.appearance, primary.equipment_appearance(index)) and _exact(inputs.ground, primary.combat_ground(index)) and _exact(inputs.origin, primary.combat_ground(index) + primary.combat_offset(index)),
				"Warm full queries must reuse the original target slot's exact sample, recipe and origin"):
				return false
			if primary._needs_weapon_sample(index):
				# The original sampling loop can set blocked during the batch.
				# This must stay live even though pose inputs remain unchanged.
				primary.combat_units[index].blocked = true
				var live_eligibility := not primary._needs_weapon_sample(index) and is_same(inputs, primary._contact_inputs(index))
				primary.combat_units[index].blocked = false
				if not _check(live_eligibility, "Input reuse must not cache mutable weapon eligibility"):
					return false
			input_checks += 1
		var after := _profile()
		if mode == 0:
			expected = results
			expected_full = full
			expected_heads = heads
		elif not _check(_exact(results, expected) and _exact(full, expected_full) and _exact(heads, expected_heads),
			"Original ordered contact/complete polygon/first head-fit bits changed", {"mode": mode, "contacts_equal": results == expected,
			"geometry_equal": full == expected_full, "head_equal": heads == expected_heads}):
			return false
		if must_static and enabled:
			if not _check(int(far_profile.source.query_bounds_fills) > int(before.source.query_bounds_fills), "Far A must exercise actual cheap query bounds"):
				return false
			if not _check(int(warm_profile.source.query_bounds_hits) > int(far_profile.source.query_bounds_hits), "Cold full A -> B -> warm A must actually return the static enclosure"):
				return false
			if centered and not _check(int(warm_profile.source.centered_query_bounds_hits) > int(far_profile.source.centered_query_bounds_hits), "Centered mode must really use its native clip enclosure"):
				return false
		profiles.append({"cheap": enabled, "batched": batched, "inputs": mode >= 4, "before": before, "after_cold_far": far_profile, "after_warm": warm_profile, "after_full": after})
		fixture_lab._end_army_contact_inputs()
		fixture_lab._sampling_army_contacts = false
		fixture_lab._army_contact_geometry.clear()
		if not _check(primary._contact_batch_inputs.is_empty(), "Every mode must detach transient inputs before resolution or mutation"):
			return false
		if not _check(_exact(_state(), before_state) and _owners_unchanged(), "Read-only bounds changed original row, life, clock, equipment or presenter"):
			return false
	comparisons.append({"case": label, "target": primary.combat_identity(index), "ordered_contact_bits_exact": true,
		"full_geometry_bits_exact": true, "cold_head_first_fit_bits_exact": true, "profiles": profiles})
	return _check_deadline()

func run() -> void:
	if not _check(DisplayServer.get_name() != "headless" and group in [0, 1], "GPU group 0/1 required"):
		return
	if not _check(not Geometry.strict_contact_order_enabled and not Geometry.melee_hit_cull_enabled, "Keep the original approximate comparator and all targets"):
		return
	var data := TerrainGenerator.generate(0, 581, {"size": Vector2i(48, 48)})
	SiteEnvironment.initialize(data, "query-bounds-original-four-row-fixture")
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	if not _check(Runtime.initialize_item_storage(data.site).ok, "Original item registry initialization"):
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
	var source: Variant = TerrainArmy._contact_source
	source.centered_query_bounds_enabled = centered
	var source_id: int = source.editor.get_instance_id()
	var saved_radius: bool = source.conservative_nonattack_bounds_enabled
	# Isolate the new bound. Otherwise the independently verified 128-radius
	# gate may reject A before EITHER path performs its original first head fit.
	source.conservative_nonattack_bounds_enabled = false
	_set_pose(3, "rescue", 1.137)
	if reuse_inputs and not _inputs_lifecycle():
		return
	if group == 0:
		_set_pose(1, "idle", 0.317)
		if not _case(1, "ordinary_idle_cold_full_A_B_warm_static_A", true):
			return
		_set_pose(1, "guard", 0.073)
		if not _case(1, "ordinary_actual_shield_guard"):
			return
		_set_pose(1, "walk_slash", 1.4, true, true)
		if not _check(float(primary.contact_sample(1)[4]) > 0.0, "Exercise actual original DOWN attack aim, not a zero-weight fixture") or not _case(1, "original_aimed_active_fallback"):
			return
		_set_pose(1, "walk_slash", 1.4, true)
		primary.facing[1] = Vector2i.UP
		if not _check(primary._needs_weapon_sample(1) and float(primary.contact_sample(1)[4]) == 0.0 and not primary.combat_shapes(1, "weapon").is_empty(),
			"Unaimed UP fixture must really require the original active offensive weapon sample"):
			return
		if not _case(1, "original_unaimed_UP_active_warm_static_and_full_weapon", true):
			return
		_set_pose(1, "guard", 0.073)
		_remove(primary, 1, "shield")
		if failed or not _case(1, "actual_shieldless_weapon_parry_fallback"):
			return
		_remove(primary, 1, "armor")
		if failed:
			return
		_remove(primary, 1, "weapon")
		if failed or not _case(1, "actual_unarmed_missing_armor"):
			return
		_set_pose(1, "attack_unarmed", 0.537, true)
		if not _case(1, "original_unarmed_active_capsule"):
			return
	else:
		_set_pose(0, "guard", 0.073)
		if not _case(0, "original_female_live_guard_cold_head"):
			return
		_set_pose(0, "down", 10.0)
		if not _case(0, "original_female_live_down"):
			return
		_set_pose(1, "down", 10.0)
		if not _case(1, "ordinary_completed_down_full_terminal"):
			return
		_set_pose(1, "idle", 0.0)
		if not _check(primary._reserve_combat_step(1, primary.cells[1] + Vector2i.RIGHT), "Original committed move fixture"):
			return
		primary.prepare_combat(1.0 / 120.0)
		if not _case(1, "original_moving_ground_step_one"):
			return
		primary.prepare_combat(1.0 / 120.0)
		if not _case(1, "original_moving_ground_next_step"):
			return
	if failed or not _check_deadline():
		return
	if not _check(comparisons.size() == (7 if group == 0 else 5) and source.editor.get_instance_id() == source_id and _owners_unchanged(), "Final coverage/original owner guard"):
		return
	source.cheap_query_bounds_enabled = false
	source.conservative_nonattack_bounds_enabled = saved_radius
	var report := {"status": "PASS", "group": group, "centered": centered, "input_reuse": reuse_inputs, "input_checks": input_checks, "comparisons": comparisons, "original_rows": original_rows.size(),
		"original_items": initial_item_count, "elapsed_usec": Time.get_ticks_usec() - started_usec,
		"scope": "Static warm-face native proof replaces dynamic per-pose bounds. Optional inputs mode also compares the same Lab target-slot input reuse, detach/next-batch mutation and live blocked eligibility. Same original approximate sorter, exact ordered contacts and numeric bits, source/live cold head first-fit, cold full A/B/warm no-seek A/full A, actual equipment and movement. Four-row diagnostic, not damage/FPS/visual acceptance.",
		"test_sha256": FileAccess.get_sha256("res://scripts/tests/site_army_query_bounds_test.gd"), "source_fingerprints": _fingerprints()}
	_write_report(report)
	primary.free()
	fixture_lab.combat_armies.clear()
	fixture_lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_ARMY_QUERY_BOUNDS_PASS ", JSON.stringify(report))
	quit(0)
