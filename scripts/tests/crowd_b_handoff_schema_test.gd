extends SceneTree
## Real SiteStore pure guards; no scene, mock owner, asset mutation or save file.
const Store = preload("res://scripts/terrain_lab/site_store.gd")
var checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, label: String, details: Variant = null) -> bool:
	checks += 1
	if value: return true
	printerr("CROWD_B_HANDOFF_SCHEMA_FAIL check=", checks, " ", label, " ", details if details != null else "")
	quit(2)
	return false

func _formation() -> Dictionary:
	return {"morale": 50.0, "rally_rest": 0.0, "fatigue": 12.5, "fatigue_rest": 1.25,
		"training": 2.0, "fatigue_count": 2, "order": 0, "goal_x": 10.5, "goal_y": 20.5,
		"goal_facing": 0.125, "pursuit_left": 0.0, "origin_x": 10.5, "origin_y": 20.5,
		"cx": 10.5, "cy": 20.5, "facing": 0.125, "order_delay": 0.0, "ref_x": 10.5, "ref_y": 20.5,
		"routed": false, "needs_attack_order": false, "commander_present": true, "ai_enabled": false,
		"no_orders": false, "attacking": false, "ref_valid": true, "resupplying": false, "host_center": false,
		"formal_person": 1, "acting_person": -1, "current_person": 1, "target_person": 2, "officer_persons": [1, 2]}

func _roster() -> Dictionary:
	var roster: Dictionary = {"schema": 2, "roster_version": 1, "team_id": 3, "goal": [10, 20],
		"units": [{"person_id": 2, "hp": 37.125, "cargo": {"grain": 3}}],
		"player_member": {"id": 1, "present": true, "goal": [10, 20]}, "crowd_state": _formation()}
	roster.crowd_source_sha256 = Store._crowd_roster_source_sha256(roster)
	return roster

func _references(roster: Dictionary) -> Dictionary:
	return {"actors": {"player": {"person_id": 1}}, "armies": [roster]}

func _hash_checks() -> bool:
	var roster: Dictionary = _roster()
	var before: Dictionary = roster.duplicate(true)
	var source: String = str(roster.crowd_source_sha256)
	if not _check(Store._crowd_roster_handoff_current(roster), "new roster SHA is current"): return false
	if not _check(Store._crowd_roster_source_sha256(roster) == source and roster == before, "hash helper does not mutate the original nested snapshot"): return false
	var envelope: Dictionary = roster.duplicate(true)
	envelope.crowd_state.goal_x = 123.5
	envelope.crowd_state.target_person = 999
	envelope.crowd_source_sha256 = "e".repeat(64)
	if not _check(Store._crowd_roster_source_sha256(envelope) == source, "source SHA excludes both envelope keys"): return false
	var without: Dictionary = roster.duplicate(true)
	without.erase("crowd_source_sha256")
	if not _check(not Store._crowd_roster_handoff_current(without), "missing source SHA is not a current ordinary handoff"): return false
	for hp: float in [0.0, 0.1, 0.37, 1.0 / 30.0, 37.125, 50.123456789012345, 99.99999999999999]:
		var numeric: Dictionary = roster.duplicate(true)
		numeric.units[0].hp = hp
		numeric.crowd_source_sha256 = Store._crowd_roster_source_sha256(numeric)
		var decoded: Variant = JSON.parse_string(JSON.stringify(numeric, "", true, true))
		if not _check(decoded is Dictionary and Store._crowd_roster_handoff_current(decoded), "source SHA survives real JSON integer/float roundtrip", {"hp": hp, "before": numeric.crowd_source_sha256, "after": Store._crowd_roster_source_sha256(decoded) if decoded is Dictionary else "invalid JSON"}): return false
	var ulp_source: Dictionary = roster.duplicate(true)
	ulp_source.command_radius = float(PackedFloat32Array([10.984682083129883])[0])
	ulp_source.units[0].face = float(PackedFloat32Array([-0.12320729345083237])[0])
	ulp_source.crowd_source_sha256 = Store._crowd_roster_source_sha256(ulp_source)
	var ulp_loaded: Dictionary = ulp_source.duplicate(true)
	ulp_loaded.command_radius = 10.984682083129885
	ulp_loaded.units[0].face = -0.12320729345083235
	if not _check(ulp_source.command_radius != ulp_loaded.command_radius and ulp_source.units[0].face != ulp_loaded.units[0].face, "restart precision fixture contains the observed distinct doubles"): return false
	if not _check(Store._crowd_roster_handoff_current(ulp_loaded), "observed restart radius/face one-to-two ULP differences retain the source SHA", {"source": ulp_source.crowd_source_sha256, "loaded": Store._crowd_roster_source_sha256(ulp_loaded)}): return false
	var midpoint: Dictionary = roster.duplicate(true)
	midpoint.command_radius = float(PackedFloat32Array([7.867223262786865])[0]) + 2.0
	midpoint.crowd_source_sha256 = Store._crowd_roster_source_sha256(midpoint)
	var midpoint_loaded: Dictionary = JSON.parse_string(JSON.stringify(midpoint, "", true, true))
	if not _check(midpoint.command_radius != midpoint_loaded.command_radius and Store._crowd_roster_handoff_current(midpoint_loaded), "radius at a float32 midpoint retains full-precision JSON identity"): return false
	for field: String in ["hp", "ko", "exch_cd"]:
		var precise: Dictionary = roster.duplicate(true)
		precise.units[0][field] = 1.25
		precise.crowd_source_sha256 = Store._crowd_roster_source_sha256(precise)
		precise.units[0][field] = 1.25 + 0.000000001
		if not _check(not Store._crowd_roster_handoff_current(precise), "real double state changes remain stale", field): return false
	for mutation: String in ["hp", "goal", "cargo"]:
		var changed: Dictionary = roster.duplicate(true)
		match mutation:
			"hp": changed.units[0].hp = 37.115
			"goal": changed.goal[0] = 11
			"cargo": changed.units[0].cargo.grain = 4
		if not _check(not Store._crowd_roster_handoff_current(changed) and changed.crowd_source_sha256 == source, "ordinary body change makes the envelope stale without re-signing", mutation): return false
	return true

