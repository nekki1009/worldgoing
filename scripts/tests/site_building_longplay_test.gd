extends SceneTree
## Original TerrainLab clock, original GD people and original Store across three game days.
## No Runtime.advance/Sustain.advance second clock or replacement work/food simulation.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Stocks = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const Housing = preload("res://scripts/terrain_lab/site_housing.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const MAIN := "res://scenes/terrain_lab/TerrainLab.tscn"
const OUT := "res://output/site_building_close_20261004/longplay/"
var lab: TerrainLab
var team_id: int = -1
var courier: int = -1
var worker_ids: Array[int] = []
var house: String = ""
var warehouse: String = ""
var weaver: String = ""
var folder: String = ""
var save_path: String = ""
var deadline_us: int = 0
var finished: bool = false
var expected_materials: Dictionary = {}
var initial_items: Array = []
var initial_people: Array = []
var food_at: float = 0.0
var food_baseline: float = 0.0
var report: Dictionary = {"status": "PREPARING", "costs": [], "checkpoints": [], "hp_history": [], "sources": {}}

func _initialize() -> void:
	deadline_us = Time.get_ticks_usec() + 600000000
	folder = OUT + "%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	assert(DirAccess.make_dir_recursive_absolute(folder) == OK)
	_launch.call_deferred()

func _launch() -> void:
	await _run()
	if not finished: _finish("FAILED", "Original assertion aborted the active phase; inspect the retained canonical error")

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_usec() >= deadline_us: _finish("TIMEOUT", "600-second internal deadline")
	return false

func _team() -> TerrainArmy:
	for team: TerrainArmy in lab.combat_armies:
		if team.team_id == team_id and team.combat_enabled: return team
	return null

func _data() -> TerrainData:
	return lab.terrain

func _controller() -> SiteController:
	return lab.site_controller

func _sources() -> Dictionary:
	var hashes: Dictionary = {}
	for path: String in [MAIN, "res://project.godot", "res://scripts/terrain_lab/terrain_lab.gd", "res://scripts/terrain_lab/terrain_generator.gd",
		"res://scripts/terrain_lab/terrain_data.gd", "res://scripts/terrain_lab/terrain_army.gd", "res://scripts/terrain_lab/terrain_test_character.gd",
		"res://scripts/terrain_lab/terrain_test_npc.gd", "res://scripts/terrain_lab/person_fatigue.gd", "res://scripts/terrain_lab/site_runtime.gd",
		"res://scripts/terrain_lab/site_controller.gd", "res://scripts/terrain_lab/site_store.gd", "res://scripts/terrain_lab/site_work_team.gd",
		"res://scripts/terrain_lab/site_stockpiles.gd", "res://scripts/terrain_lab/site_sustain.gd", "res://scripts/terrain_lab/site_food_delivery.gd",
		"res://scripts/terrain_lab/site_captivity_supply.gd", "res://scripts/terrain_lab/site_person_actions.gd", "res://scripts/terrain_lab/site_vehicle_transport.gd",
		"res://scripts/terrain_lab/site_housing.gd", "res://scripts/region_lab/region_save_slot.gd", "res://scripts/tests/site_building_longplay_test.gd"]:
		hashes[path] = FileAccess.get_sha256(path)
	return hashes

func _freeze_automatic_process() -> void:
	lab.set_process(false)
	lab.character.set_process(false)
	if is_instance_valid(lab.npc): lab.npc.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	_controller()._auto_save_blocked = true

func _step() -> bool:
	# The same bounded manual common-clock entry used by site_work_team_clock_test.
	# The original 0.5/1/2/4 speed setting applies inside TerrainLab.
	var before: float = Runtime.now(_data())
	lab._process(0.25)
	var fault: Dictionary = _controller().original_step_fault_guard()
	if not fault.ok:
		_finish("STEP_FAULT", str(fault.message))
		return false
	if Runtime.now(_data()) <= before:
		_finish("CLOCK_STOPPED", "The original common clock did not advance an unpaused 0.25-second manual step")
		return false
	return true

func _until(predicate: Callable, maximum_minutes: float, label: String) -> bool:
	var until: float = Runtime.now(_data()) + maximum_minutes
	var steps: int = 0
	while not bool(predicate.call()):
		if finished: return false
		if Time.get_ticks_usec() >= deadline_us or Runtime.now(_data()) >= until:
			_finish("FAILED", label + " exceeded original game-time/wall deadline")
			return false
		if not _step(): return false
		steps += 1
		if steps % 32 == 0: await process_frame
	return true

