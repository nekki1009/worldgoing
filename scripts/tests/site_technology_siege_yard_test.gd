extends "res://scripts/tests/site_technology_armor_recipes_test.gd"
## Original training-ground geometry, 40 true resident rows and actual paid
## upgrades, real six-person WT registry/planner work, Store wire round trip.
## Fixture moves true initial hot cells directly (no route/Native/GPU proof).
## S11 must be enabled by the guarded original-owner implementation candidate.

const YardStore = preload("res://scripts/terrain_lab/site_store.gd")
const YardTraining = preload("res://scripts/terrain_lab/site_training_ground.gd")
const YardView = preload("res://scripts/terrain_lab/site_resource_view.gd")
const YardCoordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")

func _yard_fixture(known: bool = true) -> Dictionary:
	var fixture := _armor_fixture(false)
	var data: TerrainData = fixture.data
	var team: TerrainArmy = fixture.team
	fixture.row.technology = Technology.learned_candidate(fixture.row.technology, "F11")
	data.site.family.technology.known = ["F04", "F11", "F14"]
	data.site.settlement.technology.known = ["S11"] if known else []
	fixture.yard = _cold_natural_feature(data, "training_ground", Vector2i(21, 41) + Vector2i(fixture.natural_offset), Vector2i(10, 10))
	team.cells[1] = Vector2i(22, 42) + Vector2i(fixture.natural_offset) # Rows 41 and 50 hold the ground's own racks; rows 44-46 hold the ballista stations.
	fixture.ids = []
	for index: int in range(1, 7): fixture.ids.append(team.combat_identity(index))
	return fixture

func _yard_guards_and_revoke() -> void:
	var fixture := _yard_fixture()
	var data: TerrainData = fixture.data
	var feature: Dictionary = data.site.features[fixture.yard]
	var row: Dictionary = fixture.row
	var before := var_to_bytes([data.site, row])
	_check(Runtime.is_training_facility(feature), "The genuine original ground initially retains its original training use")
	_check(Runtime.configure_siege_yard(data, str(fixture.yard), int(fixture.control), int(fixture.executor), true, true).ok and var_to_bytes([data.site, row]) == before, "Actual head/F11 master preview is entirely readonly")
	_check(not Runtime.configure_siege_yard(data, str(fixture.yard), int(fixture.executor), int(fixture.executor)).ok and var_to_bytes([data.site, row]) == before, "A genuine non-head cannot use the facility config as authority")
	var old_skill: Dictionary = row.technology
	row.technology = {}
	before = var_to_bytes([data.site, row])
	_check(not Runtime.configure_siege_yard(data, str(fixture.yard), int(fixture.control), int(fixture.executor)).ok and var_to_bytes([data.site, row]) == before, "Unlearned actual person fails before any config/stock/effort change")
	row.technology = old_skill
	for index: int in range(40): fixture.team.cells[index] = Vector2i(21 + index % 10, [42, 43, 47, 48][floori(float(index) / 10.0)]) + Vector2i(fixture.natural_offset)
	var captain_index = fixture.team.index_for_identity(fixture.team.duty_decider("team.training"))
	_check(fixture.lab.site_controller.order_team_training(fixture.team, captain_index, true, str(fixture.yard)).ok, "Original Training/Supply owners establish their actual bounded training order on the true ground")
	before = var_to_bytes(data.site)
	_check(not Runtime.configure_siege_yard(data, str(fixture.yard), int(fixture.control), int(fixture.executor)).ok and var_to_bytes(data.site) == before, "The actual original training order prevents adopting its occupied ground")
	_check(fixture.lab.site_controller.order_team_training(fixture.team, captain_index, false).ok, "Original current team authority stops its own actual training order")
	_check(Runtime.configure_siege_yard(data, str(fixture.yard), int(fixture.control), int(fixture.executor)).ok, "Original head explicitly designates the true completed ground")
	_check(feature.kind == "training_ground" and feature.technology_siege_yard == {"version": 1, "settlement_id": fixture.settlement_id} and not Runtime.is_training_facility(feature), "Exact original feature config reuses the training-ground asset and prevents simultaneous training")
	var presenter := YardView.new()
	presenter.data = data
	_check(presenter.building_art_key(feature) == "road" and presenter.building_art_available(feature), "Original presenter keeps the already approved genuine training-ground asset")
	presenter.free()
	_check(not YardTraining.inspect(fixture.lab.site_controller, int(fixture.team.team_id), str(fixture.yard)).ok, "Original Training owner rejects the actually designated ground")
	before = var_to_bytes(data.site)
	_check(Runtime.technology_siege_yard_context(data, str(fixture.yard), false).ok and Runtime.technology_siege_yard_context(data, str(fixture.yard)).ok and var_to_bytes(data.site) == before, "Geometry and current work queries preserve all original owner dictionaries")
	var malformed := feature.duplicate(true)
	malformed.technology_siege_yard.extra = true
	_check(not Runtime.valid_technology_siege_yard(malformed) and not Runtime.validate_feature_layout(data, malformed).ok, "Extra/malformed config is rejected strictly rather than falling back to the old ground")
	var forged := feature.duplicate(true)
	forged.technology_siege_yard.settlement_id = "wrong-original-settlement"
	var original: Dictionary = data.site.features[fixture.yard]
	data.site.features[fixture.yard] = forged
	before = var_to_bytes(data.site)
	_check(not Runtime.technology_siege_yard_context(data, str(fixture.yard), false).ok and var_to_bytes(data.site) == before, "A foreign original key cannot masquerade as this yard")
	data.site.features[fixture.yard] = original
	var housing: Dictionary = data.site.housing
	data.site.housing = {}
	_check(Runtime.technology_siege_yard_context(data, str(fixture.yard), false).ok and not Runtime.technology_siege_yard_context(data, str(fixture.yard)).ok, "Loss of true residents suspends work while retaining six-slot geometry")
	_check(Runtime.configure_siege_yard(data, str(fixture.yard), int(fixture.control), 0, false).ok and Runtime.is_training_facility(feature), "Original current head may revoke a clear suspended yard and recover its actual training use")
	data.site.housing = housing
	for index: int in range(40): fixture.team.cells[index] = Vector2i(21 + index % 10, [42, 43, 47, 48][floori(float(index) / 10.0)]) + Vector2i(fixture.natural_offset)
	_check(YardTraining.inspect(fixture.lab.site_controller, int(fixture.team.team_id), str(fixture.yard)).ok, "After revocation the original training owner again admits the real original team on the same genuine ground")
	_cleanup_fixture(fixture.lab, fixture.team)
	await process_frame

