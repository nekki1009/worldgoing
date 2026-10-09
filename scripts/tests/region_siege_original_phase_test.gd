extends "res://scripts/tests/region_siege_cold_action_epoch_test.gd"
## Genuine fixed Slot, dispatched NPC bodies, paid siege mechanics and selected
## original graphs. Fixture construction uses original paid authoring APIs;
## phase/action/capture time comes only from the original common shared step.
const PhaseBattle = preload("res://scripts/region_lab/region_gameplay_battle.gd")
const PhaseAI = preload("res://scripts/region_lab/region_gameplay_ai.gd")
const PhasePanel = preload("res://scripts/region_lab/region_travel_panel.gd")
var phase_case := "all"
var phase_observe := "siege"
var phase_expected := "siege"
var phase_topology := "closed"
var phase_wall: Dictionary = {}
var phase_npc_token := ""
var phase_source_team := -1
var phase_infantry_team := -1
var phase_source_people: Array[int] = []
var phase_arrival_people: Array[int] = []
var phase_source_refs: Dictionary = {}
var phase_observations: Array[Dictionary] = []
var phase_panel: PhasePanel
var phase_flight_id := ""
var phase_flight_snapshot: Dictionary = {}

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 360000
	out = "res://.godot-temp/region_siege_original_phase/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	last_world_exists = FileAccess.file_exists(Entry.LAST_WORLD)
	if last_world_exists: last_world_bytes = FileAccess.get_file_as_bytes(Entry.LAST_WORLD)
	action_kind = "ballista"
	action_case = "aiming"
	action_speed = 1.0
	for argument: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument.begins_with("--phase-case="): phase_case = argument.trim_prefix("--phase-case=")
		if argument.begins_with("--observe-phase="): phase_observe = argument.trim_prefix("--observe-phase=")
		if argument.begins_with("--siege-topology="): phase_topology = argument.trim_prefix("--siege-topology=")
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_msec() > deadline: _finish(false, "360-second original siege phase deadline")
	return false

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _check(phase_case in ["all", "flight_wreck", "flight_removed", "flight_crew_invalid", "player"] and phase_topology in ["closed", "thick"]
		and phase_observe in ["siege", "breach", "assault", "capture"], "one genuine bounded phase/caller case", {"case": phase_case, "topology": phase_topology, "phase": phase_observe}): _finish(); return
	if not _write_manifest() or not _setup_action_world(): _finish(); return
	if not await _phase_dispatch_original_infantry(): _finish(); return
	if not await _phase_ready_engine(): _finish(); return
	if not _phase_no_path() or not _phase_observe_actual("siege"): _finish(); return
	if phase_case == "player":
		if not await _phase_player_intervene(): _finish(); return
		_finish(); return
	phase_expected = "siege"
	if not await _phase_reopen(): _finish(); return
	var attack: Dictionary = action_owner.site_controller.vehicles.order_siege(str(action_context.key), "attack", action_context.target, int(action_context.commander), true)
	if not _check(attack.ok, "real captain accepts the original finite attack order", attack): _finish(); return
	if not await _action_until(func() -> bool: return str(_action_vehicle().action.get("stage", "")) == "aiming" and float(_action_vehicle().action.get("elapsed", 0.0)) > 0.0, "original common intervals pay loading and partial aiming"): _finish(); return
	if not _phase_no_path() or not _phase_observe_actual("breach"): _finish(); return
	phase_expected = "breach"
	if not await _phase_reopen(): _finish(); return
	if not await _action_until(func() -> bool: return not action_owner.siege_projectiles.is_empty() and float(action_owner.siege_projectiles[0].elapsed) > 0.0, "original finite ammo release produces a genuine paid flight"): _finish(); return
	phase_flight_snapshot = action_owner.siege_projectiles[0].duplicate(true)
	phase_flight_id = str(phase_flight_snapshot.attack_id)
	if not _check(int(_action_vehicle().next_attack_seq) == action_initial_sequence + 1 and int(_action_vehicle().holder.version) == action_initial_holder + 1
		and int(_action_vehicle().cargo.get(str(SiteRuntime.SIEGE_DEFINITIONS.ballista.ammo), 0)) == 0, "original paid flight has one actual ammo, holder version and attack sequence"): _finish(); return
	if not _phase_fault_original_source(): _finish(); return
	phase_flight_snapshot = action_owner.siege_projectiles[0].duplicate(true)
	if not _phase_observe_actual("breach"): _finish(); return
	if not await _phase_reopen(): _finish(); return
	if not _phase_same_flight(): _finish(); return
	if not await _action_until(func() -> bool: return action_owner.siege_projectiles.is_empty(), "same original paid flight reaches its one actual impact after positive reopen"): _finish(); return
	if not _check(_actual_target_hp(action_context.target) == 0.0 and action_owner.siege_shots == 1
		and (not action_owner.terrain.site.vehicles.has(str(action_context.key)) if phase_case == "flight_removed" else int(_action_vehicle().next_attack_seq) == action_initial_sequence + 1), "one retained original impact destroys only the prepaid vulnerable original wall part", _action_facts()): _finish(); return
	if phase_topology == "thick":
		if not _phase_no_path() or not _phase_observe_actual("siege"): _finish(); return
		var rejected_move: Dictionary = _phase_infantry().issue_combat_order(_phase_infantry().current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(22, 26))
		if not _check(not rejected_move.ok, "destroying the outer part does not invent a route through the intact second wall", rejected_move): _finish(); return
		if not _action_step(): _finish(); return
		report["thick_wall"] = {"actual_outer_hp": _actual_target_hp(action_context.target), "inner_remains": true, "original_move_rejected": rejected_move, "positive_original_future": true}
		_finish(); return
	var infantry := _phase_infantry()
	if not _check(infantry != null, "same actual incoming infantry resolves after selected bind"): _finish(); return
	var assault: Dictionary = infantry.issue_combat_order(infantry.current_commander, TerrainArmy.CombatOrder.ATTACK)
	if not _check(assault.ok, "true original infantry captain issues the original assault order", assault): _finish(); return
	if not _phase_observe_actual("assault"): _finish(); return
	phase_expected = "assault"
	if not await _phase_reopen(): _finish(); return
	infantry = _phase_infantry()
	var advance: Dictionary = infantry.issue_combat_order(infantry.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(22, 26))
	if not _check(advance.ok, "actual original formation admits movement through its real breached entry", advance): _finish(); return
	if not await _action_until(func() -> bool: return int(SiteSettlement.capture_sample(action_owner).get("attacker", -1)) == 1, "original actual bodies enter the genuine center capture zone"): _finish(); return
	if not _phase_observe_actual("capture"): _finish(); return
	phase_expected = "capture"
	if not await _phase_reopen(): _finish(); return
	var before_fall: Dictionary = SiteSettlement.record(action_owner.terrain).fall_record.duplicate(true)
	if not _check(float(before_fall.contest_seconds) < SiteSettlement.CAPTURE_SECONDS, "selected capture source contains its actual paid prefix", before_fall): _finish(); return
	if not await _action_until(func() -> bool: return int(SiteSettlement.record(action_owner.terrain).owner_faction) == 1, "original shared step and zero-time center settlement complete the same true fall"): _finish(); return
	if not _phase_observe_actual("finished"): _finish(); return
	var settled_fall: Dictionary = SiteSettlement.record(action_owner.terrain).fall_record.duplicate(true)
	var retry_bytes := var_to_bytes([slot.control, action_owner.terrain.site, _action_graph()])
	var retried: Dictionary = slot.consume_due_region_events()
	if not _check(retried.ok and retry_bytes == var_to_bytes([slot.control, action_owner.terrain.site, _action_graph()]), "actual finished siege same-point retry pays no second fall, impact or phase", retried): _finish(); return
	report["four_actual_phases"] = {"trace": phase_observations, "actual_fall_before": before_fall, "actual_fall_after": settled_fall, "flight_case": phase_case,
		"calibrated_casualty_coefficient": false, "numeric_balance_tolerance": null, "resolution": "original_exact_gd"}
	_finish()

