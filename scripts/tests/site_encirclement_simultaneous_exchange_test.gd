extends SceneTree
## Headless Lab + original Actor owners. Fixed abilities give unambiguous
## small wins/losses and seeded boundary draws without mocking pair results.

func _initialize() -> void:
	run.call_deferred()

func _require(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
	return condition

func _fixture(abilities: Array, hp: float = 100.0, stun: float = 0.0, batch: bool = true,
		enemy_factions: Array = [], layout: Dictionary = {}) -> Dictionary:
	var data := TerrainData.new()
	data.allocate(Vector2i(12, 12))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.resize(144)
	data.feature_at.resize(144)
	data.site = {"paused": false, "features": {}, "combat_left": 0.0}
	var lab := TerrainLab.new()
	lab.terrain = data
	lab.exchange_batch_enabled = batch
	var people: Array[TerrainTestCharacter] = []
	var cells: Array[Vector2i] = [Vector2i(5, 5), Vector2i(6, 5), Vector2i(5, 6),
		Vector2i(4, 5), Vector2i(5, 4)]
	var custom_cells: Array = layout.get("cells", [])
	var ids: Array = layout.get("ids", [])
	var targets: Array = layout.get("targets", [])
	for i in range(abilities.size() + 1):
		var actor := TerrainTestCharacter.new()
		actor.data = data
		actor.exchange_enabled = true
		actor.person_id = int(ids[i]) if ids.size() > i else i + 1
		actor.faction_id = 0 if i == 0 else int(enemy_factions[i - 1]) if not enemy_factions.is_empty() else 1
		actor.combat_ability = 50.0 if i == 0 else float(abilities[i - 1])
		actor._saved_appearance = {"parts": {"weapon": "longsword_01", "armor": "armor_iron_01"}}
		actor.attack_target_id = int(targets[i]) if targets.size() > i else (2 if i == 0 else 1)
		actor.combatants = func() -> Array[TerrainTestCharacter]: return people
		var cell: Vector2i = custom_cells[i] if custom_cells.size() > i else cells[i]
		assert(actor.place(cell, true))
		people.append(actor)
	people[0].hp = hp
	people[0].stun = stun
	lab.character = people[0]
	lab.combat_actors.append_array(people)
	if bool(layout.get("reverse_roster", false)):
		lab.combat_actors.reverse()
	var events: Array[Dictionary] = []
	lab.exchange_resolved.connect(func(a_id: int, b_id: int, result: Dictionary) -> void:
		var health: Array[float] = []
		for actor: TerrainTestCharacter in people:
			health.append(actor.hp)
		events.append({"a": a_id, "b": b_id, "result": result.duplicate(true),
			"health": health, "center_status": people[0].combat_status}))
	return {"lab": lab, "people": people, "events": events}

func _dispose(fixture: Dictionary) -> void:
	for actor: TerrainTestCharacter in fixture.people:
		actor.free()
	(fixture.lab as TerrainLab).free()

func _check_case(spec: Dictionary) -> bool:
	var fixture := _fixture(spec.abilities, float(spec.get("initial_hp", 100.0)),
		float(spec.get("initial_stun", 0.0)), bool(spec.get("batch", true)), spec.get("factions", []))
	var lab: TerrainLab = fixture.lab
	var people: Array = fixture.people
	var events: Array = fixture.events
	lab._resolve_exchanges()
	var name: String = spec.name
	var count: int = spec.abilities.size()
	var center: TerrainTestCharacter = people[0]
	var ok := _require(lab.exchange_count == count and events.size() == count,
		"%s: all %d adjacent opponents must exchange exactly once" % [name, count])
	var final_health: Array[float] = []
	for actor: TerrainTestCharacter in people:
		final_health.append(actor.hp)
	var seen := {}
	for event: Dictionary in events:
		var a_id: int = event.a
		var b_id: int = event.b
		var opponent_id := b_id if a_id == 1 else a_id
		ok = _require((a_id == 1 or b_id == 1) and opponent_id >= 2 and opponent_id <= count + 1
			and not seen.has(opponent_id), "%s: duplicate or unrelated pair" % name) and ok
		seen[opponent_id] = true
		var winner: int = event.result.winner
		var winner_id := 0 if winner == 0 else (a_id if winner == 1 else b_id)
		ok = _require(winner_id == int(spec.winners[opponent_id - 2]),
			"%s: unexpected independent outcome against person %d" % [name, opponent_id]) and ok
		ok = _require(event.health == final_health and event.center_status == center.combat_status,
			"%s: event observed a partially settled round" % name) and ok
	ok = _require(is_equal_approx(center.hp, float(spec.center_hp))
		and is_equal_approx(center.stun, float(spec.center_stun))
		and is_equal_approx(center.fatigue, float(spec.center_fatigue)),
		"%s: center HP, stun, or fatigue did not aggregate per pair" % name) and ok
	ok = _require(center._received_effective_hit == int(spec.hit_notifications)
		and center.combat_status.begins_with(str(spec.status))
		and center.exchange_cooldown == SiteCombatRules.EXCHANGE_ROUND_SECONDS,
		"%s: center must commit one final reaction and one cooldown" % name) and ok
	if spec.has("animation"):
		ok = _require(center.visual_state.animation_id == StringName(spec.animation),
			"%s: final animation contradicts the aggregate outcome" % name) and ok
	if spec.has("knockout"):
		ok = _require((center.knockout_left > 0.0) == bool(spec.knockout),
			"%s: same-round knockout result" % name) and ok
	if spec.has("center_cell"):
		ok = _require(center.terrain_cell == spec.center_cell,
			"%s: occupied retreat cell must block knockback" % name) and ok
	if bool(spec.get("no_overlap", false)):
		var reserved := {}
		for actor: TerrainTestCharacter in people:
			var actor_cells: Array[Vector2i] = [actor.terrain_cell]
			if actor.is_moving() and actor.movement_from_cell != actor.terrain_cell:
				actor_cells.append(actor.movement_from_cell)
			for cell: Vector2i in actor_cells:
				ok = _require(not reserved.has(cell), "%s: two original Actors occupy or reserve %s" % [name, cell]) and ok
				reserved[cell] = actor.person_id
	for i in range(count):
		var enemy: TerrainTestCharacter = people[i + 1]
		ok = _require(is_equal_approx(enemy.hp, float(spec.enemy_hp[i]))
			and is_equal_approx(enemy.stun, float(spec.enemy_stun[i]))
			and is_equal_approx(enemy.fatigue, float(spec.enemy_fatigue[i]))
			and enemy.exchange_cooldown == SiteCombatRules.EXCHANGE_ROUND_SECONDS,
			"%s: opponent %d lost its independent outcome" % [name, i + 2]) and ok
	_dispose(fixture)
	return ok

func _check_cooldown() -> bool:
	var fixture := _fixture([35.0, 70.0])
	var lab: TerrainLab = fixture.lab
	var people: Array = fixture.people
	lab._resolve_exchanges()
	var center: TerrainTestCharacter = people[0]
	var weak: TerrainTestCharacter = people[1]
	lab._resolve_exchanges()
	var ok := _require(lab.exchange_count == 2 and center.hp == 99.0 and weak.hp == 99.0,
		"Repeated query within one second must not replay either pair")
	for actor: TerrainTestCharacter in people:
		actor.advance_combat(0.99, true)
	lab._resolve_exchanges()
	ok = _require(lab.exchange_count == 2, "A round cannot restart before one second") and ok
	for actor: TerrainTestCharacter in people:
		actor.advance_combat(0.01, true)
	lab._resolve_exchanges()
	ok = _require(lab.exchange_count == 4 and center.hp == 98.0 and weak.hp == 98.0,
		"At one second both still-adjacent opponents may exchange again") and ok
	_dispose(fixture)
	return ok

func _graph_run(batch: bool, reverse_roster: bool) -> Dictionary:
	# B and C share their low 32 bits, so a truncated pair key loses A-C.
	var large_id := 4294967298
	var fixture := _fixture([0.0, 0.0, 50.0], 100.0, 0.0, batch, [1, 1, 0],
		{"cells": [Vector2i(5, 5), Vector2i(6, 5), Vector2i(5, 6), Vector2i(5, 7)],
			"ids": [1, 2, large_id, 3], "targets": [2, 1, 1, large_id],
			"reverse_roster": reverse_roster})
	var lab: TerrainLab = fixture.lab
	var people: Array = fixture.people
	var events: Array = fixture.events
	lab._resolve_exchanges()
	var label := "graph batch=%s reverse=%s" % [batch, reverse_roster]
	var edges := {}
	var sequence: Array[String] = []
	var final_health: Array[float] = []
	for actor: TerrainTestCharacter in people:
		final_health.append(actor.hp)
	var ok := _require(lab.exchange_count == 3 and events.size() == 3,
		"%s: A-B, A-C and C-D must all exchange once" % label)
	for event: Dictionary in events:
		var a_id := int(event.a)
		var b_id := int(event.b)
		var low := mini(a_id, b_id)
		var high := maxi(a_id, b_id)
		var key := "%d:%d" % [low, high]
		var result: Dictionary = event.result
		var winner := int(result.winner)
		var winner_id := 0 if winner == 0 else (a_id if winner == 1 else b_id)
		ok = _require(not edges.has(key), "%s: duplicate pair %s" % [label, key]) and ok
		ok = _require(event.health == final_health, "%s: event saw partial settlement" % label) and ok
		edges[key] = [winner_id, str(result.kind),
			float(result.margin) if a_id == low else -float(result.margin),
			float(result.hp_a) if a_id == low else float(result.hp_b),
			float(result.hp_b) if a_id == low else float(result.hp_a),
			float(result.stun_a) if a_id == low else float(result.stun_b),
			float(result.stun_b) if a_id == low else float(result.stun_a),
			float(result.fatigue_a) if a_id == low else float(result.fatigue_b),
			float(result.fatigue_b) if a_id == low else float(result.fatigue_a)]
		sequence.append(key)
	ok = _require(edges.size() == 3 and edges.has("1:2") and edges.has("1:%d" % large_id)
		and edges.has("3:%d" % large_id) and int(edges["1:2"][0]) == 1
		and int(edges["1:%d" % large_id][0]) == 1 and int(edges["3:%d" % large_id][0]) == 3,
		"%s: wrong graph edge or independent winner" % label) and ok
	ok = _require(is_equal_approx(people[0].hp, 100.0) and is_equal_approx(people[1].hp, 98.0)
		and is_equal_approx(people[2].hp, 96.0) and is_equal_approx(people[3].hp, 100.0)
		and is_equal_approx(people[2].stun, 24.0) and is_equal_approx(people[2].fatigue, 2.0),
		"%s: C must absorb both A and D losses" % label) and ok
	var ordered_edges: Array = []
	var keys: Array = edges.keys()
	keys.sort()
	for key: Variant in keys:
		ordered_edges.append([key, edges[key]])
	var state: Array = []
	for actor: TerrainTestCharacter in people:
		state.append([actor.hp, actor.stun, actor.fatigue, actor.terrain_cell,
			actor.exchange_cooldown, actor.combat_status, actor._received_effective_hit])
	_dispose(fixture)
	return {"ok": ok, "result": [ordered_edges, state], "sequence": sequence}

func _check_graph_and_ids() -> bool:
	var reference := _graph_run(true, false)
	if not bool(reference.ok): return false
	var changed_traversal := false
	for mode: Array in [[true, true], [false, false], [false, true]]:
		var candidate := _graph_run(bool(mode[0]), bool(mode[1]))
		if not bool(candidate.ok): return false
		if not _require(candidate.result == reference.result,
			"Graph pair outcomes and owner state must be independent of roster order and snapshot/fallback"):
			return false
		changed_traversal = changed_traversal or candidate.sequence != reference.sequence
	return _require(changed_traversal, "Reversed roster must exercise a different pair traversal order")

func _mixed_army_fixture(kind: String, batch: bool = true, reverse_owners: bool = false) -> Dictionary:
	# Real Actor/Army owners and the Lab resolver, with a small walkable Site.
	# This contract fixture does not create inventory or claim a save/UI pass.
	var data := TerrainData.new()
	data.allocate(Vector2i(40, 40))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.resize(1600)
	data.feature_at.resize(1600)
	data.site = {"paused": false, "features": {}, "combat_left": 0.0, "controlled_person_id": 1}
	var lab := TerrainLab.new()
	lab.terrain = data
	lab.exchange_batch_enabled = batch
	var actor := TerrainTestCharacter.new()
	actor.data = data
	actor.exchange_enabled = true
	actor.person_id = 1
	actor.faction_id = 0
	actor._saved_appearance = {"parts": {"weapon": "longsword_01", "armor": "armor_iron_01"}}
	assert(actor.place(Vector2i(20, 20) if kind in ["skill", "competition", "dying_blocker"] else Vector2i(18, 17), true))
	lab.character = actor
	lab.combat_actors.append(actor)
	actor.combatants = func() -> Array[TerrainTestCharacter]: return lab.combat_actors
	actor.exchange_skill_authorized = func() -> bool: return actor.person_id == lab.controlled_person_id()
	var friendly := TerrainArmy.new()
	friendly.team_id = 1
	friendly.faction_id = 0
	friendly.exchange_enabled = true
	root.add_child(friendly)
	friendly.set_process(false)
	var enemy := TerrainArmy.new()
	enemy.team_id = 2
	enemy.faction_id = 1
	enemy.exchange_enabled = true
	root.add_child(enemy)
	enemy.set_process(false)
	var friendly_cells: Array[Vector2i] = [Vector2i(18, 18), Vector2i(20, 20), Vector2i(22, 20), Vector2i(18, 19)]
	var enemy_cells: Array[Vector2i] = [Vector2i(30, 30), Vector2i(21, 20), Vector2i(20, 21), Vector2i(22, 21)]
	if kind == "skill":
		friendly_cells = [Vector2i(10, 10), Vector2i(11, 10), Vector2i(10, 11), Vector2i(11, 11)]
		enemy_cells = [Vector2i(30, 30), Vector2i(21, 20), Vector2i(20, 21), Vector2i(19, 20), Vector2i(20, 19)]
	elif kind == "army_skill":
		friendly_cells = [Vector2i(20, 20), Vector2i(10, 10), Vector2i(11, 10), Vector2i(10, 11)]
		enemy_cells = [Vector2i(30, 30), Vector2i(21, 20), Vector2i(20, 21), Vector2i(19, 20), Vector2i(20, 19)]
	elif kind == "competition":
		friendly_cells = [Vector2i(10, 10), Vector2i(22, 20), Vector2i(10, 11), Vector2i(11, 11)]
		enemy_cells = [Vector2i(30, 30), Vector2i(19, 20), Vector2i(23, 20)]
	elif kind == "dying_blocker":
		friendly_cells = [Vector2i(10, 10), Vector2i(19, 20), Vector2i(10, 11), Vector2i(11, 11)]
		enemy_cells = [Vector2i(30, 30), Vector2i(21, 20), Vector2i(18, 20)]
	friendly.roster_size = friendly_cells.size()
	enemy.roster_size = enemy_cells.size()
	assert(friendly.deploy_at(data, actor, null, friendly_cells) and friendly.enable_combat(true))
	assert(enemy.deploy_at(data, actor, null, enemy_cells) and enemy.enable_combat(true))
	friendly.external_blocker = enemy.blocks_cell
	enemy.external_blocker = friendly.blocks_cell
	actor.cell_blocker = func(cell: Vector2i, _requester: Node) -> bool:
		return friendly.blocks_cell(cell) or enemy.blocks_cell(cell)
	friendly.controlled_person_query = lab.controlled_person_id
	enemy.controlled_person_query = lab.controlled_person_id
	assert(friendly.join_player(actor).ok)
	lab.combat_armies.assign([friendly, enemy])
	if reverse_owners: lab.combat_armies.reverse()
	actor.attack_target_id = enemy.combat_identity(1)
	if kind == "skill":
		actor.combat_ability = 100.0
	elif kind == "army_skill":
		friendly.training = 100.0
	else:
		friendly.team_fatigue.fatigue = 95.0
		enemy.training = 100.0
		if kind in ["death", "ko", "committed"]:
			data.site.controlled_person_id = friendly.combat_identity(2)
			if kind == "death": friendly.combat_units[1].hp = 0.01
			elif kind == "ko": friendly.combat_units[1].stun = 95.0
			elif kind == "committed":
				assert(friendly._reserve_combat_step(2, Vector2i(23, 20)))
		else:
			actor.combat_ability = 0.0
			if kind == "dying_blocker": friendly.combat_units[1].hp = 0.01
	var events: Array[Dictionary] = []
	var deaths: Array[int] = []
	lab.exchange_resolved.connect(func(a_id: int, b_id: int, result: Dictionary) -> void:
		events.append({"a": a_id, "b": b_id, "result": result.duplicate(true)}))
	friendly.died.connect(func(id: int) -> void: deaths.append(id))
	return {"lab": lab, "actor": actor, "friendly": friendly, "enemy": enemy, "events": events, "deaths": deaths}

func _dispose_mixed(fixture: Dictionary) -> void:
	(fixture.friendly as TerrainArmy).free()
	(fixture.enemy as TerrainArmy).free()
	(fixture.actor as TerrainTestCharacter).free()
	(fixture.lab as TerrainLab).free()

func _mixed_pair_results(events: Array[Dictionary]) -> Dictionary:
	var pairs := {}
	for event: Dictionary in events:
		var low := mini(int(event.a), int(event.b))
		var high := maxi(int(event.a), int(event.b))
		var winner := int(event.result.winner)
		var winner_id := 0 if winner == 0 else int(event.a) if winner == 1 else int(event.b)
		var key := "%d:%d" % [low, high]
		assert(not pairs.has(key), "One unordered pair must resolve once")
		pairs[key] = [winner_id, str(event.result.kind), float(event.result.hp), float(event.result.stun)]
	return pairs

func _check_existing_fatigue_on_draw() -> bool:
	var fixture := _fixture([50.0, 50.0])
	for actor: TerrainTestCharacter in fixture.people:
		actor.fatigue = 20.0
		actor.fatigue_rest = 5.0
	(fixture.lab as TerrainLab)._resolve_exchanges()
	var center: TerrainTestCharacter = fixture.people[0]
	var ok := _require(fixture.events.size() == 2 and int(fixture.events[0].result.winner) == 0
		and int(fixture.events[1].result.winner) == 0 and center.hp == 100.0
		and center.fatigue == 20.0 and center.fatigue_rest == 0.0
		and center._received_effective_hit == 1,
		"Two draws add no fatigue or HP, retain prior fatigue, and apply one hit/rest reaction")
	_dispose(fixture)
	return ok

func _check_two_big_losses_one_reaction() -> bool:
	var fixture := _fixture([100.0, 100.0])
	var lab: TerrainLab = fixture.lab
	var center: TerrainTestCharacter = fixture.people[0]
	var opponent: TerrainTestCharacter = fixture.people[1]
	var expected_hp := SiteCombatRules.exchange_hp(str(opponent.exchange_stats().weapon), str(center.exchange_stats().armor), true)
	var expected_stun := SiteCombatRules.exchange_stun(str(opponent.exchange_stats().weapon))
	lab._resolve_exchanges()
	var ok := _require(lab.exchange_count == 2 and fixture.events.size() == 2
		and str(fixture.events[0].result.kind) == "big" and str(fixture.events[1].result.kind) == "big"
		and is_equal_approx(center.hp, 100.0 - 2.0 * expected_hp)
		and is_equal_approx(center.stun, 2.0 * expected_stun)
		and is_equal_approx(center.fatigue, 2.0) and center._received_effective_hit == 1
		and is_equal_approx(center.exchange_stagger, SiteCombatRules.EXCHANGE_BIG_STAGGER)
		and center.is_moving() and center.terrain_cell == Vector2i(5, 4)
		and center.movement_from_cell == Vector2i(5, 5),
		"Two big losses must accumulate damage and cost, but choose one deterministic push and maximum hold: %s" %
		str({"exchanges": lab.exchange_count, "events": fixture.events, "hp": center.hp,
			"expected_hp": 100.0 - 2.0 * expected_hp, "stun": center.stun,
			"expected_stun": 2.0 * expected_stun, "fatigue": center.fatigue,
			"hit": center._received_effective_hit, "stagger": center.exchange_stagger,
			"moving": center.is_moving(), "cell": center.terrain_cell,
			"from": center.movement_from_cell}))
	_dispose(fixture)
	return ok

func _check_actor_committed_step() -> bool:
	var fixture := _fixture([100.0, 100.0], 100.0, 0.0, true, [],
		{"cells": [Vector2i(5, 5), Vector2i(6, 4), Vector2i(5, 3)]})
	var lab: TerrainLab = fixture.lab
	var center: TerrainTestCharacter = fixture.people[0]
	assert(center.place(Vector2i(5, 4), false, TerrainTestCharacter.MOVE_DURATION))
	var committed := center.terrain_cell
	var source := center.movement_from_cell
	lab._resolve_exchanges()
	var ok := _require(lab.exchange_count == 2 and center.is_moving()
		and center.terrain_cell == committed and center.movement_from_cell == source
		and is_equal_approx(center.exchange_stagger, TerrainTestCharacter.MOVE_DURATION + SiteCombatRules.EXCHANGE_BIG_STAGGER),
		"Two incoming losses cannot replace the Actor's previously committed step")
	center.advance_combat(TerrainTestCharacter.MOVE_DURATION, true)
	ok = _require(not center.is_moving() and center.terrain_cell == committed
		and is_equal_approx(center.exchange_stagger, SiteCombatRules.EXCHANGE_BIG_STAGGER),
		"After the Actor arrives, exactly one maximum stagger remains") and ok
	_dispose(fixture)
	return ok

func _mixed_death_round(kind: String, batch: bool, reverse_owners: bool) -> Dictionary:
	var fixture := _mixed_army_fixture(kind, batch, reverse_owners)
	var lab: TerrainLab = fixture.lab
	var actor: TerrainTestCharacter = fixture.actor
	var friendly: TerrainArmy = fixture.friendly
	var enemy: TerrainArmy = fixture.enemy
	var first_id := friendly.combat_identity(1)
	var second_id := friendly.combat_identity(2)
	var enemy_ids := [enemy.combat_identity(1), enemy.combat_identity(2), enemy.combat_identity(3)]
	var expected_hp := SiteCombatRules.exchange_hp(str(enemy.exchange_stats(1).weapon), str(friendly.exchange_stats(2).armor), true)
	# The named officer at row 3 automatically uses power when facing one adjacent enemy.
	assert(enemy.command_abilities.has(3))
	var expected_stun := SiteCombatRules.exchange_stun(str(enemy.exchange_stats(1).weapon)) \
		+ SiteCombatRules.exchange_stun(str(enemy.exchange_stats(3).weapon)) \
		+ SiteCombatRules.EXCHANGE_POWER_STUN
	var initial_row2_stun := float(friendly.combat_units[2].stun)
	var original_destination := friendly.moving_to[2]
	var accepted_before := friendly.accepted_count
	lab._resolve_exchanges()
	var pairs := _mixed_pair_results(fixture.events)
	var expected_keys := {}
	for edge: Array in [[first_id, enemy_ids[0]], [first_id, enemy_ids[1]],
			[second_id, enemy_ids[0]], [second_id, enemy_ids[2]]]:
		expected_keys["%d:%d" % [mini(int(edge[0]), int(edge[1])), maxi(int(edge[0]), int(edge[1]))]] = true
	var ok := _require(lab.exchange_count == 4 and pairs.size() == 4 and expected_keys.size() == 4,
		"Mixed Army round must settle exactly four independent edges")
	for key: Variant in pairs.keys():
		ok = _require(expected_keys.has(key), "Mixed Army round produced an unrelated edge") and ok
	for edge: Array in pairs.values():
		ok = _require(int(edge[0]) in enemy_ids and str(edge[1]) == "big", "High-training enemies must win each edge by a big margin") and ok
	ok = _require(is_equal_approx(float(friendly.team_fatigue.fatigue), 95.8)
		and friendly.team_fatigue.count == (4 if kind == "death" else 5)
		and is_equal_approx(float(enemy.team_fatigue.fatigue), 0.5)
		and is_equal_approx(actor.fatigue, 95.8) and actor.fatigue_rest == 0.0
		and is_same(PersonFatigue.pool(friendly.combat_units[3]), friendly.team_fatigue)
		and is_equal_approx(PersonFatigue.read(friendly.combat_units[3]), 95.8),
		"All four costs must use the five-person pool before any death") and ok
	ok = _require(is_equal_approx(float(friendly.combat_units[2].hp), 100.0 - 2.0 * expected_hp)
		and is_equal_approx(float(friendly.combat_units[2].stun), initial_row2_stun + expected_stun)
		and int(friendly.combat_units[1].hit_revision) == 1 and int(friendly.combat_units[2].hit_revision) == 1,
		"Two Army rows must each receive one aggregate hit from two pairs: %s" %
		str({"kind": kind, "row1_revision": friendly.combat_units[1].hit_revision,
			"row2_revision": friendly.combat_units[2].hit_revision,
			"row2_hp": friendly.combat_units[2].hp, "expected_hp": 100.0 - 2.0 * expected_hp,
			"row2_stun": friendly.combat_units[2].stun,
			"expected_stun": initial_row2_stun + expected_stun,
			"events": fixture.events})) and ok
	if kind == "death":
		ok = _require(float(friendly.combat_units[1].hp) == 0.0 and fixture.deaths == [first_id]
			and PersonFatigue.pool(friendly.combat_units[1]).is_empty(),
			"One multi-pair casualty dies once after paying the original pool") and ok
	elif kind == "ko":
		ok = _require(float(friendly.combat_units[1].hp) > 0.0 and float(friendly.combat_units[1].ko) > 0.0
			and fixture.deaths.is_empty() and is_same(PersonFatigue.pool(friendly.combat_units[1]), friendly.team_fatigue),
			"A multi-pair knockout remains a living member of the shared pool") and ok
	else:
		ok = _require(original_destination == Vector2i(23, 20) and friendly.moving_to[2] == original_destination
			and friendly.moving_to[1] == Vector2i(20, 19) and friendly.accepted_count == accepted_before + 1
			and is_equal_approx(float(friendly.combat_units[2].exchange_stagger), TerrainArmy.MOVE_DURATION + SiteCombatRules.EXCHANGE_BIG_STAGGER),
			"Multi-pair losses retain the already committed Army step and add one maximum stagger") and ok
	if kind != "committed":
		ok = _require(friendly.moving_to[1] == Vector2i(20, 19) and friendly.moving_to[2] == Vector2i(22, 19)
			and friendly.blocks_cell(Vector2i(20, 20)) and friendly.blocks_cell(Vector2i(22, 20))
			and friendly.blocks_cell(Vector2i(20, 19)) and friendly.blocks_cell(Vector2i(22, 19)),
			"One deterministic push per loser retains source and destination reservations: %s" %
			str({"kind": kind, "moving1": friendly.moving_to[1], "moving2": friendly.moving_to[2],
				"block20": friendly.blocks_cell(Vector2i(20, 20)),
				"block22": friendly.blocks_cell(Vector2i(22, 20)),
				"block19": friendly.blocks_cell(Vector2i(19, 20)),
				"block23": friendly.blocks_cell(Vector2i(23, 20)),
				"owners": friendly._cell_owners, "reservations": friendly._reserved_cells})) and ok
	var state := [friendly.combat_units[1].hp, friendly.combat_units[1].stun, friendly.combat_units[1].ko,
		friendly.combat_units[2].hp, friendly.combat_units[2].stun,
		friendly.team_fatigue.fatigue, friendly.team_fatigue.count, enemy.team_fatigue.fatigue,
		friendly.moving_to[1], friendly.moving_to[2], friendly.combat_units[2].exchange_stagger, fixture.deaths]
	_dispose_mixed(fixture)
	return {"ok": ok, "pairs": pairs, "state": state}

func _check_mixed_death_and_ko() -> bool:
	for kind: String in ["death", "ko"]:
		var reference := _mixed_death_round(kind, true, false)
		if not bool(reference.ok): return false
		for mode: Array in [[true, true], [false, false], [false, true]]:
			var other := _mixed_death_round(kind, bool(mode[0]), bool(mode[1]))
			if not bool(other.ok) or not _require(other.pairs == reference.pairs and other.state == reference.state,
				"Mixed Army %s changed with owner order or batch query" % kind): return false
	var committed := _mixed_death_round("committed", true, false)
	if not bool(committed.ok): return false
	for mode: Array in [[true, true], [false, false], [false, true]]:
		var other := _mixed_death_round("committed", bool(mode[0]), bool(mode[1]))
		if not bool(other.ok) or not _require(other.pairs == committed.pairs and other.state == committed.state,
			"Committed Army step changed with owner order or batch query"): return false
	return true

func _check_mixed_skills() -> bool:
	var fixture := _mixed_army_fixture("skill")
	var lab: TerrainLab = fixture.lab
	var actor: TerrainTestCharacter = fixture.actor
	var friendly: TerrainArmy = fixture.friendly
	var enemy: TerrainArmy = fixture.enemy
	assert(not enemy.command_abilities.has(2))
	var ordinary_rejected := not enemy.activate_exchange_skill(2, "power")
	var captain_queued := enemy.activate_exchange_skill(0, "brace")
	var player_queued := actor.activate_exchange_skill("power")
	var ok := _require(ordinary_rejected and captain_queued and player_queued,
		"An ordinary member cannot queue a skill; the real player and formal captain can: %s" %
		str({"ordinary_rejected": ordinary_rejected, "captain_queued": captain_queued,
			"player_queued": player_queued, "enemy_abilities": enemy.command_abilities,
			"enemy_commander": enemy.current_commander, "controlled": lab.controlled_person_id()}))
	if not ok:
		_dispose_mixed(fixture)
		return false
	var skill_score := SiteCombatRules.exchange_score(actor.exchange_stats())
	var skill_stun := SiteCombatRules.exchange_stun(str(actor.exchange_stats().weapon)) + SiteCombatRules.EXCHANGE_POWER_STUN
	lab._resolve_exchanges()
	var pairs := _mixed_pair_results(fixture.events)
	ok = _require(lab.exchange_count == 4 and pairs.size() == 4
		and actor._exchange_pending_skill.is_empty() and actor.exchange_skill_cooldown == SiteCombatRules.EXCHANGE_SKILL_COOLDOWN
		and actor._received_effective_hit == 0 and actor.hp == 100.0,
		"Player power must cover four edges while being consumed once") and ok
	for event: Dictionary in fixture.events:
		var result: Dictionary = event.result
		var winner_id := int(event.a) if int(result.winner) == 1 else int(event.b)
		var actor_score := float(result.score_a) if int(event.a) == actor.person_id else float(result.score_b)
		ok = _require(winner_id == actor.person_id and str(result.kind) == "big"
			and is_equal_approx(actor_score, skill_score) and is_equal_approx(float(result.stun), skill_stun),
			"Every Army opponent must read the same queued player power before settlement") and ok
	ok = _require(is_equal_approx(float(friendly.team_fatigue.fatigue), 0.4)
		and friendly.team_fatigue.count == 5 and is_equal_approx(actor.fatigue, 0.4)
		and str(enemy.combat_units[0].get("exchange_skill", "")) == "brace"
		and float(enemy.combat_units[0].get("exchange_skill_cooldown", 0.0)) == 0.0,
		"Four costs share five members; an unengaged captain keeps its queued skill") and ok
	_dispose_mixed(fixture)
	return ok

func _check_army_captain_skill() -> bool:
	var fixture := _mixed_army_fixture("army_skill")
	var lab: TerrainLab = fixture.lab
	var friendly: TerrainArmy = fixture.friendly
	var enemy: TerrainArmy = fixture.enemy
	var captain_id := friendly.combat_identity(0)
	var queued := friendly.command_abilities.has(0) and not friendly.activate_exchange_skill(1, "power") \
		and friendly.activate_exchange_skill(0, "power")
	var skilled := friendly.exchange_stats(0)
	var plain := skilled.duplicate()
	plain.skill = ""
	var expected_score := SiteCombatRules.exchange_score(skilled)
	var expected_stun := SiteCombatRules.exchange_stun(str(skilled.weapon)) + SiteCombatRules.EXCHANGE_POWER_STUN
	lab._resolve_exchanges()
	var pairs := _mixed_pair_results(fixture.events)
	var ok := _require(queued and is_equal_approx(expected_score,
		SiteCombatRules.exchange_score(plain) + SiteCombatRules.EXCHANGE_SKILL_BONUS)
		and lab.exchange_count == 4 and pairs.size() == 4,
		"A legal Army captain must use one queued power against four adjacent enemies")
	for index in range(1, 5):
		var enemy_id := enemy.combat_identity(index)
		var key := "%d:%d" % [mini(captain_id, enemy_id), maxi(captain_id, enemy_id)]
		ok = _require(pairs.has(key) and int(enemy.combat_units[index].get("hit_revision", 0)) == 1,
			"Each captain-opponent edge must settle once") and ok
	for event: Dictionary in fixture.events:
		var result: Dictionary = event.result
		var winner := int(result.winner)
		var winner_id := 0 if winner == 0 else int(event.a) if winner == 1 else int(event.b)
		var captain_score := float(result.score_a) if int(event.a) == captain_id else float(result.score_b)
		ok = _require(winner_id == captain_id and is_equal_approx(captain_score, expected_score)
			and is_equal_approx(float(result.stun), expected_stun),
			"All four pairs must read the captain's pre-settlement power and impact") and ok
	ok = _require(str(friendly.combat_units[0].get("exchange_skill", "")).is_empty()
		and is_equal_approx(float(friendly.combat_units[0].get("exchange_skill_cooldown", 0.0)), SiteCombatRules.EXCHANGE_SKILL_COOLDOWN)
		and is_equal_approx(float(friendly.team_fatigue.fatigue), 0.4)
		and friendly.team_fatigue.count == 5 and int(friendly.combat_units[0].get("hit_revision", 0)) == 0,
		"Four wins must consume the captain's skill once and charge the five-person pool") and ok
	_dispose_mixed(fixture)
	var no_pair := _mixed_army_fixture("army_skill")
	var waiting: TerrainArmy = no_pair.friendly
	var waiting_lab: TerrainLab = no_pair.lab
	waiting.combat_units[0].exchange_cooldown = SiteCombatRules.EXCHANGE_ROUND_SECONDS
	var waiting_queued := waiting.activate_exchange_skill(0, "power")
	waiting_lab._resolve_exchanges()
	ok = _require(waiting_queued and waiting_lab.exchange_count == 0 and no_pair.events.is_empty()
		and str(waiting.combat_units[0].get("exchange_skill", "")) == "power"
		and float(waiting.combat_units[0].get("exchange_skill_cooldown", 0.0)) == 0.0
		and is_equal_approx(float(waiting.combat_units[0].exchange_cooldown), SiteCombatRules.EXCHANGE_ROUND_SECONDS)
		and float(waiting.team_fatigue.fatigue) == 0.0,
		"Adjacent enemies without a legal pair must not consume queued captain power") and ok
	_dispose_mixed(no_pair)
	return ok

func _mixed_competition_round(batch: bool, reverse_owners: bool) -> Dictionary:
	var fixture := _mixed_army_fixture("competition", batch, reverse_owners)
	var lab: TerrainLab = fixture.lab
	var actor: TerrainTestCharacter = fixture.actor
	var friendly: TerrainArmy = fixture.friendly
	var enemy: TerrainArmy = fixture.enemy
	var row_id := friendly.combat_identity(1)
	var enemy_ids := [enemy.combat_identity(1), enemy.combat_identity(2)]
	lab._resolve_exchanges()
	var pairs := _mixed_pair_results(fixture.events)
	var ok := _require(lab.exchange_count == 2 and pairs.size() == 2
		and actor.is_moving() and actor.terrain_cell == Vector2i(21, 20)
		and actor.movement_from_cell == Vector2i(20, 20) and actor.occupies_cell(Vector2i(21, 20))
		and friendly.cells[1] == Vector2i(22, 20) and friendly.moving_to[1] == TerrainArmy.INVALID_CELL
		and not friendly.blocks_cell(Vector2i(21, 20)) and friendly.blocks_cell(Vector2i(22, 20)),
		"Actor and Army cannot both reserve the one retreat cell")
	for edge: Array in pairs.values():
		ok = _require(int(edge[0]) in enemy_ids and str(edge[1]) == "big", "Both mixed-owner losses must settle") and ok
	ok = _require(actor.hp < 100.0 and float(friendly.combat_units[1].hp) < 100.0
		and int(actor._received_effective_hit) == 1 and int(friendly.combat_units[1].hit_revision) == 1
		and is_equal_approx(float(friendly.team_fatigue.fatigue), 95.4)
		and friendly.team_fatigue.count == 5 and row_id != actor.person_id,
		"A rejected retreat still receives its full hit and pre-death shared cost") and ok
	var state := [actor.hp, actor.terrain_cell, actor.movement_from_cell, friendly.combat_units[1].hp,
		friendly.cells[1], friendly.moving_to[1], friendly.team_fatigue.fatigue, actor.exchange_stagger]
	_dispose_mixed(fixture)
	return {"ok": ok, "pairs": pairs, "state": state}

func _check_mixed_retreat_competition() -> bool:
	var reference := _mixed_competition_round(true, false)
	if not bool(reference.ok): return false
	for mode: Array in [[true, true], [false, false], [false, true]]:
		var other := _mixed_competition_round(bool(mode[0]), bool(mode[1]))
		if not bool(other.ok) or not _require(other.pairs == reference.pairs and other.state == reference.state,
			"Competing Actor/Army retreat changed with owner order or batch query"): return false
	return true

func _mixed_dying_blocker_round(batch: bool, reverse_owners: bool) -> Dictionary:
	var fixture := _mixed_army_fixture("dying_blocker", batch, reverse_owners)
	var lab: TerrainLab = fixture.lab
	var actor: TerrainTestCharacter = fixture.actor
	var friendly: TerrainArmy = fixture.friendly
	var enemy: TerrainArmy = fixture.enemy
	var row_id := friendly.combat_identity(1)
	var enemy_ids := [enemy.combat_identity(1), enemy.combat_identity(2)]
	lab._resolve_exchanges()
	var pairs := _mixed_pair_results(fixture.events)
	var ok := _require(lab.exchange_count == 2 and pairs.size() == 2
		and actor.terrain_cell == Vector2i(20, 20) and not actor.is_moving()
		and not friendly.blocks_cell(Vector2i(19, 20))
		and float(friendly.combat_units[1].hp) == 0.0 and fixture.deaths == [row_id],
		"A blocker dying in contact cannot release its cell early for the same-round push")
	for edge: Array in pairs.values():
		ok = _require(int(edge[0]) in enemy_ids and str(edge[1]) == "big", "Both contacts must settle despite blocked pushes") and ok
	ok = _require(actor.hp < 100.0 and actor._received_effective_hit == 1
		and is_equal_approx(float(friendly.team_fatigue.fatigue), 95.4)
		and friendly.team_fatigue.count == 4,
		"Blocked push and death retain both hits and the original five-person cost divisor") and ok
	var state := [actor.hp, actor.terrain_cell, actor.is_moving(), friendly.combat_units[1].hp,
		friendly.team_fatigue.fatigue, friendly.team_fatigue.count, fixture.deaths]
	_dispose_mixed(fixture)
	return {"ok": ok, "pairs": pairs, "state": state}

func _check_dying_retreat_blocker() -> bool:
	var reference := _mixed_dying_blocker_round(true, false)
	if not bool(reference.ok): return false
	for mode: Array in [[true, true], [false, false], [false, true]]:
		var other := _mixed_dying_blocker_round(bool(mode[0]), bool(mode[1]))
		if not bool(other.ok) or not _require(other.pairs == reference.pairs and other.state == reference.state,
			"A same-round dying blocker changed with owner order or batch query"): return false
	return true

func run() -> void:
	var cases: Array[Dictionary] = [
		{"name": "all win 1v2", "abilities": [0.0, 0.0], "winners": [1, 1],
			"center_hp": 100.0, "center_stun": 0.0, "center_fatigue": 1.0,
			"enemy_hp": [98.0, 98.0], "enemy_stun": [12.0, 12.0], "enemy_fatigue": [1.0, 1.0],
			"hit_notifications": 0, "status": "Exchange win", "animation": "attack_jump_heavy"},
		{"name": "third faction 1v2", "abilities": [0.0, 0.0], "factions": [1, 2], "winners": [1, 1],
			"center_hp": 100.0, "center_stun": 0.0, "center_fatigue": 1.0,
			"enemy_hp": [98.0, 98.0], "enemy_stun": [12.0, 12.0], "enemy_fatigue": [1.0, 1.0],
			"hit_notifications": 0, "status": "Exchange win", "animation": "attack_jump_heavy"},
		{"name": "all win 1v3", "abilities": [0.0, 0.0, 0.0], "winners": [1, 1, 1],
			"center_hp": 100.0, "center_stun": 0.0, "center_fatigue": 1.5,
			"enemy_hp": [98.0, 98.0, 98.0], "enemy_stun": [12.0, 12.0, 12.0], "enemy_fatigue": [1.0, 1.0, 1.0],
			"hit_notifications": 0, "status": "Exchange win", "animation": "attack_jump_heavy"},
		{"name": "all win 1v4", "abilities": [0.0, 0.0, 0.0, 0.0], "winners": [1, 1, 1, 1],
			"center_hp": 100.0, "center_stun": 0.0, "center_fatigue": 2.0,
			"enemy_hp": [98.0, 98.0, 98.0, 98.0], "enemy_stun": [12.0, 12.0, 12.0, 12.0], "enemy_fatigue": [1.0, 1.0, 1.0, 1.0],
			"hit_notifications": 0, "status": "Exchange win", "animation": "attack_jump_heavy"},
		{"name": "all win 1v4 fallback", "abilities": [0.0, 0.0, 0.0, 0.0], "batch": false,
			"winners": [1, 1, 1, 1], "center_hp": 100.0, "center_stun": 0.0, "center_fatigue": 2.0,
			"enemy_hp": [98.0, 98.0, 98.0, 98.0], "enemy_stun": [12.0, 12.0, 12.0, 12.0], "enemy_fatigue": [1.0, 1.0, 1.0, 1.0],
			"hit_notifications": 0, "status": "Exchange win", "animation": "attack_jump_heavy"},
		{"name": "one win one loss", "abilities": [35.0, 70.0], "winners": [1, 3],
			"center_hp": 99.0, "center_stun": 12.0, "center_fatigue": 1.0,
			"enemy_hp": [99.0, 100.0], "enemy_stun": [12.0, 0.0], "enemy_fatigue": [0.5, 0.5],
			"hit_notifications": 1, "status": "Exchange loss", "animation": "hit"},
		{"name": "two wins one loss", "abilities": [35.0, 70.0, 35.0], "winners": [1, 3, 1],
			"center_hp": 99.0, "center_stun": 12.0, "center_fatigue": 1.5,
			"enemy_hp": [99.0, 100.0, 99.0], "enemy_stun": [12.0, 0.0, 12.0], "enemy_fatigue": [0.5, 0.5, 0.5],
			"hit_notifications": 1, "status": "Exchange loss", "animation": "hit"},
		{"name": "one win three losses", "abilities": [35.0, 70.0, 70.0, 70.0], "winners": [1, 3, 4, 5],
			"center_hp": 97.0, "center_stun": 36.0, "center_fatigue": 2.0,
			"enemy_hp": [99.0, 100.0, 100.0, 100.0], "enemy_stun": [12.0, 0.0, 0.0, 0.0],
			"enemy_fatigue": [0.5, 0.5, 0.5, 0.5], "hit_notifications": 1,
			"status": "Exchange loss", "animation": "hit"},
		{"name": "occupied retreat in same round", "abilities": [100.0, 0.0, 0.0],
			"winners": [2, 1, 1], "center_hp": 98.0, "center_stun": 12.0,
			"center_fatigue": 2.0, "enemy_hp": [100.0, 98.0, 98.0],
			"enemy_stun": [0.0, 12.0, 12.0], "enemy_fatigue": [0.5, 1.0, 1.0],
			"hit_notifications": 1, "status": "Exchange loss", "animation": "knockback",
			"center_cell": Vector2i(5, 5), "no_overlap": true},
		{"name": "fully occupied ring 1v4", "abilities": [100.0, 0.0, 0.0, 0.0],
			"winners": [2, 1, 1, 1], "center_hp": 98.0, "center_stun": 12.0,
			"center_fatigue": 2.5, "enemy_hp": [100.0, 98.0, 98.0, 98.0],
			"enemy_stun": [0.0, 12.0, 12.0, 12.0], "enemy_fatigue": [0.5, 1.0, 1.0, 1.0],
			"hit_notifications": 1, "status": "Exchange loss", "animation": "knockback",
			"center_cell": Vector2i(5, 5), "no_overlap": true},
		{"name": "one win one draw", "abilities": [35.0, 50.0], "winners": [1, 0],
			"center_hp": 100.0, "center_stun": 12.0, "center_fatigue": 0.5,
			"enemy_hp": [99.0, 100.0], "enemy_stun": [12.0, 12.0], "enemy_fatigue": [0.5, 0.0],
			"hit_notifications": 1, "status": "Exchange hit: draw", "animation": "hit"},
		{"name": "two draws", "abilities": [50.0, 50.0], "winners": [0, 0],
			"center_hp": 100.0, "center_stun": 24.0, "center_fatigue": 0.0,
			"enemy_hp": [100.0, 100.0], "enemy_stun": [12.0, 12.0], "enemy_fatigue": [0.0, 0.0],
			"hit_notifications": 1, "status": "Exchange hit: draw", "animation": "hit"},
		{"name": "single draw", "abilities": [50.0], "winners": [0],
			"center_hp": 100.0, "center_stun": 12.0, "center_fatigue": 0.0,
			"enemy_hp": [100.0], "enemy_stun": [12.0], "enemy_fatigue": [0.0],
			"hit_notifications": 1, "status": "Exchange draw", "animation": "guard"},
		{"name": "KO cannot cancel other pair", "abilities": [35.0, 70.0], "winners": [1, 3],
			"initial_stun": 95.0, "center_hp": 99.0, "center_stun": 107.0, "center_fatigue": 1.0,
			"enemy_hp": [99.0, 100.0], "enemy_stun": [12.0, 0.0], "enemy_fatigue": [0.5, 0.5],
			"hit_notifications": 1, "status": "Unconscious", "animation": "down", "knockout": true},
		{"name": "death cannot cancel other pair", "abilities": [35.0, 70.0], "winners": [1, 3],
			"initial_hp": 1.0, "center_hp": 0.0, "center_stun": 12.0, "center_fatigue": 1.0,
			"enemy_hp": [99.0, 100.0], "enemy_stun": [12.0, 0.0], "enemy_fatigue": [0.5, 0.5],
			"hit_notifications": 1, "status": "Dead", "animation": "down", "knockout": false},
	]
	for spec: Dictionary in cases:
		if not _check_case(spec):
			quit(1)
			return
	if not _check_cooldown():
		quit(1)
		return
	if not _check_graph_and_ids():
		quit(1)
		return
	if not _check_existing_fatigue_on_draw() or not _check_two_big_losses_one_reaction() or not _check_actor_committed_step() \
			or not _check_mixed_death_and_ko() or not _check_mixed_skills() or not _check_army_captain_skill() or not _check_mixed_retreat_competition() \
			or not _check_dying_retreat_blocker():
		quit(1)
		return
	print("SITE_ENCIRCLEMENT_SIMULTANEOUS_EXCHANGE_PASS %d actor cases, graph/64-bit ID, real Army/Actor shared-pool death and KO, committed step, skill and retreat competition parity" % cases.size())
	quit(0)
