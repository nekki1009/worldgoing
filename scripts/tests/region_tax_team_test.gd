extends "res://scripts/tests/region_caravan_trip_test.gd"
## 軍餉與稅收 P3b slice 2 (pay-and-tax plan §4.5; PT-15 with one fief): a tax team's round on the Region map. The
## remote-nation fixture: faction 1 gets its head (the source Nation's head, king) and one baron (a guard at the
## neighbouring cold Site). The king founds a settlement at the live Site (the capital) with a bound treasury; the
## baron founds one at the cold Site, levies into a tax warehouse holding coin and grain, and had 500 points of receipts
## last season. A two-person team becomes the tax team (an officer captain, a 文吏 as 稅使). Then:
## - 派收稅 sends it on its round: the one direct fief is its stop, the route is in the Region ledger;
## - at the fief its own Region evaluation hands over 10 percent (5 coins): the team carries them, the fief's tax
##   warehouse loses them, its record shows tribute_out, the baron gains 1 credit, the ledger remembers due and paid;
## - the team comes home and the capital's evaluation unloads the coins into the treasury as tribute_in; the round
##   ends; a second 派收稅 this season finds nothing left to collect (NO_FIEFS).
## Output: the fixture's REGION_REMOTE_NATION_ORIGINAL_PASS marker and exit 0; quit(1) on any failure or the deadline.
const TaxEnvoy = preload("res://scripts/terrain_lab/site_tax_envoy.gd")
const TaxRoutes = preload("res://scripts/region_lab/region_tax_routes.gd")
const TaxSettlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const TaxProduce = preload("res://scripts/terrain_lab/site_produce_tax.gd")
const TaxFinance = preload("res://scripts/terrain_lab/site_finance.gd")
const TaxTribute = preload("res://scripts/terrain_lab/site_tribute.gd")
const TaxPayTable = preload("res://scripts/terrain_lab/site_pay_table.gd")
const TaxCalendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const TaxRegionFinance = preload("res://scripts/region_lab/region_finance.gd")
const RECEIPTS := 5000
var tax_baron := -1
var tax_treasury := ""
var tax_source_key := ""
var tax_team := -1

func _owner_as(owner: TerrainLab, person: int, action: Callable) -> Variant:
	# The Site's own stored value comes back exactly (present or absent): the crowd's save checks it.
	var had: bool = owner.terrain.site.has("controlled_person_id")
	var previous: Variant = owner.terrain.site.get("controlled_person_id")
	owner.terrain.site["controlled_person_id"] = person
	var result: Variant = action.call()
	if had: owner.terrain.site["controlled_person_id"] = previous
	else: owner.terrain.site.erase("controlled_person_id")
	return result

func _complete(data: TerrainData, key: String) -> bool:
	var feature: Dictionary = data.site.features[key]
	var entrance: int = int(feature.get("pending_build", feature).get("entrance", feature.entrance))
	SiteRuntime.assign_task(data, SiteRuntime.ok("", {"target": "feature:" + key, "action": "construct", "cell": entrance}))
	data.site.worker.cell = entrance
	data.site.worker.mode = "work"
	SiteRuntime.advance(data, float(feature.get("pending_build", feature).work) + 1.0, true, false, Callable(), Callable(), Callable(), SiteRuntime.CARRY_CAPACITY, SiteRuntime.CARRY_CAPACITY, 1.0, 1)
	data.site.worker.mode = "idle"
	return str(feature.stage) == "complete" and not feature.has("pending_build")

