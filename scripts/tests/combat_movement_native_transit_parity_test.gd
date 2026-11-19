extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Transit = preload("res://scripts/terrain_lab/formation_transit_planner.gd")
const STATE_FIELDS := ["member_sequence_rank", "member_observed_path_s", "member_path_s", "member_row_map", "member_lane_map", "pre_route_staging_slots", "member_transit_slots", "assignment_epoch", "member_soft_assignment_epoch"]
const STATE_META := ["_transit_soft_key", "_transit_soft_retry", "_transit_soft_cells", "_transit_soft_reject_counts", "_transit_row_sections_key", "_transit_row_sections", "_transit_exact_path_indices"]
var _checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok

func _plan(case_index: int, mids: Array[int]) -> CombatMovePlan:
	var plan := CombatMovePlan.new()
	for x in range(5, 51):
		plan.macro_path.append(Vector2i(x, 12))
	if case_index % 3 == 1:
		# Repeated cells deliberately use the final exact-path occurrence.
		plan.macro_path.insert(12, Vector2i(16, 12))
	elif case_index % 3 == 2:
		plan.macro_path.clear()
		for x in range(5, 21):
			plan.macro_path.append(Vector2i(x, 12))
		for y in range(13, 22):
			plan.macro_path.append(Vector2i(20, y))
		for x in range(21, 51):
			plan.macro_path.append(Vector2i(x, 21))
	plan.current_width = 4
	plan.pending_width = 4
	plan.macro_cursor = 18
	plan.set_meta("_transit_soft_debug_enabled", true)
	for i in range(mids.size()):
		plan.member_checkpoint_path_k[mids[i]] = maxi(0, 15 - i)
		if i % 3 != 0:
			plan.member_observed_path_s[mids[i]] = float(15 - i) + 0.25
	if case_index >= 3:
		var destination := CombatDeploymentPlan.new()
		destination.resolved_anchor = Vector2i(44, 12)
		destination.ingress_cell = Vector2i(25, 12)
		destination.final_facing = Vector2i.RIGHT
		for x in range(25, 55):
			for y in range(8, 17):
				destination.platform_footprint.append(Vector2i(x, y))
		for i in range(24):
			destination.platform_slots.append(Vector2i(43 + i % 4, 9 + floori(float(i) / 4.0)))
		for i in range(mids.size()):
			destination.member_role_map[mids[i]] = 1 if i % 5 == 4 else 0
			destination.member_slot_map[mids[i]] = destination.platform_slots[i]
			if i % 3 == 0:
				destination.admitted_platform_member_ids.append(mids[i])
		plan.destination_plan = destination
	return plan

func _snapshot(plan: CombatMovePlan) -> Dictionary:
	var state := {}
	for field_name: String in STATE_FIELDS:
		state[field_name] = plan.get(field_name)
	for meta_name: String in STATE_META:
		var metadata_present: bool = plan.has_meta(meta_name)
		state[meta_name] = {"present": metadata_present, "value": plan.get_meta(meta_name) if metadata_present else null}
	if plan.destination_plan != null:
		var destination := plan.destination_plan
		var scan_present: bool = destination.has_meta("_transit_bottleneck_scan_key")
		state["destination"] = [destination.approach_bottlenecked, destination.approach_last_bottleneck_cell, destination.centered_platform_handoff, {"present": scan_present, "value": destination.get_meta("_transit_bottleneck_scan_key") if scan_present else null}]
	return state.duplicate(true)

