extends "res://scripts/tests/site_technology_work_credit_test.gd"

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

## Actual NPC WorkTeam/Fatigue/Runtime paid credit, separate from the PA test.
## The previous analysis receipt is an explicit strict saved precondition.
## This does not prove capture provenance, whole Lab/Native time or rendering.

func _weights_fixture() -> Dictionary:
	var data: TerrainData = _building_fixture()
	if not _return_errors.accepts(self, true, "callee failure"): return {}
	var lab: TerrainLab = _building_lab(data)
	if not _return_errors.accepts(self, true, "callee failure"): return {}
	var control: int = lab.controlled_person_id()
	var actions = lab.site_controller.person_actions
	var team: TerrainArmy = _army(lab, data)
	if not _return_errors.accepts(self, true, "callee failure"): return {}
	team.exchange_enabled = true
	team.sync_shared_fatigue(true)
	var executor: int = team.combat_identity(1)
	var row: Dictionary = team.combat_units[1]
	if not _require(lab.character.place(Vector2i(9, 10), true), "Actual camp grantor is physically present"): return {}
	var refs: Array = []
	for identity: int in [control, int(lab.npc.person_id), team.combat_identity(0), executor]:
		refs.append({"site_id": str(data.site.id), "person_id": identity, "path": "", "label": "真原成員", "age_years": -1})
	if not _require(lab.site_controller.family_continuity.register_members(refs, true, control).ok and lab.site_controller.family_continuity.appoint_head(control, control).ok, "Original registry and head establish the actual family"): return {}
	var family_candidate: Dictionary = actions._technology_candidate()
	if not _require(not family_candidate.is_empty() and Family.validate_family(family_candidate, str(data.site.id)), "Original pure Family migration admits the same registered members and offices before the explicit saved archive"): return {}
	data.site.family = family_candidate
	data.site.family.technology = Technology.empty_scope_record(str(data.site.id))
	data.site.family.technology.known = ["F09"]
	if not _require(actions.prepare_scope_technology(control, executor, "F11").ok, "Actual unlearned original NPC prepares its genuine research purpose"): return {}
	var family_id: String = str(data.site.family.family_id)
	if not _require(actions.grant_scope_technology_budget(control, "family", family_id, {"wood": 300, "iron": 100, "fiber": 100, "cloth": 50}).ok and actions.request_scope_technology_consent(control, "family", family_id, executor).ok, "Finite original camp budget and true original AI consent are accepted"): return {}
	row.technology = Technology.analysis_candidate({}, "F11", family_id, _project(lab), "previously-consumed-real-engine", "previously-accepted-real-capture")
	if not _require(Technology.valid_person(row.technology), "One strict previously earned analysis allowance is the source precondition"): return {}
	var key: String = str(int(data.site.get("next_vehicle", 1)))
	var request: Dictionary = {"anchor": Vector2i(20, 20), "facing": Vector2i.RIGHT, "team_id": team.team_id}
	if not _require(actions.begin_scope_technology_phase(control, "family", family_id, "ballista_build", "vehicle:" + key, request).ok, "Actual Runtime publishes one paid original vehicle and its original targeted NPC task"): return {}
	var vehicle: Dictionary = data.site.vehicles[key]
	var task: Dictionary = _work_task(lab, team, executor, key)
	if not _return_errors.accepts(self, true, "callee failure"): return {}
	return {"lab": lab, "data": data, "team": team, "row": row, "executor": executor, "key": key, "vehicle": vehicle, "task": task}

