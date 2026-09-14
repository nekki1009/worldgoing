extends "res://scripts/tests/site_workflow_test.gd"

const CLOCK_SAVE := "res://.godot-temp/site_resources_contract/work_team_clock.json"
const WorkTeam = preload("res://scripts/terrain_lab/site_work_team.gd")

func _near(actual: float, expected: float, label: String) -> void:
	assert(absf(actual - expected) < 0.00001, "%s: %.12f != %.12f" % [label, actual, expected])

func _press(controller: SiteController, button_name: String) -> void:
	var button := controller.panel.find_child(button_name, true, false) as Button
	assert(button != null, "Actual controller button missing: " + button_name)
	button.pressed.emit()

func _work_fixture() -> Dictionary:
	# Keep the real generated base intact so the normal Store can regenerate it.
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345, {"size": Vector2i(48, 48)})
	Env.initialize(data, "work-team-common-clock")
	data.site.worker_enabled = false
	var keys := data.resource_base.keys()
	keys.sort()
	for kind: int in [Env.Kind.HERB, Env.Kind.TIMBER, Env.Kind.STONE]:
		for first_key: String in keys:
			var first := Env.resource(data, first_key)
			if int(first.kind) != kind or int(first.remaining) < int(Env.BATCH[kind]):
				continue
			for second_key: String in keys:
				var second := Env.resource(data, second_key)
				if second_key <= first_key or int(second.kind) != kind or int(second.remaining) < int(Env.BATCH[kind]):
					continue
				var source_a := data.cell_from_index(int(first.cell))
				var source_b := data.cell_from_index(int(second.cell))
				if source_a.distance_squared_to(source_b) > 64.0:
					continue
				for worker_a: Vector2i in Env.work_cells(data, first_key):
					for worker_b: Vector2i in Env.work_cells(data, second_key):
						if worker_a == worker_b or worker_a == data.spawn_cell or worker_b == data.spawn_cell:
							continue
						var route := data.path_between(worker_a, worker_b)
						if route.is_empty() or route.size() > 10:
							continue
						var reserved: Array[Vector2i] = [worker_a, worker_b, data.spawn_cell]
						var captain := _nearby_free(data, worker_a, reserved, 1, 4)
						if captain == TerrainArmy.INVALID_CELL:
							continue
						reserved.append(captain)
						var depot := _nearby_free(data, worker_a, reserved, 3, 8, worker_b)
						if depot == TerrainArmy.INVALID_CELL:
							continue
						data.site.depot_cell = data.index(depot)
						var rectangle := Rect2i(Vector2i(mini(source_a.x, source_b.x), mini(source_a.y, source_b.y)), Vector2i(absi(source_a.x - source_b.x) + 1, absi(source_a.y - source_b.y) + 1))
						assert(Runtime.add_zone(data, rectangle, kind).ok)
						return {"data": data, "kind": kind, "cells": [captain, worker_a, worker_b]}
	assert(false, "The generated fixture needs two nearby real nonfood resources")
	return {}

