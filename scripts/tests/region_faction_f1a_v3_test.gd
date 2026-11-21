extends "res://scripts/tests/region_faction_f1a_v2_test.gd"
## Real original RegionData/Store/writer/recovery/publication; no fake success.
## Existing v2 joined/missing-nation cases run separately and remain delivered.
const Grid = preload("res://scripts/region_lab/region_grid.gd")
var source_root := ""

class CountedSlot extends RegionSaveSlot:
	var scope_hashes: int = 0
	var content_hashes: int = 0
	func _faction_scope_digest(inputs: Array) -> String:
		scope_hashes += 1
		return super._faction_scope_digest(inputs)
	func _faction_digest_bytes(bytes: PackedByteArray) -> String:
		content_hashes += 1
		return super._faction_digest_bytes(bytes)
	var latest_reads := 0
	var commit_reads := 0
	var faction_scans := 0
	var site_reads := 0
	var site_hashes := 0
	var party_reads := 0
	var party_hashes := 0
	func _recover_read_latest(preserve_live: bool, live_control: Dictionary) -> Dictionary:
		latest_reads += 1
		return super._recover_read_latest(preserve_live, live_control)
	func _read_document(path: String, maximum: int = 1048576) -> Dictionary:
		if path.contains("/commits/"): commit_reads += 1
		return super._read_document(path, maximum)
	func _faction_scan(sites: Dictionary, clock: Dictionary, journey: Dictionary, previous: Dictionary, reserved: Array = [], include_legacy: bool = true, with_persons: bool = false, with_organization_sources: bool = false) -> Dictionary:
		faction_scans += 1
		return super._faction_scan(sites, clock, journey, previous, reserved, include_legacy, with_persons, with_organization_sources)
	func _load_checked(path: String, site: Vector2i) -> Dictionary:
		site_reads += 1
		return super._load_checked(path, site)
	func _faction_read_party(path: String) -> Dictionary:
		party_reads += 1
		return super._faction_read_party(path)
	func _faction_file_sha256(path: String) -> String:
		if path.contains("/generations/") or path.contains("/sites/"): site_hashes += 1
		if path.contains("/travel/"): party_hashes += 1
		return super._faction_file_sha256(path)