func _charge(label: String, before: Dictionary, cost: Dictionary) -> void:
	for item: String in Env.ITEM_NAMES:
		assert(int(_data().site.inventory.get(item, 0)) == int(before.get(item, 0)) - int(cost.get(item, 0)), label + ": original debit mismatch for " + item)
	for item: String in cost:
		expected_materials[item] = int(expected_materials.get(item, 0)) - int(cost[item])
	report.costs.append({"label": label, "at": Runtime.now(_data()), "cost": cost.duplicate(true)})

func _construct(kind: String) -> String:
	var data: TerrainData = _data()
	var options: Dictionary = {"owner_faction": lab.character.faction_id, "quarter": 0, "variant": "small"}
	var anchors: Array[Vector2i] = []
	for y: int in range(4, data.size.y - 5, 4):
		for x: int in range(4, data.size.x - 5, 4): anchors.append(Vector2i(x, y))
	var depot: Vector2i = data.cell_from_index(int(data.site.depot_cell))
	anchors.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.distance_squared_to(depot) < b.distance_squared_to(depot))
	for anchor: Vector2i in anchors:
		var cells: Dictionary = Runtime.building_cells(data, kind, anchor, Vector2i.ONE, options)
		if not cells.ok: continue
		var preview: Dictionary = Runtime.preview_build(data, kind, cells.cells, _controller().reserves_cell, options)
		if not preview.ok: continue
		var before: Dictionary = data.site.inventory.duplicate(true)
		var result: Dictionary = Runtime.request_build(data, kind, cells.cells, _controller().reserves_cell, options)
		assert(result.ok, str(result))
		_charge("build:" + kind, before, preview.cost)
		var key: String = str(result.feature)
		_controller().enable_worker()
		if not await _until(func() -> bool: return str(_data().site.features[key].stage) == "complete", 150.0, "original NPC builds " + kind): return ""
		var completed: Dictionary = _data().site.features[key]
		assert(float(completed.progress) <= float(completed.work) and float(completed.progress) + 0.00000001 >= float(completed.work), "Completed original construction must meet the unchanged Runtime work boundary without overshoot")
		_controller().release_worker()
		return key
	_finish("NO_SPACE", "Original generated-base placement rejected " + kind)
	return ""

func _logistics_spawn() -> Vector2i:
	var data: TerrainData = _data()
	var depot: Vector2i = data.cell_from_index(int(data.site.depot_cell))
	for radius: int in range(2, 9):
		for y: int in range(depot.y - radius, depot.y + radius + 1):
			for x: int in range(depot.x - radius, depot.x + radius + 1):
				var anchor: Vector2i = Vector2i(x, y)
				if absi(x - depot.x) + absi(y - depot.y) != radius: continue
				var formation: Array[Vector2i] = lab._third_trial_formation(anchor, 3)
				if not lab._melee_trial_formation_legal(formation, {}): continue
				var reachable: bool = true
				for cell: Vector2i in formation:
					if _data().path_between(cell, depot).is_empty(): reachable = false
				if reachable: return anchor
	return TerrainArmy.INVALID_CELL

func _stocks() -> Array[Dictionary]:
	var data: TerrainData = _data()
	var result: Array[Dictionary] = []
	var candidates: Array[Dictionary] = [data.site.inventory, data.site.manual.cargo, data.site.worker.cargo]
	for team: TerrainArmy in lab.combat_armies:
		for row: Dictionary in team.combat_units: candidates.append(row.cargo)
	for stock: Dictionary in data.site.get("stockpiles", {}).values(): candidates.append(stock.cargo)
	for vehicle: Dictionary in data.site.get("vehicles", {}).values(): candidates.append(vehicle.cargo)
	for container: Dictionary in data.site.get("ground_loot", {}).values(): candidates.append(container.cargo)
	for entry: Dictionary in data.site.get("team_supply", {}).values():
		if int(entry.version) == 3:
			for location: Dictionary in entry.locations.values(): candidates.append(location.inventory)
		else: candidates.append(entry.inventory)
	for cargo: Dictionary in candidates:
		var already: bool = false
		for original: Dictionary in result:
			if is_same(cargo, original): already = true; break
		if not already: result.append(cargo)
	return result