func _yard_work_point(fixture: Dictionary, seconds: float) -> Dictionary:
	var lab: TerrainLab = fixture.lab
	var workers = lab.site_controller.work_team
	var requests = workers.prepare_work_requests(seconds)
	lab._shared_work_requests = requests
	_check(lab._refresh_shared_work_preflight().ok, "Actual original final WorkTeam requests are revalidated at the real stations")
	var captured = workers.prepare_shared_work_prefix(seconds)
	var planned := PersonFatigue.plan_work_interval(lab._shared_work_requests, seconds)
	_check(captured.ok and planned.ok, "Original six-person refs and the true existing fatigue planner capture this actual interval")
	var priors: Array = []
	var before := var_to_bytes([lab.terrain.site, fixture.team.capture_combat_state()])
	var admitted = workers.validate_shared_work_prefix(captured, planned, priors)
	_check(admitted.ok and var_to_bytes([lab.terrain.site, fixture.team.capture_combat_state()]) == before, "All actual six-person Runtime prefix candidates are prepared before stock or effort changes")
	lab._shared_work_plan = planned
	lab.site_controller._shared_work_plan = planned
	lab._shared_work_pools_committed = false
	lab._commit_shared_work_pools()
	var handled = workers.publish_shared_work_prefix(admitted)
	var retained := var_to_bytes(fixture.vehicle)
	var fatigue: Dictionary = fixture.team.team_fatigue.duplicate(true)
	workers.publish_shared_work_prefix(admitted)
	lab._commit_shared_work_pools()
	_check(var_to_bytes(fixture.vehicle) == retained and fixture.team.team_fatigue == fatigue, "Same registered six-person publication spends physical work and pooled fatigue once")
	workers.finish_shared_work_prefix(admitted)
	return {"admitted": admitted, "handled": handled, "plan": planned}

