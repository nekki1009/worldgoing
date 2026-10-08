extends SceneTree
## Real person damage/fatigue callbacks with formula interval metadata.
## Does not certify cold Site admission, calibration, political or GPU results.
const Battle = preload("res://scripts/region_lab/region_gameplay_battle.gd")
const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
var checks := 0
var _teams: Array[TerrainArmy] = []
var _labs: Array[TerrainLab] = []
var _players: Array[TerrainTestCharacter] = []
var _damage_calls: Dictionary = {}
var _fail_fatigue_once := false

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func _fixture(actual_contacts: bool = false) -> Dictionary:
	var data := Helper.build_flat_map(24, 24)
	data.site.id = "battle-test-site"
	if actual_contacts:
		data.height_levels[data.index(Vector2i(6, 6))] = 2 # A real cliff excludes this soldier's contact.
	var lab := TerrainLab.new()
	lab.terrain = data
	_labs.append(lab)
	var player := TerrainTestCharacter.new()
	player.data = data
	player.person_id = 1
	player.faction_id = 1
	player.terrain_cell = Vector2i(2, 2)
	lab.character = player
	lab.combat_actors.append(player)
	data.site.controlled_person_id = 1
	_players.append(player)
	var groups: Array[Array] = []
	for side: int in range(2):
		var team := TerrainArmy.new()
		team.team_id = side + 1
		team.faction_id = side + 1
		team.roster_size = 2
		team.exchange_enabled = actual_contacts
		var x := 5 + side * (1 if actual_contacts else 2)
		_check(team.deploy_at(data, null, null, [Vector2i(x, 5), Vector2i(x, 6)]), "Original battle deploy")
		_check(team.enable_combat(false), "Original battle combat")
		team.needs_attack_order = true
		lab.combat_armies.append(team)
		_teams.append(team)
		var ids: Array = []
		for index: int in team.combat_units.size(): ids.append(team.combat_identity(index))
		groups.append(ids)
	var created := Battle.create({"id": "battle-1", "site_id": str(data.site.id), "attackers": groups[0],
		"defenders": groups[1], "game_time": 0.0, "loss_coefficient": 1.0 / 600.0})
	_check(bool(created.ok), "Battle metadata created")
	return {"data": data, "battle": created.battle, "lab": lab}

func _dispose() -> void:
	for team: TerrainArmy in _teams: team.free()
	_teams.clear()
	for lab: TerrainLab in _labs: lab.free()
	_labs.clear()
	for player: TerrainTestCharacter in _players: player.free()
	_players.clear()
	_damage_calls.clear()
	TerrainArmy.release_contact_source()

func _people() -> Dictionary:
	var result := {}
	for team: TerrainArmy in _teams:
		for index: int in team.combat_units.size():
			var id := team.combat_identity(index)
			result[id] = {"id": id, "hp": float(team.combat_hot_get(index, &"hp")), "stun": float(team.combat_hot_get(index, &"stun")),
				"ready": team.combat_can_act(index), "eligible": true, "ability": 50.0, "training": 0.0,
				"morale": 100.0, "fatigue": PersonFatigue.read(team.combat_units[index]),
				"weapon": "weapon_sword_wood", "armor": "none", "rank": 2 if index == team.current_commander else 0}
	return result

func _interval(start: float, end: float, id: String, revision: int = 0) -> Dictionary:
	return {"game_start": start, "game_end": end, "action_start": start, "action_end": end,
		"tactical_action": end - start, "time_scale": 1.0, "permit_id": id, "journal_revision": revision}

func _damage(effect: Dictionary) -> Dictionary:
	var id := int(effect.person_id)
	for team: TerrainArmy in _teams:
		var index := team.index_for_identity(id)
		if index < 0: continue
		team.apply_unit_contact(index, {"result": {"hp": float(effect.hp), "stun": float(effect.stun), "guard_break": false}, "shield": false})
		_damage_calls[str(effect.id)] = int(_damage_calls.get(str(effect.id), 0)) + 1
		return {"ok": true, "owner": "TerrainArmy.apply_unit_contact"}
	return {"ok": false, "code": "NO_PERSON"}

func _fatigue(effect: Dictionary) -> Dictionary:
	if _fail_fatigue_once:
		_fail_fatigue_once = false
		return {"ok": false, "code": "INJECTED_OWNER_FAILURE"}
	for team: TerrainArmy in _teams:
		var index := team.index_for_identity(int(effect.person_id))
		if index < 0: continue
		PersonFatigue.charge(team.combat_units[index], float(effect.amount))
		return {"ok": true, "owner": "PersonFatigue.charge"}
	return {"ok": false, "code": "NO_PERSON"}

func _callbacks() -> Dictionary:
	return {"damage": _damage, "fatigue": _fatigue, "order": func(_effect: Dictionary) -> Dictionary: return {"ok": true}}

func _state() -> Array:
	var values: Array = []
	for team: TerrainArmy in _teams:
		for index: int in team.combat_units.size():
			values.append([float(team.combat_hot_get(index, &"hp")), float(team.combat_hot_get(index, &"stun")), PersonFatigue.read(team.combat_units[index])])
	return values

