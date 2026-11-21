extends "res://scripts/tests/site_fire_exposure_surface_death_test.gd"
## OUTPUT ONLY / NOT RUN. Actual paid Lab arrows and original building services.
var policy_evidence: Array[Dictionary] = []

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	for f: Fixture in fixtures.duplicate(): _close(f)
	TerrainArmy.release_contact_source()
	var file := FileAccess.open(OUTPUT + "/shooting_policy_result.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"ok": ok, "checks": checks, "reason": reason, "evidence": policy_evidence}, "\t"))
	print("SITE_FIRE_SHOOTING_POLICY_", "PASS" if ok else "FAIL", " checks=", checks)
	await process_frame
	quit(0 if ok else 1)

func _arrows(f: Fixture) -> TerrainArmy:
	var cells: Array[Vector2i] = []
	for y in range(8, 16): cells.append(Vector2i(18, y))
	var army := _team(f, cells)
	# Isolated genesis gives each original registered holder finite ammunition.
	for row: Dictionary in army.combat_units: row.cargo.fire_arrow = 10
	return army

func _stock(army: TerrainArmy) -> int:
	var total := 0
	for row: Dictionary in army.combat_units: total += int(row.cargo.fire_arrow)
	return total

func _blocking_wall(f: Fixture) -> String:
	var options := {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	var placement := SiteRuntime.building_cells(f.data, "stone_wall", Vector2i(21, 6), Vector2i(1, 12), options)
	if not _check(placement.ok, "Original wall layout admits post-release crossing"): return ""
	var requested := SiteRuntime.request_build(f.data, "stone_wall", placement.cells, Callable(), options)
	if not _check(requested.ok, "Original depot pays interception wall"): return ""
	var key := str(requested.feature)
	var feature: Dictionary = f.data.site.features[key]
	var task := {"version": 2, "zone": -1, "target": "feature:" + key, "action": "construct",
		"work_cell": int(feature.entrance), "cell": int(feature.entrance), "mode": "work", "progress": 0.0, "status": "", "work_slot": -1}
	SiteRuntime._feature_work(f.data, key, float(feature.work), Callable(), Callable(), task, {}, 20, 1)
	return key if _check(feature.stage == "complete", "Original paid construction completes without publishing another clock") else ""

func _pending_and_observed() -> bool:
	var f := _fixture()
	var cell := Vector2i(25, 12)
	SiteEnvironment._add_resource(f.data, SiteEnvironment.Kind.TIMBER, f.data.index(cell), 256, 0)
	SiteEnvironment.rebuild_indexes(f.data)
	var army := _arrows(f)
	var target := _ground(cell)
	if not _check(f.lab.issue_fire_order(army.current_commander, army, target, "FIRE_ARROW", "IGNITE_ONLY").ok, "AR13 original policy command admitted"): return false
	var pending_seen := false
	var stable_seen := false
	var paused_shots := -1
	for tick in range(900):
		_step(f, STEP)
		var policy: Dictionary = army.ranged_fire_policy
		# The first real pending decision must exceed the threshold. Later physical
		# contacts may reduce flights inside its original cached 5Hz decision.
		if str(policy.get("reason", "")) == "PAID_FLIGHTS_PENDING" and not pending_seen:
			pending_seen = true
			paused_shots = f.lab.ranged_shots
			var before := JSON.stringify(f.data.site.get("fire", {}), "", false, true)
			var targets: Array[Dictionary] = [target]
			var estimate := f.lab.fire_pending_ignition_estimate(army, targets)
			if not _check(float(estimate.get("ground:%d" % f.data.index(cell), 0.0)) >= 40.0
				and before == JSON.stringify(f.data.site.get("fire", {}), "", false, true)
				and not f.lab.fire_projectiles.is_empty(), "Paid-flight estimate reads original flights without mutating thermal state"): return false
		if str(policy.get("reason", "")) == "OBSERVED_STABLE_BURNING":
			stable_seen = true
			break
	if not _check(pending_seen and paused_shots >= 3 and stable_seen and 80 - _stock(army) == f.lab.ranged_shots,
		"AR13 actual paid flight pending pauses preparation, then three visible committed burning steps stop shooting",
		{"pending": pending_seen, "stable": stable_seen, "shots": f.lab.ranged_shots, "stock": _stock(army), "policy": army.ranged_fire_policy}): return false
	var shots := f.lab.ranged_shots
	_step(f, 0.4)
	if not _check(f.lab.ranged_shots == shots and f.lab.fire_reservations.is_empty(), "Stable visible ignition stops new preparation without refunding released arrows"): return false
	policy_evidence.append({"case": "AR13", "shots": shots, "remaining": _stock(army), "policy": army.ranged_fire_policy.duplicate(true)})
	_close(f)
	return true

func _interception_recheck() -> bool:
	var f := _fixture()
	var cell := Vector2i(25, 12)
	SiteEnvironment._add_resource(f.data, SiteEnvironment.Kind.TIMBER, f.data.index(cell), 256, 0)
	SiteEnvironment.rebuild_indexes(f.data)
	var army := _arrows(f)
	var target := _ground(cell)
	if not _check(f.lab.issue_fire_order(army.current_commander, army, target, "FIRE_ARROW", "IGNITE_ONLY").ok, "AR14 original ignition order admitted"): return false
	for tick in range(180):
		_step(f, STEP)
		if army.ranged_fire_policy.get("reason", "") == "PAID_FLIGHTS_PENDING": break
	if not _check(army.ranged_fire_policy.get("reason", "") == "PAID_FLIGHTS_PENDING", "AR14 actual paid volley creates a finite observation wait"): return false
	var shots := f.lab.ranged_shots
	# Complete an actual paid wall after release, preserving original LOS admission.
	var wall := _blocking_wall(f)
	if wall.is_empty(): return false
	var targets: Array[Dictionary] = [target]
	var forecast := f.lab.fire_pending_ignition_estimate(army, targets)
	if not _check(float(forecast.get("ground:%d" % f.data.index(cell), 0.0)) == 0.0, "AR14 original first static wall contact removes rear-target forecast"): return false
	for tick in range(180):
		_step(f, STEP)
		if army.ranged_fire_policy.reason == "EVALUATING" and bool(army.ranged_fire_policy.allow): break
	var blocked := false
	for event: Dictionary in f.lab.fire_impact_recorder:
		if str(event.get("feature", "")) == wall: blocked = true
	if not _check(blocked and f.lab.fire_projectiles.is_empty() and f.lab.ranged_shots == shots
		and army.ranged_fire_policy.reason == "EVALUATING" and bool(army.ranged_fire_policy.allow)
		and 80 - _stock(army) == shots, "AR14 actual interception ends paid flights; finite wait reevaluates without invented heat or ammunition", army.ranged_fire_policy): return false
	# Observe the first deadline decision before its newly admitted preparation
	# can release; then prove the original physical pipeline really retries.
	_step(f, 1.2)
	if not _check(f.lab.ranged_shots > shots and 80 - _stock(army) == f.lab.ranged_shots,
		"AR14 finite wait admits a new real paid volley with exact original ammunition debit"): return false
	if not _check(f.lab.stop_fire_order(army.current_commander, army).ok, "Original cease ends the retry order without refunding paid flights"): return false
	var retried := f.lab.ranged_shots
	_step(f, 2.0)
	if not _check(f.lab.fire_projectiles.is_empty() and f.lab.fire_reservations.is_empty() and f.lab.ranged_shots == retried
		and 80 - _stock(army) == retried, "Retry paid flights settle once after original cease"): return false
	policy_evidence.append({"case": "AR14", "wall": wall, "first_shots": shots, "retry_shots": retried, "events": f.lab.fire_impact_recorder.duplicate(true)})
	_close(f)
	return true

func _disabled_service() -> bool:
	var f := _fixture()
	var key := _paid_feature(f, "house", Vector2i(25, 12))
	if key.is_empty(): return false
	var army := _arrows(f)
	var target := {"type": "structure", "feature_id": key, "part_id": "roof"}
	if not _check(f.lab.issue_fire_order(army.current_commander, army, target, "FIRE_ARROW", "DESTROY_FUNCTION", "lodging").ok, "Original service command admits exposed paid roof"): return false
	# Declared original damage fixture; no substitute HP authority or heat genesis.
	var damaged := f.lab.siege_apply_damage_batch({key + "|roof": {"feature": key, "part": "roof", "damage": 100000.0}}, {})
	if not _check(damaged.results[key + "|roof"].ok and SiteRuntime.feature_function_state(f.data.site.features[key], "lodging") == "DISABLED", "Original destroyed roof disables the original lodging service"): return false
	_step(f, 0.3)
	if not _check(f.lab.ranged_shots == 0 and army.ranged_fire_policy.reason == "OBSERVED_FUNCTION_DISABLED", "Exposed destroyed footprint remains observable and stops new paid release", army.ranged_fire_policy): return false
	_close(f)
	return true

func _run() -> void:
	var ok := _pending_and_observed() and _interception_recheck() and _disabled_service()
	_finish(ok, "P4 AR13/AR14 and public service decisions; no Native/persistence/performance claim")
