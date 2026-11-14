extends SceneTree

const Timings = preload("res://scripts/terrain_lab/character_combat_timings.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")

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
	lab.npc = TerrainTestNPC.new() # Historical command fixture supplies its original NPC before entering the tree.
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.terrain.site.worker_enabled = false
	var save_path: String = lab.site_controller.save_path
	assert(not lab.site_controller.crowd_test_run_id.is_empty(), "A unique --crowd-test run is required for original autosave isolation")
	assert(lab.site_controller._save_path_guard(save_path).ok, "Original Controller must admit its configured fixture save path")
	var actor := lab.character
	var npc := lab.npc
	actor.fatigue = 67.25
	actor.fatigue_rest = 12.5
	npc.fatigue = 91.5
	actor.hp = 41.0
	lab.site_controller._capture_positions()
	assert(Store.save(lab.terrain, save_path).ok)
	var loaded := Store.load_site(save_path)
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
	var automatic := Store.load_site(save_path)
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
	# Nekki 11/14 A: the rest/threat/guard/attack-effort part ran on the retired legacy geometry mode (exchange off)
	# and a GD army; it was removed. Timing tables, Actor fatigue save/load/autosave and state validation remain.
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	await process_frame
	print("SITE FATIGUE PASS: ", timing_cases, " timing combinations; original actor fatigue save/autosave/legacy defaults/state validation; no GPU claim")
	quit(0)
