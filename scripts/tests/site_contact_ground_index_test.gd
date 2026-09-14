extends SceneTree
## Native broad-phase input test. No GPU/FPS claim, no pose/hit-rule substitution.
## Rejected production candidate: 214245_883 was exact, but 1/4/16 queries per
## step were slower; only 64 amortized the build. Keep the experiment test-only.
class Probe extends TerrainLab:
	func _contact_ground_candidates(team_id: int, grounds: Array[Vector2], bounds: Rect2) -> PackedInt32Array:
		# Pure broad-phase input work in the existing post-advance cache. Leave the
		# first two queries linear: sorting a whole team for one swing costs more.
		var count := grounds.size()
		var all_indices := PackedInt32Array(range(count))
		if count < 16 or count > 16777216 or not bounds.position.is_finite() or not bounds.end.is_finite() or bounds.size.x <= 0.0:
			return all_indices
		var key := ["ground_x", team_id]
		if not _army_contact_geometry.has(key):
			_army_contact_geometry[key] = {"uses": 1}
			return all_indices
		var entry: Dictionary = _army_contact_geometry[key]
		entry.uses += 1
		if int(entry.uses) < 3 or bool(entry.get("unsupported", false)):
			return all_indices
		if not entry.has("sorted"):
			var sorted: Array[Vector2] = []
			for index in count:
				if not grounds[index].is_finite():
					entry.unsupported = true
					return all_indices
				# Vector2's native lexicographic order: x coordinate, then exact row
				# index (float32 integers are exact within the explicit roster guard).
				sorted.append(Vector2(grounds[index].x, index))
			sorted.sort()
			entry.sorted = sorted
		var sorted: Array[Vector2] = entry.sorted
		var first := sorted.bsearch(Vector2(bounds.position.x, -1.0))
		var last := sorted.bsearch(Vector2(bounds.end.x, -1.0))
		var candidates := PackedInt32Array([0]) # Original captain bypasses anchor rejection.
		for slot in range(first, last):
			var index := int(sorted[slot].y)
			if index != 0:
				candidates.append(index)
		candidates.sort() # Restore original row order before ANY pose or hit query.
		return candidates

func _initialize() -> void:
	var lab := Probe.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260913
	var cases := 0
	var times: Array[Dictionary] = []
	for scenario in 100:
		var grounds: Array[Vector2] = []
		for index in 200:
			grounds.append(Vector2(rng.randf_range(-16384, 16384), rng.randf_range(-16384, 16384)))
		grounds[0] = Vector2(-INF, NAN) if scenario == 0 else grounds[0]
		if scenario == 1:
			grounds[5].x = -0.0
			grounds[6].x = 0.0
		lab._army_contact_geometry.clear()
		for query in 50:
			var bounds := Rect2(Vector2(rng.randf_range(-16384, 16384), -16384.0), Vector2(rng.randf_range(0, 1024), 32768.0))
			if query % 3 == 0:
				bounds.position = grounds[query + 1] # Exact left/bottom boundary included.
			if query % 3 == 1:
				bounds.position = grounds[query + 1] - bounds.size # Right/top excluded.
			if scenario == 1:
				bounds = Rect2(Vector2(0, -16384), Vector2(1, 32768))
			var expected := PackedInt32Array()
			for index in grounds.size():
				if index == 0 or bounds.has_point(grounds[index]):
					expected.append(index)
			var candidates: PackedInt32Array = lab._contact_ground_candidates(1, grounds, bounds)
			var actual := PackedInt32Array()
			for index in candidates:
				if index == 0 or bounds.has_point(grounds[index]):
					actual.append(index)
			assert(expected == actual, "Ordered native has_point candidates differ")
			cases += 1
	# Workload measure includes preparing/discarding the original batch's index.
	var grounds: Array[Vector2] = []
	for index in 200:
		grounds.append(Vector2((index % 20) * 64, (index / 20.0) * 64))
	for query_count: int in [1, 4, 16, 64]:
		var passes: Array[Dictionary] = []
		for enabled: bool in [false, true, true, false]:
			var checksum := 0
			var started := Time.get_ticks_usec()
			for batch in 100:
				lab._army_contact_geometry.clear()
				for query in query_count:
					var bounds := Rect2(Vector2((query % 20) * 64 - 256, -256), Vector2(512, 1024))
					var candidates: Variant = lab._contact_ground_candidates(1, grounds, bounds) if enabled else range(200)
					for index: int in candidates:
						checksum += int(index == 0 or bounds.has_point(grounds[index]))
			passes.append({"enabled": enabled, "usec": Time.get_ticks_usec() - started, "checksum": checksum})
		for pass_result: Dictionary in passes:
			assert(pass_result.checksum == passes[0].checksum)
		times.append({"queries_per_step": query_count, "passes": passes})
	lab.free()
	print("SITE_CONTACT_GROUND_INDEX_PASS ", JSON.stringify({"ordered_cases": cases, "times": times}))
	quit()
