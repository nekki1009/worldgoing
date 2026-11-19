extends SceneTree

const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Ship = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
const OUT := "res://output/site_ship_implementation_20261003/json_contract"
const GOOD := OUT + "/generated_ship.json"
const ROUTED := OUT + "/generated_ship_routed.json"
const EMPTY_DRIVER := OUT + "/generated_ship_empty_dead_operator.json"

var deadline := 0
var lab: TerrainLab
var team: TerrainArmy
var people: Array[int] = []
var boat_id := ""

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 90000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("Generated ship JSON contract deadline")
		quit(1)
	return false

func _must(condition: bool, message: String) -> bool:
	if condition: return true
	push_error(message)
	quit(1)
	return false

func _shore_cluster(data: TerrainData, shore: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var pending: Array[Vector2i] = [shore]
	var seen := {shore: true}
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_front()
		if lab.character.occupies_cell(cell) or lab.npc.occupies_cell(cell): continue
		result.append(cell)
		if result.size() == 4: return result
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cell + direction
			if not seen.has(next) and data.can_step(cell, next) and next.distance_to(shore) <= 5.0:
				seen[next] = true
				pending.append(next)
	return []

func _dock(data: TerrainData) -> Dictionary:
	for y in range(4, data.size.y - 4):
		for x in range(4, data.size.x - 4):
			var anchor := Vector2i(x, y)
			if not data.can_navigate_water(anchor): continue
			for facing: Vector2i in TerrainData.DIRECTIONS:
				if not data.can_place_water_vehicle(Ship.footprint("ferry", anchor, facing)): continue
				if not data.can_place_water_vehicle(Ship.swept_footprint("ferry", anchor, facing, anchor + facing, facing)): continue
				for shore: Vector2i in Ship.boarding_cells("ferry", anchor, facing):
					if not data.is_walkable(shore) or absi(data.effective_height(shore) - data.effective_height(anchor)) > 1: continue
					var cells := _shore_cluster(data, shore)
					if cells.size() == 4: return {"anchor": anchor, "facing": facing, "shore": shore, "cells": cells}
	return {}

func _finish_job(identity: int) -> bool:
	var actions: SitePersonActions = lab.site_controller.person_actions
	if not _must(actions.is_busy(identity), "Expected original ship job"): return false
	var job: Dictionary = actions._jobs[str(identity)]
	actions.advance_ship_jobs(maxf(0.01, float(job.duration) - float(job.elapsed) + 0.01))
	actions.settle_after_contacts()
	return _must(not actions.is_busy(identity), "Original ship job did not commit")

func _walk(index: int, shore: Vector2i) -> bool:
	if team.cells[index] == shore: return true
	var blocked := func(cell: Vector2i) -> bool:
		return team._cell_owners.has(cell) and int(team._cell_owners[cell]) != index or lab.character.occupies_cell(cell) or lab.npc.occupies_cell(cell)
	var path := lab.terrain.path_between(team.cells[index], shore, blocked)
	if not _must(not path.is_empty(), "Original natural shore path missing"): return false
	for next: Vector2i in path:
		if next == team.cells[index]: continue
		if not _must(team._reserve_combat_step(index, next), "Original shore step rejected"): return false
		team.prepare_combat(float(team.move_duration[index]) + 0.01)
		if not _must(team.cells[index] == next, "Original shore person did not arrive"): return false
	return true

func _bad_candidate(name: String, change: Callable, expected_code: String = "") -> bool:
	# Re-sign a well-formed JSON envelope: rejection must come from the semantic
	# candidate validator rather than an intentionally broken checksum.
	var good_bytes := FileAccess.get_file_as_string(GOOD)
	var wrapper: Dictionary = JSON.parse_string(good_bytes)
	var payload: Dictionary = JSON.parse_string(wrapper.payload)
	change.call(payload.state)
	var body := JSON.stringify(payload, "", true, true)
	var path := OUT + "/bad_%s.json" % name
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not _must(file != null, "Cannot write isolated corrupt candidate"): return false
	file.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}))
	file.close()
	var original_owner := lab.terrain
	var original_state := JSON.stringify(lab.terrain.site, "", true, true)
	var result: Dictionary = lab.site_controller.load_from(path)
	if not _must(not result.ok, "Corrupt candidate unexpectedly accepted: %s" % name): return false
	if not expected_code.is_empty() and not _must(str(result.code) == expected_code,
		"Candidate did not fail through its semantic validator: %s: %s" % [name, str(result)]): return false
	if not _must(is_same(original_owner, lab.terrain) and JSON.stringify(lab.terrain.site, "", true, true) == original_state,
		"Rejected candidate changed original live owner/state: %s" % name): return false
	return _must(FileAccess.get_file_as_string(GOOD) == good_bytes, "Rejected candidate overwrote the good JSON")

