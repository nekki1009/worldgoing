extends SceneTree
## Deterministic small-roster contracts through the original Lab/Army/Grid owners.
## This fixture does not claim formal-scene visual or 5,000-person acceptance.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const TacticalAI = preload("res://scripts/terrain_lab/site_army_ai.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const ALLIED_STORE_SITE := "tactical-ai-allied-third-resume"
const STEP := 1.0 / 30.0
const DEADLINE_SECONDS := 120.0
var _started := 0
var _folder := ""
var _checks := 0
var _failures: Array[String] = []
var _cases: Array[Dictionary] = []
var _current_case := "setup"

func _initialize() -> void:
	_started = Time.get_ticks_usec()
	_folder = "res://output/three_faction_ai_20260928/behavior/run_%d_%d" % [int(Time.get_unix_time_from_system()), _started]
	DirAccess.make_dir_recursive_absolute(_folder)
	create_timer(DEADLINE_SECONDS).timeout.connect(func() -> void:
		_check(false, "Execution deadline reached")
		_finish())
	_run.call_deferred()

func _check(value: bool, message: String) -> bool:
	_checks += 1
	if not value:
		var detail := "%s: %s" % [_current_case, message]
		_failures.append(detail)
		push_error(detail)
	return value

func _within_deadline() -> bool:
	if (Time.get_ticks_usec() - _started) / 1000000.0 < DEADLINE_SECONDS:
		return true
	_check(false, "Execution deadline reached")
	return false

func _fixture(counts: Array[int], origins: Array[Vector2i], placements: Dictionary = {}, map_size: Vector2i = Vector2i(64, 64), troops: Dictionary = {}, supplied_map: TerrainData = null) -> Dictionary:
	var data := supplied_map if supplied_map != null else Helper.build_flat_map(map_size.x, map_size.y)
	var lab := TerrainLab.new()
	lab.terrain = data
	lab.exchange_enabled = true
	var coordinator := Coordinator.new()
	lab.combat_movement_coordinator = coordinator
	var supply := SiteController.new()
	supply.lab = lab
	data.site["team_supply"] = {}
	var teams: Array[TerrainArmy] = []
	for faction in range(3):
		var team := TerrainArmy.new()
		# Like TerrainLab's dynamic team slots (_ensure_army_slots), the captain uses the
		# shared pooled geometry instead of a private live presenter SubViewport per army.
		team.defer_captain_presenter = true
		# Production armies live in the scene tree; the set_process(false) below then sticks.
		root.add_child(team)
		team.team_id = faction + 1
		team.faction_id = faction
		team.roster_size = counts[faction]
		team.exchange_enabled = true
		team.set_process(false)
		var positions: Array[Vector2i] = []
		if placements.has(faction):
			positions.assign(placements[faction])
		else:
			for index in range(counts[faction]):
				positions.append(origins[faction] + Vector2i(index % 2, floori(float(index) / 2.0)))
		_check(team.deploy_at(data, null, null, positions), "Fixture deployment")
		_check(team.enable_combat(false, 0, StringName(troops.get(faction, TerrainArmy.TROOP_TYPE_ID))), "Fixture combat initialization")
		coordinator.register_formation(team)
		teams.append(team)
		lab.combat_armies.append(team)
		team.enemy_query = lab._nearest_unit_enemy
		team.target_query = lab._army_target
		team.combat_target_query = lab._combat_target
		team.exchange_people_query = lab._exchange_people.bind(false)
		team.ranged_tactics_query = lab._ranged_tactics
		team.sustain_routed_query = supply.team_is_routed
		if supplied_map == null:
			var members := {}
			var identities: Array[int] = []
			for index in range(counts[faction]):
				var identity := team.combat_identity(index)
				members[identity] = team.combat_units[index]
				identities.append(identity)
			var sustain := SiteSustain.create()
			_check(bool(SiteSustain.add_members(sustain, members, identities).ok), "Original sustain cohorts")
			data.site.team_supply[str(team.team_id)] = {"sustain": sustain}
		_check(bool(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.HOLD).ok), "Initial HOLD")
	for team: TerrainArmy in teams:
		team.external_blocker = lab._armies_block_cell.bind(team)
	if supplied_map != null:
		# Store scenarios need the complete original opt-in feeding transaction,
		# including inventory and life checkpoints, not just decision-test cohorts.
		supply.captivity_supply.init(supply)
		for team: TerrainArmy in teams:
			_check(bool(supply.captivity_supply.enable_team(team).ok), "Original complete supply owner for save/resume")
	return {"data": data, "lab": lab, "coordinator": coordinator, "teams": teams, "supply": supply}

func _dispose(f: Dictionary) -> void:
	for team: TerrainArmy in f.teams:
		team.external_blocker = Callable()
		team.enemy_query = Callable()
		team.target_query = Callable()
		team.combat_target_query = Callable()
		team.exchange_people_query = Callable()
		team.ranged_tactics_query = Callable()
		team.sustain_routed_query = Callable()
		team.controlled_person_query = Callable()
		team.equipment_appearance_query = Callable()
		f.coordinator.unregister_formation(team)
		team.free()
	f.lab.combat_armies.clear()
	for actor: TerrainTestCharacter in f.lab.combat_actors:
		actor.cell_blocker = Callable()
		actor.free()
	f.lab.combat_actors.clear()
	f.supply.free()
	f.lab.free()

func _enable(team: TerrainArmy) -> void:
	_check(bool(team.set_tactical_ai_enabled(team.current_commander, true).get("ok", false)), "Enable AI through current commander")

func _decide(f: Dictionary, seconds: float = 0.51) -> void:
	f.lab._advance_tactical_ai(seconds)

# Nekki 2026-10-13 (retreat rule, option 3): with intact morale the tactical AI may
# withdraw in good order to a destination (SiteArmyAI._withdraw). It must never rout.
func _orderly_withdrawal(team: TerrainArmy) -> bool:
	return team.combat_order in [TerrainArmy.CombatOrder.HOLD, TerrainArmy.CombatOrder.RETREAT] and not team.is_sustain_routed() \
		and str(team._retreat_resolution.get("reason", "")) != "morale_collapse"

