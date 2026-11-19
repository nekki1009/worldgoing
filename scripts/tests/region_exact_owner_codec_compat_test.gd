extends SceneTree
const Codec = preload("res://scripts/terrain_lab/site_region_owner_snapshot.gd")
const Checkpoint = preload("res://scripts/terrain_lab/site_region_checkpoint.gd")
const Battle = preload("res://scripts/region_lab/region_gameplay_battle.gd")
var failed: bool = false
var checks: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("REGION_EXACT_OWNER_CODEC_COMPAT_FAIL " + label)

func context() -> Dictionary:
	return {"purpose": "region_checkpoint", "mode": "cold_exact", "source_generation": 13,
		"runtime_revision": 1824, "token": "exact-owner-codec", "game_seconds": 1806.3045871559664,
		"action_seconds": 28.855076452599985, "fire_epoch": "fire:test", "fire_sequence": 916,
		"interval_complete": true, "effects_complete": true, "mode_revision": 0, "backend": "gd", "events": [], "endpoint_payload": {}}

func _initialize() -> void:
	var value: float = "00237f574ae6ba3f".hex_decode().decode_double(0)
	var next_value: float = "01237f574ae6ba3f".hex_decode().decode_double(0)
	var owner: Node = Node.new()
	var stock: Dictionary = {"grain": 19}
	var references: Dictionary = {"owner": owner, "stock": stock}
	var job: Dictionary = {"elapsed": value, "owner": owner, "stock": stock}
	var roots: Dictionary = {"controller": {"_settlement_elapsed": value}, "first": job, "second": job,
		"packed": PackedFloat64Array([value, next_value, -0.0]), "typed_key": {&"flag": true}, "large_int": 9007199254740993}
	var before: PackedByteArray = var_to_bytes([stock, value])
	var captured: Dictionary = Codec.capture(roots, references, context())
	check(captured.ok and captured.get("state", {}).get("version") == 2, "new exact atom writer uses version2")
	if not captured.ok: owner.free(); quit(1); return
	var made: Dictionary = Checkpoint.make({"id": "site:A", "inventory": {"grain": 19}}, context(), {"scene": captured["state"]})
	check(made.ok, "actual RegionCheckpoint save settling accepts exact graph")
	if not made.ok: owner.free(); quit(1); return
	var json_snapshot: Variant = JSON.parse_string(JSON.stringify(made["snapshot"], "", true, true))
	var admitted: Dictionary = Checkpoint.validate(made["state"], json_snapshot, {"source_generation": 13})
	check(admitted.ok, "original checksum/context admission remains mandatory")
	if not admitted.ok: owner.free(); quit(1); return
	var restored: Dictionary = Codec.prepare_restore(admitted["owners"]["scene"], references, {"source_generation": 13})
	check(restored.ok, "JSON-persisted version2 prepares through original references")
	if restored.ok:
		var actual: Dictionary = restored["roots"]
		check(var_to_bytes(actual["controller"]["_settlement_elapsed"]) == var_to_bytes(value), "actual failing elapsed double survives save and restore exactly")
		check(var_to_bytes(actual["packed"]) == var_to_bytes(roots["packed"]), "packed double values and signed zero retain exact typed bytes")
		check(actual["large_int"] is int and actual["large_int"] == 9007199254740993, "integer above double precision is never coerced")
		check(actual["typed_key"].keys()[0] is StringName, "StringName key type remains exact")
		check(is_same(actual["first"], actual["second"]) and actual["first"]["owner"] == owner and is_same(actual["first"]["stock"], stock), "all original shared graph and reference aliases survive")
	var peek: Dictionary = Codec.peek_values(admitted["owners"]["scene"], "controller")
	check(peek.ok and var_to_bytes(peek["value"]["_settlement_elapsed"]) == var_to_bytes(value), "pure bind peek validates exact atom")
	var symbolic: Dictionary = Codec.validate_for_bind(admitted["owners"]["scene"], func(key: String, kind: int) -> bool: return key == "owner" and kind == TYPE_OBJECT or key == "stock" and kind == TYPE_DICTIONARY)
	check(symbolic.ok, "original symbolic bind validator accepts registered references only")
	if symbolic.ok:
		var rebound: Dictionary = Codec.capture_bind_roots(symbolic["roots"], context())
		var positive: Dictionary = Codec.prepare_restore(rebound["state"], references) if rebound.ok else rebound
		check(positive.ok and var_to_bytes(positive["roots"]["controller"]["_settlement_elapsed"]) == var_to_bytes(value), "symbolic preflight/recapture keeps the exact persisted value")
	check(not Codec.prepare_restore(admitted["owners"]["scene"], {}, {}).ok, "missing original reference still rejects")
	check(not Codec.prepare_restore(admitted["owners"]["scene"], references, {"source_generation": 14}).ok, "wrong generation still rejects before mutation")
	check(before == var_to_bytes([stock, value]), "codec does not consume original stock or change live values")
	var legacy: Dictionary = {"version": 1, "context": context(), "root": {"kind": "node", "index": 0},
		"nodes": [{"kind": "dictionary", "entries": [[{"kind": "value", "wire": "elapsed"}, {"kind": "value", "wire": 0.625}]]}]}
	var legacy_read: Dictionary = Codec.prepare_restore(legacy, {})
	check(legacy_read.ok and legacy_read["roots"]["elapsed"] == 0.625, "unchanged legacy v1 wire remains readable")
	var mislabeled: Dictionary = captured["state"].duplicate(true)
	mislabeled["version"] = 1
	check(not Codec.prepare_restore(mislabeled, references).ok, "v1 cannot smuggle v2 atom descriptors")
	var bad: Dictionary = {"kind": "atom", "bytes": Marshalls.raw_to_base64(var_to_bytes({"surrogate": true}))}
	check(not Codec._valid_atom(bad), "atom cannot replace graph aliases with a container payload")
	check(Battle._siege_hash({"holder": "person:4", "items": ["a", "b"]}) == Battle._siege_hash({"items": ["a", "b"], "holder": "person:4"}), "new typed digest is independent of dictionary insertion order")
	check(Battle._siege_hash({"n": 1}) != Battle._siege_hash({"n": 1.0}), "typed integer versus float digest remains distinct")
	check(Battle._siege_hash({"elapsed": value}) != Battle._siege_hash({"elapsed": next_value}), "one ULP remains a digest difference")
	_metadata_checks(value, next_value)
	owner.free()
	print("REGION_EXACT_OWNER_CODEC_COMPAT_", "FAILED" if failed else "PASS", " checks=", checks)
	quit(1 if failed else 0)

