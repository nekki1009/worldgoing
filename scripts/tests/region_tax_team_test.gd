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
	candidate.entries["1"]["name"] = "甲國"
	var seated: Dictionary
	if tax_case == "lord":
		# Q9-A: the source Nation's head is a count here; his king sits elsewhere; the baron is the count's vassal.
		var far_king := RegionPeerage.world_person_ref(world, 999999)
		candidate.entries["1"]["leader_ref"] = far_king
		candidate["peerage"] = {RegionPeerage.key_of(far_king): {"person_ref": far_king, "faction_id": 1, "rank": "king", "liege_ref": null, "granted_at": 0.0},
			RegionPeerage.key_of(king): {"person_ref": king, "faction_id": 1, "rank": "count", "liege_ref": far_king, "granted_at": 0.0},
			RegionPeerage.key_of(baron): {"person_ref": baron, "faction_id": 1, "rank": "baron", "liege_ref": king, "granted_at": 0.0}}
		seated = TaxRegionFinance.candidate(candidate)
		seated.finance.seats[RegionPeerage.key_of(far_king)] = Grid.site_id(str(slot.pin.atlas_id), Vector2i(1, 0))
	else:
		candidate.entries["1"]["leader_ref"] = king
		candidate["peerage"] = {RegionPeerage.key_of(king): {"person_ref": king, "faction_id": 1, "rank": "king", "liege_ref": null, "granted_at": 0.0},
			RegionPeerage.key_of(baron): {"person_ref": baron, "faction_id": 1, "rank": "baron", "liege_ref": king, "granted_at": 0.0}}
		seated = TaxRegionFinance.candidate(candidate)
	seated.revision = candidate.revision
	seated.finance.seats[RegionPeerage.key_of(king)] = home
	seated.finance.seats[RegionPeerage.key_of(baron)] = goal
	var committed: Dictionary = controller._commit_diplomacy({"ok": true, "registry": seated}, "")
	if not _check(committed.get("ok", false) and TaxEnvoy.collector_at(slot.control.faction_registry, 1, home).get("nation", null) == (tax_case != "lord"),
		"faction 1's collector sits here (the king, or a count in the lord case) and a baron's seat is the neighbour", committed): return false
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

## The case (-- --tax-case=<case>): "pay" (default: 派收稅 by the test, the baron pays in full), "npc_day" (the NPC
## nation's own daily hook sends the team), "refuse" (a lawless, ambitious baron refuses: PT-18's outcome), "room" (the
## team's people have room for only 3 coins: PT-19, the rest stays pending and the fief stays due), "lord" (Q9-A: the
## source's head is a count whose baron owes him; the king sits elsewhere; the count's own tax team collects), "cart" (the
## people's hands are full; the team's parked cart gets a driver (he walks to it, takes it, settles it) and carries the tax
## there and back across the Sites, §4.5's recommended cart).
var tax_case := "pay"
var tax_cart := ""

