extends SceneTree
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Vehicles = preload("res://scripts/terrain_lab/site_vehicle_transport.gd")
const OUT := "res://output/site_siege_p0_p1_20261003/legacy_vehicle_fixture"
var deadline := 0
var _run_completed := false
var _run_failed := false

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 60000
	_run.call_deferred()
	_check_run_completion.call_deferred()

func _check_run_completion() -> void:
	# The fixture runs synchronously through its final acceptance assertions.
	# An assertion abort must fail immediately instead of waiting for the deadline.
	if not _run_completed or _run_failed:
		push_error("Vehicle transport contract did not complete its acceptance assertions")
		quit(1)

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("Vehicle transport contract deadline")
		quit(1)
	return false

func _patch(lab: TerrainLab) -> Vector2i:
	for y in range(1, lab.terrain.size.y - 10):
		for x in range(1, lab.terrain.size.x - 10):
			var legal := true
			for row in range(10):
				for column in range(10):
					var cell := Vector2i(x + column, y + row)
					if not lab.terrain.is_walkable(cell) or lab.character.occupies_cell(cell) or lab.npc.occupies_cell(cell): legal = false
					if column > 0 and not lab.terrain.can_step(cell - Vector2i.RIGHT, cell) or row > 0 and not lab.terrain.can_step(cell - Vector2i.DOWN, cell): legal = false
			if legal: return Vector2i(x, y)
	return TerrainArmy.INVALID_CELL

func _finish(team: TerrainArmy) -> void:
	for step in range(25): team.prepare_combat(1.0 / 30.0)
	if team.moving_count() != 0:
		_run_failed = true
		push_error("Original committed vehicle step did not complete: " + str({"cells": team.cells, "moving_to": team.moving_to, "progress": team.move_progress}))
		quit(1)
		return
	assert(team.moving_count() == 0)

