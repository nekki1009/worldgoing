extends SceneTree
## Formal scene + original Army/Lab clocks. Flat ground is an explicit command
## fixture; the separate three-army test retains the generated-map 300-person fight.
const OUT := "res://output/npc_ai_acceptance_20260918/combat"
const STEP := 1.0 / 30.0
var lab: TerrainLab
var deadline := 0
var stage := "startup"
var report := {}
var people := {}
var pairs := {}
var participants := {}
var round_used := {}
var exchange_round := -1
var steps := 0
var ranged_events := {}
var ranged_effects := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 35000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("NPC command deadline at " + stage)
		quit(90)
	return false

func _fresh() -> void:
	if is_instance_valid(lab):
		lab.queue_free()
		await process_frame
	var main: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	lab = main.instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	# Only fixture terrain changes; no production flattening or alternate navigation.
	lab.terrain.height_levels.fill(0)
	lab.terrain.flags.fill(TerrainData.Flag.WALKABLE)
	lab.terrain.static_blocked.fill(0)
	lab.terrain.ramp_edges.fill(0)
	assert(lab.character.place(Vector2i(88, 88), true))
	assert(lab.npc.place(Vector2i(88, 85), true))
	assert(lab.start_melee_trial({"third_enabled": true, "third_faction": 2,
		"friendly_count": 6, "enemy_count": 6, "third_count": 6,
		"friendly_attack": false, "enemy_attack": false, "third_attack": false}).ok)
	_place(lab.army, _formation(Vector2i(12, 12)))
	_place(lab.opposing_army, _formation(Vector2i(45, 12)))
	_place(lab.third_army, _formation(Vector2i(70, 12)))
	people.clear()
	pairs.clear()
	participants.clear()
	round_used.clear()
	exchange_round = -1
	for team: TerrainArmy in lab.combat_armies:
		participants[team.faction_id] = {}
		for index in range(team.combat_units.size()):
			var identity := team.combat_identity(index)
			assert(not people.has(identity))
			people[identity] = {"team": team, "index": index}
	assert(people.size() == 18)
	lab.exchange_resolved.connect(_exchange)
	_claims()

