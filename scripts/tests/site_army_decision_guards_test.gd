extends "res://scripts/tests/site_army_tactics_test.gd"
# Reuse the existing headless real-army fixture; no second simulation/reference
# owner. Small read-only oracles cover just the three changed expressions.
const Timings = preload("res://scripts/terrain_lab/character_combat_timings.gd")
const STEP := 1.0 / 120.0

class CountedArmy extends TerrainArmy:
	var eligibility_calls := 0
	var control_calls := 0
	func combat_can_act(index: int) -> bool:
		eligibility_calls += 1
		return super.combat_can_act(index)
	func is_controlled_person(index: int) -> bool:
		control_calls += 1
		return super.is_controlled_person(index)

class CountedActor extends TerrainTestCharacter:
	var eligibility_calls := 0
	func can_act() -> bool:
		eligibility_calls += 1
		return super.can_act()

class CountedNPC extends TerrainTestNPC:
	var eligibility_calls := 0
	func can_act() -> bool:
		eligibility_calls += 1
		return super.can_act()

var actor: CountedActor
var other: CountedNPC
var queried: Array[int] = []
var deadline_usec := 0

func run() -> void:
	deadline_usec = Time.get_ticks_usec() + 15000000
	create_timer(15.0).timeout.connect(func() -> void: quit(1))
	data = TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "decision-guards-fixture")
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	data.site.worker_enabled = false
	data.site.worker.target = ""
	lab = TerrainLab.new() # Original tactics fixture: no extra UI/world or rig.
	lab.terrain = data
	team = CountedArmy.new()
	enemy = CountedArmy.new()
	root.add_child(team)
	root.add_child(enemy)
	team.set_process(false)
	enemy.set_process(false)
	enemy.team_id = 2
	enemy.faction_id = 1
	lab.combat_armies.assign([team, enemy])
	team.external_blocker = enemy.blocks_cell
	enemy.external_blocker = team.blocks_cell
	reset_team()
	assert(enemy.deploy_at(data, null, null, placement(Vector2i(50, 20))) and enemy.enable_combat(false))
	actor = CountedActor.new()
	other = CountedNPC.new()
	root.add_child(actor)
	root.add_child(other)
	for body: TerrainTestCharacter in [actor, other]:
		body.data = data
		body.set_process(false)
	actor.person_id = 1
	other.person_id = 2
	other.faction_id = 1
	assert(actor.place(Vector2i(70, 20), true) and other.place(Vector2i(71, 20), true))
	lab.character = actor
	lab.npc = other
	lab.combat_actors.assign([actor, other])
	_check_think()
	_check_nearest()
	_check_fatigue()
	assert(Time.get_ticks_usec() < deadline_usec)
	team.clear()
	enemy.clear()
	team.free()
	enemy.free()
	actor.free()
	other.free()
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE ARMY DECISION GUARDS PASS: exact conditions, boundary callbacks, full fatigue snapshots and eligibility counts; no GPU/FPS or supply-provider claim")
	quit(0)

func _count_reset() -> void:
	team.set("eligibility_calls", 0)
	enemy.set("eligibility_calls", 0)
	team.set("control_calls", 0)
	actor.eligibility_calls = 0
	other.eligibility_calls = 0

func _counts() -> Array[int]:
	return [actor.eligibility_calls, other.eligibility_calls, int(team.get("eligibility_calls")), int(enemy.get("eligibility_calls"))]

func _query(_source: TerrainArmy, index: int) -> Dictionary:
	queried.append(index)
	return {}

