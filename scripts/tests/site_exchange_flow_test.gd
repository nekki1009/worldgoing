extends SceneTree
## Actual Lab pairing/owner integration without rendering or fabricated body shapes.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var data := TerrainData.new()
	data.allocate(Vector2i(12, 12))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.resize(144)
	data.feature_at.resize(144)
	data.site = {"paused": false, "features": {}, "combat_left": 0.0}
	var lab := TerrainLab.new()
	lab.terrain = data
	var a := TerrainTestCharacter.new()
	var b := TerrainTestCharacter.new()
	var c := TerrainTestCharacter.new()
	var people: Array[TerrainTestCharacter] = [a, b, c]
	lab.character = a
	lab.combat_actors = people
	for index in range(3):
		var actor := people[index]
		actor.data = data
		actor.exchange_enabled = true
		actor.person_id = index + 1
		actor.faction_id = 0 if index == 0 else 1
		actor.combatants = func() -> Array[TerrainTestCharacter]: return people
	assert(a.place(Vector2i(5, 5), true) and b.place(Vector2i(6, 5), true) and c.place(Vector2i(5, 6), true))
	a.combat_ability = 100
	b.combat_ability = 0
	c.combat_ability = 0
	lab._resolve_exchanges()
	assert(lab.exchange_count == 0, "Peaceful actor neighbours need an actual attack command")
	a.attack_target_id = b.person_id
	b.attack_target_id = a.person_id
	c.attack_target_id = a.person_id
	lab._resolve_exchanges()
	assert(lab.exchange_count == 2 and b.hp + c.hp == 196.0 and a.hp == 100.0,
		"Both eligible neighbours exchange with the surrounded actor in one round")
	lab._resolve_exchanges()
	assert(lab.exchange_count == 2, "Repeated queries cannot bypass owner cooldown")
	for tick in range(30):
		for actor: TerrainTestCharacter in people:
			actor.advance_combat(1.0 / 30.0, true)
	assert(a.exchange_cooldown == 0.0)
	# Both big losers have retreated out of adjacency; the next round reads their
	# current positions instead of replaying either old pair.
	lab._resolve_exchanges()
	assert(lab.exchange_count == 2)
	for actor: TerrainTestCharacter in people:
		actor.reset_combat()
	assert(a.place(Vector2i(5, 5), true) and b.place(Vector2i(6, 5), true) and c.place(Vector2i(5, 6), true))
	var indexed := {b.terrain_cell: [{"faction": 1}], c.terrain_cell: [{"faction": 1}]}
	var person := {"owner": a, "unit": -1, "id": a.person_id, "cell": a.terrain_cell, "faction": 0}
	assert(lab._exchange_context(person, indexed).encirclement == 2)
	data.static_blocked[data.index(b.terrain_cell)] = 1
	assert(lab._exchange_context(person, indexed).encirclement == 1, "Walls prevent threat sectors and cross-wall exchanges")
	c.faction_id = 0
	a.attack_target_id = b.person_id
	b.attack_target_id = a.person_id
	var before := lab.exchange_count
	lab._resolve_exchanges()
	assert(lab.exchange_count == before and b.hp == 100.0)
	data.site.actors = {"player": {"projectiles": [{"remaining": 1.0}]}}
	assert(lab.exchange_snapshot_guard(data).code == "UNSUPPORTED_ACTIVE_PROJECTILES")
	data.site.actors.player.projectiles.clear()
	assert(lab.exchange_snapshot_guard(data).ok)
	# Retained common action time: render partitions cannot drop slow-frame debt.
	var clock_lab := ClockLab.new()
	clock_lab._advance_action_time(0.017)
	clock_lab._advance_action_time(0.184)
	assert(is_equal_approx(clock_lab.consumed, 0.2))
	assert(absf(clock_lab._action_time_remainder - 0.001) < 0.000000001)
	clock_lab.free()
	_true_clock_duel()
	_single_pair_gate()
	_army_clock_gate()
	for actor: TerrainTestCharacter in people:
		actor.free()
	lab.free()
	print("SITE_EXCHANGE_FLOW_PASS pairing, fixed Actor/Army single-pair outcomes, direct owner parity, ranged melee, real Actor/Army clocks and pause")
	quit(0)

