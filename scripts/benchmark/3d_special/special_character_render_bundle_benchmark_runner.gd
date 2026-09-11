extends SceneTree

const SimulationType = preload("res://scripts/benchmark/3d_crowd/battle_crowd_simulation.gd")
const RenderModeType = preload("res://scripts/benchmark/3d_special/special_character_render_mode.gd")
const ControllerType = preload("res://scripts/benchmark/3d_crowd_promotion/crowd_promotion_benchmark_controller.gd")
const ShadowBudgetType = preload("res://scripts/benchmark/3d_special/special_shadow_budget.gd")
const ScenePath: String = "res://scenes/benchmark/3d_special_render_bundle/SpecialCharacterRenderBundleBenchmark3D.tscn"
const WARMUP_FRAMES: int = 45
const SAMPLE_FRAMES: int = 120
const SHORT_WARMUP_FRAMES: int = 15
const SHORT_SAMPLE_FRAMES: int = 30
const CAPTURE_PATH: String = "res://.visual_captures/special_character_render_bundle/special_character_render_bundle_64.png"

var benchmark: CrowdPromotionBenchmarkController
var warmup_frames: int = WARMUP_FRAMES
var sample_frames: int = SAMPLE_FRAMES
var only_case: String = ""
var print_breakdown_after_case: bool = false
var capture_requested: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	OS.low_processor_usage_mode = false
	Engine.max_fps = 0
	if OS.get_cmdline_user_args().has("--short"):
		warmup_frames = SHORT_WARMUP_FRAMES
		sample_frames = SHORT_SAMPLE_FRAMES
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):
			only_case = argument.trim_prefix("--only=")
		elif argument.begins_with("--warmup="):
			warmup_frames = maxi(int(argument.trim_prefix("--warmup=")), 1)
		elif argument.begins_with("--frames="):
			sample_frames = maxi(int(argument.trim_prefix("--frames=")), 1)
		elif argument == "--breakdown":
			print_breakdown_after_case = true
		elif argument == "--capture":
			capture_requested = true
	var scene: PackedScene = load(ScenePath) as PackedScene
	assert(scene != null, "RenderBundle benchmark scene could not be loaded")
	benchmark = scene.instantiate() as CrowdPromotionBenchmarkController
	assert(benchmark != null, "RenderBundle benchmark controller type mismatch")
	get_root().add_child(benchmark)
	benchmark.set_simulation_paused(true)
	await _settle(warmup_frames)
	print("SPECIAL_BUNDLE_ENV godot=%s renderer=%s driver=%s seed=%d soldiers=%d pool_capacity=%d bundle_entries=%d bundle_builds=%d" % [
		Engine.get_version_info().get("string", "unknown"),
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"),
		RenderingServer.get_video_adapter_name(), benchmark.deterministic_seed,
		benchmark.simulation.active_soldier_count, benchmark.actor_pool.capacity,
		benchmark.actor_pool.render_bundle_cache.bundle_count(),
		benchmark.actor_pool.render_bundle_cache.build_count
	])
	if capture_requested:
		benchmark.reset_deterministic_state()
		benchmark.set_near_actor_budget(64)
		benchmark.set_special_render_mode(RenderModeType.Mode.SKINNED_BUNDLE)
		benchmark.set_near_render_options(true, true, true, 1)
		benchmark.set_simulation_paused(true)
		benchmark.focus_on_soldier(0, 14.0)
		await _settle(30)
		assert(benchmark.capture_view(CAPTURE_PATH), "RenderBundle capture could not be saved")
		print("SPECIAL_BUNDLE_CAPTURE_PASS path=%s" % ProjectSettings.globalize_path(CAPTURE_PATH))
		benchmark.queue_free()
		await process_frame
		quit(0)
		return
	if not only_case.is_empty():
		await _run_named_case(only_case)
		if print_breakdown_after_case:
			_print_breakdown(RenderModeType.name_for(benchmark.special_render_mode))
		print("SPECIAL_BUNDLE_BENCHMARK_PASS cases=1")
		benchmark.queue_free()
		await process_frame
		quit(0)
		return

	var case_count := 0
	case_count += await _run_configured_case("A_current_bundle_64", 64, false, false, ShadowBudgetType.Mode.ALL, false)
	case_count += await _run_configured_case("B_shared_rigid_resources_64", 64, false, false, ShadowBudgetType.Mode.ALL, false)
	case_count += await _run_configured_case("C_rigid_batch_64", 64, true, false, ShadowBudgetType.Mode.ALL, false)
	case_count += await _run_configured_case("D_material_consolidated_64", 64, false, true, ShadowBudgetType.Mode.ALL, false)
	case_count += await _run_configured_case("E_shadow_body_bundle_64", 64, false, false, ShadowBudgetType.Mode.BODY_BUNDLE_ONLY, false)
	case_count += await _run_configured_case("F_combined_64", 64, true, true, ShadowBudgetType.Mode.BODY_BUNDLE_ONLY, false)
	case_count += await _run_configured_case("G_combined_camera_64", 64, true, true, ShadowBudgetType.Mode.DISTANCE_BUDGETED, true)
	for budget: int in [16, 32, 128]:
		case_count += await _run_configured_case("baseline_%d" % budget, budget, false, false, ShadowBudgetType.Mode.ALL, false)
		case_count += await _run_configured_case("combined_%d" % budget, budget, true, true, ShadowBudgetType.Mode.BODY_BUNDLE_ONLY, false)

	print("SPECIAL_BUNDLE_BENCHMARK_PASS cases=%d" % case_count)
	benchmark.queue_free()
	await process_frame
	quit(0)

