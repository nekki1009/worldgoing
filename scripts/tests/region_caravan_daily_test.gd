extends "res://scripts/tests/region_caravan_trip_test.gd"
## 貿易 T5 end to end from the real daily rule (trade plan §7.2; 土匪 B5 slice 1). The trip fixture's world; nothing is
## dispatched by the test. The source Nation's head founds a settlement at the live Site (its centre built and completed),
## a warehouse in its jurisdiction is stocked with grain and bound to the settlement's trade by the head, and the head is
## told of the neighbouring Site as a settlement of his own side. Then only real steps:
## - the day's hook sends a caravan by SiteCaravan.dispatch: a two-person team that is not the head's own leaves with
##   grain from the warehouse (per-trade limit, half the stock), the mission is in the Region ledger without a risk
##   (no band is known), the grain counts against the source's used total;
## - it reaches the cold Site, turns back (no market there), comes home to the live Site and unloads: the warehouse has
##   its grain again, the reservation is given back, the mission ends.
## Output: the fixture's REGION_REMOTE_NATION_ORIGINAL_PASS marker and exit 0; quit(1) on any failure or the deadline.
const DailySettlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const DailyStrength = preload("res://scripts/region_lab/region_site_strength.gd")
const DailyAI = preload("res://scripts/region_lab/region_gameplay_ai.gd")
const PER_TRADE := 10
const STOCK := 40

func _as(person: int, action: Callable) -> Variant:
	var previous: int = lab.controlled_person_id()
	lab.terrain.site["controlled_person_id"] = person
	var result: Variant = action.call()
	lab.terrain.site["controlled_person_id"] = previous
	return result

func _daily_complete(key: String) -> bool:
	var data: TerrainData = lab.terrain
	var feature: Dictionary = data.site.features[key]
	var entrance: int = int(feature.get("pending_build", feature).get("entrance", feature.entrance))
	SiteRuntime.assign_task(data, SiteRuntime.ok("", {"target": "feature:" + key, "action": "construct", "cell": entrance}))
	data.site.worker.cell = entrance
	data.site.worker.mode = "work"
	SiteRuntime.advance(data, float(feature.get("pending_build", feature).work) + 1.0, true, false, Callable(), Callable(), Callable(), SiteRuntime.CARRY_CAPACITY, SiteRuntime.CARRY_CAPACITY, 1.0, 1)
	data.site.worker.mode = "idle"
	return str(feature.stage) == "complete" and not feature.has("pending_build")

func _daily_settlement() -> bool:
	var data: TerrainData = lab.terrain
	var head: Dictionary = controller.person_actions._person(nation_head, false)
	if not _check(not head.is_empty(), "the Nation's head stands at the source"): return false
	var settings := {"layout_version": 1, "quarter": 0, "owner_faction": int(head.faction)}
	var cells: Array[int] = []
	for offset: Vector2i in [Vector2i(2, 2), Vector2i(-6, 2), Vector2i(2, -6), Vector2i(-6, -6)]:
		var placement := SiteRuntime.building_cells(data, "settlement_center", Vector2i(head.cell) + offset, Vector2i(5, 5), settings)
		if placement.ok:
			cells.assign(placement.cells)
			break
	if not _check(not cells.is_empty(), "there is ground for a centre beside the head", head.cell): return false
	var founded: Dictionary = _as(nation_head, func() -> Dictionary: return DailySettlement.found(lab, nation_head, cells, {"layout_version": 1, "quarter": 0}, controller.reserves_cell, "商隊村"))
	if not _check(founded.get("ok", false), "the head founds a settlement", founded): return false
	if not _check(_daily_complete(str(founded.feature)) and int(DailySettlement.record(data).get("level", 0)) >= 1, "its centre is built: a level 1 settlement", DailySettlement.record(data).get("level")): return false
	var key := ""
	var centre := Vector2i(head.cell)
	for radius: int in range(4, 12, 2):
		for step: Vector2i in [Vector2i(radius, 0), Vector2i(-radius, 0), Vector2i(0, radius), Vector2i(0, -radius), Vector2i(radius, radius), Vector2i(-radius, -radius), Vector2i(radius, -radius), Vector2i(-radius, radius)]:
			if not DailySettlement.cell_in_jurisdiction(data, centre + step): continue
			var placement := SiteRuntime.building_cells(data, "warehouse", centre + step, Vector2i.ONE, settings)
			if not placement.ok: continue
			var built := SiteRuntime.request_build(data, "warehouse", placement.cells, Callable(), settings)
			if built.ok:
				key = str(built.feature)
				break
		if not key.is_empty(): break
	if not _check(not key.is_empty() and _daily_complete(key) and DailySettlement.feature_in_jurisdiction(data, data.site.features[key]) and TripStocks.ensure_storage(data, key, 1).ok,
		"a warehouse stands complete in its jurisdiction", key): return false
	trip_warehouse = key
	var stock := _trip_stock()
	stock.cargo["grain"] = STOCK
	stock.holder.version = int(stock.holder.version) + 1
	var bound: Dictionary = _as(nation_head, func() -> Dictionary: return DailySettlement.bind_trade_source(lab, nation_head, key, {"grain": {"per_trade": PER_TRADE, "total": 100}}))
	if not _check(bound.get("ok", false) and int(DailySettlement.head_executor(lab, true)) == nation_head and nation_head != int(lab.controlled_person_id()), "the head binds it to the settlement's trade; he is not the player", bound): return false
	var scope := str(data.site.id)
	var goal := Grid.site_id(str(slot.pin.atlas_id), nation_goal_coordinate)
	var now := float(slot.control.logical_game_seconds)
	# As a real strength report carries it: the head's own stable reference as observer and receiver (the Nation's
	# evaluation may also take the Site as a known target and send a carried command, which checks those references).
	var head_ref: Dictionary = DailyAI.person_ref(data.site, nation_head)
	var told: Dictionary = DailyAI.observe(slot.region_registry(), {"id": "test-daily:%s" % goal, "source": "report", "observation_kind": DailyStrength.KIND, "observer": nation_head, "receiver": nation_head,
		"observer_ref": head_ref.duplicate(true), "receiver_ref": head_ref.duplicate(true),
		"observer_scope": goal, "receiver_scope": scope, "object_scope": goal, "object": goal,
		"value": {"power": 0, "factions": {}, "settlement_owner": int(head.faction)}, "game_time": now, "expires_at": now + 7.0 * 86400.0, "confidence": 1.0})
	return _check(told.ok and TripCaravan.destinations(controller, nation_head, int(head.faction)) == [goal], "the head is told of a settlement of his side next door", [told, TripCaravan.destinations(controller, nation_head, int(head.faction))])

