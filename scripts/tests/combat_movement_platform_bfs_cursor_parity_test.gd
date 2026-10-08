extends SceneTree

const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")

class DirectedTerrain:
	extends RefCounted
	var forbidden: Dictionary = {}

	func forbid(from_cell: Vector2i, to_cell: Vector2i) -> void:
		if not forbidden.has(from_cell):
			forbidden[from_cell] = {}
		forbidden[from_cell][to_cell] = true

	func can_step(from_cell: Vector2i, to_cell: Vector2i) -> bool:
		return absi(from_cell.x - to_cell.x) + absi(from_cell.y - to_cell.y) == 1 \
			and not (forbidden.get(from_cell, {}) as Dictionary).has(to_cell)

func _initialize() -> void:
	call_deferred("_run")

func _require(ok: bool, message: String) -> bool:
	if ok:
		return true
	push_error(message)
	quit(1)
	return false

# Frozen prechange queue and per-member allowed-set behavior. Keep this only
# as the parity oracle for the 128-cell cutoff and directed edge order.
func _old_distances(start: Vector2i, terrain: DirectedTerrain, free_cells: Dictionary, max_cells: int) -> Dictionary:
	var allowed := free_cells.duplicate()
	allowed[start] = true
	var frontier: Array[Vector2i] = [start]
	var distances: Dictionary = {start: 0}
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	while not frontier.is_empty() and distances.size() <= max_cells:
		var cell: Vector2i = frontier.pop_front()
		for direction in directions:
			var next_cell := cell + direction
			if distances.has(next_cell) or not allowed.has(next_cell) or not terrain.can_step(cell, next_cell):
				continue
			distances[next_cell] = int(distances[cell]) + 1
			frontier.append(next_cell)
	return distances

func _run() -> void:
	var terrain := DirectedTerrain.new()
	var start := Vector2i(10, 10)
	terrain.forbid(start, start + Vector2i.UP)
	terrain.forbid(Vector2i(11, 10), Vector2i(12, 10))
	var free_cells: Dictionary = {}
	for x in range(20):
		for y in range(20):
			if Vector2i(x, y) != start and Vector2i(x, y) != Vector2i(9, 11):
				free_cells[Vector2i(x, y)] = true
	var original := free_cells.duplicate()
	for limit in [0, 1, 8, 128, 400]:
		var expected := _old_distances(start, terrain, free_cells, limit)
		var actual: Dictionary = Destination._platform_distances(start, terrain, free_cells, limit)
		if not _require(actual == expected and free_cells == original and not free_cells.has(start),
			"Cursor BFS must preserve directed reachability, frontier order, cutoff, and read-only free cells at limit %d" % limit): return
	var corridor: Dictionary = {}
	for x in range(1, 201):
		corridor[Vector2i(x, 0)] = true
	var corridor_result: Dictionary = Destination._platform_distances(Vector2i.ZERO, terrain, corridor, 128)
	if not _require(corridor_result.size() == 129 and int(corridor_result[Vector2i(128, 0)]) == 128 and not corridor_result.has(Vector2i(129, 0)),
		"The 128-cell cutoff must retain the exact last discovered neighbor"): return
	print("PLATFORM_BFS_CURSOR_PARITY_PASS")
	quit(0)
