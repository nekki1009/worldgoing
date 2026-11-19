extends "res://scripts/tests/site_work_team_master_groups_test.gd"
## Original six-slot paid counterweight, five WT people + joined controlled
## Actor PA, real F11/F12 on different owners. No mocked owner/skill/prefix.

func _cross_fixture() -> Dictionary:
	var fixture: Dictionary = _masters_fixture()
	var lab: TerrainLab = fixture.lab
	var workers: SiteWorkTeam = lab.site_controller.work_team
	var actions: SitePersonActions = lab.site_controller.person_actions
	var station: Vector2i = fixture.team.cells[2]
	workers.cancel(fixture.team.combat_identity(2))
	fixture.team.combat_units[2].technology = {}
	fixture.team.cells[2] = Vector2i(8, 50)
	lab.character.technology = Technology.learned_candidate({}, "F12")
	fixture.team.team_fatigue.fatigue = 0.0
	fixture.team.team_fatigue.fatigue_rest = 0.0
	_check(lab.character.place(station, true), "The SAME controlled Actor reaches the now-free original F12 station")
	var prepared := actions.prepare_controlled_vehicle_work({}, fixture.vehicle, {}, int(fixture.control))
	_check(prepared.ok, "True current original team.work decider prepares its actual controlled job on the same already-paid vehicle: " + str(prepared))
	actions.publish_controlled_vehicle_work(prepared)
	_check(actions._jobs[str(fixture.control)].kind == "technology_vehicle" and not workers.is_assigned(int(fixture.control)), "Controlled PA holds its genuine job while the original WT owns only the other five original rows")
	return fixture

func _cross_capture(fixture: Dictionary, seconds: float) -> Dictionary:
	var lab: TerrainLab = fixture.lab
	var actions: SitePersonActions = lab.site_controller.person_actions
	var workers: SiteWorkTeam = lab.site_controller.work_team
	var pa_requests := actions.work_requests(seconds)
	var wt_requests := workers.prepare_work_requests(seconds, 0.0, pa_requests)
	var requests: Array = wt_requests.duplicate(false)
	requests.append_array(pa_requests)
	lab._shared_work_requests.assign(requests)
	_check(lab._refresh_shared_work_preflight().ok, "Original final finite material/water refresh retains both actual providers")
	requests = lab._shared_work_requests
	_check(lab._capture_shared_vehicle_groups(requests).ok, "Original Lab groups only true same target/build refs after the last preflight")
	var plan := lab._plan_shared_vehicle_work_interval(requests, seconds)
	var wt_capture := workers.prepare_shared_work_prefix(seconds)
	var pa_capture := actions.prepare_shared_work_prefix(requests, seconds)
	_check(plan.ok and wt_capture.ok and pa_capture.ok, "True union plan and both original start registries are captured without a second owner")
	return {"requests": requests, "plan": plan, "wt": wt_capture, "pa": pa_capture}

func _cross_admit(fixture: Dictionary, captured: Dictionary) -> Dictionary:
	var lab: TerrainLab = fixture.lab
	var workers: SiteWorkTeam = lab.site_controller.work_team
	var actions: SitePersonActions = lab.site_controller.person_actions
	var priors: Array = []
	var pa := actions.validate_shared_work_prefix(captured.pa, captured.plan, captured.requests)
	var wt_registered := workers.prepare_shared_work_prefix_allocations(captured.wt, captured.plan, priors)
	var pa_registered := actions.prepare_checked_controlled_prefix_allocations(pa, priors)
	_check(pa.ok and wt_registered.ok and pa_registered.ok and priors.is_empty(), "BOTH true original owner allocations are registered before the first pure Runtime cost/geometry candidate")
	var wt := workers.validate_shared_work_runtime_prefixes(wt_registered)
	var controlled := actions.validate_checked_controlled_runtime_prefixes(pa_registered)
	# Only the codes on failure: the admitted prefixes hold live owner references (cyclic), and str() of them recursed for
	# minutes on every run (Maximum dictionary recursion) until the test timed out (found 2026-11-19).
	var admitted_ok: bool = wt.ok and controlled.ok
	_check(admitted_ok, "Actual cross-provider F11/F12 witnesses admit the same positive prefix without learned/permission borrowing" + ("" if admitted_ok else ": %s %s %s %s" % [str(wt.get("code", "")), str(wt.get("message", "")), str(controlled.get("code", "")), str(controlled.get("message", ""))]))
	return {"wt": wt, "pa": pa, "controlled": controlled, "priors": priors}

