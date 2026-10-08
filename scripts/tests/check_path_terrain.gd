extends SceneTree

const TerrainLabScene = preload("res://scenes/terrain_lab/TerrainLab.tscn")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Checking Terrain along Macro Path ---")
	var lab: TerrainLab = TerrainLabScene.instantiate()
	root.add_child(lab)
	for i in range(5):
		await process_frame

	lab.start_melee_trial(lab.site_controller._trial_setup())
	for i in range(5):
		await process_frame

	var army: TerrainArmy = lab.army
	lab.site_controller._test_army_order(TerrainArmy.CombatOrder.MOVE, Vector2i(49, 37))
	var plan = army.get_active_move_plan()

	print("Macro path size: ", plan.macro_path.size())
	for i in range(12, 22):
		var p1 = plan.macro_path[i]
		var p2 = plan.macro_path[i + 1] if i + 1 < plan.macro_path.size() else Vector2i(-1, -1)
		var walkable = lab.terrain.is_walkable(p1)
		var can_step = lab.terrain.can_step(p1, p2) if p2 != Vector2i(-1, -1) else false
		var height = lab.terrain.height_levels[lab.terrain.index(p1)] if lab.terrain.contains(p1) else -1
		var owner = army._cell_owners.get(p1, -1)
		print("  path[%2d]=%s height=%d walk=%s step_next=%s owner=%d" % [i, str(p1), height, walkable, can_step, owner])

	quit(0)
