extends SceneTree

func _init() -> void:
	assert(load("res://scenes/Main.tscn") is PackedScene, "Main scene could not be loaded")
	_check_case(Vector2i(0, 0), Vector2i(0, 0), Vector2i(0, 0))
	_check_case(Vector2i(0, 0), Vector2i(99, 99), Vector2i(9900, 9900))
	_check_case(Vector2i(1, 0), Vector2i(0, 0), Vector2i(10000, 0))
	_check_case(Vector2i(12, 7), Vector2i(35, 62), Vector2i(123500, 76200))
	print("Coordinate tests passed: 4 cases")
	quit()

func _check_case(world_cell: Vector2i, region_cell: Vector2i, expected_global_meters: Vector2i) -> void:
	var global_meters: Vector2i = WorldCoordinates.world_region_to_global_meters(world_cell, region_cell)
	assert(global_meters == expected_global_meters, "Forward conversion failed")
	var reverse: Dictionary = WorldCoordinates.global_meters_to_world_region(global_meters)
	assert(reverse["world_cell"] == world_cell, "World cell reverse conversion failed")
	assert(reverse["region_cell"] == region_cell, "Region cell reverse conversion failed")
	print("%s + %s -> %s -> %s + %s" % [world_cell, region_cell, global_meters, reverse["world_cell"], reverse["region_cell"]])