func _cross_publish(fixture: Dictionary, captured: Dictionary, admitted: Dictionary) -> void:
	var lab: TerrainLab = fixture.lab
	var workers: SiteWorkTeam = lab.site_controller.work_team
	var actions: SitePersonActions = lab.site_controller.person_actions
	lab._shared_work_plan = captured.plan
	lab.site_controller._shared_work_plan = captured.plan
	lab._shared_work_pools_committed = false
	lab._commit_shared_work_pools()
	workers.publish_shared_work_prefix(admitted.wt)
	actions.begin_shared_work_prefix_consumption(admitted.pa)
	actions.publish_checked_controlled_prefixes(admitted.controlled)
	actions.end_shared_work_prefix_consumption()

func _close_cross(fixture: Dictionary, admitted: Dictionary = {}) -> void:
	var lab: TerrainLab = fixture.lab
	var actions: SitePersonActions = lab.site_controller.person_actions
	if not admitted.is_empty():
		lab.site_controller.work_team.finish_shared_work_prefix(admitted.wt)
		actions.finish_checked_controlled_prefixes(admitted.controlled)
		actions.finish_shared_work_prefix(admitted.pa)
	actions.discard_checked_controlled_prefixes()
	lab._shared_vehicle_groups.clear()
	_cleanup_fixture(lab, fixture.team)

func _cross_actual_masters() -> void:
	var fixture := _cross_fixture()
	var captured := _cross_capture(fixture, 10.0)
	_check(captured.requests.size() == 2 and fixture.lab._shared_vehicle_groups.size() == 1 and fixture.lab._shared_vehicle_groups[0].person_ids.size() == 6, "Five original WT bodies and one actual controlled PA body form exactly one true six-person sum")
	var before := var_to_bytes([fixture.vehicle, fixture.data.site.inventory, fixture.team.team_fatigue, fixture.lab.character.technology])
	var admitted := _cross_admit(fixture, captured)
	_check(var_to_bytes([fixture.vehicle, fixture.data.site.inventory, fixture.team.team_fatigue, fixture.lab.character.technology]) == before and admitted.priors.size() == 6, "All six true original Runtime candidates are pure and append once in original WT then PA source order")
	var helper: Dictionary = admitted.wt.prefixes[0]
	var actor_prefix: Dictionary = fixture.lab.site_controller.work_team.checked_work_prefix_for_task(helper.task, int(fixture.control))
	_check(actor_prefix.owner == fixture.lab.site_controller.person_actions and is_same(actor_prefix.target_ref, helper.target_ref) and actor_prefix.plan_key == helper.plan_key and actor_prefix.eligible_skills == ["F12"], "WT receives the genuine original PA registry witness, with only that Actor's actual F12 capability")
	_check(not actor_prefix.owner.valid_checked_work_prefix(actor_prefix.task, int(fixture.control), actor_prefix.duplicate(false)), "Copied cross-provider allocation cannot impersonate a true registry witness")
	_cross_publish(fixture, captured, admitted)
	var own_base := 0.0
	for prefix: Dictionary in admitted.wt.prefixes: own_base += float(prefix.productive_seconds)
	for prefix: Dictionary in admitted.controlled.checked.prefixes: own_base += float(prefix.productive_seconds)
	_check(is_equal_approx(float(fixture.vehicle.build.progress), 60.0) and is_equal_approx(own_base, 60.0) and not fixture.vehicle.has("tech_batch"), "One true six-person physical sum and six unweighted personal contributions publish once; ordinary construction does not invent a research ledger")
	var published := var_to_bytes([fixture.vehicle, fixture.team.team_fatigue])
	fixture.lab.site_controller.work_team.publish_shared_work_prefix(admitted.wt)
	fixture.lab.site_controller.person_actions.begin_shared_work_prefix_consumption(admitted.pa)
	fixture.lab.site_controller.person_actions.publish_checked_controlled_prefixes(admitted.controlled)
	fixture.lab.site_controller.person_actions.end_shared_work_prefix_consumption()
	_check(var_to_bytes([fixture.vehicle, fixture.team.team_fatigue]) == published, "Same true WT/PA candidates replay without shared progress, ledger or effort duplication")
	_close_cross(fixture, admitted)
	await process_frame