func _action_target() -> Dictionary:
	var data := action_owner.terrain
	action_owner.character.faction_id = 2
	if not _check(action_owner.character.place(Vector2i(20, 15), true), "actual original defender founder starts in founding jurisdiction"): return {}
	var center_layout: Dictionary = SiteRuntime.building_cells(data, "settlement_center", Vector2i(20, 20), Vector2i.ONE)
	if not _check(center_layout.ok, "genuine center layout is legal", center_layout): return {}
	var center_cells: Array[int] = []; center_cells.assign(center_layout.cells)
	var founded: Dictionary = SiteSettlement.found(action_owner, action_owner.controlled_person_id(), center_cells, {}, Callable(), "原據點")
	if not _check(founded.ok, "actual original founding command pays original center materials", founded): return {}
	if not _phase_complete_initial_work(str(founded.feature)): return {}
	if not _check(action_owner.character.place(Vector2i(80, 80), true), "original defender body is initially outside the assault and capture zone"): return {}
	var target := {}
	for y: int in range(16, 29):
		for x: int in range(16, 29):
			if x not in [16, 28] and y not in [16, 28]: continue
			var cell := Vector2i(x, y)
			var wall: Dictionary = _phase_initial_wall(cell)
			if wall.is_empty(): return {}
			if cell == Vector2i(22, 28): target = wall
	if phase_topology == "thick":
		var inner: Dictionary = _phase_initial_wall(Vector2i(22, 27))
		if inner.is_empty(): return {}
		# A complete second row closes every otherwise free lower entry.
		for x: int in range(17, 28):
			if x == 22: continue
			if _phase_initial_wall(Vector2i(x, 27)).is_empty(): return {}
	var feature: Dictionary = data.site.features[str(target.feature_id)]
	var original_hp := float(feature.parts[str(target.part_id)].hp)
	var damaged: Dictionary = SiteRuntime.damage_structure_part(data, str(target.feature_id), str(target.part_id), original_hp - 1.0)
	if not _check(damaged.ok and float(feature.parts[str(target.part_id)].hp) == 1.0, "explicit authored vulnerable wall uses original structural damage, never a combat coefficient", damaged): return {}
	phase_wall = target.duplicate(true)
	return target

