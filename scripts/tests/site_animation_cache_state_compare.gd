extends SceneTree
## Diagnose serialized cross-engine state; no tolerance or acceptance relaxation.
var differences: Array = []

func _compare(expected: Variant, actual: Variant, path: String) -> void:
	if expected == actual:
		return
	if expected is Array and actual is Array and expected.size() == actual.size():
		for index in expected.size():
			_compare(expected[index], actual[index], path + "[%d]" % index)
		return
	var row := {"path": path, "type": type_string(typeof(expected)),
		"expected": var_to_str(expected), "actual": var_to_str(actual)}
	if expected is Color and actual is Color:
		row["max_absolute_channel_difference"] = maxf(maxf(absf(expected.r - actual.r), absf(expected.g - actual.g)), maxf(absf(expected.b - actual.b), absf(expected.a - actual.a)))
	differences.append(row)

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	assert(arguments.size() == 3)
	for index in range(2):
		assert(arguments[index].begins_with("res://output/site_captain_clip_sequence_20260917/") and FileAccess.file_exists(arguments[index]))
	assert(arguments[2].begins_with("res://output/site_animation_cache_retention_20260917/"))
	var expected: Variant = bytes_to_var(FileAccess.get_file_as_bytes(arguments[0]))
	var actual: Variant = bytes_to_var(FileAccess.get_file_as_bytes(arguments[1]))
	_compare(expected, actual, "state")
	for row: Dictionary in differences:
		# The first two components of each observation are arrays of model records.
		var components: PackedStringArray = str(row.path).replace("]", "").split("[")
		if components.size() > 3 and int(components[1]) < 2:
			var record: Array = expected[int(components[1])][int(components[2])]
			row["record_identity"] = str(record[0])
	var file := FileAccess.open(arguments[2], FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"expected": arguments[0], "actual": arguments[1], "exact": differences.is_empty(), "differences": differences}, "\t"))
	file.close()
	print("CACHE_STATE_AUDIT exact=", differences.is_empty(), " differences=", differences.size(), " output=", arguments[2])
	# A completed diagnostic with a mismatch is still a failed equality check.
	quit(0 if differences.is_empty() else 1)