func _run_named_case(case_name: String) -> void:
	match case_name:
		"modular0":
			await _run_configured_case("10k_moving_0_modular", 0, false, false, ShadowBudgetType.Mode.ALL, false, RenderModeType.Mode.MODULAR)
		"modular64":
			await _run_configured_case("10k_moving_64_modular", 64, false, false, ShadowBudgetType.Mode.ALL, false, RenderModeType.Mode.MODULAR)
		"shared64":
			await _run_configured_case("10k_moving_64_shared_resources", 64, false, false, ShadowBudgetType.Mode.ALL, false, RenderModeType.Mode.SHARED_RESOURCES)
		"bundle64":
			await _run_configured_case("10k_moving_64_skinned_bundle", 64, false, false, ShadowBudgetType.Mode.ALL, false)
		"reduced64":
			await _run_configured_case("10k_moving_64_bundle_reduced_shadow", 64, false, false, ShadowBudgetType.Mode.BODY_BUNDLE_ONLY, false, RenderModeType.Mode.BUNDLE_REDUCED_SHADOW)
		"lod64":
			await _run_configured_case("10k_moving_64_bundle_lod", 64, false, false, ShadowBudgetType.Mode.DISTANCE_BUDGETED, false, RenderModeType.Mode.BUNDLE_LOD)
		"rigid_batch64":
			await _run_configured_case("rigid_batch64", 64, true, false, ShadowBudgetType.Mode.ALL, false)
		"material64":
			await _run_configured_case("material64", 64, false, true, ShadowBudgetType.Mode.ALL, false)
		"shadow64":
			await _run_configured_case("shadow64", 64, false, false, ShadowBudgetType.Mode.BODY_BUNDLE_ONLY, false)
		"shadowmajor64":
			await _run_configured_case("shadowmajor64", 64, false, false, ShadowBudgetType.Mode.BODY_MAJOR, false)
		"combined64":
			await _run_configured_case("combined64", 64, true, true, ShadowBudgetType.Mode.BODY_BUNDLE_ONLY, false)
		"combined_camera64":
			await _run_configured_case("combined_camera64", 64, true, true, ShadowBudgetType.Mode.DISTANCE_BUDGETED, true)
		"combined30hz64":
			await _run_configured_case("combined30hz64", 64, true, true, ShadowBudgetType.Mode.BODY_BUNDLE_ONLY, false, RenderModeType.Mode.SKINNED_BUNDLE, 2)
		"modular16", "modular32", "modular128":
			var modular_budget: int = int(case_name.trim_prefix("modular"))
			await _run_configured_case("10k_moving_%d_modular" % modular_budget, modular_budget, false, false, ShadowBudgetType.Mode.ALL, false, RenderModeType.Mode.MODULAR)
		"bundle16", "bundle32", "bundle128":
			var bundle_budget: int = int(case_name.trim_prefix("bundle"))
			await _run_configured_case("10k_moving_%d_skinned_bundle" % bundle_budget, bundle_budget, false, false, ShadowBudgetType.Mode.ALL, false)
		"combined16", "combined32", "combined128":
			var combined_budget: int = int(case_name.trim_prefix("combined"))
			await _run_configured_case("combined_%d" % combined_budget, combined_budget, true, true, ShadowBudgetType.Mode.BODY_BUNDLE_ONLY, false)
		_:
			assert(false, "Unknown RenderBundle case: %s" % case_name)

