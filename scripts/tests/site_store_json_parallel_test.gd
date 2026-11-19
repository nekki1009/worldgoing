extends SceneTree
## Original Store JSON bytes and native eligibility.
const Store = preload("res://scripts/terrain_lab/site_store.gd")
var kernel: RefCounted
var failed := false
var checks := 0

class Observer extends RefCounted:
	var label := ""
	var calls := 0
	var main := true
	var trace: Array = []
	var state: Dictionary
	func _to_string() -> String:
		calls += 1
		main = main and Thread.is_main_thread()
		trace.append(label)
		state["callback_value"] = 7
		return "original callback " + label

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	failed = failed or not ok
	print("STORE JSON ", "OK: " if ok else "FAIL: ", label)

func _payload(value: Variant) -> Dictionary:
	return {"format": 3, "state": {"crowd": {}, "armies": [{"units": [value]}, {"units": [value]}]}, "parameters": {}}

func _guards(value: Variant, generic: bool, json: bool, label: String) -> void:
	_check(bool(kernel.contains_unsupported(value)) == generic and bool(kernel.contains_json_unsupported(value)) == json, label)

func _parity(payload: Dictionary, label: String) -> void:
	var before := var_to_bytes(payload)
	var expected := JSON.stringify(payload, "", false, true)
	var actual := Store._stringify_crowd_payload(payload)
	_check(expected.to_utf8_buffer() == actual.to_utf8_buffer() and before == var_to_bytes(payload), label)

func _chain(depth: int) -> Variant:
	var value: Variant = 1.0
	for index in range(depth): value = [value]
	return value

func _cow(values: Array, use_assign: bool) -> void:
	var peer: Array = values.duplicate(false)
	if use_assign: peer.assign(values)
	var alias: Array = values
	var payload := _payload(values)
	payload.state["nested"] = [values, {"inner": values}]
	payload.parameters[values] = "array key"
	var before := var_to_bytes([payload, peer])
	var builtin := values.get_typed_builtin()
	# Candidate first, while the distinct retained peer is still alive.
	var actual := Store._stringify_crowd_payload(payload)
	var expected := JSON.stringify(payload, "", false, true)
	_check(actual.to_utf8_buffer() == expected.to_utf8_buffer() and before == var_to_bytes([payload, peer]), "retained duplicate/assign exact JSON and values")
	_check(is_same(alias, values) and not is_same(peer, values) and is_same(payload.state.armies[0].units[0], values) and is_same(payload.state.armies[1].units[0], values) and is_same(payload.state.nested[0], values), "retained peer and original alias identities")
	_check(values.get_typed_builtin() == builtin and peer.get_typed_builtin() == builtin and not values.is_read_only() and not peer.is_read_only(), "retained typed metadata and flags")
	_guards(payload, false, false, "mutable retained array remains eligible")
	var first: Variant = values[0]
	peer[0] = 91
	_check(values[0] == first and alias[0] == first, "retained peer modification remains isolated")

func _object_fixture() -> Dictionary:
	var payload := _payload({})
	var first := Observer.new()
	var second := Observer.new()
	var trace: Array = []
	first.label = "first"
	second.label = "second"
	for observer: Observer in [first, second]:
		observer.state = payload.state
		observer.trace = trace
	payload.state.armies[0].units[0] = first
	payload.state.armies[1].units[0] = second
	return {"payload": payload, "first": first, "second": second, "trace": trace}

