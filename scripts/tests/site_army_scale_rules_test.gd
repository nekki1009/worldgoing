extends SceneTree
## Original V0.41R pairing/threat functions versus the optimized real owners.
const Reference = preload("res://scripts/tests/fixtures/site_army_scale_reference_v041r.gd")
const ArmyReference = preload("res://scripts/tests/fixtures/site_army_encirclement_reference_v041r.gd")
const ScaleClockReference = preload("res://scripts/tests/fixtures/site_army_scale_game_clock_reference.gd")

func _initialize() -> void:
	_run.call_deferred()

func _fixture(reference: bool, per_team: int = 100, maneuver: bool = false, army_type: GDScript = null, lab_type: GDScript = null, in_tree: bool = false) -> TerrainLab:
	var lab: TerrainLab = lab_type.new() if lab_type != null else (Reference.new() if reference else TerrainLab.new())
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581)
	SiteEnvironment.initialize(data, "scale-rules")
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	lab.terrain = data
	for side in range(2):
		var team: TerrainArmy = army_type.new() if army_type != null else (ArmyReference.new() if reference else TerrainArmy.new())
		team.team_id = side + 1
		team.faction_id = side
		team.exchange_enabled = true
		team.shared_fatigue_enabled = false # Frozen V0.41R arithmetic parity; new team policy has separate tests.
		team.roster_size = per_team
		if in_tree:
			# Like TerrainLab's dynamic team slots (_ensure_army_slots), the captain uses the
			# shared pooled geometry; live presenters build their UI in _ready, so the army
			# joins the tree before it deploys. READY re-enables an overridden _process.
			team.defer_captain_presenter = true
			root.add_child(team)
			team.set_process(false)
		var cells: Array[Vector2i] = []
		for i in range(per_team):
			cells.append(Vector2i(49 - floori(float(i) / 98.0) if side == 0 else 50 + floori(float(i) / 98.0), 1 + i % 98) if maneuver else Vector2i(40 + side * 10 + i % 10, 40 + floori(float(i) / 10.0)))
		assert(team.deploy_at(data, null, null, cells) and team.enable_combat())
		team.controlled_person_query = lab.controlled_person_id
		lab.combat_armies.append(team)
		for i in range(per_team):
			team.combat_units[i].combat_ability = TerrainArmy.TROOP_COMBAT_ABILITY
			team.combat_units[i].fatigue = float(i % 3) * 20.0
			team.combat_units[i].stun = 80.0 if i % 13 == 0 else 0.0
			team.combat_units[i].hp = 1.0 if i % 17 == 0 else 100.0
	# Opposing bodies behind a wall may prevent rest, but cannot exchange.
	data.static_blocked[data.index(Vector2i(50, 45))] = 1
	if maneuver:
		for side in range(2):
			lab.combat_armies[side].external_blocker = lab.combat_armies[1 - side].blocks_cell
			lab.combat_armies[side].exchange_people_query = lab._exchange_people.bind(false)
	return lab

func _state(lab: TerrainLab) -> Array:
	var state: Array = [lab._exchange_round, lab._exchange_phase, lab.exchange_count, lab.exchange_results.duplicate(), lab.ranged_shots]
	for team: TerrainArmy in lab.combat_armies:
		state.append([team.cells.duplicate(), team.moving_to.duplicate(), team.move_progress.duplicate(), team.combat_units.duplicate(true), team.command_abilities.duplicate(true)])
	return state

func _dispose(lab: TerrainLab) -> void:
	for team: TerrainArmy in lab.combat_armies:
		team.external_blocker = Callable()
		team.exchange_people_query = Callable()
		team.free()
	lab.free()

