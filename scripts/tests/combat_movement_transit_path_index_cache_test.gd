extends SceneTree

const Transit = preload("res://scripts/terrain_lab/formation_transit_planner.gd")

func _initialize() -> void:
	var plan := CombatMovePlan.new()
	plan.macro_path = [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 1)]
	var first := Transit._get_exact_path_indices(plan)
	assert(first[Vector2i(1, 1)] == 2, "Repeated path cells must use the last index")
	assert(is_same(first, Transit._get_exact_path_indices(plan)), "Unchanged path must reuse its index map")

	plan.macro_path = plan.macro_path.duplicate()
	var replaced := Transit._get_exact_path_indices(plan)
	assert(not is_same(first, replaced), "A different path array must rebuild even at the same epoch and size")
	assert(replaced == first, "Replacing the path with equal values must preserve the index mapping")

	plan.macro_path[1] = Vector2i(3, 1)
	plan.path_epoch += 1
	var revised := Transit._get_exact_path_indices(plan)
	assert(not is_same(replaced, revised), "Changing the path epoch must rebuild an in-place edited path")
	assert(revised.has(Vector2i(3, 1)) and not revised.has(Vector2i(2, 1)), "Rebuilt indices must follow the new path")
	print("TRANSIT PATH INDEX CACHE PASS")
	quit(0)
