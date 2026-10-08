extends SceneTree
## Compares the inlined A* heap ordering with the previous comparator-backed heap.

func _initialize() -> void:
	call_deferred("_run")

func _require(ok: bool, message: String) -> bool:
	if ok:
		return true
	push_error(message)
	quit(1)
	return false

func _reference_push(army: TerrainArmy, heap: Array[Vector4i], item: Vector4i) -> void:
	heap.append(item)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) >> 1
		if not army._frontier_less(heap[index], heap[parent]):
			break
		var value := heap[parent]
		heap[parent] = heap[index]
		heap[index] = value
		index = parent

func _reference_pop(army: TerrainArmy, heap: Array[Vector4i]) -> Vector4i:
	var first := heap[0]
	var last: Vector4i = heap.pop_back()
	if heap.is_empty():
		return first
	heap[0] = last
	var index := 0
	while index * 2 + 1 < heap.size():
		var child := index * 2 + 1
		if child + 1 < heap.size() and army._frontier_less(heap[child + 1], heap[child]):
			child += 1
		if not army._frontier_less(heap[child], heap[index]):
			break
		var value := heap[index]
		heap[index] = heap[child]
		heap[child] = value
		index = child
	return first

func _run() -> void:
	var army := TerrainArmy.new()
	var fast_heap: Array[Vector4i] = []
	var reference_heap: Array[Vector4i] = []
	for i in range(600):
		# Repeated f and h ties exercise the final insertion-sequence key.
		var item := Vector4i(i, (i * 37) % 23, (i * 19) % 17, i)
		army._frontier_push(fast_heap, item)
		_reference_push(army, reference_heap, item)
		if not _require(fast_heap == reference_heap, "Heap push changed comparator ordering at item %d" % i): return
		if i % 3 == 0:
			var actual := army._frontier_pop(fast_heap)
			var expected := _reference_pop(army, reference_heap)
			if not _require(actual == expected and fast_heap == reference_heap, "Heap pop changed comparator ordering at item %d" % i): return
	while not fast_heap.is_empty():
		var actual := army._frontier_pop(fast_heap)
		var expected := _reference_pop(army, reference_heap)
		if not _require(actual == expected and fast_heap == reference_heap, "Heap drain changed comparator ordering"): return

	var data := TerrainData.new()
	data.allocate(Vector2i(5, 5))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.height_levels.fill(0)
	army.data = data
	var profile := FormationMovementProfile.new(TerrainData.Flag.WALKABLE, 1, true, 1)
	var route := army._find_local_route(Vector2i.ZERO, Vector2i(4, 4), 64, false, -1, 0, false, profile)
	var expected_route: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0),
		Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 4),
	]
	if not _require(route == expected_route and route.size() - 1 == 8 and army.expanded_nodes == 9 and army.route_calls == 1,
		"Local A* route, cost, calls, or expansions changed on the deterministic tie fixture"): return

	# Timing is diagnostic only; correctness does not depend on machine load.
	var reference_us := 0
	var fast_us := 0
	for pass_index in range(2):
		var started := Time.get_ticks_usec()
		for batch in range(40):
			var heap: Array[Vector4i] = []
			for i in range(256):
				var item := Vector4i(i, (i * 37) % 23, (i * 19) % 17, i)
				if pass_index == 0:
					_reference_push(army, heap, item)
				else:
					army._frontier_push(heap, item)
			while not heap.is_empty():
				if pass_index == 0:
					_reference_pop(army, heap)
				else:
					army._frontier_pop(heap)
		if pass_index == 0:
			reference_us = Time.get_ticks_usec() - started
		else:
			fast_us = Time.get_ticks_usec() - started
	print("COMBAT MOVEMENT FRONTIER HEAP EQUIVALENCE PASS reference_us=%d inline_us=%d" % [reference_us, fast_us])
	army.free()
	quit(0)
