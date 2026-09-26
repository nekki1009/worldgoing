extends "res://scripts/tests/site_army_oracle_calibration_test.gd"
## Exact, process-isolated frozen-A / candidate-B logical comparison.

const Gate = preload("res://scripts/tests/fixtures/site_army_mechanism_gate.gd")
const ROOT := "res://output/site_army_5k_hot_close_20260926/"
const SNAPSHOTS := 1801 # Initial state plus 1,800 30 Hz action steps.
const REFERENCE := ROOT + "frozen_A_logical.bin"
const REFERENCE_REPORT := ROOT + "frozen_A_logical.json"
const CANDIDATE_REPORT := ROOT + "candidate_B_logical.json"
const BUDGET_REPORT := ROOT + "oracle_budget.json"
const SEGMENT_BUDGET_REPORT := ROOT + "oracle_segment_budget.json"
const SEGMENT_BOUNDS := [[0, 600], [601, 1200], [1201, 1800]]
const CHECKPOINT_TICKS := [0, 600, 1200, 1800]
const PRODUCT_PATHS := {"army": "res://scripts/terrain_lab/terrain_army.gd",
	"lab": "res://scripts/terrain_lab/terrain_lab.gd",
	"batch": "res://scripts/terrain_lab/terrain_army_batch_view.gd",
	"controller": "res://scripts/terrain_lab/site_controller.gd",
	"person_actions": "res://scripts/terrain_lab/site_person_actions.gd",
	"work_team": "res://scripts/terrain_lab/site_work_team.gd",
	"test_character": "res://scripts/terrain_lab/terrain_test_character.gd",
	"vehicle_transport": "res://scripts/terrain_lab/site_vehicle_transport.gd",
	"family_continuity": "res://scripts/terrain_lab/site_family_continuity.gd",
	"sustain": "res://scripts/terrain_lab/site_sustain.gd",
	"food_delivery": "res://scripts/terrain_lab/site_food_delivery.gd",
	"captivity_supply": "res://scripts/terrain_lab/site_captivity_supply.gd",
	"captive_escort": "res://scripts/terrain_lab/site_captive_escort.gd",
	"native_cpp": "res://native/army_idle/army_idle.cpp",
	"native_dll": "res://native/army_idle/bin/army_idle.windows.x86_64.dll"}
const FROZEN_FILES := {"army": "terrain_army.gd.txt", "lab": "terrain_lab.gd.txt",
	"batch": "terrain_army_batch_view.gd.txt", "controller": "site_controller.gd.txt",
	"person_actions": "site_person_actions.gd.txt", "work_team": "site_work_team.gd.txt",
	"test_character": "terrain_test_character.gd.txt", "vehicle_transport": "site_vehicle_transport.gd.txt",
	"family_continuity": "site_family_continuity.gd.txt", "sustain": "site_sustain.gd.txt",
	"food_delivery": "site_food_delivery.gd.txt", "captivity_supply": "site_captivity_supply.gd.txt",
	"captive_escort": "site_captive_escort.gd.txt",
	"native_cpp": "army_idle.cpp", "native_dll": "army_idle.windows.x86_64.dll"}


func _initialize() -> void:
	_run_stream.call_deferred()


