extends "res://scripts/tests/site_garrison_test.gd"
## Original Runtime/Army/Garrison/Sustain owners; this fixture never writes a formal save.
const Ground = preload("res://scripts/terrain_lab/site_training_ground.gd")
const TYPES_CONTRACT_ROOT := "res://output/site_barracks_two_types_20261003/contract/"
var type_groups := 0
var type_rejections := 0
var training_samples := {}

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 180000
	_run.call_deferred()

func _run() -> void:
	_check_type_input()
	_check_type_geometry_and_jobs()
	for camp_type: String in ["standard", "chinese"]:
		await _check_original_garrison(camp_type)
	training_samples.school = await _exercise_training("training_ground", false)
	training_samples.standard = await _exercise_training("barracks", false)
	training_samples.legacy = await _exercise_training("barracks", true)
	_near(float(training_samples.standard.gain), float(training_samples.school.gain) * 1.25, "Western barracks actual GD training bonus")
	_near(float(training_samples.legacy.gain), float(training_samples.standard.gain), "Missing camp_type retains Western training eligibility")
	for key: String in ["standard", "legacy"]:
		_near(float(training_samples[key].fatigue), float(training_samples.school.fatigue), "Bonus must not multiply actual fatigue effort")
		assert(training_samples[key].handled_seconds == training_samples.school.handled_seconds)
		assert(training_samples[key].at_start == training_samples.school.at_start)
		_near(float(training_samples[key].food_used), float(training_samples.school.food_used), "Bonus must not multiply actual eaten rations")
	_check_training_effort()
	await _check_original_recovery()
	if type_groups != 9 or type_rejections != 16 or training_samples.size() != 3:
		push_error("A barracks type contract group stopped before completion")
		quit(1)
		return
	assert(DirAccess.make_dir_recursive_absolute(TYPES_CONTRACT_ROOT) == OK)
	var report := FileAccess.open(TYPES_CONTRACT_ROOT + "results.json", FileAccess.WRITE)
	assert(report != null)
	report.store_string(JSON.stringify({"status": "SITE_BARRACKS_TYPES_CONTRACT_PASS", "groups": type_groups,
		"rejected_build_inputs": type_rejections, "training": training_samples,
		"scope": "Original GD Runtime, Army, Garrison, Sustain and fatigue phase. Native parity and GPU appearance are separate checks."}, "\t"))
	report.close()
	print("SITE_BARRACKS_TYPES_CONTRACT_PASS: 9 groups; strict types/atomic rejection, unchanged legacy geometry/cost/capacity, parent-only resize type, original people/holders through admit/form, actual GD 1.25 training with equal effort, facility stop/resize guards and whole-pool Chinese recovery")
	quit(0)

func _near(actual: float, expected: float, label: String) -> void:
	assert(absf(actual - expected) < 0.00002, "%s: %.12f != %.12f" % [label, actual, expected])

func _type_cells(data: TerrainData, kind: String, extent: Vector2i, options: Dictionary = {}) -> Array[int]:
	var placement := Runtime.building_cells(data, kind, Vector2i(20, 20), extent, options)
	assert(placement.ok, str(placement))
	var cells: Array[int] = []
	cells.assign(placement.cells)
	return cells

func _check_type_input() -> void:
	var data := _building_fixture()
	var cells := _type_cells(data, "barracks", Vector2i(10, 10))
	assert(Runtime.building_spec("barracks").options.camp_type == "standard")
	assert(Runtime.barracks_type({"kind": "barracks"}) == "standard")
	assert(Runtime.is_training_facility({"kind": "barracks"}) and Runtime.is_training_facility({"kind": "training_ground"}))
	assert(not Runtime.is_training_facility({"kind": "house"}))
	for camp_type: String in ["standard", "chinese"]:
		var spec := Runtime.building_spec("barracks", {"camp_type": camp_type})
		assert(spec.ok and spec.options.camp_type == camp_type and int(spec.options.barracks_layout_version) == 2)
		var feature := {"kind": "barracks", "camp_type": camp_type}
		assert(Runtime.barracks_type(feature) == camp_type and not Runtime.barracks_type_name(feature).is_empty() and not Runtime.barracks_type_description(feature).is_empty())
		assert(Runtime.is_training_facility(feature) == (camp_type == "standard"))
		_near(Runtime.training_multiplier(feature), 1.25 if camp_type == "standard" else 1.0, "Shared training multiplier")
	for bad: Variant in ["", "unknown", "STANDARD", 1, 1.0, true, false, null, [], {}]:
		var options := {"camp_type": bad}
		var before := JSON.stringify(data.site)
		var blocked := data.static_blocked.duplicate()
		var feature_at := data.feature_at.duplicate()
		assert(not Runtime.building_spec("barracks", options).ok)
		assert(not Runtime.preview_build(data, "barracks", cells, Callable(), options).ok)
		assert(not Runtime.request_build(data, "barracks", cells, Callable(), options).ok)
		assert(JSON.stringify(data.site) == before and data.static_blocked == blocked and data.feature_at == feature_at, "Invalid type spent stock or changed existing navigation")
		type_rejections += 1
	for kind: String in ["training_ground", "house", "farm"]:
		var spec := Runtime.building_spec(kind)
		var other_cells := _type_cells(data, kind, spec.min_size)
		for camp_type: String in ["standard", "chinese"]:
			var before := JSON.stringify(data.site)
			assert(not Runtime.building_spec(kind, {"camp_type": camp_type}).ok)
			assert(not Runtime.request_build(data, kind, other_cells, Callable(), {"camp_type": camp_type}).ok)
			assert(JSON.stringify(data.site) == before, "A non-barracks accepted or spent a camp_type")
			type_rejections += 1
	type_groups += 1