# An accepted withdrawal finishes before the AI reviews again (arrival returns HOLD).
func _finish_withdrawal(f: Dictionary, team: TerrainArmy) -> void:
	for window in range(40):
		if team.combat_order != TerrainArmy.CombatOrder.RETREAT or not _within_deadline(): return
		_advance(f, 0.5)

func _no_overlap(f: Dictionary) -> bool:
	var occupied := {}
	var reserved := {}
	for team: TerrainArmy in f.teams:
		for index in range(team.cells.size()):
			var identity := team.combat_identity(index)
			var cell: Vector2i = team.cells[index]
			var target: Vector2i = team.moving_to[index]
			var claims_cell := int(team._cell_owners.get(cell, -1)) == index
			# Original knockouts release occupancy after their committed step lands.
			# Their resting cell remains on the original body and may be walked over.
			if claims_cell:
				if occupied.has(cell) and int(occupied[cell]) != identity:
					return _check(false, "Actual occupied cells overlap at %s (person %d)" % [cell, identity])
				occupied[cell] = identity
			elif team.combat_can_act(index) or target != TerrainArmy.INVALID_CELL:
				return _check(false, "Standing or committed member %d lost its source occupancy" % identity)
			elif not team.member_gone(index) and float(team.combat_hot_get(index, &"ko", 0.0)) <= 0.0:
				return _check(false, "Non-knocked-out member %d lost its source occupancy" % identity)
			if target != TerrainArmy.INVALID_CELL:
				if not f.data.can_step(cell, target):
					return _check(false, "A committed step crossed illegal geometry")
				if reserved.has(target) and int(reserved[target]) != identity:
					return _check(false, "Two members reserved the same destination")
				reserved[target] = identity
	return true

func _advance(f: Dictionary, seconds: float) -> void:
	for tick in range(ceili(seconds / STEP)):
		if not _within_deadline():
			return
		f.lab._advance_combat(STEP)
		if not _no_overlap(f):
			return

func _nearest_gap(team: TerrainArmy, enemy: TerrainArmy) -> float:
	var closest := INF
	for cell: Vector2i in team.cells:
		for other: Vector2i in enemy.cells:
			closest = minf(closest, cell.distance_to(other))
	return closest

func _record(f: Dictionary, extra: Dictionary = {}) -> void:
	var rows: Array[Dictionary] = []
	for team: TerrainArmy in f.teams:
		var bodies: Array[Dictionary] = []
		for index in range(team.cells.size()):
			bodies.append({"id": team.combat_identity(index), "hp": team.combat_hot_get(index, &"hp", 0.0),
				"ko": team.combat_hot_get(index, &"ko", 0.0), "pose": team.combat_hot_get(index, &"pose", ""),
				"member": team.is_member(index), "owns_cell": int(team._cell_owners.get(team.cells[index], -1)) == index})
		rows.append({"faction": team.faction_id, "order": team.combat_order,
			"target_id": team.tactical_ai_target_id, "decisions": team.tactical_ai_decisions,
			"orders": team.tactical_ai_orders, "enabled": team.tactical_ai_enabled,
			"recovering": team.tactical_ai_recovering, "cells": str(team.cells),
			"accepted_steps": team.accepted_count, "bodies": bodies})
	var result := {"case": _current_case, "teams": rows, "exchanges": f.lab.exchange_count}
	result.merge(extra)
	_cases.append(result)
	_write_report()

func _rotation_matrix() -> void:
	for subject in range(3):
		for mode in ["far_approach", "adjacent_attack", "outnumbered_hold"]:
			_current_case = "faction_%d_%s" % [subject, mode]
			var counts: Array[int] = [1, 1, 1]
			var origins: Array[Vector2i] = [Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO]
			var enemy_index := (subject + 1) % 3
			var third_index := (subject + 2) % 3
			counts[subject] = 1 if mode == "outnumbered_hold" else 8
			counts[enemy_index] = 8 if mode == "outnumbered_hold" else 1
			origins[subject] = Vector2i(24, 24)
			origins[enemy_index] = Vector2i(45, 24) if mode == "far_approach" else (Vector2i(29, 24) if mode == "outnumbered_hold" else Vector2i(26, 24))
			origins[third_index] = Vector2i(42, 45)
			var f := _fixture(counts, origins)
			var team: TerrainArmy = f.teams[subject]
			var enemy: TerrainArmy = f.teams[enemy_index]
			var initial_cells := team.cells.duplicate()
			var initial_gap := _nearest_gap(team, enemy)
			_enable(team)
			_decide(f)
			var expected := TerrainArmy.CombatOrder.MOVE
			if mode == "adjacent_attack": expected = TerrainArmy.CombatOrder.ATTACK
			# Nekki 2026-10-13 (retreat rule, option 3): with intact morale tactical AI may
			# order an orderly destination RETREAT, so an outnumbered team withdraws.
			if mode == "outnumbered_hold": expected = TerrainArmy.CombatOrder.RETREAT
			_check(team.combat_order == expected, "Expected order %d, got %d" % [expected, team.combat_order])
			_check(enemy.index_for_identity(team.tactical_ai_target_id) >= 0, "Chosen enemy must be the nearest hostile group")
			var initial_orders := team.tactical_ai_orders
			for decision in range(6): _decide(f)
			_check(team.tactical_ai_orders == initial_orders, "Unchanged intent must not reissue the order every decision")
			_advance(f, 4.0)
			if mode == "adjacent_attack":
				_check(f.lab.exchange_count > 0, "Adjacent ATTACK must produce real exchanges")
			elif mode == "outnumbered_hold":
				# A one-person withdrawal may already have arrived (HOLD) within the 4 s.
				_check(team.combat_order in [TerrainArmy.CombatOrder.RETREAT, TerrainArmy.CombatOrder.HOLD] and not team.is_sustain_routed()
					and str(team._retreat_resolution.get("reason", "")) != "morale_collapse"
					and team.cells != initial_cells and _nearest_gap(team, enemy) > initial_gap,
					"Strength disadvantage without a sustain rout must withdraw in good order, not rout")
			else:
				_check(team.cells != initial_cells, "Decision must produce actual landed movement")
				_check(_nearest_gap(team, enemy) < initial_gap, "Physical distance must follow the issued approach")
			_record(f, {"initial_gap": initial_gap, "final_gap": _nearest_gap(team, enemy)})
			_dispose(f)

