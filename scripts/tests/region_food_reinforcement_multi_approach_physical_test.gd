extends "res://scripts/tests/region_npc_ship_lawful_arrival_unload_physical_test.gd"
## Two independently committed original routes share the actual coast owner.
## A paid real gate closes the foot source leg while the sea hull lane stays open.
## Crowd port (2026-11-08, Option C batch 1): every body is a crowd person (region_ship_finite_food_physical_test). The
## foot cohort and the gate operator are one-person crowd teams born with the ship teams; the destination's founder, heir
## and hostile are crowd people of the hot destination. A native melee has no exchange signal, so each hit on the pair
## is read from its native hit revision at the paid step that applied it.
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
var multi_static_before: Dictionary = {}
var multi_shore_faction := false
var multi_original: TerrainLab
var multi_pair_trace: Array[Dictionary] = []
var multi_pair_polls := 0
var multi_wait_impossible := ""
var multi_siege_id := ""
var multi_ko_probe: Dictionary = {}
var multi_hostile_team := 0
var multi_hit_revisions: Dictionary = {}

func _initialize() -> void:
	super()
	ship_faction = 1 # Explicit GENESIS scenario faction (OPUS72), see _multi_shore_faction.
	deadline = Time.get_ticks_msec() + 900000 # Nekki 2026-11-08 11:27Z (B): in-file 900 s, outer 960 s (07:48Z: 700/760; 10/26: 540/600). The full crowd run measured 744-762 s.

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_msec() > deadline: _finish(false, "900-second original multi-approach reinforcement deadline")
	return false

func _multi_center_genesis(original: TerrainLab) -> bool:
	var data: TerrainData = original.terrain
	for key: String in data.resource_base: Env.change(data, key, {"cleared": true, "remaining": 0})
	data.site.capacity = 100000
	for item: String in Env.ITEM_NAMES: data.site.inventory[item] = 1000
	if not _check(SiteRuntime.initialize_item_storage(data.site).ok and _multi_place_team(original, original.controlled_person_id(), Vector2i(20, 25)), "finite initial destination Depot and actual founder occupy genuine coast dry ground before center construction"): return false
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
	return _check(feature.stage == "complete" and int(data.site.settlement.level) == 1 and _multi_place(original, original.controlled_person_id(), Vector2i(19, 29)) and int(Settlement.capture_sample(original).attacker) == -1, "original GENESIS work completes the real center and its actual live founder protects the true capture zone")

## GENESIS placement of one crowd person (crowd_c2_natural_ammo_test _place): its native body and its formation's
## anchor move to the cell centre. No paid time passes.
func _multi_place(original: TerrainLab, identity: int, cell: Vector2i) -> bool:
	var site: Variant = original.crowd_site
	if site == null or not site.active or not original.terrain.is_walkable(cell): return false
	var owner: Variant = site.person_owner(identity)
	if not owner is CrowdPersonOwner: return false
	var at := Vector2(cell) + Vector2.ONE * 0.5
	return site.set_soldier_fields(owner.index_for_identity(identity), {"px": at.x, "py": at.y}) and site.set_formation_fields(owner.formation_index,
		{"cx": at.x, "cy": at.y, "goal_x": at.x, "goal_y": at.y, "origin_x": at.x, "origin_y": at.y, "ref_x": at.x, "ref_y": at.y, "ref_valid": true, "ai_enabled": false})

## GENESIS placement of a whole crowd team around near: the named person at near, every other member on its own free
## walkable cell beside it.
func _multi_place_team(original: TerrainLab, identity: int, near: Vector2i) -> bool:
	var site: Variant = original.crowd_site
	var owner: Variant = site.person_owner(identity) if site != null and site.active else null
	if not owner is CrowdPersonOwner or not _multi_place(original, identity, near): return false
	var used: Array[Vector2i] = [near]
	for index: int in owner.records:
		var other: int = owner.combat_identity(index)
		if other == identity: continue
		var cell := Vector2i(-1, -1)
		for radius: int in range(1, 6):
			for y: int in range(-radius, radius + 1):
				for x: int in range(-radius, radius + 1):
					var candidate := near + Vector2i(x, y)
					if cell.x < 0 and not used.has(candidate) and original.terrain.contains(candidate) and original.terrain.is_walkable(candidate): cell = candidate
		if cell.x < 0: return false
		used.append(cell)
		var at := Vector2(cell) + Vector2.ONE * 0.5
		if not site.set_soldier_fields(owner.index_for_identity(other), {"px": at.x, "py": at.y}): return false
	return true

## Explicit GENESIS scenario faction (OPUS72). Both approaches reinforce the
## destination center of faction 1, so the whole shore side is faction 1: the
## shore person's start team, the ship crew and the transfer recipient. It is
## checked at the first barrier request, after the inherited genesis births those
## teams and before any structure or paid interval, so the walls share the gate's
## owner faction. Otherwise the sea crew enters the destination as a third faction
## (0) and the original siege owner rightly refuses the roster (EXACT_FACTION_TOPOLOGY).
## Crowd port: a native formation keeps its deploy faction, so the base deploys the
## shore side with ship_faction 1 (_initialize); this checks it.
func _multi_shore_faction() -> bool:
	multi_shore_faction = true
	var site: Variant = lab.crowd_site
	var shore: Variant = site.person_owner(ship_actor_id) if site != null and site.active else null
	var crew: Variant = _ship_team()
	var recipient: Variant = null
	if site != null and site.active:
		for owner: Variant in site.person_owners():
			if owner is CrowdPersonOwner and int(owner.team_id) == ship_resident_team_id: recipient = owner
	return _check(shore != null and crew != null and recipient != null and int(shore.faction_id) == 1 and int(crew.faction_id) == 1 and int(recipient.faction_id) == 1
		and action_paid == 0.0 and action_game_paid == 0.0,
		"explicit GENESIS scenario faction 1 covers the shore person, its crew and the transfer recipient before any structure or paid interval")

## The foot cohort east of the gate and the gate operator at its operation square, born with the ship teams.
func _ship_extra_teams() -> Array:
	var foot := _ship_side(1)
	var operator := _ship_side(1)
	if foot.is_empty() or operator.is_empty(): return []
	return [{"side": foot, "cells": [Vector2i(30, 49)]}, {"side": operator, "cells": [Vector2i(27, 49)]}]

func _ship_build_barrier(anchor: Vector2i, length: int) -> bool:
	if not multi_shore_faction and not _multi_shore_faction(): return false
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

