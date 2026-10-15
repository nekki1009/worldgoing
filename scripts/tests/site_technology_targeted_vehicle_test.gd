extends "res://scripts/tests/site_technology_paid_feature_resume_test.gd"

const ReturnFailureGuard = preload("res://scripts/tests/fixtures/technology_return_failure_guard.gd")
var _return_errors: Variant = ReturnFailureGuard.new()

func _initialize() -> void:
	OS.add_logger(_return_errors)
	super._initialize()

func _finalize() -> void:
	OS.remove_logger(_return_errors)

func _process(delta: float) -> bool:
	if not _return_errors.accepts(self, true, ""): return false
	return super._process(delta)

func _require(condition: bool, message: String) -> bool:
	checks += 1
	return _return_errors.accepts(self, condition, message)

## True original Actor/Army membership, Family duties, paid vehicle and held
## PA/WT work. Controlled work uses the original shared planner and publisher;
## NPC direct intervals exclude movement/Fatigue/full TerrainLab frame proof.
## The analysis allowance is an explicit legal saved precondition, not proof
## of the separate 600-second capture/analysis owner transaction.
const VehiclePolicy = preload("res://scripts/terrain_lab/site_technology_policy.gd")

func _vehicle_team(lab: TerrainLab, join_actor: bool) -> TerrainArmy:
	var team: TerrainArmy = TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.team_id = 301
	team.roster_size = 2
	team.faction_id = 1
	var cells: Array[Vector2i] = [Vector2i(11, 11), Vector2i(12, 11)]
	if not _require(team.deploy_at(lab.terrain, lab.character, lab.npc, cells) and team.enable_combat(false), "Original finite Army creates true rows using the actual original Actors"): return null
	for row: Dictionary in team.combat_units:
		row.cargo = {}
		row.item_state = Runtime.new_item_state("person:" + str(row.person_id))
	lab.combat_armies.append(team)
	team.controlled_person_query = lab.controlled_person_id
	team.person_busy_query = lab.site_controller.person_actions.is_busy
	team.settle_combat_command()
	if not _require(team.set_duty_ai_enabled(team.combat_identity(team.formal_commander), true).ok, "The original NPC captain enables the real team duty flag"): return null
	if join_actor:
		if not _require(team.join_player(lab.character).ok and team.index_for_identity(lab.character.person_id) == TerrainArmy.PLAYER_MEMBER, "The actual Actor legally joins through the original Army owner"): return null
	return team

func _vehicle_family(lab: TerrainLab, team: TerrainArmy, executor: int) -> String:
	var actions = lab.site_controller.person_actions
	var control: int = lab.controlled_person_id()
	var refs: Array = []
	for identity: int in [control, int(lab.npc.person_id), team.combat_identity(0), team.combat_identity(1)]:
		refs.append({"site_id": str(lab.terrain.site.id), "person_id": identity, "path": "", "label": "真实原人物", "age_years": -1})
	if not _require(lab.site_controller.family_continuity.register_members(refs, true, control).ok and lab.site_controller.family_continuity.appoint_head(control, control).ok, "Original family registration and current duty establish the true named family"): return ""
	# Original pure schema upgrade for this explicitly registered prerequisite fixture.
	lab.terrain.site.family = actions._technology_candidate()
	lab.terrain.site.family.technology = Technology.empty_scope_record(str(lab.terrain.site.id))
	lab.terrain.site.family.technology.known = ["F09"]
	if not _require(Family.validate_family(lab.terrain.site.family, str(lab.terrain.site.id)), "Original Family validator admits the explicit legitimate prerequisite archive"): return ""
	if not _require(lab.character.place(Vector2i(9, 10), true), "The actual grantor stands at original camp contact"): return ""
	if not _require(actions.prepare_scope_technology(control, executor, "F11").ok, "Original F11 research names this actual executor"): return ""
	var family_id: String = str(lab.terrain.site.family.family_id)
	if not _require(actions.grant_scope_technology_budget(control, "family", family_id, {"wood": 300, "iron": 100, "fiber": 100, "cloth": 50}).ok and actions.request_scope_technology_consent(control, "family", family_id, executor).ok, "Original finite material grant and actual team consent are both accepted"): return ""
	return family_id

