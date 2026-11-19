extends SceneTree
## Dedicated Fire P0 baseline derived from site_ranged_army_test.gd.
## Original SHA-256: 589EED79F20AA4BB6E275D51FFB2E8BCE80C133770569562842F210B4018582C
## Keep the contact source prepared by original enable_combat and its sampling
## count unchanged, then release it during isolated-test cleanup. Recipe admission
## uses an explicit legal fixture ray. All original owner expectations remain
## release-active guards; mutations run separately and sticky errors prevent PASS.
## Siege/headless foot admission already prepares shared geometry. This test
## requires no additional ranged geometry queries, not an absent geometry source.
## The PASS marker is distinct so this cannot overwrite the original FAIL claim.

var geometry_calls := 0

class FirstError extends Logger:
	var _mutex := Mutex.new()
	var _first := ""

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING: return
		# Logger callbacks may be concurrent; only store the first error here.
		_mutex.lock()
		if _first.is_empty(): _first = "%s:%d %s: %s %s" % [file, line, function, code, rationale]
		_mutex.unlock()

	func first_error() -> String:
		_mutex.lock()
		var result := _first
		_mutex.unlock()
		return result

var _errors := FirstError.new()
var _guard_failure := ""
var _stopped := false

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

func _process(_delta: float) -> bool:
	if _has_failure(): _abort()
	return false

func _finalize() -> void:
	OS.remove_logger(_errors)

func _initialize() -> void:
	OS.add_logger(_errors)
	call_deferred("run")

func _weapon(data: TerrainData, row: Dictionary, asset: String) -> Dictionary:
	var made := SiteRuntime.create_equipment(data, row.item_state, "ranged_test_" + asset,
		{"slot": "weapon", "asset": asset, "tint": [1.0, 1.0, 1.0, 1.0]}, int(row.person_id))
	if not _expect(made.ok, "Original assertion at source line 20", 20): return {"ok": false}
	return made

func _packet(kind: String, hp: float, stun: float, stagger: float) -> Dictionary:
	return {"shield": false, "result": {"kind": kind, "hp": hp, "stun": stun, "stagger": stagger, "knockback": false}}

func run() -> void:
	create_timer(18.0).timeout.connect(func() -> void: quit(1))
	var completed: bool = _run_checks()
	if not completed or _has_failure():
		_abort()
		return
	call_deferred("_finish_success")

