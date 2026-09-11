extends SceneTree

const SimulationType = preload("res://scripts/benchmark/3d_crowd/battle_crowd_simulation.gd")
const ControllerType = preload("res://scripts/benchmark/3d_crowd_promotion/crowd_promotion_benchmark_controller.gd")
const ScenePath: String = "res://scenes/benchmark/3d_crowd_promotion/CrowdPromotionBenchmark3D.tscn"
const WARMUP_FRAMES: int = 30
const SAMPLE_FRAMES: int = 120
const BUDGETS: Array[int] = [0, 16, 32, 64, 128]

var benchmark: CrowdPromotionBenchmarkController
var phase_name: String = "baseline"
var warmup_frame_count: int = WARMUP_FRAMES
var sample_frame_count: int = SAMPLE_FRAMES
var only_case: String = ""

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	OS.low_processor_usage_mode = false
	Engine.max_fps = 0
	phase_name = "after" if OS.get_cmdline_user_args().has("--after") else "baseline"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			only_case = argument.trim_prefix("--case=")
	if OS.get_cmdline_user_args().has("--short"):
		warmup_frame_count = 15
		sample_frame_count = 30

	var scene: PackedScene = load(ScenePath) as PackedScene
	assert(scene != null, "Crowd performance scene could not be loaded")
	benchmark = scene.instantiate() as CrowdPromotionBenchmarkController
	assert(benchmark != null, "Crowd performance controller type mismatch")
	get_root().add_child(benchmark)
	benchmark.set_simulation_paused(true)
	await _settle(warmup_frame_count)

	print("CROWD_PERF_ENV phase=%s godot=%s renderer=%s driver=%s seed=%d soldiers=%d pool_capacity=%d pool_init_ms=%.3f" % [
		phase_name,
		Engine.get_version_info().get("string", "unknown"),
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"),
		RenderingServer.get_video_adapter_name(),
		benchmark.deterministic_seed,
		benchmark.simulation.active_soldier_count,
		benchmark.actor_pool.capacity,
		benchmark.actor_pool.initialization_cpu_ms
	])
	if not only_case.is_empty():
		var single_result: Dictionary = await _run_named_case(only_case)
		_print_result(single_result)
		print("CROWD_PERF_BENCHMARK_PASS phase=%s cases=1" % phase_name)
		benchmark.queue_free()
		await process_frame
		quit(0)
		return

	for budget: int in BUDGETS:
		if budget == 128 and OS.get_cmdline_user_args().has("--skip128"):
			continue
		var moving_result: Dictionary = await _run_case(
			"moving_near_%d" % budget,
			budget,
			SimulationType.BenchmarkMode.HUMANOID_LOD,
			false,
			true,
			true,
			true,
			1,
			Vector3(0.0, 16.0, 1.0),
			Vector3.ZERO,
			110.0
		)
		_print_result(moving_result)

	var static_result: Dictionary = await _run_case(
		"static_near_64",
		64,
		SimulationType.BenchmarkMode.HUMANOID_STATIC,
		true,
		true,
		true,
		true,
		1,
		Vector3(0.0, 16.0, 1.0),
		Vector3.ZERO,
		110.0
	)
	_print_result(static_result)

	var animation_off_result: Dictionary = await _run_case(
		"moving_near_64_animation_off",
		64,
		SimulationType.BenchmarkMode.HUMANOID_LOD,
		false,
		false,
		true,
		true,
		1,
		Vector3(0.0, 16.0, 1.0),
		Vector3.ZERO,
		110.0
	)
	_print_result(animation_off_result)

	var equipment_off_result: Dictionary = await _run_case(
		"moving_near_64_equipment_hidden",
		64,
		SimulationType.BenchmarkMode.HUMANOID_LOD,
		false,
		true,
		false,
		true,
		1,
		Vector3(0.0, 16.0, 1.0),
		Vector3.ZERO,
		110.0
	)
	_print_result(equipment_off_result)

	var shadows_off_result: Dictionary = await _run_case(
		"moving_near_64_shadows_off",
		64,
		SimulationType.BenchmarkMode.HUMANOID_LOD,
		false,
		true,
		true,
		false,
		1,
		Vector3(0.0, 16.0, 1.0),
		Vector3.ZERO,
		110.0
	)
	_print_result(shadows_off_result)

	var animation_stride_result: Dictionary = await _run_case(
		"moving_near_64_animation_stride_2",
		64,
		SimulationType.BenchmarkMode.HUMANOID_LOD,
		false,
		true,
		true,
		true,
		2,
		Vector3(0.0, 16.0, 1.0),
		Vector3.ZERO,
		110.0
	)
	_print_result(animation_stride_result)

	await _run_promotion_burst()
	print("CROWD_PERF_BENCHMARK_PASS phase=%s cases=%d" % [phase_name, BUDGETS.size() + 5])
	benchmark.queue_free()
	await process_frame
	quit(0)

func _run_case(
	case_name: String,
	budget: int,
	mode: int,
	paused: bool,
	animation_enabled: bool,
	equipment_visible: bool,
	shadows_enabled: bool,
	animation_stride: int,
	camera_position: Vector3,
	camera_target: Vector3,
	orthographic_size: float
) -> Dictionary:
	benchmark.reset_deterministic_state()
	benchmark.set_crowd_mode(mode)
	benchmark.set_near_actor_budget(budget)
	benchmark.set_near_render_options(
		animation_enabled,
		equipment_visible,
		shadows_enabled,
		animation_stride
	)
	benchmark.set_camera_state(camera_position, camera_target, orthographic_size)
	benchmark.set_simulation_paused(paused)
	await _settle(warmup_frame_count)
	benchmark.begin_measurement()
	await _settle(sample_frame_count)
	var result: Dictionary = benchmark.end_measurement()
	result["phase"] = phase_name
	result["case"] = case_name
	result["mode"] = "static" if paused else "moving"
	result["animation_enabled"] = animation_enabled
	result["equipment_visible"] = equipment_visible
	result["shadows_enabled"] = shadows_enabled
	result["animation_stride"] = animation_stride
	return result

