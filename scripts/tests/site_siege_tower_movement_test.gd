extends "res://scripts/tests/site_siege_ram_compound_test.gd"

func _run() -> void:
	create_timer(70.0).timeout.connect(func() -> void: quit(1))
	if not _check_tower_action_commit(): return
	if not _check_tower_original_person_path(): return
	if not _check_tower_retained_pose_exit(): return
	if not _require(completed == 3, "Every tower movement group must finish before PASS"): return
	TerrainArmy.release_contact_source()
	print("SITE_SIEGE_TOWER_MOVEMENT_PASS: original 15/10-second same-vehicle surface commit, empty people/KO/reservation withdrawal guards, crewless roof and original operator reassignment, original Army ramp/roof/bridge path, retained disabled/wreck pose and multi-step outside-goal exit without reentry; headless GD only, no Actor/UI/native/GPU claim")
	quit(0)

func _tower_context() -> Dictionary:
	var data := _fixture()
	var created := SiteRuntime.begin_siege_build(data, "siege_tower", Vector2i(20, 20), Vector2i.RIGHT, 1, 1)
	assert(created.ok, str(created))
	var key := str(created.vehicle)
	var vehicle: Dictionary = data.site.vehicles[key]
	var work: Dictionary = SiteRuntime.siege_work_slots(data, vehicle)[0]
	assert(SiteRuntime.advance_siege_work(data, key, "construct", float(vehicle.build.total_work), data.cell_from_index(int(work.cell)), 0, 1).ok)
	for side in range(3): data.height_levels[data.index(Vector2i(25, 20 + side))] = 2
	SiteEnvironment.rebuild_indexes(data)
	var lab := QueryLab.new()
	lab.terrain = data
	var controller := Controller.new()
	controller.lab = lab
	lab.site_controller = controller
	controller.person_actions.init(lab)
	controller.vehicles.init(controller)
	var positions: Array[Vector2i] = [Vector2i(17, 18)]
	for slot in range(8): positions.append(SiteRuntime.siege_crew_cell(data, vehicle, str(slot)))
	positions.append(Vector2i(17, 21))
	var fixture := CrewFixture.new()
	fixture.setup(root, data, positions)
	lab.army = fixture.army
	lab.combat_armies.append(fixture.army)
	fixture.army.vehicle_transport = controller.vehicles
	fixture.army.exchange_enabled = true
	controller.work_team.init(lab)
	var coordinator := RamCoordinator.new()
	coordinator.register_formation(fixture.army)
	lab.combat_movement_coordinator = coordinator
	var commander := fixture.army.combat_identity(0)
	for slot in range(8): assert(controller.vehicles.assign_operator(key, fixture.army.combat_identity(slot + 1), commander, true).ok)
	controller.vehicles.update_siege(0.001)
	assert(controller.vehicles.crew_ready(vehicle))
	return {"data": data, "key": key, "vehicle": vehicle, "lab": lab, "controller": controller, "fixture": fixture, "commander": commander, "coordinator": coordinator}

func _deploy_tower(context: Dictionary) -> bool:
	var result: Dictionary = context.controller.vehicles.order_siege(context.key, "deploy", {}, int(context.commander), true)
	if not _require(result.ok, "Authorized original tower deployment failed: " + str(result)): return false
	_ram_ticks(context, 15.0)
	return _require(str(context.vehicle.phase) == "deployed" and not context.vehicle.deployed_pose.is_empty(), "Tower did not commit its original pose after 15 action seconds")

func _walk_tower_member(context: Dictionary, index: int, goal: Vector2i) -> bool:
	var army: TerrainArmy = context.fixture.army
	for _edge in range(40):
		if army.cells[index] == goal: return true
		var from: Vector2i = army.cells[index]
		var next := army._common_order_route_step(index, goal, 0)
		if not _require(next != TerrainArmy.INVALID_CELL, "Original Army route could not leave/reach tower: " + str({"from": from, "goal": goal, "phase": context.vehicle.phase})): return false
		if not _require(army._reserve_combat_step(index, next, 0, false, false, false, goal), "Original person step rejected its already checked tower edge: " + str({"from": from, "to": next, "goal": goal})): return false
		_ram_ticks(context, TerrainArmy.MOVE_DURATION)
		if not _require(army.cells[index] == next and army.moving_to[index] == TerrainArmy.INVALID_CELL, "Tower path did not finish its original person edge"): return false
	return _require(false, "Original tower path exceeded 40 legal edges")

