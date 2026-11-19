extends "res://scripts/tests/site_fire_projectile_pipeline_test.gd"
## OUTPUT ONLY / NOT RUN. Pause is a simulation permission, not invalid cargo.

func _run() -> void:
	var f := _fixture()
	var army := _team(f, [Vector2i(12, 20)])
	army.combat_units[0].cargo.fire_arrow = 1 # Finite isolated original holder genesis.
	var target := _ground(Vector2i(20, 20))
	if not _order(f, army, target, "FIRE_ARROW"): _finish(false, "original order"); return
	var reservation := f.lab.request_fire_release(_person(army), target)
	if not _check(reservation.ok and f.lab.fire_reservations.size() == 1 and f.lab.ranged_shots == 0, "Original preparation is unpaid and pending"): _finish(false); return
	var before := var_to_bytes([army.combat_units[0].cargo, f.lab.fire_reservations, f.lab.fire_action_cursor, f.lab.ranged_shots])
	f.data.site.paused = true
	if not _check(not f.lab._fire_person_ready(_person(army)), "Original paused release permission remains denied"): _finish(false); return
	var captured := f.lab.capture_fire_transport()
	if not _check(captured.ok and captured.state.reservations.size() == 1
		and captured.state.reservations[0].ready_at == f.lab.fire_reservations[army.combat_identity(0)].ready_at
		and before == var_to_bytes([army.combat_units[0].cargo, f.lab.fire_reservations, f.lab.fire_action_cursor, f.lab.ranged_shots]),
		"Paused pure capture preserves original preparation, ready time, cursor and unpaid ammunition", captured): _finish(false); return
	# Real invalidation still rejects the capture; ignore_pause bypasses no holder check.
	army.combat_units[0].cargo.fire_arrow = 0
	var rejected := f.lab.capture_fire_transport()
	if not _check(not rejected.ok and rejected.code == "BUSY" and f.lab.ranged_shots == 0,
		"Paused capture cannot bypass changed original cargo stamp", rejected): _finish(false); return
	f.data.site.paused = false
	print("SITE_FIRE_TRANSPORT_PAUSED_PASS checks=", checks)
	_finish(not failed, "Paused transport capture only; no full Store/Region save acceptance")
