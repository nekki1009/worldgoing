extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(18.0).timeout.connect(func() -> void: quit(1))
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
	assert(army.deploy_at(data, null, null, selected) and army.enable_combat(false))
	assert(army.set_unit_guard(1, true))
	assert(not army.start_unit_attack(1, army.cells[2]))
	assert(not army._reserve_combat_step(1, army.cells[1] + Vector2i.UP))
	army.prepare_combat(0.15)
	assert(army.combat_units[1].pose == "guard" and army.combat_frame(1).clip == "guard")
	assert(army.set_unit_guard(1, false))
	army.prepare_combat(0.15)
	assert(army.combat_units[1].pose == "idle")
	var down := {"result": {"hp": 7.5, "stun": 110.0, "guard_break": false}, "shield": false}
	army.apply_unit_contact(2, down)
	assert(army.start_unit_rescue(1, 2))
	assert(not army.start_unit_rescue(3, 2), "Only one rescuer per patient")
	assert(not army.start_unit_attack(1, army.cells[2]))
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
	assert(army.combat_units[2].ko == 0.0 and army.combat_units[2].hp == 92.5 and army.combat_units[2].pose == "get_up")
	assert(not army.combat_can_act(2), "Waking preserves the get-up lock")
	army.prepare_combat(2.3)
	assert(army.combat_can_act(2))
	army.apply_unit_contact(2, down)
	assert(army.start_unit_rescue(1, 2))
	army.prepare_combat(1.0)
	army.apply_unit_contact(2, {"result": {"hp": 0.0, "stun": 1.0, "guard_break": false}, "shield": false})
	assert(army._unit_rescues.is_empty() and army.combat_units[1].pose == "idle")
	assert(army.start_unit_rescue(1, 2))
	army.apply_unit_contact(1, {"result": {"hp": 1.0, "stun": 0.0, "guard_break": false}, "shield": false})
	assert(army._unit_rescues.is_empty())
	assert(army.start_unit_rescue(1, 2))
	assert(army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.RETREAT, Vector2i(25, 20)).ok)
	assert(army._unit_rescues.is_empty(), "A new retreat order interrupts help without completing it")
	assert(army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.HOLD).ok)
	assert(army.start_unit_rescue(1, 2))
	paused = true
	army.prepare_combat(5.0)
	assert(army.combat_units[1].age == 0.0 and not army.set_unit_guard(3, true))
	paused = false
	army.external_blocker = func(cell: Vector2i) -> bool: return cell == army.cells[2]
	army.prepare_combat(4.0)
	assert(army.combat_units[2].ko > 0.0 and not army.blocks_cell(army.cells[2]), "Rescue cannot stand inside a new occupant")
	army.clear()
	army.queue_free()
	await process_frame
	print("SITE ARMY GUARD RESCUE PASS: authored guard locks, four-second help/save continuation, unique rescuer, hit/order/pause interruption, no heal or occupied wake")
	quit(0)