func _run_stream() -> void:
	var role := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--oracle-role="):
			role = argument.trim_prefix("--oracle-role=")
	if role == "selfcheck":
		_selfcheck()
		return
	if role == "merge":
		_merge_segments()
		return
	if role not in ["budget", "segment-budget", "A", "B0", "B1", "B2"]:
		push_error("Expected --oracle-role=selfcheck|budget|segment-budget|A|B0|B1|B2|merge")
		quit(1)
		return
	var is_segment: bool = role.begins_with("B")
	var segment_index := int(role.trim_prefix("B")) if is_segment else -1
	var segment_first := int(SEGMENT_BOUNDS[segment_index][0]) if is_segment else -1
	var segment_last := int(SEGMENT_BOUNDS[segment_index][1]) if is_segment else -1
	var start_usec := Time.get_ticks_usec()
	var deadline := start_usec + 600000000
	var source_hashes := {}
	for label: String in PRODUCT_PATHS:
		source_hashes[label] = FileAccess.get_sha256(PRODUCT_PATHS[label])
	source_hashes["fixture"] = FileAccess.get_sha256("res://scripts/tests/site_army_oracle_stream_test.gd")
	source_hashes["oracle"] = FileAccess.get_sha256("res://scripts/tests/fixtures/site_army_logical_state_oracle.gd")
	var report := {"status": "INCOMPLETE", "role": role,
		"scene": MAIN, "preset": "PLAINS", "seed": 581, "per_team": PER_TEAM,
		"teams": 2, "steps": SNAPSHOTS - 1, "step_seconds": STEP,
		"engine": Engine.get_version_info(), "first_unfinished_tick": 0,
		"source_sha256": source_hashes,
		"samples": [], "snapshot_assembly_usec": 0, "unsupported_scan_usec": 0,
		"inventory_usec": 0, "inventories": [],
		"serialize_usec": 0, "compress_usec": 0, "decompress_usec": 0,
		"deserialize_usec": 0,
		"compare_usec": 0, "process_usec": 0, "process_steps": 0,
		"bytes_uncompressed": 0, "bytes_stored": 0, "snapshots_checked": 0,
		"materialized_ticks": 0, "hot_active_checked_ticks": 0,
		"reference_frames_traversed": 0,
		"checkpoint_ticks": [], "checkpoint_checked": 0,
		"hot_stats": [], "snapshot_encoding": "original_dictionary_order",
		"A_unsupported_validation_deferred_to_B": role == "A",
		"segment_first": 0 if role == "segment-budget" else segment_first,
		"segment_last": 600 if role == "segment-budget" else segment_last}
	var report_path := BUDGET_REPORT if role == "budget" else (SEGMENT_BUDGET_REPORT if role == "segment-budget" else (REFERENCE_REPORT if role == "A" else _segment_path(segment_index)))
	var source_capture: Dictionary = Gate.capture_source_manifest()
	report["source_manifest"] = source_capture.hashes
	report["source_manifest_errors"] = source_capture.errors
	if not source_capture.errors.is_empty():
		_finish_stream(report, report_path, "source_manifest_incomplete", 1)
		return
	if str(ProjectSettings.get_setting("application/run/main_scene")) != MAIN:
		_finish_stream(report, report_path, "wrong_main_scene", 1)
		return
	# Keep the formal harness's deployment-only in-memory limit, without
	# changing production roster admission or the on-disk source fingerprint.
	if TerrainArmy.MAX_ROSTER_SIZE < PER_TEAM:
		var army_script := load("res://scripts/terrain_lab/terrain_army.gd") as GDScript
		var guard := "selected.size() > MAX_ROSTER_SIZE"
		if army_script.source_code.count(guard) != 1:
			_finish_stream(report, report_path, "deployment_guard_drifted", 1)
			return
		army_script.source_code = army_script.source_code.replace(guard, "selected.size() > %d" % PER_TEAM)
		if army_script.reload(true) != OK:
			_finish_stream(report, report_path, "deployment_override_reload_failed", 1)
			return
		report["deployment_only_memory_override"] = guard + " -> selected.size() > %d" % PER_TEAM
		report["army_runtime_sha256"] = army_script.source_code.sha256_text()
	var reference_report: Variant = null
	var stream: FileAccess = null
	if is_segment:
		reference_report = JSON.parse_string(FileAccess.get_file_as_string(REFERENCE_REPORT)) if FileAccess.file_exists(REFERENCE_REPORT) else null
		if not reference_report is Dictionary or reference_report.get("status") != "PASS" or reference_report.get("snapshots_checked") != SNAPSHOTS or reference_report.get("scene") != MAIN or reference_report.get("per_team") != PER_TEAM:
			_finish_stream(report, report_path, "frozen_A_reference_missing_or_incomplete", 1)
			return
		for label: String in FROZEN_FILES:
			var frozen_hash := FileAccess.get_sha256(ROOT + "frozen_A/" + str(FROZEN_FILES[label]))
			if frozen_hash.length() != 64 or reference_report.get("source_sha256", {}).get(label, "") != frozen_hash:
				_finish_stream(report, report_path, "frozen_A_source_mismatch:" + label, 1)
				return
		report["reference_binary_sha256"] = FileAccess.get_sha256(REFERENCE)
		if str(report.reference_binary_sha256).length() != 64 or report.reference_binary_sha256 != reference_report.get("binary_sha256", ""):
			_finish_stream(report, report_path, "frozen_A_binary_changed", 1)
			return
		var allowed_differences := {}
		for label: String in PRODUCT_PATHS: allowed_differences[PRODUCT_PATHS[label]] = true
		var original_manifest: Variant = reference_report.get("source_manifest", {})
		if not original_manifest is Dictionary or original_manifest.size() != source_capture.hashes.size():
			_finish_stream(report, report_path, "frozen_A_manifest_missing", 1)
			return
		for path: String in source_capture.hashes:
			if not allowed_differences.has(path) and original_manifest.get(path, "") != source_capture.hashes[path]:
				_finish_stream(report, report_path, "unreviewed_A_B_source_difference:" + path, 1)
				return
		stream = FileAccess.open(REFERENCE, FileAccess.READ)
		if stream == null or stream.get_buffer(4).get_string_from_ascii() != "SAO2":
			_finish_stream(report, report_path, "frozen_A_binary_missing_or_invalid", 1)
			return
	elif role == "A":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
		stream = FileAccess.open(REFERENCE, FileAccess.WRITE)
		if stream == null:
			_finish_stream(report, report_path, "frozen_A_binary_open_failed", 1)
			return
		stream.store_buffer("SAO2".to_ascii_buffer())
	var lab: TerrainLab = _formal_scene()
	if lab == null:
		_finish_stream(report, report_path, "scene_setup:" + _setup_error, 1)
		return
	if is_segment:
		for side in range(2):
			var team: TerrainArmy = lab.combat_armies[side]
			team.set("combat_hot_diagnostics_enabled", true)
			if team.has_method("combat_hot_reset_stats"): team.call("combat_hot_reset_stats")
	var oracle_kernel: RefCounted = null
	if role != "A":
		oracle_kernel = TerrainArmy._get_idle_kernel()
		if oracle_kernel == null or not oracle_kernel.has_method("exact_value_equal") \
				or not oracle_kernel.has_method("contains_unsupported"):
			lab.free()
			_finish_stream(report, report_path, "native_exact_oracle_unavailable", 1)
			return
		report["native_exact_checks_both_values"] = true
	var events: Array = []
	_attach_events(lab, events)
	if is_segment and not _hot_active(lab):
		lab.free()
		_finish_stream(report, report_path, "candidate_hot_inactive_at_start", 1)
		return
	for tick in SNAPSHOTS:
		if Time.get_ticks_usec() > deadline:
			report.first_unfinished_tick = tick
			break
		if tick > 0:
			var process_begin := Time.get_ticks_usec()
			lab._process(STEP)
			report.process_usec += Time.get_ticks_usec() - process_begin
			report.process_steps += 1
		if is_segment and not _hot_active(lab):
			report["first_inactive_tick"] = tick
			break
		if is_segment: report.hot_active_checked_ticks += 1
		if is_segment and tick in [0, 600, 1200, 1800]:
			var team_stats: Array = []
			for side in range(2):
				var team: TerrainArmy = lab.combat_armies[side]
				team_stats.append(team.call("combat_hot_stats") if team.has_method("combat_hot_stats") else {})
			report.hot_stats.append({"tick": tick, "teams": team_stats})
		if role == "budget" and tick not in [0, 600, 1200, 1800]:
			events.clear()
			report.first_unfinished_tick = tick + 1
			continue
		var begun := Time.get_ticks_usec()
		var snapshot := _snapshot(lab, events)
		report.snapshot_assembly_usec += Time.get_ticks_usec() - begun
		report.materialized_ticks += 1
		if role == "segment-budget" and tick > 600:
			report.first_unfinished_tick = tick + 1
			events.clear()
			continue
		if role == "budget":
			begun = Time.get_ticks_usec()
			var inventory := _inventory_snapshot(snapshot)
			report.inventory_usec += Time.get_ticks_usec() - begun
			report.inventories.append({"tick": tick, "counts": inventory})
		if role == "budget":
			begun = Time.get_ticks_usec()
			var unsupported: bool = bool(oracle_kernel.call("contains_unsupported", snapshot))
			report.unsupported_scan_usec += Time.get_ticks_usec() - begun
			if unsupported:
				report["unsupported_tick"] = tick
				break
		var bytes := PackedByteArray()
		if not is_segment:
			begun = Time.get_ticks_usec()
			bytes = var_to_bytes(snapshot)
			report.serialize_usec += Time.get_ticks_usec() - begun
			if bytes.is_empty():
				report["empty_serialization_tick"] = tick
				break
		var packed := PackedByteArray()
		if not is_segment:
			begun = Time.get_ticks_usec()
			packed = bytes.compress()
			report.compress_usec += Time.get_ticks_usec() - begun
			if packed.is_empty():
				report["compression_failure_tick"] = tick
				break
		var recorded_packed_size := 0
		var recorded_original_size := bytes.size()
		if role == "A":
			stream.store_32(bytes.size())
			stream.store_32(packed.size())
			stream.store_buffer(packed)
		elif is_segment:
			var compare_tick: bool = (tick >= segment_first and tick <= segment_last) \
				or tick in CHECKPOINT_TICKS
			var reference_frame := _read_reference_frame(stream, compare_tick)
			if reference_frame.get("ok") != true:
				report["corrupt_reference_tick"] = tick
				break
			recorded_packed_size = int(reference_frame.packed_size)
			recorded_original_size = int(reference_frame.original_size)
			report.reference_frames_traversed += 1
			if not compare_tick:
				report.first_unfinished_tick = tick + 1
				events.clear()
				continue
			report.decompress_usec += int(reference_frame.decompress_usec)
			report.deserialize_usec += int(reference_frame.deserialize_usec)
			var original: Array = reference_frame.value
			begun = Time.get_ticks_usec()
			var exact: int = int(oracle_kernel.call("exact_value_equal", original, snapshot))
			report.compare_usec += Time.get_ticks_usec() - begun
			if exact != 1:
				if exact == 0:
					var mismatch: String = Oracle.first_mismatch(original, snapshot)
					report["first_mismatch"] = mismatch if not mismatch.is_empty() else \
						"native unequal without a field-localized mismatch"
				else:
					report["first_mismatch"] = "native exact comparator rejected unsupported/error"
				report["first_mismatch_tick"] = tick
				report["native_exact_result"] = exact
				report["reference_bytes_at_mismatch"] = recorded_original_size
				break
			if tick in CHECKPOINT_TICKS:
				report.checkpoint_ticks.append(tick)
				report.checkpoint_checked += 1
		elif role == "budget" or role == "segment-budget":
			begun = Time.get_ticks_usec()
			var roundtrip: PackedByteArray = packed.decompress(bytes.size())
			report.decompress_usec += Time.get_ticks_usec() - begun
			if roundtrip != bytes:
				report["roundtrip_mismatch_tick"] = tick
				break
			begun = Time.get_ticks_usec()
			var decoded: Variant = bytes_to_var(roundtrip)
			report.deserialize_usec += Time.get_ticks_usec() - begun
			begun = Time.get_ticks_usec()
			var same: int = int(oracle_kernel.call("exact_value_equal", decoded, snapshot))
			report.compare_usec += Time.get_ticks_usec() - begun
			if same != 1:
				report["native_roundtrip_result"] = same
				report["native_roundtrip_mismatch_tick"] = tick
				break
		if not is_segment or tick >= segment_first and tick <= segment_last:
			report.snapshots_checked += 1
		report.bytes_uncompressed += recorded_original_size
		report.bytes_stored += packed.size() if not is_segment else recorded_packed_size
		if role == "budget" or role == "segment-budget" and tick in [0, 600]:
			report.samples.append({"tick": tick, "uncompressed_bytes": recorded_original_size,
				"stored_bytes": packed.size(), "snapshot_usec": report.snapshot_assembly_usec,
				"inventory_usec": report.inventory_usec,
				"unsupported_usec": report.unsupported_scan_usec,
				"serialize_usec": report.serialize_usec, "compress_usec": report.compress_usec,
				"decompress_usec": report.decompress_usec, "deserialize_usec": report.deserialize_usec,
				"compare_usec": report.compare_usec})
		report.first_unfinished_tick = tick + 1
		events.clear()
	var expected_checks := segment_last - segment_first + 1 if is_segment else (601 if role == "segment-budget" else SNAPSHOTS)
	var complete := int(report.first_unfinished_tick) == SNAPSHOTS and (role == "budget" or int(report.snapshots_checked) == expected_checks)
	if role == "segment-budget" and (int(report.materialized_ticks) != SNAPSHOTS \
			or int(report.process_steps) != SNAPSHOTS - 1):
		complete = false
	if is_segment and (int(report.materialized_ticks) != SNAPSHOTS \
			or int(report.hot_active_checked_ticks) != SNAPSHOTS \
			or int(report.reference_frames_traversed) != SNAPSHOTS \
			or int(report.process_steps) != SNAPSHOTS - 1 \
			or int(report.checkpoint_checked) != CHECKPOINT_TICKS.size() \
			or report.checkpoint_ticks != CHECKPOINT_TICKS):
		complete = false
	if role == "A" and complete and stream.get_error() != OK:
		report["stream_error"] = stream.get_error()
		complete = false
	if is_segment and complete:
		complete = stream.get_position() == stream.get_length()
		if not complete: report["trailing_reference_bytes"] = stream.get_length() - stream.get_position()
	var source_changed: Array[String] = []
	for label: String in PRODUCT_PATHS:
		if FileAccess.get_sha256(PRODUCT_PATHS[label]) != source_hashes[label]:
			source_changed.append(label)
	if FileAccess.get_sha256("res://scripts/tests/site_army_oracle_stream_test.gd") != source_hashes.fixture or FileAccess.get_sha256("res://scripts/tests/fixtures/site_army_logical_state_oracle.gd") != source_hashes.oracle:
		source_changed.append("oracle_fixture")
	for path: String in source_capture.hashes:
		if FileAccess.get_sha256(path) != source_capture.hashes[path]:
			source_changed.append(path)
	if not source_changed.is_empty():
		report["source_changed_during_run"] = source_changed
		complete = false
	if stream != null: stream.close()
	if role == "A" and complete:
		report["binary_sha256"] = FileAccess.get_sha256(REFERENCE)
		complete = str(report.binary_sha256).length() == 64
	if is_segment and complete:
		complete = FileAccess.get_sha256(REFERENCE) == report.reference_binary_sha256
		if not complete: report["reference_binary_changed_during_run"] = true
	lab.free()
	report["elapsed_usec"] = Time.get_ticks_usec() - start_usec
	_finish_stream(report, report_path, "PASS" if complete else "incomplete_or_mismatch", 0 if complete else 1)