func _formation_checks() -> bool:
	var valid: Dictionary = _formation()
	if not _check(valid.size() == 33 and Store._valid_crowd_handoff_formation(valid), "full 33-field formation is valid"): return false
	for field: String in valid:
		var missing: Dictionary = valid.duplicate(true)
		missing.erase(field)
		if not _check(not Store._valid_crowd_handoff_formation(missing), "missing formation field is rejected", field): return false
	var extra: Dictionary = valid.duplicate(true)
	extra.unexpected = 0
	if not _check(not Store._valid_crowd_handoff_formation(extra), "extra formation field is rejected"): return false
	for field: String in ["routed", "needs_attack_order", "commander_present", "ai_enabled", "no_orders", "attacking", "ref_valid", "resupplying", "host_center"]:
		var wrong: Dictionary = valid.duplicate(true)
		wrong[field] = 0
		if not _check(not Store._valid_crowd_handoff_formation(wrong), "boolean formation fields cannot be numeric", field): return false
	for field: String in ["morale", "rally_rest", "fatigue", "fatigue_rest", "training", "fatigue_count", "order", "goal_x", "goal_y", "goal_facing", "pursuit_left", "origin_x", "origin_y", "cx", "cy", "facing", "order_delay", "ref_x", "ref_y"]:
		for value: float in [NAN, INF, -INF]:
			var nonfinite: Dictionary = valid.duplicate(true)
			nonfinite[field] = value
			if not _check(not Store._valid_crowd_handoff_formation(nonfinite), "nonfinite formation number is rejected", {"field": field, "value": str(value)}): return false
	for case: Array in [["fatigue_count", -1], ["fatigue_count", Store.MAX_CROWD_ROWS + 1], ["fatigue_count", 1.5], ["order", -1], ["order", 6], ["order", 0.5], ["morale", -0.1], ["morale", 100.1], ["fatigue", -0.1], ["fatigue", 100.1], ["training", -0.1], ["rally_rest", -0.1], ["fatigue_rest", -0.1]]:
		var wrong: Dictionary = valid.duplicate(true)
		wrong[str(case[0])] = case[1]
		if not _check(not Store._valid_crowd_handoff_formation(wrong), "formation range/count bounds are enforced", case): return false
	for field: String in ["pursuit_left", "order_delay"]:
		var cooldown: Dictionary = valid.duplicate(true)
		cooldown[field] = -0.125
		if not _check(Store._valid_crowd_handoff_formation(cooldown), "sub-second negative native cooldown remains legal", field): return false
		cooldown[field] = -1.0
		if not _check(not Store._valid_crowd_handoff_formation(cooldown), "negative cooldown boundary -1 is rejected", field): return false
	for officers: Variant in [[0], [-1], [1.5], ["1"], [2147483648], [1, 1], {}]:
		var wrong: Dictionary = valid.duplicate(true)
		wrong.officer_persons = officers
		if not _check(not Store._valid_crowd_handoff_formation(wrong), "officer type/range/uniqueness is enforced", officers): return false
	for field: String in ["formal_person", "acting_person", "current_person", "target_person"]:
		for bad: Variant in [0, 1.5, "1", 2147483648]:
			var wrong: Dictionary = valid.duplicate(true)
			wrong[field] = bad
			if not _check(not Store._valid_crowd_handoff_formation(wrong), "formation reference scalar schema is enforced", {"field": field, "value": bad}): return false
	var actor_formation: Dictionary = valid.duplicate(true)
	actor_formation.officer_persons = [1]
	var actor_extra: Dictionary = {"version": 1, "bandaged": false, "role": 0, "face": 0.0, "escape_t": 0.0, "knock_t": 0.0, "act_t": 0.0, "stagger": 0.0, "exch_cd": 0.0, "ranged_cd": 0.0, "skill_cd": 0.0, "solo_formation": actor_formation}
	if not _check(Store._valid_crowd_actor_handoff(actor_extra, 1), "actor still accepts its own single-officer formation"): return false
	for field: String in ["formal_person", "acting_person", "current_person"]:
		var wrong: Dictionary = actor_extra.duplicate(true)
		wrong.solo_formation[field] = 2
		if not _check(not Store._valid_crowd_actor_handoff(wrong, 1), "actor formation commander cannot be another person", field): return false
	for officers: Array in [[2], [1, 2]]:
		var wrong: Dictionary = actor_extra.duplicate(true)
		wrong.solo_formation.officer_persons = officers
		if not _check(not Store._valid_crowd_actor_handoff(wrong, 1), "actor retains own-identity and single-officer limits", officers): return false
	return true