func _pair_appearance(weapon: String) -> Dictionary:
	var appearance := HumanCharacter3DEditor.default_appearance()
	appearance.parts.weapon = weapon
	appearance.parts.armor = "armor_light_leather_01"
	appearance.parts.shield = "none"
	assert(HumanCharacter3DEditor.valid_appearance(appearance))
	return appearance

func _single_pair_fixture(ability: float, troop_type: StringName = TerrainArmy.TROOP_TYPE_ID,
		wall: Vector2i = Vector2i(-1, -1), extra_row: bool = false) -> Dictionary:
	var data := TerrainData.new()
	data.allocate(Vector2i(12, 12))
	data.seed_value = 27
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.resize(144)
	data.static_blocked.fill(0)
	data.feature_at.resize(144)
	data.site = {"paused": false, "features": {}, "combat_left": 0.0, "controlled_person_id": 2}
	if data.contains(wall):
		data.static_blocked[data.index(wall)] = 1
	var lab := TrueClockLab.new()
	root.add_child(lab)
	lab.set_process(false)
	lab.terrain = data
	var actor := TerrainTestCharacter.new()
	lab.add_child(actor)
	actor.set_process(false)
	actor.data = data
	actor.exchange_enabled = true
	actor.combat_driven_by_lab = true
	actor.person_id = 1
	actor.faction_id = 0
	actor.combat_ability = ability
	actor.attack_target_id = 2
	actor.exchange_skill_authorized = func() -> bool: return true
	var actors: Array[TerrainTestCharacter] = [actor]
	actor.combatants = func() -> Array[TerrainTestCharacter]: return actors
	lab.character = actor
	lab.combat_actors = actors
	var actor_appearance := _pair_appearance("longsword_01")
	actor._saved_appearance = actor_appearance.duplicate(true)
	assert(Runtime.seed_person_equipment(data, actor.item_state, 1, actor_appearance).ok)
	assert(actor.place(Vector2i(5, 5), true))
	var team := TerrainArmy.new()
	lab.add_child(team)
	team.set_process(false)
	team.exchange_enabled = true
	team.team_id = 1
	team.faction_id = 1
	team.roster_size = 2 if extra_row else 1
	team.person_id_allocator = func(count: int) -> Array: return [2, 3] if count == 2 else [2]
	team.controlled_person_query = lab.controlled_person_id
	var selected: Array[Vector2i] = [Vector2i(6, 5)]
	if extra_row:
		selected.append(Vector2i(2, 2))
	assert(team.deploy_at(data, null, null, selected) and team.enable_combat(false, 0, troop_type))
	team.external_blocker = func(cell: Vector2i) -> bool: return actor.occupies_cell(cell)
	actor.cell_blocker = team.blocks_cell
	for index in range(team.combat_units.size()):
		var unit: Dictionary = team.combat_units[index]
		var weapon := "longsword_01"
		if index == 0 and troop_type == &"bow": weapon = "bow_01"
		if index == 0 and troop_type == &"crossbow": weapon = "crossbow_01"
		unit.appearance = _pair_appearance(weapon)
		unit.item_state = {}
		assert(Runtime.seed_person_equipment(data, unit.item_state, team.combat_identity(index), unit.appearance).ok)
	team.equipment_appearance_query = func(identity: int) -> Dictionary:
		var index := team.index_for_identity(identity)
		if index < 0: return {}
		var unit: Dictionary = team.combat_units[index]
		return Runtime.equipment_appearance(data, unit.item_state, unit.appearance)
	if troop_type in [&"bow", &"crossbow"]:
		team.combat_units[0].cargo = {"arrow": 1} if troop_type == &"bow" else {"bolt": 1}
	assert(actor.exchange_stats().weapon == "longsword_01" and actor.exchange_stats().armor == "armor_light_leather_01")
	assert(team.combat_identity(0) == 2 and team.exchange_stats(0).weapon == str(team.combat_units[0].appearance.parts.weapon)
		and team.exchange_stats(0).armor == "armor_light_leather_01",
		"Actor and Army combat stats must read their original, valid equipment holders")
	lab.army = team
	lab.combat_armies = [team]
	var events: Array[Dictionary] = []
	lab.exchange_resolved.connect(func(first: int, second: int, result: Dictionary) -> void:
		var winner_id := 0
		if int(result.winner) != 0:
			winner_id = first if int(result.winner) > 0 else second
		events.append({"round": lab._exchange_round, "low": mini(first, second), "high": maxi(first, second),
			"winner": winner_id, "kind": str(result.kind),
			"actor_margin": float(result.margin) * (1.0 if first == 1 else -1.0),
			"actor_hp": actor.hp, "army_hp": float(team.combat_units[0].hp),
			"actor_stun": actor.stun, "army_stun": float(team.combat_units[0].stun),
			"actor_fatigue": actor.fatigue, "army_fatigue": PersonFatigue.read(team.combat_units[0])})
	)
	return {"lab": lab, "data": data, "actor": actor, "army": team, "actors": actors, "events": events}