func _read_reference_frame(stream: FileAccess, decode: bool) -> Dictionary:
	if stream == null or stream.get_length() - stream.get_position() < 8:
		return {"ok": false}
	var original_size := stream.get_32()
	var packed_size := stream.get_32()
	if original_size <= 0 or original_size > 100000000 or packed_size <= 0 or packed_size > 100000000 \
			or stream.get_error() != OK or stream.get_position() + packed_size > stream.get_length():
		return {"ok": false}
	if not decode:
		var end_position := stream.get_position() + packed_size
		stream.seek(end_position)
		return {"ok": stream.get_position() == end_position,
			"original_size": original_size, "packed_size": packed_size}
	var begun := Time.get_ticks_usec()
	var raw: PackedByteArray = stream.get_buffer(packed_size).decompress(original_size)
	var decompress_usec := Time.get_ticks_usec() - begun
	if raw.size() != original_size:
		return {"ok": false}
	begun = Time.get_ticks_usec()
	var restored: Variant = bytes_to_var(raw)
	var deserialize_usec := Time.get_ticks_usec() - begun
	if not restored is Array:
		return {"ok": false}
	return {"ok": true, "original_size": original_size, "packed_size": packed_size,
		"value": restored, "decompress_usec": decompress_usec,
		"deserialize_usec": deserialize_usec}


