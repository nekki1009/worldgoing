extends "res://scripts/tests/combat_movement_formal_mountain_arrival_test.gd"
## Diagnostic-only: measure whether the existing static corridor rows can support a forward-edge rule.

func _advance() -> bool:
	if not super._advance():
		return false
	var move: CombatMovePlan = _army.get_active_move_plan()
	var rows: Array = Transit._get_static_row_sections(move, _army.data, _army._formation_movement_profile)
	var owner: Dictionary = {}
	for k in range(rows.size()):
		for cell: Vector2i in rows[k]:
			if owner.has(cell):
				owner[cell] = -1
			else:
				owner[cell] = k
	var unique_centers := 0
	var connected_rows := 0
	var unique_cells := 0
	var total_cells := 0
	for k in range(rows.size()):
		if int(owner.get(move.macro_path[k], -1)) == k:
			unique_centers += 1
		for cell: Vector2i in rows[k]:
			total_cells += 1
			if int(owner.get(cell, -1)) == k:
				unique_cells += 1
		if k + 1 >= rows.size():
			continue
		var connected := false
		for from_cell: Vector2i in rows[k]:
			if int(owner.get(from_cell, -1)) != k:
				continue
			for to_cell: Vector2i in rows[k + 1]:
				if int(owner.get(to_cell, -1)) == k + 1 and absi(from_cell.x - to_cell.x) + absi(from_cell.y - to_cell.y) == 1 and Transit._can_profile_step(_army.data, from_cell, to_cell, _army._formation_movement_profile):
					connected = true
					break
			if connected:
				break
		if connected:
			connected_rows += 1
	var initial_on_graph := 0
	for cell: Vector2i in _army.cells:
		if int(owner.get(cell, -1)) >= 0:
			initial_on_graph += 1
	print("TRANSIT_GRAPH_COVERAGE path_rows=", rows.size(), " unique_centers=", unique_centers,
		" unique_cells=", unique_cells, "/", total_cells, " connected_row_pairs=", connected_rows,
		"/", rows.size() - 1, " friendly_on_unique_row=", initial_on_graph, "/", _army.cells.size())
	var goal: Vector2i = move.macro_path[-1]
	var distances: Dictionary = {goal: 0}
	var queue: Array[Vector2i] = [goal]
	var head := 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var neighbor := cell + direction
			if distances.has(neighbor) or not _army.data.contains(neighbor) or not Transit._can_profile_step(_army.data, neighbor, cell, _army._formation_movement_profile):
				continue
			distances[neighbor] = int(distances[cell]) + 1
			queue.append(neighbor)
	var reached := 0
	var min_distance := 999999
	var max_distance := 0
	var has_gradient := 0
	for cell: Vector2i in _army.cells:
		if not distances.has(cell):
			continue
		reached += 1
		var distance: int = distances[cell]
		min_distance = mini(min_distance, distance)
		max_distance = maxi(max_distance, distance)
		for direction: Vector2i in TerrainData.DIRECTIONS:
			if int(distances.get(cell + direction, 999999)) == distance - 1:
				has_gradient += 1
				break
	print("TRANSIT_DISTANCE_FIELD goal=", goal, " reachable=", distances.size(),
		" friendly_reached=", reached, "/", _army.cells.size(),
		" distance_min_max=", min_distance, "/", max_distance,
		" friendly_with_forward_gradient=", has_gradient, "/", _army.cells.size(),
		" macro_start_distance=", distances.get(move.macro_path[0], -1),
		" macro_steps=", move.macro_path.size() - 1)
	var commander_id: int = _army.current_commander
	var commander_slot: Vector2i = _plan.get_slot_for_member(commander_id)
	print("TRANSIT_COMMANDER id=", commander_id, " slot=", commander_slot,
		" tactical_role=", _plan.slot_tactical_roles.get(commander_slot, -1),
		" member2_slot=", _plan.get_slot_for_member(2),
		" member2_role=", _plan.slot_tactical_roles.get(_plan.get_slot_for_member(2), -1))
	if is_instance_valid(_lab):
		_lab.queue_free()
	quit(0)
	return false