func _materials() -> Dictionary:
	var totals: Dictionary = {}
	for cargo: Dictionary in _stocks():
		for item: String in cargo: totals[item] = int(totals.get(item, 0)) + int(cargo[item])
	return totals

func _food_total() -> float:
	var total: float = 0.0
	for cargo: Dictionary in _stocks():
		for item: String in Sustain.FOODS: total += float(cargo.get(item, 0))
	for container: Dictionary in _data().site.get("ground_loot", {}).values(): total += float(container.get("open_rations", 0.0))
	for entry: Dictionary in _data().site.get("team_supply", {}).values():
		if int(entry.version) == 3:
			for location: Dictionary in entry.locations.values(): total += float(location.open_rations)
		else: total += float(entry.sustain.open_rations)
	for state: Dictionary in _data().site.get("person_supply", {}).values(): total += float(state.get("open_rations", 0.0))
	for wrapped: Dictionary in _controller().captivity_supply._states(false).values():
		for cohort: Dictionary in wrapped.state.cohorts:
			total += cohort.ids.size() * float(cohort.coverage) * (float(cohort.meal_until) - float(wrapped.state.at)) / Sustain.DAY
	return total

func _meal_snapshot(expected_site: Variant = null) -> Dictionary:
	# Explicit original numerical fields, retained as evidence only.
	var result: Dictionary = {}
	var states: Dictionary = {}
	if expected_site == null:
		states = _controller().captivity_supply._states(false)
	else:
		assert(expected_site is Dictionary)
		for identity: String in expected_site.get("team_supply", {}):
			states["team:" + identity] = {"state": expected_site.team_supply[identity].sustain}
		for identity: String in expected_site.get("person_supply", {}):
			states["person:" + identity] = {"state": expected_site.person_supply[identity]}
	for key: String in states:
		var state: Dictionary = states[key].state
		var cohorts: Array[Dictionary] = []
		for cohort: Dictionary in state.cohorts:
			var ids: Array[int] = []
			for identity: Variant in cohort.ids: ids.append(int(identity))
			cohorts.append({"ids": ids, "hunger": float(cohort.hunger), "coverage": float(cohort.coverage),
				"meal_until": float(cohort.meal_until), "bonus_paid": bool(cohort.bonus_paid), "bonus_pending": bool(cohort.bonus_pending),
				"unused_eaten_credit": ids.size() * float(cohort.coverage) * (float(cohort.meal_until) - float(state.at)) / Sustain.DAY})
		result[key] = {"version": int(state.version), "at": float(state.at), "cohorts": cohorts,
			"morale": float(state.morale), "routed": bool(state.routed), "regroup_seconds": float(state.regroup_seconds),
			"commander_present": bool(state.commander_present), "last_combat_event": int(state.last_combat_event)}
	return result

func _people() -> Array:
	var people: Array[int] = []
	var seen: Dictionary = {}
	for actor: TerrainTestCharacter in lab.combat_actors:
		assert(not seen.has(actor.person_id))
		seen[actor.person_id] = true
		people.append(actor.person_id)
	for team: TerrainArmy in lab.combat_armies:
		for row: Dictionary in team.combat_units:
			assert(not seen.has(int(row.person_id)), "Original person duplicated in live owner graph")
			seen[int(row.person_id)] = true
			people.append(int(row.person_id))
	people.sort()
	return people

func _hp() -> Dictionary:
	var result: Dictionary = {}
	for identity: int in _people():
		var person: Dictionary = _controller().person_actions._person(identity)
		assert(not person.is_empty() and float(person.hp) == 100.0 and float(person.ko) == 0.0, "Fed peaceful original person unexpectedly lost HP")
		result[str(identity)] = {"hp": float(person.hp), "ko": float(person.ko)}
	return result

