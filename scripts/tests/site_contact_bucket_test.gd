extends SceneTree
## Conservative broad-phase candidates only: preserve original row order and
## Rect2.has_point filtering. No occupancy/HP table, contact-rule or FPS claim.
const Lab = preload("res://scripts/terrain_lab/terrain_lab.gd")
const DEADLINE_USEC := 20000000
var _started := 0
var _cases := 0
var _fallback_cases := 0

func _initialize() -> void:
	_started = Time.get_ticks_usec()
	assert(DisplayServer.get_name() == "headless")
	var empty: Array[Vector2] = []
	_check(Rect2(-256, -256, 512, 512), empty, Lab._build_contact_buckets(empty), true)
	var grounds: Array[Vector2] = [
		Vector2(9000, 9000), # Original row 0 bypasses anchor culling, even far away.
		Vector2(-512, -512), Vector2(-256.001, -256.001),
		Vector2(-256, -256), Vector2(-255.999, -255.999),
		Vector2(-0.001, -0.001), Vector2(-0.0, 0.0), Vector2(0, 0),
		Vector2(0.001, 0.001), Vector2(255.999, 255.999),
		Vector2(256, 256), Vector2(256.001, 256.001),
		Vector2(512, 512), Vector2(0, 256), Vector2(256, 0),
	]
	var buckets := Lab._build_contact_buckets(grounds)
	var original_bits := var_to_bytes(grounds)
	for corner: Vector2 in [Vector2(-512, -512), Vector2(-256, -256), Vector2.ZERO, Vector2(256, 256)]:
		_check(Rect2(corner, Vector2(256, 256)), grounds, buckets)
		_check(Rect2(corner - Vector2(0.001, 0.001), Vector2(0.002, 0.002)), grounds, buckets)
	_check(Rect2(-10000, -10000, 1, 1), grounds, buckets)
	_check(Rect2(-256, -256, 512, 512), grounds, {})
	assert(var_to_bytes(grounds) == original_bits, "Index/query must not mutate original anchors")
	_check_fallbacks(grounds, buckets)
	_check_rebuilds(grounds)
	_check_randomized()
	assert(_cases == 5091, "All planned cases must finish before emitting the success marker")
	assert(Time.get_ticks_usec() - _started < DEADLINE_USEC)
	print("SITE_CONTACT_BUCKET_PASS ", JSON.stringify({"ordered_cases": _cases,
		"fallback_cases": _fallback_cases, "random_seed": 20260914,
		"scope": "Original ordered anchor-filter equivalence only; no actual contact or FPS acceptance"}))
	quit(0)

func _check(bounds: Rect2, grounds: Array[Vector2], buckets: Dictionary, fallback: bool = false) -> void:
	assert(Time.get_ticks_usec() - _started < DEADLINE_USEC, "20-second monotonic deadline")
	var candidates: Array[int] = Lab._contact_bucket_candidates(bounds, grounds, buckets)
	var expected: Array[int] = []
	var actual: Array[int] = []
	var all_indices: Array[int] = []
	# Invalid rectangles test only the conservative fallback contract. Calling
	# Godot's has_point on negative sizes is itself an engine error, not an oracle.
	var comparable := bounds.position.is_finite() and bounds.end.is_finite() and bounds.size.x >= 0.0 and bounds.size.y >= 0.0
	assert(comparable or fallback, "Invalid rectangle must be an explicit fallback case")
	for index in grounds.size():
		all_indices.append(index)
		if not comparable or index == 0 or bounds.has_point(grounds[index]):
			expected.append(index)
	var previous := -1
	for index: int in candidates:
		assert(index >= 0 and index < grounds.size() and index > previous,
			"Candidates must be in-range, unique and in original ascending row order")
		previous = index
		if not comparable or index == 0 or bounds.has_point(grounds[index]):
			actual.append(index)
	assert(grounds.is_empty() or (not candidates.is_empty() and candidates[0] == 0),
		"Original first-row bypass must survive even an otherwise empty query")
	assert(actual == expected, "Bucket prefilter changed original ordered has_point results")
	if fallback:
		assert(candidates == all_indices, "Unsupported input must conservatively return every original row")
		_fallback_cases += 1
	_cases += 1