func _check_tower_action_commit() -> bool:
	var context := _tower_context()
	var transport: SiteVehicleTransport = context.controller.vehicles
	var vehicle: Dictionary = context.vehicle
	var initial: Array[Vector2i] = context.fixture.army.cells.duplicate()
	var roof := Vector2i(21, 21)
	var order: Dictionary = transport.order_siege(context.key, "deploy", {}, int(context.commander), true)
	if not _require(order.ok, str(order)): return false
	_ram_ticks(context, 14.9)
	if not _require(context.data.effective_height(roof) == 0 and vehicle.deployed_pose.is_empty() and not transport.siege_save_guard().ok, "Deployment raised a roof before its original 15-second commit"): return false
	_ram_ticks(context, 0.1)
	if not _require(context.data.effective_height(roof) == 2 and str(vehicle.phase) == "deployed" and context.fixture.army.cells == initial and transport.crew_ready(vehicle), "Deployment moved original people or confused ground operator height with its own roof"): return false
	if not _require(not transport.order_siege(context.key, "move", {"type": "ground", "cell": [21, 20]}, int(context.commander), true).ok and not transport.order_siege(context.key, "turn", {"facing": [0, 1]}, int(context.commander), true).ok, "A retained tower bridge must be withdrawn before moving/turning"): return false
	var blocker := _add_projected_actor(context, roof, 900011)
	blocker.knockout_left = 4.0
	if not _require(not transport.order_siege(context.key, "retract", {}, int(context.commander), true).ok, "A KO original body must prevent empty-surface withdrawal"): return false
	context.lab.combat_actors.erase(blocker)
	blocker.free()
	context.fixture.army._reserved_cells[roof] = 9
	if not _require(not transport.order_siege(context.key, "retract", {}, int(context.commander), true).ok, "Original destination reservations must prevent tower withdrawal"): return false
	context.fixture.army._reserved_cells.erase(roof)
	if not _require(transport.order_siege(context.key, "retract", {}, int(context.commander), true).ok, "Empty original tower refused retraction"): return false
	_ram_ticks(context, 0.4)
	blocker = _add_projected_actor(context, roof, 900012)
	_ram_ticks(context, 0.1)
	if not _require(vehicle.action.is_empty() and str(vehicle.phase) == "deployed" and context.data.effective_height(roof) == 2, "Changed real surface occupancy did not cancel withdrawal while retaining the roof"): return false
	context.lab.combat_actors.erase(blocker)
	blocker.free()
	if not _require(transport.order_siege(context.key, "retract", {}, int(context.commander), true).ok, "Empty tower could not restart canceled withdrawal"): return false
	_ram_ticks(context, 9.9)
	if not _require(context.data.effective_height(roof) == 2 and str(vehicle.phase) == "deployed" and not transport.siege_save_guard().ok, "Retraction removed a surface before its ten-second commit"): return false
	_ram_ticks(context, 0.1)
	if not _require(context.data.effective_height(roof) == 0 and vehicle.deployed_pose.is_empty() and str(vehicle.phase) == "idle" and transport.siege_save_guard().ok, "Retraction did not settle the same original vehicle pose"): return false
	_close_ram(context)
	completed += 1
	return true

