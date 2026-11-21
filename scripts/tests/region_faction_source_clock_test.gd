extends SceneTree
const Slot = preload("res://scripts/region_lab/region_save_slot.gd")
var failed: bool = false
func _check(ok: bool, message: String) -> bool:
	if ok: return true
	failed = true
	push_error(message)
	quit(1)
	return false

func _validate(at: Variant, now: float) -> Dictionary:
	var registry: Dictionary = {"version": 1, "revision": 0, "next_faction_id": 1, "migration_complete": true, "entries": {},
		"coverage": {"complete": false, "counts": null, "sources": [{"owner": "original", "source_generation": 1, "runtime_revision": 0, "checksum": "a".repeat(64), "as_of_game_seconds": at, "complete": true}]}}
	return RegionFactionQuery.validate(registry, now)

func _native_receipt_cases(slot: RegionSaveSlot) -> bool:
	var now: float = 120.05999999999999
	var bits: PackedByteArray = PackedFloat64Array([now]).to_byte_array()
	bits.encode_u64(0, bits.decode_u64(0) + 1)
	var projected: float = bits.decode_double(0)
	var action: float = 2.0010000000000026
	var clock: Dictionary = {"logical_game_seconds": now, "fire_clock": {"epoch": "original", "index": {"original": {"sequence": 61, "game_seconds": projected, "action_seconds": action}}}}
	var native: Dictionary = {"owner": "original", "at": now, "runtime_revision": 61}
	var kept: Dictionary = slot._faction_remember("074h:native", native)
	var warmed: Dictionary = slot._faction_cached("074h:native")
	if not _check(kept.ok and warmed.ok and slot._faction_source_game_seconds(warmed.summary, clock) == now,
		"Digest-checked actual capture time stays exact even when the cold index is a JSON projection"): return false
	var loaded: Dictionary = {"owner": "original", "at": projected, "runtime_revision": 61, "source_clock": {"fire_epoch": "original", "fire_sequence": 61, "game_seconds": projected, "action_seconds": JSON.parse_string(JSON.stringify(action, "", false, true))}}
	# Use the exact Godot codec identity that a reopened source must match.
	loaded.at = JSON.parse_string(JSON.stringify(now, "", false, true))
	loaded.source_clock.game_seconds = loaded.at
	var receipt: Dictionary = {"owner": "original", "source_generation": 5, "runtime_revision": 61, "checksum": "a".repeat(64), "as_of_game_seconds": now, "complete": true}
	var previous: Dictionary = {"coverage": {"sources": [receipt]}}
	var before: PackedByteArray = var_to_bytes([loaded, previous, clock])
	var resolved: Variant = slot._faction_source_receipt_seconds(loaded, "a".repeat(64), 5, previous, clock)
	if not _check(PackedFloat64Array([float(resolved)]).to_byte_array() == PackedFloat64Array([now]).to_byte_array()
		and _validate(resolved, now).ok and before == var_to_bytes([loaded, previous, clock]),
		"Same immutable accepted receipt survives fresh reopen without clock or source mutation"): return false
	for field: String in ["owner", "checksum", "source_generation", "runtime_revision"]:
		var changed: Dictionary = previous.duplicate(true)
		changed.coverage.sources[0][field] = "other" if field in ["owner", "checksum"] else 6
		if not _check(slot._faction_source_receipt_seconds(loaded, "a".repeat(64), 5, changed, clock) == slot._faction_source_game_seconds(loaded, clock),
			"Changed immutable receipt identity cannot lend its accepted clock"): return false
	var future: Dictionary = previous.duplicate(true)
	future.coverage.sources[0].as_of_game_seconds = projected
	var future_value: Variant = slot._faction_source_receipt_seconds({"owner": "original", "at": projected, "runtime_revision": 61}, "a".repeat(64), 5, future, clock)
	return _check(not _validate(future_value, now).ok, "A matched genuinely future accepted receipt remains future and is rejected")

func _departure_source_cases(slot: RegionSaveSlot) -> bool:
	var now: float = 2129.1999999999816
	var action: float = now / 60.0
	var data: TerrainData = TerrainData.new()
	# The origin has no old region_snapshot after extraction; its paid receipt survives.
	data.site = {"id": "original", "minute": 35, "phase": 0.486666666666678,
		"fire_settlement": {"version": 1, "epoch": "departure", "sequence": 61,
			"game_seconds": JSON.parse_string(JSON.stringify(now, "", false, true)),
			"action_seconds": JSON.parse_string(JSON.stringify(action, "", false, true))}}
	var before: PackedByteArray = var_to_bytes(data.site)
	var source: Dictionary = slot._faction_site_summary(data)
	if not _check(source.ok and source.summary.runtime_revision == null
		and float(source.summary.at) == float(data.site.fire_settlement.game_seconds)
		and float(Slot._site_seconds(data)) > now, "Departure summary uses its actual paid receipt instead of the future minute/phase projection"): return false
	var clock: Dictionary = {"logical_game_seconds": now, "fire_clock": {"epoch": "departure", "index": {
		"original": {"sequence": 61, "game_seconds": now, "action_seconds": action}}}}
	var resolved: Variant = slot._faction_source_game_seconds(source.summary, clock)
	if not _check(PackedFloat64Array([float(resolved)]).to_byte_array() == PackedFloat64Array([now]).to_byte_array()
		and _validate(resolved, now).ok and before == var_to_bytes(data.site), "Departure resolves the identical indexed binary endpoint without mutating its original body"): return false
	for field: String in ["fire_epoch", "fire_sequence", "game_seconds", "action_seconds"]:
		var wrong: Dictionary = source.summary.duplicate(true)
		wrong.source_clock[field] = "other" if field == "fire_epoch" else float(wrong.source_clock[field]) + 1.0
		if not _check(slot._faction_source_game_seconds(wrong, clock) == wrong.at, "A mismatched departure source cannot borrow the indexed endpoint"): return false
	data.site["region_snapshot"] = {"context": {"game_seconds": 2000.0, "action_seconds": 20.0,
		"fire_epoch": "prior", "fire_sequence": 60, "runtime_revision": 7}}
	source = slot._faction_site_summary(data)
	if not _check(source.ok and source.summary.at == 2000.0 and source.summary.runtime_revision == 7
		and source.summary.source_clock.fire_epoch == "prior", "Existing full-body context retains precedence over the fire receipt"): return false
	data.site.erase("region_snapshot")
	data.site.erase("fire_settlement")
	source = slot._faction_site_summary(data)
	return _check(source.ok and source.summary.at == Slot._site_seconds(data) and not source.summary.has("source_clock"), "Legacy source without either original clock retains its historical projection")

