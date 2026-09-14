extends SceneTree
## One real Lab replayed through its normal _process -> Site/common action clock.
## This isolates institutions, not enemy AI, weapon contact, GPU or a long soak.

const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const START_SECONDS := 21570.0
const ELAPSED_SECONDS := 90.0

func _initialize() -> void:
	call_deferred("_run")

func _near(actual: float, expected: float, label: String) -> void:
	assert(absf(actual - expected) < 0.000001, "%s: %.12f != %.12f" % [label, actual, expected])

func _same(first: Variant, second: Variant, path: String = "state") -> void:
	if first is float or second is float:
		assert((first is int or first is float) and (second is int or second is float), path + " numeric type")
		_near(float(first), float(second), path)
	elif first is Dictionary:
		assert(second is Dictionary and first.size() == second.size(), path + " dictionary size")
		for key: Variant in first:
			assert(second.has(key), path + " missing " + str(key))
			_same(first[key], second[key], path + "/" + str(key))
	elif first is Array:
		assert(second is Array and first.size() == second.size(), path + " array size")
		for index: int in first.size():
			_same(first[index], second[index], path + "/" + str(index))
	else:
		# Integer identity/RNG values stay exact; never cast int64 RNG to a float.
		assert(first == second, path + ": " + str(first) + " != " + str(second))

func _capture(lab: TerrainLab) -> Dictionary:
	var controller: SiteController = lab.site_controller
	controller._capture_positions()
	var armies: Array[Dictionary] = []
	for team: TerrainArmy in lab.combat_armies:
		armies.append(team.capture_combat_state())
	return {"armies": armies, "actors": lab.terrain.site.actors.duplicate(true),
		"supply": lab.terrain.site.team_supply.duplicate(true),
		"minute": lab.terrain.site.minute, "phase": lab.terrain.site.phase,
		"combat_left": lab.terrain.site.combat_left,
		"inventory": lab.terrain.site.inventory.duplicate(true),
		"manual": lab.terrain.site.manual.duplicate(true),
		"worker": lab.terrain.site.worker.duplicate(true),
		"total_produced": lab.terrain.site.total_produced}