func _geometry(data: TerrainData, feature: Dictionary) -> Dictionary:
	return {"modules": Runtime.military_modules(data, feature), "blocked": Runtime.feature_geometry(data, feature).blocked,
		"standing": Runtime.military_walkable_cells(data, feature), "capacity": Runtime.military_capacity(data, feature),
		"cost": Runtime._building_cost(data, "barracks", feature.cells, Runtime._feature_options(feature))}

func _check_type_geometry_and_jobs() -> void:
	for camp_type: String in ["standard", "chinese"]:
		for version: int in [1, 2]:
			var data := _building_fixture()
			var key := _formal_feature(data, "barracks", Vector2i(20, 20), Vector2i(10, 10), {"camp_type": camp_type, "barracks_layout_version": version})
			var feature: Dictionary = data.site.features[key]
			assert(feature.camp_type == camp_type and int(feature.barracks_layout_version) == version)
			for quarter: int in range(4):
				var candidate := feature.duplicate(true)
				candidate.quarter = quarter
				var typed_geometry := _geometry(data, candidate)
				candidate.erase("camp_type")
				assert(_geometry(data, candidate) == typed_geometry, "Type changed existing military geometry, cost or standing capacity")
				assert(typed_geometry.capacity == (72 if version == 1 else 60))
				assert(typed_geometry.modules.size() == (3 if version == 1 else 7))
			var large := _type_cells(data, "barracks", Vector2i(11, 10), {"camp_type": camp_type, "barracks_layout_version": version})
			var changed := Runtime.request_resize(data, key, large, Callable(), 1)
			assert(changed.ok, str(changed))
			assert(feature.camp_type == camp_type and feature.pending_build.size() == 7 and not feature.pending_build.has("camp_type"))
			var broken := feature.duplicate(true)
			broken.pending_build.camp_type = camp_type
			assert(not Runtime.validate_feature_layout(data, broken).ok, "Pending job must not become a second type owner")
			_complete_key(data, key)
			assert(feature.camp_type == camp_type and int(feature.barracks_layout_version) == version and feature.cells == large)
			assert(Runtime.validate_feature_layout(data, feature).ok)
			var legacy := feature.duplicate(true)
			legacy.erase("camp_type")
			assert(_geometry(data, legacy) == _geometry(data, feature))
	type_groups += 1

func _original_people(controller: SiteController, teams: Array[TerrainArmy]) -> Dictionary:
	var result := {}
	for team: TerrainArmy in teams:
		for body: Dictionary in team.combat_units:
			var person := controller.person_actions._person(int(body.person_id))
			result[int(body.person_id)] = {"body": person.body, "holder": person.holder, "cargo": person.cargo,
				"items": person.holder.duplicate(true), "cargo_copy": person.cargo.duplicate(true), "cell": person.cell}
	return result

func _assert_people_unchanged(controller: SiteController, original: Dictionary) -> bool:
	for identity: int in original:
		var person := controller.person_actions._person(identity)
		var saved: Dictionary = original[identity]
		assert(is_same(person.body, saved.body) and is_same(person.holder, saved.holder) and is_same(person.cargo, saved.cargo))
		assert(person.holder == saved.items and person.cargo == saved.cargo_copy and person.cell == saved.cell, "Garrison operation replaced, duplicated or teleported an original person/holder")
	return true