func _authority_pause_and_target() -> void:
	_current_case = "manual_authority_pause_and_retarget"
	var f := _fixture([8, 1, 1], [Vector2i(12, 12), Vector2i(26, 12), Vector2i(38, 12)])
	var team: TerrainArmy = f.teams[0]
	var first: TerrainArmy = f.teams[1]
	var last: TerrainArmy = f.teams[2]
	_enable(team)
	_decide(f)
	var order := team.combat_order
	var serial := team._current_order_serial
	var invalid: Dictionary = team.issue_combat_order(-99, TerrainArmy.CombatOrder.HOLD)
	_check(not bool(invalid.ok) and team.tactical_ai_enabled and team.combat_order == order and team._current_order_serial == serial,
		"Unauthorized manual order must preserve AI and the accepted command")
	invalid = team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(-1, -1))
	_check(not bool(invalid.ok) and team.tactical_ai_enabled and team.combat_order == order and team._current_order_serial == serial,
		"Failed MOVE preflight must preserve AI and the accepted command")
	var decision_count := team.tactical_ai_decisions
	var order_count := team.tactical_ai_orders
	var cells_before := team.cells.duplicate()
	f.data.site.paused = true
	_advance(f, 2.0)
	_check(team.tactical_ai_decisions == decision_count and team.tactical_ai_orders == order_count and team.cells == cells_before,
		"Paused Site must not advance AI decisions, commands or bodies")
	f.data.site.paused = false
	first.faction_id = team.faction_id
	_decide(f, 2.1)
	_check(last.index_for_identity(team.tactical_ai_target_id) >= 0, "Same faction must be excluded even when it is nearer")
	first.faction_id = 1
	last.combat_hot_set(0, &"hp", 0.0)
	_decide(f, 2.1)
	_check(first.index_for_identity(team.tactical_ai_target_id) >= 0, "Dead enemy must cause a valid remaining enemy to be selected")
	var manual: Dictionary = team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.HOLD)
	_check(bool(manual.ok) and not team.tactical_ai_enabled, "Accepted manual order must take over AI")
	_decide(f, 3.0)
	_check(team.combat_order == TerrainArmy.CombatOrder.HOLD, "Disabled AI must preserve manual HOLD")
	_record(f)
	_dispose(f)

func _non_morale_retreat_guards() -> void:
	for condition in ["low_hp", "few_ready", "saved_recovering"]:
		_current_case = "no_rout_from_" + condition
		var f := _fixture([8, 1, 1], [Vector2i(24, 24), Vector2i(28, 24), Vector2i(45, 45)])
		var team: TerrainArmy = f.teams[0]
		_enable(team)
		if condition == "low_hp":
			for index in range(team.combat_units.size()): team.combat_hot_set(index, &"hp", 20.0)
		elif condition == "few_ready":
			for index in range(3, team.combat_units.size()): team.combat_hot_set(index, &"ko", 10.0)
		else:
			team.tactical_ai_recovering = true
		var initial_cells := team.cells.duplicate()
		for decision in range(3): _decide(f)
		_check(team.tactical_ai_recovering and _orderly_withdrawal(team),
			"Non-morale condition may hold or withdraw in good order, never rout")
		_check(team.cells == initial_cells, "AI caution must not relocate original people")
		var before := team.capture_combat_state()
		# A captain RETREAT with a destination is an allowed orderly retreat (round 54,
		# site_tactical_ai_retreat_test); a goal-less one stays refused before a collapse.
		var refused := team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.RETREAT)
		_check(not bool(refused.ok) and team.capture_combat_state() == before,
			"Direct goal-less pre-collapse RETREAT must be rejected without changing the original army")
		_record(f)
		_dispose(f)

func _recovery_and_rout() -> void:
	_current_case = "fatigue_morale_recovery_and_routed_authority"
	var f := _fixture([8, 1, 1], [Vector2i(24, 24), Vector2i(30, 24), Vector2i(45, 45)])
	var team: TerrainArmy = f.teams[0]
	var state: Dictionary = f.data.site.team_supply[str(team.team_id)].sustain
	_enable(team)
	PersonFatigue.write(team.combat_units[0], "fatigue", 85.0)
	_decide(f)
	_check(_orderly_withdrawal(team) and team.tactical_ai_recovering, "Fatigue without a sustain rout must hold or withdraw in good order")
	_advance(f, 0.5)
	_check(_orderly_withdrawal(team) and team.tactical_ai_recovering,
		"Fatigue recovery must not manufacture a rout")
	PersonFatigue.write(team.combat_units[0], "fatigue", 60.0)
	_decide(f, 3.0)
	_check(team.tactical_ai_recovering and team.combat_order not in [TerrainArmy.CombatOrder.ATTACK, TerrainArmy.CombatOrder.PURSUE],
		"Recovery hysteresis must not attack at fatigue 60")
	PersonFatigue.write(team.combat_units[0], "fatigue", 40.0)
	state.morale = 30.0
	_decide(f, 3.0)
	_check(team.tactical_ai_recovering, "Low morale must prevent premature recovery")
	state.morale = 70.0
	_finish_withdrawal(f, team)
	_decide(f, 3.0)
	_check(not team.tactical_ai_recovering and team.combat_order in [TerrainArmy.CombatOrder.MOVE, TerrainArmy.CombatOrder.ATTACK],
		"Recovered fatigue/morale and favourable strength must resume approach")
	_record(f)
	_dispose(f)
	_current_case = "original_morale_retreat_rout_and_no_commander"
	f = _fixture([8, 1, 1], [Vector2i(24, 24), Vector2i(30, 24), Vector2i(45, 45)])
	team = f.teams[0]
	state = f.data.site.team_supply[str(team.team_id)].sustain
	_enable(team)
	state.morale = 20.0
	_decide(f, 3.0)
	_check(team.tactical_ai_recovering and _orderly_withdrawal(team) and not state.routed,
		"A low morale snapshot cannot replace the original sustain rout transition")
	state.morale = 100.0
	state.routed = true
	f.supply._start_supply_rout(team)
	var original_rout_order := team.combat_order
	var original_rout_goal := team.combat_goal
	var original_rout_slots := team.combat_slots.duplicate()
	var original_ai_orders := team.tactical_ai_orders
	_decide(f, 3.0)
	_check(team.is_sustain_routed() and team.combat_order not in [TerrainArmy.CombatOrder.ATTACK, TerrainArmy.CombatOrder.MOVE, TerrainArmy.CombatOrder.PURSUE],
		"AI cannot bypass original sustain rout")
	_check(team.combat_order == original_rout_order and team.combat_goal == original_rout_goal
		and team.combat_slots == original_rout_slots and team.tactical_ai_orders == original_ai_orders,
		"AI must preserve the original sustain owner's accepted rout without a second command")
	var refused: Dictionary = team.issue_tactical_ai_order(TerrainArmy.CombatOrder.ATTACK)
	_check(not bool(refused.ok) and team.is_sustain_routed(), "AI wrapper must preserve original routed validation")
	state.routed = false
	for index in range(team.combat_units.size()): team.combat_hot_set(index, &"ko", 10.0)
	team._command_dirty = true
	team.settle_combat_command()
	_decide(f, 3.0)
	_check(team.current_commander < 0 and not team.combat_attacking, "No eligible commander cannot issue an attack")
	_record(f)
	_dispose(f)