func _run_and_print(case_name: String, budget: int, render_mode: int) -> int:
	return await _run_configured_case(case_name, budget, false, false, ShadowBudgetType.Mode.ALL, false, render_mode)

func _run_configured_case(
	case_name: String,
	budget: int,
	use_rigid_batch: bool,
	use_material_consolidation: bool,
	shadow_mode: int,
	move_camera: bool,
	render_mode: int = RenderModeType.Mode.SKINNED_BUNDLE,
	socket_update_stride: int = 1
) -> int:
	benchmark.set_crowd_mode(SimulationType.BenchmarkMode.HUMANOID_LOD)
	benchmark.set_near_actor_budget(budget)
	benchmark.set_special_render_mode(render_mode)
	benchmark.set_special_rigid_render_options(
		use_rigid_batch, use_material_consolidation, shadow_mode, 24, socket_update_stride
	)
	benchmark.set_deterministic_camera_motion(move_camera)
	benchmark.reset_deterministic_state()
	benchmark.set_near_render_options(true, true, true, 1)
	benchmark.set_camera_state(Vector3(0.0, 16.0, 1.0), Vector3.ZERO, 110.0)
	benchmark.set_simulation_paused(false)
	await _settle(warmup_frames)
	benchmark.begin_measurement()
	await _settle(sample_frames)
	var result: Dictionary = benchmark.end_measurement()
	_print_result(case_name, render_mode, result)
	_print_audit(case_name, result)
	_print_spike_trace(case_name, result)
	return 1

