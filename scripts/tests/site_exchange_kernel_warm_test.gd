extends "res://scripts/tests/site_army_scale_rules_test.gd"

func _run() -> void:
	create_timer(45.0).timeout.connect(func() -> void: quit(1))
	var script := load("res://scripts/terrain_lab/terrain_army.gd") as GDScript
	assert(script.source_code.count("selected.size() > MAX_ROSTER_SIZE") == 1)
	script.source_code = script.source_code.replace("selected.size() > MAX_ROSTER_SIZE", "selected.size() > 2500")
	assert(script.reload(true) == OK)
	for count in [100, 2500]:
		var cold := _fixture(false, count, true)
		var warm := _fixture(false, count, true)
		var untouched := var_to_bytes([_state(warm), warm.terrain.site, warm._action_time_remainder])
		warm._prepare_exchange_kernel(true)
		assert(warm._exchange_kernel != null and warm._exchange_kernel_checked)
		var kernel := warm._exchange_kernel
		warm._prepare_exchange_kernel(true)
		assert(warm._exchange_kernel == kernel)
		assert(untouched == var_to_bytes([_state(warm), warm.terrain.site, warm._action_time_remainder]), "Preparation must not start a battle or advance people/site/clock")
		for tick in range(90 if count == 100 else 60):
			cold._advance_combat(1.0 / 30.0)
			warm._advance_combat(1.0 / 30.0)
			assert(var_to_bytes(_state(cold)) == var_to_bytes(_state(warm)))
			for side in range(2):
				var a: TerrainArmy = cold.combat_armies[side]
				var b: TerrainArmy = warm.combat_armies[side]
				assert(a.command_rng.state == b.command_rng.state)
				assert(var_to_bytes([a.combat_slots, a._reserved_cells, a._cell_owners, a._command_elapsed]) == var_to_bytes([b.combat_slots, b._reserved_cells, b._cell_owners, b._command_elapsed]))
		assert(warm.exchange_count > 0)
		print("EXCHANGE_KERNEL_WARM_PASS people=", count * 2, " no startup state/time/RNG change; one kernel; exact cold/warm steps/claims/events")
		_dispose(cold)
		_dispose(warm)
	quit(0)