func _phase_complete_initial_work(key: String) -> bool:
	var feature: Dictionary = action_owner.terrain.site.features[key]
	var task := {"version": 2, "zone": -1, "target": "feature:" + key, "action": "construct", "work_cell": int(feature.entrance), "cell": int(feature.entrance), "mode": "work", "progress": 0.0, "status": "", "work_slot": -1}
	SiteRuntime._feature_work(action_owner.terrain, key, float(feature.work), Callable(), Callable(), task, {}, SiteRuntime.CARRY_CAPACITY, 2, action_owner.character.person_id)
	return _check(str(feature.stage) == "complete", "initial authored fixture work completes only through original paid feature owner", key)

func _phase_initial_wall(cell: Vector2i) -> Dictionary:
	var cells: Array[int] = [action_owner.terrain.index(cell)]
	var built: Dictionary = SiteRuntime.request_build(action_owner.terrain, "stone_wall", cells, Callable(), {"owner_faction": 2, "material": "stone"})
	if not _check(built.ok, "original closed-wall fixture reserves actual construction materials", {"cell": cell, "result": built}): return {}
	if not _phase_complete_initial_work(str(built.feature)): return {}
	return {"type": "structure", "feature_id": str(built.feature), "part_id": "c:%d" % action_owner.terrain.index(cell)}

