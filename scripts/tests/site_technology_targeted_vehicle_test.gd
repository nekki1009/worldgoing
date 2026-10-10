extends "res://scripts/tests/site_technology_paid_feature_resume_test.gd"
## True original Actor/Army membership, Family duties, paid vehicle and held
## PA/WT work. Controlled work uses the original shared planner and publisher;
## NPC direct intervals exclude movement/Fatigue/full TerrainLab frame proof.
## The analysis allowance is an explicit legal saved precondition, not proof
## of the separate 600-second capture/analysis owner transaction.
const VehiclePolicy = preload("res://scripts/terrain_lab/site_technology_policy.gd")

func _vehicle_team(lab: TerrainLab, join_actor: bool) -> TerrainArmy:
	var team := TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.team_id = 301
	team.roster_size = 2
	team.faction_id = 1
	var cells: Array[Vector2i] = [Vector2i(11, 11), Vector2i(12, 11)]
	_check(team.deploy_at(lab.terrain, lab.character, lab.npc, cells) and team.enable_combat(false), "Original finite Army creates true rows using the actual original Actors")
	for row: Dictionary in team.combat_units:
		row.cargo = {}
		row.item_state = Runtime.new_item_state("person:" + str(row.person_id))
	lab.combat_armies.append(team)
	team.controlled_person_query = lab.controlled_person_id
	team.person_busy_query = lab.site_controller.person_actions.is_busy
	team.settle_combat_command()
	_check(team.set_duty_ai_enabled(team.combat_identity(team.formal_commander), true).ok, "The original NPC captain enables the real team duty flag")
	if join_actor: _check(team.join_player(lab.character).ok and team.index_for_identity(lab.character.person_id) == TerrainArmy.PLAYER_MEMBER, "The actual Actor legally joins through the original Army owner")
	return team

func _vehicle_family(lab: TerrainLab, team: TerrainArmy, executor: int) -> String:
	var actions = lab.site_controller.person_actions
	var control := lab.controlled_person_id()
	var refs: Array = []
	for identity: int in [control, int(lab.npc.person_id), team.combat_identity(0), team.combat_identity(1)]:
		refs.append({"site_id": str(lab.terrain.site.id), "person_id": identity, "path": "", "label": "真实原人物", "age_years": -1})
	_check(lab.site_controller.family_continuity.register_members(refs, true, control).ok and lab.site_controller.family_continuity.appoint_head(control, control).ok, "Original family registration and current duty establish the true named family")
	# Original pure schema upgrade for this explicitly registered prerequisite fixture.
	lab.terrain.site.family = actions._technology_candidate()
	lab.terrain.site.family.technology = Technology.empty_scope_record(str(lab.terrain.site.id))
	lab.terrain.site.family.technology.known = ["F09"]
	_check(Family.validate_family(lab.terrain.site.family, str(lab.terrain.site.id)), "Original Family validator admits the explicit legitimate prerequisite archive")
	_check(lab.character.place(Vector2i(9, 10), true), "The actual grantor stands at original camp contact")
	_check(actions.prepare_scope_technology(control, executor, "F11").ok, "Original F11 research names this actual executor")
	var family_id := str(lab.terrain.site.family.family_id)
	_check(actions.grant_scope_technology_budget(control, "family", family_id, {"wood": 300, "iron": 100, "fiber": 100, "cloth": 50}).ok and actions.request_scope_technology_consent(control, "family", family_id, executor).ok, "Original finite material grant and actual team consent are both accepted")
	return family_id

func _vehicle_station(data: TerrainData, kind: String, anchor: Vector2i) -> Vector2i:
	var proposed := {"kind": kind, "cell": data.index(anchor), "facing": [1, 0]}
	var slots := Runtime.siege_work_slots(data, proposed)
	_check(slots.size() == 4, "Original vehicle geometry computes exactly four true construction stations")
	return data.cell_from_index(int(slots[0].cell))