func _check_think() -> void:
	team.enemy_query = _query
	team.controlled_person_query = func() -> int: return team.combat_identity(9)
	team.person_busy_query = func(_identity: int) -> bool: return true
	for unit: Dictionary in team.combat_units:
		unit.think = 1.0
	team.combat_units[1].think = STEP
	team.combat_units[2].think = STEP * 1.5
	assert(team.start_unit_attack(3, team.cells[3] + Vector2i.DOWN))
	team.combat_units[3].think = 0.0
	knockout(4) # Original contact releases original occupancy.
	team.combat_units[4].ko = STEP
	team.combat_units[4].think = 0.0
	assert(team.start_unit_attack(5, team.cells[5] + Vector2i.DOWN))
	team.combat_units[5].age = Timings.action_duration(team.attack_clip(5),
		float(team.combat_units[5].attack_reduction), float(team.combat_units[5].attack_fatigue)) - STEP
	team.combat_units[5].think = 0.0
	team.combat_units[6].captive = true
	team.combat_units[6].think = 0.0
	team.combat_units[9].think = 0.0
	# Pure original/new guard oracle: actual can_act/control methods, no mutation.
	var before := team.capture_combat_state()
	var old_results: Array[bool] = []
	_count_reset()
	for index in range(100):
		var unit: Dictionary = team.combat_units[index]
		old_results.append(team.combat_can_act(index) and not team.is_controlled_person(index) and not bool(unit.attack) and float(unit.think) <= 0.0 and (not team.is_member(index) or team._order_delay <= 0.0) and team.enemy_query.is_valid())
	var old_calls := int(team.get("eligibility_calls"))
	_count_reset()
	for index in range(100):
		var unit: Dictionary = team.combat_units[index]
		var actual := not bool(unit.attack) and float(unit.think) <= 0.0 and team.combat_can_act(index) and not team.is_controlled_person(index) and (not team.is_member(index) or team._order_delay <= 0.0) and team.enemy_query.is_valid()
		assert(actual == old_results[index])
	assert(team.capture_combat_state() == before and int(team.get("eligibility_calls")) < old_calls)
	for tick in range(2):
		if tick == 1:
			team.combat_units[4].age = float(Timings.POSE_SECONDS[&"get_up"]) - STEP
		queried.clear()
		_count_reset()
		team.prepare_combat(STEP)
		assert(queried == ([1] if tick == 0 else [2]), "Exact think, active attack and control boundary")
		assert(bool(team.combat_units[3].attack) and not bool(team.combat_units[5].attack))
		assert(str(team.combat_units[4].pose) == ("get_up" if tick == 0 else "idle"))
		assert(int(team.get("eligibility_calls")) < 10 and int(team.get("control_calls")) < 10)
		print("GUARDS think tick ", tick, " eligibility ", team.get("eligibility_calls"), ", control ", team.get("control_calls"))
	before = team.capture_combat_state()
	paused = true
	team.prepare_combat(STEP)
	paused = false
	team.prepare_combat(0.0)
	assert(team.capture_combat_state() == before)
	team.enemy_query = Callable()
	team.controlled_person_query = Callable()

func _candidate_oracle() -> Dictionary:
	# This fixture has exactly one in-range enemy row and no nearby Actor.
	# Keep the old eligibility-before-distance ordering for its count reference.
	var expected := {}
	for index in range(enemy.combat_units.size()):
		if not enemy.combat_can_act(index):
			continue
		var offset := enemy.cells[index] - team.cells[9]
		if absi(offset.x) + absi(offset.y) <= 2 and SiteCombatRules.terrain_line_clear(data, team.cells[9], enemy.cells[index]):
			assert(expected.is_empty())
			expected = {"cell": enemy.cells[index], "identity": enemy.combat_identity(index),
				"threat": bool(enemy.combat_units[index].attack) and int(enemy.combat_units[index].target) == team.combat_identity(9)}
	return expected

func _check_nearest() -> void:
	var original := team.cells[9]
	# Move only the query point, never occupancy/body: include the historical
	# coincident-distance contract without creating overlapping standing people.
	for distance: int in [0, 1, 2, 3, 9]:
		team.cells[9] = enemy.cells[0] + Vector2i.LEFT * distance + Vector2i.UP * 9
		# Row 0 is isolated by this temporary pure-query location.
		var old_cell := enemy.cells[0]
		enemy.cells[0] = team.cells[9] + Vector2i.RIGHT * distance
		for state: String in ["idle", "captive", "get_up", "ko", "dead"]:
			var unit: Dictionary = enemy.combat_units[0]
			unit.captive = state == "captive"
			unit.pose = "get_up" if state == "get_up" else "idle"
			unit.ko = 1.0 if state == "ko" else 0.0
			unit.hp = 0.0 if state == "dead" else 100.0
			_count_reset()
			var expected := _candidate_oracle()
			var old_calls := int(enemy.get("eligibility_calls"))
			_count_reset()
			assert(lab._nearest_unit_enemy(team, 9) == expected)
			assert(int(enemy.get("eligibility_calls")) < old_calls)
		enemy.cells[0] = old_cell
	enemy.combat_units[0].hp = 100.0
	enemy.combat_units[0].ko = 0.0
	team.cells[9] = original
	assert(lab._nearest_unit_enemy(team, 9).is_empty())

