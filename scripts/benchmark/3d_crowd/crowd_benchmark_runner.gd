extends SceneTree

const SimulationType = preload("res://scripts/benchmark/3d_crowd/battle_crowd_simulation.gd")
const ControllerType = preload("res://scripts/benchmark/3d_crowd/crowd_benchmark_controller.gd")
const RendererType = preload("res://scripts/benchmark/3d_crowd/crowd_renderer_3d.gd")

const SCENE_PATH: String = "res://scenes/benchmark/3d_crowd/CrowdBenchmark3D.tscn"
const CLOSE_CAPTURE_PATH: String = "res://.visual_captures/soldier_visual_benchmark_3d/soldier_visual_close.png"
const FULL_CAPTURE_PATH: String = "res://.visual_captures/soldier_visual_benchmark_3d/soldier_visual_full.png"
const WARMUP_FRAMES: int = 60
const SAMPLE_FRAMES: int = 180
const COUNTS: Array[int] = [1000, 2500, 5000, 10000]
const MODES: Array[int] = [
	SimulationType.BenchmarkMode.HUMANOID_STATIC,
	SimulationType.BenchmarkMode.HUMANOID_ANIMATED,
	SimulationType.BenchmarkMode.HUMANOID_LOD
]

var benchmark: CrowdBenchmarkController

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	OS.low_processor_usage_mode = false
	Engine.max_fps = 0
	var scene: PackedScene = load(SCENE_PATH) as PackedScene
	assert(scene != null, "Soldier visual benchmark scene could not be loaded")
	benchmark = scene.instantiate() as CrowdBenchmarkController
	assert(benchmark != null, "Soldier visual benchmark root type mismatch")
	get_root().add_child(benchmark)
	await _settle(45)

	if OS.get_cmdline_user_args().has("--soldier-visual-capture"):
		benchmark.set_soldier_count(10000)
		benchmark.set_benchmark_mode(SimulationType.BenchmarkMode.HUMANOID_LOD)
		benchmark.set_near_actor_budget(64)
		benchmark.set_camera_state(Vector3(17.0, 20.0, 17.0), Vector3(17.0, 0.0, 17.0), 28.0)
		await _settle(90)
		assert(benchmark.capture_view(CLOSE_CAPTURE_PATH), "Close soldier visual capture could not be saved")
		benchmark.set_camera_state(Vector3(180.0, 230.0, 210.0), Vector3.ZERO, 350.0)
		await _settle(90)
		assert(benchmark.capture_view(FULL_CAPTURE_PATH), "Full soldier visual capture could not be saved")
		print("SOLDIER_VISUAL_CAPTURE_PASS close=%s full=%s" % [
			ProjectSettings.globalize_path(CLOSE_CAPTURE_PATH),
			ProjectSettings.globalize_path(FULL_CAPTURE_PATH)
		])
		quit(0)
		return

	print("SOLDIER_VISUAL_ENV: godot=%s renderer=%s driver=%s seed=%d chunk_size=%.0f near=%.0f mid=%.0f far=%.0f" % [
		Engine.get_version_info().get("string", "unknown"),
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"),
		RenderingServer.get_video_adapter_name(),
		benchmark.simulation.seed,
		RendererType.CROWD_CHUNK_SIZE,
		RendererType.LOD_NEAR_DISTANCE,
		RendererType.LOD_MID_DISTANCE,
		RendererType.LOD_FAR_DISTANCE
	])
	var mid_triangle_counts: Array[int] = []
	var far_triangle_counts: Array[int] = []
	for spec: SoldierVisualArchetype in benchmark.crowd_renderer.registry.entries:
		mid_triangle_counts.append(_triangle_count(spec.mid_mesh))
		far_triangle_counts.append(_triangle_count(spec.far_mesh))
	print("SOLDIER_VISUAL_ASSETS: mid_triangles=%s far_triangles=%s placeholder_triangles=%d crowd_materials=%d near_materials=%d" % [
		str(mid_triangle_counts),
		str(far_triangle_counts),
		_triangle_count(benchmark.crowd_renderer.registry.placeholder_mesh),
		benchmark.crowd_renderer.crowd_material_count(),
		benchmark.crowd_renderer.near_material_count()
	])

	var targeted_case: String = _argument_value("--crowd-case=")
	if not targeted_case.is_empty():
		await _run_targeted_case(targeted_case)
		benchmark.queue_free()
		await process_frame
		quit(0)
		return

	# Matrix camera: close enough to exercise Mid/Far classification while keeping all counts visible.
	benchmark.set_camera_state(Vector3(80.0, 120.0, 100.0), Vector3.ZERO, 320.0)
	var case_count: int = 0
	for mode: int in MODES:
		benchmark.set_near_actor_budget(64 if mode == SimulationType.BenchmarkMode.HUMANOID_LOD else 0)
		for soldier_count: int in COUNTS:
			benchmark.set_soldier_count(soldier_count)
			benchmark.set_benchmark_mode(mode)
			await _settle(WARMUP_FRAMES)
			benchmark.begin_measurement()
			await _settle(SAMPLE_FRAMES)
			var result: Dictionary = benchmark.end_measurement()
			var result_format: String = (
				"SOLDIER_VISUAL_RESULT mode=%s soldiers=%d formations=%d frames=%d "
				+ "fps=%.3f frame_ms=%.3f worst_frame_ms=%.3f simulation_ms=%.3f renderer_ms=%.3f "
				+ "near_actor_cpu_ms=%.3f near=%.1f mid=%.1f far=%.1f "
				+ "skeletons=%.1f animation_players=%.1f multimesh_groups=%.1f multimesh_instances=%.1f "
				+ "visible_chunks=%.1f visible_soldiers=%.1f draw_calls=%d triangles=%d"
			)
			print(result_format % [
					result.mode,
					result.soldiers,
					result.formations,
					result.frames,
					result.fps,
					result.frame_ms,
					result.worst_frame_ms,
					result.simulation_ms,
					result.renderer_ms,
					result.near_actor_cpu_ms,
					result.near,
					result.mid,
					result.far,
					result.skeletons,
					result.animation_players,
					result.multimesh_groups,
					result.multimesh_instances,
					result.visible_chunks,
					result.visible_soldiers,
					result.draw_calls,
					result.triangles
			])
			case_count += 1
			await process_frame

	# Near actor budget sweep is deliberately run in increasing pool sizes so allocation is visible.
	benchmark.set_soldier_count(10000)
	benchmark.set_benchmark_mode(SimulationType.BenchmarkMode.HUMANOID_LOD)
	benchmark.set_camera_state(Vector3(0.0, 20.0, 0.0), Vector3.ZERO, 110.0)
	for near_budget: int in [0, 64, 128, 256]:
		benchmark.set_near_actor_budget(near_budget)
		await _settle(WARMUP_FRAMES)
		benchmark.begin_measurement()
		await _settle(SAMPLE_FRAMES)
		var near_result: Dictionary = benchmark.end_measurement()
		var near_result_format: String = (
			"SOLDIER_NEAR_RESULT max_full_actors=%d soldiers=%d frames=%d "
			+ "fps=%.3f frame_ms=%.3f worst_frame_ms=%.3f near_actor_cpu_ms=%.3f "
			+ "near=%.1f skeletons=%.1f animation_players=%.1f"
		)
		print(near_result_format % [
				near_budget,
				near_result.soldiers,
				near_result.frames,
				near_result.fps,
				near_result.frame_ms,
				near_result.worst_frame_ms,
				near_result.near_actor_cpu_ms,
				near_result.near,
				near_result.skeletons,
				near_result.animation_players
		])
		case_count += 1
		await process_frame
	print("SOLDIER_VISUAL_BENCHMARK_PASS cases=%d" % case_count)
	benchmark.queue_free()
	await process_frame
	quit(0)

