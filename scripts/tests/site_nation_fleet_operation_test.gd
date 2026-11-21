extends "res://scripts/tests/site_ship_transport_test.gd"
## Original real ship setup uses the existing test owner's explicit setup
## transactions. Nation commands themselves never pass test_dispatch=true.
const Orders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
const Tech = preload("res://scripts/terrain_lab/site_technology.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")

func _run() -> void:
	deadline = Time.get_ticks_msec() + 90000
	assert(SiteOffices.duty_ids("nation").has("nation.fleet"), "Actual original duty must be wired")
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
	lab.character.faction_id = 1
	lab.npc.faction_id = 1
	assert(lab.character.place(Vector2i(21, 11), true))
	var founder_id := int(lab.character.person_id)
	var placement := Runtime.building_cells(lab.terrain, "settlement_center", Vector2i(20, 12), Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	assert(placement.ok, str(placement))
	var cells: Array[int] = []
	cells.assign(placement.cells)
	for resource: String in Env.ITEM_NAMES: lab.terrain.site.inventory[resource] = 10000
	lab.terrain.site.capacity = 1000000
	var founded := Settlement.found(lab, founder_id, cells)
	assert(founded.ok, str(founded))
	var center: Dictionary = lab.terrain.site.features[str(founded.feature)]
	Runtime.assign_task(lab.terrain, Runtime.ok("", {"target": "feature:" + str(founded.feature), "action": "construct", "cell": center.entrance}))
	lab.terrain.site.worker.cell = center.entrance
	lab.terrain.site.worker.mode = "work"
	Runtime.advance(lab.terrain, float(center.work) + 1.0, true, false, Callable(), Callable(), Callable(), Runtime.CARRY_CAPACITY, Runtime.CARRY_CAPACITY, 1.0, 1)
	assert(str(center.stage) == "complete")
	lab.terrain.site.worker.mode = "idle"
	var settlement_technology := Tech.empty_scope_record(str(lab.terrain.site.id))
	settlement_technology.known = ["S01", "S12"]
	lab.terrain.site.settlement.technology = settlement_technology # Initial known fixture, not earned research.

	team = lab.army
	team.role = "logistics"
	team.team_id = lab._next_army_identity()
	team.roster_size = 4
	var original_cells: Array[Vector2i] = [Vector2i(29, 20), Vector2i(32, 20), Vector2i(29, 40), Vector2i(32, 40)]
	assert(team.deploy_at(lab.terrain, lab.character, lab.npc, original_cells) and team.enable_combat(false, 1))
	team.set_process(false)
	lab.terrain.site.army_next_team = team.team_id + 1
	lab.terrain.site.army_trial_active = true
	for index: int in range(team.combat_units.size()):
		people.append(team.combat_identity(index))
		team.combat_units[index].logistics = true
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var actions: SitePersonActions = lab.site_controller.person_actions
	var first := vehicles.deploy_ship(team, "ferry", Vector2i(30, 20), Vector2i.UP, true)
	var second := vehicles.deploy_ship(team, "ferry", Vector2i(30, 40), Vector2i.UP, true)
	assert(first.ok and second.ok, str([first, second]))
	var ship_ids: Array[String] = [str(first.vehicle_id), str(second.vehicle_id)]
	_board(0, ship_ids[0], 0)
	_board(1, ship_ids[0], 1)
	_board(2, ship_ids[1], 0)
	_board(3, ship_ids[1], 1)
	for index: int in [0, 2]:
		var ship_id := ship_ids[0] if index == 0 else ship_ids[1]
		assert(actions.begin_ship_helm(people[index], ship_id, people[index], true).ok)
		_finish_job(people[index])
		assert(int(vehicles.records()[ship_id].operator_id) == people[index])

	lab.terrain.site.corps = {"real_fleet": {"version": 1, "commander_person_id": people[0], "team_ids": [team.team_id]}}
	assert(lab.site_controller._control_family_person(null, people[0]).ok)
	var technology := Tech.empty_scope_record(str(lab.terrain.site.id))
	technology.known = ["N05", "N12"]
	lab.terrain.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", people[0]), "members": people.duplicate(), "standards": {}, "technology": technology}}
	var orders: SiteEquipmentOrders = lab.site_controller.equipment_orders
	var issued := orders.request_fleet_order(people[0], "n1", "real_fleet", ship_ids)
	assert(issued.ok, str(issued))
	var order_id := str(issued.order_id)
	var before := JSON.stringify([vehicles.records(), lab.terrain.site.equipment_nations])
	assert(not orders.command_fleet_ship(people[2], "n1", order_id, ship_ids[1]).ok, "An actual helm cannot be impersonated in a manual nation command")
	assert(JSON.stringify([vehicles.records(), lab.terrain.site.equipment_nations]) == before)
	for ship_id: String in ship_ids:
		assert(orders.command_fleet_ship(people[0], "n1", order_id, ship_id).ok, "Original commander keeps every original single-ship authority guard")
		var ship: Dictionary = vehicles.records()[ship_id]
		assert(not ship.move.is_empty() and ship.command.is_empty())
		before = JSON.stringify([vehicles.records(), lab.terrain.site.equipment_nations])
		assert(not orders.accept_fleet_ship_stop(people[0], "n1", order_id, ship_id).ok, "Acceptance of a command is not a true arrived ship")
		assert(JSON.stringify([vehicles.records(), lab.terrain.site.equipment_nations]) == before)
	var duration := maxf(float(vehicles.records()[ship_ids[0]].move.duration), float(vehicles.records()[ship_ids[1]].move.duration))
	vehicles.update_ships(duration + 0.01) # Actual original ship owner only; no new national clock.
	for ship_id: String in ship_ids:
		var ship: Dictionary = vehicles.records()[ship_id]
		assert(ship.move.is_empty() and ship.command.is_empty() and not bool(ship.stop_pending))
		assert(orders.accept_fleet_ship_stop(people[0], "n1", order_id, ship_id).ok)
		before = JSON.stringify([vehicles.records(), lab.terrain.site.equipment_nations])
		assert(not orders.accept_fleet_ship_stop(people[0], "n1", order_id, ship_id).ok)
		assert(JSON.stringify([vehicles.records(), lab.terrain.site.equipment_nations]) == before)
	assert(lab.terrain.site.equipment_nations.n1.technology_operations.public_orders[order_id].status == "complete")
	assert(vehicles.records().size() == 2 and team.combat_units.size() == 4, "Same two hulls/four original persons; no generated fleet/person authority")
	var known_people := {}
	for identity: int in people: known_people[identity] = true
	assert(Orders.valid_nations(lab.terrain.site.equipment_nations, lab.terrain.site.item_definitions, known_people))
	assert(Orders.validate_nation_operations(lab.terrain, lab.terrain.site, known_people).ok)
	lab.free()
	print("NATION_FLEET_REAL_SHIP_OPERATION_PASS: original real persons/boarding/helm/Corp; exact two original ships; original controlled commander and single-ship guards; actual original move completion and stop; replay refusal; extra300 research admin/time/whole12N close excluded")
	quit(0)

