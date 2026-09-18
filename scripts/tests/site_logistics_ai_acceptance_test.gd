extends SceneTree
## Formal main, actual team popup commands, untouched generated terrain and original common clock.
const OUT := "res://output/npc_ai_acceptance_20260918/logistics"
const Vehicles = preload("res://scripts/terrain_lab/site_vehicle_transport.gd")
var deadline := 0
var lab: TerrainLab
var results: Array[Dictionary] = []
var paused_checks := 0
var claim_checks := 0

func _space_safe() -> bool:
	var occupied := {}
	var transport: Vehicles = lab.site_controller.vehicles
	for vehicle: Dictionary in transport.records().values():
		var claims: Dictionary = transport._claims(vehicle)
		for cell: Vector2i in claims:
			if not _check(not occupied.has(cell), "Actual car bodies/sweeps must never overlap during a multi-vehicle command"): return false
			occupied[cell] = vehicle.id
			for team: TerrainArmy in lab.combat_armies:
				for people: Dictionary in [team._cell_owners, team._reserved_cells]:
					if people.has(cell) and not _check(team.combat_identity(int(people[cell])) == int(vehicle.operator_id), "A real reserved sweep cannot pass through another original person"): return false
	claim_checks += 1
	return true

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 105000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("Multi-vehicle logistics acceptance deadline")
		quit(1)
	return false

func _check(value: bool, message: String) -> bool:
	if not value:
		var file := FileAccess.open(OUT + "/result.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"passed":false,"failure":message,"cases":results}, "\t"))
		push_error(message)
		quit(1)
	return value

func _press(name: String) -> void:
	var button := lab.site_controller.combat_window.find_child(name, true, false) as Button
	assert(button != null, name)
	button.pressed.emit()

func _patch(width: int) -> Vector2i:
	for y in range(1, lab.terrain.size.y - width):
		for x in range(1, lab.terrain.size.x - width):
			var legal := true
			for row in range(width):
				for column in range(width):
					var cell := Vector2i(x + column, y + row)
					if not lab.terrain.is_walkable(cell) or lab.character.occupies_cell(cell) or lab.npc.occupies_cell(cell): legal = false
					if column > 0 and not lab.terrain.can_step(cell - Vector2i.RIGHT, cell) or row > 0 and not lab.terrain.can_step(cell - Vector2i.DOWN, cell): legal = false
				if not legal: break
			if legal: return Vector2i(x, y)
	return TerrainArmy.INVALID_CELL

func _state(team: TerrainArmy) -> Dictionary:
	var rows: Array[Dictionary] = []
	for index in range(team.combat_units.size()):
		rows.append({"id":team.combat_identity(index),"cell":[team.cells[index].x,team.cells[index].y],
			"goal":[team.combat_slots[index].x,team.combat_slots[index].y],"moving":team.moving_to[index] != TerrainArmy.INVALID_CELL,
			"operator":lab.site_controller.vehicles.is_operator(team.combat_identity(index))})
	return {"order":team.combat_order,"status":team.command_status,"rows":rows,"vehicles":lab.site_controller.vehicles.records().duplicate(true)}

func _large_anchor() -> Vector2i:
	# Read-only choose an actual original 96-person footprint whose requested goals are real ground.
	for y in range(lab.terrain.size.y - 10):
		for x in range(9, lab.terrain.size.x - 1):
			var anchor := Vector2i(x, y)
			var legal := true
			for offset: Vector2i in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.ONE, Vector2i.DOWN]:
				if not lab._melee_trial_formation_legal(lab._melee_trial_formation(anchor + offset, 96, true), {}):
					legal = false
					break
			if legal: return anchor
	return TerrainArmy.INVALID_CELL

func _camp_anchor() -> Vector2i:
	var depot := lab.terrain.cell_from_index(int(lab.terrain.site.depot_cell))
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var formation := lab._melee_trial_formation(depot + direction, 2, true)
		if not lab._melee_trial_formation_legal(formation, {}): continue
		var plan: Dictionary = lab.site_controller.vehicles.plan_team(1, 1, 1, formation)
		if plan.ok and int(plan.plan[0].operator_index) == 0 and int(plan.plan[1].operator_index) == 1: return depot + direction
	return TerrainArmy.INVALID_CELL

