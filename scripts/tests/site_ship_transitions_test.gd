extends "res://scripts/tests/site_ship_lifecycle_test.gd"
## Original-owner transitions; existing acceptance remains intact.

var proofs: Array[Dictionary] = []

func _setup() -> Array[String]:
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	var controller: SiteController = lab.site_controller
	controller.set_process(false)
	controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for army: TerrainArmy in lab.combat_armies: army.set_process(false)
	_water_fixture()
	# Explicit land corridor to the real map edge.
	var data: TerrainData = lab.terrain
	for y in range(18, 27):
		for x in range(20):
			var cell := Vector2i(x, y)
			var i := data.index(cell)
			if not _must(int(data.feature_at[i]) == 0, "Fixture would replace building"): return []
			data.height_levels[i] = 0
			data.ramp_edges[i] = 0
			data.static_blocked[i] = 0
			data.flags[i] = Data.Flag.WALKABLE
			data.surface_types[i] = Data.Surface.GRASS
			data.water_kind[i] = 0
			data.water_body[i] = -1
			for key: String in data.resources_at.get(i, []): Env.change(data, key, {"cleared": true, "remaining": 0})
	Env.rebuild_indexes(data)
	Runtime.rebuild_terrain_edges(data)
	team = lab.army
	team.role = "logistics"
	team.team_id = lab._next_army_identity()
	team.roster_size = 21
	var cells: Array[Vector2i] = [Vector2i(29, 20), Vector2i(29, 25), Vector2i(25, 23), Vector2i(25, 24)]
	for index in range(4, 21): cells.append(Vector2i(25, 22 + index))
	if not _must(team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false, 0), "Original 21-row deploy rejected"): return []
	data.site.army_next_team = team.team_id + 1
	data.site.army_trial_active = true
	people.clear()
	proofs.clear()
	for index in range(21):
		var row: Dictionary = team.combat_units[index]
		people.append(team.combat_identity(index))
		row.logistics = true
		proofs.append({"row": row, "holder": row.item_state, "cargo": row.cargo.duplicate(true), "items": row.item_state.item_ids.duplicate(), "slots": row.item_state.equipped.duplicate(true), "version": int(row.item_state.version)})
	var ids: Array[String] = []
	var vehicles: SiteVehicleTransport = controller.vehicles
	for anchor: Vector2i in [Vector2i(30, 20), Vector2i(30, 25)]:
		var deployed: Dictionary = vehicles.deploy_ship(team, "ferry", anchor, Vector2i.UP, true)
		if not _must(deployed.ok, "Deploy: " + str(deployed)): return []
		ids.append(str(deployed.vehicle_id))
	return ids

func _people_intact() -> bool:
	if not _must(team.combat_units.size() == 21, "Roster changed"): return false
	for index in range(21):
		var row: Dictionary = team.combat_units[index]
		var proof: Dictionary = proofs[index]
		if not _must(team.combat_identity(index) == people[index] and is_same(row, proof.row) and is_same(row.item_state, proof.holder) and row.cargo == proof.cargo and row.item_state.item_ids == proof.items and row.item_state.equipped == proof.slots and int(row.item_state.version) == int(proof.version), "Original row/ID/holder/goods changed"): return false
	return true

func _board_original(index: int, id: String, berth: int, shore: Vector2i) -> bool:
	if not _walk_checked(index, shore): return false
	var actions: SitePersonActions = lab.site_controller.person_actions
	var begun: Dictionary = actions.begin_ship_board(people[index], id, people[index], berth, true)
	return _must(begun.ok, "Board: " + str(begun)) and _finish_checked(people[index])

func _collapse() -> bool:
	var supply: Dictionary = lab.terrain.site.team_supply[str(team.team_id)]
	supply.sustain.routed = true
	supply.sustain.morale = 0.0
	var result: Dictionary = team.begin_morale_retreat()
	return _must(result.ok and team.combat_order == TerrainArmy.CombatOrder.RETREAT, "Collapse: " + str(result))

func _nq(ids: Array[String]) -> Array:
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	return [vehicles.ship_people(vehicles.records()[ids[0]]).size(), vehicles.ship_people(vehicles.records()[ids[1]]).size(), vehicles.ship_load(ids[0]), vehicles.ship_load(ids[1])]