func _ship_more_genesis() -> bool:
	if not super._ship_more_genesis(): return false
	var data: TerrainData = lab.terrain
	var feature: Dictionary = data.site.features[multi_gate]
	var foot: Variant = _crowd_owner_at(Vector2i(30, 49))
	if not _check(foot != null and int(foot.faction_id) == 1 and foot.records.size() == 1, "initial original allocator births one full finite foot formation east of the real closed gate"): return false
	multi_foot_team = int(foot.team_id); multi_foot_person = foot.combat_identity(int(foot.current_commander))
	var operator: Variant = _crowd_owner_at(Vector2i(27, 49))
	if not _check(operator != null and operator != foot and int(operator.faction_id) == 1 and operator.records.size() == 1, "initial original allocator births the actual gate operator at the original operation square"): return false
	multi_gate_operator = operator.combat_identity(int(operator.current_commander))
	for team: Variant in [foot, operator]:
		for unit: int in team.records: data.site.equipment_nations[sea_nation_id].members.append(team.combat_identity(unit))
	if not _check(SiteRuntime._gate_operator(data, feature, multi_gate_operator, lab.site_controller._building_person_query).ok, "true gate owner, actual qualified NPC and exact operation geometry admit the original public gate caller"): return false
	# Decision A (Nekki 2026-10-26): the destination center and its hostile body are
	# born later, after the founder stands the destination up hot
	# (_multi_destination_decision_a).
	return _check(action_paid == 0.0 and action_game_paid == 0.0 and controller.checkpoint_region_internal("region_checkpoint", true).ok, "finite boats, gate, foot cohort and real Nation birth precede every original productive interval")

## Decision A for the destination (Nekki 2026-10-26, same pattern as the phase and
## center tests). Since P6 S1 a cold Site opened after world genesis has no people,
## and only the controlled person founds a settlement (site_settlement.gd found).
## The shore Actor has finished its own public ship work and left the crew. It walks
## out through the same paid gate, travels to the destination, founds the center
## there while that Site is hot, and hands living control to a newly born family
## member, who returns to the shore Site. The founder stays at the destination as
## its living defender; from here on the shore Site's human control is the heir.
## The paid gate opening and the Region journeys now come before the destination's
## birth, so its zero-paid gate is measured from the founder's departure instead.
func _multi_destination_decision_a() -> bool:
	if not await _multi_gate_to(true): return false
	var paid := [action_paid, action_game_paid]
	var goal_site := Grid.site_id(str(slot.pin.atlas_id), sea_goal_coordinate)
	if not await _multi_travel_controlled(sea_goal_coordinate): return false
	lab.simulation_speed = action_speed
	if not _check(lab.controlled_person_id() == ship_actor_id and str(slot.control.active_site_id) == goal_site and str(lab.terrain.site.id) == goal_site,
		"the same shore Actor arrives at and controls the hot destination Site"): return false
	# The founder's start team was deployed with the shore faction 1 (_initialize).
	if not _multi_center_genesis(lab): return false
	center_founder = lab.controlled_person_id()
	if not _birth_successor(): return false
	if not await _hand_over_and_leave(Vector2i.ZERO): return false
	lab.simulation_speed = action_speed
	action_owner = lab
	ship_actor_id = lab.controlled_person_id()
	if not _check(ship_actor_id == center_heir and str(slot.control.active_site_id) == str(lab.terrain.site.id) and str(slot.control.active_site_id) != goal_site and not lab.controlled_target().is_empty(),
		"the living heir holds the shore Site's human control and the destination is cold", {"heir": center_heir, "controlled": ship_actor_id, "active": slot.control.active_site_id}): return false
	var goal: Dictionary = _sea_goal()
	if not _check(goal.ok and goal.lab is TerrainLab, "the destination's actual complete cold owner binds after the heir leaves", goal.get("code")): return false
	var destination: TerrainLab = goal.lab
	var center: Dictionary = Settlement.record(destination.terrain)
	var founder_owner: Variant = destination.crowd_site.person_owner(center_founder) if destination.crowd_site != null and destination.crowd_site.active else null
	if not _check(founder_owner is CrowdPersonOwner and float(founder_owner.combat_hot_get(founder_owner.index_for_identity(center_founder), &"hp", 0.0)) > 0.0
		and not center.is_empty() and int(center.level) == 1 and int(center.owner_faction) == 1,
		"the founder stays as the cold destination's living original person and its completed center keeps faction 1", {"founder": center_founder}): return false
	var hostile: Variant = null
	for owner: Variant in destination.crowd_site.person_owners():
		if owner is CrowdPersonOwner and int(owner.team_id) == multi_hostile_team: hostile = owner
	if not _check(hostile != null and int(hostile.faction_id) == 2 and hostile.records.size() == 1 and hostile.person(hostile.records.keys()[0], false).cell == Vector2i(98, 50),
		"initial actual hostile military body is adjacent to the true east entry through genuine original ground geometry"): return false
	multi_enemy_id = hostile.combat_identity(int(hostile.records.keys()[0]))
	if not _check([action_paid, action_game_paid] == paid and controller.checkpoint_region_internal("region_checkpoint", true).ok,
		"the destination center, its staying founder and the hostile body are born before any paid interval after the founder's departure and before either NPC route"): return false
	# Stable Site person references come only from the original travel identity
	# allocator, which a departure or arrival runs. This Site was indexed by the
	# founder's arrival and the heir's departure, before the hostile was born, and
	# the NPC static-contact gate skips an unindexed body (8e9577b). As in
	# region_npc_static_siege_entry_original_test, index the captured armies after
	# the whole-graph checkpoint and publish them before any paid interval.
	var held_refs: Dictionary = destination.terrain.site.get("travel_identity", {}).get("refs", {}).get("person", {}).duplicate(true)
	var indexed := RegionTravel.prepare_identity(destination.terrain.site)
	var refs_kept: bool = indexed.ok
	if refs_kept:
		for local: String in held_refs: refs_kept = refs_kept and indexed.state.travel_identity.refs.person.get(local) == held_refs[local]
	if not _check(refs_kept and indexed.state.travel_identity.refs.person.get(str(multi_enemy_id)) is Dictionary,
		"original identity allocator indexes the destination's hostile body and keeps every existing destination reference", indexed.get("code")): return false
	destination.terrain.site["travel_identity"] = indexed.state.travel_identity
	if not _check([action_paid, action_game_paid] == paid and controller.checkpoint_region_internal("region_checkpoint", true).ok,
		"the indexed destination identity publishes with the same whole graphs before any paid interval"): return false
	var begun: Dictionary = destination.crowd_site.issue_order(multi_hostile_team, TerrainArmy.CombatOrder.ATTACK, TerrainArmy.INVALID_CELL, -1, "test")
	if not _check(begun.ok, "actual hostile captain accepts the original siege attack before its real registry publication", begun): return false
	var siege: Dictionary = slot.refresh_original_region_siege_battle(destination)
	if not _check(siege.ok and not str(siege.get("battle_id", "")).is_empty(), "actual destination bodies and center create the original shared siege registry", siege): return false
	var held: Dictionary = destination.crowd_site.issue_order(multi_hostile_team, TerrainArmy.CombatOrder.HOLD, TerrainArmy.INVALID_CELL, -1, "test")
	return _check(held.ok, "same actual hostile captain holds its real body for the independent arriving contact through the original public order", held)