func _segment_path(index: int) -> String:
	return ROOT + "candidate_B_segment_%d.json" % index


func _merge_segments() -> void:
	var started := Time.get_ticks_usec()
	var serialized_step: Variant = JSON.parse_string(JSON.stringify(STEP))
	var capture: Dictionary = Gate.capture_source_manifest()
	var report := {"role": "B", "status": "INCOMPLETE", "scene": MAIN,
		"preset": "PLAINS", "seed": 581, "per_team": PER_TEAM,
		"teams": 2, "steps": SNAPSHOTS - 1, "step_seconds": STEP,
		"engine": Engine.get_version_info(), "source_manifest": capture.hashes,
		"source_manifest_errors": capture.errors, "source_sha256": {},
		"snapshot_encoding": "original_dictionary_order",
		"native_exact_checks_both_values": true,
		"snapshots_checked": 0, "first_unfinished_tick": 0,
		"hot_stats": [], "segments": [], "segment_sha256": {},
		"process_usec": 0, "total_process_usec": 0,
		"validation_elapsed_usec": 0, "elapsed_usec": 0}
	var failure := ""
	if not capture.errors.is_empty(): failure = "source_manifest_incomplete"
	var reference: Variant = _read_json(REFERENCE_REPORT)
	if failure.is_empty() and (not reference is Dictionary or reference.get("status") != "PASS" \
			or reference.get("role") != "A" or reference.get("snapshots_checked") != SNAPSHOTS \
			or reference.get("scene") != MAIN or reference.get("preset") != "PLAINS" \
			or reference.get("seed") != 581 or reference.get("per_team") != PER_TEAM \
			or reference.get("teams") != 2 or reference.get("steps") != SNAPSHOTS - 1 \
			or reference.get("step_seconds") != serialized_step \
			or reference.get("engine") != Engine.get_version_info() \
			or not reference.get("source_sha256") is Dictionary \
			or reference.get("first_unfinished_tick") != SNAPSHOTS \
			or reference.get("materialized_ticks") != SNAPSHOTS \
			or reference.get("process_steps") != SNAPSHOTS - 1 \
			or reference.get("snapshot_encoding") != "original_dictionary_order" \
			or reference.get("A_unsupported_validation_deferred_to_B") != true):
		failure = "frozen_A_report_missing_or_incomplete"
	var binary_sha := FileAccess.get_sha256(REFERENCE)
	if failure.is_empty() and (binary_sha.length() != 64 or binary_sha != reference.get("binary_sha256", "")):
		failure = "frozen_A_binary_changed"
	var allowed_differences := {}
	for label: String in PRODUCT_PATHS:
		allowed_differences[PRODUCT_PATHS[label]] = true
	if failure.is_empty():
		var original_manifest: Variant = reference.get("source_manifest")
		if not original_manifest is Dictionary or original_manifest.size() != capture.hashes.size():
			failure = "frozen_A_manifest_missing"
		else:
			for path: String in capture.hashes:
				if not allowed_differences.has(path) and original_manifest.get(path, "") != capture.hashes[path]:
					failure = "unreviewed_A_B_source_difference:" + path
					break
	if failure.is_empty():
		for label: String in FROZEN_FILES:
			var path: String = PRODUCT_PATHS[label]
			if reference.get("source_sha256", {}).get(label) != FileAccess.get_sha256(ROOT + "frozen_A/" + str(FROZEN_FILES[label])) \
					or reference.source_manifest.get(path) != reference.source_sha256.get(label):
				failure = "frozen_A_product_mismatch:" + label
				break
	var summed_usec := 0
	var summed_process_usec := 0
	var candidate_source: Dictionary = {}
	for index in SEGMENT_BOUNDS.size():
		if not failure.is_empty(): break
		var path := _segment_path(index)
		var segment: Variant = _read_json(path)
		var bounds: Array = SEGMENT_BOUNDS[index]
		if not segment is Dictionary or segment.get("status") != "PASS" \
				or segment.get("role") != "B%d" % index \
				or segment.get("scene") != MAIN or segment.get("preset") != "PLAINS" \
				or segment.get("seed") != 581 or segment.get("per_team") != PER_TEAM \
				or segment.get("teams") != 2 or segment.get("steps") != SNAPSHOTS - 1 \
				or segment.get("step_seconds") != serialized_step \
				or segment.get("segment_first") != bounds[0] or segment.get("segment_last") != bounds[1] \
				or segment.get("snapshots_checked") != int(bounds[1]) - int(bounds[0]) + 1 \
				or segment.get("first_unfinished_tick") != SNAPSHOTS \
				or segment.get("materialized_ticks") != SNAPSHOTS \
				or segment.get("hot_active_checked_ticks") != SNAPSHOTS \
				or segment.get("reference_frames_traversed") != SNAPSHOTS \
				or segment.get("process_steps") != SNAPSHOTS - 1 \
				or segment.get("checkpoint_checked") != CHECKPOINT_TICKS.size() \
				or segment.get("checkpoint_ticks") != CHECKPOINT_TICKS \
				or segment.get("snapshot_encoding") != "original_dictionary_order" \
				or segment.get("native_exact_checks_both_values") != true \
				or segment.get("source_manifest") != capture.hashes \
				or segment.get("engine") != Engine.get_version_info() \
				or segment.get("reference_binary_sha256") != binary_sha \
				or segment.has("first_mismatch_tick") or segment.has("native_exact_result") \
				or segment.has("first_inactive_tick") or segment.has("source_changed_during_run") \
				or not segment.get("hot_stats") is Array or segment.hot_stats.size() != 4 \
				or not segment.get("source_sha256") is Dictionary:
			failure = "candidate_segment_invalid:%d" % index
			break
		if index == 0:
			candidate_source = segment.source_sha256
		elif segment.source_sha256 != candidate_source:
			failure = "candidate_segment_source_changed:%d" % index
			break
		var digest := FileAccess.get_sha256(path)
		if digest.length() != 64:
			failure = "candidate_segment_missing:%d" % index
			break
		report.segment_sha256[path.get_file()] = digest
		report.segments.append({"path": path, "sha256": digest,
			"first": bounds[0], "last": bounds[1],
			"snapshots_checked": segment.snapshots_checked,
			"elapsed_usec": segment.elapsed_usec, "process_usec": segment.process_usec})
		report.snapshots_checked += int(segment.snapshots_checked)
		summed_usec += int(segment.get("elapsed_usec", 0))
		summed_process_usec += int(segment.get("process_usec", 0))
		if index == SEGMENT_BOUNDS.size() - 1:
			report.hot_stats = segment.hot_stats
			report.process_usec = segment.process_usec
	if failure.is_empty() and int(report.snapshots_checked) != SNAPSHOTS:
		failure = "candidate_segment_coverage_incomplete"
	if failure.is_empty():
		for label: String in PRODUCT_PATHS:
			var path: String = PRODUCT_PATHS[label]
			if candidate_source.get(label) != FileAccess.get_sha256(path) \
					or capture.hashes.get(path) != candidate_source.get(label):
				failure = "candidate_product_changed:" + label
				break
	if failure.is_empty() and (candidate_source.get("fixture") != FileAccess.get_sha256("res://scripts/tests/site_army_oracle_stream_test.gd") \
			or candidate_source.get("oracle") != FileAccess.get_sha256("res://scripts/tests/fixtures/site_army_logical_state_oracle.gd")):
		failure = "candidate_oracle_fixture_changed"
	if failure.is_empty() and Gate.capture_source_manifest() != capture:
		failure = "source_changed_during_merge"
	report.source_sha256 = candidate_source
	report.reference_binary_sha256 = binary_sha
	report.total_process_usec = summed_process_usec
	report.validation_elapsed_usec = summed_usec
	report.first_unfinished_tick = SNAPSHOTS if failure.is_empty() else 0
	report.elapsed_usec = Time.get_ticks_usec() - started
	if not failure.is_empty(): report["failure"] = failure
	_finish_stream(report, CANDIDATE_REPORT, "PASS" if failure.is_empty() else failure,
		0 if failure.is_empty() else 1)


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path): return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _snapshot(lab: TerrainLab, events: Array) -> Array:
	var all_units: Array = []
	for team: TerrainArmy in lab.combat_armies:
		all_units.append(team.call("materialized_combat_rows") if team.has_method("materialized_combat_rows") else team.combat_units)
	return [all_units, _aux(lab), events]