func _blocked_exit_and_pursuit_return() -> void:
	_current_case = "outmatched_hold_is_bounded"
	var f := _fixture([1, 8, 1], [Vector2i(24, 24), Vector2i(28, 24), Vector2i(45, 45)])
	var team: TerrainArmy = f.teams[0]
	for direction: Vector2i in TerrainData.DIRECTIONS:
		f.data.static_blocked[f.data.index(team.cells[0] + direction)] = 1
	_enable(team)
	_decide(f)
	var initial_orders := team.tactical_ai_orders
	for decision in range(10): _decide(f)
	_check(team.combat_order == TerrainArmy.CombatOrder.HOLD and team.cells[0] == Vector2i(24, 24), "A blocked weaker army must hold without inventing a rout")
	_check(team.tactical_ai_orders == initial_orders, "Unchanged caution cannot cause repeated identical commands")
	_record(f)
	_dispose(f)
	_current_case = "original_pursue_return_hold"
	f = _fixture([1, 1, 1], [Vector2i(14, 14), Vector2i(21, 14), Vector2i(45, 45)])
	team = f.teams[0]
	var enemy: TerrainArmy = f.teams[1]
	var origin: Vector2i = team.cells[0]
	var pursued: Dictionary = team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.PURSUE, TerrainArmy.INVALID_CELL, enemy.combat_identity(0))
	_check(bool(pursued.ok), "Original PURSUE admission")
	_advance(f, 2.0)
	_check(team.cells[0] != origin, "Original PURSUE must physically chase")
	enemy.combat_hot_set(0, &"hp", 0.0)
	_advance(f, STEP)
	_check(team.combat_order == TerrainArmy.CombatOrder.RETURN, "Lost pursuit target must enter original RETURN")
	_advance(f, 8.0)
	_check(team.combat_order == TerrainArmy.CombatOrder.HOLD and team.cells[0] == origin, "RETURN must physically finish at its original slot")
	_record(f)
	_dispose(f)

func _all_three_live() -> void:
	_current_case = "three_ai_owners_live_together"
	var f := _fixture([8, 2, 1], [Vector2i(20, 20), Vector2i(30, 20), Vector2i(28, 29)])
	var initial_cells: Array = []
	for team: TerrainArmy in f.teams:
		initial_cells.append(team.cells.duplicate())
		_enable(team)
	_advance(f, 12.0)
	var moving_owners := 0
	for index in range(3):
		var team: TerrainArmy = f.teams[index]
		_check(team.tactical_ai_decisions > 1, "Each faction must receive recurring decisions")
		if team.cells != initial_cells[index] or team.accepted_count > 0:
			moving_owners += 1
		else:
			_check(team.combat_order == TerrainArmy.CombatOrder.HOLD and not team.is_sustain_routed(), "An intact-morale weaker faction may hold, but cannot invent a retreat")
	_check(moving_owners > 0, "At least one faction must physically execute its original AI move")
	_check(_no_overlap(f), "Three simultaneous AI owners retain Grid occupancy")
	_record(f)
	_dispose(f)

func _bbox_contact_guard() -> void:
	_current_case = "bbox_contact_guard"
	var data := Helper.build_flat_map(8, 8)
	var own := {"minimum": Vector2i(2, 2), "maximum": Vector2i(2, 2)}
	var own_people := [{"cell": Vector2i(2, 2)}]
	for sample: Dictionary in [
		{"cell": Vector2i(5, 2), "contact": false},
		{"cell": Vector2i(3, 2), "contact": true},
		{"cell": Vector2i(3, 3), "contact": false},
		{"cell": Vector2i(2, 2), "contact": false},
	]:
		var other := {"minimum": sample.cell, "maximum": sample.cell}
		var enemy_people := [{"cell": sample.cell}]
		var exact := TacticalAI._touching(data, own_people, enemy_people)
		var guarded := TacticalAI._gap(own, other) <= 1.0 and TacticalAI._touching(data, own_people, enemy_people)
		_check(guarded == exact and exact == bool(sample.contact), "Bounding guard must preserve four-way contact at %s" % sample.cell)

func _contact_beats_overlapping_bounds() -> void:
	_current_case = "true_contact_beats_nearer_empty_bounding_box"
	var f := _fixture([8, 2, 1], [Vector2i(24, 24), Vector2i.ZERO, Vector2i(26, 24)],
		{1: [Vector2i(20, 20), Vector2i(30, 30)]})
	var team: TerrainArmy = f.teams[0]
	var empty_bounds: TerrainArmy = f.teams[1]
	var touching: TerrainArmy = f.teams[2]
	_check(_nearest_gap(team, empty_bounds) > 1.0 and _nearest_gap(team, touching) == 1.0,
		"Fixture must contain an empty overlapping enemy bounding box and another real contact")
	_enable(team)
	_decide(f)
	_check(team.combat_order == TerrainArmy.CombatOrder.ATTACK
		and team.tactical_ai_target_id == touching.combat_identity(0),
		"Real four-way contact must win over the other faction's empty overlapping bounds")
	_advance(f, 0.25)
	_check(f.lab.exchange_count > 0, "The prioritized contact must produce an original exchange")
	_record(f)
	_dispose(f)