func _check_fallbacks(grounds: Array[Vector2], buckets: Dictionary) -> void:
	for bounds: Rect2 in [
		Rect2(Vector2.ZERO, Vector2.ZERO), Rect2(0, 0, 1, 0),
		Rect2(0, 0, -1, 10), Rect2(0, 0, 10, -1),
		Rect2(Vector2(INF, 0), Vector2.ONE), Rect2(Vector2(NAN, 0), Vector2.ONE),
		Rect2(Vector2.ZERO, Vector2(INF, 1)), Rect2(Vector2.ZERO, Vector2(1, NAN)),
		Rect2(-1e30, -1e30, 2e30, 2e30), Rect2(1048577, 0, 1, 1),
		Rect2(0, 0, 16385, 16385), # More than 4096 query buckets: bounded-work fallback.
	]:
		_check(bounds, grounds, buckets, true)
	_check(Rect2(-256, -256, 512, 512), grounds, {}, true)
	for bad_point: Vector2 in [Vector2(INF, 0), Vector2(NAN, 0), Vector2(0, -INF),
		Vector2(1e30, 0), Vector2(0, -1e30), Vector2(1048577, 0)]:
		for bad_index: int in [0, grounds.size() - 1]:
			var invalid := grounds.duplicate()
			invalid[bad_index] = bad_point
			_check(Rect2(-256, -256, 512, 512), invalid, Lab._build_contact_buckets(invalid), true)
	var edge: Array[Vector2] = [Vector2.ZERO, Vector2(-1048576, -1048576), Vector2(1048576, 1048576)]
	_check(Rect2(-1048576, -1048576, 256, 256), edge, Lab._build_contact_buckets(edge))
	_check(Rect2(1048320, 1048320, 256, 256), edge, Lab._build_contact_buckets(edge))

func _check_rebuilds(initial: Array[Vector2]) -> void:
	var grounds := initial.duplicate()
	for revision in 4:
		if revision == 1:
			# Movement crosses positive/negative bucket edges. Distinct original
			# rows may overlap; the index must not collapse them like occupancy.
			for index in grounds.size():
				grounds[index] += Vector2(512.125 - float(index) * 47.0, -768.25)
			grounds[2] = grounds[3]
		elif revision == 2:
			grounds.reverse() # Current indices, not persisted identities.
		elif revision == 3:
			grounds.resize(5)
		var original_bits := var_to_bytes(grounds)
		var buckets := Lab._build_contact_buckets(grounds)
		for point: Vector2 in grounds:
			_check(Rect2(point - Vector2.ONE, Vector2(2, 2)), grounds, buckets)
		assert(var_to_bytes(grounds) == original_bits)
	var same: Array[Vector2] = []
	for _index in 200:
		same.append(Vector2(128, -128))
	_check(Rect2(127, -129, 2, 2), same, Lab._build_contact_buckets(same))
	_check(Rect2(128, -128, 1, 1), same, Lab._build_contact_buckets(same))
	_check(Rect2(127, -129, 1, 1), same, Lab._build_contact_buckets(same))
	var single: Array[Vector2] = [Vector2(9000, 9000)]
	_check(Rect2(-1, -1, 2, 2), single, Lab._build_contact_buckets(single))

func _check_randomized() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260914
	for scenario in 100:
		var grounds: Array[Vector2] = []
		for _index in 200:
			grounds.append(Vector2(rng.randf_range(-16384, 16384), rng.randf_range(-16384, 16384)))
		grounds[2] = grounds[3] # Overlap does not remove either original row.
		var buckets := Lab._build_contact_buckets(grounds)
		for query in 50:
			var size := Vector2(rng.randf_range(0.001, 3072), rng.randf_range(0.001, 3072))
			var bounds := Rect2(Vector2(rng.randf_range(-16384, 16384), rng.randf_range(-16384, 16384)), size)
			if query % 3 == 0:
				bounds.position = grounds[query + 1] # Exact left/top edge is included.
			elif query % 3 == 1:
				bounds.position = grounds[query + 1] - size # Exact right/bottom is excluded.
			_check(bounds, grounds, buckets)
		if scenario == 0:
			var local := Rect2(grounds[1] - Vector2.ONE, Vector2(2, 2))
			assert(Lab._contact_bucket_candidates(local, grounds, buckets).size() < grounds.size(),
				"Supported sparse queries must actually reject some rows, not always return the full roster")
