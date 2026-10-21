extends SceneTree
## Formal Lab/UI deployment, actual holders, homogeneous troops and Site restore.
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const OUT := "res://output/ranged_behavior_fix_20260918/deployment"
var deadline := 0

class FirstError extends Logger:
	var _mutex: Mutex = Mutex.new()
	var _first: String = ""

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING: return
		# Logger callbacks may be concurrent; only store the first error here.
		_mutex.lock()
		if _first.is_empty(): _first = "%s:%d %s: %s %s" % [file, line, function, code, rationale]
		_mutex.unlock()

	func first_error() -> String:
		_mutex.lock()
		var result: String = _first
		_mutex.unlock()
		return result

var _errors: FirstError = FirstError.new()
var _guard_failure: String = ""
var _stopped: bool = false

func _has_failure() -> bool:
	return not _guard_failure.is_empty() or not _errors.first_error().is_empty()

func _expect(condition: bool, message: String, source_line: int) -> bool:
	if _has_failure(): return false
	if condition: return true
	_guard_failure = "line %d: %s" % [source_line, message]
	printerr("FIRE_P0_SITE_RANGED_ARMY_FAIL: " + _guard_failure)
	return false

func _abort() -> void:
	if _stopped: return
	_stopped = true
	if not _errors.first_error().is_empty(): printerr("FIRE_P0_FIRST_ERROR: " + _errors.first_error())
	quit(1)

func _finalize() -> void:
	OS.remove_logger(_errors)

func _initialize() -> void:
	OS.add_logger(_errors)
	deadline = Time.get_ticks_msec() + 90000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if _has_failure(): _abort(); return false
	if Time.get_ticks_msec() > deadline:
		push_error("Ranged deployment integration deadline")
		quit(1)
	return false

func _assert_team(team: TerrainArmy, weapon: String, women: int, spent_first: int = 0) -> bool:
	var ammo := "arrow" if weapon == "bow_01" else "bolt"
	var female_count := 0
	for index in range(team.combat_units.size()):
		var row: Dictionary = team.combat_units[index]
		var appearance := team.equipment_appearance(index)
		if not _expect(appearance.parts.weapon == weapon and appearance.parts.shield == "none", "Original deployment expectation at prior FIX5 line 23", 23): _abort(); return false
		female_count += int(appearance.body == 1)
		if not _expect(str(row.visual_role).begins_with("female") == (appearance.body == 1), "Original deployment expectation at prior FIX5 line 25", 25): _abort(); return false
		if not _expect(row.cargo == {ammo: 20 - (spent_first if index == 0 else 0)}, "Only actual carried test ammo is initialized; restore cannot refill it", 26): _abort(); return false
		if not _expect(SiteRuntime.carried_size(row.cargo, row.item_state) <= SiteRuntime.CARRY_CAPACITY, "Original deployment expectation at prior FIX5 line 27", 27): _abort(); return false
		var record: Dictionary = team.data.site.item_records[row.item_state.equipped.weapon]
		if not _expect(str(record.holder) == "person:%d" % team.combat_identity(index), "Original deployment expectation at prior FIX5 line 29", 29): _abort(); return false
		if not _expect(team.data.site.item_definitions[record.definition].asset == weapon, "Original deployment expectation at prior FIX5 line 30", 30): _abort(); return false
		if not team._uses_live_presenter(index):
			if not _expect(team.supports_equipment_recipe(appearance), "Original deployment expectation at prior FIX5 line 32", 32): _abort(); return false
	if not _expect(female_count == women, "Original deployment expectation at prior FIX5 line 33", 33): _abort(); return false
	if not _expect(TerrainArmy.single_troop_class(team.combat_units, team.data, team._troop_exempt_ids()) == (&"bow" if weapon == "bow_01" else &"crossbow"), "Original deployment expectation at prior FIX5 line 34", 34): _abort(); return false

	return true