func _phase_dispatch_original_infantry() -> bool:
	for key: String in lab.terrain.resource_base: Env.change(lab.terrain, key, {"cleared": true, "remaining": 0})
	lab._ensure_army_slots(2)
	var source: TerrainArmy = lab.combat_armies[1]
	source.faction_id = 1
	source.roster_size = 2
	var positions: Array[Vector2i] = [Vector2i(70, 70), Vector2i(71, 70)]
	if not _check(source.deploy_at(lab.terrain, lab.character, lab.npc, positions) and source.enable_combat(false, 0), "source births the actual original NPC captain and infantry row"): return false
	lab.site_controller.initialize_team_items(source)
	lab.terrain.site.army_next_team = maxi(int(lab.terrain.site.army_next_team), source.team_id + 1)
	phase_source_team = source.team_id
	for index: int in source.combat_units.size(): phase_source_people.append(source.combat_identity(index))
	var captain := source.combat_identity(source.current_commander)
	var nation_id := "phase_nation_%d" % OS.get_process_id()
	lab.terrain.site.equipment_nations[nation_id] = {"members": phase_source_people.duplicate(), "standards": {}, "offices": SiteOffices.default_offices("nation", captain, true)}
	var source_checkpoint: Dictionary = controller.checkpoint_region_internal("region_checkpoint", true)
	if not _check(source_checkpoint.ok, "actual original full checkpoint validates source nation and two body/item owners", source_checkpoint): return false
	var target_id := str(action_owner.terrain.site.id)
	var at := float(slot.control.logical_game_seconds)
	var observed: Dictionary = PhaseAI.observe(slot.region_registry(), {"id": "phase_known_target", "source": "site_observation", "observer": captain, "receiver": captain,
		"observer_scope": str(lab.terrain.site.id), "receiver_scope": str(lab.terrain.site.id), "object_scope": target_id, "object": target_id,
		"value": {"power": float(action_context.count + 1)}, "game_time": at, "expires_at": at + 86400.0})
	if not _check(observed.ok, "original intelligence owner admits the explicit scenario's source-scoped observation", observed): return false
	var body: Dictionary = lab._combat_target_in_site(captain)
	var component := RegionTravelSite.start_component(slot, Vector2i.ZERO, body.cell, lab.terrain)
	phase_npc_token = "phase_npc_%d" % OS.get_process_id()
	var prepared: Dictionary = slot.prepare_npc_region_dispatch(lab, nation_id, source.team_id, action_coordinate, component, [], phase_npc_token)
	if not _check(prepared.ok, "original authorized Slot producer prepares the true incoming infantry route", prepared): return false
	phase_source_refs = prepared.party.content.travel_identity.refs.person.duplicate(true)
	var committed: Dictionary = slot.commit_npc_region_dispatch(prepared)
	if not _check(committed.ok, "actual single marker commits the original NPC departure and source retirement", committed): return false
	if not await _action_until(func() -> bool: return str(slot.region_registry().parties[phase_npc_token].phase) == "entered", "actual common original route and arrival consumers admit the NPC at its own real endpoint"): return false
	var reference: Dictionary = slot.region_registry().parties[phase_npc_token]
	var mapping: Dictionary = reference.arrival_mapping.maps
	if not _check(mapping.get("team", {}).has(str(phase_source_team)), "true selected arrival mapping names the existing original incoming team", mapping): return false
	phase_infantry_team = int(mapping.team[str(phase_source_team)])
	for identity: int in phase_source_people:
		var local := int(mapping.person[str(identity)])
		phase_arrival_people.append(local)
		if not _check(not action_owner.site_controller.person_actions._person(local, false).is_empty(), "actual arrived person occupies one true original Site body", {"source": phase_source_refs[str(identity)], "local": local}): return false
	var infantry := _phase_infantry()
	if not _check(infantry != null, "same original full bind preserves incoming NPC army"): return false
	var moved: Dictionary = infantry.issue_combat_order(infantry.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(30, 31))
	if not _check(moved.ok, "true original captain approaches the outside of the still-closed fortification", moved): return false
	if not await _action_until(func() -> bool: return _phase_infantry()._combat_move_plan == null and _phase_infantry().moving_member_count() == 0, "incoming actual formation completes its legal outside approach"): return false
	var held: Dictionary = _phase_infantry().issue_combat_order(_phase_infantry().current_commander, TerrainArmy.CombatOrder.HOLD)
	return _check(held.ok, "actual incoming infantry holds outside the original center zone", held)

func _phase_infantry() -> TerrainArmy:
	for team: TerrainArmy in action_owner.combat_armies:
		if team.team_id == phase_infantry_team: return team
	return null

func _phase_ready_engine() -> bool:
	if not await _action_until(func() -> bool: return action_owner.site_controller.vehicles.crew_ready(_action_vehicle()), "true original crew reaches the prepaid engine stations"): return false
	var turned: Dictionary = action_owner.site_controller.vehicles.order_siege(str(action_context.key), "turn", {"facing": [0, -1]}, int(action_context.commander), true)
	if not _check(turned.ok, "original captain turns the actual engine toward its real wall target", turned): return false
	return await _action_until(func() -> bool: return _action_vehicle().action.is_empty() and _action_vehicle().facing == [0, -1] and action_owner.site_controller.vehicles.crew_ready(_action_vehicle()), "original paid rotation and actual crew return finish")

func _phase_no_path() -> bool:
	for identity: int in phase_arrival_people:
		for goal: Vector2i in SiteSettlement.capture_zone(action_owner.terrain):
			if not _check(PhaseBattle.original_siege_path(action_owner, identity, goal).is_empty(), "same original person purpose/nav guard cannot cross the intact wall", {"person": identity, "goal": goal}): return false
	return true

func _phase_battle() -> Dictionary:
	for battle: Dictionary in slot.region_registry().battles.values():
		if str(battle.get("kind", "")) == "siege" and str(battle.get("site_id", "")) == str(action_owner.terrain.site.id): return battle
	return {}

