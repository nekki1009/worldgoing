extends SceneTree

## GPU-backed smoke benchmark for the 100-unit Terrain Lab formation.
## It measures the shipped baked-atlas path, not a synthetic headless loop.

const WARMUP_FRAMES := 60
const SAMPLE_FRAMES := 180

func _collect_frame_samples(sample_count: int) -> Array[float]:
	var samples: Array[float] = []
	var previous_usec := Time.get_ticks_usec()
	for _frame: int in range(sample_count):
		await process_frame
		var now_usec := Time.get_ticks_usec()
		samples.append(float(now_usec - previous_usec) / 1000.0)
		previous_usec = now_usec
	samples.sort()
	return samples

func _percentile(samples: Array[float], fraction: float) -> float:
	return samples[int(floor(float(samples.size() - 1) * fraction))]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("TERRAIN LAB ARMY PERFORMANCE SKIP: visual mode required")
		quit(0)
		return
	DisplayServer.window_set_size(Vector2i(2560, 1440))
	var scene: PackedScene = load("res://scenes/terrain_lab/TerrainLab.tscn")
	var lab: TerrainLab = scene.instantiate() as TerrainLab
	root.add_child(lab)
	current_scene = lab
	lab.preset_dropdown.select(TerrainPreset.Kind.PLAINS)
	lab.seed_input.text = "24680"
	lab.generate_button.pressed.emit()
	for _frame: int in range(WARMUP_FRAMES):
		await process_frame
	var baseline_samples: Array[float] = await _collect_frame_samples(SAMPLE_FRAMES)
	assert(lab.army.deploy(lab.terrain, lab.character, lab.npc), lab.army.command_status)
	assert(lab.army.visual_mode() == "baked_atlas")
	assert(lab.army.active_3d_source_count() == 1)
	var idle_samples: Array[float] = await _collect_frame_samples(SAMPLE_FRAMES)
	assert(lab.army.completed_steps() == 0, "Idle benchmark unexpectedly advanced the army")
	lab.army.issue_command(TerrainArmy.Command.MOVE_TO_EDGE)
	var captain_before: Vector2i = lab.army.cells[0]
	var steps_before := lab.army.completed_steps()
	for _frame: int in range(WARMUP_FRAMES):
		await process_frame
	var army_samples: Array[float] = await _collect_frame_samples(SAMPLE_FRAMES)
	assert(lab.army.completed_steps() > steps_before or lab.army.cells[0] != captain_before or lab.army.moving_count() > 0, "Moving benchmark made no measurable progress")
	print("TERRAIN LAB ARMY PERFORMANCE PASS: mode=%s sources=%d nodes=%d baseline_p95_ms=%.3f idle_p95_ms=%.3f moving_p50_ms=%.3f moving_p95_ms=%.3f moving_p99_ms=%.3f moving_max_ms=%.3f fps=%d completed_steps=%d swaps=%d arrived=%d" % [lab.army.visual_mode(), lab.army.active_3d_source_count(), get_node_count(), _percentile(baseline_samples, 0.95), _percentile(idle_samples, 0.95), _percentile(army_samples, 0.50), _percentile(army_samples, 0.95), _percentile(army_samples, 0.99), army_samples.back(), Engine.get_frames_per_second(), lab.army.completed_steps(), lab.army.swap_count(), lab.army.arrived_count()])
	lab.queue_free()
	await process_frame
	quit(0)