func _run() -> void:
	if not _expect(DisplayServer.get_name() == "headless", "Original deployment expectation at prior FIX5 line 37", 37): _abort(); return
	var operation_38_1: int = DirAccess.make_dir_recursive_absolute(OUT)
	if _has_failure(): _abort(); return
	if not _expect(operation_38_1 == OK, "Original deployment expectation at prior FIX5 line 38", 38): _abort(); return
	# Equipment recipe support reads the baked soldier atlas (terrain_army.gd _combat_bake),
	# which only the crowd and Store paths load. This test has no crowd, so load it here.
	var combat_bake_loaded: bool = TerrainArmy.load_combat_bake()
	if not _expect(combat_bake_loaded, "Soldier combat atlas must load before recipe support is checked", 42): _abort(); return
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	# Explicit legacy/reference owner and render regression; new physical admission has separate tests.
	lab.physical_ranged_enabled = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	# The trial deployment controls live only in the Lab test window, which the
	# canonical run does not create (no --site-test-ui). Build it as the fire fixture does.
	if not is_instance_valid(lab.site_test_window):
		var window_script: Script = load("res://scripts/terrain_lab/site_test_window.gd")
		lab.site_test_window = window_script.new()
		lab.add_child(lab.site_test_window)
		lab.site_test_window.call("setup", lab)
	var controller: SiteController = lab.site_controller
	for prefix: String in ["friendly", "enemy", "third"]:
		var choice: OptionButton = controller.trial_troop_types[prefix]
		if not _expect(controller.combat_window.is_ancestor_of(choice) and choice.item_count == 3, "Original deployment expectation at prior FIX5 line 63", 63): _abort(); return
		if not _expect(choice.name == prefix.capitalize() + "TroopType", "Original deployment expectation at prior FIX5 line 64", 64): _abort(); return
		choice.select(2)
		controller.trial_roles[prefix].select(1)
		controller._trial_role_changed(prefix)
		if not _expect(choice.disabled and choice.selected == 0, "Original deployment expectation at prior FIX5 line 68", 68): _abort(); return
		if not _expect(controller._trial_setup()[prefix + "_troop_type"] == "melee_infantry", "Original deployment expectation at prior FIX5 line 69", 69): _abort(); return
		controller.trial_roles[prefix].select(2)
		controller._trial_role_changed(prefix)
		if not _expect(choice.disabled and choice.selected == 0, "Original deployment expectation at prior FIX5 line 72", 72): _abort(); return
		controller.trial_roles[prefix].select(0)
		controller._trial_role_changed(prefix)
		if not _expect(not choice.disabled, "Original deployment expectation at prior FIX5 line 75", 75): _abort(); return
	for invalid: Dictionary in [
		{"friendly_troop_type": "mixed"}, {"enemy_troop_type": true},
		{"friendly_role": "work", "friendly_troop_type": "bow"},
		{"enemy_role": "logistics", "enemy_troop_type": "crossbow"},
		{"third_enabled": true, "third_troop_type": "invalid"},
	]:
		var before := var_to_bytes(lab.terrain.site)
		var operation_83_1: Dictionary = lab.start_melee_trial(invalid)
		if _has_failure(): _abort(); return
		if not _expect(operation_83_1.code == "INVALID", "Original deployment expectation at prior FIX5 line 83", 83): _abort(); return
		if not _expect(var_to_bytes(lab.terrain.site) == before and not lab.army.has_army(), "Original deployment expectation at prior FIX5 line 84", 84): _abort(); return
	controller.trial_friendly_count.value = 6
	controller.trial_enemy_count.value = 4
	controller.trial_third_count.value = 3
	controller.trial_friendly_female_percent.value = 50
	controller.trial_enemy_female_percent.value = 50
	controller.trial_third_female_percent.value = 100
	controller.trial_troop_types["friendly"].select(1)
	controller.trial_troop_types["enemy"].select(2)
	controller.trial_troop_types["third"].select(1)
	controller.trial_friendly_order.select(0)
	controller.trial_enemy_order.select(0)
	controller.trial_third_order.select(0)
	controller.trial_third_enabled.button_pressed = true
	# Directional UI defaults deploy from map edges. This shot/save regression
	# requests a legal six-cell fixture through the existing custom-spawn UI.
	var layout := lab.find_melee_trial_layout(6, 4, TerrainArmy.INVALID_CELL, TerrainArmy.INVALID_CELL, 3, TerrainArmy.INVALID_CELL, 8.0, 8.0)
	if not _expect(not layout.is_empty(), "Original planner supplies three legal ranged formations", 101): _abort(); return
	var custom := lab.find_melee_trial_layout(6, 4, layout.friendly[0], layout.enemy[0], 3, layout.third[0], 8.0, 8.0)
	if not _expect(not custom.is_empty(), "All three anchors must pass the original custom-shape contract", 103): _abort(); return
	if not _expect(Vector2i(custom.friendly[0]).distance_to(custom.enemy[0]) == 6.0, "Original deployment expectation at prior FIX5 line 104", 104): _abort(); return
	if not _expect(SiteCombatRules.ranged_line_clear(lab.terrain, custom.friendly[0], custom.enemy[0]), "The original first bow has a clear firing lane", 105): _abort(); return
	controller.selected = custom.friendly[0]
	controller._set_trial_spawn(true)
	controller.selected = custom.enemy[0]
	controller._set_trial_spawn(false)
	controller.selected = custom.third[0]
	controller._set_third_trial_spawn()
	var setup := controller._trial_setup()
	if not _expect(setup.friendly_spawn == custom.friendly[0] and setup.enemy_spawn == custom.enemy[0] and setup.third_spawn == custom.third[0], "Original deployment expectation at prior FIX5 line 113", 113): _abort(); return
	if not _expect(setup.friendly_troop_type == "bow" and setup.enemy_troop_type == "crossbow" and setup.third_troop_type == "bow", "Original deployment expectation at prior FIX5 line 114", 114): _abort(); return
	controller._deploy_melee_trial()
	if not _expect(lab.army.combat_units.size() == 6 and lab.opposing_army.combat_units.size() == 4 and lab.third_army.combat_units.size() == 3, controller.message.text, 116): _abort(); return
	if not _expect(lab.army.cells[0].distance_to(lab.opposing_army.cells[0]) == 6.0, "Explicit legal UI spawns leave six cells between fronts", 117): _abort(); return
	if not _assert_team(lab.army, "bow_01", 3): return
	if not _assert_team(lab.opposing_army, "crossbow_01", 2): return
	if not _cc121_regular_third(lab.third_army): _abort(); return
	if not _assert_team(lab.third_army, "bow_01", 3): return
	var mixed := lab.army.equipment_appearance(1).duplicate(true)
	mixed.parts.weapon = "crossbow_01"
	var person := controller.person_actions._person(lab.army.combat_identity(1))
	var held_before := var_to_bytes(lab.terrain.site.item_records)
	if not _expect(controller._equipment_recipe_guard(person, mixed).code == "MIXED_TROOP", "Original deployment expectation at prior FIX5 line 131", 131): _abort(); return
	if not _expect(var_to_bytes(lab.terrain.site.item_records) == held_before, "Original deployment expectation at prior FIX5 line 132", 132): _abort(); return
	var operation_133_1: bool = lab.army.ranged_fire(0, lab.opposing_army.cells[0], 7001)
	if _has_failure(): _abort(); return
	if not _expect(operation_133_1, "Original deployment expectation at prior FIX5 line 133", 133): _abort(); return
	if not _expect(lab.army.combat_units[0].cargo.arrow == 19 and controller.supply_save_guard().code == "BUSY", "Original deployment expectation at prior FIX5 line 134", 134): _abort(); return
	# Advance the original Lab clock in completed action slices (2.0 s), as the
	# physical ranged path requires; _advance_ranged rejects deltas above one slice.
	for tick in range(60): lab._process(TerrainLab.EXCHANGE_ACTION_STEP)
	for tick in range(450): lab._process(TerrainLab.EXCHANGE_ACTION_STEP)
	if not _expect(not lab.has_ranged_projectiles() and is_zero_approx(float(lab.terrain.site.combat_left)), "Original deployment expectation at prior FIX5 line 139", 139): _abort(); return
	if not _assert_team(lab.army, "bow_01", 3, 1): return
	_cc121_team("live_before_capture", lab.third_army)
	controller._capture_positions()
	_cc121_snapshots("live_capture", lab.terrain.site.get("armies", []))
	var operation_142_1: Dictionary = Store.save(lab.terrain, OUT + "/three_troops.json")
	if _has_failure(): _abort(); return
	if not _expect(operation_142_1.ok, "Original deployment expectation at prior FIX5 line 142", 142): _abort(); return
	var raw_saved: Dictionary = Store._read(OUT + "/three_troops.json")
	if bool(raw_saved.get("ok", false)): _cc121_snapshots("raw_saved", raw_saved.payload.state.get("armies", []))
	else: print("CC121_RAW_SAVED_READ ", JSON.stringify(raw_saved))
	var loaded := Store.load_site(OUT + "/three_troops.json")
	if bool(loaded.get("ok", false)): _cc121_snapshots("loaded", loaded.data.site.get("armies", []))
	if not _expect(loaded.ok and loaded.data.site.armies.size() == 3, "Original deployment expectation at prior FIX5 line 144", 144): _abort(); return
	lab.bind_terrain(loaded.data)
	_cc121_team("post_bind", lab.third_army)
	controller._auto_save_blocked = true
	if not _assert_team(lab.army, "bow_01", 3, 1): return
	if not _assert_team(lab.opposing_army, "crossbow_01", 2): return
	if not _assert_team(lab.third_army, "bow_01", 3): return
	lab.clear_army()
	if not _expect(not lab.army.has_army() and not lab.third_army.has_army(), "Original deployment expectation at prior FIX5 line 151", 151): _abort(); return
	var invalid_spawn := {"friendly_count": 3, "enemy_count": 3, "friendly_troop_type": "bow", "enemy_troop_type": "crossbow",
		"friendly_spawn": lab.character.terrain_cell, "enemy_spawn": lab.character.terrain_cell + Vector2i(6, 0)}
	var before_spawn := var_to_bytes(lab.terrain.site)
	var operation_155_1: Dictionary = lab.start_melee_trial(invalid_spawn)
	if _has_failure(): _abort(); return
	if not _expect(not operation_155_1.ok, "Original deployment expectation at prior FIX5 line 155", 155): _abort(); return
	if not _expect(var_to_bytes(lab.terrain.site) == before_spawn and not lab.army.has_army(), "Original deployment expectation at prior FIX5 line 156", 156): _abort(); return
	var first_two := {"friendly_count": 3, "enemy_count": 3, "friendly_troop_type": "bow", "enemy_troop_type": "crossbow",
		"friendly_female_percent": 0, "enemy_female_percent": 100, "friendly_attack": false, "enemy_attack": false}
	var deployed := lab.start_melee_trial(first_two)
	if not _expect(deployed.ok, str(deployed), 160): _abort(); return
	var first_cargo: Dictionary = lab.army.combat_units[0].cargo
	var site_alias: Dictionary = lab.terrain.site
	var original_site := var_to_bytes(lab.terrain.site)
	var first_snapshot := lab.army.capture_combat_state()
	var original_initializer: Callable = lab.third_army.equipment_initializer
	lab.third_army.equipment_initializer = func(team: TerrainArmy) -> void:
		original_initializer.call(team)
		if _has_failure(): _abort(); return
		team.combat_units[0].cargo.wood = 1 # Force the final real capacity guard, after initial items/IDs were allocated.
	var third := {"third_count": 3, "third_female_percent": 100, "third_troop_type": "crossbow", "third_attack": false}
	var failed := lab.add_melee_trial_team(third)
	lab.third_army.equipment_initializer = original_initializer
	if not _expect(not failed.ok and failed.code == "DEPLOY_FAILED", str(failed), 172): _abort(); return
	if not _expect(not lab.third_army.has_army() and lab.army.capture_combat_state() == first_snapshot, "Original deployment expectation at prior FIX5 line 173", 173): _abort(); return
	if not _expect(is_same(lab.terrain.site, site_alias) and is_same(lab.army.combat_units[0].cargo, first_cargo), "Original deployment expectation at prior FIX5 line 174", 174): _abort(); return
	if not _expect(var_to_bytes(lab.terrain.site) == original_site, "Late capacity failure preserves items, allocators and existing ammo", 175): _abort(); return
	var added := lab.add_melee_trial_team(third)
	if not _expect(added.ok and added.third_troop_type == "crossbow", str(added), 177): _abort(); return
	if not _expect(lab.army.capture_combat_state() == first_snapshot and is_same(lab.army.combat_units[0].cargo, first_cargo), "Original deployment expectation at prior FIX5 line 178", 178): _abort(); return
	if not _cc121_regular_third(lab.third_army): _abort(); return
	if not _assert_team(lab.third_army, "crossbow_01", 3): return
	controller._capture_positions()
	var operation_181_1: Dictionary = Store.save(lab.terrain, OUT + "/appended_troop.json")
	if _has_failure(): _abort(); return
	if not _expect(operation_181_1.ok, "Original deployment expectation at prior FIX5 line 181", 181): _abort(); return
	lab.clear_army()
	var support := lab.start_melee_trial({"friendly_count": 2, "enemy_count": 3, "friendly_role": "work", "enemy_role": "logistics",
		"enemy_cart_count": 1, "friendly_attack": false, "enemy_attack": false})
	if not _expect(support.ok and lab.army.role == "work" and lab.opposing_army.role == "logistics", str(support), 185): _abort(); return
	for team: TerrainArmy in [lab.army, lab.opposing_army]:
		for index in range(team.combat_units.size()):
			if not _expect(team.equipment_appearance(index).parts.weapon == "longsword_01", "Original deployment expectation at prior FIX5 line 188", 188): _abort(); return
			if not _expect(int(team.combat_units[index].cargo.get("arrow", 0)) == 0 and int(team.combat_units[index].cargo.get("bolt", 0)) == 0, "Original deployment expectation at prior FIX5 line 189", 189): _abort(); return
	controller._capture_positions()
	var operation_191_1: Dictionary = Store.save(lab.terrain, OUT + "/support_unchanged.json")
	if _has_failure(): _abort(); return
	if not _expect(operation_191_1.ok, "Original deployment expectation at prior FIX5 line 191", 191): _abort(); return
	if _has_failure(): _abort(); return
	lab.queue_free()
	await process_frame
	if _has_failure(): _abort(); return
	print("SITE RANGED DEPLOYMENT PASS: UI three troop selectors; formal mixed-gender bow/crossbow teams; real 20-round holders; six-cell deployment; spent ammo save/restore; homogeneous guard; atomic invalid/late-failed/third append; original work/logistics")
	quit(0)

