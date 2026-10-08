extends SceneTree

const Data = preload("res://scripts/terrain_lab/terrain_data.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Ship = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")

var deadline := 0
var lab: TerrainLab
var team: TerrainArmy
var people: Array[int] = []

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 60000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("Ship transport contract deadline")
		quit(1)
	return false

func _water_fixture() -> void:
	# Explicit fixture only. The generated-map JSON roundtrip is a separate test.
	var data := lab.terrain
	assert(data.contains(Vector2i(80, 70)))
	var permissions: Array[int] = []
	for y in range(10, 71):
		for x in range(20, 81):
			var cell := Vector2i(x, y)
			var i := data.index(cell)
			assert(int(data.feature_at[i]) == 0, "Fixture must not replace a real building")
			data.height_levels[i] = 0
			data.ramp_edges[i] = 0
			data.static_blocked[i] = 0
			var water := x >= 30 and cell not in [Vector2i(32, 20), Vector2i(32, 40)]
			data.flags[i] = Data.Flag.BLOCKED | Data.Flag.WET if water else Data.Flag.WALKABLE
			data.surface_types[i] = Data.Surface.WATER if water else Data.Surface.GRASS
			data.water_kind[i] = 1 if water else 0
			data.water_body[i] = 10 if water else -1
			if water: permissions.append(i)
			for key: String in data.resources_at.get(i, []):
				Env.change(data, key, {"cleared": true, "remaining": 0})
	data.parameters.navigable_water_version = 1
	data.parameters.navigable_water_cells = permissions
	data.parameters.erase("navigable_water_bodies")
	Env.rebuild_indexes(data)
	Runtime.rebuild_terrain_edges(data)
	assert(data.can_place_water_vehicle(Ship.footprint("ferry", Vector2i(30, 20), Vector2i.UP)))

func _step(index: int, destination: Vector2i) -> void:
	assert(team.cells[index].distance_to(destination) == 1.0)
	assert(team._reserve_combat_step(index, destination), "Original shore person must commit their own legal step")
	team.prepare_combat(float(team.move_duration[index]) + 0.01)
	assert(team.cells[index] == destination and team.moving_to[index] == TerrainArmy.INVALID_CELL)

func _walk(index: int, destination: Vector2i) -> void:
	assert(not lab.site_controller.vehicles.is_embarked(people[index]))
	while team.cells[index].x != 26:
		_step(index, team.cells[index] + Vector2i(signi(26 - team.cells[index].x), 0))
	while team.cells[index].y != destination.y:
		_step(index, team.cells[index] + Vector2i(0, signi(destination.y - team.cells[index].y)))
	while team.cells[index].x != destination.x:
		_step(index, team.cells[index] + Vector2i(signi(destination.x - team.cells[index].x), 0))

func _finish_job(identity: int) -> void:
	var actions: SitePersonActions = lab.site_controller.person_actions
	assert(actions.is_busy(identity))
	var job: Dictionary = actions._jobs[str(identity)]
	actions.advance_ship_jobs(maxf(0.01, float(job.duration) - float(job.elapsed) + 0.01))
	actions.settle_after_contacts()
	assert(not actions.is_busy(identity), "Committed original ship job must finish")

func _board(index: int, vehicle_id: String, berth: int) -> void:
	var actions: SitePersonActions = lab.site_controller.person_actions
	var before: Dictionary = team.combat_units[index]
	var result: Dictionary = actions.begin_ship_board(people[index], vehicle_id, people[index], berth, true)
	assert(result.ok, str(result))
	assert(not before.has("embarked_vehicle_id") and team._cell_owners.get(team.cells[index], -1) == index,
		"Boarding is a job; the real person keeps their original shore claim until commit")
	assert(actions.save_guard().code == "BUSY")
	_finish_job(people[index])
	assert(is_same(before, team.combat_units[index]) and str(before.embarked_vehicle_id) == vehicle_id and int(before.berth_id) == berth)
	assert(team.moving_to[index] == TerrainArmy.INVALID_CELL and team.combat_slots[index] == TerrainArmy.INVALID_CELL)
	assert(not team._cell_owners.values().has(index), "Committed boarding releases every ground claim")
	assert(team.combat_ground(index).is_equal_approx(lab.site_controller.vehicles.ship_person_ground(people[index])))