func _routed_half_step_roundtrip(fingerprint: String, load_before: float, saved_ko: float, saved_loot: Dictionary, personal: Dictionary) -> bool:
	var controller: SiteController = lab.site_controller
	var boat: Dictionary = controller.vehicles.records()[boat_id]
	var original_move: Dictionary = boat.move.duplicate(true)
	var good_bytes := FileAccess.get_file_as_string(GOOD)
	if not _must(not original_move.is_empty(), "Routed test needs the original loaded committed half-step"): return false
	var entry: Dictionary = lab.terrain.site.team_supply[str(team.team_id)]
	# Explicit collapse input on the existing original sustain owner. The original
	# Army entry point creates all retreat/stop state; no saved snapshot is forged.
	entry.sustain.routed = true
	entry.sustain.morale = 0.0
	var routed: Dictionary = team.begin_morale_retreat()
	if not _must(routed.ok and team.combat_order == TerrainArmy.CombatOrder.RETREAT and bool(boat.stop_pending) and boat.command.is_empty(),
		"Original collapse did not stop future sailing: %s" % str(routed)): return false
	if not _must(boat.move == original_move, "Original collapse rolled back or rewrote its committed ship step"): return false
	team._update_morale_retreat()
	var test_delta := minf(0.01, (float(original_move.duration) - float(original_move.elapsed)) * 0.5)
	if not _must(test_delta > 0.0, "Routed test has no remaining committed action time"): return false
	controller.vehicles.update_ships(test_delta)
	var expected_move: Dictionary = original_move.duplicate(true)
	expected_move.elapsed = float(original_move.elapsed) + test_delta
	if not _must(boat.move == expected_move and bool(boat.stop_pending) and boat.command.is_empty(),
		"Routed update changed the source, target, duration or intended stop"): return false
	for index in [0, 1, 3]:
		if not _must(controller.vehicles.is_embarked(people[index]) and team.moving_to[index] == TerrainArmy.INVALID_CELL and not team._retreat_paths.has(people[index]),
			"Routed original passenger acquired a historical ground retreat path"): return false
	var delta_file := FileAccess.open(OUT + "/routed_test_delta.json", FileAccess.WRITE)
	if not _must(delta_file != null, "Cannot preserve the isolated routed test_delta evidence"): return false
	delta_file.store_string(JSON.stringify({"test_delta": test_delta, "elapsed_before": float(original_move.elapsed),
		"elapsed_after": float(boat.move.elapsed), "destination": int(boat.move.cell), "duration": float(boat.move.duration)}, "\t", true, true))
	delta_file.close()
	print("SITE_SHIP_JSON_ROUTED_TEST_DELTA:action_seconds=%.9f" % test_delta)
	var routed_supply: Dictionary = lab.terrain.site.team_supply.duplicate(true)
	# Preserve every retreat key/value while matching the JSON number boundary.
	var retreat: Dictionary = JSON.parse_string(JSON.stringify(team._retreat_resolution, "", true, true))
	var saved: Dictionary = controller.save_to(ROUTED)
	if not _must(saved.ok, "True routed Controller save rejected: %s" % str(saved)): return false
	controller.save_path = ROUTED # Same isolated file: no unrelated archive on load.
	var loaded: Dictionary = controller.load_from(ROUTED)
	if not _must(loaded.ok, "True routed Controller atomic load rejected: %s" % str(loaded)): return false
	team = lab.army
	controller = lab.site_controller
	boat = controller.vehicles.records()[boat_id]
	if not _must(lab.terrain.fingerprint() == fingerprint and boat.move == expected_move and bool(boat.stop_pending) and boat.command.is_empty(),
		"Routed JSON changed original terrain, committed step or stop state"): return false
	if not _must(team.combat_order == TerrainArmy.CombatOrder.RETREAT and team._retreat_resolution == retreat and team.is_sustain_routed(),
		"Routed JSON lost the original sustain/Army retreat relationship"): return false
	if not _must(controller.vehicles.ship_people(boat).size() == 3 and is_equal_approx(controller.vehicles.ship_load(boat_id), load_before) and float(team.combat_hot_get(1, &"ko", 0.0)) == saved_ko,
		"Routed JSON changed original living/KO passenger N/Q"): return false
	if not _must(lab.terrain.site.ground_loot == saved_loot and lab.terrain.site.team_supply == routed_supply and lab.terrain.site.person_supply[str(people[3])] == personal,
		"Routed JSON changed local remains, location stock or original retirement history"): return false
	for index in range(4):
		if not _must(team.combat_identity(index) == people[index], "Routed JSON replaced an original person ID"): return false
	for index in [0, 1, 3]:
		if not _must(team.moving_to[index] == TerrainArmy.INVALID_CELL and not team._cell_owners.values().has(index) and not team._retreat_paths.has(people[index]),
			"Loaded routed passenger acquired a ground claim or retreat path"): return false
	controller.vehicles.update_ships(float(expected_move.duration) - float(expected_move.elapsed) + 0.01)
	if not _must(boat.move.is_empty() and int(boat.cell) == int(expected_move.cell) and boat.facing == expected_move.facing and not bool(boat.stop_pending) and boat.command.is_empty(),
		"Loaded routed committed step did not reach its original endpoint exactly once"): return false
	var completed: Dictionary = boat.duplicate(true)
	controller.vehicles.update_ships(0.25)
	team._update_morale_retreat()
	if not _must(boat == completed and is_equal_approx(controller.vehicles.ship_load(boat_id), load_before), "Routed boat continued after its original committed step"): return false
	for index in [0, 1, 3]:
		if not _must(team.moving_to[index] == TerrainArmy.INVALID_CELL and not team._retreat_paths.has(people[index]), "Stopped routed passenger began a historical land retreat"): return false
	if not _must(FileAccess.get_file_as_string(GOOD) == good_bytes and lab.terrain.fingerprint() == fingerprint, "Routed test changed the original good file or generated terrain"): return false
	# Restore the genuine initial file so its existing ordinary completion/history
	# acceptance below still runs independently of this additional routed case.
	controller.save_path = GOOD
	var restored: Dictionary = controller.load_from(GOOD)
	if not _must(restored.ok, "Cannot restore original good half-step after isolated routed case"): return false
	team = lab.army
	controller = lab.site_controller
	if not _must(controller.vehicles.records()[boat_id].move == original_move and not team.is_sustain_routed(), "Routed case did not restore the independent original half-step"): return false
	print("SITE_SHIP_JSON_ROUTED_HALF_STEP_PASS")
	return true