func _vehicle_station(data: TerrainData, kind: String, anchor: Vector2i) -> Vector2i:
	var proposed: Dictionary = {"kind": kind, "cell": data.index(anchor), "facing": [1, 0]}
	var slots: Array = Runtime.siege_work_slots(data, proposed)
	if not _require(slots.size() == 4, "Original vehicle geometry computes exactly four true construction stations"): return TerrainArmy.INVALID_CELL
	return data.cell_from_index(int(slots[0].cell))

func _controlled_vehicle_resume() -> bool:
	var data: TerrainData = _building_fixture()
	if not _return_errors.accepts(self, true, "callee failure"): return false
	var lab: TerrainLab = _building_lab(data)
	if not _return_errors.accepts(self, true, "callee failure"): return false
	var team: TerrainArmy = _vehicle_team(lab, true)
	if not _return_errors.accepts(self, true, "callee failure"): return false
	var control: int = lab.controlled_person_id()
	var actions = lab.site_controller.person_actions
	var family_id: String = _vehicle_family(lab, team, control)
	if not _return_errors.accepts(self, true, "callee failure"): return false
	var allowance: Dictionary = Technology.analysis_candidate(lab.character.technology, "F11", family_id, _project(lab), "original-consumed-engine", "original-accepted-capture")
	if not _require(not allowance.is_empty(), "Original strict historical analysis receipt is an explicit saved precondition"): return false
	lab.character.technology = allowance
	var key: String = str(int(data.site.get("next_vehicle", 1)))
	var target: String = "vehicle:" + key
	var request: Dictionary = {"anchor": Vector2i(20, 20), "facing": Vector2i.RIGHT, "team_id": int(team.team_id)}
	var before: PackedByteArray = var_to_bytes([data.site, actions._jobs, lab.character.technology, lab.character.fatigue])
	var refused = actions.begin_scope_technology_phase(control, "family", family_id, "ballista_build", target, request)
	if not _require(not refused.ok and refused.code == "UNREACHABLE" and var_to_bytes([data.site, actions._jobs, lab.character.technology, lab.character.fatigue]) == before, "A controlled Actor outside the real station cannot pay, allocate credit or publish any job"): return false
	var station: Vector2i = _vehicle_station(data, "ballista", request.anchor)
	if not _return_errors.accepts(self, true, "callee failure"): return false
	if not _require(lab.character.place(station, true), "Actual original Actor reaches the original construction station"): return false
	var npc_origin: Vector2i = lab.npc.terrain_cell
	var build_stations: Array = Runtime.siege_work_slots(data, {"kind": "ballista", "cell": data.index(request.anchor), "facing": [1, 0]})
	if not _require(build_stations.size() == 4 and int(build_stations[1].cell) != data.index(station), "Original geometry provides a distinct construction station for the second real Actor"): return false
	var occupied_station: Vector2i = data.cell_from_index(int(build_stations[1].cell))
	if not _require(lab.npc.place(occupied_station, true), "A second actual original Actor legally occupies another original construction station"): return false
	before = var_to_bytes([data.site, actions._jobs, lab.character.technology])
	refused = actions.begin_scope_technology_phase(control, "family", family_id, "ballista_build", target, request)
	if not _require(not refused.ok and refused.code == "OCCUPIED" and var_to_bytes([data.site, actions._jobs, lab.character.technology]) == before, "The named-person exclusion cannot hide a second original Actor or debit any stock"): return false
	if not _require(lab.npc.place(npc_origin, true), "The other real Actor leaves the station"): return false
	before = var_to_bytes([data.site, actions._jobs, lab.character.technology])
	var preview: Dictionary = Runtime.begin_technology_operation(data, _token(lab, control, target), true, request)
	if not _require(preview.ok and var_to_bytes([data.site, actions._jobs, lab.character.technology]) == before, "A legal actual stationed named Actor previews without its own body falsely blocking the station"): return false
	var stock = data.site.inventory.duplicate()
	var started = actions.begin_scope_technology_phase(control, "family", family_id, "ballista_build", target, request)
	if not _require(started.ok and actions.is_busy(control) and actions.save_guard().code == "BUSY", "Actual material, credit, vehicle and original controlled work are published in one tail"): return false
	var vehicle: Dictionary = data.site.vehicles[key]
	var token: Dictionary = vehicle.tech_trial
	var job: Dictionary = actions._jobs[str(control)]
	if not _require(job.kind == "technology_vehicle" and is_same(job.vehicle_ref, vehicle) and is_same(job.build_ref, vehicle.build) and is_same(job.operation_selector.token, token) and not _has_actor_work_task(lab.character), "Original PA _jobs owns the SAME task and original vehicle; Actor schema is unchanged"): return false
	if not _require(vehicle.build.total_work == 5400.0 and vehicle.tech_work_credit == {"remaining_work": 5400.0, "credit": 2700.0} and lab.character.technology.analysis[0].used_work == 2700.0 and _project(lab).budget.payments.size() == 1, "One actual 50-percent allocation keeps immutable original work and one real full payment"): return false
	for resource: String in Runtime.SIEGE_DEFINITIONS.ballista.cost:
		if not _require(int(data.site.inventory[resource]) == int(stock[resource]) - int(Runtime.SIEGE_DEFINITIONS.ballista.cost[resource]), "Original full vehicle material is deducted exactly once: " + resource): return false
	before = var_to_bytes([vehicle, lab.character.technology, lab.character.fatigue])
	actions.advance(600.0, {})
	if not _require(var_to_bytes([vehicle, lab.character.technology, lab.character.fatigue]) == before, "No canonical collector means no timer progress, evidence or fatigue"): return false
	var step: Dictionary = _controlled_step(lab, 60.0)
	if not _return_errors.accepts(self, true, "callee failure"): return false
	if not _require(vehicle.build.progress == 120.0 and vehicle.tech_batch.work_seconds == 60.0 and float(step.handled.get(control, -1.0)) == 60.0 and PersonalFatigue.read(lab.character) > 0.0, "True 60-second effort moves only physical progress by two; original shared fatigue is charged once"): return false
	var stopped_project: Dictionary = _project(lab)
	var paid: PackedByteArray = var_to_bytes(_project(lab).budget)
	var attempt: int = int(_project(lab).next_attempt)
	var stop_projection: Dictionary = actions.job_for(control)
	var stop_before: PackedByteArray = var_to_bytes([data.site, lab.character.technology, actions._jobs.keys()])
	if not _require(stop_projection == job and not is_same(stop_projection, job) and is_same(actions._jobs[str(control)], job) and is_same(job.operation_selector.token, token) and not is_same(stop_projection.operation_selector.token, token), "Original job_for is a deep read projection while the registry retains the same live operation token"): return false
	var stop_refused: Dictionary = actions.stop_scope_technology(team.combat_identity(0), "family", family_id)
	if not _require(not stop_refused.ok and stop_refused.code == "NO_AUTHORITY" and var_to_bytes([data.site, lab.character.technology, actions._jobs.keys()]) == stop_before and is_same(actions._jobs[str(control)], job), "Unrelated original NPC cannot stop or replace the real controlled paid job"): return false
	var stop_result: Dictionary = actions.stop_scope_technology(control, "family", family_id)
	print("TECH_SCOPE_STOP_DIAG " + JSON.stringify({"result": stop_result, "busy_after": actions.is_busy(control), "live_job_remaining": actions._jobs.has(str(control)), "same_job_after": is_same(actions._jobs.get(str(control)), job), "same_paid_token_after": is_same(vehicle.get("tech_trial"), token), "progress_after": vehicle.build.get("progress"), "active_after": data.site.family.technology.get("active")}))
	if not _return_errors.accepts(self, true, "original Scope stop error"): return false
	if not _require(stop_result.ok and not actions.is_busy(control), "Original Scope stop immediately cancels this exact controlled vehicle job"): return false
	if not _require(data.site.family.technology.active == 0 and data.site.family.technology.projects.any(func(project: Dictionary) -> bool: return is_same(project, stopped_project)) and stopped_project.has("budget"), "Stopped research retains the same stored project and real budget even when no project is active"): return false
	if not _require(not actions._jobs.has(str(control)) and is_same(vehicle.tech_trial, token) and vehicle.build.progress == 120.0 and var_to_bytes(stopped_project.budget) == paid and lab.character.technology.analysis[0].used_work == 2700.0, "Stopping the exact controlled job retains its original paid target, progress, budget and consumed allowance"): return false
	if not _require(actions.prepare_scope_technology(control, control, "F11").ok, "Original project reactivates its same purpose and retained paid target"): return false
	if not _require(lab.character.place(Vector2i(9, 10), true), "The actual worker temporarily leaves the station"): return false
	before = var_to_bytes([data.site, actions._jobs, lab.character.technology])
	refused = actions.begin_scope_technology_phase(control, "family", family_id, "ballista_build", target)
	if not _require(not refused.ok and refused.code == "UNREACHABLE" and var_to_bytes([data.site, actions._jobs, lab.character.technology]) == before, "Canceled paid resume still requires the true original controlled station"): return false
	if not _require(lab.character.place(station, true), "Actual worker returns to the SAME original station"): return false
	started = actions.begin_scope_technology_phase(control, "family", family_id, "ballista_build", target)
	if not _require(started.ok and started.resumed and not started.already_working and actions.is_busy(control) and is_same(vehicle.tech_trial, token) and is_same(actions._jobs[str(control)].vehicle_ref, vehicle) and vehicle.build.progress == 120.0 and int(_project(lab).next_attempt) == attempt and var_to_bytes(_project(lab).budget) == paid and lab.character.technology.analysis[0].used_work == 2700.0, "Resume republishes actual SAME paid work without stock/attempt/quota/credit double charge"): return false
	before = var_to_bytes([data.site, actions._jobs, lab.character.technology])
	var busy_command: Dictionary = actions.prepare_scope_technology(control, control, "F11")
	if not _require(not busy_command.ok and busy_command.code == "BUSY" and var_to_bytes([data.site, actions._jobs, lab.character.technology]) == before, "The live controlled research job does not admit a general Scope command"): return false
	var wrong_target: Dictionary = actions.begin_scope_technology_phase(control, "family", family_id, "ballista_build", "vehicle:unrelated")
	if not _require(not wrong_target.ok and wrong_target.code == "BUSY" and var_to_bytes([data.site, actions._jobs, lab.character.technology]) == before and is_same(actions._jobs[str(control)].operation_selector.token, token), "A busy original worker cannot use the resume exception for another target or replace the live token"): return false
	started = actions.begin_scope_technology_phase(control, "family", family_id, "ballista_build", target)
	print("TECH_SCOPE_RESUME_DIAG " + JSON.stringify({"result": started, "bytes_unchanged": var_to_bytes([data.site, actions._jobs, lab.character.technology]) == before, "same_token": is_same(actions._jobs.get(str(control), {}).get("operation_selector", {}).get("token"), token)}))
	if not _return_errors.accepts(self, true, "original Scope repeat resume"): return false
	if not _require(started.ok and started.already_working and var_to_bytes([data.site, actions._jobs, lab.character.technology]) == before, "Existing genuine controlled vehicle task resumes as a byte-equivalent no-op"): return false
	_controlled_step(lab, 2640.0)
	if not _return_errors.accepts(self, true, "callee failure"): return false
	if not _require(vehicle.phase == "idle" and vehicle.build.is_empty() and not actions.is_busy(control) and not vehicle.has("tech_trial") and not vehicle.has("tech_work_credit") and vehicle.technology_construction.work_seconds == 2700.0 and _project(lab).receipts.size() == 1 and _project(lab).budget.payments.size() == 1, "Original real completion accepts one truthful named phase and stops work without producing another vehicle"): return false
	if not _require(data.site.family.technology.siege_history.size() == 1 and Family.validate_family(data.site.family, str(data.site.id)) and not Technology.learned(lab.character.technology, "F11"), "One original ballista adds bounded real family history, while F11 still needs the distinct tower"): return false
	data.site.world_pin = {"format": 2, "technology_policy": VehiclePolicy.new_policy(["F11"]).policy}
	key = str(int(data.site.next_vehicle))
	target = "vehicle:" + key
	request = {"anchor": Vector2i(32, 20), "facing": Vector2i.RIGHT, "team_id": int(team.team_id)}
	if not _require(lab.character.place(_vehicle_station(data, "siege_tower", request.anchor), true), "Actual unlearned research worker stands at the distinct tower station"): return false
	before = var_to_bytes([data.site, actions._jobs, lab.character.technology])
	preview = Runtime.begin_technology_operation(data, _token(lab, control, target), true, request)
	if not _require(preview.ok and var_to_bytes([data.site, actions._jobs, lab.character.technology]) == before, "Legal current F11 trial exception admits true tower preview under frozen F11 policy without first requiring learned F11"): return false
	before = var_to_bytes(data.site)
	refused = Runtime.begin_siege_build(data, "siege_tower", Vector2i(40, 35), Vector2i.RIGHT, int(team.team_id), control, Callable(), true)
	if not _require(not refused.ok and refused.code == "NO_OPERATOR" and var_to_bytes(data.site) == before, "New gated ordinary tower requires a real named skilled operator before cost"): return false
	for categories: Array in [[], ["F04"]]:
		data.site.world_pin = {"format": 2, "technology_policy": VehiclePolicy.new_policy(categories).policy}
		if not _require(Runtime.begin_siege_build(data, "siege_tower", Vector2i(40, 35), Vector2i.RIGHT, int(team.team_id), control, Callable(), true).ok, "Empty or F04-only world admits ordinary ungated siege preview without artificial prior F11"): return false
	data.site.world_pin = {"format": 2}
	before = var_to_bytes(data.site)
	refused = Runtime.begin_siege_build(data, "ballista", Vector2i(40, 35), Vector2i.RIGHT, int(team.team_id), control, Callable(), true)
	if not _require(not refused.ok and var_to_bytes(data.site) == before, "Malformed new-world policy fails before an ordinary payment, even for an ungated type"): return false
	_cleanup_fixture(lab, team)
	if not _return_errors.accepts(self, true, "callee failure"): return false
	await process_frame
	return true

