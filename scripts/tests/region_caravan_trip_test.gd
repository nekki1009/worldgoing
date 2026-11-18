extends "res://scripts/tests/region_remote_nation_original_test.gd"
## 貿易 T5 slice 3 (trade plan §7.2, TR-50/51/53): a caravan's whole trip on the Region map. The remote-nation fixture
## world (a live source Site with its authored teams, a cold strategic Site next to it). A warehouse is built and
## completed at the source; the courier team loads the mission's grain from it (the warehouse loses it, TR-50) and
## leaves on its captain's word for the cold Site, with its mission in the Region ledger. Checks:
## - the caravan really travels and enters the cold Site; that Site's own Region evaluation turns it home (phase back);
## - the world saves and reopens with the mission in flight (the ledger and the party survive, TR-53);
## - it travels home and the source's evaluation unloads it: the warehouse has its grain again, the members carry none
##   of it, the mission ends; nothing was sold (no market there), so the grain is conserved exactly.
## Output: the fixture's REGION_REMOTE_NATION_ORIGINAL_PASS marker and exit 0 on success; quit(1) on any failure or the deadline.
const Caravans = preload("res://scripts/region_lab/region_caravans.gd")
const TripCaravan = preload("res://scripts/terrain_lab/site_caravan.gd")
const TripStocks = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const TripPayroll = preload("res://scripts/terrain_lab/site_payroll.gd")
const TripJoin = preload("res://scripts/terrain_lab/site_join_faction.gd")
const GRAIN := 6
var trip_warehouse := ""
var trip_token := ""
var trip_mission := -1

func _initialize() -> void:
	super._initialize()
	nation_goal_guard_faction = 1 # the destination's gate guards are the caravan's own side (destinations are friendly)
	deadline = Time.get_ticks_msec() + 900000
	out = "res://.godot-temp/region_caravan_trip/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_msec() > deadline: _finish(false, "900-second caravan trip deadline")
	return false

