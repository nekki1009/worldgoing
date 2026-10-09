extends "res://scripts/tests/region_npc_ship_lawful_arrival_unload_physical_test.gd"
## Two independently committed original routes share the actual coast owner.
## A paid real gate closes the foot source leg while the sea hull lane stays open.
const MultiBattle = preload("res://scripts/region_lab/region_gameplay_battle.gd")
var multi_gate := ""
var multi_gate_operator := 0
var multi_foot_team := 0
var multi_foot_person := 0
var multi_foot_token := ""
var multi_foot_refs: Dictionary = {}
var multi_blocked_event: Dictionary = {}
var multi_enemy_id := 0
var multi_arrived_person := 0
var multi_melee: Array[Dictionary] = []
var multi_static_contact: Dictionary = {}

func _multi_center_genesis(original: TerrainLab) -> bool:
	var data: TerrainData = original.terrain
	for key: String in data.resource_base: Env.change(data, key, {"cleared": true, "remaining": 0})
	data.site.capacity = 100000
	for item: String in Env.ITEM_NAMES: data.site.inventory[item] = 1000
	if not _check(SiteRuntime.initialize_item_storage(data.site).ok and original.character.place(Vector2i(20, 25), true), "finite initial destination Depot and actual founder occupy genuine coast dry ground before center construction"): return false
	var layout: Dictionary = SiteRuntime.building_cells(data, "settlement_center", Vector2i(20, 30), Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	if not _check(layout.ok, "original complete settlement center geometry lies entirely on actual coast land", layout): return false
	var cells: Array[int] = []; cells.assign(layout.cells)
	var before: Dictionary = data.site.inventory.duplicate(true)
	var founded: Dictionary = Settlement.found(original, original.controlled_person_id(), cells, {"layout_version": 1, "quarter": 0}, Callable(), "原海岸增援中心")
	if not _check(founded.ok, "original founder transaction reserves the finite real center materials", founded): return false
	var feature: Dictionary = data.site.features[str(founded.feature)]
	for item: String in feature.cost:
		if not _check(int(data.site.inventory[item]) == int(before[item]) - int(feature.cost[item]), "initial original center material debit is exact", item): return false
	var task := {"version": 2, "zone": -1, "target": "feature:" + str(founded.feature), "action": "construct", "work_cell": int(feature.entrance), "cell": int(feature.entrance), "mode": "work", "progress": 0.0, "status": "", "work_slot": -1}
	SiteRuntime._feature_work(data, str(founded.feature), float(feature.work), Callable(), Callable(), task, {}, 20, 1)
	return _check(feature.stage == "complete" and int(data.site.settlement.level) == 1 and original.character.place(Vector2i(19, 29), true) and int(Settlement.capture_sample(original).attacker) == -1, "original GENESIS work completes the real center and its actual live founder protects the true capture zone")

func _ship_build_barrier(anchor: Vector2i, length: int) -> bool:
	# The same finite original wall has one authored gate span, closed at birth.
	var begin := anchor.y
	var end := anchor.y + length
	if begin < 48 and not super._ship_build_barrier(Vector2i(anchor.x, begin), mini(end, 48) - begin): return false
	if end > 52 and not super._ship_build_barrier(Vector2i(anchor.x, maxi(begin, 52)), end - maxi(begin, 52)): return false
	if begin < 52 and end > 48 and multi_gate.is_empty() and not _multi_build_initial_gate(): return false
	return true

func _multi_build_initial_gate() -> bool:
	var data: TerrainData = lab.terrain
	var layout: Dictionary = SiteRuntime.building_cells(data, "gate", Vector2i(24, 48), Vector2i(3, 4), {"quarter": 3, "owner_faction": 1})
	if not _check(layout.ok, "finite initial original gate occupies the declared wall span on actual dry ground", layout): return false
	var options: Dictionary = layout.options.duplicate(true)
	options.owner_faction = 1
	var built: Dictionary = SiteRuntime.request_build(data, "gate", layout.cells, Callable(), options)
	if not _check(built.ok, "original gate allocator pays actual finite materials once", built): return false
	multi_gate = str(built.feature)
	var feature: Dictionary = data.site.features[multi_gate]
	var task := {"version": 2, "zone": -1, "target": "feature:" + multi_gate, "action": "construct", "work_cell": int(feature.entrance), "cell": int(feature.entrance), "mode": "work", "progress": 0.0, "status": "", "work_slot": -1}
	SiteRuntime._feature_work(data, multi_gate, float(feature.work), Callable(), Callable(), task, {}, 20, 1)
	return _check(feature.stage == "complete" and not bool(feature.gate.open), "original GENESIS construction leaves the true gate closed before the inherited physical barrier check")

func _setup_action_world() -> bool:
	if not super._setup_action_world(): return false
	var data: TerrainData = lab.terrain
	var feature: Dictionary = data.site.features[multi_gate]
	lab._ensure_army_slots(4)
	var foot: TerrainArmy = lab.combat_armies[2]
	foot.faction_id = 1; foot.roster_size = 1
	var foot_cells: Array[Vector2i] = [Vector2i(30, 49)]
	if not _check(foot.deploy_at(data, null, null, foot_cells) and foot.enable_combat(false, 0), "initial original allocator births one full finite foot formation east of the real closed gate"): return false
	lab.site_controller.initialize_team_items(foot)
	multi_foot_team = foot.team_id; multi_foot_person = foot.combat_identity(foot.current_commander)
	var operator: TerrainArmy = lab.combat_armies[3]
	operator.faction_id = 1; operator.roster_size = 1
	var operator_cells: Array[Vector2i] = [Vector2i(27, 49)]
	if not _check(operator.deploy_at(data, null, null, operator_cells) and operator.enable_combat(false, 0), "initial original allocator births the actual gate operator at the original operation square"): return false
	lab.site_controller.initialize_team_items(operator)
	multi_gate_operator = operator.combat_identity(operator.current_commander)
	data.site.army_next_team = lab._next_army_identity()
	for team: TerrainArmy in [foot, operator]:
		for unit: int in team.combat_units.size(): data.site.equipment_nations[sea_nation_id].members.append(team.combat_identity(unit))
	if not _check(SiteRuntime._gate_operator(data, feature, multi_gate_operator, lab.site_controller._building_person_query).ok, "true gate owner, actual qualified NPC and exact operation geometry admit the original public gate caller"): return false
	var goal: Dictionary = _sea_goal()
	if not goal.ok or not _multi_center_genesis(goal.lab): return false
	var destination: TerrainLab = goal.lab
	destination._ensure_army_slots(3)
	var hostile: TerrainArmy = destination.combat_armies[2]
	hostile.faction_id = 2; hostile.roster_size = 1
	var hostile_cells: Array[Vector2i] = [Vector2i(98, 50)]
	if not _check(hostile.deploy_at(destination.terrain, null, null, hostile_cells) and hostile.enable_combat(false, 0), "initial actual hostile military body is adjacent to the true east entry through genuine original ground geometry"): return false
	destination.site_controller.initialize_team_items(hostile)
	multi_enemy_id = hostile.combat_identity(0)
	destination.terrain.site.army_next_team = destination._next_army_identity()
	if not _check(action_paid == 0.0 and action_game_paid == 0.0 and controller.checkpoint_region_internal("region_checkpoint", true).ok, "finite boats, gate, foot cohort, hostile center and real Nation birth precede every original productive interval"): return false
	var begun: Dictionary = hostile.issue_combat_order(hostile.current_commander, TerrainArmy.CombatOrder.ATTACK)
	if not _check(begun.ok, "actual hostile captain accepts the original siege attack before its real registry publication", begun): return false
	var siege: Dictionary = slot.refresh_original_region_siege_battle(destination)
	if not _check(siege.ok and not str(siege.get("battle_id", "")).is_empty(), "actual destination bodies and center create the original shared siege registry", siege): return false
	var held: Dictionary = hostile.issue_combat_order(hostile.current_commander, TerrainArmy.CombatOrder.HOLD)
	return _check(held.ok, "same actual hostile captain holds its real body for the independent arriving contact through the original public order", held)

func _multi_source_gate() -> Dictionary:
	return lab.terrain.site.features.get(multi_gate, {})

func _multi_gate_to(open: bool) -> bool:
	var changed: Dictionary = SiteRuntime.request_gate(lab.terrain, multi_gate, open, multi_gate_operator, lab.site_controller._building_person_query, lab.site_controller.reserves_cell)
	if not _check(changed.ok, "actual original NPC begins public paid gate operation without changing any terrain or gate flag", changed): return false
	return await _ship_until(func() -> bool: return bool(_multi_source_gate().gate.open) == open and str(_multi_source_gate().gate.pending).is_empty(), "original accepted common work completes the true gate operation")

func _multi_prepare_routes() -> bool:
	if not await _multi_gate_to(true): return false
	if not _check(not lab.terrain.path_between(Vector2i(30, 49), Vector2i(0, 50)).is_empty(), "actual paid original open gate makes the foot source leg legally reachable"): return false
	# Keep the inherited genuine unknown-target refusal before its first
	# original observation; that same observation then also admits the foot route.
	if not _sea_dispatch(): return false
	var observed: Dictionary = slot.record_region_officer_geography_observation(lab, sea_nation_head, sea_goal_coordinate)
	if not _check(observed.ok, "original strategic head observes the actual common destination before either dispatch", observed): return false
	var foot: TerrainArmy
	for team: TerrainArmy in lab.combat_armies:
		if team.team_id == multi_foot_team: foot = team
	if not _check(foot != null and foot.command_eligible(foot.current_commander), "original finite foot captain resolves independently of both boats"): return false
	var component := RegionTravelSite.start_component(slot, Vector2i.ZERO, Vector2i(30, 49), lab.terrain)
	multi_foot_token = "c06_required_foot_%d" % OS.get_process_id()
	var prepared: Dictionary = slot.prepare_npc_region_dispatch(lab, sea_nation_id, multi_foot_team, sea_goal_coordinate, component, [], multi_foot_token)
	if not _check(prepared.ok and prepared.party.mode == "land" and prepared.party.person_ids == [multi_foot_person] and prepared.party.content.vehicles.is_empty() and prepared.plan.steps.size() == 2 and RegionRoute.entry_cell(prepared.plan.steps.back()) == Vector2i(99, 50), "existing Nation compiles a genuine one-row full-formation foot route with its own exact east entry", prepared.get("code")): return false
	multi_foot_refs = prepared.party.content.travel_identity.refs.duplicate(true)
	var stock := var_to_bytes(lab.terrain.site.inventory)
	var actor_ref: Dictionary = lab.terrain.site.travel_identity.refs.person[str(ship_actor_id)].duplicate(true)
	if not _check(slot.commit_npc_region_dispatch(prepared).ok and stock == var_to_bytes(lab.terrain.site.inventory) and actor_ref == lab.terrain.site.travel_identity.refs.person[str(ship_actor_id)] and lab.controlled_person_id() == ship_actor_id, "actual foot dispatch removes only its real movers and preserves unrelated source stock and human body"): return false
	if not await _multi_gate_to(false): return false
	return _check(lab.terrain.path_between(Vector2i(30, 49), Vector2i(0, 50)).is_empty(), "subsequent true paid closed gate blocks that original foot source leg while sea retains its independent water geometry")

func _multi_land_blocked() -> bool:
	var selected: Dictionary = slot._region_npc_party(multi_foot_token)
	if not selected.ok or not selected.party.upkeep.has("route_blocked"): return false
	for event: Dictionary in slot.region_registry().events:
		if event.payload.get("token") == multi_foot_token and event.payload.get("navigation_result", {}).get("navigation_blocked", false): multi_blocked_event = event.duplicate(true)
	return not multi_blocked_event.is_empty()

func _multi_blocked_scope() -> bool:
	var selected: Dictionary = slot._region_npc_party(multi_foot_token)
	var owner: Dictionary = lab.prepare_region_party_original_owner(multi_foot_token, selected.party, slot)
	var receipt: Dictionary = multi_blocked_event.payload.navigation_result
	if not _check(selected.ok and owner.ok and receipt.no_effect and receipt.navigation_blocked and receipt.complete and multi_blocked_event.status == "complete" and slot.region_registry().parties[multi_foot_token].phase == "travelling" and selected.party.upkeep.route_node.site == [0, 0], "actual blocked-land original event completes with truthful navigation no-effect while the whole foot body keeps its source node", receipt): return false
	var goal: Dictionary = _sea_goal()
	var own: Dictionary = goal.lab.terrain.site.travel_identity.refs.person
	for identity: String in own:
		if own[identity] == multi_foot_refs.person[str(multi_foot_person)]: return _check(false, "blocked foot body must stay outside destination capture and battle owners")
	var sea: Dictionary = _sea_selected()
	return _check(sea.ok and sea.party.mode == "sea" and not sea.party.upkeep.has("route_blocked") and lab.controlled_person_id() == ship_actor_id, "same actual closed land edge leaves the separately admitted true sea approach open and preserves human control")

func _sea_graphs(in_transit: bool) -> Dictionary:
	var graphs: Dictionary = super._sea_graphs(in_transit)
	if graphs.is_empty(): return graphs
	var reference: Dictionary = slot.region_registry().parties.get(multi_foot_token, {})
	if reference.get("phase") == "travelling":
		var selected: Dictionary = slot._region_npc_party(multi_foot_token)
		if not selected.ok: return {}
		var owner: Dictionary = lab.prepare_region_party_original_owner(multi_foot_token, selected.party, slot)
		if not owner.ok: return {}
		var captured: Dictionary = slot._region_capture_party_graph(multi_foot_token, selected.party)
		if not _check(captured.ok and not captured.original_live_graph.is_empty(), "same common checkpoint captures the full independent blocked foot party graph", captured): return {}
		graphs["foot_party"] = {"selected": var_to_bytes(selected.party), "owners": captured.original_live_graph.owners.duplicate(true), "reference": reference.duplicate(true)}
	return graphs

func _multi_actual_exchange(first: int, second: int, result: Dictionary) -> void:
	if [mini(first, second), maxi(first, second)] != [mini(multi_arrived_person, multi_enemy_id), maxi(multi_arrived_person, multi_enemy_id)]: return
	multi_melee.append({"first": first, "second": second, "result": result.duplicate(true), "game": slot.control.logical_game_seconds, "action": slot.control.fire_clock.action_seconds, "sequence": slot.control.fire_clock.sequence})

func _multi_original_reinforcement() -> bool:
	if not await _multi_gate_to(true): return false
	if not await _ship_until(func() -> bool: return slot.region_registry().parties[multi_foot_token].phase == "entered", "original blocked route retry pays its true independent approach and full arrival after actual gate reopening"): return false
	var reference: Dictionary = slot.region_registry().parties[multi_foot_token]
	var goal: Dictionary = _sea_goal()
	var original: TerrainLab = goal.lab
	multi_arrived_person = int(reference.arrival_mapping.maps.person[str(multi_foot_person)])
	var person: Dictionary = original.site_controller.person_actions._person(multi_arrived_person, false)
	if not _check(reference.destination_site == str(original.terrain.site.id) and person.cell == Vector2i(99, 50) and original.terrain.site.travel_identity.refs.person[str(multi_arrived_person)] == multi_foot_refs.person[str(multi_foot_person)] and original._region_bind_receipt_value.owners_restored and person.owner.combat_units.size() == 1, "true original independent entry capacity binds the entire same finite foot formation at its exact actual east entry"): return false
	for event: Dictionary in slot.region_registry().events:
		if event.payload.get("token") == multi_foot_token and event.payload.get("contact_receipt", {}).get("kind") == "npc_siege_channel": multi_static_contact = event.duplicate(true)
	if not _check(not multi_static_contact.is_empty() and multi_static_contact.kind == "reinforcement" and multi_static_contact.status == "complete" and float(multi_static_contact.at) == float(reference.arrival_game_seconds), "original Slot consumes its own true earliest NPC static siege-contact event at the exact accepted foot insertion point", multi_static_contact): return false
	var contact: Dictionary = multi_static_contact.payload.contact_receipt
	var witness: Dictionary = contact.witness
	var actual_enemy: Dictionary = original._original_person_target(multi_enemy_id)
	if not _check(witness.party_token == multi_foot_token and witness.person_id == multi_enemy_id and witness.person_cell == [98, 50] and witness.entry == [99, 50] and witness.party_reference == multi_foot_refs.person[str(multi_foot_person)] and witness.static_reference == original.terrain.site.travel_identity.refs.person[str(multi_enemy_id)] and witness.party_source is Dictionary and not witness.party_source.is_empty() and witness.navigation_revision >= 0 and witness.source_generation <= int(slot._marker.generation) and witness.runtime_revision <= int(slot.region_registry().revision) and contact.first.position.mode == "land" and contact.second.position.mode == "land" and float(contact.at) == float(multi_static_contact.at) and not actual_enemy.is_empty() and actual_enemy.cell == Vector2i(98, 50) and original.terrain.can_attack_across(person.cell, actual_enemy.cell), "real source/body/entry/navigation witness and current original body prove earliest lawful ground contact before later local melee work", contact): return false
	var callback := Callable(self, "_multi_actual_exchange")
	if not original.exchange_resolved.is_connected(callback): original.exchange_resolved.connect(callback)
	var team: TerrainArmy = person.owner
	var move: Dictionary = team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(98, 51))
	if not _check(move.ok, "same real arrived captain orders public formation MOVE toward the actual local hostile body", move): return false
	if not await _ship_until(func() -> bool:
		var current: Dictionary = original._original_person_target(multi_arrived_person)
		return not current.is_empty() and current.cell == Vector2i(98, 51) and team.moving_member_count() == 0, "actual paid original formation completes its real local melee approach"): return false
	var held: Dictionary = team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.HOLD)
	if not _check(held.ok, "existing arrived captain stops the real complete foot formation before actual contact", held): return false
	var refreshed: Dictionary = slot.refresh_original_region_siege_battle(original)
	if not _check(refreshed.ok, "original siege owner refreshes its actual newly arrived body roster", refreshed): return false
	var battle: Dictionary = slot.region_registry().battles[str(refreshed.battle_id)]
	var resolved: Dictionary = MultiBattle.resolve_people(original, battle)
	if not _check(battle.defenders.has(multi_arrived_person) and not battle.attackers.has(multi_arrived_person) and battle.attackers.has(multi_enemy_id) and resolved.ok and resolved.people[multi_arrived_person].legal_targets.has(multi_enemy_id), "real original body geometry and opposite battle sides admit the actual hostile melee target rather than food flags, rank or shared component", resolved): return false
	var attacked: Dictionary = team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.ATTACK, TerrainArmy.INVALID_CELL, multi_enemy_id)
	if not _check(attacked.ok, "same actual NPC captain issues its original public attack order for the real legal hostile body", attacked): return false
	if not await _ship_until(func() -> bool: return not multi_melee.is_empty(), "original shared paid step emits a true accepted melee resolution between the physically arrived reinforcement and actual hostile body"): return false
	if not await _sea_reopen(false): return false
	return _check(not multi_melee.is_empty() and multi_blocked_event.payload.navigation_result.no_effect and lab.controlled_person_id() == ship_actor_id, "true melee and full selected cold preserve blocked-route history and actual human control")

