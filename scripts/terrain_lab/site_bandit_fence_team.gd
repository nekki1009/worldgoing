extends RefCounted
## 土匪 B5b-2 NPC 銷贓隊 (reports/bandit-faction-spec.md §7.1 item 7; Nekki 2026-11-22 chose A).
## - Want (the band's daily turn, SiteBanditDay, NPC chief standing in the live Site: no made-up history): the lair's hoard
##   holds goods other than food worth at least MIN_VALUE grain (SiteTradeValues), less food than the band eats in FOOD_DAYS
##   (one unit a person a day), no fence trip of the band is out, and the chief knows a settlement of another faction within
##   REACH_SITES (RegionSiteStrength receipts, as a far raid's targets).
## - Send (from the lair Site only): one multi-person team of the band without the chief or the player carries those goods
##   (CARRY each, the dearest first) out of the hoard. The trip is a caravan mission (RegionCaravans, `fence` true, warehouse
##   WAREHOUSE): the hoard's change and the mission are saved first, then the team leaves on its captain's word (captain:band);
##   a refused departure puts everything back.
## - Sell (SiteCaravan.sell_here at the destination, live or cold, once): the best-loaded member sells to one civilian of the
##   settlement (§7.1 rules 2–5: owner faction, civilian role, no office, no duty) who pays in food or coin from his own
##   cargo, at the fence price (SiteBanditFence.PRICE_FACTOR); nobody of the settlement may see the seller (WATCHED: no
##   sale). The meeting itself is abstracted as a caravan's trade is: the civilian comes to him. Then the caravan rules
##   send the team home.
## - Home (the band's daily turn at the lair Site, before today's decision): what the team carries of the mission's goods
##   and of what it got goes back into the hoard, the band's heat rises by Bandit.HEAT_FENCE when it sold, and the mission
##   ends, in one commit. A trip that just left is no longer on the lair Site the next day, so only a returned team is met.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const Caravans = preload("res://scripts/region_lab/region_caravans.gd")
const FarRaid = preload("res://scripts/terrain_lab/site_bandit_far_raid.gd")
const Fence = preload("res://scripts/terrain_lab/site_bandit_fence.gd")
const Values = preload("res://scripts/terrain_lab/site_trade_values.gd")
const Trade = preload("res://scripts/terrain_lab/site_trade.gd")
const TradeSession = preload("res://scripts/terrain_lab/site_trade_session.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Strength = preload("res://scripts/region_lab/region_site_strength.gd")
const JoinFaction = preload("res://scripts/terrain_lab/site_join_faction.gd")
const BanditAmnesty = preload("res://scripts/terrain_lab/site_bandit_amnesty.gd")
const PersonPersonality = preload("res://scripts/terrain_lab/person_personality.gd")
const CARAVAN_PATH := "res://scripts/terrain_lab/site_caravan.gd" # loaded on use: SiteCaravan preloads this script

const MIN_VALUE := 60
const FOOD_DAYS := 7
const REACH_SITES := 2
const WAREHOUSE := "hoard"
const CARRY := Runtime.CARRY_CAPACITY

## The last send / sell / home result (read by tests and diagnostics only; never saved).
static var last_result := {}

static func _caravan() -> Script:
	return load(CARAVAN_PATH)

static func _value(resource: String) -> float:
	return float(Values.RESOURCE_VALUES.get(resource, 0.0))

## {goods {item: n} other than food, food (units), value (grain worth of the goods)} of a hoard.
static func split(hoard: Dictionary) -> Dictionary:
	var goods := {}
	var food := 0
	var value := 0.0
	for item: Variant in hoard:
		var n := int(hoard[item])
		if n <= 0: continue
		if str(item) in Values.FOODS: food += n
		else:
			goods[str(item)] = n
			value += _value(str(item)) * n
	return {"goods": goods, "food": food, "value": value}

## The band's fence missions in the world ledger.
static func missions(slot: Variant, band: int) -> Array:
	return Caravans.missions(slot.region_registry()).filter(func(mission: Dictionary) -> bool:
		return bool(mission.get("fence", false)) and int(mission.faction) == band)

## The settlement this chief would send a fence trip to today, or {} (see the header).
static func want(controller: Variant, band: int, chief: int) -> Dictionary:
	var slot: Variant = controller.region_slot
	var lab: Variant = controller.lab
	if slot == null or chief <= 0 or not missions(slot, band).is_empty(): return {}
	var table: Dictionary = RegionFactionQuery.bandit_of(slot.control.faction_registry, band)
	var lair: Variant = table.get("lair")
	var scope := str(lab.terrain.site.id)
	if not lair is Dictionary or str(lair.site_id) != scope: return {}
	var hoard := split(table.get("hoard", {}))
	var eaters: int = BanditAmnesty._members(lab, band).size()
	if float(hoard.value) < MIN_VALUE or int(hoard.food) >= eaters * FOOD_DAYS: return {}
	var targets: Array = FarRaid.targets(controller, band, chief).filter(func(target: Dictionary) -> bool:
		return Bandit.site_distance(scope, str(target.site_id)) <= REACH_SITES)
	if targets.is_empty(): return {}
	targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := Bandit.site_distance(scope, str(a.site_id))
		var db := Bandit.site_distance(scope, str(b.site_id))
		return da < db or da == db and str(a.site_id) < str(b.site_id))
	return targets[0]

