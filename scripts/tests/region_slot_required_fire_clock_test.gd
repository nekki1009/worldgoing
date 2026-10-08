extends "res://scripts/tests/region_initial_world_transaction_test.gd"
## Original fixed-source/check/deadline fixture; original bare JSON Slot wire.
## No scene, person, bind receipt, codec wrapper or second save authority.

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 120000
	_run.call_deferred()

func _clock_case(source: RegionData, label: String, logical_clock: Dictionary, expected_code: String = "") -> bool:
	var world_id := _world("required_fire_" + label)
	var slot := RegionSaveSlot.new()
	var opened := slot.open_map(source, world_id, SLOT)
	if not _check(opened.ok, "Original empty Slot opens: " + label, opened): return false
	var record := {"format": 1, "generation": 1, "pin": slot.pin.duplicate(true), "sites": {},
		"control": logical_clock.duplicate(true), "transfer_token": "", "journey": {}}
	var marker_path := slot.folder.path_join("commits/%020d.json" % 1)
	var written := slot._write_new_document(marker_path, record)
	if not _check(written.ok, "Original checksum writer records isolated bare JSON fixture: " + label, written): return false
	var marker_sha := FileAccess.get_sha256(marker_path)
	var probe := RegionSaveSlot.new()
	var result := probe.open_map(source, world_id, SLOT)
	if expected_code.is_empty():
		if not _check(result.ok, "Original reader admits valid legacy control: " + label, result): return false
		if not _check(probe.control.get("fire_clock") is Dictionary, "Valid legacy size2 owns the original default clock: " + label): return false
		var validated := RegionSaveSlot.validate_fire_clock(probe.control.fire_clock, probe.control.logical_game_seconds)
		if not _check(validated.ok, "Original complete fire validator accepts legacy default: " + label, validated): return false
		if not _check(float(probe.control.logical_game_seconds) == 0.0 and float(probe.control.fire_clock.action_seconds) == 0.0 and int(probe.control.fire_clock.sequence) == 0 and str(probe.control.active_site_id).is_empty(), "Legacy default adds no world/action time or active owner"): return false
	else:
		if not _check(not result.ok and str(result.get("code", "")) == expected_code, "Malformed required fire clock returns clean CORRUPT_SAVE: " + label, result): return false
		if not _check(probe._marker.is_empty(), "Rejected control never selects a durable marker: " + label): return false
	if not _check(FileAccess.get_sha256(marker_path) == marker_sha, "Read/rejection preserves original marker bytes: " + label): return false
	report[label] = {"expected_code": expected_code, "ok": result.ok, "code": result.get("code", ""), "marker_sha256": marker_sha}
	return true