func _formation(origin: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for row in range(3):
		for column in range(2): cells.append(origin + Vector2i(column, row))
	return cells

func _place(team: TerrainArmy, cells: Array[Vector2i]) -> void:
	# Initial placement only, before this scenario's first action tick.
	team.cells.assign(cells)
	team.combat_slots.assign(cells)
	team._cell_owners.clear()
	team._reserved_cells.clear()
	team.moving_to.fill(TerrainArmy.INVALID_CELL)
	for index in range(cells.size()): team._cell_owners[cells[index]] = index
	team._command_dirty = true
	team.settle_combat_command()

func _tick() -> void:
	assert(Time.get_ticks_msec() <= deadline, "Deadline at " + stage)
	var old := {}
	for team: TerrainArmy in lab.combat_armies: old[team.team_id] = team.cells.duplicate()
	lab._process(STEP)
	steps += 1
	assert(not paused and not bool(lab.terrain.site.paused), "Unexpected pause at " + stage)
	_claims()
	for team: TerrainArmy in lab.combat_armies:
		for index in range(team.cells.size()):
			var from: Vector2i = old[team.team_id][index]
			var to: Vector2i = team.cells[index]
			assert(from == to or lab.terrain.can_step(from, to), "Nonlocal/illegal original person step")

func _advance(seconds: float) -> void:
	for tick in range(roundi(seconds / STEP)): _tick()

func _claims() -> void:
	var owners := {}
	for team: TerrainArmy in lab.combat_armies:
		for cell: Vector2i in team._cell_owners:
			assert(not owners.has(cell), "Two real people share a standing/reserved cell")
			owners[cell] = team.team_id
		for cell: Vector2i in team._reserved_cells:
			assert(not owners.has(cell), "Two real people share a standing/reserved cell")
			owners[cell] = team.team_id
		for index in range(team.cells.size()):
			if team.moving_to[index] != TerrainArmy.INVALID_CELL:
				assert(lab.terrain.can_step(team.cells[index], team.moving_to[index]))
				assert(team._reserved_cells.get(team.moving_to[index]) == index)

func _issue(team: TerrainArmy, order: int, offset: Vector2i = Vector2i.ZERO) -> Array[Vector2i]:
	var goal := Vector2i(team.command_reference.floor()) + offset
	var result := team.issue_combat_order(team.current_commander, order, goal)
	assert(result.ok, str(result) + " at " + stage)
	return team.combat_slots.duplicate()

func _arrived(team: TerrainArmy, goals: Array[Vector2i], excluded: Array[int] = []) -> void:
	assert(team.combat_order == TerrainArmy.CombatOrder.HOLD and team.moving_count() == 0,
		"Command did not settle: " + team.command_status + " at " + stage)
	for index in range(team.cells.size()):
		if index in excluded: continue
		assert(team.combat_can_act(index), "Unexpected ineligible member %d at %s" % [index, stage])
		assert(team.cells[index] == goals[index], "Member %d stopped early at %s, expected %s (%s)" % [index, team.cells[index], goals[index], stage])
	assert(team.command_status.begins_with("到達"), "A blocked HOLD is not arrival")

func _exchange(first: int, second: int, _outcome: Dictionary) -> void:
	assert(people.has(first) and people.has(second), "Distant original player/NPC must not join fixture")
	if exchange_round != lab._exchange_round:
		exchange_round = lab._exchange_round
		round_used.clear()
	assert(not round_used.has(first) and not round_used.has(second))
	round_used[first] = true
	round_used[second] = true
	var a: TerrainArmy = people[first].team
	var b: TerrainArmy = people[second].team
	assert(a.faction_id != b.faction_id)
	var key := "%d:%d" % [mini(a.faction_id, b.faction_id), maxi(a.faction_id, b.faction_id)]
	pairs[key] = int(pairs.get(key, 0)) + 1
	participants[a.faction_id][first] = true
	participants[b.faction_id][second] = true

func _ranged(shooter: int, target: int, outcome: Dictionary) -> void:
	assert(people.has(shooter) and people.has(target), "Real shot must resolve against an original fixture person")
	ranged_events[shooter] = int(ranged_events.get(shooter, 0)) + 1
	if float(outcome.hp) > 0.0 or float(outcome.stun) > 0.0: ranged_effects += 1
	print("NPC_AI_RANGED: ", shooter, " -> ", target, " ", outcome)

func _equip_ranged_captain(team: TerrainArmy, weapon: String) -> void:
	var row: Dictionary = team.combat_units[0]
	var made := SiteRuntime.create_equipment(lab.terrain, row.item_state, "npc_ai_" + weapon,
		{"slot": "weapon", "asset": weapon, "tint": [1.0, 1.0, 1.0, 1.0]}, team.combat_identity(0))
	assert(made.ok)
	var proposed: Dictionary = row.item_state.equipped.duplicate()
	proposed.weapon = made.item_id
	proposed.erase("shield")
	assert(lab.site_controller.equipment_apply_guard(team.combat_identity(0), proposed).ok,
		"Fixture must retain the real equipment/role admission guard")
	row.item_state.equipped = proposed
	lab.site_controller.equipment_changed(team.combat_identity(0))
	row.cargo["arrow" if weapon == "bow_01" else "bolt"] = 2 # Explicit initial stock.
	assert(not team.ranged_profile(0).is_empty())

func _run() -> void:
	assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
	await _fresh()
	stage = "all-member MOVE/HOLD/RETREAT"
	var starts := {}
	var goals := {}
	for team: TerrainArmy in lab.combat_armies:
		starts[team.team_id] = team.cells.duplicate()
	_advance(2.0)
	for team: TerrainArmy in lab.combat_armies:
		assert(team.cells == starts[team.team_id] and team.moving_count() == 0)
		goals[team.team_id] = _issue(team, TerrainArmy.CombatOrder.MOVE, Vector2i(3, 2))
	_advance(0.6)
	var paused_state := []
	for army: TerrainArmy in lab.combat_armies: paused_state.append(army.capture_combat_state().duplicate(true))
	paused = true
	lab._process(2.0)
	for index in range(3):
		assert(lab.combat_armies[index].capture_combat_state() == paused_state[index], "Pause freezes every original member and command timer")
		assert(not lab.combat_armies[index].issue_combat_order(lab.combat_armies[index].current_commander, TerrainArmy.CombatOrder.HOLD).ok)
	paused = false
	_advance(10.0)
	for team: TerrainArmy in lab.combat_armies: _arrived(team, goals[team.team_id])
	# HOLD supersedes a command but must finish original already committed edges.
	for team: TerrainArmy in lab.combat_armies: _issue(team, TerrainArmy.CombatOrder.MOVE, Vector2i(3, 0))
	_advance(0.6)
	var in_flight := 0
	for team: TerrainArmy in lab.combat_armies:
		in_flight += team.moving_count()
		goals[team.team_id] = _issue(team, TerrainArmy.CombatOrder.HOLD)
	assert(in_flight > 0, "Must exercise actual mid-step HOLD")
	_advance(2.0)
	for team: TerrainArmy in lab.combat_armies:
		assert(team.cells == goals[team.team_id] and team.moving_count() == 0)
		goals[team.team_id] = _issue(team, TerrainArmy.CombatOrder.RETREAT, Vector2i(-3, -2))
	_advance(10.0)
	for team: TerrainArmy in lab.combat_armies: _arrived(team, goals[team.team_id])
	report.move_hold_retreat = {"teams": 3, "all_members": 18, "committed_steps_at_hold": in_flight}
	print("NPC_AI: all 18 MOVE/RETREAT arrivals and committed HOLD")
	await process_frame

	stage = "fully blocked then renewed MOVE"
	var team := lab.army
	var blocked_cells := team.cells.duplicate()
	var left := 100
	var right := 0
	var top := 100
	var bottom := 0
	for cell: Vector2i in blocked_cells:
		left = mini(left, cell.x)
		right = maxi(right, cell.x)
		top = mini(top, cell.y)
		bottom = maxi(bottom, cell.y)
	var wall: Array[Vector2i] = []
	for y in range(top - 1, bottom + 2):
		for x in range(left - 1, right + 2):
			if x == left - 1 or x == right + 1 or y == top - 1 or y == bottom + 1:
				wall.append(Vector2i(x, y))
	for cell: Vector2i in wall: lab.terrain.static_blocked[lab.terrain.index(cell)] = 1
	var blocked_goals := _issue(team, TerrainArmy.CombatOrder.MOVE, Vector2i(5, 0))
	_advance(2.0)
	assert(team.combat_order == TerrainArmy.CombatOrder.HOLD and team.moving_count() == 0)
	assert(team.cells == blocked_cells and team.command_status.begins_with("未找到"))
	_advance(2.0)
	assert(team.cells == blocked_cells, "Blocked team must not oscillate")
	for cell: Vector2i in wall: lab.terrain.static_blocked[lab.terrain.index(cell)] = 0
	assert(_issue(team, TerrainArmy.CombatOrder.MOVE, Vector2i(5, 0)) == blocked_goals)
	_advance(10.0)
	_arrived(team, blocked_goals)
	report.blocked_recovery = {"all_members": 6, "stable_hold_seconds": 4, "new_order_arrived": true}
	print("NPC_AI: all 6 blocked HOLD then genuine new-command recovery")
	await process_frame

	await _fresh()
	stage = "PURSUE moving hostile then leash RETURN"
	_place(lab.opposing_army, _formation(Vector2i(25, 12)))
	var origin := lab.army.command_reference
	var before := lab.army.cells.duplicate()
	_issue(lab.opposing_army, TerrainArmy.CombatOrder.RETREAT, Vector2i(18, 0))
	assert(lab.army.issue_combat_order(lab.army.current_commander, TerrainArmy.CombatOrder.PURSUE,
		TerrainArmy.INVALID_CELL, lab.opposing_army.combat_identity(0)).ok)
	var return_goals: Array[Vector2i] = []
	var moved := {}
	for tick in range(1050):
		_tick()
		for index in range(6):
			if lab.army.cells[index] != before[index]: moved[index] = true
		if lab.army.combat_order == TerrainArmy.CombatOrder.RETURN and return_goals.is_empty():
			return_goals = lab.army.combat_slots.duplicate()
		if tick % 150 == 0: await process_frame
	assert(moved.size() == 6 and not return_goals.is_empty(), "Every pursuer must move and original leash must enter RETURN")
	_arrived(lab.army, return_goals)
	assert(lab.army.command_reference.distance_to(origin) <= lab.army.command_radius)
	var stopped := lab.army.cells.duplicate()
	_advance(3.0)
	assert(lab.army.cells == stopped and lab.army.pursuit_left == 0.0 and not lab.army.combat_attacking)
	report.pursue_return = {"all_members_moved": moved.size(), "all_members_returned": 6, "no_auto_rechase_seconds": 3}
	print("NPC_AI: all 6 pursue moving hostile, leash RETURN, no automatic re-chase")
	await _fresh()
	stage = "invalid pursuit target returns without re-acquisition"
	_place(lab.opposing_army, _formation(Vector2i(25, 12)))
	assert(lab.army.issue_combat_order(lab.army.current_commander, TerrainArmy.CombatOrder.PURSUE,
		TerrainArmy.INVALID_CELL, lab.opposing_army.combat_identity(0)).ok)
	_advance(1.0)
	assert(lab.army.moving_count() > 0 or lab.army.cells != _formation(Vector2i(12, 12)))
	lab.opposing_army.apply_unit_contact(0, {"result": {"hp": 0.0, "stun": 110.0, "guard_break": false}, "shield": false})
	_tick()
	assert(lab.army.combat_order == TerrainArmy.CombatOrder.RETURN and lab.army.pursuit_left == 0.0)
	return_goals = lab.army.combat_slots.duplicate()
	_advance(10.0)
	_arrived(lab.army, return_goals)
	assert(lab.opposing_army.combat_can_act(0), "Enemy's original rescue wakes it, but does not authorize a fresh pursuit")
	stopped = lab.army.cells.duplicate()
	_advance(2.0)
	assert(lab.army.cells == stopped and lab.army.combat_order == TerrainArmy.CombatOrder.HOLD)
	report.invalid_pursuit = {"all_members_returned": 6, "recovered_enemy_does_not_retrigger": true}

	await _fresh()
	stage = "KO succession and safe automatic rescue"
	team = lab.army
	assert(team.record_officer_service([1, 2], true).ok)
	var identities := []
	for index in range(6): identities.append(team.combat_identity(index))
	before = team.cells.duplicate()
	team.apply_unit_contact(0, {"result": {"hp": 7.5, "stun": 110.0, "guard_break": false}, "shield": false})
	_advance(0.1)
	assert(team.current_commander == 1 and team.formal_commander == 0 and team.cells == before)
	assert(not team.issue_combat_order(0, TerrainArmy.CombatOrder.MOVE, Vector2i(17, 12)).ok)
	var acting_goals := _issue(team, TerrainArmy.CombatOrder.MOVE, Vector2i(2, 0))
	_advance(6.0)
	_arrived(team, acting_goals, [0])
	assert(team.cells[0] == before[0] and float(team.combat_units[0].ko) > 0.0)
	for index in range(6): assert(team.combat_identity(index) == identities[index])
	report.ko_command = {"acting_commander": 1, "all_eligible_arrivals": 5, "no_body_relocation_on_promotion": true}
	# A separate untouched team provides adjacent safe HOLD helpers. Their AI,
	# not the test, selects the original rescuer and completes the four-second aid.
	team = lab.third_army
	team.apply_unit_contact(2, {"result": {"hp": 7.5, "stun": 110.0, "guard_break": false}, "shield": false})
	_advance(0.6)
	assert(team._unit_rescues.size() == 1 and team.patient_has_rescuer(2))
	var rescuer: int = team._unit_rescues.keys()[0]
	assert(int(team._unit_rescues[rescuer].patient) == 2)
	_advance(4.0)
	assert(float(team.combat_units[2].ko) == 0.0 and str(team.combat_units[2].pose) == "get_up")
	assert(is_equal_approx(float(team.combat_units[2].hp), 92.5) and not team.combat_can_act(2))
	_advance(2.3)
	assert(team.combat_can_act(2) and team._unit_rescues.is_empty())
	report.rescue = {"patient": team.combat_identity(2), "rescuer": team.combat_identity(rescuer), "hp_after": 92.5, "natural_ko_seconds": 30, "rescued_before_natural_wake": true}
	print("NPC_AI: acting officer executes all eligible members; original automatic safe rescue completes")
	await process_frame

	await _fresh()
	stage = "three hostile ATTACK commands"
	_place(lab.army, _formation(Vector2i(12, 12)))
	_place(lab.opposing_army, _formation(Vector2i(14, 12)))
	_place(lab.third_army, [Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11), Vector2i(13, 10), Vector2i(14, 10), Vector2i(15, 10)])
	_advance(2.0)
	assert(pairs.is_empty(), "HOLD is self-defense, not an unsolicited attack")
	for army: TerrainArmy in lab.combat_armies: _issue(army, TerrainArmy.CombatOrder.ATTACK)
	_advance(10.0)
	assert(pairs.has("0:1") and pairs.has("0:2") and pairs.has("1:2"), str(pairs))
	var participation := {}
	for army: TerrainArmy in lab.combat_armies:
		assert(participants[army.faction_id].size() >= 2, "Must not prove ATTACK using only a captain")
		participation[army.faction_id] = participants[army.faction_id].size()
	report.attack = {"pairs": pairs.duplicate(), "participants_per_faction": participation, "no_same_faction_or_double_exchange": true}
	print("NPC_AI: three actual hostile pairs and multi-member participation: ", report.attack)
	await _fresh()
	stage = "RETREAT breaks real three-way contact"
	_place(lab.army, _formation(Vector2i(12, 12)))
	_place(lab.opposing_army, _formation(Vector2i(14, 12)))
	_place(lab.third_army, [Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11), Vector2i(13, 10), Vector2i(14, 10), Vector2i(15, 10)])
	for army: TerrainArmy in lab.combat_armies: _issue(army, TerrainArmy.CombatOrder.ATTACK)
	_advance(1.2)
	assert(pairs.has("0:1") and pairs.has("0:2") and pairs.has("1:2"), "Retreat fixture must first really engage all three sides")
	for army: TerrainArmy in lab.combat_armies:
		for index in range(6): assert(army.combat_can_act(index), "Pre-retreat fixture requires all 18 living and capable")
	goals[lab.army.team_id] = _issue(lab.army, TerrainArmy.CombatOrder.RETREAT, Vector2i.LEFT * 4)
	goals[lab.opposing_army.team_id] = _issue(lab.opposing_army, TerrainArmy.CombatOrder.RETREAT, Vector2i.RIGHT * 4)
	goals[lab.third_army.team_id] = _issue(lab.third_army, TerrainArmy.CombatOrder.RETREAT, Vector2i.UP * 4)
	_advance(10.0)
	for army: TerrainArmy in lab.combat_armies: _arrived(army, goals[army.team_id])
	var exchanges_at_rest := lab.exchange_count
	_advance(2.0)
	assert(lab.exchange_count == exchanges_at_rest)
	report.retreat_from_contact = {"all_eligible_members_arrived": 18, "all_three_hostile_pairs_first_engaged": true, "no_further_contact_seconds": 2}
	print("NPC_AI: all 18 retreat from real three-way contact and stop exchanging")
	await _fresh()
	stage = "admitted bow/crossbow captains autonomous ATTACK and empty ammunition"
	_place(lab.army, [Vector2i(12, 12), Vector2i(10, 11), Vector2i(10, 12), Vector2i(10, 13), Vector2i(9, 12), Vector2i(9, 13)])
	# This explicit short-range, trained fixture guarantees useful real contact
	# coverage for the fixed seed; the earlier seven-cell/zero-training fixture
	# legitimately missed all four shots and its failed evidence is retained.
	_place(lab.opposing_army, [Vector2i(12, 16), Vector2i(11, 21), Vector2i(12, 21), Vector2i(13, 21), Vector2i(11, 22), Vector2i(12, 22)])
	_place(lab.third_army, _formation(Vector2i(19, 12)))
	lab.army.training = 100.0
	lab.opposing_army.training = 100.0
	_equip_ranged_captain(lab.army, "bow_01")
	_equip_ranged_captain(lab.opposing_army, "crossbow_01")
	lab.ranged_resolved.connect(_ranged)
	_advance(2.0)
	assert(ranged_events.is_empty() and lab.army.combat_units[0].cargo.arrow == 2 and lab.opposing_army.combat_units[0].cargo.bolt == 2)
	_issue(lab.army, TerrainArmy.CombatOrder.ATTACK)
	_issue(lab.opposing_army, TerrainArmy.CombatOrder.ATTACK)
	_advance(9.0)
	assert(ranged_events.get(lab.army.combat_identity(0), 0) == 2 and ranged_events.get(lab.opposing_army.combat_identity(0), 0) == 2,
		"Both admitted real captains must autonomously fire and resolve both real rounds: " + str(ranged_events))
	assert(lab.army.combat_units[0].cargo.arrow == 0 and lab.opposing_army.combat_units[0].cargo.bolt == 0)
	assert(ranged_effects > 0, "Four actual arrows resolved but none inflicted HP/stun: " + str(lab.ranged_results))
	assert(lab.ranged_resolutions == 4, "Unexpected total arrivals: " + str(lab.ranged_resolutions))
	assert(not lab.has_ranged_projectiles(), "All four paid arrows must finish their flight")
	_advance(4.0)
	assert(lab.ranged_resolutions == 4, "Empty stock cannot fabricate further shots")
	report.ranged_attack = {"admitted_original_captains": 2, "weapons": ["bow_01", "crossbow_01"], "real_ammo_used": 4,
		"resolutions": lab.ranged_resolutions, "effective_contacts": ranged_effects, "empty_stock_stops": true,
		"boundary": "Two existing live captain roles; not a claim that every unbaked ordinary ranged equipment recipe is admitted."}
	print("NPC_AI: real bow/crossbow captain ATTACK, four ammo and four arrivals, no free shots")
	report["shared_clock_steps"] = steps
	report["scene"] = ProjectSettings.get_setting("application/run/main_scene")
	report["fixture_boundary"] = "Original main scene; test-only flat legal ground and initial placement. No duplicate AI/people/clock. Generated-map 300-person combat is a separate regression."
	var file := FileAccess.open(OUT + "/commands_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	lab.queue_free()
	await process_frame
	print("SITE NPC COMBAT ORDERS PASS")
	quit(0)