func _phase_observe_actual(expected: String) -> bool:
	var before_world := float(slot.control.logical_game_seconds)
	var before_action := float(slot.control.fire_clock.action_seconds)
	var refreshed: Dictionary = slot.refresh_original_region_siege_battle(action_owner)
	if not _check(refreshed.ok, "actual same original completed point derives its siege metadata", refreshed): return false
	var battle := _phase_battle()
	var expected_mode := "live" if str(slot.control.active_site_id) == str(action_owner.terrain.site.id) else "cold_exact"
	if not _check(not battle.is_empty() and str(battle.phase) == expected and battle.mode == expected_mode and battle.siege.resolution == "original_exact_gd"
		and PhaseBattle.validate_siege_metadata(battle.siege).ok, "real original producers derive phase " + expected, battle): return false
	if not _check(float(slot.control.logical_game_seconds) == before_world and float(slot.control.fire_clock.action_seconds) == before_action
		and battle.siege.arrivals.has(phase_npc_token), "phase query preserves both actual clocks and retains the real incoming route/mapping provenance"): return false
	for identity: int in phase_arrival_people:
		if not _check(battle.attackers.has(identity) and battle.siege.bodies.has(str(identity)), "actual incoming body ID survives in the same siege source graph", identity): return false
	var source_copy: Dictionary = battle.siege.duplicate(true)
	source_copy.version = int(source_copy.version) + 1
	var before_bytes := var_to_bytes([slot.control, action_owner.terrain.site, _action_graph()])
	var rejected: Dictionary = PhaseBattle.validate_siege_metadata(source_copy)
	if not _check(not rejected.ok and before_bytes == var_to_bytes([slot.control, action_owner.terrain.site, _action_graph()]), "invalid siege version rejects without changing the successful original owner", rejected): return false
	phase_observations.append({"phase": expected, "battle_id": battle.id, "source": battle.siege.source.duplicate(true), "source_sha256": battle.siege.source_sha256,
		"arrivals": battle.siege.arrivals.duplicate(true), "actual_capture": SiteSettlement.capture_sample(action_owner), "actual_fall": SiteSettlement.record(action_owner.terrain).fall_record.duplicate(true)})
	return true

func _partial_ready() -> bool:
	return not _phase_battle().is_empty() and str(_phase_battle().phase) == phase_expected

func _phase_reopen() -> bool:
	var source_battle: Dictionary = _phase_battle().duplicate(true)
	if not await _reopen_actual_partial(): return false
	if not _check(source_battle == _phase_battle(), "selected complete positive reopen preserves phase, RNG, paid source metadata and pending receipts", {"source": source_battle, "restored": _phase_battle()}): return false
	return _check(_phase_infantry() != null, "positively restored complete original graph retains the arrived team owner")

func _phase_fault_original_source() -> bool:
	if phase_case == "flight_crew_invalid":
		for identity: int in action_context.crew:
			var person: Dictionary = action_owner.site_controller.person_actions._person(identity, false)
			person.owner.apply_unit_contact(int(person.unit), {"result": {"hp": 1.0, "stun": 110.0, "guard_break": false}, "shield": false, "environmental": true})
			if not _check(float(person.owner.combat_hot_get(int(person.unit), &"ko", 0.0)) > 0.0, "original contact incapacitates the actual released-shot crew without erasing its paid flight", identity): return false
	elif phase_case in ["flight_wreck", "flight_removed"]:
		var wrecked: Dictionary = SiteRuntime.damage_siege_vehicle(action_owner.terrain, str(action_context.key), float(_action_vehicle().hp))
		if not _check(wrecked.ok and float(_action_vehicle().hp) == 0.0 and not action_owner.siege_projectiles.is_empty(), "original structural damage wrecks the real source while the paid flight remains", wrecked): return false
	else:
		var stopped: Dictionary = action_owner.site_controller.vehicles.order_siege(str(action_context.key), "stop", {}, int(action_context.commander), true)
		if not _check(stopped.ok, "original stop retains the paid flight and recovery", stopped): return false
	if not _action_step(): return false
	if not _check(not action_owner.siege_projectiles.is_empty(), "paid original flight still exists after actual source-fault completion"): return false
	if phase_case == "flight_removed":
		var vehicle := _action_vehicle()
		if not _check(vehicle.action.is_empty() and vehicle.move.is_empty() and vehicle.crew_slots.is_empty() and vehicle.cargo.is_empty() and vehicle.holder.item_ids.is_empty(), "real original wreck release completes all legal source-removal guards", vehicle): return false
		var removed: Dictionary = SiteRuntime.remove_siege_vehicle(action_owner.terrain, str(action_context.key), int(vehicle.team_id), func(cell: Vector2i) -> bool: return action_owner.site_controller.vehicles._people_block(cell))
		if not _check(removed.ok and not action_owner.terrain.site.vehicles.has(str(action_context.key)) and not action_owner.siege_projectiles.is_empty(), "existing original team-owned removal legally clears the empty source without deleting its released projectile", removed): return false
	report["paid_source_fault"] = {"case": phase_case, "actual_flight_id": phase_flight_id, "source_present": action_owner.terrain.site.vehicles.has(str(action_context.key)), "raw_paid_source": phase_flight_snapshot}
	return true