func _case_expect() -> Dictionary:
	match tax_case:
		"refuse": return {"outcome": "refused", "paid": 0, "coins_left": 12, "credit": -2, "carried": {}, "treasury": 0, "still_due": true}
		"room": return {"outcome": "room", "paid": 300, "coins_left": 9, "credit": 1, "carried": {"coin": 3}, "treasury": 3, "still_due": true}
	return {"outcome": "full", "paid": 500, "coins_left": 7, "credit": 1, "carried": {"coin": 5}, "treasury": 5, "still_due": false}

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--tax-case="): tax_case = argument.trim_prefix("--tax-case=")
	if not _check(tax_case in ["pay", "npc_day", "refuse", "room", "lord", "cart"], "one tax case", tax_case): _finish(); return
	if not _write_manifest() or not await _setup_action_world() or not _nation_initial_bodies(): _finish(); return
	for _frame: int in range(10): await process_frame
	if not _tax_world() or not _tax_team(): _finish(); return
	var expect := _case_expect()
	var goal := str(nation_goal.terrain.site.id)
	var season := TaxEnvoy._season(lab)
	if tax_case == "refuse":
		var body: Variant = nation_goal.site_controller.person_actions._person(tax_baron, false).get("body")
		var defiant: Dictionary = (body.get("personality") as Dictionary).duplicate()
		defiant["lawful"] = 20
		defiant["ambition"] = 80
		if body is Dictionary: body["personality"] = defiant
		else: body.set("personality", defiant)
	if tax_case in ["room", "cart"]:
		var army: Variant = TaxEnvoy._army_of(lab, tax_team)
		# Each member's room (gear counts) is filled with wood, all but 3 units in the last one.
		var people: Array = []
		for index: int in range(army.combat_units.size()):
			if army.is_member(index): people.append(controller.person_actions._person(army.combat_identity(index), false))
		for at: int in range(people.size()):
			var person: Dictionary = people[at]
			person.cargo.erase("wood")
			var free := SiteRuntime.CARRY_CAPACITY - SiteRuntime.carried_size(person.cargo, person.holder) - (3 if at == people.size() - 1 and tax_case == "room" else 0)
			if free > 0: person.cargo["wood"] = free
			person.holder.version = int(person.holder.version) + 1
		if tax_case == "cart":
			# A parked cart of the team, three cells from its captain, with no driver.
			var captain := int(army.combat_identity(int(army.formal_commander)))
			var near: Vector2i = controller.person_actions._person(captain, false).cell
			var spot := Vector2i(-1, -1)
			for offset: Vector2i in [Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3), Vector2i(0, -3), Vector2i(4, 1), Vector2i(-4, 1)]:
				if lab.terrain.contains(near + offset) and lab.terrain.is_walkable(near + offset) and lab.terrain.is_walkable(near + offset + Vector2i(1, 0)):
					spot = near + offset
					break
			tax_cart = str(int(lab.terrain.site.get("next_vehicle", 1)))
			lab.terrain.site["next_vehicle"] = int(tax_cart) + 1
			if not lab.terrain.site.has("vehicles"): lab.terrain.site["vehicles"] = {}
			lab.terrain.site.vehicles[tax_cart] = {"id": tax_cart, "kind": "cart", "team_id": tax_team, "cell": lab.terrain.index(spot), "facing": [1, 0],
				"holder": SiteRuntime.new_item_state("vehicle:" + tax_cart), "cargo": {}, "move": {}, "operator_id": 0, "stop_pending": false} # the Store's ten cart fields
			if not _check(spot.x >= 0 and TaxEnvoy._room(lab, controller, tax_team) == SiteVehicleTransport.CAPACITY.cart, "the people's hands are full; the team's cart has room", TaxEnvoy._room(lab, controller, tax_team)): _finish(); return
		elif not _check(TaxEnvoy._room(lab, controller, tax_team) == 3, "the team's people have room for 3 units", TaxEnvoy._room(lab, controller, tax_team)): _finish(); return
	if tax_case == "npc_day":
		controller.set_meta(&"resident_exodus_day", -1) # the capital's day hook runs again
		if not await _nation_until(func() -> bool: return not _tax_route().is_empty() or TaxEnvoy.last_event.has("dispatched"), "the NPC nation's own day sends its tax team"):
			_check(false, "diagnosis", TaxEnvoy.day(controller))
			_finish(); return
	elif tax_case == "cart":
		# 派收稅 is asked again until the cart's driver has walked to it, taken it and settled it.
		var attempts := {"last": {}}
		var try_send := func() -> bool:
			var tried: Dictionary = TaxEnvoy.dispatch(controller, tax_team)
			attempts["last"] = tried
			return bool(tried.get("ok", false)) or str(tried.get("code", "")) != "DRIVER"
		if not await _nation_until(try_send, "the cart gets its driver and the team sets out"):
			_finish(); return
		var cart_now: Dictionary = lab.terrain.site.get("vehicles", {}).get(tax_cart, {})
		if not _check(bool(attempts.last.get("ok", false)) and attempts.last.stops == [goal] and cart_now.is_empty(), "派收稅 with its cart: the cart leaves with the team", [attempts.last, cart_now]): _finish(); return
	else:
		var sent: Dictionary = TaxEnvoy.dispatch(controller, tax_team)
		if not _check(sent.get("ok", false) and sent.stops == [goal], "派收稅: the team sets out for its one direct fief", [sent, _overloads()]): _finish(); return
	var marked: bool = TaxRoutes.lord_uses_teams(slot.region_registry(), RegionPeerage.key_of(RegionPeerage.world_person_ref(str(slot.pin.world_instance_id), nation_head))) and not TaxRoutes.uses_teams(slot.region_registry(), 1) 		if tax_case == "lord" else TaxRoutes.uses_teams(slot.region_registry(), 1)
	if not _check(_tax_route().get("phase", "") == "out" and _tax_route().get("stops", []) == [goal] and marked, "the round is on the road; the nation (or the count) now collects by tax teams", _tax_route()): _finish(); return
	var credit := int(nation_goal.site_controller.reputation_of(tax_baron).credit)
	var unpaid := int(TaxProduce.record_of(nation_goal.terrain).get("unpaid_seasons", 0))
	if not await _nation_until(func() -> bool: return _tax_route().get("done", {}).has(goal), "the team reaches the fief and its evaluation hands the tax over"):
		_check(false, "diagnosis", {"route": _tax_route(), "last": TaxEnvoy.last_event, "parties": slot.region_registry().parties.keys()})
		_finish(); return
	var collected: Dictionary = TaxRoutes.collected_of(slot.region_registry(), 1, goal, season)
	var fief: Dictionary = TaxProduce.record_of(nation_goal.terrain)
	if not _check(str(_tax_route().done[goal]) == str(expect.outcome) and int(collected.get("due", 0)) == RECEIPTS / 10 and int(collected.get("paid", 0)) == int(expect.paid)
		and int(nation_goal.terrain.site.stockpiles[tax_source_key].cargo.get("coin", 0)) == int(expect.coins_left) and TaxFinance.receipts_of(fief, "tribute_out", season) == int(expect.paid)
		and int(nation_goal.site_controller.reputation_of(tax_baron).credit) == credit + int(expect.credit) * TaxEnvoy.Reputation.SCALE and _tax_route().get("carried", {}) == expect.carried
		and int(fief.get("unpaid_seasons", 0)) == unpaid + (1 if tax_case == "refuse" else 0),
		"the handover at the fief: %s" % str(expect.outcome),
		{"route": _tax_route(), "collected": collected, "source": nation_goal.terrain.site.stockpiles[tax_source_key].cargo, "credit": [credit, nation_goal.site_controller.reputation_of(tax_baron)], "unpaid": fief.get("unpaid_seasons")}): _finish(); return
	if tax_case == "cart":
		var team_there := TaxEnvoy.Caravan._team_of_person(nation_goal, slot.person_id_of_ref(_tax_route().captain_ref))
		var carts: Array = TaxEnvoy._carts(nation_goal, team_there)
		if not _check(carts.size() == 1 and carts[0].cargo == {"coin": 5}, "the cart crossed with the team and carries the tax", [team_there, carts, nation_goal.terrain.site.get("vehicles", {}).keys()]): _finish(); return
	if not await _nation_until(func() -> bool: return TaxRoutes.routes(slot.region_registry()).is_empty(), "the team comes home and the capital's evaluation unloads it"):
		_check(false, "diagnosis", {"route": _tax_route(), "last": TaxEnvoy.last_event})
		_finish(); return
	var capital: Dictionary = TaxProduce.record_of(lab.terrain)
	var treasury: Dictionary = lab.terrain.site.stockpiles[tax_treasury].cargo # read now: a publication may replace the Site's dictionaries
	if not _check(int(treasury.get("coin", 0)) == int(expect.treasury) and TaxFinance.receipts_of(capital, "tribute_in", TaxEnvoy._season(lab)) == int(expect.paid),
		"PT-15: the treasury holds what was collected, as tribute_in", [treasury, capital.get("receipts")]): _finish(); return
	for _frame: int in range(10): await process_frame
	var left: Array = TaxEnvoy.due_stops(slot.control.faction_registry, slot.region_registry(), 1, str(lab.terrain.site.id), season)
	if not _check(left == ([goal] if bool(expect.still_due) else []), "what is left to collect this season (a fief that paid in full is not visited again)", left): _finish(); return
	# §4.3: a nation that collects by tax teams has its direct fiefs send nothing on the road on their next tax day.
	var next_day := TaxCalendar.day_index(float(nation_goal.terrain.site.get("minute", 0))) + 120
	while TaxPayTable.season_index(next_day) == season: next_day += 30
	var tax_day: Dictionary = TaxTribute.tax_day(nation_goal, next_day, TaxTribute.context_of(nation_goal))
	if not _check(str(tax_day.get("reason", "")) == "tax_team", "the fief's next tax day waits for the tax team", tax_day): _finish(); return
	report["tax_team"] = {"case": tax_case, "world": float(slot.control.logical_game_seconds), "collected": collected}
	_finish()