func _run() -> void:
	create_timer(18.0).timeout.connect(func() -> void:
		push_error("SITE TEAM SUSTAIN SLOW FRAME exceeded its bounded fixture time")
		quit(1))
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.npc_retaliates = false
	var controller: SiteController = lab.site_controller
	controller._auto_save_blocked = true
	var data := TerrainGenerator.generate(0, 581)
	Env.initialize(data, "team-sustain-slow-fixture")
	# Controlled flat Site; remove generated obstacles through their existing
	# sparse resource owner so minute-boundary index rebuilds remain identical.
	for key: String in data.resource_base:
		Env.change(data, key, {"cleared": true, "remaining": 0})
	Env.rebuild_indexes(data)
	for index: int in data.surface_types.size():
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
		data.surface_types[index] = TerrainData.Surface.GRASS
	data.ramp_edges.fill(0)
	data.site.minute = 359
	data.site.phase = 0.5
	data.site.worker_enabled = false
	data.site.combat_left = 0.0
	lab.bind_terrain(data)
	assert(lab.character.place(Vector2i(15, 15), true))
	assert(lab.npc.place(Vector2i(16, 15), true))
	lab.npc.faction_id = lab.character.faction_id
	lab.character.fatigue = 35.0
	lab.npc.fatigue = 40.0
	for army_index: int in lab.combat_armies.size():
		var team: TerrainArmy = lab.combat_armies[army_index]
		team.team_id = army_index + 1
		team.faction_id = lab.character.faction_id
		var cells: Array[Vector2i] = []
		var origin := Vector2i(20 + army_index * 20, 20)
		for index: int in 100:
			cells.append(origin + Vector2i(index % 10, floori(float(index) / 10.0)))
		assert(team.deploy_at(data, lab.character, lab.npc, cells))
		assert(team.enable_combat(false))
		team.set_process(false)
		team.settle_combat_command()
		assert(controller.order_team_training(team, team.current_commander, army_index == 0).ok)
		team.training = 12.0 if army_index == 0 else 5.0
		for unit: Dictionary in team.combat_units:
			unit.fatigue = 10.0
			unit.fatigue_rest = 0.0
			unit.work_resting = false
		var entry: Dictionary = controller._supply_entry(team)
		entry.inventory.grain = 60 if army_index == 0 else 25
		assert(entry.sustain.cohorts.size() == 1)
		var cohort: Dictionary = entry.sustain.cohorts[0]
		# The initial fixture includes a real prior meal credit. It is not held
		# stock; the next period must be bought once at the shared six-hour edge.
		cohort.meal_until = 21600.0
		cohort.coverage = 1.0 if army_index == 0 else 0.5
		cohort.hunger = 0.0 if army_index == 0 else 48.02
		assert(Sustain.validate(entry.sustain, controller._team_members(team)))
	data.site.army_next_team = 3
	lab.army.combat_units[1].fatigue = 79.9
	lab.opposing_army.combat_units[99].hp = 0.002
	assert(lab.army.combat_units.size() + lab.opposing_army.combat_units.size() == 200)
	assert(lab.army.faction_id == lab.opposing_army.faction_id)
	var initial := _capture(lab)
	var original_ids: Array[int] = []
	for snapshot: Dictionary in initial.armies:
		assert(TerrainArmy.valid_combat_state(snapshot, data), "Keep the existing two-army save contract")
		original_ids.append_array(TerrainArmy.snapshot_person_ids(snapshot))
	assert(TerrainArmy.valid_person_ids(original_ids, 200))
	var initial_site: Dictionary = data.site.duplicate(true)
	# Both independent pause mechanisms must freeze the real common clock,
	# original bodies and meal inventory, not merely a copied formula fixture.
	data.site.paused = true
	lab._process(0.5)
	_same(initial, _capture(lab), "site pause")
	data.site.paused = false
	paused = true
	lab._process(0.5)
	_same(initial, _capture(lab), "tree pause")
	paused = false
	for tick: int in 180:
		lab._process(1.0 / 120.0)
	var normal := _capture(lab)
	_near(Runtime.now(data) * 60.0, START_SECONDS + ELAPSED_SECONDS, "actual Site elapsed game time")
	_near(float(lab.army.combat_units[2].fatigue), 10.0 + ELAPSED_SECONDS * PersonFatigue.WORK_RATE, "training charged exactly once; no concurrent recovery")
	_near(float(lab.army.combat_units[2].fatigue_rest), 0.0, "trainee is not also resting")
	_near(float(lab.army.combat_units[1].fatigue), 80.0 - 24.0 * PersonFatigue.RECOVERY_RATE, "80 stop, 30-second delay, then actual safe recovery")
	assert(lab.army.combat_units[1].work_resting)
	_near(lab.character.fatigue, 35.0 - 60.0 * PersonFatigue.RECOVERY_RATE, "independent original player recovers only after delay")
	assert(lab.army.training > 12.0 and lab.opposing_army.training == 5.0)
	assert(lab.opposing_army.combat_units[99].hp == 0.0 and lab.opposing_army.combat_units[99].pose == "down", "hunger death uses original row life state")
	_near(float(data.site.combat_left), 0.0, "hunger never manufactures combat time")
	var fed: Dictionary = controller._supply_entry(lab.army)
	var hungry: Dictionary = controller._supply_entry(lab.opposing_army)
	_near(Sustain.rations(fed.sustain, fed.inventory), 35.0, "100 living people buy exactly 25 day-rations")
	_near(Sustain.rations(hungry.sustain, hungry.inventory), 0.25, "99 living people buy24.75; dead person receives no new meal")
	_near(float(hungry.sustain.cohorts[0].coverage), 1.0, "refill ends shortage for current interval")
	# Restore the same original owners through their existing snapshot APIs.
	# Keep one Lab and existing assets/query source; no second simulation scene.
	data.site = initial_site.duplicate(true)
	Env.rebuild_indexes(data)
	Runtime.rebuild_water(data)
	lab.character.restore_state(initial.actors.player)
	lab.npc.restore_state(initial.actors.npc)
	for army_index: int in 2:
		lab.combat_armies[army_index].restore_combat_state(initial.armies[army_index], data, lab.character, lab.npc)
	lab._fatigue_work_seconds.clear()
	controller._supply_rout_review.clear()
	controller.bind()
	_same(initial, _capture(lab), "restored original owners")
	for tick: int in 3:
		lab._process(0.5)
	var slow := _capture(lab)
	_same(normal, slow, "180 normal vs 3 slow frames")
	for team: TerrainArmy in lab.combat_armies:
		assert(team.combat_order == TerrainArmy.CombatOrder.HOLD and not team.combat_attacking)
		for unit: Dictionary in team.combat_units:
			assert(not unit.attack and unit.hits.is_empty(), "No contact may contaminate institution comparison")
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE TEAM SUSTAIN SLOW FRAME PASS: one real Lab / 200 original NPC rows, 180 normal vs3 slow frames,90 game seconds across meal boundary, training fatigue once/80-rest, hunger death/no combat, exact stock/history and both pauses; not GPU/long-duration performance")
	quit(0)
