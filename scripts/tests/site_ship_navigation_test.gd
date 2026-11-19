extends "res://scripts/tests/site_ship_transport_test.gd"
## Real original commands travel away from a small shore, turn, reverse and dock.

func _check(condition: bool, reason: String) -> bool:
	if condition: return true
	push_error(reason)
	quit(1)
	return false

func _finish_step(boat: Dictionary) -> void:
	lab.site_controller.vehicles.update_ships(float(boat.move.duration) + 0.01)

func _navigate(boat: Dictionary, action: String, target: Vector2i) -> bool:
	var transport: SiteVehicleTransport = lab.site_controller.vehicles
	var result: Dictionary = transport.ship_order(str(boat.id), action, target, people[0], true)
	if not _check(result.ok, "Original %s order rejected: %s" % [action, str(result)]): return false
	var saw_step := false
	var saw_turn := false
	var saw_dock := false
	for tick in range(512):
		transport.update_ships(0.25)
		if not boat.move.is_empty():
			saw_step = true
			saw_turn = saw_turn or str(boat.move.action) == "turn"
			if str(boat.move.action) == "dock":
				saw_dock = true
				if not _check(float(boat.move.duration) >= 2.0, "Dock/shore departure exceeded 0.5 cells per second"): return false
			for cell: Vector2i in transport._claims(boat):
				if not _check(lab.terrain.can_navigate_water(cell), "Original command reserved a non-navigable cell"): return false
		if boat.command.is_empty() and boat.move.is_empty(): break
	if not _check(boat.command.is_empty() and boat.move.is_empty() and lab.terrain.cell_from_index(int(boat.cell)) == target,
		"Original %s route failed to finish its physical steps" % action): return false
	if not _check(saw_step and (action != "dock" or saw_dock), "The original route did not exercise its expected physical steps"): return false
	print("SITE_SHIP_NAVIGATION_ROUTE:%s:turn=%s:dock=%s" % [action, str(saw_turn), str(saw_dock)])
	return true

func _run() -> void:
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for original: TerrainArmy in lab.combat_armies: original.set_process(false)
	_water_fixture()
	# This explicit fixture is a one-cell shore surrounded by licensed water.
	# The original generated-terrain save test remains independent and unchanged.
	var shore := Vector2i(42, 40)
	var shore_index := lab.terrain.index(shore)
	lab.terrain.flags[shore_index] = Data.Flag.WALKABLE
	lab.terrain.surface_types[shore_index] = Data.Surface.GRASS
	lab.terrain.water_kind[shore_index] = 0
	lab.terrain.water_body[shore_index] = -1
	lab.terrain.parameters.navigable_water_cells.erase(shore_index)
	Runtime.rebuild_terrain_edges(lab.terrain)
	team = lab.army
	team.role = "logistics"
	team.team_id = lab._next_army_identity()
	team.roster_size = 4
	var cells: Array[Vector2i] = [shore, Vector2i(25, 55), Vector2i(25, 56), Vector2i(25, 57)]
	if not _check(team.deploy_at(lab.terrain, lab.character, lab.npc, cells) and team.enable_combat(false, 0), "Original navigation people failed to deploy"): return
	lab.terrain.site.army_next_team = team.team_id + 1
	for index in range(4):
		people.append(team.combat_identity(index))
		team.combat_units[index].logistics = true
	var transport: SiteVehicleTransport = lab.site_controller.vehicles
	var deployed: Dictionary = transport.deploy_ship(team, "ferry", Vector2i(43, 40), Vector2i.UP, true)
	if not _check(deployed.ok, str(deployed)): return
	var boat: Dictionary = transport.records()[str(deployed.vehicle_id)]
	_board(0, str(boat.id), 0)
	var actions: SitePersonActions = lab.site_controller.person_actions
	if not _check(actions.begin_ship_helm(people[0], str(boat.id), people[0], true).ok, "Original navigation helm rejected"): return
	_finish_job(people[0])
	var original_row: Dictionary = team.combat_units[0]
	var original_holder: Dictionary = original_row.item_state
	if not _check(transport.ship_order(str(boat.id), "forward", TerrainArmy.INVALID_CELL, people[0], true).ok, "Manual shore departure rejected"): return
	if not _check(str(boat.move.action) == "dock" and float(boat.move.duration) >= 2.0, "Manual first departure missed the docking cap"): return
	_finish_step(boat)
	if not _navigate(boat, "sail", Vector2i(43, 34)): return
	if not _navigate(boat, "sail", Vector2i(50, 34)): return
	if not _check(boat.facing == [1, 0], "Automatic original route did not turn east"): return
	if not _check(transport.ship_order(str(boat.id), "reverse", TerrainArmy.INVALID_CELL, people[0], true).ok, "Original reverse rejected"): return
	var forward_speed := Ship.speed("ferry", 1, transport.ship_load(str(boat.id)), 1)
	if not _check(absf(float(boat.move.duration) - 4.0 / forward_speed) < 0.000001, "Reverse did not preserve the quarter-speed contract"): return
	_finish_step(boat)
	if not _check(lab.terrain.cell_from_index(int(boat.cell)) == Vector2i(49, 34), "Reverse committed the wrong adjacent cell"): return
	for quarter in range(4):
		if not _check(transport.ship_order(str(boat.id), "turn_right", TerrainArmy.INVALID_CELL, people[0], true).ok, "Open-water original quarter-turn rejected"): return
		_finish_step(boat)
	if not _check(boat.facing == [1, 0], "Four original quarter-turns changed the starting heading"): return
	if not _navigate(boat, "sail", Vector2i(43, 34)): return
	if not _check(transport.ship_order(str(boat.id), "turn_left", TerrainArmy.INVALID_CELL, people[0], true).ok, "Original return heading rejected"): return
	_finish_step(boat)
	if not _check(boat.facing == [0, -1], "Return heading must keep the original west-side shore contact"): return
	if not _navigate(boat, "dock", Vector2i(43, 40)): return
	if not _check(transport.ship_contacts(boat).has(shore), "Real docking lost its original shore contact"): return
	_disembark(0, str(boat.id), shore)
	if not _check(is_same(team.combat_units[0], original_row) and is_same(original_row.item_state, original_holder) and team._cell_owners.get(shore, -1) == 0,
		"Navigation replaced an original person/holder or failed to restore the shore claim"): return
	print("SITE_SHIP_NAVIGATION_PASS")
	quit(0)
