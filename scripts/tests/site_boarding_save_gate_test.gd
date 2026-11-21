extends "res://scripts/tests/site_boarding_contract_test.gd"
const B0_OUT: String = "res://output/site_boarding_b0_tests"
const B0_GOOD: String = B0_OUT + "/stable.json"
var owner_calls: int = 0

func _context() -> Dictionary:
	return {"purpose": "region_checkpoint", "mode": "live", "source_generation": 0, "runtime_revision": 0,
		"token": "b0-fixture", "game_seconds": float(lab.terrain.site.get("simulation_settlement", {}).get("last_settled_game_seconds", 0.0)),
		"action_seconds": lab.fire_action_cursor, "fire_epoch": "b0-fixture", "fire_sequence": 0,
		"interval_complete": true, "effects_complete": true, "mode_revision": 0, "backend": "gd", "events": [], "endpoint_payload": {}}

func _owner_probe(_context_value: Dictionary) -> Dictionary:
	owner_calls += 1
	return Runtime.fail("B0_OWNER_CALLED")

func _live_bytes() -> PackedByteArray:
	var rows: Array = []
	for owner: TerrainArmy in lab.combat_armies: rows.append(owner.combat_units)
	var actors: Array = []
	for actor: TerrainTestCharacter in lab.combat_actors: actors.append(actor.capture_state())
	return var_to_bytes({"site": lab.terrain.site, "rows": rows, "actors": actors,
		"jobs": lab.site_controller.person_actions._jobs, "duty": lab._region_capture_duty_cache(),
		"duty_depth": lab._region_duty_depth, "duty_transient": lab._region_duty_transient,
		"fire_action_cursor": lab.fire_action_cursor})

func _four_gates(code: String) -> bool:
	var original: PackedByteArray = _live_bytes()
	var file_bytes: PackedByteArray = FileAccess.get_file_as_bytes(B0_GOOD)
	var nq: Dictionary = _nq(lab.terrain.site)
	var controller: SiteController = lab.site_controller
	var captured: Dictionary = controller._capture_for_save()
	if not _must(not captured.ok and captured.code == code and original == _live_bytes(), "B0_CONTROLLER_FIRST_MUTATION"): return false
	var pure: Dictionary = Store.save(lab.terrain, B0_GOOD)
	if not _must(not pure.ok and pure.code == code and original == _live_bytes() and file_bytes == FileAccess.get_file_as_bytes(B0_GOOD), "B0_PURE_STORE_ATOMIC"): return false
	var request: Dictionary = _context()
	request.owners = {"scene": _owner_probe}
	var hot: Dictionary = Store.save(lab.terrain, B0_GOOD, null, false, request)
	if not _must(not hot.ok and hot.code == code and owner_calls == 0 and original == _live_bytes(), "B0_BEFORE_REGION_OWNER_CALLBACK"): return false
	var slot: RegionSaveSlot = RegionSaveSlot.new()
	var party: Dictionary = {"party_id": "b0-fixture", "controller": "player", "content": lab.terrain.site}
	var previous_slot: RegionSaveSlot = controller.region_slot
	controller.region_slot = slot
	var checkpoint: Dictionary = controller.capture_region_checkpoint("region_checkpoint")
	controller.region_slot = previous_slot
	if not _must(not checkpoint.ok and checkpoint.code == code and original == _live_bytes(), "B0_REGION_CONTROLLER_BEFORE_POSITIONS"): return false
	var party_before: PackedByteArray = var_to_bytes(party)
	var control_before: PackedByteArray = var_to_bytes({"pin": slot.pin, "control": slot.control, "marker": slot._marker})
	var document: Dictionary = slot._region_party_document("b0-fixture", party)
	if not _must(not document.ok and document.code == code and party_before == var_to_bytes(party) and control_before == var_to_bytes({"pin": slot.pin, "control": slot.control, "marker": slot._marker}), "B0_PARTY_BEFORE_SERIALIZE"): return false
	var region: Dictionary = lab.capture_region_owner_state(_context())
	if not _must(not region.ok and region.code == code and original == _live_bytes(), "B0_REGION_BEFORE_DUTY_ENTER"): return false
	return _must(nq == _nq(lab.terrain.site) and file_bytes == FileAccess.get_file_as_bytes(B0_GOOD), "B0_ALL_GATES_TRUE_N_Q_FILE")

func _bad_load(name: String, candidate: Dictionary, code: String) -> bool:
	var wrapper: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(B0_GOOD))
	var payload: Dictionary = JSON.parse_string(wrapper.payload)
	payload.state = candidate
	var body: String = JSON.stringify(payload, "", true, true)
	var path: String = B0_OUT + "/bad_" + name + ".json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if not _must(file != null, "B0_BAD_FIXTURE_WRITE"): return false
	file.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}))
	file.close()
	var before: PackedByteArray = _live_bytes()
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var loaded: Dictionary = Store.load_site(path)
	return _must(not loaded.ok and loaded.code == code and before == _live_bytes() and bytes == FileAccess.get_file_as_bytes(path), "B0_LOADER_NO_INFERENCE: " + str(loaded))