func _transport_hash_checks() -> bool:
	# The actual team-2 face takes two JSON transports to settle. Preserve its
	# binary64 fixtures: original float32-derived value, then the observed 23 ULP step.
	var original_face: float = PackedByteArray([0, 0, 0, 224, 226, 82, 110, 63]).decode_double(0)
	var first_face: float = PackedByteArray([237, 255, 255, 223, 226, 82, 110, 63]).decode_double(0)
	var settled_face: float = PackedByteArray([214, 255, 255, 223, 226, 82, 110, 63]).decode_double(0)
	var roster: Dictionary = _roster()
	roster.units[0].face = original_face
	roster.crowd_source_sha256 = Store._crowd_roster_source_sha256(roster)
	var frozen_sha: String = str(roster.crowd_source_sha256)
	var original_bytes: PackedByteArray = var_to_bytes(roster)
	if not _check(frozen_sha.length() == 64 and original_face != first_face and first_face != settled_face,
		"exact observed tiny-face fixture has a nonempty converged source hash"): return false
	if not _check(Store._crowd_roster_handoff_current(roster) and var_to_bytes(roster) == original_bytes,
		"canonical hashing preserves every original tiny-face snapshot byte"): return false
	for iteration in range(4):
		roster = JSON.parse_string(JSON.stringify(roster, "", true, true))
		var before: PackedByteArray = var_to_bytes(roster)
		if not _check(float(roster.units[0].face) == (first_face if iteration == 0 else settled_face),
			"real JSON transport reproduces and then retains the exact observed face bits", iteration): return false
		if not _check(Store._crowd_roster_handoff_current(roster) and roster.crowd_source_sha256 == frozen_sha
			and var_to_bytes(roster) == before, "frozen roster hash survives four transports without changing payloads", iteration): return false
		if iteration == 0:
			var old: Dictionary = roster.duplicate(true)
			old.erase("crowd_state")
			old.erase("crowd_source_sha256")
			var old_sha: String = JSON.stringify(old, "", true, true).sha256_text()
			old.crowd_state = _formation()
			old.crowd_source_sha256 = old_sha
			if not _check(old_sha != frozen_sha and not Store._crowd_roster_handoff_current(old)
				and old.crowd_source_sha256 == old_sha, "old one-round hash remains stale and is never re-signed"): return false
	var actor: Dictionary = {"schema": 2, "person_id": 1, "hp": 37.125,
		"action_time": original_face, "facing": [1, 0], "cargo": {"grain": 3}}
	var handoff: Dictionary = {"solo_source_sha256": Store._crowd_actor_source_sha256(actor), "solo_formation": _formation()}
	actor.crowd_handoff = handoff.duplicate(true)
	for iteration in range(4):
		actor = JSON.parse_string(JSON.stringify(actor, "", true, true))
		var before: PackedByteArray = var_to_bytes(actor)
		if not _check(Store._crowd_actor_solo_current(actor, handoff) and var_to_bytes(actor) == before,
			"Actor action timer uses the same immutable hash across four transports", iteration): return false
	actor.action_time = float(actor.action_time) + 0.000000001
	if not _check(not Store._crowd_actor_solo_current(actor, handoff), "real Actor timer changes remain stale"): return false
	roster.crowd_source_sha256 = ""
	handoff.solo_source_sha256 = ""
	if not _check(not Store._crowd_roster_handoff_current(roster) and not Store._crowd_actor_solo_current(actor, handoff),
		"empty failure hashes cannot authorize either ordinary handoff"): return false
	return true