func _empty_dead_operator_roundtrip(fingerprint: String, load_before: float, saved_ko: float, saved_loot: Dictionary, personal: Dictionary) -> bool:
	var controller: SiteController = lab.site_controller
	var vehicles: SiteVehicleTransport = controller.vehicles
	var boat: Dictionary = vehicles.records()[boat_id]
	var good_move: Dictionary = boat.move.duplicate(true)
	var good_bytes := FileAccess.get_file_as_string(GOOD)
	# Original transfer forbids a moving hull. Finish this baseline step and stop,
	# then transfer while parked; reverse retraces the same validated water sweep.
	if not _must(not good_move.is_empty(), "EMPTY driver test needs the genuine good half-step"): return false
	var stopped: Dictionary = vehicles.ship_order(boat_id, "stop", TerrainArmy.INVALID_CELL, people[0], true)
	if not _must(stopped.ok, "Original stop before EMPTY transfer rejected: %s" % str(stopped)): return false
	vehicles.update_ships(float(good_move.duration) - float(good_move.elapsed) + 0.01)
	if not _must(boat.move.is_empty() and int(boat.cell) == int(good_move.cell), "Original parked transfer preparation did not finish its committed step"): return false
	var driver: Dictionary = team.combat_units[0]
	var driver_items: Array = driver.item_state.item_ids.duplicate()
	var driver_cargo: Dictionary = driver.cargo.duplicate(true)
	if not _must(not driver_items.is_empty(), "EMPTY driver fixture must transfer real original belongings"): return false
	var emptied: Dictionary = vehicles.transfer("person:%d" % people[0], boat_id, driver_cargo, driver_items,
		int(driver.item_state.version), int(boat.holder.version), people[0], true)
	if not _must(emptied.ok, "Original parked EMPTY driver transfer rejected: %s" % str(emptied)): return false
	controller.equipment_changed(people[0])
	if not _must(driver.cargo.is_empty() and driver.item_state.item_ids.is_empty() and driver.item_state.equipped.is_empty()
		and float(controller._personal_opened_food(people[0]).get("open_rations", 0.0)) == 0.0 and is_equal_approx(vehicles.ship_load(boat_id), load_before),
		"Original driver-to-boat transfer did not produce EMPTY with conserved Q"): return false
	for item_id: String in driver_items:
		if not _must(boat.holder.item_ids.has(item_id) and str(lab.terrain.site.item_records[item_id].holder) == str(boat.holder.holder), "Original driver item did not reach the boat holder"): return false
	var reversed: Dictionary = vehicles.ship_order(boat_id, "reverse", TerrainArmy.INVALID_CELL, people[0], true)
	if not _must(reversed.ok, "Original reverse over the proven water sweep rejected: %s" % str(reversed)): return false
	vehicles.update_ships(float(boat.move.duration) * 0.25)
	var committed: Dictionary = boat.move.duplicate(true)
	var anchor := int(boat.cell)
	var loot_next := int(lab.terrain.site.next_loot)
	var boat_items: Array = boat.holder.item_ids.duplicate()
	var boat_cargo: Dictionary = boat.cargo.duplicate(true)
	var supplies: Dictionary = lab.terrain.site.team_supply.duplicate(true)
	if not _must(int(committed.cell) == int(good_move.from_cell) and float(committed.elapsed) > 0.0 and float(committed.elapsed) < float(committed.duration), "EMPTY driver death needs a genuine reverse half-step to the original source"): return false
	team.apply_unit_contact(0, {"result": {"hp": 10000.0, "stun": 0.0, "guard_break": false}, "shield": false})
	controller.settle_person_deaths(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"]) + 0.5)
	team.settle_combat_command()
	if not _must(driver.get("loot_settled", false) == true and driver.get("ship_death_settled", false) == true and str(driver.get("remains_id", "")) == ""
		and not driver.has("embarked_vehicle_id") and not driver.has("berth_id"), "Original EMPTY driver death retained a berth or invented remains"): return false
	if not _must(int(lab.terrain.site.next_loot) == loot_next and lab.terrain.site.ground_loot == saved_loot and boat.holder.item_ids == boat_items and boat.cargo == boat_cargo
		and vehicles.ship_people(boat).size() == 2 and is_equal_approx(vehicles.ship_load(boat_id), load_before), "Original EMPTY driver death changed N/Q or allocated an extra container"): return false
	if not _must(boat.move == committed and int(boat.cell) == anchor and int(boat.operator_id) == people[0] and bool(boat.stop_pending) and boat.command.is_empty()
		and float(team.combat_hot_get(1, &"ko", 0.0)) == saved_ko, "EMPTY death/command settlement rewrote the committed step, historical driver or KO clock"): return false
	lab.terrain.site.combat_left = 0.0 # Same original contact-settlement save contract as GOOD.
	var saved: Dictionary = controller.save_to(EMPTY_DRIVER)
	if not _must(saved.ok, "True EMPTY historical driver Controller save rejected: %s" % str(saved)): return false
	var candidate: Dictionary = Store.load_site(EMPTY_DRIVER)
	if not _must(candidate.ok and candidate.data.fingerprint() == fingerprint, "True EMPTY historical driver Store reconstruction rejected: %s" % str(candidate)): return false
	controller.save_path = EMPTY_DRIVER
	var loaded: Dictionary = controller.load_from(EMPTY_DRIVER)
	if not _must(loaded.ok, "True EMPTY historical driver atomic load rejected: %s" % str(loaded)): return false
	team = lab.army
	controller = lab.site_controller
	vehicles = controller.vehicles
	boat = vehicles.records()[boat_id]
	driver = team.combat_units[0]
	if not _must(lab.terrain.fingerprint() == fingerprint and boat.move == committed and int(boat.cell) == anchor and int(boat.operator_id) == people[0]
		and bool(boat.stop_pending) and boat.command.is_empty(), "EMPTY driver JSON changed the historical operator/source/target/sweep/time"): return false
	if not _must(driver.get("loot_settled", false) == true and driver.get("ship_death_settled", false) == true and str(driver.get("remains_id", "")) == ""
		and not driver.has("embarked_vehicle_id") and not driver.has("berth_id") and driver.cargo.is_empty() and driver.item_state.item_ids.is_empty() and driver.item_state.equipped.is_empty(), "Loaded EMPTY dead driver lost its settled original identity/holder relationship"): return false
	if not _must(vehicles.ship_people(boat).size() == 2 and is_equal_approx(vehicles.ship_load(boat_id), load_before) and float(team.combat_hot_get(1, &"ko", 0.0)) == saved_ko
		and boat.holder.item_ids == boat_items and boat.cargo == boat_cargo and lab.terrain.site.ground_loot == saved_loot and lab.terrain.site.team_supply == supplies
		and lab.terrain.site.person_supply[str(people[3])] == personal, "EMPTY driver JSON changed N/Q, belongings, local remains, food or retirement history"): return false
	for index in range(4):
		if not _must(team.combat_identity(index) == people[index], "EMPTY driver JSON replaced an original person ID"): return false
	vehicles.update_ships(float(committed.duration) - float(committed.elapsed) + 0.01)
	if not _must(boat.move.is_empty() and int(boat.cell) == int(committed.cell) and boat.facing == committed.facing and int(boat.operator_id) == 0 and not bool(boat.stop_pending) and boat.command.is_empty(), "Loaded EMPTY dead-driver step did not finish once and clear its historical operator"): return false
	var completed: Dictionary = boat.duplicate(true)
	vehicles.update_ships(0.25)
	if not _must(boat == completed and is_equal_approx(vehicles.ship_load(boat_id), load_before) and FileAccess.get_file_as_string(GOOD) == good_bytes, "EMPTY dead-driver boat continued or changed Q/the original good file"): return false
	controller.save_path = GOOD
	var restored: Dictionary = controller.load_from(GOOD)
	if not _must(restored.ok, "Cannot restore original GOOD after isolated EMPTY driver JSON case"): return false
	team = lab.army
	controller = lab.site_controller
	boat = controller.vehicles.records()[boat_id]
	if not _must(boat.move == good_move and int(boat.operator_id) == people[0] and float(team.combat_hot_get(0, &"hp", 0.0)) > 0.0
		and controller.vehicles.ship_people(boat).size() == 3 and is_equal_approx(controller.vehicles.ship_load(boat_id), load_before)
		and lab.terrain.fingerprint() == fingerprint and lab.terrain.site.ground_loot == saved_loot and lab.terrain.site.person_supply[str(people[3])] == personal,
		"EMPTY driver case did not restore the independent GOOD half-step/history"): return false
	print("SITE_SHIP_JSON_EMPTY_DEAD_OPERATOR_HALF_STEP_PASS")
	return true

func _diagnose_rejected_save() -> void:
	# Save the exact Controller-captured candidate and test source on rejection.
	# The ignored helper only logs the original predicate's false-return line.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var captured := FileAccess.open(OUT + "/rejected_captured_state.json", FileAccess.WRITE)
	if captured != null:
		captured.store_string(JSON.stringify(lab.terrain.site, "\t", true, true))
		captured.close()
	var task_copy := FileAccess.open(OUT + "/rejected_test_source.gd.txt", FileAccess.WRITE)
	if task_copy != null:
		task_copy.store_string(FileAccess.get_file_as_string("res://scripts/tests/site_ship_json_test.gd"))
		task_copy.close()
	var probe: Script = load("res://output/site_ship_implementation_20261003/army_validator_probe.gd")
	if probe == null: return
	var state: Dictionary = lab.terrain.site
	for snapshot: Dictionary in state.armies:
		var actor: Dictionary = state.actors.get("player", {})
		if not snapshot.get("player_member", {}).is_empty():
			actor = {}
			for candidate: Dictionary in state.actors.values():
				if int(candidate.get("person_id", 0)) == int(snapshot.player_member.id): actor = candidate
		var original: bool = TerrainArmy.valid_combat_state(snapshot, lab.terrain, actor, state)
		var diagnosed: bool = probe.diagnose_combat_state(snapshot, lab.terrain, actor, state)
		print("SITE_SHIP_JSON_ARMY_DIAGNOSTIC:team=%d:original=%s:probe=%s:state=%s" % [int(snapshot.team_id), str(original), str(diagnosed), OUT + "/rejected_captured_state.json"])

func _run() -> void:
	if not _must(DisplayServer.get_name() == "headless", "This JSON contract uses a headless verifier"): return
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for army: TerrainArmy in lab.combat_armies: army.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	var dock := {}
	# Every candidate is generated by the real source. No heights, surface flags,
	# resources or water IDs are overwritten to make a saved map look navigable.
	for seed_value: int in [17, 12345, 98761]:
		var data := TerrainGenerator.generate(TerrainPreset.Kind.COASTAL_CLIFF, seed_value, {"max_height": 1})
		Env.initialize(data, "ship_json_%d" % seed_value)
		var bodies := {}
		for identity: int in data.water_body:
			if identity >= 0: bodies[identity] = true
		data.parameters.navigable_water_version = 1
		data.parameters.navigable_water_bodies = bodies.keys()
		lab.bind_terrain(data)
		lab.site_controller.set_process(false)
		lab.site_controller._auto_save_blocked = true
		dock = _dock(data)
		if not dock.is_empty(): break
	if not _must(not dock.is_empty(), "No genuine generated shoreline admits the ferry plus one committed step"): return
	var fingerprint := lab.terrain.fingerprint()
	var controller: SiteController = lab.site_controller
	controller.save_root = OUT
	controller.save_path = GOOD
	team = lab.army
	team.role = "logistics"
	team.team_id = lab._next_army_identity()
	team.roster_size = 4
	var cells: Array[Vector2i] = []
	cells.assign(dock.cells)
	if not _must(team.deploy_at(lab.terrain, lab.character, lab.npc, cells) and team.enable_combat(false, 0), "Original four-person deployment failed"): return
	lab.terrain.site.army_next_team = team.team_id + 1
	lab.terrain.site.army_trial_active = true
	for index in range(4):
		people.append(team.combat_identity(index))
		team.combat_units[index].logistics = true
	var enabled: Dictionary = controller.captivity_supply.enable_team(team)
	if not _must(enabled.ok, "Original team sustain enable failed: %s" % str(enabled)): return
	var entry: Dictionary = enabled.entry
	# Explicit original common-food/history fixture; conversion and transfer must
	# preserve it once. No test writes a second boat food total.
	entry.inventory.grain = 12
	entry.sustain.open_rations = 0.5
	if not _must(not entry.sustain.cohorts.is_empty(), "Original sustain has no cohort"): return
	for cohort: Dictionary in entry.sustain.cohorts:
		cohort.hunger = 123.0
		cohort.coverage = 0.75
		cohort.meal_until = minf(float(entry.sustain.at) + 600.0, (floorf(float(entry.sustain.at) / SiteSustain.MEAL) + 1.0) * SiteSustain.MEAL)
		cohort.bonus_paid = true
		cohort.bonus_pending = false
	var deployed: Dictionary = controller.vehicles.deploy_ship(team, "ferry", dock.anchor, dock.facing, true)
	if not _must(deployed.ok, "Generated water deployment rejected: %s" % str(deployed)): return
	boat_id = str(deployed.vehicle_id)
	for index in range(4):
		if not _walk(index, dock.shore): return
		var begun: Dictionary = controller.person_actions.begin_ship_board(people[index], boat_id, people[index], index, true)
		if not _must(begun.ok, "Natural shoreline boarding rejected: %s" % str(begun)) or not _finish_job(people[index]): return
	entry = lab.terrain.site.team_supply[str(team.team_id)]
	if not _must(int(entry.version) == 3 and int(entry.sustain.version) == 2 and not entry.has("inventory") and not entry.sustain.has("open_rations"), "Locations must be the unique physical common-food authority"): return
	var shore_key := "shore:%d" % lab.terrain.index(dock.shore)
	var ship_key := "vehicle:" + boat_id
	var supplied: Dictionary = controller.transfer_ship_supply(team, shore_key, ship_key, {"grain": 6}, 0.25, people[0], true)
	if not _must(supplied.ok, "Original shoreline food transfer rejected: %s" % str(supplied)): return
	var helm: Dictionary = controller.person_actions.begin_ship_helm(people[0], boat_id, people[0], true)
	if not _must(helm.ok, "Original helm qualification rejected") or not _finish_job(people[0]): return
	lab.terrain.site.controlled_person_id = people[3]
	if not _must(team.leave_row(people[3]).ok and not team.is_member(3), "Original aboard player retirement failed"): return
	var personal: Dictionary = lab.terrain.site.person_supply[str(people[3])].duplicate(true)
	if not _must(not personal.cohorts.is_empty(), "Retired person lost original meal history"): return
	lab.terrain.site.controlled_person_id = people[0]
	var load_before: float = controller.vehicles.ship_load(boat_id)
	team.apply_unit_contact(2, {"result": {"hp": 10000.0, "stun": 0.0, "guard_break": false}, "shield": false})
	controller.settle_person_deaths(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"]) + 0.5)
	if not _must(bool(team.combat_units[2].loot_settled) and bool(team.combat_units[2].ship_death_settled), "Original docked death did not settle locally"): return
	if not _must(is_equal_approx(controller.vehicles.ship_load(boat_id), load_before), "Death moved original Q outside its hull"): return
	var started: Dictionary = controller.vehicles.ship_order(boat_id, "forward", TerrainArmy.INVALID_CELL, people[0], true)
	if not _must(started.ok, "Real generated whole-hull step rejected: %s" % str(started)): return
	var boat: Dictionary = controller.vehicles.records()[boat_id]
	controller.vehicles.update_ships(float(boat.move.duration) * 0.25)
	team.apply_unit_contact(1, {"result": {"hp": 0.0, "stun": 1000.0, "guard_break": false}, "shield": false})
	var saved_move: Dictionary = boat.move.duplicate(true)
	var saved_ko := float(team.combat_hot_get(1, &"ko", 0.0))
	var saved_loot: Dictionary = lab.terrain.site.ground_loot.duplicate(true)
	var saved_supply: Dictionary = lab.terrain.site.team_supply.duplicate(true)
	# The formal TerrainLab tick settles original command presence after contacts.
	# This manual fixture must do the same without advancing either ship/KO clock.
	controller._capture_positions()
	if not TerrainArmy.valid_combat_state(lab.terrain.site.armies[0], lab.terrain, lab.terrain.site.actors.player, lab.terrain.site):
		_diagnose_rejected_save()
	team.settle_combat_command()
	if not _must(boat.move == saved_move and float(team.combat_hot_get(1, &"ko", 0.0)) == saved_ko,
		"Original command settlement advanced a committed ship/KO clock"): return
	lab.terrain.site.combat_left = 0.0 # Original save contract requires contact settlement/out of combat.
	var saved: Dictionary = controller.save_to(GOOD)
	if not saved.ok: _diagnose_rejected_save()
	if not _must(saved.ok, "True Controller JSON save rejected: %s" % str(saved)): return
	var candidate: Dictionary = Store.load_site(GOOD)
	if not _must(candidate.ok, "True generated Store reconstruction rejected: %s" % str(candidate)): return
	if not _must(candidate.data.fingerprint() == fingerprint, "JSON reconstruction changed original generated terrain arrays"): return
	var loaded: Dictionary = controller.load_from(GOOD)
	if not _must(loaded.ok, "True Controller atomic load rejected: %s" % str(loaded)): return
	team = lab.army
	controller = lab.site_controller
	boat = controller.vehicles.records()[boat_id]
	if not _must(boat.move == saved_move and not boat.move.is_empty() and int(boat.operator_id) == people[0], "Loaded half-step/operator changed"): return
	if not _must(controller.vehicles.ship_people(boat).size() == 3 and is_equal_approx(controller.vehicles.ship_load(boat_id), load_before), "Loaded original N/Q changed"): return
	if not _must(float(team.combat_hot_get(1, &"ko", 0.0)) == saved_ko and lab.terrain.site.ground_loot == saved_loot, "Loaded KO/local remains changed"): return
	if not _must(lab.terrain.site.team_supply == saved_supply and lab.terrain.site.person_supply[str(people[3])] == personal, "Loaded location stock or retirement history changed"): return
	for index in range(4):
		if not _must(team.combat_identity(index) == people[index], "JSON load replaced an original person ID"): return
		if index != 2 and not _must(not team._cell_owners.values().has(index), "Loaded passenger owns a historical shore claim"): return
	if not _must(not team.is_member(3) and str(team.combat_units[3].embarked_vehicle_id) == boat_id, "Loaded retired person lost their physical berth"): return
	if not _bad_candidate("berth", func(state: Dictionary) -> void: state.armies[0].units[1].berth_id = 0): return
	if not _bad_candidate("sweep", func(state: Dictionary) -> void: state.vehicles[boat_id].move.sweep.pop_back()): return
	if not _bad_candidate("capacity", func(state: Dictionary) -> void: state.vehicles[boat_id].cargo.grain = 81): return
	if not _bad_candidate("location", func(state: Dictionary) -> void:
		var stock: Dictionary = state.team_supply[str(team.team_id)].locations[ship_key]
		state.team_supply[str(team.team_id)].locations["vehicle:2147483646"] = stock
		state.team_supply[str(team.team_id)].locations.erase(ship_key)): return
	if not _bad_candidate("retirement", func(state: Dictionary) -> void: state.person_supply.erase(str(people[3]))): return
	if not _bad_candidate("fractional_destination", func(state: Dictionary) -> void: state.armies[0].units[1].destination = [-1.0, -1.5], "CORRUPT_SAVE"): return
	if not _bad_candidate("unknown_ship_definition_version", func(state: Dictionary) -> void: state.vehicles[boat_id].definition_version = Ship.VERSION + 1, "SAVE_VERSION"): return
	if not _empty_dead_operator_roundtrip(fingerprint, load_before, saved_ko, saved_loot, personal): return
	if not _routed_half_step_roundtrip(fingerprint, load_before, saved_ko, saved_loot, personal): return
	controller = lab.site_controller
	boat = controller.vehicles.records()[boat_id]
	var remaining := float(boat.move.duration) - float(boat.move.elapsed)
	controller.vehicles.update_ships(remaining + 0.01)
	if not _must(boat.move.is_empty() and is_equal_approx(controller.vehicles.ship_load(boat_id), load_before), "Loaded committed hull step did not complete once"): return
	if not _must(lab.terrain.fingerprint() == fingerprint, "Runtime ship completion changed generated terrain"): return
	print("SITE_SHIP_JSON_PASS")
	quit(0)
