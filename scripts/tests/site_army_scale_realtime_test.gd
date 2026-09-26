extends SceneTree

const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const MechanismGate = preload("res://scripts/tests/fixtures/site_army_mechanism_gate.gd")
const MAIN := "res://scenes/terrain_lab/TerrainLab.tscn"
const FIXTURE := "res://scripts/tests/site_army_scale_realtime_test.gd"
const MECHANISM_RENDER_RESULT := MechanismGate.EVIDENCE_ROOT + "render_5k_mechanism.json"
const ARMY := "res://scripts/terrain_lab/terrain_army.gd"
const DEPLOYMENT_GUARD := "selected.size() > MAX_ROSTER_SIZE"
const BATCH := "res://scripts/terrain_lab/terrain_army_batch_view.gd"
const LEGACY_BATCH := "res://scripts/tests/fixtures/terrain_army_batch_view_phase3.gd.txt"
const PHASE4_ARMY := "res://scripts/tests/fixtures/terrain_army_hotpaths_phase4.gd"
const PHASE5_ARMY := "res://scripts/tests/fixtures/terrain_army_hotpaths_phase5.gd"
const PHASE6_ARMY := "res://scripts/tests/fixtures/terrain_army_prepare_phase6.gd"
const PHASE6_LAB := "res://scripts/tests/fixtures/terrain_lab_fatigue_phase6.gd"
const PHASE7_RENDER_ARMY := "res://scripts/tests/fixtures/terrain_army_render_phase7.gd.txt"
const PHASE7_BATCH := "res://scripts/tests/fixtures/terrain_army_batch_view_phase7.gd.txt"
const PHASE8_SNAPSHOT := "res://scripts/tests/fixtures/site_exchange_snapshot_phase8.gd.txt"
const PHASE8_LAB := "res://scripts/tests/fixtures/terrain_lab_queries_phase8.gd.txt"
const PHASE9_COMMANDS := "res://scripts/tests/fixtures/terrain_army_commands_phase9.gd.txt"
const PHASE10_PRESENCE := "res://scripts/tests/fixtures/terrain_army_presence_phase10.gd.txt"
const PHASE21_SEEDS := "res://scripts/tests/fixtures/terrain_army_encirclement_phase21.gd.txt"
const PHASE22_RANGED := "res://scripts/tests/fixtures/site_exchange_snapshot_phase22.gd.txt"
const TERRAIN_RENDERER := "res://scripts/terrain_lab/terrain_renderer.gd"
const PHASE24_TERRAIN := "res://scripts/tests/fixtures/terrain_renderer_phase24.gd.txt"
const PHASE11_PREPARE := "res://scripts/tests/fixtures/terrain_army_prepare_phase11.gd.txt"
const PHASE14_FRAME := "res://scripts/tests/fixtures/terrain_army_frame_phase14.gd.txt"
const PHASE14_BATCH := "res://scripts/tests/fixtures/terrain_army_batch_view_phase14.gd.txt"
const EDITOR := "res://scripts/ui/human_character_3d_editor.gd"
const SOURCE_AUDIT_PATHS := [ARMY, BATCH, EDITOR, TERRAIN_RENDERER,
	"res://scripts/terrain_lab/terrain_lab.gd", "res://scripts/terrain_lab/terrain_test_character.gd",
	"res://scripts/terrain_lab/site_combat_rules.gd", "res://scripts/terrain_lab/site_exchange_snapshot.gd"]
const PHASE12_COMPONENTS := "res://scripts/tests/fixtures/human_editor_components_phase12.gd.txt"
var per_team := 2500
var duration := 60.0
var formal_200 := false
var resident_clock_mode := "off"
var resident_clock_mode_explicit := false
var candidate_hot := false
var mechanism_diagnostic := false
var mechanism_evidence_path := ""
var mechanism_probe_report: Dictionary = {}
var lab: TerrainLab
var started := Time.get_ticks_usec()
var done := false
var out := ""
var report := {}
var continuous_visibility := false
var intervals: Array[float] = []
var frame_at: Array[float] = []
var source_hash := ""
var viewport_probe: Array[Viewport] = []
var owner_probe: Array[Node] = []
var stall_profile := false
var report_write_usec := 0
var long_stall_profile := false
var checkpoint_io_profile := false
var io_writes: Array = []
var checkpoint_prints: Array = []
var measurement_begin_usec := 0
var trace_stop_path := ""
var rd_timestamps_profile := false
var rd_timestamp_samples: Array[Dictionary] = []
var rd_last_timestamp_usec := -1
var trace_handshake := false
var trace_late_window := false
var trace_requested := false
var trace_root := "res://output/site_stall_localization_20260917/admin_capture_05/"
var s1_profile := false
var s1_anchors: Array[String] = []
var p1_profile := false

func _p1_instrument_army(source: String) -> String:
	# Diagnostic-only stage boundaries. The original calls and branch order stay intact.
	var edits: Array = [
		["\t_update_ranged_orders()\n\tif _try_exchange_encirclement():\n\t\treturn # Engaged front holds; free melee members use the same original step claims.\n",
			"\tvar p1_order_started := Time.get_ticks_usec()\n\t_update_ranged_orders()\n\tvar p1_order_mark := _profile_combat_stage(\"p1_ranged_orders\", p1_order_started)\n\tif _try_exchange_encirclement():\n\t\t_profile_combat_stage(\"p1_encirclement\", p1_order_mark)\n\t\treturn # Engaged front holds; free melee members use the same original step claims.\n\t_profile_combat_stage(\"p1_encirclement\", p1_order_mark)\n"],
		["\t\tif update_batch and native_render_enabled and _batch_render_active(): _batch_view.prepare_idle()\n",
			"\t\tif update_batch and native_render_enabled and _batch_render_active():\n\t\t\tvar p1_projection_started := Time.get_ticks_usec()\n\t\t\t_batch_view.prepare_idle()\n\t\t\t_profile_combat_stage(\"p1_projection\", p1_projection_started)\n"],
		["\t\tif grouped: _batch_view.finish_prepared_groups()\n",
			"\t\tif grouped:\n\t\t\tvar p1_group_started := Time.get_ticks_usec()\n\t\t\t_batch_view.finish_prepared_groups()\n\t\t\t_profile_combat_stage(\"p1_group\", p1_group_started)\n"],
		["\t\t\tif _uses_live_presenter(index):\n\t\t\t\t_sync_captain_combat(combat_frame(index), index)\n\t\t\telif not exchange_enabled or _visual_dirty:\n",
			"\t\t\tif _uses_live_presenter(index):\n\t\t\t\tvar p1_live_started := Time.get_ticks_usec()\n\t\t\t\t_sync_captain_combat(combat_frame(index), index)\n\t\t\t\t_profile_combat_stage(\"p1_live\", p1_live_started)\n\t\t\telif not exchange_enabled or _visual_dirty:\n"]]
	for edit: Array in edits:
		assert(source.count(edit[0]) == 1, "P1 Army source anchor changed")
		source = source.replace(edit[0], edit[1])
	return source

func _p1_instrument_batch(source: String) -> String:
	# Only the in-memory test resource gains these counters. The packed stream is
	# compared after production packing and is always submitted as before.
	var fields := """
var _p1_totals := {}
var _p1_frame := {}
var _p1_previous_runs := {}
var _p1_current_runs := {}

func _p1_add(key: String, value: int) -> void:
	_p1_frame[key] = int(_p1_frame.get(key, 0)) + value

func _p1_begin_flush() -> void:
	_p1_frame = {"observed_rows": _native_mask.size(), "grouped_rows": native_grouped_count,
		"exception_rows": rendered_count - native_grouped_count}
	_p1_current_runs = {}

func _p1_record_run(key: Vector2i, members: Array, start: int, stop: int, packed: PackedFloat32Array) -> void:
	var count := stop - start
	var ids := PackedInt32Array()
	ids.resize(count)
	for local_index in count: ids[local_index] = int(members[start + local_index])
	var previous: Array = _p1_previous_runs.get(key, [])
	var previous_ids: PackedInt32Array = previous[0] if previous.size() == 2 else PackedInt32Array()
	var previous_packed: PackedFloat32Array = previous[1] if previous.size() == 2 else PackedFloat32Array()
	var comparable := previous_ids.size() == count and previous_packed.size() == packed.size()
	var changed := 0
	var rebuilt := 0
	var frame_only := 0
	var other_payload := 0
	if comparable and previous_ids == ids and previous_packed == packed:
		pass
	else:
		for local_index in count:
			if not comparable or previous_ids[local_index] != ids[local_index]:
				changed += 1
				rebuilt += 1
				continue
			var offset := local_index * 12
			var has_frame_change := false
			var has_other_change := false
			for column in 12:
				if previous_packed[offset + column] != packed[offset + column]:
					if column == 9: has_frame_change = true
					else: has_other_change = true
			if has_frame_change or has_other_change:
				changed += 1
				if has_other_change: other_payload += 1
				else: frame_only += 1
	_p1_add("packed_rows", count)
	_p1_add("changed_rows", changed)
	_p1_add("rebuilt_rows", rebuilt)
	_p1_add("frame_only_changed_rows", frame_only)
	_p1_add("other_payload_changed_rows", other_payload)
	_p1_add("pack_bytes", packed.size() * 4)
	_p1_add("runs", 1)
	_p1_add("changed_runs" if changed > 0 else "unchanged_runs", 1)
	_p1_current_runs[key] = [ids, packed]

func _p1_finish_flush() -> void:
	_p1_previous_runs = _p1_current_runs
	for key: String in _p1_frame:
		_p1_totals[key] = int(_p1_totals.get(key, 0)) + int(_p1_frame[key])

"""
	var edits: Array = [
		["var _groups_ready := false\n", "var _groups_ready := false\n" + fields],
		["func flush() -> void:\n", "func flush() -> void:\n\t_p1_begin_flush()\n"],
		["\t\t_retain_active_gpu_keys()\n\t\treturn\n", "\t\t_retain_active_gpu_keys()\n\t\t_p1_finish_flush()\n\t\treturn\n"],
		["\t_retain_active_gpu_keys()\n\nfunc _retain_active_gpu_keys()", "\t_retain_active_gpu_keys()\n\t_p1_finish_flush()\n\nfunc _retain_active_gpu_keys()"],
		["\t\tvar packet := _pack_run(members, start, stop, float(page.scale))\n\t\tbatch.multimesh.buffer = packet[0]\n",
			"\t\tvar p1_started := Time.get_ticks_usec()\n\t\tvar packet := _pack_run(members, start, stop, float(page.scale))\n\t\t_p1_add(\"pack_usec\", Time.get_ticks_usec() - p1_started)\n\t\tp1_started = Time.get_ticks_usec()\n\t\t_p1_record_run(key, members, start, stop, packet[0])\n\t\t_p1_add(\"compare_usec\", Time.get_ticks_usec() - p1_started)\n\t\tp1_started = Time.get_ticks_usec()\n\t\tbatch.multimesh.buffer = packet[0]\n\t\t_p1_add(\"buffer_assign_usec\", Time.get_ticks_usec() - p1_started)\n\t\t_p1_add(\"submitted_buffer_bytes\", packet[0].size() * 4)\n"]]
	for edit: Array in edits:
		assert(source.count(edit[0]) == 1, "P1 BatchView source anchor changed")
		source = source.replace(edit[0], edit[1])
	return source

func _s1_instrument_army(source: String) -> String:
	# Insert-only diagnostics on the original resource preserve pure-owner guards.
	# Counters stay separate from combat_profile_usec, whose values are durations.
	var fields := "var _s1_reviews: Array[Dictionary] = []\nvar _s1_active_counts: Array[int] = []\nvar _s1_geometry_possible := false\n\n"
	var scan_setup := """
	var _s1_pre_scan_usec := Time.get_ticks_usec() - _s1_review_started
	var _s1_counts: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	_s1_active_counts = _s1_counts
	var _s1_duty_sizes := {}
	var _s1_duty_owner: Object = person_busy_query.get_object() if person_busy_query.is_valid() else null
	if _s1_duty_owner != null and _s1_duty_owner.get_script() == SiteController:
		var _s1_jobs: Dictionary = _s1_duty_owner.person_actions._jobs
		var _s1_target_ids := 0
		for _s1_job: Dictionary in _s1_jobs.values():
			if str(_s1_job.kind) == "equipment" and str(_s1_job.order.mode) == "team_issue":
				_s1_target_ids += _s1_job.order.target_ids.size()
		var _s1_deliveries := 0
		for _s1_supply: Dictionary in data.site.get("team_supply", {}).values():
			if not _s1_supply.get("delivery", {}).is_empty(): _s1_deliveries += 1
		_s1_duty_sizes = {"jobs": _s1_jobs.size(), "team_issue_target_ids": _s1_target_ids,
			"captivity": data.site.get("captivity", {}).size(), "work_ids": _s1_duty_owner.work_team._active_ids.size(),
			"supply_entries": data.site.get("team_supply", {}).size(), "deliveries": _s1_deliveries,
			"vehicles": data.site.get("vehicles", {}).size()}
	var _s1_scan_started := Time.get_ticks_usec()
"""
	var scan_row := """
		_s1_counts[0] += 1
		_s1_geometry_possible = false
		for _s1_direction: Vector2i in TerrainData.DIRECTIONS:
			if distance.has(cells[index] + _s1_direction):
				_s1_geometry_possible = true
				break
		_s1_counts[4 if _s1_geometry_possible else 5] += 1
"""
	var finish := """
	_s1_reviews.append({"frame_id": Engine.get_process_frames(), "team_id": team_id,
		"started_usec": _s1_review_started, "ended_usec": Time.get_ticks_usec(),
		"field_size": distance.size(), "filter_origins": filter_origins, "roster_size": combat_units.size(),
		"scan_rows": _s1_counts[0], "origins_rejected": _s1_counts[1], "qualification_entered": _s1_counts[2],
		"qualification_rejected": _s1_counts[2] - _s1_counts[3], "qualification_passed": _s1_counts[3],
		"geometry_possible": _s1_counts[4], "geometry_impossible": _s1_counts[5],
		"geometry_impossible_qualification": _s1_counts[6], "maneuver_calls": _s1_counts[7],
		"geometry_impossible_maneuver_calls": _s1_counts[8], "candidates": candidates.size(),
		"reserve_attempts": _s1_counts[9], "issued": issued, "duty_sizes": _s1_duty_sizes,
		"pre_scan_ms": _s1_pre_scan_usec / 1000.0, "scan_ms": _s1_scan_usec / 1000.0,
		"sort_ms": _s1_sort_usec / 1000.0, "reserve_ms": (Time.get_ticks_usec() - _s1_reserve_started) / 1000.0})
"""
	# Each edit is [unique original anchor, inserted prefix, inserted suffix].
	var edits: Array = [
		["func _try_exchange_encirclement() -> bool:\n", fields, "\tvar _s1_review_started := Time.get_ticks_usec()\n"],
		["\tvar candidates: Array[Dictionary] = []\n\tfor index in range(combat_units.size()):\n\t\tif filter_origins", scan_setup.trim_prefix("\n"), ""],
		["\tvar candidates: Array[Dictionary] = []\n\tfor index in range(combat_units.size()):\n", "", scan_row.trim_prefix("\n")],
		["\t\tif filter_origins and not origins.has(cells[index]):\n", "", "\t\t\t_s1_counts[1] += 1\n"],
		["\t\tif pinned.has(index) or not is_member(index) or is_controlled_person(index) or not combat_can_act(index)", "\t\t_s1_counts[2] += 1\n\t\tif not _s1_geometry_possible: _s1_counts[6] += 1\n", ""],
		["\t\tvar best := INVALID_CELL\n\t\tvar cost := ENCIRCLEMENT_ROUTE_DISTANCE\n", "\t\t_s1_counts[3] += 1\n", ""],
		["\tcandidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:\n\t\treturn int(a.cost) < int(b.cost) if int(a.cost) != int(b.cost) else int(a.id) < int(b.id))\n", "\t_s1_active_counts = []\n\tvar _s1_scan_usec := Time.get_ticks_usec() - _s1_scan_started\n\tvar _s1_sort_started := Time.get_ticks_usec()\n", "\tvar _s1_sort_usec := Time.get_ticks_usec() - _s1_sort_started\n\tvar _s1_reserve_started := Time.get_ticks_usec()\n"],
		["\t\tif _reserve_combat_step(index, candidate.step):\n", "\t\t_s1_counts[9] += 1\n", ""],
		["\treturn true # A blocked flank waits;", finish.trim_prefix("\n"), ""],
		["func _exchange_maneuver_blocked(index: int) -> bool:\n", "", "\tif not _s1_active_counts.is_empty():\n\t\t_s1_active_counts[7] += 1\n\t\tif not _s1_geometry_possible: _s1_active_counts[8] += 1\n"],
		["\t_update_ranged_orders()\n", "\tvar _s1_ranged_started := Time.get_ticks_usec()\n", "\t_profile_combat_stage(\"s1_ranged_orders\", _s1_ranged_started)\n"],
		["\tif _try_exchange_encirclement():\n", "\tvar _s1_encirclement_started := Time.get_ticks_usec()\n", "\t\t_profile_combat_stage(\"s1_encirclement\", _s1_encirclement_started)\n"],
		["\t\treturn # Engaged front holds; free melee members use the same original step claims.\n", "", "\t_profile_combat_stage(\"s1_encirclement\", _s1_encirclement_started)\n"],
		["\t\tif update_batch and native_render_enabled and _batch_render_active(): _batch_view.prepare_idle()\n", "\t\tvar _s1_projection_started := Time.get_ticks_usec()\n", "\t\t_profile_combat_stage(\"s1_projection\", _s1_projection_started)\n"],
		["\n\t\t\t\t_sync_captain_combat(combat_frame(index), index)\n", "\n\t\t\t\tvar _s1_live_started := Time.get_ticks_usec()\n", "\t\t\t\t_profile_combat_stage(\"s1_live\", _s1_live_started)\n"],
		["\t\tif grouped: _batch_view.finish_prepared_groups()\n", "\t\tvar _s1_groups_started := Time.get_ticks_usec()\n", "\t\t_profile_combat_stage(\"s1_groups\", _s1_groups_started)\n"]]
	var instrumented := source
	s1_anchors.clear()
	for edit: Array in edits:
		assert(instrumented.count(edit[0]) == 1, "S1 source anchor changed: " + str(edit[0]))
		instrumented = instrumented.replace(edit[0], str(edit[1]) + str(edit[0]) + str(edit[2]))
		s1_anchors.append(str(edit[0]))
	var restored := instrumented
	for i in range(edits.size() - 1, -1, -1):
		var edit: Array = edits[i]
		var expanded := str(edit[1]) + str(edit[0]) + str(edit[2])
		assert(restored.count(expanded) == 1, "S1 insertion reversal changed")
		restored = restored.replace(expanded, edit[0])
	assert(restored == source, "S1 must preserve every original statement")
	return instrumented

class StallFrameEdge extends Node:
	var marks: Array[int]
	var first := false
	func _process(_delta: float) -> void:
		if not first: marks[0] = Time.get_ticks_usec()
	func _physics_process(_delta: float) -> void:
		if first: marks[1] = Time.get_ticks_usec()
		else: marks[2] += Time.get_ticks_usec() - marks[1]

func _instrument_owner(path: String, methods: Array[String], trace_slow: bool = false) -> void:
	# Diagnostic only: wrap existing callbacks in this process, never save the
	# altered script or use this instrumented run as an FPS acceptance score.
	var script := load(path) as GDScript
	var source := script.source_code
	var wrappers := "\n"
	for method: String in methods:
		var matcher := RegEx.new()
		assert(matcher.compile("(?m)^func " + method + "\\(([^)]*)\\) -> (void|bool):") == OK)
		assert(matcher.search_all(source).size() == 1)
		var found := matcher.search(source)
		var arguments := found.get_string(1)
		var names := PackedStringArray()
		for argument: String in arguments.split(",", false): names.append(argument.get_slice(":", 0).strip_edges())
		var call_argument := ", ".join(names)
		var returns_value := found.get_string(2) == "bool"
		source = source.replace(found.get_string(), found.get_string().replace(method, "_phase26" + method))
		wrappers += "\n" + found.get_string() + "\n\tvar begin := Time.get_ticks_usec()\n\t" + ("var _probe_return: bool = " if returns_value else "") + "_phase26%s(%s)\n\tvar timings: Dictionary = get_meta(&\"phase26_owner_usec\", {})\n\ttimings[\"%s\"] = int(timings.get(\"%s\", 0)) + Time.get_ticks_usec() - begin\n\tset_meta(&\"phase26_owner_usec\", timings)\n" % [method, call_argument, method, method]
		if trace_slow:
			wrappers += "\tvar end := Time.get_ticks_usec()\n\tif end - begin >= 5000:\n\t\tvar events: Array = get_meta(&\"stall_settle_events\", [])\n\t\tevents.append({\"method\": \"%s\", \"begin_ticks_usec\": begin, \"end_ticks_usec\": end, \"ms\": (end - begin) / 1000.0, \"identity\": %s, \"stack\": get_stack()})\n\t\tset_meta(&\"stall_settle_events\", events)\n" % [method, "identity" if method == "equipment_changed" else "-1"]
		if returns_value: wrappers += "\treturn _probe_return\n"
	script.source_code = source + wrappers
	assert(script.reload(true) == OK)