func _yard_move_out(fixture: Dictionary) -> void:
	var team: TerrainArmy = fixture.team
	var lab: TerrainLab = fixture.lab
	var vehicle: Dictionary = fixture.vehicle
	var transport = lab.site_controller.vehicles
	# Initial placement of true existing crew is fixture setup. Subsequent travel
	# uses the actual original Grid/coordinator and committed adjacent Army moves.
	for index: int in range(1, 7): team.cells[index] = Vector2i(9 + index, 49) + Vector2i(fixture.natural_offset)
	for slot: int in range(2): team.cells[slot + 1] = transport.crew_cell(vehicle, str(slot))
	team.settle_combat_command()
	var coordinator := YardCoordinator.new()
	coordinator.register_formation(team)
	lab.combat_movement_coordinator = coordinator
	var captain := team.combat_identity(team.current_commander)
	for slot: int in range(2):
		_check(transport.assign_crew(str(fixture.key), team.combat_identity(slot + 1), str(slot), captain, true).ok, "Original current captain assigns an actual original person to the genuine completed vehicle's original crew slot")
	transport.update_siege(0.01)
	_check(transport.crew_ready(vehicle), "True original crew can stand on their actual original designated-ground stations")
	# The ballista is a fixed engine (move_speed 0): it is never pushed off the yard.
	# Its geometry source stays until the lawful removal below; once complete it keeps
	# only its original four repair contacts.
	var pushed: Dictionary = transport.order_siege(str(fixture.key), "move", {"type": "ground", "cell": [34 + int(fixture.natural_offset.x), 44 + int(fixture.natural_offset.y)]}, captain, true)
	_check(not pushed.ok and pushed.get("code") == "INVALID_ORDER" and vehicle.move.is_empty() and vehicle.has("technology_yard_id"), "The fixed original ballista refuses travel and keeps its yard geometry source")
	_check(Runtime.siege_work_slots(lab.terrain, vehicle).size() == 4 and transport.siege_save_guard().ok, "The completed original equipment retains its original four repair contacts and a settled save boundary")
	_check(transport.unassign_crew(str(fixture.key), 0, captain, true).ok, "Actual original current captain releases the same original crew before removing the empty engine")
	coordinator.unregister_formation(team)
	lab.combat_movement_coordinator = null

