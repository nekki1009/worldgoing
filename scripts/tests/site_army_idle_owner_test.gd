extends "res://scripts/tests/site_army_scale_rules_test.gd"
const Phase6 = preload("res://scripts/tests/fixtures/terrain_army_prepare_phase6.gd")
const LabPhase6 = preload("res://scripts/tests/fixtures/terrain_lab_fatigue_phase6.gd")

class Before extends Phase6:
	func _complete_move(index: int) -> void:
		super._complete_move(index)
		combat_order = CombatOrder.HOLD # Reentrant-order test seam after the real commit.

class After extends TerrainArmy:
	func _complete_move(index: int) -> void:
		super._complete_move(index)
		combat_order = CombatOrder.HOLD

func _run() -> void:
	for scenario in range(3):
		var before := _fixture(false, 8, false, Before, LabPhase6)
		var after := _fixture(false, 8, false, After)
		var fallback := _fixture(false, 8, false, After)
		for lab: TerrainLab in [before, after, fallback]:
			for army: TerrainArmy in lab.combat_armies:
				army.native_idle_enabled = lab != fallback
				army.combat_order = TerrainArmy.CombatOrder.ATTACK
				army._command_elapsed = 0.0
				for row: Dictionary in army.combat_units:
					row.hp = 100.0; row.ko = 0.0; row.stun = 0.0; row.grace = 0.0
					row.pose = "idle"; row.age = 0.0; row.think = 0.0
					row.fatigue = 0.0; row.fatigue_rest = 20.0
				if scenario < 2:
					var rescuer := 1 if scenario == 0 else 2
					var patient := 2 if scenario == 0 else 1
					army.combat_units[patient].ko = 10.0
					army.combat_units[patient].pose = "unconscious"
					army._cell_owners.erase(army.cells[patient])
					assert(army.start_unit_rescue(rescuer, patient))
					army.combat_units[rescuer].age = 3.99
				else:
					assert(army._reserve_combat_step(6, army.cells[6] + Vector2i.DOWN))
					army.move_progress[6] = 0.999999
		for lab: TerrainLab in [before, after, fallback]:
			lab._advance_fatigue(1.0 / 30.0)
			for army: TerrainArmy in lab.combat_armies: army.prepare_combat(1.0 / 30.0)
		assert(var_to_bytes(_state(before)) == var_to_bytes(_state(after)))
		assert(var_to_bytes(_state(before)) == var_to_bytes(_state(fallback)))
		for side in range(2):
			var original := before.combat_armies[side]
			var candidate := after.combat_armies[side]
			for field: String in ["_unit_rescues", "_cell_owners", "_reserved_cells", "combat_order", "_command_dirty", "_visual_dirty"]:
				assert(var_to_bytes(original.get(field)) == var_to_bytes(candidate.get(field)))
			assert(candidate.native_idle_rows > 0 and candidate.native_fatigue_rows > 0)
			assert(fallback.combat_armies[side].native_idle_rows == 0 and fallback.combat_armies[side].native_fatigue_rows == 0)
			if scenario < 2:
				var patient := 2 if scenario == 0 else 1
				assert(candidate.combat_units[patient].ko == 0.0 and candidate._unit_rescues.is_empty())
				assert(candidate.combat_units[patient].age == (1.0 / 30.0 if scenario == 0 else 0.0))
			else:
				assert(candidate.combat_order == TerrainArmy.CombatOrder.HOLD and candidate.moving_to[6] == TerrainArmy.INVALID_CELL)
				assert(candidate.combat_units[7].think == 0.5, "Later row must see HOLD from earlier completion")
		_dispose(before); _dispose(after); _dispose(fallback)
	print("ARMY_IDLE_OWNER_INTERLEAVING_PASS actual rescue earlier/later, movement commit then HOLD, native-disabled fallback, exact rows/claims")
	quit(0)