func _phase_same_flight() -> bool:
	if not _check(action_owner.siege_projectiles.size() == 1, "reopened original graph retains exactly one paid flight"): return false
	var flight: Dictionary = action_owner.siege_projectiles[0]
	for field: String in ["attack_id", "source_vehicle", "kind", "rule", "rule_version", "source_cell", "faction", "origin", "goal", "screen_origin", "screen_goal", "budget"]:
		if not _check(flight[field] == phase_flight_snapshot[field], "selected paid original flight keeps immutable field " + field): return false
	return _check(str(flight.attack_id) == phase_flight_id and int(action_owner.siege_shots) == 1, "source loss/reopen creates no extra shot identity")

func _phase_player_intervene() -> bool:
	if not _check(phase_topology == "closed", "positive player phase case uses a legally reachable true fortification"): return false
	if phase_observe in ["assault", "capture"]:
		var attacked: Dictionary = action_owner.site_controller.vehicles.order_siege(str(action_context.key), "attack", action_context.target, int(action_context.commander), true)
		if not _check(attacked.ok, "original finite engine creates the real breach before the player approaches", attacked): return false
		if not await _action_until(func() -> bool: return int(_action_vehicle().next_attack_seq) == action_initial_sequence + 1, "one original real round is released before the incoming player route"): return false
		var stopped: Dictionary = action_owner.site_controller.vehicles.order_siege(str(action_context.key), "stop", {}, int(action_context.commander), true)
		if not _check(stopped.ok, "true original stop retains the already paid shot and recovery", stopped): return false
		if not await _action_until(func() -> bool: return action_owner.siege_projectiles.is_empty() and _action_vehicle().action.is_empty(), "actual original paid breach and recovery finish"): return false
		if not _check(_actual_target_hp(action_context.target) == 0.0 and action_owner.siege_shots == 1, "real impact opens the original entry with one finite shot"): return false
		var infantry := _phase_infantry()
		var approached: Dictionary = infantry.issue_combat_order(infantry.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(22, 27))
		if not _check(approached.ok, "true incoming formation approaches just outside the original capture zone", approached): return false
		if not await _action_until(func() -> bool: return _phase_infantry()._combat_move_plan == null and _phase_infantry().moving_member_count() == 0, "actual formation completes its real near-zone approach"): return false
		var held: Dictionary = _phase_infantry().issue_combat_order(_phase_infantry().current_commander, TerrainArmy.CombatOrder.HOLD)
		if not _check(held.ok and int(SiteSettlement.capture_sample(action_owner).attacker) < 0, "original noncontesting HOLD has not paid any future capture", held): return false
	var actual_player := lab.controlled_person_id()
	var source_player: Dictionary = lab._original_person_target(actual_player)
	if not _check(not source_player.is_empty(), "original active player body exists before the real departure"): return false
	var departed: Dictionary = RegionTravelSite.depart(controller)
	if not _check(departed.ok, "actual original player departure uses the existing guarded full-source caller", departed): return false
	var departure_generation := int(slot._marker.generation)
	var departure_game := float(slot.control.logical_game_seconds)
	var player_token := str(slot.region_travel_journey().token)
	phase_panel = PhasePanel.new()
	root.add_child(phase_panel)
	phase_panel.setup(phase_panel)
	phase_panel.set_process(false)
	var opened: Dictionary = phase_panel.start({"world_id": world_id, "slot_id": "main", "manifest": manifest_path})
	if not _check(opened.ok and is_instance_valid(phase_panel._original_adapter_host), "same production RegionTravelPanel restores the actual original complete map host", opened): return false
	lab = phase_panel._original_adapter_host
	controller = lab.site_controller
	slot = phase_panel.slot
	var host_bind: Dictionary = lab.region_bind_receipt(lab.terrain)
	if not _check(lab.restore_only and controller.region_slot == slot and host_bind.get("complete", false)
		and int(slot._marker.generation) == departure_generation and float(slot.control.logical_game_seconds) == departure_game
		and str(slot.region_travel_journey().token) == player_token and slot.region_original_travel_interval.get_object() == lab, "actual selected map host owns the sole original world/party interval without a replay", host_bind): return false
	var selected: Dictionary = slot.region_travel_party()
	if not _check(selected.ok, "original map selects the same real player party", selected): return false
	var player_reference: Dictionary = selected.party.content.travel_identity.refs.person[str(actual_player)].duplicate(true)
	var current: Dictionary = slot.region_travel_status()
	var route_context: Dictionary = slot.prepare_region_route_context(null, selected.party)
	if not _check(route_context.ok, "actual original party route derives its genuine effective navigation", route_context): return false
	var search := RegionRoute.Search.new()
	search.source = slot.source
	search.start_site = current.site
	search.start_component = int(current.component)
	search.goal_site = action_coordinate
	search.context = route_context.context
	var route: Dictionary = search.run()
	if not _check(route.ok, "same real route producer finds the original incoming ground direction", route): return false
	var planned: Dictionary = slot.set_region_travel_plan(route.steps)
	if not _check(planned.ok, "original Slot admits its independently produced player route", planned): return false
	var restored: Dictionary = lab._region_gameplay_owner_lab(str(_phase_battle().site_id), "cold_exact")
	if not _check(restored.ok and restored.lab is TerrainLab, "same map host positively restores the whole original siege owner", restored): return false
	action_owner = restored.lab
	_freeze(action_owner)
	var activated := phase_observe == "siege"
	for iteration: int in range(18000):
		current = slot.region_travel_status()
		if not _check(current.ok, "actual ongoing player route has one original status", current): return false
		if slot.has_meta(&"region_player_materialized") or bool(current.get("arrived", false)): break
		if not activated:
			var selected_now: Dictionary = slot.region_travel_party()
			if not _check(selected_now.ok, "same actual party remains selected during the phase approach"): return false
			var actual_speed := maxf(0.000001, float(selected_now.party.speed_mps))
			var remaining := float(current.remaining_metres) / actual_speed
			var due := remaining <= (30.0 if phase_observe == "capture" else 0.5)
			if due:
				var original_order: Dictionary
				if phase_observe == "breach": original_order = action_owner.site_controller.vehicles.order_siege(str(action_context.key), "attack", action_context.target, int(action_context.commander), true)
				else:
					var infantry := _phase_infantry()
					original_order = infantry.issue_combat_order(infantry.current_commander, TerrainArmy.CombatOrder.MOVE if phase_observe == "capture" else TerrainArmy.CombatOrder.ATTACK, Vector2i(22, 26) if phase_observe == "capture" else TerrainArmy.INVALID_CELL)
				if not _check(original_order.ok, "true existing original captain accepts the scenario's current command before the real incoming endpoint", original_order): return false
				activated = true
		var advanced: Dictionary = slot.advance_region_travel(1)
		if not _check(advanced.ok, "existing map caller accepts one true common Site/party interval", advanced): return false
		if not slot.region_player_barrier().is_empty() or slot.has_meta(&"region_player_materialized"): break
		if iteration % 60 == 0: await process_frame
	if not _check(activated, "requested phase came from a real accepted original command"): return false
	current = slot.region_travel_status()
	if not _check(slot.has_meta(&"region_player_materialized") or bool(current.get("arrived", false)), "actual producer reaches a genuine player arrival or physical encounter endpoint", current): return false
	var endpoint_due: Dictionary = slot.consume_due_region_events()
	if not _check(endpoint_due.ok, "same actual queued endpoint is consumed by the existing public zero-time P0 owner", endpoint_due): return false
	current = slot.region_travel_status()
	if not _check(current.ok, "same accepted original endpoint remains readable after its true consumer", current): return false
	var endpoint_body: Dictionary = action_owner._original_person_target(action_owner.controlled_person_id())
	var materialized_cell: Vector2i = endpoint_body.get("cell", TerrainArmy.INVALID_CELL)
	if not _check(slot.has_meta(&"region_player_materialized") and not endpoint_body.is_empty()
		and action_owner.terrain.contains(materialized_cell) and action_owner.terrain.is_walkable(materialized_cell)
		and not SiteSettlement.capture_zone(action_owner.terrain).has(materialized_cell), "existing original materializer has placed the true player body at its incoming ground entry before visible bind", endpoint_body.get("cell")): return false
	var event_clock := {"game": float(slot.control.logical_game_seconds), "action": float(slot.control.fire_clock.action_seconds), "sequence": int(slot.control.fire_clock.sequence)}
	var checkpoint: Dictionary = slot.checkpoint_region_travel() if current.get("pending", false) else action_owner._region_gameplay_endpoint_checkpoint({"phase_observer": true})
	if not _check(checkpoint.ok, "original common publisher stores the real player endpoint and paid siege graph together", checkpoint): return false
	var source_battle: Dictionary = _phase_battle().duplicate(true)
	# Use the real original visible Controller world-open, as the scene handoff
	# does. This is a positive selected bind, not a manually completed P0 event.
	var visible := _shell()
	if not _check(visible != null, "actual visible original main shell exists"): return false
	visible.restore_only = false
	var visible_open: Dictionary = visible.site_controller.open_fixed_world(manifest_path, world_id, "main", Vector2i(-1, -1), false)
	for retry: int in range(200000):
		if str(visible_open.get("code", "")) != "PENDING" and not visible.site_controller.region_operation_pending(): break
		visible_open = visible.site_controller.resume_region_operation()
		if retry % 60 == 0: await process_frame
	if not _check(visible_open.ok and not visible_open.get("travel_handoff", false), "actual production world-open completes the selected siege Site instead of inventing a party body", visible_open): return false
	_freeze(visible)
	lab = visible
	controller = visible.site_controller
	slot = controller.region_slot
	action_owner = visible
	var consumed: Dictionary = slot.consume_due_region_events()
	if not _check(consumed.ok and consumed.get("complete", false), "true visible bind and original P0 consumers complete the selected player endpoint", consumed): return false
	if not _check(float(slot.control.logical_game_seconds) == float(event_clock.game) and float(slot.control.fire_clock.action_seconds) == float(event_clock.action)
		and int(slot.control.fire_clock.sequence) == int(event_clock.sequence) and str(slot.control.active_site_id) == str(visible.terrain.site.id), "positive visible handoff pays no second interval, flight or capture time"): return false
	if not _phase_observe_actual(phase_observe): return false
	var scope: Dictionary = PhaseBattle.scoped_controlled_person(visible)
	var controlled := visible.controlled_person_id()
	if not _check(scope.ok and int(scope.person_id) == controlled and not _phase_battle().attackers.has(controlled) and not _phase_battle().defenders.has(controlled), "same real player scope stays excluded from formula roster after positive P0 bind", scope): return false
	var actual_body: Dictionary = visible._original_person_target(controlled)
	if not _check(not actual_body.is_empty() and actual_body.cell == materialized_cell and visible.terrain.contains(actual_body.cell)
		and visible.terrain.is_walkable(actual_body.cell) and not SiteSettlement.capture_zone(visible.terrain).has(actual_body.cell), "actual visible body retains its selected original materializer entry outside the center zone", actual_body.get("cell")): return false
	report["player_intervention"] = {"phase": phase_observe, "real_player_reference": player_reference, "route_steps": route.steps, "source_battle": source_battle,
		"selected_battle": _phase_battle().duplicate(true), "actual_controlled": controlled, "actual_cell": actual_body.cell, "original_materialized_entry": materialized_cell, "clocks": event_clock,
		"actual_visible_bind": visible.region_bind_receipt(visible.terrain), "original_endpoint_consumer": endpoint_due, "event_consumer": consumed}
	return true

