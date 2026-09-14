extends "res://scripts/tests/site_work_team_clock_test.gd"

const CONTROL_SAVE := "res://.godot-temp/site_resources_contract/controlled_person_actions.json"
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const CLOCK_STEP := TerrainLab.EXCHANGE_ACTION_STEP

func _independent_supply_roundtrip(lab: TerrainLab, identity: int, teammate_id: int) -> void:
	var controller: SiteController = lab.site_controller
	var data: TerrainData = lab.terrain
	var team: TerrainArmy = lab.army
	var index := team.index_for_identity(identity)
	var row: Dictionary = team.combat_units[index]
	var cargo: Dictionary = row.cargo
	var holder: Dictionary = row.item_state
	var original_cell := team.cells[index]
	var original_hp := float(row.hp)
	var original_fatigue := float(row.fatigue)
	var original_count := team.combat_units.size()
	# Fresh feeding is initialized at the actual current Site instant. add_members
	# makes the first meal due now; no populated owner is jumped through six hours.
	assert(Runtime.now(data) == 0.0)
	controller._enable_team_supply(team)
	cargo["fish"] = 1 # Explicit fixture stock in this original person's own cargo.
	_press(controller, "LeavePlayerArmy")
	assert(not team.is_member(index) and lab.player_army() == null, controller.message.text)
	assert(team.player_member == lab.npc, "The row's exit cannot remove the separately joined original NPC")
	assert(is_same(team.combat_units[index], row) and is_same(row.cargo, cargo) and is_same(row.item_state, holder))
	assert(team.cells[index] == original_cell and float(row.hp) == original_hp and float(row.fatigue) == original_fatigue)
	var personal: Dictionary = data.site.person_supply[str(identity)]
	assert(Sustain._ids(personal) == [identity] and float(personal.cohorts[0].meal_until) == Runtime.now(data) * 60.0)
	var entry := controller._supply_entry(team)
	entry.inventory["fish"] = 8 # Existing-team fixture stock, not a private transfer.
	assert(Sustain.resupply(entry.sustain, controller._team_members(team), entry.inventory).ok)
	assert(controller.order_team_training(team, team.current_commander, true).ok)
	assert(entry.training_order and not controller._work_person_unavailable(identity))
	assert(controller._work_person_unavailable(teammate_id), "Real members still obey the original training/work exclusion")
	var saved_gear := holder.duplicate(true)
	controller.save_current()
	controller._auto_save_blocked = true
	assert(controller.message.text == "地圖已保存", controller.message.text)
	controller.load_current()
	controller._auto_save_blocked = true
	assert(lab.terrain != data, controller.message.text)
	data = lab.terrain
	team = lab.army
	index = team.index_for_identity(identity)
	row = team.combat_units[index]
	cargo = row.cargo
	holder = row.item_state
	assert(lab.controlled_person_id() == identity and not team.is_member(index) and lab.player_army() == null)
	assert(lab.controlled_target().owner == team and int(lab.controlled_target().unit) == index and team.combat_units.size() == original_count)
	assert(team.cells[index] == original_cell and float(row.hp) == original_hp and float(row.fatigue) == original_fatigue)
	assert(holder == saved_gear and cargo == {"clay": 2, "fish": 1})
	assert(is_same(controller.person_actions._person(identity).cargo, cargo))
	entry = controller._supply_entry(team)
	personal = data.site.person_supply[str(identity)]
	assert(entry.training_order and not controller._work_person_unavailable(identity) and controller._work_person_unavailable(teammate_id))
	var team_stock: Dictionary = entry.inventory.duplicate(true)
	var team_open := float(entry.sustain.open_rations)
	var other_cargo := [data.site.manual.cargo.duplicate(true), data.site.worker.cargo.duplicate(true)]
	var before_version := int(holder.version)
	var personal_before: Dictionary = personal.duplicate(true)
	assert(lab.exchange_enabled and lab._action_time_remainder == 0.0, "Loaded Site starts the original 30Hz clock with no prior phase")
	lab._process(CLOCK_STEP * 0.5)
	assert(Runtime.now(data) == 0.0 and personal == personal_before and float(entry.sustain.at) == 0.0)
	assert(int(cargo.fish) == 1 and int(holder.version) == before_version and entry.inventory == team_stock, "Sub-step input cannot consume a meal early")
	assert(absf(lab._action_time_remainder - CLOCK_STEP * 0.5) <= TerrainLab.ACTION_TIME_EPSILON)
	lab._process(CLOCK_STEP * 0.5) # Two half inputs make one 30Hz step: two peaceful game seconds.
	assert(absf(lab._action_time_remainder) <= TerrainLab.ACTION_TIME_EPSILON)
	_near(Runtime.now(data) * 60.0, 2.0, "independent first meal uses original Site clock")
	_near(float(personal.at), 2.0, "private feeding advances with Site")
	_near(float(entry.sustain.at), 2.0, "old team's feeding advances with Site")
	assert(int(cargo.get("fish", 0)) == 0 and int(cargo.clay) == 2 and Runtime.inventory_size(cargo) == 2)
	_near(float(personal.open_rations), 0.75, "remaining opened food belongs to the original private owner")
	assert(float(personal.cohorts[0].coverage) == 1.0 and float(personal.cohorts[0].hunger) == 0.0)
	assert(int(holder.version) == before_version + 1 and is_same(row.cargo, cargo) and is_same(row.item_state, holder))
	assert(entry.inventory == team_stock and float(entry.sustain.open_rations) == team_open, "The independent person's meal cannot debit the old team's stock")
	assert(data.site.manual.cargo == other_cargo[0] and data.site.worker.cargo == other_cargo[1])
	assert(float(row.fatigue) == original_fatigue, "The independent row is not trained by the former team's order")
	lab._process(CLOCK_STEP)
	_near(Runtime.now(data) * 60.0, 4.0, "next full step advances the same Site clock")
	_near(float(personal.at), 4.0, "private feeding keeps the shared clock")
	assert(absf(lab._action_time_remainder) <= TerrainLab.ACTION_TIME_EPSILON)
	assert(int(holder.version) == before_version + 1 and float(personal.open_rations) == 0.75, "An already paid meal cannot be consumed twice")
	_press(controller, "JoinPlayerArmy")
	assert(team.is_member(index) and lab.player_army() == team and team.player_member == lab.npc, controller.message.text)
	assert(is_same(team.combat_units[index], row) and is_same(row.cargo, cargo) and is_same(row.item_state, holder))
	assert(team.combat_units.size() == original_count and personal.cohorts.is_empty() and float(personal.open_rations) == 0.75)
	assert(identity in Sustain._ids(controller._supply_entry(team).sustain))
	assert(controller._supply_entry(team).inventory == team_stock, "Rejoining moves meal credit, not physical private or team stock")
	assert(controller.order_team_training(team, team.current_commander, false).ok)

