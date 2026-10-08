extends SceneTree

const TerrainLabScene = preload("res://scenes/terrain_lab/TerrainLab.tscn")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Starting reproduce_user_move_error ---")
	var lab: TerrainLab = TerrainLabScene.instantiate()
	root.add_child(lab)
	
	for i in range(5):
		await process_frame

	print("Save path exists: ", FileAccess.file_exists(lab.site_controller.save_path))
	print("Army has_army: ", lab.army.has_army())
	print("Army units: ", lab.army.combat_units.size(), " cells: ", lab.army.cells.size())

	# If no army, deploy trial
	if not lab.army.has_army() or lab.army.combat_units.is_empty():
		print("No army currently loaded, deploying melee trial...")
		var setup: Dictionary = lab.site_controller._trial_setup()
		var res: Dictionary = lab.start_melee_trial(setup)
		print("Trial deploy result: ", res.get("ok"))
		for i in range(5):
			await process_frame

	var army: TerrainArmy = lab.army
	print("Army captain cell: ", army.cells[0] if not army.cells.is_empty() else "none")
	print("Army medoid: ", army._get_active_members_medoid())

	# Issue MOVE command like user does in UI
	var target := Vector2i(49, 37)
	print("Issuing MOVE order to target: ", target)
	lab.site_controller.selected = target
	lab.site_controller._test_army_order(TerrainArmy.CombatOrder.MOVE, target)

	print("Simulating 60 frames...")
	for frame in range(1, 61):
		await process_frame
		if frame % 10 == 0:
			print("Frame %d: medoid=%s status=%s" % [frame, str(army._get_active_members_medoid()), army.command_status])

	print("Done reproduce test.")
	quit(0)