func _instrument_settlement() -> void:
	# Insert only timers; verify removal restores the exact original statements.
	var script := load("res://scripts/terrain_lab/terrain_lab.gd") as GDScript
	var matcher := RegEx.new()
	assert(matcher.compile("(?ms)^func _advance_combat\\([^\\n]*\\n.*?(?=^func )") == OK)
	assert(matcher.search_all(script.source_code).size() == 1)
	var original := matcher.search(script.source_code).get_string()
	var measured := original.replace("\r\n", "\n")
	for pair: Array in [
		["\t\tif site_controller != null:\n\t\t\tsite_controller.settle_person_deaths(elapsed)", "\t\tvar _settle_mark := Time.get_ticks_usec()\n"],
		["\t\t\tfor result: Dictionary in site_controller.person_actions.settle_after_contacts():", "\t\t\t_settle_mark = _combat_profile_stage(\"settle_deaths\", _settle_mark)\n"],
		["\t\t\tsite_controller.settle_supply_deliveries()", "\t\t\t_settle_mark = _combat_profile_stage(\"settle_jobs_and_messages\", _settle_mark)\n"],
		["\t\tfor team: TerrainArmy in combat_armies:\n\t\t\tteam.settle_combat_command()", "\t\t_settle_mark = _combat_profile_stage(\"settle_supply\", _settle_mark)\n"],
		["\t\tif site_controller != null:\n\t\t\tsite_controller.check_family_death()", "\t\t_settle_mark = _combat_profile_stage(\"settle_commands\", _settle_mark)\n"]]:
		assert(measured.count(str(pair[0])) == 1)
		measured = measured.replace(pair[0], str(pair[1]) + str(pair[0]))
	var family := "\t\t\tsite_controller.check_family_death()\n"
	assert(measured.count(family) == 1)
	measured = measured.replace(family, family + "\t\t\t_settle_mark = _combat_profile_stage(\"settle_family\", _settle_mark)\n")
	var restored := ""
	for line: String in measured.split("\n"):
		if not line.strip_edges().begins_with("var _settle_mark") and not line.strip_edges().begins_with("_settle_mark ="):
			restored += line + "\n"
	assert(restored.trim_suffix("\n") == original.replace("\r\n", "\n"), "Settlement probe changed original statements")
	script.source_code = script.source_code.replace(original, measured)
	assert(script.reload(true) == OK)
	_instrument_owner("res://scripts/terrain_lab/site_controller.gd", ["settle_person_deaths", "equipment_changed", "settle_supply_deliveries", "check_family_death", "show_result"], true)
	_instrument_owner(ARMY, ["settle_combat_command"], true)
	_instrument_owner(EDITOR, ["restore_appearance"], true)
	report["settlement_profile"] = {"original_statements_preserved": true, "event_threshold_ms": 5,
		"note": "Diagnostic inclusive times; nested equipment/appearance costs overlap deaths or commands. Slow-call timestamps and stacks are retained. No gameplay or file-source changes."}

func _initialize() -> void:
	mechanism_diagnostic = "--mechanism-diagnostic" in OS.get_cmdline_user_args()
	if mechanism_diagnostic:
		assert(OS.get_cmdline_user_args().size() == 1, "Mechanism diagnostic uses only its dedicated flag and the original 5k settings")
	candidate_hot = "--candidate-hot" in OS.get_cmdline_user_args() or mechanism_diagnostic
	p1_profile = "--p1-profile" in OS.get_cmdline_user_args()
	if p1_profile:
		for required: String in ["--profile", "--spike-profile", "--stall-profile", "--long-stall-profile", "--viewport-profile"]:
			assert(required in OS.get_cmdline_user_args(), "P1 needs " + required)
	long_stall_profile = "--long-stall-profile" in OS.get_cmdline_user_args()
	trace_handshake = "--trace-handshake" in OS.get_cmdline_user_args()
	trace_late_window = "--trace-late-window" in OS.get_cmdline_user_args()
	if trace_late_window:
		assert(trace_handshake, "Late-window capture requires the approved trace handshake")
		trace_root = "res://output/site_stall_localization_20260917/admin_capture_06/"
	if trace_handshake:
		assert(long_stall_profile and FileAccess.file_exists(trace_root + "armed.json"), "Start the explicitly approved trace controller first")
		trace_stop_path = trace_root + "stop.request"
	rd_timestamps_profile = "--rd-timestamps-profile" in OS.get_cmdline_user_args()
	if rd_timestamps_profile:
		assert(long_stall_profile, "RD timestamps require the existing full frame boundaries")
		assert(int(ProjectSettings.get_setting("rendering/driver/threads/thread_model", 1)) != 2, "This diagnostic journal requires the current non-threaded renderer")
	checkpoint_io_profile = "--checkpoint-io-profile" in OS.get_cmdline_user_args()
	continuous_visibility = "--continuous-visibility" in OS.get_cmdline_user_args()
	stall_profile = "--stall-profile" in OS.get_cmdline_user_args()
	if long_stall_profile: stall_profile = true
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--per-team="): per_team = clampi(int(argument.get_slice("=", 1)), 1, 5000)
		if argument.begins_with("--seconds="): duration = clampf(float(argument.get_slice("=", 1)), 5.0, 600.0 if long_stall_profile else 120.0)
		if argument.begins_with("--resident-clock="):
			assert(not resident_clock_mode_explicit, "Resident clock mode may only be specified once")
			resident_clock_mode_explicit = true
			resident_clock_mode = argument.get_slice("=", 1)
			assert(resident_clock_mode in ["on", "off"], "Resident clock mode must be on or off")
		if argument.begins_with("--mechanism-evidence="):
			assert(mechanism_evidence_path.is_empty(), "Mechanism evidence may only be specified once")
			mechanism_evidence_path = argument.trim_prefix("--mechanism-evidence=")
		if argument.begins_with("--trace-stop-file="):
			trace_stop_path = argument.get_slice("=", 1)
			assert(long_stall_profile and trace_stop_path in ["res://output/site_stall_localization_20260917/admin_capture_01/stop.request", "res://output/site_stall_localization_20260917/admin_capture_02/stop.request", "res://output/site_stall_localization_20260917/admin_capture_03/stop.request", "res://output/site_stall_localization_20260917/admin_capture_04/stop.request"])
	if trace_late_window: assert(duration >= 360.0, "Keep the game alive through late capture and save")
	formal_200 = (per_team == 100 and duration == 60.0 and OS.get_cmdline_user_args().size() == 2
		and "--per-team=100" in OS.get_cmdline_user_args() and "--seconds=60" in OS.get_cmdline_user_args())
	out = (MechanismGate.EVIDENCE_ROOT + "render_diagnostic_run_%d_%d" if mechanism_diagnostic
		else "res://output/site_army_5k_event_update_20260926/p1_current_source/run_%d_%d" if p1_profile
		else ("res://output/encirclement_gap_closure_20260925/performance_200/run_%d_%d" if formal_200
		else "res://output/site_army_scale_20260914/run_%d_%d")) % [int(Time.get_unix_time_from_system()), OS.get_process_id()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	_run.call_deferred()

func _request_admin_trace(battle_at: float) -> void:
	assert(not trace_requested and not FileAccess.file_exists(trace_root + "start.request"), "Never reuse a trace capture")
	var write_begin := Time.get_ticks_usec()
	var request := FileAccess.open(trace_root + "start.pending", FileAccess.WRITE)
	assert(request != null)
	request.store_string(JSON.stringify({"pid": OS.get_process_id(), "engine_main_thread_id": OS.get_main_thread_id(), "output": out, "battle_at_seconds": battle_at}))
	request.close()
	assert(DirAccess.rename_absolute(trace_root + "start.pending", trace_root + "start.request") == OK)
	trace_requested = true
	report["admin_trace_request"] = {"battle_at_seconds": battle_at, "write_ms": (Time.get_ticks_usec() - write_begin) / 1000.0, "late_window": trace_late_window}

func _instrument_actor_seek() -> void:
	var script := load("res://scripts/terrain_lab/terrain_test_character.gd") as GDScript
	var line := "\t\t\teditor.animation_player.seek(visual_state.animation_time, true)\n\t\t\t_exchange_pose_dirty = false"
	assert(script.source_code.count(line) == 1)
	script.source_code = script.source_code.replace(line,
		"\t\t\tvar seek_begin := Time.get_ticks_usec()\n\t\t\teditor.animation_player.seek(visual_state.animation_time, true)\n\t\t\tvar timings: Dictionary = get_meta(&\"phase26_owner_usec\", {})\n\t\t\ttimings[\"frame_seek\"] = int(timings.get(\"frame_seek\", 0)) + Time.get_ticks_usec() - seek_begin\n\t\t\tset_meta(&\"phase26_owner_usec\", timings)\n\t\t\t_exchange_pose_dirty = false")
	assert(script.reload(true) == OK)

func _instrument_animation_switch() -> void:
	# Diagnostic only: split the observed 304 ms switch, retaining every original
	# statement and callback order. Never save the instrumented editor script.
	var script := load(EDITOR) as GDScript
	var matcher := RegEx.new()
	assert(matcher.compile("(?ms)^func _play_selected_animation\\([^\\n]*\\n.*?(?=^func )") == OK)
	assert(matcher.search_all(script.source_code).size() == 1)
	var original := matcher.search(script.source_code).get_string()
	var measured := original.replace("\tvar play_anim:", "\tvar _stall_mark := Time.get_ticks_usec()\n\tvar play_anim:")
	for stage: Array in [
		["lookup", "\tvar requested_loop :="],
		["loop_mode", "\tanimation_player.speed_scale ="],
		["speed", "\tif animation_player.current_animation !="],
		["morph_reset", "\t\tvar skeleton :="],
		["play_state", "\t_update_weapon_sheath_state()"],
		["weapons", "\t_sync_mount_animation()"],
		["mount", "\t_update_preview_framing()"]]:
		var anchor: String = stage[1]
		assert(measured.count(anchor) == 1)
		var indent := "\t\t" if anchor.begins_with("\t\t") else "\t"
		measured = measured.replace(anchor, indent + "_stall_mark = _stall_switch_stage(\"%s\", _stall_mark)\n" % stage[0] + anchor)
	var first_play := "\t\tanimation_player.play(play_anim)\n\tif _is_playing:"
	assert(measured.count(first_play) == 1)
	measured = measured.replace(first_play, "\t\t_stall_mark = _stall_switch_stage(\"bone_reset\", _stall_mark)\n\t\tanimation_player.play(play_anim)\n\t\t_stall_mark = _stall_switch_stage(\"first_play\", _stall_mark)\n\tif _is_playing:")
	measured = measured.replace("\t_update_preview_framing()\n", "\t_update_preview_framing()\n\t_stall_switch_stage(\"framing\", _stall_mark)\n")
	var helper := """
func _stall_switch_stage(stage: String, begin: int) -> int:
	var end := Time.get_ticks_usec()
	var elapsed := end - begin
	var timings: Dictionary = get_meta(&"phase26_owner_usec", {})
	var key := "switch_" + stage
	timings[key] = int(timings.get(key, 0)) + elapsed
	set_meta(&"phase26_owner_usec", timings)
	if elapsed >= 100000:
		var events: Array = get_meta(&"stall_switch_events", [])
		events.append({"stage": stage, "ms": elapsed / 1000.0, "begin_ticks_usec": begin,
			"end_ticks_usec": end, "end_unix_usec": int(Time.get_unix_time_from_system() * 1000000.0),
			"selected": str(_selected_animation), "current": str(animation_player.current_animation), "stack": get_stack()})
		set_meta(&"stall_switch_events", events)
	return Time.get_ticks_usec()
"""
	script.source_code = script.source_code.replace(original, measured) + helper
	assert(script.reload(true) == OK)

func _process(_delta: float) -> bool:
	if not done and Time.get_ticks_usec() - started > int((duration + 165.0 if long_stall_profile else 285.0) * 1000000):
		_fail("Internal bounded verification deadline")
	return false

func _write() -> void:
	var write_started := Time.get_ticks_usec() if stall_profile else 0
	if checkpoint_io_profile:
		var begin := Time.get_ticks_usec()
		var file := FileAccess.open(out + "/measurements.json", FileAccess.WRITE)
		assert(file != null, "Diagnostic report open failed")
		var opened := Time.get_ticks_usec()
		var payload := JSON.stringify(report, "\t")
		var serialized := Time.get_ticks_usec()
		file.store_string(payload)
		var stored := Time.get_ticks_usec()
		file.close()
		var closed := Time.get_ticks_usec()
		io_writes.append({"at": (begin - measurement_begin_usec) / 1000000.0 if measurement_begin_usec > 0 else -1.0,
			"stage": str(report.get("stage", "")), "status": str(report.get("status", "")),
			"open_ms": (opened - begin) / 1000.0, "serialize_ms": (serialized - opened) / 1000.0,
			"store_ms": (stored - serialized) / 1000.0, "close_ms": (closed - stored) / 1000.0,
			"total_ms": (closed - begin) / 1000.0, "characters": payload.length()})
		if stall_profile: report_write_usec += closed - write_started
		return
	var file := FileAccess.open(out + "/measurements.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	if stall_profile: report_write_usec += Time.get_ticks_usec() - write_started

func _fail(reason: String) -> void:
	done = true
	report["status"] = "INCOMPLETE"
	report["reason"] = reason
	_write()
	if mechanism_diagnostic:
		_write_render_mechanism("FAIL", reason)
	push_error(reason)
	quit(1)

func _write_render_mechanism(status: String, reason: String) -> void:
	var result: Dictionary = mechanism_probe_report.duplicate(true)
	result["schema"] = 1
	result["status"] = status
	result["reason"] = reason
	result["generated_by"] = FIXTURE
	result["scene"] = MAIN
	result["preset"] = "PLAINS"
	result["seed"] = 581
	result["per_team"] = per_team
	result["teams"] = 2
	result["engine"] = Engine.get_version_info()
	result["renderer"] = RenderingServer.get_current_rendering_method()
	result["driver"] = RenderingServer.get_current_rendering_driver_name()
	result["window_pixels"] = str(DisplayServer.window_get_size())
	result["logical_viewport"] = str(lab.get_viewport_rect().size) if lab != null else ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MechanismGate.EVIDENCE_ROOT))
	var file := FileAccess.open(MECHANISM_RENDER_RESULT, FileAccess.WRITE)
	if file == null:
		push_error("Could not write 5k render mechanism result")
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()

func _render_probe_frame() -> Dictionary:
	var sides: Array = []
	for side in range(2):
		var team: TerrainArmy = lab.combat_armies[side]
		var view: Variant = team._batch_view
		sides.append({"side": side, "hot_active": team.has_method("combat_hot_active") and bool(team.call("combat_hot_active")),
			"rendered_count": int(view.rendered_count) if view != null else -1,
			"moving_count": team.moving_count(), "cells_sha256": str(team.cells).sha256_text(),
			"stats": view.call("mechanism_stats") if view != null and view.has_method("mechanism_stats") else {}})
	return {"clock": _clock(), "exchange_count": lab.exchange_count,
		"drawn_frame": Engine.get_frames_drawn(), "sides": sides}

func _render_probe_assessment(frames: Array, stationary_window: bool) -> Dictionary:
	var zero_static := [0, 0]
	var zero_upload := [0, 0]
	var unchanged_output := [0, 0]
	var upload_without_change := [0, 0]
	var full_projection := [0, 0]
	var sampled := [0, 0]
	var stable_cells := ["", ""]
	var stable_positions := true
	var counts_valid := frames.size() >= 4
	for frame: Variant in frames:
		if not frame is Dictionary or not frame.get("sides") is Array or frame.sides.size() != 2:
			counts_valid = false
			continue
		for side in range(2):
			var observed: Variant = frame.sides[side]
			if not observed is Dictionary or not observed.get("stats") is Dictionary:
				counts_valid = false
				continue
			var stats: Dictionary = observed.stats
			if not bool(observed.get("hot_active", false)) or int(observed.get("rendered_count", -1)) != per_team - 1:
				counts_valid = false
			if int(observed.get("moving_count", -1)) < 0 or str(observed.get("cells_sha256", "")).length() != 64:
				counts_valid = false
			if stationary_window:
				if int(observed.moving_count) != 0: stable_positions = false
				if stable_cells[side].is_empty(): stable_cells[side] = str(observed.cells_sha256)
				elif stable_cells[side] != str(observed.cells_sha256): stable_positions = false
			if int(stats.get("static_observations", -1)) >= per_team - 1 \
					or int(stats.get("ground_projections", -1)) >= per_team - 1:
				full_projection[side] += 1
			if int(stats.get("animation_samples", 0)) > 0: sampled[side] += 1
			if int(stats.get("changed_outputs", -1)) < 0 \
					or int(stats.get("changed_outputs", -1)) > int(observed.rendered_count):
				counts_valid = false
			if int(stats.get("static_observations", -1)) == 0 and int(stats.get("ground_projections", -1)) == 0 \
					and int(stats.get("row_rebuilds", -1)) == 0 and int(stats.get("run_rebuilds", -1)) == 0 \
					and int(stats.get("animation_samples", 0)) > 0:
				zero_static[side] += 1
			if int(stats.get("changed_outputs", -1)) == 0:
				unchanged_output[side] += 1
				if int(stats.get("packed_instances", -1)) == 0 and int(stats.get("packed_bytes", -1)) == 0 \
						and int(stats.get("multimesh_setters", -1)) == 0 \
						and int(stats.get("multimesh_bytes", -1)) == 0 \
						and int(stats.get("gpu_dispatches", -1)) == 0:
					zero_upload[side] += 1
				else:
					upload_without_change[side] += 1
	var first: Dictionary = frames[0] if frames.size() >= 1 and frames[0] is Dictionary else {}
	var last: Dictionary = frames.back() if frames.size() >= 1 and frames.back() is Dictionary else {}
	var clock_advance := float(last.get("clock", 0.0)) - float(first.get("clock", 0.0))
	var exchange_advance := int(last.get("exchange_count", 0)) - int(first.get("exchange_count", 0))
	var passed := counts_valid and clock_advance > 0.0 and mini(sampled[0], sampled[1]) >= 2 \
		and maxi(full_projection[0], full_projection[1]) == 0 \
		and maxi(upload_without_change[0], upload_without_change[1]) == 0
	if stationary_window:
		passed = passed and stable_positions and mini(zero_static[0], zero_static[1]) >= 2
	else:
		passed = passed and exchange_advance > 0
	return {"passed": passed, "zero_static_frames": zero_static,
		"zero_upload_frames": zero_upload, "unchanged_output_frames": unchanged_output,
		"upload_without_change_frames": upload_without_change,
		"full_projection_frames": full_projection,
		"animation_sample_frames": sampled, "clock_advance": clock_advance,
		"exchange_advance": exchange_advance, "stable_positions": stable_positions,
		"all_batch_counts_and_activation_valid": counts_valid}

