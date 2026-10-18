extends "res://scripts/tests/site_boarding_commit_test.gd"
## B2S5: every save path that can see a boarding action refuses it, and the legacy
## path still passes. Test only: no production gate is added or lifted here.
const B2S5Contract = preload("res://scripts/terrain_lab/site_boarding_link_contract.gd")
const StoreB2S5 = preload("res://scripts/terrain_lab/site_store.gd")

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	if not _must(DisplayServer.get_name() == "headless", "B2S5_CANONICAL_HEADLESS"): return
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for owner: TerrainArmy in lab.combat_armies: owner.set_process(false)
	if not _fixture() or not _cases_b2s5(): return
	print("SITE_BOARDING_B2S5_PASS: " + get_script().resource_path)
	await _cleanup(0)

## Every path that can see the action, in one place. Each must refuse with BUSY and write nothing.
func _refuse_all_b2s5(path: String, expect_busy: bool) -> bool:
	var vehicles: Variant = lab.site_controller.vehicles
	var data_guard: Dictionary = B2S5Contract.data_save_guard(lab.terrain)
	var capture: Dictionary = lab.site_controller._capture_for_save()
	var stored: Dictionary = StoreB2S5.save(lab.terrain, path, null, false, {}, true)
	var vehicle_guard: Dictionary = vehicles.boarding_save_guard()
	if expect_busy:
		if not _must(data_guard.get("code", "") == "BUSY", "B2S5_DATA_GUARD_BUSY: " + str(data_guard)): return false
		if not _must(capture.get("code", "") == "BUSY", "B2S5_CAPTURE_BUSY: " + str(capture)): return false
		if not _must(stored.get("code", "") == "BUSY", "B2S5_STORE_BUSY: " + str(stored)): return false
		if not _must(vehicle_guard.get("code", "") == "BUSY", "B2S5_VEHICLE_GUARD_BUSY: " + str(vehicle_guard)): return false
	else:
		if not _must(data_guard.ok and capture.ok and stored.ok and vehicle_guard.ok, "B2S5_LEGACY_PASSES"): return false
	return _must(not FileAccess.file_exists(path), "B2S5_NOTHING_WRITTEN")

func _cases_b2s5() -> bool:
	var vehicles: Variant = lab.site_controller.vehicles
	var actions: Variant = lab.site_controller.person_actions
	var aboard: int = people[0]
	var path: String = "user://b2s5_refused_save.json"
	# The data guard only sees the job through the garrison metadata set by the lab.
	if not _must(lab.terrain.has_meta(&"site_garrison_lab"), "B2S5_PREMISE_GARRISON_META"): return false
	# Legacy: nothing open, every path passes.
	if not _refuse_all_b2s5(path, false): return false
	# Open hold: every path refuses; the held job is not yet a link.
	if not _begin_hold_b2s4(aboard): return false
	if not _refuse_all_b2s5(path, true): return false
	# Committed link: the job is gone, but the B0 gate keeps every path refusing until B5.
	actions.advance_ship_jobs(0.1)
	if not _must(actions._jobs.is_empty() and not _no_link_b2s3(), "B2S5_PREMISE_COMMITTED"): return false
	if not _refuse_all_b2s5(path, true): return false
	# Party-document writers call the same contract on a copy of the Site state.
	var content: Dictionary = {"vehicles": vehicles.records().duplicate(true), "actors": {}, "armies": [], "ground_loot": {}}
	if not _must(B2S5Contract.save_guard(content).code == "BUSY", "B2S5_PARTY_COPY_LINKED_BUSY"): return false
	# Same copy with the link removed (a legacy shape) passes again.
	for identity: String in content.vehicles:
		content.vehicles[identity].naval.erase("boarding_link")
		content.vehicles[identity].naval.version = 1
	return _must(B2S5Contract.save_guard(content).ok, "B2S5_PARTY_COPY_LEGACY_PASSES")