func _run_case(case_index: int) -> bool:
	var terrain := Helper.build_flat_map(80, 35)
	if case_index >= 6:
		for x in range(80):
			for y in range(13, 35):
				terrain.height_levels[terrain.index(Vector2i(x, y))] = 1
			terrain.ramp_edges[terrain.index(Vector2i(x, 12))] = 1 << 2
			terrain.ramp_edges[terrain.index(Vector2i(x, 13))] = 1 << 0
	if case_index % 2 == 1:
		for x in range(19, 23):
			for y in range(35):
				if y != 12:
					terrain.static_blocked[terrain.index(Vector2i(x, y))] = 1
	var mids: Array[int] = []
	var cells := {}
	for i in range(24):
		var mid: int = (1 << 40) + i + 1
		mids.append(mid)
		cells[mid] = Vector2i(20 - i % 12, 12 + floori(float(i) / 12.0))
	if case_index >= 3:
		cells[mids[0]] = Vector2i(28, 12) # admitted but behind lazily derived handoff
	var reference := _plan(case_index, mids)
	var candidate := _plan(case_index, mids)
	var profile: FormationMovementProfile = FormationMovementProfile.new() if case_index % 2 == 0 else null
	for tick in range(16):
		for plan: CombatMovePlan in [reference, candidate]:
			plan.macro_cursor = mini(plan.macro_path.size() - 1, 18 + tick)
			if tick in [1, 2, 3]:
				Transit.update_width_hysteresis(plan, 2)
			if tick in [4, 5]:
				plan.member_route_retry_count[mids[0]] = tick - 2 # retry 2 -> 3
			if tick in [6, 7]:
				plan.member_defer_count[mids[1]] = tick + 1 # defer 7 -> 8
			if tick == 8:
				plan.path_epoch += 1
				plan.macro_path = plan.macro_path.duplicate()
			if tick == 9:
				plan.terrain_revision += 1
			if tick == 10 and plan.destination_plan != null:
				plan.destination_plan.admitted_platform_member_ids.append(mids[2])
				plan.destination_plan.member_role_map[mids[3]] = 1
			if tick == 14 and plan.destination_plan != null:
				for mid in mids:
					plan.destination_plan.member_role_map[mid] = 1 # no flow clears slots
			if tick == 15 and plan.destination_plan != null:
				plan.destination_plan.member_role_map[mids[0]] = 0
		if tick == 9:
			terrain.static_blocked[terrain.index(Vector2i(18, 11))] = 1
			terrain.navigation_revision += 1
		if tick == 11 and profile != null:
			profile.can_use_ramp = false
			profile.recompute_hash()
		if tick == 12 and profile != null:
			profile.max_step_height = 0
			profile.recompute_hash()
		if tick >= 2:
			cells[mids[tick % mids.size()]] = reference.macro_path[mini(reference.macro_path.size() - 1, 17 + tick)]
		Transit.native_transit_enabled = false
		var expected := Transit.calculate_transit_slots(reference, terrain, profile, mids, cells)
		var expected_state := _snapshot(reference)
		Transit.native_transit_enabled = true
		var calls_before := Transit.native_transit_calls
		var actual := Transit.calculate_transit_slots(candidate, terrain, profile, mids, cells)
		if not _require(Transit.native_transit_calls == calls_before + 1, "Native transit did not execute case=%d tick=%d" % [case_index, tick]): return false
		if not _require(expected == actual, "Transit result mismatch case=%d tick=%d expected=%s actual=%s" % [case_index, tick, expected, actual]): return false
		var actual_state := _snapshot(candidate)
		for key in expected_state:
			if not _require(expected_state[key] == actual_state[key], "Transit state mismatch case=%d tick=%d field=%s expected=%s actual=%s" % [case_index, tick, key, expected_state[key], actual_state[key]]): return false
		var cache: Dictionary = candidate.get_meta("_transit_exact_path_indices", {})
		if not cache.is_empty() and not _require(is_same(cache["path"], candidate.macro_path), "Native path cache must retain original macro_path identity"): return false
		_checks += 1
	return true

func _run() -> void:
	for case_index in range(8):
		if not _run_case(case_index): return
	if not _run_mixed_rank_fallback(): return
	if not _run_invalid_numeric_packets(): return
	print("NATIVE TRANSIT PARITY PASS stateful_checks=%d native_calls=%d" % [_checks, Transit.native_transit_calls])
	quit(0)