func _npc_vehicle_resume() -> bool:
	var data: TerrainData = _building_fixture()
	if not _return_errors.accepts(self, true, "callee failure"): return false
	var lab: TerrainLab = _building_lab(data)
	if not _return_errors.accepts(self, true, "callee failure"): return false
	var team: TerrainArmy = _vehicle_team(lab, false)
	if not _return_errors.accepts(self, true, "callee failure"): return false
	var actions = lab.site_controller.person_actions
	var control: int = lab.controlled_person_id()
	var executor: int = team.combat_identity(1)
	var family_id: String = _vehicle_family(lab, team, executor)
	if not _return_errors.accepts(self, true, "callee failure"): return false
	var key: String = str(int(data.site.get("next_vehicle", 1)))
	var target: String = "vehicle:" + key
	var request: Dictionary = {"anchor": Vector2i(20, 20), "facing": Vector2i.RIGHT, "team_id": int(team.team_id)}
	var started = actions.begin_scope_technology_phase(control, "family", family_id, "ballista_build", target, request)
	if not _require(started.ok and lab.site_controller.work_team.is_assigned(executor), "Original Runtime publishes the actual named WT vehicle task in the same paid tail"): return false
	var vehicle: Dictionary = data.site.vehicles[key]
	var token: Dictionary = vehicle.tech_trial
	var row: Dictionary = team.combat_units[1]
	var task: Dictionary = row.work_task
	if not _require(task.version == 3 and task.named and task.target == target and task.action == "construct" and task.zone == -1, "The original saved task is strictly the vehicle named schema"): return false
	team.cells[1] = data.cell_from_index(int(task.work_cell))
	task.cell = int(task.work_cell)
	task.mode = "work"
	var before: PackedByteArray = var_to_bytes(vehicle)
	var wrong: Dictionary = Runtime.advance_siege_work(data, key, "construct", 60.0, team.cells[1], int(task.work_slot), int(team.team_id), task, team.combat_identity(0))
	if not _require(not wrong.ok and var_to_bytes(vehicle) == before, "Another real NPC cannot borrow the SAME named task identity"): return false
	if not _require(Runtime.advance_siege_work(data, key, "construct", 60.0, team.cells[1], int(task.work_slot), int(team.team_id), task, executor).ok and vehicle.build.progress == 60.0, "The actual original NPC at its true station performs a real direct interval"): return false
	var paid: PackedByteArray = var_to_bytes(_project(lab).budget)
	var attempt: int = int(_project(lab).next_attempt)
	if not _require(actions.stop_scope_technology(control, "family", family_id).ok and not lab.site_controller.work_team.is_assigned(executor) and row.work_task.is_empty(), "Original Scope stop removes its exact true NPC vehicle assignment"): return false
	if not _require(actions.prepare_scope_technology(control, executor, "F11").ok, "Original project reactivates the retained purpose"): return false
	started = actions.begin_scope_technology_phase(control, "family", family_id, "ballista_build", target)
	task = row.work_task
	if not _require(started.ok and started.resumed and not started.already_working and lab.site_controller.work_team.is_assigned(executor) and task.version == 3 and is_same(vehicle.tech_trial, token) and vehicle.build.progress == 60.0 and var_to_bytes(_project(lab).budget) == paid and int(_project(lab).next_attempt) == attempt, "Paid NPC resume republishes genuine original work with no stock/attempt/payment reset"): return false
	before = var_to_bytes([data.site, row])
	started = actions.begin_scope_technology_phase(control, "family", family_id, "ballista_build", target)
	if not _require(started.ok and started.already_working and var_to_bytes([data.site, row]) == before, "A genuine idle/traveling named WT task is preserved as a no-op"): return false
	team.cells[1] = data.cell_from_index(int(task.work_cell))
	task.cell = int(task.work_cell)
	task.mode = "work"
	var finished: Dictionary = Runtime.advance_siege_work(data, key, "construct", 5340.0, team.cells[1], int(task.work_slot), int(team.team_id), task, executor)
	if not _require(finished.ok and finished.complete and vehicle.phase == "idle" and row.work_task.is_empty() and not lab.site_controller.work_team.is_assigned(executor) and _project(lab).receipts.size() == 1 and _project(lab).budget.payments.size() == 1, "True NPC completion commits one paid personal phase and clears the finite named original task"): return false
	_cleanup_fixture(lab, team)
	if not _return_errors.accepts(self, true, "callee failure"): return false
	await process_frame
	return true