func _run_render_mechanism_diagnostic() -> void:
	_event("diagnosing_5k_render_mechanism")
	var source_capture: Dictionary = MechanismGate.capture_source_manifest()
	mechanism_probe_report = {"source_sha256": source_capture.hashes,
		"source_errors": source_capture.errors, "stationary_frames": [], "late_frames": [],
		"initial_visibility": report.initial_visibility,
		"product_hot_preconfigured": report.get("product_hot_preconfigured", []),
		"viewport_size": [root.get_texture().get_size().x, root.get_texture().get_size().y],
		"ordinary_expected": (per_team - 1) * 2,
		"diagnostic_probe_only": true}
	if not source_capture.errors.is_empty() or per_team != 2500 or report.renderer != "forward_plus" or report.driver != "d3d12" \
			or str(report.window_pixels) != str(Vector2i(1600, 900)) or str(report.logical_viewport) != str(Vector2(2560, 1440)) \
			or int(report.initial_visibility.visible_textured_sprites) != 5000:
		_fail("5k render diagnostic setup or source manifest invalid")
		return
	var readiness: Array[Dictionary] = []
	for side in range(2):
		var observed_team: TerrainArmy = lab.combat_armies[side]
		var observed_view: Variant = observed_team._batch_view
		readiness.append({"side": side, "view_present": observed_view != null,
			"view_script": observed_view.get_script().resource_path if observed_view != null else "",
			"stats_method": observed_view != null and observed_view.has_method("mechanism_stats"),
			"reset_method": observed_view != null and observed_view.has_method("_reset_mechanism"),
			"hot_method": observed_team.has_method("combat_hot_active"),
			"hot_active": observed_team.has_method("combat_hot_active") and observed_team.call("combat_hot_active") == true})
	mechanism_probe_report["readiness"] = readiness
	for side in range(2):
		var team: TerrainArmy = lab.combat_armies[side]
		if team._batch_view == null or not team._batch_view.has_method("mechanism_stats") \
				or not team._batch_view.has_method("_reset_mechanism") \
				or not team.has_method("combat_hot_active") or not bool(team.call("combat_hot_active")):
			_write_render_mechanism("FAIL", "5k render diagnostic readiness failed")
			_fail("5k render diagnostic readiness failed: " + str(readiness))
			return
		team._batch_view.set("mechanism_enabled", true)
	# Sample frames while the original main scene is processing. A paused Lab
	# produces all-zero counters without exercising the retained render path.
	lab.set_process(true)
	for tick in range(4):
		for side in range(2): lab.combat_armies[side]._batch_view.call("_reset_mechanism")
		await process_frame
		await RenderingServer.frame_post_draw
		mechanism_probe_report.stationary_frames.append(_render_probe_frame())
	for side in range(2): lab.combat_armies[side]._batch_view.set("mechanism_enabled", false)
	mechanism_probe_report["stationary_assessment"] = _render_probe_assessment(mechanism_probe_report.stationary_frames, true)
	var clock_start := _clock()
	var deadline := Time.get_ticks_usec() + 180000000
	for side in range(2):
		var team: TerrainArmy = lab.combat_armies[side]
		team.call("combat_hot_reset_stats")
		team.set("combat_hot_diagnostics_enabled", true)
	while _clock() - clock_start < 40.0 and Time.get_ticks_usec() < deadline:
		await RenderingServer.frame_post_draw
	mechanism_probe_report["late_clock_advance"] = _clock() - clock_start
	mechanism_probe_report["late_exchange_count"] = lab.exchange_count
	if float(mechanism_probe_report.late_clock_advance) < 40.0 or int(mechanism_probe_report.late_exchange_count) <= 0:
		lab.set_process(false)
		for side in range(2): lab.combat_armies[side].set("combat_hot_diagnostics_enabled", false)
		_fail("5k render diagnostic did not reach active late combat within 180 seconds")
		return
	for side in range(2): lab.combat_armies[side]._batch_view.set("mechanism_enabled", true)
	for tick in range(12):
		for side in range(2): lab.combat_armies[side]._batch_view.call("_reset_mechanism")
		await process_frame
		await RenderingServer.frame_post_draw
		mechanism_probe_report.late_frames.append(_render_probe_frame())
	lab.set_process(false)
	for side in range(2): lab.combat_armies[side]._batch_view.set("mechanism_enabled", false)
	var late_hot_stats: Array[Dictionary] = []
	for side in range(2):
		var team: TerrainArmy = lab.combat_armies[side]
		late_hot_stats.append({"side": side, "stats": team.call("combat_hot_stats")})
		team.set("combat_hot_diagnostics_enabled", false)
	mechanism_probe_report["late_hot_stats"] = late_hot_stats
	mechanism_probe_report["late_assessment"] = _render_probe_assessment(mechanism_probe_report.late_frames, false)
	mechanism_probe_report["final_visibility"] = _visibility()
	mechanism_probe_report["final_viewport_size"] = [root.get_texture().get_size().x, root.get_texture().get_size().y]
	var final_capture: Dictionary = MechanismGate.capture_source_manifest()
	mechanism_probe_report["source_unchanged"] = final_capture.errors.is_empty() and final_capture.hashes == source_capture.hashes
	var passed := bool(mechanism_probe_report.stationary_assessment.passed) \
		and bool(mechanism_probe_report.late_assessment.passed) \
		and bool(mechanism_probe_report.source_unchanged) \
		and int(mechanism_probe_report.final_visibility.visible_textured_sprites) == 5000
	_write_render_mechanism("PASS" if passed else "FAIL", "" if passed else "5k render mechanism assertion failed")
	report["render_mechanism_result"] = MECHANISM_RENDER_RESULT
	report["render_mechanism_passed"] = passed
	report["status"] = "PASS" if passed else "FAIL"
	_write()
	if not passed: push_error("5k render mechanism diagnostic failed: " + MECHANISM_RENDER_RESULT)
	quit(0 if passed else 1)

func _event(stage: String) -> void:
	report["stage"] = stage
	report["elapsed_wall_seconds"] = (Time.get_ticks_usec() - started) / 1000000.0
	_write()
	print("FPS5000_STAGE ", stage, " output=", out)

func _clock() -> float:
	return lab._exchange_round * TerrainLab.EXCHANGE_QUERY_STEP + lab._exchange_phase + lab._action_time_remainder

func _team_clock_enabled(team: TerrainArmy) -> bool:
	return team.has_method("materialized_combat_rows") and _has_property(team, "resident_clock_enabled") \
		and team.get("resident_clock_enabled") == true

func _has_property(object: Object, name: String) -> bool:
	for property: Dictionary in object.get_property_list():
		if str(property.name) == name: return true
	return false

func _resident_clock_team_modes() -> Array[Dictionary]:
	var modes: Array[Dictionary] = []
	for side in range(2):
		var team: TerrainArmy = lab.combat_armies[side]
		var supported := team.has_method("materialized_combat_rows")
		var enabled := _team_clock_enabled(team)
		var native_ready := false
		if enabled:
			var clock: Variant = team.get("_combat_clock")
			native_ready = clock != null and bool(clock.call("ready", team.combat_units.size()))
		modes.append({"side": side, "supported": supported, "enabled": enabled, "native_ready": native_ready})
	return modes

func _candidate_hot_team_modes() -> Array[Dictionary]:
	var modes: Array[Dictionary] = []
	for side in range(2):
		var team: TerrainArmy = lab.combat_armies[side]
		modes.append({"side": side, "supported": team.has_method("combat_hot_active"),
			"active": team.has_method("combat_hot_active") and bool(team.call("combat_hot_active"))})
	return modes

func _candidate_hot_both_active(modes: Array[Dictionary]) -> bool:
	return modes.size() == 2 and int(modes[0].side) == 0 and int(modes[1].side) == 1 \
		and bool(modes[0].active) and bool(modes[1].active)

func _audit_sources(stage: String) -> bool:
	var sources := {}
	var all_match := true
	for path: String in SOURCE_AUDIT_PATHS:
		var disk_hash := FileAccess.get_sha256(path)
		var disk_text := FileAccess.get_file_as_string(path).replace("\r\n", "\n")
		var runtime_text := (load(path) as GDScript).source_code.replace("\r\n", "\n")
		var matches_disk := disk_text == runtime_text
		var expected := disk_text
		var guard_replacements := 0
		if path == ARMY and bool(report.deployment_override_applied):
			guard_replacements = disk_text.count(DEPLOYMENT_GUARD)
			if guard_replacements == 1:
				expected = disk_text.replace(DEPLOYMENT_GUARD, "selected.size() > %d" % int(report.deployment_limit))
		if p1_profile and path == ARMY: expected = _p1_instrument_army(expected)
		if p1_profile and path == BATCH: expected = _p1_instrument_batch(expected)
		var matches_allowlist := runtime_text == expected and (path != ARMY or not bool(report.deployment_override_applied) or guard_replacements == 1)
		sources[path] = {"disk_sha256": disk_hash, "runtime_normalized_sha256": runtime_text.sha256_text(),
			"expected_normalized_sha256": expected.sha256_text(), "runtime_matches_disk": matches_disk,
			"matches_allowlist": matches_allowlist, "deployment_guard_replacements": guard_replacements}
		all_match = all_match and matches_allowlist
		if stage != "setup" and report.source_audit.has("setup"):
			if disk_hash != str(report.source_audit.setup[path].disk_sha256):
				report["disk_source_changed"] = true
			if runtime_text.sha256_text() != str(report.source_audit.setup[path].runtime_normalized_sha256):
				report["runtime_source_changed"] = true
	report.source_audit[stage] = sources
	if not all_match: report["runtime_source_changed"] = true
	report["source_files_edited"] = bool(report.disk_source_changed) or bool(report.runtime_source_changed)
	return all_match and not bool(report.disk_source_changed) and not bool(report.runtime_source_changed)

func _formal_200_performance_gate() -> Dictionary:
	var windows: Array[float] = []
	for window in range(6):
		var count := 0
		for at: float in frame_at:
			if at > window * 10.0 and at <= (window + 1) * 10.0: count += 1
		windows.append(count / 10.0)
	var failures: Array[String] = []
	if not bool(report.source_parity_setup) or not bool(report.source_parity_measurement_start) or not bool(report.source_parity_end): failures.append("source_parity")
	if bool(report.disk_source_changed) or bool(report.runtime_source_changed) or bool(report.deployment_override_applied): failures.append("source_changed")
	if int(report.initial_visibility.visible_textured_sprites) != 200 or int(report.final_visibility.visible_textured_sprites) != 200: failures.append("visible_count")
	if int(report.initial_life.rows) != 200 or int(report.final_life.rows) != 200 or int(report.exchanges) <= 0: failures.append("full_battle")
	if float(report.wall_seconds) < 60.0 or float(report.fps) < 30.0: failures.append("average_fps")
	if float(report.p95_ms) > 33.334: failures.append("p95")
	for window in range(6):
		if windows[window] < 30.0: failures.append("fps_window_%d" % window)
	return {"passed": failures.is_empty(), "failures": failures, "fps_by_10s": windows,
		"average_fps": report.fps, "p95_ms": report.p95_ms,
		"frame_ms_count": intervals.size(), "frame_at_count": frame_at.size()}

func _formal_5k_performance_gate(frame_at: Array[float], frame_ms: Array[float]) -> Dictionary:
	var window_fps: Array[float] = []
	for window in range(6):
		var frames_in_window := 0
		for at: float in frame_at:
			if at > window * 10.0 and at <= (window + 1) * 10.0:
				frames_in_window += 1
		window_fps.append(frames_in_window / 10.0)
	var ratio := float(report.action_clock_seconds) / maxf(0.001, float(report.wall_seconds))
	var failures: Array[String] = []
	if per_team != 2500 or duration != 60.0: failures.append("fixture")
	var allowed_args := ["--per-team=2500", "--seconds=60", "--resident-clock=on", "--resident-clock=off",
		"--verify-render", "--require-ko-native", "--assert-5k-performance", "--candidate-hot"]
	var rejected_args: Array[String] = []
	for argument: String in OS.get_cmdline_user_args():
		if argument not in allowed_args and not (candidate_hot and argument == "--mechanism-evidence=" + mechanism_evidence_path): rejected_args.append(argument)
	if bool(report.profile_enabled) or stall_profile or continuous_visibility or not rejected_args.is_empty(): failures.append("probed_or_nonformal_run")
	if str(report.project_main_scene) != MAIN or str(report.main_scene) != MAIN: failures.append("main_scene")
	if str(report.preset) != "PLAINS" or int(report.seed) != 581 or str(report.map_cells) != str(Vector2i(100, 100)): failures.append("terrain_fixture")
	if int(report.engine.major) != 4 or int(report.engine.minor) != 7 or int(report.engine.patch) != 2 or str(report.engine.status) != "stable" or str(report.engine.build) != "official": failures.append("engine")
	if str(report.renderer) != "forward_plus" or str(report.driver) != "d3d12": failures.append("renderer")
	if str(report.logical_viewport) != str(Vector2(2560, 1440)) or str(report.window_pixels) != str(Vector2i(1600, 900)) or str(report.window_pixels) != str(report.window_pixels_measurement_start) or str(report.window_pixels) != str(report.window_pixels_end): failures.append("window_or_logical_viewport")
	if str(report.viewport_pixels_after_warmup) != str(report.viewport_pixels_measurement_start) or str(report.viewport_pixels_after_warmup) != str(report.viewport_pixels_end) or int(report.viewport_min_width) < 1000 or int(report.viewport_min_height) < 563: failures.append("render_viewport")
	if int(report.vsync) != DisplayServer.VSYNC_DISABLED or int(report.fps_cap) != 0 or int(report.shader_instance_buffer_size) != 131072: failures.append("render_quality")
	if str(report.catalog) != Atlas.CATALOG or str(report.implementation_sha256.get(str(report.catalog), "")).length() != 64: failures.append("atlas_catalog")
	if not bool(report.deployment_override_applied) or int(report.deployment_limit) != 2500: failures.append("deployment_guard")
	if not bool(report.source_parity_setup) or not bool(report.source_parity_measurement_start) or not bool(report.source_parity_end) or bool(report.disk_source_changed) or bool(report.runtime_source_changed) or not bool(report.implementation_unchanged_during_measurement) or not bool(report.army_disk_unchanged): failures.append("source_allowlist_or_manifest_changed")
	var required_hashes := [FIXTURE, ARMY, BATCH, MAIN, "res://project.godot", Atlas.BASE_MANIFEST, Atlas.CATALOG,
		"res://native/army_idle/army_idle.cpp", "res://native/army_idle/army_idle.gdextension", "res://native/army_idle/bin/army_idle.windows.x86_64.dll"]
	for path: String in required_hashes:
		if str(report.implementation_sha256.get(path, "")).length() != 64:
			failures.append("missing_manifest_hash:" + path)
	for path: String in report.implementation_sha256:
		if str(report.implementation_sha256[path]).length() != 64:
			failures.append("missing_source_or_asset:" + path)
	if bool(report.paused) or bool(report.measurement_start_paused) or bool(report.terrain_modified) or str(report.terrain_fingerprint_before) != str(report.measurement_start_terrain_fingerprint) or str(report.terrain_fingerprint_before) != str(report.terrain_fingerprint_after): failures.append("paused_or_terrain_changed")
	if str(report.movement_tick_mode) != "idle_fast_path" or str(report.combat_summary_tick_mode) != "visible_only" or str(report.fatigue_policy) != "shared_except_player" or not bool(report.periodic_review_stagger_enabled) or not bool(report.exchange_batch_enabled): failures.append("gameplay_mode")
	if not bool(report.native_render_enabled) or not bool(report.native_buffer_enabled) or not bool(report.native_grouping_enabled) or str(report.native_unconscious_mode) != "idle_and_unconscious" or int(report.batch_rendered) != 4998 or int(report.native_rendered_final) <= 0: failures.append("presentation_mode")
	if "--verify-render" not in OS.get_cmdline_user_args() \
			or not bool(report.get("before_render_parity", {}).get("exact_full_rgba", false)) \
			or not bool(report.get("after_render_parity", {}).get("exact_full_rgba", false)):
		failures.append("full_rgba_parity")
	var resident_expected := resident_clock_mode == "on"
	var resident_modes_ok: bool = report.resident_clock_teams_after_deployment.size() == 2 and report.resident_clock_teams_measurement_start.size() == 2 and report.resident_clock_teams_end.size() == 2
	if resident_modes_ok:
		for rows: Array in [report.resident_clock_teams_after_deployment, report.resident_clock_teams_measurement_start, report.resident_clock_teams_end]:
			for side in range(2):
				var row: Dictionary = rows[side]
				resident_modes_ok = resident_modes_ok and int(row.side) == side and bool(row.enabled) == resident_expected and (not resident_expected or bool(row.native_ready))
	if not resident_modes_ok: failures.append("resident_clock_mode")
	if candidate_hot and not mechanism_diagnostic:
		if not bool(report.get("mechanism_gate", {}).get("passed", false)): failures.append("mechanism_gate")
		for stage: String in ["after_deployment", "measurement_start", "end"]:
			if not _candidate_hot_both_active(report.get("candidate_hot_teams_" + stage, [])):
				failures.append("candidate_hot_inactive:" + stage)
	if int(report.initial_life.rows) != 5000 or int(report.final_life.rows) != 5000 or int(report.initial_life.living) + int(report.initial_life.dead) != 5000 or int(report.final_life.living) + int(report.final_life.dead) != 5000: failures.append("roster_rows")
	if int(report.initial_visibility.visible_textured_sprites) != 5000 or int(report.final_visibility.visible_textured_sprites) != 5000 or int(report.initial_visibility.outside_unobscured_map) != 0 or int(report.final_visibility.outside_unobscured_map) != 0: failures.append("visible_start_or_end")
	if float(report.wall_seconds) < 60.0 or int(report.exchanges) <= 0: failures.append("full_battle")
	if float(report.p95_ms) > 33.33: failures.append("p95")
	if float(report.p99_ms) > 50.0: failures.append("p99")
	for window in range(6):
		if window_fps[window] < 30.0: failures.append("fps_window_%d" % window)
	if ratio < 0.99 or ratio > 1.01: failures.append("action_clock")
	if float(report.action_remainder_end) < -TerrainLab.ACTION_TIME_EPSILON or float(report.action_remainder_end) >= TerrainLab.EXCHANGE_ACTION_STEP + TerrainLab.ACTION_TIME_EPSILON: failures.append("unhandled_action_time")
	var over_33 := 0
	var over_50 := 0
	var over_100 := 0
	for ms: float in frame_ms:
		if ms > 33.33: over_33 += 1
		if ms > 50.0: over_50 += 1
		if ms > 100.0: over_100 += 1
	return {"passed": failures.is_empty(), "failures": failures, "fps_by_10s": window_fps,
		"action_clock_ratio": ratio, "frames_over_33_33_ms": over_33,
		"frames_over_50_ms": over_50, "frames_over_100_ms": over_100,
		"every_frame_30_fps": over_33 == 0, "resident_clock_mode": resident_clock_mode,
		"candidate_hot": candidate_hot,
		"resident_clock_both_teams_verified": resident_modes_ok, "rejected_args": rejected_args}

func _life() -> Dictionary:
	var result := {"rows": 0, "living": 0, "ko": 0, "dead": 0, "moving": 0}
	for team: TerrainArmy in lab.combat_armies:
		for index in range(team.combat_units.size()):
			var hp := float(_logical_hot_field(team, index, &"hp", 0.0))
			result.rows += 1
			result.living += int(hp > 0.0)
			result.dead += int(hp <= 0.0)
			result.ko += int(float(_logical_hot_field(team, index, &"ko", 0.0)) > 0.0)
			result.moving += int(team.moving_to[index] != TerrainArmy.INVALID_CELL)
	return result

func _logical_hot_field(team: TerrainArmy, index: int, field: StringName, default: Variant) -> Variant:
	if team.has_method("combat_hot_get"):
		return team.call("combat_hot_get", index, field, default)
	return team.combat_units[index].get(String(field), default)

func _visibility() -> Dictionary:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var outside := 0
	var visible_sprites := 0
	var map_rect := Rect2(Vector2(0, 0), Vector2(lab.site_controller.panel.position.x - 8, lab.get_viewport_rect().size.y))
	for team: TerrainArmy in lab.combat_armies:
		for sprite: Sprite2D in team._sprites:
			if sprite != null: visible_sprites += int(sprite.is_visible_in_tree() and sprite.texture != null)
		if team._batch_view != null: visible_sprites += int(team._batch_view.rendered_count)
		for index in range(team.combat_units.size()):
			var point := team.get_global_transform_with_canvas() * team.combat_ground(index)
			minimum = minimum.min(point)
			maximum = maximum.max(point)
			outside += int(not map_rect.has_point(point))
	return {"visible_textured_sprites": visible_sprites, "outside_unobscured_map": outside,
		"screen_min": str(minimum), "screen_max": str(maximum), "map_rect": str(map_rect)}

func _capture(name: String) -> bool:
	return root.get_texture().get_image().save_png(out + "/" + name + ".png") == OK

func _render_owner_bytes() -> PackedByteArray:
	var state := [lab._exchange_round, lab._exchange_phase, lab._action_time_remainder, lab.exchange_count]
	for team: TerrainArmy in lab.combat_armies:
		var logical_rows: Array = team.combat_units.duplicate(true)
		if team.has_method("materialized_combat_rows"):
			logical_rows = team.call("materialized_combat_rows")
			assert(logical_rows.size() == team.combat_units.size(), "Resident state could not be read without flushing raw rows")
		state.append([logical_rows, team.combat_units, team.cells, team.moving_to, team.move_progress, team.move_duration,
			team.facing, team.combat_slots, team._reserved_cells, team._cell_owners, team._unit_rescues, team.command_rng.state])
	return var_to_bytes(state)

func _verify_render_pair(stage: String) -> bool:
	# Freeze the SAME actual main-screen battle; compare only presentation paths.
	var before := _render_owner_bytes()
	var before_clock := _clock()
	var before_tick := roundi((before_clock - lab._action_time_remainder) / TerrainLab.EXCHANGE_ACTION_STEP)
	var reference: Image
	var native_count := 0
	var grouped_count := 0
	var native_unconscious_count := 0
	for enabled: bool in [false, true]:
		for team: TerrainArmy in [lab.army, lab.opposing_army]:
			team.native_render_enabled = enabled
			team._batch_view.native_buffer_enabled = enabled
			team._batch_view.native_grouping_enabled = enabled
			team._visual_dirty = true
			team.advance_frame(0.0)
		# Settle the original transparent live-presenter viewports as well.
		for frame in range(2):
			await process_frame
			await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		assert(picture.save_png(out + "/" + stage + ("_native.png" if enabled else "_gd.png")) == OK)
		if not enabled: reference = picture
		else:
			for team: TerrainArmy in [lab.army, lab.opposing_army]:
				native_count += team._batch_view.native_prepared_count
				grouped_count += team._batch_view.native_grouped_count
				for index in range(team.combat_units.size()):
					if str(_logical_hot_field(team, index, &"pose", "")) == "unconscious" and index < team._batch_view._native_mask.size() and team._batch_view._native_mask[index] != 0:
						native_unconscious_count += 1
			if reference.get_data() != picture.get_data():
				_fail("Frozen original main pixel mismatch: " + stage)
				return false
		if before != _render_owner_bytes() or before_clock != _clock():
			_fail("Presentation mutated materialized person/claim/RNG/action state: " + stage)
			return false
	for team: TerrainArmy in [lab.army, lab.opposing_army]:
		team.native_render_enabled = "--gd-render" not in OS.get_cmdline_user_args()
		team._batch_view.native_buffer_enabled = "--gd-buffers" not in OS.get_cmdline_user_args()
		team._batch_view.native_grouping_enabled = "--gd-groups" not in OS.get_cmdline_user_args()
	if native_count <= 0 or grouped_count <= 0:
		_fail("No native presentation exercised: " + stage)
		return false
	if stage == "after" and "--require-ko-native" in OS.get_cmdline_user_args() and native_unconscious_count <= 0:
		_fail("No unconscious person exercised the native pixel oracle")
		return false
	report[stage + "_render_parity"] = {"exact_full_rgba": true, "owner_bytes_equal": true,
		"action_tick": before_tick, "action_clock": before_clock,
		"native_people": native_count, "grouped_people": grouped_count, "native_unconscious_people": native_unconscious_count}
	print("ARMY_MAIN_NATIVE_RENDER_PASS stage=", stage, " native=", native_count, " exact full RGBA and original owner bytes")
	return true

