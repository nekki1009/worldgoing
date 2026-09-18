extends SceneTree

## Review probe: an obstructed swept corner must not mask an available detour.
const OUT := "res://output/logistics_vehicles_20260918/review/"
const Vehicles = preload("res://scripts/terrain_lab/site_vehicle_transport.gd")
var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 20000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("Vehicle route review deadline")
		quit(90)
	return false

func _patch(lab: TerrainLab) -> Vector2i:
	for y in range(1, lab.terrain.size.y - 10):
		for x in range(1, lab.terrain.size.x - 10):
			var legal := true
			for row in range(10):
				for column in range(10):
					var cell := Vector2i(x + column, y + row)
					if not lab.terrain.is_walkable(cell) or lab.character.occupies_cell(cell) or lab.npc.occupies_cell(cell): legal = false
					if column > 0 and not lab.terrain.can_step(cell-Vector2i.RIGHT,cell) or row > 0 and not lab.terrain.can_step(cell-Vector2i.DOWN,cell): legal = false
			if legal: return Vector2i(x,y)
	return TerrainArmy.INVALID_CELL

func _probe(kind: String, trapped: bool = false) -> Dictionary:
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for army: TerrainArmy in lab.combat_armies: army.set_process(false)
	var corner := _patch(lab)
	assert(corner != TerrainArmy.INVALID_CELL)
	var team := lab.army
	team.team_id = lab._next_army_identity()
	team.role = "logistics"
	team.roster_size = 1
	var start := corner + Vector2i(4,3)
	var formation: Array[Vector2i] = [start]
	assert(team.deploy_at(lab.terrain,lab.character,lab.npc,formation) and team.enable_combat(false,0))
	var transport = lab.site_controller.vehicles
	var anchor := Vehicles.anchor_from_operator(kind, start, Vector2i.RIGHT)
	assert(transport.deploy_plan(team,[{"kind":kind,"team_id":team.team_id,"cell":lab.terrain.index(anchor),"facing":[1,0],"operator_index":0}]).ok)
	# Obstructions never invalidate an already occupied person/vehicle cell.
	if trapped:
		var obstacles := [Vector2i.UP, Vector2i.DOWN, Vector2i.RIGHT, Vector2i.LEFT * 3] if kind == "wagon" else [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT * 2]
		for offset: Vector2i in obstacles: lab.terrain.static_blocked[lab.terrain.index(start + offset)] = 1
		for direction: Vector2i in TerrainData.DIRECTIONS: assert(not transport.before_step(team, 0, start + direction))
	else:
		# One real obstacle prevents only the initial downward turning sweep.
		var obstruction := Vector2i(-1, -1) if kind == "wagon" else Vector2i(1, 1)
		lab.terrain.static_blocked[lab.terrain.index(start + obstruction)] = 1
	assert(not transport.before_step(team, 0, start + Vector2i.DOWN), "Fixture must obstruct the actual cart or mounted-wagon turning sweep")
	var vehicle_before: Dictionary = transport.records().values()[0].duplicate(true)
	var goal := start + Vector2i.DOWN*2
	assert(team.issue_combat_order(team.current_commander,TerrainArmy.CombatOrder.MOVE,goal).ok)
	var travelled: Array = [[start.x,start.y]]
	for tick in range(120):
		team.prepare_combat(1.0/30.0)
		var cell: Vector2i = team.cells[0]
		if travelled.back() != [cell.x,cell.y]: travelled.append([cell.x,cell.y])
	var automatic_reached: bool = team.cells[0] == goal
	var manual_detour := false
	var blocked_status := team.command_status
	if not trapped and not automatic_reached and team.cells[0] == start and team.moving_count() == 0:
		manual_detour = true
		for direction: Vector2i in [Vector2i.LEFT,Vector2i.DOWN,Vector2i.DOWN,Vector2i.RIGHT]:
			if not team._reserve_combat_step(0,team.cells[0]+direction):
				manual_detour = false
				break
			for tick in range(25): team.prepare_combat(1.0/30.0)
		manual_detour = manual_detour and team.cells[0] == goal
	var stable_hold: bool = trapped and travelled.size() == 1 and team.cells[0] == start and team.moving_count() == 0 and team.combat_order == TerrainArmy.CombatOrder.HOLD and transport.records().values()[0] == vehicle_before
	var result := {"kind":kind,"trapped":trapped,"stable_hold":stable_hold,"automatic_reached":automatic_reached,"manual_original_reservation_detour_reached":manual_detour,
		"blocked_status":blocked_status,"start":[start.x,start.y],"goal":[goal.x,goal.y],"automatic_travelled":travelled}
	print("VEHICLE_ROUTE_REVIEW ",JSON.stringify(result))
	lab.queue_free()
	await process_frame
	return result

func _run() -> void:
	var results: Array[Dictionary] = []
	var reached := true
	for kind: String in ["cart","wagon"]:
		for trapped: bool in [false, true]:
			var result: Dictionary = await _probe(kind, trapped)
			results.append(result)
			reached = reached and bool(result.stable_hold if trapped else result.automatic_reached)
	var file := FileAccess.open(OUT+"route_result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t")+"\n")
	if not reached:
		push_error("Original MOVE must reach a legal detour goal, or remain stable HOLD when every real first step is blocked")
		quit(1)
	else: quit(0)
