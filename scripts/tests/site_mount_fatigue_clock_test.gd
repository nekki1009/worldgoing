extends "res://scripts/tests/site_movement_input_clock_test.gd"
## Original Lab game clock and Actor/Army owners, explicit legal flat fixture.

func _near(actual: float, expected: float, context: String) -> void:
	assert(absf(actual - expected) < 0.000001, "%s: %.12f != %.12f" % [context, actual, expected])

func _game_time() -> float:
	return (float(lab.terrain.site.minute) + float(lab.terrain.site.phase)) * 60.0

func _clock_matrix() -> void:
	await _fresh(false)
	_key(KEY_F, true)
	assert(lab.character.is_mounted())
	for running: bool in [false, true]:
		for combat: bool in [false, true]:
			for multiplier: float in [0.25, 1.0, 2.0]:
				var samples := {}
				for fps: int in [30, 60, 144]:
					lab._clear_movement_input()
					assert(lab.character.place(Vector2i(20, 20), true))
					lab.character.fatigue = 0.0 # Fresh-value fixture, not a gameplay reset.
					lab.character.fatigue_rest = 0.0
					lab.simulation_speed = multiplier
					lab.terrain.site.combat_left = 1000.0 if combat else 0.0
					var before := _game_time()
					if running: _key(KEY_SHIFT, true)
					_key(KEY_D, true)
					_advance(fps, 2)
					var seconds := SiteRuntime.game_seconds(2.0, 1000.0 if combat else 0.0) * multiplier
					var expected := seconds * (PersonFatigue.RUN_RATE if running else PersonFatigue.WORK_RATE)
					var label := "%s/%s/x%.2f/%dfps" % ["run" if running else "cruise", "combat" if combat else "peace", multiplier, fps]
					print("MOUNT_FATIGUE_CLOCK ", label, " value=", lab.character.fatigue, " expected=", expected, " game_seconds=", _game_time() - before)
					_near(lab.character.fatigue, expected, label)
					_near(_game_time() - before, seconds, "same Site clock " + label)
					_near(lab.character.fatigue_rest, 0.0, "moving is not resting " + label)
					assert(lab.character.terrain_cell.x > 20 and lab.character._movement_ride_running == running)
					samples[str(fps)] = _snapshot()
				for fps: int in [60, 144]:
					assert(_same(samples["30"], samples[str(fps)]), "Mounted fatigue must not introduce render-FPS movement differences")
	var threshold_samples := {}
	for fps: int in [30, 60, 144]:
		lab._clear_movement_input()
		assert(lab.character.place(Vector2i(20, 20), true))
		lab.character.fatigue = 29.0
		lab.character.fatigue_rest = 0.0
		lab.simulation_speed = 1.0
		lab.terrain.site.combat_left = 0.0
		_key(KEY_SHIFT, true)
		_key(KEY_D, true)
		_advance(fps, 2)
		_near(lab.character.fatigue, 41.0, "cross threshold through original movement")
		threshold_samples[str(fps)] = _snapshot()
		print("MOUNT_FATIGUE_CROSS_THRESHOLD ", fps, " value=", lab.character.fatigue, " ", threshold_samples[str(fps)])
	for fps: int in [60, 144]:
		assert(_same(threshold_samples["30"], threshold_samples[str(fps)]), "In-flight threshold crossing must remain FPS independent")
	# Both original pause boundaries freeze the unique state and reject held input.
	lab._clear_movement_input()
	lab.site_controller.toggle_pause()
	var value: float = lab.character.fatigue
	var rested: float = lab.character.fatigue_rest
	var now := _game_time()
	_key(KEY_D, true)
	lab._process(3.0)
	assert(lab.character.fatigue == value and lab.character.fatigue_rest == rested and _game_time() == now)
	assert(lab._held_directions.is_empty())
	lab.site_controller.toggle_pause()
	lab.terrain.site.paused = true
	lab._process(3.0)
	assert(lab.character.fatigue == value and lab.character.fatigue_rest == rested and _game_time() == now)
	lab.terrain.site.paused = false