func _run() -> void:
	RegionTravelSite.scene_handoff = false; RegionRoute.clear_memory_cache()
	if not _write_manifest() or not _setup_action_world(): _finish(); return
	if not _ship_public_cargo(): _finish(); return
	if not await _ship_board(0, true) or not await _ship_public_food() or not await _ship_board(1, false): _finish(); return
	if not _check(not _ship_supply().locations.has("vehicle:" + ship_ids[1]), "second true boat still has no invented own food pool"): _finish(); return
	if not await _ship_helm(0, false) or not await _ship_helm(1, true) or not await _ship_open_sea_positive() or not await _ship_original_two_boat_closure(): _finish(); return
	if not await _multi_prepare_routes(): _finish(); return
	ship_observation = "region_sea"
	if not await _ship_until(_multi_land_blocked, "actual original closed land entry produces its genuine no-effect navigation receipt"): _finish(); return
	if not _multi_blocked_scope(): _finish(); return
	if not await _ship_until(_sea_partial, "same original sea ACTION lane reaches a physically projected partial hull despite the independent land block"): _finish(); return
	if not await _sea_reopen(true) or not _multi_blocked_scope(): _finish(); return
	var before := action_paid
	if not await _ship_until(func() -> bool: return slot.region_registry().parties[sea_token].phase == "entered", "actual independent sea route pays and fully binds its true adjacent arrival"): _finish(); return
	if not _check(action_paid > before and _sea_arrived(), "genuine distinct sea approach has positive accepted physical arrival"): _finish(); return
	if not _sea_food_conserved() or not await _sea_reopen(false) or not _sea_arrived(): _finish(); return
	if not _sea_food_conserved() or not await _arrival_public_unload(): _finish(); return
	if not await _multi_original_reinforcement(): _finish(); return
	report["food_reinforcement_multi_approach"] = {"blocked_foot_event": multi_blocked_event, "earliest_original_static_contact": multi_static_contact, "foot_reference": slot.region_registry().parties[multi_foot_token].duplicate(true), "sea_reference": slot.region_registry().parties[sea_token].duplicate(true), "lawful_finite_unload": arrival_unload_evidence, "original_physical_melee": multi_melee, "source_scope": "actual existing owners and required physical assertions authored; parser/runtime NOT_RUN"}
	_finish()

func _finish(ok: bool = true, message: String = "") -> void:
	if finished: return
	print("REGION_FOOD_REINFORCEMENT_MULTI_APPROACH_", "FAILED" if failed or not ok else "PASS", " ", JSON.stringify(report))
	super._finish(ok, message)
