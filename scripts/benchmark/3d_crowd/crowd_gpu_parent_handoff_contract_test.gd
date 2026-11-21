extends SceneTree

# Reproduces the narrow B -> GPU -> B switch after the render thread hides B's
# RS instances but before the main thread frees their still-visible Nodes.
const ControllerType = preload("res://scripts/benchmark/3d_crowd_promotion/crowd_promotion_benchmark_controller.gd")
const RendererType = preload("res://scripts/benchmark/3d_crowd/crowd_renderer_3d.gd")
const SimulationType = preload("res://scripts/benchmark/3d_crowd/battle_crowd_simulation.gd")
const SCENE_PATH := "res://scenes/benchmark/3d_crowd/FormationSpaceCrowdBenchmark3D.tscn"
const CAPTURE_DIR := "res://.visual_captures/crowd_gpu_handoff"

var _benchmark: CrowdPromotionBenchmarkController

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_rendering_device() == null:
		_fail("GPU-backed Forward+ window required")
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(800, 600))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR)) != OK:
		_fail("Could not create handoff capture directory")
		return
	var scene: PackedScene = load(SCENE_PATH)
	if scene == null:
		_fail("Formation-Space scene did not load")
		return
	_benchmark = scene.instantiate() as CrowdPromotionBenchmarkController
	if _benchmark == null:
		_fail("Formation-Space controller type mismatch")
		return
	get_root().add_child(_benchmark)
	_benchmark.hud.visible = false
	_benchmark.set_simulation_paused(true)
	_benchmark.set_near_actor_budget(0)
	_benchmark.set_crowd_render_path(RendererType.RenderPath.FORMATION_PARENT_TRANSFORM)
	_benchmark.set_crowd_mode(SimulationType.BenchmarkMode.HUMANOID_STATIC)
	_benchmark.simulation.set_active_soldiers(100)
	_benchmark.crowd_renderer.invalidate_layout()
	var center: Vector3 = _benchmark.simulation.formations[0].center_position
	_benchmark.set_camera_state(center + Vector3(0.0, 16.0, 1.0), center, 30.0)
	await _settle(4)

	# Freeze controller while obtaining an image of the same scene without B;
	# this gives an image-space oracle independent of sky/ground colors.
	_benchmark.set_process(false)
	var batches: Array = _benchmark.crowd_renderer.get("_formation_batches")
	if batches.is_empty():
		_fail("B Formation batches were not built")
		return
	var original_visibility: Array[bool] = []
	for batch: Node3D in batches:
		original_visibility.append(batch.visible)
		batch.visible = false
	await _settle(3)
	var empty_pixels: PackedByteArray = _capture("empty")
	for index: int in range(batches.size()):
		(batches[index] as Node3D).visible = original_visibility[index]
	await _settle(3)
	var baseline_pixels: PackedByteArray = _capture("parent_before")
	_benchmark.set_process(true)
	if empty_pixels.is_empty() or baseline_pixels.is_empty():
		return
	var baseline_signal: int = _changed_pixels(baseline_pixels, empty_pixels)
	if baseline_signal < 100:
		_fail("B baseline is not visibly different from the empty scene: pixels=%d" % baseline_signal)
		return

	for cycle: int in range(3):
		_benchmark.set_crowd_render_path(RendererType.RenderPath.GPU_FORMATION_OUTPUT)
		var deadline: int = Time.get_ticks_msec() + 15000
		var intercepted: bool = false
		while Time.get_ticks_msec() < deadline:
			await process_frame
			var status: Dictionary = _benchmark.crowd_renderer.crowd_gpu_status()
			if not str(status.get("error", "")).is_empty():
				_fail("GPU handoff failed in cycle %d: %s" % [cycle, status["error"]])
				return
			if int(status.get("completed_frames", 0)) > 0:
				var bridge_batches: Array = _benchmark.crowd_renderer.get("_formation_batches")
				if bridge_batches.is_empty():
					_fail("Missed B-to-GPU bridge window in cycle %d" % cycle)
					return
				intercepted = true
				_benchmark.set_crowd_render_path(RendererType.RenderPath.FORMATION_PARENT_TRANSFORM)
				break
		if not intercepted:
			_fail("GPU packet never completed during B handoff in cycle %d" % cycle)
			return
		await _settle(4)
		var after_pixels: PackedByteArray = _capture("parent_after_toggle_%d" % cycle)
		if after_pixels.is_empty():
			return
		var after_signal: int = _changed_pixels(after_pixels, empty_pixels)
		var changed_from_baseline: int = _changed_pixels(after_pixels, baseline_pixels)
		if after_signal < int(float(baseline_signal) * 0.80) or changed_from_baseline > int(float(baseline_signal) * 0.25):
			_fail("B remained hidden or changed after GPU toggle %d: before=%d after=%d delta=%d" % [
				cycle, baseline_signal, after_signal, changed_from_baseline
			])
			return
		if _benchmark.crowd_renderer.render_path != RendererType.RenderPath.FORMATION_PARENT_TRANSFORM:
			_fail("Renderer did not return to B mode in cycle %d" % cycle)
			return
		var restored_batches: Array = _benchmark.crowd_renderer.get("_formation_batches")
		if restored_batches.is_empty() or not (restored_batches[0] as Node3D).visible:
			_fail("B Node visibility did not recover in cycle %d" % cycle)
			return
		print("CROWD_GPU_PARENT_HANDOFF_CYCLE_PASS cycle=%d before_pixels=%d after_pixels=%d delta=%d" % [
			cycle, baseline_signal, after_signal, changed_from_baseline
		])
	print("CROWD_GPU_PARENT_HANDOFF_PASS cycles=3 captures=%s" % ProjectSettings.globalize_path(CAPTURE_DIR))
	_benchmark.queue_free()
	await process_frame
	quit(0)

func _settle(frames: int) -> void:
	for frame: int in range(frames):
		await process_frame
		await RenderingServer.frame_post_draw

func _capture(label: String) -> PackedByteArray:
	var image: Image = get_root().get_texture().get_image()
	if image == null or image.is_empty():
		_fail("No viewport image for " + label)
		return PackedByteArray()
	image.convert(Image.FORMAT_RGBA8)
	if image.save_png(CAPTURE_DIR + "/" + label + ".png") != OK:
		_fail("Could not save handoff capture: " + label)
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
	print("CROWD_GPU_PARENT_HANDOFF_FAIL " + message)
	if _benchmark != null:
		_benchmark.queue_free()
	quit(1)
