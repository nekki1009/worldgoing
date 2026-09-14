extends SceneTree
## One original sword swing, two original two-row teams, replayed on the same
## row/holder/presenter owners. GPU, internal 53 seconds / canonical helper 55.
## No replacement sampling/resolution, fabricated packet, lowered HP or clock.
## --redundant-work holds input reuse on and compares both new candidates off/on.
## --compiled-source instead holds other candidates fixed and compares original
## Source geometry with native-pose C# geometry + native shadow validation.
## --contact-buckets holds every other candidate fixed and compares batch
## anchor indexing off/on, including ordered contacts and native pose keys;
## one distant original third row per team makes actual culling observable.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Geometry = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")
const STEP := 1.0 / 120.0
const MAX_STEPS := 360
const AFTER_HIT_STEPS := 8

class FlowLab extends TerrainLab:
	var queued: Array = []
	var boundary_clean := true
	var resolve_calls := 0
	var sampled_input_slots := 0
	var trace_contacts := false
	var ordered_contacts: Array = []
	func _collect_unit_contacts(previous: Array[PackedVector2Array], current: Array[PackedVector2Array], source_cell: Vector2i, source_position: Vector2, source: Variant, source_unit: int) -> Array[Dictionary]:
		var contacts := super._collect_unit_contacts(previous, current, source_cell, source_position, source, source_unit)
		if trace_contacts:
			var values: Array = []
			for hit: Dictionary in contacts:
				var value := hit.duplicate(true)
				value.target = hit.target.get_instance_id()
				values.append(value)
			ordered_contacts.append({"source": source.get_instance_id(), "unit": source_unit, "contacts": values})
		return contacts
	func _end_army_contact_inputs() -> void:
		if _sampling_army_contacts and contact_input_reuse_enabled:
			for team: TerrainArmy in combat_armies:
				for slot: Variant in team._contact_batch_inputs:
					if slot is Dictionary and slot.has("inputs"):
						sampled_input_slots += 1
		super._end_army_contact_inputs()
	func _resolve_combat_contacts() -> void:
		boundary_clean = boundary_clean and not _sampling_army_contacts and _army_contact_geometry.is_empty()
		for team: TerrainArmy in combat_armies:
			boundary_clean = boundary_clean and team._contact_batch_inputs.is_empty() and team._contact_batch_pose_results.is_empty()
		for packet: Dictionary in _combat_contacts:
			var value := packet.duplicate(true)
			value.attacker = packet.attacker.get_instance_id()
			value.target = packet.target.get_instance_id()
			queued.append(value)
		resolve_calls += 1
		super._resolve_combat_contacts()

var started := 0
var failed := false
var output_path := ""
var lab: FlowLab
var teams: Array[TerrainArmy] = []
var owners: Array = []
var item_baseline := {}
var source_owner := 0
var completed_steps := 0
var redundant_work := false
var compiled_source := false
var contact_buckets := false

func _initialize() -> void:
	started = Time.get_ticks_usec()
	redundant_work = "--redundant-work" in OS.get_cmdline_user_args()
	compiled_source = "--compiled-source" in OS.get_cmdline_user_args()
	contact_buckets = "--contact-buckets" in OS.get_cmdline_user_args()
	var mode := "contact_buckets/" if contact_buckets else ("compiled_source/" if compiled_source else ("redundant_work/" if redundant_work else ""))
	output_path = "res://output/site_combat_performance_20260913/contact_inputs_flow/%s%d_%d" % [mode, int(Time.get_unix_time_from_system()), started]
	run.call_deferred()

func _process(_delta: float) -> bool:
	_check(Time.get_ticks_usec() - started < 53000000, "53-second monotonic deadline")
	return false