func _single_pair_owner_state(fixture: Dictionary) -> Dictionary:
	var actor: TerrainTestCharacter = fixture.actor
	var team: TerrainArmy = fixture.army
	var unit: Dictionary = team.combat_units[0]
	return {"actor_hp": actor.hp, "actor_stun": actor.stun, "actor_fatigue": actor.fatigue,
		"actor_rest": actor.fatigue_rest, "actor_cooldown": actor.exchange_cooldown,
		"actor_stagger": actor.exchange_stagger, "actor_skill_cooldown": actor.exchange_skill_cooldown,
		"actor_skill": actor._exchange_pending_skill, "actor_cell": actor.terrain_cell,
		"actor_from": actor.movement_from_cell, "actor_moving": actor.is_moving(),
		"actor_status": actor.combat_status, "actor_ammo": actor.ammo_inventory.duplicate(true),
		"actor_projectiles": actor.projectiles.duplicate(true), "army_hp": float(unit.hp),
		"army_stun": float(unit.stun), "army_fatigue": PersonFatigue.read(unit),
		"army_rest": float(unit.get("fatigue_rest", 0.0)), "army_cooldown": float(unit.get("exchange_cooldown", 0.0)),
		"army_stagger": float(unit.get("exchange_stagger", 0.0)), "army_skill_cooldown": float(unit.get("exchange_skill_cooldown", 0.0)),
		"army_skill": str(unit.get("exchange_skill", "")), "army_cell": team.cells[0], "army_to": team.moving_to[0],
		"army_progress": team.move_progress[0], "army_pose": str(unit.pose), "army_status": str(unit.status),
		"army_cargo": unit.get("cargo", {}).duplicate(true), "army_projectiles": team.projectiles.duplicate(true),
		"reserved": team._reserved_cells.duplicate(true), "occupied": team._cell_owners.duplicate(true)}

func _single_pair_direct(fixture: Dictionary) -> void:
	var lab: TerrainLab = fixture.lab
	var actor: TerrainTestCharacter = fixture.actor
	var team: TerrainArmy = fixture.army
	var actor_stats := actor.exchange_stats()
	var army_stats := team.exchange_stats(0)
	actor_stats.facility = 0.0
	army_stats.facility = 0.0
	var result := SiteCombatRules.exchange_result(actor_stats, army_stats, 0.0)
	var actor_ref := {"id": 1, "owner": actor, "unit": -1, "cell": actor.terrain_cell}
	var army_ref := {"id": 2, "owner": team, "unit": 0, "cell": team.cells[0]}
	actor.apply_exchange(team.cells[0], lab._exchange_side_outcome(army_ref, result, actor_stats, 1))
	team.apply_exchange(0, Vector2i(5, 5), lab._exchange_side_outcome(actor_ref, result, army_stats, -1))

