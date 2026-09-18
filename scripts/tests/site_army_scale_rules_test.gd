extends SceneTree
## Original V0.41R pairing/threat functions versus the optimized real owners.
const Reference = preload("res://scripts/tests/fixtures/site_army_scale_reference_v041r.gd")
const ArmyReference = preload("res://scripts/tests/fixtures/site_army_encirclement_reference_v041r.gd")

func _initialize() -> void:
	_run.call_deferred()

func _fixture(reference: bool, per_team: int = 100, maneuver: bool = false, army_type: GDScript = null, lab_type: GDScript = null) -> TerrainLab:
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

func _run() -> void:
	var original := _fixture(true)
	var candidate := _fixture(false)
	candidate.combat_armies[0].combat_units[0].combat_ability = 100.0
	assert(candidate.combat_armies[0].exchange_stats(0).ability == TerrainArmy.TROOP_COMBAT_ABILITY,
		"A legacy per-row value cannot override the single troop-type base")
	candidate.combat_armies[0].combat_units[0].combat_ability = TerrainArmy.TROOP_COMBAT_ABILITY
	for step in range(360):
		original._advance_combat(1.0 / 30.0)
		candidate._advance_combat(1.0 / 30.0)
		if var_to_bytes(_state(original)) != var_to_bytes(_state(candidate)):
			for side in range(2):
				for i in range(100):
					var before: Dictionary = original.combat_armies[side].combat_units[i]
					var after: Dictionary = candidate.combat_armies[side].combat_units[i]
					if var_to_bytes(before) != var_to_bytes(after):
						print("First changed row ", side, ":", i, " before=", before, " after=", after)
						break
			push_error("Scale optimization changed original gameplay at 30 Hz step %d" % step)
			_dispose(original); _dispose(candidate); quit(1); return
	var queries := 0
	for faction in range(3):
		var before := {}
		var after := {}
		for y in range(30, 61):
			for x in range(30, 71):
				var cell := Vector2i(x, y)
				if original._fatigue_threat(cell, faction, original.combat_armies[0], 0, before) != candidate._fatigue_threat(cell, faction, candidate.combat_armies[0], 0, after):
					push_error("Scale optimization changed rest threat at %s" % cell)
					_dispose(original); _dispose(candidate); quit(1); return
				queries += 1
	print("SCALE_RULES_PASS original V0.41R exact state, 200 people, 360 common steps, exchanges=", candidate.exchange_count, "; rest queries=", queries)
	_dispose(original)
	_dispose(candidate)
	quit(0)