func _hot_active(lab: TerrainLab) -> bool:
	for side in range(2):
		var team: TerrainArmy = lab.combat_armies[side]
		if not team.has_method("combat_hot_active") or not bool(team.call("combat_hot_active")):
			return false
	return true


func _finish_stream(report: Dictionary, path: String, status: String, code: int) -> void:
	report.status = status
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write oracle report")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	if code != 0: push_error("SITE_ARMY_ORACLE_STREAM_FAIL " + status + " output=" + path)
	else: print("SITE_ARMY_ORACLE_STREAM_PASS role=", report.role, " output=", path)
	quit(code)


func _selfcheck() -> void:
	var path := ROOT + "oracle_stream_selfcheck.bin"
	var report_path := ROOT + "oracle_stream_selfcheck.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	var writer := FileAccess.open(path, FileAccess.WRITE)
	if writer == null:
		_finish_stream({"role": "selfcheck"}, report_path, "binary_open_failed", 1)
		return
	writer.store_buffer("SAO1".to_ascii_buffer())
	var originals := [
		[[1, {"hp": 0.0, "cell": Vector2i(4, 5)}]],
		[[1, {"hp": 7.125, "cell": Vector2i(4, 6)}]],
	]
	for value: Array in originals:
		var bytes := var_to_bytes(value)
		var packed := bytes.compress()
		writer.store_32(bytes.size())
		writer.store_32(packed.size())
		writer.store_buffer(packed)
	writer.close()
	var reader := FileAccess.open(path, FileAccess.READ)
	if reader == null or reader.get_buffer(4).get_string_from_ascii() != "SAO1":
		_finish_stream({"role": "selfcheck"}, report_path, "header_mismatch", 1)
		return
	for value: Array in originals:
		var length := reader.get_32()
		var stored := reader.get_32()
		var restored: PackedByteArray = reader.get_buffer(stored).decompress(length)
		if restored != var_to_bytes(value) or not Oracle.first_mismatch(bytes_to_var(restored), value).is_empty():
			reader.close()
			_finish_stream({"role": "selfcheck"}, report_path, "roundtrip_mismatch", 1)
			return
	var clean_end := reader.get_position() == reader.get_length()
	reader.close()
	if not clean_end or Oracle.first_mismatch(originals[0], originals[1]).is_empty():
		_finish_stream({"role": "selfcheck"}, report_path, "end_or_divergence_check_failed", 1)
		return
	var order_probe := _materialization_order_probe()
	var canonical_contract := _canonical_contract_probe()
	var unsupported_serialization := _unsupported_serialization_probe()
	var segment_stream := _segment_stream_probe()
	var serialized_step: Variant = JSON.parse_string(JSON.stringify(STEP))
	var report_roundtrip: Variant = JSON.parse_string(JSON.stringify({"step_seconds": STEP}))
	var step_contract := {"report_roundtrip_exact": report_roundtrip is Dictionary
		and report_roundtrip.get("step_seconds") == serialized_step,
		"wrong_step_rejected": JSON.parse_string(JSON.stringify(STEP * 0.5)) != serialized_step}
	var canonical_contract_ok := true
	for check: String in canonical_contract:
		if canonical_contract[check] != true: canonical_contract_ok = false
	var unsupported_safe := true
	for check: String in unsupported_serialization:
		if unsupported_serialization[check] != true: unsupported_safe = false
	if order_probe.get("semantic_equal") != true or order_probe.get("canonical_byte_equal") != true \
			or order_probe.get("error", "") != "" or not canonical_contract_ok or not unsupported_safe \
			or step_contract.get("report_roundtrip_exact") != true or step_contract.get("wrong_step_rejected") != true \
			or segment_stream.get("skip_decode_and_end") != true \
			or segment_stream.get("reject_corrupt_length") != true:
		_finish_stream({"role": "selfcheck", "materialization_order": order_probe,
			"canonical_contract": canonical_contract,
			"unsupported_serialization": unsupported_serialization,
			"step_contract": step_contract,
			"segment_stream": segment_stream},
			report_path, "canonical_order_or_type_failed", 1)
		return
	_finish_stream({"role": "selfcheck", "frames": originals.size(),
		"materialization_order": order_probe,
		"canonical_contract": canonical_contract,
		"unsupported_serialization": unsupported_serialization,
		"step_contract": step_contract,
		"segment_stream": segment_stream,
		"fixture_sha256": FileAccess.get_sha256("res://scripts/tests/site_army_oracle_stream_test.gd")},
		report_path, "PASS", 0)