func _single_pair_gate() -> void:
	# Fixed expected values are independent of the direct and Lab entry points.
	# The existing site_exchange_army_test.gd also exercises the original row's
	# direct draw/win/loss/reservation owner in a large deployed team.
	var cases: Array[Dictionary] = [
		{"name": "draw", "ability": 50.0, "kind": "draw", "winner": 0, "margin": 0.0,
			"actor_hp": 100.0, "actor_stun": 12.0, "actor_fatigue": 0.0,
			"army_hp": 100.0, "army_stun": 12.0, "army_fatigue": 0.0},
		{"name": "actor_small_win", "ability": 60.0, "kind": "small", "winner": 1, "margin": 10.0,
			"actor_hp": 100.0, "actor_stun": 0.0, "actor_fatigue": 0.5,
			"army_hp": 98.0, "army_stun": 12.0, "army_fatigue": 0.5},
		{"name": "army_small_win", "ability": 40.0, "kind": "small", "winner": 2, "margin": -10.0,
			"actor_hp": 98.0, "actor_stun": 12.0, "actor_fatigue": 0.5,
			"army_hp": 100.0, "army_stun": 0.0, "army_fatigue": 0.5},
		{"name": "actor_big_win_legal_push", "ability": 100.0, "kind": "big", "winner": 1, "margin": 50.0,
			"actor_hp": 100.0, "actor_stun": 0.0, "actor_fatigue": 0.5,
			"army_hp": 96.0, "army_stun": 12.0, "army_fatigue": 1.0, "army_to": Vector2i(7, 5)},
		{"name": "actor_big_win_wall", "ability": 100.0, "wall": Vector2i(7, 5),
			"kind": "big", "winner": 1, "margin": 50.0,
			"actor_hp": 100.0, "actor_stun": 0.0, "actor_fatigue": 0.5,
			"army_hp": 96.0, "army_stun": 12.0, "army_fatigue": 1.0},
		{"name": "army_big_win_legal_push", "ability": 0.0, "kind": "big", "winner": 2, "margin": -50.0,
			"actor_hp": 96.0, "actor_stun": 12.0, "actor_fatigue": 1.0,
			"army_hp": 100.0, "army_stun": 0.0, "army_fatigue": 0.5, "actor_cell": Vector2i(4, 5)},
		{"name": "army_big_win_wall", "ability": 0.0, "wall": Vector2i(4, 5),
			"kind": "big", "winner": 2, "margin": -50.0,
			"actor_hp": 96.0, "actor_stun": 12.0, "actor_fatigue": 1.0,
			"army_hp": 100.0, "army_stun": 0.0, "army_fatigue": 0.5},
		{"name": "actor_power", "ability": 50.0, "skill": "power", "kind": "small", "winner": 1, "margin": 15.0,
			"actor_hp": 100.0, "actor_stun": 0.0, "actor_fatigue": 0.5,
			"army_hp": 98.0, "army_stun": 22.0, "army_fatigue": 0.5, "actor_skill_cooldown": 8.0},
		{"name": "army_brace", "ability": 100.0, "skill": "brace", "kind": "big", "winner": 1, "margin": 35.0,
			"actor_hp": 100.0, "actor_stun": 0.0, "actor_fatigue": 0.5,
			"army_hp": 96.0, "army_stun": 12.0, "army_fatigue": 1.0, "army_skill_cooldown": 8.0},
		{"name": "adjacent_bow", "ability": 40.0, "troop": &"bow", "kind": "small", "winner": 2, "margin": -10.0,
			"actor_hp": 98.0, "actor_stun": 8.0, "actor_fatigue": 0.5,
			"army_hp": 100.0, "army_stun": 0.0, "army_fatigue": 0.5, "ammo": "arrow"},
		{"name": "adjacent_crossbow", "ability": 40.0, "troop": &"crossbow", "kind": "small", "winner": 2, "margin": -10.0,
			"actor_hp": 98.0, "actor_stun": 8.0, "actor_fatigue": 0.5,
			"army_hp": 100.0, "army_stun": 0.0, "army_fatigue": 0.5, "ammo": "bolt"},
	]
	for expected: Dictionary in cases:
		var fixture := _single_pair_fixture(float(expected.ability), expected.get("troop", TerrainArmy.TROOP_TYPE_ID),
			expected.get("wall", Vector2i(-1, -1)))
		var lab: TerrainLab = fixture.lab
		var actor: TerrainTestCharacter = fixture.actor
		var team: TerrainArmy = fixture.army
		if expected.get("skill", "") == "power": assert(actor.activate_exchange_skill("power"))
		if expected.get("skill", "") == "brace": assert(team.activate_exchange_skill(0, "brace"))
		lab._resolve_exchanges()
		var unit: Dictionary = team.combat_units[0]
		assert(lab._exchange_round == 1 and lab.exchange_count == 1 and fixture.events.size() == 1
			and int(lab.exchange_results[str(expected.kind)]) == 1,
			"Single-pair Lab resolution must occur exactly once: " + str(expected.name))
		var event: Dictionary = fixture.events[0]
		assert(event.low == 1 and event.high == 2 and event.winner == expected.winner
			and event.kind == expected.kind and event.actor_margin == expected.margin,
			"First-round IDs, winner, size and fixed roll differ: " + str(expected.name))
		assert(actor.hp == expected.actor_hp and actor.stun == expected.actor_stun
			and actor.fatigue == expected.actor_fatigue and float(unit.hp) == expected.army_hp
			and float(unit.stun) == expected.army_stun and PersonFatigue.read(unit) == expected.army_fatigue,
			"Original Actor/Army HP, stun or once-only fatigue differs: " + str(expected.name))
		assert(actor.exchange_cooldown == 1.0 and float(unit.get("exchange_cooldown", 0.0)) == 1.0
			and actor.exchange_skill_cooldown == expected.get("actor_skill_cooldown", 0.0)
			and float(unit.get("exchange_skill_cooldown", 0.0)) == expected.get("army_skill_cooldown", 0.0)
			and actor._exchange_pending_skill == "" and str(unit.get("exchange_skill", "")) == "",
			"The original one-round lock and queued skill must be consumed once: " + str(expected.name))
		assert(actor.terrain_cell == expected.get("actor_cell", Vector2i(5, 5))
			and team.cells[0] == Vector2i(6, 5)
			and team.moving_to[0] == expected.get("army_to", TerrainArmy.INVALID_CELL),
			"A legal or blocked push must preserve the original cell and reservation: " + str(expected.name))
		if expected.has("army_to"):
			assert(team._reserved_cells == {Vector2i(7, 5): 0} and team.blocks_cell(Vector2i(6, 5))
				and team.blocks_cell(Vector2i(7, 5)))
		else:
			assert(team._reserved_cells.is_empty())
		if expected.has("actor_cell"):
			assert(actor.movement_from_cell == Vector2i(5, 5) and actor.is_moving()
				and actor.occupies_cell(Vector2i(5, 5)) and actor.occupies_cell(Vector2i(4, 5)))
		else:
			assert(actor.terrain_cell == Vector2i(5, 5) and not actor.is_moving())
		assert(lab.ranged_shots == 0 and actor.projectiles.is_empty() and team.projectiles.is_empty())
		if expected.has("ammo"):
			assert(str(unit.pose) == "attack_unarmed" and int(unit.cargo[expected.ammo]) == 1,
				"An adjacent armed bow/crossbow row fights unarmed without releasing or spending ammo")
		# The one-pair direct entry is deliberately compared only on original owner
		# state: Lab's counters and pair reports are extra output, not owner state.
		if str(expected.name) in ["draw", "actor_small_win", "army_small_win"]:
			var direct := _single_pair_fixture(float(expected.ability))
			_single_pair_direct(direct)
			assert(_single_pair_owner_state(direct) == _single_pair_owner_state(fixture),
				"Original direct and Lab single-pair owner state differ: " + str(expected.name))
			(direct.lab as TerrainLab).free()
		lab.free()