func _cases() -> bool:
	DirAccess.make_dir_recursive_absolute(B0_OUT)
	var controller: SiteController = lab.site_controller
	controller.save_root = B0_OUT
	controller.save_path = B0_GOOD
	team.settle_combat_command()
	enemy.settle_combat_command()
	lab.terrain.site.combat_left = 0.0
	if not _must(controller._capture_for_save().ok, "B0_STABLE_CAPTURE"): return false
	var saved: Dictionary = Store.save(lab.terrain, B0_GOOD)
	if not _must(saved.ok, "B0_STABLE_PURE_STORE: " + str(saved)): return false
	var loaded: Dictionary = Store.load_site(B0_GOOD)
	if not _must(loaded.ok, "B0_STABLE_LOADER: " + str(loaded)): return false
	var slot: RegionSaveSlot = RegionSaveSlot.new()
	var party: Dictionary = {"party_id": "b0-fixture", "controller": "player", "content": lab.terrain.site}
	var document: Dictionary = slot._region_party_document("b0-fixture", party)
	if not _must(document.ok and bytes_to_var(Marshalls.base64_to_raw(document.payload.party)) == party, "B0_STABLE_PARTY"): return false
	var region: Dictionary = lab.capture_region_owner_state(_context())
	if not _must(region.ok, "B0_STABLE_REGION_CAPTURE: " + str(region)): return false
	var original: Dictionary = lab.terrain.site.duplicate(true)
	var linked: Dictionary = _linked_state()
	# B5: a steady link is admitted; the unsettled case here has a crosser in the channel (Q7 A).
	for identity: String in [boat_id, enemy_boat]: linked.vehicles[identity].naval.boarding_link.crosser_id = people[0]
	# Original record mutation only in this isolated fixture, no producer enabled.
	for identity: String in [boat_id, enemy_boat]: lab.terrain.site.vehicles[identity].naval = linked.vehicles[identity].naval.duplicate(true)
	if not _four_gates("BUSY"): return false
	lab.terrain.site.vehicles[boat_id].naval.boarding_link.version = 99
	if not _four_gates("CORRUPT_SAVE"): return false
	for identity: String in [boat_id, enemy_boat]: lab.terrain.site.vehicles[identity].naval = original.vehicles[identity].naval.duplicate(true)
	# Original live row is not yet in snapshot: Controller and Lab must see it.
	team.combat_units[0].boarding_position = _position(linked)
	var before: PackedByteArray = _live_bytes()
	var live_capture: Dictionary = controller._capture_for_save()
	var live_region: Dictionary = lab.capture_region_owner_state(_context())
	var live_pure: Dictionary = Store.save(lab.terrain, B0_GOOD)
	if not _must(not live_capture.ok and live_capture.code == "BUSY" and not live_region.ok and live_region.code == "BUSY" and not live_pure.ok and live_pure.code == "BUSY" and before == _live_bytes(), "B0_LIVE_ROW_BEFORE_SNAPSHOT_REPLACEMENT"): return false
	team.combat_units[0].erase("boarding_position")
	lab.terrain.site.armies[0].units[0].boarding_position = _position(linked)
	if not _four_gates("BUSY"): return false
	lab.terrain.site.armies[0].units[0].erase("boarding_position")
	var actions: SitePersonActions = controller.person_actions
	actions._jobs["b0-transient"] = {"kind": "boarding_cross"}
	before = _live_bytes()
	var job_capture: Dictionary = controller._capture_for_save()
	var job_region: Dictionary = lab.capture_region_owner_state(_context())
	var job_pure: Dictionary = Store.save(lab.terrain, B0_GOOD)
	if not _must(not job_capture.ok and job_capture.code == "BUSY" and not job_region.ok and job_region.code == "BUSY" and not job_pure.ok and job_pure.code == "BUSY" and before == _live_bytes(), "B0_UNSETTLED_ORIGINAL_JOB"): return false
	actions._jobs.erase("b0-transient")
	var legacy_job: Dictionary = {"kind": "ship_cross"}
	actions._jobs["b0-legacy"] = legacy_job
	if not _must(actions.boarding_save_guard().ok and not actions.save_guard().ok, "B0_ORIGINAL_CROSS_BUSY_UNCHANGED"): return false
	actions._jobs.erase("b0-legacy")
	var unknown: Dictionary = original.duplicate(true)
	unknown.vehicles[boat_id].naval.version = 99
	if not _bad_load("unknown_naval", unknown, "CORRUPT_SAVE"): return false
	if not _bad_load("unsupported_complete", linked, "BUSY"): return false
	var half: Dictionary = linked.duplicate(true)
	half.vehicles[enemy_boat].naval.erase("boarding_link")
	if not _bad_load("half", half, "CORRUPT_SAVE"): return false
	# Legacy empty metadata round-trips as itself, rather than being stripped.
	for identity: String in [boat_id, enemy_boat]: lab.terrain.site.vehicles[identity].naval.boarding_link = {} if identity == boat_id else null
	var empty_saved: Dictionary = Store.save(lab.terrain, B0_OUT + "/legacy_empty.json")
	var empty_loaded: Dictionary = Store.load_site(B0_OUT + "/legacy_empty.json")
	if not _must(empty_saved.ok and empty_loaded.ok and empty_loaded.data.site.vehicles[boat_id].naval.has("boarding_link") and empty_loaded.data.site.vehicles[boat_id].naval.boarding_link.is_empty(), "B0_LEGACY_EMPTY_ROUNDTRIP"): return false
	return true