## Crowd port of the center root's heir birth (region_siege_center_original_test). A live crowd deploys only whole, so
## the destination's teams return to their holders and deploy again with the heir's two-person family team beside the
## founder and the one-person hostile at the east entry. The hostile is far from the center, so no capture accrues; it
## receives its siege order only after the destination is cold.
func _birth_successor() -> bool:
	var cleared: Dictionary = lab.crowd_site.clear()
	if not _check(cleared.get("ok", false) == true and not lab.crowd_site.active, "the destination's crowd teams return to their holders before the heir's birth", cleared): return false
	var founder: Dictionary = lab.site_controller.person_actions._person(lab.controlled_person_id(), false)
	if not _check(not founder.is_empty(), "the founder has an original body before the heir's birth"): return false
	var cells := _genesis_cells(Vector2i(founder.cell) + Vector2i(3, 0), 2, lab)
	if not _check(cells.size() == 2, "actual free cells beside the founder", cells): return false
	var heir_side := _ship_side(2)
	var hostile_side := _ship_side(1)
	if heir_side.is_empty() or hostile_side.is_empty(): return false
	hostile_side["faction"] = 2
	var hostile_cells: Array[Vector2i] = [Vector2i(98, 50)]
	var entered: Dictionary = lab.crowd_site.deploy([heir_side, hostile_side], [cells, hostile_cells])
	if not _check(entered.get("ok", false) == true and lab.crowd_site.active, "original named genesis births the heir's real team and the hostile body", entered): return false
	var heir_team: Variant = _multi_owner_at(lab, cells[0])
	var hostile: Variant = _multi_owner_at(lab, hostile_cells[0])
	if not _check(heir_team != null and hostile != null and heir_team.records.size() == 2, "the successor's original team and the hostile are present"): return false
	center_heir = heir_team.combat_identity(int(heir_team.current_commander))
	multi_hostile_team = int(hostile.team_id)
	return _check(center_heir > 0 and center_heir != center_founder and heir_team.command_eligible(int(heir_team.current_commander)), "the heir is the eligible captain of its newly born team", center_heir)

func _multi_owner_at(original: TerrainLab, cell: Vector2i) -> Variant:
	for owner: Variant in original.crowd_site.person_owners():
		if not owner is CrowdPersonOwner: continue
		for index: int in owner.records:
			var person: Dictionary = owner.person(index, false)
			if not person.is_empty() and person.cell == cell: return owner
	return null

## The controlled Actor's own original Region travel (the travel half of
## _hand_over_and_leave, without a handover): depart, route, paid map
## intervals, then the production world-open binds the arrived Site.
func _multi_travel_controlled(destination: Vector2i) -> bool:
	var traveller := lab.controlled_person_id()
	var due: Dictionary = slot.consume_due_region_events()
	if not _check(due.ok and bool(due.get("complete", false)), "original due endpoints finish before the Actor's own departure", due): return false
	var settled: Dictionary = controller.checkpoint_region_internal("region_checkpoint")
	if not _check(settled.ok, "original complete checkpoint captures the source Site before the Actor departs", settled): return false
	var departed_lab := lab
	var departed: Dictionary = RegionTravelSite.depart(controller)
	if not _check(departed.ok, "the controlled Actor departs through the original Region travel", departed): return false
	if is_instance_valid(genesis_panel): genesis_panel.free()
	genesis_panel = GenesisPanel.new()
	root.add_child(genesis_panel)
	genesis_panel.setup(genesis_panel)
	genesis_panel.set_process(false)
	var opened: Dictionary = genesis_panel.start({"world_id": world_id, "slot_id": "main", "manifest": manifest_path})
	if not _check(opened.ok and is_instance_valid(genesis_panel._original_adapter_host), "production travel panel restores the original map host", opened): return false
	lab = genesis_panel._original_adapter_host
	controller = lab.site_controller
	slot = genesis_panel.slot
	var selected: Dictionary = slot.region_travel_party()
	if not _check(selected.ok, "original map selects the Actor's party", selected): return false
	var current: Dictionary = slot.region_travel_status()
	var route_context: Dictionary = slot.prepare_region_route_context(null, selected.party)
	if not _check(route_context.ok, "original party route context", route_context): return false
	var search := RegionRoute.Search.new()
	search.source = slot.source
	search.start_site = current.site
	search.start_component = int(current.component)
	search.goal_site = destination
	search.context = route_context.context
	var route: Dictionary = search.run()
	if not _check(route.ok, "original route producer reaches the destination Site", route): return false
	var planned: Dictionary = slot.set_region_travel_plan(route.steps)
	if not _check(planned.ok, "original Slot admits the Actor's route", planned): return false
	for iteration: int in range(18000):
		current = slot.region_travel_status()
		if not _check(current.ok, "the Actor's route has one original status", current): return false
		if bool(current.get("arrived", false)): break
		var advanced: Dictionary = slot.advance_region_travel(37)
		if not _check(advanced.ok, "original map caller advances one common interval", advanced): return false
		if bool(advanced.get("arrived", false)): break
		if iteration % 60 == 0: await process_frame
	if not _check(bool(slot.region_travel_status().get("arrived", false)), "the Actor genuinely arrives at the destination Site"): return false
	var stored: Dictionary = slot.checkpoint_region_travel()
	if not _check(stored.ok, "the original travel publisher stores the arrived party", stored): return false
	# The departed scene's own Controller opens the arrival, as the real world-open path does.
	var visible := departed_lab
	var visible_open: Dictionary = visible.site_controller.open_fixed_world(manifest_path, world_id, "main", Vector2i(-1, -1), false)
	for retry: int in range(200000):
		if str(visible_open.get("code", "")) != "PENDING" and not visible.site_controller.region_operation_pending(): break
		visible_open = visible.site_controller.resume_region_operation()
		if retry % 60 == 0: await process_frame
	if not _check(visible_open.ok and bool(visible_open.get("arrived", false)), "production world-open binds the arrived destination Site", visible_open): return false
	_freeze(visible)
	lab = visible
	controller = visible.site_controller
	slot = controller.region_slot
	var wired := lab._wire_region_gameplay_adapters(slot)
	if not _check(wired.ok, "arrived Site wires the same original Slot owners", wired): return false
	return _check(lab.controlled_person_id() == traveller and str(slot.control.active_site_id) == str(lab.terrain.site.id), "the same Actor controls the arrived Site")

