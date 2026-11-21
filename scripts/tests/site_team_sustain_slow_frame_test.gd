extends SceneTree
## One real Lab replayed through its normal _process -> Site/common action clock.
## This isolates institutions, not enemy AI, weapon contact, GPU or a long soak.

const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const TrainingFixture = preload("res://scripts/tests/site_training_ground_fixture.gd")
const START_SECONDS := 21570.0
const ELAPSED_SECONDS := 90.0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String = "Original fixture contract failed") -> bool:
	if not condition:
		push_error("SITE TEAM SUSTAIN SLOW FRAME: " + message)
		quit(1)
	return condition

func _near(actual: float, expected: float, label: String) -> bool:
	return _check(absf(actual - expected) < 0.000001, "%s: %.12f != %.12f" % [label, actual, expected])

func _same(first: Variant, second: Variant, path: String = "state") -> bool:
	if first is float or second is float:
		if not _check((first is int or first is float) and (second is int or second is float), path + " numeric type"): return false
		return _near(float(first), float(second), path)
	elif first is Dictionary:
		if not _check(second is Dictionary and first.size() == second.size(), path + " dictionary size"): return false
		for key: Variant in first:
			if not _check(second.has(key), path + " missing " + str(key)): return false
			if not _same(first[key], second[key], path + "/" + str(key)): return false
	elif first is Array:
		if not _check(second is Array and first.size() == second.size(), path + " array size"): return false
		for index: int in first.size():
			if not _same(first[index], second[index], path + "/" + str(index)): return false
	else:
		# Integer identity/RNG values stay exact; never cast int64 RNG to a float.
		return _check(first == second, path + ": " + str(first) + " != " + str(second))
	return true

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
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	if is_instance_valid(lab.npc):
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
	if not _check(lab.character.place(Vector2i(15, 15), true)): return
	if is_instance_valid(lab.npc):
		if not _check(lab.npc.place(Vector2i(16, 15), true)): return
		lab.npc.faction_id = lab.character.faction_id
	lab.character.fatigue = 35.0
	if is_instance_valid(lab.npc):
		lab.npc.fatigue = 40.0
	var total_deployed := 0
	for army_index: int in lab.combat_armies.size():
		var team: TerrainArmy = lab.combat_armies[army_index]
		team.team_id = army_index + 1
		team.faction_id = lab.character.faction_id
		var cells: Array[Vector2i] = []
		var origin := Vector2i(20 + army_index * 20, 20)
		TrainingFixture.build(data, origin - Vector2i.ONE, Vector2i(12, 12), team.faction_id)
		for index: int in 100:
			cells.append(origin + Vector2i(index % 10, floori(float(index) / 10.0)))
		if not _check(team.deploy_at(data, lab.character, lab.npc, cells)): return
		if not _check(team.enable_combat(false)): return
		total_deployed += team.combat_units.size()
		team.set_process(false)
		team.settle_combat_command()
		# Stopping an absent training order no longer enables food implicitly.
		# Explicitly set up this fixture's original three feeding owners first.
		if not _check(not controller._enable_team_supply(team).is_empty()): return
		if army_index == 1:
			# The non-training cohort stops an actual order from the same officer;
			# this setup advances no clock and grants no training or food credit.
			var started: Dictionary = controller.order_team_training(team, team.current_commander, true)
			if not _check(started.ok, str({"army_index": army_index, "start": started})): return
		var ordered: Dictionary = controller.order_team_training(team, team.current_commander, army_index != 1)
		if not _check(ordered.ok, str({"army_index": army_index, "order": ordered})): return
		team.training = 5.0 if army_index == 1 else 12.0
		if not _check(not team.team_fatigue.is_empty(), "Training fixture must use the original shared Army fatigue owner"): return
		# The third team reaches 80 within the action step ending at game second
		# 36, then rests for 54 seconds (30 delay + 24 actual recovery).
		PersonFatigue.write(team.combat_units[0], "fatigue", PersonFatigue.WORK_REST_AT - 35.0 * PersonFatigue.WORK_RATE if army_index == 2 else 10.0)
		PersonFatigue.write(team.combat_units[0], "fatigue_rest", 0.0)
		for unit: Dictionary in team.combat_units:
			if not _check(is_same(PersonFatigue.pool(unit), team.team_fatigue), "Every original member borrows the same team fatigue"): return
			unit.work_resting = false
		var entry: Dictionary = controller._supply_entry(team)
		entry.inventory.grain = 25 if army_index == 1 else 60
		if not _check(entry.sustain.cohorts.size() == 1): return
		var cohort: Dictionary = entry.sustain.cohorts[0]
		# The initial fixture includes a real prior meal credit. It is not held
		# stock; the next period must be bought once at the shared six-hour edge.
		cohort.meal_until = 21600.0
		cohort.coverage = 0.5 if army_index == 1 else 1.0
		cohort.hunger = 48.02 if army_index == 1 else 0.0
		if not _check(Sustain.validate(entry.sustain, controller._team_members(team))): return
	data.site.army_next_team = lab.combat_armies.size() + 1
	lab.opposing_army.combat_hot_set(99, &"hp", 0.002)
	if not _check(lab.character._fatigue_pool.is_empty(), "The unaffiliated player retains independent fatigue"): return
	if not _check(lab.army.combat_units.size() + lab.opposing_army.combat_units.size() == 200): return
	if not _check(lab.army.faction_id == lab.opposing_army.faction_id): return
	var initial := _capture(lab)
	var original_ids: Array[int] = []
	for snapshot: Dictionary in initial.armies:
		if not _check(TerrainArmy.valid_combat_state(snapshot, data), "Keep the existing army save contract"): return
		original_ids.append_array(TerrainArmy.snapshot_person_ids(snapshot))
	if not _check(TerrainArmy.valid_person_ids(original_ids, total_deployed)): return
	var initial_site: Dictionary = data.site.duplicate(true)
	# Both independent pause mechanisms must freeze the real common clock,
	# original bodies and meal inventory, not merely a copied formula fixture.
	data.site.paused = true
	lab._process(0.5)
	if not _same(initial, _capture(lab), "site pause"): return
	data.site.paused = false
	paused = true
	lab._process(0.5)
	if not _same(initial, _capture(lab), "tree pause"): return
	paused = false
	for tick: int in 180:
		lab._process(1.0 / 120.0)
	var normal := _capture(lab)
	if not _near(Runtime.now(data) * 60.0, START_SECONDS + ELAPSED_SECONDS, "actual Site elapsed game time"): return
	if not _near(PersonFatigue.read(lab.army.combat_units[2]), 10.0 + ELAPSED_SECONDS * PersonFatigue.WORK_RATE, "training charged exactly once to the whole team; no concurrent recovery"): return
	if not _near(PersonFatigue.read(lab.army.combat_units[2], "fatigue_rest"), 0.0, "trainee team is not also resting"): return
	for unit: Dictionary in lab.third_army.combat_units:
		if not _near(PersonFatigue.read(unit), 80.0 - 24.0 * PersonFatigue.RECOVERY_RATE, "shared 80 stop, 30-second delay, then exactly 24 seconds safe recovery"): return
		if not _check(unit.work_resting, "The whole training team remains on its original 80-to-50 rest cycle"): return
	if not _near(lab.character.fatigue, 35.0 - 60.0 * PersonFatigue.RECOVERY_RATE, "independent original player recovers only after delay"): return
	if not _check(lab.army.training > 12.0 and lab.third_army.training > 12.0 and lab.opposing_army.training == 5.0): return
	if not _check(float(lab.opposing_army.combat_hot_get(99, &"hp")) == 0.0 and str(lab.opposing_army.combat_hot_get(99, &"pose")) == "down", "hunger death uses original hot life state"): return
	if not _near(float(data.site.combat_left), 0.0, "hunger never manufactures combat time"): return
	var fed: Dictionary = controller._supply_entry(lab.army)
	var hungry: Dictionary = controller._supply_entry(lab.opposing_army)
	if not _near(Sustain.rations(fed.sustain, fed.inventory), 35.0, "100 living people buy exactly 25 day-rations"): return
	if not _near(Sustain.rations(hungry.sustain, hungry.inventory), 0.25, "99 living people buy24.75; dead person receives no new meal"): return
	if not _near(float(hungry.sustain.cohorts[0].coverage), 1.0, "refill ends shortage for current interval"): return
	# Restore the same original owners through their existing snapshot APIs.
	# Keep one Lab and existing assets/query source; no second simulation scene.
	data.site = initial_site.duplicate(true)
	Env.rebuild_indexes(data)
	Runtime.rebuild_water(data)
	lab.character.restore_state(initial.actors.player)
	if is_instance_valid(lab.npc):
		lab.npc.restore_state(initial.actors.npc)
	for army_index: int in lab.combat_armies.size():
		lab.combat_armies[army_index].restore_combat_state(initial.armies[army_index], data, lab.character, lab.npc)
	lab._fatigue_work_seconds.clear()
	controller._supply_rout_review.clear()
	controller.bind()
	if not _same(initial, _capture(lab), "restored original owners"): return
	for tick: int in 3:
		lab._process(0.5)
	var slow := _capture(lab)
	if not _same(normal, slow, "180 normal vs 3 slow frames"): return
	for team: TerrainArmy in lab.combat_armies:
		if not _check(team.combat_order == TerrainArmy.CombatOrder.HOLD and not team.combat_attacking): return
		for index in range(team.combat_units.size()):
			if not _check(not bool(team.combat_hot_get(index, &"attack")) and team.combat_units[index].hits.is_empty(), "No contact may contaminate institution comparison"): return
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE TEAM SUSTAIN SLOW FRAME PASS: one real Lab / %d original NPC rows, 180 normal vs3 slow frames,90 game seconds across meal boundary, training fatigue once/80-rest, hunger death/no combat, exact stock/history and both pauses; not GPU/long-duration performance" % total_deployed)
	quit(0)