func _nearby_free(data: TerrainData, origin: Vector2i, reserved: Array[Vector2i], minimum: int, maximum: int, other: Vector2i = TerrainArmy.INVALID_CELL) -> Vector2i:
	for radius in range(minimum, maximum + 1):
		for y in range(origin.y - radius, origin.y + radius + 1):
			for x in range(origin.x - radius, origin.x + radius + 1):
				var cell := Vector2i(x, y)
				if absi(x - origin.x) + absi(y - origin.y) != radius or reserved.has(cell) or not data.is_walkable(cell):
					continue
				if other != TerrainArmy.INVALID_CELL and (absi(cell.x - other.x) + absi(cell.y - other.y) < minimum or data.path_between(other, cell).is_empty()):
					continue
				var route := data.path_between(origin, cell)
				if not route.is_empty() and route.size() <= maximum + 2:
					return cell
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
	data.site.army_next_team = team.team_id + 1
	var identities: Array[int] = [team.combat_identity(1), team.combat_identity(2)]
	lab.selected_army_target = identities[0]
	_press(controller, "AssignSelectedWorker")
	assert(team.combat_units[1].get("work_task", {}).is_empty(), "Original player identity alone cannot order another team's workers")
	# This fixture selects the existing captain through the real control-bind
	# callback. Death-only family selection is verified by its separate test.
	assert(controller._control_family_person(null, team.combat_identity(team.current_commander)).ok)
	for identity: int in identities:
		lab.selected_army_target = identity
		_press(controller, "AssignSelectedWorker")
		assert(controller.work_team.is_assigned(identity))
	for frame in range(12):
		lab._process(1.0 / 60.0)
	var first: Dictionary = team.combat_units[1]
	var second: Dictionary = team.combat_units[2]
	assert(first.work_task.mode == "work" and second.work_task.mode == "work")
	assert(first.work_task.target != second.work_task.target)
	_near(Runtime.now(data) * 60.0, 12.0, "normal frame common clock")
	_near(float(first.work_task.progress), 0.2, "first original worker productive time")
	_near(float(second.work_task.progress), 0.2, "second original worker productive time")
	_near(float(first.fatigue), 12.0 * PersonFatigue.WORK_RATE, "one work fatigue charge")
	var frozen := JSON.stringify([first.work_task, second.work_task, first.fatigue, second.fatigue, data.site.minute, data.site.phase, data.site.inventory])
	controller.toggle_pause()
	lab._process(1.0)
	assert(frozen == JSON.stringify([first.work_task, second.work_task, first.fatigue, second.fatigue, data.site.minute, data.site.phase, data.site.inventory]))
	controller.toggle_pause()
	lab._process(0.5)
	_near(float(first.work_task.progress), 0.7, "slow frame is still sliced by original Lab")
	_near(float(first.fatigue), 42.0 * PersonFatigue.WORK_RATE, "slow frame neither rests nor double-charges work")
	controller.save_path = CLOCK_SAVE
	controller.save_current()
	controller._auto_save_blocked = true
	print("WORK_CLOCK_SAVE ", controller.message.text)
	assert(FileAccess.file_exists(CLOCK_SAVE))
	var saved_work := [first.work_task.duplicate(true), second.work_task.duplicate(true)]
	var saved_clock := Runtime.now(data)
	var json_state: Dictionary = JSON.parse_string(JSON.stringify(data.site))
	for work: Dictionary in saved_work:
		assert(WorkTeam.valid_task(data, json_state, JSON.parse_string(JSON.stringify(work))), "JSON number representation must preserve actual work-zone references")
	controller.load_current()
	controller._auto_save_blocked = true
	print("WORK_CLOCK_LOAD ", controller.message.text, " combat_left=", data.site.combat_left)
	assert(lab.terrain != data and lab.terrain.site.id == data.site.id, "Normal Controller load must bind the real saved Site")
	data = lab.terrain
	team = lab.army
	first = team.combat_units[team.index_for_identity(identities[0])]
	second = team.combat_units[team.index_for_identity(identities[1])]
	for index in range(2):
		var row: Dictionary = first if index == 0 else second
		assert(controller.work_team.is_assigned(identities[index]))
		assert(row.work_task.target == saved_work[index].target)
		_near(float(row.work_task.progress), float(saved_work[index].progress), "saved original task progress")
	_near(Runtime.now(data), saved_clock, "load cannot advance Site work time")
	lab._process(0.25)
	_near(float(first.work_task.progress), 0.95, "loaded worker resumes same work")
	# Inject only the boundary state, not 90 minutes of invented work/recovery.
	first.fatigue = 79.999
	lab._process(0.1)
	assert(bool(first.work_resting) and first.work_task.mode == "rest")
	var rest_progress := float(first.work_task.progress)
	lab._process(0.1)
	_near(float(first.fatigue), 80.0, "80 stop and initial safe-rest delay")
	_near(float(first.work_task.progress), rest_progress, "rest cannot make output progress")
	first.fatigue = 50.01
	first.fatigue_rest = PersonFatigue.REST_DELAY
	lab._process(0.01)
	assert(first.work_resting and first.work_task.progress == rest_progress)
	lab._process(0.05)
	assert(not first.work_resting and float(first.work_task.progress) > rest_progress, "Original safe recovery crosses 50 before the same order resumes")
	first.fatigue = 0.0 # End the boundary fixture; both subsequent batches stay fresh.
	var item := str(Env.ITEMS[int(fixture.kind)])
	var batch := int(Env.BATCH[int(fixture.kind)])
	var depot_before := int(data.site.inventory.get(item, 0))
	var original_cargos := [first.cargo, second.cargo]
	var observed_cargo := {}
	var deposited := {}
	var saw_original_step := false
	for frame in range(220):
		lab._process(0.05)
		for identity: int in identities:
			var index := team.index_for_identity(identity)
			var row: Dictionary = team.combat_units[index]
			if team.moving_to[index] != TerrainArmy.INVALID_CELL:
				saw_original_step = true
				assert(data.can_step(team.cells[index], team.moving_to[index]))
				assert(int(team._reserved_cells.get(team.moving_to[index], -1)) == index)
			if int(row.cargo.get(item, 0)) == batch:
				observed_cargo[identity] = true
			if observed_cargo.has(identity) and row.cargo.is_empty() and not deposited.has(identity):
				deposited[identity] = true
				lab.selected_army_target = identity
				_press(controller, "CancelSelectedWorker")
		if deposited.size() == 2:
			break
	assert(observed_cargo.size() == 2 and deposited.size() == 2 and saw_original_step)
	assert(int(data.site.inventory.get(item, 0)) == depot_before + batch * 2)
	assert(is_same(first.cargo, original_cargos[0]) and is_same(second.cargo, original_cargos[1]))
	assert(data.site.manual.cargo.is_empty() and data.site.worker.cargo.is_empty())
	assert(first.work_task.is_empty() and second.work_task.is_empty())
	# Finish a step already committed before cancellation, never snap it back.
	lab._process(TerrainArmy.MOVE_DURATION + 0.00001)
	data.site.manual.cargo["stone"] = 2
	data.site.worker.cargo["wood"] = 1
	first.cargo["clay"] = 1
	_manual_original(lab, lab.npc.person_id, data.site.worker.cargo)
	_manual_original(lab, identities[0], first.cargo)
	assert(data.site.manual.cargo == {"stone": 2})
	assert(data.site.worker.cargo.get("wood", 0) >= 1 and first.cargo.get("clay", 0) >= 1)
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE WORK TEAM CLOCK PASS: real Controller buttons and Lab common clock, two original workers/native paths/separate cargo/depot, normal and slow frames, pause, 80/50 boundary recovery, real save/load/bind resume, controlled NPC and row one-shot manual gathering without cargo swaps; not full family selection or visual/performance proof")
	quit(0)