func _print_result(case_name: String, render_mode: int, result: Dictionary) -> void:
	var stats: Dictionary = result.get("near_render_stats", {})
	var near: float = float(result.get("near", 0.0))
	var near_draw_calls: float = float(stats.get("surfaces", 0))
	var draw_calls_per_actor: float = near_draw_calls / near if near > 0.0 else 0.0
	var result_format: String = (
		"SPECIAL_BUNDLE_RESULT case=%s mode=%s budget=%d frames=%d "
		+ "fps=%.3f frame_ms=%.3f p95_frame_ms=%.3f worst_frame_ms=%.3f "
		+ "crowd_renderer_ms=%.3f special_actor_cpu_ms=%.3f animation_cpu_ms=%.3f "
		+ "rigid_batch_ms=%.3f rigid_updates=%.1f rigid_upload_calls=%.1f buffer_upload_calls=%.1f bytes_uploaded=%.1f rigid_structural=%.1f "
		+ "draw_calls=%d near_draw_calls=%.1f draw_calls_per_actor=%.3f rigid_draw_calls=%d shadow_submissions=%d "
		+ "rendered_objects=%d mesh_instances=%d skinned_meshes=%d materials=%d unique_materials=%d unique_meshes=%d triangles=%d "
		+ "skeletons=%d near=%.1f lod0=%d lod1=%d cache_misses=%d bundle_builds=%d bundle_entries=%d promotions_sec=%.1f demotions_sec=%.1f "
		+ "lod_changes_sec=%.1f shadow_changes_sec=%.1f "
		+ "crowd_instances=%d visible_chunks=%.1f"
	)
	print(result_format % [
			case_name, RenderModeType.name_for(render_mode), int(result.get("near", 0.0)),
			int(result.get("frames", 0)), float(result.get("fps", 0.0)),
			float(result.get("frame_ms", 0.0)), float(result.get("p95_frame_ms", 0.0)), float(result.get("worst_frame_ms", 0.0)),
			float(result.get("renderer_ms", 0.0)), float(result.get("pool_ms", 0.0)),
			float(result.get("animation_ms", 0.0)), float(result.get("rigid_batch_cpu_ms", 0.0)),
			float(result.get("rigid_transform_updates", 0.0)), float(result.get("rigid_upload_calls", 0.0)),
			float(result.get("rigid_buffer_upload_calls", 0.0)), float(result.get("rigid_bytes_uploaded", 0.0)),
			float(result.get("rigid_structural_changes", 0.0)), int(result.get("draw_calls", 0)),
			near_draw_calls, draw_calls_per_actor, int(stats.get("rigid_equipment_draw_calls", 0)),
			int(stats.get("shadow_submissions", 0)), int(stats.get("mesh_instances", 0)),
			int(stats.get("mesh_instances", 0)), int(stats.get("skinned_meshes", 0)),
			int(stats.get("materials", 0)), int(stats.get("unique_materials", 0)), int(stats.get("unique_meshes", 0)),
			int(stats.get("triangles", 0)), int(result.get("active_skeletons", 0)),
			near, int(result.get("bundle_lod0_active", 0)), int(result.get("bundle_lod1_active", 0)),
			int(result.get("bundle_cache_misses", 0)), int(stats.get("bundle_cache_builds", 0)),
			int(stats.get("bundle_cache_entries", 0)), float(result.get("promotions_per_second", 0.0)),
			float(result.get("demotions_per_second", 0.0)), float(result.get("lod_transitions", 0.0)),
			float(result.get("shadow_transitions", 0.0)), int(result.get("crowd_instances", 0)),
		float(result.get("visible_chunks", 0.0))
	])

func _print_audit(case_name: String, result: Dictionary) -> void:
	print("SPECIAL_RIGID_AUDIT case=%s data=%s" % [case_name, JSON.stringify(result.get("rigid_equipment_audit", {}))])

func _print_spike_trace(case_name: String, result: Dictionary) -> void:
	print("SPECIAL_SPIKE_TRACE case=%s count=%d events=%s" % [case_name, int(result.get("spike_count", 0)), JSON.stringify(result.get("spike_trace", []))])

func _print_breakdown(label: String) -> void:
	var breakdown: Dictionary = benchmark.actor_pool.component_breakdown()
	for component: StringName in breakdown.keys():
		var entry: Dictionary = breakdown[component]
		var component_format: String = (
			"SPECIAL_BUNDLE_COMPONENT mode=%s component=%s mesh_instances=%d surfaces=%d draw_calls=%d "
			+ "triangles=%d skinned_meshes=%d shadow_meshes=%d"
		)
		print(component_format % [
				label, component, int(entry.get("mesh_instances", 0)), int(entry.get("surfaces", 0)),
				int(entry.get("draw_calls", 0)), int(entry.get("triangles", 0)),
			int(entry.get("skinned_meshes", 0)), int(entry.get("shadow_meshes", 0))
		])

func _settle(frame_count: int) -> void:
	for _frame: int in range(frame_count):
		await process_frame
