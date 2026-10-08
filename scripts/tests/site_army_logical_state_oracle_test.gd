extends SceneTree

const Oracle = preload("res://scripts/tests/fixtures/site_army_logical_state_oracle.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var inserted_left: Dictionary = {}
	inserted_left["a"] = [1, {"nested": 2.0}]
	inserted_left["b"] = null
	var inserted_right: Dictionary = {}
	inserted_right["b"] = null
	inserted_right["a"] = [1, {"nested": 2.0}]
	var string_key: Dictionary = {}
	string_key["name"] = 1
	var string_name_key: Dictionary = {}
	string_name_key[&"name"] = 1
	var unsupported_object := RefCounted.new()
	var unsupported_callable := Callable(self, "_run")
	var unsupported_signal: Signal = process_frame
	var object_key: Dictionary = {}
	object_key[unsupported_object] = 1
	var shared: Dictionary = {"x": 1}
	var aliased: Array = [shared, shared]
	var separate: Array = [{"x": 1}, {"x": 1}]
	var negative_zero_bytes := PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128])
	var negative_zero := negative_zero_bytes.decode_double(0)
	if var_to_bytes(0.0) == var_to_bytes(negative_zero):
		push_error("Negative-zero fixture did not preserve its float bits")
		quit(1)
		return
	var cases: Array[Dictionary] = [
		{"name": "nested equal with shuffled keys", "left": [inserted_left], "right": [inserted_right], "same": true},
		{"name": "missing versus nil", "left": [{"x": null}], "right": [{}], "same": false},
		{"name": "nil versus nonnil", "left": [{"x": null}], "right": [{"x": false}], "same": false},
		{"name": "integer versus float", "left": [1], "right": [1.0], "same": false},
		{"name": "positive versus negative zero", "left": [0.0], "right": [negative_zero], "same": false},
		{"name": "nested positive versus negative zero", "left": [{"x": [0.0]}], "right": [{"x": [negative_zero]}], "same": false},
		{"name": "String versus StringName value", "left": ["name"], "right": [&"name"], "same": false},
		{"name": "String versus StringName key", "left": [string_key], "right": [string_name_key], "same": false},
		{"name": "array order", "left": [[1, 2]], "right": [[2, 1]], "same": false},
		{"name": "object rejected", "left": [unsupported_object], "right": [unsupported_object], "same": false},
		{"name": "nested object rejected", "left": [{"x": [unsupported_object]}], "right": [{"x": [unsupported_object]}], "same": false},
		{"name": "object key rejected", "left": [object_key], "right": [object_key], "same": false},
		{"name": "callable rejected", "left": [unsupported_callable], "right": [unsupported_callable], "same": false},
		{"name": "nested callable rejected", "left": [{"x": [unsupported_callable]}], "right": [{"x": [unsupported_callable]}], "same": false},
		{"name": "signal rejected", "left": [unsupported_signal], "right": [unsupported_signal], "same": false},
		{"name": "nested signal rejected", "left": [{"x": [unsupported_signal]}], "right": [{"x": [unsupported_signal]}], "same": false},
		{"name": "alias identity outside oracle", "left": aliased, "right": separate, "same": true},
	]
	for check: Dictionary in cases:
		var reference: String = Oracle._compare(check.left, check.right, "rows")
		var fast: String = Oracle.first_mismatch(check.left, check.right)
		if fast != reference or fast.is_empty() != bool(check.same):
			push_error("Oracle changed %s: reference=%s fast=%s" % [check.name, reference, fast])
			quit(1)
			return
	if not is_same(aliased[0], aliased[1]) or is_same(separate[0], separate[1]):
		push_error("Alias fixture identity is invalid")
		quit(1)
		return
	shared.x = 2
	if aliased[1].x != 2 or separate[1].x != 1:
		push_error("Alias write propagation changed")
		quit(1)
		return
	print("SITE_ARMY_LOGICAL_STATE_ORACLE_PASS cases=", cases.size())
	quit(0)
