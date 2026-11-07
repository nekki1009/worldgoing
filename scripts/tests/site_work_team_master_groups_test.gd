extends "res://scripts/tests/site_technology_siege_yard_test.gd"
## Actual original Army offices, separate F11/F12 masters, six true stations,
## frozen original World policy, shared original pool and checked Runtime tail.
## Use Gate's S11 source + 51EB prefix correction and this independent AND pack.
## Setup directly places true existing hot cells; travel/Native/GPU are excluded.
const MasterPolicy = preload("res://scripts/terrain_lab/site_technology_policy.gd")

func _masters_fixture(alternate: bool = false) -> Dictionary:
	var fixture := _yard_fixture()
	var lab: TerrainLab = fixture.lab
	var data: TerrainData = fixture.data
	var team: TerrainArmy = fixture.team
	team.exchange_enabled = true
	team.sync_shared_fatigue(true)
	# Original role/office source setup: the living original captain delegates
	# the existing civil work duty to the actual joined Actor. No controlled-ID
	# swap, vacant-captain bypass, synthetic consent or parallel roster is used.
	for index: int in range(40): team.cells[index] = Vector2i(9 + index, 50)
	team.cells[0] = Vector2i(25, 40) + Vector2i(fixture.natural_offset) # Template-relative: row 40 lies between the house row and the yard.
	_check(lab.character.place(Vector2i(24, 40) + Vector2i(fixture.natural_offset), true) and team.join_player(lab.character).ok, "Actual controlled Actor legally joins the living original captain's formation")
	team.settle_combat_command()
	var offices := team.team_offices()
	_check(team.apply_office_plan(team.combat_identity(team.formal_commander), int(offices.revision), [{"op": "appoint", "position_id": str(offices.duties["team.work"]), "person_id": int(fixture.control)}]).ok, "Original living current captain delegates its real existing civil work duty through the original office transaction")
	_check(team.duty_resolve_readonly("team.work", team).decider == fixture.control, "Current original work decider is the SAME joined controlled Actor")
	team.combat_units[1].technology = Technology.learned_candidate({}, "F11")
	team.combat_units[2].technology = Technology.learned_candidate({}, "F12")
	team.combat_units[3].technology = Technology.learned_candidate({}, "F11") if alternate else {}
	data.site.family.technology.known = ["F04", "F11", "F12", "F14"]
	data.site.world_pin = {"format": 2, "technology_policy": MasterPolicy.new_policy(["F12"]).policy}
	team.cells[1] = Vector2i(22, 42) + Vector2i(fixture.natural_offset) # Row 41 holds the ground's own racks.
	_check(Runtime.configure_siege_yard(data, str(fixture.yard), int(fixture.control), team.combat_identity(1)).ok, "Actual same-settlement head configures the genuine ground while the real F11 master is present")
	var prospective := {"kind": "counterweight_trebuchet", "cell": data.index(Vector2i(26, 43) + Vector2i(fixture.natural_offset)), "facing": [0, 1]}
	var stations := Runtime.siege_work_slots(data, prospective)
	_check(stations.size() == 6, "Actual frozen S11 geometry gives six genuine original construction stations")
	team.cells[2] = data.cell_from_index(int(stations[0].cell))
	var paid_before = data.site.inventory.duplicate(true)
	var begun := Runtime.begin_siege_build(data, "counterweight_trebuchet", Vector2i(26, 43) + Vector2i(fixture.natural_offset), Vector2i.DOWN, int(team.team_id), int(fixture.control), lab.site_controller.reserves_cell, false, {}, {}, team.combat_identity(2))
	_check(begun.ok, "Original finite new construction admits a genuine named F12 operator and a different genuinely available F11 master before real cost: " + str(begun))
	fixture.key = str(begun.vehicle)
	fixture.vehicle = data.site.vehicles[fixture.key]
	for material: String in Runtime.SIEGE_DEFINITIONS.counterweight_trebuchet.cost:
		_check(int(data.site.inventory[material]) == int(paid_before[material]) - int(Runtime.SIEGE_DEFINITIONS.counterweight_trebuchet.cost[material]), "Actual original full %s construction cost is paid once" % material)
	var others: Array[int] = [] # The owner takes Array[int].
	for index: int in [1, 3, 4, 5, 6]: others.append(team.combat_identity(index))
	_check(lab.site_controller.work_team.assign(team, others, int(fixture.control)).ok, "Original actual work decider assigns the five other real helpers through the unchanged selector")
	lab.site_controller.work_team.prepare_work_requests(30.0)
	for index: int in range(1, 7):
		var row: Dictionary = team.combat_units[index]
		_check(row.work_task.target == "vehicle:" + fixture.key, "Each real original row holds this SAME genuine paid target")
		team.cells[index] = data.cell_from_index(int(row.work_task.work_cell))
		# The placed body has no pending step or walking pose left from its cancelled route.
		team.moving_to[index] = TerrainArmy.INVALID_CELL
		team.combat_hot_set(index, &"pose", "idle")
		row.work_task.cell = int(row.work_task.work_cell)
		row.work_task.mode = "work"
		_check(SiteWorkTeam.valid_task(data, data.site, row.work_task), "Each held original named/helper task validates its actual original slot")
	return fixture

func _master_requests(fixture: Dictionary, seconds: float) -> Array[Dictionary]:
	var lab: TerrainLab = fixture.lab
	var requests = lab.site_controller.work_team.prepare_work_requests(seconds)
	lab._shared_work_requests = requests
	_check(lab._refresh_shared_work_preflight().ok, "Actual final material/water projection preserves held skill facts")
	return lab._shared_work_requests

