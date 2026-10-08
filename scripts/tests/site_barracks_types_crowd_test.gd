extends "res://scripts/tests/site_barracks_dense_garrison_crowd_test.gd"
## Actual original GD phase -> D5 deployment -> native step -> Store/load/common step.
## Scalar recovery measurements call only the existing host phase, so meals and Site time stay fixed.

const TYPES_INTERVAL := 6.0
var types_groups := 0
var types_failures := 0

func _types_near(actual: float, expected: float, label: String) -> void:
	if not (absf(actual - expected) < 0.0000001): types_failures += 1
	assert(absf(actual - expected) < 0.0000001, "%s: %.12f != %.12f" % [label, actual, expected])

func _types_persistent_fixture() -> TerrainData:
	var data := _building_fixture()
	# Match the existing native training/Store fixture: height is the persisted navigation delta.
	var base := TerrainGenerator.generate(data.preset, data.seed_value, data.parameters)
	data.surface_types = base.surface_types.duplicate()
	data.flags = base.flags.duplicate()
	data.ramp_edges = base.ramp_edges.duplicate()
	for y: int in range(8, 55):
		for x: int in range(8, 55):
			var cell := Vector2i(x, y)
			data.site.terrain_changes[str(data.index(cell))] = int(data.height_levels[data.index(cell)])
	Runtime.rebuild_terrain_edges(data)
	Env.rebuild_indexes(data)
	return data

func _types_require_native() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.has("--crowd-test") and args.has("--crowd-atlas-root") and not args.has("--crowd"))
	assert(DisplayServer.get_name() != "headless" and ClassDB.class_has_method(&"ArmyCrowd", &"set_recovery_input"), "Publish the accepted new DLL before this test")

func _types_enter_crowd(lab: TerrainLab, row: Dictionary) -> Node:
	assert(await CrowdHost.prepare_captivity_recipe(lab, Runtime.equipment_appearance(lab.terrain, row.item_state, row.appearance)))
	lab.crowd_site = CrowdHost.new()
	lab.add_child(lab.crowd_site)
	lab.crowd_site.setup(lab)
	var imported := lab.deploy_trial_armies([{"faction": 2, "count": 1, "female_percent": 0,
		"attack": false, "ai_enabled": false, "spawn": Vector2i(44, 40)}])
	assert(imported.ok and lab.crowd_site.active, str(imported))
	return lab.crowd_site

func _types_people(controller: SiteController, identities: Array[int]) -> Dictionary:
	var result := {}
	for identity: int in identities:
		var person: Dictionary = controller.person_actions._person(identity)
		assert(not person.is_empty())
		result[identity] = {"body": person.body, "holder": person.holder, "cargo": person.cargo,
			"items": person.holder.duplicate(true), "cargo_copy": person.cargo.duplicate(true), "cell": person.cell}
	return result

func _types_same_people(controller: SiteController, original: Dictionary, require_aliases: bool = true) -> void:
	for identity: int in original:
		var person: Dictionary = controller.person_actions._person(identity)
		var saved: Dictionary = original[identity]
		if require_aliases:
			assert(is_same(person.body, saved.body) and is_same(person.holder, saved.holder) and is_same(person.cargo, saved.cargo))
		assert(person.holder == saved.items and person.cargo == saved.cargo_copy and person.cell == saved.cell)

func _types_restore_soldier(host: Node, index: int, state: Dictionary) -> void:
	var fields := {}
	for key: String in CrowdHost.SOLDIER_FIELDS.slice(0, 22): fields[key] = state[key]
	fields.captor_person = state.captor_person
	fields.prison_id = state.prison_id
	assert(host.set_soldier_fields(index, fields))
	assert(host.crowd.step_clock(TerrainLab.ACTION_STEP, 0.0, 0.0)) # Settle original derived pose without a game interval.

func _types_native_loss(host: Node, formation: int, combat: float = 0.0) -> float:
	assert(host.set_formation_fields(formation, {"fatigue": 60.0, "fatigue_rest": PersonFatigue.REST_DELAY}))
	host.step(TerrainLab.ACTION_STEP, TYPES_INTERVAL, combat)
	assert(host.last_event_error.is_empty(), str(host.last_event_error))
	return 60.0 - float(host.formation_state(formation).fatigue)

