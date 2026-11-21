extends "res://scripts/tests/site_boarding_cross_link_test.gd"
## B5B (plan line 99, Q7 A): load-side refusals. A hand-written save (valid checksum, the same envelope
## as site_boarding_save_gate_test.gd `_bad_load`) with a crosser in the channel, an invalid link, a peerless
## link, a missing peer hull or a mismatched link id is refused by Store.load_site, and neither the live
## records nor the file change.

const StoreB5B = preload("res://scripts/terrain_lab/site_store.gd")
const B5B_GOOD: String = "user://b5b_good.json"

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	if not _must(DisplayServer.get_name() == "headless", "B5B_CANONICAL_HEADLESS"): return
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for owner: TerrainArmy in lab.combat_armies: owner.set_process(false)
	if not _fixture() or not _cases_b5b(): return
	print("SITE_BOARDING_B5B_PASS: " + get_script().resource_path)
	await _cleanup(0)

## Writes a candidate payload.state inside the same checksum envelope the B0 test uses.
func _write_candidate_b5b(name: String, candidate: Dictionary) -> String:
	var wrapper: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(B5B_GOOD))
	var payload: Dictionary = JSON.parse_string(wrapper.payload)
	payload.state = candidate
	var body: String = JSON.stringify(payload, "", true, true)
	var path: String = "user://b5b_bad_" + name + ".json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return ""
	file.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}))
	file.close()
	return path

func _refuse_load_b5b(name: String, candidate: Dictionary, code: String) -> bool:
	var path: String = _write_candidate_b5b(name, candidate)
	if not _must(path != "", "B5B_WRITE " + name): return false
	var live_before: PackedByteArray = var_to_bytes(lab.site_controller.vehicles.records())
	var file_before: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var loaded: Dictionary = StoreB5B.load_site(path)
	var got: String = str(loaded.get("code", ""))
	return _must(not bool(loaded.get("ok", false)) and got == code and live_before == var_to_bytes(lab.site_controller.vehicles.records()) and file_before == FileAccess.get_file_as_bytes(path), "B5B_LOAD_REFUSED " + name + " expected=" + code + " actual=" + str(loaded))

func _cases_b5b() -> bool:
	if not _must(_link_live_b3(), "B5B_PREMISE_LINK"): return false
	var saved: Dictionary = StoreB5B.save(lab.terrain, B5B_GOOD)
	if not _must(bool(saved.get("ok", false)), "B5B_GOOD_SAVE: " + str(saved)): return false
	var good: Dictionary = StoreB5B.load_site(B5B_GOOD)
	if not _must(bool(good.get("ok", false)), "B5B_GOOD_LOAD: " + str(good)): return false
	var wrapper: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(B5B_GOOD))
	var base: Dictionary = JSON.parse_string(wrapper.payload).state

	# B5S4: a crosser in the channel on load (no crossing job exists to settle it): refused.
	var crosser: Dictionary = base.duplicate(true)
	for identity: String in [boat_id, enemy_boat]: crosser.vehicles[identity].naval.boarding_link.crosser_id = people[0]
	if not _refuse_load_b5b("crosser", crosser, "BUSY"): return false

	# B5S5: an invalid link record is corrupt (a sink clears the link; invalid is never persisted).
	var invalid: Dictionary = base.duplicate(true)
	for identity: String in [boat_id, enemy_boat]: invalid.vehicles[identity].naval.boarding_link.state = "invalid"
	if not _refuse_load_b5b("invalid", invalid, "CORRUPT_SAVE"): return false

	# B5S5: a peerless link (the enemy record lost its end): corrupt, no inference of the missing end.
	var peerless: Dictionary = base.duplicate(true)
	peerless.vehicles[enemy_boat].naval.erase("boarding_link")
	peerless.vehicles[enemy_boat].naval.version = 1
	if not _refuse_load_b5b("peerless", peerless, "CORRUPT_SAVE"): return false

	# B5S5: a missing peer hull: corrupt.
	var missing: Dictionary = base.duplicate(true)
	missing.vehicles.erase(enemy_boat)
	if not _refuse_load_b5b("missing_peer", missing, "CORRUPT_SAVE"): return false

	# B5S5: the two ends name different links: corrupt.
	var mismatch: Dictionary = base.duplicate(true)
	mismatch.vehicles[enemy_boat].naval.boarding_link.id = "other-link"
	if not _refuse_load_b5b("id_mismatch", mismatch, "CORRUPT_SAVE"): return false
	return true