func _check_balances(label: String, food: bool = true) -> bool:
	var actual: Dictionary = _materials()
	for item: String in Env.ITEM_NAMES:
		if item in Sustain.FOODS or item in ["fiber", "rope"]: continue
		assert(int(actual.get(item, 0)) == int(expected_materials.get(item, 0)), label + ": material conservation " + item)
	# Each paid rope batch has consumed 2 fiber and owns exactly 2 unfinished rope.
	var paid_output: int = 2 if not weaver.is_empty() and bool(_data().site.features[weaver].batch_paid) else 0
	assert(int(actual.get("fiber", 0)) + int(actual.get("rope", 0)) + paid_output == int(expected_materials.get("fiber", 0)) + int(expected_materials.get("rope", 0)), label + ": original paid/output fiber-rope conservation")
	assert(_people() == initial_people, label + ": original IDs changed")
	assert(_data().site.item_records.keys().size() == initial_items.size())
	for item: Variant in initial_items: assert(_data().site.item_records.has(item), label + ": original equipment lost")
	assert(_controller()._capture_for_save().ok)
	var item_check: Dictionary = Store._validate_items(_data(), _data().site)
	assert(item_check.ok, str(item_check))
	var states: Dictionary = _controller().captivity_supply._states(false)
	var original_states: Array = []
	var keys: Array[String] = []
	var fed_ids: Dictionary = {}
	for key: String in states:
		keys.append(key)
		original_states.append(states[key].state)
		assert(absf(float(states[key].state.at) - Runtime.now(_data()) * 60.0) < 0.00001, label + ": original populated feeding clock differs from Site clock")
		for cohort: Dictionary in states[key].state.cohorts:
			for identity: int in cohort.ids:
				assert(not fed_ids.has(identity))
				fed_ids[identity] = true
			if food: assert(float(cohort.coverage) == 1.0, label + ": uncovered real supply cohort")
	var owner_check: Dictionary = Sustain.validate_owner_index(original_states, _controller().captivity_supply._all_members(), keys)
	assert(owner_check.ok, str(owner_check))
	if food:
		assert(fed_ids.size() == 3, "The explicit supply scope must remain the original three people")
		var expected: float = food_baseline - 3.0 * (Runtime.now(_data()) * 60.0 - food_at) / Sustain.DAY
		assert(absf(_food_total() - expected) < 0.00001, "%s: food %.9f != %.9f" % [label, _food_total(), expected])
	var hp_history: Dictionary = _hp()
	assert(hp_history.size() == initial_people.size(), "Original HP history must contain every actual person")
	report.hp_history.append({"label": label, "at": Runtime.now(_data()), "original_people": hp_history, "house_hp": _data().site.features[house].parts.body.hp, "house_grade": Runtime.building_grade(_data().site.features[house])})
	return true

func _walk_courier(destination: Vector2i) -> bool:
	var team: TerrainArmy = _team()
	var index: int = team.index_for_identity(courier)
	var occupied: Callable = func(cell: Vector2i) -> bool: return _controller().person_actions.prison_blocked(cell, [courier])
	var route: Array[Vector2i] = _data().path_between(team.cells[index], destination, occupied)
	if team.cells[index] != destination and route.is_empty():
		_finish("FAILED", "Original courier route is blocked: " + str([team.cells[index], destination]))
		return false
	for next: Vector2i in route:
		assert(team._reserve_combat_step(index, next), "Original movement refused legal reserved courier step")
		var before: Vector2i = team.cells[index]
		if not await _until(func() -> bool: return _team().moving_to[index] == TerrainArmy.INVALID_CELL, 2.0, "original courier reserved step"): return false
		assert(team.cells[index] == next and next != before)
	return true

func _transfer(source: String, destination: String, resources: Dictionary) -> void:
	var from: Dictionary = _controller().vehicles._stock(source, true)
	var to: Dictionary = _controller().vehicles._stock(destination, true)
	assert(not from.is_empty() and not to.is_empty())
	var result: Dictionary = _controller().vehicles.transfer(source, destination, resources, [], int(from.holder.version), int(to.holder.version), courier)
	assert(result.ok, str(result))

func _stop_workers() -> bool:
	Runtime._stop_feature_zones(_data(), weaver, "operate")
	for identity: int in worker_ids: assert(_controller().work_team.cancel(identity).ok)
	return await _until(func() -> bool: return _team().moving_count() == 0, 5.0, "finish existing original worker reservations")