func _check_original_garrison(camp_type: String) -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var key := _formal_feature(data, "barracks", Vector2i(20, 20), Vector2i(10, 10), {"camp_type": camp_type, "barracks_layout_version": 2})
	var source: TerrainArmy = lab.army
	var second: TerrainArmy = lab.opposing_army
	_make_garrison_team(lab, source, [Vector2i(23, 26), Vector2i(24, 26), Vector2i(25, 26)])
	_make_garrison_team(lab, second, [Vector2i(23, 27), Vector2i(24, 27)])
	for team: TerrainArmy in [source, second]:
		var entry: Dictionary = controller._enable_team_supply(team)
		entry.inventory.grain = 100
		entry.sustain.open_rations = 0.375
	var original := _original_people(controller, [source, second])
	var meals := _meal_history(controller)
	var captain := source.combat_identity(0)
	var soldier := source.combat_identity(1)
	var second_soldier := second.combat_identity(1)
	var snapshot := source.capture_combat_state()
	assert(not Garrison.admit(lab, key, source.team_id, [captain, captain]).ok)
	assert(source.capture_combat_state() == snapshot and _meal_history(controller) == meals)
	assert(Garrison.admit(lab, key, source.team_id).ok and Garrison.admit(lab, key, second.team_id).ok)
	assert(source.current_commander == -1 and source.formal_commander == -1 and source.garrison_feature_id == key)
	assert(not Ground.inspect(controller, source.team_id).ok)
	assert(not controller.order_team_training(source, 0, true, key).ok, "Unformed garrison cannot train without an original qualified commander")
	assert(not Garrison.form(lab, key, [soldier, second_soldier], soldier).ok)
	assert(_assert_people_unchanged(controller, original) and _meal_history(controller) == meals)
	var query := Garrison.query(lab, key)
	assert(query.ok and query.people_count == 5 and query.officers.size() == 2)
	var before := JSON.stringify(data.site)
	assert(not Runtime.cancel_feature(data, key, Callable(), 1).ok, "Registered barracks people must prevent demolition")
	var large := _type_cells(data, "barracks", Vector2i(11, 10), {"camp_type": camp_type, "barracks_layout_version": 2})
	assert(not Runtime.request_resize(data, key, large, Callable(), 1).ok, "Registered dense barracks people must prevent rearranging their modules")
	assert(JSON.stringify(data.site) == before)
	var formed := Garrison.form(lab, key, [captain, soldier, second_soldier], captain)
	assert(formed.ok, str(formed))
	var team: TerrainArmy = Garrison._team(lab, int(formed.team_id))
	assert(team != null and team.garrison_feature_id.is_empty() and team.combat_identity(team.current_commander) == captain)
	assert(_assert_people_unchanged(controller, original) and _meal_history(controller) == meals)
	var checked := Ground.inspect(controller, team.team_id, key)
	assert(checked.ok == (camp_type == "standard"), str(checked))
	var ordered := controller.order_team_training(team, team.current_commander, true, key)
	assert(ordered.ok == (camp_type == "standard"), str(ordered))
	if ordered.ok:
		assert(controller.order_team_training(team, team.current_commander, false).ok)
	else:
		var prior_training := team.training
		controller.advance_team_sustain(team, 6.0)
		_near(team.training, prior_training, "Chinese barracks rejects Western training bonus")
	assert(_assert_people_unchanged(controller, original))
	lab.free()
	await process_frame
	TerrainArmy.release_contact_source()
	type_groups += 1