func _daily_used() -> int:
	return int(DailySettlement.record(lab.terrain).get("trade_sources", {}).get(trip_warehouse, {}).get("used", {}).get("grain", 0))

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest() or not await _setup_action_world() or not _nation_initial_bodies(): _finish(); return
	for _frame: int in range(10): await process_frame
	if not _daily_settlement(): _finish(); return
	controller.set_meta(&"resident_exodus_day", -1) # the day's hook has not run for this settlement yet
	if not await _nation_until(func() -> bool: return not Caravans.missions(slot.region_registry()).is_empty() or not TripCaravan.last_dispatch.is_empty() and not TripCaravan.last_dispatch.has("sent"),
		"the day's hook decides inside real steps"): _finish(); return
	var missions: Array = Caravans.missions(slot.region_registry())
	if not _check(missions.size() == 1 and TripCaravan.last_dispatch.has("sent"), "a caravan is sent by the daily rule", TripCaravan.last_dispatch): _finish(); return
	var mission: Dictionary = missions[0]
	trip_mission = int(mission.id)
	trip_token = str(mission.token)
	var captain: int = slot.person_id_of_ref(mission.captain_ref)
	if not _check(mission.goods == {"grain": PER_TRADE} and not mission.has("risk") and str(mission.phase) == "out" and captain > 0 and captain != nation_head
		and int(_trip_stock().cargo.get("grain", 0)) == STOCK - PER_TRADE and _daily_used() == PER_TRADE,
		"TR-50: the per-trade grain left the warehouse with a team that is not the head's; it counts as used; no risk on a quiet road", [mission, _trip_stock().cargo, _daily_used()]): _finish(); return
	if not await _nation_until(func() -> bool: return str(slot.region_registry().parties.get(trip_token, {}).get("phase", "")) == "entered", "the caravan travels and enters the cold Site"): _finish(); return
	if not await _nation_until(func() -> bool: return _trip_phase() == "back", "the cold Site's own evaluation turns the caravan home"):
		_check(false, "diagnosis", _trip_diag())
		_finish(); return
	if not await _nation_until(func() -> bool: return _trip_phase() == "gone", "the caravan comes home and the source's evaluation unloads it"): _finish(); return
	if not _check(int(_trip_stock().cargo.get("grain", 0)) == STOCK and _daily_used() == 0 and Caravans.lost(slot.region_registry()).is_empty(),
		"the warehouse has its grain again and the reservation is given back", [_trip_stock().cargo, _daily_used()]): _finish(); return
	report["caravan_daily"] = {"token": trip_token, "world": float(slot.control.logical_game_seconds)}
	_finish()