func _settle(frame_count: int) -> void:
	for _frame: int in range(frame_count):
		await process_frame

func _run_targeted_case(case_name: String) -> void:
	var profile: String = _argument_value("--crowd-profile=")
	if profile.is_empty():
		profile = "baseline"
	var short_run: bool = OS.get_cmdline_user_args().has("--crowd-short")
	var warmup_frames: int = 15 if short_run else WARMUP_FRAMES
	var sample_frames: int = 30 if short_run else SAMPLE_FRAMES
	var is_static: bool = case_name.to_lower().begins_with("static")
	var near_budget: int = 64 if case_name.to_lower().contains("64") else 0
	benchmark.reset_deterministic_state()
	benchmark.set_renderer_profile(profile)
	benchmark.set_soldier_count(10000)
	benchmark.set_benchmark_mode(
		SimulationType.BenchmarkMode.HUMANOID_STATIC if is_static else SimulationType.BenchmarkMode.HUMANOID_LOD
	)
	benchmark.set_near_actor_budget(near_budget)
	benchmark.set_deterministic_camera_motion(case_name.to_lower().contains("camera"))
	if case_name.to_lower().contains("max_visible"):
		benchmark.set_camera_state(Vector3(0.0, 20.0, 0.0), Vector3.ZERO, 420.0)
	elif near_budget > 0:
		benchmark.set_camera_state(Vector3(0.0, 20.0, 0.0), Vector3.ZERO, 110.0)
	else:
		benchmark.set_camera_state(Vector3(80.0, 120.0, 100.0), Vector3.ZERO, 320.0)
	await _settle(warmup_frames)
	benchmark.begin_measurement()
	await _settle(sample_frames)
	var result: Dictionary = benchmark.end_measurement()
	print(
		("CROWD_PERF_RESULT profile=%s case=%s mode=%s soldiers=%d near=%d frames=%d "
		+ "fps=%.3f frame_ms=%.3f worst_frame_ms=%.3f simulation_ms=%.3f renderer_ms=%.3f "
		+ "near_actor_cpu_ms=%.3f multimesh_upload_cpu_ms=%.3f buffer_prepare_ms=%.3f "
		+ "visible_chunks=%.1f visible_soldiers=%.1f dirty_chunks=%.1f "
		+ "transform_dirty=%.1f animation_dirty=%.1f visual_dirty=%.1f structural_changes=%.1f "
		+ "chunk_migrations=%.1f upload_calls=%.1f bulk_upload_calls=%.1f instances_uploaded=%.1f bytes_uploaded=%.1f "
		+ "draw_calls=%d triangles=%d profile_name=%s") % [
			profile,
			case_name,
			result.mode,
			result.soldiers,
			near_budget,
			result.frames,
			result.fps,
			result.frame_ms,
			result.worst_frame_ms,
			result.simulation_ms,
			result.renderer_ms,
			result.near_actor_cpu_ms,
			result.multimesh_upload_cpu_ms,
			result.buffer_prepare_cpu_ms,
			result.visible_chunks,
			result.visible_soldiers,
			result.dirty_chunks,
			result.transform_dirty_instances,
			result.animation_dirty_instances,
			result.visual_dirty_instances,
			result.structural_changes,
			result.chunk_migrations,
			result.upload_calls,
			result.bulk_upload_calls,
			result.instances_uploaded,
			result.bytes_uploaded,
			result.draw_calls,
			result.triangles,
			result.update_profile
		]
	)

func _argument_value(prefix: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.substr(prefix.length())
	return ""

func _triangle_count(mesh: Mesh) -> int:
	var triangle_count: int = 0
	for surface_index: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var index_data: Variant = arrays[Mesh.ARRAY_INDEX]
		if index_data is PackedInt32Array and not (index_data as PackedInt32Array).is_empty():
			var indices: PackedInt32Array = index_data
			triangle_count += indices.size() / 3
		else:
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			triangle_count += vertices.size() / 3
	return triangle_count
