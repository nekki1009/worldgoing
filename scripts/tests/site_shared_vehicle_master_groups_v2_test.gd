extends "res://scripts/tests/site_shared_vehicle_master_groups_test.gd"
## Both actual owner directions: controlled PA F11 + WT F12 is a true helper,
## not a fake F12 operator. Original first paid D10 admission is unchanged.

func _reverse_actual_masters() -> void:
	var fixture: Dictionary = _cross_fixture()
	var lab: TerrainLab = fixture.lab
	var actions: SitePersonActions = lab.site_controller.person_actions
	_check(actions.cancel(int(fixture.control)).ok, "Actual controlled owner stops its original old job while retaining the already-paid vehicle")
	lab.character.technology = Technology.learned_candidate({}, "F11")
	fixture.team.combat_units[1].technology = Technology.learned_candidate({}, "F12")
	var prepared := actions.prepare_controlled_vehicle_work({}, fixture.vehicle, {}, int(fixture.control))
	_check(prepared.ok, "Actual original team.work owner admits this true F11 helper on the existing paid target, without changing first-paid F12 admission")
	actions.publish_controlled_vehicle_work(prepared)
	var pa_requests := actions.work_requests(10.0)
	_check(pa_requests.size() == 1 and pa_requests[0].paused == "SHARED_MASTER", "True PA F11 request records its derived wait for another actual provider's F12")
	_check(actions.shared_vehicle_work_request_facts(pa_requests[0].duplicate(false)).is_empty(), "A shallow cloned PA demand cannot impersonate the original held request")
	var alone := PersonFatigue.plan_work_interval(pa_requests, 10.0)
	_check(alone.ok and float(alone.jobs.person_actions[str(fixture.control)].actual_seconds) == 0.0 and float(alone.jobs.person_actions[str(fixture.control)].effective_seconds) == 0.0, "The exact standalone request remains valid and grants zero effort or production before a true same-vehicle union")
	var captured := _cross_capture(fixture, 10.0)
	_check(lab.site_controller.work_team.shared_vehicle_work_request_facts(captured.requests[0].duplicate(false)).is_empty(), "A shallow cloned WT demand cannot impersonate any original prepared entry request")
	var admitted := _cross_admit(fixture, captured)
	var pa_prefix: Dictionary = admitted.controlled.checked.prefixes[0]
	var true_f12: Dictionary = actions.checked_work_prefix_for_task(pa_prefix.task, fixture.team.combat_identity(1))
	_check(pa_prefix.eligible_skills == ["F11"] and true_f12.owner == lab.site_controller.work_team and true_f12.eligible_skills == ["F12"] and is_same(true_f12.target_ref, pa_prefix.target_ref), "Actual registry reads the separate original WT F12, while the controlled original person remains only F11")
	_cross_publish(fixture, captured, admitted)
	_check(float(fixture.vehicle.build.progress) == 60.0, "The reverse true owner direction publishes one genuine six-person shared physical sum")
	_close_cross(fixture, admitted)
	await process_frame

func _run() -> void:
	deadline = Time.get_ticks_msec() + 420000 # builds the six-station cross fixture seven times (~40 s each)
	await _cross_actual_masters()
	await _reverse_actual_masters()
	await _cross_endpoint_and_death()
	await _cross_missing_and_rest()
	await _cross_partition()
	TerrainArmy.release_contact_source()
	print("SITE_SHARED_VEHICLE_MASTER_GROUPS_V2_PASS checks=", checks, " both genuine PA/WT F11/F12 directions, solo helper zero effort, same target six stations and original physical prefix; no Native/Region wholeframe claim")
	quit(0)