func _owner_boundaries() -> void:
	await _fresh(false)
	_key(KEY_F, true)
	assert(lab.character.step(Vector2i.RIGHT))
	# Work already consumed this interval: riding must not add a second charge.
	lab.fatigue_work_minutes(true, 2.0 / 60.0)
	var human: float = lab.character.fatigue
	lab._advance_combat(TerrainLab.EXCHANGE_ACTION_STEP)
	_near(lab.character.fatigue, human, "handled rider must not be charged twice")
	await _fresh(false)
	var cells: Array[Vector2i] = [Vector2i(50, 50), Vector2i(51, 50)]
	lab.army.roster_size = cells.size()
	assert(lab.army.deploy_at(lab.terrain, lab.character, lab.npc, cells) and lab.army.enable_combat(false, 0))
	lab.npc.faction_id = lab.army.faction_id
	assert(lab.army.join_player(lab.npc).ok)
	var shared := lab.army.team_fatigue
	assert(is_same(lab.npc._fatigue_pool, shared) and shared.count == 3)
	shared.fatigue = 40.0
	assert(lab.npc.toggle_mount() and lab.npc.step(Vector2i.RIGHT))
	lab._advance_combat(TerrainLab.EXCHANGE_ACTION_STEP)
	_near(lab.npc.fatigue, 40.0 + 2.0 * PersonFatigue.WORK_RATE / 3.0, "pooled rider contributes once through the unique team path")
	assert(is_same(lab.npc._fatigue_pool, shared) and is_same(PersonFatigue.pool(lab.army.combat_units[0]), shared))
	assert(not shared.has("mount_fatigue") and not shared.has("mount_fatigue_rest"))
	for identity: int in [lab.npc.person_id, lab.army.combat_identity(0), lab.character.person_id]:
		lab.terrain.site.controlled_person_id = identity
		lab.army.sync_shared_fatigue(true)
		assert(is_same(lab.army.team_fatigue, shared) and is_same(lab.npc._fatigue_pool, shared) and shared.count == 3)
		for row: Dictionary in lab.army.combat_units: assert(is_same(PersonFatigue.pool(row), shared))
	# The same provider skip must work for the Actor borrowed into an Army too.
	lab.fatigue_work_minutes(false, 2.0 / 60.0)
	var after_work: float = lab.npc.fatigue
	lab._advance_combat(TerrainLab.EXCHANGE_ACTION_STEP)
	_near(lab.npc.fatigue, after_work, "pooled rider handled work interval is not charged again")
	lab._advance_combat(TerrainLab.EXCHANGE_ACTION_STEP * 2.0)
	_near(lab.npc.fatigue, after_work + 4.0 * PersonFatigue.WORK_RATE / 3.0, "later direct substeps cannot consume an already handled work interval again")
	after_work = lab.npc.fatigue
	PersonFatigue.charge(lab.army.combat_units[0], 3.0)
	_near(lab.npc.fatigue, after_work + 1.0, "row effort changes the same value read by the rider")
	lab.npc.advance_combat(lab.npc._movement_duration - lab.npc._movement_elapsed)
	var before_mount: float = lab.npc.fatigue
	lab.npc.toggle_mount()
	assert(not lab.npc.is_mounted())
	assert(lab.npc.toggle_mount() and lab.npc.is_mounted())
	_near(lab.npc.fatigue, before_mount, "F cycling retains borrowed team fatigue")
	assert(is_same(lab.npc._fatigue_pool, shared))
	for gate: String in ["knockout_left", "guard_transition_left", "guard_break_left", "exchange_stagger"]:
		shared.fatigue = 20.0
		shared.fatigue_rest = PersonFatigue.REST_DELAY
		shared.active = false
		lab.npc.set(gate, 0.5)
		lab._advance_fatigue(2.0)
		_near(float(shared.fatigue), 20.0, "pooled Actor blocks team rest during " + gate)
		_near(float(shared.fatigue_rest), 0.0, "pooled busy Actor resets rest qualification " + gate)
		lab.npc.set(gate, 0.0)
	shared.fatigue_rest = PersonFatigue.REST_DELAY
	lab._advance_fatigue(2.0)
	_near(float(shared.fatigue), 20.0 - 2.0 * PersonFatigue.RECOVERY_RATE, "three members and a mounted Actor recover only once")
	await _fresh(false)
	lab.site_controller.release_worker()
	assert(lab.npc.toggle_mount())
	var start: Vector2i = lab.npc.terrain_cell
	assert(lab.npc.issue_command(TerrainTestNPC.Command.MOVE_TO_CELL, start + Vector2i.RIGHT * 2))
	assert(not lab.npc.is_moving())
	lab._advance_action_time(TerrainLab.EXCHANGE_ACTION_STEP)
	assert(lab.npc.is_moving() and lab.npc.terrain_cell != start)
	_near(lab.npc.fatigue, 2.0 * PersonFatigue.WORK_RATE,
		"Autonomous original NPC navigation must charge the very first committed tick too")

