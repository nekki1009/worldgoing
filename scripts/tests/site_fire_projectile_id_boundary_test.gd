extends "res://scripts/tests/site_fire_projectile_pipeline_test.gd"
## Install only with the reviewed P2 Lab candidate. Actual original owner releases;
## the high sequence value is fixture genesis for the receipt schema boundary.
const MAX_PROJECTILE_ID := 2147483647

func _run() -> void:
	if not _maximum_legal_release(): _finish(false, "maximum legal release"); return
	if not _exhausted_release_refusal(): _finish(false, "exhausted release refusal"); return
	_finish(not failed)

func _maximum_legal_release() -> bool:
	var f := _fixture()
	var bow := _team(f, [Vector2i(10, 10)])
	bow.combat_units[0].cargo.arrow = 1
	f.lab._fire_release_sequence = MAX_PROJECTILE_ID - 1
	if not _order(f, bow, _ground(Vector2i(16, 10))): return false
	var admitted := f.lab.request_fire_release(_person(bow), bow.ranged_target)
	if not _check(admitted.ok, "Maximum legal ID preparation uses original request", admitted): return false
	f.lab._commit_fire_releases()
	if not _check(f.lab.ranged_shots == 1 and f.lab.fire_projectiles.size() == 1, "Maximum legal ID produces one original flight"): return false
	if not _check(int(f.lab.fire_projectiles[0].projectile_id) == MAX_PROJECTILE_ID and f.lab._fire_release_sequence == MAX_PROJECTILE_ID, "Exact receipt maximum is admitted"): return false
	if not _check(int(bow.combat_units[0].cargo.arrow) == 0 and int(bow._ranged_last_release_ids.get(bow.combat_identity(0), 0)) == MAX_PROJECTILE_ID, "Original owner debits once and records maximum legal ID"): return false
	if not _check(not f.lab._fire_committing and f.lab.fire_reservations.is_empty(), "Legal edge leaves no commit lock or reservation"): return false
	evidence.append({"case": "maximum_legal", "projectile_id": f.lab._fire_release_sequence, "shots": f.lab.ranged_shots})
	_close(f)
	return true

func _exhausted_release_refusal() -> bool:
	var f := _fixture()
	var bow := _team(f, [Vector2i(10, 10), Vector2i(10, 12)])
	for row: Dictionary in bow.combat_units: row.cargo.arrow = 1
	f.lab._fire_release_sequence = MAX_PROJECTILE_ID
	if not _order(f, bow, _ground(Vector2i(16, 11))): return false
	var rows_before := bow.combat_units.duplicate(true)
	var release_ids_before := bow._ranged_last_release_ids.duplicate(true)
	var abilities_before := bow.command_abilities.duplicate(true)
	var order_before := {"serial": bow.ranged_order_serial, "enabled": bow.ranged_enabled, "target": bow.ranged_target.duplicate(true)}
	# Two passes prove the original reentrancy guard is restored after refusal;
	# the second pass is still a new original request, never a fake flight.
	for attempt in range(2):
		for index in range(bow.combat_units.size()):
			var admitted := f.lab.request_fire_release(_person(bow, index), bow.ranged_target)
			if not _check(admitted.ok, "Original preparation remains callable after prior commit", {"attempt": attempt, "result": admitted}): return false
		f.lab._commit_fire_releases()
		if not _check(not f.lab._fire_committing and f.lab.fire_reservations.is_empty(), "Exhaustion clears each ready reservation and commit lock", attempt): return false
		if not _check(str(f.lab.fire_scheduler_result.get("code", "")) == "PROJECTILE_ID_EXHAUSTED" and not bool(f.lab.fire_scheduler_result.get("ok", true)), "Exhaustion exposes a precise refusal", f.lab.fire_scheduler_result): return false
		if not _check(f.lab._fire_release_sequence == MAX_PROJECTILE_ID and f.lab.ranged_shots == 0 and f.lab.fire_projectiles.is_empty() and not f.lab._fire_unsaved, "Rejected release creates no flight, sequence increment or unsaved shot"): return false
		if not _check(bow.combat_units == rows_before and bow._ranged_last_release_ids == release_ids_before and bow.command_abilities == abilities_before, "Refusal preserves original ammo, fatigue, cooldown, skill and holder state"): return false
		if not _check({"serial": bow.ranged_order_serial, "enabled": bow.ranged_enabled, "target": bow.ranged_target} == order_before, "Refusal preserves the original order"): return false
	evidence.append({"case": "exhausted", "projectile_id": f.lab._fire_release_sequence, "refusal": f.lab.fire_scheduler_result.duplicate(true), "attempts": 2})
	_close(f)
	return true

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	for f: Fixture in fixtures.duplicate(): _close(f)
	TerrainArmy.release_contact_source()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var file := FileAccess.open(OUTPUT + "/projectile_id_boundary_result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok": ok, "checks": checks, "reason": reason, "evidence": evidence,
			"scope": "Original GD release ID schema boundary only; no runtime heat, GPU, Native or persistence acceptance"}, "\t"))
		file.close()
	print("SITE_FIRE_PROJECTILE_ID_BOUNDARY_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	await process_frame
	quit(0 if ok else 1)
