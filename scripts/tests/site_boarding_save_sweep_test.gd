extends "res://scripts/tests/site_boarding_crossing_finish_test.gd"
## B3R save-gate sweep: each save path refuses while a link is connected or a crossing is open,
## and accepts once the link is cleared. Test only; no gate is added or lifted.
const StoreB3S6 = preload("res://scripts/terrain_lab/site_store.gd")
const ContractB3S6 = preload("res://scripts/terrain_lab/site_boarding_link_contract.gd")

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	if not _must(DisplayServer.get_name() == "headless", "B3S6_CANONICAL_HEADLESS"): return
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for owner: TerrainArmy in lab.combat_armies: owner.set_process(false)
	if not _fixture() or not _cases_b3s6(): return
	print("SITE_BOARDING_B3S6_PASS: " + get_script().resource_path)
	await _cleanup(0)

## Every save path returns the expected result and writes nothing.
func _paths_b3s6(path: String, busy: bool) -> bool:
	var vehicles: Variant = lab.site_controller.vehicles
	var data_guard: Dictionary = ContractB3S6.data_save_guard(lab.terrain)
	var capture: Dictionary = lab.site_controller._capture_for_save()
	var vehicle_guard: Dictionary = vehicles.boarding_save_guard()
	if busy:
		if not _must(data_guard.get("code", "") == "BUSY" and capture.get("code", "") == "BUSY" and vehicle_guard.get("code", "") == "BUSY", "B3S6_BUSY_PATHS: " + str([data_guard, capture, vehicle_guard])): return false
		var stored: Dictionary = StoreB3S6.save(lab.terrain, path, null, false, {}, true)
		if not _must(stored.get("code", "") == "BUSY", "B3S6_STORE_BUSY: " + str(stored)): return false
	else:
		if not _must(data_guard.ok and capture.ok and vehicle_guard.ok, "B3S6_CLEAR_PATHS_PASS"): return false
	return _must(not FileAccess.file_exists(path), "B3S6_NOTHING_WRITTEN")

func _cases_b3s6() -> bool:
	var vehicles: Variant = lab.site_controller.vehicles
	var actions: Variant = lab.site_controller.person_actions
	var aboard: int = people[0]
	var path: String = "user://b3s6_refused_save.json"
	if not _must(lab.terrain.has_meta(&"site_garrison_lab"), "B3S6_PREMISE_GARRISON_META"): return false
	# Legacy: no link, no job.
	if not _paths_b3s6(path, false): return false
	# Connected link with a crossing open: refuse everywhere.
	if not _must(_link_live_b3(), "B3S6_PREMISE_LINK"): return false
	var began: Dictionary = actions.begin_boarding_cross(aboard, enemy_boat, aboard)
	if not _must(began.ok, "B3S6_BEGIN: " + str(began)): return false
	if not _paths_b3s6(path, true): return false
	# Cancel: entries close, the crossing is still open, so every path still refuses.
	actions.advance_ship_jobs(0.5)
	if not _must(actions.cancel(aboard).ok and not actions._jobs.is_empty(), "B3S6_CANCEL_KEEPS_CROSS"): return false
	if not _paths_b3s6(path, true): return false
	# The crossing finishes, the link clears, and the save paths pass again.
	if not _must(_settle_b3(actions), "B3S6_CROSS_SETTLES: " + _state_b3(actions)): return false
	if not _must(bool(last_b3.get("ok", false)) and str(vehicles.ship_for_person(aboard).id) == enemy_boat, "B3S6_CROSS_LANDED: result=" + str(last_b3) + " on=" + str(vehicles.ship_for_person(aboard).id)): return false
	if not _must(_cleared_b3(vehicles.records()), "B3S6_LINK_CLEARED_ON_EXIT: " + _naval_b3(vehicles.records())): return false
	if not _paths_b3s6(path, false): return false
	# Sink during a fresh crossing. Direction comes from where the person is now, not from a fixed order.
	if not _must(_link_live_b3(), "B3S6_PREMISE_LINK_AGAIN"): return false
	var from_hull: String = str(vehicles.ship_for_person(aboard).id)
	var to_hull: String = boat_id if from_hull == enemy_boat else enemy_boat
	began = actions.begin_boarding_cross(aboard, to_hull, aboard)
	if not _must(began.ok, "B3S6_SINK_BEGIN from=" + from_hull + " to=" + to_hull + ": " + str(began)): return false
	var live: Dictionary = vehicles.records()
	live[to_hull].naval.state = "wrecked"
	live[to_hull].naval.hp = 0.0
	if not _must(_settle_b3(actions), "B3S6_SINK_SETTLES: " + _state_b3(actions)): return false
	if not _must(_cleared_b3(live), "B3S6_SINK_CLEARED: " + _naval_b3(live)): return false
	if not _paths_b3s6(path, false): return false
	var content: Dictionary = {"vehicles": vehicles.records().duplicate(true), "actors": {}, "armies": [], "ground_loot": {}}
	return _must(ContractB3S6.save_guard(content).ok, "B3S6_PARTY_COPY_CLEAR")