func _controlled_vehicle_resume() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var team := _vehicle_team(lab, true)
	var control := lab.controlled_person_id()
	var actions = lab.site_controller.person_actions
	var family_id := _vehicle_family(lab, team, control)
	var allowance := Technology.analysis_candidate(lab.character.technology, "F11", family_id, _project(lab), "original-consumed-engine", "original-accepted-capture")
	_check(not allowance.is_empty(), "Original strict historical analysis receipt is an explicit saved precondition")
	lab.character.technology = allowance
	var key := str(int(data.site.get("next_vehicle", 1)))
	var target := "vehicle:" + key
	var request := {"anchor": Vector2i(20, 20), "facing": Vector2i.RIGHT, "team_id": int(team.team_id)}
	var before := var_to_bytes([data.site, actions._jobs, lab.character.technology, lab.character.fatigue])
	var refused = actions.begin_scope_technology_phase(control, "family", family_id, "ballista_build", target, request)
	_check(not refused.ok and refused.code == "UNREACHABLE" and var_to_bytes([data.site, actions._jobs, lab.character.technology, lab.character.fatigue]) == before, "A controlled Actor outside the real station cannot pay, allocate credit or publish any job")
	var station := _vehicle_station(data, "ballista", request.anchor)
	_check(lab.character.place(station, true), "Actual original Actor reaches the original construction station")
	var npc_origin := lab.npc.terrain_cell
	_check(lab.npc.place(station, true), "A second actual original Actor deliberately occupies the same fixture station")
	before = var_to_bytes([data.site, actions._jobs, lab.character.technology])
	refused = actions.begin_scope_technology_phase(control, "family", family_id, "ballista_build", target, request)
	_check(not refused.ok and refused.code == "OCCUPIED" and var_to_bytes([data.site, actions._jobs, lab.character.technology]) == before, "The named-person exclusion cannot hide a second original Actor or debit any stock")
	_check(lab.npc.place(npc_origin, true), "The other real Actor leaves the station")
	before = var_to_bytes([data.site, actions._jobs, lab.character.technology])
	var preview := Runtime.begin_technology_operation(data, _token(lab, control, target), true, request)
	_check(preview.ok and var_to_bytes([data.site, actions._jobs, lab.character.technology]) == before, "A legal actual stationed named Actor previews without its own body falsely blocking the station")
	var stock = data.site.inventory.duplicate()
	var started = actions.begin_scope_technology_phase(control, "family", family_id, "ballista_build", target, request)
	_check(started.ok and actions.is_busy(control) and actions.save_guard().code == "BUSY", "Actual material, credit, vehicle and original controlled work are published in one tail")
	var vehicle: Dictionary = data.site.vehicles[key]
	var token: Dictionary = vehicle.tech_trial
	var job: Dictionary = actions._jobs[str(control)]
	_check(job.kind == "technology_vehicle" and is_same(job.vehicle_ref, vehicle) and is_same(job.build_ref, vehicle.build) and is_same(job.operation_selector.token, token) and not _has_actor_work_task(lab.character), "Original PA _jobs owns the SAME task and original vehicle; Actor schema is unchanged")
	_check(vehicle.build.total_work == 5400.0 and vehicle.tech_work_credit == {"remaining_work": 5400.0, "credit": 2700.0} and lab.character.technology.analysis[0].used_work == 2700.0 and _project(lab).budget.payments.size() == 1, "One actual 50-percent allocation keeps immutable original work and one real full payment")
	for resource: String in Runtime.SIEGE_DEFINITIONS.ballista.cost:
		_check(int(data.site.inventory[resource]) == int(stock[resource]) - int(Runtime.SIEGE_DEFINITIONS.ballista.cost[resource]), "Original full vehicle material is deducted exactly once: " + resource)
	before = var_to_bytes([vehicle, lab.character.technology, lab.character.fatigue])
	actions.advance(600.0, {})
	_check(var_to_bytes([vehicle, lab.character.technology, lab.character.fatigue]) == before, "No canonical collector means no timer progress, evidence or fatigue")
	var step := _controlled_step(lab, 60.0)
	_check(vehicle.build.progress == 120.0 and vehicle.tech_batch.work_seconds == 60.0 and float(step.handled.get(control, -1.0)) == 60.0 and PersonalFatigue.read(lab.character) > 0.0, "True 60-second effort moves only physical progress by two; original shared fatigue is charged once")
	var paid := var_to_bytes(_project(lab).budget)
	var attempt := int(_project(lab).next_attempt)
	_check(actions.stop_scope_technology(control, "family", family_id).ok and not actions.is_busy(control), "Original Scope stop immediately cancels this exact controlled vehicle job")
	_check(actions.prepare_scope_technology(control, control, "F11").ok, "Original project reactivates its same purpose and retained paid target")
	_check(lab.character.place(Vector2i(9, 10), true), "The actual worker temporarily leaves the station")
	before = var_to_bytes([data.site, actions._jobs, lab.character.technology])
	refused = actions.begin_scope_technology_phase(control, "family", family_id, "ballista_build", target)
	_check(not refused.ok and refused.code == "UNREACHABLE" and var_to_bytes([data.site, actions._jobs, lab.character.technology]) == before, "Canceled paid resume still requires the true original controlled station")
	_check(lab.character.place(station, true), "Actual worker returns to the SAME original station")
	started = actions.begin_scope_technology_phase(control, "family", family_id, "ballista_build", target)
	_check(started.ok and started.resumed and not started.already_working and actions.is_busy(control) and is_same(vehicle.tech_trial, token) and is_same(actions._jobs[str(control)].vehicle_ref, vehicle) and vehicle.build.progress == 120.0 and int(_project(lab).next_attempt) == attempt and var_to_bytes(_project(lab).budget) == paid and lab.character.technology.analysis[0].used_work == 2700.0, "Resume republishes actual SAME paid work without stock/attempt/quota/credit double charge")
	before = var_to_bytes([data.site, actions._jobs, lab.character.technology])
	started = actions.begin_scope_technology_phase(control, "family", family_id, "ballista_build", target)
	_check(started.ok and started.already_working and var_to_bytes([data.site, actions._jobs, lab.character.technology]) == before, "Existing genuine controlled vehicle task resumes as a byte-equivalent no-op")
	_controlled_step(lab, 2640.0)
	_check(vehicle.phase == "idle" and vehicle.build.is_empty() and not actions.is_busy(control) and not vehicle.has("tech_trial") and not vehicle.has("tech_work_credit") and vehicle.technology_construction.work_seconds == 2700.0 and _project(lab).receipts.size() == 1 and _project(lab).budget.payments.size() == 1, "Original real completion accepts one truthful named phase and stops work without producing another vehicle")
	_check(data.site.family.technology.siege_history.size() == 1 and Family.validate_family(data.site.family, str(data.site.id)) and not Technology.learned(lab.character.technology, "F11"), "One original ballista adds bounded real family history, while F11 still needs the distinct tower")
	data.site.world_pin = {"format": 2, "technology_policy": VehiclePolicy.new_policy(["F11"]).policy}
	key = str(int(data.site.next_vehicle))
	target = "vehicle:" + key
	request = {"anchor": Vector2i(32, 20), "facing": Vector2i.RIGHT, "team_id": int(team.team_id)}
	_check(lab.character.place(_vehicle_station(data, "siege_tower", request.anchor), true), "Actual unlearned research worker stands at the distinct tower station")
	before = var_to_bytes([data.site, actions._jobs, lab.character.technology])
	preview = Runtime.begin_technology_operation(data, _token(lab, control, target), true, request)
	_check(preview.ok and var_to_bytes([data.site, actions._jobs, lab.character.technology]) == before, "Legal current F11 trial exception admits true tower preview under frozen F11 policy without first requiring learned F11")
	before = var_to_bytes(data.site)
	refused = Runtime.begin_siege_build(data, "siege_tower", Vector2i(40, 35), Vector2i.RIGHT, int(team.team_id), control, Callable(), true)
	_check(not refused.ok and refused.code == "NO_OPERATOR" and var_to_bytes(data.site) == before, "New gated ordinary tower requires a real named skilled operator before cost")
	for categories: Array in [[], ["F04"]]:
		data.site.world_pin = {"format": 2, "technology_policy": VehiclePolicy.new_policy(categories).policy}
		_check(Runtime.begin_siege_build(data, "siege_tower", Vector2i(40, 35), Vector2i.RIGHT, int(team.team_id), control, Callable(), true).ok, "Empty or F04-only world admits ordinary ungated siege preview without artificial prior F11")
	data.site.world_pin = {"format": 2}
	before = var_to_bytes(data.site)
	refused = Runtime.begin_siege_build(data, "ballista", Vector2i(40, 35), Vector2i.RIGHT, int(team.team_id), control, Callable(), true)
	_check(not refused.ok and var_to_bytes(data.site) == before, "Malformed new-world policy fails before an ordinary payment, even for an ungated type")
	_cleanup_fixture(lab, team)
	await process_frame