func _check_ko_clock_contract(in_tree: bool) -> bool:
	assert(SiteCombatRules.KNOCKOUT_GAME_SECONDS == 14400.0 and SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS == 3600.0)
	var reference: TerrainLab = _fixture(true, 1, false, ScaleClockReference, null, in_tree)
	var candidate: TerrainLab = _fixture(false, 1, false, null, null, in_tree)
	# Independent clock examples from the documented 60:1 peace / 1:1 combat contract.
	var action: float = 1.0 / 30.0
	var cases: Array[Dictionary] = [
		{"combat": 0.0, "speed": 1.0, "initial": 14400.0, "game": 2.0, "expected": 14398.0},
		{"combat": 1.0, "speed": 1.0, "initial": 14400.0, "game": action, "expected": 14400.0 - action},
		{"combat": 1.0 / 60.0, "speed": 2.0, "initial": 14400.0, "game": (1.0 / 60.0 + 1.0) * 2.0, "expected": 14400.0 - (1.0 / 60.0 + 1.0) * 2.0},
		{"combat": 0.0, "speed": 2.0, "initial": 14400.0, "game": 4.0, "expected": 14396.0},
		{"combat": 0.0, "speed": 1.0, "initial": 1.0, "game": 2.0, "expected": 0.0}]
	for sample: Dictionary in cases:
		assert(SiteRuntime.game_seconds(action, float(sample.combat)) * float(sample.speed) == float(sample.game))
		for lab: TerrainLab in [reference, candidate]:
			lab.simulation_speed = float(sample.speed)
			for team: TerrainArmy in lab.combat_armies:
				team.combat_hot_set(0, &"hp", 100.0)
				team.combat_hot_set(0, &"stun", 0.0)
				team.combat_hot_set(0, &"ko", 0.0)
				team.apply_unit_contact(0, {"shield": false, "result": {"hp": 0.0, "stun": 110.0, "guard_break": false}})
				assert(float(team.combat_hot_get(0, &"ko")) == 14400.0, "Original contact creates four game hours")
				team.combat_hot_set(0, &"ko", float(sample.initial)) # Explicit initial remaining-time boundary input.
				team.combat_hot_set(0, &"exchange_cooldown", 0.75)
			lab._advance_combat(action, float(sample.combat))
			for team: TerrainArmy in lab.combat_armies:
				assert(float(team.combat_hot_get(0, &"ko")) == float(sample.expected), "KO must match the independent game-clock expected value")
				assert(float(team.combat_hot_get(0, &"exchange_cooldown")) == 0.75 - action, "Combat cooldown remains in action seconds")
				if float(sample.expected) > 0.0:
					assert(float(team.combat_hot_get(0, &"age")) == action)
				else:
					assert(str(team.combat_hot_get(0, &"pose")) == "get_up" and float(team.combat_hot_get(0, &"age")) == 0.0)
	for lab: TerrainLab in [reference, candidate]:
		for team: TerrainArmy in lab.combat_armies:
			team.combat_hot_set(0, &"ko", 10.0)
			team.combat_hot_set(0, &"age", 0.0)
			team.prepare_combat(action) # Original direct-call fallback is still 1:1.
			assert(float(team.combat_hot_get(0, &"ko")) == 10.0 - action)
		lab.terrain.site.paused = true
		var stopped: PackedByteArray = var_to_bytes(_state(lab))
		lab._advance_combat(action, 0.0)
		assert(var_to_bytes(_state(lab)) == stopped, "Site pause freezes the full original combat state")
	_dispose(reference); _dispose(candidate)
	return true

func _run() -> void:
	var in_tree: bool = DisplayServer.get_name() != "headless"
	if not _check_ko_clock_contract(in_tree): TerrainArmy.release_contact_source(); quit(1); return
	var original: TerrainLab = _fixture(true, 100, false, ScaleClockReference, null, in_tree)
	var candidate: TerrainLab = _fixture(false, 100, false, null, null, in_tree)
	candidate.combat_armies[0].combat_units[0].combat_ability = 100.0
	assert(candidate.combat_armies[0].exchange_stats(0).ability == TerrainArmy.TROOP_COMBAT_ABILITY,
		"A legacy per-row value cannot override the single troop-type base")
	candidate.combat_armies[0].combat_units[0].combat_ability = TerrainArmy.TROOP_COMBAT_ABILITY
	for step in range(360):
		var step_clock: Dictionary = {"action_delta": 1.0 / 30.0, "reference_combat_left": original.terrain.site.get("combat_left", 0.0), "candidate_combat_left": candidate.terrain.site.get("combat_left", 0.0), "reference_speed": original.simulation_speed, "candidate_speed": candidate.simulation_speed}
		original._advance_combat(1.0 / 30.0)
		candidate._advance_combat(1.0 / 30.0)
		if var_to_bytes(_state(original)) != var_to_bytes(_state(candidate)):
			for side in range(2):
				for i in range(100):
					var before: Dictionary = original.combat_armies[side].combat_units[i]
					var after: Dictionary = candidate.combat_armies[side].combat_units[i]
					if var_to_bytes(before) != var_to_bytes(after):
						print("First changed row ", side, ":", i, " before=", before, " after=", after)
						var changed_fields: Array[String] = []
						for field: Variant in before:
							if before[field] != after.get(field): changed_fields.append(str(field))
						print("SCALE_FIRST_ROW_DIAG ", {"side": side, "row": i, "fields": changed_fields, "clock_before": step_clock, "reference_ko": before.get("ko"), "candidate_ko": after.get("ko")})
						break
			push_error("Scale optimization changed original gameplay at 30 Hz step %d" % step)
			_dispose(original); _dispose(candidate); TerrainArmy.release_contact_source(); quit(1); return
	var queries := 0
	for faction in range(3):
		var before := {}
		var after := {}
		for y in range(30, 61):
			for x in range(30, 71):
				var cell := Vector2i(x, y)
				if original._fatigue_threat(cell, faction, original.combat_armies[0], 0, before) != candidate._fatigue_threat(cell, faction, candidate.combat_armies[0], 0, after):
					push_error("Scale optimization changed rest threat at %s" % cell)
					_dispose(original); _dispose(candidate); TerrainArmy.release_contact_source(); quit(1); return
				queries += 1
	print("SCALE_RULES_PASS original V0.41R exact state, 200 people, 360 common steps, exchanges=", candidate.exchange_count, "; rest queries=", queries)
	_dispose(original)
	_dispose(candidate)
	TerrainArmy.release_contact_source()
	quit(0)
