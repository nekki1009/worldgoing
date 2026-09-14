extends SceneTree
## Headless <= 5s internal / 20s helper. No scene setup, geometry or combat claim.
## Uses the real Lab sorter. Godot 4.6 Array.sort_custom uses SortArray's
## insertion-sort path for <=16 entries; an independent offline replay found
## the three-entry case below, which this test must confirm on the real engine.
## The original fraction example is GENERIC only: collision fractions use an
## eight-refinement lattice. The added distance case uses that reachable 0.5
## fraction and actual native Vector2 distance_squared_to results instead.
## https://github.com/godotengine/godot/blob/4.6/core/templates/sort_array.h
## https://github.com/godotengine/godot/blob/4.6/core/math/math_funcs.h

const FRACTIONS: Array[float] = [0.500015, 0.5000075, 0.5]
const PERMUTATIONS: Array = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
var lab: TerrainLab

func _initialize() -> void:
	run.call_deferred()

func _sorted(input: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(input)
	lab._sort_contacts(result)
	return result

func _without(input: Array[Dictionary], removed: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for hit: Dictionary in input:
		if not removed.has(int(hit.identity)):
			result.append(hit)
	return result

func _identities(input: Array[Dictionary]) -> Array[int]:
	var result: Array[int] = []
	for hit: Dictionary in input:
		result.append(int(hit.identity))
	return result

func _native_distance_counterexample() -> Dictionary:
	var points: Array[Vector2] = [Vector2(10.000075, 0.0), Vector2(10.0000375, 0.0), Vector2(10.0, 0.0)]
	var contacts: Array[Dictionary] = []
	var distances: Array[float] = []
	var coordinates: Array = []
	for index: int in points.size():
		var point := points[index]
		# Record the actual engine's native vector values, not hand-entered
		# decimal distances or a double-precision substitute distance function.
		assert(point.x == float(PackedFloat32Array([point.x])[0]), "This fixture targets the standard native float32 Vector2 build")
		var distance := point.distance_squared_to(Vector2.ZERO)
		distances.append(distance)
		coordinates.append([point.x, point.y])
		contacts.append({"identity": index + 3, "fraction": 0.5, "distance": distance,
			"faction": 1, "shield": index == 1})
	assert(is_equal_approx(distances[0], distances[1]) and is_equal_approx(distances[1], distances[2]))
	assert(not is_equal_approx(distances[0], distances[2]))
	var removed := {3: true}
	var full := _sorted(contacts)
	var original := _without(full, removed)
	var culled := _sorted(_without(contacts, removed))
	assert(_identities(full) == [5, 3, 4])
	assert(_identities(original) == [5, 4] and _identities(culled) == [4, 5])
	assert(not bool(original[0].shield) and bool(culled[0].shield))
	return {"coordinates": coordinates, "input": contacts, "full_sorted": _identities(full),
		"original_survivors": _identities(original), "early_cull_survivors": _identities(culled),
		"scope": "Native float32 Vector2 squared distances and lattice-valid fraction 0.5; actual sorter, not a full mesh-contact scene"}

func run() -> void:
	var started := Time.get_ticks_usec()
	assert(DisplayServer.get_name() == "headless")
	lab = TerrainLab.new() # Never add it to the tree; only its original pure sorter runs.
	var input: Array[Dictionary] = []
	for index: int in 3:
		input.append({"identity": index + 3, "fraction": FRACTIONS[index], "distance": 100.0,
			"faction": 1, "shield": index == 1})
	assert(is_equal_approx(FRACTIONS[0], FRACTIONS[1]) and is_equal_approx(FRACTIONS[1], FRACTIONS[2]))
	assert(not is_equal_approx(FRACTIONS[0], FRACTIONS[2]), "The actual engine must exercise non-transitive approximate equality")
	var removed := {3: true}
	var full := _sorted(input)
	var original_survivors := _without(full, removed)
	var early_cull_survivors := _sorted(_without(input, removed))
	assert(_identities(full) == [5, 3, 4])
	assert(_identities(original_survivors) == [5, 4])
	assert(_identities(early_cull_survivors) == [4, 5])
	# Original Army skips existing unit.hits BEFORE its faction/packet/blocked
	# handling. In this generic metadata example ID4 is an enemy shield and
	# ID5 another enemy body. Reachable numeric types are checked separately.
	assert(not bool(original_survivors[0].shield) and bool(early_cull_survivors[0].shield))
	var counterexamples: Array[Dictionary] = []
	var singleton_checks := 0
	for permutation: Array in PERMUTATIONS:
		var candidates: Array[Dictionary] = []
		for index: int in permutation:
			candidates.append(input[index])
		var ordered := _sorted(candidates)
		for omitted: int in [3, 4, 5]:
			var known := {omitted: true}
			var original := _identities(_without(ordered, known))
			var culled := _identities(_sorted(_without(candidates, known)))
			if original != culled:
				counterexamples.append({"input": _identities(candidates), "already_hit": omitted,
					"original": original, "early_cull": culled})
		# At most one not-already-hit candidate has no relative survivor order.
		# This is safe ONLY if candidates cover the full original conservative
		# set, including other armies and both Actors, not just a selected target.
		for remaining: int in [-1, 3, 4, 5]:
			var known := {3: true, 4: true, 5: true}
			known.erase(remaining)
			assert(_identities(_without(ordered, known)) == _identities(_sorted(_without(candidates, known))))
			singleton_checks += 1
	assert(not counterexamples.is_empty() and singleton_checks == 24)
	var native_distance_case := _native_distance_counterexample()
	assert(Time.get_ticks_usec() - started < 5000000, "Bounded sorter-only test")
	var output := "res://output/site_combat_performance_20260913/contact_sort_cull/%d_%d" % [int(Time.get_unix_time_from_system()), started]
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)) == OK)
	var file := FileAccess.open(output + "/measurements.json", FileAccess.WRITE)
	assert(file != null)
	var report := {"counterexample_confirmed": true, "direct_cull_safe": false, "input": input,
		"fraction_example_scope": "Generic comparator proof only; these fine fractions are not claimed as original eight-refinement collision output",
		"native_distance_counterexample": native_distance_case,
		"full_sorted": _identities(full), "original_survivors": _identities(original_survivors),
		"early_cull_survivors": _identities(early_cull_survivors), "permutation_counterexamples": counterexamples,
		"at_most_one_survivor_checks": singleton_checks,
		"lab_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_lab.gd"),
		"scope": "Real original sorter only; no production culling, comparator change, geometry, full combat or performance acceptance"}
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SITE CONTACT SORT CULL PASS: ", JSON.stringify(report))
	lab.free()
	quit(0)