func _army_clock_state(fixture: Dictionary) -> Dictionary:
	var state := _true_clock_state(fixture)
	var team: TerrainArmy = fixture.army
	var actor: TerrainTestCharacter = fixture.actor
	var data: TerrainData = fixture.data
	var rows: Array[Dictionary] = []
	for index in range(team.combat_units.size()):
		var unit: Dictionary = team.combat_units[index]
		rows.append({"id": team.combat_identity(index), "hp": float(unit.hp), "stun": float(unit.stun),
			"grace": float(unit.grace), "ko": float(unit.ko), "fatigue": PersonFatigue.read(unit),
			"rest": float(unit.get("fatigue_rest", 0.0)), "cooldown": float(unit.get("exchange_cooldown", 0.0)),
			"stagger": float(unit.get("exchange_stagger", 0.0)),
			"skill_cooldown": float(unit.get("exchange_skill_cooldown", 0.0)),
			"skill": str(unit.get("exchange_skill", "")), "cell": team.cells[index],
			"to": team.moving_to[index], "progress": team.move_progress[index],
			"duration": team.move_duration[index], "move_state": team.movement_state[index],
			"pose": str(unit.pose), "status": str(unit.status), "target": int(unit.target),
			"cargo": unit.get("cargo", {}).duplicate(true)})
	state.army_rows = rows
	state.reserved = team._reserved_cells.duplicate(true)
	state.occupied = team._cell_owners.duplicate(true)
	state.army_slots = team.combat_slots.duplicate()
	state.army_order = team.combat_order
	state.army_command = team.command
	state.army_attacking = team.combat_attacking
	state.army_needs_order = team.needs_attack_order
	state.actor_ability = actor.combat_ability
	state.wall = data.static_blocked[data.index(Vector2i(7, 5))]
	state.ranged_shots = (fixture.lab as TerrainLab).ranged_shots
	return state

