extends SceneTree
const F = preload("res://scripts/terrain_lab/person_fatigue.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _body(shared: Dictionary) -> Dictionary:
	return {"fatigue": 0.0, "fatigue_rest": 0.0, "work_resting": false, "_fatigue_pool": shared}
func _person(identity: int, body: Dictionary, until: float = 4.0) -> Dictionary:
	return {"person_id": identity, "body": body, "effort_rate": 1.0, "rest_limited": true, "active_until_game_seconds": until}
func _job(people: Array, groups: Array = []) -> Dictionary:
	return {"provider": "original_math", "key": "work", "participants": people, "remaining": 100.0,
		"productive_kind": "sum", "progress_multiplier": 1.0, "max_game_seconds": 4.0, "required_all_any_ids": groups}
func _run() -> void:
	var pool := {"fatigue": 0.0, "fatigue_rest": 0.0, "count": 3}
	var a: Dictionary = _body(pool)
	var b: Dictionary = _body(pool)
	var c: Dictionary = _body(pool)
	var before: PackedByteArray = var_to_bytes([a,b,c,pool])
	var planned: Dictionary = F.plan_work_interval([_job([_person(1,a,2.0),_person(2,b),_person(3,c)], [[1,2]])],4.0)
	_check(planned.ok and var_to_bytes([a,b,c,pool]) == before,"Pure contact boundary never writes original bodies/pool")
	if planned.ok:
		var job: Dictionary = planned.jobs.original_math.work
		_check(job.actual_seconds == 4.0 and job.effective_seconds == 10.0,"One of two true masters stops; other master and helper continue")
		_check(job.participant_seconds[1] == 2.0 and job.participant_seconds[2] == 4.0 and job.participant_seconds[3] == 4.0,"Actual person seconds are independent")
		_check(job.participant_paused[1] == "CONTACT" and job.paused == "","A contact is never forged as REST")
		_check(planned.pools[0].fatigue == 10.0 and planned.pools[0].effort_seconds == 10.0,"Same pool effort counts every actual worker once")
	var last: Dictionary = F.plan_work_interval([_job([_person(1,a,2.0),_person(2,b),_person(3,c)], [[1]])],4.0)
	_check(last.ok and last.jobs.original_math.work.effective_seconds == 6.0 and last.jobs.original_math.work.actual_seconds == 2.0,"Final required master loss stops ALL group work at actual boundary")
	_check(last.ok and last.jobs.original_math.work.paused == "CONTACT","Final-master contact reason retained")
	var conjunction: Dictionary = F.plan_work_interval([_job([_person(1,a,2.0),_person(2,b),_person(3,c,3.0)], [[1,2],[3]])],4.0)
	_check(conjunction.ok and conjunction.jobs.original_math.work.effective_seconds == 8.0,"F11 AND F12: one requirement losing its last participant stops whole batch")
	var invalid: Dictionary = _person(1,a)
	invalid.active_until_game_seconds = NAN
	_check(not F.plan_work_interval([_job([invalid])],4.0).ok,"Nonfinite activity boundary rejects atomically")
	_check(var_to_bytes([a,b,c,pool]) == before,"All negative/positive calculations preserve input bytes")
	print("TECH_GD_CONTACT_BOUNDARY_MATH: "+JSON.stringify({"checks":checks,"failures":failures,"scope":"pure_math_only_no_maincaller_proof"}))
	quit(0 if failures.is_empty() else 1)