func _finish(ok: bool = true, message: String = "") -> void:
	if finished: return
	finished = true
	failed = failed or not ok
	if not message.is_empty(): printerr(message)
	paused = false
	if is_instance_valid(phase_panel): phase_panel.free()
	for scene: TerrainLab in capture_scenes:
		if is_instance_valid(scene): scene.free()
	var current: Variant = JSON.parse_string(FileAccess.get_file_as_string(Entry.LAST_WORLD)) if FileAccess.file_exists(Entry.LAST_WORLD) else null
	if current is Dictionary and str(current.get("world_id", "")).begins_with("r0_siege_action_%d_" % OS.get_process_id()):
		if last_world_exists:
			var restore := FileAccess.open(Entry.LAST_WORLD, FileAccess.WRITE); restore.store_buffer(last_world_bytes); restore.close()
		else: DirAccess.remove_absolute(ProjectSettings.globalize_path(Entry.LAST_WORLD))
	TerrainArmy.release_contact_source()
	var evidence := {"failed": failed, "checks": checks, "cases": report, "phase_trace": phase_observations, "checks_evidence": action_evidence,
		"scope": "true dispatched NPC arrival, four original exact GD siege phases, paid finite flight/source-fault full selected positive restore; not whole C02/C06/C07/C09, Native or casualty calibration"}
	var file := FileAccess.open(out.path_join("original_siege_phase_receipt.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(evidence, "\t", true, true)); file.close()
	print("REGION_SIEGE_ORIGINAL_PHASE_", "FAILED" if failed else "PASS", " ", JSON.stringify(evidence))
	quit(1 if failed else 0)
