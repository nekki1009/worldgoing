extends SceneTree

# Visual integration probe for renderer-local GPU formations under a transformed
# parent and for moving an already-running viewport to a new World3D scenario.
const ControllerType = preload("res://scripts/benchmark/3d_crowd_promotion/crowd_promotion_benchmark_controller.gd")
const RendererType = preload("res://scripts/benchmark/3d_crowd/crowd_renderer_3d.gd")
const SimulationType = preload("res://scripts/benchmark/3d_crowd/battle_crowd_simulation.gd")
const SCENE_PATH := "res://scenes/benchmark/3d_crowd/FormationSpaceCrowdBenchmark3D.tscn"
const CAPTURE_DIR := "res://.visual_captures/crowd_gpu_renderer_world"
const EXPECTED_BATCHES := 100

var _benchmark: CrowdPromotionBenchmarkController
var _viewport: SubViewport
var _world_a: World3D
var _world_b: World3D

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_rendering_device() == null:
		_fail("GPU-backed Forward+ window required")
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR)) != OK:
		_fail("Could not create renderer world capture directory")
		return
	var scene: PackedScene = load(SCENE_PATH)
	if scene == null:
		_fail("Formation-Space scene did not load")
		return
	_world_a = World3D.new()
	_world_b = World3D.new()
	if _world_a.scenario == _world_b.scenario:
		_fail("World3D fixtures share one scenario")
		return
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(640, 640)
	_viewport.own_world_3d = false
	_viewport.world_3d = _world_a
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(_viewport)
	_benchmark = scene.instantiate() as CrowdPromotionBenchmarkController
	if _benchmark == null:
		_fail("Formation-Space controller type mismatch")
		return
	_viewport.add_child(_benchmark)
	await process_frame
	if _viewport.find_world_3d() != _world_a:
		_fail("SubViewport did not enter explicit World3D A")
		return
	_benchmark.hud.visible = false
	_benchmark.set_simulation_paused(true)
	_benchmark.set_near_actor_budget(0)
	_benchmark.set_crowd_mode(SimulationType.BenchmarkMode.HUMANOID_STATIC)
	_benchmark.simulation.set_active_soldiers(100)
	_benchmark.crowd_renderer.invalidate_layout()
	var local_center: Vector3 = _benchmark.simulation.formations[0].center_position
	var parent_transform := Transform3D(
		Basis(Vector3.UP, 0.43).scaled(Vector3(1.17, 1.0, 0.86)),
		Vector3(240.0, 0.0, 180.0)
	)
	_benchmark.crowd_renderer.transform = parent_transform
	var world_center: Vector3 = _benchmark.crowd_renderer.to_global(local_center)
	if world_center.distance_to(local_center) < 100.0:
		_fail("Nonidentity fixture does not separate local and world centers")
		return
	_focus(world_center)
	await _settle(4)

	# The B-path scene with all formation batches hidden is the image-space
	# oracle; it keeps ground, sky, and lighting exactly as they were.
	_benchmark.set_process(false)
	var batches: Array = _benchmark.crowd_renderer.get("_formation_batches")
	if batches.is_empty():
		_fail("Parent-path formation batches were not built")
		return
	var initial_visibility: Array[bool] = []
	for batch: Node3D in batches:
		initial_visibility.append(batch.visible)
		batch.visible = false
	await _settle(3)
	var empty_a: PackedByteArray = _capture("empty_world_a")
	if empty_a.is_empty():
		return
	for index: int in range(batches.size()):
		(batches[index] as Node3D).visible = initial_visibility[index]
	_benchmark.set_process(true)
	await _settle(3)

	_benchmark.set_crowd_render_path(RendererType.RenderPath.GPU_FORMATION_OUTPUT)
	if not await _wait_gpu_committed():
		return
	if not _check_visibility(1, 100, "world-space camera"):
		return
	var gpu_before: PackedByteArray = _capture("gpu_world_a_nonidentity")
	if gpu_before.is_empty():
		return
	var before_signal: int = _changed_pixels(gpu_before, empty_a)
	if before_signal < 100:
		_fail("Transformed GPU formation is absent in World3D A: pixels=%d" % before_signal)
		return

	# The untransformed local center is far outside the camera's view of the
	# transformed mesh. This must cull the formation in world space.
	_focus(local_center)
	await _settle(3)
	if not _check_visibility(0, 0, "local-space camera"):
		return
	_focus(world_center)
	await _settle(3)
	if not _check_visibility(1, 100, "restored world-space camera"):
		return

	var frames_before_swap: int = int(_benchmark.crowd_renderer.crowd_gpu_status().get("completed_frames", 0))
	_viewport.world_3d = _world_b
	await process_frame
	if _viewport.find_world_3d() != _world_b:
		_fail("SubViewport did not enter explicit World3D B")
		return
	var deadline: int = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var status: Dictionary = _benchmark.crowd_renderer.crowd_gpu_status()
		if not str(status.get("error", "")).is_empty():
			_fail("GPU scenario swap failed: %s" % status["error"])
			return
		if _benchmark.crowd_renderer.get("_gpu_scenario_cache") == _world_b.scenario and int(status.get("completed_frames", 0)) > frames_before_swap:
			break
	if _benchmark.crowd_renderer.get("_gpu_scenario_cache") != _world_b.scenario or int(_benchmark.crowd_renderer.crowd_gpu_status().get("completed_frames", 0)) <= frames_before_swap:
		_fail("Renderer did not commit a GPU frame in World3D B")
		return
	await _settle(4)
	if not _check_visibility(1, 100, "World3D B after swap"):
		return
	var gpu_after: PackedByteArray = _capture("gpu_world_b_after_swap")
	if gpu_after.is_empty():
		return

	# Take a same-world empty capture after the swap so visibility is checked
	# from pixels, not just the renderer's reported counter.
	_benchmark.set_crowd_render_path(RendererType.RenderPath.FORMATION_PARENT_TRANSFORM)
	await _settle(4)
	_benchmark.set_process(false)
	batches = _benchmark.crowd_renderer.get("_formation_batches")
	if batches.is_empty():
		_fail("Parent-path batches missing after World3D swap")
		return
	for batch: Node3D in batches:
		batch.visible = false
	await _settle(3)
	var empty_b: PackedByteArray = _capture("empty_world_b")
	if empty_b.is_empty():
		return
	var after_signal: int = _changed_pixels(gpu_after, empty_b)
	if after_signal < maxi(100, int(float(before_signal) * 0.80)):
		_fail("GPU instances disappeared after scenario swap: before=%d after=%d" % [before_signal, after_signal])
		return
	print("CROWD_GPU_RENDERER_WORLD_PASS batches=%d visible=100 before_pixels=%d after_pixels=%d scenario_swap=1 captures=%s" % [
		EXPECTED_BATCHES, before_signal, after_signal, ProjectSettings.globalize_path(CAPTURE_DIR)
	])
	_benchmark.queue_free()
	_viewport.queue_free()
	await process_frame
	quit(0)

