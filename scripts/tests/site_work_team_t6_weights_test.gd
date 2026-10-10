extends "res://scripts/tests/site_technology_work_credit_test.gd"
## Actual NPC WorkTeam/Fatigue/Runtime paid credit, separate from the PA test.
## The previous analysis receipt is an explicit strict saved precondition.
## This does not prove capture provenance, whole Lab/Native time or rendering.

func _weights_fixture() -> Dictionary:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var control := lab.controlled_person_id()
	var actions = lab.site_controller.person_actions
	var team := _army(lab, data)
	team.exchange_enabled = true
	team.sync_shared_fatigue(true)
	var executor := team.combat_identity(1)
	var row: Dictionary = team.combat_units[1]
	_check(lab.character.place(Vector2i(9, 10), true), "Actual camp grantor is physically present")
	var refs: Array = []
	for identity: int in [control, int(lab.npc.person_id), team.combat_identity(0), executor]:
		refs.append({"site_id": str(data.site.id), "person_id": identity, "path": "", "label": "真原成員", "age_years": -1})
	_check(lab.site_controller.family_continuity.register_members(refs, true, control).ok and lab.site_controller.family_continuity.appoint_head(control, control).ok, "Original registry and head establish the actual family")
	data.site.family.technology = Technology.empty_scope_record(str(data.site.id))
	data.site.family.technology.known = ["F09"]
	_check(actions.prepare_scope_technology(control, executor, "F11").ok, "Actual unlearned original NPC prepares its genuine research purpose")
	var family_id := str(data.site.family.family_id)
	_check(actions.grant_scope_technology_budget(control, "family", family_id, {"wood": 300, "iron": 100, "fiber": 100, "cloth": 50}).ok and actions.request_scope_technology_consent(control, "family", family_id, executor).ok, "Finite original camp budget and true original AI consent are accepted")
	row.technology = Technology.analysis_candidate({}, "F11", family_id, _project(lab), "previously-consumed-real-engine", "previously-accepted-real-capture")
	_check(Technology.valid_person(row.technology), "One strict previously earned analysis allowance is the source precondition")
	var key := str(int(data.site.get("next_vehicle", 1)))
	var request := {"anchor": Vector2i(20, 20), "facing": Vector2i.RIGHT, "team_id": team.team_id}
	_check(actions.begin_scope_technology_phase(control, "family", family_id, "ballista_build", "vehicle:" + key, request).ok, "Actual Runtime publishes one paid original vehicle and its original targeted NPC task")
	var vehicle: Dictionary = data.site.vehicles[key]
	var task := _work_task(lab, team, executor, key)
	return {"lab": lab, "data": data, "team": team, "row": row, "executor": executor, "key": key, "vehicle": vehicle, "task": task}

func _weights_point(fixture: Dictionary, seconds: float) -> Dictionary:
	var lab: TerrainLab = fixture.lab
	var workers = lab.site_controller.work_team
	var requests = workers.prepare_work_requests(seconds)
	_check(requests.size() == 1 and is_same(requests[0].participants[0].body, fixture.row), "The real original NPC body is the sole participant, not a proxy")
	_check(requests[0].productive_kind == "sum" and float(requests[0].progress_multiplier) == 1.0 and float(requests[0].participants[0].progress_multiplier) == 2.0, "Original T6 factor belongs to physical individual weight rather than the global research multiplier")
	_check(requests[0].required_all_any_ids.has([int(fixture.executor)]), "The actual named trial participant remains its own required master group")
	lab._shared_work_requests = requests
	_check(lab._refresh_shared_work_preflight().ok, "Actual held request retains its original credit factor through final preflight")
	var captured = workers.prepare_shared_work_prefix(seconds)
	var plan := PersonFatigue.plan_work_interval(lab._shared_work_requests, seconds)
	_check(captured.ok and plan.ok, "True original credit request is valid for the existing pure planner")
	var prior: Array = []
	var state := var_to_bytes([fixture.data.site, fixture.team.capture_combat_state()])
	var prepared = workers.validate_shared_work_prefix(captured, plan, prior)
	_check(prepared.ok and var_to_bytes([fixture.data.site, fixture.team.capture_combat_state()]) == state, "All true Runtime candidates validate before stock, credit, progress or fatigue changes")
	lab._shared_work_plan = plan
	lab.site_controller._shared_work_plan = plan
	lab._shared_work_pools_committed = false
	lab._commit_shared_work_pools()
	var handled = workers.publish_shared_work_prefix(prepared)
	var once := var_to_bytes([fixture.vehicle, fixture.row.technology, fixture.team.team_fatigue])
	workers.publish_shared_work_prefix(prepared)
	lab._commit_shared_work_pools()
	_check(var_to_bytes([fixture.vehicle, fixture.row.technology, fixture.team.team_fatigue]) == once, "Same true WorkTeam publication never recharges physical work, credit or shared fatigue")
	workers.finish_shared_work_prefix(prepared)
	return {"plan": plan, "prepared": prepared, "handled": handled}

func _run() -> void:
	var fixture := _weights_fixture()
	var vehicle: Dictionary = fixture.vehicle
	var used := float(fixture.row.technology.analysis[0].used_work)
	var paid := var_to_bytes(_project(fixture.lab).budget)
	_check(vehicle.build.total_work == 5400.0 and vehicle.tech_work_credit == {"remaining_work": 5400.0, "credit": 2700.0} and used == 2700.0, "Original immutable work and lifetime allowance are charged once at the genuine operation start")
	var first := _weights_point(fixture, 2690.0)
	_check(float(vehicle.build.progress) == 5380.0 and float(vehicle.tech_batch.work_seconds) == 2690.0, "2690 true productive seconds give 5380 physical progress and one unweighted personal ledger")
	_check(float(first.prepared.runtime[0].prefix_ref.productive_seconds) == 2690.0 and float(first.prepared.runtime[0].prefix_ref.applied_productive_seconds) == 5380.0, "Same registered prefix exposes distinct true personal and physical units")
	_check(float(fixture.row.technology.analysis[0].used_work) == used and var_to_bytes(_project(fixture.lab).budget) == paid, "Work consumes neither a second allowance nor a repeated payment")
	var second := _weights_point(fixture, 10.0)
	_check(float(second.prepared.runtime[0].prefix_ref.productive_seconds) == 10.0 and float(second.prepared.runtime[0].prefix_ref.applied_productive_seconds) == 20.0, "The last real prefix reaches the original baseline endpoint with one factor")
	_check(vehicle.phase == "idle" and vehicle.build.is_empty() and not vehicle.has("tech_work_credit") and vehicle.technology_construction.work_seconds == 2700.0, "Actual current endpoint completes the same finite original paid engine and truthful personal work")
	_check(_project(fixture.lab).receipts.size() == 1 and _project(fixture.lab).budget.payments.size() == 1 and float(fixture.row.technology.analysis[0].used_work) == used, "One true T6 completion grants one bounded phase while keeping spent lifetime credit")
	fixture.lab.site_controller.work_team.discard_prepared_interval()
	fixture.lab.combat_armies.clear()
	fixture.team.free()
	fixture.lab.free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE_WORK_TEAM_T6_WEIGHTS_PASS checks=", checks, " original NPC/task/credit/Runtime/shared-pool publication; individual effort unweighted, physical factor once; no capture/whole-clock/Native/GPU claim")
	quit(0)