func _metadata_checks(value: float, next_value: float) -> void:
	var metadata: Dictionary = {"version": 2, "center_id": "center", "defender_faction": 2, "attacker_faction": 1,
		"phase": "siege", "source": {"owner": "site:A", "generation": 13, "runtime_revision": 1824,
		"game_seconds": 1806.3045871559664, "action_seconds": 28.855076452599985, "fire_epoch": "fire:test", "fire_sequence": 916,
		"navigation_revision": 1, "environment_revision": 1}, "bodies": {},
		"structures": {"center": {"kind": "settlement_center", "owner_faction": 2, "sha256": "a".repeat(64), "parts": {}}},
		"vehicles": {}, "flights": {}, "work": {}, "routes": {}, "arrivals": {},
		"capture": {"sample": {"owner": 2, "attacker": -1, "leader": -1}, "fall_sha256": "b".repeat(64), "elapsed_action": value, "unconsumed_game_seconds": 0.0},
		"source_sha256": "", "resolution": "original_exact_gd"}
	metadata["source_sha256"] = Battle._siege_source_hash(metadata)
	check(Battle.validate_siege_metadata(metadata).ok, "full new metadata validates every field and its typed digest")
	var changed: Dictionary = metadata.duplicate(true)
	changed["capture"]["elapsed_action"] = next_value
	check(not Battle.validate_siege_metadata(changed).ok, "changed elapsed cannot borrow a selected source digest")
	var legacy: Dictionary = metadata.duplicate(true)
	legacy["version"] = 1
	legacy["source_sha256"] = Battle._siege_source_hash(legacy)
	var fields: Dictionary = {}
	for field: String in Battle.SIEGE_FIELDS:
		if field != "source_sha256": fields[field] = legacy[field]
	check(legacy["source_sha256"] == Battle._siege_legacy_hash(fields) and Battle.validate_siege_metadata(legacy).ok, "legacy version1 retains exact original hash algorithm")
	legacy["capture"]["elapsed_action"] = next_value
	check(not Battle.validate_siege_metadata(legacy).ok, "legacy digest tampering remains rejected")
	metadata["version"] = 3
	check(not Battle.validate_siege_metadata(metadata).ok, "unknown future metadata schema still rejects")