func _camp_load(loading: bool) -> bool:
	var ui: SiteController = lab.site_controller
	ui._refresh_vehicle_controls()
	ui.vehicle_choice.select(0)
	for index in range(ui.vehicle_resource_choice.item_count):
		if ui.vehicle_resource_choice.get_item_metadata(index) == "grain": ui.vehicle_resource_choice.select(index)
	ui.vehicle_resource_quantity.value = 8
	var vehicle := ui._selected_vehicle()
	var before := int(lab.terrain.site.inventory.grain)
	_press("LoadTrialVehicleResources" if loading else "UnloadTrialVehicleResources")
	return _check(int(lab.terrain.site.inventory.grain) == before + (-8 if loading else 8) and int(vehicle.cargo.get("grain", 0)) == (8 if loading else 0), "Actual popup must transfer original grain at original unchanged camp: " + ui.message.text)

func _move_all(team: TerrainArmy, displacement: Vector2i, label: String) -> bool:
	var ui: SiteController = lab.site_controller
	var expected: Array[Vector2i] = []
	for cell: Vector2i in team.cells: expected.append(cell + displacement)
	ui.trial_command_team.select(0)
	ui.selected = Vector2i(team.command_reference.floor()) + displacement
	_press("TrialTeamMove")
	if not _check(team.combat_order == TerrainArmy.CombatOrder.MOVE, label + ": original popup rejected MOVE: " + ui.message.text): return false
	var elapsed := 0.0
	var arrived := false
	var checked_pause := false
	var initial_goods := {}
	for vehicle: Dictionary in ui.vehicles.records().values(): initial_goods[vehicle.id] = [vehicle.holder.duplicate(true), vehicle.cargo.duplicate(true), vehicle.team_id, vehicle.operator_id]
	for tick in range(1800):
		lab._process(1.0 / 30.0)
		if not _space_safe(): return false
		elapsed += 1.0 / 30.0
		if not checked_pause and team.moving_count() > 0:
			checked_pause = true
			ui.toggle_pause()
			var before := {"site":lab.terrain.site.duplicate(true), "team":team.capture_combat_state(), "progress":team.move_progress.duplicate()}
			for frame in range(30): lab._process(1.0 / 30.0)
			if not _check(before == {"site":lab.terrain.site.duplicate(true), "team":team.capture_combat_state(), "progress":team.move_progress.duplicate()}, "Original pause must freeze actual people, cars, reservations, cargo and common time"): return false
			ui.toggle_pause()
			paused_checks += 1
		arrived = team.moving_count() == 0
		for index in range(expected.size()): arrived = arrived and team.cells[index] == expected[index]
		if team.combat_order == TerrainArmy.CombatOrder.HOLD: break
	var state := _state(team)
	state["expected"] = expected.map(func(cell: Vector2i) -> Array: return [cell.x, cell.y])
	state["label"] = label
	state["seconds"] = elapsed
	state["all_original_people_arrived"] = arrived
	results.append(state)
	print("LOGISTICS_AI_CASE ", JSON.stringify(state))
	if not _check(arrived and team.combat_order == TerrainArmy.CombatOrder.HOLD, label + ": every original operator/member must reach its actual assigned goal and finish HOLD, not only the commander"): return false
	for vehicle: Dictionary in ui.vehicles.records().values():
		if not _check(initial_goods[vehicle.id] == [vehicle.holder, vehicle.cargo, vehicle.team_id, vehicle.operator_id], "Every convoy MOVE conserves original goods, holders, bindings and separate slots"): return false
		if int(vehicle.team_id) != team.team_id: continue
		if not _check(int(vehicle.operator_id) > 0 and vehicle.move.is_empty(), label + ": every configured vehicle needs its real operator at rest"): return false
		var person: Dictionary = lab._combat_target(int(vehicle.operator_id))
		if not _check(person.cell == ui.vehicles.operator_cell(vehicle), label + ": vehicle and original person must finish paired"): return false
	return true

