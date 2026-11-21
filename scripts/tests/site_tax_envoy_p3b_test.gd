extends "res://scripts/tests/site_building_ui_test.gd"
## 軍餉與稅收 P3b slice 1 (pay-and-tax plan §4.5): the tax team's rules. A Site with one four-person team. Checks:
## - PT-16: a captain who is not an officer is refused CAPTAIN_NOT_OFFICER; with an officer captain, an empty 稅使
##   seat or a holder who is no 文吏 is refused NO_TAX_ENVOY; a 文吏 in the seat may collect;
## - owed: TRIBUTE_PERCENT of last season's receipts, less what was taken already;
## - handover: all paid (full), part did not fit (room: the rest is pending, not unpaid; PT-19), half promised or the
##   source short (partial), refused, nothing owed; coin goes first;
## - the NPC answer: lawless and ambitious refuses, a neutral head pays;
## - settle: full gives the head +1 credit and a paid season, refused takes 2 credit and counts an unpaid one;
## - the team's cart: its room counts first; the tax goes into it and comes out of it at home;
## - the ledger: routes and collections validate with the Region registry, a second visit owes only what is left
##   (never more than due), planned stops are known, a malformed route is refused, the field stays while collections
##   are remembered.
## Output: SITE_TAX_ENVOY_P3B_PASS on success; quit(1) on failure.

