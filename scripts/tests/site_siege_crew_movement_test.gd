extends "res://scripts/tests/site_siege_ballista_contract_test.gd"

const CrewStore = preload("res://scripts/terrain_lab/site_store.gd")
const CrewCoordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")

func _ballista_fixture(crew_count: int = 2, clock_probe: bool = false) -> Dictionary:
	var context: Dictionary = super._ballista_fixture(crew_count, clock_probe)
	var coordinator := CrewCoordinator.new()
	coordinator.register_formation(context.fixture.army)
	context.lab.combat_movement_coordinator = coordinator
	context["coordinator"] = coordinator
	return context

func _close_ballista(context: Dictionary) -> void:
	context.coordinator.unregister_formation(context.fixture.army)
	context.lab.combat_movement_coordinator = null
	super._close_ballista(context)

func _run() -> void:
	create_timer(65.0).timeout.connect(func() -> void: quit(1))
	_check_crew_orders_and_rejoin()
	_check_real_turn_and_stopped_state()
	_check_crew_release_and_recovery()
	_check_original_ground_stations()
	_check_approach_stop_and_restart()
	assert(completed == 5, "All crew movement checks must finish before reporting PASS")
	TerrainArmy.release_contact_source()
	print("SITE_SIEGE_CREW_MOVEMENT_PASS: original full roster/non-crew military orders, native roster fallback, new MOVE/preset rejoin, freed plan slots/leases, conservative blocked rotation, single-cell crew walking, completed 3-second turn after stop, stable stopped turning stations, minimum-crew loss and preserved committed recovery; headless only")
	quit(0)

func _crew_ticks(context: Dictionary, seconds: float) -> void:
	var team: TerrainArmy = context.fixture.army
	var remaining := seconds
	while remaining > 0.000000001:
		var step := minf(0.05, remaining)
		var previous: Array[Vector2i] = team.cells.duplicate()
		context.controller.vehicles.update_siege(step)
		context.coordinator.combat_logic_tick_if_needed(step)
		team.prepare_combat(step)
		context.coordinator.complete_committed_moves()
		for index in range(team.cells.size()):
			var delta := team.cells[index] - previous[index]
			assert(absi(delta.x) + absi(delta.y) <= 1, "Crew movement must commit original adjacent edges")
		remaining -= step

func _movement_probe(context: Dictionary) -> Dictionary:
	var team: TerrainArmy = context.fixture.army
	var vehicle: Dictionary = context.vehicle
	var transport: SiteVehicleTransport = context.controller.vehicles
	var rows: Array[Dictionary] = []
	for slot: String in vehicle.crew_slots:
		var index := team.index_for_identity(int(vehicle.crew_slots[slot]))
		var goal := transport.crew_cell(vehicle, slot, true)
		rows.append({"slot": slot, "index": index, "cell": str(team.cells[index]),
			"destination": str(team.moving_to[index]), "progress": float(team.move_progress[index]),
			"pose": str(team.combat_hot_get(index, &"pose")), "goal": str(goal),
			"goal_owner": team._cell_owners.get(goal, -1), "goal_reserved": team._reserved_cells.get(goal, -1),
			"goal_external": team._is_external_cell(goal), "goal_engine": transport.blocks_cell(goal),
			"goal_ground": transport._crew_ground_station(vehicle, goal),
			"search_tick": team._local_search_tick.get(index, -1)})
	return {"crew": rows, "phase": str(vehicle.phase), "action": vehicle.action,
		"command": vehicle.command, "order": team.combat_order, "commander": team.current_commander,
		"commander_eligible": team.command_eligible(team.current_commander), "passage_tick": team._passage_tick,
		"path_requests_remaining": team._local_path_requests_remaining,
		"plan": team._combat_move_plan != null, "deployment": team._combat_deployment_plan != null,
		"reservations": str(team._reserved_cells)}