func _six_actual_workers_and_save() -> void:
	var fixture := _yard_fixture()
	var data: TerrainData = fixture.data
	var lab: TerrainLab = fixture.lab
	var team: TerrainArmy = fixture.team
	var workers = lab.site_controller.work_team
	_check(Runtime.configure_siege_yard(data, str(fixture.yard), int(fixture.control), int(fixture.executor)).ok, "The original head configures this real six-slot workshop once")
	var camp = data.site.inventory.duplicate(true)
	var started := Runtime.begin_siege_build(data, "ballista", Vector2i(24, 44) + Vector2i(fixture.natural_offset), Vector2i.DOWN, int(team.team_id), int(fixture.control))
	_check(started.ok, "Ordinary known S11 starts a real finite original paid ballista batch on its actual designated ground")
	fixture.key = str(started.vehicle)
	fixture.vehicle = data.site.vehicles[fixture.key]
	var vehicle: Dictionary = fixture.vehicle
	_check(vehicle.technology_yard_id == fixture.yard and vehicle.tech_batch.token.is_empty() and int(vehicle.tech_batch.operator_id) == 0, "Only true original geometry provenance and a shared ordinary payment ledger are stored")
	for material: String in Runtime.SIEGE_DEFINITIONS.ballista.cost:
		_check(int(data.site.inventory[material]) == int(camp[material]) - int(Runtime.SIEGE_DEFINITIONS.ballista.cost[material]), "Original ballista consumes its entire actual %s cost once" % material)
	var slots := Runtime.siege_work_slots(data, vehicle)
	_check(slots.size() == 6 and slots[4].cell != slots[5].cell, "The genuine vehicle has six unique actual original work cells")
	var worker_ids: Array[int] = []
	worker_ids.assign(fixture.ids) # A Dictionary field holds an untyped Array; the owner takes Array[int].
	_check(workers.assign(team, worker_ids, team.duty_decider("team.work")).ok, "Actual original current team duty assigns six real existing members")
	workers.prepare_work_requests(30.0)
	var claimed := {}
	for identity: int in fixture.ids:
		var index := team.index_for_identity(identity)
		var row: Dictionary = team.combat_units[index]
		var task: Dictionary = row.work_task
		_check(task.target == "vehicle:" + fixture.key and not claimed.has(int(task.work_slot)), "Each actual person holds a different original vehicle work slot")
		claimed[int(task.work_slot)] = true
		team.cells[index] = data.cell_from_index(int(task.work_cell))
		# The placed body has no pending step or walking pose left from its cancelled route.
		team.moving_to[index] = TerrainArmy.INVALID_CELL
		team.combat_hot_set(index, &"pose", "idle")
		task.cell = int(task.work_cell)
		task.mode = "work"
		_check(SiteWorkTeam.valid_task(data, data.site, task), "Real original task validator accepts this actual designated slot")
	_check(claimed.has(4) and claimed.has(5), "The fifth and sixth genuine Army people actually claim slots 4 and 5")
	var seventh := team.combat_identity(7)
	var seventh_ids: Array[int] = [seventh]
	_check(workers.assign(team, seventh_ids, team.duty_decider("team.work")).ok, "Original current team duty may assign another actual member through its existing operation")
	workers.prepare_work_requests(30.0)
	_check(team.combat_units[7].work_task.get("target", "") != "vehicle:" + fixture.key, "The actual original selector leaves the seventh worker waiting instead of overbooking any of the six claimed slots")
	workers.cancel(seventh)
	var before := var_to_bytes(data.site)
	var archive := var_to_bytes([data.site.settlement.technology, data.site.family.technology])
	var point := _yard_work_point(fixture, 30.0)
	_check(float(vehicle.build.progress) == 180.0 and float(vehicle.tech_batch.work_seconds) == 180.0 and point.admitted.runtime.size() == 6, "Six true accepted original contributions produce 180 physical seconds and 180 real shared effort, without double weighting")
	for slot_number: int in [4, 5]:
		var witnessed := false
		for actual: Dictionary in point.admitted.runtime:
			if int(actual.task.work_slot) == slot_number:
				witnessed = float(actual.prefix_ref.productive_seconds) > 0.0 and is_same(actual.prefix_ref.start.row, team.combat_units[team.index_for_identity(int(actual.identity))])
		_check(witnessed, "Original registered slot %d has a positive actual original-person effort witness" % slot_number)
	_check(var_to_bytes([data.site.settlement.technology, data.site.family.technology]) == archive, "Ordinary shared work neither credits a personal trial nor invents scope research")
	before = var_to_bytes([data.site, team.capture_combat_state()])
	_check(not Runtime.configure_siege_yard(data, str(fixture.yard), int(fixture.control), 0, false).ok and var_to_bytes([data.site, team.capture_combat_state()]) == before, "A true physical vehicle/work order prevents premature yard revocation")
	var housing: Dictionary = data.site.housing
	data.site.housing = {}
	_check(Runtime.siege_work_slots(data, vehicle).size() == 6 and not Runtime.work_preflight(data, fixture.row.work_task, fixture.row.cargo, Runtime.CARRY_CAPACITY, 1, int(fixture.executor)).ok, "Suspension preserves actual slot 4/5 geometry and paid progress but admits no new work")
	lab.site_controller._capture_positions()
	var saved := YardStore.save(data, "user://technology_s11_suspended_yard.json")
	_check(saved.ok, "Original Store saves the genuinely suspended six-slot paid target and real original task bodies")
	var source_fingerprint := data.fingerprint()
	var source_conditions := _cold_natural_conditions(data)
	var loaded := YardStore.load_site("user://technology_s11_suspended_yard.json")
	_check(loaded.ok, "Original strict loader accepts the saved suspended yard without needing current effect or shrinking slots")
	_check(loaded.data.fingerprint() == source_fingerprint and _cold_natural_conditions(loaded.data) == source_conditions, "Original yard Store replay retains the same natural terrain and all five actual land conditions")
	var restored: TerrainData = loaded.get("data", loaded.get("terrain"))
	_check(restored != null and restored.site.features[fixture.yard].technology_siege_yard == {"version": 1, "settlement_id": fixture.settlement_id} and Runtime.siege_work_slots(restored, restored.site.vehicles[fixture.key]).size() == 6, "Original saved config and fifth/sixth physical work cells survive an actual round trip")
	for raw: Dictionary in restored.site.armies[0].units:
		if raw.get("work_task", {}).get("target") == "vehicle:" + fixture.key:
			_check(SiteWorkTeam.valid_task(restored, restored.site, raw.work_task), "Every true restored task validates its same saved original slot")
	data.site.housing = housing
	# Direct completion exercises only the original geometry endpoint; the prior
	# six-person point above is the actual planner/Fatigue proof, not this call.
	var task: Dictionary = fixture.row.work_task
	var done := Runtime.advance_siege_work(data, str(fixture.key), "construct", float(vehicle.build.total_work) - float(vehicle.build.progress), team.cells[1], int(task.work_slot), int(team.team_id), task, int(fixture.executor))
	_check(done.ok and done.complete and vehicle.phase == "idle" and vehicle.build.is_empty() and not vehicle.has("tech_batch"), "The actual same-original paid engine completes by its current true F11 worker and consumes the finite current batch")
	_check(vehicle.technology_construction.operator_id == fixture.executor and vehicle.technology_construction.materials == Runtime.SIEGE_DEFINITIONS.ballista.cost and Runtime.validate_technology_yard_vehicle(data, vehicle).ok, "Original completed physical receipt records the true finishing master and full original material history without personal research credit")
	# Since the 10/09 family siege history, a member's completed build is recorded as
	# history only; known nodes, projects and the Settlement archive stay unchanged.
	var prior_archive: Array = bytes_to_var(archive)
	var family_after: Dictionary = data.site.family.technology
	var history: Array = family_after.get("siege_history", [])
	_check(data.site.settlement.technology == prior_archive[0] and family_after.known == prior_archive[1].known and family_after.projects == prior_archive[1].projects
		and int(family_after.active) == int(prior_archive[1].active) and history.size() == 1 and history[0].get("vehicle_id") == fixture.key and int(history[0].get("person_id", -1)) == int(fixture.executor),
		"Ordinary physical completion leaves research archives unchanged and records one family siege history entry")
	for identity: int in fixture.ids: workers.cancel(identity)
	_yard_move_out(fixture)
	_check(Runtime.remove_siege_vehicle(data, str(fixture.key), int(team.team_id)).ok, "Original vehicle owner lawfully removes the completed empty engine, retaining spent construction costs")
	_check(Runtime.configure_siege_yard(data, str(fixture.yard), int(fixture.control), 0, false).ok and Runtime.is_training_facility(data.site.features[fixture.yard]), "The real cleared original plot can be revoked after its true tasks and physical engine are gone")
	_cleanup_fixture(lab, team)
	await process_frame