func _actual_owner_adapter() -> void:
	var fixture := _fixture(true)
	var battle: Dictionary = fixture.battle
	var lab: TerrainLab = fixture.lab
	var resolved := Battle.resolve_people(lab, battle)
	_check(bool(resolved.ok), "True original GD contact adapter resolves people")
	var attacker_commander := int(battle.attackers[0])
	var attacker_soldier := int(battle.attackers[1])
	var defender_commander := int(battle.defenders[0])
	var defender_soldier := int(battle.defenders[1])
	_check(bool(resolved.people[attacker_commander].eligible) and bool(resolved.people[defender_commander].eligible),
		"Exposed original commanders retain legal melee contact")
	_check(not bool(resolved.people[attacker_soldier].eligible) and not bool(resolved.people[defender_soldier].eligible),
		"Real terrain cliff excludes low-rank soldiers from physical contact")
	var prepared := Battle.prepare_interval(battle, _interval(0.0, 1.0, "actual-contact"), resolved.people)
	_check(bool(prepared.ok) and not prepared.effects.is_empty(), "True original contacts produce accepted formula effects")
	var actual_damage := 0
	for effect: Dictionary in prepared.effects:
		if str(effect.kind) != "damage": continue
		actual_damage += 1
		_check(int(effect.person_id) in [attacker_commander, defender_commander], "Physical hit remains on original exposed commander")
	_check(actual_damage == 2, "Each real opposing original contact produces one accepted damage effect")
	var before := _state()
	var applied := Battle.apply_pending(battle, prepared, Battle.owner_callbacks(lab, battle))
	_check(bool(applied.ok), "True original apply_unit_contact and PersonFatigue callbacks consume accepted effects")
	var after := _state()
	_check(float(after[0][0]) < float(before[0][0]) and float(after[2][0]) < float(before[2][0]), "Original commander HP changes through contact entry")
	_check(float(after[1][0]) == float(before[1][0]) and float(after[3][0]) == float(before[3][0]), "Unexposed original soldiers absorb no commander damage")
	_check(lab.controlled_person_id() == 1 and float(lab.character.hp) == 100.0, "Real player control and body remain outside NPC battle")
	_dispose()

func _run() -> void:
	var fixture := _fixture()
	var battle: Dictionary = fixture.battle
	var prepared := Battle.prepare_interval(battle, _interval(0.0, 180.0, "whole"), _people())
	_check(bool(prepared.ok), "Whole interval accepted")
	_check(bool(Battle.apply_pending(battle, prepared, _callbacks()).ok), "Original owner callback commits")
	var whole := _state()
	_check(float(battle.completed_game_time) == 180.0, "Exactly accepted game endpoint")
	_dispose()

	fixture = _fixture()
	battle = fixture.battle
	for bounds: Array in [[0.0, 60.0, "part-1"], [60.0, 180.0, "part-2"]]:
		prepared = Battle.prepare_interval(battle, _interval(float(bounds[0]), float(bounds[1]), str(bounds[2])), _people())
		_check(bool(prepared.ok), "Partial interval accepted")
		_check(bool(Battle.apply_pending(battle, prepared, _callbacks()).ok), "Partial original owner commit")
	var split := _state()
	for index: int in whole.size():
		for field: int in range(3): _check(is_equal_approx(float(whole[index][field]), float(split[index][field])), "Partition preserves original HP/stun/fatigue")
	_dispose()

	fixture = _fixture()
	battle = fixture.battle
	var barrier_interval := _interval(0.0, 30.0, "player-endpoint")
	barrier_interval.player_barrier = true
	prepared = Battle.prepare_interval(battle, barrier_interval, _people())
	_check(bool(prepared.ok) and not prepared.effects.is_empty(), "Arrival endpoint integrates to pending effects")
	var before := _state()
	_check(str(Battle.apply_pending(battle, prepared, _callbacks()).code) == "PLAYER_BARRIER" and _state() == before, "Player priority blocks endpoint owner effects")
	prepared.interval.player_barrier = false
	_check(bool(Battle.apply_pending(battle, prepared, _callbacks()).ok), "Bound live consumer may consume same pending effects without a fake delta")
	var bad_clock := _interval(30.0, 60.0, "bad-scale")
	bad_clock.time_scale = 2.0
	_check(str(Battle.prepare_interval(battle, bad_clock, _people()).code) == "CLOCK_CONTRACT", "Double scale rejected")
	var old_clock := _interval(0.0, 30.0, "old")
	_check(str(Battle.prepare_interval(battle, old_clock, _people()).code) == "NONCONTIGUOUS_INTERVAL", "Old interval cannot replay")
	_dispose()

	fixture = _fixture()
	battle = fixture.battle
	prepared = Battle.prepare_interval(battle, _interval(0.0, 30.0, "retry"), _people())
	_fail_fatigue_once = true
	var failed := Battle.apply_pending(battle, prepared, _callbacks())
	_check(str(failed.code) == "INJECTED_OWNER_FAILURE", "Owner fault preserved")
	_check(bool(Battle.apply_pending(battle, prepared, _callbacks()).ok), "Owner fault resumes same candidate")
	for count: Variant in _damage_calls.values(): _check(int(count) == 1, "Original damage effect committed once after retry")
	_check(int(battle.revision) == 1, "One interval acceptance despite retry")
	_dispose()

	fixture = _fixture()
	battle = fixture.battle
	var people := _people()
	var attacker_soldier: int = int(battle.attackers[1])
	people[attacker_soldier].eligible = false # Original solid-wall/deployment resolver excludes him.
	prepared = Battle.prepare_interval(battle, _interval(0.0, 1.0, "legal-pool"), people)
	var commander_hit := false
	var soldier_hit := false
	for effect: Dictionary in prepared.effects:
		if str(effect.kind) != "damage": continue
		commander_hit = commander_hit or int(effect.person_id) == int(battle.attackers[0])
		soldier_hit = soldier_hit or int(effect.person_id) == attacker_soldier
	_check(commander_hit and not soldier_hit, "Unexposed soldier cannot absorb exposed commander's original hit")
	_dispose()
	_actual_owner_adapter()
	print("REGION_GAMEPLAY_BATTLE_PASS checks=", checks, " scope=accepted_intervals_original_damage_fatigue_partition_player_barrier_callback_retry_legal_rank_pool")
	quit(0)
