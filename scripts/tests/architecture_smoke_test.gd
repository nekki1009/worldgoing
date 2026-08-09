extends SceneTree

const TEST_SEED: int = 123456789

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
	var session: GameSession = navigation.get_session()
	var region_coord: Vector2i = Vector2i(3, 4)
	var region_runtime: RegionRuntimeState = session.get_region_runtime_state(region_coord)
	region_runtime.owner_id = "test_owner"
	region_runtime.discovered = false
	region_runtime.development_level = 7
	var initial_position: Vector2i = session.party.current_global_region_cell
	var initial_time: int = session.world_time_seconds
	var terrain: RegionTerrainData = navigation.world_data.get_or_generate_region_terrain(region_coord, TEST_SEED)
	assert(terrain != null, "Region terrain was not generated through WorldData")
	assert(
		navigation.world_data.get_region(region_coord).seed == RegionData.derive_seed(
			TEST_SEED,
			region_coord,
			RegionTerrainGenerator.GENERATION_VERSION
		),
		"Region seed was not recorded on RegionData"
	)

	navigation.show_region()
	await process_frame
	navigation.show_world()
	await process_frame

	assert(session.party.current_global_region_cell == initial_position, "Scene replacement changed Party position")
	assert(session.world_time_seconds == initial_time, "Scene replacement changed World Time")
	var restored_runtime: RegionRuntimeState = session.get_region_runtime_state(region_coord)
	assert(restored_runtime.owner_id == "test_owner", "Region Runtime State was lost on Scene replacement")
	assert(not restored_runtime.discovered and restored_runtime.development_level == 7, "Region Runtime State fields were not preserved")
	print("Architecture smoke passed: session state survives World/Region view replacement")
	main.queue_free()
	await process_frame
	quit()
