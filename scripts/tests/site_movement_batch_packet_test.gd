extends SceneTree
## Direct S1 packet contract; the owner parity test covers live orchestration.

const EXTENSION := "res://native/army_idle/army_idle.gdextension"
const OUTPUT_DIR := "res://output/site_movement_batch_implementation_20260928/"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not GDExtensionManager.is_extension_loaded(EXTENSION):
		assert(GDExtensionManager.load_extension(EXTENSION) == GDExtensionManager.LOAD_STATUS_OK)
	assert(ClassDB.class_exists(&"ArmyIdleKernel"))
	var kernel: RefCounted = ClassDB.instantiate(&"ArmyIdleKernel")
	assert(kernel != null and kernel.has_method("batch_transit_field_intents"))
	var large_id: int = 1 << 40
	var cases := [
		{"name": "free_beats_own_transit_and_int64_id", "members": PackedInt64Array([large_id, 0, 2]),
			"cells": PackedInt64Array([1, 1, 16 | 128 | 256, 2, 1, 0]), "expected": PackedInt64Array([2, 2, 1])},
		{"name": "external_and_foreign_lease_are_unhandled", "members": PackedInt64Array([large_id, 0, 2]),
			"cells": PackedInt64Array([1, 1, 1, 2, 1, 2]), "expected": PackedInt64Array([0, 0, 0])},
		{"name": "own_reserved_grid_blocked_and_moving_owner_wait", "members": PackedInt64Array([large_id, 0, 3]),
			"cells": PackedInt64Array([1, 1, 4, 2, 1, 8, 3, 1, 16 | 32]), "expected": PackedInt64Array([1, 0, 0])},
		{"name": "initial_foreign_occupancy_skipped", "members": PackedInt64Array([large_id, 0, 2]),
			"cells": PackedInt64Array([1, 1, 256, 2, 1, 16 | 128]), "expected": PackedInt64Array([2, 2, 1])},
		{"name": "initial_foreign_occupancy_alone_unhandled", "members": PackedInt64Array([large_id, 0, 1]),
			"cells": PackedInt64Array([1, 1, 256]), "expected": PackedInt64Array([0, 0, 0])},
		{"name": "two_member_packet_preserves_input_order", "members": PackedInt64Array([large_id, 0, 1, large_id + 1, 1, 1]),
			"cells": PackedInt64Array([1, 1, 8, 2, 2, 0]), "expected": PackedInt64Array([1, 0, 0, 2, 2, 2])},
		{"name": "malformed_noncontiguous_start", "members": PackedInt64Array([large_id, 1, 1]),
			"cells": PackedInt64Array([1, 1, 0]), "expected": PackedInt64Array()},
		{"name": "malformed_unknown_flag", "members": PackedInt64Array([large_id, 0, 1]),
			"cells": PackedInt64Array([1, 1, 512]), "expected": PackedInt64Array()},
		{"name": "malformed_owner_moving_without_owner", "members": PackedInt64Array([large_id, 0, 1]),
			"cells": PackedInt64Array([1, 1, 32]), "expected": PackedInt64Array()},
		{"name": "malformed_coordinate_range", "members": PackedInt64Array([large_id, 0, 1]),
			"cells": PackedInt64Array([2147483648, 1, 0]), "expected": PackedInt64Array()},
		{"name": "malformed_triplet_length", "members": PackedInt64Array([large_id, 0]),
			"cells": PackedInt64Array([1, 1, 0]), "expected": PackedInt64Array()},
	]
	var checks := {}
	var actual := {}
	var all_pass := true
	for case: Dictionary in cases:
		var output: PackedInt64Array = kernel.batch_transit_field_intents(case.members, case.cells)
		var passed: bool = output == case.expected
		checks[case.name] = passed
		actual[case.name] = Array(output)
		all_pass = all_pass and passed
		if not passed:
			push_error("MOVEMENT PACKET " + str(case.name) + " expected=" + str(case.expected) + " actual=" + str(output))
	var absolute_dir := ProjectSettings.globalize_path(OUTPUT_DIR)
	assert(DirAccess.make_dir_recursive_absolute(absolute_dir) == OK)
	var path := OUTPUT_DIR + "s1_packet_%d_%d.json" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({
		"status": "PASS" if all_pass else "FAIL", "checks": checks, "actual": actual,
		"source_hashes": {
			"cpp": FileAccess.get_sha256("res://native/army_idle/army_idle.cpp"),
			"dll": FileAccess.get_sha256("res://native/army_idle/bin/army_idle.windows.x86_64.dll"),
			"test": FileAccess.get_sha256("res://scripts/tests/site_movement_batch_packet_test.gd"),
		},
	}, "\t"))
	file.close()
	print("MOVEMENT_BATCH_PACKET_EVIDENCE ", path)
	print("MOVEMENT BATCH PACKET ", "PASS" if all_pass else "FAIL", ": ", cases.size(), " cases")
	quit(0 if all_pass else 1)