func _check_tower_original_person_path() -> bool:
	var context := _tower_context()
	var transport: SiteVehicleTransport = context.controller.vehicles
	if not _deploy_tower(context): return false
	if not _require(transport.unassign_crew(context.key, 0, int(context.commander), true).ok, "Deployed crew release failed"): return false
	if not _require(context.vehicle.crew_slots.is_empty() and str(context.vehicle.phase) == "deployed" and context.data.effective_height(Vector2i(21, 21)) == 2, "Crew absence deactivated an otherwise valid original roof"): return false
	if not _require(transport.blocks_cell(Vector2i(21, 21)) and not transport.blocks_person_cell(Vector2i(21, 21)), "Person-purpose roof must differ from physical construction/vehicle claims"): return false
	if not _walk_tower_member(context, 9, Vector2i(21, 21)): return false
	if not _require(context.data.effective_height(context.fixture.army.cells[9]) == 2, "Original Army person did not reach the derived roof"): return false
	for slot in range(8):
		if not _require(transport.assign_operator(context.key, context.fixture.army.combat_identity(slot + 1), int(context.commander), true).ok, "Deployed tower could not reassign its original ground operators"): return false
	transport.update_siege(0.001)
	if not _require(str(context.vehicle.phase) == "deployed" and transport.crew_ready(context.vehicle) and not transport.order_siege(context.key, "retract", {}, int(context.commander), true).ok, "Reassigned crew collapsed the roof or withdrew an occupied tower"): return false
	if not _walk_tower_member(context, 9, Vector2i(25, 21)): return false
	if not _require(transport.order_siege(context.key, "retract", {}, int(context.commander), true).ok, "Person safely reaching the wall did not free original tower withdrawal"): return false
	_ram_ticks(context, 10.0)
	_close_ram(context)
	completed += 1
	return true

func _check_tower_retained_pose_exit() -> bool:
	for wreck in [false, true]:
		var context := _tower_context()
		if not _deploy_tower(context): return false
		if not _walk_tower_member(context, 9, Vector2i(21, 21)): return false
		var source: Vector2i = context.fixture.army.cells[9]
		var before: PackedByteArray = context.data.navigation_heights().duplicate()
		if wreck: SiteRuntime.damage_siege_vehicle(context.data, context.key, 450.0)
		else:
			context.data.height_levels[context.data.index(Vector2i(25, 21))] = 0
			SiteRuntime.invalidate_siege_tower_supports(context.data)
		SiteEnvironment.rebuild_indexes(context.data)
		context.lab.resolve_structure_change(SiteRuntime.ok("original tower surface loss", {"lost_surfaces": {context.data.index(source): int(before[context.data.index(source)])}}))
		if not _require(context.fixture.army.cells[9] == source and is_equal_approx(float(context.fixture.army.combat_hot_get(9, &"hp")), 70.0) and context.controller.vehicles.footprint(context.data, context.vehicle).size() == 17, "Lost tower surface changed the original source, duplicated fall, or erased physical appendages"): return false
		if not _require(context.controller.vehicles.blocks_person_cell(source), "Ordinary outsiders must be blocked from retained disabled/wrecked ground"): return false
		context.data.height_levels[context.data.index(Vector2i(25, 21))] = 2
		SiteEnvironment.rebuild_indexes(context.data)
		if not _require(context.data.effective_height(source) == 0 and str(context.vehicle.phase) in ["disabled", "wrecked"], "Repairing a support silently raised an original fallen person"): return false
		context.fixture.army.prepare_combat(0.05, SiteCombatRules.KNOCKOUT_GAME_SECONDS)
		_ram_ticks(context, 2.3) # Original game-time KO expiry and 2.2-second get-up; no manual HP/KO reset.
		if not _require(context.fixture.army.combat_can_act(9) and context.fixture.army.cells[9] == source, "Original KO person could not wake at the retained source before exiting"): return false
		if not _walk_tower_member(context, 9, Vector2i(16, 21)): return false
		var outsider: int = context.fixture.army.combat_identity(9)
		if not _require(context.controller.vehicles.blocks_person_step(outsider, Vector2i(16, 21), Vector2i(17, 21), Vector2i(18, 21), Vector2i(21, 21)), "Outside people or exited originals reentered a retained wreck"): return false
		_close_ram(context)
	completed += 1
	return true