func _exercise_training(kind: String, missing_type: bool) -> Dictionary:
	var data := _building_fixture()
	var options: Dictionary = {"camp_type": "standard", "barracks_layout_version": 2} if kind == "barracks" else {}
	var key := _formal_feature(data, kind, Vector2i(20, 20), Vector2i(10, 10), options)
	if missing_type: data.site.features[key].erase("camp_type")
	# Fixture construction costs differ. Before any live person/supply exists,
	# align the meal epoch so only the facility changes the measured interval.
	data.site.minute = 0
	data.site.phase = 0.0
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var team: TerrainArmy = lab.army
	_make_garrison_team(lab, team, [Vector2i(23, 26), Vector2i(24, 26), Vector2i(25, 26)])
	for index: int in team.command_abilities:
		team.command_abilities[index].coach = 40 # Equal fixture coaching; facility is the only variable.
	team.training = 100.0
	team.team_fatigue.fatigue = 20.0
	team.team_fatigue.fatigue_rest = PersonFatigue.REST_DELAY
	team.team_fatigue.active = false
	var original := _original_people(controller, [team])
	var entry: Dictionary = controller._enable_team_supply(team)
	entry.inventory.grain = 100
	var checked := Ground.inspect(controller, team.team_id, key)
	assert(checked.ok and checked.eligible_ids.size() == 3, str(checked))
	assert(not controller.order_team_training(team, 1, true, key).ok)
	assert(controller.order_team_training(team, team.current_commander, true, key).ok)
	assert(entry.training_feature_id == key and entry.training_requester == team.combat_identity(team.current_commander))
	var fatigue_before := float(team.team_fatigue.fatigue)
	var clock_before := float(entry.sustain.at)
	var food_before := SiteController.Sustain.rations(entry.sustain, entry.inventory)
	var handled := controller.advance_team_sustain(team, 6.0)
	var effort: Array = handled.handled_seconds.values()
	effort.sort()
	assert(effort.size() == 3)
	for seconds: float in effort: _near(seconds, 6.0, "One original training effort interval per member")
	_near(float(entry.sustain.at) - clock_before, 6.0, "Supply receives the original single interval")
	_near(float(team.team_fatigue.fatigue) - fatigue_before, PersonFatigue.WORK_RATE * 6.0, "Training fatigue is not multiplied")
	assert(team.training > 100.0 and _assert_people_unchanged(controller, original))
	var result := {"gain": team.training - 100.0, "fatigue": float(team.team_fatigue.fatigue) - fatigue_before,
		"handled_seconds": effort, "at_start": clock_before,
		"food_used": food_before - SiteController.Sustain.rations(entry.sustain, entry.inventory), "coach": checked.coach}
	var large := _type_cells(data, kind, Vector2i(11, 10), options)
	var before := JSON.stringify(data.site)
	assert(not Runtime.request_resize(data, key, large, Callable(), 1).ok, "Active facility-bound training must prevent resize")
	assert(JSON.stringify(data.site) == before and entry.training_order)
	data.site.paused = true
	var paused_training := team.training
	var paused_pool := team.team_fatigue.duplicate(true)
	controller.advance_team_sustain(team, 6.0)
	assert(team.training == paused_training and team.team_fatigue == paused_pool)
	data.site.paused = false
	data.site.combat_left = 1.0
	controller.advance_team_sustain(team, 6.0)
	assert(team.training == paused_training and entry.training_order, "Combat pauses the original order without erasing its feature reference")
	data.site.combat_left = 0.0
	var removed := Runtime.cancel_feature(data, key, Callable(), 1)
	assert(removed.ok, str(removed))
	assert(not data.site.features.has(key) and not entry.training_order and entry.training_requester == -1 and entry.training_feature_id.is_empty())
	assert(not controller.order_team_training(team, team.current_commander, true, key).ok)
	assert(_assert_people_unchanged(controller, original))
	lab.free()
	await process_frame
	TerrainArmy.release_contact_source()
	type_groups += 1
	return result

func _check_training_effort() -> void:
	var members := {101: {"person_id": 101, "hp": 100.0, "ko": 0.0, "captive": false, "present": true,
		"fatigue": 79.0, "fatigue_rest": 0.0, "work_resting": false}}
	var boosted := members.duplicate(true)
	var context := {"ordered": true, "commander": true, "safe": true, "stopped": true, "fed": true, "coach": 40.0}
	var baseline := SiteController.Sustain.train(100.0, members, [101], 600.0, context)
	context.training_multiplier = 1.25
	var faster := SiteController.Sustain.train(100.0, boosted, [101], 600.0, context)
	assert(baseline.ok and faster.ok and baseline.handled_ids == faster.handled_ids and baseline.effort_seconds == faster.effort_seconds)
	assert(members == boosted, "Training multiplier changed original work/rest effort rather than only output")
	_near(float(faster.training) - 100.0, (float(baseline.training) - 100.0) * 1.25, "Shared Sustain rule retains rest-boundary effort")
	type_groups += 1

func _reset_recovery_pool(team: TerrainArmy) -> void:
	team.team_fatigue.fatigue = 60.0
	team.team_fatigue.fatigue_rest = PersonFatigue.REST_DELAY
	team.team_fatigue.active = false

func _assert_pool(team: TerrainArmy, original: Dictionary) -> bool:
	assert(is_same(team.team_fatigue, original))
	for body: Dictionary in team.combat_units: assert(is_same(PersonFatigue.pool(body), original))
	return true

