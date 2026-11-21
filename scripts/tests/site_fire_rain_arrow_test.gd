extends "res://scripts/tests/site_fire_p2_acceptance_supplement_test.gd"
## Real original FIRE_ARROW and original shared Lab clock. No flight mutation.

func _finish_fire(ok: bool, reason: String) -> void:
	if fire_finished: return
	fire_finished = true
	for lab: TerrainLab in fire_labs:
		if not is_instance_valid(lab): continue
		for hook: StringName in [&"fire_event_guard", &"fire_pending_projectile_query"]: lab.terrain.remove_meta(hook)
		lab.free()
	fire_labs.clear()
	TerrainArmy.release_contact_source()
	print("SITE_FIRE_RAIN_ARROW_", "PASS" if ok else "FAIL", ": checks=", fire_checks, " ", reason)
	await process_frame
	quit(0 if ok else 1)

func _run() -> void:
	var lab := _new_fire_lab()
	var data := lab.terrain
	var feature_key := _formal_feature(data, "house", Vector2i(17, 10))
	if feature_key.is_empty(): _finish_fire(false, "original paid house"); return
	var feature: Dictionary = data.site.features[feature_key]
	var hp := float(feature.parts.body.hp)
	if not _arm_one_arrow(lab, Vector2i(10, 11)): _finish_fire(false, "original bow"); return
	if not _check_fire(Runtime.fire_set_weather(data, lab.fire_action_cursor, Vector2.ZERO, 1.0).ok, "Original heavy rain input at current completed action boundary"):
		_finish_fire(false, "weather"); return
	if not _check_fire(lab.issue_fire_order(lab.character.person_id, lab.character,
		{"type": "structure", "feature_id": feature_key, "part_id": "body"}, "FIRE_ARROW").ok,
		"Original far legal bow target admits one fire-arrow order"):
		_finish_fire(false, "order"); return
	for tick in range(120):
		if not _shared(lab): _finish_fire(false, "release clock"); return
		if lab.ranged_shots == 1: break
	if not _check_fire(lab.ranged_shots == 1 and lab.fire_projectiles.size() == 1 and lab.character.ammo_inventory.fire_arrow == 0,
		"Real paid original fire arrow has released exactly once"):
		_finish_fire(false, "release"); return
	if not _check_fire(lab.stop_fire_order(lab.character.person_id, lab.character).ok, "Original cease preserves already released arrow"):
		_finish_fire(false, "cease"); return
	var flight: Dictionary = lab.fire_projectiles[0]
	var immutable := var_to_bytes([flight.origin, flight.velocity, flight.profile, flight.total, flight.projectile_id])
	var observed_cold_in_flight := false
	for tick in range(120):
		if not _shared(lab): _finish_fire(false, "actual rain flight"); return
		if not lab.fire_projectiles.is_empty() and float(flight.ember) == 0.0: observed_cold_in_flight = true
		if lab.ranged_resolutions == 1: break
	if not _check_fire(observed_cold_in_flight and lab.fire_impact_recorder.size() == 1 and lab.ranged_resolutions == 1,
		"AR-11 original rain integration naturally exhausts ember before first contact, without editing flight"):
		_finish_fire(false, "reachable natural airborne extinction"); return
	var event: Dictionary = lab.fire_impact_recorder[0]
	if not _check_fire(event.type == "structure" and event.feature == feature_key and float(event.remaining_heat_budget) == 0.0
		and float(feature.parts.body.hp) < hp and data.site.fire.contacts.is_empty()
		and immutable == var_to_bytes([flight.origin, flight.velocity, flight.profile, flight.total, flight.projectile_id])
		and lab.ranged_shots == 1 and lab.character.ammo_inventory.fire_arrow == 0,
		"Cold original arrow still performs one original kinetic hit with zero heat/contact and unchanged immutable launch"):
		_finish_fire(false, "cold kinetic contact"); return
	_finish_fire(not fire_failed, "original heavy-rain AR-11")