func _verify_gpu_render_pair(stage: String) -> bool:
	# Compare the same frozen formal battle before and after the RD path writes
	# the existing Canvas MultiMesh. Screenshot readback is outside FPS timing.
	var before := _render_owner_bytes()
	var reference: Image
	var dispatches := 0
	for enabled: bool in [false, true]:
		var starts: Array[int] = []
		var fallbacks: Array[int] = []
		for team: TerrainArmy in [lab.army, lab.opposing_army]:
			starts.append(team._batch_view.gpu_dispatch_count)
			fallbacks.append(team._batch_view.gpu_fallback_count)
			team._batch_view.gpu_compute_enabled = enabled
			team._visual_dirty = true
			team.advance_frame(0.0)
		for frame in range(2):
			await process_frame
			await RenderingServer.frame_post_draw
			if enabled and frame == 0 and reference.get_data() != root.get_texture().get_image().get_data():
				_fail("GPU Canvas update missed the first rendered frame: " + stage)
				return false
		var picture := root.get_texture().get_image()
		assert(picture.save_png(out + "/" + stage + ("_gpu.png" if enabled else "_cpu.png")) == OK)
		if enabled:
			for side in range(2):
				var view = [lab.army, lab.opposing_army][side]._batch_view
				var issued: int = view.gpu_dispatch_count - starts[side]
				dispatches += issued
				if issued <= 0 or view.gpu_fallback_count != fallbacks[side] or not view.gpu_last_error.is_empty():
					_fail("GPU Canvas path did not dispatch cleanly on side %d: %s" % [side, view.gpu_last_error])
					return false
			if reference.get_data() != picture.get_data():
				_fail("Frozen original main GPU Canvas pixel mismatch: " + stage)
				return false
		else:
			reference = picture
		if before != _render_owner_bytes():
			_fail("GPU presentation mutated original person/claim/RNG state: " + stage)
			return false
	report[stage + "_gpu_render_parity"] = {"exact_full_rgba": true, "owner_bytes_equal": true,
		"gpu_dispatches": dispatches, "gpu_instance_readback_bytes": 0}
	if stage == "after" and "--require-ko-native" in OS.get_cmdline_user_args():
		var native_ko := 0
		for team: TerrainArmy in [lab.army, lab.opposing_army]:
			for index in range(team.combat_units.size()):
				if str(_logical_hot_field(team, index, &"pose", "")) == "unconscious" and index < team._batch_view._native_mask.size() and team._batch_view._native_mask[index] != 0:
					native_ko += 1
		if native_ko <= 0:
			_fail("GPU Canvas oracle did not exercise native unconscious rows")
			return false
		report[stage + "_gpu_render_parity"]["native_unconscious_people"] = native_ko
	print("ARMY_MAIN_GPU_RENDER_PASS stage=", stage, " dispatches=", dispatches)
	return true

func _render_cost_sample() -> Dictionary:
	# Isolated CPU costs on the actual loaded Army, while battle is stationary.
	# These repeated sections are NOT FPS and are outside the measured interval.
	var timings := {}
	var differences := 0
	for stage: String in ["appearance_query", "appearance_with_compare", "batch_submit", "ordinary_full_path", "live_captains"]:
		var begin := Time.get_ticks_usec()
		for repeat in range(3):
			for team: TerrainArmy in lab.combat_armies:
				if team.combat_units.is_empty(): continue
				team._batch_view.begin()
				for index in range(team.combat_units.size()):
					if team._uses_live_presenter(index):
						if stage == "live_captains": team._sync_captain_combat(team.combat_frame(index), index)
						continue
					match stage:
						"appearance_query": team.equipment_appearance(index)
						"appearance_with_compare": differences += int(team.equipment_appearance(index) != team._batch_view._appearances[index])
						"batch_submit":
							var age := float(team.call("combat_age", index)) if _team_clock_enabled(team) else float(_logical_hot_field(team, index, &"age", 0.0))
							team._batch_view.submit(index, team.combat_ground(index), team.equipment_appearance(index), "combat_idle", team._soldier_direction_id(team.facing[index]), age)
						"ordinary_full_path": team._set_soldier_frame(index)
			timings[stage] = (Time.get_ticks_usec() - begin) / 3.0
	for team: TerrainArmy in lab.combat_armies:
		team._visual_dirty = true
		team.advance_frame(0.0)
	timings["appearance_differences"] = differences
	return timings

func _start_viewport_probe() -> void:
	# Diagnostic only: do not request textures, change update modes or hide nodes.
	viewport_probe.append(root)
	for node: Node in root.find_children("*", "Viewport", true, false):
		viewport_probe.append(node as Viewport)
	report["viewport_probe"] = []
	report["render_setup_cpu_ms"] = []
	for viewport: Viewport in viewport_probe:
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
		report.viewport_probe.append({"path": str(viewport.get_path()), "class": viewport.get_class(),
			"logical_rect": str(viewport.get_visible_rect()),
			"initial_update_mode": viewport.render_target_update_mode if viewport is SubViewport else -1,
			"cpu_ms": [], "gpu_ms": [], "visible_draws": [], "shadow_draws": []})
	report["viewport_probe_note"] = "Diagnostic last-reported render-only times; GPU results can be delayed and inactive viewports may retain old readings. Not whole-frame CPU time or an uninstrumented FPS score."

func _sample_viewport_probe() -> void:
	report.render_setup_cpu_ms.append(RenderingServer.get_frame_setup_time_cpu())
	for index in range(viewport_probe.size()):
		var rid := viewport_probe[index].get_viewport_rid()
		var sample: Dictionary = report.viewport_probe[index]
		var cpu := RenderingServer.viewport_get_measured_render_time_cpu(rid)
		var gpu := RenderingServer.viewport_get_measured_render_time_gpu(rid)
		assert(is_finite(cpu) and cpu >= 0.0 and is_finite(gpu) and gpu >= 0.0)
		sample.cpu_ms.append(cpu)
		sample.gpu_ms.append(gpu)
		sample.visible_draws.append(RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
		sample.shadow_draws.append(RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))

func _sample_rd_timestamps() -> void:
	# Read existing viewport markers only; no extra GPU queries, flush or sync.
	# Match CPU timestamps to stored frame boundaries, never the delayed frame ID.
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id(), "Diagnostic journal must stay on the main thread")
	var begin := Time.get_ticks_usec()
	var device := RenderingServer.get_rendering_device()
	assert(device != null, "RD timestamp diagnostic needs the existing RD renderer")
	var count := device.get_captured_timestamps_count()
	if count == 0: return
	var first := device.get_captured_timestamp_cpu_time(0)
	if first == rd_last_timestamp_usec: return
	rd_last_timestamp_usec = first
	var markers: Array = []
	for index in count:
		markers.append([device.get_captured_timestamp_name(index),
			device.get_captured_timestamp_cpu_time(index), device.get_captured_timestamp_gpu_time(index)])
	rd_timestamp_samples.append({"read_ticks_usec": begin,
		"reported_frame": device.get_captured_timestamps_frame(), "read_drawn_frames": Engine.get_frames_drawn(),
		"markers": markers, "read_usec": Time.get_ticks_usec() - begin})