func _materialization_order_probe() -> Dictionary:
	# Use the actual product admission/materialization path. Dictionary byte order
	# can differ even when the full logical comparator reports exact equality.
	var army := TerrainArmy.new()
	army.set("native_hot_enabled", true)
	var rows: Array[Dictionary] = [
		{"hp": 100.0, "cargo": {"grain": 3}, "ko": 0.0, "age": -0.0, "think": 0.5,
			"stun": 0.0, "grace": 0.0, "pose": "idle", "attack": false,
			"member": true, "captive": false, "departed": false, "present": true},
		{"person_id": 52002, "member": true, "status": "ready", "pose": "walk",
			"hp": 81.25, "ko": 0.0, "age": 0.125, "think": 0.0,
			"stun": 0.0, "grace": 0.0, "attack": false,
			"captive": false, "departed": false, "present": false}]
	var original := rows.duplicate(true)
	army.combat_units = rows
	if not bool(army.call("_try_install_combat_hot_store")):
		army.free()
		return {"error": "hot_admission_failed"}
	var projected: Array = army.call("materialized_combat_rows")
	var started := Time.get_ticks_usec()
	var byte_equal := var_to_bytes(original) == var_to_bytes(projected)
	var byte_compare_usec := Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	var first_mismatch: String = Oracle.first_mismatch(original, projected)
	var full_compare_usec := Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	var canonical_original: Array = _ordered_row_copies(original)
	var canonical_projected: Array = _ordered_row_copies(projected)
	var canonical_copy_usec := Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	var canonical_byte_equal := var_to_bytes(canonical_original) == var_to_bytes(canonical_projected)
	var canonical_compare_usec := Time.get_ticks_usec() - started
	army.free()
	return {"row_count": original.size(), "semantic_equal": first_mismatch.is_empty(),
		"byte_equal": byte_equal, "byte_compare_usec": byte_compare_usec,
		"canonical_byte_equal": canonical_byte_equal,
		"canonical_copy_usec": canonical_copy_usec,
		"canonical_compare_usec": canonical_compare_usec,
		"full_compare_usec": full_compare_usec,
		"first_mismatch": first_mismatch,
		"army_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"),
		"dll_sha256": FileAccess.get_sha256("res://native/army_idle/bin/army_idle.windows.x86_64.dll")}


