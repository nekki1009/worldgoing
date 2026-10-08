extends "res://scripts/tests/site_fire_runtime_test.gd"
## OUTPUT CANDIDATE / NOT_RUN. Arithmetic fixtures use explicit test genesis.
## This is not the actual FIRE_ARROW -> approach -> SUPPRESS M1 acceptance.

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	print("SITE_FIRE_SUPPRESSION_RUNTIME_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	quit(0 if ok else 1)

func _suppression_fixture() -> Dictionary:
	var data := _data()
	var cell := Vector2i(20, 20)
	var resource := _timber(data, cell)
	if not _prime(data, cell, resource) or not _advance(data, 0.2, 1): return {}
	var holder := Runtime.new_item_state("person:123")
	holder.fire_lab_suppression_q = 1024 # Finite test genesis; never refill while work runs.
	return {"data": data, "resource": resource, "key": "resource:" + resource,
		"holder": holder, "generation": int(_unit(data, resource).generation)}

func _partial_and_replay() -> bool:
	var f := _suppression_fixture()
	if f.is_empty(): return false
	f.holder.fire_lab_suppression_q = 7
	var before := var_to_bytes(f.data.site.fire)
	var prepared := Runtime.fire_prepare_suppression(f.data, f.key, f.generation, 0.2, 0.2 + 1.0 / 30.0, 34, f.holder, 0)
	if not _check(prepared.ok and int(prepared.paid_q) == 7 and var_to_bytes(f.data.site.fire) == before,
		"WK-04 pure prepare clips to the final seven original supply quanta"): return false
	var forged: Dictionary = prepared.duplicate()
	forged.cooling_per_q = float(prepared.cooling_per_q) * 1000.0
	if not _check(not Runtime.fire_commit_suppression(f.data, forged).ok and f.holder.fire_lab_suppression_q == 7
		and var_to_bytes(f.data.site.fire) == before, "Forged prepared coefficient cannot amplify original supply"): return false
	var paid := Runtime.fire_commit_suppression(f.data, prepared)
	if not _check(paid.ok and paid.paid_q == 7 and f.holder.fire_lab_suppression_q == 0 and f.holder.version == 1
		and _unit(f.data, f.resource).heat == 20.0, "One original-holder debit queues finite work without early heat mutation"): return false
	var after := var_to_bytes([f.holder, f.data.site.fire])
	var duplicate := Runtime.fire_commit_suppression(f.data, prepared)
	if not _check(duplicate.ok and bool(duplicate.get("duplicate", false)) and duplicate.paid_q == 0
		and var_to_bytes([f.holder, f.data.site.fire]) == after, "Replay cannot debit supply or append another cooling input"): return false
	if not _advance(f.data, 0.4, 1): return false
	return _check(is_equal_approx(float(_unit(f.data, f.resource).heat), 20.0 - 7.0 / 16.0)
		and f.data.site.fire.suppression_pending.is_empty() and _fuel(f.data, f.resource) == 4096,
		"WK-04 exact seven-quanta cooling commits at original 5 Hz boundary; no fuel creation or deletion")

func _stale_holder_and_generation() -> bool:
	var f := _suppression_fixture()
	if f.is_empty(): return false
	var prepared := Runtime.fire_prepare_suppression(f.data, f.key, f.generation, 0.2, 0.2 + 1.0 / 30.0, 34, f.holder, 0)
	if not _check(prepared.ok, "Prepared original holder ticket"): return false
	f.holder.version += 1 # An intervening original holder revision invalidates a ticket.
	var before := var_to_bytes([f.holder, f.data.site.fire])
	if not _check(not Runtime.fire_commit_suppression(f.data, prepared).ok
		and var_to_bytes([f.holder, f.data.site.fire]) == before, "Stale original holder commits zero supply and zero effect"): return false
	prepared = Runtime.fire_prepare_suppression(f.data, f.key, f.generation, 0.2, 0.2 + 1.0 / 30.0, 34, f.holder, 1)
	if not _check(prepared.ok and Runtime.fire_commit_suppression(f.data, prepared).ok, "Second valid original holder ticket commits once"): return false
	var stock := int(f.holder.fire_lab_suppression_q)
	_unit(f.data, f.resource).generation += 1 # Named replacement-generation fault fixture.
	if not _advance(f.data, 0.4, 1): return false
	return _check(_unit(f.data, f.resource).heat == 20.0 and f.holder.fire_lab_suppression_q == stock
		and f.data.site.fire.suppression_pending.is_empty(), "WK-05 already-paid old-generation work cannot affect replacement or mint a refund")

func _finite_embers_and_cold() -> bool:
	var f := _suppression_fixture()
	if f.is_empty(): return false
	_unit(f.data, f.resource).state = "EMBERS" # Explicit historical-burn genesis, zero intensity and finite retained heat.
	_unit(f.data, f.resource).scorch = 0.4
	var fraction := 0.0
	for tick in range(18):
		var begin := 0.2 + tick / 30.0
		var end := 0.2 + (tick + 1) / 30.0
		fraction += 1024.0 / 30.0
		var q := floori(fraction + Runtime.FIRE_EPS)
		fraction -= q
		var prepared := Runtime.fire_prepare_suppression(f.data, f.key, f.generation, begin, end, q, f.holder, int(f.holder.version))
		if not _check(prepared.ok, "Finite original cooling interval is valid"): return false
		if int(prepared.get("paid_q", 0)) > 0:
			if not _check(Runtime.fire_commit_suppression(f.data, prepared).ok, "Finite original ember input commits"): return false
		if not _advance(f.data, end, 1): return false
	var target := Runtime.fire_suppression_target(f.data, f.key, f.generation)
	if not _check(target.ok and target.complete and target.unit.heat == 0.0 and target.unit.scorch >= 0.4
		and _fuel(f.data, f.resource) <= 4096, "WK-06 remaining embers reach exact cold without erasing scorch or restoring fuel"): return false
	var saved := var_to_bytes([f.holder, f.data.site.fire])
	var cold := Runtime.fire_prepare_suppression(f.data, f.key, f.generation, 0.8, 0.8 + 1.0 / 30.0, 34, f.holder, int(f.holder.version))
	if not _check(cold.ok and cold.complete and cold.paid_q == 0 and var_to_bytes([f.holder, f.data.site.fire]) == saved,
		"Cold command is a zero-debit pure no-op"): return false
	var wet := float(target.unit.moisture)
	return _check(wet > 0.0 and SiteCombatRules.fire_moisture_at(target.unit, 0.0, 100.0) == 0.0
		and var_to_bytes([f.holder, f.data.site.fire]) == saved, "Dormant moisture dries by original action timestamp without permanent immunity or query mutation")

func _run() -> void:
	if not _partial_and_replay(): _finish(false, "partial/replay"); return
	if not _stale_holder_and_generation(): _finish(false, "stale owner/generation"); return
	if not _finite_embers_and_cold(): _finish(false, "embers/cold/drying"); return
	_finish(not failed)