func _master_point(fixture: Dictionary, requests: Array[Dictionary], seconds: float) -> Dictionary:
	var lab: TerrainLab = fixture.lab
	var workers = lab.site_controller.work_team
	var captured = workers.prepare_shared_work_prefix(seconds)
	var plan := PersonFatigue.plan_work_interval(requests, seconds)
	_check(captured.ok and plan.ok, "The actual original master requests capture one shared legal interval")
	var prior: Array = []
	var before := var_to_bytes([fixture.data.site, fixture.team.capture_combat_state()])
	var admitted = workers.validate_shared_work_prefix(captured, plan, prior)
	_check(admitted.ok and var_to_bytes([fixture.data.site, fixture.team.capture_combat_state()]) == before, "True separate skill witnesses validate the complete original prefix before any cost/effort/progress")
	lab._shared_work_plan = plan
	lab.site_controller._shared_work_plan = plan
	lab._shared_work_pools_committed = false
	lab._commit_shared_work_pools()
	var handled = workers.publish_shared_work_prefix(admitted)
	workers.finish_shared_work_prefix(admitted)
	# The publisher reports per-person seconds under handled_seconds.
	return {"plan": plan, "admitted": admitted, "handled": handled.get("handled_seconds", {}) if handled is Dictionary else {}}

func _distinct_masters_and_boundary() -> void:
	var fixture := _masters_fixture()
	var requests := _master_requests(fixture, 10.0)
	_check(requests.size() == 1 and requests[0].participants.size() == 6, "The original selector and fixed real slots collect one six-person shared job")
	var groups: Array = requests[0].required_all_any_ids
	_check(groups.size() == 2 and groups.has([fixture.team.combat_identity(1)]) and groups.has([fixture.team.combat_identity(2)]), "Different true original F11 and F12 bodies satisfy independent required OR groups")
	var point := _master_point(fixture, requests, 10.0)
	_check(float(fixture.vehicle.build.progress) == 60.0 and float(fixture.vehicle.tech_batch.work_seconds) == 60.0 and point.admitted.runtime.size() == 6, "Each genuine participant adds its own unweighted physical contribution once; no helper duplicates the entire crew")
	fixture.team.team_fatigue.fatigue = 79.99 # Explicit actual original pool boundary source epoch.
	fixture.team.team_fatigue.fatigue_rest = 0.0
	requests = _master_requests(fixture, 30.0)
	var rate := 0.0
	for person: Dictionary in requests[0].participants: rate += float(person.effort_rate)
	var prefix_seconds := (80.0 - 79.99) / rate
	point = _master_point(fixture, requests, 30.0)
	var allocation: Dictionary = point.plan.jobs.work_team[requests[0].key]
	_check(absf(float(allocation.actual_seconds) - prefix_seconds) < 0.000001 and allocation.paused == "REST", "Total original pool slope clips the genuine prefix at 80 before either required master can stop")
	_check(point.admitted.runtime.size() == 6 and float(fixture.vehicle.build.progress) > 60.0 and absf(float(fixture.team.team_fatigue.fatigue) - 80.0) < 0.000001, "Endpoint REST preserves all six already-spent positive prefixes and publishes one original pool value")
	_cleanup_fixture(fixture.lab, fixture.team)
	await process_frame

func _alternate_and_missing_requirement() -> void:
	var fixture := _masters_fixture(true)
	fixture.team.team_fatigue.fatigue = 60.0
	fixture.team.combat_units[1].work_resting = true # Actual 80/50 hysteresis precondition.
	var requests := _master_requests(fixture, 5.0)
	_check(requests.size() == 1, "A different actually working original F11 retains the legal crew while the first master is resting")
	var found_alternate := false
	for group: Array in requests[0].required_all_any_ids: found_alternate = found_alternate or group.has(fixture.team.combat_identity(3))
	_check(found_alternate, "The original group contains the real alternate F11 body, not a borrowed capability flag")
	var point := _master_point(fixture, requests, 5.0)
	_check(not point.handled.has(fixture.team.combat_identity(1)) and point.handled.has(fixture.team.combat_identity(3)), "Only actual accepted participants consume physical work and fatigue")
	_cleanup_fixture(fixture.lab, fixture.team)
	await process_frame
	fixture = _masters_fixture()
	fixture.team.team_fatigue.fatigue = 60.0
	fixture.team.combat_units[1].work_resting = true
	var before := var_to_bytes([fixture.vehicle, fixture.data.site.inventory, fixture.team.team_fatigue])
	requests = _master_requests(fixture, 5.0)
	_check(requests.is_empty() and var_to_bytes([fixture.vehicle, fixture.data.site.inventory, fixture.team.team_fatigue]) == before, "Without any actual working F11 the paid target is retained and the remaining F12/helpers consume zero progress/materials/fatigue")
	_cleanup_fixture(fixture.lab, fixture.team)
	await process_frame

func _run() -> void:
	await _distinct_masters_and_boundary()
	await _alternate_and_missing_requirement()
	TerrainArmy.release_contact_source()
	print("SITE_WORK_TEAM_MASTER_GROUPS_PASS checks=", checks, " original six-slot counterweight/F11+F12 different people, one shared pool, alternate/last master REST and accepted prefix; no World birth/Native/travel/GPU claim")
	quit(0)