## A settlement founded by `founder` on `owner`'s Site and a completed warehouse in its jurisdiction; returns the key.
func _found_with_warehouse(owner: TerrainLab, founder: int, label: String) -> String:
	var data: TerrainData = owner.terrain
	var person: Dictionary = owner.site_controller.person_actions._person(founder, false)
	if not _check(not person.is_empty(), "%s: the founder stands here" % label, founder): return ""
	var settings := {"layout_version": 1, "quarter": 0, "owner_faction": int(person.faction)}
	var cells: Array[int] = []
	for offset: Vector2i in [Vector2i(2, 2), Vector2i(-6, 2), Vector2i(2, -6), Vector2i(-6, -6)]:
		var placement := SiteRuntime.building_cells(data, "settlement_center", Vector2i(person.cell) + offset, Vector2i(5, 5), settings)
		if placement.ok:
			cells.assign(placement.cells)
			break
	if not _check(not cells.is_empty(), "%s: ground for a centre" % label, person.cell): return ""
	var founded: Dictionary = _owner_as(owner, founder, func() -> Dictionary: return TaxSettlement.found(owner, founder, cells, {"layout_version": 1, "quarter": 0}, owner.site_controller.reserves_cell, label))
	if not _check(founded.get("ok", false) and _complete(data, str(founded.feature)) and int(TaxSettlement.record(data).get("level", 0)) >= 1, "%s: a level 1 settlement" % label, founded): return ""
	var key := ""
	var centre := Vector2i(person.cell)
	for radius: int in range(4, 12, 2):
		for step: Vector2i in [Vector2i(radius, 0), Vector2i(-radius, 0), Vector2i(0, radius), Vector2i(0, -radius), Vector2i(radius, radius), Vector2i(-radius, -radius)]:
			if not TaxSettlement.cell_in_jurisdiction(data, centre + step): continue
			var placement := SiteRuntime.building_cells(data, "warehouse", centre + step, Vector2i.ONE, settings)
			if not placement.ok: continue
			var built := SiteRuntime.request_build(data, "warehouse", placement.cells, Callable(), settings)
			if built.ok:
				key = str(built.feature)
				break
		if not key.is_empty(): break
	if not _check(not key.is_empty() and _complete(data, key) and TripStocks.ensure_storage(data, key, 1).ok, "%s: a warehouse in its jurisdiction" % label, key): return ""
	data.site.stockpiles[key].cargo.clear()
	return key