func _run() -> void:
	deadline = Time.get_ticks_msec() + 90000
	var returned_phase_0_next: bool = await _controlled_vehicle_resume()
	if not returned_phase_0_next: return
	var returned_phase_1_next: bool = await _npc_vehicle_resume()
	if not returned_phase_1_next: return
	TerrainArmy.release_contact_source()
	if not _return_errors.accepts(self, true, "before PASS"): return
	print("SITE_TECHNOLOGY_TARGETED_VEHICLE_PASS: %d checks; actual Actor/Army/Family/PA/WT paid initial, station, quota, stop/resume and completion; full clock, analysis capture, Native, known N11 and full40 excluded" % checks)
	quit(0)

func _controlled_step(lab: TerrainLab, seconds: float) -> Dictionary:
	var workers = lab.site_controller.work_team
	var empty_work: Array[Dictionary] = workers.prepare_work_requests(seconds)
	if not _require(empty_work.is_empty(), "Controlled-only fixture prepares the real empty WT interval before shared preflight"): return {}
	var actions = lab.site_controller.person_actions
	var requests = actions.work_requests(seconds)
	if not _require(requests.size() == 1 and requests[0].provider == "person_actions", "Original PA contributes the one actual held feature job"): return {}
	lab._shared_work_requests = requests
	var refreshed = lab._refresh_shared_work_preflight()
	if not _require(refreshed.ok and str(lab._shared_work_requests[0].get("paused", "")).is_empty(), "Original shared preflight admits this SAME PA task and its actual final water context"): return {}
	var planned = PersonalFatigue.plan_work_interval(lab._shared_work_requests, seconds)
	if not _require(planned.ok, "The original complete-pool planner accepts actual effort, without a surrogate body"): return {}
	lab._shared_work_plan = planned
	lab.site_controller._shared_work_plan = planned
	lab._shared_work_pools_committed = false
	lab._commit_shared_work_pools()
	var before_second_pool = PersonalFatigue.read(lab.character)
	lab._commit_shared_work_pools()
	if not _require(PersonalFatigue.read(lab.character) == before_second_pool, "The original shared pool publisher commits only once"): return {}
	var jobs: Dictionary = planned.jobs.get("person_actions", {})
	var handled = actions.advance(seconds, {"jobs": jobs})
	var after = var_to_bytes([lab.terrain.site, lab.character.technology, lab.character.fatigue, lab.character.ammo_inventory])
	actions.advance(seconds, {"jobs": jobs})
	if not _require(var_to_bytes([lab.terrain.site, lab.character.technology, lab.character.fatigue, lab.character.ammo_inventory]) == after, "The SAME original admitted allocation cannot be consumed twice"): return {}
	workers.discard_prepared_interval()
	return {"plan": planned, "handled": handled.handled_seconds}
