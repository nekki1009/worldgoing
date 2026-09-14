extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(18.0).timeout.connect(func() -> void: quit(1))
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	print("SLOW FRAME STAGE: lab ready at ", Time.get_ticks_msec())
	lab.set_process(false)
	lab.site_controller.set_process(false)
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "slow-frame-fixture")
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)
	lab.bind_terrain(data)
	lab.character.place(Vector2i(50, 50), true)
	lab.npc.place(Vector2i(52, 50), true)
	assert(lab.start_melee_trial().ok)
	print("SLOW FRAME STAGE: deployed at ", Time.get_ticks_msec())
	# Both runs start in the same combat-clock interval; the isolated body step
	# does not rewind SiteRuntime when army snapshots alone are restored below.
	data.site.combat_left = 30.0
	var initial: Array[Dictionary] = []
	for team: TerrainArmy in lab.combat_armies:
		team.set_process(false)
		for unit: Dictionary in team.combat_units:
			unit.fatigue = 80.0
		initial.append(team.capture_combat_state())
	# Same 1.5 seconds, either 180 normal ticks or three half-second frames.
	for tick in range(180):
		lab._advance_combat(1.0 / 120.0)
	var normal: Array[Dictionary] = []
	print("SLOW FRAME STAGE: normal complete at ", Time.get_ticks_msec())
	var hit_count := 0
	for team: TerrainArmy in lab.combat_armies:
		normal.append(team.capture_combat_state())
		for unit: Dictionary in team.combat_units:
			hit_count += unit.hits.size()
	assert(hit_count > 0, "This comparison must cross actual authored weapon contact")
	for index in range(2):
		lab.combat_armies[index].restore_combat_state(initial[index], data, lab.character, lab.npc)
	data.site.combat_left = 30.0
	for tick in range(3):
		lab._advance_combat(0.5)
	for index in range(2):
		var slow := lab.combat_armies[index].capture_combat_state()
		print("SLOW FRAME STAGE: slow complete at ", Time.get_ticks_msec())
		for field: String in ["formal_commander", "acting_commander", "current_commander", "rng", "combat_order", "needs_attack_order"]:
			assert(slow[field] == normal[index][field], "Command/RNG diverged under a slow frame: " + field)
		for unit_index in range(100):
			var a: Dictionary = normal[index].units[unit_index]
			var b: Dictionary = slow.units[unit_index]
			for field: String in ["hp", "stun", "ko", "age", "think", "progress", "fatigue", "fatigue_rest", "attack_reduction", "attack_fatigue"]:
				assert(absf(float(a[field]) - float(b[field])) < 0.000001, "Lost time or changed damage: %d %s" % [unit_index, field])
			for field: String in ["hits", "pose", "cell", "destination", "attack", "blocked", "target"]:
				assert(a[field] == b[field], "Changed contact/occupancy: %d %s" % [unit_index, field])
			assert(a.get("aim", []) == b.get("aim", []), "Frozen swing aim changed under slow frames")
	paused = true
	var frozen := lab.army.capture_combat_state()
	lab._advance_combat(0.5)
	assert(lab.army.capture_combat_state() == frozen)
	paused = false
	lab.clear_army()
	lab.queue_free()
	await process_frame
	print("SITE COMBAT SLOW FRAME PASS: 200 rows / actual continuous contact, 180 small ticks equal three slow frames, command/RNG/damage/dedup/occupancy/aim preserved; contacts=", hit_count)
	quit(0)