func _tax_world() -> bool:
	var world := str(slot.pin.world_instance_id)
	var king := RegionPeerage.world_person_ref(world, nation_head)
	tax_baron = int(nation_goal.crowd_site.teams[0].person_ids[0])
	var baron := RegionPeerage.world_person_ref(world, tax_baron)
	var home := str(lab.terrain.site.id)
	var goal := str(nation_goal.terrain.site.id)
	var candidate: Dictionary = slot.control.faction_registry.duplicate(true)
	candidate.revision = int(candidate.revision) + 1
	candidate.entries["1"]["leader_ref"] = king
	candidate.entries["1"]["name"] = "甲國"
	candidate["peerage"] = {RegionPeerage.key_of(king): {"person_ref": king, "faction_id": 1, "rank": "king", "liege_ref": null, "granted_at": 0.0},
		RegionPeerage.key_of(baron): {"person_ref": baron, "faction_id": 1, "rank": "baron", "liege_ref": king, "granted_at": 0.0}}
	var seated := TaxRegionFinance.candidate(candidate)
	seated.revision = candidate.revision
	seated.finance.seats[RegionPeerage.key_of(king)] = home
	seated.finance.seats[RegionPeerage.key_of(baron)] = goal
	var committed: Dictionary = controller._commit_diplomacy({"ok": true, "registry": seated}, "")
	if not _check(committed.get("ok", false) and TaxEnvoy.capital_of(slot.control.faction_registry, 1) == home, "faction 1 has its king (seat: the capital) and a baron (seat: the neighbour)", committed): return false
	# The capital and its treasury.
	tax_treasury = _found_with_warehouse(lab, nation_head, "國都")
	if tax_treasury.is_empty(): return false
	var bound: Dictionary = _owner_as(lab, nation_head, func() -> Dictionary: return TaxTribute.bind_treasury(lab, nation_head, {"kind": "stock", "site_id": home, "feature_id": tax_treasury}))
	if not _check(bound.get("ok", false), "the king binds the treasury", bound): return false
	# The fief: its tax warehouse and last season's receipts (its camp gets the source's building stock first).
	var stock: Dictionary = nation_goal.terrain.site.get("inventory", {})
	for item: Variant in lab.terrain.site.get("inventory", {}): stock[item] = maxi(int(stock.get(item, 0)), int(lab.terrain.site.inventory[item]))
	nation_goal.terrain.site["inventory"] = stock
	nation_goal.terrain.site["capacity"] = maxi(int(nation_goal.terrain.site.get("capacity", 0)), int(lab.terrain.site.get("capacity", 0))) # the depot holds it
	tax_source_key = _found_with_warehouse(nation_goal, tax_baron, "封地")
	if tax_source_key.is_empty(): return false
	var levied: Dictionary = _owner_as(nation_goal, tax_baron, func() -> Dictionary: return TaxProduce.set_tax(nation_goal, tax_baron, 10, {"kind": "stock", "site_id": goal, "feature_id": tax_source_key}))
	if not _check(levied.get("ok", false), "the baron levies 10 percent into the tax warehouse", levied): return false
	var source: Dictionary = nation_goal.terrain.site.stockpiles[tax_source_key].cargo
	source["coin"] = 12
	source["grain"] = 30 # coin and grain within the warehouse's room
	var season := TaxEnvoy._season(nation_goal)
	TaxFinance.add_receipt(TaxProduce.record_of(nation_goal.terrain), "produce_tax", RECEIPTS, season - 1)
	nation_goal.site_controller.adjust_reputation(tax_baron, 0.0, -10.0) # away from the credit ceiling
	# A plain baron (neutral character): he pays (a lawless, ambitious one would refuse; that rule is site_tax_envoy_p3b_test's).
	var body: Variant = nation_goal.site_controller.person_actions._person(tax_baron, false).get("body")
	var neutral := {"version": TaxEnvoy.Personality.VERSION}
	for axis: String in TaxEnvoy.Personality.AXES: neutral[axis] = TaxEnvoy.Personality.NEUTRAL
	if body is Dictionary: body["personality"] = neutral
	elif body is Object: body.set("personality", neutral)
	return _check(TaxEnvoy.npc_decision(body.get("personality") if body != null else null) == "pay", "the baron is a plain man who pays")

func _tax_team() -> bool:
	tax_team = nation_courier_team
	var army: Variant = TaxEnvoy._army_of(lab, tax_team)
	if not _check(army != null, "the courier team has its roster", tax_team): return false
	var captain_index := int(army.formal_commander)
	army.combat_units[captain_index]["military_role"] = "officer"
	var clerk := -1
	for index: int in range(army.combat_units.size()):
		if index != captain_index and army.is_member(index): clerk = army.combat_identity(index)
	if not _check(str(TaxEnvoy.dispatch(controller, tax_team).get("code", "")) == "NO_TAX_ENVOY", "PT-16 in the world: without a 稅使 the team may not go"): return false
	var offices: Dictionary = army.team_offices()
	SiteOffices.position(offices, str(offices.duties.get(TaxEnvoy.DUTY, "")))["holder"] = clerk
	return _check(army.set_civil_role(clerk, "clerk") and TaxEnvoy.envoy_of(army) == clerk, "the second member is the team's 稅使", clerk)

## Holders carrying more than their room (diagnostics on failure): [site, holder, carried, capacity].
func _overloads() -> Array:
	var result: Array = []
	for owner: TerrainLab in [lab, nation_goal]:
		for key: String in owner.terrain.site.get("stockpiles", {}):
			var row: Dictionary = owner.terrain.site.stockpiles[key]
			var room := TripStocks.capacity(owner.terrain.site.features.get(key, {}))
			var carried := SiteRuntime.carried_size(row.cargo, row.holder)
			if carried > room: result.append([str(owner.terrain.site.id), "stock:" + key, carried, room])
		for team: Variant in owner.team_owners():
			for index: Variant in (team.combat_units.keys() if team.combat_units is Dictionary else range(team.combat_units.size())):
				var body: Dictionary = owner.site_controller.person_actions._person(team.combat_identity(int(index)), false)
				if body.is_empty(): continue
				var carried := SiteRuntime.carried_size(body.cargo, body.holder)
				if carried > SiteRuntime.CARRY_CAPACITY: result.append([str(owner.terrain.site.id), "person:%d" % team.combat_identity(int(index)), carried, SiteRuntime.CARRY_CAPACITY])
	return result