func _manual_original(lab: TerrainLab, identity: int, expected_cargo: Dictionary) -> void:
	var controller: SiteController = lab.site_controller
	assert(controller._control_family_person(null, identity).ok)
	var person := controller.person_actions._person(identity)
	var choice := _manual_source(lab, Vector2i(person.cell))
	assert(not choice.is_empty(), "Original controlled body needs a reachable real source")
	var start: Vector2i = person.cell
	var route := lab.terrain.path_between(start, choice.cell, controller.reserves_cell)
	assert(start == choice.cell or not route.is_empty())
	for next: Vector2i in route:
		person = controller.person_actions._person(identity)
		lab._try_move(next - Vector2i(person.cell))
		lab._process(TerrainArmy.MOVE_DURATION + 0.00001)
		assert(controller.person_actions._person(identity).cell == next)
	person = controller.person_actions._person(identity)
	controller.person_actions._body_set(person, "fatigue", 90.0)
	controller.person_actions._body_set(person, "work_resting", true)
	var others := [lab.terrain.site.manual.cargo.duplicate(true), lab.terrain.site.worker.cargo.duplicate(true), lab.army.combat_units[1].cargo.duplicate(true)]
	var stock: Dictionary = expected_cargo.duplicate(true)
	var item := str(Env.ITEMS[int(choice.kind)])
	var batch := int(Env.BATCH[int(choice.kind)])
	controller.kinds.select(int(choice.kind) + 1)
	controller.select_cell(lab.terrain.cell_from_index(int(lab.terrain.resource_base[str(choice.key)].cell)))
	assert(controller.source_key == str(choice.key))
	_press(controller, "ManualHarvest")
	assert(bool(lab.terrain.site.worker.get("manual_control", false)) if int(person.unit) < 0 else bool(person.body.work_task.get("manual", false)))
	lab._process(0.05)
	assert(float(controller.person_actions._body_get(person, "fatigue")) > 90.0, "Controlled NPC and row manual work both bypass automatic 80-rest")
	for frame in range(180):
		lab._process(0.05)
		var active := bool(lab.terrain.site.worker.get("manual_control", false)) if int(person.unit) < 0 else controller.work_team.is_assigned(identity)
		if not active:
			break
	assert(is_same(controller.person_actions._person(identity).cargo, expected_cargo))
	assert(int(expected_cargo.get(item, 0)) == int(stock.get(item, 0)) + batch)
	assert(lab.terrain.site.manual.cargo == others[0])
	if int(person.unit) < 0:
		assert(lab.army.combat_units[1].cargo == others[2])
	else:
		assert(lab.terrain.site.worker.cargo == others[1])
	var completed: Dictionary = expected_cargo.duplicate(true)
	lab._process(0.1)
	assert(expected_cargo == completed and controller.person_actions._person(identity).cell == choice.cell, "A manual batch cannot auto-walk, auto-deposit, or select another target")

func _manual_source(lab: TerrainLab, from: Vector2i) -> Dictionary:
	var keys := lab.terrain.resource_base.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return lab.terrain.cell_from_index(int(lab.terrain.resource_base[a].cell)).distance_squared_to(from) < lab.terrain.cell_from_index(int(lab.terrain.resource_base[b].cell)).distance_squared_to(from))
	for key: String in keys:
		var resource := Env.resource(lab.terrain, key)
		if int(resource.kind) not in [Env.Kind.HERB, Env.Kind.TIMBER, Env.Kind.STONE, Env.Kind.CLAY] or bool(resource.cleared) or int(resource.remaining) < int(Env.BATCH[int(resource.kind)]):
			continue
		for cell: Vector2i in Env.work_cells(lab.terrain, key):
			if cell != from and lab.site_controller.reserves_cell(cell):
				continue
			var route := lab.terrain.path_between(from, cell, lab.site_controller.reserves_cell)
			if cell == from or not route.is_empty() and route.size() <= 14:
				return {"key": key, "cell": cell, "kind": int(resource.kind)}
	return {}
