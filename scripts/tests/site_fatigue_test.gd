extends SceneTree

const Timings = preload("res://scripts/terrain_lab/character_combat_timings.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const SAVE := "res://.godot-temp/site_combat/fatigue.json"

func _initialize() -> void:
	run.call_deferred()

func near(actual: float, expected: float, label: String = "") -> void:
	assert(absf(actual - expected) < 0.000001, "%s: %.12f != %.12f" % [label, actual, expected])

func run() -> void:
	create_timer(18.0).timeout.connect(func() -> void: quit(1))
	for value: float in [0.0, 30.0, 65.0, 100.0]:
		near(PersonFatigue.slowdown(value), {0.0: 0.0, 30.0: 0.0, 65.0: 0.15, 100.0: 0.30}[value])
		for duration: float in [0.0, 1.0, 600.0, 30000.0]:
			var current := value
			var productive := 0.0
			for part in range(100):
				productive += PersonFatigue.work_seconds(current, duration / 100.0)
				current = PersonFatigue.advance(current, 0.0, duration / 100.0, PersonFatigue.WORK_RATE, false)[0]
			near(productive, PersonFatigue.work_seconds(value, duration), "partitioned work")
			near(current, minf(100.0, value + duration * PersonFatigue.WORK_RATE))
	near(PersonFatigue.work_seconds(100.0, 130.0), 100.0)
	near(PersonFatigue.advance(90, 0, 1000, PersonFatigue.ATTACK_RATE, false)[0], 100)
	near(PersonFatigue.advance(50, 0, 30, 0, true)[0], 50)
	near(PersonFatigue.advance(50, 0, 3630, 0, true)[0], 30)
	near(PersonFatigue.advance(50, 29, 10, 0, false)[1], 0)
	near(PersonFatigue.advance(0.01, 30, 60, 0, true)[0], 0)
	near(SiteRuntime.game_seconds(2, 0.5), 90.5)
	var timing_cases := 0
	for clip: StringName in Timings.ATTACKS:
		var event := Timings.events(clip)
		for training: float in [0.0, 60.0, 10000.0]:
			var reduction := SiteCombatRules.diminishing(training, 0.15)
			for fatigue: float in [0.0, 30.0, 65.0, 100.0]:
				var penalty := PersonFatigue.slowdown(fatigue)
				var scale := (1.0 - reduction) * (1.0 + penalty)
				var start: float = event.active_start * scale
				var end: float = start + event.active_end - event.active_start
				near(Timings.sample_time(clip, start, reduction, penalty), event.active_start)
				near(Timings.sample_time(clip, end, reduction, penalty), event.active_end)
				near(Timings.sample_time(clip, Timings.action_duration(clip, reduction, penalty), reduction, penalty), event.duration)
				near(end - start, event.active_end - event.active_start, "active interval unchanged")
				timing_cases += 1
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.terrain.site.worker_enabled = false
	lab.site_controller.save_path = SAVE
	var actor := lab.character
	var npc := lab.npc
	actor.fatigue = 67.25
	actor.fatigue_rest = 12.5
	npc.fatigue = 91.5
	actor.hp = 41.0
	lab.site_controller._capture_positions()
	assert(Store.save(lab.terrain, SAVE).ok)
	var loaded := Store.load_site(SAVE)
	assert(loaded.ok)
	lab.bind_terrain(loaded.data)
	near(actor.fatigue, 67.25)
	near(actor.fatigue_rest, 12.5)
	near(npc.fatigue, 91.5)
	near(actor.hp, 41.0)
	var npc_faction := npc.faction_id
	npc.faction_id = actor.faction_id
	actor.fatigue = 60
	actor.fatigue_rest = 30
	lab.site_controller._save_elapsed = 30
	lab._process(1)
	var automatic := Store.load_site(SAVE)
	assert(automatic.ok)
	near(actor.fatigue, 60.0 - 1.0 / 3.0)
	near(float(automatic.data.site.actors.player.fatigue), actor.fatigue, "autosave after frame fatigue settlement")
	npc.faction_id = npc_faction
	actor.fatigue = 67.25
	actor.fatigue_rest = 12.5
	var snapshot := actor.capture_state()
	for field: String in ["fatigue", "fatigue_rest", "_fatigue_slowdown"]:
		for bad: Variant in [-1, 101, "0", null, INF, NAN]:
			var broken: Dictionary = snapshot.duplicate(true)
			broken[field] = bad
			assert(not TerrainTestCharacter.valid_state(broken, lab.terrain), "Invalid fatigue accepted")
		var legacy: Dictionary = snapshot.duplicate(true)
		legacy.erase(field)
		assert(TerrainTestCharacter.valid_state(legacy, lab.terrain))
		actor.restore_state(legacy)
		near(float(actor.get(field)), 0.0, "legacy default")
	actor.restore_state(snapshot)
	actor.reset_combat()
	near(actor.fatigue, 67.25, "combat reset cannot erase fatigue")
	# Controlled traversable Site; no fake hit geometry or fabricated contacts.
	var data := lab.terrain
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)
	actor.place(Vector2i(20, 20), true)
	npc.place(Vector2i(29, 20), true)
	actor.fatigue = 60
	actor.fatigue_rest = 0
	lab._advance_fatigue(30)
	near(actor.fatigue, 60)
	near(actor.fatigue_rest, 30)
	lab._advance_fatigue(60)
	near(actor.fatigue, 60.0 - 1.0 / 3.0)
	npc.place(Vector2i(28, 20), true)
	lab._advance_fatigue(60)
	near(actor.fatigue_rest, 0, "eight-step threat interrupts rest")
	near(actor.fatigue, 60.0 - 1.0 / 3.0)
	for y in range(100):
		data.static_blocked[data.index(Vector2i(24, y))] = 1
	assert(not lab._fatigue_threat(actor.terrain_cell, actor.faction_id, actor, -1, {}), "Unreachable opponent is not a rest threat")
	data.static_blocked[data.index(Vector2i(24, 20))] = 0
	assert(lab._fatigue_threat(actor.terrain_cell, actor.faction_id, actor, -1, {}))
	data.static_blocked.fill(0)
	npc.place(Vector2i(40, 20), true)
	var before := actor.fatigue
	actor.guarding = true
	lab._advance_fatigue(60)
	near(actor.fatigue, before + 3, "guard effort")
	actor.guarding = false
	actor.knockout_left = 10
	before = actor.fatigue
	lab._advance_fatigue(3600)
	near(actor.fatigue, before, "unconscious is not rest")
	actor.knockout_left = 0
	actor.captive = true
	lab._advance_fatigue(3600)
	near(actor.fatigue, before, "captive is not rest")
	actor.captive = false
	npc.projectiles.append({"position": actor.position - Vector2(20, 0), "velocity": Vector2.RIGHT * 420, "ground": actor.position, "remaining": 100.0})
	assert(lab._fatigue_threat(actor.terrain_cell, actor.faction_id, actor, -1, {}), "Headless missing projection conservatively blocks near projectile rest")
	npc.projectiles.clear()
	actor.fatigue = 50
	actor.fatigue_rest = 30
	lab._advance_combat(2.0, 0.5)
	near(actor.fatigue, 50.0 - 90.5 * PersonFatigue.RECOVERY_RATE, "shared peace/combat clock")
	before = actor.fatigue
	data.site.paused = true
	lab._advance_combat(1.0)
	near(actor.fatigue, before)
	data.site.paused = false
	paused = true
	lab._advance_combat(1.0)
	near(actor.fatigue, before)
	paused = false
	# Fatigue during work belongs to this exact actor; no simultaneous rest.
	lab._fatigue_work_seconds.clear()
	actor.fatigue = 50
	var expected_work := PersonFatigue.work_seconds(50, 60) / 60.0
	near(lab.fatigue_work_minutes(true, 1), expected_work)
	lab._advance_fatigue(60)
	near(actor.fatigue, 50.0 + 1.0 / 6.0)
	near(actor.fatigue_rest, 0)
	lab._fatigue_work_seconds.clear()
	actor.training_query = Callable()
	actor.training = 60
	actor.fatigue = 100
	npc.place(Vector2i(21, 20), true)
	assert(actor.start_attack(npc))
	var duration := actor._attack_duration
	actor.fatigue = 0
	actor.training = 0
	near(actor._clip_time(duration), actor._clip_duration, "immutable action-start fatigue/training")
	near(actor._fatigue_slowdown, 0.3)
	actor.reset_combat()
	var team := lab.army
	var cells: Array[Vector2i] = []
	for index in range(100):
		cells.append(Vector2i(40 + index % 10, 40 + floori(float(index) / 10)))
	assert(team.deploy_at(data, actor, npc, cells) and team.enable_combat(false))
	lab.combat_armies.assign([team])
	team.set_process(false)
	team.training = 60
	team.combat_units[1].fatigue = 100
	assert(team.start_unit_attack(1, team.cells[1] + Vector2i.RIGHT))
	near(float(team.combat_units[1].attack_fatigue), 0.3)
	near(float(team.combat_units[1].attack_reduction), SiteCombatRules.diminishing(60, 0.15))
	team.training = 0
	team.combat_units[1].fatigue = 40
	actor.fatigue = 40
	npc.fatigue = 40
	assert(actor.start_attack(npc))
	assert(npc.start_attack(actor))
	lab._advance_fatigue(10)
	near(actor.fatigue, 41)
	near(npc.fatigue, 41)
	near(float(team.combat_units[1].fatigue), 41, "all three original owners use same attack effort")
	near(float(team.combat_units[1].attack_fatigue), 0.3, "row attack snapshot cannot drift")
	actor.reset_combat()
	npc.reset_combat()
	lab.clear_army()
	lab.queue_free()
	await process_frame
	print("SITE FATIGUE PASS: ", timing_cases, " timing combinations; integrated work partition, rest/threat/clock/pause, original actor state/save/legacy/action snapshots; no GPU claim")
	quit(0)