func _fill_for_last_person(vehicle_id: String, last: int, shore: Vector2i) -> void:
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var vehicle: Dictionary = vehicles.records()[vehicle_id]
	var person: Dictionary = vehicles.ship_person(people[last])
	var added: float = Runtime.carried_load(lab.terrain.site, person.cargo, person.holder) + float(person.holder.equipped.size())
	var amount := int(round(80.0 - vehicles.ship_load(vehicle_id) - added))
	assert(amount > 0 and is_equal_approx(float(amount) + vehicles.ship_load(vehicle_id) + added, 80.0),
		"The fixture counts the real original equipment, rather than assuming empty passenger inventories")
	lab.terrain.site.depot_cell = lab.terrain.index(shore + Vector2i.LEFT)
	var original := int(lab.terrain.site.inventory.grain)
	var result: Dictionary = vehicles.transfer("depot", vehicle_id, {"grain": amount}, [], int(lab.terrain.site.depot_items.version), int(vehicle.holder.version), people[last], true)
	assert(result.ok, str(result))
	assert(int(lab.terrain.site.inventory.grain) == original - amount and int(vehicle.cargo.grain) == amount)

func _disembark(index: int, vehicle_id: String, shore: Vector2i, retreat: bool = false) -> void:
	var before: Dictionary = team.combat_units[index]
	var result: Dictionary = lab.site_controller.person_actions.begin_ship_disembark(people[index], vehicle_id, people[index], shore, true, retreat)
	assert(result.ok, str(result))
	assert(str(before.embarked_vehicle_id) == vehicle_id, "A pending disembark still owns its original berth")
	_finish_job(people[index])
	assert(is_same(before, team.combat_units[index]) and not before.has("embarked_vehicle_id") and not before.has("berth_id"))
	assert(team.cells[index] == shore and team.combat_slots[index] == shore and team._cell_owners.get(shore, -1) == index)
	assert(team.moving_to[index] == TerrainArmy.INVALID_CELL)

func _recover(index: int) -> void:
	var knocked := float(team.combat_hot_get(index, &"ko", 0.0))
	assert(knocked > 0.0)
	team.prepare_combat(0.01, knocked + 0.1)
	team.prepare_combat(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"get_up"]) + 0.1, 0.0)
	assert(team.combat_can_act(index) and not team._cell_owners.values().has(index), "Original KO/get-up must recover aboard without publishing a historical land claim")

