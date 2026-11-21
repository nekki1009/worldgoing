extends "res://scripts/tests/site_technology_nation_material_test.gd"
## Actual original TerrainLab Controller registry, manual dictionary and Actors.
## Direct same-point pool/Runtime publication is not Native contacts or full Lab
## frame proof. A death setter is a fixture contact; no fabricated alive person.
const PersonalFatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")

func _manual_fixture() -> Dictionary:
	var data := _building_fixture()
	var resource_cell := Vector2i(35, 35)
	Env._add_resource(data, Env.Kind.FOOD, data.index(resource_cell), 24, 0)
	var source := "%d:%d" % [Env.Kind.FOOD, data.index(resource_cell)]
	Env.change(data, source, {"cleared": false, "remaining": 24, "discovered": true})
	Env.rebuild_indexes(data)
	var lab := _building_lab(data)
	var team := _army(lab, data)
	var stations := Env.work_cells(data, source)
	_check(not stations.is_empty() and lab.character.place(stations[0], true), "The actual Actor reaches a real original resource work cell")
	_check(Runtime.begin_manual(data, source, stations[0]).ok, "Original begin_manual establishes the actual saved manual shape")
	return {"data": data, "lab": lab, "team": team, "source": source}

func _manual_point(fixture: Dictionary, damage_after_capture: bool = false) -> Dictionary:
	var lab: TerrainLab = fixture.lab
	var data: TerrainData = fixture.data
	var controller: SiteController = lab.site_controller
	var actions := controller.person_actions
	var manual: Dictionary = data.site.manual
	controller._shared_worker_inputs = controller._prepare_original_work_inputs()
	var requests := controller.prepare_shared_owner_work_requests(30.0)
	_check(requests.size() == 1 and requests[0].provider == "runtime" and requests[0].key == "manual", "The original owner produces only this actual manual demand")
	requests[0] = controller.refresh_shared_runtime_work_request(requests[0])
	lab._shared_work_requests = requests
	var captured := controller.prepare_shared_runtime_work_prefix(requests, 30.0)
	var planned := PersonalFatigue.plan_work_interval(requests, 30.0)
	_check(captured.ok and planned.ok, "True original Controller start and Fatigue planner admit this finite point")
	var original_hp := float(actions._person(lab.controlled_person_id()).hp)
	if damage_after_capture: actions._body_set(actions._person(lab.controlled_person_id()), "hp", 0.0)
	var before := var_to_bytes(data.site)
	var priors: Array = []
	var admitted := controller.validate_shared_runtime_work_prefix(captured, planned, priors)
	_check(admitted.ok and priors.size() == 1 and var_to_bytes(data.site) == before, "True registry candidates change no gameplay state before the first cost")
	var candidate: Dictionary = priors[0]
	var copied_prefix: Dictionary = candidate.prefix_ref.duplicate(false)
	_check(not Runtime.prepare_checked_work_prefix(data, manual, float(copied_prefix.applied_productive_seconds), float(copied_prefix.actual_seconds), copied_prefix).ok, "A copied prefix cannot impersonate the true Controller registry entry")
	lab._shared_work_plan = planned
	controller._shared_work_plan = planned
	lab._shared_work_pools_committed = false
	var clock := controller.checked_runtime_clock_interval()
	var minute := int(data.site.minute)
	var phase := float(data.site.phase)
	var held_progress := float(manual.progress)
	var held_items = manual.cargo.duplicate(true)
	Runtime.advance(data, 0.5, false, true, controller.reserves_cell, Callable(), Callable(), Runtime.CARRY_CAPACITY, Runtime.CARRY_CAPACITY, 1.0, 1, 30.0, true, clock)
	_check(bool(clock.advanced) and float(manual.progress) == held_progress and manual.cargo == held_items, "Original checked clock advances time once without legacy manual progress or products")
	_check(is_equal_approx(Runtime.now(data), float(minute) + phase + 0.5), "Only the original Site minute/phase accounts for this half-minute")
	var after_clock := var_to_bytes(data.site)
	Runtime.advance(data, 0.5, false, true, controller.reserves_cell, Callable(), Callable(), Runtime.CARRY_CAPACITY, Runtime.CARRY_CAPACITY, 1.0, 1, 30.0, true, clock)
	_check(var_to_bytes(data.site) == after_clock, "The same true clock interval cannot advance elapsed time twice")
	lab._commit_shared_work_pools()
	var published := controller.publish_shared_runtime_work_prefix(admitted)
	_check(float(published.handled_seconds.get(lab.controlled_person_id(), 0.0)) > 0.0 and not manual.has("status") and not manual.has("mode") and not manual.has("work_cell"), "Original paid effort publishes once without inventing fields in the manual owner")
	var progress_after_publish := float(manual.progress)
	controller.publish_shared_runtime_work_prefix(admitted)
	_check(float(manual.progress) == progress_after_publish, "Repeated original provider publication does not duplicate work")
	controller.finish_shared_runtime_work_prefix(admitted)
	if damage_after_capture:
		_check(not str(manual.target).is_empty() and is_equal_approx(float(manual.progress), 2.0) and manual.cargo == held_items, "Current dead endpoint retains real completed work and creates no harvested item")
	controller.finish_shared_runtime_clock()
	_check(controller.checked_runtime_clock_interval().is_empty(), "The original discrete ship/minute endpoints release the one held clock after current work settlement")
	if damage_after_capture: actions._body_set(actions._person(lab.controlled_person_id()), "hp", original_hp)
	return {"candidate": candidate, "admitted": admitted}