func _run() -> void:
	s1_profile = "--s1-profile" in OS.get_cmdline_user_args()
	if "--p1-parse-only" in OS.get_cmdline_user_args():
		assert(p1_profile, "P1 parse check requires --p1-profile")
		var army_script := load(ARMY) as GDScript
		army_script.source_code = _p1_instrument_army(army_script.source_code)
		assert(army_script.reload(true) == OK, "P1 Army probe must compile")
		var batch_script := load(BATCH) as GDScript
		batch_script.source_code = _p1_instrument_batch(batch_script.source_code)
		assert(batch_script.reload(true) == OK, "P1 BatchView probe must compile")
		print("P1_PROFILE_PARSE_PASS in-memory Army and BatchView")
		done = true
		quit(0)
		return
	if "--s1-parse-only" in OS.get_cmdline_user_args():
		assert(s1_profile, "S1 parse check requires --s1-profile")
		var checked_script := load(ARMY) as GDScript
		checked_script.source_code = _s1_instrument_army(checked_script.source_code)
		assert(checked_script.reload(true) == OK, "S1 instrumented source must compile")
		print("S1_PROFILE_PARSE_PASS anchors=", s1_anchors.size(), " original statements restored exactly")
		done = true
		quit(0)
		return
	if DisplayServer.get_name() == "headless":
		_fail("Real GPU window required")
		return
	# Larger trials may change one deployment guard in this process only.
	var army_script := load(ARMY) as GDScript
	var original := army_script.source_code
	if "--captain-timeline-reference" in OS.get_cmdline_user_args():
		var fixture := FileAccess.get_file_as_string("res://scripts/tests/fixtures/terrain_army_captain_timeline_original.gd.txt")
		var matcher := RegEx.new()
		assert(matcher.compile("(?m)^func _sync_captain_combat\\([^\\n]*\\n(?:\\t[^\\n]*\\n|\\r?\\n)*") == OK)
		assert(matcher.search_all(original).size() == 1 and fixture.begins_with("func _sync_captain_combat("))
		original = original.replace(matcher.search(original).get_string(), fixture + "\n")
	if "--counts-reference" in OS.get_cmdline_user_args():
		var fixture := FileAccess.get_file_as_string("res://scripts/tests/fixtures/terrain_army_counts_original.gd.txt")
		for method in ["moving_count", "passage_summary"]:
			var matcher := RegEx.new()
			assert(matcher.compile("(?ms)^func " + method + "\\([^\\n]*\\n.*?(?=^(?:static )?func |\\z)") == OK)
			assert(matcher.search_all(original).size() == 1 and matcher.search_all(fixture).size() == 1)
			original = original.replace(matcher.search(original).get_string(), matcher.search(fixture).get_string() + "\n")
	if "--idle-scan-reference" in OS.get_cmdline_user_args():
		var candidate := "[] if exchange_enabled and not _visual_dirty else (_batch_view.prepared_exceptions() if grouped else range(_sprites.size()))"
		assert(original.count(candidate) == 1)
		original = original.replace(candidate, "_batch_view.prepared_exceptions() if grouped else range(_sprites.size())")
	if "--actor-profile" in OS.get_cmdline_user_args():
		for target: Array in [["res://scripts/terrain_lab/terrain_test_character.gd", [["apply_exchange", "other_cell, outcome", false], ["play_pose", "clip", false], ["_cancel_exchange_legacy_attack", "", false]]], [EDITOR, [["select_animation_by_id", "animation_id", true], ["_play_selected_animation", "", false], ["_update_weapon_sheath_state", "", false], ["_apply_attack_loop_default", "", false], ["_update_preview_framing", "", false]]]]:
			var script := load(str(target[0])) as GDScript
			var source := script.source_code
			for spec: Array in target[1]:
				var matcher := RegEx.new()
				assert(matcher.compile("(?m)^func " + str(spec[0]) + "\\([^\\n]+") == OK)
				var signature := matcher.search(source).get_string()
				source = source.replace(signature, signature.replace(str(spec[0]), "_stable30_probe_" + str(spec[0])))
				var invocation := "_stable30_probe_%s(%s)" % [spec[0], spec[1]]
				source += "\n" + signature + "\n\tvar begin := Time.get_ticks_usec()\n\t" + ("var value: Variant = " if spec[2] else "") + invocation + "\n\tvar times: Dictionary = get_meta(&\"phase26_owner_usec\", {})\n\ttimes[\"%s\"] = int(times.get(\"%s\", 0)) + Time.get_ticks_usec() - begin\n\tset_meta(&\"phase26_owner_usec\", times)\n" % [spec[0], spec[0]] + ("\treturn value\n" if spec[2] else "")
			script.source_code = source
			assert(script.reload(true) == OK)
	if "--apply-profile" in OS.get_cmdline_user_args():
		assert("--profile" in OS.get_cmdline_user_args())
		for spec: Array in [["apply_exchange", "index, other_cell, outcome", false], ["apply_unit_contact", "index, packet", false], ["attack_clip", "index", true], ["_reserve_combat_step", "index, next, escort_guard_id, running", true], ["_begin_exchange_visual", "index, pose, merge_reaction", false], ["equipment_appearance", "index", true]]:
			var matcher := RegEx.new()
			assert(matcher.compile("(?m)^func " + str(spec[0]) + "\\([^\\n]+") == OK)
			var signature := matcher.search(original).get_string()
			original = original.replace(signature, signature.replace(str(spec[0]), "_stable30_probe_" + str(spec[0])))
			var invocation := "_stable30_probe_%s(%s)" % [spec[0], spec[1]]
			original += "\n" + signature + "\n\tvar begin := Time.get_ticks_usec()\n\t" + ("var value: Variant = " if spec[2] else "") + invocation + "\n\t_profile_combat_stage(\"probe_%s\", begin)\n" % spec[0] + ("\treturn value\n" if spec[2] else "")
		var lab_script := load("res://scripts/terrain_lab/terrain_lab.gd") as GDScript
		var matcher := RegEx.new()
		assert(matcher.compile("(?ms)^func _apply_exchange_side\\([^\\n]*\\n.*?(?=^func |\\z)") == OK)
		var before := matcher.search(lab_script.source_code).get_string()
		var instrumented := before.replace("\tvar role :=", "\tvar mark := Time.get_ticks_usec()\n\tvar role :=")
		instrumented = instrumented.replace("\tif int(person.unit) >= 0:", "\tmark = _combat_profile_stage(\"detail_outcome_pack\", mark)\n\tif int(person.unit) >= 0:")
		instrumented += "\t_combat_profile_stage(\"detail_outcome_call\", mark)\n\n"
		lab_script.source_code = lab_script.source_code.replace(before, instrumented)
		assert(lab_script.reload(true) == OK)
	if "--index-profile" in OS.get_cmdline_user_args():
		assert("--profile" in OS.get_cmdline_user_args())
		var lab_script := load("res://scripts/terrain_lab/terrain_lab.gd") as GDScript
		var matcher := RegEx.new()
		assert(matcher.compile("(?ms)^func _resolve_exchanges\\([^\\n]*\\n.*?(?=^func )") == OK)
		var before := matcher.search(lab_script.source_code).get_string()
		var instrumented := before.replace("\tvar occupied := {}", "\tvar index_mark := Time.get_ticks_usec()\n\tvar occupied := {}")
		for stage: Array in [["capture", "\t\torder = snapshot.front_order"], ["front", "\t\tvar natural_order :="], ["sort", "\t\tfor ordinal: int in natural_order:"]]:
			assert(instrumented.count(str(stage[1])) == 1)
			instrumented = instrumented.replace(stage[1], "\t\tindex_mark = _combat_profile_stage(\"index_%s\", index_mark)\n%s" % [stage[0], stage[1]])
		instrumented = instrumented.replace("\tprofile_started = _combat_profile_stage(\"exchange_people_index\", profile_started)", "\t_combat_profile_stage(\"index_occupied\", index_mark)\n\tprofile_started = _combat_profile_stage(\"exchange_people_index\", profile_started)")
		lab_script.source_code = lab_script.source_code.replace(before, instrumented)
		assert(lab_script.reload(true) == OK)
	if "--context-profile" in OS.get_cmdline_user_args():
		assert("--profile" in OS.get_cmdline_user_args())
		var lab_script := load("res://scripts/terrain_lab/terrain_lab.gd") as GDScript
		var matcher := RegEx.new()
		assert(matcher.compile("(?m)^func _exchange_context\\([^\\n]*\\n(?:\\t[^\\n]*\\n|\\r?\\n)*") == OK)
		assert(matcher.search_all(lab_script.source_code).size() == 1)
		var before := matcher.search(lab_script.source_code).get_string()
		var instrumented := before.replace("\tvar sectors :=", "\tvar mark := Time.get_ticks_usec()\n\tvar sectors :=")
		for stage: Array in [["sectors", "\tvar person_owner:"], ["skill", "\tvar stats:"], ["stats", "\tstats.encirclement ="], ["facility", "\tif site_controller != null:"], ["morale", "\treturn stats"]]:
			assert(instrumented.count(str(stage[1])) == 1)
			instrumented = instrumented.replace(stage[1], "\tmark = _combat_profile_stage(\"context_%s\", mark)\n%s" % [stage[0], stage[1]])
		lab_script.source_code = lab_script.source_code.replace(before, instrumented)
		assert(lab_script.reload(true) == OK)
	if "--presence-profile" in OS.get_cmdline_user_args():
		assert("--profile" in OS.get_cmdline_user_args())
		var matcher := RegEx.new()
		assert(matcher.compile("(?m)^func _refresh_command_presence\\([^\\n]*\\n(?:\\t[^\\n]*\\n|\\r?\\n)*") == OK)
		assert(matcher.search_all(original).size() == 1)
		var before := matcher.search(original).get_string()
		# Insert timers around the active delta path and retain separate legacy timings.
		var insertions: Array[Array] = [
			["\n\t\t\tvar moving_positions := {}", "\n\t\t\tvar presence_mark := Time.get_ticks_usec()"],
			["\n\t\t\tif native_presence_delta_enabled and kernel.has_method(\"command_presence_delta\"):", "\n\t\t\tpresence_mark = _profile_combat_stage(\"presence_movers\", presence_mark)"],
			["\n\t\t\t\tif changes.size() == 5:", "\n\t\t\t\tpresence_mark = _profile_combat_stage(\"presence_delta_kernel\", presence_mark)"],
			["\n\t\t\t\t\tvar reference: PackedVector2Array = changes[0]", "\n\t\t\t\t\tvar presence_delta_writes := Time.get_ticks_usec()"],
			["\n\t\t\t\t\treturn # Native presence projection applied by the original owner.", "\n\t\t\t\t\t_profile_combat_stage(\"presence_delta_writes\", presence_delta_writes)"],
			["\n\tif projection.size() == 2:", "\n\t\t\t_profile_combat_stage(\"presence_kernel\", presence_mark)"],
			["\n\t\tvar reference: PackedVector2Array = projection[0]", "\n\t\tvar presence_writes := Time.get_ticks_usec()"],
			["\n\t\treturn # Native presence projection applied by the original owner.", "\n\t\t_profile_combat_stage(\"presence_writes\", presence_writes)"],
		]
		var instrumented := before
		for insertion: Array in insertions:
			assert(before.count(insertion[0]) == 1, "Presence profiler source anchor changed")
			instrumented = instrumented.replace(insertion[0], insertion[1] + insertion[0])
		var restored := instrumented
		for insertion: Array in insertions:
			assert(restored.count(insertion[1]) == 1, "Presence profiler inserted statement changed")
			restored = restored.replace(insertion[1], "")
		assert(restored == before, "Presence profiler changed original statements")
		original = original.replace(before, instrumented)
	var phase24_terrain := "--phase24-terrain" in OS.get_cmdline_user_args()
	var empty_component_reference := "--empty-component-reference" in OS.get_cmdline_user_args()
	if empty_component_reference:
		var editor_script := load(EDITOR) as GDScript
		var matcher := RegEx.new()
		assert(matcher.compile("(?ms)^func _find_component_nodes\\([^\\n]*\\n.*?(?=^func |\\z)") == OK)
		var baseline := FileAccess.get_file_as_string("res://output/site_army_exchange_spikes_20260915/baseline/human_character_3d_editor.gd.baseline")
		assert(matcher.search_all(editor_script.source_code).size() == 1 and matcher.search_all(baseline).size() == 1)
		editor_script.source_code = editor_script.source_code.replace(matcher.search(editor_script.source_code).get_string(), matcher.search(baseline).get_string())
		assert(editor_script.reload(true) == OK)
	if "--cold-query-startup" in OS.get_cmdline_user_args():
		var lab_script := load("res://scripts/terrain_lab/terrain_lab.gd") as GDScript
		assert(lab_script.source_code.count("\t\t_prepare_exchange_kernel(true)") == 1)
		lab_script.source_code = lab_script.source_code.replace("\t\t_prepare_exchange_kernel(true)", "\t\tpass # Test-process cold first-query reference.")
		assert(lab_script.reload(true) == OK)
	if phase24_terrain:
		assert("--verify-terrain" not in OS.get_cmdline_user_args())
		var terrain_script := load(TERRAIN_RENDERER) as GDScript
		terrain_script.source_code = FileAccess.get_file_as_string(PHASE24_TERRAIN)
		assert(terrain_script.reload(true) == OK)
	var phase22_ranged := "--phase22-ranged" in OS.get_cmdline_user_args()
	if phase22_ranged:
		var snapshot_script := load("res://scripts/terrain_lab/site_exchange_snapshot.gd") as GDScript
		snapshot_script.source_code = FileAccess.get_file_as_string(PHASE22_RANGED)
		assert(snapshot_script.reload(true) == OK)
	var phase21_seeds := "--phase21-seeds" in OS.get_cmdline_user_args()
	if phase21_seeds:
		var matcher := RegEx.new()
		assert(matcher.compile("(?ms)^func _try_exchange_encirclement\\([^\\n]*\\n.*?(?=^(?:static )?func |\\z)") == OK)
		assert(matcher.search_all(original).size() == 1)
		original = original.replace(matcher.search(original).get_string(), FileAccess.get_file_as_string(PHASE21_SEEDS) + "\n")
	if "--phase17-live-loop" in OS.get_cmdline_user_args():
		var editor_script := load(EDITOR) as GDScript
		var assignment := "\tif animation != null and animation.loop_mode != requested_loop:\n"
		assert(editor_script.source_code.count(assignment) == 1)
		editor_script.source_code = editor_script.source_code.replace(assignment, "\tif animation != null:\n")
		assert(editor_script.reload(true) == OK)
	var phase14_render := "--phase14-render" in OS.get_cmdline_user_args()
	if phase14_render:
		assert("--verify-render" not in OS.get_cmdline_user_args())
		var matcher := RegEx.new()
		assert(matcher.compile("(?ms)^func advance_frame\\([^\\n]*\\n.*?(?=^(?:static )?func |\\z)") == OK)
		assert(matcher.search_all(original).size() == 1)
		original = original.replace(matcher.search(original).get_string(), FileAccess.get_file_as_string(PHASE14_FRAME) + "\n")
		var batch_script := load(BATCH) as GDScript
		batch_script.source_code = FileAccess.get_file_as_string(PHASE14_BATCH)
		assert(batch_script.reload(true) == OK)
	var phase12_components := "--phase12-components" in OS.get_cmdline_user_args()
	if phase12_components:
		var editor_script := load(EDITOR) as GDScript
		var matcher := RegEx.new()
		assert(matcher.compile("(?ms)^func _find_component_nodes\\([^\\n]*\\n.*?(?=^(?:static )?func |\\z)") == OK)
		assert(matcher.search_all(editor_script.source_code).size() == 1)
		editor_script.source_code = editor_script.source_code.replace(matcher.search(editor_script.source_code).get_string(), FileAccess.get_file_as_string(PHASE12_COMPONENTS) + "\n")
		assert(editor_script.reload(true) == OK)
	var phase11_prepare := "--phase11-prepare" in OS.get_cmdline_user_args()
	if phase11_prepare:
		var matcher := RegEx.new()
		assert(matcher.compile("(?ms)^func prepare_combat\\([^\\n]*\\n.*?(?=^(?:static )?func |\\z)") == OK)
		var baseline_prepare := FileAccess.get_file_as_string(PHASE11_PREPARE)
		assert(matcher.search_all(original).size() == 1 and matcher.search_all(baseline_prepare).size() == 1)
		original = original.replace(matcher.search(original).get_string(), matcher.search(baseline_prepare).get_string())
	if "--hot-profile" in OS.get_cmdline_user_args():
		assert("--profile" in OS.get_cmdline_user_args())
		var native_guard := "\t\tif clock_prefix and exchange_enabled and combat_order != CombatOrder.HOLD:\n"
		assert(original.count(native_guard) == 1 and original.count("\t\telif kernel != null and exchange_enabled and combat_order != CombatOrder.HOLD:\n") == 1)
		original = original.replace(native_guard, "\t\tvar native_started := Time.get_ticks_usec()\n" + native_guard)
		assert(original.count("\t\t\tnative_idle_calls += 1") == 2)
		original = original.replace("\t\t\tnative_idle_calls += 1", "\t\t\t_profile_combat_stage(\"detail_prepare_native\", native_started)\n\t\t\tnative_idle_calls += 1")
		var render_matcher := RegEx.new()
		assert(render_matcher.compile("(?ms)^func advance_frame\\([^\\n]*\\n.*?(?=^(?:static )?func |\\z)") == OK)
		var render_original := render_matcher.search(original).get_string()
		var render_source := render_original
		var prepare_call := "\t\tif update_batch and native_render_enabled and _batch_render_active(): _batch_view.prepare_idle()"
		assert(render_source.count(prepare_call) == 1)
		render_source = render_source.replace(prepare_call, "\t\tif update_batch and native_render_enabled and _batch_render_active():\n\t\t\tvar native_started := Time.get_ticks_usec()\n\t\t\t_batch_view.prepare_idle()\n\t\t\t_profile_combat_stage(\"detail_render_projection\", native_started)\n\t\tvar row_submit_started := Time.get_ticks_usec()")
		render_source = render_source.replace("\t\tprofile_started = _profile_combat_stage(\"render_submit\", profile_started)", "\t\t_profile_combat_stage(\"detail_render_loop\", row_submit_started)\n\t\tprofile_started = _profile_combat_stage(\"render_submit\", profile_started)")
		var prepared_guard := "prepared_idle and not grouped" if render_source.contains("prepared_idle and not grouped") else "prepared_idle"
		var submit_line := "\t\t\tif " + prepared_guard + " and _batch_view.submit_prepared(index):"
		assert(render_source.count(submit_line) == 1)
		render_source = render_source.replace(submit_line, "\t\t\tvar row_started := Time.get_ticks_usec()\n\t\t\tvar admitted: bool = " + prepared_guard + " and _batch_view.submit_prepared(index)\n\t\t\t_profile_combat_stage(\"detail_render_prepared\", row_started)\n\t\t\tif admitted:")
		render_source = render_source.replace("\t\tif grouped: _batch_view.finish_prepared_groups()", "\t\tif grouped:\n\t\t\tvar group_started := Time.get_ticks_usec()\n\t\t\t_batch_view.finish_prepared_groups()\n\t\t\t_profile_combat_stage(\"detail_render_groups\", group_started)")
		render_source = render_source.replace("\t\t\t\t_sync_captain_combat(combat_frame(index), index)", "\t\t\t\tvar live_started := Time.get_ticks_usec()\n\t\t\t\t_sync_captain_combat(combat_frame(index), index)\n\t\t\t\t_profile_combat_stage(\"detail_render_live\", live_started)")
		render_source = render_source.replace("\t\t\t\t_set_soldier_frame(index)", "\t\t\t\tvar ordinary_started := Time.get_ticks_usec()\n\t\t\t\t_set_soldier_frame(index)\n\t\t\t\t_profile_combat_stage(\"detail_render_ordinary\", ordinary_started)")
		original = original.replace(render_original, render_source)
		var live_matcher := RegEx.new()
		assert(live_matcher.compile("(?ms)^func _sync_captain_combat\\([^\\n]*\\n.*?(?=^(?:static )?func |\\z)") == OK)
		var live_original := live_matcher.search(original).get_string()
		var live_source := live_original
		# Diagnostic counters only; these are calls (not microseconds).
		var select_call := "\t\tpresenter.select_animation_by_id(pose)"
		assert(live_source.count(select_call) == 1)
		live_source = live_source.replace(select_call, "\t\tvar select_started := Time.get_ticks_usec()\n" + select_call + "\n\t\t_profile_combat_stage(\"detail_live_select\", select_started)\n\t\tcombat_profile_usec[\"probe_select_calls\"] = int(combat_profile_usec.get(\"probe_select_calls\", 0)) + 1")
		var seek_call := "\tpresenter.animation_player.seek(float(sample[1]), true)"
		assert(live_source.count(seek_call) == 1)
		live_source = live_source.replace(seek_call, "\tcombat_profile_usec[\"probe_seek_calls\"] = int(combat_profile_usec.get(\"probe_seek_calls\", 0)) + 1\n\tif presenter.animation_player.current_animation_position == float(sample[1]):\n\t\tcombat_profile_usec[\"probe_same_time_calls\"] = int(combat_profile_usec.get(\"probe_same_time_calls\", 0)) + 1\n" + seek_call)
		live_source = live_source.replace("\tvar visual_sample: Array", "\tvar live_mark := Time.get_ticks_usec()\n\tvar visual_sample: Array")
		live_source = live_source.replace("\tvar readiness_changed:", "\tlive_mark = _profile_combat_stage(\"detail_live_yaw\", live_mark)\n\tvar readiness_changed:")
		live_source = live_source.replace("\tpresenter.animation_player.seek(float(sample[1]), true)", "\tlive_mark = _profile_combat_stage(\"detail_live_clip\", live_mark)\n\tpresenter.animation_player.seek(float(sample[1]), true)\n\tlive_mark = _profile_combat_stage(\"detail_live_seek\", live_mark)")
		live_source = live_source.replace("\t\tpresenter._process(0.0) #", "\t\tlive_mark = _profile_combat_stage(\"detail_live_origin\", live_mark)\n\t\tpresenter._process(0.0) #")
		live_source = live_source.replace("\telse:\n\t\tpresenter._update_scabbard_pose()", "\t\tlive_mark = _profile_combat_stage(\"detail_live_process\", live_mark)\n\telse:\n\t\tpresenter._update_scabbard_pose()")
		original = original.replace(live_original, live_source)
	var phase10_presence := "--phase10-presence" in OS.get_cmdline_user_args()
	if phase10_presence:
		var matcher := RegEx.new()
		assert(matcher.compile("(?ms)^func _refresh_command_presence\\([^\\n]*\\n.*?(?=^(?:static )?func |\\z)") == OK)
		var previous_presence := FileAccess.get_file_as_string(PHASE10_PRESENCE)
		assert(matcher.search_all(original).size() == 1 and matcher.search_all(previous_presence).size() == 1)
		original = original.replace(matcher.search(original).get_string(), matcher.search(previous_presence).get_string())
	var phase9_commands := "--phase9-commands" in OS.get_cmdline_user_args()
	if phase9_commands:
		var matcher := RegEx.new()
		assert(matcher.compile("(?ms)^func _try_exchange_encirclement\\([^\\n]*\\n.*?(?=^(?:static )?func |\\z)") == OK)
		var previous_commands := FileAccess.get_file_as_string(PHASE9_COMMANDS)
		assert(matcher.search_all(original).size() == 1 and matcher.search_all(previous_commands).size() == 1)
		original = original.replace(matcher.search(original).get_string(), matcher.search(previous_commands).get_string())
	var phase8_queries := "--phase8-queries" in OS.get_cmdline_user_args()
	if phase8_queries:
		var snapshot_script := load("res://scripts/terrain_lab/site_exchange_snapshot.gd") as GDScript
		snapshot_script.source_code = FileAccess.get_file_as_string(PHASE8_SNAPSHOT)
		assert(snapshot_script.reload(true) == OK)
		var lab_script := load("res://scripts/terrain_lab/terrain_lab.gd") as GDScript
		var matcher := RegEx.new()
		assert(matcher.compile("(?ms)^func _exchange_people\\([^\\n]*\\n.*?(?=^(?:static )?func |\\z)") == OK)
		var baseline_lab := FileAccess.get_file_as_string(PHASE8_LAB)
		assert(matcher.search_all(lab_script.source_code).size() == 1 and matcher.search_all(baseline_lab).size() == 1)
		lab_script.source_code = lab_script.source_code.replace(matcher.search(lab_script.source_code).get_string(), matcher.search(baseline_lab).get_string())
		assert(lab_script.reload(true) == OK)
	if "--detail-profile" in OS.get_cmdline_user_args():
		# Probe only in this process; no product profiling overhead is added.
		assert(original.contains("\t_update_ranged_orders()\n"))
		original = original.replace("\t_update_ranged_orders()\n", "\tvar ranged_orders_started := Time.get_ticks_usec()\n\t_update_ranged_orders()\n\t_profile_combat_stage(\"detail_ranged_orders\", ranged_orders_started)\n")
		original = original.replace("func _refresh_command_presence() -> void:\n", "func _refresh_command_presence() -> void:\n\tvar detail_started := Time.get_ticks_usec()\n")
		var presence_returns := RegEx.new()
		assert(presence_returns.compile("(?m)^(\\t+)return # Native presence projection applied by the original owner\\.") == OK)
		for found: RegExMatch in presence_returns.search_all(original):
			var line := found.get_string()
			original = original.replace("\n" + line, "\n" + found.get_string(1) + "_profile_combat_stage(\"detail_presence\", detail_started)\n" + line)
		original = original.replace("\nfunc command_eligible(index: int)", "\n\t_profile_combat_stage(\"detail_presence\", detail_started)\n\nfunc command_eligible(index: int)")
		original = original.replace("\tcommand_reference_valid = not members.is_empty()", "\tvar presence_mark := _profile_combat_stage(\"detail_presence_collect\", detail_started)\n\tcommand_reference_valid = not members.is_empty()")
		original = original.replace("\t\t\t\tcommand_reference = positions[position_index]", "\t\t\t\tcommand_reference = positions[position_index]\n\tpresence_mark = _profile_combat_stage(\"detail_presence_median\", presence_mark)")
		original = original.replace("\t\tplayer_present = command_reference_valid and player_member.can_act() and command_reference.distance_to(player_member.position / TerrainRenderer.CELL_PIXELS) <= radius", "\t\tplayer_present = command_reference_valid and player_member.can_act() and command_reference.distance_to(player_member.position / TerrainRenderer.CELL_PIXELS) <= radius\n\t_profile_combat_stage(\"detail_presence_apply\", presence_mark)")
		original = original.replace("func _try_exchange_encirclement() -> bool:\n", "func _try_exchange_encirclement() -> bool:\n\tvar detail_started := Time.get_ticks_usec()\n")
		original = original.replace("\tif contact_cells.is_empty():", "\tdetail_started = _profile_combat_stage(\"detail_order_front\", detail_started)\n\tif contact_cells.is_empty():")
		original = original.replace("\tvar filter_origins := distance.size()", "\tdetail_started = _profile_combat_stage(\"detail_order_field\", detail_started)\n\tvar filter_origins := distance.size()")
		original = original.replace("\t\t\tpending.append(goal)\n\tvar head := 0", "\t\t\tpending.append(goal)\n\tvar field_mark := _profile_combat_stage(\"detail_field_seed\", detail_started)\n\tvar head := 0")
		original = original.replace("\t# Conservative one-review origins only:", "\t_profile_combat_stage(\"detail_field_spread\", field_mark)\n\t# Conservative one-review origins only:")
		original = original.replace("\treturn true # A blocked flank waits;", "\t_profile_combat_stage(\"detail_order_candidates\", detail_started)\n\treturn true # A blocked flank waits;")
		var lab_script := load("res://scripts/terrain_lab/terrain_lab.gd") as GDScript
		var detail_source := lab_script.source_code
		detail_source = detail_source.replace("\t\t\tsite_controller.settle_person_deaths(elapsed)", "\t\t\tvar detail_started := Time.get_ticks_usec()\n\t\t\tsite_controller.settle_person_deaths(elapsed)\n\t\t\tdetail_started = _combat_profile_stage(\"detail_deaths\", detail_started)")
		detail_source = detail_source.replace("\t\t\tsite_controller.settle_supply_deliveries()", "\t\t\tdetail_started = _combat_profile_stage(\"detail_person_actions\", detail_started)\n\t\t\tsite_controller.settle_supply_deliveries()\n\t\t\t_combat_profile_stage(\"detail_deliveries\", detail_started)")
		lab_script.source_code = detail_source
		assert(lab_script.reload(true) == OK)
	var phase7_render := "--phase7-render" in OS.get_cmdline_user_args()
	if phase7_render:
		assert("--verify-render" not in OS.get_cmdline_user_args())
		var matcher := RegEx.new()
		assert(matcher.compile("(?ms)^func advance_frame\\([^\\n]*\\n.*?(?=^(?:static )?func |\\z)") == OK)
		var phase7 := FileAccess.get_file_as_string(PHASE7_RENDER_ARMY)
		assert(matcher.search_all(original).size() == 1 and matcher.search_all(phase7).size() == 1)
		original = original.replace(matcher.search(original).get_string(), matcher.search(phase7).get_string())
		var batch_script := load(BATCH) as GDScript
		batch_script.source_code = FileAccess.get_file_as_string(PHASE7_BATCH)
		assert(batch_script.reload(true) == OK)
	var phase4_methods: Array[String] = []
	if "--phase4-orders" in OS.get_cmdline_user_args(): phase4_methods.append("_try_exchange_encirclement")
	if "--phase4-prepare" in OS.get_cmdline_user_args(): phase4_methods.append("prepare_combat")
	var baseline := FileAccess.get_file_as_string(PHASE4_ARMY)
	for method: String in phase4_methods:
		var matcher := RegEx.new()
		assert(matcher.compile("(?ms)^func " + method + "\\([^\\n]*\\n.*?(?=^(?:static )?func |\\z)") == OK)
		assert(matcher.search_all(original).size() == 1 and matcher.search_all(baseline).size() == 1)
		original = original.replace(matcher.search(original).get_string(), matcher.search(baseline).get_string())
	var phase5_methods: Array[String] = []
	if "--phase5-prepare" in OS.get_cmdline_user_args(): phase5_methods.append("prepare_combat")
	if "--phase5-render" in OS.get_cmdline_user_args(): phase5_methods.append("_set_soldier_frame")
	var phase5 := FileAccess.get_file_as_string(PHASE5_ARMY)
	for method: String in phase5_methods:
		assert(not phase4_methods.has(method), "Select only one baseline per method")
		var matcher := RegEx.new()
		assert(matcher.compile("(?ms)^func " + method + "\\([^\\n]*\\n.*?(?=^(?:static )?func |\\z)") == OK)
		assert(matcher.search_all(original).size() == 1 and matcher.search_all(phase5).size() == 1)
		original = original.replace(matcher.search(original).get_string(), matcher.search(phase5).get_string())
	var phase6_prepare := "--phase6-prepare" in OS.get_cmdline_user_args()
	if phase6_prepare:
		assert(not phase4_methods.has("prepare_combat") and not phase5_methods.has("prepare_combat"))
		var matcher := RegEx.new()
		assert(matcher.compile("(?ms)^func prepare_combat\\([^\\n]*\\n.*?(?=^(?:static )?func |\\z)") == OK)
		var phase6 := FileAccess.get_file_as_string(PHASE6_ARMY)
		assert(matcher.search_all(original).size() == 1 and matcher.search_all(phase6).size() == 1)
		original = original.replace(matcher.search(original).get_string(), matcher.search(phase6).get_string())
	if p1_profile:
		assert(not s1_profile and "--hot-profile" not in OS.get_cmdline_user_args(), "P1 cannot stack source probes")
		original = _p1_instrument_army(original)
	var guard := DEPLOYMENT_GUARD
	if s1_profile:
		for required: String in ["--profile", "--spike-profile", "--stall-profile"]:
			assert(required in OS.get_cmdline_user_args(), "S1 requires " + required)
		original = _s1_instrument_army(original)
	source_hash = FileAccess.get_sha256(ARMY)
	if original.count(guard) != 1:
		_fail("Deployment guard is not unique")
		return
	var deployment_override_applied := per_team > TerrainArmy.MAX_ROSTER_SIZE
	var deployment_limit := maxi(2500, per_team) if deployment_override_applied else TerrainArmy.MAX_ROSTER_SIZE
	if deployment_override_applied: original = original.replace(guard, "selected.size() > %d" % deployment_limit)
	if original != army_script.source_code:
		army_script.source_code = original
		if army_script.reload(true) != OK:
			_fail("In-memory Army source could not compile")
			return
	var phase6_fatigue := "--phase6-fatigue" in OS.get_cmdline_user_args()
	if phase6_fatigue:
		var lab_script := load("res://scripts/terrain_lab/terrain_lab.gd") as GDScript
		var matcher := RegEx.new()
		assert(matcher.compile("(?ms)^func _advance_fatigue\\([^\\n]*\\n.*?(?=^(?:static )?func |\\z)") == OK)
		var baseline_lab := FileAccess.get_file_as_string(PHASE6_LAB)
		assert(matcher.search_all(lab_script.source_code).size() == 1 and matcher.search_all(baseline_lab).size() == 1)
		lab_script.source_code = lab_script.source_code.replace(matcher.search(lab_script.source_code).get_string(), matcher.search(baseline_lab).get_string())
		assert(lab_script.reload(true) == OK)
	var legacy_samples := "--legacy-render-samples" in OS.get_cmdline_user_args()
	if legacy_samples:
		assert(not phase7_render)
		var batch_script := load(BATCH) as GDScript
		batch_script.source_code = FileAccess.get_file_as_string(LEGACY_BATCH)
		if batch_script.reload(true) != OK:
			_fail("Frozen phase-three renderer could not compile")
			return
	if p1_profile:
		assert(not phase7_render and not legacy_samples and "--phase14-render" not in OS.get_cmdline_user_args(), "P1 needs current BatchView")
		var batch_script := load(BATCH) as GDScript
		batch_script.source_code = _p1_instrument_batch(batch_script.source_code)
		assert(batch_script.reload(true) == OK, "P1 in-memory BatchView must compile")
	report = {"status": "SETUP", "main_scene": MAIN,
		"deployment_only_memory_override": guard + " -> selected.size() > %d" % deployment_limit if deployment_override_applied else "none",
		"deployment_limit": deployment_limit,
		"army_disk_sha256": source_hash, "preset": "PLAINS", "seed": 581, "terrain_modified": false,
		"soldiers": per_team * 2, "teams": 2, "soldiers_per_team": per_team, "sample_target_seconds": duration,
		"fps_definition": "rendered frame count / monotonic wall time", "source_files_edited": false,
		"source_files_edited_compatibility": "Legacy aggregate: disk_source_changed or runtime_source_changed; see separate fields.",
		"disk_source_changed": false, "runtime_source_changed": false,
		"deployment_override_applied": deployment_override_applied, "formal_200_run": formal_200,
		"resident_clock_mode": resident_clock_mode, "resident_clock_mode_explicit": resident_clock_mode_explicit,
		"candidate_hot": candidate_hot, "mechanism_evidence_path": mechanism_evidence_path,
		"resident_clock_teams_after_deployment": [], "resident_clock_teams_measurement_start": [],
		"source_audit": {},
		"engine": Engine.get_version_info(), "cpu": OS.get_processor_name(), "gpu": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name(),
		"user_data": OS.get_user_data_dir(), "checkpoints": []}
	report["project_main_scene"] = ProjectSettings.get_setting("application/run/main_scene")
	if s1_profile:
		report["s1_profile"] = {"anchors": s1_anchors, "original_statements_preserved": true,
			"note": "Diagnostic only. Geometry adds up to four Dictionary lookups per scanned row; review scan time includes that overhead. Nested times are not additive. Duty sizes are once-per-review snapshots, not per-person timings."}
	if p1_profile:
		report["p1_profile"] = {"in_memory_army_and_batch_probe": true, "formal_fps_eligible": false,
			"note": "Packed-row comparisons run after the original pack and before the same MultiMesh assignment. Submitted bytes count the setter payload, not measured GPU bus traffic. Probe comparison time is nested in render_flush and can alter catch-up scheduling. Projection/group/live are nested in render_submit. Root viewport GPU render time can be delayed and excludes Present or fence waits."}
	if formal_200 and str(report.project_main_scene) != MAIN:
		_fail("Formal 200-person run/main_scene is not TerrainLab")
		return
	report["legacy_render_samples"] = legacy_samples
	report["empty_component_reference"] = empty_component_reference
	report["cold_query_startup"] = "--cold-query-startup" in OS.get_cmdline_user_args()
	report["idle_scan_reference"] = "--idle-scan-reference" in OS.get_cmdline_user_args()
	report["counts_reference"] = "--counts-reference" in OS.get_cmdline_user_args()
	report["captain_timeline_reference"] = "--captain-timeline-reference" in OS.get_cmdline_user_args()
	report["context_profile"] = "--context-profile" in OS.get_cmdline_user_args()
	report["presence_profile"] = "--presence-profile" in OS.get_cmdline_user_args()
	report["presence_delta_enabled"] = "--legacy-presence" not in OS.get_cmdline_user_args()
	report["captain_timeline_fixture_sha256"] = FileAccess.get_sha256("res://scripts/tests/fixtures/terrain_army_captain_timeline_original.gd.txt")
	report["counts_fixture_sha256"] = FileAccess.get_sha256("res://scripts/tests/fixtures/terrain_army_counts_original.gd.txt")
	report["fatigue_policy"] = "individual" if "--individual-fatigue" in OS.get_cmdline_user_args() else "shared_except_player"
	report["native_buffer_enabled"] = "--gd-buffers" not in OS.get_cmdline_user_args()
	var gpu_requested := "--gpu-render" in OS.get_cmdline_user_args() or "--verify-gpu-render" in OS.get_cmdline_user_args()
	assert(not gpu_requested or "--gd-render" not in OS.get_cmdline_user_args(), "GPU Canvas trial requires the batch renderer")
	report["gpu_render_requested"] = gpu_requested
	report["phase7_render"] = phase7_render
	report["phase8_queries"] = phase8_queries
	report["phase9_commands"] = phase9_commands
	report["phase10_presence"] = phase10_presence
	report["phase11_prepare"] = phase11_prepare
	report["phase21_seeds"] = phase21_seeds
	report["phase22_ranged"] = phase22_ranged
	report["periodic_review_stagger_enabled"] = "--no-review-stagger" not in OS.get_cmdline_user_args()
	var legacy_combat_summary_refresh := "--legacy-combat-summary-refresh" in OS.get_cmdline_user_args()
	report["combat_summary_tick_mode"] = "legacy_all_windows" if legacy_combat_summary_refresh else "visible_only"
	var legacy_ko_render := "--legacy-ko-render" in OS.get_cmdline_user_args()
	report["native_unconscious_mode"] = "legacy_idle_only" if legacy_ko_render else "idle_and_unconscious"
	report["native_unconscious_view_modes"] = []
	report["phase24_terrain"] = phase24_terrain
	report["phase24_terrain_fixture_sha256"] = FileAccess.get_sha256(PHASE24_TERRAIN)
	report["terrain_runtime_source_sha256"] = (load(TERRAIN_RENDERER) as GDScript).source_code.sha256_text()
	report["phase22_ranged_fixture_sha256"] = FileAccess.get_sha256(PHASE22_RANGED)
	report["phase21_seeds_fixture_sha256"] = FileAccess.get_sha256(PHASE21_SEEDS)
	report["phase12_components"] = phase12_components
	report["phase14_render"] = phase14_render
	report["phase14_frame_fixture_sha256"] = FileAccess.get_sha256(PHASE14_FRAME)
	report["phase14_batch_fixture_sha256"] = FileAccess.get_sha256(PHASE14_BATCH)
	report["native_grouping_enabled"] = not phase14_render and not phase7_render and not legacy_samples and "--gd-groups" not in OS.get_cmdline_user_args()
	report["phase12_components_fixture_sha256"] = FileAccess.get_sha256(PHASE12_COMPONENTS)
	report["editor_runtime_source_sha256"] = (load(EDITOR) as GDScript).source_code.sha256_text()
	report["phase11_prepare_fixture_sha256"] = FileAccess.get_sha256(PHASE11_PREPARE)
	report["phase10_presence_fixture_sha256"] = FileAccess.get_sha256(PHASE10_PRESENCE)
	report["phase9_commands_fixture_sha256"] = FileAccess.get_sha256(PHASE9_COMMANDS)
	report["phase8_snapshot_fixture_sha256"] = FileAccess.get_sha256(PHASE8_SNAPSHOT)
	report["phase8_lab_fixture_sha256"] = FileAccess.get_sha256(PHASE8_LAB)
	report["snapshot_runtime_source_sha256"] = (load("res://scripts/terrain_lab/site_exchange_snapshot.gd") as GDScript).source_code.sha256_text()
	report["phase7_army_fixture_sha256"] = FileAccess.get_sha256(PHASE7_RENDER_ARMY)
	report["phase7_batch_fixture_sha256"] = FileAccess.get_sha256(PHASE7_BATCH)
	report["batch_runtime_source_sha256"] = (load(BATCH) as GDScript).source_code.sha256_text()
	report["legacy_render_fixture_sha256"] = FileAccess.get_sha256(LEGACY_BATCH)
	report["phase4_army_methods"] = phase4_methods
	report["phase5_army_methods"] = phase5_methods
	report["phase6_prepare"] = phase6_prepare
	report["phase6_fatigue"] = phase6_fatigue
	report["phase6_lab_fixture_sha256"] = FileAccess.get_sha256(PHASE6_LAB)
	report["lab_runtime_source_sha256"] = (load("res://scripts/terrain_lab/terrain_lab.gd") as GDScript).source_code.sha256_text()
	report["phase6_fixture_sha256"] = FileAccess.get_sha256(PHASE6_ARMY)
	report["phase5_army_fixture_sha256"] = FileAccess.get_sha256(PHASE5_ARMY)
	report["army_runtime_source_sha256"] = army_script.source_code.sha256_text()
	report["phase4_army_fixture_sha256"] = FileAccess.get_sha256(PHASE4_ARMY)
	var hashes := {}
	hashes["res://scripts/terrain_lab/terrain_test_npc.gd"] = FileAccess.get_sha256("res://scripts/terrain_lab/terrain_test_npc.gd")
	hashes[FIXTURE] = FileAccess.get_sha256(FIXTURE)
	for path: String in [ARMY, EDITOR, "res://scripts/terrain_lab/terrain_lab.gd", "res://scripts/terrain_lab/terrain_army_batch_view.gd", "res://scripts/terrain_lab/site_controller.gd", "res://scripts/terrain_lab/site_exchange_snapshot.gd", "res://scripts/terrain_lab/compiled_exchange_candidates.cs", "res://worldgoing.csproj", "res://.godot/mono/temp/bin/Debug/worldgoing.dll", "res://project.godot", MAIN]:
		hashes[path] = FileAccess.get_sha256(path)
	report["implementation_sha256"] = hashes
	report["resident_clock_fixture_sha256"] = hashes[FIXTURE]
	for path: String in ["res://native/army_idle/army_idle.cpp", "res://native/army_idle/army_idle.gdextension", "res://native/army_idle/bin/army_idle.windows.x86_64.dll"]:
		hashes[path] = FileAccess.get_sha256(path)
	for relative: String in ["standard_soldier_atlas.json", "ranged/v1/bow_01/manifest.json", "ranged/v1/crossbow_01/manifest.json", "dyes/v1/base.json", "dyes/v1/bow_01.json", "dyes/v1/crossbow_01.json"]:
		var path := "res://assets/characters/terrain_lab_army/standard_soldier/" + relative
		hashes[path] = FileAccess.get_sha256(path)
	hashes[Atlas.CATALOG] = FileAccess.get_sha256(Atlas.CATALOG)
	for relative: String in ["person_fatigue.gd", "terrain_test_character.gd", "site_work_team.gd", "site_sustain.gd", "site_person_actions.gd"]:
		var path := "res://scripts/terrain_lab/" + relative
		hashes[path] = FileAccess.get_sha256(path)
	for relative: String in ["terrain_renderer.gd", "terrain_render_layer.gd", "site_resource_view.gd"]:
		var path := "res://scripts/terrain_lab/" + relative
		hashes[path] = FileAccess.get_sha256(path)
	# Hash original live-render sources outside the timed section as well;
	# an asset publication must invalidate a run just like a script edit.
	for path: String in [HumanCharacter3DEditor.MALE_MODEL_PATH, HumanCharacter3DEditor.FEMALE_MODEL_PATH, HumanCharacter3DEditor.COMBAT_PROPS_PATH, "res://scripts/ui/equipment_dye.gd"]:
		hashes[path] = FileAccess.get_sha256(path)
	if candidate_hot:
		var source_capture: Dictionary = MechanismGate.capture_source_manifest()
		for path: String in source_capture.hashes:
			hashes[path] = source_capture.hashes[path]
		if not mechanism_diagnostic:
			report["mechanism_gate"] = MechanismGate.validate(mechanism_evidence_path, source_capture)
			if not bool(report.mechanism_gate.passed):
				_fail("Mechanism evidence rejected: " + str(report.mechanism_gate.failures))
				return
	report["source_parity_setup"] = _audit_sources("setup")
	_event("loading_original_main_scene")
	if "--loop-prepare-reference" in OS.get_cmdline_user_args():
		var script := load(EDITOR) as GDScript
		var call := "\t_prepare_animation_loop_defaults()\n"
		assert(script.source_code.count(call) == 1)
		script.source_code = script.source_code.replace(call, "")
		assert(script.reload(true) == OK)
	report["loop_prepare_reference"] = "--loop-prepare-reference" in OS.get_cmdline_user_args()
	if "--weapon-groups-reference" in OS.get_cmdline_user_args():
		var script := load(EDITOR) as GDScript
		var original_editor := FileAccess.get_file_as_string("res://output/site_army_actor_spikes_20260916/before/human_character_3d_editor.gd.txt")
		var matcher := RegEx.new()
		assert(matcher.compile("(?ms)^func _update_weapon_sheath_state\\([^\\n]*\\n.*?(?=^func )") == OK)
		assert(matcher.search_all(script.source_code).size() == 1 and matcher.search_all(original_editor).size() == 1)
		script.source_code = script.source_code.replace(matcher.search(script.source_code).get_string(), matcher.search(original_editor).get_string())
		assert(script.reload(true) == OK)
	report["weapon_groups_reference"] = "--weapon-groups-reference" in OS.get_cmdline_user_args()
	if "--weapon-prefix-reference" in OS.get_cmdline_user_args():
		var script := load(EDITOR) as GDScript
		var previous := FileAccess.get_file_as_string("res://output/site_army_weapon_prefix_20260916/before/human_character_3d_editor.gd.txt")
		var matcher := RegEx.new()
		assert(matcher.compile("(?ms)^func _weapon_component_groups\\([^\\n]*\\n.*?(?=^func )") == OK)
		assert(matcher.search_all(script.source_code).size() == 1 and matcher.search_all(previous).size() == 1)
		script.source_code = script.source_code.replace(matcher.search(script.source_code).get_string(), matcher.search(previous).get_string())
		assert(script.reload(true) == OK)
	report["weapon_prefix_reference"] = "--weapon-prefix-reference" in OS.get_cmdline_user_args()
	report["editor_runtime_source_sha256"] = (load(EDITOR) as GDScript).source_code.sha256_text()
	if "--morph-zero-guard" in OS.get_cmdline_user_args():
		preload("res://scripts/tests/fixtures/animation_morph_zero_guard.gd").install()
		report["morph_zero_guard"] = true
		report["morph_zero_guard_fixture_sha256"] = FileAccess.get_sha256("res://scripts/tests/fixtures/animation_morph_zero_guard.gd")
		report["editor_runtime_source_sha256"] = (load(EDITOR) as GDScript).source_code.sha256_text()
	if "--animation-switch-profile" in OS.get_cmdline_user_args():
		assert("--actor-apply-profile" in OS.get_cmdline_user_args() and "--spike-profile" in OS.get_cmdline_user_args())
		if "--appearance-weapon-batch" in OS.get_cmdline_user_args():
			preload("res://scripts/tests/fixtures/appearance_weapon_batch_install.gd").install()
			report["appearance_weapon_batch"] = true
		_instrument_animation_switch()
		report["animation_switch_profile"] = true
	if "--owner-profile" in OS.get_cmdline_user_args():
		_instrument_owner("res://scripts/terrain_lab/terrain_lab.gd", ["_process", "_update_info"])
		_instrument_owner("res://scripts/terrain_lab/terrain_test_character.gd", ["_process", "_draw"])
		_instrument_owner(EDITOR, ["_process"])
		report["owner_profile_note"] = "Diagnostic inclusive callback times; nested child timings overlap parents. Not an uninstrumented FPS score."
	if "--actor-apply-profile" in OS.get_cmdline_user_args():
		assert("--owner-profile" in OS.get_cmdline_user_args())
		_instrument_owner("res://scripts/terrain_lab/terrain_test_character.gd", ["apply_exchange", "_cancel_exchange_legacy_attack", "_start_exchange_visual", "play_pose", "apply_contact", "_cancel_rescue", "_set_attack_offset"])
		_instrument_owner(EDITOR, ["_update_weapon_sheath_state", "_play_selected_animation", "_update_preview_framing", "_update_animation_ui", "_on_timeline_changed", "_update_status"])
	if "--actor-seek-profile" in OS.get_cmdline_user_args():
		assert("--owner-profile" in OS.get_cmdline_user_args())
		_instrument_actor_seek()
	if "--settlement-profile" in OS.get_cmdline_user_args():
		assert("--profile" in OS.get_cmdline_user_args() and "--owner-profile" in OS.get_cmdline_user_args() and "--spike-profile" in OS.get_cmdline_user_args())
		_instrument_settlement()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if "--fps-cap=30" in OS.get_cmdline_user_args(): Engine.max_fps = 30
	OS.low_processor_usage_mode = false
	lab = (load(MAIN) as PackedScene).instantiate() as TerrainLab
	lab.pause_when_unfocused = false
	lab.exchange_batch_enabled = "--legacy-query" not in OS.get_cmdline_user_args()
	lab.combat_profile_enabled = "--profile" in OS.get_cmdline_user_args()
	root.add_child(lab)
	lab.site_controller.refresh_hidden_combat_summary_on_tick = legacy_combat_summary_refresh
	lab.combat_movement_coordinator.idle_tick_skip_enabled = "--full-movement-ticks" not in OS.get_cmdline_user_args()
	report["movement_tick_mode"] = "idle_fast_path" if lab.combat_movement_coordinator.idle_tick_skip_enabled else "full"
	current_scene = lab
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	lab.site_controller._auto_save_blocked = true
	var ten_thousand := per_team == 5000
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581,
		{"size": Vector2i(128, 128)} if ten_thousand else {})
	Env.initialize(data, "fps5000-transient")
	report["map_cells"] = str(data.size)
	report["ten_thousand_trial"] = ten_thousand
	lab.bind_terrain(data)
	if candidate_hot:
		report["product_hot_preconfigured"] = []
		for side in range(2):
			var team: TerrainArmy = lab.combat_armies[side]
			var hot_default := bool(team.get("native_hot_enabled"))
			report.product_hot_preconfigured.append({"side": side,
				"enabled": hot_default, "scene_file_path": lab.scene_file_path})
			if not hot_default or lab.scene_file_path != MAIN:
				_fail("Formal TerrainLab did not enable native hot mode for side %d" % side)
				return
	if "--legacy-resource-redraw" in OS.get_cmdline_user_args():
		lab.site_controller.view.retain_static_rows = false
		lab.site_controller.view.refresh()
	lab.site_controller.release_worker()
	data.site.paused = false
	paused = false
	report["terrain_fingerprint_before"] = data.fingerprint()
	_event("deploying_%d_original_people" % (per_team * 2))
	var selected_owners := {}
	for side in range(2):
		var team: TerrainArmy = lab.combat_armies[side]
		team.periodic_review_stagger_enabled = "--no-review-stagger" not in OS.get_cmdline_user_args()
		team.combat_profile_enabled = lab.combat_profile_enabled
		team.batch_render_enabled = "--sprites" not in OS.get_cmdline_user_args()
		team.native_render_enabled = "--gd-render" not in OS.get_cmdline_user_args()
		team.native_queries_enabled = "--gd-queries" not in OS.get_cmdline_user_args()
		if resident_clock_mode == "on" and not team.has_method("materialized_combat_rows"):
			_fail("Requested resident clock is unavailable in this source")
			return
		if team.has_method("materialized_combat_rows"):
			team.set("resident_clock_enabled", resident_clock_mode == "on")
		var selected: Array[Vector2i] = []
		for depth in range(data.size.x / 2 if ten_thousand else 50):
			for y in range(0 if ten_thousand else 1, data.size.y if ten_thousand else 99):
				var cell := Vector2i(data.size.x / 2 - 1 - depth if side == 0 else data.size.x / 2 + depth, y)
				if data.is_walkable(cell) and not lab.character.occupies_cell(cell) and (lab.npc == null or not lab.npc.occupies_cell(cell)):
					selected.append(cell)
				if selected.size() == per_team:
					break
			if selected.size() == per_team:
				break
		if selected.size() != per_team:
			_fail("Insufficient legal original cells for side %d: %d" % [side, selected.size()])
			return
		if ten_thousand:
			for cell: Vector2i in selected:
				if selected_owners.has(cell) or not data.is_walkable(cell) or (not data.static_blocked.is_empty() and data.static_blocked[data.index(cell)] != 0) or lab.character.occupies_cell(cell) or (lab.npc != null and lab.npc.occupies_cell(cell)):
					_fail("Ten-thousand deployment contains an occupied or illegal cell: %s" % cell)
					return
				selected_owners[cell] = side
		team.shared_fatigue_enabled = "--individual-fatigue" not in OS.get_cmdline_user_args()
		team.roster_size = per_team
		if not team.deploy_at(data, lab.character, lab.npc, selected) or not team.enable_combat():
			_fail("Original deployment/combat initialization failed for side %d" % side)
			return
		if team._batch_view != null:
			team._batch_view.native_buffer_enabled = "--gd-buffers" not in OS.get_cmdline_user_args()
			if team._batch_view.has_method("can_group_prepared"): team._batch_view.native_grouping_enabled = "--gd-groups" not in OS.get_cmdline_user_args()
			var current_batch: bool = team._batch_view.get_script() == load(BATCH)
			if gpu_requested:
				assert(current_batch and team._batch_view.gpu_compute_enabled == false, "GPU Canvas trial requires the original BatchView")
				team._batch_view.gpu_compute_enabled = true
			if current_batch: team._batch_view.native_unconscious_enabled = not legacy_ko_render
			report.native_unconscious_view_modes.append({"side": side, "current_batch": current_batch,
				"enabled": bool(team._batch_view.native_unconscious_enabled) if current_batch else null})
		if team.combat_units.size() != per_team or not team.exchange_enabled or team.visual_mode() != "baked_atlas":
			_fail("Actual people/current combat/original baked presentation check failed")
			return
		for index in range(per_team):
			team.facing[index] = Vector2i.RIGHT if side == 0 else Vector2i.LEFT
		team._visual_dirty = true
		_event("deployed_side_%d" % side)
	report["resident_clock_teams_after_deployment"] = _resident_clock_team_modes()
	report["candidate_hot_teams_after_deployment"] = _candidate_hot_team_modes()
	if candidate_hot and not _candidate_hot_both_active(report.candidate_hot_teams_after_deployment):
		_fail("Candidate hot store is inactive after deployment")
		return
	for mode: Dictionary in report.resident_clock_teams_after_deployment:
		if bool(mode.enabled) and not bool(mode.native_ready):
			_fail("Resident combat clock did not seed side %d" % int(mode.side))
			return
	if ten_thousand:
		report["deployment_legal_unique_cells"] = selected_owners.size()
		if selected_owners.size() != 10000:
			_fail("Ten-thousand deployment did not claim 10000 unique legal cells")
			return
	if "--assert-native-ko-mode" in OS.get_cmdline_user_args():
		assert(report.native_unconscious_view_modes.size() == 2)
		for mode: Dictionary in report.native_unconscious_view_modes:
			assert(bool(mode.current_batch) and bool(mode.enabled) == (not legacy_ko_render), "KO A/B did not select the requested renderer on both teams")
	data.site["army_trial_active"] = true
	assert(not ("--retain-animation-cache" in OS.get_cmdline_user_args() and "--clear-animation-cache" in OS.get_cmdline_user_args()))
	if "--clear-animation-cache" in OS.get_cmdline_user_args():
		for team: TerrainArmy in [lab.army, lab.opposing_army]:
			var presenter: HumanCharacter3DEditor = team._unit_editor(0)
			assert(presenter != null and presenter.animation_player.has_method("set_clear_cache_on_stop_enabled"))
			presenter.animation_player.call("set_clear_cache_on_stop_enabled", true)
	if "--retain-animation-cache" in OS.get_cmdline_user_args():
		report["retain_animation_cache"] = []
		for team: TerrainArmy in [lab.army, lab.opposing_army]:
			var presenter: HumanCharacter3DEditor = team._unit_editor(0)
			assert(presenter != null and presenter.animation_player.has_method("set_clear_cache_on_stop_enabled"), "Cache trial requires the isolated patched engine")
			presenter.animation_player.call("set_clear_cache_on_stop_enabled", false)
			report.retain_animation_cache.append(str(presenter.get_path()))
	report["captain_cache_policy"] = []
	for team: TerrainArmy in lab.combat_armies:
		team.native_presence_delta_enabled = bool(report.presence_delta_enabled)
		team._presence_geometry_cache = []
		var presenter: HumanCharacter3DEditor = team._unit_editor(0)
		if presenter != null and presenter.animation_player.has_method("is_clear_cache_on_stop_enabled"):
			report.captain_cache_policy.append({"path": str(presenter.get_path()), "clear_on_stop": presenter.animation_player.call("is_clear_cache_on_stop_enabled")})
	var retain_npc_cache := "--retain-npc-animation-cache" in OS.get_cmdline_user_args()
	var clear_npc_cache := "--clear-npc-animation-cache" in OS.get_cmdline_user_args()
	assert(not (retain_npc_cache and clear_npc_cache))
	if retain_npc_cache or clear_npc_cache:
		for actor: TerrainTestCharacter in lab.combat_actors:
			if actor != lab.npc: continue
			assert(actor.editor.animation_player.has_method("set_clear_cache_on_stop_enabled"))
			actor.editor.animation_player.call("set_clear_cache_on_stop_enabled", clear_npc_cache)
	report["actor_cache_policy"] = []
	for actor: TerrainTestCharacter in lab.combat_actors:
		if actor.editor.animation_player.has_method("is_clear_cache_on_stop_enabled"):
			report.actor_cache_policy.append({"path": str(actor.get_path()), "clear_on_stop": actor.editor.animation_player.call("is_clear_cache_on_stop_enabled")})
	data.site["army_next_team"] = 3
	lab.fit_map()
	lab.camera.force_update_scroll()
	report["window_pixels"] = str(DisplayServer.window_get_size())
	report["viewport_pixels"] = str(root.get_texture().get_size())
	report["logical_viewport"] = str(lab.get_viewport_rect().size)
	report["camera_zoom"] = str(lab.camera.zoom)
	report["vsync"] = DisplayServer.window_get_vsync_mode()
	report["fps_cap"] = Engine.max_fps
	report["catalog"] = Atlas._catalog_path
	report["initial_life"] = _life()
	if ten_thousand and (int(report.initial_life.rows) != 10000 or int(report.initial_life.living) != 10000):
		_fail("Ten-thousand initial life rows are incomplete")
		return
	_event("warming_original_rendering")
	if "--viewport-profile" in OS.get_cmdline_user_args(): _start_viewport_probe()
	# Warm asset rendering while the native simulation is stationary, matching
	# existing tests. The following measured section enables the untouched Lab.
	var warmup := Time.get_ticks_usec()
	while Time.get_ticks_usec() - warmup < 3000000:
		await process_frame
		await RenderingServer.frame_post_draw
	if "--render-profile" in OS.get_cmdline_user_args():
		report["stationary_render_profile_usec"] = _render_cost_sample()
	if "--verify-render" in OS.get_cmdline_user_args() and not await _verify_render_pair("before"): return
	if "--verify-gpu-render" in OS.get_cmdline_user_args() and not await _verify_gpu_render_pair("before"): return
	report["initial_visibility"] = _visibility()
	# A stale dye/source publication can silently fall back to sprites. Require
	# the real default batch path before accepting a performance comparison.
	if "--sprites" not in OS.get_cmdline_user_args() and per_team >= 64:
		var ordinary := 0
		for team: TerrainArmy in lab.combat_armies:
			ordinary += team._batch_view.rendered_count if team._batch_view != null else 0
		if ordinary != (per_team - 1) * 2:
			_fail("Expected original ordinary-soldier batch not active: " + str(ordinary))
			return
	if mechanism_diagnostic:
		await _run_render_mechanism_diagnostic()
		return
	report["nodes_before"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	report["viewport_pixels_after_warmup"] = str(root.get_texture().get_size())
	report["shader_instance_buffer_size"] = ProjectSettings.get_setting("rendering/limits/global_shader_variables/buffer_size")
	if not _capture("before"):
		_fail("Initial screenshot failed")
		return
	if int(report.initial_visibility.visible_textured_sprites) != per_team * 2 or int(report.initial_visibility.outside_unobscured_map) > 0:
		_fail("Not all %d original sprites are visible on the unobscured map" % (per_team * 2))
		return
	if "--terrain-diagnostic" in OS.get_cmdline_user_args():
		await _terrain_submission_probe()
		return
	if "--verify-terrain" in OS.get_cmdline_user_args():
		await _verify_terrain_pair()
		return
	if "--verify-resources" in OS.get_cmdline_user_args():
		await _verify_resource_pair()
		return
	await process_frame
	await RenderingServer.frame_post_draw
	if trace_handshake and not trace_late_window:
		_request_admin_trace(0.0)
		var deadline := Time.get_ticks_msec() + 20000
		while not FileAccess.file_exists(trace_root + "ready.json") and Time.get_ticks_msec() < deadline:
			await process_frame
		if not FileAccess.file_exists(trace_root + "ready.json"):
			_fail("Administrative trace did not start; no trace-backed measurement")
			return
	assert(not lab.site_controller.combat_window.visible, "UI A/B requires a hidden combat window at measurement start")
	report["source_parity_measurement_start"] = _audit_sources("measurement_start")
	report["resident_clock_teams_measurement_start"] = _resident_clock_team_modes()
	report["candidate_hot_teams_measurement_start"] = _candidate_hot_team_modes()
	if candidate_hot and not _candidate_hot_both_active(report.candidate_hot_teams_measurement_start):
		_fail("Candidate hot store is inactive at measurement start")
		return
	report["window_pixels_measurement_start"] = str(DisplayServer.window_get_size())
	report["viewport_pixels_measurement_start"] = str(root.get_texture().get_size())
	report["viewport_min_width"] = int(root.get_texture().get_size().x)
	report["viewport_min_height"] = int(root.get_texture().get_size().y)
	report["measurement_start_paused"] = paused or bool(data.site.paused)
	report["measurement_start_terrain_fingerprint"] = data.fingerprint()
	if formal_200 and not bool(report.source_parity_measurement_start):
		_fail("Formal 200-person source differs from setup or disk at measurement start")
		return
	_event("measuring_native_battle")
	if "--owner-profile" in OS.get_cmdline_user_args():
		for node: Node in root.find_children("*", "Node", true, false):
			if node is TerrainLab or node is TerrainTestCharacter or node is HumanCharacter3DEditor or ("--settlement-profile" in OS.get_cmdline_user_args() and (node is SiteController or node is TerrainArmy)):
				node.set_meta(&"phase26_owner_usec", {})
				if node.has_meta(&"stall_switch_events"): node.set_meta(&"stall_switch_events", [])
				if node.has_meta(&"stall_settle_events"): node.set_meta(&"stall_settle_events", [])
				owner_probe.append(node)
		report["owner_profile_paths"] = []
		for node: Node in owner_probe: report.owner_profile_paths.append(str(node.get_path()))
	lab.combat_profile_usec.clear()
	for team: TerrainArmy in lab.combat_armies:
		team.combat_render_usec = 0
		team.combat_profile_usec.clear()
		if p1_profile and team._batch_view != null: team._batch_view.set("_p1_totals", {})
		if s1_profile:
			var reviews: Array = team.get("_s1_reviews")
			reviews.clear()
		team.native_idle_rows = 0
		team.native_idle_calls = 0
		team.native_recovery_rows = 0
		team.native_fatigue_rows = 0
		team.native_query_rows = 0
		team.native_front_cells = 0
		team.native_presence_rows = 0
		team.native_presence_delta_calls = 0
		team.native_presence_changed_rows = 0
		team.native_presence_geometry_rebuilds = 0
		team.native_presence_geometry_reuses = 0
	var initial_clock := _clock()
	report["action_remainder_start"] = lab._action_time_remainder
	var initial_exchanges := lab.exchange_count
	var frame_marks: Array[int] = [0, 0, 0, 0]
	var edge_nodes: Array[Node] = []
	var pre_draw_callback := func() -> void: frame_marks[3] = Time.get_ticks_usec()
	if long_stall_profile:
		for first: bool in [true, false]:
			var edge := StallFrameEdge.new()
			edge.first = first
			edge.marks = frame_marks
			edge.process_priority = -2147483648 if first else 2147483647
			edge.process_physics_priority = edge.process_priority
			root.add_child(edge)
			edge_nodes.append(edge)
		RenderingServer.frame_pre_draw.connect(pre_draw_callback)
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
		report["long_stall_profile"] = {"pid": OS.get_process_id(), "engine_main_thread_id": OS.get_main_thread_id(), "utc_start": Time.get_datetime_string_from_system(true),
			"threshold_ms": 100.0, "checkpoint_writes_during_measurement": checkpoint_io_profile,
			"note": "Original simulation unchanged. Scene callbacks and draw boundaries are wall time, not exclusive CPU. Root render timestamps can lag. Physics duration is nested in frame phases."}
	var begin := Time.get_ticks_usec()
	measurement_begin_usec = begin
	if checkpoint_io_profile:
		report["io_writes"] = io_writes
		report["checkpoint_prints"] = checkpoint_prints
	if long_stall_profile or checkpoint_io_profile:
		report["measurement_start_ticks_usec"] = begin
		report["measurement_start_unix_usec"] = int(Time.get_unix_time_from_system() * 1000000.0)
	var animation_cache_events: Array = []
	if "--animation-cache-profile" in OS.get_cmdline_user_args():
		report["animation_libraries"] = []
		for node: Node in root.find_children("*", "Node", true, false):
			if node is HumanCharacter3DEditor and node.animation_player != null:
				var clips := []
				for clip: StringName in node.animation_player.get_animation_list():
					var animation: Animation = node.animation_player.get_animation(clip)
					clips.append({"clip": str(clip), "tracks": animation.get_track_count(), "length": animation.length, "loop": animation.loop_mode})
				report.animation_libraries.append({"editor": str(node.get_path()), "playing": node.animation_player.is_playing(), "clips": clips})
				node.animation_player.caches_cleared.connect(func() -> void:
					# Resource replacement emits this signal between removal and add.
					# Record that intermediate state instead of dereferencing a missing clip.
					var selected_present: bool = node.animation_player.has_animation(node.selected_animation)
					animation_cache_events.append({"at": (Time.get_ticks_usec() - begin) / 1000000.0,
						"editor": str(node.get_path()), "selected": str(node.selected_animation), "stack": get_stack(),
						"playing": node.animation_player.is_playing(), "position": node.animation_player.current_animation_position,
						"length": node.animation_player.current_animation_length,
						"selected_present": selected_present,
						"loop": node.animation_player.get_animation(node.selected_animation).loop_mode if selected_present else null}))
	var previous := begin
	var continuous_frames := 0
	var continuous_min_visible := per_team * 2
	var continuous_max_outside := 0
	var checkpoint := 5.0
	var spike_profile := "--spike-profile" in OS.get_cmdline_user_args()
	var previous_costs := {}
	var previous_p1_totals := {}
	var spike_samples: Array = []
	var stall_samples: Array = []
	var previous_write_usec := report_write_usec
	var previous_physics_usec := frame_marks[2]
	if stall_profile:
		report["stall_profile_note"] = "Diagnostic wall-time partition, not exclusive CPU/GPU attribution. probe_tail includes the preceding sample bookkeeping and report write; wait_process includes engine/OS wait before process_frame; process_draw includes scene processing and draw submission. GPU timestamps may be delayed. No simulation changes."
		report["engine_step_limits"] = {"physics_ticks_per_second": Engine.physics_ticks_per_second, "max_physics_steps_per_frame": Engine.max_physics_steps_per_frame}
	var previous_completed_clock: float = lab._exchange_round * TerrainLab.EXCHANGE_QUERY_STEP + lab._exchange_phase
	var late_trace_checked := false
	lab.set_process(true)
	while Time.get_ticks_usec() - begin < int(duration * 1000000):
		var wait_started := Time.get_ticks_usec() if stall_profile else 0
		var probe_tail_ms := (wait_started - previous) / 1000.0 if stall_profile else 0.0
		await process_frame
		var process_started := Time.get_ticks_usec() if stall_profile else 0
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		intervals.append((now - previous) / 1000.0)
		frame_at.append((now - begin) / 1000000.0)
		previous = now
		if continuous_visibility:
			var sight := _visibility()
			continuous_frames += 1
			continuous_min_visible = mini(continuous_min_visible, int(sight.visible_textured_sprites))
			continuous_max_outside = maxi(continuous_max_outside, int(sight.outside_unobscured_map))
			if int(sight.visible_textured_sprites) != per_team * 2 or int(sight.outside_unobscured_map) != 0:
				report["continuous_visibility"] = {"frames_checked": continuous_frames,
					"first_failure_frame": intervals.size(), "first_failure_at": frame_at[-1], "first_failure": sight,
					"minimum_visible": continuous_min_visible, "maximum_outside": continuous_max_outside}
				_fail("Continuous presented-frame visibility failed at frame %d" % intervals.size())
				return
		if stall_profile:
			var wait_process_ms := (process_started - wait_started) / 1000.0
			var process_draw_ms := (now - process_started) / 1000.0
			var write_ms := (report_write_usec - previous_write_usec) / 1000.0
			assert(absf(probe_tail_ms + wait_process_ms + process_draw_ms - intervals[-1]) < 0.005, "Frame partition must cover the full wall interval")
			assert(write_ms <= probe_tail_ms + 0.005, "Report writes are nested within preceding diagnostic bookkeeping")
			stall_samples.append({"at": frame_at[-1], "ms": intervals[-1], "probe_tail_ms": probe_tail_ms,
				"report_write_ms": write_ms, "wait_process_ms": wait_process_ms, "process_draw_ms": process_draw_ms,
				"process_delta_ms": lab.get_process_delta_time() * 1000.0})
			if long_stall_profile:
				assert(process_started <= frame_marks[0] and frame_marks[0] <= frame_marks[3] and frame_marks[3] <= now, "Frame boundary order")
				var sample: Dictionary = stall_samples[-1]
				if rd_timestamps_profile:
					sample["pre_draw_ticks_usec"] = frame_marks[3]
					sample["post_draw_ticks_usec"] = now
				sample["scene_callbacks_ms"] = (frame_marks[0] - process_started) / 1000.0
				sample["after_callbacks_ms"] = (frame_marks[3] - frame_marks[0]) / 1000.0
				sample["draw_submission_ms"] = (now - frame_marks[3]) / 1000.0
				sample["physics_callbacks_ms"] = (frame_marks[2] - previous_physics_usec) / 1000.0
				sample["root_render_cpu_ms"] = RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
				sample["root_render_gpu_ms"] = RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
				previous_physics_usec = frame_marks[2]
				if intervals[-1] >= 100.0:
					print("LONG_STALL_CAPTURE ", JSON.stringify(sample))
					# Preserve the circular OS trace at the FIRST measured long event.
					# This diagnostic write happens after the recorded frame endpoint.
					if not trace_stop_path.is_empty() and (not trace_handshake or (intervals[-1] >= 250.0 and FileAccess.file_exists(trace_root + "ready.json"))) and not FileAccess.file_exists(trace_stop_path):
						var marker := FileAccess.open(trace_stop_path, FileAccess.WRITE)
						assert(marker != null)
						marker.store_string(JSON.stringify(sample))
						marker.close()
			previous_write_usec = report_write_usec
		if spike_profile:
			var costs := {}
			for team: TerrainArmy in lab.combat_armies:
				for key: String in team.combat_profile_usec:
					costs[key] = int(costs.get(key, 0)) + int(team.combat_profile_usec[key])
			for key: String in lab.combat_profile_usec:
				costs["lab_" + key] = int(lab.combat_profile_usec[key])
			for owner_index in owner_probe.size():
				var owner_costs: Dictionary = owner_probe[owner_index].get_meta(&"phase26_owner_usec", {})
				for key: String in owner_costs:
					costs["owner%d_%s" % [owner_index, key]] = int(owner_costs[key])
			var sample := {"ms": intervals[-1], "at": frame_at[-1]}
			if s1_profile or p1_profile: sample["frame_id"] = Engine.get_process_frames()
			var completed_clock: float = lab._exchange_round * TerrainLab.EXCHANGE_QUERY_STEP + lab._exchange_phase
			sample["action_steps"] = roundi((completed_clock - previous_completed_clock) / TerrainLab.EXCHANGE_ACTION_STEP)
			previous_completed_clock = completed_clock
			for key: String in costs:
				sample[key] = (int(costs[key]) - int(previous_costs.get(key, 0))) / 1000.0
			if p1_profile:
				var p1_totals := {}
				for team: TerrainArmy in lab.combat_armies:
					if team._batch_view != null:
						var view_totals: Dictionary = team._batch_view.get("_p1_totals")
						for key: String in view_totals:
							p1_totals[key] = int(p1_totals.get(key, 0)) + int(view_totals[key])
					for pair: Array in [["native_idle_rows", team.native_idle_rows], ["native_recovery_rows", team.native_recovery_rows], ["native_idle_calls", team.native_idle_calls]]:
						p1_totals[pair[0]] = int(p1_totals.get(pair[0], 0)) + int(pair[1])
				for key: String in p1_totals:
					sample["p1_" + key] = int(p1_totals[key]) - int(previous_p1_totals.get(key, 0))
				previous_p1_totals = p1_totals
			spike_samples.append(sample)
			previous_costs = costs
		if not viewport_probe.is_empty(): _sample_viewport_probe()
		if rd_timestamps_profile: RenderingServer.call_on_render_thread(_sample_rd_timestamps)
		# Start only once, after the measured frame endpoint. Never await the
		# administrative controller in the battle loop; its startup is observable.
		if trace_late_window and not trace_requested and frame_at[-1] >= 180.0:
			_request_admin_trace(frame_at[-1])
		if trace_late_window and trace_requested and not late_trace_checked and frame_at[-1] >= float(report.admin_trace_request.battle_at_seconds) + 20.0:
			if not FileAccess.file_exists(trace_root + "ready.json"):
				_fail("Late administrative trace did not start within 20 seconds")
				return
			late_trace_checked = true
		if frame_at[-1] >= checkpoint or intervals.size() == 1:
			var progress := {"wall": frame_at[-1], "frames": intervals.size(), "fps": intervals.size() / frame_at[-1],
				"exchanges": lab.exchange_count - initial_exchanges, "action_clock_seconds": _clock() - initial_clock}
			report.checkpoints.append(progress)
			if checkpoint_io_profile: _write()
			var print_begin := Time.get_ticks_usec()
			print("FPS5000_PROGRESS ", JSON.stringify(progress))
			if checkpoint_io_profile: checkpoint_prints.append({"at": frame_at[-1], "ms": (Time.get_ticks_usec() - print_begin) / 1000.0})
			checkpoint = frame_at[-1] + 5.0
	lab.set_process(false)
	if continuous_visibility:
		report["continuous_visibility"] = {"frames_checked": continuous_frames,
			"minimum_visible": continuous_min_visible, "maximum_outside": continuous_max_outside,
			"all_presented_frames_admitted": continuous_frames == intervals.size() and continuous_min_visible == per_team * 2 and continuous_max_outside == 0}
	if long_stall_profile:
		RenderingServer.frame_pre_draw.disconnect(pre_draw_callback)
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), false)
		for edge: Node in edge_nodes: edge.queue_free()
	var wall := (previous - begin) / 1000000.0
	var sorted := intervals.duplicate()
	sorted.sort()
	report["status"] = "MEASURED"
	report["wall_seconds"] = wall
	report["frames"] = intervals.size()
	report["fps"] = intervals.size() / wall
	report["p50_ms"] = sorted[ceili(sorted.size() * 0.50) - 1]
	report["p95_ms"] = sorted[ceili(sorted.size() * 0.95) - 1]
	report["p99_ms"] = sorted[ceili(sorted.size() * 0.99) - 1]
	report["max_ms"] = sorted.back()
	report["frame_ms"] = intervals
	report["frame_at"] = frame_at
	if spike_profile: report["spike_samples"] = spike_samples
	if p1_profile:
		report["p1_metric_totals"] = previous_p1_totals
		report["p1_profile"]["frames_with_counters"] = spike_samples.size()
	if stall_profile: report["stall_samples"] = stall_samples
	if s1_profile:
		var frames_by_id := {}
		for i in range(spike_samples.size()):
			frames_by_id[int(spike_samples[i].frame_id)] = i
		var reviews: Array[Dictionary] = []
		for team: TerrainArmy in lab.combat_armies:
			for review: Dictionary in team.get("_s1_reviews"):
				assert(frames_by_id.has(int(review.frame_id)), "S1 review must have a presented frame")
				var i: int = frames_by_id[int(review.frame_id)]
				review["at"] = (int(review.ended_usec) - begin) / 1000000.0
				review["started_at"] = (int(review.started_usec) - begin) / 1000000.0
				assert(float(review.started_at) >= (frame_at[i - 1] if i > 0 else 0.0) and float(review.at) <= frame_at[i], "S1 review timing must fit its recorded frame")
				reviews.append(review)
		reviews.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.started_usec) < int(b.started_usec))
		assert(not reviews.is_empty(), "S1 needs at least one complete encirclement review")
		report["s1_reviews"] = reviews
	if rd_timestamps_profile:
		assert(not rd_timestamp_samples.is_empty(), "No resolved RD timestamps were captured")
		report["rd_timestamp_profile"] = {"samples": rd_timestamp_samples,
			"thread_model": ProjectSettings.get_setting("rendering/driver/threads/thread_model", 1),
			"marker_columns": ["name", "cpu_usec", "gpu_nsec"],
			"note": "Read-only existing viewport markers. Resolve delayed rows by CPU timestamp containment within pre/post draw bounds. Warmup and final unresolved frames are not complete coverage. CPU wall segments are not exclusive CPU; GPU spans do not measure Present/fence waits. Observer reads occur after the frame endpoint."}
	if "--animation-cache-profile" in OS.get_cmdline_user_args(): report["animation_cache_events"] = animation_cache_events.duplicate(true)
	report["retained_resources"] = lab.site_controller.view.retain_static_rows
	report["action_clock_seconds"] = _clock() - initial_clock
	report["action_remainder_end"] = lab._action_time_remainder
	report["exchanges"] = lab.exchange_count - initial_exchanges
	report["combat_profile_usec"] = lab.combat_profile_usec
	report["team_render_usec"] = lab.army.combat_render_usec + lab.opposing_army.combat_render_usec
	if not owner_probe.is_empty():
		report["owner_profile_usec"] = {}
		for node: Node in owner_probe:
			report.owner_profile_usec[str(node.get_path())] = node.get_meta(&"phase26_owner_usec", {}).duplicate()
	if "--animation-switch-profile" in OS.get_cmdline_user_args():
		report["animation_switch_events"] = {}
		for node: Node in owner_probe:
			if node.has_meta(&"stall_switch_events"):
				report.animation_switch_events[str(node.get_path())] = node.get_meta(&"stall_switch_events").duplicate(true)
	if "--settlement-profile" in OS.get_cmdline_user_args():
		for key: String in ["settle_deaths", "settle_jobs_and_messages", "settle_supply", "settle_commands", "settle_family"]:
			assert(lab.combat_profile_usec.has(key), "Missing settlement timing: " + key)
		report["settlement_events"] = {}
		for node: Node in owner_probe:
			if node.has_meta(&"stall_settle_events"):
				report.settlement_events[str(node.get_path())] = node.get_meta(&"stall_settle_events").duplicate(true)
	report["phase17_live_loop"] = "--phase17-live-loop" in OS.get_cmdline_user_args()
	report["team_profile_calls"] = []
	for team: TerrainArmy in lab.combat_armies:
		var calls := {}
		for key: String in ["probe_select_calls", "probe_seek_calls", "probe_same_time_calls"]:
			if team.combat_profile_usec.has(key):
				calls[key] = team.combat_profile_usec[key]
				team.combat_profile_usec.erase(key)
		report.team_profile_calls.append(calls)
	report["team_profile_usec"] = [lab.army.combat_profile_usec, lab.opposing_army.combat_profile_usec]
	report["draw_calls_final"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	report["batch_structure_final"] = []
	for side in range(2):
		var view: Node = lab.combat_armies[side]._batch_view
		var structure := {"side": side}
		for field: String in ["active_batches"]:
			if _has_property(view, field): structure[field] = int(view.get(field))
		if _has_property(view, "_pages"):
			var pages: Array = view.get("_pages")
			structure["pages"] = pages.size()
		if _has_property(view, "_group_spans"):
			var spans: PackedInt32Array = view.get("_group_spans")
			structure["group_spans"] = int(spans.size() / 5.0)
		report.batch_structure_final.append(structure)
	report["batch_rendered"] = (int(lab.army._batch_view.rendered_count) if lab.army._batch_view != null else 0) + (int(lab.opposing_army._batch_view.rendered_count) if lab.opposing_army._batch_view != null else 0)
	report["profile_enabled"] = lab.combat_profile_enabled
	report["exchange_batch_enabled"] = lab.exchange_batch_enabled
	report["exchange_native_kernel"] = lab._exchange_kernel != null
	report["native_idle_rows"] = lab.army.native_idle_rows + lab.opposing_army.native_idle_rows
	report["native_idle_calls"] = lab.army.native_idle_calls + lab.opposing_army.native_idle_calls
	report["native_recovery_rows"] = lab.army.native_recovery_rows + lab.opposing_army.native_recovery_rows
	report["native_fatigue_rows"] = lab.army.native_fatigue_rows + lab.opposing_army.native_fatigue_rows
	report["native_query_rows"] = lab.army.native_query_rows + lab.opposing_army.native_query_rows
	report["native_front_cells"] = lab.army.native_front_cells + lab.opposing_army.native_front_cells
	report["native_presence_rows"] = lab.army.native_presence_rows + lab.opposing_army.native_presence_rows
	for field: String in ["native_presence_delta_calls", "native_presence_changed_rows", "native_presence_geometry_rebuilds", "native_presence_geometry_reuses"]:
		report[field] = int(lab.army.get(field)) + int(lab.opposing_army.get(field))
	report["native_render_enabled"] = not phase7_render and lab.army.native_render_enabled
	report["native_rendered_final"] = 0 if phase7_render else (int(lab.army._batch_view.native_prepared_count) if lab.army._batch_view != null else 0) + (int(lab.opposing_army._batch_view.native_prepared_count) if lab.opposing_army._batch_view != null else 0)
	report["native_grouped_final"] = 0
	for team: TerrainArmy in lab.combat_armies:
		if team._batch_view != null and team._batch_view.has_method("can_group_prepared"): report["native_grouped_final"] += team._batch_view.native_grouped_count
	report["final_life"] = _life()
	var final_pose_counts := {}
	var final_native_by_pose := {}
	for team: TerrainArmy in [lab.army, lab.opposing_army]:
		for index in range(team.combat_units.size()):
			var pose := str(_logical_hot_field(team, index, &"pose", ""))
			final_pose_counts[pose] = int(final_pose_counts.get(pose, 0)) + 1
			if team._batch_view != null and index < team._batch_view._native_mask.size() and team._batch_view._native_mask[index] != 0:
				final_native_by_pose[pose] = int(final_native_by_pose.get(pose, 0)) + 1
	report["final_pose_counts"] = final_pose_counts
	report["final_native_by_pose"] = final_native_by_pose
	report["final_visibility"] = _visibility()
	report["encirclement_steps"] = lab.army.encirclement_steps + lab.opposing_army.encirclement_steps
	report["nodes_after"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	report["native_buffer_instances"] = lab.army._batch_view.native_buffer_instances + lab.opposing_army._batch_view.native_buffer_instances if lab.army._batch_view != null and lab.opposing_army._batch_view != null else 0
	report["team_fatigue"] = [lab.army.team_fatigue.duplicate(), lab.opposing_army.team_fatigue.duplicate()]
	report["army_disk_unchanged"] = source_hash == FileAccess.get_sha256(ARMY)
	report["resident_clock_teams_end"] = _resident_clock_team_modes()
	report["candidate_hot_teams_end"] = _candidate_hot_team_modes()
	if candidate_hot and not _candidate_hot_both_active(report.candidate_hot_teams_end):
		_fail("Candidate hot store became inactive during measurement")
		return
	report["window_pixels_end"] = str(DisplayServer.window_get_size())
	report["viewport_pixels_end"] = str(root.get_texture().get_size())
	report["viewport_min_width"] = mini(int(report.viewport_min_width), int(root.get_texture().get_size().x))
	report["viewport_min_height"] = mini(int(report.viewport_min_height), int(root.get_texture().get_size().y))
	report["source_parity_end"] = _audit_sources("end")
	report["implementation_unchanged_during_measurement"] = true
	var changed_implementation_paths: Array[String] = []
	for path: String in hashes:
		if str(hashes[path]) != FileAccess.get_sha256(path):
			report["implementation_unchanged_during_measurement"] = false
			changed_implementation_paths.append(path)
	report["terrain_fingerprint_after"] = data.fingerprint()
	report["paused"] = paused or bool(data.site.paused)
	if not changed_implementation_paths.is_empty():
		report["changed_implementation_paths"] = changed_implementation_paths
		lab.queue_free()
		_fail("Implementation changed during measurement: " + str(changed_implementation_paths))
		return
	if ten_thousand:
		report["ten_thousand_acceptance"] = {
			"unique_legal_deployment": int(report.deployment_legal_unique_cells) == 10000,
			"initial_life_rows": int(report.initial_life.rows) == 10000,
			"final_life_rows": int(report.final_life.rows) == 10000,
			"final_all_accounted": int(report.final_life.living) + int(report.final_life.dead) == 10000,
			"final_visible": int(report.final_visibility.visible_textured_sprites) == 10000 and int(report.final_visibility.outside_unobscured_map) == 0,
			"battle_advanced": int(report.exchanges) > 0 and float(report.action_clock_seconds) > 0.0,
			"full_duration": float(report.wall_seconds) >= duration,
			"unpaused": not bool(report.paused)}
		for check: String in report.ten_thousand_acceptance:
			if not bool(report.ten_thousand_acceptance[check]):
				_fail("Ten-thousand formal battle check failed: " + check)
				return
	if "--verify-render" in OS.get_cmdline_user_args() and not await _verify_render_pair("after"): return
	if "--verify-gpu-render" in OS.get_cmdline_user_args() and not await _verify_gpu_render_pair("after"): return
	if gpu_requested:
		report["gpu_render_status"] = []
		for team: TerrainArmy in [lab.army, lab.opposing_army]:
			var view = team._batch_view
			var status := {"dispatches": view.gpu_dispatch_count, "fallbacks": view.gpu_fallback_count,
				"last_error": view.gpu_last_error}
			report.gpu_render_status.append(status)
			if int(status.dispatches) <= 0 or int(status.fallbacks) > 0 or not str(status.last_error).is_empty():
				_fail("GPU Canvas trial fell back or did not dispatch: " + str(status))
				return
	if not _capture("after"):
		_fail("Final screenshot failed")
		return
	if formal_200:
		report["formal_200_performance_gate"] = _formal_200_performance_gate()
		if not bool(report.formal_200_performance_gate.passed):
			report["status"] = "MEASURED_NOT_CLOSED"
			_write()
			push_error("Formal 200-person performance gate failed: " + str(report.formal_200_performance_gate.failures))
			done = true
			lab.queue_free()
			quit(1)
			return
	if per_team == 2500 and duration == 60.0 or "--assert-5k-performance" in OS.get_cmdline_user_args():
		report["formal_5k_performance_gate"] = _formal_5k_performance_gate(frame_at, intervals)
		if "--assert-5k-performance" in OS.get_cmdline_user_args() and not bool(report.formal_5k_performance_gate.passed):
			report["status"] = "MEASURED_NOT_CLOSED"
			_write()
			push_error("Formal 5k performance gate failed: " + str(report.formal_5k_performance_gate.failures))
			done = true
			lab.queue_free()
			quit(1)
			return
	_write()
	print("FPS%d_MEASURED fps=" % (per_team * 2), report.fps, " p95_ms=", report.p95_ms, " output=", out)
	done = true
	for viewport: Viewport in viewport_probe:
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), false)
	viewport_probe.clear()
	lab.queue_free()
	await process_frame
	quit(0)