## Failure evidence only: which gate cells read as occupied, and the crowd bodies within three cells of the gate.
func _multi_gate_occupancy() -> Dictionary:
	var feature: Dictionary = _multi_source_gate()
	var cells := {}
	for index: int in feature.get("cells", []):
		var cell: Vector2i = lab.terrain.cell_from_index(index)
		cells[str(cell)] = {"controller": lab.site_controller.reserves_cell(cell), "crowd": lab.crowd_site != null and lab.crowd_site.reserves_cell(cell), "vehicle": lab.site_controller.vehicles.blocks_cell(cell)}
	var near := []
	if lab.crowd_site != null and lab.crowd_site.active:
		for owner: Variant in lab.crowd_site.person_owners():
			if not owner is CrowdPersonOwner: continue
			for index: int in owner.records:
				var person: Dictionary = owner.person(index, false)
				if person.is_empty(): continue
				if absi(person.cell.x - 25) <= 4 and absi(person.cell.y - 50) <= 4: near.append({"id": person.person_id, "team": owner.team_id, "cell": str(person.cell), "moving": person.moving, "to": str(owner.moving_to.get(index, Vector2i(-1, -1)))})
	var armies := []
	for team: TerrainArmy in lab.combat_armies:
		if team.cells.is_empty(): continue
		armies.append({"team": team.team_id, "owned": lab.crowd_site != null and lab.crowd_site.owns_original_team(team), "cells": str(team.cells)})
	return {"cells": cells, "near": near, "armies": armies, "operator": multi_gate_operator}

func _multi_source_gate() -> Dictionary:
	return lab.terrain.site.features.get(multi_gate, {})

func _multi_gate_to(open: bool) -> bool:
	var changed: Dictionary = SiteRuntime.request_gate(lab.terrain, multi_gate, open, multi_gate_operator, lab.site_controller._building_person_query, lab.site_controller.reserves_cell)
	if not _check(changed.ok, "actual original NPC begins public paid gate operation without changing any terrain or gate flag", changed if changed.ok else {"result": changed, "occupancy": _multi_gate_occupancy()}): return false
	return await _ship_until(func() -> bool: return bool(_multi_source_gate().gate.open) == open and str(_multi_source_gate().gate.pending).is_empty(), "original accepted common work completes the true gate operation")

func _multi_prepare_routes() -> bool:
	# Decision A already opened this gate (paid) for the founder's own departure.
	if not bool(_multi_source_gate().gate.open):
		if not await _multi_gate_to(true): return false
	if not _check(not lab.terrain.path_between(Vector2i(30, 49), Vector2i(0, 50)).is_empty(), "actual paid original open gate makes the foot source leg legally reachable"): return false
	# Keep the inherited genuine unknown-target refusal before its first
	# original observation; that same observation then also admits the foot route.
	if not _sea_dispatch(): return false
	var observed: Dictionary = slot.record_region_officer_geography_observation(lab, sea_nation_head, sea_goal_coordinate)
	if not _check(observed.ok, "original strategic head observes the actual common destination before either dispatch", observed): return false
	var foot: Variant = null
	for owner: Variant in lab.crowd_site.person_owners():
		if owner is CrowdPersonOwner and int(owner.team_id) == multi_foot_team: foot = owner
	if not _check(foot != null and foot.command_eligible(int(foot.current_commander)), "original finite foot captain resolves independently of both boats"): return false
	var component := RegionTravelSite.start_component(slot, Vector2i.ZERO, Vector2i(30, 49), lab.terrain)
	multi_foot_token = "c06_required_foot_%d" % OS.get_process_id()
	var prepared: Dictionary = slot.prepare_npc_region_dispatch(lab, sea_nation_id, multi_foot_team, sea_goal_coordinate, component, [], multi_foot_token)
	if not _check(prepared.ok and prepared.party.mode == "land" and prepared.party.person_ids == [multi_foot_person] and prepared.party.content.vehicles.is_empty() and prepared.plan.steps.size() == 2 and RegionRoute.entry_cell(prepared.plan.steps.back()) == Vector2i(99, 50), "existing Nation compiles a genuine one-row full-formation foot route with its own exact east entry", prepared.get("code")): return false
	multi_foot_refs = prepared.party.content.travel_identity.refs.duplicate(true)
	var stock := var_to_bytes(lab.terrain.site.inventory)
	var actor_ref: Dictionary = lab.terrain.site.travel_identity.refs.person[str(ship_actor_id)].duplicate(true)
	var inventory_before: Dictionary = lab.terrain.site.inventory.duplicate(true)
	var committed: Dictionary = slot.commit_npc_region_dispatch(prepared)
	var actor_after: Variant = lab.terrain.site.travel_identity.refs.person.get(str(ship_actor_id))
	var dispatch_detail := {"commit": committed if not committed.get("ok", false) else {"ok": true},
		"stock_same": stock == var_to_bytes(lab.terrain.site.inventory), "inventory_before": inventory_before if stock != var_to_bytes(lab.terrain.site.inventory) else {},
		"inventory_after": lab.terrain.site.inventory if stock != var_to_bytes(lab.terrain.site.inventory) else {},
		"actor_before": actor_ref, "actor_after": actor_after, "controlled": lab.controlled_person_id(), "ship_actor": ship_actor_id}
	if not _check(committed.get("ok", false) and stock == var_to_bytes(lab.terrain.site.inventory) and actor_ref == actor_after and lab.controlled_person_id() == ship_actor_id, "actual foot dispatch removes only its real movers and preserves unrelated source stock and human body", dispatch_detail): return false
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
		# Same owner fields the inherited sea party graph records (scene root/nodes and
		# transport). The scene's capture context carries a fresh random capture token
		# on every capture (region_party_checkpoint_context), so it cannot be part of a
		# byte comparison between two observations of the same unchanged state.
		var owners: Dictionary = captured.original_live_graph.owners
		graphs["foot_party"] = {"selected": var_to_bytes(selected.party), "reference": reference.duplicate(true),
			"owners": {"root": owners.scene.root.duplicate(true), "nodes": owners.scene.nodes.duplicate(true), "transport": owners.transport.duplicate(true)}}
	return graphs