func _army_clock_gate() -> void:
	var regular := _single_pair_fixture(60.0, TerrainArmy.TROOP_TYPE_ID, Vector2i(-1, -1), true)
	var slow := _single_pair_fixture(60.0, TerrainArmy.TROOP_TYPE_ID, Vector2i(-1, -1), true)
	var regular_lab: TerrainLab = regular.lab
	var slow_lab: TerrainLab = slow.lab
	var regular_team: TerrainArmy = regular.army
	var slow_team: TerrainArmy = slow.army
	assert(regular_team._reserve_combat_step(1, Vector2i(3, 2))
		and slow_team._reserve_combat_step(1, Vector2i(3, 2)))
	assert(regular_team._reserved_cells == {Vector2i(3, 2): 1}
		and slow_team._reserved_cells == {Vector2i(3, 2): 1})
	var previous := 0.0
	for checkpoint: float in [0.1, 0.4, 1.2, 2.4, 3.25]:
		var duration := checkpoint - previous
		_true_clock_feed(regular_lab, duration, [1.0 / 60.0])
		_true_clock_feed(slow_lab, duration, [0.017, 0.184, 0.4])
		assert(_army_clock_state(regular) == _army_clock_state(slow),
			"Actual Lab/Army states or events differ across render partitions at %.2f seconds" % checkpoint)
		assert(absf(regular_lab._action_time_remainder - slow_lab._action_time_remainder) < 0.000000001,
			"The Army case must retain the same common-clock sub-step debt")
		var actor: TerrainTestCharacter = regular.actor
		var unit: Dictionary = regular_team.combat_units[0]
		if checkpoint == 0.1:
			assert(regular_lab.exchange_count == 1 and regular.events[0].round == 1
				and regular.events[0].actor_margin == 10.0 and regular.events[0].kind == "small"
				and actor.hp == 100.0 and float(unit.hp) == 98.0
				and regular_team._reserved_cells == {Vector2i(3, 2): 1},
				"First small exchange must preserve another Army row's committed destination")
		elif checkpoint == 0.4:
			assert(regular_team.cells[1] == Vector2i(3, 2) and regular_team.moving_to[1] == TerrainArmy.INVALID_CELL
				and regular_team._reserved_cells.is_empty() and regular_team._cell_owners.get(Vector2i(3, 2)) == 1,
				"The original Army reservation completes and transfers occupancy")
		elif checkpoint == 1.2:
			assert(regular_lab.exchange_count == 2 and float(unit.hp) == 96.0,
				"The Actor/Army pair may exchange again only after its round lock")
			var paused_state := _army_clock_state(slow)
			var paused_remainder := slow_lab._action_time_remainder
			(slow.data as TerrainData).site.paused = true
			slow_lab._advance_action_time(0.4)
			assert(_army_clock_state(slow) == paused_state and slow_lab._action_time_remainder == paused_remainder,
				"Site pause must freeze Army movement, cooldown, fatigue and events")
			(slow.data as TerrainData).site.paused = false
			paused = true
			slow_lab._advance_action_time(0.4)
			assert(_army_clock_state(slow) == paused_state and slow_lab._action_time_remainder == paused_remainder,
				"SceneTree pause must not accumulate a delayed Army exchange")
			paused = false
			# Change both fixtures at the same simulated tick, not at their outer
			# render-frame index. The new wall blocks the later legal big-loss push.
			for fixture: Dictionary in [regular, slow]:
				(fixture.actor as TerrainTestCharacter).attack_target_id = 0
				var data: TerrainData = fixture.data
				data.static_blocked[data.index(Vector2i(7, 5))] = 1
		elif checkpoint == 2.4:
			assert(regular_lab.exchange_count == 2 and float(unit.hp) == 96.0,
				"An explicit command stop prevents all intervening pair reports")
			for fixture: Dictionary in [regular, slow]:
				var current_actor: TerrainTestCharacter = fixture.actor
				current_actor.attack_target_id = 2
				current_actor.combat_ability = 100.0
				assert(current_actor.activate_exchange_skill("power"))
		previous = checkpoint
	assert(regular_lab.exchange_count == 3 and slow_lab.exchange_count == 3)
	assert(regular.events[2].kind == "big" and regular.events[2].winner == 1
		and float(regular_team.combat_units[0].hp) == 92.0 and regular_team.cells[0] == Vector2i(6, 5)
		and regular_team.moving_to[0] == TerrainArmy.INVALID_CELL and regular_team._reserved_cells.is_empty()
		and (regular.actor as TerrainTestCharacter).exchange_skill_cooldown > 7.0,
		"The resumed powered win applies once while the same-tick wall blocks knockback")
	assert(absf(regular_lab._action_time_remainder - TerrainLab.EXCHANGE_ACTION_STEP * 0.5) < 0.000000001,
		"The Army real clock retains the unfinished half-step after 3.25 seconds")
	regular_lab.free()
	slow_lab.free()

