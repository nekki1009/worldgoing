extends "res://scripts/tests/site_barracks_types_crowd_test.gd"
## Actual TrainingGround.advance_native and the existing common supply clock.
const TypesGround = preload("res://scripts/terrain_lab/site_training_ground.gd")

func _run() -> void:
	deadline = Time.get_ticks_msec() + 300000
	_types_require_native()
	var school: Dictionary = await _exercise_types_native_training("training_ground", "")
	if not _complete_types_training_sample(school, false): return
	var standard: Dictionary = await _exercise_types_native_training("barracks", "standard")
	if not _complete_types_training_sample(standard, false): return
	var chinese: Dictionary = await _exercise_types_native_training("barracks", "chinese")
	if not _complete_types_training_sample(chinese, true): return
	_types_near(float(standard.direct_gain), float(school.direct_gain) * 1.25, "Actual advance_native standard gain is 1.25")
	_types_near(float(standard.common_gain), float(school.common_gain) * 1.25, "Common-clock standard gain is 1.25")
	for field: String in ["direct_fatigue", "common_fatigue", "food_used", "clock_start", "clock_elapsed", "supply_elapsed", "coach", "eligible_count"]:
		_types_near(float(standard[field]), float(school[field]), "Training multiplier retains original " + field)
	assert(float(school.direct_gain) > 0.0 and float(school.food_used) > 0.0 and chinese.rejected)
	if types_failures != 0:
		push_error("Two-type native training numerical failures: %d" % types_failures)
		quit(1)
		return
	TerrainArmy.release_contact_source()
	print("SITE_BARRACKS_TYPES_TRAINING_CROWD_PASS: original native TrainingGround.advance_native and common clock; standard output 1.25 vs school; three original trainees, coaching, work fatigue and positive meal-boundary consumption unchanged; Chinese rejects training; active standard reference Store roundtrip")
	quit(0)

func _complete_types_training_sample(sample: Dictionary, rejected: bool) -> bool:
	var required: Array = ["rejected"] if rejected else ["direct_gain", "common_gain", "direct_fatigue", "common_fatigue", "food_used", "clock_start", "clock_elapsed", "supply_elapsed", "coach", "eligible_count"]
	for field: String in required:
		if not sample.has(field):
			push_error("Native training fixture stopped before a complete %s result" % ("rejection" if rejected else "training"))
			quit(1)
			return false
	return true

