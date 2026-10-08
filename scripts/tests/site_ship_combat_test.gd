extends "res://scripts/tests/site_ship_transport_test.gd"

var failed := false
var other: TerrainArmy
var enemy_ids: Array[int] = []

func _must(condition: bool, message: String) -> bool:
	if condition: return true
	failed = true
	push_error("SHIP_COMBAT_FAIL: " + message)
	quit(1)
	return false

func _job(identity: int) -> bool:
	var actions: SitePersonActions = lab.site_controller.person_actions
	if not _must(actions._jobs.has(str(identity)), "Missing original job for %d" % identity): return false
	var job: Dictionary = actions._jobs[str(identity)]
	if str(job.kind).begins_with("ship_"):
		actions.advance_ship_jobs(float(job.duration) - float(job.elapsed) + 0.01)
	else:
		actions.advance(float(job.duration) - float(job.elapsed) + 0.01)
	var results: Array[Dictionary] = actions.settle_after_contacts()
	for result: Dictionary in results:
		if not _must(bool(result.ok), "Original job commit rejected: " + str(result)): return false
	return _must(not actions.is_busy(identity), "Original job did not finish for %d" % identity)

func _board_pair(owner: TerrainArmy, ids: Array[int], boat_id: String) -> bool:
	var actions: SitePersonActions = lab.site_controller.person_actions
	var result: Dictionary = actions.begin_ship_board(ids[0], boat_id, ids[0], 1, true)
	if not _must(result.ok, "Original shooter board: " + str(result)) or not _job(ids[0]): return false
	var destination := owner.cells[1] + Vector2i.RIGHT
	if not _must(owner._reserve_combat_step(1, destination), "Original next sailor shore reservation"): return false
	owner.prepare_combat(float(owner.move_duration[1]) + 0.01)
	if not _must(owner.cells[1] == destination and owner.moving_to[1] == TerrainArmy.INVALID_CELL, "Original shore step completion"): return false
	result = actions.begin_ship_board(ids[1], boat_id, ids[1], 0, true)
	if not _must(result.ok, "Original helm sailor board: " + str(result)): return false
	return _job(ids[1])

func _deck(identity: int, point: Vector2) -> bool:
	var result: Dictionary = lab.site_controller.person_actions.begin_ship_walk(identity, point, identity, true)
	return _must(result.ok, "Original deck job: " + str(result)) and _job(identity)

