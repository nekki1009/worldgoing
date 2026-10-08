extends "res://scripts/tests/site_fire_suppression_person_test.gd"
## Exercise the existing P3 interruption cases through original P4 IGNITE jobs.
var ignition_holders: Array[Dictionary] = []

func _worker_fixture(start: Vector2i, supply: int = 1024, house: bool = false) -> Dictionary:
	var c := super._worker_fixture(start, supply, house)
	if c.is_empty(): return c
	c.unit.heat = 0.0 # Explicit cold finite TEST_HEAT_100 genesis before any work.
	c.holder.fire_lab_ignition_q = supply
	ignition_holders.append(c.holder)
	return c

func _begin_worker(c: Dictionary) -> bool:
	var result: Dictionary = c.fixture.controller.person_actions.begin_fire_ignite(c.team.combat_identity(c.team.current_commander), c.worker, c.key, c.slot)
	return _check(result.ok and c.fixture.controller.person_actions.job_for(c.worker).fire_work_mode == "IGNITE",
		"Original P4 commander admits the same real job/lease with IGNITE mode", result)

func _partial_ignition() -> bool:
	var c := _worker_fixture(Vector2i(14, 12), 17)
	if c.is_empty(): return false
	var f: Fixture = c.fixture
	var remote_before := var_to_bytes([c.holder, f.data.site.fire, f.lab.combat_movement_coordinator.deployment_registry.capture_handoff_state()])
	var remote := f.controller.person_actions.begin_fire_ignite(c.team.combat_identity(c.team.current_commander), c.worker, c.key, Vector2i(12, 12))
	if not _check(not remote.ok and not f.controller.person_actions.is_busy(c.worker)
		and var_to_bytes([c.holder, f.data.site.fire, f.lab.combat_movement_coordinator.deployment_registry.capture_handoff_state()]) == remote_before,
		"WK-03 distant original work contact produces no heat, debit, job or lease"): return false
	if not _begin_worker(c): return false
	var version := int(c.holder.version)
	var inventory := var_to_bytes(f.data.site.inventory)
	_step(f, STEP)
	var queue: Array = f.data.site.fire.suppression_pending
	if not _check(queue.size() == 1 and str(queue[0].mode) == "IGNITE" and int(queue[0].total_q) == 17
		and absf(float(queue[0].end) - float(queue[0].begin) - 17.0 / 1024.0) < 0.000000001
		and c.holder.fire_lab_ignition_q == 0 and int(c.holder.version) == version + 1
		and is_same(c.holder, c.team.combat_units[1].item_state) and var_to_bytes(f.data.site.inventory) == inventory,
		"WK-04 final17 original ignition quanta produce exactly their partial interval and one holder debit"): return false
	var before := var_to_bytes([c.holder, f.data.site.fire])
	f.controller.person_actions.settle_after_contacts()
	if not _check(var_to_bytes([c.holder, f.data.site.fire]) == before, "Replayed original settlement cannot repeat paid ignition"): return false
	_step(f, 0.2 - STEP)
	if not _check(absf(float(f.data.site.fire.units[c.key].heat) - 1.0625) < 0.000000001
		and not f.controller.person_actions.is_busy(c.worker) and f.data.site.fire.suppression_pending.is_empty()
		and f.lab.combat_movement_coordinator.deployment_registry.owner_of(c.slot) == null,
		"Original5Hz boundary applies exactly1.0625 finite paid heat and releases exhausted original work"): return false
	_close(f)
	return true

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	for f: Fixture in fixtures.duplicate(): _close(f)
	TerrainArmy.release_contact_source()
	var file := FileAccess.open(OUTPUT + "/ignite_interrupt_result.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"ok": ok, "checks": checks, "reason": reason, "evidence": evidence}, "\t"))
	print("SITE_FIRE_P4_IGNITE_INTERRUPT_", "PASS" if ok else "FAIL", ": checks=", checks)
	await process_frame
	quit(0 if ok else 1)

func _run() -> void:
	if not _half_step_cancel(): _finish(false, "IGNITE half-step/cancel"); return
	for kind: String in ["death", "ko"]:
		if not _hurt_half_step(kind): _finish(false, "IGNITE " + kind); return
	if not _accepted_hold_and_stale_lease() or not _accepted_move_half_step(): _finish(false, "IGNITE original commands and replaced lease"); return
	if not _slot_becomes_hot(): _finish(false, "IGNITE newly unsafe slot"); return
	for holder: Dictionary in ignition_holders:
		if not _check(holder.fire_lab_ignition_q == 1024, "WK-03/05 all real interrupted IGNITE approaches retain the full original unpaid supply"):
			_finish(false, "unpaid supply"); return
	if not _partial_ignition(): _finish(false, "IGNITE finite partial interval"); return
	_finish(not failed, "WK-03/04/05 original IGNITE interruption/partial input supplement; no full phase, UI, persistence or performance claim")