func _independent_people_stay_visible() -> void:
	_current_case = "out_of_command_radius_player_member_remains_enemy"
	var f := _fixture([8, 1, 1], [Vector2i(24, 24), Vector2i(45, 45), Vector2i(50, 12)])
	var team: TerrainArmy = f.teams[0]
	var distant_owner: TerrainArmy = f.teams[1]
	var actor := TerrainTestCharacter.new()
	actor.data = f.data
	actor.person_id = 9001
	actor.faction_id = distant_owner.faction_id
	actor.exchange_enabled = true
	actor._saved_appearance = distant_owner.combat_units[0].appearance.duplicate(true)
	_check(actor.place(Vector2i(26, 24), true), "Original Actor placement")
	distant_owner.player = actor
	f.lab.combat_actors.append(actor)
	_check(bool(distant_owner.join_player(actor).ok), "Original Actor joins its distant faction owner")
	_check(distant_owner.player_member == actor and not distant_owner.player_present and actor.can_act(),
		"Joined Actor must be actionable but outside its own command presence radius")
	_enable(team)
	_decide(f)
	_check(team.combat_order == TerrainArmy.CombatOrder.ATTACK and team.tactical_ai_target_id == actor.person_id,
		"An absent player_member must remain discoverable through the original combat Actor")
	_record(f, {"actor_id": actor.person_id, "actor_present": distant_owner.player_present,
		"actor_can_act": actor.can_act(), "actor_cell": str(actor.terrain_cell)})
	_dispose(f)
	_current_case = "departed_roster_member_remains_physical_enemy"
	f = _fixture([8, 2, 1], [Vector2i(24, 24), Vector2i.ZERO, Vector2i(50, 12)],
		{1: [Vector2i(26, 24), Vector2i(45, 45)]})
	team = f.teams[0]
	distant_owner = f.teams[1]
	var independent_id := distant_owner.combat_identity(0)
	distant_owner.controlled_person_query = func() -> int: return independent_id
	_check(bool(distant_owner.leave_row(independent_id).ok), "Original controlled row leaves its roster")
	_check(not distant_owner.is_member(0) and distant_owner.combat_can_act(0)
		and distant_owner.blocks_cell(Vector2i(26, 24)), "Unregistered row remains the same actionable occupied body")
	_enable(team)
	_decide(f)
	_check(team.combat_order == TerrainArmy.CombatOrder.ATTACK and team.tactical_ai_target_id == independent_id,
		"A nonmember row must remain visible as a hostile original person")
	_advance(f, 0.25)
	_check(f.lab.exchange_count > 0, "The independent hostile row participates in real exchanges")
	_record(f)
	_dispose(f)

func _approach_tries_reachable_candidate() -> void:
	_current_case = "walkable_isolated_candidate_then_reachable_approach"
	var f := _fixture([1, 1, 1], [Vector2i(5, 10), Vector2i(18, 10), Vector2i(21, 21)], {}, Vector2i(24, 24))
	var team: TerrainArmy = f.teams[0]
	var enemy: TerrainArmy = f.teams[1]
	var isolated := Vector2i(17, 10)
	f.data.height_levels[f.data.index(isolated)] = 2
	_check(f.data.is_walkable(isolated), "First candidate must be walkable, not trivially filtered out")
	_check(not bool(team.preview_combat_move(isolated).ok), "Original MOVE preflight must reject the isolated cliff cell")
	_check(bool(team.preview_combat_move(Vector2i(18, 9)).ok)
		and bool(team.preview_combat_move(Vector2i(18, 11)).ok), "The next vertical candidates must have real admissible routes")
	_enable(team)
	_decide(f)
	var plan := team.get_active_move_plan()
	_check(team.combat_order == TerrainArmy.CombatOrder.MOVE and plan != null,
		"AI must try the next reachable approach after the first legal-looking goal has no path")
	if plan != null:
		_check(plan.requested_goal != isolated and plan.macro_path.size() > 1,
			"Accepted original plan must use the alternate candidate and an actual macro route")
	var initial_gap := _nearest_gap(team, enemy)
	_advance(f, 2.0)
	_check(_nearest_gap(team, enemy) < initial_gap, "Alternate admitted route must move the original body closer")
	_record(f, {"isolated": str(isolated), "initial_gap": initial_gap, "final_gap": _nearest_gap(team, enemy)})
	_dispose(f)

func _retarget_changes_actual_route() -> void:
	_current_case = "dead_target_replaces_original_move_goal_and_route"
	var f := _fixture([8, 1, 1], [Vector2i(24, 24), Vector2i(40, 24), Vector2i(24, 44)])
	var team: TerrainArmy = f.teams[0]
	var first: TerrainArmy = f.teams[1]
	var next_enemy: TerrainArmy = f.teams[2]
	_enable(team)
	_decide(f)
	var first_plan := team.get_active_move_plan()
	_check(first_plan != null and team.tactical_ai_target_id == first.combat_identity(0), "Initial real route targets the eastern enemy")
	if first_plan == null:
		_record(f)
		_dispose(f)
		return
	var old_goal: Vector2i = first_plan.requested_goal
	var old_serial := team._current_order_serial
	_advance(f, 0.6)
	first.apply_unit_contact(0, {"result": {"hp": 100.0, "stun": 0.0, "guard_break": false}, "shield": false})
	_check(first.member_gone(0), "Original damage path must remove the former target")
	_decide(f, 2.1)
	var new_plan := team.get_active_move_plan()
	_check(team.tactical_ai_target_id == next_enemy.combat_identity(0) and new_plan != null,
		"Remaining southern enemy must replace the old target")
	if new_plan != null:
		_check(new_plan != first_plan and team._current_order_serial > old_serial
			and new_plan.requested_goal != old_goal and team.combat_goal == new_plan.requested_goal
			and new_plan.requested_goal.distance_to(next_enemy.cells[0]) <= 3.0
			and new_plan.macro_path[-1] == new_plan.resolved_anchor,
			"Retargeting must replace the actual accepted goal, serial and macro route, not only an AI label")
	var before_y := 0.0
	for cell: Vector2i in team.cells: before_y += cell.y
	_advance(f, 3.0)
	var after_y := 0.0
	for cell: Vector2i in team.cells: after_y += cell.y
	_check(after_y > before_y, "The redirected original bodies must progress south along the replacement route")
	_record(f, {"old_goal": str(old_goal), "new_goal": str(team.combat_goal), "old_serial": old_serial,
		"new_serial": team._current_order_serial, "sum_y_before": before_y, "sum_y_after": after_y})
	_dispose(f)