func _check_crew_orders_and_rejoin() -> void:
	var context := _ballista_fixture()
	var team: TerrainArmy = context.fixture.army
	var vehicle: Dictionary = context.vehicle
	var transport: SiteVehicleTransport = context.controller.vehicles
	var roster := team.combat_units.size()
	var first := team.combat_identity(1)
	var second := team.combat_identity(2)
	transport.update_siege(0.01)
	assert(team._get_active_member_ids() == [int(context.commander)], "Native and GD rosters must exclude derived crew roles")
	assert(team.combat_units.size() == roster and team.is_member(1) and team.is_member(2))
	assert(not team.start_unit_attack(1, Vector2i(18, 20)) and not team.set_unit_guard(1, true))
	assert(not team.start_unit_rescue(1, 0) and not team._reserve_combat_step(1, Vector2i(18, 20)))
	_attack(context)
	var command: Dictionary = vehicle.command.duplicate(true)
	assert(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.HOLD).ok)
	assert(vehicle.command == command, "General HOLD retains the engine's separate command")
	assert(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(10, 15), -1, Vector2i.RIGHT, "square").ok)
	assert(vehicle.command == command and team._combat_deployment_plan.requested_count == 1)
	assert(not team._combat_deployment_plan.member_slot_map.has(first) and not team._combat_deployment_plan.member_slot_map.has(second))
	assert(transport.unassign_crew(context.key, first, int(context.commander), true).ok)
	assert(team.combat_order == TerrainArmy.CombatOrder.MOVE and team.combat_goal == Vector2i(10, 15))
	assert(team._combat_deployment_plan != null and team._combat_deployment_plan.requested_count == 2,
		"Release after a new smaller MOVE must plan the current preset for the current participants")
	assert(team._combat_deployment_plan.member_slot_map.has(first))
	assert(transport.assign_crew(context.key, first, "0", int(context.commander), true).ok)
	assert(team._combat_deployment_plan.requested_count == 2, "Temporarily removing a crew member must not shrink the retained geometry")
	assert(not team._combat_deployment_plan.member_slot_map.has(first))
	assert(not team._combat_deployment_plan.slot_lease_owner_map.values().has(first))
	var snapshot: Dictionary = team.capture_combat_state()
	assert(CrewStore._valid_combat_movement_snapshot(context.data, snapshot, {}, {first: true, second: true}),
		"A retained partial shape plus derived crew exclusion must remain valid")
	_close_ballista(context)
	completed += 1

func _check_original_ground_stations() -> void:
	var context := _ballista_fixture()
	var vehicle: Dictionary = context.vehicle
	var team: TerrainArmy = context.fixture.army
	var transport: SiteVehicleTransport = context.controller.vehicles
	var data: TerrainData = context.data
	var person := team.combat_identity(1)
	var station := transport.crew_cell(vehicle, "0")
	var index := data.index(station)
	data.feature_at[index] = 99 # Explicit witness of another feature claiming the station.
	assert(not transport.crew_ready(vehicle) and transport.crew_count(vehicle) == 1)
	assert(transport.unassign_crew(context.key, person, int(context.commander), true).ok)
	assert(not transport.assign_crew(context.key, person, "0", int(context.commander), true).ok)
	data.feature_at[index] = 0
	data.height_levels[index] = 1
	assert(not transport._crew_ground_station(vehicle, station))
	assert(not transport.assign_crew(context.key, person, "0", int(context.commander), true).ok)
	data.height_levels[index] = 0
	data.surface_types[index] = TerrainData.Surface.WATER
	assert(not transport.assign_crew(context.key, person, "0", int(context.commander), true).ok)
	data.surface_types[index] = TerrainData.Surface.GRASS
	assert(transport.assign_crew(context.key, person, "0", int(context.commander), true).ok)
	_close_ballista(context)
	completed += 1

func _check_real_turn_and_stopped_state() -> void:
	var context := _ballista_fixture()
	var team: TerrainArmy = context.fixture.army
	var vehicle: Dictionary = context.vehicle
	var transport: SiteVehicleTransport = context.controller.vehicles
	var anchor := int(vehicle.cell)
	# The fixture's distinct commander initially occupies the turn station.
	# Move that original person by its own committed edge, keeping them nearby.
	assert(team._reserve_combat_step(0, Vector2i(16, 19)))
	_crew_ticks(context, 0.5)
	assert(team.cells[0] == Vector2i(16, 19))
	var blocker: int = context.data.index(Vector2i(18, 22))
	context.data.static_blocked[blocker] = 1
	assert(transport.order_siege(context.key, "turn", {"facing": [0, 1]}, int(context.commander), true).ok)
	_crew_ticks(context, 4.0)
	assert(vehicle.facing == [1, 0] and str(vehicle.action.stage) == "approach", "A blocked sweep cannot rotate the body")
	for slot: String in vehicle.crew_slots:
		var index := team.index_for_identity(int(vehicle.crew_slots[slot]))
		if team.cells[index] != transport.crew_cell(vehicle, slot, true):
			print("CREW_TURN_APPROACH_DIAGNOSTIC: " + JSON.stringify(_movement_probe(context)))
		assert(team.cells[index] == transport.crew_cell(vehicle, slot, true), "Three original adjacent steps must reach the turn station within four action seconds")
	context.data.static_blocked[blocker] = 0
	transport.update_siege(0.01)
	context.coordinator.combat_logic_tick(0.0)
	assert(str(vehicle.action.stage) == "rotate" and transport.blocks_cell(Vector2i(18, 22)))
	var stations: Array[Vector2i] = [team.cells[1], team.cells[2]]
	assert(transport.order_siege(context.key, "stop", {}, int(context.commander), true).ok)
	_crew_ticks(context, 2.95)
	assert(vehicle.facing == [1, 0] and not vehicle.action.is_empty())
	_crew_ticks(context, 0.05)
	assert(vehicle.facing == [0, 1] and int(vehicle.cell) == anchor and vehicle.action.is_empty())
	assert(team.cells[1] == stations[0] and team.cells[2] == stations[1], "Stopping rotation never teleports crew to the new stations")
	assert(str(vehicle.phase) == "idle" and transport.siege_save_guard().ok)
	assert(not transport.blocks_cell(Vector2i(18, 22)), "Only the actual current footprint remains after rotation")
	_close_ballista(context)
	completed += 1

