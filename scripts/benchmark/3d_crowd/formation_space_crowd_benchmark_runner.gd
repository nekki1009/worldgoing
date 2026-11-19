extends SceneTree

const SimulationType = preload("res://scripts/benchmark/3d_crowd/battle_crowd_simulation.gd")
const CrowdRendererType = preload("res://scripts/benchmark/3d_crowd/crowd_renderer_3d.gd")
const ControllerType = preload("res://scripts/benchmark/3d_crowd_promotion/crowd_promotion_benchmark_controller.gd")
const SpecialRenderModeType = preload("res://scripts/benchmark/3d_special/special_character_render_mode.gd")
const ScenePath: String = "res://scenes/benchmark/3d_crowd/FormationSpaceCrowdBenchmark3D.tscn"
const WARMUP_FRAMES: int = 30
const SAMPLE_FRAMES: int = 120

var benchmark: CrowdPromotionBenchmarkController
var warmup_frames: int = WARMUP_FRAMES
var sample_frames: int = SAMPLE_FRAMES
var sample_seconds: float = 0.0
var only_case: String = ""
var case_order: Array[String] = []
var suite: String = "fixed"
var requested_soldiers: int = 10000
var capture_requested: bool = false
var diagnostic_progress: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	OS.low_processor_usage_mode = false
	Engine.max_fps = 0
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--short":
			warmup_frames = 15
			sample_frames = 30
		elif argument.begins_with("--only="):
			only_case = argument.trim_prefix("--only=")
		elif argument.begins_with("--warmup="):
			warmup_frames = maxi(int(argument.trim_prefix("--warmup=")), 1)
		elif argument.begins_with("--frames="):
			sample_frames = maxi(int(argument.trim_prefix("--frames=")), 1)
		elif argument.begins_with("--seconds=") or argument.begins_with("--sample-seconds="):
			sample_seconds = maxf(float(argument.get_slice("=", 1)), 0.1)
		elif argument.begins_with("--soldiers="):
			requested_soldiers = int(argument.trim_prefix("--soldiers="))
		elif argument.begins_with("--case-order="):
			for raw_name: String in argument.trim_prefix("--case-order=").split(",", false):
				var name: String = raw_name.strip_edges()
				if not name.is_empty():
					case_order.append(name)
		elif argument.begins_with("--suite="):
			suite = argument.trim_prefix("--suite=")
		elif argument == "--capture":
			capture_requested = true
		elif argument == "--diagnostic-progress":
			diagnostic_progress = true
	if requested_soldiers not in [1000, 5000, 10000]:
		_fail("--soldiers must be 1000, 5000, or 10000")
		return
	if suite not in ["fixed", "legacy", "all"]:
		_fail("--suite must be fixed, legacy, or all")
		return

	var scene: PackedScene = load(ScenePath) as PackedScene
	assert(scene != null, "Formation-Space benchmark scene could not be loaded")
	benchmark = scene.instantiate() as CrowdPromotionBenchmarkController
	assert(benchmark != null, "Formation-Space controller type mismatch")
	get_root().add_child(benchmark)
	benchmark.set_simulation_paused(true)
	await _settle(warmup_frames)
	benchmark.simulation.set_active_soldiers(requested_soldiers)
	print("FORMATION_SPACE_ENV godot=%s renderer=%s driver=%s seed=%d soldiers=%d formations=%d gpu_backend_ready_before_case=%s" % [
		Engine.get_version_info().get("string", "unknown"),
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"),
		RenderingServer.get_video_adapter_name(),
		benchmark.deterministic_seed,
		benchmark.simulation.active_soldier_count,
		benchmark.simulation.active_formation_count,
		str(benchmark.crowd_renderer.formation_gpu_transform_supported())
	])

	var fixed_cases: Array[String] = [
		"A_fixed_0", "B_fixed_0", "C_gpu_fixed_0",
		"A_fixed_64", "B_fixed_64", "C_gpu_fixed_64",
		"A_fixed_max_visible_64", "B_fixed_max_visible_64", "C_gpu_fixed_max_visible_64"
	]
	var legacy_cases: Array[String] = [
		"A_current_0",
		"B_formation_0",
		"C_current_64",
		"D_formation_64",
		"E_formation_camera_64",
		"G_current_max_visible_64",
		"F_formation_max_visible_64"
	]
	var case_names: Array[String] = []
	if suite != "legacy":
		case_names.append_array(fixed_cases)
	if suite != "fixed":
		case_names.append_array(legacy_cases)
	if not case_order.is_empty():
		case_names.clear()
		for name: String in case_order:
			if not fixed_cases.has(name) and not legacy_cases.has(name):
				_fail("Unknown case in --case-order: " + name)
				return
			case_names.append(name)
	elif not only_case.is_empty():
		case_names.clear()
		case_names.append(only_case)
	var occurrences := {}
	for case_index: int in range(case_names.size()):
		var case_name: String = case_names[case_index]
		var occurrence: int = int(occurrences.get(case_name, 0)) + 1
		occurrences[case_name] = occurrence
		var case_ok: bool = await _run_case(case_name, case_index + 1, occurrence)
		if not case_ok:
			benchmark.queue_free()
			await process_frame
			quit(1)
			return
	print("FORMATION_SPACE_BENCHMARK_PASS cases=%d soldiers=%d suite=%s" % [case_names.size(), requested_soldiers, suite])
	benchmark.queue_free()
	await process_frame
	quit(0)