func _run_named_case(case_name: String) -> Dictionary:
	match case_name:
		"0", "16", "32", "64", "128":
			var budget: int = int(case_name)
			return await _run_case(
				"moving_near_%d" % budget,
				budget,
				SimulationType.BenchmarkMode.HUMANOID_LOD,
				false, true, true, true, 1,
				Vector3(0.0, 16.0, 1.0), Vector3.ZERO, 110.0
			)
		"static":
			return await _run_case(
				"static_near_64", 64, SimulationType.BenchmarkMode.HUMANOID_STATIC,
				true, true, true, true, 1,
				Vector3(0.0, 16.0, 1.0), Vector3.ZERO, 110.0
			)
		"animation_off":
			return await _run_case(
				"moving_near_64_animation_off", 64, SimulationType.BenchmarkMode.HUMANOID_LOD,
				false, false, true, true, 1,
				Vector3(0.0, 16.0, 1.0), Vector3.ZERO, 110.0
			)
		"equipment_off":
			return await _run_case(
				"moving_near_64_equipment_hidden", 64, SimulationType.BenchmarkMode.HUMANOID_LOD,
				false, true, false, true, 1,
				Vector3(0.0, 16.0, 1.0), Vector3.ZERO, 110.0
			)
		"shadows_off":
			return await _run_case(
				"moving_near_64_shadows_off", 64, SimulationType.BenchmarkMode.HUMANOID_LOD,
				false, true, true, false, 1,
				Vector3(0.0, 16.0, 1.0), Vector3.ZERO, 110.0
			)
		"stride_2":
			return await _run_case(
				"moving_near_64_animation_stride_2", 64, SimulationType.BenchmarkMode.HUMANOID_LOD,
				false, true, true, true, 2,
				Vector3(0.0, 16.0, 1.0), Vector3.ZERO, 110.0
			)
		_:
			assert(false, "Unknown performance case: %s" % case_name)
			return {}

func _run_promotion_burst() -> void:
	benchmark.reset_deterministic_state()
	benchmark.set_crowd_mode(SimulationType.BenchmarkMode.HUMANOID_LOD)
	benchmark.set_near_actor_budget(64)
	benchmark.set_near_render_options(true, true, true, 1)
	benchmark.set_simulation_paused(true)
	benchmark.focus_on_soldier(0, 42.0)
	await _settle(WARMUP_FRAMES)
	var before_promotions: int = benchmark.actor_pool.total_promotions
	var before_demotions: int = benchmark.actor_pool.total_demotions
	benchmark.focus_on_soldier(9999, 42.0)
	await process_frame
	print("CROWD_PERF_PROMOTION_BURST phase=%s promotions=%d demotions=%d transition_ms=%.3f frame_ms=%.3f allocation_count=%d" % [
		phase_name,
		benchmark.actor_pool.total_promotions - before_promotions,
		benchmark.actor_pool.total_demotions - before_demotions,
		benchmark.actor_pool.last_transition_cpu_ms,
		benchmark.last_frame_ms,
		benchmark.actor_pool.allocation_count
	])

func _print_result(result: Dictionary) -> void:
	var stats: Dictionary = result.get("near_render_stats", {})
	var result_format: String = (
		"CROWD_PERF_RESULT phase=%s case=%s mode=%s budget=%d frames=%d "
		+ "fps=%.3f frame_ms=%.3f worst_frame_ms=%.3f "
		+ "simulation_ms=%.3f policy_ms=%.3f pool_ms=%.3f animation_ms=%.3f promotion_ms=%.3f renderer_ms=%.3f "
		+ "near=%.1f draw_calls=%d triangles=%d near_mesh_instances=%d near_surfaces=%d "
		+ "skeletons=%d active_skeletons=%d animation_players=%d active_animation_players=%d "
		+ "skinned_meshes=%d materials=%d "
		+ "crowd_instances=%d visible_chunks=%.1f visible_crowd_instances=%.1f visible_soldiers=%.1f "
		+ "updated_chunks=%.1f updated_transforms=%.1f updated_custom=%.1f "
		+ "promotions_per_frame=%.3f demotions_per_frame=%.3f animation_enabled=%s equipment_visible=%s shadows_enabled=%s stride=%d"
	)
	print(result_format % [
			result.phase,
			result.case,
			result.mode,
			int(result.get("near", 0.0)),
			result.frames,
			result.fps,
			result.frame_ms,
			result.worst_frame_ms,
			result.simulation_ms,
			result.policy_ms,
			result.pool_ms,
			result.animation_ms,
			result.promotion_ms,
			result.renderer_ms,
			result.near,
			result.draw_calls,
			result.triangles,
			int(stats.get("mesh_instances", 0)),
			int(stats.get("surfaces", 0)),
			result.allocated_skeletons,
			result.active_skeletons,
			result.allocated_animation_players,
			result.active_animation_players,
			int(stats.get("skinned_meshes", 0)),
			int(stats.get("materials", 0)),
			result.crowd_instances,
			result.visible_chunks,
			result.visible_crowd_instances,
			result.visible_soldiers,
			result.updated_chunks,
			result.updated_transform_instances,
			result.updated_custom_instances,
			result.promotions_per_frame,
			result.demotions_per_frame,
			str(result.animation_enabled),
			str(result.equipment_visible),
			str(result.shadows_enabled),
			result.animation_stride
		]
	)

func _settle(frame_count: int) -> void:
	for _frame: int in range(frame_count):
		await process_frame