func _check_approach_stop_and_restart() -> void:
	var context := _ballista_fixture()
	var team: TerrainArmy = context.fixture.army
	var vehicle: Dictionary = context.vehicle
	var transport: SiteVehicleTransport = context.controller.vehicles
	assert(team._reserve_combat_step(0, Vector2i(16, 19)))
	_crew_ticks(context, 0.5)
	assert(transport.order_siege(context.key, "turn", {"facing": [0, 1]}, int(context.commander), true).ok)
	_crew_ticks(context, 0.1)
	assert(str(vehicle.action.stage) == "approach" and team.moving_to[1] != TerrainArmy.INVALID_CELL)
	assert(float(team.move_progress[1]) > 0.0 and float(team.move_progress[1]) < 1.0)
	var committed: Array[Vector2i] = [team.moving_to[1], team.moving_to[2]]
	assert(transport.order_siege(context.key, "stop", {}, int(context.commander), true).ok)
	assert(vehicle.action.is_empty() and str(vehicle.phase) == "turning" and not transport.siege_save_guard().ok)
	_crew_ticks(context, 0.5)
	assert(team.cells[1] == committed[0] and team.cells[2] == committed[1], "Only the already committed approach edges may finish after stop")
	assert(team.moving_to[1] == TerrainArmy.INVALID_CELL and team.moving_to[2] == TerrainArmy.INVALID_CELL)
	assert(vehicle.facing == [1, 0] and vehicle.action.is_empty() and str(vehicle.phase) == "idle")
	assert(transport.siege_save_guard().ok, "A stopped approach must become a saveable stable state")
	context.data.site.armies = [team.capture_combat_state()]
	context.data.site.army_next_team = team.team_id + 1
	assert(CrewStore._validate_vehicles(context.data, context.data.site, true).ok, "Stopped real crew cells must pass the stored vehicle contract")
	assert(transport.order_siege(context.key, "turn", {"facing": [0, 1]}, int(context.commander), true).ok,
		"The settled stopped engine must accept a new authorized turn without another stop click")
	_close_ballista(context)
	completed += 1

func _check_crew_release_and_recovery() -> void:
	var context := _ballista_fixture()
	var team: TerrainArmy = context.fixture.army
	var vehicle: Dictionary = context.vehicle
	var transport: SiteVehicleTransport = context.controller.vehicles
	_attack(context)
	_tick(context, 7.0)
	assert(str(vehicle.action.stage) == "recovering")
	assert(transport.unassign_crew(context.key, 0, int(context.commander), true).ok)
	assert(vehicle.crew_slots.is_empty() and str(vehicle.action.stage) == "recovering")
	assert(not transport.order_siege(context.key, "attack", {"type": "ground", "cell": [45, 20]}, int(context.commander), true).ok)
	_tick(context, 1.0)
	assert(vehicle.action.is_empty() and str(vehicle.phase) == "idle")
	_close_ballista(context)
	context = _ballista_fixture()
	team = context.fixture.army
	vehicle = context.vehicle
	transport = context.controller.vehicles
	_attack(context)
	team.combat_hot_set(1, &"ko", 30.0)
	transport.update_siege(0.01)
	assert(not transport.is_siege_crew(team.combat_identity(1)) and transport.crew_count(vehicle) == 1)
	assert(str(vehicle.command.type) == "attack", "One remaining ready operator preserves the attack at reduced speed")
	team.combat_hot_set(2, &"ko", 30.0)
	transport.update_siege(0.01)
	assert(vehicle.crew_slots.is_empty() and vehicle.action.is_empty() and str(vehicle.command.type) == "stop")
	_close_ballista(context)
	completed += 1
