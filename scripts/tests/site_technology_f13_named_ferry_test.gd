extends "res://scripts/tests/site_technology_shipyard_physical_test.gd"
## Actual original Army/person/Family, camp source, one original ferry and
## registered WorkTeam/Fatigue intervals. NOT_RUN; F13 must be guarded-enabled.
## This fixture is not Native, whole Lab clock, travel or all40 acceptance.

func _f13_named_initial_and_paid_resume() -> void:
	var f := _shipyard_fixture()
	var data: TerrainData = f.data
	var actions = f.actions
	var family_id := str(data.site.family.family_id)
	# Strict original starting-world prerequisites; the trial executor has never
	# learned F13. No scenario population, family or skill is created by Runtime.
	data.site.family.technology.known = ["F04", "F09", "F14"]
	f.row.technology = Technology.learned_candidate(Technology.learned_candidate({}, "F04"), "F14")
	_check(Family.validate_family(data.site.family, str(data.site.id)) and not Technology.learned(f.row.technology, "F13"), "True original registered family and unlearned person start the genuine ferry trial")
	_check(actions.prepare_scope_technology(int(f.control), int(f.executor), "F13", family_id).ok, "Original head prepares only this actual F13 executor and F09 prerequisite")
	var cost := Runtime.Ships.build_cost("ferry")
	# The grant is a hand-craft action at the camp: stand on a free legal cell next to the depot.
	var placed := false
	var depot: Vector2i = data.cell_from_index(int(data.site.depot_cell))
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var cell: Vector2i = depot + direction
		if not placed and data.is_walkable(cell) and data.can_step(depot, cell) and not f.lab.site_controller.reserves_cell(cell): placed = f.lab.character.place(cell, true)
	var granted: Dictionary = actions.grant_scope_technology_budget(int(f.control), "family", family_id, cost)
	var consented: Dictionary = actions.request_scope_technology_consent(int(f.control), "family", family_id, int(f.executor)) if granted.ok else {}
	_check(placed and granted.ok and consented.get("ok", false), "Original camp head grants full finite hull cost and actual team gives purpose-bound consent: %s %s %s" % [str(placed), str(granted), str(consented)])
	var raw: Dictionary = data.site.family.technology
	var project := Technology.active_project(raw)
	var phase := Technology.scope_next_phase(project, project.executor, raw.get("person_links", []))
	var token := {"scope": "family", "scope_id": family_id, "project_id": int(project.id), "epoch": int(raw.epoch), "purpose": str(project.purpose), "tech_id": "F13", "phase_id": str(phase.id), "attempt": int(project.next_attempt), "person": project.executor.duplicate(), "binding": "ferry_build", "target_id": "feature:" + str(f.yard), "materials": phase.materials.duplicate()}
	var before := var_to_bytes([data.site, f.team.capture_combat_state()])
	_check(Runtime.begin_technology_operation(data, token, true, {"team_id": int(f.team.team_id)}).ok and var_to_bytes([data.site, f.team.capture_combat_state()]) == before, "Actual project-derived token previews source/ship/SAME zone/one named task without mutation")
	var inventory = data.site.inventory.duplicate(true)
	var vehicle_id := str(data.site.next_vehicle)
	_check(actions.begin_scope_technology_phase(int(f.control), "family", family_id, "ferry_build", "feature:" + str(f.yard), {"team_id": int(f.team.team_id)}).ok, "Single original begin adopts true hull, finite payment and named task in the same tail")
	var yard: Dictionary = data.site.features[f.yard]
	var task: Dictionary = f.row.work_task
	_check(not task.is_empty() and task.get("named") == true and task.target == "feature:" + str(f.yard) and int(f.row.person_id) == int(f.executor), "Initial F13 has its exact original executor task immediately; no second manual assignment is needed")
	_check(not yard.has("technology_shipyard_work") and int(task.work_slot) == -1 and yard.ship_build.total_work == 600.0, "Unconfigured original one-station shipyard retains the ordinary 600 baseline")
	for material: String in cost: _check(int(data.site.inventory.get(material, 0)) == int(inventory.get(material, 0)) - int(cost[material]), "Original finite trial pays actual %s once" % material)
	f.team.cells[1] = data.cell_from_index(int(task.work_cell))
	f.team.moving_to[1] = TerrainArmy.INVALID_CELL # No stale step or walking pose from the cancelled route.
	f.team.combat_hot_set(1, &"pose", "idle")
	task.cell = int(task.work_cell)
	task.mode = "work"
	_check(SiteWorkTeam.valid_task(data, data.site, task), "Original cold task accepts the actual unconfigured ship station")
	var person = actions._person(int(f.executor))
	var checked := Runtime.work_preflight(data, task, person.cargo, Runtime.CARRY_CAPACITY, 1, int(f.executor), f.lab.site_controller.reserves_cell)
	_check(checked.ok and is_equal_approx(float(checked.productivity), 1.0), "Unlearned F13 trial receives no pre-awarded joinery improvement")
	_shipyard_work_point(f, 30.0)
	var paid = yard.tech_batch.duplicate(true)
	var physical := float(yard.production)
	var paid_inventory = data.site.inventory.duplicate(true)
	var original_token = yard.tech_trial.duplicate(true)
	var original_id := int(project.id)
	var original_purpose := str(project.purpose)
	var attempts := int(Technology.active_project(data.site.family.technology).next_attempt)
	_check(actions.stop_scope_technology(int(f.control), "family", family_id).ok and f.row.get("work_task", {}).is_empty(), "Actual Scope stop parks its single original named task")
	_check(yard.tech_batch == paid and float(yard.production) == physical and data.site.inventory == paid_inventory, "Stop preserves true paid work and cannot refund or consume the hull twice")
	_check(actions.prepare_scope_technology(int(f.control), int(f.executor), "F13", family_id).ok, "Original unfinished project explicitly resumes")
	project = Technology.active_project(data.site.family.technology)
	_check(int(project.id) == original_id and str(project.purpose) == original_purpose, "Resume keeps the same original person/project/purpose")
	_check(actions.begin_scope_technology_phase(int(f.control), "family", family_id, "ferry_build", "feature:" + str(f.yard), {"team_id": int(f.team.team_id)}).ok, "Retained paid ferry really reassigns the original named task")
	_check(not f.row.work_task.is_empty() and yard.tech_batch == paid and yard.tech_trial == original_token and float(yard.production) == physical and data.site.inventory == paid_inventory and int(Technology.active_project(data.site.family.technology).next_attempt) == attempts, "Paid resume retains SAME payment/attempt/progress and material, with a real task")
	task = f.row.work_task
	f.team.cells[1] = data.cell_from_index(int(task.work_cell))
	f.team.moving_to[1] = TerrainArmy.INVALID_CELL # No stale step or walking pose from the cancelled route.
	f.team.combat_hot_set(1, &"pose", "idle")
	task.cell = int(task.work_cell)
	task.mode = "work"
	for index: int in range(60):
		if not yard.has("ship_build"): break
		_shipyard_work_point(f, 30.0)
		# The original point clock then launches a fully built hull (finish_checked_work_clock).
		Runtime.advance_ship_builds(data, f.lab.site_controller.reserves_cell)
	_check(not yard.has("ship_build") and data.site.vehicles.has(vehicle_id) and data.site.vehicles[vehicle_id].ship_type == "ferry" and int(data.site.next_vehicle) == int(vehicle_id) + 1, "Only original Ships.make_record adopts one genuine completed ferry: %s" % str({"ship_build": yard.get("ship_build", {}).keys() if yard.get("ship_build") is Dictionary else yard.get("ship_build"), "production": yard.get("production"), "vehicles": data.site.vehicles.keys(), "expected": vehicle_id, "next": data.site.get("next_vehicle"), "task": f.row.get("work_task", {}).get("mode", "")}))
	_check(Technology.scope_known(data.site.family.technology, "F13") and Technology.learned(f.row.technology, "F13"), "True output evidence teaches only the original full-phase person and archive")
	var finished: Dictionary = data.site.family.technology.projects[0]
	_check(finished.receipts.size() == 1 and is_equal_approx(float(finished.receipts[0].work_seconds), 600.0) and data.site.inventory == paid_inventory, "One actual 600-second trial receipt records unweighted original effort and no second payment")
	before = var_to_bytes([data.site, f.team.capture_combat_state()])
	_check(not Runtime.begin_technology_operation(data, original_token, false, {"team_id": int(f.team.team_id)}).ok and var_to_bytes([data.site, f.team.capture_combat_state()]) == before, "Completed original token cannot replay output, stock or skill")
	_cleanup_fixture(f.lab, f.team)
	await process_frame

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	await _f13_named_initial_and_paid_resume()
	TerrainArmy.release_contact_source()
	print("SITE_TECHNOLOGY_F13_NAMED_FERRY_PASS: %d checks; true initial single-task/camp cost/paid stop-resume/original ferry/one 600 effort receipt; Native/fullLab/travel/all40 excluded" % checks)
	quit(0)