func _run() -> void:
	deadline = Time.get_ticks_msec() + 240000
	_types_require_native()
	var data := _types_persistent_fixture()
	var standard := _formal_feature(data, "barracks", Vector2i(20, 20), Vector2i(10, 10), {"camp_type": "standard"})
	var chinese := _formal_feature(data, "barracks", Vector2i(36, 20), Vector2i(10, 10), {"camp_type": "chinese"})
	data.site.minute = 0
	data.site.phase = 0.0
	var lab := _building_lab(data)
	lab.fixed_action_steps_enabled = false
	var controller: SiteController = lab.site_controller
	var teams: Array[TerrainArmy] = [lab.army, lab.opposing_army]
	_make_garrison_team(lab, teams[0], [Vector2i(23, 26), Vector2i(24, 26), Vector2i(25, 26)])
	_make_garrison_team(lab, teams[1], [Vector2i(39, 26), Vector2i(40, 26), Vector2i(41, 26)])
	var keys: Array[String] = [standard, chinese]
	var ids: Array[int] = []
	var captain_ids: Array[int] = []
	for slot: int in range(2):
		var team := teams[slot]
		captain_ids.append(team.combat_identity(0))
		for row: Dictionary in team.combat_units: ids.append(int(row.person_id))
		var entry: Dictionary = controller._enable_team_supply(team)
		entry.inventory.grain = 100
		entry.sustain.open_rations = 0.375
		assert(Garrison.admit(lab, keys[slot], team.team_id).ok)
	var original := _types_people(controller, ids)
	var meals := _meal_history(controller)
	var site_time := Runtime.now(data)
	var gd_losses: Array[float] = []
	for slot: int in range(2):
		var team := teams[slot]
		team.team_fatigue.fatigue = 60.0
		team.team_fatigue.fatigue_rest = PersonFatigue.REST_DELAY
		team.team_fatigue.active = false
		_types_near(Garrison.recovery_multiplier(lab, keys[slot], 1, team.combat_units), 1.0 if slot == 0 else 1.25, "Original whole-pool qualifier")
		lab._advance_team_fatigue(team, TYPES_INTERVAL, {}, {})
		gd_losses.append(60.0 - float(team.team_fatigue.fatigue))
		team.team_fatigue.fatigue = 60.0
		team.team_fatigue.fatigue_rest = PersonFatigue.REST_DELAY
	_types_near(gd_losses[0], PersonFatigue.RECOVERY_RATE * TYPES_INTERVAL, "Actual GD ordinary phase")
	_types_near(gd_losses[1], gd_losses[0] * 1.25, "Actual GD Chinese phase")
	assert(_meal_history(controller) == meals and Runtime.now(data) == site_time)
	var seed_row: Dictionary = teams[0].combat_units[0]
	var host: Node = await _types_enter_crowd(lab, seed_row)
	var formations: Array[int] = []
	for identity: int in captain_ids: formations.append(int(host.person_owner(identity).formation_index))
	for formation: int in formations:
		assert(host.formation_state(formation).garrisoned and int(host.formation_state(formation).current_person) == -1)
	for slot: int in range(2): _types_near(_types_native_loss(host, formations[slot]), gd_losses[slot], "Native/GD same six-second interval")
	assert(_meal_history(controller) == meals and Runtime.now(data) == site_time)
	_types_same_people(controller, original)
	types_groups += 1
	print("SITE_BARRACKS_TYPES_CROWD_RATE_PASS gd=", gd_losses, " native_same_interval; meals/time unchanged")
	# The native API receives no input at all on this following step.
	var before: Array[float] = []
	for formation: int in formations: before.append(float(host.formation_state(formation).fatigue))
	assert(host.crowd.step_clock(TerrainLab.ACTION_STEP, TYPES_INTERVAL, 0.0))
	for slot: int in range(2): _types_near(before[slot] - float(host.formation_state(formations[slot]).fatigue), gd_losses[0], "Missing next-step input defaults to one")
	types_groups += 1
	_check_types_native_eligibility(lab, host, formations[1], chinese)
	_check_types_native_safety(lab, host, formations[1], chinese)
	_types_same_people(controller, original)
	assert(_meal_history(controller) == meals and Runtime.now(data) == site_time)
	await _check_types_native_roundtrip(lab, host, formations, captain_ids, keys, original, meals)
	for _frame: int in range(3): await process_frame
	lab.free()
	await process_frame
	TerrainArmy.release_contact_source()
	if types_groups != 12 or types_failures != 0:
		push_error("Two-type native recovery incomplete: groups=%d/12 numerical failures=%d" % [types_groups, types_failures])
		quit(1)
		return
	print("SITE_BARRACKS_TYPES_CROWD_PASS: actual standard/Chinese original admission and D5 deployment; GD/native 1/1.25 recovery parity; whole-pool outside/KO/captive/get-up/dead eligibility; native combat/knock/escort/hostile guards; no-input default; Store and new CrowdSite load followed by one common-clock phase; groups=", types_groups)
	quit(0)