func _restored_unknown_target_replans_after_cooldown() -> void:
	_current_case = "restored_unknown_target_replans_after_saved_cooldown"
	var f := _fixture([8, 1, 1], [Vector2i(24, 24), Vector2i(40, 24), Vector2i(40, 29)])
	var team: TerrainArmy = f.teams[0]
	var old_enemy: TerrainArmy = f.teams[1]
	var new_enemy: TerrainArmy = f.teams[2]
	_enable(team)
	_decide(f)
	var old_plan := team.get_active_move_plan()
	if not _check(old_plan != null and team.tactical_ai_target_id == old_enemy.combat_identity(0), "Initial AI MOVE must select the old enemy"):
		_record(f)
		_dispose(f)
		return
	var old_goal: Vector2i = old_plan.requested_goal
	var old_serial := team._current_order_serial
	_check(old_goal.distance_to(new_enemy.cells[0]) <= 8.0, "Replacement enemy must be within the old route's eight-cell reuse range")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(team.capture_combat_state()))
	if not _check(TerrainArmy.valid_combat_state(saved, f.data), "Actual JSON Army state must validate before restoration"):
		_record(f)
		_dispose(f)
		return
	f.coordinator.unregister_formation(team)
	team.restore_combat_state(saved, f.data, null, null)
	f.coordinator.register_formation(team)
	_check(team.tactical_ai_enabled and team.tactical_ai_target_id == -1
		and team.tactical_ai_order_cooldown > 1.0 and team.combat_order == TerrainArmy.CombatOrder.MOVE,
		"Original restore keeps accepted MOVE/cooldown and intentionally rebuilds derived target identity")
	old_enemy.apply_unit_contact(0, {"result": {"hp": 100.0, "stun": 0.0, "guard_break": false}, "shield": false})
	_decide(f, 0.51)
	_check(team._current_order_serial == old_serial and team.combat_goal == old_goal,
		"Restored cooldown must protect the accepted route until it expires")
	_decide(f, 1.6)
	var replacement := team.get_active_move_plan()
	_check(replacement != null and team._current_order_serial > old_serial
		and team.combat_goal != old_goal and team.tactical_ai_target_id == new_enemy.combat_identity(0),
		"Unknown restored target must be re-evaluated after cooldown even when another enemy is near the old goal")
	if replacement != null:
		_check(replacement.requested_goal == team.combat_goal
			and replacement.requested_goal.distance_to(new_enemy.cells[0]) <= 3.0,
			"Restored AI must replace the original accepted route with a valid approach to the surviving enemy")
	_record(f, {"old_goal": str(old_goal), "new_goal": str(team.combat_goal), "old_serial": old_serial,
		"new_serial": team._current_order_serial})
	_dispose(f)

func _pursuit_display_tracks_original_target() -> void:
	_current_case = "pursuit_display_matches_original_target_despite_nearer_enemy"
	var f := _fixture([8, 1, 1], [Vector2i(24, 24), Vector2i(34, 24), Vector2i(29, 29)])
	var team: TerrainArmy = f.teams[0]
	var pursued: TerrainArmy = f.teams[1]
	var nearer: TerrainArmy = f.teams[2]
	var target := pursued.combat_identity(0)
	_check(_nearest_gap(team, nearer) < _nearest_gap(team, pursued), "A different hostile group must actually be nearer")
	_check(bool(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.PURSUE,
		TerrainArmy.INVALID_CELL, target).ok), "Original pursuit must be admitted before AI takes over")
	_enable(team)
	var initial_orders := team.tactical_ai_orders
	_decide(f)
	_check(team.combat_order == TerrainArmy.CombatOrder.PURSUE and team.pursuit_target == target
		and team.tactical_ai_target_id == target and team.tactical_ai_orders == initial_orders,
		"AI must display the actual original pursuit target rather than the newly nearest enemy")
	_advance(f, 1.0)
	_check(team.combat_order == TerrainArmy.CombatOrder.PURSUE and team.pursuit_target == target
		and team.tactical_ai_target_id == target and team.pursuit_left < 20.0 and team.accepted_count > 0,
		"Pursuit target display must remain accurate while the original pursuit clock and bodies advance")
	_record(f, {"pursued_id": target, "nearer_enemy_id": nearer.combat_identity(0), "pursuit_left": team.pursuit_left})
	_dispose(f)

func _allied_store_base_map() -> TerrainData:
	var data := TerrainData.new()
	data.allocate(Vector2i(48, 40))
	data.preset = TerrainPreset.Kind.PLAINS
	data.seed_value = 581
	data.parameters = TerrainPreset.defaults(data.preset)
	data.parameters["size"] = data.size
	data.parameters["composition"] = "fixed_geography"
	data.height_levels.fill(1)
	data.surface_types.fill(TerrainData.Surface.GRASS)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.ramp_edges.fill(0)
	data.water_kind.resize(data.size.x * data.size.y)
	data.water_kind.fill(0)
	data.water_body.resize(data.size.x * data.size.y)
	data.water_body.fill(-1)
	data.spawn_cell = Vector2i(2, 2)
	data.parameters["fixed_base"] = {"base_kind": "fixed_geography", "atlas_id": ALLIED_STORE_SITE,
		"base_revision": "1", "manifest_sha256": ALLIED_STORE_SITE.sha256_text(),
		"site_id": ALLIED_STORE_SITE, "terrain_fingerprint": data.fingerprint(),
		"grid_contract_version": 1, "site": [0, 0]}
	SiteEnvironment.initialize(data, ALLIED_STORE_SITE)
	return data

func _load_allied_store_base(_requested: Dictionary) -> Dictionary:
	var data := _allied_store_base_map()
	return {"ok": true, "data": data, "base": data.parameters.fixed_base}