func _cross_endpoint_and_death() -> void:
	var fixture := _cross_fixture()
	fixture.vehicle.build.progress = float(fixture.vehicle.build.total_work) - 9.0 # Explicit genuine saved starting work; materials already paid.
	var captured := _cross_capture(fixture, 10.0)
	var wt_key: String = captured.requests[0].key
	var pa_key: String = str(fixture.control)
	_check(is_equal_approx(float(captured.plan.jobs.work_team[wt_key].actual_seconds), 1.5) and is_equal_approx(float(captured.plan.jobs.person_actions[pa_key].actual_seconds), 1.5), "Both original providers stop at the SAME weighted sum completion, rather than independently overshooting the true remaining nine seconds")
	var actions: SitePersonActions = fixture.lab.site_controller.person_actions
	actions._body_set(actions._person(int(fixture.control)), "hp", 0.0)
	var admitted := _cross_admit(fixture, captured)
	_cross_publish(fixture, captured, admitted)
	_check(is_equal_approx(float(fixture.vehicle.build.progress), float(fixture.vehicle.build.total_work)) and fixture.vehicle.phase == "building", "Real endpoint death preserves the complete already-spent prefix while no publisher invents a ready product or learning receipt")
	_close_cross(fixture, admitted)
	await process_frame

func _cross_missing_and_rest() -> void:
	var fixture := _cross_fixture()
	fixture.team.team_fatigue.fatigue = 79.99
	var captured := _cross_capture(fixture, 30.0)
	var group: Dictionary = fixture.lab._shared_vehicle_groups[0]
	var rate := 0.0
	for source: Dictionary in group.sources:
		for participant: Dictionary in source.request.participants: rate += float(participant.effort_rate)
	var edge: float = (80.0 - 79.99) / rate
	var allocation: Dictionary = captured.plan.jobs.person_actions[str(fixture.control)]
	_check(absf(float(allocation.actual_seconds) - edge) < 0.000001 and allocation.paused == "REST", "The controlled unrestricted F12 and helpers stop with the last genuine WT F11 at its true common pool REST boundary")
	var admitted := _cross_admit(fixture, captured)
	_cross_publish(fixture, captured, admitted)
	_check(absf(float(fixture.team.team_fatigue.fatigue) - 80.0) < 0.000001 and float(fixture.vehicle.build.progress) > 0.0, "All original owners preserve the legal prefix ending at 80 and publish the original pool once")
	_close_cross(fixture, admitted)
	await process_frame
	fixture = _cross_fixture()
	fixture.team.combat_units[1].technology = {}
	var before := var_to_bytes([fixture.vehicle, fixture.data.site.inventory, fixture.team.team_fatigue])
	captured = _cross_capture(fixture, 5.0)
	allocation = captured.plan.jobs.person_actions[str(fixture.control)]
	_check(float(allocation.actual_seconds) == 0.0 and allocation.paused == "MASTER" and var_to_bytes([fixture.vehicle, fixture.data.site.inventory, fixture.team.team_fatigue]) == before, "Actual PA F12 never borrows absent WT F11: no request effort, material or physical progress is granted")
	_close_cross(fixture)
	await process_frame

func _cross_partition() -> void:
	var whole := _cross_fixture()
	var split := _cross_fixture()
	var first := _cross_capture(whole, 10.0)
	var admitted := _cross_admit(whole, first)
	_cross_publish(whole, first, admitted)
	for iteration: int in range(2):
		var part := _cross_capture(split, 5.0)
		var part_admitted := _cross_admit(split, part)
		_cross_publish(split, part, part_admitted)
		split.lab.site_controller.work_team.finish_shared_work_prefix(part_admitted.wt)
		split.lab.site_controller.person_actions.finish_checked_controlled_prefixes(part_admitted.controlled)
		split.lab.site_controller.person_actions.finish_shared_work_prefix(part_admitted.pa)
		split.lab._shared_vehicle_groups.clear()
	_check(is_equal_approx(float(whole.vehicle.build.progress), float(split.vehicle.build.progress)) and absf(float(whole.team.team_fatigue.fatigue) - float(split.team.team_fatigue.fatigue)) < 0.000001, "Actual original PA/WT sum contributions and shared pool agree for one 10-second interval versus two five-second intervals")
	_close_cross(whole, admitted)
	_close_cross(split)
	await process_frame

func _run() -> void:
	await _cross_actual_masters()
	await _cross_endpoint_and_death()
	await _cross_missing_and_rest()
	await _cross_partition()
	TerrainArmy.release_contact_source()
	print("SITE_SHARED_VEHICLE_MASTER_GROUPS_PASS checks=", checks, " actual PA+WT F11/F12 distinct owners, SAME six-station target, true sum endpoint/REST/death prefix/replay; Native/Region wholeframe excluded")
	quit(0)
