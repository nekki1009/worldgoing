extends "res://scripts/tests/site_boarding_unlink_test.gd"
const B6Store = preload("res://scripts/terrain_lab/site_store.gd")
var b6_case: String = "source"

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--b6-case="): b6_case = argument.trim_prefix("--b6-case=")
	if not _setup_b6(): return
	if not _exit_case_b6(): return
	print("SITE_BOARDING_B6_EXIT_PASS case=" + b6_case)
	await _cleanup(0)

func _setup_b6() -> bool:
	if not _must(DisplayServer.get_name() == "headless", "B6_HEADLESS"): return false
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for owner: TerrainArmy in lab.combat_armies: owner.set_process(false)
	return _fixture()

# Override the fixture's dispatch shortcut: all new boarding uses the controlled original person.
func _board(index: int, berth: int) -> bool:
	if not _step_person(team, people[index], native_dock.shore): return false
	lab.terrain.site.controlled_person_id = people[index]
	var began: Dictionary = lab.site_controller.person_actions.begin_ship_board(people[index], boat_id, people[index], berth, false)
	if not _must(began.ok, "B6_PUBLIC_BOARD " + str(began)): return false
	return _job(people[index])

func _public_link_b6() -> bool:
	var actions: SitePersonActions = lab.site_controller.person_actions
	lab.terrain.site.controlled_person_id = people[0]
	var begun: Dictionary = actions.begin_boarding_link(people[0], boat_id, enemy_boat, people[0], false)
	if not _must(begun.ok, "B6_PUBLIC_LINK_BEGIN " + str(begun)): return false
	actions.advance_ship_jobs(B2Contract.LINK_ACTION_SECONDS)
	actions.advance_ship_jobs(0.1)
	var queried: Dictionary = lab.site_controller.vehicles.boarding_link_query(boat_id)
	return _must(queried.ok and queried.get("linked", false) and not actions.is_busy(people[0]), "B6_PUBLIC_LINK_COMMIT " + str(queried))

func _paid_point_b6(on_target: bool) -> bool:
	var vehicles: Variant = lab.site_controller.vehicles
	var actions: SitePersonActions = lab.site_controller.person_actions
	var begun: Dictionary = actions.begin_boarding_cross(people[0], enemy_boat, people[0], false)
	if not _must(begun.ok, "B6_PUBLIC_CROSS " + str(begun)): return false
	for attempt: int in range(4000):
		actions.advance_ship_jobs(0.01)
		var job: Dictionary = actions.job_for(people[0])
		if job.is_empty(): return _must(false, "B6_PAID_JOB_LOST")
		var point: Vector2 = vehicles._ship_job_point(job)
		var wanted: String = enemy_boat if on_target else boat_id
		if float(job.elapsed) > 0.0 and float(job.elapsed) < float(job.duration) and point.distance_to(point.round()) > 0.0001 and point.distance_to(job.path.back()) > 0.005 and vehicles._boarding_exit_supported(job, wanted, point): return true
	return _must(false, "B6_NO_FRACTIONAL_PAID_SUPPORTED_POINT")