func _ordered_snapshot_rows_copy(snapshot: Array) -> Array:
	var ordered_snapshot: Array = snapshot.duplicate(false)
	var original_teams: Array = snapshot[0]
	var ordered_teams: Array = original_teams.duplicate(false)
	for side in ordered_teams.size():
		ordered_teams[side] = _ordered_row_copies(original_teams[side])
	ordered_snapshot[0] = ordered_teams
	return ordered_snapshot


func _ordered_row_copies(rows: Array) -> Array:
	var ordered_rows: Array = rows.duplicate(false)
	for index in ordered_rows.size():
		ordered_rows[index] = _ordered_row_copy(rows[index])
	return ordered_rows


func _ordered_row_copy(row: Dictionary) -> Dictionary:
	var ordered: Dictionary = row.duplicate(false)
	var all_string_keys := true
	for key: Variant in row:
		if typeof(key) != TYPE_STRING:
			all_string_keys = false
			break
	if all_string_keys:
		ordered.sort()
		return ordered
	# Godot 4.7 Dictionary.sort() does not canonicalize mixed key types.
	var mixed_order: Dictionary = ordered.duplicate(false)
	mixed_order.clear()
	for pair: Array in Oracle._sorted_keys(ordered):
		mixed_order[pair[1]] = ordered[pair[1]]
	return mixed_order


func _canonical_contract_probe() -> Dictionary:
	var typed: Array[Dictionary] = [{"b": 1, "a": -0.0, "nested": {"z": 1, "x": 2}}, {"present": false}]
	var before: PackedByteArray = var_to_bytes(typed)
	var canonical: Array = _ordered_row_copies(typed)
	var mixed_first := {3: "number", "3": "string"}
	var mixed_second := {"3": "string", 3: "number"}
	var snapshot := [[typed], {"aux": 4}, ["event"]]
	var ordered_snapshot := _ordered_snapshot_rows_copy(snapshot)
	return {
		"source_not_mutated": var_to_bytes(typed) == before,
		"array_type_preserved": canonical.is_typed() == typed.is_typed()
			and canonical.get_typed_builtin() == typed.get_typed_builtin(),
		"array_order_preserved": canonical.size() == 2 and canonical[0].has("a")
			and canonical[1].has("present") and not canonical[0].has("present"),
		"optional_key_preserved": canonical[0].has("b") and not canonical[1].has("b"),
		"signed_zero_bytes_preserved": var_to_bytes(typed[0]["a"]) == var_to_bytes(canonical[0]["a"]),
		"mixed_key_order_canonical": var_to_bytes(_ordered_row_copy(mixed_first))
			== var_to_bytes(_ordered_row_copy(mixed_second)),
		"nested_dictionary_preserved": is_same(canonical[0]["nested"], typed[0]["nested"]),
		"nonrow_snapshot_preserved": is_same(ordered_snapshot[1], snapshot[1])
			and is_same(ordered_snapshot[2], snapshot[2])}


func _unsupported_serialization_probe() -> Dictionary:
	var kernel: RefCounted = TerrainArmy._get_idle_kernel()
	if kernel == null or not kernel.has_method("exact_value_equal"):
		return {"object": false, "callable": false, "signal": false}
	var cases := {"object": RefCounted.new(), "callable": Callable(self, "_selfcheck"),
		"signal": self.process_frame}
	var result := {}
	for name: String in cases:
		var original: Variant = cases[name]
		var serialized: PackedByteArray = var_to_bytes(original)
		var decoded: Variant = bytes_to_var(serialized) if not serialized.is_empty() else null
		result[name] = not serialized.is_empty() and typeof(decoded) == typeof(original) \
			and int(kernel.call("exact_value_equal", decoded, original)) == -1
	return result