func _published_clock_case(source: RegionData, logical_clock: Dictionary, label: String) -> bool:
	var world_id := _world("required_fire_" + label)
	var slot: RegionSaveSlot = RegionSaveSlot.new()
	var opened: Dictionary = slot.open_map(source, world_id, SLOT)
	if not _check(opened.ok, "Original empty Slot opens for publication: " + label, opened): return false
	var published: Dictionary = slot._publish({}, logical_clock)
	if not _check(published.ok, "Original publisher commits bare JSON fractional clock: " + label, published): return false
	if not _check(not is_same(slot._marker.control, slot.control) and not is_same(slot._marker.control.fire_clock, slot.control.fire_clock), "Published durable control and nested fire clock are distinct from live owners: " + label): return false
	var marker_path := slot.folder.path_join("commits/%020d.json" % int(published.generation))
	var marker_sha := FileAccess.get_sha256(marker_path)
	var live_ref: Dictionary = slot.control
	var live_values: Dictionary = slot.control.duplicate(true)
	var recovered: Dictionary = slot._recover_control()
	if not _check(recovered.ok and is_same(slot.control, live_ref), "Same-generation original recovery preserves the live control reference: " + label, recovered): return false
	if not _check(slot.control == live_values and float(slot.control.logical_game_seconds) == float(live_values.logical_game_seconds) and float(slot.control.fire_clock.action_seconds) == float(live_values.fire_clock.action_seconds), "Same-generation recovery leaves exact logical values unchanged: " + label): return false
	if not _check(FileAccess.get_sha256(marker_path) == marker_sha, "Same-generation recovery preserves committed marker bytes: " + label): return false
	var probe: RegionSaveSlot = RegionSaveSlot.new()
	var result: Dictionary = probe.open_map(source, world_id, SLOT)
	if not _check(result.ok, "Original reader reopens published bare JSON clock: " + label, result): return false
	if not _check(probe.control == logical_clock and float(probe.control.fire_clock.action_seconds) == float(logical_clock.fire_clock.action_seconds) and float(probe.control.logical_game_seconds) == float(logical_clock.logical_game_seconds), "Original JSON publisher/reader retain exact complete fractional clock: " + label): return false
	var validated: Dictionary = RegionSaveSlot.validate_fire_clock(probe.control.fire_clock, probe.control.logical_game_seconds)
	if not _check(validated.ok, "Original full fire validator admits bare JSON roundtrip: " + label, validated): return false
	if logical_clock.has("region_gameplay"):
		var registry: Dictionary = RegionSaveSlot.GameplayClock.validate_registry(probe.control.region_gameplay, float(probe.control.logical_game_seconds))
		if not _check(registry.ok, "Original registry validator admits recovered JSON numeric fields: " + label, registry): return false
	if not _check(FileAccess.get_sha256(marker_path) == marker_sha, "Reopen never rewrites published fractional marker: " + label): return false
	report[label] = {"generation": int(published.generation), "marker_sha256": marker_sha, "action_seconds": probe.control.fire_clock.action_seconds, "game_seconds": probe.control.logical_game_seconds}
	return true

func _run() -> void:
	var source := _fixed_source()
	if source == null: _finish(); return
	var missing := {"logical_game_seconds": 0.0, "active_site_id": "", "unused": 0}
	var wrong_type := {"logical_game_seconds": 0.0, "active_site_id": "", "fire_clock": 0}
	var legacy := {"logical_game_seconds": 0.0, "active_site_id": ""}
	if not _clock_case(source, "missing_bare", missing, "CORRUPT_SAVE"): _finish(); return
	if not _clock_case(source, "wrong_type_bare", wrong_type, "CORRUPT_SAVE"): _finish(); return
	if not _clock_case(source, "legacy_bare", legacy): _finish(); return
	var fire := RegionSaveSlot._new_fire_clock(0.0)
	var interval := RegionSaveSlot.preview_fire_interval(fire, 0.0, 1.0 / 60.0, 1.0, 0.0)
	if not _check(interval.get("ok", false), "Original producer admits fractional complete clock", interval): _finish(); return
	RegionSaveSlot.append_completed_fire_interval(fire, interval)
	var complete := {"logical_game_seconds": float(interval.game_end), "active_site_id": "", "fire_clock": fire}
	if not _published_clock_case(source, complete, "fractional_size3"): _finish(); return
	complete.region_gameplay = RegionSaveSlot.GameplayClock.empty_registry()
	if not _published_clock_case(source, complete, "fractional_size4_registry"): _finish(); return
	_finish()

func _finish(reason: String = "") -> void:
	if finished: return
	finished = true
	if not reason.is_empty(): failures.append(reason)
	print("REGION_SLOT_REQUIRED_FIRE_CLOCK_REPORT: " + JSON.stringify({"checks": checks, "failures": failures, "cases": report,
		"source_epochs": {"slot": FileAccess.get_sha256("res://scripts/region_lab/region_save_slot.gd"),
		"inherited_fixture": FileAccess.get_sha256("res://scripts/tests/region_initial_world_transaction_test.gd")}, "fixture": root_path}, "", true, true))
	print("REGION_SLOT_REQUIRED_FIRE_CLOCK_", "PASS" if failures.is_empty() else "FAIL", " scope=original_bare_JSON_required_fire_clock_legacy_size2_exactpublishedfractional_size3_size4")
	quit(0 if failures.is_empty() else 1)