func _exit_case_b6() -> bool:
	var vehicles: Variant = lab.site_controller.vehicles
	var actions: SitePersonActions = lab.site_controller.person_actions
	var controller: SiteController = lab.site_controller
	if b6_case in ["plain_death", "evac_death"]: return _plain_death_b6()
	if b6_case == "ko" and not _board(1, 1): return false
	if not _public_link_b6(): return false
	if not _paid_point_b6(b6_case in ["target", "late", "death"]): return false
	var original: Dictionary = team.combat_units[0]
	var holder: Dictionary = original.item_state
	var cargo: PackedByteArray = var_to_bytes(original.cargo)
	var item_count: int = lab.terrain.site.item_records.size()
	var before: Vector2 = vehicles.ship_person_ground(people[0])
	var paid: Dictionary = actions.job_for(people[0])
	var speed: float = float(paid.speed)
	if not _must(vehicles.boarding_save_guard().code == "BUSY", "B6_OPEN_JOB_SAVE_BUSY"): return false
	if not _busy_save_b6(): return false
	if b6_case == "death":
		team.apply_unit_contact(0, {"environmental": true, "shield": false, "result": {"hp": float(team.combat_hot_get(0, &"hp")) + 1.0, "stun": 0.0, "guard_break": false}})
		# Explicit deletion fault after a real paid crossing; never construct a link or job.
		vehicles.records().erase(enemy_boat)
		vehicles.records().erase(boat_id)
		actions.advance_ship_jobs(0.01)
		actions.settle_after_contacts()
		controller.settle_person_deaths(100.0)
		if not _must(float(team.combat_hot_get(0, &"hp")) <= 0.0 and original.get("loot_settled", false), "B6_REAL_DEATH_SETTLED_AFTER_BOTH_DELETED"): return false
		var remains: Dictionary = lab.terrain.site.ground_loot.get(str(original.get("remains_id", "")), {})
		var location: Dictionary = {"ship_world_version": remains.get("ship_world_version"), "world_point": remains.get("world_point")}
		var checked: Dictionary = B6Store._validate_ship_loot_location(lab.terrain, lab.terrain.site, str(original.get("remains_id", "")), remains)
		if not _must(checked.ok and Runtime.valid_ship_loot_location(lab.terrain, location) and vehicles.ship_loot_ground(remains).distance_to(before) < 0.00001 and team.combat_ground(0).distance_to(before) < 0.00001 and is_same(holder, original.item_state) and var_to_bytes(remains.cargo) == cargo and lab.terrain.site.item_records.size() == item_count, "B6_ACTUAL_DEATH_BODY_LOOT_CLOSURE " + str(checked)): return false
		return _settled_save_b6(str(original.remains_id), before)
	var lost: String = boat_id if b6_case in ["target", "late"] else enemy_boat
	var damage: Dictionary = Runtime.damage_ship_vehicle(lab.terrain, lost, Ship.hull_hp("ferry"))
	if not _must(damage.ok, "B6_REAL_HULL_DAMAGE " + str(damage)): return false
	vehicles.update_ships(0.001)
	if not _must(vehicles.ship_person_ground(people[0]).distance_to(before) < 0.00001, "B6_NO_ZERO_TIME_RELOCATION"): return false
	if b6_case == "both":
		var second: Dictionary = Runtime.damage_ship_vehicle(lab.terrain, boat_id, Ship.hull_hp("ferry"))
		if not _must(second.ok, "B6_SECOND_REAL_HULL_DAMAGE"): return false
		vehicles.update_ships(0.001)
	if b6_case == "ko":
		team.apply_unit_contact(0, {"environmental": true, "shield": false, "result": {"hp": 0.0, "stun": 10000.0, "guard_break": true}})
		if not _must(float(team.combat_hot_get(0, &"ko")) > 0.0, "B6_REAL_CONTACT_KO"): return false
		var ko_point: Vector2 = vehicles.ship_person_ground(people[0])
		for attempt: int in range(4):
			actions.advance_ship_jobs(0.1)
			actions.settle_after_contacts()
		if not _must(float(team.combat_hot_get(0, &"hp")) > 0.0 and vehicles.ship_person_ground(people[0]).distance_to(ko_point) < 0.00001 and actions.is_busy(people[0]) and vehicles.boarding_save_guard().code == "BUSY", "B6_SUPPORTED_KO_NEITHER_WALKS_NOR_DIES"): return false
		if not _busy_save_b6(): return false
		var rescued: bool = team.start_unit_rescue(1, 0)
		if not _must(rescued, "B6_ORIGINAL_RESCUE_QUALIFICATION_RETAINED"): return false
		for attempt: int in range(600):
			team.prepare_combat(0.1, 0.1)
			actions.advance_ship_jobs(0.1)
			actions.settle_after_contacts()
			if team.combat_can_act(0): break
		if not _must(team.combat_can_act(0), "B6_ORIGINAL_RESCUE_RECOVERS_BEFORE_WALKOUT"): return false
	if b6_case == "cancel":
		var cancel_result: Dictionary = actions.cancel(people[0])
		if not _must(cancel_result.ok and actions.is_busy(people[0]), "B6_CANCEL_RETAINS_COMMITTED_EXIT"): return false
	var previous: Vector2 = vehicles.ship_person_ground(people[0])
	for attempt: int in range(6000):
		if Time.get_ticks_msec() > deadline: return _must(false, "B6_EXIT_DEADLINE")
		actions.advance_ship_jobs(0.01)
		var current: Vector2 = vehicles.ship_person_ground(people[0])
		# Vector2 is float32: at |coordinate| ~1300 px one ulp is ~1.2e-4 px, so the slack is 1e-3 px (about 8 ulp).
		if not _must(current.distance_to(previous) <= speed * 0.01 * TerrainRenderer.CELL_PIXELS + 0.001, "B6_ORIGINAL_PAID_LEG_NO_TELEPORT attempt=%d case=%s previous=%s current=%s distance=%s bound=%s" % [attempt, b6_case, previous, current, current.distance_to(previous), speed * 0.01 * TerrainRenderer.CELL_PIXELS + 0.001]): return false
		previous = current
		actions.settle_after_contacts()
		if b6_case == "late" and attempt == 1:
			var late: Dictionary = Runtime.damage_ship_vehicle(lab.terrain, enemy_boat, Ship.hull_hp("ferry"))
			if not _must(late.ok, "B6_LATE_ENDPOINT_LOSS"): return false
			vehicles.update_ships(0.001)
		if not actions.is_busy(people[0]): break
	if not _must(not actions.is_busy(people[0]), "B6_EXIT_EVENTUALLY_SETTLES"): return false
	return _must(is_same(original, team.combat_units[0]) and is_same(holder, original.item_state) and var_to_bytes(original.cargo) == cargo and int(original.person_id) == people[0] and float(team.combat_hot_get(0, &"hp")) > 0.0, "B6_ORIGINAL_PERSON_ID_ITEMS_CARGO_SURVIVE")