func _manual_complete() -> void:
	var fixture := _manual_fixture()
	var data: TerrainData = fixture.data
	var manual: Dictionary = data.site.manual
	var keys := manual.keys()
	var before := var_to_bytes(data.site)
	_check(Runtime.work_preflight(data, manual, manual.cargo, Runtime.CARRY_CAPACITY, 1, fixture.lab.controlled_person_id()).ok, "SAME original manual is admitted without mode or work_cell")
	_check(not Runtime.work_preflight(data, manual.duplicate(true), manual.cargo, Runtime.CARRY_CAPACITY, 1, fixture.lab.controlled_person_id()).ok and var_to_bytes(data.site) == before, "A copied manual dictionary gets no shape exception and changes no source")
	var remaining := int(Env.resource(data, fixture.source).remaining)
	for step: int in range(4): _manual_point(fixture)
	_check(str(manual.target).is_empty() and float(manual.progress) == 0.0 and int(manual.cargo.get("wild_food", 0)) == 3 and int(Env.resource(data, fixture.source).remaining) == remaining - 3, "Four real accepted prefixes complete exactly one original two-minute harvest")
	_check(manual.keys() == keys and int(data.site.minute) == 2 and float(data.site.phase) == 0.0, "Manual keeps its exact original keys and the Site clock records exactly two minutes")
	_cleanup_fixture(fixture.lab, fixture.team)
	await process_frame

func _manual_dead_endpoint() -> void:
	var fixture := _manual_fixture()
	for step: int in range(3): _manual_point(fixture)
	_manual_point(fixture, true)
	_check(not fixture.data.site.manual.cargo.has("wild_food"), "A simulated contact death never turns the earlier accepted effort into false endpoint permission")
	_cleanup_fixture(fixture.lab, fixture.team)
	await process_frame

func _run() -> void:
	deadline = Time.get_ticks_msec() + 90000
	await _manual_complete()
	await _manual_dead_endpoint()
	TerrainArmy.release_contact_source()
	print("SITE_TECHNOLOGY_CONTROLLER_PREFIX_PASS: %d checks; true Controller/manual/Fatigue registry, readonly rejection, original keys/clock/output once, current dead endpoint; Native/full Lab frame/full40 excluded" % checks)
	quit(0)