## One native hit on either body of the pair, read at the paid step that applied it: its hit revision rose. Each entry
## carries the resolver's pair rule (_legal_melee_pair) at that accepted point and the hit body's hp loss and stun gain.
func _multi_observe_hits() -> void:
	if not is_instance_valid(multi_original) or multi_original.crowd_site == null or not multi_original.crowd_site.active: return
	var site: Variant = multi_original.crowd_site
	var a: Dictionary = multi_original._original_person_target(multi_arrived_person)
	var b: Dictionary = multi_original._original_person_target(multi_enemy_id)
	for identity: int in [multi_arrived_person, multi_enemy_id]:
		var index := int(site.crowd.soldier_index(identity))
		if index < 0: continue
		var state: Dictionary = site.soldier_state(index)
		var last: Dictionary = multi_hit_revisions.get(identity, {})
		multi_hit_revisions[identity] = {"revision": int(state.hit_revision), "hp": float(state.hp), "stun": float(state.stun)}
		if last.is_empty() or int(state.hit_revision) == int(last.revision): continue
		var entry := {"first": multi_enemy_id if identity == multi_arrived_person else multi_arrived_person, "second": identity, "hit": identity,
			"revision": [int(last.revision), int(state.hit_revision)], "hp_loss": maxf(0.0, float(last.hp) - float(state.hp)), "stun_gain": maxf(0.0, float(state.stun) - float(last.stun)),
			"ko": float(state.ko), "game": slot.control.logical_game_seconds, "action": slot.control.fire_clock.action_seconds, "sequence": slot.control.fire_clock.sequence, "pair_legal": false}
		if not a.is_empty() and not b.is_empty():
			entry["cells"] = [str(a.cell), str(b.cell)]
			entry["pair_legal"] = MultiBattle._legal_melee_pair(multi_original, {"id": multi_arrived_person, "cell": a.cell, "faction": int(a.owner.faction_id)}, {"id": multi_enemy_id, "cell": b.cell, "faction": int(b.owner.faction_id)})
		multi_melee.append(entry)

## Test-only bounded readout (OPUS74) of the actual pair's original exchange
## state; read-only. Sampled at every 10th poll of the paid waits that involve
## the pair, at most 80 samples, so a failed wait always carries evidence.
func _multi_pair_state() -> Dictionary:
	var state := {"world": float(slot.control.logical_game_seconds), "action": float(slot.control.fire_clock.action_seconds), "exchanges": multi_melee.size()}
	if not is_instance_valid(multi_original): return state
	for identity: int in [multi_arrived_person, multi_enemy_id]:
		var person: Dictionary = multi_original._original_person_target(identity)
		if person.is_empty() or not (person.owner is TerrainArmy or person.owner is CrowdPersonOwner):
			state[str(identity)] = "MISSING" if person.is_empty() else "NOT_ARMY"
			continue
		var team: Variant = person.owner
		var unit := int(person.unit)
		var row := {"cell": str(person.cell), "receive": team.exchange_can_receive(unit), "ready": team.exchange_ready(unit), "order": int(team.combat_order)}
		if team is CrowdPersonOwner: row["hit_revision"] = int(multi_original.crowd_site.soldier_state(multi_original.crowd_site.crowd.soldier_index(identity)).get("hit_revision", -1))
		for field: StringName in [&"hp", &"stun", &"ko", &"exchange_cooldown", &"exchange_stagger", &"pose", &"captive", &"surrender_pending"]:
			row[String(field)] = str(team.combat_hot_get(unit, field, null))
		state[str(identity)] = row
	return state

## Effects the recorded original exchanges dealt to the hostile (result a/b
## follow the emitted pair order).
func _multi_hostile_dealt() -> Dictionary:
	var dealt := {"hp": 0.0, "stun": 0.0, "hostile_lost": 0}
	for entry: Dictionary in multi_melee:
		if int(entry.get("hit", -1)) != multi_enemy_id: continue
		dealt.hp = float(dealt.hp) + float(entry.get("hp_loss", 0.0))
		dealt.stun = float(dealt.stun) + float(entry.get("stun_gain", 0.0))
		dealt.hostile_lost = int(dealt.hostile_lost) + 1
	return dealt

## Why a body can no longer take part in the paid wait, or "" while it can.
func _multi_body_down(identity: int) -> String:
	if not is_instance_valid(multi_original): return "NO_ORIGINAL"
	var person: Dictionary = multi_original._original_person_target(identity)
	if person.is_empty(): return "MISSING"
	if not (person.owner is TerrainArmy or person.owner is CrowdPersonOwner): return ""
	var team: Variant = person.owner
	var unit := int(person.unit)
	if float(team.combat_hot_get(unit, &"hp", 0.0)) <= 0.0: return "DEAD"
	if bool(team.combat_hot_get(unit, &"captive", false)): return "CAPTIVE"
	if float(team.combat_hot_get(unit, &"ko", 0.0)) > 0.0: return "KO"
	return ""

func _multi_trace_pair() -> void:
	_multi_observe_hits()
	multi_pair_polls += 1
	if multi_pair_polls % 10 == 1 and multi_pair_trace.size() < 80: multi_pair_trace.append(_multi_pair_state())