func _duties(team: TerrainArmy) -> bool:
	var ui: SiteController = lab.site_controller
	for vehicle: Dictionary in ui.vehicles.records().values():
		var identity := int(vehicle.operator_id)
		var person := ui.person_actions._person(identity)
		var before := team.combat_units.duplicate(true)
		var ids: Array[int] = [identity]
		if not _check(not ui._delivery_person_ready(person) and ui.work_team.assign(team, ids, team.combat_identity(team.current_commander)).code == "BUSY", "Original vehicle operator cannot simultaneously execute a real food delivery or harvest job"): return false
		if not _check(before == team.combat_units and int(vehicle.operator_id) == identity, "Rejected conflicting job cannot erase operator or mutate original people"): return false
	return true

func _probe(slots: int) -> bool:
	var main: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	lab = main.instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	var ui: SiteController = lab.site_controller
	ui.set_process(false)
	ui._auto_save_blocked = true
	ui.release_worker()
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	var width := 10
	var origin := _patch(width)
	if not _check(origin != TerrainArmy.INVALID_CELL, "The actual default terrain needs a connected untouched test area; never flatten it"): return false
	ui.trial_roles.friendly.select(2)
	ui.trial_roles.friendly.item_selected.emit(2)
	ui.trial_roles.enemy.select(2)
	ui.trial_roles.enemy.item_selected.emit(2)
	ui.trial_friendly_count.value = slots
	ui.trial_enemy_count.value = 1
	ui.trial_friendly_female_percent.value = 50
	ui.trial_enemy_female_percent.value = 0
	ui.trial_carts.friendly.value = 1 if slots == 4 else 2
	ui.trial_wagons.friendly.value = 1 if slots == 4 else 2
	ui.trial_friendly_spawn = _camp_anchor() if slots == 4 else (origin + Vector2i(3,3) if slots == 12 else _large_anchor())
	if not _check(ui.trial_friendly_spawn != TerrainArmy.INVALID_CELL, "Find untouched legal 96-person original formation and all three goal formations"): return false
	_press("StartMeleeTrial")
	var team := lab.army
	var cars := 2 if slots == 4 else 4
	if not _check(team.combat_units.size() == slots - cars and ui.vehicles.team_vehicle_count(team) == cars, "Original popup must generate separate people/car slots: " + ui.message.text): return false
	for army: TerrainArmy in lab.combat_armies: army.set_process(false)
	for vehicle: Dictionary in ui.vehicles.records().values():
		if not _check(int(vehicle.operator_id) > 0, "This AI fixture requires four real different operators, not parked substitutes"): return false
	if not _duties(team): return false
	if slots == 4:
		var initial_stock: Dictionary = lab.terrain.site.inventory.duplicate(true)
		var outward := ui.trial_friendly_spawn - lab.terrain.cell_from_index(int(lab.terrain.site.depot_cell))
		if not _camp_load(true): return false
		if not _move_all(team, outward * 3, "Original camp loaded grain / mixed convoy departure"): return false
		if not _move_all(team, -outward * 3, "Original camp loaded grain / return and unload"): return false
		if not _camp_load(false) or not _check(lab.terrain.site.inventory == initial_stock, "Real loaded convoy trip must conserve all original camp resources"): return false
		lab.queue_free()
		await process_frame
		return true
	if not _move_all(team, Vector2i(5 if slots == 12 else 1,0), "%d slots / first mixed convoy MOVE" % slots): return false
	_press("TrialTeamHold")
	if not _move_all(team, Vector2i(0,4 if slots == 12 else 1), "%d slots / 90-degree direction change" % slots): return false
	_press("TrialTeamHold")
	if not _move_all(team, Vector2i(-3 if slots == 12 else -1,0), "%d slots / renewed MOVE after HOLD" % slots): return false
	lab.queue_free()
	await process_frame
	return true

func _run() -> void:
	assert(DisplayServer.get_name() == "headless")
	assert(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/terrain_lab/TerrainLab.tscn")
	assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
	if not await _probe(12): return
	if not await _probe(100): return
	if not await _probe(4): return
	var file := FileAccess.open(OUT + "/result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":true,"cases":results,"paused_checks":paused_checks,"claim_checks":claim_checks}, "\t"))
	print("LOGISTICS AI ACCEPTANCE PASS: actual original popup, mixed four-vehicle multi-person convoys, all-member arrival, turns/HOLD/new orders, original untouched main terrain and common clock")
	quit(0)