func _allied_third_commander_store_resume() -> void:
	_current_case = "allied_third_commander_natural_move_store_resume"
	var f := _fixture([1, 1, 3], [Vector2i(20, 22), Vector2i(40, 16), Vector2i(14, 16)],
		{}, Vector2i(48, 40), {}, _allied_store_base_map())
	var ally: TerrainArmy = f.teams[0]
	var enemy: TerrainArmy = f.teams[1]
	var team: TerrainArmy = f.teams[2]
	team.faction_id = ally.faction_id
	if not _check(bool(team.set_military_role(team.combat_identity(1), "officer").ok), "Original row 1 explicitly qualifies as an officer before appointment"):
		_dispose(f)
		return
	if not _check(bool(team.record_officer_service([1], true).ok), "Original row 1 enters the commander succession order"):
		_dispose(f)
		return
	team.apply_unit_contact(0, {"result": {"hp": 100.0, "stun": 0.0, "guard_break": false}, "shield": false})
	team.settle_combat_command()
	if not _check(team.current_commander == 1 and team.formal_commander == 1
		and team.command_eligible(1), "Original commander death must appoint eligible row 1, not a person ID as index"):
		_dispose(f)
		return
	var commander_id := team.combat_identity(1)
	var enemy_id := enemy.combat_identity(0)
	var first_cell: Vector2i = team.cells[1]
	_check(_nearest_gap(team, ally) < _nearest_gap(team, enemy), "Allied third-team fixture must have a nearer friendly formation")
	_enable(team)
	_advance(f, 3.0) # Original common action path decides and moves; no direct order or helper review.
	if not _check(team.tactical_ai_decisions > 0 and team.combat_order == TerrainArmy.CombatOrder.MOVE
		and team.tactical_ai_target_id == enemy_id and team.cells[1] != first_cell and team.completed_steps() > 0,
		"Third-team AI must naturally command row 1 to move toward the enemy while excluding its closer ally"):
		_record(f)
		_dispose(f)
		return
	f.data.site["army_trial_active"] = true
	f.data.site["army_next_team"] = 4
	f.data.site["actors"] = {}
	f.data.site["armies"] = []
	var before_ai: Array[Dictionary] = []
	for original: TerrainArmy in f.teams:
		f.data.site.armies.append(original.capture_combat_state())
		before_ai.append(original._capture_tactical_ai_state())
	var saved_cell: Vector2i = team.cells[1]
	var saved_destinations := team.moving_to.duplicate()
	var saved_progress := team.move_progress.duplicate()
	var saved_slots := team.combat_slots.duplicate()
	var saved_goal := team.combat_goal
	var saved_batches: Array = f.coordinator.get_inflight_batches_for_formation(team)
	var saved_leases: Array[Vector2i] = f.coordinator.deployment_registry.get_formation_reserved_slots(team.team_id)
	_check(not saved_batches.is_empty() and not saved_leases.is_empty(), "Save fixture must contain actual in-flight batches and original destination leases")
	var save_path := _folder.path_join("allied-third-moving.json")
	var saved := Store.save(f.data, save_path)
	if not _check(bool(saved.ok), "Actual SiteStore must accept the original moving allied formation: " + str(saved)):
		_record(f)
		_dispose(f)
		return
	var loaded := Store.load_site(save_path, _load_allied_store_base)
	if not _check(bool(loaded.ok), "Actual SiteStore must restore the same fixed map and three original teams: " + str(loaded)):
		_dispose(f)
		return
	for original: TerrainArmy in f.teams:
		original.clear()
	# Match Lab.bind_terrain: original Army nodes stay bound while their old
	# occupancy is cleared, so restore can rebuild leases and in-flight batches.
	f.coordinator.reset_for_site_replacement()
	f.data = loaded.data
	f.lab.terrain = loaded.data
	f.lab._tactical_ai_elapsed = 0.0 # Same derived review reset as successful Lab binding.
	for index in range(f.teams.size()):
		var original: TerrainArmy = f.teams[index]
		original.restore_combat_state(loaded.data.site.armies[index], loaded.data, null, null)
		_check(original._capture_tactical_ai_state() == before_ai[index], "Store preserves each original team's AI consent and cooldowns")
	_check(f.coordinator.get_inflight_batches_for_formation(team) == saved_batches,
		"Original coordinator must restore the saved in-flight batches before any action step")
	var restored_leases: Array[Vector2i] = f.coordinator.deployment_registry.get_formation_reserved_slots(team.team_id)
	_check(restored_leases.size() == saved_leases.size(), "Original coordinator must restore every saved destination lease")
	for cell: Vector2i in saved_leases:
		_check(restored_leases.has(cell), "Restored destination lease remains on the original accepted cell")
	_check(team.current_commander == 1 and team.formal_commander == 1 and team.combat_identity(1) == commander_id
		and team.command_eligible(1), "Saved successor remains the same eligible original commander row and identity")
	_check(team.cells[1] == saved_cell and team.moving_to == saved_destinations and team.move_progress == saved_progress
		and team.combat_slots == saved_slots and team.combat_goal == saved_goal,
		"Store resume preserves actual in-flight movement, destinations, slots and accepted goal")
	_check(team.faction_id == ally.faction_id and team.faction_id != enemy.faction_id
		and not ally.tactical_ai_enabled and not enemy.tactical_ai_enabled and team.tactical_ai_enabled,
		"Restoration preserves third-team alliance and independent AI consent")
	_check(f.lab._army_target(team, ally.combat_identity(0)).is_empty()
		and not f.lab._army_target(team, enemy_id).is_empty(), "Original target query excludes allies after restore")
	var gap_before_resume := team.cells[1].distance_to(enemy.cells[0])
	var steps_before_resume := team.completed_steps()
	_advance(f, 3.0)
	_check(team.current_commander == 1 and team.combat_identity(team.current_commander) == commander_id
		and team.tactical_ai_decisions > 0 and team.tactical_ai_target_id == enemy_id,
		"Natural restored AI must re-evaluate to the actual enemy through the same successor commander")
	_check(team.cells[1] != saved_cell and team.cells[1].distance_to(enemy.cells[0]) < gap_before_resume
		and team.completed_steps() > steps_before_resume, "Restored original bodies must physically continue toward the enemy")
	_record(f, {"save_path": save_path, "commander_row": team.current_commander,
		"commander_id": commander_id, "enemy_id": enemy_id, "saved_cell": str(saved_cell),
		"resumed_cell": str(team.cells[1])})
	_dispose(f)