func _wreck_retains_spent_history() -> void:
	var fixture := _yard_fixture()
	var data: TerrainData = fixture.data
	_check(Runtime.configure_siege_yard(data, str(fixture.yard), int(fixture.control), int(fixture.executor)).ok, "Actual original head adopts the genuine clear ground for the wreck boundary fixture")
	var started := Runtime.begin_siege_build(data, "ballista", Vector2i(24, 44) + Vector2i(fixture.natural_offset), Vector2i.DOWN, int(fixture.team.team_id), int(fixture.control))
	_check(started.ok, "Original finite manufacture pays its actual complete cost before any wreck occurs")
	var key := str(started.vehicle)
	var vehicle: Dictionary = data.site.vehicles[key]
	var spent := var_to_bytes(data.site.inventory)
	var archive := var_to_bytes([data.site.family.technology, data.site.settlement.technology])
	_check(Runtime.damage_siege_vehicle(data, key, float(vehicle.hp)).ok and vehicle.phase == "wrecked" and vehicle.build.is_empty(), "Original fatal damage clears its original build job without manufacturing an output")
	_check(not vehicle.has("technology_construction") and Runtime.validate_technology_yard_vehicle(data, vehicle).ok and Runtime.validate_technology_target_storage(data, key, vehicle, "vehicle").ok, "A true destroyed original paid batch remains strict spent history and is never a completion receipt")
	_check(var_to_bytes(data.site.inventory) == spent and var_to_bytes([data.site.family.technology, data.site.settlement.technology]) == archive, "Fatal damage neither refunds original materials nor grants research knowledge")
	var invalid := vehicle.duplicate(true)
	invalid.hp = 1.0
	_check(not Runtime.validate_technology_yard_vehicle(data, invalid).ok, "A forged living target cannot use the original wreck history exception")
	fixture.lab.site_controller._capture_positions()
	_check(YardStore.save(data, "user://technology_s11_original_wreck.json").ok, "Actual original Store saves an unfinished destroyed paid target on the true original ground")
	var source_fingerprint := data.fingerprint()
	var source_conditions := _cold_natural_conditions(data)
	var loaded := YardStore.load_site("user://technology_s11_original_wreck.json")
	_check(loaded.ok and loaded.data.site.vehicles[key].phase == "wrecked" and not loaded.data.site.vehicles[key].has("technology_construction"), "Strict original load preserves the real spent wreck without inventing a completed physical event")
	_check(loaded.data.fingerprint() == source_fingerprint and _cold_natural_conditions(loaded.data) == source_conditions, "Original yard Store replay retains the same natural terrain and all five actual land conditions")
	_cleanup_fixture(fixture.lab, fixture.team)
	await process_frame