## Test-only failure evidence (OPUS67). Reads, without changing any owner, clock,
## order or body, each condition the production static-contact gate
## (_region_first_npc_siege_contact) applies to the hostile body at the foot entry.
func _multi_static_probe() -> Dictionary:
	var goal_owner := Grid.site_id(str(slot.pin.atlas_id), sea_goal_coordinate)
	var probe := {"world": float(slot.control.logical_game_seconds), "action": float(slot.control.fire_clock.action_seconds)}
	var battles: Array = []
	for id: String in slot.region_registry().battles:
		var battle: Dictionary = slot.region_registry().battles[id]
		if str(battle.get("site_id", "")) != goal_owner: continue
		battles.append({"id": id, "kind": str(battle.get("kind", "")), "phase": str(battle.get("phase", "")), "mode": str(battle.get("mode", "")),
			"attackers": str(battle.get("attackers", [])), "defenders": str(battle.get("defenders", [])), "revision": int(battle.get("revision", -1))})
	probe["battles"] = battles
	var events: Array = []
	for event: Dictionary in slot.region_registry().events:
		if str(event.payload.get("token", "")) != multi_foot_token: continue
		events.append({"id": str(event.id), "kind": str(event.kind), "at": float(event.at), "status": str(event.status),
			"contact": str(event.payload.get("contact_receipt", {}).get("kind", "")),
			"navigation_blocked": bool(event.payload.get("navigation_result", {}).get("navigation_blocked", false))})
	probe["foot_events"] = events
	var foot_reference: Dictionary = slot.region_registry().parties.get(multi_foot_token, {})
	probe["foot"] = {"phase": str(foot_reference.get("phase", "")), "position": str(foot_reference.get("position", {})), "arrival_game_seconds": str(foot_reference.get("arrival_game_seconds", ""))}
	var foot_party: Dictionary = slot._region_npc_party_runtime.get(multi_foot_token, {})
	var foot_upkeep: Dictionary = foot_party.get("upkeep", {})
	probe["foot_upkeep"] = {"at": str(foot_upkeep.get("at", "")), "distance": str(foot_upkeep.get("distance", "")), "route_blocked": foot_upkeep.has("route_blocked"),
		"pending_route_entry": foot_upkeep.has("pending_route_entry"), "route_node": str(foot_upkeep.get("route_node", {})),
		"live": not foot_upkeep.get("live", {}).is_empty(), "attempt": str(foot_upkeep.get("route_entry_attempt", 0))}
	var bound: Variant = slot._region_original_labs.get(goal_owner)
	if not is_instance_valid(bound) or not bound is TerrainLab:
		probe["destination"] = "UNBOUND"
		return probe
	var destination: TerrainLab = bound
	var refs: Dictionary = destination.terrain.site.get("travel_identity", {}).get("refs", {}).get("person", {})
	probe["hostile_indexed"] = refs.get(str(multi_enemy_id)) is Dictionary
	var person: Dictionary = destination.site_controller.person_actions._person(multi_enemy_id, false)
	if person.is_empty():
		probe["hostile"] = "MISSING"
		return probe
	var entry := Vector2i(99, 50)
	var cell: Vector2i = person.cell
	var gap: Vector2i = entry - cell
	var hostile := {"cell": [cell.x, cell.y], "faction": int(person.faction), "fit": Settlement._fit(person), "moving": bool(person.moving),
		"role": Settlement._role(person), "siege_crew": destination.site_controller.vehicles.is_siege_crew(multi_enemy_id),
		"gap": absi(gap.x) + absi(gap.y), "attack_across": destination.terrain.can_attack_across(cell, entry),
		"vehicle_blocks": destination.site_controller.vehicles.blocks_person_step(multi_enemy_id, cell, cell, entry, entry)}
	if person.owner is TerrainArmy or person.owner is CrowdPersonOwner:
		var team: Variant = person.owner
		var unit := int(person.unit)
		hostile["exchange_ready"] = team.exchange_ready(unit)
		hostile["combat_enabled"] = team.combat_enabled
		hostile["combat_can_act"] = team.combat_can_act(unit)
		hostile["combat_order"] = int(team.combat_order)
		if team is TerrainArmy:
			hostile["exchange_enabled"] = team.exchange_enabled
			hostile["garrison"] = str(team.garrison_feature_id)
		hostile["cooldown"] = float(team.combat_hot_get(unit, &"exchange_cooldown", 0.0))
		hostile["stagger"] = float(team.combat_hot_get(unit, &"exchange_stagger", 0.0))
		hostile["pose"] = str(team.combat_hot_get(unit, &"pose"))
	probe["hostile"] = hostile
	return probe

## Test-only exact readout (OPUS78): the IEEE-754 bits of a float.
func _multi_bits(value: Variant) -> String:
	if not (value is float or value is int): return "<%s>" % str(value)
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, float(value))
	return "%s (%s)" % [bytes.hex_encode(), String.num(float(value), 17)]

## The hostile's ko, the stored snapshot ko and the destination's own clocks,
## each as exact bits, read from the given destination Lab (read-only).
func _multi_ko_stage(destination: Variant) -> Dictionary:
	var stage := {"world": _multi_bits(slot.control.logical_game_seconds), "action": _multi_bits(slot.control.fire_clock.action_seconds)}
	var battle: Dictionary = slot.region_registry().battles.get(multi_siege_id, {})
	stage["stored_ko"] = _multi_bits(battle.get("siege", {}).get("bodies", {}).get(str(multi_enemy_id), {}).get("ko"))
	stage["stored_source_game"] = _multi_bits(battle.get("siege", {}).get("source", {}).get("game_seconds"))
	if not is_instance_valid(destination) or not destination is TerrainLab:
		stage["destination"] = "UNBOUND"
		return stage
	var lab_d: TerrainLab = destination
	var person: Dictionary = lab_d._original_person_target(multi_enemy_id)
	if not person.is_empty() and (person.owner is TerrainArmy or person.owner is CrowdPersonOwner):
		var team: Variant = person.owner
		var unit := int(person.unit)
		stage["live_ko"] = _multi_bits(team.combat_hot_get(unit, &"ko", null))
		if team is TerrainArmy: stage["row_ko"] = _multi_bits(team.combat_units[unit].get("ko"))
		stage["json_round_trip_ko"] = _multi_bits(JSON.parse_string(JSON.stringify(float(team.combat_hot_get(unit, &"ko", 0.0)), "", false, true)))
	var fire: Dictionary = lab_d.terrain.site.get("fire_settlement", {})
	stage["site_fire_game"] = _multi_bits(fire.get("game_seconds"))
	stage["site_fire_action"] = _multi_bits(fire.get("action_seconds"))
	stage["fire_action_cursor"] = _multi_bits(lab_d.fire_action_cursor)
	stage["site_minute"] = str(lab_d.terrain.site.get("minute", ""))
	stage["site_phase"] = _multi_bits(lab_d.terrain.site.get("phase"))
	stage["lab"] = str(lab_d.get_instance_id())
	return stage