func _true_clock_fixture() -> Dictionary:
	var data := TerrainData.new()
	data.allocate(Vector2i(12, 12))
	data.seed_value = 32125
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.resize(144)
	data.static_blocked.fill(0)
	data.static_blocked[data.index(Vector2i(7, 5))] = 1 # A real wall prevents the loser's retreat.
	data.feature_at.resize(144)
	data.site = {"paused": false, "features": {}, "combat_left": 0.0, "controlled_person_id": 1}
	var lab := TrueClockLab.new()
	root.add_child(lab)
	lab.set_process(false)
	lab.terrain = data
	var winner := TerrainTestCharacter.new()
	var loser := TerrainTestCharacter.new()
	var mover := TerrainTestCharacter.new()
	var actors: Array[TerrainTestCharacter] = [winner, loser, mover]
	lab.character = winner
	lab.combat_actors = actors
	for index in range(actors.size()):
		var actor := actors[index]
		lab.add_child(actor)
		actor.set_process(false)
		actor.data = data
		actor.exchange_enabled = true
		actor.combat_driven_by_lab = true
		actor.person_id = index + 1
		actor.faction_id = 1 if index == 1 else 0
		actor.combatants = func() -> Array[TerrainTestCharacter]: return actors
	var appearance := HumanCharacter3DEditor.default_appearance()
	appearance.parts.weapon = "hammer_01"
	appearance.parts.armor = "armor_iron_01"
	appearance.parts.shield = "none"
	appearance.parts.cape = "none"
	for actor: TerrainTestCharacter in actors:
		actor._saved_appearance = appearance.duplicate(true)
		var seeded := Runtime.seed_person_equipment(data, actor.item_state, actor.person_id, appearance)
		assert(seeded.ok
			and actor.exchange_stats().weapon == "hammer_01" and actor.exchange_stats().armor == "armor_iron_01",
			"The action-clock duel uses each original person's valid iron hammer and armor holder")
	assert(winner.place(Vector2i(5, 5), true) and loser.place(Vector2i(6, 5), true)
		and mover.place(Vector2i(2, 2), true))
	winner.combat_ability = 100.0
	loser.combat_ability = 0.0
	winner.attack_target_id = loser.person_id
	loser.attack_target_id = winner.person_id
	winner.exchange_skill_authorized = func() -> bool: return true
	assert(winner.activate_exchange_skill("power"))
	assert(mover.step(Vector2i.RIGHT), "A third original person commits a step on the same clock")
	var events: Array[Dictionary] = []
	lab.exchange_resolved.connect(func(first: int, second: int, result: Dictionary) -> void:
		var winner_id := 0
		if int(result.winner) != 0:
			winner_id = first if int(result.winner) > 0 else second
		events.append({"round": lab._exchange_round, "low": mini(first, second), "high": maxi(first, second),
			"winner": winner_id, "kind": str(result.kind), "margin": absf(float(result.margin)),
			"winner_hp": winner.hp, "loser_hp": loser.hp, "loser_stun": loser.stun})
	)
	return {"lab": lab, "data": data, "actors": actors, "events": events}

func _true_clock_feed(lab: TerrainLab, duration: float, chunks: Array[float]) -> void:
	var remaining := duration
	var index := 0
	while remaining > 0.000000000001:
		var interval := minf(chunks[index % chunks.size()], remaining)
		lab._advance_action_time(interval)
		remaining -= interval
		index += 1