func _fresh_trial_and_legacy_four() -> void:
	var fixture := _yard_fixture(false)
	var data: TerrainData = fixture.data
	var lab: TerrainLab = fixture.lab
	var actions = fixture.actions
	var scope_id := str(fixture.settlement_id)
	_check(not Runtime.configure_siege_yard(data, str(fixture.yard), int(fixture.control), int(fixture.executor)).ok, "Unknown S11 cannot expand ordinary construction merely by selecting a ground")
	_check(actions.prepare_scope_technology(int(fixture.control), int(fixture.executor), "S11", scope_id).ok, "Actual original head/F11 worker may prepare first S11 before its own effect exists")
	_check(lab.character.place(Vector2i(9, 10) + Vector2i(fixture.natural_offset), true) and actions.grant_scope_technology_budget(int(fixture.control), "settlement", scope_id, {"wood": 24, "iron": 12, "fiber": 10}).ok and actions.request_scope_technology_consent(int(fixture.control), "settlement", scope_id, int(fixture.executor)).ok, "The true camp owner allowance and actual original team request bound the single fresh trial")
	var key := str(int(data.site.get("next_vehicle", 1)))
	_check(actions.begin_scope_technology_phase(int(fixture.control), "settlement", scope_id, "ballista_build", "vehicle:" + key, {"anchor": Vector2i(24, 44) + Vector2i(fixture.natural_offset), "facing": Vector2i.DOWN, "team_id": int(fixture.team.team_id)}).ok, "True bound original S11 trial uses the existing unconfigured ground without needing S11 known/adopted first")
	var vehicle: Dictionary = data.site.vehicles[key]
	_check(not data.site.features[fixture.yard].has("technology_siege_yard") and Runtime.siege_work_slots(data, vehicle).size() == 4 and vehicle.technology_yard_id == fixture.yard, "Fresh trial remains four original slots with actual original ground provenance")
	var task: Dictionary = fixture.row.work_task
	fixture.team.cells[1] = data.cell_from_index(int(task.work_cell))
	task.cell = int(task.work_cell)
	task.mode = "work"
	var finished := Runtime.advance_siege_work(data, key, "construct", float(vehicle.build.total_work), fixture.team.cells[1], int(task.work_slot), int(fixture.team.team_id), task, int(fixture.executor))
	_check(finished.ok and finished.complete and Technology.scope_known(data.site.settlement.technology, "S11") and not Technology.learned(fixture.row.technology, "S11"), "Actual paid trial completion closes original settlement S11 without claiming a personal skill")
	_check(Runtime.validate_technology_yard_vehicle(data, vehicle).ok and vehicle.technology_construction.target_id == "vehicle:" + key, "Consumed true token keeps its genuine original completed ground provenance")
	var legacy := {"kind": "ballista", "cell": data.index(Vector2i(40, 24) + Vector2i(fixture.natural_offset)), "facing": [0, 1]}
	_check(Runtime.siege_work_slots(data, legacy).size() == 4, "Every unconfigured/legacy engine retains the original four-station geometry")
	_cleanup_fixture(lab, fixture.team)
	await process_frame

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	await _yard_guards_and_revoke()
	await _six_actual_workers_and_save()
	await _wreck_retains_spent_history()
	await _fresh_trial_and_legacy_four()
	TerrainArmy.release_contact_source()
	print("SITE_TECHNOLOGY_SIEGE_YARD_PASS: %d checks; original ground/head/master/config/revoke, true slots5/6, shared planner effort, strict suspended/wreck Store roundtrip, original adjacent siege travel, fresh trial four slots; Native/GPU/dual-F11-F12/whole-Lab-clock/full40 excluded" % checks)
	quit(0)