func _sea_after_checkpoint() -> void:
	if multi_siege_id.is_empty(): return
	multi_ko_probe["after_checkpoint"] = _multi_ko_stage(multi_original)

func _sea_retry_failure_extra() -> Dictionary:
	if multi_siege_id.is_empty(): return {}
	multi_ko_probe["after_retry"] = _multi_ko_stage(slot._region_original_labs.get(Grid.site_id(str(slot.pin.atlas_id), sea_goal_coordinate)))
	return multi_ko_probe

func _multi_original_reinforcement() -> bool:
	multi_static_before = _multi_static_probe()
	if not await _multi_gate_to(true): return false
	if not await _ship_until(func() -> bool:
		if slot.region_registry().parties[multi_foot_token].phase == "entered": return true
		multi_static_before = _multi_static_probe()
		return false, "original blocked route retry pays its true independent approach and full arrival after actual gate reopening"): return false
	var reference: Dictionary = slot.region_registry().parties[multi_foot_token]
	var goal: Dictionary = _sea_goal()
	var original: TerrainLab = goal.lab
	multi_arrived_person = int(reference.arrival_mapping.maps.person[str(multi_foot_person)])
	var person: Dictionary = original.site_controller.person_actions._person(multi_arrived_person, false)
	if not _check(reference.destination_site == str(original.terrain.site.id) and person.cell == Vector2i(99, 50) and original.terrain.site.travel_identity.refs.person[str(multi_arrived_person)] == multi_foot_refs.person[str(multi_foot_person)] and original._region_bind_receipt_value.owners_restored and (person.owner.records.size() if person.owner is CrowdPersonOwner else person.owner.combat_units.size()) == 1, "true original independent entry capacity binds the entire same finite foot formation at its exact actual east entry"): return false
	for event: Dictionary in slot.region_registry().events:
		if event.payload.get("token") == multi_foot_token and event.payload.get("contact_receipt", {}).get("kind") == "npc_siege_channel": multi_static_contact = event.duplicate(true)
	var static_detail := {"event": multi_static_contact, "last_before_entry": multi_static_before, "after_entry": _multi_static_probe()}
	if not _check(not multi_static_contact.is_empty() and multi_static_contact.kind == "reinforcement" and multi_static_contact.status == "complete" and float(multi_static_contact.at) == float(reference.arrival_game_seconds), "original Slot consumes its own true earliest NPC static siege-contact event at the exact accepted foot insertion point", static_detail): return false
	var contact: Dictionary = multi_static_contact.payload.contact_receipt
	var witness: Dictionary = contact.witness
	var actual_enemy: Dictionary = original._original_person_target(multi_enemy_id)
	if not _check(witness.party_token == multi_foot_token and witness.person_id == multi_enemy_id and witness.person_cell == [98, 50] and witness.entry == [99, 50] and witness.party_reference == multi_foot_refs.person[str(multi_foot_person)] and witness.static_reference == original.terrain.site.travel_identity.refs.person[str(multi_enemy_id)] and witness.party_source is Dictionary and not witness.party_source.is_empty() and witness.navigation_revision >= 0 and witness.source_generation <= int(slot._marker.generation) and witness.runtime_revision <= int(slot.region_registry().revision) and contact.first.position.mode == "land" and contact.second.position.mode == "land" and float(contact.at) == float(multi_static_contact.at) and not actual_enemy.is_empty() and actual_enemy.cell == Vector2i(98, 50) and original.terrain.can_attack_across(person.cell, actual_enemy.cell), "real source/body/entry/navigation witness and current original body prove earliest lawful ground contact before later local melee work", contact): return false
	multi_original = original
	multi_hit_revisions.clear()
	_multi_observe_hits() # Baseline: hits are recorded from here on, as the GD exchange signal was connected here.
	var team: Variant = person.owner
	var move: Dictionary = original.crowd_site.issue_order(int(team.team_id), TerrainArmy.CombatOrder.MOVE, Vector2i(98, 51), -1, "test")
	if not _check(move.ok, "same real arrived captain orders public formation MOVE toward the actual local hostile body", move): return false
	multi_wait_impossible = ""
	var approached: bool = await _ship_until(func() -> bool:
		_multi_trace_pair()
		multi_wait_impossible = _multi_body_down(multi_arrived_person)
		if not multi_wait_impossible.is_empty(): return true
		var current: Dictionary = original._original_person_target(multi_arrived_person)
		return not current.is_empty() and current.cell == Vector2i(98, 51) and team.moving_member_count() == 0, "actual paid original formation completes its real local melee approach")
	if not approached or not multi_wait_impossible.is_empty():
		_check(false, "actual pair readout at the failed melee approach", {"impossible": multi_wait_impossible, "trace": multi_pair_trace, "last": _multi_pair_state()})
		return false
	var held: Dictionary = original.crowd_site.issue_order(int(team.team_id), TerrainArmy.CombatOrder.HOLD, TerrainArmy.INVALID_CELL, -1, "test")
	if not _check(held.ok, "existing arrived captain stops the real complete foot formation before actual contact", held): return false
	var refreshed: Dictionary = slot.refresh_original_region_siege_battle(original)
	if not _check(refreshed.ok and not str(refreshed.get("battle_id", "")).is_empty() and slot.region_registry().battles.has(str(refreshed.get("battle_id", ""))),
		"original siege owner refreshes its actual newly arrived body roster", refreshed): return false
	var battle: Dictionary = slot.region_registry().battles[str(refreshed.battle_id)]
	if not _check(battle.defenders.has(multi_arrived_person) and not battle.attackers.has(multi_arrived_person) and battle.attackers.has(multi_enemy_id),
		"the refreshed original siege holds the arrived reinforcement as defender and the actual hostile as attacker", {"attackers": str(battle.attackers), "defenders": str(battle.defenders)}): return false
	# The arrived body stood adjacent to the hostile from its entry cell, so the
	# original self-defence melee (HOLD) already resolved exchanges between them
	# during the paid approach. An original exchange fires only for an adjacent,
	# opposite-faction pair with a clear melee line where both bodies can receive
	# and one can initiate (terrain_lab exchange round). Each recorded exchange
	# also carries the resolver's pair rule (_legal_melee_pair) at that accepted
	# point. Stun and cooldown renew on every exchange, so a step boundary never
	# shows both bodies receivable (OPUS73); the accepted exchanges are the
	# original's own admission of this legal pair.
	var legal_exchanges: Array = multi_melee.filter(func(entry: Dictionary) -> bool: return bool(entry.get("pair_legal", false)))
	if not _check(not multi_melee.is_empty() and legal_exchanges.size() == multi_melee.size(),
		"real original body geometry and opposite battle sides admit the actual hostile melee target rather than food flags, rank or shared component", {"exchanges": multi_melee.size(), "legal": legal_exchanges.size(), "first": multi_melee.front() if not multi_melee.is_empty() else {}, "trace": multi_pair_trace, "last": _multi_pair_state()}): return false
	# The accepted exchanges' own effects are visible on the actual hostile body.
	var dealt := _multi_hostile_dealt()
	var hostile_now: Dictionary = original._original_person_target(multi_enemy_id)
	var hostile_team: Variant = hostile_now.owner if not hostile_now.is_empty() and (hostile_now.owner is TerrainArmy or hostile_now.owner is CrowdPersonOwner) else null
	var hostile_unit := int(hostile_now.get("unit", -1))
	var hostile_hp: float = float(hostile_team.combat_hot_get(hostile_unit, &"hp", 100.0)) if hostile_team != null else 100.0
	var hostile_stun: float = float(hostile_team.combat_hot_get(hostile_unit, &"stun", 0.0)) if hostile_team != null else 0.0
	var hostile_ko: float = float(hostile_team.combat_hot_get(hostile_unit, &"ko", 0.0)) if hostile_team != null else 0.0
	if not _check(hostile_team != null and (float(dealt.hp) > 0.0 or float(dealt.stun) > 0.0)
		and (float(dealt.hp) <= 0.0 or hostile_hp < 100.0) and (float(dealt.stun) <= 0.0 or hostile_stun > 0.0 or hostile_ko > 0.0),
		"the accepted original exchanges' damage and stun are visible on the actual hostile body", {"dealt": dealt, "hp": hostile_hp, "stun": hostile_stun, "ko": hostile_ko, "last": _multi_pair_state()}): return false
	# The public ATTACK order for the same hostile is still issued. When the
	# self-defence exchanges have already knocked the hostile out, no exchange can
	# follow (an original exchange needs both bodies receivable), so the test
	# asserts the original's actual response and the target's real state, and
	# does not wait for an exchange that cannot happen.
	var target_state := _multi_body_down(multi_enemy_id)
	var attacked: Dictionary = original.crowd_site.issue_order(int(team.team_id), TerrainArmy.CombatOrder.ATTACK, TerrainArmy.INVALID_CELL, multi_enemy_id, "test")
	var hostile_receives: bool = hostile_team != null and hostile_team.exchange_can_receive(hostile_unit)
	# Crowd port (2026-11-08): the native crowd refuses an ATTACK order whose target is already down with NO_TARGET (the
	# grid accepted it and then found no exchange); either way no exchange can follow a downed target.
	var order_answered: bool = attacked.get("ok", false) or not target_state.is_empty() and str(attacked.get("code", "")) == "NO_TARGET"
	if not _check(order_answered and (target_state.is_empty() or not hostile_receives),
		"same actual NPC captain issues its original public attack order for the real legal hostile body", {"response": attacked, "target_state": target_state, "target_receives": hostile_receives, "last": _multi_pair_state()}): return false
	if target_state.is_empty():
		# A hostile still standing must meet the ordered melee as a new accepted exchange.
		var melee_before := multi_melee.size()
		multi_wait_impossible = ""
		var ordered: bool = await _ship_until(func() -> bool:
			_multi_trace_pair()
			for identity: int in [multi_arrived_person, multi_enemy_id]:
				if multi_wait_impossible.is_empty() and not _multi_body_down(identity).is_empty(): multi_wait_impossible = str(identity) + ":" + _multi_body_down(identity)
			return multi_melee.size() > melee_before or not multi_wait_impossible.is_empty(), "original shared paid step emits a true accepted melee resolution between the physically arrived reinforcement and actual hostile body")
		if not ordered or multi_melee.size() <= melee_before:
			_check(false, "actual pair readout at the failed ordered melee", {"impossible": multi_wait_impossible, "trace": multi_pair_trace, "last": _multi_pair_state()})
			return false
		if not _check(bool(multi_melee.back().get("pair_legal", false)), "the ordered melee exchange is the same legal original pair", multi_melee.back()): return false
	# The ATTACK order changed a body's original order after the roster refresh
	# at HOLD. The original siege owner admits that metadata at its next consumer
	# call; publish it here, at the same point and before the final selected
	# reopen, so the reopen's zero-time retry compares a settled registry.
	var ordered_refresh: Dictionary = slot.refresh_original_region_siege_battle(original)
	if not _check(ordered_refresh.ok and str(ordered_refresh.get("battle_id", "")) == str(refreshed.battle_id),
		"original siege owner publishes the ordered roster at the same point before the final selected reopen", ordered_refresh): return false
	multi_siege_id = str(refreshed.battle_id)
	multi_ko_probe["after_ordered_refresh"] = _multi_ko_stage(multi_original)
	if not await _sea_reopen(false): return false
	return _check(not multi_melee.is_empty() and multi_blocked_event.payload.navigation_result.no_effect and lab.controlled_person_id() == ship_actor_id, "true melee and full selected cold preserve blocked-route history and actual human control")

func _run() -> void:
	RegionTravelSite.scene_handoff = false; RegionRoute.clear_memory_cache()
	if not _write_manifest() or not await _setup_action_world(): _finish(); return
	if not _ship_public_cargo(): _finish(); return
	if not await _ship_board(0, true) or not await _ship_public_food() or not await _ship_board(1, false): _finish(); return
	if not _check(not _ship_supply().locations.has("vehicle:" + ship_ids[1]), "second true boat still has no invented own food pool"): _finish(); return
	if not await _ship_helm(0, false) or not await _ship_helm(1, true) or not await _ship_open_sea_positive() or not await _ship_original_two_boat_closure(): _finish(); return
	if not await _multi_destination_decision_a(): _finish(); return
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
	if is_instance_valid(genesis_panel): genesis_panel.free()
	print("REGION_FOOD_REINFORCEMENT_MULTI_APPROACH_", "FAILED" if failed or not ok else "PASS", " ", JSON.stringify(report))
	super._finish(ok, message)