func _terrain_submission_probe() -> void:
	# Frozen actual main only: visibility ablation is a diagnostic, NEVER FPS.
	var original_paused := paused
	paused = true
	var state := _render_owner_bytes()
	var clock_before := _clock()
	var terrain_before := lab.terrain.fingerprint()
	var original_visibility: Array[bool] = []
	for layer: Node2D in lab.renderer.layers: original_visibility.append(layer.visible)
	var rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	report["terrain_submission_probe"] = []
	report["status"] = "DIAGNOSTIC_ONLY"
	report["fps_definition"] = "No gameplay FPS: frozen original scene with temporary terrain-layer visibility ablation."
	var first: Image
	for excluded in [-2, -1, -2, 0, -2, 1, -2, 2, -2, 3, -2]:
		for index in range(lab.renderer.layers.size()):
			lab.renderer.layers[index].visible = original_visibility[index] and excluded != -1 and excluded != index
		# Allow delayed render counters / GPU timestamps to settle after changes.
		for frame in range(8):
			await process_frame
			await RenderingServer.frame_post_draw
		var sample := {"excluded": "none" if excluded == -2 else ("all_terrain" if excluded == -1 else str(lab.renderer.layers[excluded].name)), "cpu_ms": [], "gpu_ms": [], "setup_cpu_ms": [], "draws": [], "total_draws": [], "frame_ms": []}
		var previous := Time.get_ticks_usec()
		for frame in range(64):
			await process_frame
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			sample.frame_ms.append((now - previous) / 1000.0)
			previous = now
			sample.cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
			sample.gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
			sample.setup_cpu_ms.append(RenderingServer.get_frame_setup_time_cpu())
			sample.draws.append(RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
			# Some backends report zero for root 2D viewport draws; retain that raw
			# value but also record the same global monitor used by the FPS test.
			sample.total_draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		report.terrain_submission_probe.append(sample)
		if first == null:
			first = root.get_texture().get_image()
			assert(first.save_png(out + "/diagnostic_full_before.png") == OK)
		assert(state == _render_owner_bytes() and clock_before == _clock() and terrain_before == lab.terrain.fingerprint())
	var restored := root.get_texture().get_image()
	assert(first.get_data() == restored.get_data(), "Full picture changed after terrain diagnostic")
	assert(restored.save_png(out + "/diagnostic_full_after.png") == OK)
	report["terrain_probe_restored_exact_rgba"] = true
	report["terrain_probe_owner_clock_terrain_unchanged"] = true
	RenderingServer.viewport_set_measure_render_time(rid, false)
	paused = original_paused
	_write()
	print("TERRAIN_SUBMISSION_DIAGNOSTIC_PASS original 5000-person scene; full picture/state restored; NOT gameplay FPS output=", out)
	done = true
	lab.queue_free()
	await process_frame
	quit(0)

func _verify_resource_pair() -> void:
	paused = true
	var before := _render_owner_bytes()
	var terrain_before := lab.terrain.fingerprint()
	var clock_before := _clock()
	var view: SiteResourceView = lab.site_controller.view
	var state := {}
	# Keep the actual row nodes and their painter order. Replacing only the
	# parent script avoids hot-reloading the nested ResourceRow class.
	for property: String in ["data", "view_mode", "resource_filter", "selection", "selection_valid", "preview_entrance", "selected_resource", "resources_by_row", "features_by_row", "loot_cells_by_row", "rows", "heat", "animation_time", "_animation_elapsed", "_seen_revision"]:
		state[property] = view.get(property)
	var original_zoom := lab.camera.zoom
	var original_position := lab.camera.position
	if "--resource-animated" in OS.get_cmdline_user_args(): state["animation_time"] = 3.7
	report["resource_animation_time"] = state.animation_time
	var original_script: Script = view.get_script()
	var reference_script := preload("res://scripts/tests/fixtures/site_resource_view_phase25.gd")
	report["status"] = "VISUAL_CONTRACT_ONLY"
	report["fps_definition"] = "Frozen original main resource RGBA parity; not gameplay FPS."
	report["resource_parity"] = []
	for zoom: Vector2 in [original_zoom, Vector2.ONE * 0.375, Vector2.ONE]:
		for mode: int in [0, 1]:
			lab.camera.zoom = zoom
			lab.camera.position = original_position + (Vector2.ZERO if zoom == original_zoom else Vector2(0.37, 0.61))
			lab.camera.force_update_scroll()
			var pictures: Array[Image] = []
			var draws := []
			var reference_calls := 0
			for selected: Script in [reference_script, original_script]:
				view.set_script(selected)
				for property: String in state: view.set(property, state[property])
				view.view_mode = mode
				view.set_meta(&"reference_oval_calls", 0)
				view.refresh()
				for frame in range(3):
					await process_frame
					await RenderingServer.frame_post_draw
				pictures.append(root.get_texture().get_image())
				draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
				if selected == reference_script: reference_calls = int(view.get_meta(&"reference_oval_calls", 0))
			var label := "resources_%d" % report.resource_parity.size()
			var equal := pictures[0].get_data() == pictures[1].get_data()
			var unchanged := before == _render_owner_bytes() and terrain_before == lab.terrain.fingerprint() and clock_before == _clock()
			report.resource_parity.append({"zoom": str(zoom), "mode": mode, "exact_full_rgba": equal, "owner_clock_terrain_unchanged": unchanged, "draws": draws, "reference_ovals": reference_calls, "resource_rows": view.rows.size()})
			assert(pictures[0].save_png(out + "/" + label + "_reference.png") == OK)
			assert(pictures[1].save_png(out + "/" + label + "_candidate.png") == OK)
			if not equal or not unchanged or reference_calls <= 0:
				_fail("Original main resource parity or reference coverage failed: " + label)
				return
	lab.camera.zoom = original_zoom
	lab.camera.position = original_position
	lab.camera.force_update_scroll()
	_write()
	print("RESOURCE_MAIN_PARITY_PASS 6 exact full RGBA pairs, original resources/owner/clock/terrain unchanged output=", out)
	done = true
	lab.queue_free()
	await process_frame
	quit(0)

func _verify_terrain_pair() -> void:
	# The same frozen original main scene, not a replacement FPS scene.
	paused = true
	var before := _render_owner_bytes()
	var terrain_before := lab.terrain.fingerprint()
	var clock_before := _clock()
	var camera_zoom := lab.camera.zoom
	var camera_position := lab.camera.position
	var debug_before := lab.renderer.debug_enabled
	var script := load(TERRAIN_RENDERER) as GDScript
	var candidate := script.source_code
	var reference := FileAccess.get_file_as_string(PHASE24_TERRAIN)
	report["status"] = "VISUAL_CONTRACT_ONLY"
	report["fps_definition"] = "Frozen original main terrain RGBA parity; not gameplay FPS."
	report["terrain_parity"] = []
	for zoom: Vector2 in [camera_zoom, Vector2.ONE * 0.375, Vector2.ONE]:
		for debug: bool in [false, true]:
			lab.camera.zoom = zoom
			lab.camera.position = camera_position + (Vector2.ZERO if zoom == camera_zoom else Vector2(0.37, 0.61))
			lab.camera.force_update_scroll()
			lab.renderer.debug_enabled = debug
			var images: Array[Image] = []
			var draws := []
			var label := "terrain_%d" % report.terrain_parity.size()
			for source: String in [reference, candidate]:
				script.source_code = source
				assert(script.reload(true) == OK)
				lab.renderer.redraw()
				for frame in range(3):
					await process_frame
					await RenderingServer.frame_post_draw
				images.append(root.get_texture().get_image())
				draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			var equal := images[0].get_data() == images[1].get_data()
			var unchanged := before == _render_owner_bytes() and terrain_before == lab.terrain.fingerprint() and clock_before == _clock()
			report.terrain_parity.append({"zoom": str(zoom), "debug": debug, "exact_full_rgba": equal, "owner_clock_terrain_unchanged": unchanged, "draws_reference_candidate": draws})
			assert(images[0].save_png(out + "/" + label + "_reference.png") == OK)
			assert(images[1].save_png(out + "/" + label + "_candidate.png") == OK)
			if not equal or not unchanged:
				_fail("Original main terrain parity failed: " + label)
				return
	lab.camera.zoom = camera_zoom
	lab.camera.position = camera_position
	lab.camera.force_update_scroll()
	lab.renderer.debug_enabled = debug_before
	lab.renderer.redraw()
	_write()
	print("TERRAIN_MAIN_PARITY_PASS 6 exact full RGBA pairs, original owner/clock/terrain unchanged output=", out)
	done = true
	lab.queue_free()
	await process_frame
	quit(0)
