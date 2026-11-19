extends "res://scripts/tests/site_fire_suppression_runtime_test.gd"
## STAGE / NOT_RUN. Uses the true original TerrainData/fire/holder fixture,
## plus exact Runtime split+batch candidate generated from the frozen source.
## Native World51 is separate evidence; this is not Lab/PA integration proof.
const JointRuntime = preload("res://output/tech_tree_implementation_20261007/p5_point_runtime_oracle.gd")
const JointFatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	print("SITE_FIRE_SHARED_POINT_CONTRACT_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	quit(0 if ok else 1)

func _ticket(f: Dictionary, key: String, holder: Dictionary, quantity: int, fraction: float = 0.0, ratio: float = 1800.0) -> Dictionary:
	var seconds: float = (quantity - fraction) / 1024.0
	var prepared: Dictionary = JointRuntime.fire_prepare_suppression(f.data, f.key, f.generation, 0.2, 0.2 + seconds,
		quantity, holder, int(holder.version))
	return {"key": key, "prepared": prepared, "fraction": fraction, "ratio": ratio, "supply_per_second": 1024}

func _same_holder_batch() -> bool:
	var f: Dictionary = _suppression_fixture()
	if f.is_empty(): return false
	f.holder.fire_lab_suppression_q = 7
	var first: Dictionary = _ticket(f, "a", f.holder, 4)
	var second: Dictionary = _ticket(f, "b", f.holder, 4)
	var before: PackedByteArray = var_to_bytes([f.holder, f.data.site.fire])
	var clipped: Dictionary = JointRuntime.prepare_fire_suppression_batch(f.data, [first, second])
	if not _check(clipped.ok and clipped.needs_replan and is_equal_approx(float(clipped.limits.b), 3.0 / 1024.0 * 1800.0)
		and var_to_bytes([f.holder, f.data.site.fire]) == before, "True shared holder seven units clips second job before any cost"): return false
	second = _ticket(f, "b", f.holder, 3)
	var stable: Dictionary = JointRuntime.prepare_fire_suppression_batch(f.data, [first, second])
	if not _check(stable.ok and not stable.needs_replan and stable.jobs.a.prepared.sequence == 1 and stable.jobs.b.prepared.sequence == 2
		and stable.jobs.b.prepared.expected_holder_version == 1 and stable.jobs.b.prepared.expected_supply_q == 3
		and is_same(stable.jobs.a.prepared.holder_owner, f.holder) and is_same(stable.jobs.b.prepared.unit_owner, _unit(f.data, f.resource))
		and var_to_bytes([f.holder, f.data.site.fire]) == before, "Both future debits retain SAME original refs and ordered finite source admission"): return false
	JointRuntime.publish_validated_fire_suppression(f.data, stable.jobs.a.prepared, stable.jobs.a.check)
	JointRuntime.publish_validated_fire_suppression(f.data, stable.jobs.b.prepared, stable.jobs.b.check)
	if not _check(f.holder.fire_lab_suppression_q == 0 and f.holder.version == 2 and f.data.site.fire.suppression_sequence == 2
		and f.data.site.fire.suppression_pending.size() == 2 and _unit(f.data, f.resource).heat == 20.0,
		"One no-failure original tail charges seven once, queues two inputs, no early heat progress"): return false
	before = var_to_bytes([f.holder, f.data.site.fire])
	var replay_a: Dictionary = JointRuntime.fire_commit_suppression(f.data, stable.jobs.a.prepared)
	var replay_b: Dictionary = JointRuntime.fire_commit_suppression(f.data, stable.jobs.b.prepared)
	return _check(replay_a.ok and replay_a.duplicate and replay_b.ok and replay_b.duplicate
		and var_to_bytes([f.holder, f.data.site.fire]) == before, "Original wrapper replays both sequence receipts with zero second cost")

func _true_heat_and_endpoint_caps() -> bool:
	var f: Dictionary = _suppression_fixture()
	if f.is_empty(): return false
	var second_holder: Dictionary = Runtime.new_item_state("person:124")
	second_holder.fire_lab_suppression_q = 1024
	_unit(f.data, f.resource).heat = 1.0 / 16.0 # One exact original cooling quantum.
	var first: Dictionary = _ticket(f, "a", f.holder, 1)
	var second: Dictionary = _ticket(f, "b", second_holder, 1, 0.25)
	var before: PackedByteArray = var_to_bytes([f.holder, second_holder, f.data.site.fire])
	var clipped: Dictionary = JointRuntime.prepare_fire_suppression_batch(f.data, [first, second])
	if not _check(clipped.ok and clipped.needs_replan and float(clipped.limits.b) == 0.0
		and var_to_bytes([f.holder, second_holder, f.data.site.fire]) == before,
		"Two distinct original holders cannot reserve the same last target heat twice; waiting effort zero"): return false
	first.prepared = JointRuntime.fire_prepare_suppression(f.data, f.key, -1, 0.2, 0.2 + 1.0 / 1024.0, 1, f.holder, int(f.holder.version))
	clipped = JointRuntime.prepare_fire_suppression_batch(f.data, [first, second])
	if not _check(clipped.ok and clipped.needs_replan and float(clipped.limits.b) == 0.0
		and var_to_bytes([f.holder, second_holder, f.data.site.fire]) == before,
		"Auto -1 and explicit generation resolve SAME original unit and cannot duplicate heat allowance"): return false
	_unit(f.data, f.resource).heat = 20.0
	f.data.site.fire.suppression_sequence = 2147483645
	first = _ticket(f, "a", f.holder, 1)
	second = _ticket(f, "b", second_holder, 1)
	clipped = JointRuntime.prepare_fire_suppression_batch(f.data, [first, second])
	if not _check(clipped.ok and clipped.needs_replan and clipped.jobs.a.prepared.sequence == 2147483646 and float(clipped.limits.b) == 0.0,
		"Last real original sequence permits one debit and makes next same-point job wait"): return false
	f.data.site.fire.suppression_sequence = 0
	f.holder.version = 2147483645
	first = _ticket(f, "a", f.holder, 1)
	second = _ticket(f, "b", f.holder, 1)
	clipped = JointRuntime.prepare_fire_suppression_batch(f.data, [first, second])
	return _check(clipped.ok and clipped.needs_replan and float(clipped.limits.b) == 0.0,
		"Last real original holder revision permits only one same-point debit")

func _reject_before_cost() -> bool:
	var f: Dictionary = _suppression_fixture()
	if f.is_empty(): return false
	var ticket: Dictionary = _ticket(f, "a", f.holder, 4)
	var before: PackedByteArray = var_to_bytes([f.holder, f.data.site.fire])
	var forged: Dictionary = ticket.duplicate(true)
	# Keep true held source refs; corrupt only a numerical coefficient.
	forged.prepared = ticket.prepared.duplicate(false)
	forged.prepared.cooling_per_q *= 2.0
	if not _check(not JointRuntime.prepare_fire_suppression_batch(f.data, [forged]).ok
		and var_to_bytes([f.holder, f.data.site.fire]) == before, "Forged actual cooling coefficient rejects before cost"): return false
	if not _check(not JointRuntime.prepare_fire_suppression_batch(f.data, [ticket, ticket]).ok
		and var_to_bytes([f.holder, f.data.site.fire]) == before, "Same held job cannot consume two slots or debits"): return false
	for value: float in [NAN, INF, 0.0, -1.0]:
		forged = ticket.duplicate(false)
		forged.ratio = value
		if not _check(not JointRuntime.prepare_fire_suppression_batch(f.data, [forged]).ok
			and var_to_bytes([f.holder, f.data.site.fire]) == before, "Invalid same-interval ratio rejects even without partial quota"): return false
	forged = ticket.duplicate(false); forged.supply_per_second = 2048
	if not _check(not JointRuntime.prepare_fire_suppression_batch(f.data, [forged]).ok
		and var_to_bytes([f.holder, f.data.site.fire]) == before, "Actual original work profile determines quantity conversion"): return false
	f.holder.version += 1
	before = var_to_bytes([f.holder, f.data.site.fire])
	return _check(not JointRuntime.prepare_fire_suppression_batch(f.data, [ticket]).ok
		and var_to_bytes([f.holder, f.data.site.fire]) == before, "Stale true holder rejects before all costs/progress")

func _finite_fire_shared_productivity() -> bool:
	var f: Dictionary = _suppression_fixture()
	if f.is_empty(): return false
	f.holder.fire_lab_suppression_q = 7
	var ticket: Dictionary = _ticket(f, "fire", f.holder, 7)
	var admitted: Dictionary = JointRuntime.prepare_fire_suppression_batch(f.data, [ticket])
	if not _check(admitted.ok and not admitted.needs_replan, "True finite last seven-unit fire job admitted before shared effort"): return false
	var pool := {"fatigue": 40.0, "fatigue_rest": 0.0, "count": 4}
	var worker := {"fatigue": 40.0, "fatigue_rest": 0.0, "work_resting": false, "_fatigue_pool": pool}
	var firefighter := {"fatigue": 40.0, "fatigue_rest": 0.0, "work_resting": false, "_fatigue_pool": pool}
	var runner := {"fatigue": 40.0, "fatigue_rest": 0.0, "work_resting": false, "_fatigue_pool": pool}
	var fire_seconds: float = 7.0 / 1024.0 * 1800.0
	var requests: Array = [
		{"provider": "work_team", "key": "worker", "participants": [{"person_id": 1, "body": worker, "effort_rate": JointFatigue.WORK_RATE / 4.0, "rest_limited": true}], "remaining": 100.0, "productive_kind": "single", "progress_multiplier": 1.0, "max_game_seconds": 60.0},
		{"provider": "fire_suppress", "key": "fire", "participants": [{"person_id": 2, "body": firefighter, "effort_rate": JointFatigue.WORK_RATE / 4.0, "rest_limited": true}], "remaining": fire_seconds, "productive_kind": "raw", "progress_multiplier": 1.0, "max_game_seconds": fire_seconds},
		{"provider": "native_run", "key": "runner", "participants": [{"person_id": 3, "body": runner, "effort_rate": JointFatigue.RUN_RATE / 4.0, "rest_limited": false}], "remaining": 60.0, "productive_kind": "raw", "progress_multiplier": 1.0, "max_game_seconds": 60.0}]
	var saved: PackedByteArray = var_to_bytes([requests, pool, f.holder, f.data.site.fire])
	var planned: Dictionary = JointFatigue.plan_work_interval(requests, 60.0)
	if not _check(planned.ok and var_to_bytes([requests, pool, f.holder, f.data.site.fire]) == saved,
		"Finite original candidate and whole shared interval remain pure before final Native gate"): return false
	var first_rate: float = (JointFatigue.WORK_RATE * 2.0 + JointFatigue.RUN_RATE) / 4.0
	var later_rate: float = (JointFatigue.WORK_RATE + JointFatigue.RUN_RATE) / 4.0
	var oracle: float = JointFatigue.work_seconds(40.0, fire_seconds, first_rate)
	oracle += JointFatigue.work_seconds(40.0 + fire_seconds * first_rate, 60.0 - fire_seconds, later_rate)
	if not _check(is_equal_approx(float(planned.jobs.work_team.worker.effective_seconds), oracle)
		and is_equal_approx(float(planned.jobs.fire_suppress.fire.participant_seconds[2]), fire_seconds)
		and is_equal_approx(float(planned.pools[0].fatigue), 40.0 + (60.0 * JointFatigue.WORK_RATE + fire_seconds * JointFatigue.WORK_RATE + 60.0 * JointFatigue.RUN_RATE) / 4.0),
		"Last finite supply stops fire alone; work productivity includes accepted fire/RUN once using true start denominator"): return false
	JointRuntime.publish_validated_fire_suppression(f.data, admitted.jobs.fire.prepared, admitted.jobs.fire.check)
	return _check(f.holder.fire_lab_suppression_q == 0 and f.holder.version == 1 and _unit(f.data, f.resource).heat == 20.0
		and pool.fatigue == 40.0, "Actual fire source charges once; pure snapshot is not hot Native fatigue authority")

func _run() -> void:
	if not _same_holder_batch(): _finish(false, "shared holder batch"); return
	if not _true_heat_and_endpoint_caps(): _finish(false, "heat/sequence/version"); return
	if not _reject_before_cost(): _finish(false, "pre-cost invalid/stale"); return
	if not _finite_fire_shared_productivity(): _finish(false, "finite fire shared pool"); return
	_finish(not failed)