func _write(report: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path))
	var file := FileAccess.open(output_path + "/measurements.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()

func _check(condition: bool, message: String, detail: Dictionary = {}) -> bool:
	if condition and not failed:
		return true
	if not failed:
		failed = true
		var report := {"status": "FAIL", "message": message, "detail": detail, "completed_steps": completed_steps, "redundant_work": redundant_work, "compiled_source": compiled_source,
			"contact_buckets": contact_buckets, "elapsed_usec": Time.get_ticks_usec() - started}
		_write(report)
		push_error("SITE_ARMY_CONTACT_INPUTS_FLOW_FAIL " + JSON.stringify(report))
		quit(1)
	return false

func _copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Array or value is Dictionary else value

func _exact(a: Variant, b: Variant) -> bool:
	return a == b and var_to_bytes(a) == var_to_bytes(b)

func _snapshot() -> Dictionary:
	var result := {"rows": [], "combat": [], "private": []}
	for team: TerrainArmy in teams:
		result.rows.append(team.combat_units.duplicate(true)) # Includes native previous polygons and integer hit keys.
		result.combat.append(team.capture_combat_state())
		# These are the non-saved values touched by prepare/apply/settle in this
		# stationary HOLD fixture. No navigation/rescue or commander loss occurs.
		result.private.append({"dirty": team._command_dirty, "visual_dirty": team._visual_dirty,
			"owners": team._cell_owners.duplicate(), "reference": team.command_reference})
	return result

func _rewind(initial: Dictionary) -> bool:
	# Test replay only: mutate the same existing rows, never clear/deploy/restore
	# the Army (restore_combat_state would replace its live presenter owners).
	for team_index: int in teams.size():
		var team := teams[team_index]
		for index: int in team.combat_units.size():
			var row: Dictionary = team.combat_units[index]
			var saved: Dictionary = initial.rows[team_index][index]
			for key: Variant in row.keys():
				if not saved.has(key):
					row.erase(key) # e.g. optional original hit_revision added by the real hit.
			for key: Variant in saved:
				if key not in ["item_state", "cargo"]:
					row[key] = _copy(saved[key])
		# Audited HOLD/standing path changes only these saved scalars; its
		# commander/slot/rescue/identity state is checked below, not blindly reset.
		team._command_elapsed = float(initial.combat[team_index]._command_elapsed)
		team._order_delay = float(initial.combat[team_index]._order_delay)
		team._command_dirty = bool(initial.private[team_index].dirty)
		team._visual_dirty = bool(initial.private[team_index].visual_dirty)
		team.command_reference = initial.private[team_index].reference
		team._cell_owners = initial.private[team_index].owners.duplicate()
		team._combat_pose_cache.clear()
		team._combat_geometry._head_bounds.clear()
	lab._end_army_contact_inputs()
	lab._sampling_army_contacts = false
	lab._army_contact_geometry.clear()
	lab._combat_contacts.clear()
	lab._fatigue_work_seconds.clear()
	lab.queued.clear()
	lab.ordered_contacts.clear()
	lab.boundary_clean = true
	lab.resolve_calls = 0
	lab.sampled_input_slots = 0
	TerrainArmy.clear_contact_samples()
	TerrainArmy._contact_source.geometry._head_bounds.clear()
	return _check(_exact(_snapshot(), initial), "Replay must restore all original row/command/movement values exactly without replacing owners")

func _owners_intact() -> bool:
	if TerrainArmy._contact_source.editor.get_instance_id() != source_owner or not _exact(lab.terrain.site.item_records, item_baseline):
		return false
	for entry: Dictionary in owners:
		var row: Dictionary = entry.team.combat_units[entry.index]
		if not is_same(row, entry.row) or not is_same(row.item_state, entry.holder) or not is_same(row.cargo, entry.cargo):
			return false
		if int(entry.editor) != 0 and entry.team._unit_editor(entry.index).get_instance_id() != int(entry.editor):
			return false
	return true

func _set_redundant_work(enabled: bool) -> void:
	TerrainArmy._contact_source.same_batch_result_reuse_enabled = enabled
	TerrainArmy._contact_source.geometry.weapon_mesh_filter_enabled = enabled
	for team: TerrainArmy in teams:
		team._combat_geometry.weapon_mesh_filter_enabled = enabled

func _candidate_flags() -> Dictionary:
	var team_weapon_flags: Array[bool] = []
	for team: TerrainArmy in teams:
		team_weapon_flags.append(team._combat_geometry.weapon_mesh_filter_enabled)
	return {"contact_input_reuse": lab.contact_input_reuse_enabled,
		"contact_buckets": lab.contact_buckets_enabled,
		"same_batch_result_reuse": TerrainArmy._contact_source.same_batch_result_reuse_enabled,
		"source_weapon_mesh_filter": TerrainArmy._contact_source.geometry.weapon_mesh_filter_enabled,
		"team_weapon_mesh_filter": team_weapon_flags,
		"compiled_geometry": TerrainArmy._contact_source.compiled_geometry_enabled,
		"compiled_geometry_shadow": TerrainArmy._contact_source.compiled_geometry_shadow_enabled}

func _pose_result_hits() -> int:
	var result := 0
	for team: TerrainArmy in teams:
		result += int(team.combat_geometry_profile.pose_result_hits)
	return result

func _step() -> Dictionary:
	lab.queued.clear()
	lab.ordered_contacts.clear()
	lab._advance_combat(STEP, 10.0) # Original fatigue -> prepare -> sample -> resolve -> settle.
	completed_steps += 1
	if not _check(Time.get_ticks_usec() - started < 53000000 and lab.boundary_clean and not lab._sampling_army_contacts and lab._army_contact_geometry.is_empty() and lab._combat_contacts.is_empty() and _owners_intact(),
		"Original shared step must resolve only after detaching inputs and preserve people/items"):
		return {}
	for team: TerrainArmy in teams:
		if not _check(team._contact_batch_inputs.is_empty() and team._contact_batch_pose_results.is_empty(), "Next step cannot inherit a target input or pose-result reference"):
			return {}
	var result := {"state": _snapshot(), "packets": lab.queued.duplicate(true)}
	if contact_buckets:
		result["ordered_contacts"] = lab.ordered_contacts.duplicate(true)
		# Do not reset the shared live Source pose or replace its owner. Compare
		# the original insertion-ordered sampled keys left by each real step.
		result["source_pose_keys"] = TerrainArmy._contact_source._poses.keys().duplicate(true)
		result["source_terminal_keys"] = TerrainArmy._contact_source._terminal_poses.keys().duplicate(true)
	return result

func run() -> void:
	if not _check(int(compiled_source) + int(redundant_work) + int(contact_buckets) <= 1, "Each candidate mode is independent; do not combine --compiled-source, --redundant-work or --contact-buckets"):
		return
	if not _check(DisplayServer.get_name() != "headless", "GPU required for both original female captains"):
		return
	if not _check(not Geometry.strict_contact_order_enabled and not Geometry.melee_hit_cull_enabled, "Original contact comparator and once-per-swing skip remain unchanged"):
		return
	var data := TerrainGenerator.generate(0, 581, {"size": Vector2i(48, 48)})
	SiteEnvironment.initialize(data, "actual-contact-input-flow")
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	if not _check(Runtime.initialize_item_storage(data.site).ok, "Original item registry"):
		return
	lab = FlowLab.new()
	lab.terrain = data
	lab.contact_buckets_enabled = false
	lab.trace_contacts = contact_buckets
	lab.contact_candidate_profile_enabled = contact_buckets
	for team_index: int in 2:
		var team := TerrainArmy.new() # No probe subclass: actual sample_combat runs.
		root.add_child(team)
		team.set_process(false)
		team.team_id = team_index + 1
		team.faction_id = team_index
		team.roster_size = 3 if contact_buckets else 2
		var cells: Array[Vector2i] = [Vector2i(10 + team_index * 25, 10), Vector2i(20 + team_index, 20)]
		if contact_buckets:
			cells.append(Vector2i(1 + team_index * 45, 1))
		if not _check(team.deploy_at(data, null, null, cells) and team.enable_combat(false), "Two original teams with the native replay roster"):
			return
		team._ensure_live_presenters()
		team.advance_frame(0.0)
		for index: int in team.roster_size:
			var row: Dictionary = team.combat_units[index]
			row.appearance = team._unit_editor(index).capture_appearance() if index == 0 else TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
			row.item_state = {}
			row.cargo = {}
			row.think = 1000.0 # No additional autonomous order during this one commanded swing.
			if not _check(Runtime.seed_person_equipment(data, row.item_state, team.combat_identity(index), row.appearance).ok, "Original per-person equipment"):
				return
			owners.append({"team": team, "index": index, "row": row, "holder": row.item_state, "cargo": row.cargo,
				"editor": team._unit_editor(index).get_instance_id() if index == 0 else 0})
		team.equipment_appearance_query = func(identity: int) -> Dictionary:
			var row: Dictionary = team.combat_units[team.index_for_identity(identity)]
			return Runtime.equipment_appearance(data, row.item_state, row.appearance)
		team.contact_query = lab._collect_unit_contacts
		team.combat_target_query = lab._combat_target
		team.contact_sink = func(packet: Dictionary) -> void: lab._combat_contacts.append(packet)
		teams.append(team)
	lab.combat_armies.assign(teams)
	teams[0].external_blocker = teams[1].blocks_cell
	teams[1].external_blocker = teams[0].blocks_cell
	teams[0].facing[1] = Vector2i.RIGHT
	teams[1].facing[1] = Vector2i.LEFT
	# Genuine missing armor/shield makes the original sword damage observable;
	# this is initial equipment fixture transfer, not a timed-looting claim.
	var victim: Dictionary = teams[1].combat_units[1]
	for slot: String in ["shield", "armor"]:
		var item := str(victim.item_state.equipped[slot])
		if not _check(Runtime.transfer_items(data, victim.item_state, victim.cargo, data.site.depot_items, data.site.inventory,
			{}, [item], int(victim.item_state.version), int(data.site.depot_items.version), int(data.site.capacity)).ok, "Actual victim item transfer"):
			return
	item_baseline = data.site.item_records.duplicate(true)
	source_owner = TerrainArmy._contact_source.editor.get_instance_id()
	TerrainArmy._contact_source.cheap_query_bounds_enabled = true
	TerrainArmy._contact_source.centered_query_bounds_enabled = true
	# Explicit native baseline, including when this test is run after a future
	# production default changes. No other candidate switch changes in this mode.
	TerrainArmy._contact_source.compiled_geometry_enabled = false
	TerrainArmy._contact_source.compiled_geometry_shadow_enabled = false
	if redundant_work:
		_set_redundant_work(false)
	for team: TerrainArmy in teams:
		team.combat_shapes(0, "body") # Same original ready state before both replays.
		team.settle_combat_command()
	if not _check(teams[0].start_unit_attack(1, teams[1].cells[1], teams[1].combat_identity(1)), "Start the original adjacent sword attack"):
		return
	var initial := _snapshot()
	var expected: Array = []
	var first_hit := -1
	var packet_count := 0
	lab.contact_input_reuse_enabled = redundant_work or compiled_source or contact_buckets
	if not _rewind(initial):
		return
	var baseline_flags := _candidate_flags()
	for tick: int in MAX_STEPS:
		var result := _step()
		if failed:
			return
		expected.append(result)
		packet_count += result.packets.size()
		if first_hit < 0 and not result.packets.is_empty():
			first_hit = tick
		if first_hit >= 0 and tick >= first_hit + AFTER_HIT_STEPS:
			break
	if not _check(first_hit >= 0 and packet_count == 1 and float(victim.hp) < 100.0 and teams[0].combat_units[1].hits.has(teams[1].combat_identity(1)) and not teams[0].combat_units[1].previous.is_empty(),
		"Actual common-step sword must queue one real damaging enemy packet and retain original swing history", {"first_hit": first_hit, "packets": packet_count, "hp": victim.hp}):
		return
	var baseline_candidates: Dictionary = lab.contact_candidate_profile.duplicate(true)
	if not _rewind(initial):
		return
	lab.contact_input_reuse_enabled = true
	lab.contact_buckets_enabled = contact_buckets
	if redundant_work:
		_set_redundant_work(true)
	if compiled_source:
		TerrainArmy._contact_source.compiled_geometry_enabled = true
		TerrainArmy._contact_source.compiled_geometry_shadow_enabled = true
	var candidate_flags := _candidate_flags()
	var compiled_before: Dictionary = TerrainArmy._contact_source.compiled_geometry_profile.duplicate(true)
	if contact_buckets:
		var before_other := baseline_flags.duplicate()
		var after_other := candidate_flags.duplicate()
		before_other.erase("contact_buckets")
		after_other.erase("contact_buckets")
		if not _check(_exact(before_other, after_other), "Only contact bucket indexing may differ between the original replays"):
			return
	if compiled_source:
		var before_other := baseline_flags.duplicate()
		var after_other := candidate_flags.duplicate()
		for key: String in ["compiled_geometry", "compiled_geometry_shadow"]:
			before_other.erase(key)
			after_other.erase(key)
		if not _check(_exact(before_other, after_other), "Only Source compiled geometry/shadow may differ between the original replays"):
			return
	var pose_hits_before := _pose_result_hits()
	var live_before: Array[int] = [int(teams[0].combat_geometry_profile.live_cache_misses), int(teams[1].combat_geometry_profile.live_cache_misses)]
	for tick: int in expected.size():
		var actual := _step()
		if failed or not _check(_exact(actual, expected[tick]), "Queued damage and complete original rows differ at a common step", {"tick": tick, "state_equal": actual.get("state") == expected[tick].state, "packets_equal": actual.get("packets") == expected[tick].packets}):
			return
		if compiled_source and not _check(int(TerrainArmy._contact_source.compiled_geometry_profile.shadow_mismatches) == 0,
			"Compiled geometry shadow differs from the original native geometry", TerrainArmy._contact_source.compiled_geometry_profile.duplicate(true)):
			return
	if not _check(lab.resolve_calls == expected.size() and lab.sampled_input_slots > 0 and _owners_intact() and int(teams[0].combat_geometry_profile.live_cache_misses) > live_before[0] and int(teams[1].combat_geometry_profile.live_cache_misses) > live_before[1],
		"Both original live captains must actually sample; ordinary source and original owners remain"):
		return
	var pose_result_hits := _pose_result_hits() - pose_hits_before
	if redundant_work and not _check(pose_result_hits > 0, "Combined candidate must actually reuse an original same-batch pose result", {"pose_result_hits": pose_result_hits}):
		return
	var compiled_after: Dictionary = TerrainArmy._contact_source.compiled_geometry_profile.duplicate(true)
	var candidate_candidates := {}
	if contact_buckets:
		for key: String in lab.contact_candidate_profile:
			candidate_candidates[key] = int(lab.contact_candidate_profile[key]) - int(baseline_candidates[key])
		if not _check(int(candidate_candidates.bucket_builds) > 0 and int(candidate_candidates.rows_visited) < int(candidate_candidates.rows_before),
			"Candidate must actually build batch buckets and visit fewer original rows, not silently fall back", candidate_candidates):
			return
	var compiled_successes: int = int(compiled_after.sample_success) - int(compiled_before.sample_success)
	if compiled_source and not _check(compiled_successes > 0 and int(compiled_after.shadow_mismatches) == 0,
		"The actual damaging replay must use compiled geometry successfully, not only native fallbacks", compiled_after):
		return
	var report := {"status": "PASS", "steps_per_replay": expected.size(), "step_seconds": STEP, "first_actual_hit_step": first_hit,
		"actual_packets_per_replay": packet_count, "post_hit_steps": AFTER_HIT_STEPS, "all_step_row_packet_bits_exact": true,
		"actual_sampled_input_slots": lab.sampled_input_slots,
		"redundant_work": redundant_work, "baseline_flags": baseline_flags, "candidate_flags": candidate_flags,
		"compiled_source": compiled_source, "compiled_geometry_successes_delta": compiled_successes,
		"contact_buckets": contact_buckets, "ordered_contacts_and_native_pose_keys_exact": contact_buckets,
		"baseline_contact_candidates": baseline_candidates, "candidate_contact_candidates_delta": candidate_candidates,
		"compiled_geometry_before": compiled_before, "compiled_geometry_after": compiled_after,
		"candidate_pose_result_hits": pose_result_hits, "input_and_pose_results_detached_before_resolution": lab.boundary_clean,
		"final": _snapshot(), "items": item_baseline.size(), "original_rows": 6 if contact_buckets else 4, "original_live_presenters": 2,
		"ko_observed": float(victim.ko) > 0.0, "elapsed_usec": Time.get_ticks_usec() - started,
		"scope": "One actual original common-clock enemy sword hit plus subsequent steps, flag false/true on the same owners. Exact queued packets/full native row state including HP, KO, blocked, hits and previous; input detach before resolution. Not sustained battle, visual or FPS acceptance.",
		"test_sha256": FileAccess.get_sha256("res://scripts/tests/site_army_contact_inputs_flow_test.gd")}
	if redundant_work:
		report.scope = "One actual original common-clock enemy sword hit plus subsequent steps on the same owners. Input reuse remains enabled in both replays; weapon mesh filtering and same-batch pose-result reuse are OFF/OFF then ON/ON. Exact queued packets/full native rows including HP, KO, blocked, hits and previous; inputs and pose results detached before resolution. Not sustained battle, visual or FPS acceptance."
	if compiled_source:
		report.scope = "One actual original common-clock enemy damaging hit plus eight following 120Hz steps on the same original four people. Only Source native-pose compiled geometry/shadow changes OFF/OFF -> ON/ON; all other candidate settings fixed. Positive compiled sample success and zero shadow mismatches required; exact actual queued/resolved HP, KO, blocked, hits, previous, complete rows and item owners. No full battle/FPS claim."
	if contact_buckets:
		report.scope = "One actual original common-clock enemy damaging hit plus eight following 120Hz steps on the same original six people and two female live presenters; one distant ordinary row per team makes candidate culling observable. Only batch contact bucket indexing changes OFF -> ON; input reuse remains ON and all other candidate settings remain fixed. Exact ordered contact arrays, queued packets, full rows including HP/KO/fatigue/RNG/hits/previous, and native Source insertion-ordered sampled keys. Original row/item/presenter owners and pre-resolution cache detach preserved. Native collision only; no proxy, all-weapon, sustained battle or FPS claim."
	_write(report)
	for team: TerrainArmy in teams:
		team.free()
	lab.combat_armies.clear()
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_ARMY_CONTACT_INPUTS_FLOW_PASS ", JSON.stringify(report))
	quit(0)
