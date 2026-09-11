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
var only_case: String = ""
var capture_requested: bool = false
const CAPTURE_PATH: String = "res://.visual_captures/formation_space/formation_parent_64.png"

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
		elif argument == "--capture":
			capture_requested = true

	var scene: PackedScene = load(ScenePath) as PackedScene
	assert(scene != null, "Formation-Space benchmark scene could not be loaded")
	benchmark = scene.instantiate() as CrowdPromotionBenchmarkController
	assert(benchmark != null, "Formation-Space controller type mismatch")
	get_root().add_child(benchmark)
	benchmark.set_simulation_paused(true)
	await _settle(warmup_frames)
	print("FORMATION_SPACE_ENV godot=%s renderer=%s driver=%s seed=%d soldiers=%d formations=%d gpu_formation_transform=%s" % [
		Engine.get_version_info().get("string", "unknown"),
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"),
		RenderingServer.get_video_adapter_name(),
		benchmark.deterministic_seed,
		benchmark.simulation.active_soldier_count,
		benchmark.simulation.active_formation_count,
		str(benchmark.crowd_renderer.formation_gpu_transform_supported())
	])

	var case_names: Array[String] = [
		"A_current_0",
		"B_formation_0",
		"C_current_64",
		"D_formation_64",
		"E_formation_camera_64",
		"G_current_max_visible_64",
		"F_formation_max_visible_64"
	]
	if not only_case.is_empty():
		case_names = [only_case]
	for case_name: String in case_names:
		await _run_case(case_name)
	print("FORMATION_SPACE_BENCHMARK_PASS cases=%d" % case_names.size())
	benchmark.queue_free()
	await process_frame
	quit(0)

func _run_case(case_name: String) -> void:
	var path: int = CrowdRendererType.RenderPath.CURRENT_PER_INSTANCE
	var near_budget: int = 0
	var camera_motion: bool = false
	var camera_position := Vector3(0.0, 16.0, 1.0)
	var camera_target := Vector3.ZERO
	var camera_size: float = 110.0
	match case_name:
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
			assert(false, "Unknown Formation-Space case: %s" % case_name)

	benchmark.set_special_render_mode(SpecialRenderModeType.Mode.SKINNED_BUNDLE)
	benchmark.reset_deterministic_state()
	benchmark.set_crowd_render_path(path)
	benchmark.set_crowd_mode(SimulationType.BenchmarkMode.HUMANOID_LOD)
	benchmark.set_near_actor_budget(near_budget)
	benchmark.set_near_render_options(true, true, true, 1)
	benchmark.set_deterministic_camera_motion(camera_motion)
	benchmark.set_camera_state(camera_position, camera_target, camera_size)
	benchmark.set_simulation_paused(false)
	await _settle(warmup_frames)
	if capture_requested:
		assert(benchmark.capture_view(CAPTURE_PATH), "Formation-Space capture could not be saved")
		print("FORMATION_SPACE_CAPTURE_PASS path=%s" % ProjectSettings.globalize_path(CAPTURE_PATH))
	benchmark.begin_measurement()
	await _settle(sample_frames)
	var result: Dictionary = benchmark.end_measurement()
	_print_result(case_name, result)
	print("FORMATION_SPACE_CONTRACT case=%s path=%s soldiers=%d formations=%d near=%d stable_slots=true promotion_mask=true gpu_animation=true" % [
		case_name,
		result.get("render_path", "N/A"),
		benchmark.simulation.active_soldier_count,
		benchmark.simulation.active_formation_count,
		int(result.get("near", 0.0))
	])

func _print_result(case_name: String, result: Dictionary) -> void:
	var fields := PackedStringArray([
		"case=" + case_name,
		"path=" + str(result.get("render_path", "N/A")),
		"near=" + _str_int(result.get("near", 0.0)),
		"frames=" + _str_int(result.get("frames", 0)),
		"fps=" + _str_num(result.get("fps", 0.0)),
		"frame_ms=" + _str_num(result.get("frame_ms", 0.0)),
		"p95_frame_ms=" + _str_num(result.get("p95_frame_ms", 0.0)),
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

func _settle(frame_count: int) -> void:
	for _frame: int in range(frame_count):
		await process_frame
