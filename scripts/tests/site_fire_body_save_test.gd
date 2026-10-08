extends "res://scripts/tests/site_fire_exposure_test.gd"
## Original Actor/Army body persistence only. Root owns the full SiteStore gate.

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	for f: Fixture in fixtures.duplicate(): _close(f)
	TerrainArmy.release_contact_source()
	print("SITE_FIRE_BODY_SAVE_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	await process_frame
	quit(0 if ok else 1)

func _same_saved_value(left: Variant, right: Variant) -> bool:
	if (left is int or left is float) and (right is int or right is float): return absf(float(left) - float(right)) <= 0.000000001
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size(): return false
		for key: Variant in left:
			if not right.has(key) or not _same_saved_value(left[key], right[key]): return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size(): return false
		for index in range(left.size()):
			if not _same_saved_value(left[index], right[index]): return false
		return true
	return left == right

func _schema_and_contact() -> bool:
	var body := {}
	var payload := {"event_id": "arrow:17", "action_time": 3.0, "remaining_heat_budget": 12.0, "heat_rate": 10.0, "heat_transfer": 0.5, "contact_scale": 0.1, "max_seconds": 2.0}
	if not _check(SiteCombatRules.fire_body_receive_contact(body, payload), "Original body accepts finite protected contact"): return false
	var saved := SiteCombatRules.fire_body_capture(body)
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(saved))
	if not _check(SiteCombatRules.fire_body_saved_valid(parsed), "JSON finite contact admitted with original version"): return false
	var restored := SiteCombatRules.fire_body_restore(parsed)
	var segments: Array[Dictionary] = [{"begin": 3.0, "end": 3.2, "risk": 0.0, "wet": false}]
	var a := SiteCombatRules.fire_body_advance(body, 8, 3.0, 3.2, segments, 1.0)
	var b := SiteCombatRules.fire_body_advance(restored, 8, 3.0, 3.2, segments, 1.0)
	if not _check(_same_saved_value(a, b) and _same_saved_value(SiteCombatRules.fire_body_capture(body), SiteCombatRules.fire_body_capture(restored)), "Original contact remainder continues identically across JSON"): return false
	var corruptions: Array[Dictionary] = []
	for field: String in ["dose", "burn_left", "episode_left"]:
		var invalid := parsed.duplicate(true)
		invalid[field] = -0.1
		corruptions.append(invalid)
	var extra := parsed.duplicate(true)
	extra["second_hp"] = 1.0
	corruptions.append(extra)
	var version := parsed.duplicate(true)
	version.version = "invented"
	corruptions.append(version)
	var sequence := parsed.duplicate(true)
	sequence.last_interval = 1.5
	corruptions.append(sequence)
	var contact := parsed.duplicate(true)
	contact.contacts["arrow:17"].end = 9.0
	corruptions.append(contact)
	for invalid: Dictionary in corruptions:
		if not _check(not SiteCombatRules.fire_body_saved_valid(invalid), "Body rejects corrupt fields before replacement", invalid): return false
	return true

func _actor_save() -> bool:
	var f := _fixture()
	var actor := _actor_fixture(f, Vector2i(10, 10))
	_hot_fixture(f, actor.terrain_cell)
	_step(f, 2.5)
	if not _check(float(actor.fire_body.burn_left) > 0.0, "Original shared motion interval ignites Actor before save"): return false
	var saved := actor.capture_state()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(saved))
	if not _check(TerrainTestCharacter.valid_state(parsed, f.data) and parsed.fire_body.size() == 8 and not parsed.fire_body.has("last_interval_fire_hp"), "Original Actor save includes only durable fire body", parsed.fire_body): return false
	var begin := float(parsed.fire_body.last_action_end)
	var sequence := int(parsed.fire_body.last_interval) + 1
	var segments: Array[Dictionary] = [{"begin": begin, "end": begin + STEP, "risk": 0.0, "wet": false}]
	actor.advance_fire_exposure(sequence, begin, begin + STEP, segments)
	var expected_hp := actor.hp
	var expected := SiteCombatRules.fire_body_capture(actor.fire_body)
	actor.restore_state(parsed)
	if not _check(actor.hp == float(parsed.hp) and SiteCombatRules.fire_body_capture(actor.fire_body) == SiteCombatRules.fire_body_restore(parsed.fire_body), "Actor restoration itself applies no HP or time"): return false
	actor.advance_fire_exposure(sequence, begin, begin + STEP, segments)
	var actual := SiteCombatRules.fire_body_capture(actor.fire_body)
	if not _check(absf(actor.hp - expected_hp) <= 0.000000001 and _same_saved_value(actual, expected), "Actor continues identical finite episode after original restore", {"expected_hp": expected_hp, "actual_hp": actor.hp, "expected_body": expected, "actual_body": actual}): return false
	var hp := actor.hp
	actor.advance_fire_exposure(sequence, begin, begin + STEP, segments)
	if not _check(actor.hp == hp, "Restored original interval watermark rejects duplicate HP"): return false
	_close(f)
	return true

func _army_save() -> bool:
	var f := _fixture()
	var team := _team(f, [Vector2i(10, 10)])
	_hot_fixture(f, team.cells[0])
	_step(f, 0.1)
	if not _check(float(team.combat_units[0].fire_body.dose) > 0.0, "Original protected Army row retains finite dose before save"): return false
	var saved := team.capture_combat_state()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(saved))
	if not _check(TerrainArmy.valid_combat_state(parsed, f.data, {}, f.data.site) and parsed.units[0].fire_body.size() == 8, "Original Army snapshot validates durable body JSON"): return false
	var body: Dictionary = parsed.units[0].fire_body
	var begin := float(body.last_action_end)
	var sequence := int(body.last_interval) + 1
	var segments: Array[Dictionary] = [{"begin": begin, "end": begin + STEP, "risk": 0.0, "wet": false}]
	team.advance_fire_exposure(0, sequence, begin, begin + STEP, segments)
	var expected_hp := float(team.combat_units[0].hp)
	var expected := SiteCombatRules.fire_body_capture(team.combat_units[0].fire_body)
	team.restore_combat_state(parsed, f.data, f.character, null)
	if not _check(float(team.combat_units[0].hp) == float(parsed.units[0].hp), "Army restore itself applies no fire packet"): return false
	team.advance_fire_exposure(0, sequence, begin, begin + STEP, segments)
	if not _check(absf(float(team.combat_units[0].hp) - expected_hp) <= 0.000000001 and _same_saved_value(SiteCombatRules.fire_body_capture(team.combat_units[0].fire_body), expected), "Same original row continues identically after restore"): return false
	_close(f)
	return true

func _run() -> void:
	if not _schema_and_contact(): _finish(false, "strict finite body schema/contact continuation"); return
	if not _actor_save(): _finish(false, "Actor original capture/restore"); return
	if not _army_save(): _finish(false, "Army original capture/restore"); return
	_finish(not failed, "P5 original body owners only; full SiteStore/flight/Region gate belongs to root")
