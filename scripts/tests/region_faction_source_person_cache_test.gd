extends "res://scripts/tests/region_siege_cold_action_epoch_test.gd"

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest(): _finish(); return
	# Startup publication itself requires the original source-person projection.
	if not await _setup_action_world(): _finish(); return
	var coordinate: Vector2i = Vector2i.ZERO
	var entry: Dictionary = slot._marker.sites[slot._site_key(coordinate)]
	var path: String = slot.folder.path_join(str(entry.path))
	var checksum: String = str(entry.sha256)
	var key: String = slot._faction_site_key(checksum, coordinate, path)
	var loaded: Dictionary = slot._load_checked(path, coordinate)
	if not _check(loaded.ok, "real immutable initial publication source loads", loaded): _finish(); return
	var expected: Dictionary = slot.person_projection(loaded.data.site)
	if not _check(not expected.bodies.is_empty(), "person-cache regression covers actual saved bodies"): _finish(); return
	var original: PackedByteArray = var_to_bytes([slot.control, slot._marker, loaded.data.site])
	slot._faction_source_cache.erase(key)
	slot._faction_summary_digest_memo.erase(key)
	slot._person_source_cache.erase(key)
	var result: Dictionary = slot._faction_site_source(path, coordinate, checksum, true)
	if not _check(result.ok and slot._person_source_cache.has(key), "cold with_persons source read fills its original person memo", result): _finish(); return
	if not _check(var_to_bytes(slot._person_source_cache[key]) == var_to_bytes(expected), "cold memo is the real body's exact projection, including identities and aliases"): _finish(); return
	# A summary hit alone cannot satisfy a subsequent person-source request.
	slot._person_source_cache.erase(key)
	result = slot._faction_site_source(path, coordinate, checksum, true)
	if not _check(result.ok and slot._person_source_cache.has(key), "warm summary with missing person memo reloads the original source", result): _finish(); return
	if not _check(var_to_bytes(slot._person_source_cache[key]) == var_to_bytes(expected), "reloaded person memo retains the same actual identities"): _finish(); return
	result = slot._faction_site_source(path, coordinate, checksum, true)
	if not _check(result.ok and var_to_bytes(slot._person_source_cache[key]) == var_to_bytes(expected), "complete warm cache retains its original projection"): _finish(); return
	var scanned: Dictionary = slot._faction_scan(slot._marker.sites, slot.control, slot.region_travel_journey(), slot.control.faction_registry, [], false, true)
	if not _check(scanned.ok and not scanned.get("person_sources", []).is_empty(), "original publication scan with_persons consumes real nonempty projections", scanned): _finish(); return
	var bad_checksum: String = "0".repeat(64)
	var bad_key: String = slot._faction_site_key(bad_checksum, coordinate, path)
	var rejected: Dictionary = slot._faction_site_source(path, coordinate, bad_checksum, true)
	if not _check(not rejected.ok and not slot._person_source_cache.has(bad_key), "wrong immutable checksum cannot publish a person-source memo", rejected): _finish(); return
	if not _check(original == var_to_bytes([slot.control, slot._marker, loaded.data.site]) and FileAccess.get_sha256(path) == checksum, "source-person reads and rejection preserve control, marker, original body and saved bytes"): _finish(); return
	_finish()

func _finish(ok: bool = true, message: String = "") -> void:
	if finished: return
	print("CC153_PERSON_SOURCE_CACHE_", "FAILED" if failed or not ok else "PASS")
	super._finish(ok, message)
