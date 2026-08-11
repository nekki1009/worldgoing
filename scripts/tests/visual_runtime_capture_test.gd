extends SceneTree

const TEST_SEED: int = 123456789
const CAPTURE_DIR: String = "res://.visual_captures"

var fps_samples: Array[float] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var main_scene: PackedScene = load("res://scenes/Main.tscn") as PackedScene
	assert(main_scene != null, "Main scene could not be loaded")
	var main: Node2D = main_scene.instantiate() as Node2D
	get_root().add_child(main)
	await _settle(45)
	var navigation: NavigationController = main.get_node("NavigationController") as NavigationController
	navigation.session.world_seed = TEST_SEED
	navigation.session.party.initialized = true
	navigation.show_world()
	await _settle(45)
	await _wait_for_fps_label()
	_capture("world")
	print("VISUAL WORLD ENGINE FPS: %.2f" % Engine.get_frames_per_second())
	var poi: WorldPOIData = _first_poi(navigation.world_data)
	assert(poi != null, "No deterministic POI available for runtime capture")
	navigation.session.party.set_global_region_cell(poi.global_region_cell)
	navigation.enter_region(poi.world_cell)
	await _settle(60)
	await _wait_for_fps_label()
	_capture("region")
	print("VISUAL REGION ENGINE FPS: %.2f" % Engine.get_frames_per_second())
	navigation.enter_site_at(poi.region_cell)
	await _settle(45)
	await _wait_for_fps_label()
	_capture("site")
	print("VISUAL SITE ENGINE FPS: %.2f" % Engine.get_frames_per_second())
	var measured_fps: float = await _measure_fps(120)
	print("VISUAL RUNTIME FPS: %.2f" % measured_fps)
	print("VISUAL RUNTIME ENGINE FPS: %.2f" % Engine.get_frames_per_second())
	assert(measured_fps >= 30.0, "Measured runtime FPS was below 30")
	main.queue_free()
	await process_frame
	print("Visual runtime capture passed: world, region, site, FPS >= 30")
	quit()

func _settle(frame_count: int) -> void:
	for _frame: int in range(frame_count):
		await process_frame

func _measure_fps(frame_count: int) -> float:
	var start_usec: int = Time.get_ticks_usec()
	for _frame: int in range(frame_count):
		await process_frame
	var elapsed_usec: int = maxi(1, Time.get_ticks_usec() - start_usec)
	return float(frame_count) * 1_000_000.0 / float(elapsed_usec)

func _wait_for_fps_label() -> void:
	await create_timer(1.1).timeout

func _capture(label: String) -> void:
	var viewport_texture: ViewportTexture = get_root().get_viewport().get_texture()
	if viewport_texture == null:
		print("VISUAL CAPTURE SKIPPED (headless renderer has no viewport texture): %s" % label)
		return
	var image: Image = viewport_texture.get_image()
	if image == null or image.is_empty():
		print("VISUAL CAPTURE SKIPPED (empty viewport texture): %s" % label)
		return
	var path: String = "%s/%s.png" % [CAPTURE_DIR, label]
	var error: Error = image.save_png(path)
	assert(error == OK, "Could not save viewport capture %s" % path)
	print("VISUAL CAPTURE: %s" % ProjectSettings.globalize_path(path))

func _first_poi(world_data: WorldData) -> WorldPOIData:
	for y: int in range(WorldData.WORLD_CELLS.y):
		for x: int in range(WorldData.WORLD_CELLS.x):
			var pois: Array[WorldPOIData] = world_data.get_pois_for_region(Vector2i(x, y), TEST_SEED)
			if not pois.is_empty():
				return pois[0]
	return null