func _rest_gate() -> void:
	await _fresh(false)
	var actor := lab.character
	actor.fatigue = 10.0
	actor.fatigue_rest = PersonFatigue.REST_DELAY
	# Dismounted, stationary, safe: original human recovery applies once.
	lab._advance_combat(TerrainLab.EXCHANGE_ACTION_STEP)
	_near(actor.fatigue, 10.0 - 2.0 * PersonFatigue.RECOVERY_RATE, "safe unique recovery")
	for gate: String in ["threat", "action_time", "guarding", "guard_transition_left", "guard_break_left", "_rescue_left", "knockout_left", "foot_move"]:
		actor.fatigue_rest = PersonFatigue.REST_DELAY
		var before: float = actor.fatigue
		if gate == "threat":
			lab.npc_allied_toggle.button_pressed = false
			assert(lab.npc.faction_id != actor.faction_id)
			assert(lab.npc.place(actor.terrain_cell + Vector2i.RIGHT * 4, true))
		elif gate == "foot_move": assert(actor.step(Vector2i.DOWN))
		elif gate == "guarding": actor.guarding = true
		else: actor.set(gate, 0.5)
		# Direct original fatigue boundary keeps each explicit gate unchanged;
		# timing/multipliers are covered through the full Lab clock above.
		lab._advance_fatigue(2.0)
		_near(actor.fatigue, before, "unsafe recovery gate " + gate)
		_near(actor.fatigue_rest, 0.0, "unsafe rest continuity reset " + gate)
		if gate == "threat":
			assert(lab.npc.place(Vector2i(85, 85), true))
			lab.npc_allied_toggle.button_pressed = true
		elif gate == "guarding": actor.guarding = false
		elif gate != "foot_move": actor.set(gate, 0.0)
	# An explicit Site with no actor snapshots creates fresh test people, like
	# the pre-existing human reset. This is not a move/F/reset-combat shortcut.
	assert(lab.terrain.site.get("actors", {}).is_empty())
	lab.npc.fatigue = 25.0
	lab.npc.fatigue_rest = 12.0
	lab.bind_terrain(lab.terrain)
	for fresh_actor: TerrainTestCharacter in lab.combat_actors:
		assert(fresh_actor.fatigue == 0.0 and fresh_actor.fatigue_rest == 0.0)

func _run() -> void:
	deadline = Time.get_ticks_msec() + 30000
	await _clock_matrix()
	await _owner_boundaries()
	await _rest_gate()
	lab.queue_free()
	await process_frame
	print("SITE MOUNT FATIGUE CLOCK PASS: 36 original clock/FPS cruise-run cases plus 3 threshold crossings, both pauses, no double charge, controlled Actor/row same team alias, original rest gates, fresh-people bind")
	quit(0)
