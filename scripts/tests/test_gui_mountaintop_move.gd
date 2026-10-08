extends SceneTree

const TerrainLabScene = preload("res://scenes/terrain_lab/TerrainLab.tscn")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Starting Dual-Army Mountaintop Movement Integration Test ---")
	var lab: TerrainLab = TerrainLabScene.instantiate()
	root.add_child(lab)

	for i in range(10):
		await process_frame

	var summit_cell := Vector2i(49, 37)
	print("Target summit cell: ", summit_cell)

	# 1. Deploy melee trial via SiteController
	print("Deploying melee trial...")
	lab.site_controller._deploy_melee_trial()
	for i in range(5):
		await process_frame

	var friendly: TerrainArmy = lab.combat_armies[0]
	var enemy: TerrainArmy = lab.combat_armies[1]
	assert(friendly != null and friendly.combat_units.size() == 100, "Friendly army must have 100 units")
	assert(enemy != null and enemy.combat_units.size() == 100, "Enemy army must have 100 units")

	var f_start_medoid := friendly._get_active_members_medoid()
	var e_start_medoid := enemy._get_active_members_medoid()
	print("Initial Friendly medoid: ", f_start_medoid)
	print("Initial Enemy medoid: ", e_start_medoid)

	# 2. Select mountaintop cell and issue MOVE to Friendly army (Team 0)
	lab.site_controller.select_cell(summit_cell)
	lab.site_controller._test_army_order(TerrainArmy.CombatOrder.MOVE, summit_cell)
	print("Friendly order issued. Order: ", friendly.combat_order, " Status: ", friendly.command_status)

	# 3. Select mountaintop cell and issue MOVE to Enemy army (Team 1)
	lab.site_controller.trial_command_team.select(1)
	lab.site_controller._trial_team_order(TerrainArmy.CombatOrder.MOVE)
	print("Enemy order issued. Order: ", enemy.combat_order, " Status: ", enemy.command_status)

	var f_plan: CombatMovePlan = friendly.get_active_move_plan()
	var e_plan: CombatMovePlan = enemy.get_active_move_plan()
	assert(f_plan != null, "Friendly CombatMovePlan must be initialized")
	assert(e_plan != null, "Enemy CombatMovePlan must be initialized")

	# 4. Simulate 250 frames
	print("\nSimulating 250 frames of dual-army ascent...")
	for f in range(1, 251):
		await process_frame
		if f % 50 == 0:
			var fc = f_plan.macro_cursor if f_plan else -1
			var ec = e_plan.macro_cursor if e_plan else -1
			var f_med = friendly._get_active_members_medoid()
			var e_med = enemy._get_active_members_medoid()
			var f_med_s = f_plan.get_median_path_s() if f_plan else -1.0
			var e_med_s = e_plan.get_median_path_s() if e_plan else -1.0
			print("Frame %3d: Friendly cursor=%2d med_s=%4.1f medoid=%s | Enemy cursor=%2d med_s=%4.1f medoid=%s" % [
				f, fc, f_med_s, f_med, ec, e_med_s, e_med
			])

	# 5. Verify Results
	var f_final_medoid := friendly._get_active_members_medoid()
	var e_final_medoid := enemy._get_active_members_medoid()
	var f_disp: int = absi(f_final_medoid.x - f_start_medoid.x) + absi(f_final_medoid.y - f_start_medoid.y)
	var e_disp: int = absi(e_final_medoid.x - e_start_medoid.x) + absi(e_final_medoid.y - e_start_medoid.y)

	print("\n--- Final Verification Results ---")
	print("Friendly displacement: %d cells (from %s to %s)" % [f_disp, f_start_medoid, f_final_medoid])
	print("Enemy displacement:    %d cells (from %s to %s)" % [e_disp, e_start_medoid, e_final_medoid])
	print("Friendly final cursor: %d, order: %d" % [f_plan.macro_cursor if f_plan else -1, friendly.combat_order])
	print("Enemy final cursor:    %d, order: %d" % [e_plan.macro_cursor if e_plan else -1, enemy.combat_order])

	assert(friendly.combat_order == TerrainArmy.CombatOrder.MOVE, "Friendly army must remain in MOVE order without aborting")
	assert(enemy.combat_order == TerrainArmy.CombatOrder.MOVE, "Enemy army must remain in MOVE order without aborting")
	assert(f_plan.macro_cursor >= 40, "Friendly macro_cursor must have progressed >= 40 (got %d)" % f_plan.macro_cursor)
	assert(e_plan.macro_cursor >= 40, "Enemy macro_cursor must have progressed >= 40 (got %d)" % e_plan.macro_cursor)
	assert(f_disp >= 15, "Friendly medoid displacement must be >= 15 cells (got %d)" % f_disp)
	assert(e_disp >= 15, "Enemy medoid displacement must be >= 15 cells (got %d)" % e_disp)

	print("\nTEST PASSED: Both Friendly and Enemy 100-man armies successfully and continuously advanced up the mountain!")
	quit(0)