func _save_load(label: String) -> bool:
	if not _check_balances(label + ":before"): return false
	assert(_controller()._capture_for_save().ok)
	var at: float = Runtime.now(_data())
	var meals: Dictionary = _meal_snapshot()
	var before: Dictionary = _data().site.duplicate(true)
	# Exactly one original save/load transport; only the detached expected state is normalized.
	var parsed_before: Variant = JSON.parse_string(JSON.stringify(before, "", true, true))
	assert(parsed_before is Dictionary, "Original full-site save expression must parse as a Dictionary")
	var expected: Dictionary = parsed_before
	Store._normalize_state(expected)
	var expected_meals: Dictionary = _meal_snapshot(expected)
	var saved: Dictionary = _controller().save_to(save_path)
	assert(saved.ok, str(saved))
	_controller()._auto_save_blocked = true
	var loaded: Dictionary = _controller().load_from(save_path)
	assert(loaded.ok, str(loaded))
	_freeze_automatic_process()
	assert(absf(Runtime.now(_data()) - at) < 0.000001, "Original Store load advanced time")
	for key: String in ["inventory", "stockpiles", "housing", "item_records", "item_definitions", "team_supply", "person_supply", "features"]:
		assert(_data().site.get(key, {}) == expected.get(key, {}), label + ": Store changed original once-loaded " + key)
	assert(_meal_snapshot() == expected_meals, label + ": Store changed original once-loaded IDs/coverage/hunger/meal_until/bonus/meal credit")
	assert(lab.controlled_person_id() == courier and _team() != null)
	if not _check_balances(label + ":after"): return false
	report.checkpoints.append({"label": label, "at": at, "save": save_path, "people": _people(), "food": _food_total(), "materials": _materials(), "original_meals": meals})
	_write_report()
	return true

func _write_report() -> void:
	var file: FileAccess = FileAccess.open(folder + "/result.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t", true, true))
	file.close()