func _run_checks() -> bool:
	var data := TerrainData.new()
	data.allocate(Vector2i(40, 40))
	if _has_failure(): return false
	data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(data, "ranged-army-owner")
	if _has_failure(): return false
	data.static_blocked.fill(0)
	var operation_33_1: Dictionary = SiteRuntime.initialize_item_storage(data.site)
	if _has_failure(): return false
	if not _expect(operation_33_1.ok, "Original assertion at source line 33", 33): return false
	var army := TerrainArmy.new()
	root.add_child(army)
	if _has_failure(): return false
	army.set_process(false)
	army.exchange_enabled = true
	army.roster_size = 3
	var selected: Array[Vector2i] = [Vector2i(10, 10), Vector2i(12, 10), Vector2i(13, 10)]
	var operation_40_1: bool = army.deploy_at(data, null, null, selected)
	if _has_failure(): return false
	if not _expect(operation_40_1, "Original left prerequisite before operation", 40): return false
	var operation_40_2: bool = army.enable_combat(false, 0)
	if _has_failure(): return false
	if not _expect(operation_40_1 and operation_40_2, "Original assertion at source line 40", 40): return false
	var prepared_source: RefCounted = TerrainArmy._contact_source
	if not _expect(prepared_source != null, "Original enable_combat prepares the shared male contact source before queries", 42): return false
	var prepared_sample_calls := int(prepared_source.query_profile.sample_calls)
	for initial_row: Dictionary in army.combat_units:
		initial_row.cargo = {"arrow": 0, "bolt": 2}
		initial_row.appearance = TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
		initial_row.appearance.parts.shield = "none"
		initial_row.item_state = {}
		if not _expect(HumanCharacter3DEditor.valid_appearance(initial_row.appearance), "Fixture starts with a valid published body recipe", 49): return false
		var operation_50_1: Dictionary = SiteRuntime.seed_person_equipment(data, initial_row.item_state, int(initial_row.person_id), initial_row.appearance)
		if _has_failure(): return false
		if not _expect(operation_50_1.ok, "Fixture registers the original full equipment through its canonical item owner", 50): return false
	army.equipment_appearance_query = func(identity: int) -> Dictionary:
		var index := army.index_for_identity(identity)
		if not _expect(index >= 0, "Fixture appearance query resolves the original row identity", 54): return {}
		var original_row: Dictionary = army.combat_units[index]
		if not _expect(SiteRuntime._item_holder_shape(original_row.item_state), "Fixture holder retains actual equipment identities", 56): return {}
		var appearance := SiteRuntime.equipment_appearance(data, original_row.item_state, original_row.appearance)
		if not _expect(not appearance.is_empty(), "Fixture equipment projection remains valid: " + str(original_row.item_state), 58): return {}
		return appearance
	army.combat_target_query = func(_identity: int, _bodies: bool) -> Dictionary:
		geometry_calls += 1
		return {}
	var row: Dictionary = army.combat_units[0]
	var cargo: Dictionary = row.cargo
	var bow_created: Dictionary = _weapon(data, row, "bow_01")
	if not _expect(bool(bow_created.get("ok", false)), "Original weapon helper must complete", 0): return false
	var bow: String = str(bow_created.item_id)
	var crossbow_created: Dictionary = _weapon(data, row, "crossbow_01")
	if not _expect(bool(crossbow_created.get("ok", false)), "Original weapon helper must complete", 0): return false
	var crossbow: String = str(crossbow_created.item_id)
	var sword_created: Dictionary = _weapon(data, row, "longsword_01")
	if not _expect(bool(sword_created.get("ok", false)), "Original weapon helper must complete", 0): return false
	var sword: String = str(sword_created.item_id)
	row.item_state.equipped.weapon = bow
	if not _expect(army.ranged_profile(0).get("ammo", "") == "arrow", "The actual equipped bow must produce its arrow profile", 69): return false
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(army.capture_combat_state()))
	snapshot.units[0].ranged_cooldown = 2.0
	if not _expect(TerrainArmy.valid_combat_state(snapshot, data), "Original assertion at source line 72", 72): return false
	for invalid: Variant in [-1.0, 3.01, "0", null, INF, NAN]:
		var corrupt := snapshot.duplicate(true)
		corrupt.units[0].ranged_cooldown = invalid
		if not _expect(not TerrainArmy.valid_combat_state(corrupt, data), "Original assertion at source line 76", 76): return false
	snapshot.units[0].erase("ranged_cooldown")
	if not _expect(TerrainArmy.valid_combat_state(snapshot, data), "Legacy rows omit the new firing timer without being reinterpreted", 78): return false
	var operation_79_1: bool = army.start_unit_attack(0, selected[0] + Vector2i.RIGHT * 6, 9999)
	if _has_failure(): return false
	if not _expect(operation_79_1, "Original assertion at source line 79", 79): return false
	if not _expect(cargo.arrow == 0 and army.projectiles.is_empty(), "Target selection cannot create a shot or consume ammunition", 80): return false
	var operation_81_1: bool = army.ranged_fire(0, selected[0] + Vector2i.RIGHT * 6, 1)
	if _has_failure(): return false
	if not _expect(not operation_81_1, "No original ammunition means no shot", 81): return false
	if not _expect(cargo.arrow == 0 and army.projectiles.is_empty(), "Original assertion at source line 82", 82): return false
	cargo.arrow = 2 # Explicit fixture stock, never generated by the firing query.
	var operation_84_1: bool = army.ranged_fire(0, selected[0] + Vector2i.RIGHT, 1)
	if _has_failure(): return false
	if not _expect(not operation_84_1, "Original assertion at source line 84", 84): return false
	var operation_85_1: bool = army.ranged_fire(0, selected[0] + Vector2i.RIGHT * 9, 1)
	if _has_failure(): return false
	if not _expect(not operation_85_1, "Original assertion at source line 85", 85): return false
	var blocked := selected[0] + Vector2i.RIGHT * 3
	data.static_blocked[data.index(blocked)] = 1
	var operation_88_1: bool = army.ranged_fire(0, selected[0] + Vector2i.RIGHT * 6, 1)
	if _has_failure(): return false
	if not _expect(not operation_88_1, "Original assertion at source line 88", 88): return false
	data.static_blocked[data.index(blocked)] = 0
	row.item_state.equipped.weapon = sword
	if not _expect(army.ranged_profile(0).is_empty(), "Original left prerequisite before operation", 91): return false
	var operation_91_1: bool = army.ranged_fire(0, selected[0] + Vector2i.RIGHT * 6, 1)
	if _has_failure(): return false
	if not _expect(army.ranged_profile(0).is_empty() and not operation_91_1, "Original assertion at source line 91", 91): return false
	row.item_state.equipped.weapon = bow
	PersonFatigue.write(row, "fatigue", 10.0)
	PersonFatigue.write(row, "fatigue_rest", 15.0)
	var operation_95_1: bool = army.activate_exchange_skill(0, "power")
	if _has_failure(): return false
	if not _expect(operation_95_1, "Original assertion at source line 95", 95): return false
	var events: Array[float] = []
	army.combat_event.connect(func(seconds: float) -> void: events.append(seconds))
	var operation_98_1: bool = army.ranged_fire(0, selected[0] + Vector2i.RIGHT * 6, 1)
	if _has_failure(): return false
	if not _expect(operation_98_1, "Original assertion at source line 98", 98): return false
	if not _expect(is_same(cargo, row.cargo) and cargo.arrow == 1 and cargo.bolt == 2, "Original assertion at source line 99", 99): return false
	if not _expect(army.projectiles.size() == 1 and is_equal_approx(PersonFatigue.read(row), 10.0 + 1.0 / 3.0)
		and PersonFatigue.read(row, "fatigue_rest") == 0.0, "One shot charges the original three-person shared fatigue pool once", 100): return false
	var shot: Dictionary = army.projectiles[0]
	if not _expect(shot.shot_id == 1 and shot.shooter_id == army.combat_identity(0) and shot.target_cell == selected[0] + Vector2i.RIGHT * 6, "Original assertion at source line 104", 104): return false
	if not _expect(shot.mode == "cell" and shot.visual == "arrow" and is_equal_approx(float(shot.total), 0.6), "Original assertion at source line 105", 105): return false
	if not _expect(shot.shooter.fatigue == 10.0 and shot.shooter.skill == "power" and shot.shooter.weapon == "bow_01" and row.exchange_skill == "", "Original assertion at source line 106", 106): return false
	if not _expect(row.exchange_skill_cooldown == 8.0 and row.ranged_cooldown == 2.0 and row.exchange_stagger == 0.25, "Original assertion at source line 107", 107): return false
	if not _expect(float(row.get("exchange_cooldown", 0.0)) == 0.0 and army.exchange_can_receive(0), "Reloading must not grant melee immunity", 108): return false
	if not _expect(army.combat_frame(0).clip == "attack_bow" and events.has(12.0), "Original assertion at source line 109", 109): return false
	if not _expect(float(army.contact_sample(0)[1]) == float(TerrainArmy.CombatTimings.events(&"attack_bow").release), "Already released arrows start presentation at the authored release time", 110): return false
	var operation_111_1: bool = army.ranged_fire(0, selected[0] + Vector2i.RIGHT * 6, 2)
	if _has_failure(): return false
	if not _expect(not operation_111_1 and cargo.arrow == 1, "Original assertion at source line 111", 111): return false
	var frozen_shot := shot.duplicate(true)
	row.item_state.equipped.weapon = crossbow
	if not _expect(army.ranged_profile(0).ammo == "bolt" and shot == frozen_shot, "In-flight shot never follows new equipment or a new target", 114): return false
	army.ranged_apply_hit(0, selected[0] + Vector2i.DOWN, _packet("graze", 1.0, 6.0, 0.2))
	if _has_failure(): return false
	if not _expect(row.hp == 99.0 and row.pose == "hit" and row.ranged_cooldown == 2.0 and row.exchange_stagger == 0.25, "Original assertion at source line 116", 116): return false
	if not _expect(army.projectiles.size() == 1 and shot == frozen_shot, "Original assertion at source line 117", 117): return false
	army.prepare_combat(1.0)
	if _has_failure(): return false
	if not _expect(army.exchange_ready(0) and row.ranged_cooldown == 1.0, "Original assertion at source line 119", 119): return false
	var operation_120_1: bool = army.ranged_fire(0, selected[0] + Vector2i.RIGHT * 6, 2)
	if _has_failure(): return false
	if not _expect(not operation_120_1 and cargo.bolt == 2, "Finishing a reaction does not shorten the independent firing cadence", 120): return false
	army.prepare_combat(7.0)
	if _has_failure(): return false
	var operation_122_1: bool = army.activate_exchange_skill(0, "brace")
	if _has_failure(): return false
	if not _expect(operation_122_1, "Original assertion at source line 122", 122): return false
	var operation_123_1: bool = army.ranged_fire(0, selected[0] + Vector2i.RIGHT * 10, 2)
	if _has_failure(): return false
	if not _expect(operation_123_1, "Original assertion at source line 123", 123): return false
	if not _expect(cargo.arrow == 1 and cargo.bolt == 1 and army.projectiles.size() == 2, "Original assertion at source line 124", 124): return false
	if not _expect(row.exchange_skill == "brace" and row.ranged_cooldown == 3.0 and row.exchange_stagger == 0.4, "Original assertion at source line 125", 125): return false
	if not _expect(army.combat_frame(0).clip == "attack_crossbow", "Original assertion at source line 126", 126): return false
	army.ranged_apply_hit(0, selected[0] + Vector2i.DOWN, _packet("miss", 0.0, 0.0, 0.0))
	if _has_failure(): return false
	if not _expect(row.exchange_skill == "" and row.exchange_skill_cooldown == 8.0 and row.pose == "attack_crossbow", "Original assertion at source line 128", 128): return false
	if not _expect(row.hp == 99.0 and row.ranged_cooldown == 3.0 and row.exchange_stagger == 0.4, "Original assertion at source line 129", 129): return false
	# Isolate ordinary atlas recipe admission before this row ever rescues or is hit.
	# All original ammo/projectile expectations stay local to this paid shot.
	var ordinary: Dictionary = army.combat_units[1]
	ordinary.cargo.arrow = 1
	var ordinary_bow_created: Dictionary = _weapon(data, ordinary, "bow_01")
	if not _expect(bool(ordinary_bow_created.get("ok", false)), "Original ordinary weapon helper must complete", 0): return false
	ordinary.item_state.equipped.weapon = str(ordinary_bow_created.item_id)
	var recipe_source: Vector2i = army._combat_attack_cell(1)
	var recipe_target: Vector2i = army.cells[1] + Vector2i.RIGHT * 6
	var recipe_cells: Array[Vector2i] = SiteCombatRules.ranged_cells(recipe_source, recipe_target)
	var recipe_profile: Dictionary = army.ranged_profile(1)
	if not army.exchange_ready(1) or float(army.combat_hot_get(1, &"ranged_cooldown", 0.0)) > 0.000000001:
		push_error("FIRE_P0_RECIPE_PRECONDITION_NOT_READY: " + JSON.stringify({
			"pose": army.combat_hot_get(1, &"pose", ""), "stagger": army.combat_hot_get(1, &"exchange_stagger", 0.0),
			"cooldown": army.combat_hot_get(1, &"exchange_cooldown", 0.0), "reload": army.combat_hot_get(1, &"ranged_cooldown", 0.0)}))
		return false
	if army._uses_live_presenter(1) or recipe_profile.is_empty() or recipe_cells.is_empty():
		push_error("FIRE_P0_RECIPE_PRECONDITION_INVALID: ordinary atlas bow and a nonempty cell ray are required")
		return false
	if not SiteCombatRules.ranged_in_range(recipe_source, recipe_target, float(recipe_profile.range)) or not army._combat_ranged_line_clear(1, recipe_source, recipe_target):
		push_error("FIRE_P0_RECIPE_PRECONDITION_BLOCKED: fixture ray must pass the original range/LOS owners")
		return false
	var supported := army.supports_equipment_recipe(army.equipment_appearance(1))
	var count := army.projectiles.size()
	var fired := army.ranged_fire(1, army.cells[1] + Vector2i.RIGHT * 6, 3)
	if not _expect(fired == supported and ordinary.cargo.arrow == (0 if supported else 1), "Original assertion at source line 176", 176): return false
	if not _expect(army.projectiles.size() == count + int(supported), "Original assertion at source line 177", 177): return false
	if not supported:
		if not _expect("圖集" in str(ordinary.status), "Original assertion at source line 179", 179): return false
	if supported:
		# Finish the paid shot through the original timers/pose owner before rescue.
		army.prepare_combat(float(recipe_profile.cooldown))
		if _has_failure(): return false
		if not _expect(army.exchange_ready(1) and float(army.combat_hot_get(1, &"ranged_cooldown", 0.0)) <= 0.0,
			"Recipe-only shooter must naturally recover before the later rescue case", 0): return false
	# Other original rows cannot obtain immunity by helping, moving or already
	# recovering. Arrow hits do not push, reset melee cooldown or consume power.
	army.apply_unit_contact(2, {"result": {"hp": 0.0, "stun": 110.0, "guard_break": false}, "shield": false})
	if _has_failure(): return false
	var operation_133_1: bool = army.start_unit_rescue(1, 2)
	if _has_failure(): return false
	if not _expect(operation_133_1, "Original assertion at source line 133", 133): return false
	army.ranged_apply_hit(1, selected[1] + Vector2i.UP, _packet("hit", 2.0, 12.0, 0.35))
	if _has_failure(): return false
	if not _expect(army._unit_rescues.is_empty() and army.combat_units[1].hp == 98.0 and army.combat_units[2].ko > 0.0, "Original assertion at source line 135", 135): return false
	army._wake_unit(2)
	if _has_failure(): return false
	army.prepare_combat(0.4)
	if _has_failure(): return false
	var recovering_row: Dictionary = army.combat_units[2]
	var recovery_age := float(recovering_row.age)
	if not _expect(recovering_row.pose == "get_up" and not army.combat_can_act(2), "Original assertion at source line 140", 140): return false
	army.ranged_apply_hit(2, selected[2] + Vector2i.LEFT, _packet("graze", 1.0, 6.0, 0.2))
	if _has_failure(): return false
	if not _expect(recovering_row.hp == 99.0 and recovering_row.pose == "get_up" and recovering_row.age == recovery_age, "A non-KO arrow cannot replace or restart the original get-up animation", 142): return false
	if not _expect(not army.combat_can_act(2) and not army.exchange_ready(2), "Original assertion at source line 144", 144): return false
	army.prepare_combat(1.8)
	if _has_failure(): return false
	var moving_row: Dictionary = army.combat_units[2]
	var operation_147_1: bool = army._reserve_combat_step(2, selected[2] + Vector2i.UP)
	if _has_failure(): return false
	if not _expect(operation_147_1, "Original assertion at source line 147", 147): return false
	army.prepare_combat(0.05)
	if _has_failure(): return false
	moving_row.exchange_stagger = 0.7
	moving_row.exchange_cooldown = 0.8
	moving_row.exchange_skill = "power"
	army.ranged_apply_hit(2, selected[2] + Vector2i.LEFT, _packet("graze", 1.0, 6.0, 0.2))
	if _has_failure(): return false
	if not _expect(moving_row.hp == 98.0 and moving_row.exchange_stagger == 0.7 and moving_row.exchange_cooldown == 0.8, "Original assertion at source line 153", 153): return false
	if not _expect(moving_row.exchange_skill == "power" and army.moving_to[2] == selected[2] + Vector2i.UP, "Original assertion at source line 154", 154): return false
	if not _expect(army.ranged_defense(2).moving and not army.ranged_defense(2).shield
		and army.ranged_defense(2).armor == str(army.equipment_appearance(2).parts.armor), "Original assertion at source line 155", 155): return false
	var before_knockout := army.projectiles.duplicate(true)
	army.ranged_apply_hit(0, selected[0] + Vector2i.DOWN, _packet("hit", 2.0, 110.0, 0.35))
	if _has_failure(): return false
	if not _expect(row.ko > 0.0 and row.pose == "down" and army.projectiles == before_knockout, "Original assertion at source line 159", 159): return false
	var death_ids: Array[int] = []
	army.died.connect(func(identity: int) -> void: death_ids.append(identity))
	army.ranged_apply_hit(0, selected[0] + Vector2i.DOWN, _packet("hit", 100.0, 12.0, 0.35))
	if _has_failure(): return false
	if not _expect(row.hp == 0.0 and row.ko == 0.0 and row.pose == "down" and death_ids == [army.combat_identity(0)], "Original assertion at source line 163", 163): return false
	if not _expect(army.projectiles == before_knockout and cargo.arrow == 1 and cargo.bolt == 1, "Original assertion at source line 164", 164): return false
	var operation_165_1: bool = army.ranged_fire(0, selected[0] + Vector2i.RIGHT * 6, 3)
	if _has_failure(): return false
	if not _expect(not operation_165_1, "Original assertion at source line 165", 165): return false
	if not _expect(not army.capture_combat_state().has("projectiles"), "Flight events are transient; the Lab's combat/save guard owns active-flight refusal", 166): return false
	army.prepare_combat(1.0)
	if _has_failure(): return false
	if not _expect(geometry_calls == 0, "Original ranged owner must not query legacy target geometry", 180): return false
	if not _expect(is_same(TerrainArmy._contact_source, prepared_source), "Ranged operations must reuse the source prepared at admission", 181): return false
	if not _expect(int(prepared_source.query_profile.sample_calls) == prepared_sample_calls, "Original cell-ranged owner must not add exact geometry sampling after admission", 182): return false
	army.clear()
	if _has_failure(): return false
	if not _expect(army.projectiles.is_empty(), "Original assertion at source line 185", 185): return false
	army.free()
	if _has_failure(): return false
	TerrainArmy.release_contact_source()
	if _has_failure(): return false
	return not _has_failure()

func _finish_success() -> void:
	if _has_failure():
		_abort()
		return
	print("FIRE_P0_SITE_RANGED_ARMY_PASS: original equipment and ammo alias/conservation, blocked/empty/changed weapon, authored bow/crossbow, frozen released shot, power/brace cooldown, rescue/movement hit guards, original KO/death, no additional geometry queries/sampling after shared-source admission, explicit atlas admission")
	if _has_failure():
		_abort()
		return
	_stopped = true
	quit(0)
