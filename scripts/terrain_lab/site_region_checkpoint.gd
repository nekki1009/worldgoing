extends RefCounted
## Durable metadata for the original SiteStore payload. No body or simulation owner.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Clock = preload("res://scripts/region_lab/region_gameplay_clock.gd")
const PURPOSES := ["region_checkpoint", "region_barrier", "region_materialize", "region_dematerialize", "region_family"]
const MODES := ["live", "formula_active", "cold_exact", "materializing", "dematerializing", "committed-unbound"]
const FIELDS := ["purpose", "mode", "source_generation", "runtime_revision", "token", "game_seconds", "action_seconds", "fire_epoch", "fire_sequence", "interval_complete", "effects_complete", "mode_revision", "backend", "events", "endpoint_payload"]

static func integer(value: Variant, lower: int = 0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= lower and float(value) <= 2147483647.0 and float(value) == floorf(float(value))

static func time(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= 1.0e12

static func validate_context(value: Variant, expected: Dictionary = {}) -> Dictionary:
	if not value is Dictionary: return Runtime.fail("INVALID_REGION_CONTEXT")
	for field: String in FIELDS:
		if not value.has(field): return Runtime.fail("INVALID_REGION_CONTEXT", "missing " + field)
	if str(value.purpose) not in PURPOSES or str(value.mode) not in MODES or not value.token is String or str(value.token).is_empty() or str(value.token).length() > 256:
		return Runtime.fail("INVALID_REGION_CONTEXT")
	for field: String in ["source_generation", "runtime_revision", "fire_sequence", "mode_revision"]:
		if not integer(value[field]): return Runtime.fail("INVALID_REGION_CONTEXT", field)
	if not time(value.game_seconds) or not time(value.action_seconds) or not value.fire_epoch is String or str(value.fire_epoch).length() > 256 or value.backend != "gd":
		return Runtime.fail("REGION_BACKEND_UNADMITTED" if value.get("backend") != "gd" else "INVALID_REGION_CONTEXT")
	if not value.interval_complete is bool or not value.effects_complete is bool or not bool(value.interval_complete):
		return Runtime.fail("REGION_BARRIER_PENDING")
	if not value.events is Array or value.events.size() > 100000 or not value.endpoint_payload is Dictionary:
		return Runtime.fail("INVALID_REGION_CONTEXT")
	var seen := {}
	var sequences := {}
	var pending: Array = []
	var previous: Dictionary = {}
	for event: Variant in value.events:
		if not Clock.validate_event(event).ok or seen.has(event.id) or sequences.has(int(event.sequence)) or float(event.at) > float(value.game_seconds) or not previous.is_empty() and Clock.before(event, previous):
			return Runtime.fail("REGION_EVENT_PENDING")
		seen[event.id] = true
		sequences[int(event.sequence)] = true
		previous = event
		if event.status == "pending": pending.append(event)
	if bool(value.effects_complete) and not pending.is_empty(): return Runtime.fail("REGION_EFFECTS_PENDING")
	if not bool(value.effects_complete) and (value.purpose == "region_checkpoint" or pending.is_empty() and value.endpoint_payload.is_empty()): return Runtime.fail("INVALID_REGION_BARRIER")
	for field: String in expected:
		# Context is JSON metadata; its owner graph retains typed numbers. Compare
		# complete canonical values so an unchanged persisted event is accepted.
		if not value.has(field) or not supported(expected[field]) or JSON.stringify(_hash_numbers(value[field]), "", true, true) != JSON.stringify(_hash_numbers(expected[field]), "", true, true):
			return Runtime.fail("STALE_REGION_CONTEXT", field)
	if not supported(value): return Runtime.fail("INVALID_REGION_CONTEXT", "unsupported value")
	return Runtime.ok("", {"context": value.duplicate(true), "effects_pending": not bool(value.effects_complete), "pending_events": pending})

static func supported(value: Variant, depth: int = 0) -> bool:
	if depth > 48: return false
	if value == null or value is bool or value is String or value is StringName or value is int: return true
	if value is float: return is_finite(value)
	if value is Rect2 or value is Rect2i: return supported(value.position, depth + 1) and supported(value.size, depth + 1)
	if value is Vector2 or value is Vector2i: return is_finite(float(value.x)) and is_finite(float(value.y))
	if value is Vector3 or value is Vector3i: return is_finite(float(value.x)) and is_finite(float(value.y)) and is_finite(float(value.z))
	if value is Dictionary:
		if value.size() > 100000: return false
		for key: Variant in value:
			if not supported(key, depth + 1) or not supported(value[key], depth + 1): return false
		return true
	if value is Array or value is PackedByteArray or value is PackedInt32Array or value is PackedInt64Array or value is PackedFloat32Array or value is PackedFloat64Array or value is PackedStringArray or value is PackedVector2Array or value is PackedVector3Array:
		if value.size() > 1000000: return false
		for entry: Variant in value:
			if not supported(entry, depth + 1): return false
		return true
	return false

static func wire(value: Variant) -> Variant:
	if value is int: return {"@region_type": "int", "value": str(value)}
	if value is StringName: return {"@region_type": "StringName", "value": str(value)}
	if value is Dictionary:
		var entries: Array = []
		for key: Variant in value: entries.append([wire(key), wire(value[key])])
		return {"@region_type": "dict", "entries": entries}
	if value is Rect2 or value is Rect2i: return {"@region_type": "Rect2i" if value is Rect2i else "Rect2", "values": [value.position.x, value.position.y, value.size.x, value.size.y]}
	if value is Vector2: return {"@region_type": "Vector2", "values": [value.x, value.y]}
	if value is Vector2i: return {"@region_type": "Vector2i", "values": [value.x, value.y]}
	if value is Vector3: return {"@region_type": "Vector3", "values": [value.x, value.y, value.z]}
	if value is Vector3i: return {"@region_type": "Vector3i", "values": [value.x, value.y, value.z]}
	if value is Array:
		var entries: Array = []
		for entry: Variant in value: entries.append(wire(entry))
		return entries
	if value is PackedByteArray or value is PackedInt32Array or value is PackedInt64Array or value is PackedFloat32Array or value is PackedFloat64Array or value is PackedStringArray or value is PackedVector2Array or value is PackedVector3Array:
		var entries: Array = []
		for entry: Variant in value: entries.append(wire(entry))
		return {"@region_type": type_string(typeof(value)), "values": entries}
	return str(value) if value is StringName else value

static func valid_wire(value: Variant, depth: int = 0) -> bool:
	if depth > 48: return false
	if value is Dictionary:
		var kind := str(value.get("@region_type", ""))
		if kind == "int": return value.size() == 2 and value.get("value") is String and str(value.value).is_valid_int() and str(int(value.value)) == str(value.value)
		if kind == "StringName": return value.size() == 2 and value.get("value") is String
		if kind == "dict":
			if value.size() != 2 or not value.get("entries") is Array or value.entries.size() > 100000: return false
			var seen := {}
			for pair: Variant in value.entries:
				if not pair is Array or pair.size() != 2 or not valid_wire(pair[0], depth + 1) or not valid_wire(pair[1], depth + 1): return false
				var key: Variant = unwire(pair[0])
				if key == null or key is Array or key is Dictionary or seen.has(key): return false
				seen[key] = true
			return true
		if value.size() != 2 or not value.get("values") is Array: return false
		var entries: Array = value.values
		if kind in ["Vector2", "Vector2i", "Vector3", "Vector3i", "Rect2", "Rect2i"]:
			if entries.size() != (4 if kind in ["Rect2", "Rect2i"] else (2 if kind in ["Vector2", "Vector2i"] else 3)): return false
			for entry: Variant in entries:
				if not (entry is int or entry is float) or not is_finite(float(entry)): return false
				if kind.ends_with("i") and (float(entry) != floorf(float(entry)) or absf(float(entry)) > 2147483647.0): return false
			return true
		if kind not in ["PackedByteArray", "PackedInt32Array", "PackedInt64Array", "PackedFloat32Array", "PackedFloat64Array", "PackedStringArray", "PackedVector2Array", "PackedVector3Array"] or entries.size() > 1000000: return false
		for entry: Variant in entries:
			if not valid_wire(entry, depth + 1): return false
			if kind == "PackedStringArray" and not entry is String: return false
			if kind in ["PackedByteArray", "PackedInt32Array", "PackedInt64Array"] and not unwire(entry) is int: return false
			if kind == "PackedInt32Array" and (int(unwire(entry)) < -2147483648 or int(unwire(entry)) > 2147483647): return false
			if kind == "PackedByteArray" and (int(unwire(entry)) < 0 or int(unwire(entry)) > 255): return false
			if kind in ["PackedFloat32Array", "PackedFloat64Array"] and not (entry is int or entry is float): return false
			if kind == "PackedVector2Array" and not unwire(entry) is Vector2 or kind == "PackedVector3Array" and not unwire(entry) is Vector3: return false
		return true
	if value is Array:
		if value.size() > 1000000: return false
		for entry: Variant in value:
			if not valid_wire(entry, depth + 1): return false
		return true
	return value == null or value is bool or value is String or value is int or value is float and is_finite(value)

static func unwire(value: Variant) -> Variant:
	if value is Array:
		var entries: Array = []
		for entry: Variant in value: entries.append(unwire(entry))
		return entries
	if not value is Dictionary: return value
	var kind := str(value["@region_type"])
	if kind == "int": return int(value.value)
	if kind == "StringName": return StringName(value.value)
	if kind == "dict":
		var entries := {}
		for pair: Array in value.entries: entries[unwire(pair[0])] = unwire(pair[1])
		return entries
	var entries: Array = unwire(value.values)
	match kind:
		"Rect2": return Rect2(Vector2(entries[0], entries[1]), Vector2(entries[2], entries[3]))
		"Rect2i": return Rect2i(Vector2i(int(entries[0]), int(entries[1])), Vector2i(int(entries[2]), int(entries[3])))
		"Vector2": return Vector2(entries[0], entries[1])
		"Vector2i": return Vector2i(int(entries[0]), int(entries[1]))
		"Vector3": return Vector3(entries[0], entries[1], entries[2])
		"Vector3i": return Vector3i(int(entries[0]), int(entries[1]), int(entries[2]))
		"PackedByteArray": return PackedByteArray(entries)
		"PackedInt32Array": return PackedInt32Array(entries)
		"PackedInt64Array": return PackedInt64Array(entries)
		"PackedFloat32Array": return PackedFloat32Array(entries)
		"PackedFloat64Array": return PackedFloat64Array(entries)
		"PackedStringArray": return PackedStringArray(entries)
		"PackedVector2Array": return PackedVector2Array(entries)
		"PackedVector3Array": return PackedVector3Array(entries)
	return null

static func state_hash(state: Dictionary) -> String:
	var body := state.duplicate(true)
	body.erase("region_snapshot")
	body.erase("water_links")
	body.erase("water_status")
	body.erase("notices")
	return JSON.stringify(_hash_canonical(body), "", true, true).sha256_text()

## Pre-2026-10-09 formula. Only used to admit region_snapshot hashes already
## written by older builds; every new hash uses state_hash().
static func _snapshot_hash_matches(state: Dictionary, stored: String) -> bool:
	return stored == state_hash(state) or stored == legacy_state_hash(state)

static func legacy_state_hash(state: Dictionary) -> String:
	var body := state.duplicate(true)
	body.erase("region_snapshot")
	body.erase("water_links")
	body.erase("water_status")
	body.erase("notices")
	return JSON.stringify(_hash_numbers(body), "", true, true).sha256_text()

## Godot's JSON parser does not return the identical double for every
## 17-digit value it wrote (e.g. 0.10999999999999999 reloads as 0.11), so a
## saved body can never re-hash equal at full precision. Integral values below
## 1e15 hash exactly; other finite numbers hash at 12 significant digits, far
## coarser than the round-trip error and far finer than any game rule.
static func _hash_number(value: float) -> String:
	if is_nan(value): return "nan"
	if is_inf(value): return "inf" if value > 0.0 else "-inf"
	if value == floorf(value) and absf(value) < 1e15: return "i%d" % int(value)
	var exponent := floori(log(absf(value)) / log(10.0))
	var mantissa := roundf(value / pow(10.0, float(exponent - 11)))
	return "f%de%d" % [int(mantissa), exponent - 11]

static func _hash_canonical(value: Variant) -> Variant:
	if value is int or value is float: return _hash_number(float(value))
	if value is Dictionary:
		var normalized := {}
		for key: Variant in value: normalized[str(key)] = _hash_canonical(value[key])
		return normalized
	if value is Array or value is PackedInt32Array or value is PackedInt64Array or value is PackedFloat32Array or value is PackedFloat64Array or value is PackedStringArray or value is PackedByteArray:
		var normalized: Array = []
		for entry: Variant in value: normalized.append(_hash_canonical(entry))
		return normalized
	return value

static func make(state: Dictionary, context: Dictionary, owners: Dictionary) -> Dictionary:
	var checked := validate_context(context)
	if not checked.ok: return checked
	if not supported(owners): return Runtime.fail("INVALID_REGION_OWNERS")
	return Runtime.ok("", {"snapshot": {"version": 1, "context": checked.context, "owners": wire(owners), "state_hash": state_hash(state)}})

static func validate(state: Dictionary, snapshot: Variant, expected: Dictionary = {}) -> Dictionary:
	if not snapshot is Dictionary or snapshot.size() != 4 or not integer(snapshot.get("version"), 1) or int(snapshot.version) != 1 or not snapshot.get("state_hash") is String or not _snapshot_hash_matches(state, str(snapshot.state_hash)):
		return _snapshot_failure(state, snapshot)
	var checked := validate_context(snapshot.get("context"), expected)
	if not checked.ok: return checked
	if not valid_wire(snapshot.get("owners")): return Runtime.fail("INVALID_REGION_OWNERS")
	var owners: Variant = unwire(snapshot.owners)
	if not owners is Dictionary: return Runtime.fail("INVALID_REGION_OWNERS")
	return Runtime.ok("", {"context": checked.context, "owners": owners, "snapshot": snapshot.duplicate(true)})


static func _hash_numbers(value: Variant) -> Variant:
	if value is int or value is float: return float(value)
	if value is Dictionary:
		var normalized := {}
		for key: Variant in value: normalized[str(key)] = _hash_numbers(value[key])
		return normalized
	if value is Array or value is PackedInt32Array or value is PackedInt64Array or value is PackedFloat32Array or value is PackedFloat64Array or value is PackedStringArray or value is PackedByteArray:
		var normalized: Array = []
		for entry: Variant in value: normalized.append(_hash_numbers(entry))
		return normalized
	return value

static func _snapshot_failure(state: Dictionary, snapshot: Variant) -> Dictionary:
	var result := Runtime.fail("CORRUPT_REGION_SNAPSHOT")
	var computed := state_hash(state)
	if not snapshot is Dictionary: result["check"] = "type"
	elif snapshot.size() != 4: result["check"] = "size"
	elif not integer(snapshot.get("version"), 1) or int(snapshot.version) != 1: result["check"] = "version"
	else: result["check"] = "hash"
	result["stored_hash"] = str(snapshot.get("state_hash", "")) if snapshot is Dictionary else ""
	result["computed_hash"] = computed
	if snapshot is Dictionary: result["snapshot_size"] = snapshot.size()
	return result