## A warehouse of faction 1, built and completed by the source's worker (the formal construction path).
func _trip_warehouse() -> bool:
	var data: TerrainData = lab.terrain
	var settings := {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	var key := ""
	for y: int in range(30, 90, 4):
		for x: int in range(30, 90, 4):
			var placement := SiteRuntime.building_cells(data, "warehouse", Vector2i(x, y), Vector2i.ONE, settings)
			if not placement.ok: continue
			var built := SiteRuntime.request_build(data, "warehouse", placement.cells, Callable(), settings)
			if built.ok:
				key = str(built.feature)
				break
		if not key.is_empty(): break
	if not _check(not key.is_empty(), "a warehouse is placed at the source"): return false
	var feature: Dictionary = data.site.features[key]
	var entrance: int = int(feature.get("pending_build", feature).get("entrance", feature.entrance))
	SiteRuntime.assign_task(data, SiteRuntime.ok("", {"target": "feature:" + key, "action": "construct", "cell": entrance}))
	data.site.worker.cell = entrance
	data.site.worker.mode = "work"
	SiteRuntime.advance(data, float(feature.get("pending_build", feature).work) + 1.0, true, false, Callable(), Callable(), Callable(), SiteRuntime.CARRY_CAPACITY, SiteRuntime.CARRY_CAPACITY, 1.0, 1)
	data.site.worker.mode = "idle"
	if not _check(str(feature.stage) == "complete" and TripStocks.ensure_storage(data, key, 1).ok, "the warehouse is complete and holds a stock", feature.get("stage")): return false
	trip_warehouse = key
	var stock: Dictionary = TripPayroll.source_of(lab, {"kind": "stock", "site_id": str(data.site.id), "feature_id": key})
	stock.cargo["grain"] = int(stock.cargo.get("grain", 0)) + 40
	stock.holder.version = int(stock.holder.version) + 1
	return true

func _trip_stock() -> Dictionary:
	return TripPayroll.source_of(lab, {"kind": "stock", "site_id": str(lab.terrain.site.id), "feature_id": trip_warehouse})

func _trip_carried(team_id: int) -> int:
	var total := 0
	for team: Variant in lab.team_owners():
		if int(team.team_id) != team_id: continue
		for index: Variant in (team.combat_units.keys() if team.combat_units is Dictionary else range(team.combat_units.size())):
			var body: Dictionary = controller.person_actions._person(team.combat_identity(int(index)), false)
			if not body.is_empty(): total += int(body.cargo.get("grain", 0))
	return total

func _trip_depart() -> bool:
	var stock := _trip_stock()
	var before := int(stock.cargo.grain)
	var captain := int(controller.team_captain_of_team(nation_courier_team)) if lab.crowd_site != null and lab.crowd_site.active else -1
	if not _check(captain > 0, "the courier team has a captain", captain): return false
	var body: Dictionary = controller.person_actions._person(captain, false)
	var moved := SiteRuntime.transfer_items(lab.terrain, stock.holder, stock.cargo, body.holder, body.cargo, {"grain": GRAIN}, [], int(stock.holder.version), int(body.holder.version))
	if not _check(moved.ok and int(stock.cargo.grain) == before - GRAIN and int(body.cargo.get("grain", 0)) >= GRAIN, "TR-50: the grain leaves the warehouse into the captain's cargo", moved): return false
	var ref: Dictionary = TripJoin._world_ref(controller, captain)
	if not _check(not ref.is_empty(), "the captain has a world reference"): return false
	trip_token = "caravan_trip_%d" % OS.get_process_id()
	var added := Caravans.add(slot.region_registry(), {"token": trip_token, "faction": 1, "from_site": str(lab.terrain.site.id), "warehouse": trip_warehouse,
		"to_site": Grid.site_id(str(slot.pin.atlas_id), nation_goal_coordinate), "captain_ref": ref, "goods": {"grain": GRAIN}, "phase": "out", "day": int(float(slot.control.logical_game_seconds) / 86400.0)})
	if not _check(added.ok, "the mission is in the Region ledger", added): return false
	trip_mission = int(added.id)
	var person: Dictionary = lab.crowd_site.combat_target(captain)
	var component: int = RegionTravelSite.start_component(slot, slot._coordinate(lab.terrain).site, person.cell, lab.terrain)
	var prepared: Dictionary = slot.prepare_npc_region_dispatch(lab, "captain:trade", nation_courier_team, nation_goal_coordinate, component, [], trip_token)
	if not _check(prepared.ok and str(prepared.request.get("captain_dispatch", "")) == "trade", "the captain sends the caravan onto the road", prepared): return false
	return _check(slot.commit_npc_region_dispatch(prepared).ok, "the caravan leaves")

## Why a mission is not turning (printed on failure only): the captain's id and body on the destination, his team there,
## the destination's queued evaluations and a dry run of the trip home.
func _trip_diag() -> Dictionary:
	var mission: Dictionary = Caravans.find(slot.region_registry(), trip_mission)
	var captain: int = slot.person_id_of_ref(mission.get("captain_ref", {}))
	var goal_id := Grid.site_id(str(slot.pin.atlas_id), nation_goal_coordinate)
	var events := []
	for event: Variant in slot.region_registry().events:
		if event is Dictionary and str(event.get("kind", "")) == "evaluation": events.append([str(event.get("owner", "")), float(event.get("at", 0.0)), str(event.get("status", ""))])
	var diag := {"mission": mission, "captain": captain, "goal_scope": str(nation_goal.terrain.site.id), "goal_id": goal_id,
		"target": nation_goal._original_person_target(captain).keys() if captain > 0 else [], "team": TripCaravan._team_of_person(nation_goal, captain),
		"evaluations": events, "world": float(slot.control.logical_game_seconds), "party": slot.region_registry().parties.get(trip_token, {}).get("phase", "")}
	if nation_goal.site_controller != null and captain > 0:
		var target: Dictionary = nation_goal._original_person_target(captain)
		var here: Dictionary = slot._coordinate(nation_goal.terrain)
		diag["here"] = here
		if not target.is_empty() and here.get("ok", true):
			var component: int = RegionTravelSite.start_component(slot, here.site, target.cell, nation_goal.terrain)
			diag["component"] = component
			diag["dry_home"] = slot.prepare_npc_region_dispatch(nation_goal, "captain:trade", TripCaravan._team_of_person(nation_goal, captain), Vector2i.ZERO, component, [], "caravan_trip_probe")
		var cs: Variant = nation_goal.crowd_site
		if cs != null and cs.active:
			var members := []
			for team: Dictionary in cs.teams:
				if int(team.team_id) != int(diag.team): continue
				for person: Variant in team.person_ids:
					var index := int(cs._index_by_id.get(int(person), -1))
					var owner: Variant = cs.person_owner(int(person))
					members.append({"person": int(person), "index": index, "fighting": cs.person_fighting(int(person)), "state": cs.soldier_state(index) if index >= 0 else {},
						"exit": owner.site_exit_ready(index) if owner != null and index >= 0 else null, "host": index == cs.player_index})
			diag["members"] = members
			diag["teams"] = cs.teams.map(func(t: Dictionary) -> Array: return [int(t.team_id), int(t.get("faction", -1)), t.get("person_ids", []).size(), bool(t.get("departed", false))])
		diag["last_evaluation"] = TripCaravan.last_evaluation.duplicate(true)
		diag["evaluate"] = TripCaravan.evaluate(slot, nation_goal)
	return diag

## The inherited reopen also asks for the remote Nation's carried report in flight; this trip carries no report, so the
## reopen proves the rest (facts, graph, clocks, bind proof) and the caravan's own ledger is checked after it.
func _partial_ready() -> bool:
	return true

func _trip_phase() -> String:
	return str(Caravans.find(slot.region_registry(), trip_mission).get("phase", "gone"))

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest() or not await _setup_action_world() or not _nation_initial_bodies(): _finish(); return
	if not _trip_warehouse(): _finish(); return
	for _frame: int in range(10): await process_frame
	if not _trip_depart(): _finish(); return
	var grain_after_loading := int(_trip_stock().cargo.grain)
	if not await _nation_until(func() -> bool: return str(slot.region_registry().parties.get(trip_token, {}).get("phase", "")) == "entered", "the caravan travels and enters the cold Site"): _finish(); return
	if not await _nation_until(func() -> bool: return _trip_phase() == "back", "the cold Site's own evaluation turns the caravan home"):
		_check(false, "diagnosis", _trip_diag())
		_finish(); return
	if not await _nation_reopen(): _finish(); return
	if not _check(_trip_phase() == "back" and str(Caravans.find(slot.region_registry(), trip_mission).get("to_site", "")) == Grid.site_id(str(slot.pin.atlas_id), nation_goal_coordinate), "TR-53: the mission survives the save and reopen", Caravans.missions(slot.region_registry())): _finish(); return
	if not await _nation_until(func() -> bool: return _trip_phase() == "gone", "the caravan comes home and the source's evaluation unloads it"): _finish(); return
	if not _check(int(_trip_stock().cargo.grain) == grain_after_loading + GRAIN and _trip_carried(nation_courier_team) == 0, "the warehouse has its grain again; the members carry none (conserved, nothing sold)", [_trip_stock().cargo.grain, grain_after_loading, _trip_carried(nation_courier_team)]): _finish(); return
	report["caravan_trip"] = {"token": trip_token, "world": float(slot.control.logical_game_seconds)}
	_finish()
