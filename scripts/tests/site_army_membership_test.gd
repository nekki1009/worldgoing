extends "res://scripts/tests/site_workflow_test.gd"

func _run() -> void:
	var data := _fixture()
	var team := TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.roster_size = 4
	var cells: Array[Vector2i] = [Vector2i(21, 21), Vector2i(22, 21), Vector2i(21, 22), Vector2i(22, 22)]
	var deployed: bool = team.deploy_at(data, null, null, cells)
	var enabled: bool = team.enable_combat(false) if deployed else false
	assert(deployed and enabled)
	var identity := team.combat_identity(0)
	var control := {"id": identity}
	team.controlled_person_query = func() -> int: return int(control.id)
	team.training = 120.0
	# R1b: officer qualification and a real post are both required for succession.
	for member: int in [1, 2]:
		var promoted: Dictionary = team.set_military_role(team.combat_identity(member), "officer")
		assert(promoted.ok, str(promoted))
	team.command_abilities[1] = {"tactics": 5, "leadership": 6, "coach": 7}
	team.command_abilities[2] = {"tactics": 8, "leadership": 9, "coach": 10}
	var row: Dictionary = team.combat_units[0]
	var cargo := {"wood": 2}
	var holder := Runtime.new_item_state("person:%d" % identity)
	row["cargo"] = cargo
	row["item_state"] = holder
	row.hp = 61.0
	row.fatigue = 72.0
	var hooks := {"calls": 0, "commits": 0, "reject": true}
	team.membership_change_hook = func(original: TerrainArmy, original_id: int, joining: bool) -> Dictionary:
		assert(original == team and original_id == identity and is_same(original.combat_units[0], row))
		assert(bool(row.member) != joining, "Membership must not be mutated before its atomic owner hook")
		hooks.calls = int(hooks.calls) + 1
		if hooks.reject:
			return Runtime.fail("INVALID_SUSTAIN", "Fixture: original owner rejects before committing")
		hooks.commits = int(hooks.commits) + 1
		return Runtime.ok()
	control.id = team.combat_identity(1)
	var leave_result: Dictionary = team.leave_row(identity)
	assert(leave_result.code == "NO_AUTHORITY" and hooks.calls == 0)
	control.id = identity
	row.ko = 1.0
	row.pose = "unconscious"
	var leave_result_2: Dictionary = team.leave_row(identity)
	assert(not leave_result_2.ok and hooks.calls == 0)
	row.ko = 0.0
	row.pose = "idle"
	var guard_changed: bool = team.set_unit_guard(0, true)
	assert(guard_changed)
	var leave_result_3: Dictionary = team.leave_row(identity)
	assert(not leave_result_3.ok and hooks.calls == 0)
	team.prepare_combat(1.0)
	var guard_changed_2: bool = team.set_unit_guard(0, false)
	assert(guard_changed_2)
	team.prepare_combat(1.0)
	var step_reserved: bool = team._reserve_combat_step(0, cells[0] + Vector2i.LEFT)
	assert(step_reserved)
	var leave_result_4: Dictionary = team.leave_row(identity)
	assert(not leave_result_4.ok and hooks.calls == 0)
	team.prepare_combat(TerrainArmy.MOVE_DURATION + 0.00001)
	assert(team.moving_to[0] == TerrainArmy.INVALID_CELL)
	var stopped := team.cells[0]
	var before := team.capture_combat_state()
	var leave_result_5: Dictionary = team.leave_row(identity)
	assert(leave_result_5.code == "INVALID_SUSTAIN")
	var captured: Dictionary = team.capture_combat_state()
	assert(captured == before and hooks.commits == 0)
	hooks.reject = false
	var leave_result_6: Dictionary = team.leave_row(identity)
	assert(leave_result_6.ok and hooks.commits == 1)
	assert(not team.is_member(0) and not team.command_members().has(0) and not team.command_eligible(0))
	assert(team.current_commander == 1 and team.formal_commander == 1, "The original officer succession handles a captain's formal departure")
	assert(not team.member_gone(0) and team.combat_can_act(0), "Logical departure is neither death nor off-Site departure")
	assert(team.cells[0] == stopped and team.combat_identity(0) == identity and team.combat_units.size() == 4)
	assert(is_same(team.combat_units[0], row) and is_same(row.cargo, cargo) and is_same(row.item_state, holder))
	assert(row.hp == 61.0 and row.fatigue == 72.0 and not row.departed and not row.present)
	var order_result: Dictionary = team.issue_combat_order(0, TerrainArmy.CombatOrder.HOLD)
	assert(not order_result.ok)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(team.capture_combat_state()))
	assert(TerrainArmy.valid_combat_state(saved, data))
	var invalid := saved.duplicate(true)
	invalid.units[0].member = "false"
	assert(not TerrainArmy.valid_combat_state(invalid, data), "An explicit non-bool member flag is not legacy")
	invalid = saved.duplicate(true)
	invalid.units[0].present = true
	assert(not TerrainArmy.valid_combat_state(invalid, data), "Independent original body cannot be command-present")
	var legacy := saved.duplicate(true)
	for unit: Dictionary in legacy.units:
		unit.erase("member")
	assert(TerrainArmy.valid_combat_state(legacy, data))
	var normalized: Dictionary = TerrainArmy.normalize_roster_snapshot(legacy)
	assert(normalized.units[0].member)
	# Native movement/guard continue, but another member's orders do not drag
	# this body into its former formation or lower its independent guard.
	control.id = team.combat_identity(1)
	var guard_changed_3: bool = team.set_unit_guard(0, true)
	assert(guard_changed_3)
	team.prepare_combat(1.0)
	assert(row.pose == "guard")
	var order_result_2: Dictionary = team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(26, 21))
	assert(order_result_2.ok)
	team.prepare_combat(0.6)
	assert(row.pose == "guard" and team.cells[0] == stopped and team.moving_to[0] == TerrainArmy.INVALID_CELL)
	var order_result_3: Dictionary = team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.HOLD)
	assert(order_result_3.ok)
	team.prepare_combat(TerrainArmy.MOVE_DURATION + 0.00001)
	control.id = identity
	var guard_changed_4: bool = team.set_unit_guard(0, false)
	assert(guard_changed_4)
	team.prepare_combat(1.0)
	var step_reserved_2: bool = team._reserve_combat_step(0, stopped + Vector2i.LEFT, 0, true)
	assert(step_reserved_2)
	assert(is_equal_approx(team.move_duration[0], TerrainArmy.RUN_DURATION))
	assert(team.moving_count() == 1 and team.moving_member_count() == 0, "An independent body's original step is not a member movement")
	team.prepare_combat(TerrainArmy.RUN_DURATION + 0.00001)
	assert(team.cells[0] == stopped + Vector2i.LEFT)
	team.training = 900.0
	var attack_started: bool = team.start_unit_attack(0, team.cells[0] + Vector2i.LEFT)
	assert(attack_started)
	assert(float(row.attack_reduction) == 0.0, "An independent row never borrows later training from its former team")
	var join_result: Dictionary = team.join_row(identity)
	assert(not join_result.ok and hooks.commits == 1)
	team.prepare_combat(TerrainArmy.CombatTimings.action_duration(team.attack_clip(0), float(row.attack_reduction), float(row.attack_fatigue)) + 0.00001)
	assert(not row.attack and row.pose == "idle")
	var ready_save: Dictionary = JSON.parse_string(JSON.stringify(team.capture_combat_state()))
	ready_save.units[0].erase("attack_reduction")
	var restored := TerrainArmy.new()
	root.add_child(restored)
	restored.set_process(false)
	assert(TerrainArmy.valid_combat_state(ready_save, data))
	restored.restore_combat_state(ready_save, data, null, null)
	assert(not restored.is_member(0) and float(restored.combat_units[0].attack_reduction) == 0.0)
	var join_result_2: Dictionary = team.join_row(identity)
	assert(join_result_2.ok and hooks.commits == 2)
	assert(team.training == 675.0, "Rejoining uses the original untrained batch-of-one dilution")
	assert(team.is_member(0) and team.current_commander == 1 and team.formal_commander == 1, "Rejoining does not reclaim a former office")
	assert(is_same(team.combat_units[0], row) and is_same(row.cargo, cargo) and is_same(row.item_state, holder))
	assert(row.hp == 61.0 and row.fatigue == 72.0 and cargo == {"wood": 2})
	team.free()
	restored.free()
	TerrainArmy.release_contact_source()
	print("SITE ARMY MEMBERSHIP PASS: same-row leave/rejoin, original authority/guard/hook atomicity, succession, independent movement and training, saved bool migration")
	quit(0)
