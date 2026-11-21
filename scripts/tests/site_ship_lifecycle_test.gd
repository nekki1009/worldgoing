extends "res://scripts/tests/site_ship_transport_test.gd"
## Original death, inventory, movement, loot and save owners; no surrogate rows.

var original_rows: Array[Dictionary] = []
var original_holders: Array[Dictionary] = []

func _must(condition: bool, reason: String) -> bool:
	if condition: return true
	push_error("SHIP_LIFECYCLE_FAIL: " + reason)
	quit(1)
	return false

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		_must(false, "Original lifecycle fixture exceeded its sixty-second deadline")
	return false

func _walk_checked(index: int, goal: Vector2i) -> bool:
	var start := team.cells[index]
	var identity := people[index]
	var route: Array[Vector2i] = team.data.path_between(start, goal, func(cell: Vector2i) -> bool:
		return team.blocks_cell(cell) or team._is_external_cell(cell, identity))
	if not _must(start == goal or not route.is_empty(), "Original pier route is absent: " + str({"id": identity, "start": start, "goal": goal})): return false
	if not _must(route.size() <= 256, "Original pier route exceeded the finite fixture budget"): return false
	for next: Vector2i in route:
		if not _must(team._reserve_combat_step(index, next), "Original shore reservation failed: " + str({"id": identity, "from": team.cells[index], "next": next})): return false
		team.prepare_combat(float(team.move_duration[index]) + 0.01)
		if not _must(team.cells[index] == next and team.moving_to[index] == TerrainArmy.INVALID_CELL, "Original shore step did not commit"): return false
	return true

func _finish_checked(identity: int, ship_job: bool = true) -> bool:
	var actions: SitePersonActions = lab.site_controller.person_actions
	if not _must(actions.is_busy(identity) and actions._jobs.has(str(identity)), "Original person job is absent"): return false
	var job: Dictionary = actions._jobs[str(identity)]
	var remaining := maxf(0.01, float(job.duration) - float(job.elapsed) + 0.01)
	if ship_job: actions.advance_ship_jobs(remaining)
	else: actions.advance(remaining)
	var results: Array[Dictionary] = actions.settle_after_contacts()
	if not _must(not actions.is_busy(identity), "Original person job did not finish"): return false
	for result: Dictionary in results:
		if int(result.get("executor_id", 0)) == identity:
			return _must(bool(result.get("ok", false)), "Original person job rejected: " + str(result))
	return _must(false, "Original job completed without its own settlement result")

func _board_checked(index: int, boat_id: String) -> bool:
	if not _walk_checked(index, Vector2i(29, 20)): return false
	var actions: SitePersonActions = lab.site_controller.person_actions
	var begun: Dictionary = actions.begin_ship_board(people[index], boat_id, people[index], index, true)
	if not _must(begun.ok, "Original boarding rejected: " + str(begun)): return false
	if not _finish_checked(people[index]): return false
	return _must(str(team.combat_units[index].get("embarked_vehicle_id", "")) == boat_id and int(team.combat_units[index].get("berth_id", -1)) == index and not team._cell_owners.values().has(index), "Original boarding must commit its berth and release its shore claim")

func _original_people_unchanged() -> bool:
	if not _must(team.combat_units.size() == 4, "Lifecycle must retain exactly four original GD rows"): return false
	for index in range(4):
		if not _must(team.combat_identity(index) == people[index] and is_same(team.combat_units[index], original_rows[index]) and is_same(team.combat_units[index].item_state, original_holders[index]), "Death or collection replaced an original person ID, row or holder"): return false
	return true

func _validate_original_vehicles() -> bool:
	var controller: SiteController = lab.site_controller
	controller._capture_positions()
	var valid: Dictionary = Store._validate_vehicles(lab.terrain, lab.terrain.site, true)
	return _must(valid.ok, "Original captured vehicle save state rejected: " + str(valid))