func _weights_point(fixture: Dictionary, seconds: float) -> Dictionary:
	var lab: TerrainLab = fixture.lab
	var workers = lab.site_controller.work_team
	var requests = workers.prepare_work_requests(seconds)
	if not _require(requests.size() == 1 and is_same(requests[0].participants[0].body, fixture.row), "The real original NPC body is the sole participant, not a proxy"): return {}
	if not _require(requests[0].productive_kind == "sum" and float(requests[0].progress_multiplier) == 1.0 and float(requests[0].participants[0].progress_multiplier) == 2.0, "Original T6 factor belongs to physical individual weight rather than the global research multiplier"): return {}
	if not _require(requests[0].required_all_any_ids.has([int(fixture.executor)]), "The actual named trial participant remains its own required master group"): return {}
	lab._shared_work_requests = requests
	if not _require(lab._refresh_shared_work_preflight().ok, "Actual held request retains its original credit factor through final preflight"): return {}
	var captured = workers.prepare_shared_work_prefix(seconds)
	var plan: Dictionary = PersonFatigue.plan_work_interval(lab._shared_work_requests, seconds)
	if not _require(captured.ok and plan.ok, "True original credit request is valid for the existing pure planner"): return {}
	var prior: Array = []
	var state: PackedByteArray = var_to_bytes([fixture.data.site, fixture.team.capture_combat_state()])
	var prepared = workers.validate_shared_work_prefix(captured, plan, prior)
	if not _require(prepared.ok and var_to_bytes([fixture.data.site, fixture.team.capture_combat_state()]) == state, "All true Runtime candidates validate before stock, credit, progress or fatigue changes"): return {}
	lab._shared_work_plan = plan
	lab.site_controller._shared_work_plan = plan
	lab._shared_work_pools_committed = false
	lab._commit_shared_work_pools()
	var handled = workers.publish_shared_work_prefix(prepared)
	var once: PackedByteArray = var_to_bytes([fixture.vehicle, fixture.row.technology, fixture.team.team_fatigue])
	workers.publish_shared_work_prefix(prepared)
	lab._commit_shared_work_pools()
	if not _require(var_to_bytes([fixture.vehicle, fixture.row.technology, fixture.team.team_fatigue]) == once, "Same true WorkTeam publication never recharges physical work, credit or shared fatigue"): return {}
	workers.finish_shared_work_prefix(prepared)
	if not _require(bool(prepared.get("finished", false)) and is_same(prior, prepared.runtime_priors), "Only the settled original endpoint may release this same transient sequential ledger"): return {}
	# The prior Array owns candidates whose prefix_ref points back to this Array.
	prior.clear()
	for candidate: Dictionary in prepared.runtime:
		# The loop is broken when the finished prefix no longer names the ledger at all,
		# or still names this SAME emptied ledger.
		if not _require(not candidate.prefix_ref.has("runtime_priors") or is_same(candidate.prefix_ref.runtime_priors, prior) and candidate.prefix_ref.runtime_priors.is_empty(), "Terminal cleanup breaks the actual prefix-prior cycle after all publication checks"): return {}
	return {"plan": plan, "prepared": prepared, "handled": handled}

func _run() -> void:
	var fixture := _weights_fixture()
	if not _return_errors.accepts(self, true, "callee failure"): return
	var vehicle: Dictionary = fixture.vehicle
	var used: float = float(fixture.row.technology.analysis[0].used_work)
	var paid: PackedByteArray = var_to_bytes(_project(fixture.lab).budget)
	if not _require(vehicle.build.total_work == 5400.0 and vehicle.tech_work_credit == {"remaining_work": 5400.0, "credit": 2700.0} and used == 2700.0, "Original immutable work and lifetime allowance are charged once at the genuine operation start"): return
	var first: Dictionary = _weights_point(fixture, 2690.0)
	if not _return_errors.accepts(self, true, "callee failure"): return
	if not _require(float(vehicle.build.progress) == 5380.0 and float(vehicle.tech_batch.work_seconds) == 2690.0, "2690 true productive seconds give 5380 physical progress and one unweighted personal ledger"): return
	if not _require(float(first.prepared.runtime[0].prefix_ref.productive_seconds) == 2690.0 and float(first.prepared.runtime[0].prefix_ref.applied_productive_seconds) == 5380.0, "Same registered prefix exposes distinct true personal and physical units"): return
	if not _require(float(fixture.row.technology.analysis[0].used_work) == used and var_to_bytes(_project(fixture.lab).budget) == paid, "Work consumes neither a second allowance nor a repeated payment"): return
	var second: Dictionary = _weights_point(fixture, 10.0)
	if not _return_errors.accepts(self, true, "callee failure"): return
	if not _require(float(second.prepared.runtime[0].prefix_ref.productive_seconds) == 10.0 and float(second.prepared.runtime[0].prefix_ref.applied_productive_seconds) == 20.0, "The last real prefix reaches the original baseline endpoint with one factor"): return
	if not _require(vehicle.phase == "idle" and vehicle.build.is_empty() and not vehicle.has("tech_work_credit") and vehicle.technology_construction.work_seconds == 2700.0, "Actual current endpoint completes the same finite original paid engine and truthful personal work"): return
	if not _require(_project(fixture.lab).receipts.size() == 1 and _project(fixture.lab).budget.payments.size() == 1 and float(fixture.row.technology.analysis[0].used_work) == used, "One true T6 completion grants one bounded phase while keeping spent lifetime credit"): return
	for identity: int in fixture.lab.site_controller.work_team.active_ids():
		if not _require(fixture.lab.site_controller.work_team.cancel(identity).ok, "Original cleanup releases each actual remaining assignment"): return
	fixture.lab.site_controller.work_team.discard_prepared_interval()
	fixture.lab.site_controller.work_team.unavailable = Callable()
	fixture.lab.site_controller.work_team.vehicle_blocked = Callable()
	fixture.lab.site_controller.equipment_orders.nation_arsenal_request = Callable()
	fixture.lab.site_controller.equipment_orders.nation_owner_receipt_query = Callable()
	fixture.team.controlled_person_query = Callable()
	fixture.team.person_busy_query = Callable()
	first.clear()
	second.clear()
	fixture.lab.combat_armies.clear()
	fixture.team.free()
	fixture.lab.free()
	await process_frame
	TerrainArmy.release_contact_source()
	if not _return_errors.accepts(self, true, "before PASS"): return
	print("SITE_WORK_TEAM_T6_WEIGHTS_PASS checks=", checks, " original NPC/task/credit/Runtime/shared-pool publication; individual effort unweighted, physical factor once; no capture/whole-clock/Native/GPU claim")
	quit(0)

