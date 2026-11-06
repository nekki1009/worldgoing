extends "res://scripts/tests/site_nation_fleet_operation_test.gd"
## First-earned derivative; original setup dispatch is a named component fixture only.

var _earned_first_dock: Dictionary = {}
var _earned_docks: Array = []

func _water_fixture() -> void:
	# Original generated geometry/resources remain untouched and reproducible.
	for seed_value: int in [17,12345,98761]:
		var data: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.COASTAL_CLIFF,seed_value,{"max_height":1})
		Env.initialize(data,"nation_n12_earned_generated_"+str(seed_value))
		var bodies := {}
		for identity: int in data.water_body:
			if identity >= 0: bodies[identity] = true
		data.parameters.navigable_water_version = 1
		data.parameters.navigable_water_bodies = bodies.keys() # Original explicit water-navigation admission.
		lab.bind_terrain(data)
		lab.site_controller.set_process(false)
		lab.site_controller._auto_save_blocked = true
		_earned_first_dock = {}
		var first: Dictionary = _earned_dock(data)
		if first.is_empty(): continue
		_earned_first_dock = first
		var second: Dictionary = _earned_dock(data)
		if second.is_empty(): continue
		_earned_docks = [first,second]
		break
	assert(_earned_docks.size() == 2,"Original true generated source has two separate legal original ferry footprints and forward sweeps")


func _earned_center_geometry() -> Dictionary:
	for y: int in range(5,lab.terrain.size.y-6):
		for x: int in range(5,lab.terrain.size.x-6):
			var anchor := Vector2i(x,y)
			var contact := anchor+Vector2i.UP
			if not lab.terrain.is_walkable(contact): continue
			var placement: Dictionary = Runtime.building_cells(lab.terrain,"settlement_center",anchor,Vector2i(5,5),{"layout_version":1,"quarter":0,"owner_faction":1})
			if not placement.ok: continue
			var checked := Runtime.preview_build(lab.terrain, "settlement_center", placement.cells, lab.site_controller.reserves_cell, {"layout_version": 1, "quarter": 0, "owner_faction": 1})
			if checked.ok and checked.get("clearing", []).is_empty():
				placement["fixture_contact"] = contact
				return placement
	return Runtime.fail("NO_LEGAL_CENTER","No terrain/soil/water field will be overwritten to create one")

func _earned_natural_walk(index: int, destination: Vector2i) -> void:
	if team.cells[index] == destination: return
	var blocked := func(cell: Vector2i) -> bool: return team._cell_owners.has(cell) and int(team._cell_owners[cell]) != index or lab.character.occupies_cell(cell) or lab.npc.occupies_cell(cell)
	var path := lab.terrain.path_between(team.cells[index],destination,blocked)
	assert(not path.is_empty(),"Original source shore path is real")
	for next: Vector2i in path:
		if next == team.cells[index]: continue
		assert(team._reserve_combat_step(index,next))
		team.prepare_combat(float(team.move_duration[index])+0.01)
		assert(team.cells[index] == next and team.moving_to[index] == TerrainArmy.INVALID_CELL)