func _run() -> void:
	if not _must(DisplayServer.get_name() == "headless", "Lifecycle entrypoint requires canonical headless verification"): return
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	var controller: SiteController = lab.site_controller
	controller.set_process(false)
	controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for original: TerrainArmy in lab.combat_armies: original.set_process(false)
	_water_fixture() # Existing explicit water fixture; original queries stay intact.
	var data: TerrainData = lab.terrain
	team = lab.army
	team.role = "logistics"
	team.team_id = lab._next_army_identity()
	team.roster_size = 4
	var cells: Array[Vector2i] = [Vector2i(29, 20), Vector2i(25, 23), Vector2i(25, 24), Vector2i(25, 25)]
	if not _must(team.deploy_at(data, lab.character, lab.npc, cells), "Original four-person deployment rejected"): return
	if not _must(team.enable_combat(false, 0), "Original four-person combat/item initialization rejected"): return
	data.site.army_next_team = team.team_id + 1
	data.site.army_trial_active = true
	data.site.inventory.grain = 200 # Explicit initial depot stock; all later moves use original transactions.
	data.site.depot_cell = data.index(Vector2i(28, 20))
	var people_load := 0.0
	for index in range(4):
		people.append(team.combat_identity(index))
		team.combat_units[index].logistics = true
		original_rows.append(team.combat_units[index])
		original_holders.append(team.combat_units[index].item_state)
		people_load += Runtime.carried_load(data.site, team.combat_units[index].cargo, original_holders[index]) + float(original_holders[index].equipped.size())
	var vehicles: SiteVehicleTransport = controller.vehicles
	var actions: SitePersonActions = controller.person_actions
	var deployed: Dictionary = vehicles.deploy_ship(team, "ferry", Vector2i(30, 20), Vector2i.UP, true)
	if not _must(deployed.ok, "Original ferry deployment rejected: " + str(deployed)): return
	var boat_id := str(deployed.vehicle_id)
	var boat: Dictionary = vehicles.records()[boat_id]
	var capacity := float(Ship.definition("ferry").capacity)
	var initial_grain := capacity - people_load
	if not _must(initial_grain >= 2.0 and is_equal_approx(initial_grain, roundf(initial_grain)), "Original four-person equipment leaves no integral full-Q stock fixture"): return
	var loaded: Dictionary = vehicles.transfer("depot", boat_id, {"grain": int(initial_grain)}, [], int(data.site.depot_items.version), int(boat.holder.version), people[0], true)
	if not _must(loaded.ok, "Actual initial depot-to-boat transaction rejected: " + str(loaded)): return
	for index in range(4):
		if not _board_checked(index, boat_id): return
	if not _must(vehicles.ship_people(boat).size() == 4 and is_equal_approx(vehicles.ship_load(boat_id), capacity), "Actual four-passenger boat must start exactly at full Q"): return
	var driver: Dictionary = team.combat_units[0]
	var driver_items: Array = driver.item_state.item_ids.duplicate()
	if not _must(not driver_items.is_empty(), "Original driver must initially own actual equipped items"): return
	var ration: Dictionary = vehicles.transfer(boat_id, "person:%d" % people[0], {"grain": 1}, [], int(boat.holder.version), int(driver.item_state.version), people[0], true)
	if not _must(ration.ok, "Actual driver cargo transaction rejected: " + str(ration)): return
	var emptied: Dictionary = vehicles.transfer("person:%d" % people[0], boat_id, driver.cargo.duplicate(), driver_items, int(driver.item_state.version), int(boat.holder.version), people[0], true)
	if not _must(emptied.ok, "Actual complete driver-to-boat transaction rejected: " + str(emptied)): return
	controller.equipment_changed(people[0])
	if not _must(driver.cargo.is_empty() and driver.item_state.item_ids.is_empty() and driver.item_state.equipped.is_empty() and float(controller._personal_opened_food(people[0]).get("open_rations", 0.0)) == 0.0, "Driver EMPTY must result from original transfer, without clearing belongings"): return
	for item_id: String in driver_items:
		if not _must(boat.holder.item_ids.has(item_id) and str(data.site.item_records[item_id].holder) == str(boat.holder.holder), "Actual driver items must now belong to the original boat holder"): return
	var helm: Dictionary = actions.begin_ship_helm(people[0], boat_id, people[0], true)
	if not _must(helm.ok, "Original driver helm job rejected: " + str(helm)): return
	if not _finish_checked(people[0]): return

	# Case 1: genuine EMPTY death during a genuine committed boat half-step.
	var ordered: Dictionary = vehicles.ship_order(boat_id, "forward", TerrainArmy.INVALID_CELL, people[0], true)
	if not _must(ordered.ok, "Original half-step departure rejected: " + str(ordered)): return
	vehicles.update_ships(float(boat.move.duration) * 0.5)
	var committed: Dictionary = boat.move.duplicate(true)
	var original_anchor := int(boat.cell)
	var next_loot := int(data.site.next_loot)
	var loot_count: int = data.site.ground_loot.size()
	var boat_items: Array = boat.holder.item_ids.duplicate()
	var boat_cargo: Dictionary = boat.cargo.duplicate(true)
	if not _must(not committed.is_empty() and float(committed.elapsed) > 0.0 and float(committed.elapsed) < float(committed.duration), "Original boat must actually be halfway through its committed step"): return
	team.apply_unit_contact(0, {"result": {"hp": 10000.0, "stun": 0.0, "guard_break": false}, "shield": false})
	if not _must(vehicles.ship_people(boat).size() == 3 and is_equal_approx(vehicles.ship_load(boat_id), capacity), "Driver death must immediately release N while preserving full Q"): return
	controller.settle_person_deaths(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"]) + 0.5)
	if not _must(driver.get("loot_settled", false) == true and driver.get("ship_death_settled", false) == true and not driver.has("embarked_vehicle_id") and not driver.has("berth_id") and str(driver.get("remains_id", "")) == "", "Original EMPTY death must settle locally during the committed hull step and release its berth"): return
	if not _must(int(data.site.next_loot) == next_loot and data.site.ground_loot.size() == loot_count and boat.holder.item_ids == boat_items and boat.cargo == boat_cargo and is_equal_approx(vehicles.ship_load(boat_id), capacity), "EMPTY death must allocate no container and preserve actual boat cargo/items/Q"): return
	if not _must(boat.move == committed and int(boat.cell) == original_anchor and bool(boat.stop_pending) and boat.command.is_empty() and int(boat.operator_id) == people[0], "Dead operator must retain exactly the committed half-step and historical ID with stop_pending"): return
	vehicles.update_ships(0.001)
	if not _must(not boat.move.is_empty() and int(boat.cell) == original_anchor and int(boat.move.from_cell) == int(committed.from_cell) and int(boat.move.cell) == int(committed.cell) and boat.move.sweep == committed.sweep and is_equal_approx(float(boat.move.elapsed), float(committed.elapsed) + 0.001) and bool(boat.stop_pending), "Small death-stop tick must advance the original half-step once without rollback"): return
	if not _validate_original_vehicles(): return
	vehicles.update_ships(float(committed.duration))
	if not _must(boat.move.is_empty() and int(boat.cell) == int(committed.cell) and boat.command.is_empty() and not bool(boat.stop_pending) and int(boat.operator_id) == 0, "Original committed step must finish once and leave the dead-driver boat stopped"): return
	if not _validate_original_vehicles() or not _original_people_unchanged(): return
	print("SITE_SHIP_LIFECYCLE_EMPTY_HALF_STEP_PASS")

	# Case 2: one original allocation preflight failure, then one corrected retry.
	var passenger: Dictionary = team.combat_units[1]
	var passenger_items: Array = passenger.item_state.item_ids.duplicate()
	var passenger_slots: Dictionary = passenger.item_state.equipped.duplicate(true)
	if not _must(not passenger_items.is_empty() and not passenger_slots.is_empty(), "Original next passenger must retain equipped goods for the death case"): return
	var passenger_cargo: Dictionary = passenger.cargo.duplicate(true)
	var holder_version := int(passenger.item_state.version)
	var available_counter := int(data.site.next_loot)
	data.site.next_loot = 2147483647 # Explicit failure injection; restore this exact counter once.
	team.apply_unit_contact(1, {"result": {"hp": 10000.0, "stun": 0.0, "guard_break": false}, "shield": false})
	controller.settle_person_deaths(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"]) + 0.5)
	if not _must(vehicles.ship_people(boat).size() == 2 and is_equal_approx(vehicles.ship_load(boat_id), capacity) and data.site.ground_loot.size() == loot_count and int(data.site.next_loot) == 2147483647, "Rejected original death preflight must release N, keep full pending Q and allocate nothing"): return
	if not _must(passenger.get("loot_settled", false) != true and str(passenger.get("embarked_vehicle_id", "")) == boat_id and passenger.item_state.item_ids == passenger_items and passenger.item_state.equipped == passenger_slots and passenger.cargo == passenger_cargo and int(passenger.item_state.version) == holder_version, "Failed death must retain the same original pending holder, cargo and ship relation"): return
	var pending_guard: Dictionary = controller.supply_save_guard()
	if not _must(pending_guard.code == "BUSY" and controller._pending_deaths.has(people[1]), "Original Controller save guard must retain and refuse the pending failed death"): return
	data.site.next_loot = available_counter
	controller.settle_person_deaths(0.0)
	var remains_id := str(passenger.get("remains_id", ""))
	if not _must(remains_id == str(available_counter) and data.site.ground_loot.has(remains_id) and data.site.ground_loot.size() == loot_count + 1 and int(data.site.next_loot) == available_counter + 1, "Corrected original death retry must allocate exactly one original container"): return
	var remains: Dictionary = data.site.ground_loot[remains_id]
	if not _must(str(remains.vehicle_id) == boat_id and not remains.has("cell") and remains.local_position.size() == 2 and int(remains.original_owner) == people[1] and remains.item_ids == passenger_items and remains.equipped == passenger_slots and remains.cargo == passenger_cargo, "One death container must preserve original goods and their exact boat-relative owner"): return
	if not _must(passenger.get("ship_death_settled", false) == true and passenger.get("loot_settled", false) == true and not passenger.has("embarked_vehicle_id") and not passenger.has("berth_id") and not controller._pending_deaths.has(people[1]) and is_equal_approx(vehicles.ship_load(boat_id), capacity), "Successful retry must settle the original death and conserve full Q"): return
	controller.settle_person_deaths(1.0)
	if not _must(data.site.ground_loot.size() == loot_count + 1 and int(data.site.next_loot) == available_counter + 1 and is_same(data.site.ground_loot[remains_id], remains), "Settled death cannot duplicate its original container on another settlement call"): return
	if not _validate_original_vehicles() or not _original_people_unchanged(): return
	print("SITE_SHIP_LIFECYCLE_FAILED_DEATH_RETRY_PASS")

	# Case 3: actual same-boat loot jobs at full Q, then original empty recycling.
	var snapshot: Dictionary = data.site.armies[0].units[1]
	if not _must(str(snapshot.remains_id) == remains_id and str(passenger.remains_id) == remains_id, "Original captured and live death rows must both reference the same container"): return
	data.site.controlled_person_id = people[2] # The original living row executes its own job.
	var batches: int = remains.item_ids.size() + int(not remains.cargo.is_empty()) + int(float(remains.get("open_rations", 0.0)) > 0.0)
	if not _must(batches > 0 and batches <= 32, "Actual original remains need a finite nonempty collection fixture"): return
	for _batch in range(batches):
		if not _must(data.site.ground_loot.has(remains_id), "Original remains disappeared before the final actual collection"): return
		var resources: Dictionary = {}
		var items: Array = []
		var open_amount := 0.0
		if not remains.item_ids.is_empty(): items.append(remains.item_ids[0]) # Worn items use the original one-item removal job.
		elif not remains.cargo.is_empty(): resources = remains.cargo.duplicate()
		else: open_amount = float(remains.get("open_rations", 0.0))
		var begun: Dictionary = actions.begin_loot(people[2], "ground", remains_id, resources, items, open_amount)
		if not _must(begun.ok, "Original full-Q same-boat loot admission rejected: " + str(begun)): return
		if not _finish_checked(people[2], false): return
		if not _must(is_equal_approx(vehicles.ship_load(boat_id), capacity) and vehicles.ship_people(boat).size() == 2, "Same-boat loot must preserve full original Q and N after each actual batch"): return
	if not _must(not data.site.ground_loot.has(remains_id) and str(passenger.remains_id) == "" and str(snapshot.remains_id) == "", "Original empty recycling must clear both live and captured remains references"): return
	for item_id: String in passenger_items:
		if not _must(team.combat_units[2].item_state.item_ids.has(item_id) and str(data.site.item_records[item_id].holder) == str(team.combat_units[2].item_state.holder), "Original collected goods must belong to the same living person's holder"): return
	if not _validate_original_vehicles() or not _original_people_unchanged(): return
	if not _must(controller.supply_save_guard().ok, "Settled original lifecycle must release its pending death/job save guards"): return
	print("SITE_SHIP_LIFECYCLE_PASS: EMPTY half-step death, historical stop save, one failed allocation and corrected original retry, full-Q same-boat loot and original live/snapshot empty cleanup")
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	quit(0)