## The dearest goods first, at most `room` units.
static func load_for(goods: Dictionary, room: int) -> Dictionary:
	var names: Array = goods.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return _value(a) > _value(b) or _value(a) == _value(b) and a < b)
	var result := {}
	for item: String in names:
		if room <= 0: break
		var n := mini(int(goods[item]), room)
		if n <= 0: continue
		result[item] = n
		room -= n
	return result

static func _bump(body: Dictionary) -> void:
	if body.get("holder") is Dictionary and body.holder.has("version"): body.holder["version"] = int(body.holder.version) + 1

static func _hoard_change(registry: Dictionary, band: int, change: Dictionary, sign_value: int, heat_events: int, now: float) -> Dictionary:
	return Bandit._with_table(registry, band, func(table: Dictionary) -> void:
		var hoard: Dictionary = table.get("hoard", {})
		for item: String in change:
			var n := int(hoard.get(item, 0)) + sign_value * int(change[item])
			if n > 0: hoard[item] = mini(100000000, n)
			else: hoard.erase(item)
		if hoard.is_empty(): table.erase("hoard")
		else: table["hoard"] = hoard
		for _sale: int in range(heat_events): table["heat"] = Bandit.heat_after(int(table.get("heat", 0)), "fence"), now)

## Sends today's fence trip toward `target` (from want). {ok, token, team, goods, to} or a refusal.
static func send(controller: Variant, band: int, target: Dictionary) -> Dictionary:
	var lab: Variant = controller.lab
	var slot: Variant = controller.region_slot
	if lab.crowd_site == null or not lab.crowd_site.active: return _done(Runtime.fail("UNSUPPORTED", "群眾未啟用"))
	var scope := str(lab.terrain.site.id)
	var registry: Dictionary = slot.control.faction_registry
	var entry: Dictionary = registry.entries.get(str(band), {})
	var table: Dictionary = RegionFactionQuery.bandit_of(registry, band)
	if not table.get("lair") is Dictionary or str(table.lair.site_id) != scope: return _done(Runtime.fail("NO_LAIR", "銷贓隊只從山寨出發"))
	var chief: int = slot.person_id_of_ref(entry.get("leader_ref"))
	var player := int(lab.controlled_person_id())
	var caravan := _caravan()
	var team: Dictionary = {}
	var teams: Array = lab.crowd_site.teams.duplicate()
	teams.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.team_id) < int(b.team_id))
	for candidate: Dictionary in teams:
		if bool(candidate.get("departed", false)) or bool(candidate.get("solo", false)) or int(candidate.get("faction", -1)) != band: continue
		if candidate.get("person_ids", []).size() < 2 or candidate.person_ids.has(chief) or candidate.person_ids.has(player): continue
		if int(controller.team_captain_of_team(int(candidate.team_id))) <= 0 or not caravan._team_ready(lab, candidate): continue
		team = candidate
		break
	if team.is_empty(): return _done(Runtime.fail("NO_TEAM", "沒有可派出的隊伍"))
	var goods := load_for(split(table.get("hoard", {})).goods, CARRY * team.person_ids.size())
	if goods.is_empty(): return _done(Runtime.fail("NO_GOODS", "山寨沒有可銷的貨"))
	# Load: the goods leave the hoard into the members' own cargo, CARRY each (the hoard is a record, not a stock).
	var loads: Array = []
	var left := goods.duplicate()
	for person: Variant in team.person_ids:
		var body: Dictionary = controller.person_actions._person(int(person), false)
		if body.is_empty(): continue
		var share := load_for(left, CARRY - Runtime.inventory_size(body.cargo))
		if share.is_empty(): continue
		Runtime.add_items(body.cargo, share)
		_bump(body)
		for item: String in share:
			left[item] = int(left[item]) - int(share[item])
			if int(left[item]) <= 0: left.erase(item)
		loads.append({"person": int(person), "share": share})
	var unload := func() -> void:
		for step: Dictionary in loads:
			var body: Dictionary = controller.person_actions._person(int(step.person), false)
			Runtime.add_items(body.cargo, step.share, -1)
			for item: String in step.share:
				if int(body.cargo.get(item, 0)) <= 0: body.cargo.erase(item)
			_bump(body)
	if not left.is_empty():
		unload.call()
		return _done(Runtime.fail("NO_ROOM", "隊伍背不動"))
	var captain := int(controller.team_captain_of_team(int(team.team_id)))
	var captain_ref: Dictionary = JoinFaction._world_ref(controller, captain)
	var person: Dictionary = lab.crowd_site.combat_target(captain)
	if captain_ref.is_empty() or person.is_empty():
		unload.call()
		return _done(Runtime.fail("NO_COMMANDER", "隊長不在"))
	var now := float(slot.control.logical_game_seconds)
	var token := "band_fence_%s" % Crypto.new().generate_random_bytes(12).hex_encode()
	var ledger_before: Variant = slot.region_registry().get("caravans")
	ledger_before = ledger_before.duplicate(true) if ledger_before is Dictionary else null
	var restore_ledger := func() -> void:
		if ledger_before == null: slot.region_registry().erase("caravans")
		else: slot.region_registry()["caravans"] = ledger_before
	var added: Dictionary = Caravans.add(slot.region_registry(), {"token": token, "faction": band, "from_site": scope, "warehouse": WAREHOUSE,
		"to_site": str(target.site_id), "captain_ref": captain_ref, "goods": goods, "phase": "out", "day": int(now / 86400.0), "fence": true})
	if not added.ok:
		unload.call()
		return _done(added)
	# The hoard's change, the loads and the mission are saved first: the departure's preparation captures the Site its
	# commit binds (as a caravan's reservation, SiteCaravan._dispatch).
	var saved: Dictionary = controller.commit_registry(_hoard_change(registry, band, goods, -1, 0, now))
	if not saved.ok:
		restore_ledger.call()
		unload.call()
		return _done(saved)
	var undo := func(reason: Dictionary) -> Dictionary:
		restore_ledger.call()
		unload.call()
		var back: Dictionary = controller.commit_registry(_hoard_change(slot.control.faction_registry, band, goods, 1, 0, float(slot.control.logical_game_seconds)))
		reason["restored"] = bool(back.get("ok", false))
		return _done(reason)
	var here: Dictionary = slot._coordinate(lab.terrain)
	var component: int = RegionTravelSite.start_component(slot, here.site, person.cell, lab.terrain)
	var prepared: Dictionary = slot.prepare_npc_region_dispatch(lab, "captain:band", int(team.team_id), caravan._coordinate(str(target.site_id)), component, [], token)
	if not prepared.ok: return undo.call({"ok": false, "code": str(prepared.get("code", "")), "message": str(prepared.get("message", ""))})
	var committed: Dictionary = slot.commit_npc_region_dispatch(prepared)
	if not committed.ok:
		if slot.region_registry().get("parties", {}).has(token): return _done(committed) # the team left: the goods travel with it
		return undo.call({"ok": false, "code": str(committed.get("code", "")), "message": str(committed.get("message", ""))})
	if lab.terrain.site.get("notices") is Array: lab.terrain.site.notices.append("土匪派人出寨銷贓")
	return _done({"ok": true, "token": token, "team": int(team.team_id), "goods": goods, "to": str(target.site_id)})