func _run() -> void:
	if not OS.get_cmdline_user_args().has("--grid"):
		_finish("INVALID_SCOPE", "This longplay proves the original GD work owner; run it with --grid (crowd is the default); native crowd is a separate test")
		return
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var run_at: int = arguments.find("--crowd-test")
	if run_at < 0 or run_at + 1 >= arguments.size():
		_finish("INVALID_TEST_PATH", "Require an explicit fresh --crowd-test run_id before creating the original scene")
		return
	var run_id: String = arguments[run_at + 1]
	if run_id.is_empty() or run_id != run_id.validate_filename() or run_id in [".", ".."] or run_id.contains(":") or run_id.contains("/") or run_id.contains("\\"):
		_finish("INVALID_TEST_PATH", "Original crowd-test run_id must be one legal path segment")
		return
	report.sources = _sources()
	report["scope"] = "Original formal PackedScene with an explicit existing command-test NPC and a true three-person logistics Army. Three game days of original Lab common clock at its existing 4x setting. True walking/cargo/local supply, construction, grade/repair, food, equipment and normal Store roundtrips. No native/GPU/performance acceptance."
	lab = (load(MAIN) as PackedScene).instantiate() as TerrainLab
	lab.restore_only = true
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	assert(lab.terrain == null and is_instance_valid(lab.npc), "Restore-only startup must skip default generation/load and preserve the explicit original test NPC")
	assert(_controller()._save_path_guard(_controller().save_path).ok and _controller().crowd_test_run_id == run_id)
	assert(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_controller().save_root)) and not FileAccess.file_exists(_controller().save_path), "Original longplay test root/current must be fresh; never reuse existing saves")
	report["isolation"] = {"run_id": run_id, "save_root": _controller().save_root, "initial_save_path": _controller().save_path, "startup": "original_restore_only"}
	current_scene = lab
	_freeze_automatic_process()
	lab.npc_retaliates = false
	var data: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345, {"size": Vector2i(64, 64)})
	Env.initialize(data, "building-longplay-" + str(Time.get_ticks_usec()))
	# Persist only original natural-resource clearance; generated terrain base remains intact.
	for key: String in data.resource_base: Env.change(data, key, {"cleared": true, "remaining": 0})
	data.site.inventory = {"wood": 100, "stone": 50, "tools": 6, "fiber": 12, "rope": 4, "pottery": 3, "grain": 80}
	data.site.capacity = 5000
	lab.bind_terrain(data)
	assert(lab.terrain == data and lab.actor_present(lab.character) and lab.actor_present(lab.npc))
	lab.restore_only = false
	lab.show()
	lab.npc.faction_id = lab.character.faction_id
	_controller().release_worker()
	while lab.simulation_speed < 4.0: lab.change_simulation_speed(1)
	expected_materials = _materials().duplicate(true)
	house = await _construct("house")
	if finished: return
	warehouse = await _construct("warehouse")
	if finished: return
	weaver = await _construct("weaver")
	if finished: return
	# Releasing work stops the original NPC at the workshop entrance; vacate it by real navigation.
	var constructor_cell: Vector2i = lab.npc.terrain_cell
	var logistics_route: Array[Vector2i] = data.path_between(data.cell_from_index(int(data.site.features[warehouse].entrance)), constructor_cell)
	var constructor_parked: bool = false
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var parking_cell: Vector2i = constructor_cell + direction
		if logistics_route.has(parking_cell) or not lab.npc.can_enter_cell(parking_cell): continue
		if not lab.npc.issue_command(TerrainTestNPC.Command.MOVE_TO_CELL, parking_cell): continue
		if not await _until(func() -> bool: return lab.npc.terrain_cell == parking_cell and not lab.npc.is_moving(), 2.0, "original constructor walks clear of the workshop entrance"): return
		assert(lab.npc.terrain_cell != constructor_cell and not lab.npc.occupies_cell(constructor_cell))
		report["constructor_clearance"] = {"person_id": lab.npc.person_id, "from": [constructor_cell.x, constructor_cell.y], "to": [parking_cell.x, parking_cell.y], "at": Runtime.now(data), "command": "original_MOVE_TO_CELL"}
		constructor_parked = true
		break
	assert(constructor_parked, "Original constructor must really vacate the logistics entrance")
	var spawn: Vector2i = _logistics_spawn()
	assert(spawn != TerrainArmy.INVALID_CELL, "Original legal connected logistics formation must be reachable from depot")
	var deployed: Dictionary = lab.deploy_trial_armies([{"faction": lab.character.faction_id, "count": 3, "role": "logistics", "attack": false, "ai_enabled": false, "female_percent": 0, "spawn": spawn}])
	assert(deployed.ok, str(deployed))
	var team: TerrainArmy
	for original: TerrainArmy in lab.combat_armies:
		if original.combat_enabled: team = original; break
	assert(team != null and team.combat_units.size() == 3 and team.role == "logistics")
	team_id = team.team_id
	courier = team.combat_identity(team.current_commander)
	for index: int in range(team.combat_units.size()):
		if team.combat_identity(index) != courier: worker_ids.append(team.combat_identity(index))
	assert(worker_ids.size() == 2 and _controller()._control_family_person(null, courier).ok)
	_freeze_automatic_process()
	initial_people = _people()
	assert(initial_people.size() == 5)
	initial_items = _data().site.item_records.keys().duplicate()
	assert(not initial_items.is_empty(), "Original deployment must retain real initialized equipment")
	assert(Stocks.ensure_storage(_data(), warehouse, team.faction_id).ok and Stocks.ensure_storage(_data(), weaver, team.faction_id).ok)
	assert(Stocks.set_local_supply(_data(), weaver, true, team.faction_id).ok and Runtime.request_feature_recipe(_data(), weaver, "rope", team.faction_id).ok)
	assert(Housing.assign(lab, worker_ids[0], house, courier).ok)
	var depot: Vector2i = _data().cell_from_index(int(_data().site.depot_cell))
	var contact: Vector2i = TerrainArmy.INVALID_CELL
	for offset: Vector2i in TerrainData.DIRECTIONS:
		if _data().can_step(depot + offset, depot) and not _controller().person_actions.prison_blocked(depot + offset, [courier]): contact = depot + offset; break
	assert(contact != TerrainArmy.INVALID_CELL)
	if not await _walk_courier(contact): return
	var feeding_started: float = Runtime.now(_data()) * 60.0
	assert(_controller().begin_team_food(_team(), 12.0, courier, {"kind": "depot"}).ok)
	if not await _until(func() -> bool: return _controller()._supply_entry(_team()).delivery.is_empty(), 10.0, "original food contact/commit"): return
	food_at = Runtime.now(_data()) * 60.0
	food_baseline = _food_total()
	assert(food_baseline <= 80.0 + Sustain.EPS and food_baseline >= 80.0 - 3.0 * (food_at - feeding_started) / Sustain.DAY - Sustain.EPS, "Food acquisition lost more than original elapsed consumption or minted food/meal credit")
	report["feeding_setup"] = {"initial_food": 80.0, "started_game_seconds": feeding_started, "settled_game_seconds": food_at, "conserved_food_after_elapsed_consumption": food_baseline}
	save_path = _controller().save_root.path_join("building_longplay_" + str(Time.get_ticks_usec()) + ".json")
	_controller().save_path = save_path
	var self_stock: String = "person:" + str(courier)
	_transfer("depot", self_stock, {"fiber": 6})
	if not await _walk_courier(_data().cell_from_index(int(_data().site.features[warehouse].entrance))): return
	_transfer(self_stock, "feature:" + warehouse, {"fiber": 6})
	_transfer("feature:" + warehouse, self_stock, {"fiber": 6})
	if not await _walk_courier(_data().cell_from_index(int(_data().site.features[weaver].entrance))): return
	_transfer(self_stock, "feature:" + weaver, {"fiber": 6})
	# The controlled courier leaves the actual workshop work cell before another original person is assigned.
	if not await _walk_courier(contact): return
	if not await _until(func() -> bool: return _team().command_eligible(_team().current_commander) and _team().combat_identity(_team().current_commander) == courier, 10.0, "original returning officer regains actual command presence"): return
	var workers_stopped: Callable = func() -> bool:
		for identity: int in worker_ids:
			var index: int = _team().index_for_identity(identity)
			if _team().moving_to[index] != TerrainArmy.INVALID_CELL or not _team().combat_can_act(index) or str(_team().combat_hot_get(index, &"pose")) != "idle": return false
		return true
	if not await _until(workers_stopped, 5.0, "original workers finish existing movement before assignment"): return
	# Dedicated hauling and workshop work are mutually exclusive in the original owner.
	var released_hauling: Dictionary = _controller().order_team_logistics(_team(), worker_ids, courier, false)
	assert(released_hauling.ok, str(released_hauling))
	for identity: int in worker_ids: assert(not bool(_team().combat_units[_team().index_for_identity(identity)].logistics))
	assert(bool(_team().combat_units[_team().index_for_identity(courier)].logistics))
	var rope_before: int = int(_data().site.inventory.get("rope", 0))
	var source_version: int = int(Stocks.storage(_data(), weaver).holder.version)
	var operated: Dictionary = Runtime.operate_feature(_data(), weaver)
	assert(operated.ok, str(operated))
	var assigned: Dictionary = _controller().work_team.assign(_team(), worker_ids, courier)
	if not assigned.ok:
		for identity: int in worker_ids:
			var index: int = _team().index_for_identity(identity)
			print("LONGPLAY_ASSIGN_REFUSAL: ", JSON.stringify({"person_id": identity, "cell": _team().cells[index], "moving_to": _team().moving_to[index], "pose": _team().combat_hot_get(index, &"pose"), "attack": _team().combat_hot_get(index, &"attack"), "stagger": _team().combat_hot_get(index, &"exchange_stagger", 0.0), "can_act": _team().combat_can_act(index), "row": _team().combat_units[index]}))
	assert(assigned.ok, str(assigned))
	if not await _until(func() -> bool: return bool(_data().site.features[weaver].batch_paid) and float(_data().site.features[weaver].production) > 0.0 and float(_data().site.features[weaver].production) < 8.0, 120.0, "original worker reaches and prepays local rope"): return
	assert(int(Stocks.storage(_data(), weaver).holder.version) == source_version + 1)
	assert(await _save_load("paid-local-batch"))
	if finished: return
	if not await _until(func() -> bool: return int(_data().site.inventory.get("rope", 0)) == rope_before + 6, 300.0, "original workers deliver three local rope batches"): return
	assert(int(Stocks.storage(_data(), weaver).cargo.get("fiber", 0)) == 0 and int(_data().site.inventory.get("fiber", 0)) == 6)
	var unchanged: String = JSON.stringify([_data().site.inventory, Stocks.storage(_data(), weaver), _data().site.features[weaver].production, _data().site.features[weaver].batch_paid], "", true, true)
	var blocked_until: float = Runtime.now(_data()) + 30.0
	if not await _until(func() -> bool: return Runtime.now(_data()) >= blocked_until, 31.0, "local material shortage remains blocked"): return
	assert(JSON.stringify([_data().site.inventory, Stocks.storage(_data(), weaver), _data().site.features[weaver].production, _data().site.features[weaver].batch_paid], "", true, true) == unchanged, "Local shortage burned/created cargo or silently debited remote depot")
	if not await _stop_workers(): return
	var feature: Dictionary = _data().site.features[house]
	var cells: Array = feature.cells.duplicate()
	var home: Dictionary = _data().site.housing.duplicate(true)
	var stock: Dictionary = _data().site.stockpiles.duplicate(true)
	var damaged: Dictionary = Runtime.damage_structure_part(_data(), house, "body", 40.0)
	assert(damaged.ok)
	lab.resolve_structure_change(damaged)
	var before: Dictionary = _data().site.inventory.duplicate(true)
	var preview: Dictionary = Runtime.request_upgrade(_data(), house, _team().faction_id, _controller().reserves_cell, true)
	assert(preview.ok)
	assert(Runtime.request_upgrade(_data(), house, _team().faction_id, _controller().reserves_cell).ok)
	_charge("grade2", before, preview.cost)
	assert(_controller().work_team.assign(_team(), worker_ids, courier).ok)
	if not await _until(func() -> bool: return not _data().site.features[house].has("pending_build"), 150.0, "original grade2 construction"): return
	feature = _data().site.features[house]
	assert(int(feature.building_grade) == 2 and float(feature.parts.body.hp) == 90.0 and feature.cells == cells and _data().site.housing == home and _data().site.stockpiles == stock)
	if not await _stop_workers(): return
	var frozen: String = JSON.stringify(_data().site, "", true, true)
	var shortage: Dictionary = Runtime.request_upgrade(_data(), house, _team().faction_id, _controller().reserves_cell)
	assert(not shortage.ok and shortage.code == "MATERIALS" and JSON.stringify(_data().site, "", true, true) == frozen, "Unaffordable grade3 changed original paid/state/stock")
	before = _data().site.inventory.duplicate(true)
	var repair_requested: Dictionary = Runtime.request_repair(_data(), house, "body", _team().faction_id, _controller().reserves_cell)
	assert(repair_requested.ok, str(repair_requested))
	_charge("body-repair", before, _data().site.features[house].repair.cost)
	assert(_controller().work_team.assign(_team(), worker_ids, courier).ok)
	if not await _until(func() -> bool: return not _data().site.features[house].has("repair"), 150.0, "original body repair"): return
	assert(float(_data().site.features[house].parts.body.hp) == 150.0)
	if not await _stop_workers(): return
	assert(await _save_load("grade-repaired"))
	if finished: return
	var end_minute: float = food_at / 60.0 + 3.0 * 1440.0
	var checkpoint: float = Runtime.now(_data()) + 720.0
	while Runtime.now(_data()) < end_minute:
		var destination: float = minf(checkpoint, end_minute)
		if not await _until(func() -> bool: return Runtime.now(_data()) >= destination, 721.0, "original three-day peaceful longplay"): return
		assert(await _save_load("game-minute-" + str(roundi(Runtime.now(_data())))))
		if finished: return
		checkpoint = Runtime.now(_data()) + 720.0
	assert(Runtime.now(_data()) * 60.0 - food_at >= 3.0 * Sustain.DAY)
	assert(_sources() == report.sources, "Original source drift during longplay")
	report["elapsed_game_seconds"] = Runtime.now(_data()) * 60.0 - food_at
	report["final_materials"] = _materials()
	report["final_food_total"] = _food_total()
	report["initial_food_total"] = food_baseline
	report["people"] = _people()
	report["unique_equipment"] = initial_items.size()
	_finish("PASS", "")

func _finish(status: String, failure: String) -> void:
	if finished: return
	finished = true
	report.status = status
	report["failure"] = failure
	_write_report()
	print("SITE_BUILDING_LONGPLAY_", status, " ", JSON.stringify({"folder": folder, "game_seconds": report.get("elapsed_game_seconds"), "checkpoints": report.checkpoints.size(), "failure": failure}))
	if lab != null: lab.queue_free()
	quit(0 if status == "PASS" else 2)
