extends "res://scripts/tests/site_workflow_test.gd"
## Real Controller callers; pure ship stock partition is tested separately.
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const TrainingFixture = preload("res://scripts/tests/site_training_ground_fixture.gd")
const TrainingGround = preload("res://scripts/terrain_lab/site_training_ground.gd")

func _near(actual: float, expected: float) -> void:
	assert(absf(actual - expected) < 0.000001, "%.12f != %.12f" % [actual, expected])

func _check_shore_training(lab: TerrainLab, team: TerrainArmy, entry: Dictionary) -> void:
	var data: TerrainData = lab.terrain
	var controller: SiteController = lab.site_controller
	assert(data.site.vehicles.is_empty(), "This regression trains original shore people, without a boat fixture")
	for index: int in team.combat_units.size(): assert(not controller.vehicles.is_embarked(team.combat_identity(index)))
	var field := TrainingFixture.build(data, Vector2i(30, 35), Vector2i(10, 10), team.faction_id)
	var positions := TrainingFixture.enter(lab, field)
	team.settle_combat_command()
	var captain := team.current_commander
	assert(captain >= 0 and team.command_eligible(captain))
	var original_control := lab.controlled_person_id()
	data.site.controlled_person_id = team.combat_identity(captain)
	var checked := TrainingGround.inspect(controller, team.team_id, field)
	assert(checked.ok and not checked.eligible_ids.is_empty(), str(checked))
	var other := (captain + 1) % team.combat_units.size()
	var before := var_to_bytes(entry)
	assert(not controller.order_team_training(team, other, true, field).ok, "Another original member cannot issue the command")
	assert(var_to_bytes(entry) == before, "Rejected training never changes supply or history")
	var history := var_to_bytes(entry.sustain)
	var foods := var_to_bytes(entry.locations)
	var locations: Dictionary = entry.locations
	var original_state: Dictionary = entry.sustain
	assert(controller.order_team_training(team, captain, true, field).ok)
	assert(entry.version == 3 and entry.sustain.version == 2 and not entry.has("inventory") and not entry.sustain.has("open_rations"), "Starting shore training must not downgrade positional supply")
	assert(entry.training_order and entry.training_feature_id == field and entry.training_requester == team.combat_identity(captain))
	assert(is_same(entry.locations, locations) and is_same(entry.sustain, original_state))
	assert(var_to_bytes(entry.sustain) == history and var_to_bytes(entry.locations) == foods, "An order cannot reset meals or mint training food")
	var state := data.site.duplicate(true)
	state.armies = [{"team_id": team.team_id, "faction_id": team.faction_id, "units": team.combat_units}]
	assert(Store._validate_supply(state, data).ok, "Active v3 shore training remains valid for original supply saving")
	before = var_to_bytes(entry)
	assert(not controller.order_team_training(team, other, false).ok, "Stopping still requires the original ordering officer")
	assert(var_to_bytes(entry) == before)
	assert(controller.order_team_training(team, captain, false).ok)
	assert(not entry.training_order and entry.training_requester == -1 and entry.training_feature_id.is_empty())
	assert(entry.version == 3 and entry.sustain.version == 2 and not entry.has("inventory") and not entry.sustain.has("open_rations"))
	assert(is_same(entry.locations, locations) and is_same(entry.sustain, original_state))
	assert(var_to_bytes(entry.sustain) == history and var_to_bytes(entry.locations) == foods, "Stopping preserves physical food and exact meal credit")
	state = data.site.duplicate(true)
	state.armies = [{"team_id": team.team_id, "faction_id": team.faction_id, "units": team.combat_units}]
	assert(Store._validate_supply(state, data).ok, "Stopped v3 shore training remains valid for original supply saving")
	TrainingFixture.leave(lab, positions)
	data.site.controlled_person_id = original_control