func _segment_stream_probe() -> Dictionary:
	var path := ROOT + "oracle_segment_probe.bin"
	var values := [[["tick", 0]], [["tick", 1]], [["tick", 2]], [["tick", 3]]]
	var writer := FileAccess.open(path, FileAccess.WRITE)
	if writer == null: return {"skip_decode_and_end": false, "reject_corrupt_length": false}
	writer.store_buffer("SAO2".to_ascii_buffer())
	for value: Array in values:
		var raw := var_to_bytes(value)
		var packed := raw.compress()
		writer.store_32(raw.size())
		writer.store_32(packed.size())
		writer.store_buffer(packed)
	writer.close()
	var reader := FileAccess.open(path, FileAccess.READ)
	if reader == null or reader.get_buffer(4).get_string_from_ascii() != "SAO2":
		return {"skip_decode_and_end": false, "reject_corrupt_length": false}
	var kernel: RefCounted = TerrainArmy._get_idle_kernel()
	var correct := kernel != null
	for index in values.size():
		var decode := index == 1 or index == 3
		var frame := _read_reference_frame(reader, decode)
		correct = correct and frame.get("ok") == true
		if decode and frame.get("ok") == true:
			correct = correct and int(kernel.call("exact_value_equal", frame.value, values[index])) == 1
	correct = correct and reader.get_position() == reader.get_length()
	reader.close()
	var corrupt := FileAccess.open(path, FileAccess.READ)
	corrupt.seek(0)
	var rejected: bool = _read_reference_frame(corrupt, false).get("ok") != true
	corrupt.close()
	return {"skip_decode_and_end": correct, "reject_corrupt_length": rejected}


func _inventory_snapshot(snapshot: Array) -> Dictionary:
	var counts := {"variant_nodes": 0, "max_depth": 0, "dictionary_nodes": 0,
		"dictionary_keys": 0, "mixed_key_dictionaries": 0, "array_nodes": 0,
		"array_elements": 0, "packed_elements": 0, "float_components": 0,
		"variant_types": {}, "key_types": {}, "packed_types": {},
		"array_metadata": {}, "dictionary_metadata": {},
		"unsupported": {}, "special_floats": {"negative_zero": 0,
			"positive_zero": 0, "nan": 0, "positive_inf": 0, "negative_inf": 0},
		"float_scope": "scalar, PackedFloat32/64, Vector2/3/4, Quaternion, Color"}
	_inventory_value(snapshot, counts, 0)
	return counts


func _inventory_value(value: Variant, counts: Dictionary, depth: int) -> void:
	var kind := typeof(value)
	counts.variant_nodes += 1
	counts.max_depth = maxi(int(counts.max_depth), depth)
	_inventory_count(counts.variant_types, type_string(kind))
	if kind in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL]:
		_inventory_count(counts.unsupported, type_string(kind))
		return
	if value is Dictionary:
		counts.dictionary_nodes += 1
		_inventory_count(counts.dictionary_metadata, "%d/%s/%s -> %d/%s/%s" % [
			value.get_typed_key_builtin(), str(value.get_typed_key_class_name()),
			_inventory_script_path(value.get_typed_key_script()),
			value.get_typed_value_builtin(), str(value.get_typed_value_class_name()),
			_inventory_script_path(value.get_typed_value_script())])
		var first_kind := -1
		var mixed := false
		for key: Variant in value:
			counts.dictionary_keys += 1
			var key_kind := typeof(key)
			_inventory_count(counts.key_types, type_string(key_kind))
			if first_kind < 0: first_kind = key_kind
			elif key_kind != first_kind: mixed = true
			_inventory_value(key, counts, depth + 1)
			_inventory_value(value[key], counts, depth + 1)
		if mixed: counts.mixed_key_dictionaries += 1
		return
	if value is Array:
		counts.array_nodes += 1
		counts.array_elements += value.size()
		_inventory_count(counts.array_metadata, "%s/%d/%s/%s" % [
			str(value.is_typed()), value.get_typed_builtin(),
			str(value.get_typed_class_name()), _inventory_script_path(value.get_typed_script())])
		for entry: Variant in value: _inventory_value(entry, counts, depth + 1)
		return
	if kind >= TYPE_PACKED_BYTE_ARRAY and kind <= TYPE_PACKED_VECTOR4_ARRAY:
		_inventory_count(counts.packed_types, type_string(kind))
		counts.packed_elements += value.size()
		if value is PackedFloat32Array or value is PackedFloat64Array:
			for number: float in value: _inventory_float(number, counts)
		return
	if kind == TYPE_FLOAT:
		_inventory_float(value, counts)
	elif value is Vector2:
		_inventory_float(value.x, counts)
		_inventory_float(value.y, counts)
	elif value is Vector3:
		_inventory_float(value.x, counts)
		_inventory_float(value.y, counts)
		_inventory_float(value.z, counts)
	elif value is Vector4 or value is Quaternion:
		for component: String in ["x", "y", "z", "w"]:
			_inventory_float(value[component], counts)
	elif value is Color:
		for component: String in ["r", "g", "b", "a"]:
			_inventory_float(value[component], counts)


func _inventory_float(number: float, counts: Dictionary) -> void:
	counts.float_components += 1
	if is_nan(number):
		counts.special_floats.nan += 1
	elif is_inf(number):
		if number < 0.0: counts.special_floats.negative_inf += 1
		else: counts.special_floats.positive_inf += 1
	elif number == 0.0:
		var bits := PackedByteArray()
		bits.resize(8)
		bits.encode_double(0, number)
		if bits[7] & 128: counts.special_floats.negative_zero += 1
		else: counts.special_floats.positive_zero += 1


func _inventory_count(bins: Dictionary, key: String) -> void:
	bins[key] = int(bins.get(key, 0)) + 1


func _inventory_script_path(script: Variant) -> String:
	return script.resource_path if script is Resource else ""