func _run_case(case_name: String, run_index: int, occurrence: int) -> bool:
	var path: int = CrowdRendererType.RenderPath.CURRENT_PER_INSTANCE
	var mode: int = SimulationType.BenchmarkMode.HUMANOID_LOD
	var near_budget: int = 0
	var camera_motion: bool = false
	var camera_position := Vector3(0.0, 16.0, 1.0)
	var camera_target := Vector3.ZERO
	var camera_size: float = 110.0
	match case_name:
		"A_fixed_0", "A_fixed_64", "A_fixed_max_visible_64":
			path = CrowdRendererType.RenderPath.CURRENT_PER_INSTANCE
			mode = SimulationType.BenchmarkMode.HUMANOID_ANIMATED
			near_budget = 64 if case_name.ends_with("64") else 0
		"B_fixed_0", "B_fixed_64", "B_fixed_max_visible_64":
			path = CrowdRendererType.RenderPath.FORMATION_PARENT_TRANSFORM
			mode = SimulationType.BenchmarkMode.HUMANOID_ANIMATED
			near_budget = 64 if case_name.ends_with("64") else 0
		"C_gpu_fixed_0", "C_gpu_fixed_64", "C_gpu_fixed_max_visible_64":
			path = CrowdRendererType.RenderPath.GPU_FORMATION_OUTPUT
			mode = SimulationType.BenchmarkMode.HUMANOID_ANIMATED
			near_budget = 64 if case_name.ends_with("64") else 0
		"A_current_0":
			path = CrowdRendererType.RenderPath.CURRENT_PER_INSTANCE
		"B_formation_0":
			path = CrowdRendererType.RenderPath.FORMATION_PARENT_TRANSFORM
		"C_current_64":
			path = CrowdRendererType.RenderPath.CURRENT_PER_INSTANCE
			near_budget = 64
		"D_formation_64":
			path = CrowdRendererType.RenderPath.FORMATION_PARENT_TRANSFORM
			near_budget = 64
		"E_formation_camera_64":
			path = CrowdRendererType.RenderPath.FORMATION_PARENT_TRANSFORM
			near_budget = 64
			camera_motion = true
		"F_formation_max_visible_64":
			path = CrowdRendererType.RenderPath.FORMATION_PARENT_TRANSFORM
			near_budget = 64
			camera_position = Vector3(0.0, 16.0, 1.0)
			camera_size = 350.0
		"G_current_max_visible_64":
			path = CrowdRendererType.RenderPath.CURRENT_PER_INSTANCE
			near_budget = 64
			camera_position = Vector3(0.0, 16.0, 1.0)
			camera_size = 350.0
		_:
			_fail("Unknown Formation-Space case: %s" % case_name)
			return false
	if case_name.contains("max_visible"):
		camera_size = 350.0

	benchmark.set_special_render_mode(SpecialRenderModeType.Mode.SKINNED_BUNDLE)
	benchmark.reset_deterministic_state()
	benchmark.benchmark_fixed_delta = 1.0 / 60.0 if case_name.contains("_fixed_") else -1.0
	benchmark.set_crowd_render_path(path)
	benchmark.set_crowd_mode(mode)
	benchmark.simulation.set_active_soldiers(requested_soldiers)
	benchmark.crowd_renderer.invalidate_layout()
	if requested_soldiers < 10000:
		var active_rows: int = ceili(float(benchmark.simulation.active_formation_count) / 10.0)
		var focus_row: int = floori(float(active_rows - 1) * 0.5)
		var focus_id: int = focus_row * 10 + 4
		var focus: Vector3 = benchmark.simulation.formations[focus_id].center_position
		camera_position = focus + Vector3(0.0, 16.0, 1.0)
		camera_target = focus
	benchmark.set_near_actor_budget(near_budget)
	benchmark.set_near_render_options(true, true, true, 1)
	benchmark.set_deterministic_camera_motion(camera_motion)
	benchmark.set_camera_state(camera_position, camera_target, camera_size)
	benchmark.set_simulation_paused(false)
	await _settle(warmup_frames)
	# Complete two full, untimed frames on every path so the main thread can
	# observe a committed GPU packet and retire its temporary B bridge.
	for sync_frame: int in range(2):
		await process_frame
		await RenderingServer.frame_post_draw
	if benchmark.crowd_renderer.render_path != path:
		_fail("Render path fallback invalidated case %s" % case_name)
		return false
	if path == CrowdRendererType.RenderPath.GPU_FORMATION_OUTPUT:
		var admission: Dictionary = benchmark.crowd_renderer.crowd_gpu_status()
		var expected_batches: int = SimulationType.FORMATION_COUNT
		var bridge_batches: Array = benchmark.crowd_renderer.get("_formation_batches")
		if benchmark.crowd_renderer.render_path_name() != "GPU_FORMATION_OUTPUT" or (
			int(admission.get("batch_count", -1)) != expected_batches
			or int(admission.get("ready_batches", -1)) != expected_batches
			or int(admission.get("completed_frames", 0)) <= 0
			or not str(admission.get("error", "")).is_empty()
			or benchmark.crowd_renderer.formation_batch_node_count != 0
			or not bridge_batches.is_empty()
		):
			_fail("GPU case %s not admitted after warmup: status=%s B_nodes=%d path=%s" % [
				case_name, admission, bridge_batches.size(), benchmark.crowd_renderer.render_path_name()
			])
			return false
		print("FORMATION_SPACE_GPU_ADMISSION case=%s completed=%d ready_batches=%d B_nodes=0" % [
			case_name, int(admission.get("completed_frames", 0)), expected_batches
		])
	if capture_requested:
		var capture_path: String = "res://.visual_captures/formation_space/%02d_%s_%d.png" % [
			run_index, case_name, requested_soldiers
		]
		if not benchmark.capture_view(capture_path):
			_fail("Formation-Space capture could not be saved: " + capture_path)
			return false
		print("FORMATION_SPACE_CAPTURE_PASS path=%s" % ProjectSettings.globalize_path(capture_path))
	if diagnostic_progress:
		benchmark.benchmark_stage_trace = true
		_print_progress(case_name, "before_begin", 0)
	benchmark.begin_measurement()
	if diagnostic_progress:
		_print_progress(case_name, "after_begin", 0)
	var wall_started_usec: int = Time.get_ticks_usec()
	var sampled_frames: int = 0
	if sample_seconds > 0.0:
		while float(Time.get_ticks_usec() - wall_started_usec) < sample_seconds * 1000000.0:
			await process_frame
			sampled_frames += 1
			if diagnostic_progress and (sampled_frames <= 3 or sampled_frames % 10 == 0):
				_print_progress(case_name, "sample", sampled_frames)
	else:
		for frame: int in range(sample_frames):
			await process_frame
			sampled_frames = frame + 1
			if diagnostic_progress and (sampled_frames <= 3 or sampled_frames % 10 == 0):
				_print_progress(case_name, "sample", sampled_frames)
	var wall_seconds: float = float(Time.get_ticks_usec() - wall_started_usec) / 1000000.0
	if diagnostic_progress:
		_print_progress(case_name, "before_end", sampled_frames)
	var result: Dictionary = benchmark.end_measurement()
	if diagnostic_progress:
		_print_progress(case_name, "after_end", sampled_frames)
		benchmark.benchmark_stage_trace = false
	result["wall_seconds"] = wall_seconds
	result["wall_fps"] = float(result.get("frames", 0)) / maxf(wall_seconds, 0.001)
	result["frame_intervals_ms"] = benchmark.sample_frame_times.duplicate()
	var sorted_intervals: Array[float] = benchmark.sample_frame_times.duplicate()
	sorted_intervals.sort()
	result["p50_frame_ms"] = _percentile(sorted_intervals, 0.50)
	result["p99_frame_ms"] = _percentile(sorted_intervals, 0.99)
	result["max_frame_ms"] = sorted_intervals[sorted_intervals.size() - 1] if not sorted_intervals.is_empty() else 0.0
	if not result.has("render_thread_ms"):
		result["render_thread_ms"] = null
	if not result.has("gpu_ms"):
		result["gpu_ms"] = null
	result["soldiers"] = benchmark.simulation.active_soldier_count
	result["run_index"] = run_index
	result["case_occurrence"] = occurrence
	result["seed"] = benchmark.deterministic_seed
	result["mode"] = "HUMANOID_ANIMATED_FIXED_MID" if mode == SimulationType.BenchmarkMode.HUMANOID_ANIMATED else "HUMANOID_LOD"
	result["simulation_step_seconds"] = benchmark.benchmark_fixed_delta if benchmark.benchmark_fixed_delta > 0.0 else null
	result["visible_count_basis"] = "renderer_frustum_estimate"
	result["camera_position"] = [camera_position.x, camera_position.y, camera_position.z]
	result["camera_target"] = [camera_target.x, camera_target.y, camera_target.z]
	result["camera_orthographic_size"] = camera_size
	result["environment"] = {
		"godot": Engine.get_version_info().get("string", "unknown"),
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"),
		"adapter": RenderingServer.get_video_adapter_name(),
		"window": [1600, 900],
		"vsync": "disabled"
	}
	_print_result(case_name, result)
	print("FORMATION_SPACE_JSON " + JSON.stringify({
		"case": case_name, "run_index": run_index, "case_occurrence": occurrence, "result": result
	}))
	var active_near: int = int(result.get("active_near", -1))
	var proxies: int = int(result.get("crowd_instances", -1))
	if active_near != near_budget or proxies + active_near != benchmark.simulation.active_soldier_count:
		_fail("Population mismatch in %s: proxies=%d near=%d total=%d" % [
			case_name, proxies, active_near, benchmark.simulation.active_soldier_count
		])
		return false
	print("FORMATION_SPACE_CONTRACT case=%s path=%s soldiers=%d formations=%d near=%d stable_slots=true promotion_mask=true gpu_animation=true" % [
		case_name,
		result.get("render_path", "N/A"),
		benchmark.simulation.active_soldier_count,
		benchmark.simulation.active_formation_count,
		int(result.get("near", 0.0))
	])
	return true