func _seed_real_equipment(f: Dictionary, team: TerrainArmy) -> void:
	_check(bool(SiteRuntime.initialize_item_storage(f.data.site).ok), "Original equipment storage")
	for row: Dictionary in team.combat_units:
		row.item_state = {}
		row.cargo = {}
		_check(bool(SiteRuntime.seed_person_equipment(f.data, row.item_state, int(row.person_id), row.appearance).ok),
			"Original weapon instances seeded")
	team.equipment_appearance_query = func(identity: int) -> Dictionary:
		var row: Dictionary = team.combat_units[team.index_for_identity(identity)]
		return SiteRuntime.equipment_appearance(f.data, row.item_state, row.appearance)

func _ammunition_and_mixed_commander() -> void:
	for troop: StringName in [&"bow", &"crossbow"]:
		_current_case = "%s_empty_ammunition_hold_then_resupply" % troop
		var f := _fixture([2, 1, 1], [Vector2i(20, 20), Vector2i(27, 20), Vector2i(50, 50)], {}, Vector2i(64, 64), {0: troop})
		var team: TerrainArmy = f.teams[0]
		_seed_real_equipment(f, team)
		var profile := team.ranged_profile(0)
		_check(not profile.is_empty(), "The original equipment owner must identify the ranged troop")
		if profile.is_empty():
			_record(f)
			_dispose(f)
			continue
		_enable(team)
		var initial_gap := _nearest_gap(team, f.teams[1])
		_decide(f)
		_check(team.tactical_ai_recovering and _orderly_withdrawal(team),
			"Empty ammunition without a sustain rout must hold or withdraw in good order, never falsely attack")
		_advance(f, 1.0)
		_check(f.lab.ranged_shots == 0 and _nearest_gap(team, f.teams[1]) >= initial_gap, "Empty ammunition must not fabricate shots or advance on the enemy")
		_check(_orderly_withdrawal(team), "Ranged caution persists before resupply")
		var ammo := str(profile.ammo)
		for row: Dictionary in team.combat_units: row.cargo[ammo] = 6
		_finish_withdrawal(f, team)
		_decide(f, 3.0)
		_check(not team.tactical_ai_recovering and team.combat_order in [TerrainArmy.CombatOrder.MOVE, TerrainArmy.CombatOrder.ATTACK],
			"Real ammunition replenishment permits recovery and a new approach")
		for window in range(40):
			_advance(f, 0.5)
			if f.lab.ranged_shots > 0:
				break
		var ammunition_left := 0
		for row: Dictionary in team.combat_units: ammunition_left += int(row.cargo.get(ammo, 0))
		_check(f.lab.ranged_shots > 0 and ammunition_left >= 0 and ammunition_left < 12,
			"Recovered ranged AI must fire through original projectile logic and consume real ammunition")
		_record(f, {"ammunition_kind": ammo, "ammunition_initial": 12, "ammunition_left": ammunition_left,
			"ranged_shots": f.lab.ranged_shots})
		_dispose(f)
	_current_case = "one_ranged_captain_does_not_reclassify_melee_army"
	var mixed_fixture := _fixture([8, 1, 1], [Vector2i(20, 20), Vector2i(27, 20), Vector2i(50, 50)])
	var mixed_team: TerrainArmy = mixed_fixture.teams[0]
	mixed_team.combat_units[0].appearance = mixed_team.combat_units[0].appearance.duplicate(true)
	mixed_team.combat_units[0].appearance.parts.weapon = "bow_01"
	mixed_team.combat_units[0].appearance.parts.shield = "none"
	_seed_real_equipment(mixed_fixture, mixed_team)
	_check(not mixed_team.ranged_profile(0).is_empty() and mixed_team.ranged_profile(1).is_empty(), "Only the original captain is a ranged soldier")
	_enable(mixed_team)
	_decide(mixed_fixture)
	_check(not mixed_team.tactical_ai_recovering and mixed_team.combat_order == TerrainArmy.CombatOrder.MOVE,
		"One empty bow captain cannot force seven melee soldiers to retreat or stop at bow range")
	_record(mixed_fixture)
	_dispose(mixed_fixture)

func _write_report() -> void:
	var report := {"passed": _failures.is_empty(), "checks": _checks, "failures": _failures,
		"wall_seconds": (Time.get_ticks_usec() - _started) / 1000000.0, "cases": _cases,
		"scope": "Small deterministic Lab/Army/Grid behavior contracts; not formal-scene visual or FPS acceptance"}
	var file := FileAccess.open(_folder.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	var text_file := FileAccess.open(_folder.path_join("behavior.log"), FileAccess.WRITE)
	if text_file != null:
		text_file.store_string("SITE TACTICAL AI BEHAVIOR %s\nchecks=%d\n%s\n" % ["PASS" if _failures.is_empty() else "FAIL", _checks, "\n".join(_failures)])

func _finish() -> void:
	_write_report()
	print("SITE TACTICAL AI BEHAVIOR %s checks=%d report=%s" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _folder])
	quit(0 if _failures.is_empty() else 1)

func _run() -> void:
	_rotation_matrix()
	if _within_deadline(): _non_morale_retreat_guards()
	if OS.get_cmdline_user_args().has("--morale-authority-only"):
		if _within_deadline(): _recovery_and_rout()
		if _within_deadline(): _ammunition_and_mixed_commander()
		_finish()
		return
	if _within_deadline(): _authority_pause_and_target()
	if _within_deadline(): _recovery_and_rout()
	if _within_deadline(): _blocked_exit_and_pursuit_return()
	if _within_deadline(): _all_three_live()
	if _within_deadline(): _bbox_contact_guard()
	if _within_deadline(): _contact_beats_overlapping_bounds()
	if _within_deadline(): _independent_people_stay_visible()
	if _within_deadline(): _approach_tries_reachable_candidate()
	if _within_deadline(): _retarget_changes_actual_route()
	if _within_deadline(): _restored_unknown_target_replans_after_cooldown()
	if _within_deadline(): _pursuit_display_tracks_original_target()
	if _within_deadline(): _allied_third_commander_store_resume()
	if _within_deadline(): _ammunition_and_mixed_commander()
	_finish()