func _check_types_native_eligibility(lab: TerrainLab, host: Node, formation: int, feature: String) -> void:
	var roster: Dictionary = host.team_record(formation)
	var identity := int(roster.units[1].person_id)
	var index := int(host.crowd.soldier_index(identity))
	var saved: Dictionary = host.soldier_state(index)
	var captor := -1
	for row: Dictionary in host.rosters:
		if int(row.faction_id) == 2: captor = int(row.units[0].person_id)
	assert(captor > 0)
	# Isolate attendance from the independently tested hostile-threat gate.
	# The old (45,40) fixture stood next to the enemy spawned at (44,40).
	var outside := Vector2i(48, 10)
	assert(lab.terrain.is_walkable(outside))
	assert(not Runtime.military_walkable_cells(lab.terrain, lab.terrain.site.features[feature]).has(lab.terrain.index(outside)))
	for hostile: Dictionary in host.rosters:
		if int(hostile.faction_id) == int(roster.faction_id): continue
		for row: Dictionary in hostile.units:
			var enemy_index := int(host.crowd.soldier_index(int(row.person_id)))
			var enemy: Dictionary = host.soldier_state(enemy_index)
			var distance := absf(float(outside.x) + 0.5 - float(enemy.px)) + absf(float(outside.y) + 0.5 - float(enemy.py))
			assert(distance > 8.0, "Outside attendance fixture must remain beyond the original hostile threat range")
	for condition: String in ["outside", "ko", "captive", "getup", "dead"]:
		var changes := {}
		if condition == "outside": changes = {"px": float(outside.x) + 0.5, "py": float(outside.y) + 0.5}
		elif condition == "ko": changes = {"ko": 1000.0, "bandaged": 1}
		elif condition == "captive": changes = {"captive": 1, "captor_person": captor, "escape_t": 0.0}
		elif condition == "getup": changes = {"getup": 1.0}
		else: changes = {"hp": 0.0}
		assert(host.set_soldier_fields(index, changes))
		_types_near(Garrison.recovery_multiplier(lab, feature, 1, roster.units), 1.25 if condition == "dead" else 1.0, "Whole-pool eligibility: " + condition)
		var expected := PersonFatigue.RECOVERY_RATE * TYPES_INTERVAL * (1.25 if condition == "dead" else 1.0)
		if condition == "getup": expected = 0.0
		_types_near(_types_native_loss(host, formation), expected, "Native eligibility: " + condition)
		_types_restore_soldier(host, index, saved)
		types_groups += 1
	print("SITE_BARRACKS_TYPES_CROWD_ELIGIBILITY_PASS: one original outside/KO/captive/get-up person blocks whole-pool bonus; dead excluded")

func _check_types_native_safety(lab: TerrainLab, host: Node, formation: int, feature: String) -> void:
	var roster: Dictionary = host.team_record(formation)
	var index := int(host.crowd.soldier_index(int(roster.units[1].person_id)))
	var saved: Dictionary = host.soldier_state(index)
	_types_near(Garrison.recovery_multiplier(lab, feature, 1, roster.units), 1.25, "Eligible before native combat gate")
	_types_near(_types_native_loss(host, formation, 1.0), 0.0, "Original native combat clock gate")
	types_groups += 1
	assert(host.set_soldier_fields(index, {"knock_t": 1.0}))
	_types_near(_types_native_loss(host, formation), 0.0, "Original native knock lock gate")
	_types_restore_soldier(host, index, saved)
	types_groups += 1
	var cell := Vector2i(floori(float(saved.px)), floori(float(saved.py)))
	assert(host.crowd.order_escort_step(index, index, lab.terrain.index(cell)))
	_types_near(_types_native_loss(host, formation), 0.0, "Original native escort activity gate")
	assert(host.crowd.cancel_escort(index))
	_types_restore_soldier(host, index, saved)
	types_groups += 1
	var enemy := -1
	for row: Dictionary in host.rosters:
		if int(row.faction_id) == 2: enemy = int(host.crowd.soldier_index(int(row.units[0].person_id)))
	assert(enemy >= 0)
	var enemy_saved: Dictionary = host.soldier_state(enemy)
	assert(host.set_soldier_fields(enemy, {"px": 46.5, "py": 26.5}))
	_types_near(_types_native_loss(host, formation), 0.0, "Actual native hostile within eight cells")
	_types_near(float(host.formation_state(formation).fatigue_rest), 0.0, "Original hostile gate resets the pool rest delay")
	_types_restore_soldier(host, enemy, enemy_saved)
	# Contact refresh is staggered over three native ticks. Advance no game
	# time through all contacts, then refresh the derived formation threat.
	var fatigue_before := float(host.formation_state(formation).fatigue)
	var site_before := Runtime.now(lab.terrain)
	var meals_before := _meal_history(lab.site_controller)
	for _tick: int in range(4):
		host.crowd.step_clock(TerrainLab.ACTION_STEP, 0.0, 0.0)
	_types_near(float(host.formation_state(formation).fatigue), fatigue_before, "Zero game-time contact refresh preserves fatigue")
	assert(Runtime.now(lab.terrain) == site_before and _meal_history(lab.site_controller) == meals_before)
	types_groups += 1
	print("SITE_BARRACKS_TYPES_CROWD_SAFETY_PASS: native combat/knock/escort locks and actual hostile threat retain original no-recovery behavior")