func _run() -> void:
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	lab.npc = TerrainTestNPC.new() # Original command-test fixture; formal Site has no default worker.
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	for army: TerrainArmy in lab.combat_armies: army.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	var data := _fixture()
	lab.bind_terrain(data)
	var controller: SiteController = lab.site_controller
	controller._auto_save_blocked = true
	controller.release_worker()
	assert(lab.character.place(Vector2i(16, 30), true))
	assert(lab.npc.place(Vector2i(18, 30), true))
	var team: TerrainArmy = lab.army
	team.roster_size = 4
	var cells: Array[Vector2i] = [Vector2i(18, 23), Vector2i(19, 23), Vector2i(18, 24), Vector2i(19, 24)]
	assert(team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false))
	team.set_process(false)
	controller.initialize_team_items(team)
	data.site.army_next_team = team.team_id + 1
	assert(controller._supply_entry(team).is_empty())
	var before := var_to_bytes(data.site.get("team_supply", {}))
	assert(controller.prepare_ship_supply(team, cells[0], true).ok)
	assert(var_to_bytes(data.site.get("team_supply", {})) == before, "Preview does not opt in or mint food")
	assert(not controller.prepare_ship_supply(team, Vector2i(40, 40), true).ok)
	assert(controller._supply_entry(team).is_empty(), "Remote shore cannot choose an anchor")
	# The original action owner keeps the same boarding job until after commit.
	var boarding_id := team.combat_identity(0)
	var boarding_job := controller.person_actions._new_job(controller._supply_person(boarding_id), "ship_board", 0)
	boarding_job.merge({"vehicle_id": "1", "shore": cells[0], "ship_revision": 0, "terrain": data, "site_state": data.site})
	data.site.vehicles["1"] = {"id": "1", "kind": "ship", "team_id": team.team_id, "operator_id": 0, "move": {}, "revision": 0}
	controller.person_actions._jobs[str(boarding_id)] = boarding_job
	assert(not controller.prepare_ship_supply(team, cells[0], true).ok, "Ordinary transactions cannot ignore a boarding job")
	assert(not controller.prepare_ship_supply(team, cells[0], true, boarding_job.duplicate()).ok, "Only the original stored action may be ignored")
	assert(controller.prepare_ship_supply(team, cells[0], true, boarding_job).ok, "Boarding recheck does not collide with its own action")
	data.site.vehicles["1"].move = {"pending": true}
	assert(not controller.prepare_ship_supply(team, cells[0], true, boarding_job).ok, "The exception never ignores a committed ship step")
	data.site.vehicles["1"].move = {}
	var other_id := team.combat_identity(1)
	controller.person_actions._jobs[str(other_id)] = {"kind": "ship_board", "executor_id": other_id}
	assert(not controller.prepare_ship_supply(team, cells[0], true, boarding_job).ok, "Another original ship action remains busy")
	controller.person_actions._jobs.erase(str(other_id))
	assert(controller.prepare_ship_supply(team, cells[0], false, boarding_job).ok)
	controller.person_actions._jobs.erase(str(boarding_id))
	data.site.vehicles.erase("1")
	assert(controller.prepare_ship_supply(team, cells[0]).ok)
	var entry := controller._supply_entry(team)
	assert(entry.version == 3 and entry.sustain.version == 2 and not entry.has("inventory") and not entry.sustain.has("open_rations"))
	assert(Sustain._ids(entry.sustain).size() == 4)
	_near(Sustain.rations(entry.sustain, entry.locations), 0.0)
	var shore_key := "shore:%d" % data.index(cells[0])
	assert(entry.locations.has(shore_key))
	# A valid old land entry converts its one original aggregate exactly once.
	entry.version = 2
	entry.erase("locations")
	entry.inventory = {"grain": 4}
	entry.sustain.version = 1
	entry.sustain.open_rations = 0.5
	var old_snapshot := var_to_bytes(entry)
	assert(controller.prepare_ship_supply(team, cells[0], true).ok)
	assert(var_to_bytes(entry) == old_snapshot)
	assert(controller.prepare_ship_supply(team, cells[0]).ok)
	assert(not entry.has("inventory") and not entry.sustain.has("open_rations"))
	_near(Sustain.rations(entry.sustain, entry.locations), 4.5)
	var location: Dictionary = entry.locations[shore_key]
	var original_stock: Dictionary = location.inventory
	var original_state: Dictionary = entry.sustain
	var snapshot := var_to_bytes(entry)
	assert(controller.prepare_ship_supply(team, cells[0], true).ok)
	assert(var_to_bytes(entry) == snapshot, "Repeated preflight preserves both stock and meal history")
	var map := controller.ship_food_locations(team, controller._team_members(team))
	assert(map.size() == 4)
	assert(map[team.combat_identity(0)] == shore_key and map[team.combat_identity(1)] == shore_key)
	assert(map[team.combat_identity(3)] == "", "Diagonal without original contact cannot eat through walls")
	controller.advance_team_sustain(team, 3600.0)
	data.site.minute = 60
	data.site.phase = 0.0
	_near(float(entry.sustain.at), 3600.0)
	assert(is_same(entry.sustain, original_state) and is_same(entry.locations[shore_key].inventory, original_stock))
	# The fourth original person is remote; only the three reachable people eat.
	_near(Sustain.rations(entry.sustain, entry.locations), 3.75)
	_near(float(entry.sustain.morale), 99.5)
	var identity := team.combat_identity(0)
	var row: Dictionary = team.combat_units[0]
	row.cargo.grain = 2
	var cargo: Dictionary = row.cargo
	var holder: Dictionary = row.item_state
	data.site.controlled_person_id = identity
	assert(team.leave_row(identity).ok)
	var personal: Dictionary = data.site.person_supply[str(identity)]
	assert(personal.version == 1 and personal.has("open_rations") and identity in Sustain._ids(personal))
	assert(identity not in Sustain._ids(entry.sustain) and is_same(row.cargo, cargo) and is_same(row.item_state, holder))
	var shared := Sustain.rations(entry.sustain, entry.locations)
	controller.advance_person_supply(18001.0)
	controller.advance_team_sustain(team, 18001.0)
	data.site.minute = 360
	data.site.phase = 1.0 / 60.0
	assert(Sustain.rations(entry.sustain, entry.locations) < shared)
	assert(row.cargo.grain == 1)
	_near(float(personal.open_rations), 0.75)
	var private_stock := float(personal.open_rations)
	assert(team.join_row(identity).ok)
	assert(personal.cohorts.is_empty() and identity in Sustain._ids(entry.sustain))
	assert(is_same(row.cargo, cargo) and is_same(row.item_state, holder) and row.cargo.grain == 1)
	_near(float(personal.open_rations), private_stock)
	# R1b: leaving the team ends the formal command; a rejoined officer is re-appointed through the original roster path.
	var reseat: Array[int] = []
	reseat.append(0)
	var reseated: Dictionary = team.record_officer_service(reseat, true)
	assert(reseated.ok, str(reseated))
	_check_shore_training(lab, team, entry)
	# Saved positional stock validates against the original terrain and owner.
	var state := data.site.duplicate(true)
	state.armies = [{"team_id": team.team_id, "faction_id": team.faction_id, "units": team.combat_units}]
	assert(Store._validate_supply(state, data).ok)
	var corrupt := state.duplicate(true)
	corrupt.team_supply[str(team.team_id)].inventory = {}
	assert(not Store._validate_supply(corrupt, data).ok)
	corrupt = state.duplicate(true)
	corrupt.team_supply[str(team.team_id)].locations["vehicle:999"] = {"inventory": {}, "open_rations": 0.0}
	assert(not Store._validate_supply(corrupt, data).ok)
	var completed_in_time: bool = _finish_workflow_body()
	lab.queue_free()
	if not completed_in_time or _workflow_deadline_failed: return
	print("SITE SHIP SUPPLY FLOW PASS: zero-food first opt-in, no remote migration, positional Controller meal/clock, original row leave/join private stocks, original shore training start/stop authority without v3 downgrade or free food, active/stopped supply save validation and versioned save rejection")
	quit(0)