## At the destination (SiteCaravan.sell_here for a fence mission): one sale to one unwatched civilian. Returns
## {ok, decision, gave, got, civilian} or {ok false, code}.
static func sell(lab: Variant, controller: Variant, mission: Dictionary, captain: int) -> Dictionary:
	var data: TerrainData = lab.terrain
	var settlement: Dictionary = Settlement.record(data)
	if settlement.is_empty() or not settlement.has("owner_faction") or int(settlement.owner_faction) == int(mission.faction): return _done({"ok": false, "code": "NO_MARKET"})
	var owner := int(settlement.owner_faction)
	var team_id: int = _caravan()._team_of_person(lab, captain)
	if team_id < 0: return _done({"ok": false, "code": "NO_TEAM"})
	# The seller: the member carrying most of the mission's goods.
	var seller := -1
	var carried := {}
	for team: Variant in lab.team_owners():
		if int(team.team_id) != team_id: continue
		for index: Variant in (team.combat_units.keys() if team.combat_units is Dictionary else range(team.combat_units.size())):
			var identity: int = team.combat_identity(int(index))
			var body: Dictionary = controller.person_actions._person(identity, false)
			if body.is_empty(): continue
			var share := {}
			for item: String in mission.goods:
				if int(body.cargo.get(item, 0)) > 0: share[item] = mini(int(mission.goods[item]), int(body.cargo[item]))
			if Runtime.inventory_size(share) > Runtime.inventory_size(carried):
				seller = identity
				carried = share
	if seller < 0 or carried.is_empty(): return _done({"ok": false, "code": "NOTHING_TO_SELL"})
	var seller_body: Dictionary = controller.person_actions._person(seller, false)
	if Fence.watched(controller, [seller_body.cell]): return _done({"ok": false, "code": "WATCHED"})
	var seller_end: Dictionary = Runtime.trade_endpoint(data, "person:%d" % seller)
	if not seller_end.get("ok", false): return _done({"ok": false, "code": str(seller_end.get("code", "")), "message": str(seller_end.get("message", ""))})
	# The civilians who could pay, the richest first.
	var buyers: Array = []
	for person: Dictionary in Strength.people(lab):
		if int(person.faction) != owner or bool(person.armed): continue
		var body: Dictionary = controller.person_actions._person(int(person.id), false)
		if body.is_empty() or not Fence.civilian_refusal(controller, int(person.id), body).is_empty(): continue
		# What he could pay: all his coin, and the food above his own reserve (a trade never takes him below it: SiteTrade
		# refuses RESERVE before any counter).
		var pay := {}
		var worth := 0.0
		var spare := 0
		for item: String in Values.FOODS: spare += int(body.cargo.get(item, 0))
		spare = maxi(0, spare - ceili(float(TradeSession.FOOD_TARGET_DAYS)))
		for item: String in Values.FOODS:
			var n := mini(spare, int(body.cargo.get(item, 0)))
			if n <= 0: continue
			pay[item] = n
			spare -= n
			worth += _value(item) * n
		if int(body.cargo.get("coin", 0)) > 0:
			pay["coin"] = int(body.cargo.coin)
			worth += float(body.cargo.coin)
		if not pay.is_empty(): buyers.append({"id": int(person.id), "pay": pay, "worth": worth})
	buyers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.worth) > float(b.worth) or float(a.worth) == float(b.worth) and int(a.id) < int(b.id))
	var tried: Array = []
	for buyer: Dictionary in buyers:
		var body: Dictionary = controller.person_actions._person(int(buyer.id), false)
		var share := load_for(carried, CARRY - Runtime.inventory_size(body.cargo) + Runtime.inventory_size(buyer.pay))
		if share.is_empty(): continue
		var buyer_end: Dictionary = Runtime.trade_endpoint(data, "person:%d" % int(buyer.id))
		if not buyer_end.get("ok", false): # in a fight, aboard, ...: he cannot trade now
			tried.append([int(buyer.id), str(buyer_end.get("code", ""))])
			continue
		var seller_ref := {"holder": "person:%d" % seller, "expected_version": int(Runtime.trade_endpoint(data, "person:%d" % seller).holder.version)}
		var buyer_ref := {"holder": "person:%d" % int(buyer.id), "expected_version": int(buyer_end.holder.version)}
		var legal := func(r: Dictionary, g: Dictionary) -> bool: return bool(Runtime.exchange_items(data, seller_ref, buyer_ref, r, g, true).ok)
		var thrift := float(PersonPersonality.read(body.body.get("personality") if body.get("body") is Dictionary else null).get("thrift", 50))
		var answer: Dictionary = Trade.counter_offer(TradeSession.goods(share), TradeSession.goods(buyer.pay), body.cargo, {"food": float(TradeSession.FOOD_TARGET_DAYS)},
			seller_body.cargo, legal, thrift, 0, data.site, {}, Fence.PRICE_FACTOR)
		tried.append([int(buyer.id), str(answer.get("decision", answer.get("code", "")))])
		if not answer.ok or str(answer.decision) == "REJECT" or Trade._unit_count(answer.receive) == 0 or Trade._unit_count(answer.give) == 0: continue
		var done: Dictionary = Runtime.exchange_items(data, seller_ref, buyer_ref, answer.receive, answer.give)
		if not done.ok:
			tried.append([int(buyer.id), str(done.get("code", ""))])
			continue
		if data.site.get("notices") is Array: data.site.notices.append("有人私下收了土匪的貨")
		return _done({"ok": true, "decision": str(answer.decision), "gave": answer.receive.resources.duplicate(), "got": answer.give.resources.duplicate(), "civilian": int(buyer.id)})
	return _done({"ok": false, "code": "NO_DEAL", "tried": tried})

