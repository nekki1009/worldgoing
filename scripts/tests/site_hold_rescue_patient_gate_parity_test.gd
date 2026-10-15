extends "res://scripts/tests/site_army_scale_rules_test.gd"
## Same original Lab/Army owners and native hot rows; compare the HOLD rescue gate per action step.

const STEPS := 17 # First due review and the next 0.5-second review at 30 Hz.

func _setup_world(gated: bool, patient_kind: String, columns: bool = true) -> TerrainLab:
	var lab := _fixture(false, 8)
	lab.enemy_query_owner_cells_enabled = true
	for team: TerrainArmy in lab.combat_armies:
		team.enemy_query = lab._nearest_unit_enemy
		team.combat_order = TerrainArmy.CombatOrder.HOLD
		team.combat_attacking = false
		team.hold_empty_rescue_skip_enabled = gated
		team.hold_rescue_column_enabled = columns
		team.native_hold_no_patient_enabled = false # Preserve the original three-way gate oracle below.
		team.native_hot_enabled = true
		var _army_action_check_1: bool = team._try_install_combat_hot_store()
		assert(_army_action_check_1)
		for index in range(team.combat_units.size()):
			team.combat_hot_set(index, &"think", 0.0)
	var holding: TerrainArmy = lab.combat_armies[0]
	if patient_kind == "member":
		holding.combat_hot_set(1, &"ko", SiteCombatRules.KNOCKOUT_GAME_SECONDS)
		holding.combat_hot_set(1, &"pose", "unconscious")
		holding._cell_owners.erase(holding.cells[1])
		assert(holding._rescue_reachable(0, 1))
	elif patient_kind == "player":
		var actor := TerrainTestCharacter.new()
		actor.person_id = 900001
		actor.faction_id = holding.faction_id
		actor.terrain_cell = holding.cells[0] + Vector2i.UP
		actor.position = (Vector2(actor.terrain_cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
		actor.knockout_left = SiteCombatRules.KNOCKOUT_GAME_SECONDS
		holding.player_member = actor
		assert(holding._rescue_reachable(0, TerrainArmy.PLAYER_MEMBER))
	return lab

func _owner_state(lab: TerrainLab) -> Array:
	var state := [lab._exchange_round, lab._exchange_phase, lab.exchange_count, lab.exchange_results.duplicate(true)]
	for team: TerrainArmy in lab.combat_armies:
		var player := []
		if is_instance_valid(team.player_member):
			player = [team.player_member.person_id, team.player_member.terrain_cell,
				team.player_member.hp, team.player_member.knockout_left,
				team.player_member._army_rescuer == team]
		state.append([team.capture_combat_state(), team._cell_owners.duplicate(true),
			team._reserved_cells.duplicate(true), team._unit_rescues.duplicate(true), player])
	return state

func _dispose_world(lab: TerrainLab) -> void:
	for team: TerrainArmy in lab.combat_armies:
		if is_instance_valid(team.player_member):
			team.player_member.free()
			team.player_member = null
	_dispose(lab)

func _native_world(enabled: bool, scenario: String) -> TerrainLab:
	var lab := _setup_world(true, "player" if scenario == "player" else "none")
	for team: TerrainArmy in lab.combat_armies:
		team.native_hold_no_patient_enabled = enabled
		team.combat_hot_diagnostics_enabled = true
		for index in range(team.combat_units.size()):
			team.combat_hot_set(index, &"hp", 100.0)
			team.combat_hot_set(index, &"stun", 0.0)
		team.combat_hot_reset_stats()
	var holding: TerrainArmy = lab.combat_armies[0]
	match scenario:
		"member", "threshold_below", "threshold_above":
			var knockout := SiteCombatRules.KNOCKOUT_GAME_SECONDS
			if scenario == "threshold_below": knockout = SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS - 1.0
			if scenario == "threshold_above": knockout = SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS + 1.0 / 60.0
			holding.combat_hot_set(1, &"ko", knockout)
			holding.combat_hot_set(1, &"pose", "unconscious")
			holding._cell_owners.erase(holding.cells[1])
			assert(holding._rescue_reachable(0, 1))
		"controlled":
			lab.terrain.site["controlled_person_id"] = holding.combat_identity(2)
		"nonmember":
			holding.combat_hot_set(2, &"member", false)
		"custom_enemy":
			holding.enemy_query = func(_team: TerrainArmy, _index: int) -> Dictionary:
				lab.set_meta("callback_count", int(lab.get_meta("callback_count", 0)) + 1)
				return {}
		"custom_busy":
			holding.person_busy_query = func(_identity: int) -> bool:
				lab.set_meta("callback_count", int(lab.get_meta("callback_count", 0)) + 1)
				return false
		"custom_routed":
			holding.sustain_routed_query = func(_team: TerrainArmy) -> bool:
				lab.set_meta("callback_count", int(lab.get_meta("callback_count", 0)) + 1)
				return false
		"columns_disabled":
			holding.hold_rescue_column_enabled = false
		"timers":
			for index in range(holding.combat_units.size()):
				holding.combat_hot_set(index, &"stun", 2.0)
				holding.combat_hot_set(index, &"grace", 0.05)
				for field: StringName in [&"exchange_cooldown", &"exchange_stagger", &"exchange_skill_cooldown", &"ranged_cooldown"]:
					holding.combat_hot_set(index, field, 0.1)
		"visual_expiry":
			holding.combat_hot_set(2, &"exchange_visual", {"pose": "hit", "age": 0.2, "left": 1.0 / 60.0, "facing": Vector2i.DOWN})
		"rescue_completion":
			holding.combat_hot_set(3, &"ko", SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS - 1.0)
			holding.combat_hot_set(3, &"pose", "unconscious")
			holding._cell_owners.erase(holding.cells[3])
			holding.combat_hot_set(2, &"pose", "rescue")
			holding.combat_hot_set(2, &"age", float(TerrainArmy.CombatTimings.POSE_SECONDS[&"rescue"]))
			holding._unit_rescues[2] = {"patient": 3, "revision": 0}
	return lab

func _native_case(scenario: String, steps: int = STEPS) -> String:
	var reference := _native_world(false, scenario)
	var candidate := _native_world(true, scenario)
	var team: TerrainArmy = candidate.combat_armies[0]
	var failure := ""
	if not team._combat_hot_store.has_method("advance_numeric_hold_no_patient_reason"):
		failure = "New HOLD native capability was not loaded"
	for step in range(steps + 1):
		if not failure.is_empty(): break
		if step > 0:
			for lab: TerrainLab in [reference, candidate]:
				# Compare the original prepare owner directly, including divergent wall/game clocks.
				for army: TerrainArmy in lab.combat_armies:
					army.prepare_combat(1.0 / 30.0, 0.2 if scenario == "timers" else 1.0 / 30.0)
		if var_to_bytes(_owner_state(reference)) != var_to_bytes(_owner_state(candidate)) \
			or reference.get_meta("callback_count", 0) != candidate.get_meta("callback_count", 0):
			failure = "%s new native HOLD changed owner/save/callback state at step %d" % [scenario, step]
	var original: Dictionary = reference.combat_armies[0].combat_hot_stats()
	var optimized: Dictionary = team.combat_hot_stats()
	if failure.is_empty() and scenario == "none":
		if int(original.fallback_rows) <= 0 or int(optimized.fallback_rows) != 0 \
			or int(optimized.native_rows) != steps * team.combat_units.size() \
			or int((optimized.owner_reasons as Dictionary).get("think_hold", 0)) != 0 \
			or team.hold_rescue_column_uses < 2:
			failure = "Ordinary no-patient HOLD did not remove both due-review owner fallbacks: " + str(optimized)
	if failure.is_empty() and scenario in ["member", "player", "threshold_above", "controlled", "nonmember", "custom_enemy", "custom_busy", "custom_routed", "columns_disabled"]:
		if int(optimized.fallback_rows) <= 0 or int((optimized.owner_reasons as Dictionary).get("think_hold", 0)) <= 0:
			failure = "%s failed to retain a required HOLD owner fallback: %s" % [scenario, optimized]
	if failure.is_empty() and scenario in ["custom_enemy", "custom_busy", "custom_routed"] \
		and int(candidate.get_meta("callback_count", 0)) <= 0:
		failure = "%s custom callback was not exercised" % scenario
	if failure.is_empty() and scenario in ["controlled", "nonmember"] and float(team.combat_hot_get(2, &"think")) != 0.0:
		failure = "%s incorrectly reset the excluded row's think clock" % scenario
	if failure.is_empty() and scenario in ["visual_expiry", "rescue_completion"]:
		var reason := "visual_expiry" if scenario == "visual_expiry" else "rescue"
		if team.hold_rescue_column_uses < 2 or int((optimized.owner_reasons as Dictionary).get(reason, 0)) != 1 \
			or int((optimized.owner_reasons as Dictionary).get("think_hold", 0)) != 0:
			failure = "%s did not recompute absence after its interleaved owner barrier: %s" % [scenario, optimized]
		elif scenario == "visual_expiry" and team.combat_hot_has(2, &"exchange_visual") \
			or scenario == "rescue_completion" and (team._unit_rescues.has(2) or str(team.combat_hot_get(2, &"pose")) != "idle"):
			failure = "%s did not complete the real ordered owner effect" % scenario
	_dispose_world(reference)
	_dispose_world(candidate)
	return failure

func _save_clock_state(lab: TerrainLab) -> PackedByteArray:
	var clocks := []
	for team: TerrainArmy in lab.combat_armies:
		for field: StringName in [&"hp", &"ko", &"age", &"think", &"stun", &"grace", &"exchange_cooldown", &"exchange_stagger", &"exchange_skill_cooldown", &"ranged_cooldown", &"exchange_pose_duration"]:
			clocks.append(team.combat_hot_column(field))
		clocks.append_array([team.move_progress, team.move_duration])
	return var_to_bytes(clocks)

func _state_difference(original: Variant, loaded: Variant, path: String = "owner") -> String:
	if original == loaded: return ""
	if original is Dictionary and loaded is Dictionary:
		for key: Variant in original:
			if not loaded.has(key): return "%s.%s missing after restore" % [path, key]
			var difference := _state_difference(original[key], loaded[key], "%s.%s" % [path, key])
			if not difference.is_empty(): return difference
		for key: Variant in loaded:
			if not original.has(key): return "%s.%s added after restore" % [path, key]
	elif original is Array and loaded is Array and original.size() == loaded.size():
		for index in range(original.size()):
			var difference := _state_difference(original[index], loaded[index], "%s[%d]" % [path, index])
			if not difference.is_empty(): return difference
	return "%s differs: %s != %s" % [path, original, loaded]

func _save_continuation_case(boundary: String) -> String:
	var uninterrupted := _native_world(true, "none")
	var restored := _native_world(true, "none")
	var failure := ""
	for lab: TerrainLab in [uninterrupted, restored]:
		for team: TerrainArmy in lab.combat_armies:
			# Restore explicitly supplies this existing optional body default. Save a
			# current-format body so the oracle compares continuation, not migration.
			for row: Dictionary in team.combat_units: row["work_resting"] = false
			if boundary == "rescue" and team == lab.combat_armies[0]:
				# Use the original contact owner so KO, occupancy and command dirtiness
				# enter the same valid save boundary as formal gameplay.
				team.apply_unit_contact(1, {"result": {"hp": 7.5, "stun": 110.0, "guard_break": false}, "shield": false})
			if boundary == "before_due":
				for index in range(team.combat_units.size()): team.combat_hot_set(index, &"think", 0.01)
			else:
				team.prepare_combat(1.0 / 30.0) # Save just after the native reset or actual rescue admission.
			team.settle_combat_command() # Original action-tick/save boundary refreshes KO eligibility/presence.
	if boundary == "rescue" and uninterrupted.combat_armies[0]._unit_rescues.is_empty():
		failure = "Save-continuation fixture did not start the real member rescue"
	for side in range(uninterrupted.combat_armies.size()):
		var source: TerrainArmy = uninterrupted.combat_armies[side]
		var copy: TerrainArmy = restored.combat_armies[side]
		# The same full-precision JSON boundary used by Site persistence retains hot clock bits.
		var saved: Dictionary = JSON.parse_string(JSON.stringify(source.capture_combat_state(), "", true, true))
		if not TerrainArmy.valid_combat_state(saved, restored.terrain):
			failure = "%s saved hot army failed original schema validation" % boundary
			break
		copy.restore_combat_state(saved, restored.terrain, null, null)
		copy.enemy_query = restored._nearest_unit_enemy
		copy.controlled_person_query = restored.controlled_person_id
		if not copy.combat_hot_active() or not copy._combat_hot_store.has_method("advance_numeric_hold_no_patient_reason"):
			failure = "%s restore did not rebind the original hot/native capability" % boundary
			break
		copy.combat_hot_reset_stats()
	var steps := 122 if boundary == "rescue" else STEPS # Continue through real four-second help completion.
	for step in range(steps + 1):
		if not failure.is_empty(): break
		if step > 0:
			for lab: TerrainLab in [uninterrupted, restored]:
				for team: TerrainArmy in lab.combat_armies:
					team.prepare_combat(1.0 / 30.0)
					team.settle_combat_command()
		var original: Variant = JSON.parse_string(JSON.stringify(_owner_state(uninterrupted), "", true, true))
		var loaded: Variant = JSON.parse_string(JSON.stringify(_owner_state(restored), "", true, true))
		if original != loaded or _save_clock_state(uninterrupted) != _save_clock_state(restored):
			failure = "%s uninterrupted/restored owner, full save, or exact hot clocks differ at step %d: %s" % [boundary, step, _state_difference(original, loaded)]
			break
		for side in range(uninterrupted.combat_armies.size()):
			var source: TerrainArmy = uninterrupted.combat_armies[side]
			var copy: TerrainArmy = restored.combat_armies[side]
			if source.cells != copy.cells or source.moving_to != copy.moving_to \
				or source._cell_owners != copy._cell_owners or source._reserved_cells != copy._reserved_cells \
				or source._unit_rescues != copy._unit_rescues:
				failure = "%s restore changed original cell, reservation, or rescue authority at step %d" % [boundary, step]
				break
	if failure.is_empty() and boundary == "rescue":
		if not restored.combat_armies[0]._unit_rescues.is_empty() \
			or float(restored.combat_armies[0].combat_hot_get(1, &"ko")) > SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS:
			failure = "Restored hot member rescue did not reach its original completion"
	elif failure.is_empty():
		for team: TerrainArmy in restored.combat_armies:
			if int(team.combat_hot_stats().fallback_rows) != 0 or team.hold_rescue_column_uses == 0:
				failure = "%s loaded healthy HOLD did not exercise the no-patient native path" % boundary
	_dispose_world(uninterrupted)
	_dispose_world(restored)
	return failure

func _run() -> void:
	if "--hold-save-only" in OS.get_cmdline_user_args():
		for boundary: String in ["before_due", "after_reset", "rescue"]:
			var failure := _save_continuation_case(boundary)
			if not failure.is_empty():
				push_error(failure)
				TerrainArmy.release_contact_source()
				quit(1)
				return
		print("HOLD_SAVE_CONTINUATION_DIAGNOSTIC_PASS")
		TerrainArmy.release_contact_source()
		quit(0)
		return
	for patient_kind: String in ["none", "member", "player"]:
		var reference := _setup_world(false, patient_kind)
		var scalar := _setup_world(true, patient_kind, false)
		var candidate := _setup_world(true, patient_kind)
		var failure := ""
		for step in range(STEPS + 1):
			if step > 0:
				reference._advance_combat(1.0 / 30.0)
				scalar._advance_combat(1.0 / 30.0)
				candidate._advance_combat(1.0 / 30.0)
			var original: PackedByteArray = var_to_bytes(_owner_state(reference))
			if original != var_to_bytes(_owner_state(scalar)) or original != var_to_bytes(_owner_state(candidate)):
				failure = "%s owner or save state differs at action step %d" % [patient_kind, step]
				break
		if failure.is_empty() and patient_kind == "none" and not (reference.enemy_query_owner_cell_hits > 0 \
			and scalar.enemy_query_owner_cell_hits == 0 and candidate.enemy_query_owner_cell_hits == 0):
			failure = "No-patient A/B did not prove that both guarded paths skip enemy queries"
		if failure.is_empty() and (candidate.combat_armies[0].hold_rescue_column_uses == 0 \
			or scalar.combat_armies[0].hold_rescue_column_uses != 0):
			failure = "%s column A/B did not exercise the enabled path alone" % patient_kind
		if failure.is_empty() and patient_kind != "none":
			var original_rescues: Dictionary = reference.combat_armies[0]._unit_rescues
			var scalar_rescues: Dictionary = scalar.combat_armies[0]._unit_rescues
			var candidate_rescues: Dictionary = candidate.combat_armies[0]._unit_rescues
			var patient := 1 if patient_kind == "member" else TerrainArmy.PLAYER_MEMBER
			if original_rescues.is_empty() or original_rescues != scalar_rescues or original_rescues != candidate_rescues \
				or int(original_rescues.get(0, {}).get("patient", -999)) != patient:
				failure = "%s original/scalar/column rescue did not start for the same patient" % patient_kind
		_dispose_world(reference)
		_dispose_world(scalar)
		_dispose_world(candidate)
		if not failure.is_empty():
			push_error(failure)
			TerrainArmy.release_contact_source()
			quit(1)
			return
	var unsupported := _setup_world(true, "none")
	var team: TerrainArmy = unsupported.combat_armies[0]
	team.combat_hot_erase(0, &"member")
	team._borrow_combat_hot_row(0)
	var missing_member_falls_back: bool = team._hold_rescue_patient_from_columns() == null
	team._return_combat_hot_row()
	team.combat_hot_set(0, &"member", true)
	team._borrow_combat_hot_row(0)
	team.combat_units[0].ko = 1.0
	var changed_borrow_falls_back: bool = team._hold_rescue_patient_from_columns() == null
	team.combat_units[0].ko = 0.0
	team._return_combat_hot_row()
	_dispose_world(unsupported)
	unsupported = _setup_world(true, "player")
	team = unsupported.combat_armies[0]
	team.player_member.knockout_left = NAN
	var nonfinite_player_falls_back: bool = team._hold_rescue_patient_from_columns() == null
	_dispose_world(unsupported)
	if not (missing_member_falls_back and changed_borrow_falls_back and nonfinite_player_falls_back):
		push_error("Unsupported member, borrowed-row, or player KO column state failed to fall back")
		TerrainArmy.release_contact_source()
		quit(1)
		return
	for scenario: String in ["none", "member", "player", "threshold_below", "threshold_above", "controlled", "nonmember", "custom_enemy", "custom_busy", "custom_routed", "columns_disabled", "timers", "visual_expiry", "rescue_completion"]:
		var failure := _native_case(scenario, 1 if scenario in ["visual_expiry", "rescue_completion"] else STEPS)
		if not failure.is_empty():
			push_error(failure)
			TerrainArmy.release_contact_source()
			quit(1)
			return
	var duplicate_control := _native_world(true, "controlled")
	team = duplicate_control.combat_armies[0]
	team.combat_units[3]["person_id"] = team.combat_identity(2)
	var duplicate_control_falls_back: bool = team._hold_no_patient_controlled_index() == null
	_dispose_world(duplicate_control)
	if not duplicate_control_falls_back:
		push_error("Ambiguous controlled identity incorrectly admitted the no-patient native prefix")
		TerrainArmy.release_contact_source()
		quit(1)
		return
	for boundary: String in ["before_due", "after_reset", "rescue"]:
		var failure := _save_continuation_case(boundary)
		if not failure.is_empty():
			push_error(failure)
			TerrainArmy.release_contact_source()
			quit(1)
			return
	print("HOLD_RESCUE_PATIENT_GATE_PARITY PASS original 17-step three-way replay; 14 no-patient native A/B owner/save/callback cases; both due reviews, KO thresholds, exclusions, interleaved visual/rescue barriers; before/after think and real rescue JSON-restore continuation")
	TerrainArmy.release_contact_source()
	quit(0)