func _tax_route() -> Dictionary:
	var routes: Array = TaxRoutes.routes(slot.region_registry())
	return routes[0] if not routes.is_empty() else {}

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest() or not await _setup_action_world() or not _nation_initial_bodies(): _finish(); return
	for _frame: int in range(10): await process_frame
	if not _tax_world() or not _tax_team(): _finish(); return
	var goal := str(nation_goal.terrain.site.id)
	var season := TaxEnvoy._season(lab)
	var sent: Dictionary = TaxEnvoy.dispatch(controller, tax_team)
	if not _check(sent.get("ok", false) and sent.stops == [goal] and _tax_route().get("phase", "") == "out", "派收稅: the team sets out for its one direct fief", [sent, _overloads()]): _finish(); return
	var credit := int(nation_goal.site_controller.reputation_of(tax_baron).credit)
	if not await _nation_until(func() -> bool: return _tax_route().get("done", {}).has(goal), "the team reaches the fief and its evaluation hands the tax over"):
		_check(false, "diagnosis", {"route": _tax_route(), "last": TaxEnvoy.last_event, "parties": slot.region_registry().parties.keys()})
		_finish(); return
	var collected: Dictionary = TaxRoutes.collected_of(slot.region_registry(), 1, goal, season)
	var fief: Dictionary = TaxProduce.record_of(nation_goal.terrain)
	if not _check(str(_tax_route().done[goal]) == "full" and int(collected.get("due", 0)) == RECEIPTS / 10 and int(collected.get("paid", 0)) == RECEIPTS / 10
		and int(nation_goal.terrain.site.stockpiles[tax_source_key].cargo.get("coin", 0)) == 7 and TaxFinance.receipts_of(fief, "tribute_out", season) == RECEIPTS / 10
		and int(nation_goal.site_controller.reputation_of(tax_baron).credit) == credit + TaxEnvoy.Reputation.SCALE and _tax_route().get("carried", {}) == {"coin": 5},
		"5 coins handed over in full: the fief pays on the spot, the baron gains credit, the team carries them",
		{"route": _tax_route(), "collected": collected, "source": nation_goal.terrain.site.stockpiles[tax_source_key].cargo, "credit": [credit, nation_goal.site_controller.reputation_of(tax_baron)]}): _finish(); return
	if not await _nation_until(func() -> bool: return TaxRoutes.routes(slot.region_registry()).is_empty(), "the team comes home and the capital's evaluation unloads it"):
		_check(false, "diagnosis", {"route": _tax_route(), "last": TaxEnvoy.last_event})
		_finish(); return
	var capital: Dictionary = TaxProduce.record_of(lab.terrain)
	var treasury: Dictionary = lab.terrain.site.stockpiles[tax_treasury].cargo # read now: a publication may replace the Site's dictionaries
	if not _check(int(treasury.get("coin", 0)) == 5 and TaxFinance.receipts_of(capital, "tribute_in", TaxEnvoy._season(lab)) == RECEIPTS / 10,
		"PT-15: the treasury holds the 5 coins as tribute_in", [treasury, capital.get("receipts")]): _finish(); return
	for _frame: int in range(10): await process_frame
	var left: Array = TaxEnvoy.due_stops(slot.control.faction_registry, slot.region_registry(), 1, str(lab.terrain.site.id), season)
	if not _check(left.is_empty(), "nothing is left to collect this season (a second 派收稅 is refused NO_FIEFS)", left): _finish(); return
	report["tax_team"] = {"world": float(slot.control.logical_game_seconds), "collected": collected}
	_finish()