func _cases() -> void:
	for value: float in [NAN, INF, -INF]:
		for leaf: Variant in [value, {"nested": [value]}, PackedFloat64Array([0.25, value]), Vector2(value, 1.0), Vector2(1.0, value)]:
			var before := var_to_bytes(leaf)
			_guards(leaf, false, true, "nonfinite JSON-only fallback; old generic unchanged")
			_check(before == var_to_bytes(leaf), "nonfinite guard leaves input bytes unchanged")
	var same_nan: Variant = NAN
	var negative_zero := -1.0
	negative_zero *= 0.0
	_check(var_to_bytes(0.0) != var_to_bytes(negative_zero), "signed-zero fixture bytes genuinely distinct")
	_check(int(kernel.exact_value_equal(same_nan, same_nan)) == 1 and int(kernel.exact_value_equal(0.0, negative_zero)) == 0, "old exact NaN/signed-zero semantics")
	_guards(_chain(64), false, false, "64-level native tree")
	_guards(_chain(65), true, true, "65-level original fallback")
	var array_cycle: Array = []
	array_cycle.append(array_cycle)
	_guards(array_cycle, true, true, "array cycle guard only")
	_check(array_cycle.size() == 1 and is_same(array_cycle[0], array_cycle), "array cycle unmodified")
	array_cycle.clear()
	var dict_cycle := {}
	dict_cycle["self"] = dict_cycle
	_guards(dict_cycle, true, true, "dictionary cycle guard only")
	_check(dict_cycle.size() == 1 and is_same(dict_cycle.self, dict_cycle), "dictionary cycle unmodified")
	dict_cycle.clear()
	var typed: Array[int] = [1, 2, 3]
	for assign_copy: bool in [false, true]:
		_cow([1, 2, 3], assign_copy)
		_cow(typed, assign_copy)
	var readonly_array: Array[float] = [0.25, 1.5]
	readonly_array.make_read_only()
	var readonly_dict := {"field": [0.25, 1.5]}
	readonly_dict.make_read_only()
	for value: Variant in [readonly_array, readonly_dict]:
		var payload := _payload(value)
		payload.state["shared"] = value
		payload.parameters["shared"] = value
		_guards(payload, false, true, "shared readonly input uses whole original fallback")
		_parity(payload, "readonly fallback bytes and source flags unchanged")
	var typed_dict: Dictionary[String, int] = {"field": 7}
	_guards(typed_dict, true, true, "typed dictionary retains original fallback")
	_parity(_payload(typed_dict), "typed dictionary exact fallback")
	_parity(_payload([]), "empty shared array exact JSON")
	_parity(_payload({"float": 0.10000000000000002, "zero": negative_zero, "large": 9007199254740993, "text": "文字\n\t\"\\", "vector": Vector2(0.25, -1.5), "packed": PackedFloat64Array([0.25, 1.5]), "typed": typed}), "finite full precision, unicode, packed and typed values")
	var duplicate_keys := _payload({"value": 1})
	duplicate_keys.state[1] = "integer key"
	duplicate_keys.state["1"] = "string key"
	_parity(duplicate_keys, "insertion order and duplicate stringified keys")
	_parity({"anything": [1, 2.0, "x"]}, "malformed shape original fallback")
	var original := _object_fixture()
	var actual := _object_fixture()
	_guards(original.payload, true, true, "Object original fallback")
	_check(original.first.calls == 0 and original.second.calls == 0, "Object guard is callback free")
	var expected := JSON.stringify(original.payload, "", false, true)
	var text := Store._stringify_crowd_payload(actual.payload)
	_check(expected.to_utf8_buffer() == text.to_utf8_buffer() and original.trace == actual.trace and original.first.calls == actual.first.calls and original.second.calls == actual.second.calls, "Object text, callback order and count unchanged")
	_check(original.first.main and original.second.main and actual.first.main and actual.second.main and original.payload.state.callback_value == actual.payload.state.callback_value, "Object caller main thread and mutation retained")
	for fixture: Dictionary in [original, actual]:
		fixture.first.state = {}
		fixture.second.state = {}

func _run() -> void:
	create_timer(60.0).timeout.connect(func() -> void: printerr("STORE JSON FAIL: deadline"); quit(3))
	kernel = TerrainArmy._get_idle_kernel()
	if kernel == null:
		_parity(_payload({"value": 0.125}), "missing optional accelerator whole original fallback")
		print("STORE JSON SKIP: optional native eligibility checks; original fallback tested")
	else:
		_check(kernel.has_method("contains_json_unsupported") and kernel.has_method("contains_unsupported") and kernel.has_method("exact_value_equal"), "installed native guard methods present")
		if not failed: _cases()
	print("SITE STORE JSON PARALLEL PASS: " if not failed else "SITE STORE JSON PARALLEL FAIL: ", checks, " checks")
	quit(2 if failed else 0)
