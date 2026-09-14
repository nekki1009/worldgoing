extends "res://scripts/tests/site_army_combat_longrun_test.gd"
## New combat policy acceptance. Original people/items/renderers, not old hit equivalence.
## Canonical GPU helper timeout 150 s, internal deadline 130 s. --short is diagnostic only.

const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const SOURCES := ["terrain_lab", "terrain_army", "terrain_army_equipment_atlas", "terrain_test_character", "character_exchange_timings", "site_combat_rules", "site_runtime", "site_resource_view"]
var lab: TerrainLab
var done := false
var duration := 60.0
var frame_ms: Array[float] = []
var frame_at: Array[float] = []
var begin_us := 0
var previous_us := 0
var fingerprints := {}

class MeasuredLab extends TerrainLab:
	var accepted_seconds := 0.0
	var action_seconds := 0.0
	var cpu_usec := 0
	var recording := false
	var geometry_calls := 0
	func _process(delta: float) -> void:
		var before := Time.get_ticks_usec()
		super._process(delta)
		if recording:
			accepted_seconds += delta
			cpu_usec += Time.get_ticks_usec() - before
	func _advance_combat(delta: float, combat_clock: float = -1.0) -> void:
		super._advance_combat(delta, combat_clock)
		if recording:
			action_seconds += delta
	func _collect_army_contacts(previous: Array[PackedVector2Array], current: Array[PackedVector2Array], source_cell: Vector2i, source_position: Vector2, source: Variant, source_unit: int, ranged: bool = false, prepared: Array = []) -> Array[Dictionary]:
		geometry_calls += 1
		return super._collect_army_contacts(previous, current, source_cell, source_position, source, source_unit, ranged, prepared)

func _initialize() -> void:
	started_us = Time.get_ticks_usec()
	deadline_us = started_us + 130000000
	duration = 10.0 if "--short" in OS.get_cmdline_user_args() else 60.0
	output_path = "res://output/site_exchange_20260914/%d" % int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path))
	for source: String in SOURCES:
		var path := "res://scripts/terrain_lab/%s.gd" % source
		fingerprints[path] = FileAccess.get_sha256(path)
	fingerprints["res://scripts/tests/site_exchange_realtime_test.gd"] = FileAccess.get_sha256("res://scripts/tests/site_exchange_realtime_test.gd")
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not done and Time.get_ticks_usec() >= deadline_us:
		push_error("EXCHANGE benchmark deadline; not a performance pass")
		quit(1)
	return false