func _npc_vehicle_resume() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var team := _vehicle_team(lab, false)
	var actions = lab.site_controller.person_actions
	var control := lab.controlled_person_id()
	var executor := team.combat_identity(1)
	var family_id := _vehicle_family(lab, team, executor)
	var key := str(int(data.site.get("next_vehicle", 1)))
	var target := "vehicle:" + key
	var request := {"anchor": Vector2i(20, 20), "facing": Vector2i.RIGHT, "team_id": int(team.team_id)}
	var started = actions.begin_scope_technology_phase(control, "family", family_id, "ballista_build", target, request)
	_check(started.ok and lab.site_controller.work_team.is_assigned(executor), "Original Runtime publishes the actual named WT vehicle task in the same paid tail")
	var vehicle: Dictionary = data.site.vehicles[key]
	var token: Dictionary = vehicle.tech_trial
	var row: Dictionary = team.combat_units[1]
	var task: Dictionary = row.work_task
	_check(task.version == 3 and task.named and task.target == target and task.action == "construct" and task.zone == -1, "The original saved task is strictly the vehicle named schema")
	team.cells[1] = data.cell_from_index(int(task.work_cell))
	task.cell = int(task.work_cell)
	task.mode = "work"
	var before := var_to_bytes(vehicle)
	var wrong := Runtime.advance_siege_work(data, key, "construct", 60.0, team.cells[1], int(task.work_slot), int(team.team_id), task, team.combat_identity(0))
	_check(not wrong.ok and var_to_bytes(vehicle) == before, "Another real NPC cannot borrow the SAME named task identity")
	_check(Runtime.advance_siege_work(data, key, "construct", 60.0, team.cells[1], int(task.work_slot), int(team.team_id), task, executor).ok and vehicle.build.progress == 60.0, "The actual original NPC at its true station performs a real direct interval")
	var paid := var_to_bytes(_project(lab).budget)
	var attempt := int(_project(lab).next_attempt)
	_check(actions.stop_scope_technology(control, "family", family_id).ok and not lab.site_controller.work_team.is_assigned(executor) and row.work_task.is_empty(), "Original Scope stop removes its exact true NPC vehicle assignment")
	_check(actions.prepare_scope_technology(control, executor, "F11").ok, "Original project reactivates the retained purpose")
	started = actions.begin_scope_technology_phase(control, "family", family_id, "ballista_build", target)
	task = row.work_task
	_check(started.ok and started.resumed and not started.already_working and lab.site_controller.work_team.is_assigned(executor) and task.version == 3 and is_same(vehicle.tech_trial, token) and vehicle.build.progress == 60.0 and var_to_bytes(_project(lab).budget) == paid and int(_project(lab).next_attempt) == attempt, "Paid NPC resume republishes genuine original work with no stock/attempt/payment reset")
	before = var_to_bytes([data.site, row])
	started = actions.begin_scope_technology_phase(control, "family", family_id, "ballista_build", target)
	_check(started.ok and started.already_working and var_to_bytes([data.site, row]) == before, "A genuine idle/traveling named WT task is preserved as a no-op")
	team.cells[1] = data.cell_from_index(int(task.work_cell))
	task.cell = int(task.work_cell)
	task.mode = "work"
	var finished := Runtime.advance_siege_work(data, key, "construct", 5340.0, team.cells[1], int(task.work_slot), int(team.team_id), task, executor)
	_check(finished.ok and finished.complete and vehicle.phase == "idle" and row.work_task.is_empty() and not lab.site_controller.work_team.is_assigned(executor) and _project(lab).receipts.size() == 1 and _project(lab).budget.payments.size() == 1, "True NPC completion commits one paid personal phase and clears the finite named original task")
	_cleanup_fixture(lab, team)
	await process_frame

func _run() -> void:
	deadline = Time.get_ticks_msec() + 90000
	await _controlled_vehicle_resume()
	await _npc_vehicle_resume()
	TerrainArmy.release_contact_source()
	print("SITE_TECHNOLOGY_TARGETED_VEHICLE_PASS: %d checks; actual Actor/Army/Family/PA/WT paid initial, station, quota, stop/resume and completion; full clock, analysis capture, Native, known N11 and full40 excluded" % checks)
	quit(0)
