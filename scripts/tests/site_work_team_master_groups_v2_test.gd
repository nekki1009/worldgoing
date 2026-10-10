extends "res://scripts/tests/site_work_team_master_groups_test.gd"
## Version 2: ordinary paid construction has no scope/research ledger.
## Preserve frozen DC3F fixture and all its remaining guards.

func _distinct_masters_and_boundary() -> void:
	var fixture := _masters_fixture()
	var requests := _master_requests(fixture, 10.0)
	_check(requests.size() == 1 and requests[0].participants.size() == 6, "The original selector and fixed real slots collect one six-person shared job")
	var groups: Array = requests[0].required_all_any_ids
	_check(groups.size() == 2 and groups.has([fixture.team.combat_identity(1)]) and groups.has([fixture.team.combat_identity(2)]), "Different true original F11 and F12 bodies satisfy independent required OR groups")
	var point := _master_point(fixture, requests, 10.0)
	var base := 0.0
	for prefix: Dictionary in point.admitted.prefixes: base += float(prefix.productive_seconds)
	_check(float(fixture.vehicle.build.progress) == 60.0 and is_equal_approx(base, 60.0) and not fixture.vehicle.has("tech_batch") and point.admitted.runtime.size() == 6, "Each genuine participant adds its own unweighted physical contribution once; ordinary construction invents no research ledger and no helper duplicates the crew")
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

func _run() -> void:
	await _distinct_masters_and_boundary()
	await _alternate_and_missing_requirement()
	TerrainArmy.release_contact_source()
	print("SITE_WORK_TEAM_MASTER_GROUPS_V2_PASS checks=", checks, " true ordinary six-slot F11/F12 and unweighted allocations; frozen v1 invalid ledger assertion preserved")
	quit(0)