func _check_original_recovery() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var key := _formal_feature(data, "barracks", Vector2i(20, 20), Vector2i(10, 10), {"camp_type": "chinese", "barracks_layout_version": 2})
	var feature: Dictionary = data.site.features[key]
	var team: TerrainArmy = lab.army
	_make_garrison_team(lab, team, [Vector2i(23, 26), Vector2i(24, 26), Vector2i(25, 26)])
	assert(Garrison.admit(lab, key, team.team_id).ok)
	var pool: Dictionary = team.team_fatigue
	var original := _original_people(lab.site_controller, [team])
	var normal_loss := PersonFatigue.RECOVERY_RATE * 6.0
	for camp_type: String in ["standard", "chinese"]:
		feature.camp_type = camp_type
		_reset_recovery_pool(team)
		_near(Garrison.recovery_multiplier(lab, key, team.faction_id, team.combat_units), 1.25 if camp_type == "chinese" else 1.0, "Only Chinese registered facility enables recovery")
		lab._advance_team_fatigue(team, 6.0, {}, {})
		_near(60.0 - float(pool.fatigue), normal_loss * (1.25 if camp_type == "chinese" else 1.0), "Original GD phase applies recovery once")
		assert(_assert_pool(team, pool))
	# One absent living member disables the bonus for the same complete pool.
	var old_cell := team.cells[1]
	team.cells[1] = Vector2i(40, 40)
	_near(Garrison.recovery_multiplier(lab, key, team.faction_id, team.combat_units), 1.0, "One outside member blocks the whole-pool bonus")
	_reset_recovery_pool(team)
	lab._advance_team_fatigue(team, 6.0, {}, {})
	_near(60.0 - float(pool.fatigue), normal_loss, "An invalid member does not split off a faster subpool")
	assert(_assert_pool(team, pool))
	team.cells[1] = old_cell
	team.combat_hot_set(1, &"ko", 2.0)
	_near(Garrison.recovery_multiplier(lab, key, team.faction_id, team.combat_units), 1.0, "One unconscious living member blocks bonus")
	team.combat_hot_set(1, &"ko", 0.0)
	team.combat_hot_set(1, &"captive", true)
	_near(Garrison.recovery_multiplier(lab, key, team.faction_id, team.combat_units), 1.0, "One captive blocks bonus")
	team.combat_hot_set(1, &"captive", false)
	team.moving_to[1] = Vector2i(24, 27)
	_near(Garrison.recovery_multiplier(lab, key, team.faction_id, team.combat_units), 1.0, "One moving member blocks bonus")
	team.moving_to[1] = TerrainArmy.INVALID_CELL
	feature.owner_faction = 2
	_near(Garrison.recovery_multiplier(lab, key, team.faction_id, team.combat_units), 1.0, "Foreign facility blocks bonus")
	feature.owner_faction = 1
	feature.stage = "building"
	_near(Garrison.recovery_multiplier(lab, key, team.faction_id, team.combat_units), 1.0, "Unfinished facility blocks bonus")
	feature.stage = "complete"
	_near(Garrison.recovery_multiplier(lab, "missing", team.faction_id, team.combat_units), 1.0, "Missing original registration blocks bonus")
	_reset_recovery_pool(team)
	pool.fatigue_rest = 0.0
	lab._advance_team_fatigue(team, PersonFatigue.REST_DELAY, {}, {})
	_near(float(pool.fatigue), 60.0, "Original rest delay is not multiplied or skipped")
	for guard: String in ["active", "combat", "order", "threat"]:
		_reset_recovery_pool(team)
		if guard == "active": pool.active = true
		elif guard == "combat": data.site.combat_left = 1.0
		elif guard == "order": team.combat_order = TerrainArmy.CombatOrder.MOVE
		else:
			lab.npc.faction_id = 2
			assert(lab.npc.place(Vector2i(26, 26), true))
		lab._advance_team_fatigue(team, 6.0, {}, {})
		_near(float(pool.fatigue), 60.0, "Original recovery safety guard: " + guard)
		data.site.combat_left = 0.0
		team.combat_order = TerrainArmy.CombatOrder.HOLD
		lab.npc.faction_id = 1
		assert(lab.npc.place(Vector2i(10, 9), true))
		assert(_assert_pool(team, pool))
	assert(_assert_people_unchanged(lab.site_controller, original))
	lab.free()
	await process_frame
	TerrainArmy.release_contact_source()
	type_groups += 1