func _reference_checks() -> bool:
	var roster: Dictionary = _roster()
	if not _check(Store._validate_crowd_formation_references(_references(roster)).ok, "actor 1 is a member beside row 2 and counted only once"): return false
	var removed: Dictionary = roster.duplicate(true)
	removed.player_member = {}
	removed.crowd_source_sha256 = Store._crowd_roster_source_sha256(removed)
	if not _check(not Store._validate_crowd_formation_references(_references(removed)).ok, "an actor outside the roster cannot be its current commander"): return false
	var duplicate: Dictionary = roster.duplicate(true)
	duplicate.units.append({"person_id": 1})
	duplicate.crowd_source_sha256 = Store._crowd_roster_source_sha256(duplicate)
	if not _check(not Store._validate_crowd_formation_references(_references(duplicate)).ok, "duplicated actor row is not hidden by membership"): return false
	for field: String in ["formal_person", "acting_person", "current_person", "target_person", "officer_persons"]:
		var unknown: Dictionary = roster.duplicate(true)
		unknown.crowd_state[field] = [999] if field == "officer_persons" else 999
		if not _check(Store._crowd_roster_handoff_current(unknown) and not Store._validate_crowd_formation_references(_references(unknown)).ok, "current ordinary formation rejects unknown reference 999", field): return false
		unknown.units[0].hp = 36.125
		if not _check(not Store._crowd_roster_handoff_current(unknown) and Store._validate_crowd_formation_references(_references(unknown)).ok, "stale ordinary formation contributes no old references", field): return false
		var native: Dictionary = _references(unknown)
		native.crowd = {} # This guard only selects native reference authority, not blob admission.
		if not _check(not Store._validate_crowd_formation_references(native).ok, "native reference validation cannot be bypassed with a stale ordinary SHA", field): return false
		unknown.erase("crowd_source_sha256")
		if not _check(not Store._validate_crowd_formation_references(_references(unknown)).ok, "legacy handoff without SHA retains reference validation", field): return false
	return true

func _envelope_checks() -> bool:
	# _validate_armies must reject these at its envelope gate, before the separate
	# full TerrainArmy/terrain validation; require its exact reason, not any failure.
	var data: TerrainData = TerrainData.new()
	for bad: Variant in [null, 1, [], {}, "", "0".repeat(63), "0".repeat(65), "A".repeat(64), "g".repeat(64)]:
		var roster: Dictionary = _roster()
		roster.crowd_source_sha256 = bad
		var state: Dictionary = _references(roster)
		var result: Dictionary = Store._validate_armies(data, state)
		if not _check(not result.ok and result.code == "CORRUPT_SAVE" and str(result.message).begins_with("CORRUPT_SAVE：軍隊群眾交接"), "malformed ordinary source SHA is rejected by the envelope guard", {"input": bad, "result": result}): return false
	var malformed: Dictionary = _roster()
	malformed.crowd_state.routed = 0
	malformed.units[0].hp = 36.125
	var rejected: Dictionary = Store._validate_armies(data, _references(malformed))
	if not _check(not Store._crowd_roster_handoff_current(malformed) and not rejected.ok and rejected.code == "CORRUPT_SAVE" and str(rejected.message).begins_with("CORRUPT_SAVE：軍隊群眾交接"), "stale ordinary envelope still requires complete legal formation schema", rejected): return false
	return true

func _run() -> void:
	if not _hash_checks() or not _transport_hash_checks() or not _formation_checks() or not _reference_checks() or not _envelope_checks(): return
	print("CROWD_B_HANDOFF_SCHEMA_PASS checks=", checks)
	quit(0)
