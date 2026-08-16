extends SceneTree

const TEST_SEED: int = 123456789
const GlobalTravelPathType = preload("res://scripts/data/global_travel_path.gd")
const TravelStatusType = preload("res://scripts/runtime/travel_status.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var main_scene: PackedScene = load("res://scenes/Main.tscn") as PackedScene
	assert(main_scene != null, "Main scene could not be loaded")
	var main: Node2D = main_scene.instantiate() as Node2D
	get_root().add_child(main)
	await process_frame
	var navigation: NavigationController = main.get_node("NavigationController") as NavigationController
	assert(navigation != null, "NavigationController missing from Main scene")
	navigation.session.world_seed = TEST_SEED
	var edge_runtime: TravelRuntime = navigation.travel_runtime
	var edge_footprint: Array[SiteRuntimeSnapshot] = edge_runtime.query_site_snapshot_footprint(
		Vector2i(1, 1),
		Vector2i(0, 50),
		1,
		false
	)
	assert(edge_footprint.size() == 9, "Cross-Region Site footprint lost edge neighbours")
	var edge_globals: Dictionary = {}
	for edge_snapshot: SiteRuntimeSnapshot in edge_footprint:
		edge_globals[edge_snapshot.global_region_cell] = true
	assert(edge_globals.has(Vector2i(99, 150)) and edge_globals.has(Vector2i(101, 150)),
		"Cross-Region Site footprint used local Region coordinates")
	print("RUNTIME PASS: Cross-Region Site footprint keeps global edge coordinates")
	var start: Vector2i = _find_clear_cell(navigation.world_data, Vector2i(3, 4))
	var destination: Vector2i = _find_clear_cell(navigation.world_data, Vector2i(4, 4))
	assert(start != Vector2i(-1, -1) and destination != Vector2i(-1, -1), "Runtime path endpoints are not passable")
	var pathfinder: PartyPathfinder = PartyPathfinder.new()
	var path: GlobalTravelPathType = pathfinder.find_global_path(
			navigation.world_data,
			start,
			destination,
			TEST_SEED,
			TravelCostConfig.DEFAULT_WALK_SPEED_KMH
		)
	assert(path.has_path() and path.regions_crossed >= 2, "Runtime Global Path did not cross a Region")
	var path_hash: String = path.path_hash()
	navigation.session.party.set_global_region_cell(start)
	navigation.session.party.initialized = true
	navigation.session.selected_world_cell = navigation.session.party.get_world_cell()
	navigation.session.selected_region_cell = navigation.session.party.get_region_cell()
	navigation.session.set_travel_plan(path)
	assert(navigation.session.confirm_travel(), "Runtime travel could not be confirmed")
	navigation.session.travel_speed_multiplier = 16.0
	var initial_time: int = navigation.session.world_time_seconds
	navigation.show_region()
	navigation._start_travel_loop()
	var frames: int = 0
	while navigation.travel_loop_running:
		await process_frame
		frames += 1
		assert(frames < 1200, "Runtime Global Travel did not finish")
	assert(not navigation.session.has_travel_plan(), "Travel state was not cleared after arrival")
	assert(navigation.session.party.current_global_region_cell == destination, "Runtime Party missed the destination")
	assert(navigation.session.world_time_seconds == initial_time + path.estimated_travel_seconds, "Runtime World Time did not advance per stored step cost")
	assert(path.path_hash() == path_hash, "Runtime travel mutated the stored path")
	assert(navigation.session.last_travel_status == TravelStatusType.Code.ARRIVED, "Arrival status was not emitted")
	assert(navigation.session.party.get_world_cell() != WorldCoordinates.global_region_cell_to_world_region(start)["world_cell"], "Runtime travel never changed Region")
	print("RUNTIME PASS: %.1f km Global Travel crossed %d Regions at 16x playback in %d frames" % [
		path.total_distance_meters / 1000.0,
		path.regions_crossed,
		frames,
	])
	var cancel_path: GlobalTravelPathType = _reverse_path(navigation.world_data, path)
	assert(cancel_path.has_path() and cancel_path.cells.size() > 3, "Could not build a cancellation path")
	var cancel_position: Vector2i = navigation.session.party.current_global_region_cell
	var cancel_time: int = navigation.session.world_time_seconds
	navigation.session.set_travel_plan(cancel_path)
	assert(navigation.session.confirm_travel(), "Cancellation travel could not be confirmed")
	navigation.session.travel_speed_multiplier = 1.0
	navigation.show_region()
	navigation._start_travel_loop()
	await create_timer(0.24).timeout
	navigation.session.travel_cancel_requested = true
	while navigation.travel_loop_running:
		await process_frame
	assert(not navigation.session.has_travel_plan(), "Cancel left an active travel plan")
	assert(navigation.session.party.current_global_region_cell != cancel_path.destination_global_cell, "Cancel reached the old destination")
	assert(navigation.session.party.current_global_region_cell != cancel_position or navigation.session.world_time_seconds > cancel_time, "Cancel did not complete a current step")
	assert(navigation.session.world_time_seconds > cancel_time, "Cancel lost consumed World Time")
	print("RUNTIME PASS: cancel stops after a completed step without teleport or time refund")
	main.queue_free()
	await process_frame
	quit()

func _find_clear_cell(world_data: WorldData, world_cell: Vector2i) -> Vector2i:
	var center: Vector2i = WorldCoordinates.world_region_to_global_region_cell(world_cell, Vector2i(50, 50))
	for radius: int in range(50):
		for y: int in range(center.y - radius, center.y + radius + 1):
			for x: int in range(center.x - radius, center.x + radius + 1):
				if maxi(abs(x - center.x), abs(y - center.y)) != radius:
					continue
				var global_cell: Vector2i = Vector2i(x, y)
				var sample: Vector4 = world_data.terrain_generator.macro_sampler.sample(TEST_SEED, global_cell)
				var terrain_type: int = world_data.terrain_generator.classify_sample(sample)
				if not TerrainType.is_water_like(terrain_type) and sample.z <= 0.0:
					return global_cell
	return Vector2i(-1, -1)

func _reverse_path(world_data: WorldData, source: GlobalTravelPathType) -> GlobalTravelPathType:
	var result: GlobalTravelPathType = GlobalTravelPathType.new()
	for index: int in range(source.cells.size() - 1, -1, -1):
		result.cells.append(source.cells[index])
	result.start_global_cell = result.cells.front()
	result.destination_global_cell = result.cells.back()
	var regions: Dictionary = {}
	for cell: Vector2i in result.cells:
		var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(cell)
		regions[converted["world_cell"] as Vector2i] = true
	for index: int in range(1, result.cells.size()):
		var from_info: Dictionary = world_data.sample_travel_data(TEST_SEED, result.cells[index - 1])
		var to_info: Dictionary = world_data.sample_travel_data(TEST_SEED, result.cells[index])
		var direction: Vector2i = result.cells[index] - result.cells[index - 1]
		var step_seconds: int = maxi(roundi(TravelCostConfig.step_travel_seconds(
				from_info,
				to_info,
				direction,
				TravelCostConfig.DEFAULT_WALK_SPEED_KMH
			)), 0)
		result.step_travel_seconds.append(step_seconds)
		result.total_distance_meters += TravelCostConfig.step_distance_meters(direction)
		result.estimated_travel_seconds += step_seconds
	result.regions_crossed = regions.size()
	return result
