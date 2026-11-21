extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var data := Helper.build_flat_map(4, 4)
	var army := Helper.create_test_army(data, 1, 0, 3, Vector2i.ZERO)
	var occupied: Array[Vector2i] = [Vector2i(2, 1), Vector2i(0, 3)]
	army._cell_owners.clear()
	army.cells[0] = Vector2i.ZERO
	army._cell_owners[Vector2i.ZERO] = 0
	for i in range(occupied.size()):
		army.cells[i + 1] = occupied[i]
		army._cell_owners[occupied[i]] = i + 1
		army.combat_slots[i + 1] = Vector2i(3, 1)
	for cell in [Vector2i(1, 1), Vector2i(0, 2), Vector2i(3, 2), Vector2i(1, 3)]:
		data.flags[data.index(cell)] = 0
		data.static_blocked[data.index(cell)] = 1
	var route: Array[Vector2i] = army._find_local_route(Vector2i.ZERO, Vector2i(3, 3), 256, true)
	var cost := route.size() - 1
	for cell in route:
		if occupied.has(cell):
			cost += 3
	if route.is_empty() or cost != 9:
		push_error("Occupied-cell A* route must keep its cheaper cost-9 predecessor; got %s cost=%d" % [route, cost])
		army.free()
		quit(1)
		return
	print("COMBAT MOVEMENT LOCAL ROUTE COST PASS")
	army.free()
	quit(0)