func _walk_original(lab: TerrainLab, destination: Vector2i) -> void:
	var person := lab.controlled_target()
	var route := lab.terrain.path_between(person.cell, destination, lab.site_controller.reserves_cell)
	assert(person.cell == destination or not route.is_empty(), "Original person needs an existing legal route")
	lab._run_held = false
	for next: Vector2i in route:
		person = lab.controlled_target()
		lab._try_move(next - Vector2i(person.cell))
		lab._process(ceili(TerrainArmy.MOVE_DURATION / CLOCK_STEP) * CLOCK_STEP)
		assert(absf(lab._action_time_remainder) <= TerrainLab.ACTION_TIME_EPSILON)
		assert(lab.controlled_target().cell == next, "Original movement must commit, not teleport")

func _adjacent_destination(lab: TerrainLab, target: Vector2i) -> Vector2i:
	var person := lab.controlled_target()
	for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var candidate := target + direction
		if not lab.terrain.can_step(candidate, target):
			continue
		if candidate == person.cell:
			return candidate
		if not lab.site_controller.reserves_cell(candidate) and not lab.terrain.path_between(person.cell, candidate, lab.site_controller.reserves_cell).is_empty():
			return candidate
	assert(false, "The natural fixture needs a reachable adjacent cell")
	return TerrainArmy.INVALID_CELL