func _print_result(case_name: String, result: Dictionary) -> void:
	var fields := PackedStringArray([
		"case=" + case_name,
		"run_index=" + _str_int(result.get("run_index", 0)),
		"occurrence=" + _str_int(result.get("case_occurrence", 0)),
		"path=" + str(result.get("render_path", "N/A")),
		"near=" + _str_int(result.get("near", 0.0)),
		"frames=" + _str_int(result.get("frames", 0)),
		"fps=" + _str_num(result.get("fps", 0.0)),
		"wall_fps=" + _str_num(result.get("wall_fps", 0.0)),
		"frame_ms=" + _str_num(result.get("frame_ms", 0.0)),
		"p50_frame_ms=" + _str_num(result.get("p50_frame_ms", 0.0)),
		"p95_frame_ms=" + _str_num(result.get("p95_frame_ms", 0.0)),
		"p99_frame_ms=" + _str_num(result.get("p99_frame_ms", 0.0)),
		"max_frame_ms=" + _str_num(result.get("max_frame_ms", 0.0)),
		"worst_frame_ms=" + _str_num(result.get("worst_frame_ms", 0.0)),
		"simulation_ms=" + _str_num(result.get("simulation_ms", 0.0)),
		"renderer_ms=" + _str_num(result.get("renderer_ms", 0.0)),
		"crowd_loop_ms=" + _str_num(result.get("gdscript_crowd_loop_cpu_ms", 0.0)),
		"formation_loop_ms=" + _str_num(result.get("formation_transform_cpu_ms", 0.0)),
		"transform_prep_ms=" + _str_num(result.get("transform_preparation_cpu_ms", -1.0)),
		"simulation_world_position_updates=" + _str_num(result.get("simulation_world_position_updates", 0.0), 1),
		"lazy_world_position_queries=" + _str_num(result.get("lazy_world_position_queries", 0.0), 1),
		"simulation_formation_updates=" + _str_num(result.get("simulation_formation_updates", 0.0), 1),
		"basis_constructions=" + _str_num(result.get("simulation_basis_constructions", 0.0), 1),
		"formation_transform_updates=" + _str_num(result.get("formation_transform_updates", 0.0), 1),
		"instance_transform_updates=" + _str_num(result.get("instance_transform_updates", 0.0), 1),
		"instance_transform_constructions=" + _str_num(result.get("instance_transform_constructions", 0.0), 1),
		"instance_basis_constructions=" + _str_num(result.get("instance_basis_constructions", 0.0), 1),
		"set_instance_transform_calls=" + _str_num(result.get("updated_transform_instances", 0.0), 1),
		"formation_custom_updates=" + _str_num(result.get("formation_custom_data_updates", 0.0), 1),
		"slot_rebuilds=" + _str_num(result.get("formation_slot_rebuilds", 0.0), 1),
		"slot_transform_writes=" + _str_num(result.get("formation_slot_transform_writes", 0.0), 1),
		"structural_changes=" + _str_num(result.get("formation_structural_changes", 0.0), 1),
		"batch_nodes=" + _str_int(result.get("formation_batch_nodes", 0)),
		"formation_culling=" + str(result.get("formation_culling", "N/A")),
		"visible_formations=" + _str_num(result.get("visible_formations", 0.0), 1),
		"draw_calls=" + _str_int(result.get("draw_calls", 0)),
		"multimesh_count=" + _str_int(result.get("crowd_groups", 0)),
		"visible_soldiers=" + _str_num(result.get("visible_soldiers", 0.0), 1),
		"visible_chunks=" + _str_num(result.get("visible_chunks", 0.0), 1),
		"crowd_instances=" + _str_int(result.get("crowd_instances", 0)),
		"promotions_sec=" + _str_num(result.get("promotions_per_second", 0.0), 1),
		"demotions_sec=" + _str_num(result.get("demotions_per_second", 0.0), 1)
	])
	print("FORMATION_SPACE_RESULT " + " ".join(fields))

func _str_num(value: Variant, decimals: int = 3) -> String:
	return String.num(float(value), decimals)

func _str_int(value: Variant) -> String:
	return str(int(value))

func _percentile(sorted_values: Array[float], fraction: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index: int = clampi(ceili(float(sorted_values.size()) * fraction) - 1, 0, sorted_values.size() - 1)
	return sorted_values[index]

func _settle(frame_count: int) -> void:
	for _frame: int in range(frame_count):
		await process_frame

func _print_progress(case_name: String, phase: String, frame: int) -> void:
	var gpu: Dictionary = benchmark.crowd_renderer.crowd_gpu_status()
	print("FORMATION_SPACE_PROGRESS case=%s phase=%s frame=%d frame_ms=%.3f renderer_ms=%.3f pool_ms=%.3f near=%d gpu_completed=%d gpu_error=%s" % [
		case_name, phase, frame, benchmark.last_frame_ms, benchmark.last_renderer_ms,
		benchmark.last_pool_ms, benchmark.actor_pool.active_actor_count,
		int(gpu.get("completed_frames", -1)), str(gpu.get("error", ""))
	])

func _fail(message: String) -> void:
	push_error(message)
	print("FORMATION_SPACE_BENCHMARK_FAIL " + message)
	quit(1)
