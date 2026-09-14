extends "res://scripts/tests/site_workflow_test.gd"
## Two original 100-row armies. Isolated death/loot cost, not sustained combat FPS.
var enabled := true
var recovery := false
var measurements := {}

func _initialize() -> void:
	recovery = "--recovery" in OS.get_cmdline_user_args()
	deadline = Time.get_ticks_msec() + 100000 if recovery else (Time.get_ticks_msec() + 23000 if "--visual" in OS.get_cmdline_user_args() else Time.get_ticks_msec() + 15000)
	enabled = "--baseline" not in OS.get_cmdline_user_args()
	assert(not recovery or enabled, "New paired recovery suite requires actual original remains")
	_run.call_deferred()

func _run() -> void:
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.npc_retaliates = false
	var data := _fixture()
	# Controlled test ground only; production terrain never changes for deployment.
	for y in range(35, 48):
		for x in range(35, 57):
			var cell := Vector2i(x, y)
			var index := data.index(cell)
			data.flags[index] = TerrainData.Flag.WALKABLE
			data.height_levels[index] = 0
			data.ramp_edges[index] = 0
			for key: String in data.resources_at.get(index, []):
				Env.change(data, key, {"cleared": true, "remaining": 0})
	Env.rebuild_indexes(data)
	Runtime.rebuild_terrain_edges(data)
	lab.bind_terrain(data)
	lab.site_controller.release_worker()
	lab.site_controller._auto_save_blocked = true
	for which in range(2):
		var team: TerrainArmy = lab.combat_armies[which]
		var cells: Array[Vector2i] = []
		for index in range(100):
			cells.append(Vector2i(35 + which * 11 + index % 10, 35 + floori(float(index) / 10.0)))
		assert(team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat())
		team.enemy_query = Callable() # Isolate loot overhead from changing combat outcomes.
		team.combat_attacking = false
		if recovery:
			team.combat_units[0].cargo.wood = 2 + which # Explicit original pre-death cargo fixture.
		if not enabled:
			team.died.disconnect(lab.site_controller._person_died)
	var original_records: int = data.site.item_records.size()
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var visual := "--visual" in OS.get_cmdline_user_args()
	if visual:
		assert(DisplayServer.get_name() != "headless")
		root.size = Vector2i(1440, 1000)
		root.content_scale_size = root.size
		lab.camera.zoom = Vector2.ONE * 0.65
		lab.camera.position = Vector2(46, 40) * TerrainRenderer.CELL_PIXELS + Vector2(250, 0)
		for frame in range(3):
			await process_frame
		measurements.alive = await _frames(lab, false)
	var death_start := Time.get_ticks_usec()
	for team: TerrainArmy in lab.combat_armies:
		for index in range(100):
			team.apply_unit_contact(index, {"result": {"hp": 1000.0, "stun": 0.0, "guard_break": false}, "shield": false, "environmental": true})
	measurements.death_dispatch_ms = (Time.get_ticks_usec() - death_start) / 1000.0
	var settle_start := Time.get_ticks_usec()
	var down_seconds := float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"]) + 0.03
	if visual:
		# The headless companion proves the full Site clock. This GPU comparison
		# isolates the real final death owners and drawing, not repeated mesh seeks.
		for team: TerrainArmy in lab.combat_armies:
			team.prepare_combat(down_seconds)
			team.settle_combat_command()
		lab.site_controller.settle_person_deaths(down_seconds)
		measurements.final_death_owners_cpu_ms = (Time.get_ticks_usec() - settle_start) / 1000.0
	else:
		lab._process(down_seconds)
		measurements.full_clock_down_and_settlement_cpu_ms = (Time.get_ticks_usec() - settle_start) / 1000.0
	assert(data.site.ground_loot.size() == (200 if enabled else 0))
	assert(data.site.item_records.size() == original_records)
	for team: TerrainArmy in lab.combat_armies:
		for unit: Dictionary in team.combat_units:
			assert(float(unit.hp) == 0.0)
			if enabled:
				assert(bool(unit.loot_settled) and unit.item_state.item_ids.is_empty())
	if visual:
		measurements.stationary = await _frames(lab, false)
		measurements.camera_motion = await _frames(lab, true)
	if recovery:
		await _recover_pair(lab)
	if visual:
		await RenderingServer.frame_post_draw
		var image_path := "res://output/site_loot_200_20260913/" + ("recovery" if recovery else "enabled" if enabled else "baseline") + ".png"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(image_path.get_base_dir()))
		assert(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(image_path)) == OK)
	measurements.nodes_before = nodes_before
	measurements.nodes_after = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	measurements.static_memory_bytes = OS.get_static_memory_usage()
	measurements.texture_memory_bytes = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	lab.site_controller._capture_positions()
	var path := "user://loot200/scene.json"
	var save_start := Time.get_ticks_usec()
	var saved := Store.save(data, path)
	assert(saved.ok, str(saved))
	measurements.save_ms = (Time.get_ticks_usec() - save_start) / 1000.0
	measurements.save_bytes = FileAccess.get_file_as_bytes(path).size()
	var load_start := Time.get_ticks_usec()
	var loaded := Store.load_site(path)
	assert(loaded.ok and loaded.data.site.ground_loot.size() == data.site.ground_loot.size(), str(loaded))
	measurements.load_ms = (Time.get_ticks_usec() - load_start) / 1000.0
	measurements.merge({"loot_enabled": enabled, "actual_army_rows": 200, "containers": data.site.ground_loot.size(), "item_records": original_records, "scope": "isolated original 200-row death burst and containers; not sustained combat FPS", "visual": visual})
	var output := "res://output/site_loot_200_20260913/" + ("recovery" if recovery else "enabled" if enabled else "baseline") + ("_visual" if visual else "_headless") + ".json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(measurements, "\t"))
	file.close()
	print("SITE_LOOT_200_SCENE_PASS ", JSON.stringify(measurements))
	lab.free()
	TerrainArmy.release_contact_source()
	quit()

