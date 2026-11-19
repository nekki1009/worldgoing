extends SceneTree
## Pure original PersonFatigue math contract. No World/body-owner writes.
var checks := 0

func _initialize() -> void:
	create_timer(10.0).timeout.connect(func() -> void: quit(1))
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	assert(value, message)

func _person(identity: int, value: float, rate: float = 0.0, limited: bool = true, shared: Dictionary = {}) -> Dictionary:
	var body := {"fatigue": value, "fatigue_rest": 0.0, "work_resting": false}
	if not shared.is_empty(): PersonFatigue.bind(body, shared)
	return {"person_id": identity, "body": body, "effort_rate": rate, "rest_limited": limited, "progress_multiplier": 1.0}

func _job(people: Array, groups: Array, key: String = "engine") -> Dictionary:
	return {"provider": "work_team", "key": key, "participants": people, "remaining": 100.0,
		"productive_kind": "sum", "progress_multiplier": 1.0, "max_game_seconds": 10.0, "required_all_any_ids": groups}

func _run() -> void:
	var people: Array = [_person(1, 80.0), _person(2, 0.0), _person(3, 0.0)]
	var request := _job(people, [[1, 3], [2]])
	var plan := PersonFatigue.plan_work_interval([request], 5.0)
	_check(plan.ok, "Two actual skill groups are admitted on the original sum request")
	var interval: Dictionary = plan.jobs.work_team.engine
	_check(float(interval.actual_seconds) == 5.0 and float(interval.effective_seconds) == 10.0 and interval.paused == "", "Rested F11 master is replaced by another actual working F11; separate F12 remains active")
	_check(float(interval.participant_seconds[1]) == 0.0 and interval.participant_paused[1] == "REST" and float(interval.participant_seconds[3]) == 5.0, "Only the rested participant stops while the complete AND gate is satisfied")
	request.required_all_any_ids = [[1], [2]]
	plan = PersonFatigue.plan_work_interval([request], 5.0)
	_check(plan.ok and plan.jobs.work_team.engine.paused == "REST" and float(plan.jobs.work_team.engine.actual_seconds) == 0.0, "A helper and an F12 cannot replace the missing last F11")
	request.required_all_any_ids = [[3], [3]]
	plan = PersonFatigue.plan_work_interval([request], 5.0)
	_check(plan.ok and float(plan.jobs.work_team.engine.actual_seconds) == 5.0, "One actual participant may cover two requirements without duplicate activity/effort")
	request.required_any_ids = [1]
	plan = PersonFatigue.plan_work_interval([request], 5.0)
	_check(plan.ok and float(plan.jobs.work_team.engine.actual_seconds) == 0.0, "Existing required_any_ids remains an independent required group")
	request.erase("required_any_ids")
	for invalid: Variant in [null, {}, [[]], [[1, 1]], [[99]], [[1.0]], ["F11"]]:
		var malformed := request.duplicate(true)
		malformed.required_all_any_ids = invalid
		_check(not PersonFatigue.plan_work_interval([malformed], 5.0).ok, "Malformed/nonparticipant group fails before actual work")
	var pool := {"fatigue": 79.99, "fatigue_rest": 0.0, "count": 2, "active": false}
	var master := _person(11, 79.99, 0.01, true, pool)
	var runner := _person(14, 79.99, 0.01, false, pool)
	var construction := _job([master, _person(12, 0.0, 0.01), _person(13, 0.0, 0.01)], [[11], [12]])
	var run := {"provider": "native_run", "key": "14", "participants": [runner], "remaining": 100.0,
		"productive_kind": "raw", "progress_multiplier": 1.0, "max_game_seconds": 5.0}
	plan = PersonFatigue.plan_work_interval([construction, run], 5.0)
	_check(plan.ok, "Original shared pool accepts actual work and distinct RUN activity once")
	interval = plan.jobs.work_team.engine
	_check(absf(float(interval.actual_seconds) - 0.5) < 0.000001 and interval.paused == "REST", "Total original pool effort clips the legal prefix at the exact last-master 80 event")
	_check(absf(float(plan.jobs.native_run["14"].actual_seconds) - 5.0) < 0.000001 and absf(float(plan.pools[0].fatigue) - 80.045) < 0.000001, "Unrelated unrestricted RUN continues with its own remaining slope after the supervised job pauses")
	_check(float(interval.participant_seconds[11]) > 0.0 and float(interval.participant_seconds[12]) > 0.0 and float(interval.participant_seconds[13]) > 0.0, "The actual legal prefix is preserved for every member; endpoint REST cannot swallow it")
	var weighted_people: Array = [_person(21, 0.0), _person(22, 0.0)]
	weighted_people[0].progress_multiplier = 2.0 # Original physical T6 factor, not the global research multiplier.
	weighted_people[1].progress_multiplier = 2.0
	var weighted := _job(weighted_people, [[21], [22]])
	weighted.remaining = 40.0
	plan = PersonFatigue.plan_work_interval([weighted], 20.0)
	_check(plan.ok and float(plan.jobs.work_team.engine.actual_seconds) == 10.0 and float(plan.jobs.work_team.engine.effective_seconds) == 40.0, "True factor2 belongs to individual physical weights and clips the original production endpoint")
	_check(float(plan.jobs.work_team.engine.participant_effective_seconds[21]) == 10.0 and float(plan.jobs.work_team.engine.participant_effective_seconds[22]) == 10.0, "Each original person's productive ledger remains unweighted; physical factor is not charged twice")
	_check(pool.fatigue == 79.99 and PersonFatigue.read(master.body) == 79.99, "Pure planner never publishes original pool state itself")
	print("SITE_FATIGUE_MASTER_GROUPS_PASS checks=", checks, " original AND/OR master groups, REST alternate/last master, same-pool RUN prefix, weighted T6 endpoint and unweighted ledger; pure math only")
	quit(0)