func _mixed_rank_plan(mids: Array[int]) -> CombatMovePlan:
	var plan := CombatMovePlan.new()
	for x in range(5, 36):
		plan.macro_path.append(Vector2i(x, 10))
	plan.macro_cursor = 8
	plan.member_sequence_rank[mids[0]] = 0
	plan.member_sequence_rank[mids[1]] = 1
	plan.member_observed_path_s[mids[0]] = 0.0
	plan.member_observed_path_s[mids[1]] = 2.0
	plan.member_observed_path_s[mids[2]] = 1.0
	for mid in mids:
		plan.member_checkpoint_path_k[mid] = 0
	return plan

func _run_mixed_rank_fallback() -> bool:
	var terrain := Helper.build_flat_map(45, 21)
	for y in range(21):
		if y != 10:
			terrain.static_blocked[terrain.index(Vector2i(12, y))] = 1
	var mids: Array[int] = [1, 2, 3]
	var cells := {1: Vector2i(6, 9), 2: Vector2i(7, 9), 3: Vector2i(8, 9)}
	var reference := _mixed_rank_plan(mids)
	var candidate := _mixed_rank_plan(mids)
	var kernel: RefCounted = ClassDB.instantiate(&"ArmyIdleKernel")
	var before := var_to_bytes(_snapshot(candidate))
	var packet: Dictionary = kernel.call("calculate_transit_slots", candidate, terrain, null, mids, cells)
	if not _require(packet.is_empty(), "Mixed prior-rank choke must reject the entire native packet"): return false
	if not _require(var_to_bytes(_snapshot(candidate)) == before, "Rejected mixed-rank packet must not apply partial owner/meta changes"): return false
	Transit.native_transit_enabled = false
	var expected := Transit.calculate_transit_slots(reference, terrain, null, mids, cells)
	Transit.native_transit_enabled = true
	var calls_before := Transit.native_transit_calls
	var fallbacks_before := Transit.native_transit_fallbacks
	var actual := Transit.calculate_transit_slots(candidate, terrain, null, mids, cells)
	if not _require(Transit.native_transit_calls == calls_before and Transit.native_transit_fallbacks == fallbacks_before + 1, "Mixed-rank choke must execute the GD fallback exactly once"): return false
	if not _require(actual == expected and _snapshot(candidate) == _snapshot(reference), "Mixed-rank fallback must match the complete GD result/state/meta"): return false
	print("NATIVE TRANSIT MIXED RANK FALLBACK PASS")
	return true

func _run_invalid_numeric_packets() -> bool:
	var terrain := Helper.build_flat_map(80, 35)
	var mids: Array[int] = [1, 2, 3]
	var cells := {1: Vector2i(6, 12), 2: Vector2i(7, 12), 3: Vector2i(8, 12)}
	var kernel: RefCounted = ClassDB.instantiate(&"ArmyIdleKernel")
	var invalid_values: Array[float] = [NAN, INF, -INF, 1.0e30, -1.0e30]
	for invalid_value in invalid_values:
		var candidate := _plan(0, mids)
		candidate.member_checkpoint_path_k[1] = invalid_value
		var before := var_to_bytes(_snapshot(candidate))
		var checkpoints_before := var_to_bytes(candidate.member_checkpoint_path_k)
		var packet: Dictionary = kernel.call("calculate_transit_slots", candidate, terrain, null, mids, cells)
		if not _require(packet.is_empty(), "Invalid floating checkpoint must reject packet before integer conversion: %s" % invalid_value): return false
		if not _require(var_to_bytes(_snapshot(candidate)) == before and var_to_bytes(candidate.member_checkpoint_path_k) == checkpoints_before, "Invalid numeric packet must leave every original field/meta unchanged"): return false
	var nan_projection := _plan(0, mids)
	nan_projection.member_observed_path_s[1] = NAN
	var projection_before := var_to_bytes(_snapshot(nan_projection))
	var projection_packet: Dictionary = kernel.call("calculate_transit_slots", nan_projection, terrain, null, mids, cells)
	if not _require(projection_packet.is_empty() and var_to_bytes(_snapshot(nan_projection)) == projection_before, "NaN projection must reject packet before sorting and preserve original fields"): return false
	print("NATIVE TRANSIT INVALID NUMERIC PACKETS PASS rejected=6")
	return true