func _focus(center: Vector3) -> void:
	_benchmark.set_camera_state(center + Vector3(0.0, 24.0, 1.0), center, 30.0)

func _wait_gpu_committed() -> bool:
	var deadline: int = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var status: Dictionary = _benchmark.crowd_renderer.crowd_gpu_status()
		if not str(status.get("error", "")).is_empty():
			_fail("GPU renderer failed: %s" % status["error"])
			return false
		if (
			_benchmark.crowd_renderer.render_path_name() == "GPU_FORMATION_OUTPUT"
			and int(status.get("batch_count", 0)) == EXPECTED_BATCHES
			and int(status.get("ready_batches", 0)) == EXPECTED_BATCHES
			and int(status.get("completed_frames", 0)) > 0
			and (_benchmark.crowd_renderer.get("_formation_batches") as Array).is_empty()
		):
			await _settle(3)
			return true
	_fail("GPU renderer did not commit its 100 batches: %s" % _benchmark.crowd_renderer.crowd_gpu_status())
	return false

func _check_visibility(formations: int, soldiers: int, label: String) -> bool:
	var renderer: CrowdRenderer3D = _benchmark.crowd_renderer
	if (
		renderer.render_path_name() != "GPU_FORMATION_OUTPUT"
		or renderer.visible_formation_count != formations
		or renderer.visible_crowd_instance_count != soldiers
	):
		_fail("GPU world-space culling wrong at %s: path=%s formations=%d soldiers=%d" % [
			label, renderer.render_path_name(), renderer.visible_formation_count,
			renderer.visible_crowd_instance_count
		])
		return false
	return true

func _settle(frames: int) -> void:
	for frame: int in range(frames):
		await process_frame
		await RenderingServer.frame_post_draw

func _capture(label: String) -> PackedByteArray:
	var image: Image = _viewport.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("No SubViewport image for " + label)
		return PackedByteArray()
	image.convert(Image.FORMAT_RGBA8)
	if image.save_png(CAPTURE_DIR + "/" + label + ".png") != OK:
		_fail("Could not save renderer world capture: " + label)
		return PackedByteArray()
	return image.get_data()

func _changed_pixels(a: PackedByteArray, b: PackedByteArray) -> int:
	if a.size() != b.size():
		return 0
	var changed: int = 0
	for offset: int in range(0, a.size(), 4):
		if absi(int(a[offset]) - int(b[offset])) > 32 or absi(int(a[offset + 1]) - int(b[offset + 1])) > 32 or absi(int(a[offset + 2]) - int(b[offset + 2])) > 32:
			changed += 1
	return changed

func _fail(message: String) -> void:
	push_error(message)
	print("CROWD_GPU_RENDERER_WORLD_FAIL " + message)
	if _benchmark != null:
		_benchmark.queue_free()
	if _viewport != null:
		_viewport.queue_free()
	quit(1)