func _earned_shore_cluster(data: TerrainData, shore: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var pending: Array[Vector2i] = [shore]
	var seen := {shore: true}
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_front()
		if lab.character.occupies_cell(cell) or lab.npc.occupies_cell(cell): continue
		result.append(cell)
		if result.size() == 4: return result
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cell + direction
			if not seen.has(next) and data.can_step(cell, next) and next.distance_to(shore) <= 5.0:
				seen[next] = true
				pending.append(next)
	return []
func _earned_dock(data: TerrainData) -> Dictionary:
	for y in range(4, data.size.y - 4):
		for x in range(4, data.size.x - 4):
			var anchor := Vector2i(x, y)
			if not data.can_navigate_water(anchor): continue
			if not _earned_first_dock.is_empty() and anchor.distance_to(_earned_first_dock.anchor) < 8.0: continue
			for facing: Vector2i in TerrainData.DIRECTIONS:
				if not data.can_place_water_vehicle(Ship.footprint("ferry", anchor, facing)): continue
				if not data.can_place_water_vehicle(Ship.swept_footprint("ferry", anchor, facing, anchor + facing, facing)): continue
				for shore: Vector2i in Ship.boarding_cells("ferry", anchor, facing):
					if not data.is_walkable(shore) or absi(data.effective_height(shore) - data.effective_height(anchor)) > 1: continue
					var cells := _earned_shore_cluster(data, shore)
					if cells.size() == 4: return {"anchor": anchor, "facing": facing, "shore": shore, "cells": cells}
	return {}

func _earned_component_job(actual_lab: TerrainLab, identity: int, kind: String) -> float:
	# This named test collects only original PA requests/Fatigue pools. It does
	# not claim a whole World/Region/Fire/main-caller scheduling interval.
	var actions: SitePersonActions = actual_lab.site_controller.person_actions
	var elapsed := 0.0
	for tick: int in 400:
		if not actions.is_busy(identity): break
		var job: Dictionary = actions._jobs.get(actions._job_key_for(identity), {})
		assert(not job.is_empty() and job.kind == kind and is_equal_approx(float(job.duration), 300.0), "True original 300-second job, no copied timer or completion")
		var requests := actions.work_requests(30.0)
		var plan := PersonFatigue.plan_work_interval(requests, 30.0)
		assert(plan.ok, str(plan))
		actual_lab._shared_work_plan = plan
		actual_lab._shared_work_pools_committed = false
		actual_lab.site_controller._shared_work_plan = plan
		elapsed += float(plan.jobs.get("person_actions", {}).get(str(identity), {}).get("effective_seconds", 0.0))
		actual_lab._advance_fatigue(30.0) # Original provider/one original shared pool debit.
		actions.settle_after_contacts()
		actual_lab._clear_shared_work_step()
	assert(not actions.is_busy(identity) and elapsed >= 300.0-0.0001, "Actual accepted joint/admin effort completes the full original job")
	return elapsed


func _earned_cold(actual_lab: TerrainLab, nation_id: String, technology_id: String, label: String) -> void:
	var controller: SiteController = actual_lab.site_controller
	assert(controller._capture_for_save().ok, "Actual original Actor/Army/vehicle/item owners capture")
	var before: String = JSON.stringify(actual_lab.terrain.site.equipment_nations[nation_id], "", true, true)
	var source_fingerprint: String = actual_lab.terrain.fingerprint()
	var path: String = "user://nation_"+label+"_first_earned_"+str(Time.get_ticks_usec())+".json"
	controller.save_path = path
	assert(controller.save_to(path).ok, "Original strict Store saves completed actual source, not a minimal/erased pin")
	var read: Dictionary = SiteStore.load_site(path)
	assert(read.ok, "True original generated source/strict technology/operations/ship cold reader: "+str(read))
	assert(JSON.stringify(read.data.site.equipment_nations[nation_id], "", true, true) == before, "True cold read keeps exact accepted owner history and knowledge")
	var loaded: Dictionary = controller.load_from(path)
	assert(loaded.ok and actual_lab.terrain.fingerprint() == source_fingerprint, "Actual Controller rebind preserves original generated terrain/source: "+str(loaded))
	assert(JSON.stringify(actual_lab.terrain.site.equipment_nations[nation_id], "", true, true) == before and SiteTechnology.scope_known(actual_lab.terrain.site.equipment_nations[nation_id].technology, technology_id), "Original load/bind neither reissues nor discards earned owner state")
	assert(FileAccess.file_exists(path), "Good original cold file persists")

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
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
	var founder_id := int(lab.character.person_id)
	var placement: Dictionary = _earned_center_geometry()
	assert(placement.ok, str(placement))
	assert(lab.character.place(placement.fixture_contact,true))
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
	lab.terrain.site.settlement.version = 2
	lab.terrain.site.settlement.technology = settlement_technology # Strict named prior S12/S01 archive, not earned N12.

	team = lab.army
	team.role = "logistics"
	team.team_id = lab._next_army_identity()
	team.roster_size = 4
	var original_cells: Array[Vector2i] = [_earned_docks[0].cells[0],_earned_docks[0].cells[1],_earned_docks[1].cells[0],_earned_docks[1].cells[1]]
	assert(team.deploy_at(lab.terrain, lab.character, lab.npc, original_cells) and team.enable_combat(false, 1))
	team.set_process(false)
	lab.terrain.site.army_next_team = team.team_id + 1
	lab.terrain.site.army_trial_active = true
	for index: int in range(team.combat_units.size()):
		people.append(team.combat_identity(index))
		team.combat_units[index].logistics = true
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var actions: SitePersonActions = lab.site_controller.person_actions
	var first := vehicles.deploy_ship(team,"ferry",_earned_docks[0].anchor,_earned_docks[0].facing,true)
	var second := vehicles.deploy_ship(team,"ferry",_earned_docks[1].anchor,_earned_docks[1].facing,true)
	assert(first.ok and second.ok, str([first, second]))
	var ship_ids: Array[String] = [str(first.vehicle_id), str(second.vehicle_id)]
	_earned_natural_walk(0,_earned_docks[0].shore)
	_board(0, ship_ids[0], 0)
	_earned_natural_walk(1,_earned_docks[0].shore)
	_board(1, ship_ids[0], 1)
	_earned_natural_walk(2,_earned_docks[1].shore)
	_board(2, ship_ids[1], 0)
	_earned_natural_walk(3,_earned_docks[1].shore)
	_board(3, ship_ids[1], 1)
	for index: int in [0, 2]:
		var ship_id := ship_ids[0] if index == 0 else ship_ids[1]
		assert(actions.begin_ship_helm(people[index], ship_id, people[index], true).ok)
		_finish_job(people[index])
		assert(int(vehicles.records()[ship_id].operator_id) == people[index])

	lab.terrain.site.corps = {"real_fleet": {"version": 1, "commander_person_id": people[0], "team_ids": [team.team_id]}}
	assert(lab.site_controller._control_family_person(null, people[0]).ok)
	var technology := Tech.empty_scope_record(str(lab.terrain.site.id))
	technology.known = ["N05"] # Strict explicit prior institution, never the earned target.
	lab.terrain.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", people[0]), "members": people.duplicate(), "standards": {}, "technology": technology}}
	var orders: SiteEquipmentOrders = lab.site_controller.equipment_orders
	assert(not Tech.scope_known(lab.terrain.site.equipment_nations.n1.technology,"N12"))
	assert(actions.prepare_scope_technology(people[0],people[0],"N12","n1").ok,"True original first N12 purpose")
	var consent: Dictionary = actions.request_scope_technology_consent(people[0],"nation","n1",people[0])
	assert(consent.ok,"Actual original controlled team decider names this original researcher: " + str(consent))
	var issued := orders.request_fleet_order(people[0], "n1", "real_fleet", ship_ids)
	assert(issued.ok, str(issued))
	var order_id := str(issued.order_id)
	var before := JSON.stringify([vehicles.records(), lab.terrain.site.equipment_nations])
	var incomplete: Dictionary = actions.begin_nation_administration(people[0],"n1",order_id,"fleet")
	assert(not incomplete.ok and incomplete.code == "INCOMPLETE_OPERATION" and JSON.stringify([vehicles.records(),lab.terrain.site.equipment_nations]) == before,"Accepted registration has no fictitious arrival/admin credit")
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
	var nation: Dictionary = lab.terrain.site.equipment_nations.n1
	assert(not Tech.scope_known(nation.technology,"N12"),"Both true stopped ships are evidence, never standalone knowledge")
	var admin: Dictionary = actions.begin_nation_administration(people[0],"n1",order_id,"fleet")
	assert(admin.ok and is_equal_approx(float(admin.seconds),300.0),str(admin))
	var actual_seconds: float = _earned_component_job(lab,people[0],"nation_administration")
	assert(Tech.scope_known(nation.technology,"N12") and nation.technology.projects[0].closed and nation.technology.projects[0].receipts.size() == 1 and nation.technology.projects[0].budget.payments.size() == 1,"Only actual original 300-second admin plus true two-ship receipts earns first N12")
	before = JSON.stringify([vehicles.records(),lab.terrain.site.equipment_nations])
	assert(actions.begin_nation_administration(people[0],"n1",order_id,"fleet").code == "NO_CHANGE" and JSON.stringify([vehicles.records(),lab.terrain.site.equipment_nations]) == before,"Known completed fleet cannot replay research receipt/clock")
	_earned_cold(lab,"n1","N12","fleet")
	assert(lab.site_controller.vehicles.records().size() == 2 and lab.terrain.site.equipment_nations.n1.technology_operations.public_orders[order_id].receipts.size() == 2,"Cold rebind preserves precisely two original hulls/true stop history; no extra fleet")
	print("N12_FIRST_EARNED_REAL_SHIPS_ADMIN_PASS: actual generated two natural docks; named prior N05/S12; first target absent; actual original finiteCorp/person/helm/forward/stoppedships; true original300 admin PA-Fatigue component; real source cold/rebind/replay/refusal; not whole Region/mainclock/navigation/GPU/release")
	lab.free()
	quit(0)