func _run() -> void:
	assert(DisplayServer.get_name() == "headless")
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for army: TerrainArmy in lab.combat_armies: army.set_process(false)
	_water_fixture()
	team = lab.army
	team.role = "logistics"
	team.team_id = lab._next_army_identity()
	team.roster_size = 21
	var cells: Array[Vector2i] = [Vector2i(29, 20), Vector2i(32, 20)]
	for y in range(22, 30): cells.append(Vector2i(25, y))
	cells.append(Vector2i(29, 40))
	cells.append(Vector2i(32, 40))
	for y in range(42, 50): cells.append(Vector2i(25, y))
	cells.append(Vector2i(24, 18))
	assert(team.deploy_at(lab.terrain, lab.character, lab.npc, cells) and team.enable_combat(false, 0))
	lab.terrain.site.army_next_team = team.team_id + 1
	lab.terrain.site.army_trial_active = true
	lab.terrain.site.inventory.grain = 200 # Explicit original depot fixture, then real transfers only.
	for index in range(team.combat_units.size()):
		people.append(team.combat_identity(index))
		team.combat_units[index].logistics = true
	assert(people.size() == 21 and people[0] != people[20])
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var actions: SitePersonActions = lab.site_controller.person_actions
	var first: Dictionary = vehicles.deploy_ship(team, "ferry", Vector2i(30, 20), Vector2i.UP, true)
	var second: Dictionary = vehicles.deploy_ship(team, "ferry", Vector2i(30, 40), Vector2i.UP, true)
	assert(first.ok and second.ok, str([first, second]))
	var first_id := str(first.vehicle_id)
	var second_id := str(second.vehicle_id)
	var boat: Dictionary = vehicles.records()[first_id]
	assert(vehicles.team_vehicle_count(team) == 0 and team.combat_units.size() == 21,
		"Ship hulls do not subtract or create real roster persons")
	for kind: String in Ship.KINDS:
		var seats := int(Ship.definition(kind).max_people)
		var hulls := ceili(100.0 / seats)
		var assigned := 0
		for hull in range(hulls): assigned += mini(seats, 100 - assigned)
		assert(assigned == 100, "Hundred-person planning preserves all persons across the six static capacities")
	# Two real people contend for the same reserved helm berth. Nothing moves on rejection.
	assert(actions.begin_ship_board(people[0], first_id, people[0], 0, true).ok)
	var contender: Dictionary = team.combat_units[1].duplicate(true)
	assert(not actions.begin_ship_board(people[1], first_id, people[1], 0, true).ok)
	assert(team.combat_units[1] == contender and not actions.is_busy(people[1]))
	_finish_job(people[0])
	assert(not team._cell_owners.values().has(0))
	assert(actions.begin_ship_board(people[1], first_id, people[1], 0, true).code == "NO_SPACE")
	_board(1, first_id, 1)
	for index in range(2, 10):
		_walk(index, Vector2i(29, 20))
		if index == 9: _fill_for_last_person(first_id, index, Vector2i(29, 20))
		_board(index, first_id, index)
	_board(10, second_id, 0)
	_board(11, second_id, 1)
	for index in range(12, 20):
		_walk(index, Vector2i(29, 40))
		if index == 19: _fill_for_last_person(second_id, index, Vector2i(29, 40))
		_board(index, second_id, index - 10)
	assert(vehicles.ship_people(boat).size() == 10 and vehicles.ship_people(vehicles.records()[second_id]).size() == 10)
	assert(is_equal_approx(vehicles.ship_load(first_id), 80.0) and is_equal_approx(vehicles.ship_load(second_id), 80.0))
	assert(team.combat_units.size() == 21 and vehicles.team_vehicle_count(team) == 0)
	var supply: Dictionary = lab.terrain.site.team_supply[str(team.team_id)]
	assert(int(supply.version) == 3 and not supply.has("inventory") and not supply.sustain.has("open_rations"),
		"First boarding converts the original stock atomically into one location authority")
	# Full incoming goods reject, while moving actual goods within the same hull conserves Q.
	_walk(20, Vector2i(29, 20))
	lab.terrain.site.depot_cell = lab.terrain.index(Vector2i(28, 20))
	var depot_before: Dictionary = lab.terrain.site.inventory.duplicate(true)
	var boat_before: Dictionary = boat.duplicate(true)
	assert(not vehicles.transfer("depot", first_id, {"grain": 1}, [], int(lab.terrain.site.depot_items.version), int(boat.holder.version), people[20], true).ok)
	assert(lab.terrain.site.inventory == depot_before and boat == boat_before)
	var cargo_holder: Dictionary = team.combat_units[2].item_state
	var load_before: float = vehicles.ship_load(first_id)
	assert(vehicles.transfer(first_id, "person:%d" % people[2], {"grain": 1}, [], int(boat.holder.version), int(cargo_holder.version), people[2], true).ok)
	assert(is_equal_approx(vehicles.ship_load(first_id), load_before))
	assert(vehicles.transfer("person:%d" % people[2], first_id, {"grain": 1}, [], int(cargo_holder.version), int(boat.holder.version), people[2], true).ok)
	assert(is_equal_approx(vehicles.ship_load(first_id), load_before))
	assert(not vehicles.transfer(first_id, second_id, {"grain": 1}, [], int(boat.holder.version), int(vehicles.records()[second_id].holder.version), people[2], true).ok)
	# The land command guard is observable through the original Army endpoints.
	team.role = "combat"
	for order in [TerrainArmy.CombatOrder.MOVE, TerrainArmy.CombatOrder.RETURN, TerrainArmy.CombatOrder.ATTACK, TerrainArmy.CombatOrder.PURSUE]:
		assert(team.issue_combat_order(team.current_commander, order, Vector2i(24, 20)).code == "EMBARKED")
	assert(team.issue_formation_change(team.current_commander, "line").code == "EMBARKED")
	assert(team.set_tactical_ai_enabled(team.current_commander, true).code == "EMBARKED")
	team.role = "logistics"
	assert(actions.begin_ship_helm(people[0], first_id, people[0], true).ok)
	_finish_job(people[0])
	assert(int(boat.operator_id) == people[0])
	# Formal player-controlled leave/join changes the original member flag only.
	lab.terrain.site.controlled_person_id = people[8]
	var original_row: Dictionary = team.combat_units[8]
	var original_holder: Dictionary = original_row.item_state
	var original_goods: Dictionary = original_row.cargo.duplicate(true)
	var original_berth := int(original_row.berth_id)
	assert(team.leave_row(people[8]).ok and not team.is_member(8))
	assert(is_same(original_row, team.combat_units[8]) and is_same(original_holder, original_row.item_state))
	assert(original_row.cargo == original_goods and int(original_row.berth_id) == original_berth and str(original_row.embarked_vehicle_id) == first_id)
	assert(vehicles.ship_people(boat).size() == 10 and is_equal_approx(vehicles.ship_load(first_id), load_before))
	assert(team.join_row(people[8]).ok and team.is_member(8))
	lab.terrain.site.controlled_person_id = people[20]
	# Save validation sees a true committed half step, not a hand-written imitation.
	assert(vehicles.ship_order(first_id, "forward", TerrainArmy.INVALID_CELL, people[0], true).ok)
	var target_cell := int(boat.move.cell)
	var duration := float(boat.move.duration)
	vehicles.update_ships(duration * 0.25)
	assert(not boat.move.is_empty() and vehicles.ship_render_pose(boat).progress > 0.0)
	lab.site_controller._capture_positions()
	assert(Store._validate_vehicles(lab.terrain, lab.terrain.site, true).ok)
	var corrupted: Dictionary = lab.terrain.site.duplicate(true)
	corrupted.vehicles[first_id].move.sweep.pop_back()
	assert(not Store._validate_vehicles(lab.terrain, corrupted, true).ok)
	corrupted = lab.terrain.site.duplicate(true)
	corrupted.vehicles[first_id].move.duration = 0.0
	assert(not Store._validate_vehicles(lab.terrain, corrupted, true).ok)
	corrupted = lab.terrain.site.duplicate(true)
	corrupted.vehicles[first_id].cargo.grain = int(corrupted.vehicles[first_id].cargo.grain) + 1
	assert(not Store._validate_vehicles(lab.terrain, corrupted, true).ok)
	corrupted = lab.terrain.site.duplicate(true)
	corrupted.armies[0].units[1].berth_id = 0
	assert(not Store._validate_vehicles(lab.terrain, corrupted, true).ok)
	lab.terrain.site.controlled_person_id = people[8]
	assert(team.leave_row(people[8]).code == "BUSY" and team.is_member(8), "The stationary passenger cannot leave during the hull's committed step")
	lab.terrain.site.controlled_person_id = people[20]
	assert(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.HOLD).ok)
	assert(bool(boat.stop_pending) and not boat.move.is_empty())
	team.apply_unit_contact(0, {"result": {"hp": 0.0, "stun": 1000.0, "guard_break": false}, "shield": false})
	assert(float(team.combat_hot_get(0, &"ko", 0.0)) > 0.0 and vehicles.ship_people(boat).size() == 10)
	vehicles.update_ships(duration)
	assert(int(boat.cell) == target_cell and boat.move.is_empty() and boat.command.is_empty() and int(boat.operator_id) == 0)
	assert(is_equal_approx(vehicles.ship_load(first_id), load_before) and not team._cell_owners.values().has(0))
	_recover(0)
	# Death frees N immediately and transfers the same original equipment into local remains once.
	team.apply_unit_contact(0, {"result": {"hp": 10000.0, "stun": 0.0, "guard_break": false}, "shield": false})
	assert(vehicles.ship_people(boat).size() == 9 and is_equal_approx(vehicles.ship_load(first_id), load_before))
	lab.site_controller.settle_person_deaths(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"]) + 0.5)
	assert(bool(team.combat_units[0].loot_settled) and bool(team.combat_units[0].ship_death_settled))
	assert(not vehicles.is_embarked(people[0]) and is_equal_approx(vehicles.ship_load(first_id), load_before))
	var remains: Dictionary = lab.terrain.site.ground_loot[str(team.combat_units[0].remains_id)]
	assert(str(remains.vehicle_id) == first_id and remains.local_position.size() == 2)
	# Real helm walking exposes intermediate positions. Cancel/KO finish the committed path without duty.
	assert(actions.begin_ship_helm(people[8], first_id, people[8], true).ok)
	var helm_duration := float(actions._jobs[str(people[8])].duration)
	var source_ground: Vector2 = vehicles.ship_person_ground(people[8])
	actions.advance_ship_jobs(helm_duration * 0.5)
	var middle: Vector2 = vehicles.ship_person_ground(people[8])
	assert(not middle.is_equal_approx(source_ground) and not middle.is_equal_approx(vehicles.ship_local_ground(boat, Ship.local_position("ferry", 0))))
	assert(team.combat_ground(8).is_equal_approx(middle) and actions.save_guard().code == "BUSY")
	assert(not actions.begin_ship_helm(people[9], first_id, people[9], true).ok)
	assert(not vehicles.ship_order(first_id, "forward", TerrainArmy.INVALID_CELL, people[20], true).ok)
	assert(actions.cancel(people[8]).ok and actions.is_busy(people[8]), "Cancel retains an already committed ship-internal path")
	_finish_job(people[8])
	assert(int(original_row.berth_id) == 0 and int(boat.operator_id) == 0 and is_equal_approx(vehicles.ship_load(first_id), load_before))
	var first_shore := Vector2i(29, 19)
	_disembark(8, first_id, first_shore)
	_board(8, first_id, 8)
	assert(actions.begin_ship_helm(people[9], first_id, people[9], true).ok)
	helm_duration = float(actions._jobs[str(people[9])].duration)
	actions.advance_ship_jobs(helm_duration * 0.25)
	team.apply_unit_contact(9, {"result": {"hp": 0.0, "stun": 1000.0, "guard_break": false}, "shield": false})
	_finish_job(people[9])
	assert(int(team.combat_units[9].berth_id) == 0 and int(boat.operator_id) == 0 and vehicles.ship_people(boat).size() == 9)
	assert(not team.start_unit_rescue(11, 9), "The other hull's person cannot rescue this patient")
	assert(team.start_unit_rescue(1, 9), "The original rescue reaches an adjacent person on the same hull")
	lab.site_controller._capture_positions()
	assert(TerrainArmy.valid_combat_state(lab.terrain.site.armies[0], lab.terrain, {}, lab.terrain.site),
		"The original saved rescue contract must use the same hull-local reachability")
	team.prepare_combat(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"rescue"]) + 0.1, 0.0)
	assert(float(team.combat_hot_get(9, &"ko", 0.0)) <= SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS)
	_recover(9)
	# Queue a genuine future sail before the original last passengers leave.
	assert(actions.begin_ship_helm(people[9], first_id, people[9], true).ok)
	_finish_job(people[9])
	assert(vehicles.ship_order(first_id, "sail", Vector2i(30, 15), people[9], true).ok and not boat.command.is_empty())
	var commanded: Dictionary = boat.command.duplicate(true)
	assert(vehicles.park_team(team).code == "BUSY" and boat.command == commanded)
	# Everyone returns through the original action; the last passenger cannot revive stale land orders.
	_walk(20, Vector2i(22, 65))
	for index in range(1, 20):
		var id := first_id if index < 10 else second_id
		var shore := first_shore if index < 10 else Vector2i(29, 40)
		_disembark(index, id, shore)
		_walk(index, Vector2i(23, 11 + index))
	assert(not vehicles.team_has_embarked(team.team_id) and team.combat_order == TerrainArmy.CombatOrder.HOLD and not team.tactical_ai_enabled)
	assert(team.combat_goal == TerrainArmy.INVALID_CELL and not team._formation_change_pending)
	assert(boat.command == commanded and boat.move.is_empty(), "Original disembark leaves this queued future intent for parking to clear")
	var parked_cargo: Dictionary = boat.cargo.duplicate(true)
	var parked_loot: Dictionary = lab.terrain.site.ground_loot.duplicate(true)
	var parked_holder: Dictionary = boat.holder
	var parked_cell := int(boat.cell)
	var parked: Dictionary = vehicles.park_team(team)
	assert(parked.ok and int(boat.team_id) == 0 and int(boat.operator_id) == 0 and boat.command.is_empty(), str(parked))
	vehicles.update_ships(10.0)
	assert(int(boat.cell) == parked_cell and boat.move.is_empty() and boat.command.is_empty())
	assert(boat.cargo == parked_cargo and is_same(boat.holder, parked_holder) and lab.terrain.site.ground_loot == parked_loot)
	assert(is_same(lab.terrain.site.ground_loot[str(team.combat_units[0].remains_id)], remains), "Parking keeps the original local remains owner")
	assert(team.combat_units.size() == 21 and not vehicles.team_has_embarked(team.team_id))
	print("SITE_SHIP_PARK_FUTURE_COMMAND_PASS")
	# A separate explicit collapsed-sustain input exercises the original retreat caller.
	# Reset only the parked empty-hull team association for this independent fixture.
	for id: String in [first_id, second_id]: vehicles.records()[id].team_id = team.team_id
	_walk(1, first_shore)
	_board(1, first_id, 1)
	_walk(11, Vector2i(29, 40))
	_board(11, second_id, 1)
	supply = lab.terrain.site.team_supply[str(team.team_id)]
	supply.sustain.routed = true
	supply.sustain.morale = 0.0
	assert(team.begin_morale_retreat().ok)
	team.prepare_combat(0.01, 0.0)
	for index in [1, 11]:
		assert(team.moving_to[index] == TerrainArmy.INVALID_CELL and not team._retreat_paths.has(people[index]))
		assert(not bool(team.combat_hot_get(index, &"site_exited", false)) and not bool(team.combat_hot_get(index, &"surrender_pending", false)))
	assert(not team.morale_retreat_terminal() and not team.morale_retreat_sheltered())
	assert(actions.begin_ship_disembark(people[1], first_id, people[1], first_shore, true).code == "ROUTED")
	assert(actions.begin_ship_disembark(people[1], first_id, people[1], first_shore, true, true).ok)
	_finish_job(people[1])
	assert(team.cells[1] == first_shore and team.combat_order == TerrainArmy.CombatOrder.RETREAT)
	for index in range(21): assert(team.combat_identity(index) == people[index], "No transaction replaces an original person ID")
	print("SITE_SHIP_TRANSPORT_PASS")
	quit(0)