func _run() -> void:
	assert(DisplayServer.get_name() != "headless", "GPU window required")
	assert(Atlas.set_catalog_path("res://output/terrain_army_m25_scalar_20260913/test_catalog.json"))
	root.size = Vector2i(1400, 900)
	root.content_scale_size = root.size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	assert(Engine.time_scale == 1.0)
	lab = MeasuredLab.new()
	lab.pause_when_unfocused = false
	lab.combat_profile_enabled = "--profile" in OS.get_cmdline_user_args()
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	lab.site_controller._auto_save_blocked = true
	var data := TerrainGenerator.generate(0, 581)
	Env.initialize(data, "exchange-realtime-fixture")
	for key: String in data.resource_base:
		Env.change(data, key, {"cleared": true, "remaining": 0})
	Env.rebuild_indexes(data)
	for index in range(data.surface_types.size()):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
		data.surface_types[index] = TerrainData.Surface.GRASS
	data.ramp_edges.fill(0)
	lab.bind_terrain(data)
	lab.site_controller.release_worker()
	assert(lab.character.place(Vector2i(50, 50), true) and lab.npc.place(Vector2i(52, 50), true))
	var deployed := lab.start_melee_trial()
	assert(deployed.ok, str(deployed))
	assert(lab.exchange_enabled)
	var original_inventory := _inventory(lab)
	assert(original_inventory.items.size() == 1018)
	var transfers := _prepare_mixed_equipment(lab)
	assert(transfers.size() == 20)
	for team: TerrainArmy in lab.combat_armies:
		assert(team.exchange_enabled and team.combat_units.size() == 100 and team.combat_attacking)
		assert(team.visual_mode() == "baked_atlas" and team.active_3d_source_count() == 1)
	lab.camera.zoom = Vector2.ONE * 0.85
	var camera_position := lab.camera.position
	lab.site_controller._capture_positions()
	var save_path := output_path + "/before_battle.json"
	assert(Store.save(data, save_path).ok)
	var save_hash := FileAccess.get_sha256(save_path)
	# Closing the editor must return this ORIGINAL actor to the Lab-driven
	# presenter, not leave an invisible editor ticking or a frozen map texture.
	lab.character.open_editor()
	assert(lab.character.editor_window.visible and lab.character.editor.is_processing())
	lab.character.editor.close()
	assert(not lab.character.editor_window.visible and not lab.character.editor.is_processing())
	assert(lab.character.editor.visible and lab.character.editor.animation_player.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL)
	var warmup := Time.get_ticks_usec()
	while Time.get_ticks_usec() - warmup < 2000000:
		await process_frame
		await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output_path + "/before.png") == OK)
	await process_frame
	await RenderingServer.frame_post_draw
	var measured := lab as MeasuredLab
	var initial_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var initial_samples := _samples()
	var initial_pages := [Atlas.page_load_count, Atlas.page_load_usec, Atlas.page_evictions]
	var initial_render := lab.army.combat_render_usec + lab.opposing_army.combat_render_usec
	measured.recording = true
	lab.set_process(true)
	begin_us = Time.get_ticks_usec()
	previous_us = begin_us
	var next_checkpoint := 10.0
	while Time.get_ticks_usec() - begin_us < int(duration * 1000000.0):
		await process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frame_ms.append((now - previous_us) / 1000.0)
		frame_at.append((now - begin_us) / 1000000.0)
		previous_us = now
		if frame_at[-1] >= next_checkpoint:
			print("EXCHANGE_PROGRESS ", JSON.stringify({"wall": frame_at[-1], "frames": frame_ms.size(), "exchanges": lab.exchange_count, "life": _life(lab)}))
			next_checkpoint += 10.0
	lab.set_process(false)
	measured.recording = false
	var wall := (previous_us - begin_us) / 1000000.0
	var sorted := frame_ms.duplicate()
	sorted.sort()
	var p95: float = sorted[mini(sorted.size() - 1, ceili(sorted.size() * 0.95) - 1)]
	var bins: Array[float] = []
	for bin_index in range(int(duration / 10.0)):
		var frames := 0
		for at: float in frame_at:
			frames += int(at >= bin_index * 10.0 and at < (bin_index + 1) * 10.0)
		bins.append(frames / 10.0)
	var final_inventory := _inventory(lab)
	var life := _life(lab)
	var source_stable := true
	for path: String in fingerprints:
		source_stable = source_stable and FileAccess.get_sha256(path) == fingerprints[path]
	var gate := {"full_60_wall_seconds": duration == 60.0 and wall >= 60.0,
		"fps30": frame_ms.size() / wall >= 30.0, "p95_33ms": p95 <= 33.334,
		"all_10s_bins30": bins.min() >= 30.0, "all_200_people": int(life.actual_rows) == 200,
		"actual_exchanges": lab.exchange_count >= 100, "exact_geometry_unused": _samples() == initial_samples and measured.geometry_calls == 0,
		"items_conserved": final_inventory.items == original_inventory.items,
		"action_clock": absf(measured.accepted_seconds - measured.action_seconds) <= TerrainLab.EXCHANGE_ACTION_STEP + 0.00001 and measured.accepted_seconds / wall >= 0.95 and measured.accepted_seconds / wall <= 1.05,
		"camera_stable": lab.camera.position == camera_position and lab.camera.zoom == Vector2.ONE * 0.85,
		"node_count_stable": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) == initial_nodes,
		"source_stable": source_stable}
	lab.site_controller._capture_positions()
	var busy_save := Store.save(data, save_path)
	gate["combat_save_preserved"] = not busy_save.ok and busy_save.code == "BUSY" and FileAccess.get_sha256(save_path) == save_hash
	var passed := true
	for value: bool in gate.values():
		passed = passed and value
	measurements = {"policy": "adjacent ability exchange / 30Hz common clock / 10Hz pairing / 1Hz per person; NOT old geometry equivalence", "targets_met": passed,
		"gate": gate, "wall_seconds": wall, "fps": frame_ms.size() / wall, "p95_ms": p95, "bins_fps": bins,
		"input_seconds": measured.accepted_seconds, "action_seconds": measured.action_seconds,
		"lab_cpu_ms": measured.cpu_usec / 1000.0, "source_samples": _samples() - initial_samples,
		"profile_usec": lab.combat_profile_usec,
		"atlas_page_loads": Atlas.page_load_count - initial_pages[0], "atlas_load_ms": (Atlas.page_load_usec - initial_pages[1]) / 1000.0,
		"atlas_evictions": Atlas.page_evictions - initial_pages[2],
		"army_render_ms": (lab.army.combat_render_usec + lab.opposing_army.combat_render_usec - initial_render) / 1000.0,
		"exchanges": lab.exchange_count, "results": lab.exchange_results, "life": life,
		"nodes": [initial_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))],
		"frame_ms": frame_ms, "source_sha256": fingerprints,
		"gpu": RenderingServer.get_video_adapter_name(), "cpu": OS.get_processor_name(),
		"catalog": Atlas._catalog_path, "catalog_scope": "existing source-verified mixed test recipe, not all production equipment recipes"}
	_write()
	assert(root.get_texture().get_image().save_png(output_path + "/after.png") == OK)
	print("EXCHANGE_REALTIME_RESULT ", JSON.stringify({"output": output_path, "fps": measurements.fps, "p95_ms": p95, "gate": gate, "targets_met": passed}))
	done = true
	lab.queue_free()
	await process_frame
	quit(0) # Complete measurement is not an unmet performance gate PASS.

func _samples() -> int:
	return 0 if TerrainArmy._contact_source == null else int(TerrainArmy._contact_source.query_profile.sample_calls)