func _exercise_types_native_training(kind: String, camp_type: String) -> Dictionary:
	var data := _types_persistent_fixture()
	var options := {"camp_type": camp_type} if kind == "barracks" else {}
	var key := _formal_feature(data, kind, Vector2i(20, 20), Vector2i(10, 10), options)
	# Every fixture reaches three seconds before the same actual six-hour meal boundary after 90 warm-up steps.
	var initial_seconds := SiteController.Sustain.MEAL - 183.0
	data.site.minute = floori(initial_seconds / 60.0)
	data.site.phase = initial_seconds / 60.0 - float(data.site.minute)
	var lab := _building_lab(data)
	lab.fixed_action_steps_enabled = false
	var controller: SiteController = lab.site_controller
	var team: TerrainArmy = lab.army
	_make_garrison_team(lab, team, [Vector2i(23, 26), Vector2i(24, 26), Vector2i(25, 26)])
	for index: int in team.command_abilities: team.command_abilities[index].coach = 40
	var captain := team.combat_identity(team.current_commander)
	var identities: Array[int] = []
	for row: Dictionary in team.combat_units: identities.append(int(row.person_id))
	var entry: Dictionary = controller._enable_team_supply(team)
	entry.inventory.grain = 100
	entry.sustain.open_rations = 0.375
	var seed_row: Dictionary = team.combat_units[0]
	var host: Node = await _types_enter_crowd(lab, seed_row)
	var owner: RefCounted = host.person_owner(captain)
	entry = controller._supply_entry(owner)
	for _warmup: int in range(90): lab._advance_action_time(TerrainLab.EXCHANGE_ACTION_STEP)
	assert(host.active and host.last_event_error.is_empty(), str(host.last_event_error))
	_types_near(Runtime.now(data) * 60.0, SiteController.Sustain.MEAL - 3.0, "Equal native training fixture epoch")
	assert(host.set_formation_fields(owner.formation_index, {"training": 100.0, "fatigue": 20.0, "fatigue_rest": PersonFatigue.REST_DELAY}))
	var checked := TypesGround.inspect(controller, int(owner.team_id), key)
	var original := _types_people(controller, identities)
	if camp_type == "chinese":
		assert(not checked.ok and not controller.order_team_training(owner, owner.index_for_identity(captain), true, key).ok)
		var values: Dictionary = host.formation_state(owner.formation_index)
		var supply := JSON.stringify(entry)
		assert(TypesGround.advance_native(controller, owner, entry, TYPES_INTERVAL, true).ok)
		assert(host.formation_state(owner.formation_index) == values and JSON.stringify(entry) == supply)
		_types_same_people(controller, original)
		print("SITE_BARRACKS_TYPES_TRAINING_CROWD_CHINESE_PASS: physical Chinese facility cannot accept original native training order")
		for _frame: int in range(3): await process_frame
		lab.free()
		await process_frame
		TerrainArmy.release_contact_source()
		return {"rejected": true}
	assert(checked.ok and checked.safe and checked.eligible_ids.size() == 3, str(checked))
	_types_near(float(checked.coach), 40.0, "Original qualified captain coaching")
	_types_near(float(checked.training_multiplier), 1.25 if camp_type == "standard" else 1.0, "Original facility output scalar")
	assert(controller.order_team_training(owner, owner.index_for_identity(captain), true, key).ok)
	assert(entry.training_feature_id == key and int(entry.training_requester) == captain and bool(entry.training_order))
	var meal_before := JSON.stringify(entry)
	var site_before := Runtime.now(data)
	var trained := TypesGround.advance_native(controller, owner, entry, TYPES_INTERVAL, true)
	assert(trained.ok, str(trained))
	var direct: Dictionary = host.formation_state(owner.formation_index)
	var result := {"direct_gain": float(direct.training) - 100.0, "direct_fatigue": float(direct.fatigue) - 20.0,
		"coach": checked.coach, "eligible_count": checked.eligible_ids.size(), "clock_start": Runtime.now(data) * 60.0}
	_types_near(float(result.direct_fatigue), PersonFatigue.WORK_RATE * TYPES_INTERVAL, "advance_native charges one original work interval")
	assert(float(result.direct_gain) > 0.0 and JSON.stringify(entry) == meal_before and Runtime.now(data) == site_before,
		"TrainingGround must leave meal and Site advancement to their original clock")
	_types_same_people(controller, original)
	# Measure the real common-clock flow from the same baseline, crossing an actual meal boundary.
	assert(host.set_formation_fields(owner.formation_index, {"training": 100.0, "fatigue": 20.0, "fatigue_rest": PersonFatigue.REST_DELAY}))
	var clock_before := Runtime.now(data)
	var supply_at := float(entry.sustain.at)
	var food_before := SiteController.Sustain.rations(entry.sustain, entry.inventory)
	lab._advance_action_time(TYPES_INTERVAL / 60.0)
	var common: Dictionary = host.formation_state(owner.formation_index)
	result.common_gain = float(common.training) - 100.0
	result.common_fatigue = float(common.fatigue) - 20.0
	result.clock_elapsed = (Runtime.now(data) - clock_before) * 60.0
	result.supply_elapsed = float(entry.sustain.at) - supply_at
	result.food_used = food_before - SiteController.Sustain.rations(entry.sustain, entry.inventory)
	_types_near(float(result.common_gain), float(result.direct_gain), "Same six-second interval through advance_native and common flow")
	_types_near(float(result.common_fatigue), PersonFatigue.WORK_RATE * TYPES_INTERVAL, "Common flow applies work effort once")
	_types_near(float(result.clock_elapsed), TYPES_INTERVAL, "Common Site interval")
	_types_near(float(result.supply_elapsed), TYPES_INTERVAL, "Original one meal interval")
	assert(float(result.food_used) > 0.0 and bool(entry.training_order) and entry.training_feature_id == key)
	_types_same_people(controller, original)
	# Store keeps the same active feature-bound native training reference and its original people/meal history.
	var path := controller.save_root.path_join("types_native_training_%s.json" % (camp_type if not camp_type.is_empty() else "school"))
	assert(not FileAccess.file_exists(path), "Use a fresh isolated --crowd-test run ID")
	assert(DirAccess.make_dir_recursive_absolute(controller.save_root) == OK)
	var meals := _meal_history(controller)
	var saved := controller.save_to(path)
	assert(saved.ok, str(saved))
	var file_before := FileAccess.get_file_as_string(path)
	var loaded := Store.load_site(path)
	assert(loaded.ok and not is_same(loaded.data, data), str(loaded))
	var persisted: Dictionary = loaded.data.site.team_supply[str(owner.team_id)]
	assert(persisted.training_order and persisted.training_feature_id == key and int(persisted.training_requester) == captain)
	assert(loaded.data.fingerprint() == data.fingerprint() and FileAccess.get_file_as_string(path) == file_before and _meal_history(controller) == meals)
	if camp_type == "standard": assert(loaded.data.site.features[key].camp_type == "standard")
	print("SITE_BARRACKS_TYPES_TRAINING_CROWD_MEASURE ", kind, "/", camp_type, " ", JSON.stringify(result))
	for _frame: int in range(3): await process_frame
	lab.free()
	await process_frame
	TerrainArmy.release_contact_source()
	return result
