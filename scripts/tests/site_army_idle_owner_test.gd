extends "res://scripts/tests/site_army_scale_rules_test.gd"
const Phase6 = preload("res://scripts/tests/fixtures/terrain_army_prepare_phase6.gd")
const LabPhase6 = preload("res://scripts/tests/fixtures/terrain_lab_fatigue_phase6.gd")
const TerminalBoundary = preload("res://scripts/tests/fixtures/site_terminal_first_error_test.gd")

var _idle_errors: TerminalBoundary.TerminalFirstError

func _initialize() -> void:
	_idle_errors = TerminalBoundary.TerminalFirstError.new()
	_idle_errors.tree = self
	OS.add_logger(_idle_errors)
	super._initialize()

func _finalize() -> void:
	if _idle_errors == null: return
	OS.remove_logger(_idle_errors)
	_idle_errors.tree = null
	_idle_errors = null

func _stop_on_first_error() -> void:
	TerrainArmy.release_contact_source()
	quit(1)

class Before extends Phase6:
	func _wake_unit(index: int) -> void:
		# Phase6's positive-KO wake call is its rescue endpoint, not natural expiry.
		if float(combat_units[index].ko) > 0.0:
			combat_hot_set(index, &"ko", minf(float(combat_units[index].ko), SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS))
			return
		super._wake_unit(index)

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
					army.apply_unit_contact(patient, {"shield": false, "result": {"hp": 0.0, "stun": 110.0, "guard_break": false}})
					assert(army.combat_units[patient].ko == SiteCombatRules.KNOCKOUT_GAME_SECONDS and army.combat_units[patient].pose == "down")
					assert(not army._cell_owners.has(army.cells[patient]))
					var rescue_started: bool = army.start_unit_rescue(rescuer, patient)
					assert(rescue_started)
					army.combat_units[rescuer].age = 3.99
				else:
					var move_started: bool = army._reserve_combat_step(6, army.cells[6] + Vector2i.DOWN)
					assert(move_started)
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
				var rescuer: int = 1 if scenario == 0 else 2
				var expected_ko: float = SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS - (1.0 / 30.0 if scenario == 0 else 0.0)
				for team: TerrainArmy in [original, candidate, fallback.combat_armies[side]]:
					assert(team.combat_units[patient].ko == expected_ko and team._unit_rescues.is_empty(), "Rescue caps KO at its actual row boundary; later patients still consume this step")
					assert(team.combat_units[patient].hp == 100.0 and team.combat_units[patient].pose == "down" and team.combat_units[patient].age == 1.0 / 30.0, "Rescue does not heal, wake, or reset the patient's pose age")
					assert(not team._cell_owners.has(team.cells[patient]) and not team._reserved_cells.has(team.cells[patient]), "Unconscious patient must not reclaim a cell")
					var before_retry: PackedByteArray = var_to_bytes([team.capture_combat_state(), team._cell_owners, team._reserved_cells, team._unit_rescues, team._command_dirty, team._visual_dirty])
					var rescue_retried: bool = team.start_unit_rescue(rescuer, patient)
					var after_retry: PackedByteArray = var_to_bytes([team.capture_combat_state(), team._cell_owners, team._reserved_cells, team._unit_rescues, team._command_dirty, team._visual_dirty])
					assert(not rescue_retried and after_retry == before_retry, "At or below one hour, repeated rescue is rejected without mutation")
			else:
				assert(candidate.combat_order == TerrainArmy.CombatOrder.HOLD and candidate.moving_to[6] == TerrainArmy.INVALID_CELL)
				assert(candidate.combat_units[7].think == 0.5, "Later row must see HOLD from earlier completion")
		_dispose(before); _dispose(after); _dispose(fallback)
	if _idle_errors.has_failed():
		_stop_on_first_error()
		return
	TerrainArmy.release_contact_source()
	print("ARMY_IDLE_OWNER_INTERLEAVING_PASS actual rescue earlier/later, movement commit then HOLD, native-disabled fallback, exact rows/claims")
	quit(0)