func _check_types_native_roundtrip(lab: TerrainLab, host: Node, formations: Array[int], captain_ids: Array[int], keys: Array[String], original: Dictionary, meals: Dictionary) -> void:
	var controller: SiteController = lab.site_controller
	var path := controller.save_path
	assert(not controller.crowd_test_run_id.is_empty() and not FileAccess.file_exists(path), "Use a fresh isolated --crowd-test run ID")
	assert(DirAccess.make_dir_recursive_absolute(controller.save_root) == OK)
	# The preceding threat test correctly reset rest to zero. Establish a
	# distinct safe/rested Store fixture before measuring its next interval.
	var saved_values: Array[float] = []
	var saved_rest: Array[float] = []
	for slot: int in range(formations.size()):
		var formation: int = formations[slot]
		var state: Dictionary = host.formation_state(formation)
		assert(int(state.order) == 0 and bool(state.garrisoned))
		_types_near(Garrison.recovery_multiplier(lab, keys[slot], 1, host.team_record(formation).units), 1.0 if slot == 0 else 1.25, "Store fixture has restored original eligible people")
		assert(host.set_formation_fields(formation, {"fatigue_rest": PersonFatigue.REST_DELAY}))
		saved_values.append(float(host.formation_state(formation).fatigue))
		saved_rest.append(float(host.formation_state(formation).fatigue_rest))
	var saved := controller.save_to(path)
	assert(saved.ok, str(saved))
	var file_before := FileAccess.get_file_as_string(path)
	var source: TerrainData = lab.terrain
	var copy := Store.load_site(path)
	assert(copy.ok and not is_same(copy.data, source), str(copy))
	assert(copy.data.fingerprint() == source.fingerprint() and copy.data.static_blocked == source.static_blocked and copy.data.feature_at == source.feature_at)
	for slot: int in range(2): assert(copy.data.site.features[keys[slot]].camp_type == ("standard" if slot == 0 else "chinese"))
	var old_host_id := host.get_instance_id()
	var loaded := controller.load_from(path)
	assert(loaded.ok and not is_same(lab.terrain, source) and lab.crowd_site.get_instance_id() != old_host_id, str(loaded))
	host = lab.crowd_site
	for slot: int in range(2):
		formations[slot] = int(host.person_owner(captain_ids[slot]).formation_index)
		_types_near(float(host.formation_state(formations[slot]).fatigue), saved_values[slot], "Load preserves one original pool")
		_types_near(float(host.formation_state(formations[slot]).fatigue_rest), saved_rest[slot], "Load preserves the original rest delay progress")
		assert(host.team_record(formations[slot]).garrison_feature_id == keys[slot])
	_types_same_people(controller, original, false)
	assert(_meal_history(controller) == meals and FileAccess.get_file_as_string(path) == file_before)
	# Re-enter through the common action clock: Site, meals and native fatigue each receive six seconds once.
	var clock_before := Runtime.now(lab.terrain)
	var supply_before := {}
	for identity: int in captain_ids:
		var owner: RefCounted = host.person_owner(identity)
		supply_before[owner.team_id] = float(controller._supply_entry(owner).sustain.at)
	lab._advance_action_time(TYPES_INTERVAL / 60.0)
	_types_near((Runtime.now(lab.terrain) - clock_before) * 60.0, TYPES_INTERVAL, "One common Site interval after replacement")
	for slot: int in range(2):
		var owner: RefCounted = host.person_owner(captain_ids[slot])
		_types_near(saved_values[slot] - float(host.formation_state(formations[slot]).fatigue), PersonFatigue.RECOVERY_RATE * TYPES_INTERVAL * (1.0 if slot == 0 else 1.25), "New CrowdSite common step has no double GD/native recovery")
		_types_near(float(controller._supply_entry(owner).sustain.at) - float(supply_before[owner.team_id]), TYPES_INTERVAL, "One original supply interval after replacement")
	_types_same_people(controller, original, false)
	assert(FileAccess.get_file_as_string(path) == file_before)
	types_groups += 1
	print("SITE_BARRACKS_TYPES_CROWD_STORE_PASS: isolated Store/load and new CrowdSite; next common clock applies one bonus and one meal/time interval; path=", path)