func _run() -> void:
	if not _must(DisplayServer.get_name() == "headless", "Canonical headless fixture required"): return
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for army_owner: TerrainArmy in lab.combat_armies: army_owner.set_process(false)
	_water_fixture()
	team = lab.army
	other = lab.opposing_army
	team.team_id = lab._next_army_identity()
	other.team_id = team.team_id + 1
	lab.terrain.site.army_next_team = other.team_id + 1
	for owner: TerrainArmy in [team, other]:
		owner.roster_size = 2
		owner.role = "logistics"
		owner.exchange_enabled = true
	var first_cells: Array[Vector2i] = [Vector2i(29, 20), Vector2i(28, 20)]
	var second_cells: Array[Vector2i] = [Vector2i(29, 25), Vector2i(28, 25)]
	if not _must(team.deploy_at(lab.terrain, lab.character, lab.npc, first_cells) and team.enable_combat(false, 0), "First original roster admission"): return
	if not _must(other.deploy_at(lab.terrain, lab.character, lab.npc, second_cells) and other.enable_combat(false, 0), "Second original roster admission"): return
	for index in range(2):
		people.append(team.combat_identity(index))
		enemy_ids.append(other.combat_identity(index))
		team.combat_units[index].logistics = true
		other.combat_units[index].logistics = true
	if not _must(people[0] != enemy_ids[0] and team.faction_id != other.faction_id, "Distinct original opponents"): return
	lab.terrain.site.controlled_person_id = people[0]
	var source: Dictionary = team.combat_units[0]
	# Actual fixture item identity, then the original five-second worn transaction.
	var made: Dictionary = Runtime.create_equipment(lab.terrain, source.item_state, "ship_combat_bow",
		{"slot": "weapon", "asset": "bow_01", "tint": [1.0, 1.0, 1.0, 1.0]}, people[0])
	if not _must(made.ok, "Original bow allocation: " + str(made)): return
	var equipped: Dictionary = lab.site_controller.equipment_orders.begin_personal(people[0], "weapon", str(made.item_id))
	if not _must(equipped.ok, "Original bow wearing: " + str(equipped)) or not _job(people[0]): return
	source.cargo.arrow = 4 # Explicit fixture ammunition belongs to the original row.
	var cargo: Dictionary = source.cargo
	var holder: Dictionary = source.item_state
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var a: Dictionary = vehicles.deploy_ship(team, "ferry", Vector2i(30, 20), Vector2i.UP, true)
	var b: Dictionary = vehicles.deploy_ship(other, "ferry", Vector2i(30, 25), Vector2i.UP, true)
	if not _must(a.ok and b.ok, "Two original test hulls: " + str([a, b])): return
	var first_id := str(a.vehicle_id)
	var second_id := str(b.vehicle_id)
	if not _board_pair(team, people, first_id) or not _board_pair(other, enemy_ids, second_id): return
	var first: Dictionary = vehicles.records()[first_id]
	var second: Dictionary = vehicles.records()[second_id]
	if not _must(vehicles.ship_can_attack(people[0]) and team.exchange_ready(0), "Afloat original archer readiness"): return
	var ground := team.combat_ground(0)
	var source_cell := vehicles.ship_person_cell(people[0])
	var target_cell := vehicles.ship_person_cell(enemy_ids[0])
	if not _must(source_cell != team.cells[0] and not lab.terrain.is_walkable(source_cell), "Ship source stays water; historical shore is not combat position"): return
	if not _must(lab.controlled_attack(enemy_ids[0]), "Controlled original aboard attack order"): return
	var events: Array[Dictionary] = []
	lab.ranged_resolved.connect(func(shooter: int, target: int, result: Dictionary) -> void:
		events.append({"shooter": shooter, "target": target, "result": result.duplicate(true)}))
	lab._resolve_exchanges()
	if not _must(lab.ranged_shots == 1 and team.projectiles.size() == 1 and int(cargo.arrow) == 3, "Original selection releases exactly one real arrow"): return
	var shot: Dictionary = team.projectiles[0]
	if not _must(shot.source_cell == source_cell and shot.target_cell == target_cell and (shot.origin as Vector2).is_equal_approx(ground - Vector2(0, 20) + lab.terrain.surface_visual_offset(source_cell)), "Flight records original launch position and target"): return
	var frozen := shot.duplicate(true)
	lab.bind_terrain(lab.terrain)
	if not _must(team.projectiles.size() == 1 and is_same(team.projectiles[0], shot) and is_same(team.combat_units[0], source), "Active original arrow blocks replacement"): return
	lab._advance_ranged(float(shot.total) + 0.01)
	if not _must(events.size() == 1 and int(events[0].shooter) == people[0] and int(events[0].target) == enemy_ids[0] and not lab.has_ranged_projectiles(), "Arrival finds the actual original aboard opponent"): return
	if not _must(shot.shooter == frozen.shooter and shot.source_cell == frozen.source_cell and shot.target_cell == frozen.target_cell and is_same(cargo, source.cargo) and is_same(holder, source.item_state), "Flight never re-aims or replaces original inventory"): return
	print("SHIP_RANGED_PASS original bow/worn job, water launch, real ammo, target selection and arrival")
	# Original recovery timers advance before the next case; no HP reset/refund.
	for owner: TerrainArmy in [team, other]:
		owner.prepare_combat(4.0, 0.0)
	var actions: SitePersonActions = lab.site_controller.person_actions
	var result: Dictionary = actions.begin_ship_helm(enemy_ids[1], second_id, enemy_ids[1], true)
	if not _must(result.ok, "Original second helm: " + str(result)) or not _job(enemy_ids[1]): return
	if not _must(not vehicles.ship_can_attack(enemy_ids[1]) and not other.start_unit_attack(1, source_cell, people[0]), "Original operator cannot attack while steering"): return
	result = vehicles.ship_order(second_id, "forward", TerrainArmy.INVALID_CELL, enemy_ids[1], true)
	if not _must(result.ok and not second.move.is_empty(), "Original hull step: " + str(result)): return
	vehicles.update_ships(float(second.move.duration) + 0.01)
	if not _must(second.move.is_empty() and lab.terrain.cell_from_index(int(second.cell)) == Vector2i(30, 24), "Original committed hull reaches adjacent water pose"): return
	if not _deck(people[0], Vector2(0, -0.25)) or not _deck(enemy_ids[0], Vector2(0, 3.25)): return
	if not _must(vehicles.ship_combat_contact(people[0], enemy_ids[0]) and team._combat_ship_contact(0, enemy_ids[0]), "Actual deck edge contact across two stopped hulls"): return
	if not _must(lab.controlled_attack(enemy_ids[0]), "Controlled true deck melee selection"): return
	var count := lab.exchange_count
	var hp_before := float(team.combat_hot_get(0, &"hp")) + float(other.combat_hot_get(0, &"hp"))
	lab._resolve_exchanges()
	if not _must(lab.exchange_count > count and float(team.combat_hot_get(0, &"hp")) + float(other.combat_hot_get(0, &"hp")) <= hp_before, "Original exchange batch settles real deck persons"): return
	if not _must(not team._reserve_combat_step(0, team.cells[0] + Vector2i.LEFT) and not team._cell_owners.values().has(0), "Combat does not create a water footstep or historical shore claim"): return
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(team.capture_combat_state()))
	if not _must(snapshot.units[0].ship_deck_position == [0.0, -0.25] and TerrainArmy.valid_combat_state(snapshot, lab.terrain), "Deck position survives strict original JSON roster validation"): return
	for invalid: Variant in [[0], [0, 100], ["0", 0], [0, NAN]]:
		var corrupt := snapshot.duplicate(true)
		corrupt.units[0].ship_deck_position = invalid
		if not _must(not TerrainArmy.valid_combat_state(corrupt, lab.terrain), "Malformed/outside deck position must be rejected: " + str(invalid)): return
	var unowned := snapshot.duplicate(true)
	unowned.units[0].erase("embarked_vehicle_id")
	unowned.units[0].erase("berth_id")
	if not _must(not TerrainArmy.valid_combat_state(unowned, lab.terrain), "Deck coordinate without original boat relation is invalid"): return
	if not _must(int(cargo.arrow) == 3 and is_same(holder, source.item_state) and first.holder.holder == "vehicle:" + first_id, "Melee/geometry cannot duplicate or consume inventory"): return
	print("SHIP_MELEE_SAVE_PASS controlled deck contact, operator guard, original HP/holders, no land path, strict position JSON")
	lab.queue_free()
	await process_frame
	quit(0)
