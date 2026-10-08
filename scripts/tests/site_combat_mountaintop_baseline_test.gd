extends SceneTree
## Baseline regression fixture: verifies and records the pre-upgrade mountaintop
## pathfinding failure (100-soldier formation exhausts 256 expansions on distant
## goal and immediately aborts to HOLD on the first decision tick).

const OUT_DIR := "res://output/combat_movement_v3_baseline"
const PEAK_CELL := Vector2i(49, 37)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var dir_err := DirAccess.make_dir_recursive_absolute(OUT_DIR)
	assert(dir_err == OK or dir_err == ERR_ALREADY_EXISTS)
	
	var lab := load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate() as TerrainLab
	assert(lab != null)
	root.add_child(lab)
	
	# Allow node setup and terrain generation to settle
	for i in range(5):
		await process_frame
		
	assert(lab.terrain.is_walkable(PEAK_CELL), "Peak cell must be walkable")
	
	# Start standard battle test (same as clicking "戰鬥測試" in UI)
	var trial_result: Dictionary = lab.start_melee_trial({})
	assert(trial_result.get("ok", false), "start_melee_trial must succeed")
	
	for i in range(5):
		await process_frame
		
	var army: TerrainArmy = lab.army
	assert(army != null and army.has_army() and army.combat_enabled)
	assert(army.cells.size() == 100)
	
	var initial_cells := army.cells.duplicate()
	var initial_commander := army.current_commander
	assert(initial_commander >= 0)
	
	army.reset_movement_metrics()
	
	# Issue MOVE order to mountaintop
	var order_result := army.issue_combat_order(initial_commander, TerrainArmy.CombatOrder.MOVE, PEAK_CELL)
	assert(order_result.get("ok", false), "MOVE order should be accepted initially")
	assert(army.combat_order == TerrainArmy.CombatOrder.MOVE)
	
	# Settle until order delay expires and first movement step is evaluated (~60 frames)
	var aborted_frame := -1
	for frame in range(90):
		await process_frame
		if army.combat_order == TerrainArmy.CombatOrder.HOLD and army.command_status.find("未找到") >= 0:
			aborted_frame = frame
			break
			
	var metrics: Dictionary = army.get_movement_metrics()
	
	# Assertions confirming the documented baseline failure mode:
	assert(aborted_frame >= 0, "Expected army to abort to HOLD after order delay")
	assert(army.combat_order == TerrainArmy.CombatOrder.HOLD, "Order should have collapsed to HOLD")
	assert(army.command_status == "未找到合法通路；就地自衛，等待新令", "Expected failure notice")
	assert(metrics.route_calls > 0, "Route calls must be greater than 0")
	assert(metrics.expanded_nodes > 0, "Expanded nodes must be recorded")
	assert(metrics.accepted_count == 0, "Accepted steps should be 0 (no progress)")
	assert(army.cells == initial_cells, "No soldier should have moved")
	assert(army.combat_slots == initial_cells, "Combat slots should have collapsed back to cells")
	
	# Save baseline summary record
	var record := {
		"fixture": "site_combat_mountaintop_baseline",
		"map_preset": "TERRACED_HIGHLAND",
		"seed": 12345,
		"roster_size": army.cells.size(),
		"peak_cell": [PEAK_CELL.x, PEAK_CELL.y],
		"initial_reference": [army.command_reference.x, army.command_reference.y],
		"aborted_at_frame": aborted_frame,
		"order_delay": army._order_delay,
		"final_combat_order": army.combat_order,
		"final_command_status": army.command_status,
		"metrics": metrics,
		"reproduced": true
	}
	
	var json_str := JSON.stringify(record, "  ")
	var file := FileAccess.open(OUT_DIR + "/mountaintop_baseline.json", FileAccess.WRITE)
	if file != null:
		file.store_string(json_str)
		file.close()
		
	lab.queue_free()
	print("COMBAT_MOUNTAINTOP_BASELINE_PASS: bug reproduced stably; route_calls=", metrics.route_calls,
		" expanded_nodes=", metrics.expanded_nodes, " accepted=", metrics.accepted_count,
		" aborted_frame=", aborted_frame)
	quit(0)
