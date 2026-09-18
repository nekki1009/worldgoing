extends SceneTree
## The original work route and original Army step must avoid ownerless parked cars.
var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 40000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("Work vehicle route deadline")
		quit(1)
	return false

func _run() -> void:
	assert(DisplayServer.get_name() == "headless")
	var lab := TerrainLab.new()
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for army: TerrainArmy in lab.combat_armies: army.set_process(false)
	var origin := TerrainArmy.INVALID_CELL
	for y in range(1, lab.terrain.size.y - 9):
		for x in range(1, lab.terrain.size.x - 9):
			var legal := true
			for row in range(9):
				for column in range(9):
					var cell := Vector2i(x + column, y + row)
					if not lab.terrain.is_walkable(cell) or lab.site_controller.reserves_cell(cell): legal = false
					if column > 0 and not lab.terrain.can_step(cell - Vector2i.RIGHT, cell) or row > 0 and not lab.terrain.can_step(cell - Vector2i.DOWN, cell): legal = false
			if legal:
				origin = Vector2i(x, y)
				break
		if origin != TerrainArmy.INVALID_CELL: break
	assert(origin != TerrainArmy.INVALID_CELL, "Find original connected ground; never flatten terrain")
	var team := lab.army
	team.team_id = lab._next_army_identity()
	team.roster_size = 2
	var cells: Array[Vector2i] = [origin + Vector2i(1, 1), origin + Vector2i(2, 4)]
	assert(team.deploy_at(lab.terrain, lab.character, lab.npc, cells) and team.enable_combat(false, 0))
	team.role = "work"
	var vehicles = lab.site_controller.vehicles
	var cart_cell := origin + Vector2i(4, 4)
	assert(vehicles.deploy_plan(team, [{"kind": "cart", "team_id": team.team_id,
		"cell": lab.terrain.index(cart_cell), "facing": [1, 0], "operator_index": -1}]).ok)
	assert(vehicles.park_team(team).ok)
	var vehicle: Dictionary = vehicles.records().values()[0]
	assert(int(vehicle.team_id) == 0 and int(vehicle.operator_id) == 0)
	var worker := team.combat_identity(1)
	var destination := origin + Vector2i(8, 4)
	var occupied := func(cell: Vector2i) -> bool: return lab.site_controller.work_team._occupied(cell, team, 1)
	assert(occupied.call(cart_cell), "Original WorkTeam must see parked team-zero vehicles")
	var route := lab.terrain.path_between(team.cells[1], destination, occupied)
	assert(route.size() > 6 and not route.has(cart_cell), "Actual work route must detour around the parked car")
	var walked := 0
	while team.cells[1] != destination and walked < 20:
		var next: Vector2i = lab.site_controller.work_team._next_step(worker, team.cells[1], destination, occupied)
		assert(next != TerrainArmy.INVALID_CELL and next != cart_cell and team._reserve_combat_step(1, next))
		for step in range(30): team.prepare_combat(1.0 / 30.0)
		assert(team.cells[1] == next and team.moving_to[1] == TerrainArmy.INVALID_CELL)
		walked += 1
	assert(team.cells[1] == destination and int(vehicle.cell) == lab.terrain.index(cart_cell))
	print("SITE_WORK_VEHICLE_PATH_PASS: original generated ground, parked team-zero obstacle, original WorkTeam route/cache, real Army steps arrived after ", walked, " cells; no path or terrain replacement")
	lab.queue_free()
	await process_frame
	quit(0)