const Envoy = preload("res://scripts/terrain_lab/site_tax_envoy.gd")
const TaxRoutes = preload("res://scripts/region_lab/region_tax_routes.gd")
const GameplayClock = preload("res://scripts/region_lab/region_gameplay_clock.gd")
const TaxTribute = preload("res://scripts/terrain_lab/site_tribute.gd")
const TaxStocks = preload("res://scripts/terrain_lab/site_stockpiles.gd")

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_TAX_ENVOY_P3B OK ", checks, ": ", message)
		return true
	push_error("SITE_TAX_ENVOY_P3B_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _route(n: int, faction: int, season: int, stops: Array) -> Dictionary:
	return {"token": "tax_%d" % n, "faction": faction, "season": season, "home_site": "a:0:0",
		"captain_ref": RegionPeerage.world_person_ref("w1", 700 + n), "envoy_ref": RegionPeerage.world_person_ref("w1", 800 + n),
		"stops": stops, "done": {}, "phase": "out", "day": 0}

func _run() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var team: TerrainArmy = lab.army
	team.roster_size = 4
	team.faction_id = 1
	if not _ok(team.deploy_at(data, null, null, [Vector2i(30, 26), Vector2i(31, 26), Vector2i(32, 26), Vector2i(33, 26)]) and team.enable_combat(false), "a four-person team deploys"): return
	team.set_process(false)
	team.settle_combat_command()

	# PT-16.
	var captain_index := int(team.formal_commander)
	team.combat_units[captain_index]["military_role"] = "soldier"
	if not _ok(str(Envoy.dispatch_refusal(team).get("code", "")) == "CAPTAIN_NOT_OFFICER", "a captain who is no officer cannot lead a tax team", Envoy.dispatch_refusal(team)): return
	team.combat_units[captain_index]["military_role"] = "officer"
	if not _ok(str(Envoy.dispatch_refusal(team).get("code", "")) == "NO_TAX_ENVOY", "an empty 稅使 seat: no tax", Envoy.dispatch_refusal(team)): return
	var clerk := -1
	for index: int in range(team.combat_units.size()):
		if index != captain_index and team.is_member(index):
			clerk = team.combat_identity(index)
			break
	var offices: Dictionary = team.team_offices()
	var seat: Dictionary = SiteOffices.position(offices, str(offices.duties.get(Envoy.DUTY, "")))
	if not _ok(not seat.is_empty() and clerk > 0, "the team has a 稅使 seat and a member to fill it", offices.get("duties")): return
	seat["holder"] = clerk
	if not _ok(str(Envoy.dispatch_refusal(team).get("code", "")) == "NO_TAX_ENVOY", "a holder who is no 文吏 is no 稅使"): return
	if not _ok(team.set_civil_role(clerk, "clerk") and Envoy.envoy_of(team) == clerk and Envoy.dispatch_refusal(team).is_empty(), "a 文吏 in the seat: the team may collect"): return

	# owed.
	var record := {"receipts": {"season": 5, "current": {"produce_tax": 900}, "previous": {"produce_tax": 4000, "market": 1000}}, "paid_seasons": 3, "unpaid_seasons": 0}
	if not _ok(Envoy.owed(record, 5, 0) == {"due": 500, "owed": 500} and Envoy.owed(record, 5, 300) == {"due": 500, "owed": 200} and Envoy.owed(record, 5, 900).owed == 0,
		"10 percent of last season's receipts, less what was taken", Envoy.owed(record, 5, 0)): return

	# handover.
	var cargo := {"coin": 3, "grain": 40}
	var full := Envoy.handover(500, cargo, 100, "pay")
	if not _ok(full.outcome == "full" and int(full.goods.get("coin", 0)) == 3 and full.paid == TaxTribute.goods_tenths(full.goods) and full.pending == 0 and full.unpaid < 10, "all paid, coin first", full): return
	var room := Envoy.handover(500, cargo, 5, "pay")
	if not _ok(room.outcome == "room" and room.goods == {"coin": 3, "grain": 2} and room.pending > 0 and room.unpaid < 10 and room.paid + room.pending == full.paid, "PT-19: what does not fit is pending, not unpaid", room): return
	var half := Envoy.handover(500, cargo, 100, "partial")
	if not _ok(half.outcome == "partial" and half.paid <= 250 and half.unpaid >= 250, "half promised: partial", half): return
	var short := Envoy.handover(500, {"coin": 1}, 100, "pay")
	if not _ok(short.outcome == "partial" and short.goods == {"coin": 1} and short.unpaid == 400, "the source is short: partial", short): return
	if not _ok(Envoy.handover(500, cargo, 100, "refuse") == {"outcome": "refused", "goods": {}, "paid": 0, "pending": 0, "unpaid": 500} and Envoy.handover(0, cargo, 100, "pay").outcome == "none", "refused; nothing owed"): return
	if not _ok(cargo == {"coin": 3, "grain": 40}, "the source is not changed by the rule"): return

	# NPC answer.
	var neutral := {"version": Envoy.Personality.VERSION}
	for axis: String in Envoy.Personality.AXES: neutral[axis] = Envoy.Personality.NEUTRAL
	var defiant := neutral.duplicate()
	defiant["lawful"] = 20
	defiant["ambition"] = 80
	if not _ok(Envoy.npc_decision(defiant) == "refuse" and Envoy.npc_decision(neutral) == "pay", "lawless and ambitious refuses; neutral pays"): return

	# settle.
	var head := team.combat_identity(captain_index)
	controller.adjust_reputation(head, 0.0, -50.0) # away from the credit ceiling
	var credit := int(controller.reputation_of(head).credit)
	Envoy.settle(controller, head, record, full)
	if not _ok(int(controller.reputation_of(head).credit) == credit + Envoy.Reputation.SCALE and int(record.paid_seasons) == 4 and int(record.unpaid_seasons) == 0, "full: +1 credit and a paid season", [controller.reputation_of(head), record]): return
	Envoy.settle(controller, head, record, Envoy.handover(500, cargo, 100, "refuse"))
	if not _ok(int(controller.reputation_of(head).credit) == credit - Envoy.Reputation.SCALE and int(record.paid_seasons) == 0 and int(record.unpaid_seasons) == 1, "refused: -2 credit and an unpaid season", [controller.reputation_of(head), record]): return

	# The ledger.
	var ledger := GameplayClock.empty_registry()
	var world := 100.0
	if not _ok(TaxRoutes.add(ledger, _route(1, 2, 5, ["a:1:0", "a:2:0"])).ok and GameplayClock.validate_registry(ledger, world).ok, "a route validates with the Region registry"): return
	if not _ok(TaxRoutes.planned(ledger, 2, "a:1:0", 5) and not TaxRoutes.planned(ledger, 2, "a:1:0", 6) and not TaxRoutes.planned(ledger, 3, "a:1:0", 5), "planned stops are known by faction and season"): return
	TaxRoutes.record_collection(ledger, 2, "a:1:0", 5, 500, 250)
	var again := TaxRoutes.record_collection(ledger, 2, "a:1:0", 5, 999, 400)
	if not _ok(int(again.due) == 500 and int(again.paid) == 500 and Envoy.owed(record, 5, int(TaxRoutes.collected_of(ledger, 2, "a:1:0", 5).paid)).owed == 0 and GameplayClock.validate_registry(ledger, world).ok,
		"a second visit takes what is left, never more than due", again): return
	var broken: Dictionary = ledger.duplicate(true)
	broken.tax_routes.routes[0].stops.append("a:0:0")
	var bad_outcome: Dictionary = ledger.duplicate(true)
	bad_outcome.tax_routes.routes[0].done["a:1:0"] = "lost"
	if not _ok(not GameplayClock.validate_registry(broken, world).ok and not GameplayClock.validate_registry(bad_outcome, world).ok, "the capital as a stop or an unknown outcome is refused"): return
	TaxRoutes.remove(ledger, 1)
	if not _ok(ledger.has("tax_routes") and TaxRoutes.routes(ledger).is_empty() and GameplayClock.validate_registry(ledger, world).ok, "the field stays while collections are remembered"): return

	# The team's cart (§4.5): its room counts first, the tax goes into it and comes out of it. (A cart travels with its
	# team only behind a driver: RegionTravel's VEHICLE_OPERATOR rule.)
	var key := _formal_feature(data, "warehouse", Vector2i(14, 14))
	if not _ok(TaxStocks.ensure_storage(data, key, 1).ok, "a warehouse holds the fief's tax"): return
	var stock := {"holder": data.site.stockpiles[key].holder, "cargo": data.site.stockpiles[key].cargo}
	stock.cargo.clear()
	stock.cargo["coin"] = 12
	for index: int in range(team.combat_units.size()):
		if not team.is_member(index): continue
		var person: Dictionary = controller.person_actions._person(team.combat_identity(index), false)
		var free := SiteRuntime.CARRY_CAPACITY - SiteRuntime.carried_size(person.cargo, person.holder)
		if free > 0: person.cargo["wood"] = int(person.cargo.get("wood", 0)) + free
	if not _ok(Envoy._room(lab, controller, team.team_id) == 0, "the people's hands are full"): return
	var cart := str(int(data.site.get("next_vehicle", 1)))
	data.site["next_vehicle"] = int(cart) + 1
	if not data.site.has("vehicles"): data.site["vehicles"] = {}
	data.site.vehicles[cart] = {"id": cart, "kind": "cart", "team_id": team.team_id, "cell": data.index(Vector2i(30, 27)), "facing": [1, 0],
		"holder": SiteRuntime.new_item_state("vehicle:" + cart), "cargo": {}, "move": {}, "operator_id": 0, "stop_pending": false}
	if not _ok(Envoy._room(lab, controller, team.team_id) == SiteVehicleTransport.CAPACITY.cart, "the team's cart has room", Envoy._room(lab, controller, team.team_id)): return
	var loaded := Envoy._move(lab, controller, team.team_id, stock, {"coin": 5}, true)
	if not _ok(loaded == {"coin": 5} and data.site.vehicles[cart].cargo == {"coin": 5} and int(stock.cargo.coin) == 7, "the tax goes into the cart", [loaded, data.site.vehicles[cart].cargo, stock.cargo]): return
	var unloaded := Envoy._move(lab, controller, team.team_id, stock, {"coin": 5}, false)
	if not _ok(unloaded == {"coin": 5} and data.site.vehicles[cart].cargo.is_empty() and int(stock.cargo.coin) == 12, "home, it comes out of the cart", [unloaded, data.site.vehicles[cart].cargo, stock.cargo]): return
	data.site.vehicles.erase(cart)
	print("SITE_TAX_ENVOY_P3B_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
