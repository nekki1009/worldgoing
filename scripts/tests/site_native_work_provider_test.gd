extends SceneTree
## Actual original CrowdSite/CrowdPersonOwner + ArmyCrowd projection/consumption.
## Does not claim the complete Lab caller order, fire, Region replay or GPU.
const CrowdSource = preload("res://scripts/terrain_lab/crowd_site.gd")
var checks := 0
var failures := 0
var finished := false

func _initialize() -> void:
	create_timer(35.0).timeout.connect(func() -> void: _finish("deadline"))
	_run.call_deferred()

func _check(value: bool, label: String, detail: Variant = null) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error("NATIVE_WORK_PROVIDER_FAIL " + label + " " + str(detail))
	return value

func _near(actual: float, expected: float, label: String) -> bool:
	return _check(is_finite(actual) and absf(actual - expected) <= 0.00000001, label, [actual, expected])

func _finish(reason: String = "") -> void:
	if finished: return
	finished = true
	if not reason.is_empty(): failures += 1
	TerrainArmy.release_contact_source()
	print("SITE_NATIVE_WORK_PROVIDER_", "PASS" if failures == 0 else "FAIL", " checks=", checks,
		"; actual original Native projection/readonly CAS/World fatigue publication/training-only/current RUN/real REST station release; no complete Lab/fire/replay claim ", reason)
	quit(0 if failures == 0 else 1)

func _fixture() -> Dictionary:
	var lab := TerrainLab.new()
	var site: Node = CrowdSource.new()
	var world: RefCounted = ClassDB.instantiate(&"ArmyCrowd")
	var data := TerrainData.new()
	data.allocate(Vector2i(32, 32))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	lab.terrain = data
	lab.crowd_site = site
	site.lab = lab
	site.crowd = world
	site.active = true
	if not _check(world.setup(1, 7311) and world.set_terrain(32, 32, data.height_levels, data.flags, data.ramp_edges, data.static_blocked, PackedByteArray()), "Actual original World setup"):
		site.free(); lab.free(); return {}
	var formation := int(world.add_formation(0, 10.5, 10.5, 0.0, 3, 1.0, 0, 50.0))
	var ids := PackedInt64Array([73101, 73102, 73103])
	if not _check(formation == 0 and int(world.add_soldiers(formation, ids, PackedInt32Array([1, 1, 1]), PackedByteArray([1, 0, 0]), PackedInt32Array([0, 0, 0]))) == 0 and world.set_order_owner(formation, false) and world.finalize() and world.set_ai(false), "Actual original three-person formation"):
		site.free(); lab.free(); return {}
	var records: Dictionary = {}
	var owner := CrowdPersonOwner.new()
	for index: int in ids.size():
		var identity: int = int(ids[index])
		var row := {"person_id": identity, "work_resting": false, "cargo": {},
			"item_state": SiteRuntime.new_item_state("person:" + str(identity)),
			"work_task": {"target": "feature:1", "progress": 2.0, "mode": "work", "status": ""}}
		records[index] = row
		site._records[identity] = row
		site._index_by_id[identity] = index
		site._owner_by_id[identity] = owner
	owner.setup(site, formation, 1, 0, records)
	site.owners.append(owner)
	var fields: PackedFloat64Array = world.get_formation_state(formation)
	fields[2] = 40.0
	fields[3] = 12.0
	if not _check(world.set_formation_state(formation, fields, world.formation_refs(formation)) and world.step_clock(1.0 / 30.0, 0.0, 0.0), "Initialize true hot shared pool and original query hash"):
		_close({"lab": lab, "site": site, "owner": owner}); return {}
	return {"lab": lab, "site": site, "world": world, "owner": owner, "records": records, "ids": ids}

func _close(fixture: Dictionary) -> void:
	var site: Node = fixture.site
	var lab: TerrainLab = fixture.lab
	site.clear_work_fatigue_interval()
	site.owners.clear()
	site._owner_by_id.clear()
	fixture.owner.crowd_site = null
	site.lab = null
	lab.crowd_site = null
	site.free()
	lab.free()

func _request(site: Node, identity: int, provider: String, seconds: float) -> Dictionary:
	var participant: Dictionary = site.work_fatigue_participant(identity, true)
	return {"provider": provider, "key": str(identity), "participants": [participant], "remaining": seconds,
		"productive_kind": "single", "progress_multiplier": 1.0, "max_game_seconds": seconds}