## The band's fence teams home at the lair: unload into the hoard, heat for a sale, end the mission (one commit each).
## {ok, home: [{mission, returned, sold}], refusals}.
static func home(controller: Variant, band: int) -> Dictionary:
	var lab: Variant = controller.lab
	var slot: Variant = controller.region_slot
	var result := {"ok": true, "home": [], "refusals": []}
	if slot == null or lab.crowd_site == null or not lab.crowd_site.active: return result
	var scope := str(lab.terrain.site.id)
	var caravan := _caravan()
	for mission: Dictionary in missions(slot, band).duplicate(true):
		# "back", or still "out" when the team came home without trading (a raid team's way home, SiteBanditAftermath, can
		# bring it back from the live Site before its caravan evaluation): either way it ends here.
		if str(mission.from_site) != scope: continue
		var captain: int = slot.person_id_of_ref(mission.captain_ref)
		if captain <= 0 or lab._original_person_target(captain).is_empty(): continue
		var team_id: int = caravan._team_of_person(lab, captain)
		if team_id < 0: continue
		var owing: Dictionary = mission.goods.duplicate()
		for item: Variant in mission.get("sold", {}): owing[str(item)] = int(owing.get(str(item), 0)) + int(mission.sold[item])
		var taken: Array = []
		var returned := {}
		for team: Variant in lab.team_owners():
			if int(team.team_id) != team_id: continue
			for index: Variant in (team.combat_units.keys() if team.combat_units is Dictionary else range(team.combat_units.size())):
				var identity: int = team.combat_identity(int(index))
				var body: Dictionary = controller.person_actions._person(identity, false)
				if body.is_empty(): continue
				var share := {}
				for item: String in owing.keys():
					var n := mini(int(owing[item]), int(body.cargo.get(item, 0)))
					if n > 0: share[item] = n
				if share.is_empty(): continue
				Runtime.add_items(body.cargo, share, -1)
				for item: String in share:
					if int(body.cargo.get(item, 0)) <= 0: body.cargo.erase(item)
					owing[item] = int(owing[item]) - int(share[item])
					if int(owing[item]) <= 0: owing.erase(item)
					returned[item] = int(returned.get(item, 0)) + int(share[item])
				_bump(body)
				taken.append({"person": identity, "share": share})
		var sold: bool = not mission.get("sold", {}).is_empty()
		var ledger_before: Dictionary = slot.region_registry().get("caravans", {}).duplicate(true)
		Caravans.remove(slot.region_registry(), int(mission.id))
		var saved: Dictionary = controller.commit_registry(_hoard_change(slot.control.faction_registry, band, returned, 1, 1 if sold else 0, float(slot.control.logical_game_seconds)))
		if not saved.ok:
			slot.region_registry()["caravans"] = ledger_before
			for step: Dictionary in taken:
				var body: Dictionary = controller.person_actions._person(int(step.person), false)
				Runtime.add_items(body.cargo, step.share)
				_bump(body)
			result.refusals.append({"mission": int(mission.id), "code": str(saved.get("code", ""))})
			continue
		if lab.terrain.site.get("notices") is Array: lab.terrain.site.notices.append("銷贓隊回寨")
		result.home.append({"mission": int(mission.id), "returned": returned, "sold": sold})
	if not result.home.is_empty() or not result.refusals.is_empty(): _done(result)
	return result

static func _done(result: Dictionary) -> Dictionary:
	last_result = result.duplicate(true)
	return result