func _check_fatigue() -> void:
	reset_team()
	team.person_busy_query = Callable()
	for owner: TerrainArmy in [team, enemy]:
		for unit: Dictionary in owner.combat_units:
			unit.fatigue = 40.0
			unit.fatigue_rest = 29.0
	actor.fatigue = 50.0
	other.fatigue = 60.0
	actor.fatigue_rest = 29.0
	other.fatigue_rest = 30.0
	assert(actor.start_attack(other))
	other.set_guard(true)
	assert(team.start_unit_attack(1, team.cells[1] + Vector2i.DOWN))
	assert(team.set_unit_guard(2, true))
	team.controlled_person_query = func() -> int: return team.combat_identity(0)
	assert(team._reserve_combat_step(0, team.cells[0] + Vector2i.LEFT, 0, true))
	assert(str(team.combat_units[0].pose) == "run" and team.move_duration[0] <= TerrainArmy.RUN_DURATION + 0.000001)
	knockout(4)
	team.combat_units[5].captive = true
	team.combat_units[6].departed = true
	team.apply_unit_contact(7, {"result": {"hp": 100.0, "stun": 0.0, "guard_break": false}, "shield": false})
	knockout(8)
	team._wake_unit(8)
	var expected := [actor.capture_state(), other.capture_state(), team.capture_combat_state(), enemy.capture_combat_state()]
	var candidates := {}
	_count_reset()
	# Read-only oracle for this explicit fixture. Same original eligibility calls
	# (twice), exact threat query and fatigue arithmetic; no timers are simulated.
	for index in range(2):
		var body: TerrainTestCharacter = [actor, other][index]
		var rate := (PersonFatigue.ATTACK_RATE if index == 0 else PersonFatigue.GUARD_RATE) if body.can_act() else 0.0
		var idle := body.can_act() and not body.is_moving() and body.action_time <= 0.0 and not body.guarding and body.guard_transition_left <= 0.0
		var safe := idle and body.fatigue > 0.0 and not lab._fatigue_threat(body.terrain_cell, body.faction_id, body, -1, candidates)
		var value := PersonFatigue.advance(body.fatigue, body.fatigue_rest, 2.0, rate, safe)
		expected[index].fatigue = value[0]
		expected[index].fatigue_rest = value[1]
	for owner_index in range(2):
		var owner: TerrainArmy = [team, enemy][owner_index]
		for index in range(100):
			var unit: Dictionary = owner.combat_units[index]
			var moving := owner.moving_to[index] != TerrainArmy.INVALID_CELL
			var rate := 0.0
			if owner.combat_can_act(index):
				rate = PersonFatigue.ATTACK_RATE if bool(unit.attack) or moving else (PersonFatigue.GUARD_RATE if str(unit.pose) == "guard_raise" else 0.0)
			var idle := owner.combat_can_act(index) and not moving and str(unit.pose) == "idle"
			var safe := idle and float(unit.fatigue) > 0.0 and not lab._fatigue_threat(owner.cells[index], owner.faction_id, owner, index, candidates)
			var value := PersonFatigue.advance(float(unit.fatigue), float(unit.fatigue_rest), 2.0, rate, safe)
			expected[2 + owner_index].units[index].fatigue = value[0]
			expected[2 + owner_index].units[index].fatigue_rest = value[1]
	var old_counts := _counts()
	_count_reset()
	lab.combat_profile_enabled = true
	lab._advance_fatigue(2.0)
	var new_counts := _counts()
	assert([actor.capture_state(), other.capture_state(), team.capture_combat_state(), enemy.capture_combat_state()] == expected,
		"Every saved field remains exact; only expected fatigue/rest changes")
	for index in range(4):
		assert(old_counts[index] - new_counts[index] == (1 if index < 2 else 100))
	for key: String in ["fatigue_providers", "fatigue_people_inclusive", "fatigue_threat"]:
		assert(lab.combat_profile_usec.has(key) and int(lab.combat_profile_usec[key]) >= 0)
	assert(int(lab.combat_profile_usec.fatigue_people_inclusive) >= int(lab.combat_profile_usec.fatigue_threat))
	var profile := lab.combat_profile_usec.duplicate()
	lab.combat_profile_enabled = false
	lab._advance_fatigue(0.0)
	lab._advance_fatigue(STEP)
	assert(lab.combat_profile_usec == profile)
	print("GUARDS fatigue eligibility old/new ", old_counts, " / ", new_counts)