func _work_and_training() -> void:
	var fixture := _fixture()
	if fixture.is_empty(): return
	var site: Node = fixture.site
	var world: RefCounted = fixture.world
	var owner: CrowdPersonOwner = fixture.owner
	if not _check(site.begin_work_fatigue_interval().ok, "One actual original interval snapshot"): _close(fixture); return
	var requests: Array = [_request(site, 73101, "work_team", 60.0), _request(site, 73102, "person_actions", 60.0), _request(site, 73103, "training", 60.0)]
	var shared: Dictionary = requests[0].participants[0].body._fatigue_pool
	for request: Dictionary in requests:
		var person: Dictionary = request.participants[0]
		_check(is_same(person.body._fatigue_pool, shared) and is_same(person.original_body, fixture.records[owner.index_for_identity(int(person.person_id))]), "All providers borrow one native pool and retain exact original body")
		_check(not person.original_body.has("_fatigue_pool"), "Read projection never binds a proxy pool to original record")
	var plan := PersonFatigue.plan_work_interval(requests, 60.0)
	if not _check(plan.ok and plan.pools.size() == 1, "Pure solver collects actual whole native pool"): _close(fixture); return
	var expected_work := PersonFatigue.work_seconds(40.0, 60.0, PersonFatigue.WORK_RATE)
	for request: Dictionary in requests:
		_near(float(plan.jobs[request.provider][request.key].effective_seconds), expected_work, "Each provider efficiency sees all three actual efforts")
	var before: PackedByteArray = world.save_state()
	_check(site.prepare_work_fatigue_plan(plan, requests, 1.0 / 30.0, 60.0, 0.0).ok and world.save_state() == before, "Whole native packet preflight is read-only")
	_check(site.validate_prepared_work_fatigue_plan(1.0 / 30.0, 60.0, 0.0).ok and world.save_state() == before, "Repeat readonly consumption guard does not create a pending authority")
	_near(float(world.work_fatigue_state(0)[2]), 40.0, "No host provider charges native fatigue before World")
	_check(world.apply_training_state(0, 50.0, 40.0, 12.0, 50.1, 40.0, 12.0, 0), "Original training commits training only with worked0")
	_check(site.validate_prepared_work_fatigue_plan(1.0 / 30.0, 60.0, 0.0).ok, "Training-only write keeps same original fatigue admission")
	_check(world.step_clock_work_plan(1.0 / 30.0, 60.0, 0.0, site._work_fatigue_tick, site._work_fatigue_packet), "Original combined World step consumes actual native pool once")
	_near(float(world.work_fatigue_state(0)[2]), 40.0 + 60.0 * PersonFatigue.WORK_RATE, "Three true people effort divided by original three-person count exactly once")
	_near(float(world.work_fatigue_state(0)[3]), 0.0, "Actual worked pool resets rest exactly once")
	_near(float(world.get_formation_state(0)[4]), 50.1, "Combined fatigue does not replay training")
	_check(not site.validate_prepared_work_fatigue_plan(1.0 / 30.0, 60.0, 0.0).ok, "Old original tick cannot replay work")
	_close(fixture)

func _current_run_and_stale_count() -> void:
	var fixture := _fixture()
	if fixture.is_empty(): return
	var site: Node = fixture.site
	var world: RefCounted = fixture.world
	# Original host_input uses velocity cells/s; 3 real 0.4-blend samples reach RUN.
	_check(world.set_host_control(0, true) and world.host_input(0, CrowdSource.RUN, 0.0, true, false) and world.step_clock(1.0 / 30.0, 0.0, 0.0) and world.step_clock(1.0 / 30.0, 0.0, 0.0) and world.step_clock(1.0 / 30.0, 0.0, 0.0), "Actual original current RUN generated by previous real movement stage")
	if not _check(site.begin_work_fatigue_interval().ok, "Snapshot true current native RUN"): _close(fixture); return
	var requests: Array = [_request(site, 73102, "person_actions", 1.0)]
	var runners: Dictionary = site.work_fatigue_run_requests(1.0, requests)
	if not _check(runners.ok and runners.requests.size() == 1 and int(runners.requests[0].participants[0].person_id) == 73101, "Collector uses current RUN original person rather than future wish"): _close(fixture); return
	_check(not site.work_fatigue_run_requests(1.0, [_request(site, 73101, "person_actions", 1.0)]).ok, "One original RUN person cannot also work in same interval")
	requests.append_array(runners.requests)
	var plan: Dictionary = PersonFatigue.plan_work_interval(requests, 1.0)
	_check(plan.ok and site.prepare_work_fatigue_plan(plan, requests, 1.0 / 30.0, 1.0, 0.0).ok, "Actual work and current RUN share one native packet")
	var life: PackedFloat64Array = world.get_soldier_state(2)
	life[0] = 0.0
	_check(world.set_soldier_state(2, life, world.soldier_refs(2)), "External true original death changes actual count")
	var after_death: PackedByteArray = world.save_state()
	_check(not site.validate_prepared_work_fatigue_plan(1.0 / 30.0, 1.0, 0.0).ok and world.save_state() == after_death, "Changed original count is rejected by readonly pre-consumption gate")
	_close(fixture)