func _recover_pair(lab: TerrainLab) -> void:
	var controller: SiteController = lab.site_controller
	var original_bodies: Array = [lab.character, lab.npc]
	var original_cargo: Array[Dictionary] = [lab.terrain.site.manual.cargo, lab.terrain.site.worker.cargo]
	var carried_before: Array[int] = []
	var containers: Array[Dictionary] = []
	for which in range(2):
		var team: TerrainArmy = lab.combat_armies[which]
		var actor: TerrainTestCharacter = original_bodies[which]
		assert(actor.place(team.cells[0] + Vector2i.UP, true))
		var identity := str(team.combat_units[0].remains_id)
		containers.append(lab.terrain.site.ground_loot[identity])
		carried_before.append(int(original_cargo[which].get("wood", 0)))
		assert(controller.person_actions.begin_loot(actor.person_id, "ground", identity, {"wood": 2 + which}, []).ok)
	var at := Runtime.now(lab.terrain) * 60.0
	var cpu := 0
	var intervals: Array[float] = []
	var previous := Time.get_ticks_usec()
	while controller.person_actions.is_busy(lab.character.person_id) or controller.person_actions.is_busy(lab.npc.person_id):
		assert(intervals.size() < 32 and Time.get_ticks_msec() < deadline, "Bounded actual peaceful work; no fake combat clock to extend the sample")
		var start := Time.get_ticks_usec()
		lab._process(1.0 / 120.0)
		cpu += Time.get_ticks_usec() - start
		await process_frame
		await RenderingServer.frame_post_draw
		var current := Time.get_ticks_usec()
		intervals.append((current - previous) / 1000.0)
		previous = current
	for which in range(2):
		assert(original_bodies[which] == (lab.character if which == 0 else lab.npc))
		assert(is_same(original_cargo[which], lab.terrain.site.manual.cargo if which == 0 else lab.terrain.site.worker.cargo))
		assert(int(original_cargo[which].get("wood", 0)) == carried_before[which] + 2 + which)
		assert(int(containers[which].cargo.get("wood", 0)) == 0 and not containers[which].item_ids.is_empty())
	assert(lab.terrain.site.ground_loot.size() == 200, "Taking loose cargo does not erase remaining worn equipment or corpses")
	intervals.sort()
	var total := 0.0
	for value: float in intervals:
		total += value
	measurements.paired_recovery = {"original_workers": 2, "original_corpses": 200, "game_seconds": Runtime.now(lab.terrain) * 60.0 - at,
		"common_clock_cpu_ms": cpu / 1000.0, "active_frame_intervals": intervals.size(), "mean_ms": total / intervals.size(),
		"p95_ms": intervals[ceili(intervals.size() * 0.95) - 1], "maximum_ms": intervals.back(),
		"scope": "Two real original Actors recover original wood in the actual peaceful clock; few active intervals, not stable-FPS or autonomous pathfinding benchmark"}

func _frames(lab: TerrainLab, pan: bool) -> Dictionary:
	var values: Array[float] = []
	var previous := Time.get_ticks_usec()
	for frame in range(32):
		if pan:
			lab.camera.position.x += 2.0 if frame < 16 else -2.0
		await process_frame
		lab.site_controller.view.animate(1.0 / 60.0)
		var current := Time.get_ticks_usec()
		values.append((current - previous) / 1000.0)
		previous = current
	values.sort()
	var total := 0.0
	for value: float in values:
		total += value
	return {"samples": values.size(), "mean_frame_ms": total / values.size(), "p95_frame_ms": values[ceili(values.size() * 0.95) - 1], "maximum_frame_ms": values.back()}
