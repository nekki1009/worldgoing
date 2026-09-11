extends SceneTree

# Each bounded GPU run starts from the unchanged default scene and keeps the
# same army alive while fast-forwarding to one explicitly selected activity.
# Only the sampling window runs at real, unthrottled render-frame delta.
const GATES = preload("res://scripts/tests/terrain_army_default_edge_test.gd").EXPECTED_GATES
const FormationCases = preload("res://scripts/tests/terrain_army_formation_advance_test.gd")
const EntranceFixture = preload("res://scripts/tests/terrain_army_entrance_clearance_test.gd")
const STAGES := ["flat", "catchup", "receiving", "turn", "march", "gate1", "gate2", "gate3", "gate4", "gate5", "regroup"]
var _physical_counts := PackedInt32Array()
var _previous: Array[Vector2i] = []

# Diagnostic-only inclusive timings; never use this instrumented subclass to
# claim a performance target. It follows the exact production implementation.
class ProfileArmy extends TerrainArmy:
	var recording := false
	var timings := {}
	func record(label: String, started: int) -> void:
		if recording:
			var sample: Vector2i = timings.get(label, Vector2i.ZERO)
			timings[label] = sample + Vector2i(Time.get_ticks_usec() - started, 1)
	func _next_passage_step(unit: int) -> Vector2i:
		var started := Time.get_ticks_usec()
		var result := super._next_passage_step(unit)
		record("next_passage", started)
		return result
	func _passage_step_to_goal(unit: int, goal: Vector2i, occupied: bool = false) -> Vector2i:
		var started := Time.get_ticks_usec()
		var result := super._passage_step_to_goal(unit, goal, occupied)
		record("step_to_goal", started)
		return result
	func _find_passage_route(start: Vector2i, goal: Vector2i, unit: int, occupied: bool = false, ignore_reservations: bool = false) -> Array[Vector2i]:
		var started := Time.get_ticks_usec()
		var before := local_search_expansions
		var result := super._find_passage_route(start, goal, unit, occupied, ignore_reservations)
		record("find_route", started)
		if recording and local_search_expansions > before:
			print("PROFILE_ROUTE phase=", _unit_passage_phase[unit], " from=", start, " goal=", goal, " expanded=", local_search_expansions - before, " length=", result.size(), " usec=", Time.get_ticks_usec() - started)
		return result
	func _follower_swap_requested(first: int, second: int) -> bool:
		var started := Time.get_ticks_usec()
		var result := super._follower_swap_requested(first, second)
		record("swap_requested", started)
		return result
	func _repair_idle_slot_bindings() -> bool:
		var started := Time.get_ticks_usec()
		var result := super._repair_idle_slot_bindings()
		record("repair_bindings", started)
		return result
	func _update_formation_status() -> void:
		var started := Time.get_ticks_usec()
		super._update_formation_status()
		record("status", started)
	func _service_push_search() -> void:
		var started := Time.get_ticks_usec()
		super._service_push_search()
		record("push_search", started)
	func _update_soldier_frames(delta: float) -> void:
		var started := Time.get_ticks_usec()
		super._update_soldier_frames(delta)
		record("soldier_frames", started)
	func _sync_visual_positions() -> void:
		var started := Time.get_ticks_usec()
		super._sync_visual_positions()
		record("visual_positions", started)

func _initialize() -> void:
	call_deferred("run")

func _p(samples: Array[float], fraction: float) -> float:
	return samples[int(floor((samples.size() - 1) * fraction))] if not samples.is_empty() else -1.0

func _observe(army: TerrainArmy) -> void:
	for unit: int in range(1, 100):
		if army.cells[unit] == _previous[unit]:
			continue
		for gate: int in range(GATES.size()):
			if _previous[unit] == GATES[gate][0] and army.cells[unit] == GATES[gate][1]:
				_physical_counts[gate] += 1
	_previous = army.cells.duplicate()