func _true_clock_state(fixture: Dictionary) -> Dictionary:
	var lab: TerrainLab = fixture.lab
	var people: Array[Dictionary] = []
	for actor: TerrainTestCharacter in fixture.actors:
		people.append({"id": actor.person_id, "hp": actor.hp, "stun": actor.stun,
			"grace": actor.stun_grace, "ko": actor.knockout_left, "fatigue": actor.fatigue,
			"rest": actor.fatigue_rest, "cooldown": actor.exchange_cooldown,
			"stagger": actor.exchange_stagger, "action_time": actor.action_time,
			"skill_cooldown": actor.exchange_skill_cooldown, "skill": actor._exchange_pending_skill,
			"cell": actor.terrain_cell, "from": actor.movement_from_cell,
			"elapsed": actor._movement_elapsed, "duration": actor._movement_duration,
			"position": actor.position, "moving": actor.is_moving(),
			"target": actor.attack_target_id, "status": actor.combat_status,
			"animation": actor.visual_state.animation_id,
			"animation_time": actor.visual_state.animation_time})
	return {"round": lab._exchange_round, "phase": lab._exchange_phase,
		"count": lab.exchange_count, "results": lab.exchange_results.duplicate(true),
		"events": fixture.events.duplicate(true), "people": people}

func _true_clock_duel() -> void:
	var regular := _true_clock_fixture()
	var slow := _true_clock_fixture()
	var regular_lab: TerrainLab = regular.lab
	var slow_lab: TerrainLab = slow.lab
	var slow_data: TerrainData = slow.data
	var previous := 0.0
	for checkpoint: float in [0.1, 0.4, 1.2, 2.4, 3.25]:
		var duration := checkpoint - previous
		_true_clock_feed(regular_lab, duration, [1.0 / 60.0])
		_true_clock_feed(slow_lab, duration, [0.017, 0.184, 0.4])
		assert(_true_clock_state(regular) == _true_clock_state(slow),
			"Actual Lab/Actor results differ at %.2f seconds across render partitions" % checkpoint)
		assert(absf(regular_lab._action_time_remainder - slow_lab._action_time_remainder) < 0.000000001,
			"The original shared action clock retains the same sub-step debt")
		var winner: TerrainTestCharacter = regular.actors[0]
		var loser: TerrainTestCharacter = regular.actors[1]
		var mover: TerrainTestCharacter = regular.actors[2]
		if checkpoint == 0.1:
			assert(regular_lab.exchange_count == 1 and winner.hp == 100.0 and loser.hp == 98.0
				and loser.stun == 45.0 and loser.terrain_cell == Vector2i(6, 5) and not loser.is_moving()
				and winner.exchange_skill_cooldown == 8.0 and regular.events[0].winner == 1
				and regular.events[0].kind == "big", "One equipped iron-hammer big win costs 2 HP, adds power stun and cannot retreat through a wall")
		elif checkpoint == 0.4:
			assert(mover.terrain_cell == Vector2i(3, 2) and not mover.is_moving(),
				"The original committed move finishes under both frame partitions")
		elif checkpoint == 1.2:
			assert(regular_lab.exchange_count == 2 and loser.hp == 96.0 and loser.stun == 80.0,
				"The same single pair can exchange again after its one-second cooldown")
			var paused_state := _true_clock_state(slow)
			var paused_remainder := slow_lab._action_time_remainder
			slow_data.site.paused = true
			slow_lab._advance_action_time(0.4)
			assert(_true_clock_state(slow) == paused_state and slow_lab._action_time_remainder == paused_remainder,
				"Site pause freezes the real exchange, movement, fatigue and action clock")
			slow_data.site.paused = false
			paused = true
			slow_lab._advance_action_time(0.4)
			assert(_true_clock_state(slow) == paused_state and slow_lab._action_time_remainder == paused_remainder,
				"SceneTree pause freezes the real exchange and does not accumulate a catch-up round")
			paused = false
		elif checkpoint == 2.4:
			assert(regular_lab.exchange_count == 3 and loser.hp == 94.0 and loser.knockout_left > 0.0,
				"Repeated single-pair stun reaches the original KO owner once")
		previous = checkpoint
	assert(regular_lab.exchange_count == 3 and slow_lab.exchange_count == 3)
	assert(absf(regular_lab._action_time_remainder - TerrainLab.EXCHANGE_ACTION_STEP * 0.5) < 0.000000001,
		"The real exchange clock retains the unfinished half-step after 3.25 seconds")
	regular_lab.free()
	slow_lab.free()

class ClockLab extends TerrainLab:
	var consumed := 0.0
	func _advance_combat(delta: float, _combat_clock: float = -1.0) -> void:
		consumed += delta

class TrueClockLab extends TerrainLab:
	func _ready() -> void:
		# Assemble only the two test owners; retain the original action/combat methods.
		process_mode = Node.PROCESS_MODE_ALWAYS