func _army(lab: TerrainLab, data: TerrainData) -> TerrainArmy:
	var team: TerrainArmy = TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.team_id = 301
	team.roster_size = 2
	team.faction_id = 1
	var cells: Array[Vector2i] = [Vector2i(11, 11), Vector2i(12, 11)]
	if not _require(team.deploy_at(data, null, null, cells) and team.enable_combat(false), "Original finite Army creates and initializes its real NPC rows"): return null
	for row: Dictionary in team.combat_units:
		row.cargo = {}
		row.item_state = Runtime.new_item_state("person:" + str(row.person_id))
	lab.combat_armies.append(team)
	team.controlled_person_query = lab.controlled_person_id
	team.person_busy_query = lab.site_controller.person_actions.is_busy
	team.settle_combat_command()
	if not _require(team.set_duty_ai_enabled(team.combat_identity(team.formal_commander), true).ok, "Actual original captain explicitly enables the actual duty flag"): return null
	return team

func _work_task(lab: TerrainLab, team: TerrainArmy, executor: int, key: String) -> Dictionary:
	var work = lab.site_controller.work_team
	var row: Dictionary = team.combat_units[team.index_for_identity(executor)]
	var already_named = work.is_assigned(executor) and row.get("work_task", {}).get("version") == 3 and row.work_task.get("named") == true and row.work_task.get("target") == "vehicle:" + key
	var selected_workers: Array[int] = [executor]
	if not already_named:
		if not _require(work.assign(team, selected_workers, team.duty_decider("team.work")).ok, "Actual original team.work authority assigns the true ordinary member"): return {}
	var slots: Array = Runtime.siege_work_slots(lab.terrain, lab.terrain.site.vehicles[key])
	if not _require(not slots.is_empty(), "Actual original vehicle computes its original work slots"): return {}
	# The fixture places the ORIGINAL Army hot cell at this real station. This
	# excludes travel acceptance; no surrogate body, consent, receipt or validator.
	team.cells[team.index_for_identity(executor)] = lab.terrain.cell_from_index(int(slots[0].cell))
	if not already_named: Runtime.assign_task(lab.terrain, Runtime.ok("原fixture明示真施工工位", {"target": "vehicle:" + key, "action": "construct", "work_slot": int(slots[0].slot), "cell": int(slots[0].cell), "zone": -1}), row.work_task)
	row.work_task.cell = int(slots[0].cell)
	row.work_task.mode = "work"
	if not _require(not lab.site_controller.person_actions._technology_operator_for_task(row.work_task, executor).is_empty(), "PA resolves the SAME original body/task/assigned member at the real station"): return {}
	return row.work_task