func _run() -> void:
	assert(DisplayServer.get_name() == "headless")
	assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
	var lab := TerrainLab.new()
	lab.npc = TerrainTestNPC.new() # Explicit occupancy fixture; formal startup has no default worker.
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	var origin := _patch(lab)
	assert(origin != TerrainArmy.INVALID_CELL, "Vehicle test uses an actual connected original terrain patch")
	var team := lab.army
	team.role = "logistics"
	team.team_id = lab._next_army_identity()
	team.roster_size = 1
	var cells: Array[Vector2i] = [origin + Vector2i(3, 3)]
	assert(team.deploy_at(lab.terrain, lab.character, lab.npc, cells) and team.enable_combat(false, 0))
	lab.terrain.site.army_next_team = team.team_id + 1
	lab.terrain.site.army_trial_active = true
	var transport: Vehicles = lab.site_controller.vehicles
	var commander := team.combat_identity(0)
	var plan := [{"kind": "cart", "team_id": team.team_id, "cell": lab.terrain.index(cells[0] + Vector2i.RIGHT), "facing": [1, 0], "operator_index": 0},
		{"kind": "wagon", "team_id": team.team_id, "cell": lab.terrain.index(origin + Vector2i(1, 7)), "facing": [1, 0], "operator_index": -1}]
	assert(transport.deploy_plan(team, plan).ok)
	var ids := transport.records().keys()
	var cart: Dictionary = transport.records()[ids[0]]
	var wagon: Dictionary = transport.records()[ids[1]]
	assert(transport.is_operator(commander) and int(wagon.operator_id) == 0)
	assert(Vehicles.footprint(lab.terrain, wagon).size() == 3)
	assert(transport.assign_operator(str(wagon.id), commander, commander, true).code == "BUSY")
	var parked_wagon := wagon.duplicate(true)
	assert(team._reserve_combat_step(0, team.cells[0] + Vector2i.RIGHT), "Own old cart cell must not block its genuine operator's forward step")
	team.prepare_combat(0.1)
	assert(not cart.move.is_empty() and transport.render_state(cart).moving and transport.render_state(cart).progress > 0.0)
	lab.site_controller._capture_positions()
	var saved := Store.save(lab.terrain, OUT + "/moving.json")
	assert(saved.ok, str(saved))
	var loaded := Store.load_site(OUT + "/moving.json")
	assert(loaded.ok, str(loaded))
	assert(not loaded.data.site.vehicles[cart.id].move.is_empty())
	var corrupted: Dictionary = lab.terrain.site.duplicate(true)
	corrupted.vehicles[cart.id].move.sweep.pop_back()
	assert(not Store._validate_vehicles(lab.terrain, corrupted, true).ok)
	corrupted = lab.terrain.site.duplicate(true)
	corrupted.vehicles[wagon.id].operator_id = commander
	assert(not Store._validate_vehicles(lab.terrain, corrupted, true).ok, "Saved operator cannot own two vehicles")
	corrupted = lab.terrain.site.duplicate(true)
	corrupted.vehicles[wagon.id].holder = corrupted.vehicles[cart.id].holder.duplicate(true)
	assert(not Store._validate_items(lab.terrain, corrupted).ok, "Saved vehicle holders cannot alias or duplicate original equipment")
	lab.bind_terrain(loaded.data)
	team = lab.army
	transport = lab.site_controller.vehicles
	cart = transport.records()[ids[0]]
	wagon = transport.records()[ids[1]]
	assert(team.moving_count() == 1 and int(cart.operator_id) == commander and not cart.move.is_empty(), "Loading must restore the same original moving person/car pair")
	_finish(team)
	assert(cart.move.is_empty() and lab.terrain.cell_from_index(int(cart.cell)) == team.cells[0] + Vector2i.RIGHT)
	assert(wagon == parked_wagon, "An unoperated wagon cannot follow the moving team")
	assert(team._reserve_combat_step(0, team.cells[0] + Vector2i.LEFT))
	_finish(team)
	assert(cart.facing == [1, 0] and lab.terrain.cell_from_index(int(cart.cell)) == team.cells[0] + Vector2i.RIGHT, "Backing up keeps the vehicle in front without crossing its own operator")
	assert(team._reserve_combat_step(0, team.cells[0] + Vector2i.RIGHT))
	_finish(team)
	# A wall in the conservative 90-degree swept area rejects without any reservation.
	var corner := team.cells[0] + Vector2i(1, 1)
	var block_index := lab.terrain.index(corner)
	var old_block: int = lab.terrain.static_blocked[block_index]
	lab.terrain.static_blocked[block_index] = 1
	var before := cart.duplicate(true)
	assert(not team._reserve_combat_step(0, team.cells[0] + Vector2i.DOWN) and cart == before and team.moving_count() == 0)
	lab.terrain.static_blocked[block_index] = old_block
	assert(team._reserve_combat_step(0, team.cells[0] + Vector2i.DOWN))
	_finish(team)
	assert(cart.facing == [0, 1] and lab.terrain.cell_from_index(int(cart.cell)) == team.cells[0] + Vector2i.DOWN)
	var move_goal := team.cells[0] + Vector2i.RIGHT * 2
	assert(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.MOVE, move_goal).ok)
	# bind_terrain restores the original Coordinator; MOVE proposals must enter
	# through its real Lab caller before the Army advances committed steps.
	for step in range(150): lab._advance_combat(1.0 / 30.0)
	assert(team.cells[0] == move_goal and team.combat_order == TerrainArmy.CombatOrder.HOLD,
		"The existing real team MOVE must drive the operator and cart through its normal local planner")
	assert(lab.terrain.cell_from_index(int(cart.cell)) == move_goal + Vector2i.RIGHT and wagon == parked_wagon)
	# The original operator is present at both inventories; real resources and item IDs move once.
	var original_depot: int = lab.terrain.site.depot_cell
	lab.terrain.site.depot_cell = lab.terrain.index(team.cells[0] + Vector2i.LEFT)
	lab.terrain.site.inventory.grain = 400
	var loading := transport.transfer("depot", str(cart.id), {"grain": 80}, [], int(lab.terrain.site.depot_items.version), int(cart.holder.version), commander, true)
	assert(loading.ok, str(loading))
	assert(int(cart.cargo.grain) == 80 and int(lab.terrain.site.inventory.grain) == 320)
	before = {"depot": lab.terrain.site.inventory.duplicate(), "cargo": cart.cargo.duplicate(), "version": cart.holder.version}
	assert(transport.transfer("depot", str(cart.id), {"grain": 1}, [], int(lab.terrain.site.depot_items.version), int(cart.holder.version), commander).code == "NO_AUTHORITY", "NPC dispatch requires the explicit developer test authority mode")
	assert(not transport.transfer("depot", str(cart.id), {"grain": 1}, [], int(lab.terrain.site.depot_items.version) - 1, int(cart.holder.version), commander, true).ok)
	assert(not transport.transfer("depot", str(cart.id), {"grain": -1}, [], int(lab.terrain.site.depot_items.version), int(cart.holder.version), commander, true).ok)
	assert(not transport.transfer("depot", str(cart.id), {"grain": 21}, [], int(lab.terrain.site.depot_items.version), int(cart.holder.version), commander, true).ok)
	assert(before == {"depot": lab.terrain.site.inventory.duplicate(), "cargo": cart.cargo.duplicate(), "version": cart.holder.version})
	var created := SiteRuntime.create_equipment(lab.terrain, lab.terrain.site.depot_items, "vehicle-test:sword", {"slot": "weapon", "asset": "longsword_01", "tint": [1.0, 1.0, 1.0, 1.0]}, commander)
	assert(created.ok)
	assert(transport.transfer("depot", str(cart.id), {}, [created.item_id], int(lab.terrain.site.depot_items.version), int(cart.holder.version), commander, true).ok)
	assert(lab.terrain.site.item_records[created.item_id].holder == cart.holder.holder)
	assert(transport.transfer(str(cart.id), "depot", {"grain": 20}, [created.item_id], int(cart.holder.version), int(lab.terrain.site.depot_items.version), commander, true).ok)
	assert(int(cart.cargo.grain) == 60 and lab.terrain.site.item_records[created.item_id].holder == "depot")
	lab.terrain.site.depot_cell = original_depot
	# KO does not teleport an already committed pair; it ends operation at that legal endpoint.
	assert(team._reserve_combat_step(0, team.cells[0] + Vector2i.DOWN))
	team.prepare_combat(0.1)
	team.apply_unit_contact(0, {"result": {"hp": 0.0, "stun": 1000.0, "guard_break": false}, "shield": false})
	transport.settle_operators()
	assert(bool(cart.stop_pending) and int(cart.operator_id) == commander)
	assert(not transport.can_park_team(team).ok)
	_finish(team)
	assert(int(cart.operator_id) == 0 and cart.move.is_empty() and int(cart.cargo.grain) == 60)
	assert(transport.park_team(team).ok and int(cart.team_id) == 0 and int(wagon.team_id) == 0)
	team.combat_units[0].ko = 0.0
	team.combat_units[0].stun = 0.0
	team.combat_units[0].pose = "idle"
	team.combat_units[0].exchange_stagger = 0.0
	team._cell_owners[team.cells[0]] = 0
	assert(transport.assign_operator(str(cart.id), commander, commander, true).ok, "Parked cargo can be reclaimed by a real adjacent same-team operator")
	assert(cart.team_id == team.team_id and int(cart.cargo.grain) == 60)
	assert(team.transfer_members_to(lab.opposing_army, [commander], 0).code == "VEHICLES_ATTACHED")
	assert(transport.unassign_operator(str(cart.id), commander, true).ok)
	assert(transport.park_team(team).ok)
	# Walk beside the real horse, then board it through the original person's step.
	var horse_cell := transport.operator_cell(wagon)
	var boarding_cell := horse_cell + Vector2i.UP
	assert(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.MOVE, boarding_cell).ok)
	for step in range(300): lab._advance_combat(1.0 / 30.0)
	assert(team.cells[0] == boarding_cell)
	assert(transport.assign_operator(str(wagon.id), commander, commander, true).ok)
	assert(bool(wagon.move.boarding) and team.cells[0] == boarding_cell and team.moving_to[0] == horse_cell and transport.rider_state(commander).is_empty())
	lab.terrain.site.combat_left = 0.0
	lab.site_controller._capture_positions()
	var boarding_saved: Dictionary = Store.save(lab.terrain, OUT + "/boarding.json")
	assert(boarding_saved.ok, "Boarding snapshot save: " + str(boarding_saved))
	loaded = Store.load_site(OUT + "/boarding.json")
	assert(loaded.ok, str(loaded))
	lab.bind_terrain(loaded.data)
	team = lab.army
	transport = lab.site_controller.vehicles
	cart = transport.records()[ids[0]]
	wagon = transport.records()[ids[1]]
	_finish(team)
	assert(team.cells[0] == horse_cell and transport.operator_cell(wagon) == team.cells[0] and not transport.rider_state(commander).is_empty())
	lab.site_controller._capture_positions()
	var forged_rider: Dictionary = lab.terrain.site.duplicate(true)
	forged_rider.armies[0].units[0].item_state.equipped.erase("weapon")
	assert(Store._validate_vehicles(lab.terrain, forged_rider, true).ok, "A valid unequipped weapon must not require another rider image; mounted cloth is display-only")
	forged_rider.armies[0].units[0].item_state.equipped.weapon = "missing-rider-item"
	assert(Store._validate_vehicles(lab.terrain, forged_rider, true).code == "MISSING_ASSET", "A fixed rider display must still reject a corrupt real holder despite a valid cached appearance")
	team.apply_unit_contact(0, {"result": {"hp": 0.0, "stun": 1000.0, "guard_break": false}, "shield": false})
	lab._advance_action_time(1.0 / 30.0)
	assert(int(wagon.operator_id) == commander and bool(wagon.stop_pending) and wagon.move.is_empty() and transport.rider_state(commander).is_empty(), "A living unconscious rider still occupies its one horse; another person cannot mount")
	var knocked_vehicle := wagon.duplicate(true)
	assert(transport.unassign_operator(str(wagon.id), commander, true).code == "BUSY" and wagon == knocked_vehicle, "A rejected unconscious dismount must retain the original stop flag and every vehicle field")
	assert(not team._reserve_combat_step(0, team.cells[0] + Vector2i.RIGHT))
	lab.terrain.site.combat_left = 0.0
	lab.site_controller._capture_positions()
	var knocked_saved := Store.save(lab.terrain, OUT + "/mounted_ko.json")
	assert(knocked_saved.ok, str(knocked_saved))
	loaded = Store.load_site(OUT + "/mounted_ko.json")
	assert(loaded.ok, str(loaded))
	lab.bind_terrain(loaded.data)
	team = lab.army
	transport = lab.site_controller.vehicles
	cart = transport.records()[ids[0]]
	wagon = transport.records()[ids[1]]
	var active_combat_seconds: float = minf(SiteCombatRules.KNOCKOUT_GAME_SECONDS, float(lab.terrain.site.combat_left))
	lab._advance_action_time(active_combat_seconds + (SiteCombatRules.KNOCKOUT_GAME_SECONDS - active_combat_seconds) / 60.0
		+ float(TerrainArmy.CombatTimings.POSE_SECONDS[&"get_up"]) + 0.5)
	assert(team.combat_can_act(0) and int(wagon.operator_id) == commander and not bool(wagon.stop_pending) and team.cells[0] == horse_cell, "Original KO timer and get-up recover the same rider without a blocked-cell deadlock or another person")
	for actor: TerrainTestCharacter in [lab.character, lab.npc]:
		var actor_state := actor.capture_state()
		assert(str(actor_state.pose) == "idle" and float(actor_state.pose_time) >= 0.0 and float(actor_state.pose_time) < actor._exchange_authored_duration(StringName(str(actor_state.pose))), "Long headless idle must retain its authored loop phase: " + str(actor_state))
		assert(TerrainTestCharacter.valid_state(actor_state, lab.terrain), "Long headless idle must remain an admissible original person state: " + str(actor_state))
	var depot_before_mount: int = lab.terrain.site.depot_cell
	lab.terrain.site.depot_cell = lab.terrain.index(horse_cell + Vector2i.UP)
	assert(transport.transfer("depot", str(wagon.id), {"grain": 10}, [], int(lab.terrain.site.depot_items.version), int(wagon.holder.version), commander, true).ok, "The true mounted person can load its own wagon from the actually adjacent depot")
	assert(transport.transfer(str(wagon.id), "depot", {"grain": 10}, [], int(wagon.holder.version), int(lab.terrain.site.depot_items.version), commander, true).ok)
	lab.terrain.site.depot_cell = depot_before_mount
	assert(team._reserve_combat_step(0, team.cells[0] + Vector2i.LEFT))
	_finish(team)
	assert(wagon.facing == [1, 0] and team.cells[0] == transport.operator_cell(wagon))
	assert(team._reserve_combat_step(0, team.cells[0] + Vector2i.RIGHT))
	_finish(team)
	assert(team._reserve_combat_step(0, team.cells[0] + Vector2i.UP))
	team.prepare_combat(0.1)
	lab.site_controller._capture_positions()
	var mounted_moving_save := Store.save(lab.terrain, OUT + "/mounted_moving.json")
	if not mounted_moving_save.ok:
		var actor_checks: Dictionary = {}
		for key: String in lab.terrain.site.actors:
			var actor: Dictionary = lab.terrain.site.actors[key]
			actor_checks[key] = {"valid": TerrainTestCharacter.valid_state(actor, lab.terrain), "pose": actor.pose, "pose_time": actor.pose_time, "movement_left": actor.movement_left}
		push_error("Mounted moving save rejected: " + JSON.stringify({"result": mounted_moving_save, "combat_left": lab.terrain.site.combat_left, "actor_checks": actor_checks, "actors": lab.terrain.site.actors, "armies": lab.terrain.site.armies, "vehicles": lab.terrain.site.vehicles}))
		quit(1)
		return
	assert(mounted_moving_save.ok, str(mounted_moving_save))
	var mounted_moving_load := Store.load_site(OUT + "/mounted_moving.json")
	if not mounted_moving_load.ok:
		push_error("Mounted moving load rejected: " + str(mounted_moving_load))
		quit(1)
		return
	assert(mounted_moving_load.ok, str(mounted_moving_load))
	assert(transport.unassign_operator(str(wagon.id), commander, true).code == "BUSY")
	_finish(team)
	assert(wagon.facing == [0, -1] and Vehicles.footprint(lab.terrain, wagon)[2] == team.cells[0])
	assert(transport.unassign_operator(str(wagon.id), commander, true).ok)
	assert(bool(wagon.move.dismount) and transport.rider_state(commander).is_empty())
	_finish(team)
	assert(int(wagon.operator_id) == 0 and not Vehicles.footprint(lab.terrain, wagon).has(team.cells[0]))
	assert(transport.park_team(team).ok)
	lab.terrain.site.combat_left = 0.0
	lab.site_controller._capture_positions()
	assert(Store.save(lab.terrain, OUT + "/parked.json").ok)
	loaded = Store.load_site(OUT + "/parked.json")
	assert(loaded.ok and int(loaded.data.site.vehicles[cart.id].cargo.grain) == 60)
	assert(transport.assign_operator(str(wagon.id), commander, commander, true).ok)
	_finish(team)
	team.apply_unit_contact(0, {"result": {"hp": 10000.0, "stun": 0.0, "guard_break": false}, "shield": false})
	transport.settle_operators()
	assert(int(wagon.operator_id) == 0 and wagon.move.is_empty(), "A dead original driver cannot move the wagon")
	assert(not lab.site_controller.supply_save_guard().ok, "Original pending death must settle before clear")
	lab._advance_action_time(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"]) + 0.5)
	assert(lab.site_controller.supply_save_guard().ok, "The original shared clock settles the original driver's death and equipment")
	var original_item_count: int = lab.terrain.site.item_records.size()
	lab.clear_army()
	assert(not team.has_army() and int(cart.team_id) == 0 and int(wagon.team_id) == 0 and int(cart.cargo.grain) == 60, lab.site_controller.message.text)
	assert(lab.terrain.site.item_records.size() == original_item_count, "Actual clear keeps every original equipment record")
	lab.terrain.site.combat_left = 0.0
	lab.site_controller._capture_positions()
	assert(Store.save(lab.terrain, OUT + "/cleared.json").ok)
	loaded = Store.load_site(OUT + "/cleared.json")
	assert(loaded.ok and loaded.data.site.armies.is_empty() and int(loaded.data.site.vehicles[cart.id].cargo.grain) == 60)
	if _run_failed: return
	_run_completed = true
	print("VEHICLE TRANSPORT PASS: actual team MOVE; cart pushing and real horse-cell wagon riding; original one-step mount/dismount; 3-cell reverse/turn/sweep; boarding/moving/KO save-load-bind; mounted KO timer/get-up resumes same rider; real-holder asset admission; authority/version/quantity/capacity rejection; resource/item conservation; death parking and actual clear/reclaim; no extra person or vehicle slot")
	lab.queue_free()
	await process_frame
	quit(0)
