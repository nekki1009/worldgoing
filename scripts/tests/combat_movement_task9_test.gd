extends SceneTree
## Task 9 smoke test: CombatDeploymentPlan/CombatMovePlan snapshot round-trip
## and early mountaintop progress. Full arrival and SiteStore I/O are separate tests.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")
const TerrainArmyScript = preload("res://scripts/terrain_lab/terrain_army.gd")
const PEAK_CELL := Vector2i(49, 37)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Running Task 9 Snapshot & Mountaintop Progress Smoke Test ---")

	# -------------------------------------------------------------------------
	# 1. Save/Load Persistence Test
	# -------------------------------------------------------------------------
	var flat_map := Helper.build_flat_map(50, 50)
	var army1 := Helper.create_test_army(flat_map, 1, 0, 100, Vector2i(5, 5))
	var commander1 := army1.current_commander
	assert(commander1 >= 0)

	var move_res := army1.issue_combat_order(commander1, TerrainArmy.CombatOrder.MOVE, Vector2i(25, 25))
	assert(move_res.get("ok", false), "MOVE order should succeed on flat map")
	assert(army1.combat_order == TerrainArmy.CombatOrder.MOVE)
	assert(army1.get_active_move_plan() != null, "Active move plan should exist")
	assert(army1.get_active_deployment_plan() != null, "Active deployment plan should exist")

	var plan1 = army1.get_active_deployment_plan()
	var move_plan1 = army1.get_active_move_plan()
	assert(plan1.platform_slots.size() == 100, "Open ground must provide all 100 platform final slots")
	assert(plan1.queue_member_ids.is_empty(), "Open ground with capacity must not assign anyone to an approach queue")
	assert(plan1.member_slot_map.size() == 100 and plan1.slot_owner_map.size() == 100)
	for member_id in plan1.member_slot_map:
		var slot: Vector2i = plan1.member_slot_map[member_id]
		assert(flat_map.is_walkable(slot) and plan1.platform_slots.has(slot))
		assert(plan1.slot_owner_map.get(slot, -1) == member_id, "Final assignment must have a unique matching owner")

	# Capture state
	var snapshot := army1.capture_combat_state()
	assert(snapshot.has("combat_deployment_plan"), "Snapshot must serialize combat_deployment_plan")
	assert(snapshot.has("combat_move_plan"), "Snapshot must serialize combat_move_plan")

	# Restore into army2
	var army2 := TerrainArmyScript.new()
	army2.roster_size = 100
	army2.exchange_enabled = true
	army2.restore_combat_state(snapshot, flat_map, null, null)

	assert(army2.combat_order == TerrainArmy.CombatOrder.MOVE)
	assert(army2.get_active_deployment_plan() != null, "Restored army must have deployment plan")
	assert(army2.get_active_move_plan() != null, "Restored army must have move plan")

	var plan2 = army2.get_active_deployment_plan()
	var move_plan2 = army2.get_active_move_plan()
	assert(plan2.formation_id == plan1.formation_id)
	assert(plan2.order_serial == plan1.order_serial)
	assert(plan2.platform_slots.size() == plan1.platform_slots.size())
	assert(plan2.approach_queue_slots.size() == plan1.approach_queue_slots.size())
	assert(plan2.member_slot_map == plan1.member_slot_map)
	assert(plan2.slot_owner_map == plan1.slot_owner_map)
	assert(move_plan2.macro_path.size() == move_plan1.macro_path.size())
	print("TASK 9: Snapshot serialization and restoration verified (100 platform, 0 queue)")
	army1.free()
	army2.free()

	# -------------------------------------------------------------------------
	# 2. Early mountaintop progress smoke check on TERRACED_HIGHLAND
	# -------------------------------------------------------------------------
	var lab := load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate() as TerrainLab
	assert(lab != null)
	root.add_child(lab)

	for i in range(5):
		await process_frame

	assert(lab.terrain.is_walkable(PEAK_CELL), "Peak cell must be walkable")

	var trial_result: Dictionary = lab.start_melee_trial({})
	assert(trial_result.get("ok", false), "start_melee_trial must succeed")

	for i in range(5):
		await process_frame

	var test_army: TerrainArmy = lab.army
	assert(test_army != null and test_army.has_army() and test_army.combat_enabled)
	assert(test_army.cells.size() == 100)

	var initial_cells := test_army.cells.duplicate()
	var initial_commander := test_army.current_commander
	assert(initial_commander >= 0)

	test_army.reset_movement_metrics()

	# Issue MOVE order to mountaintop peak (49, 37)
	var order_result := test_army.issue_combat_order(initial_commander, TerrainArmy.CombatOrder.MOVE, PEAK_CELL)
	print("Task 9 order_result: ", order_result)
	assert(order_result.get("ok", false), "MOVE order to peak must be accepted")
	assert(test_army.combat_order == TerrainArmy.CombatOrder.MOVE)
	assert(test_army.get_active_move_plan() != null, "Macro move plan must be active")
	assert(test_army.get_active_deployment_plan() != null, "Deployment plan must be active")

	# Retain the original 120-frame smoke window; this is not a completion deadline.
	var aborted_frame := -1
	for frame in range(120):
		await process_frame
		if test_army.combat_order == TerrainArmy.CombatOrder.HOLD and test_army.command_status.find("未找到") >= 0:
			aborted_frame = frame
			break

	var metrics: Dictionary = test_army.get_movement_metrics()
	print("Task 9 metrics: ", metrics)
	print("Task 9 army status: ", test_army.command_status, " order: ", test_army.combat_order, " order_delay: ", test_army._order_delay)
	if test_army.get_active_move_plan() != null:
		var mp = test_army.get_active_move_plan()
		print("Task 9 move plan cursor: ", mp.macro_cursor, " path_len: ", mp.macro_path.size(), " width: ", mp.current_width)

	# Verify early movement only; full arrival needs the bounded journey tests.
	assert(aborted_frame == -1, "Army must NOT abort on mountaintop path (baseline failed at frame 60)!")
	assert(test_army.combat_order == TerrainArmy.CombatOrder.MOVE, "Army should still be advancing or in transit")
	assert(metrics.accepted_count > 0, "Soldiers must have accepted movement steps towards peak (baseline had 0)!")
	assert(test_army.cells != initial_cells, "Soldier positions must have progressed forward towards peak!")

	print("TASK 9: Mountaintop movement past frame 60 verified (accepted_steps=", metrics.accepted_count, ")")
	print("TASK 9 SMOKE PASS: Snapshot round-trip and early mountaintop progress; full arrival and SiteStore I/O not covered")

	lab.queue_free()
	quit(0)
