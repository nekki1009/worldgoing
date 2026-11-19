extends "res://scripts/tests/fixtures/site_terminal_first_error_test.gd"
const Source = preload("res://scripts/terrain_lab/terrain_army_contact_source.gd")
const Reference = preload("res://scripts/tests/fixtures/contact_source_compaction_reference.gd")

func _initialize() -> void:
	_install_terminal_guard()
	deadline = Time.get_ticks_msec() + 15000
	_run.call_deferred()

func _snapshot(animation: Animation) -> Array:
	var result: Array = [animation.length, animation.loop_mode, animation.step, animation.resource_name, animation.get_meta(&"fixture")]
	for track: int in animation.get_track_count():
		var keys: Array = []
		for key: int in animation.track_get_key_count(track):
			keys.append([animation.track_get_key_time(track, key), animation.track_get_key_value(track, key), animation.track_get_key_transition(track, key)])
		result.append([animation.track_get_type(track), animation.track_get_path(track), animation.track_is_enabled(track), animation.track_get_interpolation_type(track), keys])
	return result

func _case(kind: String) -> bool:
	var original: Animation = Animation.new()
	original.resource_name = "compaction_" + kind
	original.length = 2.0
	original.loop_mode = Animation.LOOP_LINEAR
	original.set_meta(&"fixture", {"nested": [1, 2, 3]})
	var track: int = original.add_track(Animation.TYPE_BLEND_SHAPE)
	original.track_set_path(track, NodePath("Mesh:Shape"))
	original.track_set_enabled(track, false)
	original.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC if kind == "cubic" else Animation.INTERPOLATION_LINEAR)
	var negative_zero: float = PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128]).decode_double(0)
	for key: int in 64:
		var value: float = 0.0
		if key == 31:
			if kind == "negative_zero": value = negative_zero
			elif kind == "nonzero": value = 0.25
			elif kind == "nan": value = NAN
		var time: float = float(key) / 64.0 + (0.125 if kind == "late_start" else 0.0)
		original.track_insert_key(track, time, value, 0.5 if kind == "transition" and key == 31 else 1.0)
	if kind == "beyond_length": original.length = 0.5
	var other: int = original.add_track(Animation.TYPE_VALUE)
	original.track_set_path(other, NodePath("Mesh:visible"))
	original.track_insert_key(other, 0.0, true)
	original.track_insert_key(other, 0.5, false)
	var before: PackedByteArray = var_to_bytes(_snapshot(original))
	var expected: Animation = original.duplicate(true) as Animation
	var actual: Animation = original.duplicate(true) as Animation
	var reference: Reference = Reference.new()
	var candidate: Source = Source.new()
	reference._compact_constant_morph_keys(expected)
	if not _guard(): return false
	candidate._compact_constant_morph_keys(actual)
	if not _guard(): return false
	if not _must(var_to_bytes(_snapshot(actual)) == var_to_bytes(_snapshot(expected)), "Original full curve/flags/metadata parity: " + kind): return false
	if not _must(var_to_bytes(_snapshot(original)) == before, "Original source resource remains untouched: " + kind): return false
	return _must(actual.track_get_key_count(track) == (1 if kind == "positive_zero" else 64), "Only eligible positive-zero curves compact: " + kind)

func _run() -> void:
	for kind: String in ["positive_zero", "negative_zero", "nonzero", "nan", "transition", "cubic", "late_start", "beyond_length"]:
		if not _case(kind): return
	await _finish_terminal_pass("CONTACT_SOURCE_COMPACTION_PARITY_PASS: original positive-zero guard and complete negative-case curves/metadata")
