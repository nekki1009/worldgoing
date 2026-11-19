extends SceneTree
## Original Slot codec persistence only. No Site/Actor progress or acceptance receipt.
## Each case opens a real public Slot and publishes G1/G2 through its original writer.
const Slot = preload("res://scripts/region_lab/region_save_slot.gd")
const Clock = preload("res://scripts/region_lab/region_gameplay_clock.gd")
const Grid = preload("res://scripts/region_lab/region_grid.gd")
const ACTION := 1.0 / 60.0
const DEADLINE_MS := 45000

var checks := 0
var failures: Array[String] = []
var source: RegionData
var source_root := ""
var world := ""
var deadline := 0
var case_sequence := 0
var negative_cases := 0
var legacy_cases := 0
var finished := false


func _initialize() -> void:
	deadline = Time.get_ticks_msec() + DEADLINE_MS
	_run.call_deferred()


func _check(value: bool, label: String, detail: Variant = null) -> bool:
	checks += 1
	if not value:
		failures.append(label)
		push_error("REGION_SLOT_CONTROL_CODEC_FAIL: " + label + " " + str(detail))
	return value


func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not _check(file != null, "Real fixture file opens for writing", path): return false
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	return _check(error == OK and FileAccess.get_file_as_string(path) == text, "Real fixture bytes persisted exactly", path)


