extends "res://scripts/tests/site_ship_transport_test.gd"
## The real Lab common clock must advance boat, food and original fatigue once.

func _check(condition: bool, reason: String) -> bool:
	if condition: return true
	push_error(reason)
	quit(1)
	return false

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
	team = lab.army
	team.role = "logistics"
	team.team_id = lab._next_army_identity()
	team.roster_size = 4
	var cells: Array[Vector2i] = [Vector2i(29, 20), Vector2i(25, 23), Vector2i(25, 24), Vector2i(25, 25)]
	if not _check(team.deploy_at(lab.terrain, lab.character, lab.npc, cells) and team.enable_combat(false, 0), "Original clock fixture deploy failed"): return
	lab.terrain.site.army_next_team = team.team_id + 1
	for index in range(4):
		people.append(team.combat_identity(index))
		team.combat_units[index].logistics = true
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var actions: SitePersonActions = lab.site_controller.person_actions
	var deployed: Dictionary = vehicles.deploy_ship(team, "ferry", Vector2i(30, 20), Vector2i.UP, true)
	if not _check(deployed.ok, str(deployed)): return
	var boat_id := str(deployed.vehicle_id)
	_board(0, boat_id, 0)
	_walk(1, Vector2i(29, 20))
	_board(1, boat_id, 1)
	if not _check(actions.begin_ship_helm(people[0], boat_id, people[0], true).ok, "Clock fixture helm rejected"): return
	_finish_job(people[0])
	var boat: Dictionary = vehicles.records()[boat_id]
	var shared: Dictionary = PersonFatigue.pool(team.combat_units[0])
	if not _check(not shared.is_empty() and int(shared.count) == 4, "Crew must retain the original four-person fatigue pool"): return
	var fatigue_before := float(shared.fatigue)
	var now_before := Runtime.now(lab.terrain) * 60.0
	if not _check(vehicles.ship_order(boat_id, "forward", TerrainArmy.INVALID_CELL, people[0], true).ok, "Common clock boat step rejected"): return
	lab._advance_action_time(float(boat.move.duration) * 0.4)
	if not _check(not boat.move.is_empty() and float(boat.move.elapsed) > 0.0, "Original common clock did not move the hull"): return
	var game_elapsed := Runtime.now(lab.terrain) * 60.0 - now_before
	var expected := fatigue_before + game_elapsed * PersonFatigue.WORK_RATE / float(shared.count)
	if not _check(absf(float(shared.fatigue) - expected) < 0.000001 and float(shared.fatigue) > fatigue_before, "One original crew effort was lost or charged twice"): return
	var entry: Dictionary = lab.site_controller._supply_entry(team)
	if not _check(absf(float(entry.sustain.at) - Runtime.now(lab.terrain) * 60.0) < 0.000001, "Food left the common Site clock"): return
	var frozen := var_to_bytes([boat, shared, entry, lab.terrain.site.minute, lab.terrain.site.phase])
	paused = true
	lab._advance_action_time(1.0)
	paused = false
	if not _check(var_to_bytes([boat, shared, entry, lab.terrain.site.minute, lab.terrain.site.phase]) == frozen, "Pause advanced hull, crew or food"): return
	if not _check(vehicles.ship_order(boat_id, "stop", TerrainArmy.INVALID_CELL, people[0], true).ok, "Common clock stop rejected"): return
	lab._advance_action_time(float(boat.move.duration) + 0.1)
	if not _check(boat.move.is_empty() and boat.command.is_empty() and int(boat.operator_id) == people[0], "Committed step did not finish once after stop"): return
	print("SITE_SHIP_CLOCK_PASS")
	quit(0)