func _ready_stage(army: TerrainArmy, stage: String) -> bool:
	if stage in ["march", "flat"]:
		return army._formation_step_units.size() == 100 and army.formation_batch_steps >= 2
	if stage == "catchup":
		return army.locomotion_mode[98] == TerrainArmy.Locomotion.RUN and army.locomotion_mode[99] == TerrainArmy.Locomotion.RUN
	if stage == "receiving":
		return army._passage_crossings.size() == 1 and army._passage_clearings[0] >= 20 and army._passage_crossings[0] < 90
	if stage == "turn":
		return army._formation_bend_active and army._formation_step_units.size() >= 4
	if stage == "regroup":
		return army.passage_summary().completed == 99 and army.formation_count() < 99
	var gate := int(stage.trim_prefix("gate")) - 1
	return _physical_counts[gate] >= 20 and _physical_counts[gate] < 90

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("GPU performance requires visual mode")
		quit(1)
		return
	var stage := "march"
	var replay_hz := 30 if "--30hz" in OS.get_cmdline_user_args() else 60
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--stage="):
			stage = argument.trim_prefix("--stage=")
	if stage not in STAGES:
		push_error("Unknown performance stage")
		quit(1)
		return
	DisplayServer.window_set_size(Vector2i(2560, 1440))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var lab := (load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene).instantiate() as TerrainLab
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.npc.set_process(false)
	lab.character.set_process(false)
	if stage in ["flat", "catchup", "receiving"]:
		lab.terrain = EntranceFixture._entrance_data(false)
		if stage != "receiving":
			lab.terrain.flags.fill(TerrainData.Flag.WALKABLE)
		lab.renderer.display(lab.terrain)
		lab.character.data = lab.terrain
		lab.npc.set_data(lab.terrain)
		lab.character.place(Vector2i(3, 15), true)
		lab.npc.place(Vector2i(2, 15), true)
	if "--profile" in OS.get_cmdline_user_args():
		lab.army.free()
		lab.army = ProfileArmy.new()
		lab.add_child(lab.army)
		lab.army.player = lab.character
		lab.army.npc = lab.npc
		lab.army.data = lab.terrain
		lab.character.cell_blocker = Callable(lab.army, "blocks_cell")
		lab.npc.cell_blocker = Callable(lab.army, "blocks_cell")
	lab.army.set_process(false)
	lab.fit_map()
	lab.deploy_army()
	if not lab.army.has_army() or lab.army.visual_mode() != "baked_atlas":
		push_error("GPU performance deployment/render contract failed")
		quit(1)
		return
	var warmup_start := Time.get_ticks_usec()
	for frame: int in range(60):
		await process_frame
		await RenderingServer.frame_post_draw
	var warmup_ms := float(Time.get_ticks_usec() - warmup_start) / 1000.0
	_physical_counts.resize(GATES.size())
	_previous = lab.army.cells.duplicate()
	var initial := lab.army.cells.duplicate()
	if stage in ["flat", "catchup"]:
		FormationCases.configure_rectangular_snapshot(lab.army, Vector2i(14, 15))
		if stage == "catchup":
			for unit: int in [98, 99]:
				lab.army._cell_owners.erase(lab.army.cells[unit])
				lab.army.cells[unit] += Vector2i.LEFT * 3
				lab.army._cell_owners[lab.army.cells[unit]] = unit
		initial = lab.army.cells.duplicate()
	elif stage == "receiving":
		lab.character.place(Vector2i(36, 15), true)
		lab.issue_army_command(TerrainArmy.Command.FOLLOW_PLAYER)
	elif not lab.issue_army_command(TerrainArmy.Command.MOVE_TO_EDGE):
		push_error("GPU performance command rejected")
		quit(1)
		return
	if stage == "turn":
		for frame: int in range(20 * 60):
			lab.army.advance_frame(1.0 / 60.0)
			if lab.army._passage_descriptors.size() == 5 and not lab.army._passage_plan_pending and not lab.army._formation_target_pending:
				break
		if lab.army._passage_descriptors.size() != 5:
			push_error("PERF_TURN_FIXTURE_UNAVAILABLE")
			quit(1)
			return
		initial = FormationCases.configure_bend_snapshot(lab.army)
	_previous = initial.duplicate()
	# The V6 D01 deadline is 503 input seconds, declared before full replay.
	for frame: int in range(503 * replay_hz):
		lab.army.advance_frame(1.0 / float(replay_hz))
		_observe(lab.army)
		if _ready_stage(lab.army, stage):
			break
	if not _ready_stage(lab.army, stage):
		push_error("PERF_ACTIVITY_UNAVAILABLE " + stage)
		quit(1)
		return
	# Flush the existing renderer at the reached state. This is not a redeploy
	# or a new command; the next actual frame resumes this exact simulation.
	await process_frame
	await RenderingServer.frame_post_draw
	var input_start := lab.army.input_seconds
	var sim_start := lab.army.simulated_seconds
	var dropped_start := lab.army.dropped_seconds
	var steps_start := lab.army.completed_steps()
	var counts_start := _physical_counts.duplicate()
	var settled_start := lab.army.formation_count()
	var frame_samples: Array[float] = []
	var cpu_samples: Array[float] = []
	var phase_samples := {}
	var spike_count := 0
	var structure_max := 0
	var local_max := 0
	var push_max := 0
	var structure_before := lab.army.structure_search_expansions
	var local_before := lab.army.local_search_expansions
	var push_before := lab.army.push_search_expansions
	var sample_start := Time.get_ticks_usec()
	var previous_usec := sample_start
	if lab.army is ProfileArmy:
		lab.army.recording = true
	lab.set_process(true) # Include the production 10Hz HUD during measurement.
	lab.army.set_process(true)
	while float(Time.get_ticks_usec() - sample_start) / 1000000.0 < 3.0:
		await process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var elapsed := float(now - previous_usec) / 1000.0
		previous_usec = now
		frame_samples.append(elapsed)
		cpu_samples.append(float(lab.army.last_frame_cpu_usec) / 1000.0)
		var phase := "idle"
		if lab.army._formation_step_units.size() == 100:
			phase = "whole_batch"
		elif lab.army._formation_bend_active:
			phase = "local_turn"
		elif lab.army.locomotion_mode.count(TerrainArmy.Locomotion.RUN) > 0:
			phase = "rear_run"
		elif lab.army.moving_count() > 0:
			phase = "local_walk"
		if not phase_samples.has(phase):
			phase_samples[phase] = {"frame": [], "cpu": []}
		phase_samples[phase].frame.append(elapsed)
		phase_samples[phase].cpu.append(float(lab.army.last_frame_cpu_usec) / 1000.0)
		spike_count += int(elapsed > 50.0)
		structure_max = maxi(structure_max, lab.army.structure_search_expansions - structure_before)
		local_max = maxi(local_max, lab.army.local_search_expansions - local_before)
		push_max = maxi(push_max, lab.army.push_search_expansions - push_before)
		structure_before = lab.army.structure_search_expansions
		local_before = lab.army.local_search_expansions
		push_before = lab.army.push_search_expansions
		_observe(lab.army)
	lab.army.set_process(false)
	lab.set_process(false)
	if lab.army is ProfileArmy:
		print("PROFILE_DIAGNOSTIC_INCLUSIVE_USEC_CALLS ", lab.army.timings)
	frame_samples.sort()
	cpu_samples.sort()
	var progress := lab.army.completed_steps() - steps_start
	var sample_seconds := lab.army.input_seconds - input_start
	var gate_deltas := []
	for gate: int in range(GATES.size()):
		gate_deltas.append(_physical_counts[gate] - counts_start[gate])
	var targets_met := _p(frame_samples, 0.95) <= 16.7 and _p(frame_samples, 0.99) <= 25.0 and _p(cpu_samples, 0.95) <= 2.0
	var phase_report := {}
	for phase: String in phase_samples:
		var frames: Array[float] = []
		var cpus: Array[float] = []
		frames.assign(phase_samples[phase].frame)
		cpus.assign(phase_samples[phase].cpu)
		frames.sort()
		cpus.sort()
		phase_report[phase] = {"samples": frames.size(), "frame_p95_ms": _p(frames, 0.95), "frame_p99_ms": _p(frames, 0.99), "army_cpu_p95_ms": _p(cpus, 0.95), "max_ms": frames.back()}
	var report := {
		"stage": stage, "source_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"),
		"fingerprint": lab.terrain.fingerprint(), "initial_cells": initial,
		"gpu": RenderingServer.get_video_adapter_name(), "cpu": OS.get_processor_name(),
		"renderer": RenderingServer.get_current_rendering_method(), "driver": ProjectSettings.get_setting("rendering/rendering_device/driver.windows"),
		"resolution": "2560x1440", "vsync": "disabled", "max_fps": 0,
		"production_hud_enabled": true,
		"preparation_replay_hz": replay_hz, "sample_uses_actual_render_delta": true,
		"warmup_frames": 60, "warmup_ms": warmup_ms, "samples": frame_samples.size(),
		"activity_phases": phase_report, "fixture": "controlled_" + stage if stage in ["flat", "catchup", "receiving", "turn"] else "unchanged_D01_replay", "test_sha256": FileAccess.get_sha256("res://scripts/tests/terrain_lab_default_edge_performance_test.gd"),
		"frame_p50_ms": _p(frame_samples, 0.5), "frame_p95_ms": _p(frame_samples, 0.95), "frame_p99_ms": _p(frame_samples, 0.99), "frame_max_ms": frame_samples.back(),
		"army_cpu_p50_ms": _p(cpu_samples, 0.5), "army_cpu_p95_ms": _p(cpu_samples, 0.95), "army_cpu_p99_ms": _p(cpu_samples, 0.99), "army_cpu_max_ms": cpu_samples.back(),
		"frames_over_50ms": spike_count, "structure_max": structure_max, "local_max": local_max, "push_max": push_max,
		"input_start": input_start, "input_end": lab.army.input_seconds, "input_sample_seconds": sample_seconds,
		"sim_sample_seconds": lab.army.simulated_seconds - sim_start, "dropped_sample_seconds": lab.army.dropped_seconds - dropped_start,
		"physical_gate_counts_start": Array(counts_start), "physical_gate_counts_end": Array(_physical_counts), "physical_gate_commits": gate_deltas,
		"forward_gate_commits_per_second": float(gate_deltas.reduce(func(total: int, value: int) -> int: return total + value, 0)) / sample_seconds,
		"settled_start": settled_start, "settled_end": lab.army.formation_count(), "committed_steps": progress, "targets_met": targets_met
	}
	print("PERFORMANCE_MEASURED ", JSON.stringify(report))
	var output := ProjectSettings.globalize_path("res://.godot-temp/terrain_v6_performance/" + FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd").left(12) + "/" + stage + ("_profile" if lab.army is ProfileArmy else "") + ".json")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	var valid := frame_samples.size() >= 60 and progress > 0 and structure_max <= 256 and local_max <= 8192 and push_max <= 1024
	lab.army.clear()
	lab.queue_free()
	await process_frame
	# Wall-time targets are reported, not flaky CI assertions. EXIT 0 means
	# the activity was measured successfully, NOT that targets_met is true.
	quit(0 if valid else 1)