func _asset(name: String, bytes: PackedByteArray) -> Dictionary:
	var path := source_root.path_join(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not _check(file != null, "Geographic fixture asset opens", path): return {}
	file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	if not _check(error == OK, "Geographic fixture asset is stored", path): return {}
	return {"path": name, "sha256": FileAccess.get_sha256(path)}


func _fixed_source() -> RegionData:
	# Same complete manifest/derived-layer shape as the original initial-world test.
	source_root = "res://.godot-temp/region_control_codec/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(source_root)) == OK, "Private fixed-source directory exists"): return null
	var summary := PackedByteArray()
	summary.resize(4)
	summary.fill(2)
	var summary_record := _asset("summary.u8", summary)
	if summary_record.is_empty(): return null
	summary_record.merge({"size": [2, 2], "site_origin": [0, 0], "encoding": "u8", "row_order": "north_to_south", "nodata": 0})
	var elevation := PackedByteArray()
	var levels := PackedByteArray()
	var water := PackedByteArray()
	elevation.resize(20 * 20 * 2)
	levels.resize(20 * 20)
	water.resize(20 * 20)
	for index: int in range(20 * 20):
		elevation.encode_s16(index * 2, 40)
		levels[index] = 2
	var height_record := _asset("clock.height.zlib", elevation.compress(FileAccess.COMPRESSION_DEFLATE))
	var level_record := _asset("clock.levels.zlib", levels.compress(FileAccess.COMPRESSION_DEFLATE))
	var water_record := _asset("clock.water.zlib", water.compress(FileAccess.COMPRESSION_DEFLATE))
	if height_record.is_empty() or level_record.is_empty() or water_record.is_empty(): return null
	height_record.merge({"id": "clock_plain", "origin": [0, 0], "size": [20, 20], "spacing_m": 20,
		"encoding": "int16_le_zlib", "row_order": "north_to_south", "nodata": -32767,
		"derived": {"encoding": "u8_zlib", "levels_path": level_record.path, "levels_sha256": level_record.sha256,
			"water_path": water_record.path, "water_sha256": water_record.sha256}})
	var manifest := {"format": 1, "synthetic_fixture": true, "atlas_id": Grid.ATLAS_ID, "grid_contract_version": 1,
		"base_revision": "original-slot-control-codec-v1", "crs": "EPSG:3826",
		"grid": {"origin": [0, 0], "cell_m": 2, "site_cells": 100, "region_sites": 100},
		"summary": summary_record, "elevation_tiles": [height_record], "sources": [{"title": "Original Slot codec fixed-source fixture"}]}
	var path := source_root.path_join("manifest.json")
	if not _write_text(path, JSON.stringify(manifest, "", true, true)): return null
	var loaded := RegionData.new()
	if not _check(loaded.load_manifest(path).ok, "Original RegionData admits all checksummed fixture layers"): return null
	return loaded


func _new_case(label: String) -> Dictionary:
	if not _check(Time.get_ticks_msec() < deadline, "Internal case deadline", label): return {}
	case_sequence += 1
	var id := "%s_%d" % [label, case_sequence]
	var slot := Slot.new()
	var opened: Dictionary = slot.open_map(source, world, id)
	if not _check(opened.ok and not opened.initialization_pending, "Public original empty-slot API opens " + id, opened): return {}
	var seed: Dictionary = slot.control.duplicate(true)
	seed.region_gameplay = Clock.empty_registry()
	var first: Dictionary = slot._publish({}, seed)
	if not _check(first.ok and int(first.generation) == 1, "Original publisher writes G1 " + id, first): return {}
	var candidate: Dictionary = slot.control.duplicate(true)
	# Pure original clock fixture, not a claimed completed Actor interval.
	var interval: Dictionary = Slot.preview_fire_interval(candidate.fire_clock, 0.0, ACTION, 1.0, ACTION)
	if not _check(interval.ok and interval.game_end == ACTION and interval.action_end == ACTION, "Original interval supplies exact 1/60 clock fixture " + id, interval): return {}
	Slot.append_completed_fire_interval(candidate.fire_clock, interval)
	candidate.logical_game_seconds = float(interval.game_end)
	if not _check(Slot.validate_fire_clock(candidate.fire_clock, candidate.logical_game_seconds).ok, "Original fire validator admits pure fixture " + id): return {}
	var expected: Dictionary = candidate.duplicate(true)
	var second: Dictionary = slot._publish({}, candidate)
	if not _check(second.ok and int(second.generation) == 2, "Original publisher writes selected G2 " + id, second): return {}
	var path: String = slot.folder.path_join("commits/%020d.json" % 2)
	var document: Dictionary = slot._read_document(path)
	if not _check(document.ok, "Original checksum reader reads selected G2 " + id, document): return {}
	return {"slot": slot, "id": id, "path": path, "record": document.payload, "clock": expected}


func _encode(value: Variant) -> Dictionary:
	return {"encoding": "godot_var_v1", "value": Marshalls.raw_to_base64(var_to_bytes(value))}


func _next_double(value: float) -> float:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	bytes.encode_u64(0, bytes.decode_u64(0) + 1)
	return bytes.decode_double(0)


func _roundtrip() -> bool:
	var fixture := _new_case("roundtrip")
	if fixture.is_empty(): return false
	var slot: RegionSaveSlot = fixture.slot
	var wire: Variant = fixture.record.control
	if not _check(wire is Dictionary and wire.size() == 2 and wire.get("encoding") == "godot_var_v1" and wire.get("value") is String, "Original publisher writes only the control wire wrapper"): return false
	var raw := Marshalls.base64_to_raw(str(wire.value))
	if not _check(raw == var_to_bytes(fixture.clock) and Marshalls.raw_to_base64(raw) == str(wire.value), "Persisted clock is the complete canonical original Variant bytes"): return false
	if not _check(var_to_bytes(slot.control) == var_to_bytes(fixture.clock) and not slot._marker.control.has("encoding"), "Live control and logical RAM marker retain the original clock"): return false
	var alias: Dictionary = slot.control
	var recovered: Dictionary = slot._recover_control()
	if not _check(recovered.ok and is_same(alias, slot.control), "Successful same-generation read retains original live control alias", recovered): return false
	var hash_before := FileAccess.get_sha256(fixture.path)
	var reopened := Slot.new()
	var result: Dictionary = reopened.open_map(source, world, fixture.id)
	if not _check(result.ok and int(reopened._marker.generation) == 2, "Public fresh Slot selects genuine G2", result): return false
	if not _check(var_to_bytes(reopened.control) == var_to_bytes(fixture.clock) and reopened.control.fire_clock.action_seconds == ACTION and reopened.control.logical_game_seconds == ACTION, "Fresh Slot restores exact non-integer game/action doubles without epsilon"): return false
	if not _check(FileAccess.get_sha256(fixture.path) == hash_before, "Fresh reopen does not rewrite the accepted marker"): return false
	# Deliberately incomplete negative frame: this reaches only the original exact guard.
	# Successful original body/geometry/graph restoration belongs to the unchanged Life test.
	var next_action := _next_double(ACTION)
	var party := {"upkeep": {"live": {"frame": {"game_seconds": ACTION, "action_seconds": next_action}}}}
	var strict: Dictionary = reopened.region_live_party_geometry(party)
	return _check(next_action != ACTION and not strict.ok and strict.code == "STALE_PARTY_FRAME", "Original frame guard still rejects even one ULP of action drift", strict)


func _reject(label: String, expected_code: String = "CORRUPT_SAVE") -> bool:
	var fixture := _new_case(label)
	if fixture.is_empty(): return false
	var slot: RegionSaveSlot = fixture.slot
	var record: Dictionary = fixture.record.duplicate(true)
	var clock: Dictionary = fixture.clock.duplicate(true)
	var special_envelope := ""
	match label:
		"envelope_extra": special_envelope = "extra"
		"envelope_missing": special_envelope = "missing"
		"envelope_payload_type": special_envelope = "type"
		"envelope_checksum": special_envelope = "checksum"
		"wrapper_extra": record.control.extra = true
		"wrapper_missing_encoding": record.control.erase("encoding")
		"wrapper_missing_value": record.control.erase("value")
		"wrapper_wrong_tag": record.control.encoding = "unknown_variant_codec"
		"wrapper_value_type": record.control.value = 123
		"base64_empty": record.control.value = ""
		"base64_noncanonical":
			# Valid decoder input with a permitted newline; re-encoding removes it.
			var canonical := str(record.control.value)
			record.control.value = canonical + "\n"
			if not _check(Marshalls.base64_to_raw(str(record.control.value)) == Marshalls.base64_to_raw(canonical), "Noncanonical Base64 has the same legal bytes before Slot validation"): return false
		"decoded_primitive": record.control = _encode(123)
		"decoded_trailing":
			var raw := var_to_bytes(clock)
			raw.append_array(PackedByteArray([0, 0, 0, 0]))
			record.control = {"encoding": "godot_var_v1", "value": Marshalls.raw_to_base64(raw)}
		"clock_extra":
			clock.extra = true
			record.control = _encode(clock)
		"clock_negative_game":
			clock.logical_game_seconds = -1.0
			record.control = _encode(clock)
		"clock_active_type":
			clock.active_site_id = 123
			record.control = _encode(clock)
		"clock_unselected_active":
			clock.active_site_id = "missing-original-site"
			record.control = _encode(clock)
		"clock_invalid_fire":
			clock.fire_clock.version = 99
			record.control = _encode(clock)
		"clock_journal_endpoint":
			clock.fire_clock.action_seconds = _next_double(ACTION)
			record.control = _encode(clock)
		"clock_invalid_registry":
			clock.region_gameplay.revision = -1
			record.control = _encode(clock)
		"record_invalid_sites": record.sites = {"0:0": {"path": "outside.json", "sha256": "0".repeat(64)}}
		"record_invalid_journey": record.journey = {"unexpected": true}
		_: return _check(false, "Known reviewable negative case", label)
	var body := JSON.stringify(record, "", true, true)
	var envelope := {"payload": body, "checksum": body.sha256_text()}
	match special_envelope:
		"extra": envelope.extra = true
		"missing": envelope.erase("checksum")
		"type": envelope.payload = record
		"checksum": envelope.checksum = "0".repeat(64)
	if not _write_text(fixture.path, JSON.stringify(envelope, "\t")): return false
	var hash_after := FileAccess.get_sha256(fixture.path)
	var fresh := Slot.new()
	var reopened: Dictionary = fresh.open_map(source, world, fixture.id)
	if not _check(not reopened.ok and reopened.get("code") == expected_code, "Fresh original Slot rejects selected corrupt G2 without G1 fallback: " + label, reopened): return false
	var control_alias: Dictionary = slot.control
	var marker_alias: Dictionary = slot._marker
	var old_clock := var_to_bytes(slot.control)
	var old_marker := var_to_bytes(slot._marker)
	var live_recovery: Dictionary = slot._recover_control()
	if not _check(not live_recovery.ok and live_recovery.get("code") == expected_code, "Original live recovery rejects the same corruption: " + label, live_recovery): return false
	if not _check(is_same(control_alias, slot.control) and is_same(marker_alias, slot._marker)
		and var_to_bytes(slot.control) == old_clock and var_to_bytes(slot._marker) == old_marker, "Rejected recovery retains exact original RAM owners: " + label): return false
	if not _check(FileAccess.get_sha256(fixture.path) == hash_after, "Rejected original recovery never repairs corrupt marker bytes: " + label): return false
	negative_cases += 1
	return true


func _legacy(fields: int) -> bool:
	var fixture := _new_case("legacy%d" % fields)
	if fixture.is_empty(): return false
	var record: Dictionary = fixture.record.duplicate(true)
	var clock: Dictionary = fixture.clock.duplicate(true)
	if fields < 4: clock.erase("region_gameplay")
	if fields == 2: clock.erase("fire_clock")
	# Historical bare clocks predate the faction-era control fields and the format-2 marker.
	clock.erase("faction_registry")
	clock.erase("person_allocator")
	record["format"] = 1
	# Deliberate historical bare JSON. Capture what that exact old text decodes to;
	# the reader must retain it, never infer/round it back to a live body's 1/60.
	record.control = clock
	var body := JSON.stringify(record, "", true, true)
	var parsed: Variant = JSON.parse_string(body)
	if not _check(parsed is Dictionary and parsed.control is Dictionary and parsed.control.size() == fields, "Historical bare clock has the original supported field count", fields): return false
	var expected: Dictionary = parsed.control
	if not _write_text(fixture.path, JSON.stringify({"payload": body, "checksum": body.sha256_text()}, "\t")): return false
	var hash_before := FileAccess.get_sha256(fixture.path)
	var reopened := Slot.new()
	var result: Dictionary = reopened.open_map(source, world, fixture.id)
	if not _check(result.ok and int(reopened._marker.generation) == 2, "Original public reader still supports bare legacy clock size " + str(fields), result): return false
	if not _check(reopened.control.logical_game_seconds == expected.logical_game_seconds and reopened.control.active_site_id == expected.active_site_id,
		"Legacy reader preserves the historical parsed game double and active identity", fields): return false
	if fields == 2:
		if not _check(reopened.control.size() == 3 and reopened.control.fire_clock.action_seconds == 0.0
			and reopened.control.fire_clock.base_game_seconds == expected.logical_game_seconds
			and Slot.validate_fire_clock(reopened.control.fire_clock, reopened.control.logical_game_seconds).ok, "Original two-field migration only adds its original zero-action fire clock"): return false
	else:
		if not _check(var_to_bytes(reopened.control) == var_to_bytes(expected), "Original legacy three/four-field clock stays exactly as parsed", fields): return false
	if not _check(FileAccess.get_sha256(fixture.path) == hash_before, "Legacy recovery does not rewrite or repair historical JSON", fields): return false
	legacy_cases += 1
	return true


func _finish() -> void:
	if finished: return
	finished = true
	print("REGION_SLOT_CONTROL_CODEC_", "PASS" if failures.is_empty() else "FAILED", " checks=", checks,
		" negative_cases=", negative_cases, " legacy_cases=", legacy_cases,
		" scope=original_slot_marker_codec_only runtime_files_retained=", world)
	quit(0 if failures.is_empty() else 1)


func _run() -> void:
	source = _fixed_source()
	if source == null: _finish(); return
	world = "codec_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _roundtrip(): _finish(); return
	for label: String in ["envelope_extra", "envelope_missing", "envelope_payload_type", "envelope_checksum",
		"wrapper_extra", "wrapper_missing_encoding", "wrapper_missing_value", "wrapper_wrong_tag", "wrapper_value_type",
		"base64_empty", "base64_noncanonical", "decoded_primitive", "decoded_trailing",
		"clock_extra", "clock_negative_game", "clock_active_type", "clock_unselected_active",
		"record_invalid_sites", "record_invalid_journey"]:
		if not _reject(label): _finish(); return
	for item: Array in [["clock_invalid_fire", "CORRUPT_FIRE_CLOCK"], ["clock_journal_endpoint", "CORRUPT_FIRE_JOURNAL"], ["clock_invalid_registry", "REGION_SCHEMA"]]:
		if not _reject(str(item[0]), str(item[1])): _finish(); return
	for fields: int in [2, 3, 4]:
		if not _legacy(fields): _finish(); return
	if not _check(negative_cases == 22 and legacy_cases == 3, "Every declared negative and legacy case executed"): _finish(); return
	_finish()
