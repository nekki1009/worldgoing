extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# 1. Test flat map
	var flat := Helper.build_flat_map(40, 40)
	assert(flat != null and flat.size == Vector2i(40, 40))
	assert(flat.is_walkable(Vector2i(20, 20)))
	
	# 2. Test bottleneck map
	var bneck := Helper.build_bottleneck_map(Vector2i(60, 30), 15, 20, 35, 1)
	var b_data: TerrainData = bneck.data
	assert(b_data.is_walkable(Vector2i(25, 15)), "Corridor cell must be walkable")
	assert(not b_data.is_walkable(Vector2i(25, 14)), "Wall cell above corridor must be blocked")
	assert(not b_data.is_walkable(Vector2i(25, 16)), "Wall cell below corridor must be blocked")
	
	# 3. Test U-turn map
	var uturn := Helper.build_u_turn_map(Vector2i(50, 50))
	var u_data: TerrainData = uturn.data
	assert(not u_data.is_walkable(Vector2i(25, 30)), "Barrier must be blocked")
	
	# 4. Test platform map
	var plat := Helper.build_mountain_platform_map(Vector2i(50, 50), Vector2i(25, 25), 4)
	var p_data: TerrainData = plat.data
	assert(plat.platform_capacity > 0)
	assert(p_data.height_levels[p_data.index(Vector2i(25, 25))] == 2)
	
	# 5. Test army creation
	var army := Helper.create_test_army(flat, 1, 0, 100, Vector2i(5, 5))
	assert(army != null and army.has_army() and army.combat_enabled)
	assert(army.cells.size() == 100)
	assert(army.current_commander >= 0)
	
	# Verify metrics methods exist and work
	var metrics: Dictionary = army.get_movement_metrics()
	assert(metrics.has("route_calls"))
	assert(metrics.has("expanded_nodes"))
	assert(metrics.has("proposal_count"))
	assert(metrics.has("accepted_count"))
	assert(metrics.has("rejected_dependency_count"))
	assert(metrics.has("scheduler_deferred_count"))
	
	army.reset_movement_metrics()
	army.clear()
	army.queue_free()
	
	print("COMBAT_MOVEMENT_TEST_HELPER_PASS: All synthetic maps and test army fixture verified")
	quit(0)
