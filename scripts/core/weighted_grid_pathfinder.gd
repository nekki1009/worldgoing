class_name WeightedGridPathfinder
extends RefCounted

# Shared bounded four-direction A*. Callers own the cell data and step costs.
const NEIGHBOR_DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]
const DEFAULT_MAX_EXPANSIONS: int = 300_000

func find_path(
		start: Vector2i,
		goal: Vector2i,
		bounds_min: Vector2i,
		bounds_max: Vector2i,
		cell_info: Callable,
		step_cost: Callable,
		heuristic_min_step_cost: float = 0.0,
		max_expansions: int = DEFAULT_MAX_EXPANSIONS
	) -> Dictionary:
	if not _contains(bounds_min, bounds_max, start) or not _contains(bounds_min, bounds_max, goal):
		return _empty_result()
	var info_cache: Dictionary = {}
	var start_info: Dictionary = _get_cell_info(start, cell_info, info_cache)
	var goal_info: Dictionary = _get_cell_info(goal, cell_info, info_cache)
	if not bool(start_info.get("passable", false)) or not bool(goal_info.get("passable", false)):
		return _empty_result()

	var open_heap: Array = []
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0.0}
	var closed: Dictionary = {}
	_heap_push(open_heap, _heap_entry(start, _heuristic(start, goal, heuristic_min_step_cost), 0.0))
	var expansions: int = 0
	while not open_heap.is_empty() and expansions < max_expansions:
		var entry: Array = _heap_pop(open_heap)
		var current: Vector2i = entry[4] as Vector2i
		if closed.has(current):
			continue
		var current_g: float = float(g_score.get(current, INF))
		if float(entry[1]) > current_g + 0.000001:
			continue
		if current == goal:
			return {
				"path": _reconstruct_path(came_from, start, goal),
				"cost": current_g,
			}
		closed[current] = true
		expansions += 1
		var current_info: Dictionary = _get_cell_info(current, cell_info, info_cache)
		for direction: Vector2i in NEIGHBOR_DIRECTIONS:
			var next: Vector2i = current + direction
			if not _contains(bounds_min, bounds_max, next) or closed.has(next):
				continue
			var next_info: Dictionary = _get_cell_info(next, cell_info, info_cache)
			if not bool(next_info.get("passable", false)):
				continue
			var movement_cost: float = float(step_cost.call(
				current,
				next,
				direction,
				current_info,
				next_info
			))
			if not is_finite(movement_cost) or movement_cost < 0.0:
				continue
			var next_g: float = current_g + movement_cost
			var previous_g: float = float(g_score.get(next, INF))
			if next_g + 0.000001 >= previous_g:
				continue
			came_from[next] = current
			g_score[next] = next_g
			_heap_push(open_heap, _heap_entry(
				next,
				next_g + _heuristic(next, goal, heuristic_min_step_cost),
				next_g
			))
	return _empty_result()

func _get_cell_info(cell: Vector2i, cell_info: Callable, cache: Dictionary) -> Dictionary:
	var cached: Variant = cache.get(cell, null)
	if cached is Dictionary:
		return cached as Dictionary
	var value: Variant = cell_info.call(cell)
	var result: Dictionary = value as Dictionary if value is Dictionary else {"passable": false}
	cache[cell] = result
	return result

func _heuristic(from: Vector2i, to: Vector2i, minimum_step_cost: float) -> float:
	if minimum_step_cost <= 0.0:
		return 0.0
	var dx: float = absf(float(to.x - from.x))
	var dy: float = absf(float(to.y - from.y))
	return (dx + dy) * minimum_step_cost

func _reconstruct_path(came_from: Dictionary, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var reversed_path: Array[Vector2i] = [goal]
	var current: Vector2i = goal
	while current != start:
		if not came_from.has(current):
			return []
		current = came_from[current] as Vector2i
		reversed_path.append(current)
	reversed_path.reverse()
	return reversed_path

func _empty_result() -> Dictionary:
	return {"path": [], "cost": 0.0}

func _heap_entry(cell: Vector2i, f_score: float, g_score: float) -> Array:
	return [f_score, g_score, cell.y, cell.x, cell]

func _heap_push(heap: Array, entry: Array) -> void:
	heap.append(entry)
	var index: int = heap.size() - 1
	while index > 0:
		var parent: int = floori(float(index - 1) / 2.0)
		if not _heap_less(heap[index], heap[parent]):
			break
		var swap: Variant = heap[index]
		heap[index] = heap[parent]
		heap[parent] = swap
		index = parent

func _heap_pop(heap: Array) -> Array:
	var result: Array = heap[0]
	var last: Variant = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var index: int = 0
		while true:
			var left: int = index * 2 + 1
			var right: int = left + 1
			var smallest: int = index
			if left < heap.size() and _heap_less(heap[left], heap[smallest]):
				smallest = left
			if right < heap.size() and _heap_less(heap[right], heap[smallest]):
				smallest = right
			if smallest == index:
				break
			var swap: Variant = heap[index]
			heap[index] = heap[smallest]
			heap[smallest] = swap
			index = smallest
	return result

func _heap_less(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] < b[0]
	if a[1] != b[1]:
		return a[1] < b[1]
	if a[2] != b[2]:
		return a[2] < b[2]
	return a[3] < b[3]

func _contains(bounds_min: Vector2i, bounds_max: Vector2i, cell: Vector2i) -> bool:
	return cell.x >= bounds_min.x and cell.y >= bounds_min.y \
		and cell.x <= bounds_max.x and cell.y <= bounds_max.y