func _plain_death_b6() -> bool:
	var vehicles: Variant = lab.site_controller.vehicles
	var actions: SitePersonActions = lab.site_controller.person_actions
	if b6_case == "plain_death":
		var person: Dictionary = vehicles.ship_person(people[0])
		var source: Dictionary = vehicles.records()[boat_id]
		var target: Dictionary = vehicles.records()[enemy_boat]
		var route: Dictionary = vehicles._link_cross_route(people[0], source, target, -1, person)
		if not _must(route.ok and route.path.size() >= 2, "B6_PLAIN_ORIGINAL_DECK_ROUTE"): return false
		var edge: Vector2 = route.path[route.path.size() - 2]
		var local: Vector2 = Ship.local_from_world(lab.terrain.cell_from_index(int(source.cell)), Vector2i(int(source.facing[0]), int(source.facing[1])), edge)
		var walk: Dictionary = actions.begin_ship_walk(people[0], local, people[0], false)
		if not _must(walk.ok, "B6_PLAIN_PUBLIC_DECK_WALK " + str(walk)): return false
		if not _job(people[0]): return false
		var cross: Dictionary = actions.begin_ship_cross(people[0], enemy_boat, people[0], int(route.berth_id), false)
		if not _must(cross.ok, "B6_PLAIN_PUBLIC_CROSS " + str(cross)): return false
	else:
		var loss: Dictionary = Runtime.damage_ship_vehicle(lab.terrain, boat_id, Ship.hull_hp("ferry"))
		if not _must(loss.ok, "B6_EVAC_REAL_WRECK"): return false
		vehicles.update_ships(0.001)
		if not _must(str(actions.job_for(people[0]).get("kind", "")) == "ship_evac", "B6_ORIGINAL_WATER_OWNER_STARTED_EVAC"): return false
	actions.advance_ship_jobs(0.01)
	var before: Vector2 = vehicles.ship_person_ground(people[0])
	var original: Dictionary = team.combat_units[0]
	var cargo: PackedByteArray = var_to_bytes(original.cargo)
	team.apply_unit_contact(0, {"environmental": true, "shield": false, "result": {"hp": float(team.combat_hot_get(0, &"hp")) + 1.0, "stun": 0.0, "guard_break": false}})
	# Hull deletion precedes the next advance: STALE finish must still freeze the dead paid point.
	vehicles.records().erase(boat_id)
	vehicles.records().erase(enemy_boat)
	actions.advance_ship_jobs(0.01)
	actions.settle_after_contacts()
	lab.site_controller.settle_person_deaths(100.0)
	var remains: Dictionary = lab.terrain.site.ground_loot.get(str(original.get("remains_id", "")), {})
	var checked: Dictionary = B6Store._validate_ship_loot_location(lab.terrain, lab.terrain.site, str(original.get("remains_id", "")), remains)
	if not _must(checked.ok and original.get("loot_settled", false) and remains.has("world_point") and vehicles.ship_loot_ground(remains).distance_to(before) < 0.00001 and team.combat_ground(0).distance_to(before) < 0.00001 and var_to_bytes(remains.cargo) == cargo, "B6_PLAIN_EVAC_DEATH_NEVER_SOURCE_CLAMP " + str(checked)): return false
	return _settled_save_b6(str(original.remains_id), before)

func _busy_save_b6() -> bool:
	var path: String = "user://b6_busy_" + str(Time.get_ticks_usec()) + ".json"
	var before: PackedByteArray = var_to_bytes(lab.terrain.site)
	var controller_save: Dictionary = lab.site_controller._capture_for_save()
	var pure_save: Dictionary = B6Store.save(lab.terrain, path, null, false, {}, true)
	return _must(not controller_save.ok and controller_save.code == "BUSY" and not pure_save.ok and pure_save.code == "BUSY" and not FileAccess.file_exists(path) and var_to_bytes(lab.terrain.site) == before, "B6_CONTROLLER_AND_PURE_STORE_BUSY_WITHOUT_FILE_OR_STATE_MUTATION")

func _settled_save_b6(identity: String, actual: Vector2) -> bool:
	var captured: Dictionary = lab.site_controller._capture_for_save()
	if not _must(captured.ok, "B6_SETTLED_CAPTURE " + str(captured)): return false
	var path: String = "user://b6_settled_" + b6_case + "_" + str(Time.get_ticks_usec()) + ".json"
	var saved: Dictionary = B6Store.save(lab.terrain, path, null, false, {}, true)
	if not _must(saved.ok, "B6_SETTLED_STORE_SAVE " + str(saved)): return false
	var reopened: Dictionary = B6Store.load_site(path)
	if not _must(reopened.ok, "B6_SETTLED_STORE_RELOAD " + str(reopened)): return false
	var container: Dictionary = reopened.data.site.ground_loot.get(identity, {})
	if not _must(container.get("ship_world_version") == 1 and container.get("world_point") is Array, "B6_VERSIONED_EXACT_LOCATION_RELOAD"): return false
	var point: Vector2 = (Vector2(float(container.world_point[0]), float(container.world_point[1])) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	return _must(point.distance_to(actual) < 0.00001, "B6_RELOADED_DEATH_POINT_HAS_NO_ROUNDING_OR_PEER_DEPENDENCE")