const CC121_FREEZE_THIRD_DUTY_AI: bool = true
func _cc121_regular_third(team: TerrainArmy) -> bool:
	if CC121_FREEZE_THIRD_DUTY_AI:
		var policy: Dictionary = team.set_duty_ai_enabled(team.combat_identity(team.formal_commander), false)
		if not _expect(bool(policy.ok), "Original head disables duty AI for the named regular-troop fixture", 0): return false
	var offices: Dictionary = team.team_offices()
	var keep: Array[int] = []
	for seat: Dictionary in offices.positions:
		if bool(seat.get("head", false)) or str(seat.get("office_class", "military")) != "civil": keep.append(int(seat.holder))
	var _vacated: bool = SiteOffices.vacate_unless(offices, func(identity: int) -> bool: return keep.has(identity))
	team._sync_officer_order()
	_cc121_team("after_formal_vacate", team)
	return not _has_failure()

func _cc121_team(phase: String, team: TerrainArmy) -> void:
	print("CC121_CADRE_DIAG_ONLY ", JSON.stringify({"phase": phase, "freeze_duty_ai": CC121_FREEZE_THIRD_DUTY_AI,
		"team_id": team.team_id, "offices": team.offices, "officer_service": team.officer_service,
		"officers": team.officer_order, "formal_commander": team.formal_commander,
		"current_commander": team.current_commander, "last_holders": team._last_holders, "duty_trace_count": team.duty_traces.size()}))

func _cc121_snapshots(phase: String, armies: Array) -> void:
	for roster: Dictionary in armies:
		print("CC121_SAVED_DIAG_ONLY ", JSON.stringify({"phase": phase, "team_id": roster.get("team_id", -1),
			"cadre_seated": roster.get("cadre_seated", null), "offices": roster.get("offices", {}),
			"officer_service": roster.get("officer_service", []), "officers": roster.get("officers", [])}))
