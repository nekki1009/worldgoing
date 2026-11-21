extends "res://scripts/tests/site_ship_json_test.gd"

const NAVAL_OUT := "res://output/site_ship_close_20261004/naval_lifecycle"
var enemy: TerrainArmy
var enemy_boat := ""
var native_dock: Dictionary = {}

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 120000
	_run.call_deferred()

func _cluster(data: TerrainData, shore: Vector2i, count: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var queue: Array[Vector2i] = [shore]
	var seen := {shore: true}
	var head := 0
	while head < queue.size() and result.size() < count:
		var cell := queue[head]
		head += 1
		if not lab.character.occupies_cell(cell) and not lab.npc.occupies_cell(cell): result.append(cell)
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cell + direction
			if not seen.has(next) and data.can_step(cell, next) and next.distance_to(shore) <= 8.0:
				seen[next] = true
				queue.append(next)
	return result

func _layout(data: TerrainData, double_hull: bool, deep: bool = false) -> Dictionary:
	for y in range(4, data.size.y - 4):
		for x in range(4, data.size.x - 4):
			var anchor := Vector2i(x, y)
			if not data.can_navigate_water(anchor): continue
			for direction: Vector2i in TerrainData.DIRECTIONS:
				if not data.can_place_water_vehicle(Ship.footprint("ferry", anchor, direction)) or not data.can_place_water_vehicle(Ship.swept_footprint("ferry", anchor, direction, anchor + direction, direction)): continue
				var second := anchor + Vector2i(-direction.y, direction.x) * 2
				if double_hull and not data.can_place_water_vehicle(Ship.footprint("ferry", second, direction)): continue
				if deep:
					var valid := true
					for distance in range(1, 7):
						if not data.can_place_water_vehicle(Ship.swept_footprint("ferry", anchor + direction * (distance - 1), direction, anchor + direction * distance, direction)): valid = false; break
					for hull_cell: Vector2i in Ship.footprint("ferry", anchor + direction * 6, direction):
						for step: Vector2i in TerrainData.DIRECTIONS:
							if data.is_walkable(hull_cell + step): valid = false
					if not valid: continue
				for shore: Vector2i in Ship.boarding_cells("ferry", anchor, direction):
					if not data.is_walkable(shore) or absi(data.effective_height(shore) - data.effective_height(anchor)) > 1 or lab.character.occupies_cell(shore) or lab.npc.occupies_cell(shore): continue
					var cells := _cluster(data, shore, 6 if double_hull else 2)
					if cells.size() == (6 if double_hull else 2): return {"anchor": anchor, "facing": direction, "shore": shore, "cells": cells, "second": second}
	return {}

func _generate(double_hull: bool, deep: bool = false) -> bool:
	for seed_value: int in [17, 12345, 98761, 76404]:
		var data := TerrainGenerator.generate(TerrainPreset.Kind.ISLAND if deep else TerrainPreset.Kind.COASTAL_CLIFF, seed_value, {"max_height": 1})
		Env.initialize(data, "ship_naval_%d_%d" % [int(deep), seed_value])
		var bodies := {}
		for identity: int in data.water_body:
			if identity >= 0: bodies[identity] = true
		data.parameters.navigable_water_version = 1
		data.parameters.navigable_water_bodies = bodies.keys()
		lab.bind_terrain(data)
		lab.site_controller.set_process(false)
		lab.site_controller._auto_save_blocked = true
		native_dock = _layout(data, double_hull, deep)
		if not native_dock.is_empty(): return true
	return _must(false, "NAVAL_LAYOUT: genuine generated source lacks required natural hull/shore geometry")

func _step_person(owner: TerrainArmy, identity: int, shore: Vector2i) -> bool:
	var index := owner.index_for_identity(identity)
	var iterations := 0
	while owner.cells[index] != shore and iterations < 80:
		iterations += 1
		var blocker := func(cell: Vector2i) -> bool:
			return owner._cell_owners.has(cell) and int(owner._cell_owners[cell]) != index or lab._armies_block_cell(cell, owner) or lab.character.occupies_cell(cell) or lab.npc.occupies_cell(cell)
		var path := lab.terrain.path_between(owner.cells[index], shore, blocker)
		if not _must(not path.is_empty(), "NAVAL_SHORE_PATH: original person route missing"): return false
		var next: Vector2i = path[1] if path[0] == owner.cells[index] and path.size() > 1 else path[0]
		if not _must(owner._reserve_combat_step(index, next), "NAVAL_SHORE_RESERVE: original person step rejected"): return false
		owner.prepare_combat(float(owner.move_duration[index]) + 0.01, 0.0)
	return _must(owner.cells[index] == shore, "NAVAL_SHORE_BOUND: original person did not reach board edge")

func _job(identity: int) -> bool:
	var actions: SitePersonActions = lab.site_controller.person_actions
	if not _must(actions._jobs.has(str(identity)), "NAVAL_JOB_MISSING: %d" % identity): return false
	var job: Dictionary = actions._jobs[str(identity)]
	actions.advance_ship_jobs(maxf(0.01, float(job.duration) - float(job.elapsed) + 0.01))
	for result: Dictionary in actions.settle_after_contacts():
		if not _must(result.ok, "NAVAL_JOB_COMMIT: " + str(result)): return false
	return _must(not actions.is_busy(identity), "NAVAL_JOB_BUSY: committed job not finished")

func _board(index: int, berth: int) -> bool:
	if not _step_person(team, people[index], native_dock.shore): return false
	var result: Dictionary = lab.site_controller.person_actions.begin_ship_board(people[index], boat_id, people[index], berth, true)
	return _must(result.ok, "NAVAL_BOARD: " + str(result)) and _job(people[index])

func _target(identity: int) -> Vector2:
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var from := vehicles.ship_local_position(identity)
	for y in range(13):
		for x in range(7):
			var point := Vector2(float(x) * 0.25 - 0.25, float(y) * 0.25 - 0.25)
			if point.distance_to(from) < 0.8: continue
			if vehicles.ship_deck_path(identity, point).size() > 1: return point
	return Vector2.INF

func _walk_job(identity: int, destination: Vector2) -> bool:
	var result: Dictionary = lab.site_controller.person_actions.begin_ship_walk(identity, destination, identity, true)
	return _must(destination.is_finite() and result.ok, "NAVAL_DECK_BEGIN: " + str(result))

func _save_load(name: String) -> bool:
	var controller: SiteController = lab.site_controller
	for owner: TerrainArmy in lab.combat_armies: owner.settle_combat_command()
	lab.terrain.site.combat_left = 0.0 # Contacts settled; preserve positions/HP/timers.
	controller._capture_positions()
	var filename := NAVAL_OUT + "/" + name + ".json"
	var saved: Dictionary = controller.save_to(filename)
	if not _must(saved.ok, "NAVAL_SAVE_" + name + ": " + str(saved)): return false
	var read: Dictionary = Store.load_site(filename)
	if not _must(read.ok, "NAVAL_CANDIDATE_" + name + ": " + str(read)): return false
	var loaded: Dictionary = controller.load_from(filename)
	if not _must(loaded.ok, "NAVAL_LOAD_" + name + ": " + str(loaded)): return false
	team = lab.army
	enemy = lab.opposing_army
	return true

func _supply_locations() -> Dictionary:
	var stocks := {}
	for key: String in lab.terrain.site.team_supply:
		stocks[key] = lab.terrain.site.team_supply[key].get("locations", {})
	return stocks.duplicate(true)

func _main_cases() -> bool:
	if not _generate(true): return false
	team = lab.army
	enemy = lab.opposing_army
	team.team_id = lab._next_army_identity()
	enemy.team_id = team.team_id + 1
	lab.terrain.site.army_next_team = enemy.team_id + 1
	team.role = "logistics"
	enemy.role = "logistics"
	team.roster_size = 5
	enemy.roster_size = 1
	var selected: Array[Vector2i] = []
	for index in range(5): selected.append(native_dock.cells[index])
	var hostile_cells: Array[Vector2i] = [native_dock.cells[5]]
	if not _must(team.deploy_at(lab.terrain, lab.character, lab.npc, selected) and team.enable_combat(false, 0), "NAVAL_ORIGINAL_FIVE_ROSTER"): return false
	if not _must(enemy.deploy_at(lab.terrain, lab.character, lab.npc, hostile_cells) and enemy.enable_combat(false, 0), "NAVAL_ORIGINAL_HOSTILE_ROSTER"): return false
	people.clear()
	for index in range(5):
		people.append(team.combat_identity(index))
		team.combat_units[index].logistics = true
	team.combat_units[2].cargo.grain = 2 # Explicit stock in the original holder.
	lab.terrain.site.controlled_person_id = people[0]
	lab.terrain.site.army_trial_active = true
	var controller: SiteController = lab.site_controller
	var enabled: Dictionary = controller.captivity_supply.enable_team(team)
	if not _must(enabled.ok, "NAVAL_ORIGINAL_SUPPLY_ENABLE: " + str(enabled)): return false
	enabled.entry.inventory.grain = 12
	enabled.entry.sustain.open_rations = 0.5
	var vehicles: SiteVehicleTransport = controller.vehicles
	var made: Dictionary = vehicles.deploy_ship(team, "ferry", native_dock.anchor, native_dock.facing, true)
	var hostile: Dictionary = vehicles.deploy_ship(enemy, "ferry", native_dock.second, native_dock.facing, true)
	if not _must(made.ok and hostile.ok, "NAVAL_TWO_HULLS: " + str([made, hostile])): return false
	boat_id = str(made.vehicle_id)
	enemy_boat = str(hostile.vehicle_id)
	for index in range(5):
		if not _board(index, index): return false
	var moved: Dictionary = controller.transfer_ship_supply(team, "shore:%d" % lab.terrain.index(native_dock.shore), "vehicle:" + boat_id, {"grain": 3}, 0.25, people[0], true)
	if not _must(moved.ok, "NAVAL_REAL_FOOD_LOCATION: " + str(moved)): return false
	var boat: Dictionary = vehicles.records()[boat_id]
	var transferred: Dictionary = vehicles.transfer("person:%d" % people[2], boat_id, {"grain": 1}, [], int(team.combat_units[2].item_state.version), int(boat.holder.version), people[2], true)
	if not _must(transferred.ok and boat.cargo.grain == 1 and team.combat_units[2].cargo.grain == 1, "NAVAL_REAL_CARGO_TRANSFER: " + str(transferred)): return false
	var actions: SitePersonActions = controller.person_actions
	var destination := _target(people[1])
	if not _walk_job(people[1], destination): return false
	var walk: Dictionary = actions._jobs[str(people[1])]
	var start := vehicles.ship_person_ground(people[1])
	var q := vehicles.ship_load(boat_id)
	actions.advance_ship_jobs(float(walk.duration) * 0.4)
	var midway := vehicles.ship_person_ground(people[1])
	if not _must(not midway.is_equal_approx(start) and vehicles.ship_people(boat).size() == 5 and is_equal_approx(q, vehicles.ship_load(boat_id)) and actions.save_guard().code == "BUSY", "NAVAL_DECK_REAL_PROGRESS_AND_SAVE_GUARD"): return false
	if not _must(actions.cancel(people[1]).ok and actions.is_busy(people[1]), "NAVAL_CANCEL_KEEPS_COMMITTED_PATH"): return false
	if not _job(people[1]): return false
	if not _must(vehicles.ship_local_position(people[1]).is_equal_approx(destination), "NAVAL_CANCEL_ENDS_AT_COMMITTED_POINT"): return false
	if not _walk_job(people[1], _target(people[1])): return false
	walk = actions._jobs[str(people[1])]
	actions.advance_ship_jobs(float(walk.duration) * 0.3)
	team.apply_unit_contact(1, {"shield": false, "result": {"hp": 0.0, "stun": 1000.0, "guard_break": false}})
	if not _job(people[1]): return false
	if not _must(float(team.combat_hot_get(1, &"ko")) > 0.0 and vehicles.is_embarked(people[1]) and vehicles.ship_people(boat).size() == 5, "NAVAL_KO_KEEPS_ORIGINAL_RELATION"): return false
	team.prepare_combat(0.01, float(team.combat_hot_get(1, &"ko")) + 0.1)
	team.prepare_combat(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"get_up"]) + 0.1, 0.0)
	if not _must(team.combat_can_act(1), "NAVAL_ORIGINAL_KO_RECOVERY"): return false
	if not _walk_job(people[3], _target(people[3])): return false
	walk = actions._jobs[str(people[3])]
	actions.advance_ship_jobs(float(walk.duration) * 0.35)
	var death_local := vehicles.ship_local_position(people[3])
	var held: Dictionary = team.combat_units[3].item_state.duplicate(true)
	q = vehicles.ship_load(boat_id)
	team.apply_unit_contact(3, {"shield": false, "result": {"hp": 10000.0, "stun": 0.0, "guard_break": false}})
	if not _must(controller.supply_save_guard().code == "BUSY", "NAVAL_DEAD_PATH_PENDING_SAVE_GUARD"): return false
	actions.advance_ship_jobs(0.01)
	actions.settle_after_contacts()
	controller.settle_person_deaths(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"]) + 0.2)
	var dead: Dictionary = team.combat_units[3]
	var remains: Dictionary = lab.terrain.site.ground_loot.get(str(dead.get("remains_id", "")), {})
	if not _must(bool(dead.get("ship_death_settled", false)) and not vehicles.is_embarked(people[3]) and vehicles.ship_people(boat).size() == 4 and is_equal_approx(q, vehicles.ship_load(boat_id)), "NAVAL_DEAD_PATH_RELEASES_N_RETAINS_Q"): return false
	if not _must(not remains.is_empty() and remains.item_ids == held.item_ids and remains.equipped == held.equipped and str(remains.vehicle_id) == boat_id and Vector2(float(remains.local_position[0]), float(remains.local_position[1])).is_equal_approx(death_local), "NAVAL_DEAD_PATH_ONE_ORIGINAL_LOCAL_HOLDER"): return false
	print("SHIP_DECK_LIFECYCLE_PASS true board/path, progress, cancel, KO/recovery, pending death, original N/Q/local goods")
	# Original starboard deck edge is 0.65 cells from the parallel enemy port berth.
	if not _walk_job(people[4], Vector2(1.25, 0.25)) or not _job(people[4]): return false
	var supplies := _supply_locations()
	var common_q := vehicles.ship_load(boat_id) + vehicles.ship_load(enemy_boat)
	var original_team := team.team_id
	var original_body: Dictionary = team.combat_units[4]
	var original_holder: Dictionary = original_body.item_state
	var original_ids: Array = original_holder.item_ids.duplicate()
	var begun: Dictionary = actions.begin_ship_cross(people[4], enemy_boat, people[4], 1, true)
	if not _must(begun.ok, "NAVAL_CROSS_TRUE_EDGE: " + str(begun)): return false
	var crossing: Dictionary = actions._jobs[str(people[4])]
	if not _must(not vehicles.ship_job(boat_id).is_empty() and not vehicles.ship_job(enemy_boat).is_empty(), "NAVAL_CROSS_LOCKS_BOTH_HULLS"): return false
	if not _must(not actions.begin_ship_walk(people[1], _target(people[1]), people[1], true).ok and actions.save_guard().code == "BUSY", "NAVAL_CROSS_PREVENTS_CONFLICTING_SOURCE_JOB_AND_SAVE"): return false
	start = vehicles.ship_person_ground(people[4])
	actions.advance_ship_jobs(float(crossing.duration) * 0.5)
	midway = vehicles.ship_person_ground(people[4])
	if not _must(not midway.is_equal_approx(start) and str(original_body.embarked_vehicle_id) == boat_id and is_equal_approx(common_q, vehicles.ship_load(boat_id) + vehicles.ship_load(enemy_boat)), "NAVAL_CROSS_REAL_PROGRESS_BEFORE_ATOMIC_HANDOFF"): return false
	if not _job(people[4]): return false
	if not _must(is_same(original_body, team.combat_units[4]) and is_same(original_holder, original_body.item_state) and original_holder.item_ids == original_ids and team.team_id == original_team and bool(original_body.ship_guest) and str(original_body.embarked_vehicle_id) == enemy_boat, "NAVAL_ENEMY_CROSS_RETAINS_ORIGINAL_TEAM_BODY_AND_HOLDER"): return false
	if not _must(vehicles.ship_people(boat).size() == 3 and vehicles.ship_people(vehicles.records()[enemy_boat]).size() == 1 and is_equal_approx(common_q, vehicles.ship_load(boat_id) + vehicles.ship_load(enemy_boat)) and _supply_locations() == supplies, "NAVAL_CROSS_N_Q_AND_COMMON_FOOD_SINGLE_AUTHORITY"): return false
	if not _must(actions.begin_ship_helm(people[4], enemy_boat, people[4], true).code == "NO_AUTHORITY", "NAVAL_GUEST_HAS_NO_HELM_AUTHORITY"): return false
	if not _save_load("guest_deck"): return false
	vehicles = lab.site_controller.vehicles
	controller = lab.site_controller
	actions = controller.person_actions
	boat = vehicles.records()[boat_id]
	if not _must(bool(team.combat_units[4].ship_guest) and team.combat_units[1].has("ship_deck_position") and _supply_locations() == supplies, "NAVAL_FULL_GENERATED_GUEST_DECK_JSON_ROUNDTRIP"): return false
	var snapshot: Dictionary = team.capture_combat_state()
	var malformed := snapshot.duplicate(true)
	malformed.units[4].ship_guest = 1
	if not _must(not TerrainArmy.valid_combat_state(malformed, lab.terrain, {}, lab.terrain.site), "NAVAL_GUEST_INTEGER_REJECTED"): return false
	malformed = snapshot.duplicate(true)
	malformed.units[1].ship_deck_position = [0, 99]
	if not _must(not TerrainArmy.valid_combat_state(malformed, lab.terrain, {}, lab.terrain.site), "NAVAL_OUTSIDE_DECK_REJECTED"): return false
	print("SHIP_CROSS_JSON_PASS true enemy cross, two locks, unchanged IDs/team/items/food, strict generated full save/load")
	# Finish a real committed hull step before starting original wreck jobs.
	var helm: Dictionary = actions.begin_ship_helm(people[0], boat_id, people[0], true)
	if not _must(helm.ok, "NAVAL_SINKING_HELM: " + str(helm)) or not _job(people[0]): return false
	team.apply_unit_contact(1, {"shield": false, "result": {"hp": 0.0, "stun": 1000.0, "guard_break": false}})
	var ko_goods: Dictionary = team.combat_units[1].item_state.duplicate(true)
	var hull_goods: Dictionary = boat.holder.duplicate(true)
	var hull_cargo: Dictionary = boat.cargo.duplicate(true)
	var supply_before := _supply_locations()
	var step: Dictionary = vehicles.ship_order(boat_id, "forward", TerrainArmy.INVALID_CELL, people[0], true)
	if not _must(step.ok, "NAVAL_HALF_STEP_BEGIN: " + str(step)): return false
	vehicles.update_ships(float(boat.move.duration) * 0.4)
	var move_before: Dictionary = boat.move.duplicate(true)
	var old_cell := int(boat.cell)
	var loss: Dictionary = Runtime.damage_ship_vehicle(lab.terrain, boat_id, Ship.hull_hp("ferry"))
	if not _must(loss.ok and float(boat.naval.hp) == 0.0 and str(boat.naval.state) == "sinking" and boat.move == move_before and boat.stop_pending and boat.cell == old_cell and actions.job_for(people[0]).is_empty(), "NAVAL_HALF_STEP_HP_ZERO_RETAINS_COMMIT_NO_TELEPORT"): return false
	vehicles.update_ships(float(move_before.duration) - float(move_before.elapsed) + 0.01)
	if not _must(boat.move.is_empty() and int(boat.cell) == int(move_before.cell), "NAVAL_SINKING_FINISHES_ORIGINAL_HULL_STEP"): return false
	vehicles.update_ships(0.01)
	var evacuated_load := 0.0
	for index: int in [0, 2]: evacuated_load += Runtime.carried_load(lab.terrain.site, team.combat_units[index].cargo, team.combat_units[index].item_state) + float(team.combat_units[index].item_state.equipped.size())
	q = vehicles.ship_load(boat_id)
	var progress_seen := false
	var iterations := 0
	while not vehicles.ship_people(boat, false).is_empty() and iterations < 2000:
		iterations += 1
		vehicles.update_ships(0.05)
		for identity: int in [people[0], people[2]]:
			var job: Dictionary = actions.job_for(identity)
			if str(job.get("kind", "")) != "ship_evac": continue
			var before := vehicles.ship_person_ground(identity)
			var nearest: Array[Vector2] = vehicles.ship_evacuation_path(identity)
			if not _must(nearest.size() >= 2 and lab.terrain.is_walkable(Vector2i((job.path.back() as Vector2).round())), "NAVAL_NEAREST_LEGAL_SHORE_PATH"): return false
			actions.advance_ship_jobs(0.05)
			var after := vehicles.ship_person_ground(identity)
			if after != before:
				progress_seen = true
				if not _must(after.distance_to(before) <= 0.051 * float(job.speed) * TerrainRenderer.CELL_PIXELS and team.moving_to[team.index_for_identity(identity)] == TerrainArmy.INVALID_CELL, "NAVAL_EVAC_REAL_BOUNDED_WORLD_PROGRESS_NO_WATER_FOOTSTEP"): return false
			break
		actions.settle_after_contacts()
		controller.settle_person_deaths(0.1)
	if not _must(iterations < 2000 and progress_seen and vehicles.ship_people(boat, false).is_empty() and str(boat.naval.state) == "wrecked", "NAVAL_WRECK_EVAC_BOUND"): return false
	for index: int in [0, 2]:
		if not _must(float(team.combat_hot_get(index, &"hp")) > 0.0 and lab.terrain.is_walkable(team.cells[index]) and team._cell_owners.get(team.cells[index], -1) == index and not vehicles.is_embarked(people[index]), "NAVAL_SURVIVOR_ORIGINAL_LEGAL_SHORE_CLAIM"): return false
	dead = team.combat_units[1]
	remains = lab.terrain.site.ground_loot.get(str(dead.get("remains_id", "")), {})
	if not _must(float(team.combat_hot_get(1, &"hp")) == 0.0 and bool(dead.get("ship_death_settled", false)) and not remains.is_empty() and remains.item_ids == ko_goods.item_ids and str(remains.vehicle_id) == boat_id, "NAVAL_KO_DROWNS_VIA_ORIGINAL_DEATH_AND_LOOT"): return false
	if not _must(boat.holder == hull_goods and boat.cargo == hull_cargo and _supply_locations() == supply_before and is_equal_approx(vehicles.ship_load(boat_id), q - evacuated_load), "NAVAL_WRECK_PRESERVES_HULL_CARGO_COMMON_FOOD_AND_ALL_DEAD_GOODS"): return false
	if not _save_load("wreck_evacuated"): return false
	print("SHIP_SINKING_EVAC_PASS true hull HP, committed half-step, nearest-shore original world path, KO death, all wreck goods/full JSON")
	return true

func _no_route_case() -> bool:
	if not _generate(false, true): return false
	team = lab.army
	team.team_id = lab._next_army_identity()
	team.roster_size = 1
	team.role = "logistics"
	var cells: Array[Vector2i] = [native_dock.cells[0]]
	if not _must(team.deploy_at(lab.terrain, lab.character, lab.npc, cells) and team.enable_combat(false, 0), "NAVAL_NO_ROUTE_ORIGINAL_ROSTER"): return false
	people.clear()
	people.append(team.combat_identity(0))
	team.combat_units[0].logistics = true
	lab.terrain.site.army_next_team = team.team_id + 1
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var result: Dictionary = vehicles.deploy_ship(team, "ferry", native_dock.anchor, native_dock.facing, true)
	if not _must(result.ok, "NAVAL_NO_ROUTE_HULL: " + str(result)): return false
	boat_id = str(result.vehicle_id)
	if not _board(0, 0): return false
	result = lab.site_controller.person_actions.begin_ship_helm(people[0], boat_id, people[0], true)
	if not _must(result.ok, "NAVAL_NO_ROUTE_HELM") or not _job(people[0]): return false
	var boat: Dictionary = vehicles.records()[boat_id]
	for distance in range(6):
		result = vehicles.ship_order(boat_id, "forward", TerrainArmy.INVALID_CELL, people[0], true)
		if not _must(result.ok, "NAVAL_NO_ROUTE_TRUE_WATER_STEP_%d: %s" % [distance, str(result)]): return false
		vehicles.update_ships(float(boat.move.duration) + 0.01)
	# Actual generated island stays untouched. Only the explicit v1 navigation
	# fixture permission is restricted to the current known hull water cells.
	var fingerprint := lab.terrain.fingerprint()
	var licensed: Array[int] = []
	for cell: Vector2i in Ship.footprint("ferry", lab.terrain.cell_from_index(int(boat.cell)), native_dock.facing): licensed.append(lab.terrain.index(cell))
	lab.terrain.parameters.erase("navigable_water_bodies")
	lab.terrain.parameters.navigable_water_cells = licensed
	if not _must(vehicles.ship_evacuation_path(people[0]).is_empty() and lab.terrain.fingerprint() == fingerprint, "NAVAL_NO_ROUTE_REAL_PERMISSION_REFUSAL_WITHOUT_TERRAIN_MASK"): return false
	var q := vehicles.ship_load(boat_id)
	var goods: Dictionary = team.combat_units[0].item_state.duplicate(true)
	result = Runtime.damage_ship_vehicle(lab.terrain, boat_id, Ship.hull_hp("ferry"))
	if not _must(result.ok, "NAVAL_NO_ROUTE_REAL_HULL_DAMAGE"): return false
	vehicles.update_ships(0.01)
	lab.site_controller.settle_person_deaths(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"]) + 0.2)
	var body: Dictionary = team.combat_units[0]
	var remains: Dictionary = lab.terrain.site.ground_loot.get(str(body.get("remains_id", "")), {})
	if not _must(float(team.combat_hot_get(0, &"hp")) == 0.0 and body.get("ship_death_settled", false) and vehicles.ship_people(boat, false).is_empty() and not remains.is_empty() and remains.item_ids == goods.item_ids and is_equal_approx(vehicles.ship_load(boat_id), q), "NAVAL_NO_ROUTE_ORIGINAL_DEATH_N_RELEASE_Q_REMAINS"): return false
	if not _save_load("wreck_no_route"): return false
	print("SHIP_NO_ROUTE_PASS genuine generated island, six real boat steps, explicit known-water permission refusal, original death and full wreck JSON")
	return true

func _run() -> void:
	if not _must(DisplayServer.get_name() == "headless", "NAVAL_CANONICAL_HEADLESS_REQUIRED"): return
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for owner: TerrainArmy in lab.combat_armies: owner.set_process(false)
	lab.site_controller.save_root = NAVAL_OUT
	if not _main_cases() or not _no_route_case(): return
	lab.queue_free()
	await process_frame
	print("SITE_SHIP_NAVAL_LIFECYCLE_PASS")
	quit(0)
