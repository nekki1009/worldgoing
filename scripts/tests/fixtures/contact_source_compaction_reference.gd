extends RefCounted
## Frozen original compaction body for exact test comparison.

func _compact_constant_morph_keys(animation: Animation) -> void:
	# Only a new private copy reaches here. Keep every original track and its
	# first native key, including hidden/unworn equipment and loop metadata.
	# Unknown interpolation/compression/data retains the complete original curve.
	if not is_finite(animation.length) or animation.length <= 0.0:
		return
	for track in range(animation.get_track_count()):
		if animation.track_get_type(track) != Animation.TYPE_BLEND_SHAPE or animation.track_is_compressed(track):
			continue
		if animation.track_get_interpolation_type(track) not in [Animation.INTERPOLATION_LINEAR, Animation.INTERPOLATION_NEAREST]:
			continue
		var count: int = animation.track_get_key_count(track)
		if count <= 1 or animation.track_get_key_time(track, 0) != 0.0:
			continue
		var constant_positive_zero := true
		var previous_time := -1.0
		for index in range(count):
			var time: float = animation.track_get_key_time(track, index)
			var value: float = animation.track_get_key_value(track, index)
			# Numeric equality alone admits -0. Native float -> float64 preserves
			# its sign; all eight zero bytes are exclusively IEEE positive zero.
			if not is_finite(time) or time <= previous_time or time > animation.length or animation.track_get_key_transition(track, index) != 1.0 or value != 0.0 or PackedFloat64Array([value]).to_byte_array().decode_u64(0) != 0:
				constant_positive_zero = false
				break
			previous_time = time
		if constant_positive_zero:
			for index in range(count - 1, 0, -1):
				animation.track_remove_key(track, index)