func _run() -> void:
	if not _must(DisplayServer.get_name() == "headless", "Headless required"): return
	var ids: Array[String] = _setup()
	if ids.size() != 2: return
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var actions: SitePersonActions = lab.site_controller.person_actions
	for index in range(2):
		if not _board_original(index, ids[index], 0, Vector2i(29, 20 + index * 5)): return
		var helm: Dictionary = actions.begin_ship_helm(people[index], ids[index], people[index], true)
		if not _must(helm.ok, "Helm: " + str(helm)) or not _finish_checked(people[index]): return
	var first: Dictionary = vehicles.records()[ids[0]]
	var second: Dictionary = vehicles.records()[ids[1]]
	var second_before: Dictionary = second.duplicate(true)
	var nq: Array = _nq(ids)
	var accepted: Dictionary = vehicles.ship_order(ids[0], "reverse", TerrainArmy.INVALID_CELL, people[0], true)
	if not _must(accepted.ok, "First step: " + str(accepted)): return
	var move: Dictionary = first.move.duplicate(true)
	var overlap := false
	for cell: Vector2i in vehicles.ship_sweep(second, Vector2i(30, 24), Vector2i.UP):
		overlap = overlap or move.sweep.has(lab.terrain.index(cell))
	if not _must(overlap, "Fixture sweeps do not intersect"): return
	var rejected: Dictionary = vehicles.ship_order(ids[1], "forward", TerrainArmy.INVALID_CELL, people[1], true)
	if not _must(rejected.code == "NO_SPACE" and second == second_before and first.move == move and _nq(ids) == nq, "Second sweep changed committed state/N/Q"): return
	vehicles.update_ships(float(move.duration) * 0.5)
	var half: Dictionary = first.move.duplicate(true)
	if not _collapse(): return
	if not _must(first.move == half and bool(first.stop_pending), "Collapse rolled back hull half-step"): return
	vehicles.update_ships(float(move.duration))
	if not _must(first.move.is_empty() and int(first.cell) == int(move.cell) and _nq(ids) == nq and vehicles.is_embarked(people[0]), "Routed hull did not finish with same passenger/N/Q"): return
	if not _people_intact(): return
	print("SITE_SHIP_TRANSITIONS_SWEEP_PASS")
	lab.queue_free()
	await process_frame

	# Fresh original fixture; no live routed state reset.
	ids = _setup()
	if ids.size() != 2: return
	vehicles = lab.site_controller.vehicles
	actions = lab.site_controller.person_actions
	first = vehicles.records()[ids[0]]
	second = vehicles.records()[ids[1]]
	if not _board_original(0, ids[0], 0, Vector2i(29, 20)) or not _board_original(1, ids[1], 0, Vector2i(29, 25)) or not _board_original(3, ids[1], 1, Vector2i(29, 25)): return
	var leaving: Dictionary = actions.begin_ship_disembark(people[1], ids[1], people[1], Vector2i(29, 25), true)
	if not _must(leaving.ok and vehicles.reserves_cell(Vector2i(29, 25)), "No original shore reservation"): return
	var contender: Dictionary = team.combat_units[3].duplicate(true)
	var contested: Dictionary = actions.begin_ship_disembark(people[3], ids[1], people[3], Vector2i(29, 25), true)
	if not _must(not contested.ok and team.combat_units[3] == contender and not actions.is_busy(people[3]), "Shore contender changed person/job"): return
	if not _finish_checked(people[1]) or not _walk_checked(1, Vector2i(25, 20)) or not _walk_checked(2, Vector2i(29, 20)): return
	lab.terrain.site.controlled_person_id = people[2] # Original manually controlled shore blocker.
	var boarding: Dictionary = actions.begin_ship_board(people[2], ids[0], people[2], 1, true)
	leaving = actions.begin_ship_disembark(people[3], ids[1], people[3], Vector2i(29, 25), true)
	if not _must(boarding.ok and leaving.ok, "Timed board/leave did not begin"): return
	nq = _nq(ids)
	actions.advance_ship_jobs(1.0)
	var early_results: Array[Dictionary] = actions.settle_after_contacts()
	if not _must(actions._jobs.has(str(people[2])) and actions._jobs.has(str(people[3])) and early_results.is_empty(), "Jobs cancelled before midpoint: " + str({"results": early_results, "remaining_jobs": actions._jobs.keys()})): return
	if not _must(float(actions._jobs[str(people[2])].elapsed) == 1.0 and float(actions._jobs[str(people[3])].elapsed) == 1.0, "Actual jobs are not halfway"): return
	if not _collapse(): return
	actions.advance_ship_jobs(0.1)
	var results: Array[Dictionary] = actions.settle_after_contacts()
	var cancelled := 0
	for result: Dictionary in results:
		if int(result.executor_id) in [people[2], people[3]] and not result.ok: cancelled += 1
	if not _must(cancelled == 2 and not actions.is_busy(people[2]) and not actions.is_busy(people[3]) and not vehicles.is_embarked(people[2]) and team.cells[2] == Vector2i(29, 20) and vehicles.is_embarked(people[3]) and int(team.combat_units[3].berth_id) == 1 and _nq(ids) == nq, "Routed jobs did not cancel on original sides/N/Q"): return
	if not _must(not vehicles.is_embarked(people[1]) and team.cells[1] == Vector2i(25, 20), "Completed landing rolled back"): return
	var blocked: Dictionary = actions.begin_ship_disembark(people[0], ids[0], people[0], Vector2i(29, 20), true, true)
	if not _must(blocked.code == "NO_SPACE" and not actions.is_busy(people[0]) and _nq(ids) == nq, "Blocked retreat landing changed N/Q/job"): return
	# One original controlled shore step frees the exit; other routed rows keep moving.
	var shore := Vector2i(29, 20)
	var next: Vector2i = TerrainArmy.INVALID_CELL
	var neighbors: Array[Vector2i] = [Vector2i(28, 20), shore + Vector2i.UP, shore + Vector2i.DOWN, shore + Vector2i.RIGHT]
	for candidate: Vector2i in neighbors:
		if not lab.terrain.can_step(shore, candidate) or team.blocks_cell(candidate) or team._is_external_cell(candidate, people[2]) or vehicles.blocks_cell(candidate): continue
		if team._reserve_combat_step(2, candidate):
			next = candidate
			break
	if not _must(next != TerrainArmy.INVALID_CELL, "No original legal neighbor can free the shore: " + str(neighbors)): return
	team.prepare_combat(float(team.move_duration[2]) + 0.01, 0.0)
	if not _must(team.cells[2] == next and team.moving_to[2] == TerrainArmy.INVALID_CELL and team._cell_owners.get(next, -1) == 2 and not team.blocks_cell(shore) and not team._is_external_cell(shore, people[2]) and not vehicles.reserves_cell(shore), "Original neighbor step did not commit/free its shore slot"): return
	var retreat: Dictionary = actions.begin_ship_disembark(people[0], ids[0], people[0], Vector2i(29, 20), true, true)
	if not _must(retreat.ok, "Retreat landing: " + str(retreat)) or not _finish_checked(people[0]): return
	if not _must(not vehicles.is_embarked(people[0]) and team.cells[0] == Vector2i(29, 20) and team.combat_order == TerrainArmy.CombatOrder.RETREAT, "Landing did not retain land RETREAT"): return
	for iteration in range(32):
		team.prepare_combat(0.11, 0.0)
		if team.cells[0] != Vector2i(29, 20) or team.moving_to[0] != TerrainArmy.INVALID_CELL: break
	var route: Dictionary = team._retreat_paths.get(people[0], {})
	if not _must(not route.is_empty() and (team.cells[0] != Vector2i(29, 20) or team.moving_to[0] != TerrainArmy.INVALID_CELL) and not team._retreat_paths.has(people[3]) and team.moving_to[3] == TerrainArmy.INVALID_CELL, "Land retreat stalled or aboard person got foot path"): return
	for cell: Vector2i in route.path:
		if not _must(lab.terrain.is_walkable(cell), "Water/blocked land retreat path"): return
	if not _people_intact(): return
	print("SITE_SHIP_TRANSITIONS_PASS: same-round sweep, shore contention, timed routed cancellation, unblock and original land retreat")
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	quit(0)
