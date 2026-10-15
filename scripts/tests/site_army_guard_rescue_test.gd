extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(18.0).timeout.connect(func() -> void:
		TerrainArmy.release_contact_source()
		quit(1))
	var data := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "guard-rescue-fixture")
	for index in range(data.size.x * data.size.y):
		data.height_levels[index] = 0
		data.flags[index] = TerrainData.Flag.WALKABLE
		data.static_blocked[index] = 0
	data.ramp_edges.fill(0)
	var army := TerrainArmy.new()
	# Use the formal exchange owner; the legacy exact-contact 3D renderer is
	# unrelated to guard/rescue timing and cannot validate materials headless.
	army.exchange_enabled = true
	root.add_child(army)
	army.set_process(false)
	var selected: Array[Vector2i] = []
	for index in range(100):
		selected.append(Vector2i(10 + index % 10, 10 + floori(float(index) / 10)))
	var _army_action_check_1: bool = army.deploy_at(data, null, null, selected) and army.enable_combat(false)
	assert(_army_action_check_1)
	var _army_action_check_2: bool = army.set_unit_guard(1, true)
	assert(_army_action_check_2)
	var _army_action_check_3: bool = not army.start_unit_attack(1, army.cells[2])
	assert(_army_action_check_3)
	var _army_action_check_4: bool = not army._reserve_combat_step(1, army.cells[1] + Vector2i.UP)
	assert(_army_action_check_4)
	army.prepare_combat(0.15)
	assert(army.combat_units[1].pose == "guard" and army.combat_frame(1).clip == "guard")
	var _army_action_check_5: bool = army.set_unit_guard(1, false)
	assert(_army_action_check_5)
	army.prepare_combat(0.15)
	assert(army.combat_units[1].pose == "idle")
	var down := {"result": {"hp": 7.5, "stun": 110.0, "guard_break": false}, "shield": false}
	army.apply_unit_contact(2, down)
	var _army_action_check_6: bool = army.start_unit_rescue(1, 2)
	assert(_army_action_check_6)
	var _army_action_check_7: bool = not army.start_unit_rescue(3, 2)
	assert(_army_action_check_7, "Only one rescuer per patient")
	var _army_action_check_8: bool = not army.start_unit_attack(1, army.cells[2])
	assert(_army_action_check_8)
	army.prepare_combat(1.0)
	army.settle_combat_command()
	var saved := JSON.parse_string(JSON.stringify(army.capture_combat_state())) as Dictionary
	assert(TerrainArmy.valid_combat_state(saved, data))
	var corrupt := saved.duplicate(true)
	corrupt.rescues.append(corrupt.rescues[0].duplicate())
	assert(not TerrainArmy.valid_combat_state(corrupt, data))
	army.restore_combat_state(saved, data, null, null)
	army.prepare_combat(2.9)
	assert(army.combat_units[2].ko > 0 and army.combat_units[1].pose == "rescue")
	army.prepare_combat(0.1)
	assert(army.combat_units[2].ko <= SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS and army.combat_units[2].ko > SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS - 0.2 and army.combat_units[2].hp == 92.5 and army.combat_units[2].pose == "unconscious")
	var _army_action_check_9: bool = not army.start_unit_rescue(3, 2)
	assert(_army_action_check_9, "A second rescue cannot shorten the final hour")
	army.prepare_combat(0.1, SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS)
	assert(not army.combat_can_act(2), "Waking preserves the get-up lock")
	army.prepare_combat(2.2)
	assert(army.combat_can_act(2))
	army.apply_unit_contact(2, down)
	var _army_action_check_10: bool = army.start_unit_rescue(1, 2)
	assert(_army_action_check_10)
	army.prepare_combat(1.0)
	army.apply_unit_contact(2, {"result": {"hp": 0.0, "stun": 1.0, "guard_break": false}, "shield": false})
	assert(army._unit_rescues.is_empty() and army.combat_units[1].pose == "idle")
	var _army_action_check_11: bool = army.start_unit_rescue(1, 2)
	assert(_army_action_check_11)
	army.apply_unit_contact(1, {"result": {"hp": 1.0, "stun": 0.0, "guard_break": false}, "shield": false})
	assert(army._unit_rescues.is_empty())
	var _army_action_check_12: bool = army.start_unit_rescue(1, 2)
	assert(_army_action_check_12)
	var _army_action_check_13: bool = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(25, 20)).ok
	assert(_army_action_check_13)
	assert(army._unit_rescues.is_empty(), "A new move order interrupts help without completing it")
	var _army_action_check_14: bool = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.HOLD).ok
	assert(_army_action_check_14)
	var _army_action_check_15: bool = army.start_unit_rescue(1, 2)
	assert(_army_action_check_15)
	paused = true
	army.prepare_combat(5.0)
	var _army_action_check_16: bool = army.combat_units[1].age == 0.0 and not army.set_unit_guard(3, true)
	assert(_army_action_check_16)
	paused = false
	army.external_blocker = func(cell: Vector2i) -> bool: return cell == army.cells[2]
	army.prepare_combat(4.0)
	army.prepare_combat(0.1, SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS)
	assert(army.combat_units[2].ko > 0.0 and not army.blocks_cell(army.cells[2]), "Rescue cannot stand inside a new occupant")
	army.clear()
	army.queue_free()
	TerrainArmy.release_contact_source()
	await process_frame
	print("SITE ARMY GUARD RESCUE PASS: authored guard locks, four-second help/save continuation, unique rescuer, hit/order/pause interruption, no heal or occupied wake")
	quit(0)