func _real_rest_release() -> void:
	var fixture := _fixture()
	if fixture.is_empty(): return
	var site: Node = fixture.site
	var world: RefCounted = fixture.world
	var owner: CrowdPersonOwner = fixture.owner
	var pool_state: PackedFloat64Array = world.get_formation_state(0)
	pool_state[2] = 80.0
	pool_state[3] = 12.0
	_check(world.set_formation_state(0, pool_state, world.formation_refs(0)), "Original REST fixture reaches true hot fatigue80")
	var state: PackedFloat64Array = world.get_soldier_state(1)
	var cell := int(floor(state[15])) * 32 + int(floor(state[14]))
	_check(world.order_siege_step(1, cell), "Original native worker occupies actual arrived work station")
	var before_rest: PackedInt64Array = world.siege_person_state(1)
	_check(before_rest.size() == 8 and int(before_rest[1]) == 5, "True original work station starts at native mode5", before_rest)
	var task: Dictionary = fixture.records[1].work_task
	var target := str(task.target)
	var progress := float(task.progress)
	_check(owner.work_fatigue_rest(73102).ok, "REST releases actual original native siege station")
	var actual: PackedInt64Array = world.siege_person_state(1)
	_check(actual.size() == 8 and int(actual[1]) == 0, "Original native work mode is idle rather than stuck at mode5", actual)
	_check(is_same(task, fixture.records[1].work_task) and str(task.target) == target and float(task.progress) == progress and bool(fixture.records[1].work_resting), "REST retains exact original task/progress and original hysteresis flag")
	_near(float(world.work_fatigue_state(0)[2]), 80.0, "REST adapter does not write fatigue to native or cold projection")
	_near(float(world.work_fatigue_rest_limit(0, 50.0, 10000.0, 0.0)), 18.0, "Real released workstation exposes original remaining rest delay")
	_check(world.step_clock(1.0 / 30.0, 18.0, 0.0), "Actual original rest delay consumed once")
	var until50 := float(world.work_fatigue_rest_limit(0, 50.0, 10000.0, 0.0))
	_near(until50, 5400.0, "Real idle native pool exposes exact 80 to50 endpoint")
	_check(world.step_clock(1.0 / 30.0, until50, 0.0), "Actual original recovery consumes exact endpoint")
	_near(float(world.work_fatigue_state(0)[2]), 50.0, "Actual Native World reaches exactly50")
	_check(not PersonFatigue.needs_work_rest(float(world.work_fatigue_state(0)[2]), bool(fixture.records[1].work_resting)), "Fresh original caller can resume80/50 hysteresis")
	_close(fixture)

func _fresh_input_excludes_work() -> void:
	var fixture := _fixture()
	if fixture.is_empty(): return
	var site: Node = fixture.site
	var world: RefCounted = fixture.world
	site.player_index = 0
	# Original host_input uses velocity cells/s; 3 real 0.4-blend samples reach RUN.
	_check(world.set_host_control(0, true), "Original controlled Native person selected")
	if not _check(site.begin_work_fatigue_interval().ok, "Capture actual stopped Native start before fresh input"): _close(fixture); return
	var before: PackedByteArray = world.save_state()
	site.wish = Vector2(4.0, 0.0)
	site.running = true
	_check(not site.work_fatigue_work_start_ready(73101) and site.work_fatigue_participant(73101, false).is_empty(), "Fresh WASD blocks original controlled work/lesson despite old hot idle")
	_check(world.work_fatigue_runners(0).is_empty() and world.save_state() == before, "Fresh-wish readiness query does not invent current RUN or mutate World")
	var current: Dictionary = site.work_fatigue_run_requests(1.0, [])
	_check(current.ok and current.requests.is_empty(), "No RUN charge is guessed from future wish")
	_check(not site.work_fatigue_participant(73102, true).is_empty(), "Different original stationary worker still allowed")
	site.wish = Vector2.ZERO
	site.engage = true
	_check(not site.work_fatigue_work_start_ready(73101), "Fresh native engage also blocks simultaneous original work")
	site.engage = false
	_check(site.work_fatigue_work_start_ready(73101) and not site.work_fatigue_participant(73101, false).is_empty(), "Cleared original input allows a fresh true physical context check")
	_close(fixture)

func _run() -> void:
	if not ClassDB.class_exists(&"ArmyCrowd"):
		_check(false, "Native build required"); _finish(); return
	for method: String in ["work_fatigue_state", "work_fatigue_runners", "work_fatigue_rest_limit", "validate_step_clock_work_plan", "step_clock_work_plan"]:
		if not _check(ClassDB.class_has_method(&"ArmyCrowd", StringName(method)), "Native original API present: " + method): _finish(); return
	_work_and_training()
	_current_run_and_stale_count()
	_real_rest_release()
	_fresh_input_excludes_work()
	_finish()
