extends SceneTree
const Checkpoint = preload("res://scripts/terrain_lab/site_region_checkpoint.gd")
var checks := 0
var failed := false

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("SITE_REGION_SNAPSHOT_JSON_WRITE_FAIL: " + message)

func context() -> Dictionary:
	return {"purpose": "region_checkpoint", "mode": "live", "source_generation": 3,
		"runtime_revision": 4, "token": "json-write:3:4", "game_seconds": 120.0, "action_seconds": 2.0,
		"fire_epoch": "fire:3", "fire_sequence": 0, "interval_complete": true, "effects_complete": true,
		"mode_revision": 6, "backend": "gd", "events": [], "endpoint_payload": {}}

func _initialize() -> void:
	# Little-endian raw binary64: GDScript decimal literals may erase the defect.
	var fixtures: Array[String] = ["ffffffffffffef3f", "010000000000f03f", "ffffffffffffff3f", "ffffffffffff2340",
		"10ea2d819997713d", "11ea2d819997713d", "12ea2d819997713d", "ffff3326f56b0c43",
		"00003426f56b0c43", "01003426f56b0c43", "f068e388b5f8e43e", "f268e388b5f8e43e",
		"ffffffffffffefbf", "000000e0e2526e3f", "edffffdfe2526e3f", "d6ffffdfe2526e3f"]
	for hex: String in fixtures:
		var value: float = hex.hex_decode().decode_double(0)
		var typed_ints: Array[int] = [1, 2, 3]
		var typed_floats: Array[float] = [value, 0.5]
		var state: Dictionary = {"id": "site:A", "minute": 2, "armies": [{"units": [{"age": value}]}],
			"fire_settlement": {"action_seconds": value}, "fire_transport": {"action_cursor": value},
			"nested": [value, {"values": typed_floats}], "int_keys": {17: value},
			"typed_ints": typed_ints, "packed": PackedFloat64Array([value]), "cell": Vector2i(2, 3)}
		var owners: Dictionary = {"scene": {"nodes": [{"at": value}], "person": {17: value}}}
		var stamp: Dictionary = context()
		var before: PackedByteArray = var_to_bytes(state)
		var owners_before: PackedByteArray = var_to_bytes(owners)
		var stamp_before: PackedByteArray = var_to_bytes(stamp)
		var made: Dictionary = Checkpoint.make(state, stamp, owners)
		check(made.ok, hex + " writer produces canonical detached state")
		if not made.ok: continue
		check(var_to_bytes(state) == before and var_to_bytes(owners) == owners_before and var_to_bytes(stamp) == stamp_before,
			hex + " capture leaves original state, graph and clock bytes untouched")
		check(made.state.minute is int and made.state.int_keys.has(17) and not made.state.int_keys.has("17"),
			hex + " detached state retains integer values and keys")
		check(made.state.typed_ints.get_typed_builtin() == TYPE_INT and made.state.nested[1].values.get_typed_builtin() == TYPE_FLOAT
			and made.state.packed is PackedFloat64Array and made.state.cell is Vector2i,
			hex + " capture retains typed arrays, packed values and vector types")
		check(Checkpoint.wire(owners) == made.snapshot.owners and made.snapshot.context == stamp,
			hex + " metadata preserves authoritative owner capture and context")
		var persisted: Dictionary = made.state
		persisted["region_snapshot"] = made.snapshot
		check(Checkpoint.validate(persisted, made.snapshot).ok, hex + " capture-only state authenticates")
		# Same ordinary payload transport and flags as SiteStore.save, not wire JSON.
		var payload: Dictionary = {"format": 1, "state": persisted}
		for round_index: int in range(3):
			var body: String = JSON.stringify(payload, "", true, true)
			payload = JSON.parse_string(body)
			check(Checkpoint.state_hash(payload.state) == str(made.snapshot.state_hash),
				hex + " ordinary Store JSON hash equals written hash round " + str(round_index))
			check(Checkpoint.validate(payload.state, payload.state.region_snapshot).ok,
				hex + " ordinary JSON read validates round " + str(round_index))
		var tampered: Dictionary = payload.state.duplicate(true)
		tampered.armies[0].units[0].age = float(tampered.armies[0].units[0].age) + 1000.0
		var rejected: Dictionary = Checkpoint.validate(tampered, tampered.region_snapshot)
		check(not rejected.ok and rejected.code == "CORRUPT_REGION_SNAPSHOT" and rejected.get("check") == "hash",
			hex + " changed body remains rejected by unchanged hash guard")
	var intact: Dictionary = {"id": "site:old", "minute": 2, "values": [0.5, 8.0]}
	for old_hash: String in [Checkpoint.state_hash(intact), Checkpoint.legacy_state_hash(intact)]:
		var old: Dictionary = {"version": 1, "context": context(), "owners": Checkpoint.wire({}), "state_hash": old_hash}
		var loaded: Dictionary = JSON.parse_string(JSON.stringify({"state": intact, "snapshot": old}, "", true, true))
		check(Checkpoint.validate(loaded.state, loaded.snapshot).ok, "intact historical hash remains readable " + old_hash)
	var broken: Dictionary = {"age": "ffffffffffffef3f".hex_decode().decode_double(0)}
	var old_broken: Dictionary = {"version": 1, "context": context(), "owners": Checkpoint.wire({}), "state_hash": Checkpoint.state_hash(broken)}
	check(float(broken.age) < 1.0 and Checkpoint._hash_number(float(broken.age)) != Checkpoint._hash_number(1.0),
		"raw fixture exposes original f-versus-i boundary")
	var loaded_broken: Dictionary = JSON.parse_string(JSON.stringify({"state": broken, "snapshot": old_broken}, "", true, true))
	check(not Checkpoint.validate(loaded_broken.state, loaded_broken.snapshot).ok,
		"historically unreadable boundary save remains rejected; no alternate hash admission")
	print("SITE_REGION_SNAPSHOT_JSON_WRITE_", "FAILED" if failed else "PASS", " checks=", checks)
	quit(1 if failed else 0)