func _write_text(path: String, text: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if not check(file != null, "Real fixture file opens for writing"): return false
	file.store_string(text)
	file.flush()
	var error: Variant = file.get_error()
	file.close()
	return check(error == OK and FileAccess.get_file_as_string(path) == text, "Real fixture bytes persisted exactly")


func _asset(name: String, bytes: PackedByteArray) -> Dictionary:
	var path: Variant = source_root.path_join(name)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if not check(file != null, "Geographic fixture asset opens"): return {}
	file.store_buffer(bytes)
	file.flush()
	var error: Variant = file.get_error()
	file.close()
	if not check(error == OK, "Geographic fixture asset is stored"): return {}
	return {"path": name, "sha256": FileAccess.get_sha256(path)}


func _fixed_source() -> RegionData:
	# Original initial-world 22x22/-20m fixture covers the required one-cell Site halo.
	source_root = "user://tests/faction_f1a_v3_source/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(source_root)) == OK, "Private fixed-source directory exists"): return null
	var summary: PackedByteArray = PackedByteArray()
	summary.resize(4)
	summary.fill(2)
	var summary_record: Dictionary = _asset("summary.u8", summary)
	if summary_record.is_empty(): return null
	summary_record.merge({"size": [2, 2], "site_origin": [0, 0], "encoding": "u8", "row_order": "north_to_south", "nodata": 0})
	var elevation: PackedByteArray = PackedByteArray()
	var levels: PackedByteArray = PackedByteArray()
	var water: PackedByteArray = PackedByteArray()
	elevation.resize(22 * 22 * 2)
	levels.resize(22 * 22)
	water.resize(22 * 22)
	for index: int in range(22 * 22):
		elevation.encode_s16(index * 2, 40)
		levels[index] = 2
	var height_record: Dictionary = _asset("clock.height.zlib", elevation.compress(FileAccess.COMPRESSION_DEFLATE))
	if height_record.is_empty(): return null
	var level_record: Dictionary = _asset("clock.levels.zlib", levels.compress(FileAccess.COMPRESSION_DEFLATE))
	if level_record.is_empty(): return null
	var water_record: Dictionary = _asset("clock.water.zlib", water.compress(FileAccess.COMPRESSION_DEFLATE))
	if water_record.is_empty(): return null
	height_record.merge({"id": "clock_plain", "origin": [-20, -20], "size": [22, 22], "spacing_m": 20,
		"encoding": "int16_le_zlib", "row_order": "north_to_south", "nodata": -32767,
		"derived": {"encoding": "u8_zlib", "levels_path": level_record.path, "levels_sha256": level_record.sha256,
			"water_path": water_record.path, "water_sha256": water_record.sha256}})
	var manifest: Dictionary = {"format": 1, "synthetic_fixture": true, "atlas_id": Grid.ATLAS_ID, "grid_contract_version": 1,
		"base_revision": "original-slot-control-codec-v1", "crs": "EPSG:3826",
		"grid": {"origin": [0, 0], "cell_m": 2, "site_cells": 100, "region_sites": 100},
		"summary": summary_record, "elevation_tiles": [height_record], "sources": [{"title": "Original F1a v3 immutable-source fixture"}]}
	var path: Variant = source_root.path_join("manifest.json")
	if not _write_text(path, JSON.stringify(manifest, "", true, true)): return null
	var loaded: RegionData = RegionData.new()
	if not check(loaded.load_manifest(path).ok, "Original RegionData admits all checksummed fixture layers"): return null
	return loaded


func _prime_cache_probe(probe: CountedSlot, summary: Dictionary, encoded: String) -> bool:
	var remembered: Dictionary = probe._faction_remember("probe", summary)
	var decoded: Dictionary = probe._faction_decode_clock(encoded)
	return check(remembered.ok and decoded.ok, "V5 original cache producers prime actual admitted source/control")

func _cache_cost_regression(original: CountedSlot, fixed: RegionData, coordinate: Vector2i) -> bool:
	# Independent Slot; summaries/control come from the first real published Site.
	var record: Dictionary = original._marker.sites["0:0"]
	var actual: Dictionary = original._faction_cached(original._faction_site_key(str(record.sha256), coordinate, original.folder.path_join(str(record.path))))
	if not check(actual.get("ok", false), "V5 actual publication supplies the original validated source summary"): return false
	var summary: Dictionary = actual.summary
	var encoded: String = Marshalls.raw_to_base64(var_to_bytes(original.control))
	var probe: CountedSlot = CountedSlot.new()
	probe.source = fixed
	probe.folder = original.folder
	probe.pin = original.pin.duplicate(true)
	var scope: String = probe._faction_cache_context()
	if not check(probe.scope_hashes == 1 and scope == var_to_bytes([probe.folder, probe.pin, fixed.get_instance_id(), fixed.manifest_hash]).hex_encode().sha256_text(),
			"V5 cold scope computes exactly the original four-input digest once"): return false
	if not _prime_cache_probe(probe, summary.duplicate(true), encoded): return false
	var digest_count: int = probe.content_hashes
	for repeat: int in range(8):
		var hit: Dictionary = probe._faction_cached("probe")
		var clock_hit: Dictionary = probe._faction_decode_clock(encoded)
		if not check(probe._faction_cache_context() == scope and hit.ok and clock_hit.ok,
				"V5 warm source/clock reuse still checks exact current values"): return false
	if not check(probe.scope_hashes == 1 and probe.content_hashes == digest_count,
			"V5 unchanged warm calls execute neither scope nor content hex/SHA again"): return false
	var hit: Dictionary = probe._faction_cached("probe")
	hit.summary.owner = "returned-copy-change"
	var returned_clock: Dictionary = probe._faction_decode_clock(encoded)
	returned_clock.clock["return_probe"] = true
	if not check(probe._faction_cached("probe").summary == summary and var_to_bytes(probe._faction_decode_clock(encoded).clock) == var_to_bytes(original.control),
			"V5 returned summary/control changes cannot mutate cached owners"): return false
	var input: Dictionary = summary.duplicate(true)
	var remembered: Dictionary = probe._faction_remember("probe", input)
	remembered.summary.owner = "remember-return-change"
	if not check(probe._faction_cached("probe").summary == summary, "V5 remember's caller/input alias never aliases its stored summary"): return false
	probe._faction_source_cache["probe"].summary.owner = "poisoned"
	if not check(probe._faction_cached("probe").is_empty() and not probe._faction_source_cache.has("probe") and not probe._faction_summary_digest_memo.has("probe"),
			"V5 nested summary pollution is rejected and its independent digest memo discarded"): return false
	if not _prime_cache_probe(probe, summary.duplicate(true), encoded): return false
	probe._faction_source_cache["probe"].digest = "0".repeat(64)
	if not check(probe._faction_cached("probe").is_empty(), "V5 wrong digest cannot borrow a valid exact-bytes memo"): return false
	probe._faction_source_cache["probe"] = "invalid"
	if not check(probe._faction_cached("probe").is_empty(), "V5 wrong entry type still rejects before any cast"): return false
	# A numerical equality must not replace exact Variant bytes/type discrimination.
	var typed_summary: Dictionary = summary.duplicate(true)
	typed_summary["number_probe"] = 1
	probe._faction_remember("probe", typed_summary)
	probe._faction_source_cache["probe"].summary.number_probe = 1.0
	if not check(probe._faction_cached("probe").is_empty(), "V5 int-to-float nested content mutation is not an exact-bytes hit"): return false
	var clock_key: String = encoded.sha256_text()
	probe._faction_clock_cache[clock_key].clock["poison"] = true
	if not check(var_to_bytes(probe._faction_decode_clock(encoded).clock) == var_to_bytes(original.control), "V5 polluted clock misses and truly decodes original encoded bytes"): return false
	probe._faction_clock_cache[clock_key].digest = "0".repeat(64)
	var before_recheck: int = probe.content_hashes
	var rechecked_clock: Dictionary = probe._faction_decode_clock(encoded)
	if not check(rechecked_clock.ok and probe.content_hashes == before_recheck + 2 and var_to_bytes(rechecked_clock.clock) == var_to_bytes(original.control),
			"V5 wrong clock digest executes full SHA rejection plus original decoded-byte SHA"): return false
	probe._faction_clock_cache[clock_key] = "invalid"
	before_recheck = probe.content_hashes
	var shape_recheck: Dictionary = probe._faction_decode_clock(encoded)
	if not check(shape_recheck.ok and probe.content_hashes == before_recheck + 1 and var_to_bytes(shape_recheck.clock) == var_to_bytes(original.control),
			"V5 wrong clock entry type truly decodes original bytes without cast error"): return false
	if not _prime_cache_probe(probe, summary.duplicate(true), encoded): return false
	probe.pin["scope_probe"] = {"value": 1}
	var changed: String = probe._faction_cache_context()
	if not check(changed != scope and probe.scope_hashes == 2 and probe._faction_source_cache.is_empty() and probe._faction_clock_cache.is_empty(),
			"V5 in-place nested pin change rebuilds scope and invalidates both original caches"): return false
	if not _prime_cache_probe(probe, summary.duplicate(true), encoded): return false
	probe.pin.scope_probe.value = 1.0
	var float_scope: String = probe._faction_cache_context()
	if not check(float_scope != changed and probe.scope_hashes == 3 and probe._faction_summary_digest_memo.is_empty() and probe._faction_clock_digest_memo.is_empty(),
			"V5 exact pin encoding catches int-to-float mutation and clears validated memo snapshots"): return false
	if not _prime_cache_probe(probe, summary.duplicate(true), encoded): return false
	probe.folder += "/scope-changed"
	var folder_scope: String = probe._faction_cache_context()
	if not check(folder_scope != float_scope and probe.scope_hashes == 4 and probe._faction_source_cache.is_empty(), "V5 original folder is still part of scope identity"): return false
	if not _prime_cache_probe(probe, summary.duplicate(true), encoded): return false
	var other_source: RegionData = RegionData.new()
	if not check(other_source.load_manifest(source_root.path_join("manifest.json")).ok, "V5 distinct real source admits the original fixture manifest"): return false
	probe.source = other_source
	var other_scope: String = probe._faction_cache_context()
	if not check(other_scope != folder_scope and probe.scope_hashes == 5 and probe._faction_source_cache.is_empty(), "V5 different source instance invalidates even with identical manifest bytes"): return false
	if not _prime_cache_probe(probe, summary.duplicate(true), encoded): return false
	var changed_manifest: Dictionary = other_source.manifest.duplicate(true)
	changed_manifest.sources = [{"title": "V5 real manifest reload changes identity while preserving geography assets"}]
	var changed_path: String = source_root.path_join("manifest_scope_changed.json")
	if not _write_text(changed_path, JSON.stringify(changed_manifest, "", true, true)): return false
	if not check(other_source.load_manifest(changed_path).ok, "V5 same real source actually reloads the changed checksummed manifest"): return false
	if not check(probe._faction_cache_context() != other_scope and probe.scope_hashes == 6 and probe._faction_source_cache.is_empty(), "V5 same instance/new manifest hash invalidates original source summaries"): return false
	if not _prime_cache_probe(probe, summary.duplicate(true), encoded): return false
	probe._faction_source_cache.clear()
	probe._faction_clock_cache.clear()
	probe._faction_cache_context()
	if not check(probe._faction_summary_digest_memo.is_empty() and probe._faction_clock_digest_memo.is_empty() and probe.scope_hashes == 6,
			"V5 explicit cache clear discards independent snapshots without rebuilding unchanged scope"): return false
	for index: int in range(RegionSaveSlot.FACTION_SOURCE_CACHE_LIMIT + 1): probe._faction_remember("eviction:%d" % index, summary)
	if not check(probe._faction_source_cache.size() == RegionSaveSlot.FACTION_SOURCE_CACHE_LIMIT and probe._faction_summary_digest_memo.size() == RegionSaveSlot.FACTION_SOURCE_CACHE_LIMIT
			and not probe._faction_source_cache.has("eviction:0") and not probe._faction_summary_digest_memo.has("eviction:0"), "V5 original128-entry eviction also removes its computed snapshot"): return false
	return true

func _run() -> void:
	var fixed: RegionData = _fixed_source()
	if fixed == null or failed: return
	var slot: CountedSlot = CountedSlot.new()
	var id: Variant = "f1a_v3_" + Crypto.new().generate_random_bytes(8).hex_encode()
	if not check(slot.open_map(fixed, id, "main").ok, "original public Slot opens full admitted geographic fixture"): return
	var coordinate: Vector2i = Vector2i.ZERO
	var opened: Variant = slot.open_site(coordinate)
	# DIAG_ONLY: retain the original open result; do not build/validate/settle a second time.
	print("F1A_V4_DIAG v3_original_open_site ", JSON.stringify({
		"opened": {"ok": opened.get("ok"), "code": opened.get("code"), "message": opened.get("message"),
			"interactive": opened.get("interactive"), "created": opened.get("created")},
		"data_present": opened.get("data") is TerrainData, "expected_interactive": true,
		"coordinate": [coordinate.x, coordinate.y], "logical_game_seconds": slot.control.get("logical_game_seconds"),
		"source_base_revision": fixed.manifest.get("base_revision")}, "", true))
	if not check(opened.ok and opened.get("interactive", false), "original fixed-source Site opens with real runtime state"): return
	var data: TerrainData = opened.data
	var relative: Variant = "generations/%020d_%d_%d.json" % [1, coordinate.x, coordinate.y]
	var saved: Variant = slot._save_checked(data, coordinate, slot.folder.path_join(relative))
	if not check(saved.ok, "original Store save/readback, no substitute Site validator"): return
	var sites: Dictionary = {"0:0": {"path": relative, "sha256": FileAccess.get_sha256(slot.folder.path_join(relative))}}
	var clock: Variant = slot.control.duplicate(true)
	clock.region_gameplay = Clock.empty_registry()
	clock.active_site_id = str(data.site.id)
	var reads: int = slot.site_reads
	var hashes: int = slot.site_hashes
	var first: Variant = slot._publish(sites, clock)
	if not check(first.ok and int(first.generation) == 1 and slot.site_reads == reads + 1 and slot.site_hashes == hashes + 1, "first recorded Site miss performs original validation and exactly one final SHA"): return
	if not _cache_cost_regression(slot, fixed, coordinate): return
	var scans: int = slot.faction_scans
	var latest: int = slot.latest_reads
	var commits: int = slot.commit_reads
	if not check(slot._recover_control().ok and slot.latest_reads == latest + 1 and slot.commit_reads == commits + 1 and slot.faction_scans == scans + 1, "first new commit recovery validates faction once and records successful memo"): return
	var live: Dictionary = slot.control
	var marker_bytes: PackedByteArray = var_to_bytes(slot._marker)
	latest = slot.latest_reads; commits = slot.commit_reads; scans = slot.faction_scans
	reads = slot.site_reads; hashes = slot.site_hashes
	for repeat in range(8):
		if not check(slot._recover_control().ok, "same-commit recovery succeeds via original memo"): return
	if not check(slot.latest_reads == latest and slot.commit_reads == commits and slot.faction_scans == scans and slot.site_reads == reads and slot.site_hashes == hashes, "same commit existing, successor absent: no read/hash/faction rescan"): return
	if not check(is_same(slot.control, live) and var_to_bytes(slot._marker) == marker_bytes, "memo keeps same-generation live control object and exact logical marker"): return
	# Exercise BOTH publication preambles. G2 becomes the next latest commit
	# before the second call; helper-only cache tests would miss this path.
	var second: Variant = slot._publish(sites, slot.control)
	if not check(second.ok and int(second.generation) == 2, "first consecutive original publication creates successor G2"): return
	var third: Variant = slot._publish(sites, slot.control)
	if not check(third.ok and int(third.generation) == 3 and slot.latest_reads == latest + 1 and slot.commit_reads == commits + 1, "second consecutive publication recovers actual new G2 before writing G3"): return
	if not check(slot.site_reads == reads and slot.site_hashes == hashes, "two consecutive publish calls including new-commit recovery do not read/hash unchanged Site"): return
	if not check(int(slot._recover_known_commit[slot.folder].generation) == 2, "publisher does not seed an un-read latest-commit memo"): return
	if not check(slot._recover_control().ok and int(slot._recover_known_commit[slot.folder].generation) == 3 and slot.site_reads == reads and slot.site_hashes == hashes, "new G3 advances memo through full commit validation with Site cache hit"): return
	# This is a new immutable file produced by the original writer, with actual
	# typed bodies/holder/items from the existing original join fixture.
	var party: Variant = _fixture_party(_fixture_state("party-source", "v3:party"), "player_live")
	party.content.armies[0].faction_id = 900
	var proof: Variant = _write_party(slot, party, "travel/player_live/party_source.json")
	if failed: return
	var journey: Variant = _journey(party, proof)
	if failed: return
	var party_reads: int = slot.party_reads
	var party_hashes: int = slot.party_hashes
	var party_publish: Variant = slot._publish(sites, slot.control, "", journey)
	if not check(party_publish.ok and slot.party_reads == party_reads + 1 and slot.party_hashes == party_hashes + 1 and slot.control.faction_registry.entries.has("900"), "new original party source validates and hashes once before summary cache"): return
	party_reads = slot.party_reads; party_hashes = slot.party_hashes
	if not check(slot._publish(sites, slot.control, "", journey).ok, "first actual successor publication carries recorded original party reference"): return
	if not check(slot._publish(sites, slot.control, "", journey).ok, "second actual successor publication carries recorded original party reference"): return
	if not check(slot.party_reads == party_reads and slot.party_hashes == party_hashes and slot.site_reads == reads and slot.site_hashes == hashes, "unchanged recorded Site and party both skip source I/O across new-commit recovery"): return
	var reopened: CountedSlot = CountedSlot.new()
	reopened.folder = slot.folder; reopened.source = slot.source; reopened.pin = slot.pin.duplicate(true)
	if not check(reopened._recover_control().ok and reopened.site_reads == 1 and reopened.site_hashes == 1 and reopened.party_reads == 1 and reopened.party_hashes == 1 and reopened.faction_scans == 1, "cold reopen fully validates each original Site/party exactly once"): return
	latest = reopened.latest_reads; scans = reopened.faction_scans
	if not check(reopened._recover_control().ok and reopened.latest_reads == latest and reopened.faction_scans == scans, "cold successful recovery becomes same-commit memo"): return
	# A different immutable Site path is a new source even if payload is equal.
	var next_relative: Variant = "generations/%020d_%d_%d.json" % [int(slot._marker.generation) + 1, coordinate.x, coordinate.y]
	var next_saved: Variant = slot._save_checked(data, coordinate, slot.folder.path_join(next_relative))
	if not check(next_saved.ok, "new generation Site uses original save and full readback"): return
	var next_sites: Variant = sites.duplicate(true)
	next_sites["0:0"] = {"path": next_relative, "sha256": FileAccess.get_sha256(slot.folder.path_join(next_relative))}
	reads = slot.site_reads; hashes = slot.site_hashes
	if not check(slot._publish(next_sites, slot.control, "", journey).ok and slot.site_reads == reads + 1 and slot.site_hashes == hashes + 1, "new immutable Site path cannot borrow old path summary; miss validates exactly once"): return
	if not check(slot._recover_control().ok, "new-source commit fully validates before negative cases"): return
	# Wrong recorded digest: real reader succeeds, final SHA refuses it; no memo
	# or source summary is published for this failed candidate.
	var before: PackedByteArray = var_to_bytes([slot.control, slot._marker])
	var bad_sites: Variant = next_sites.duplicate(true)
	bad_sites["0:0"].sha256 = "b".repeat(64)
	reads = slot.site_reads; hashes = slot.site_hashes
	var rejected: Variant = slot._publish(bad_sites, slot.control, "", journey)
	if not check(not rejected.ok and rejected.code == "CORRUPT_SAVE" and slot.site_reads == reads + 1 and slot.site_hashes == hashes + 1 and var_to_bytes([slot.control, slot._marker]) == before, "new recorded digest mismatch retains full validator, refuses publish and preserves live objects"): return
	if not check(not slot._faction_source_cache.has(slot._faction_site_key("b".repeat(64), coordinate, slot.folder.path_join(next_relative))), "failed digest validation is never cached"): return
	# A fully renamed NEW successor is corrupt semantically, not overwritten.
	# It must be detected despite the older successful commit memo.
	var generation: int = int(slot._marker.generation)
	var bad_record: Dictionary = slot._marker.duplicate(true)
	bad_record.generation = generation + 1
	var invalid_clock: Dictionary = bad_record.control.duplicate(true)
	invalid_clock.faction_registry.version = 99
	bad_record.control = {"encoding": "godot_var_v1", "value": Marshalls.raw_to_base64(var_to_bytes(invalid_clock))}
	var written: Variant = slot._write_new_document(slot.folder.path_join("commits/%020d.json" % (generation + 1)), bad_record)
	if not check(written.ok, "original write-once writer publishes deliberate invalid NEW successor fixture"): return
	live = slot.control
	var marker: Dictionary = slot._marker
	latest = slot.latest_reads
	var failed_read: Variant = slot._recover_control()
	if not check(not failed_read.ok and failed_read.code == "SAVE_VERSION" and slot.latest_reads == latest + 1 and is_same(slot.control, live) and is_same(slot._marker, marker), "new corrupt generation rejects and restores exact current control/marker objects"): return
	if not check(int(slot._recover_known_commit[slot.folder].generation) == generation, "failed successor never replaces validated generation memo"): return
	var retried: Variant = slot._recover_control()
	if not check(not retried.ok and slot.latest_reads == latest + 2 and int(slot._recover_known_commit[slot.folder].generation) == generation, "failed latest commit is not cached as success or skipped on retry"): return
	if not check(fault.read().is_empty() and Time.get_ticks_msec() <= deadline, "sticky first error and inherited unchanged 90-second deadline"): return
	print("REGION_FACTION_F1A_V3_PASS ", checks, " original immutable writer/recovery and consecutive publish source-I/O contracts; no runtime/performance inference")
	quit(0)