func _run() -> void:
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.npc_retaliates = false
	var controller: SiteController = lab.site_controller
	controller._auto_save_blocked = true
	var fixture := _work_fixture()
	var data: TerrainData = fixture.data
	lab.bind_terrain(data)
	lab.npc.faction_id = lab.character.faction_id
	var team: TerrainArmy = lab.army
	team.roster_size = 3
	var cells: Array[Vector2i] = []
	cells.assign(fixture.cells)
	assert(team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false))
	team.set_process(false)
	team.faction_id = lab.character.faction_id
	team.settle_combat_command()
	controller.initialize_team_items(team)
	data.site.army_next_team = team.team_id + 1
	var identity := team.combat_identity(1)
	var other_id := team.combat_identity(2)
	var original_npc_id := lab.npc.person_id
	data.site.manual.cargo["stone"] = 7
	data.site.worker.cargo["herb"] = 2
	team.combat_units[1].cargo["clay"] = 2
	team.combat_units[2].cargo["wood"] = 3
	var npc_gear: Dictionary = lab.npc.item_state.duplicate(true)
	var npc_hp := lab.npc.hp
	lab.character.training = 17.0
	lab.npc.training = 23.0
	team.training = 91.0
	assert(float(lab.character.training_query.call()) == 17.0 and float(lab.npc.training_query.call()) == 23.0)
	# Use the actual existing control-bind callback. Family death eligibility is
	# the separate family test's responsibility, not invented in this fixture.
	assert(controller._control_family_person(null, original_npc_id).ok)
	_press(controller, "JoinPlayerArmy")
	assert(team.player_member == lab.npc and team.player_member != lab.character, controller.message.text)
	assert(float(lab.npc.training_query.call()) == team.training and float(lab.character.training_query.call()) == 17.0)
	controller.save_path = CONTROL_SAVE
	controller.save_current()
	controller._auto_save_blocked = true
	assert(controller.message.text == "地圖已保存", "Do not reuse an older file after a rejected save: " + controller.message.text)
	var saved := Store.load_site(CONTROL_SAVE)
	assert(saved.ok, "Controlled NPC membership must save: " + str(saved))
	controller.load_current()
	controller._auto_save_blocked = true
	assert(lab.terrain != data, controller.message.text)
	data = lab.terrain
	team = lab.army
	assert(lab.controlled_person_id() == original_npc_id and team.player_member == lab.npc)
	assert(team.combat_identity(TerrainArmy.PLAYER_MEMBER) == original_npc_id)
	assert(lab.npc.hp == npc_hp and lab.npc.item_state == npc_gear)
	assert(float(lab.npc.training_query.call()) == team.training and float(lab.character.training_query.call()) == 17.0)
	assert(data.site.manual.cargo == {"stone": 7} and data.site.worker.cargo == {"herb": 2})
	_press(controller, "LeavePlayerArmy")
	assert(team.player_member == null and lab.controlled_person_id() == original_npc_id)
	assert(float(lab.npc.training_query.call()) == 23.0 and float(lab.character.training_query.call()) == 17.0)
	_press(controller, "JoinPlayerArmy")
	assert(team.player_member == lab.npc)
	assert(controller._control_family_person(null, identity).ok)
	assert(float(lab.npc.training_query.call()) == team.training and float(lab.character.training_query.call()) == 17.0, "Control identity cannot swap two original actors' training owners")
	_independent_supply_roundtrip(lab, identity, other_id)
	data = lab.terrain
	team = lab.army
	var index := team.index_for_identity(identity)
	var row: Dictionary = team.combat_units[index]
	var cargo: Dictionary = row.cargo
	var main_cargo: Dictionary = data.site.manual.cargo
	var npc_cargo: Dictionary = data.site.worker.cargo
	var original_main_cell := lab.character.terrain_cell
	var origin: Vector2i = team.cells[index]
	var next := TerrainArmy.INVALID_CELL
	for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if data.can_step(origin, origin + direction) and not controller.reserves_cell(origin + direction):
			next = origin + direction
			break
	assert(next != TerrainArmy.INVALID_CELL)
	lab._run_held = false
	lab._try_move(next - origin)
	assert(team.moving_to[index] == next and is_equal_approx(team.move_duration[index], TerrainArmy.MOVE_DURATION))
	assert(team.locomotion_mode[index] == TerrainArmy.Locomotion.WALK)
	var walk_steps := ceili(TerrainArmy.MOVE_DURATION / CLOCK_STEP)
	var halfway_steps := floori(float(walk_steps) * 0.5)
	lab._process(halfway_steps * CLOCK_STEP)
	assert(team.cells[index] == origin and team.moving_to[index] == next)
	lab._process((walk_steps - halfway_steps) * CLOCK_STEP)
	assert(absf(lab._action_time_remainder) <= TerrainLab.ACTION_TIME_EPSILON)
	assert(team.cells[index] == next and team.moving_to[index] == TerrainArmy.INVALID_CELL)
	lab._run_held = true
	lab._try_move(origin - next)
	assert(is_equal_approx(team.move_duration[index], TerrainArmy.RUN_DURATION) and team.locomotion_mode[index] == TerrainArmy.Locomotion.RUN)
	lab._process(ceili(TerrainArmy.RUN_DURATION / CLOCK_STEP) * CLOCK_STEP)
	assert(absf(lab._action_time_remainder) <= TerrainLab.ACTION_TIME_EPSILON)
	assert(team.cells[index] == origin and lab.character.terrain_cell == original_main_cell)
	lab._run_held = false
	var choice := _manual_source(lab, origin)
	assert(not choice.is_empty())
	_walk_original(lab, choice.cell)
	controller.kinds.select(int(choice.kind) + 1)
	controller.select_cell(data.cell_from_index(int(data.resource_base[str(choice.key)].cell)))
	_press(controller, "ManualHarvest")
	assert(controller.work_team.is_assigned(identity) and row.work_task.manual)
	var source_before := int(Env.resource(data, str(choice.key)).remaining)
	lab.controlled_guard(true)
	assert(row.pose == "guard_raise")
	lab._process(CLOCK_STEP)
	assert(not controller.work_team.is_assigned(identity), "Original guard interrupts the original manual task")
	assert(int(cargo.clay) == 2 and Runtime.inventory_size(cargo) == 2 and int(Env.resource(data, str(choice.key)).remaining) == source_before)
	lab._process(1.0)
	assert(row.pose == "guard")
	_press(controller, "ManualHarvest")
	assert(not controller.work_team.is_assigned(identity), "A guarding original body cannot begin work")
	lab.controlled_guard(false)
	assert(row.pose == "guard_lower")
	lab._process(1.0)
	assert(row.pose == "idle")
	_press(controller, "ManualHarvest")
	assert(controller.work_team.is_assigned(identity))
	lab.selected_army_target = identity
	_press(controller, "CancelSelectedWorker")
	assert(row.work_task.is_empty() and is_same(row.cargo, cargo) and int(cargo.clay) == 2 and Runtime.inventory_size(cargo) == 2)
	var depot := data.cell_from_index(int(data.site.depot_cell))
	_walk_original(lab, _adjacent_destination(lab, depot))
	var inventory_before := int(data.site.inventory.get("clay", 0))
	var holder_revision := int(row.item_state.version)
	lab.controlled_guard(true)
	assert(row.pose == "guard_raise")
	_press(controller, "DepositCargo")
	assert(int(cargo.clay) == 2 and Runtime.inventory_size(cargo) == 2 and int(row.item_state.version) == holder_revision)
	lab._process(1.0)
	lab.controlled_guard(false)
	assert(row.pose == "guard_lower")
	lab._process(1.0)
	_press(controller, "DepositCargo")
	assert(cargo.is_empty() and int(data.site.inventory.get("clay", 0)) == inventory_before + 2)
	assert(int(row.item_state.version) == holder_revision + 1)
	assert(is_same(row.cargo, cargo) and is_same(data.site.manual.cargo, main_cargo) and is_same(data.site.worker.cargo, npc_cargo))
	assert(main_cargo == {"stone": 7} and npc_cargo == {"herb": 2})
	# Ground loot is transferred out of another original inventory, never minted
	# from appearance. Cancelling the current row's job must leave both owners.
	var other: Dictionary = team.combat_units[team.index_for_identity(other_id)]
	var ground_cell := _adjacent_destination(lab, team.cells[index])
	var drop := Runtime.leave_ground_loot(data, other.item_state, other.cargo, other_id, ground_cell, "cargo", {"wood": 1}, [], int(other.item_state.version))
	assert(drop.ok)
	assert(controller.person_actions.begin_loot(identity, "ground", str(drop.container_id), {"wood": 1}, []).ok)
	_press(controller, "CancelPersonAction")
	assert(not controller.person_actions.is_busy(identity) and cargo.is_empty())
	assert(data.site.ground_loot[str(drop.container_id)].cargo == {"wood": 1} and other.cargo == {"wood": 2})
	_walk_original(lab, _adjacent_destination(lab, team.cells[team.index_for_identity(other_id)]))
	var main_action := lab.character.action_time
	var target := lab._combat_target(other_id)
	assert(target.owner == team and int(target.unit) == team.index_for_identity(other_id))
	assert(is_same(team.combat_units[int(target.unit)], other) and team.combat_identity(int(target.unit)) == other_id)
	assert(team.cells[index].distance_squared_to(target.cell) == 1 and data.can_attack_across(team.cells[index], target.cell))
	var life_before := [float(row.hp), float(other.hp)]
	var exchanges_before := lab.exchange_count
	assert(lab.controlled_attack(other_id))
	assert(not row.attack and int(row.target) == other_id and lab.character.action_time == main_action, "Exchange mode requests the original target without launching legacy geometry")
	lab._process(CLOCK_STEP)
	assert(absf(lab._action_time_remainder) <= TerrainLab.ACTION_TIME_EPSILON)
	assert(not row.attack and int(row.target) == other_id and lab.character.action_time == main_action)
	assert([float(row.hp), float(other.hp)] == life_before and lab.exchange_count == exchanges_before, "An original same-team target request cannot bypass faction eligibility")
	assert(is_same(controller.person_actions._person(identity).cargo, cargo))
	controller._auto_save_blocked = true
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE CONTROLLED PERSON ACTIONS PASS: original NPC membership/training save/bind, original row UI leave/save/bind/private first meal/30Hz retained phase/stock isolation/rejoin, row walk/run, guard/work cancellation, own cargo deposit, loot cancellation, original exchange target request without legacy attack or friendly damage")
	quit(0)
