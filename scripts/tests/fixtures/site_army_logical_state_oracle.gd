extends RefCounted
## Test-only comparison of materialized Army rows; never called by gameplay ticks.

static func first_mismatch(expected_rows: Array, actual_rows: Array) -> String:
	# One native serialization replaces millions of per-field GDScript calls on
	# equal snapshots. A byte mismatch still uses the original order-insensitive
	# diagnostic comparator; unsupported references always reach that comparator.
	if not _has_unsupported(expected_rows) and not _has_unsupported(actual_rows):
		var expected_bytes := var_to_bytes(expected_rows)
		if not expected_bytes.is_empty() and expected_bytes == var_to_bytes(actual_rows):
			return ""
	return _compare(expected_rows, actual_rows, "rows")


static func _has_unsupported(value: Variant) -> bool:
	if typeof(value) in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL]:
		return true
	if value is Array:
		for child: Variant in value:
			if _has_unsupported(child): return true
	elif value is Dictionary:
		for key: Variant in value:
			if _has_unsupported(key) or _has_unsupported(value[key]): return true
	return false


static func _compare(expected: Variant, actual: Variant, path: String) -> String:
	if typeof(expected) != typeof(actual):
		return "%s: type %d != %d" % [path, typeof(expected), typeof(actual)]
	if expected is Array:
		var array_left: Array = expected
		var array_right: Array = actual
		if array_left.size() != array_right.size():
			return "%s: length %d != %d" % [path, array_left.size(), array_right.size()]
		for index in array_left.size():
			var element_mismatch := _compare(array_left[index], array_right[index], "%s[%d]" % [path, index])
			if not element_mismatch.is_empty():
				return element_mismatch
		return ""
	if expected is Dictionary:
		var dict_left: Dictionary = expected
		var dict_right: Dictionary = actual
		for key: Variant in dict_left:
			if typeof(key) in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL]:
				return _key_path(path, key) + ": unsupported non-value key"
		for key: Variant in dict_right:
			if typeof(key) in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL]:
				return _key_path(path, key) + ": unsupported non-value key"
		var left_keys := _sorted_keys(dict_left)
		var right_keys := _sorted_keys(dict_right)
		var left_index := 0
		var right_index := 0
		while left_index < left_keys.size() and right_index < right_keys.size():
			var left_key: Array = left_keys[left_index]
			var right_key: Array = right_keys[right_index]
			var left_token: String = left_key[0]
			var right_token: String = right_key[0]
			if left_token < right_token:
				return _key_path(path, left_key[1]) + ": missing key"
			if right_token < left_token:
				return _key_path(path, right_key[1]) + ": unexpected key"
			var child_path := _key_path(path, left_key[1])
			var field_mismatch := _compare(dict_left[left_key[1]], dict_right[right_key[1]], child_path)
			if not field_mismatch.is_empty():
				return field_mismatch
			left_index += 1
			right_index += 1
		if left_index < left_keys.size():
			return _key_path(path, left_keys[left_index][1]) + ": missing key"
		if right_index < right_keys.size():
			return _key_path(path, right_keys[right_index][1]) + ": unexpected key"
		return ""
	if typeof(expected) in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL]:
		return path + ": unsupported non-value field"
	if typeof(expected) == TYPE_FLOAT:
		var expected_bits := PackedByteArray()
		var actual_bits := PackedByteArray()
		expected_bits.resize(8)
		actual_bits.resize(8)
		expected_bits.encode_double(0, expected)
		actual_bits.encode_double(0, actual)
		return "" if expected_bits == actual_bits else path + ": float64 bytes differ"
	return "" if var_to_bytes(expected) == var_to_bytes(actual) else path + ": value bytes differ"


static func _sorted_keys(row: Dictionary) -> Array:
	var keys: Array = []
	for key: Variant in row.keys():
		keys.append(["%02d:%s" % [typeof(key), var_to_bytes(key).hex_encode()], key])
	keys.sort_custom(func(a: Array, b: Array) -> bool: return str(a[0]) < str(b[0]))
	return keys


static func _key_path(path: String, key: Variant) -> String:
	return "%s[%s<%d>]" % [path, str(key), typeof(key)]