func _initialize() -> void:
	var slot: RegionSaveSlot = Slot.new()
	if not _native_receipt_cases(slot): return
	if not _departure_source_cases(slot): return
	for now: float in [104.0, 120.05999999999999, 1104.0000000000023]:
		var action: float = now / 60.0
		var stamp: Dictionary = {"fire_epoch": "original", "fire_sequence": 61,
			"game_seconds": JSON.parse_string(JSON.stringify(now, "", false, true)),
			"action_seconds": JSON.parse_string(JSON.stringify(action, "", false, true))}
		var clock: Dictionary = {"logical_game_seconds": now, "fire_clock": {"epoch": "original", "index": {"original": {"sequence": 61, "game_seconds": now, "action_seconds": action}}}}
		var summary: Dictionary = {"owner": "original", "at": stamp.game_seconds, "source_clock": stamp}
		var cache_key: String = "074g:" + str(now)
		var immutable_before: PackedByteArray = var_to_bytes(summary)
		var remembered: Dictionary = slot._faction_remember(cache_key, summary)
		var warmed: Dictionary = slot._faction_cached(cache_key)
		var record: Dictionary = {"key": cache_key, "serial": SiteStore.faction_summary_serial(), "metadata": {"source": cache_key}}
		slot._faction_static_site_remember(record, summary)
		var shared: Dictionary = slot._faction_static_site_cached(record)
		if not _check(remembered.ok and warmed.ok and shared.ok, "Original instance and static digest-checked summary caches hit"): return
		for cached: Dictionary in [summary, warmed.summary, shared.summary]:
			if not _check(slot._faction_source_game_seconds(cached, clock) == now, "Cold/warm/shared immutable summary resolves the same original endpoint"): return
			var later: Dictionary = clock.duplicate(true)
			later.logical_game_seconds = now + 60.0
			later.fire_clock.index.original.sequence = 62
			later.fire_clock.index.original.game_seconds = now + 60.0
			if not _check(slot._faction_source_game_seconds(cached, later) == summary.at, "Same cached source under a later control endpoint stays historical"): return
			if not _check(var_to_bytes(cached) == immutable_before, "Resolving a clock never caches a control-dependent derived timestamp"): return
		slot._faction_static_site_drop(cache_key)
		var resolved: Variant = slot._faction_source_game_seconds(summary, clock)
		if not _check(PackedFloat64Array([float(resolved)]).to_byte_array() == PackedFloat64Array([now]).to_byte_array()
			and _validate(resolved, now).ok, "Matched original endpoint uses exactly the Slot index binary clock"): return
		clock.fire_clock.index.original.sequence = 62
		if not _check(slot._faction_source_game_seconds(summary, clock) == summary.at, "An older source retains its captured historical time"): return
		clock.fire_clock.index.original.sequence = 61
		stamp.fire_epoch = "other"
		if not _check(slot._faction_source_game_seconds(summary, clock) == summary.at, "A different original epoch cannot borrow the current clock"): return
		stamp.fire_epoch = "original"
		for field: String in ["game_seconds", "action_seconds"]:
			var prior: Variant = stamp[field]
			stamp[field] = float(prior) + 1.0
			if not _check(slot._faction_source_game_seconds(summary, clock) == summary.at, "Either mismatched timestamp prevents indexed clock substitution"): return
			stamp[field] = prior
		var bits: PackedByteArray = PackedFloat64Array([now]).to_byte_array()
		bits.encode_u64(0, bits.decode_u64(0) + 1)
		var future: float = bits.decode_double(0)
		if not _check(not _validate(future, now).ok, "Strict validator rejects even one future ULP"): return
		var future_clock: Dictionary = clock.duplicate(true)
		future_clock.fire_clock.index.original.game_seconds = future
		var future_summary: Dictionary = summary.duplicate(true)
		future_summary.at = JSON.parse_string(JSON.stringify(future, "", false, true))
		future_summary.source_clock.game_seconds = future_summary.at
		var decoded_future: Variant = slot._faction_source_game_seconds(future_summary, future_clock)
		if not _check(PackedFloat64Array([float(decoded_future)]).to_byte_array() == bits and not _validate(decoded_future, now).ok,
			"A fully matched future indexed endpoint survives resolution and is strictly rejected at now"): return
		stamp.game_seconds = future
		summary.at = future
		if future != JSON.parse_string(JSON.stringify(now, "", false, true)):
			if not _check(slot._faction_source_game_seconds(summary, clock) == future and not _validate(future, now).ok,
				"A forged future stamp is not clamped or overwritten with now"): return
	if not _check(slot._faction_source_game_seconds({"owner": "legacy", "at": 3.0}, {}) == 3.0, "Legacy source time is unchanged"): return
	print("REGION_FACTION_SOURCE_CLOCK_PASS: original indexed endpoint; immutable source stamp; strict future ULP")
	quit(0)
