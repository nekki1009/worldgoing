extends SceneTree

const EXTENSION := "res://native/army_idle/army_idle.gdextension"
const OUTPUT := "res://output/site_army_5k_hot_close_20260926/native_exact_oracle_smoke.json"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not GDExtensionManager.is_extension_loaded(EXTENSION):
		assert(GDExtensionManager.load_extension(EXTENSION) == GDExtensionManager.LOAD_STATUS_OK)
	var kernel: RefCounted = ClassDB.instantiate(&"ArmyIdleKernel")
	var checks := {}
	var actual := {}
	var reversed_left := {"a": 1, "b": [2.0, Vector2i(3, 4)]}
	var reversed_right := {"b": [2.0, Vector2i(3, 4)], "a": 1}
	var before_left: PackedByteArray = var_to_bytes(reversed_left)
	var before_right: PackedByteArray = var_to_bytes(reversed_right)
	var mixed_left := {3: "number", "3": "string", &"named": Vector2(1.0, 2.0)}
	var mixed_right := {&"named": Vector2(1.0, 2.0), "3": "string", 3: "number"}
	var typed: Array[Dictionary] = [{"x": 1}]
	var untyped: Array = [{"x": 1}]
	var typed_peer: Array[Dictionary] = [{"x": 1}]
	var typed_objects: Array[RefCounted] = [RefCounted.new()]
	var typed_objects_peer: Array[RefCounted] = [RefCounted.new()]
	actual["typed_array_metadata_debug"] = {
		"class_type": typeof(typed.get_typed_class_name()),
		"class_text": str(typed.get_typed_class_name()),
		"script_type": typeof(typed.get_typed_script()),
		"script_is_null": typed.get_typed_script() == null
	}
	var negative_zero := -1.0
	negative_zero *= 0.0
	var cases: Array = [
		["dictionary_order", reversed_left, reversed_right, 1],
		["mixed_key_order", mixed_left, mixed_right, 1],
		["mixed_key_string_vs_int", {3: 1}, {"3": 1}, 0],
		["mixed_key_name_vs_string", {&"named": 1}, {"named": 1}, 0],
		["optional_key", {"a": null}, {}, 0],
		["int_float_type", 1, 1.0, 0],
		["array_order", [1, 2], [2, 1], 0],
		["typed_array_equal", typed, typed_peer, 1],
		["typed_array_metadata", typed, untyped, 0],
		["typed_object_array_fail_closed", typed_objects, typed_objects_peer, -1],
		["float_signed_zero", 0.0, negative_zero, 0],
		["packed_float_signed_zero", PackedFloat64Array([0.0]), PackedFloat64Array([negative_zero]), 0],
		["vector2i_value", Vector2i(1, 2), Vector2i(1, 3), 0],
		["string_name_equal", &"value", &"value", 1],
		["packed_float_equal", PackedFloat64Array([1.0, 2.0]), PackedFloat64Array([1.0, 2.0]), 1],
		["unsupported_color", Color.RED, Color.RED, -1],
		["nested_unsupported_color", {"bad": [Color.RED]}, {"bad": [Color.RED]}, -1],
		["unsupported_object", RefCounted.new(), RefCounted.new(), -1],
		["unsupported_callable", Callable(self, "_run"), Callable(self, "_run"), -1],
		["unsupported_signal", self.process_frame, self.process_frame, -1],
	]
	for case: Array in cases:
		var result: int = kernel.exact_value_equal(case[1], case[2])
		var supported: bool = not kernel.contains_unsupported(case[1]) and not kernel.contains_unsupported(case[2])
		var name: String = case[0]
		actual[name] = result
		checks[name] = result == case[3] and supported == (case[3] != -1)
	checks["input_bytes_unchanged"] = var_to_bytes(reversed_left) == before_left and var_to_bytes(reversed_right) == before_right
	checks["fixture_negative_zero_distinct"] = var_to_bytes(0.0) != var_to_bytes(negative_zero)
	checks["native_methods_present"] = kernel.has_method("exact_value_equal") and kernel.has_method("contains_unsupported")
	var all_pass := true
	for value: bool in checks.values():
		all_pass = all_pass and value
	var output := {
		"status": "PASS" if all_pass else "FAIL",
		"checks": checks,
		"actual": actual,
		"source_sha256": {
			"cpp": FileAccess.get_sha256("res://native/army_idle/army_idle.cpp"),
			"dll": FileAccess.get_sha256("res://native/army_idle/bin/army_idle.windows.x86_64.dll"),
			"test": FileAccess.get_sha256("res://scripts/tests/site_army_native_exact_oracle_test.gd")
		}
	}
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	if not all_pass:
		push_error("Native exact oracle mismatch: " + str(output))
		quit(1)
		return
	print("NATIVE_EXACT_ORACLE_PASS ", OUTPUT)
	quit()
