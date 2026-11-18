extends RefCounted
## 貿易 T5 slice 1 (trade plan §7.2, TR-50): NPC caravans go out and come home. Trading at the destination is slice 2.
## - Dispatch (once a day on the live Site): a settlement whose head is not the player, with warehouses bound to its trade
##   (T2 trade_sources), sends one caravan when the world has fewer than MAX_ACTIVE missions and none is out from here.
##   The destination is a settlement the head knows of (a RegionSiteStrength receipt: object = that Site,
##   settlement_owner = its faction) of his own faction or one at peace with it, within REACH_SITES. The goods are, per
##   bound resource, at most its per-trade limit, what remains of its total and half the warehouse's stock, as much as
##   the team carries (CARRY per person); they leave the warehouse into the members' own cargo (TR-50: never in both)
##   and count against the source's used total (the reservation). A multi-person team of the settlement's faction (not
##   the player's, not garrisoned) leaves on its captain's word (captain:trade).
## - Trade (slice 2) and turn back (each Region evaluation of a Site, live or cold): a mission "out" whose captain stands on
##   its destination first sells, once, what its best-loaded member carries of its goods to the settlement there for
##   coin from a warehouse bound to its trade with a coin limit, on the settlement's own T2 terms (SiteTrade.counter_offer
##   on that warehouse's stock and a residents × 14 days food target, within the warehouse's quota); a counter offer is
##   taken as given, a refusal sells nothing. Then it is sent home (phase "back").
## - Home (each Region evaluation of its home Site): a mission "back" whose captain stands home unloads the mission's
##   goods its people still carry into the warehouse, gives back the unused reservation, and ends.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Payroll = preload("res://scripts/terrain_lab/site_payroll.gd")
const Strength = preload("res://scripts/region_lab/region_site_strength.gd")
const RegionAI = preload("res://scripts/region_lab/region_gameplay_ai.gd")
const Caravans = preload("res://scripts/region_lab/region_caravans.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const JoinFaction = preload("res://scripts/terrain_lab/site_join_faction.gd")
const Trade = preload("res://scripts/terrain_lab/site_trade.gd")
const Stockpiles = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const TradeSession = preload("res://scripts/terrain_lab/site_trade_session.gd")

const REACH_SITES := 3
const CARRY := Runtime.CARRY_CAPACITY

static func _coordinate(site_id: String) -> Vector2i:
	var parts := site_id.split(":")
	if parts.size() < 3 or not parts[parts.size() - 2].is_valid_int() or not parts[parts.size() - 1].is_valid_int(): return Vector2i(-2147483647, -2147483647)
	return Vector2i(int(parts[parts.size() - 2]), int(parts[parts.size() - 1]))

## The settlements the head knows of that a caravan may visit: [site_id], nearest first.
static func destinations(controller: Variant, head: int, faction: int) -> Array:
	var lab: Variant = controller.lab
	var slot: Variant = controller.region_slot
	var scope := str(lab.terrain.site.id)
	var now := float(slot.control.logical_game_seconds)
	var registry: Dictionary = slot.control.get("faction_registry", {})
	var known := RegionAI.view(slot.region_registry(), head, now, scope, RegionAI.person_ref(lab.terrain.site, head))
	var result: Array = []
	for object: String in known:
		var receipt: Dictionary = known[object]
		if receipt.get("observation_kind") != Strength.KIND or object == scope: continue
		var owner := int(receipt.value.get("settlement_owner", -1))
		if owner < 0 or not (owner == faction or RegionDiplomacy.at_peace(registry, faction, owner, now)): continue
		if Bandit.site_distance(scope, object) > REACH_SITES: continue
		result.append(object)
	result.sort_custom(func(a: String, b: String) -> bool: return Bandit.site_distance(scope, a) < Bandit.site_distance(scope, b) or Bandit.site_distance(scope, a) == Bandit.site_distance(scope, b) and a < b)
	return result

## The goods a caravan takes from `warehouse`, at most `room` units.
static func goods_for(data: TerrainData, warehouse: String, cargo: Dictionary, room: int) -> Dictionary:
	var source: Dictionary = Settlement.record(data).get("trade_sources", {}).get(warehouse, {})
	var goods := {}
	var keys: Array = source.get("limits", {}).keys()
	keys.sort()
	for resource: String in keys:
		if room <= 0: break
		var limit: Dictionary = source.limits[resource]
		var n := mini(mini(int(limit.per_trade), int(limit.total) - int(source.used.get(resource, 0))), int(cargo.get(resource, 0)) / 2)
		n = mini(n, room)
		if n <= 0: continue
		goods[resource] = n
		room -= n
	return goods

static func _team_ready(lab: Variant, team: Dictionary) -> bool:
	for person: Variant in team.person_ids:
		var owner: Variant = lab.crowd_site.person_owner(int(person))
		if owner == null or not lab.crowd_site._split_exit_ready(owner, int(lab.crowd_site._index_by_id.get(int(person), -1))): return false
	return true

## Today's dispatch on the live Site. Returns {sent: {token, to, goods}} or {reason}.
static func dispatch(controller: Variant) -> Dictionary:
	var lab: Variant = controller.lab
	var slot: Variant = controller.region_slot
	if slot == null or lab.crowd_site == null or not lab.crowd_site.active: return {"reason": "no_crowd"}
	var settlement: Dictionary = Settlement.record(lab.terrain)
	if settlement.is_empty() or (settlement.get("trade_sources", {}) as Dictionary).is_empty(): return {"reason": "no_trade"}
	var head := int(Settlement.head_executor(lab, true))
	var player := int(lab.controlled_person_id())
	if head <= 0 or head == player: return {"reason": "no_npc_head"}
	var scope := str(lab.terrain.site.id)
	var active: Array = Caravans.missions(slot.region_registry())
	if active.size() >= Caravans.MAX_ACTIVE: return {"reason": "full"}
	if active.any(func(m: Dictionary) -> bool: return str(m.from_site) == scope): return {"reason": "busy"}
	var faction := int(settlement.owner_faction)
	var targets := destinations(controller, head, faction)
	if targets.is_empty(): return {"reason": "no_destination"}
	var team: Dictionary = {}
	for candidate: Dictionary in lab.crowd_site.teams:
		if bool(candidate.get("departed", false)) or int(candidate.get("faction", -1)) != faction or candidate.get("person_ids", []).size() < 2: continue
		if candidate.person_ids.has(player) or not str(lab.crowd_site.native_roster(int(candidate.team_id)).get("garrison_feature_id", "")).is_empty(): continue
		if int(controller.team_captain_of_team(int(candidate.team_id))) <= 0 or not _team_ready(lab, candidate): continue
		team = candidate
		break
	if team.is_empty(): return {"reason": "no_team"}
	var warehouses: Array = settlement.trade_sources.keys()
	warehouses.sort()
	var warehouse := ""
	var goods := {}
	var stock: Dictionary = {}
	for key: String in warehouses:
		stock = Payroll.source_of(lab, {"kind": "stock", "site_id": scope, "feature_id": key})
		if stock.is_empty(): continue
		goods = goods_for(lab.terrain, key, stock.cargo, CARRY * team.person_ids.size())
		if not goods.is_empty():
			warehouse = key
			break
	if goods.is_empty(): return {"reason": "no_goods"}
	# Load: the goods leave the warehouse into the members' own cargo, CARRY each.
	var loads: Array = []
	var left := goods.duplicate()
	for person: Variant in team.person_ids:
		var body: Dictionary = controller.person_actions._person(int(person), false)
		if body.is_empty(): continue
		var room := CARRY - Runtime.inventory_size(body.cargo)
		var share := {}
		for resource: String in left.keys():
			if room <= 0: break
			var n := mini(int(left[resource]), room)
			if n <= 0: continue
			share[resource] = n
			room -= n
			left[resource] = int(left[resource]) - n
			if int(left[resource]) <= 0: left.erase(resource)
		if share.is_empty(): continue
		var moved: Dictionary = Runtime.transfer_items(lab.terrain, stock.holder, stock.cargo, body.holder, body.cargo, share, [], int(stock.holder.version), int(body.holder.version))
		if not moved.ok: break
		loads.append({"person": int(person), "share": share})
	var undo := func() -> void:
		for step: Dictionary in loads:
			var body: Dictionary = controller.person_actions._person(int(step.person), false)
			Runtime.transfer_items(lab.terrain, body.holder, body.cargo, stock.holder, stock.cargo, step.share, [], int(body.holder.version), int(stock.holder.version), 2000000000)
	if not left.is_empty():
		undo.call()
		return {"reason": "no_room"}
	var captain := int(controller.team_captain_of_team(int(team.team_id)))
	var captain_ref: Dictionary = JoinFaction._world_ref(controller, captain)
	if captain_ref.is_empty():
		undo.call()
		return {"reason": "no_captain_ref"}
	var here: Dictionary = slot._coordinate(lab.terrain)
	var person: Dictionary = lab.crowd_site.combat_target(captain)
	var component: int = RegionTravelSite.start_component(slot, here.site, person.cell, lab.terrain)
	var token := "caravan_%s" % Crypto.new().generate_random_bytes(12).hex_encode()
	var to := str(targets[0])
	var prepared: Dictionary = slot.prepare_npc_region_dispatch(lab, "captain:trade", int(team.team_id), _coordinate(to), component, [], token)
	if not prepared.ok:
		undo.call()
		return {"reason": "dispatch_refused", "code": str(prepared.get("code", ""))}
	# The mission is in the ledger before the departure publishes, so both are saved together.
	var added := Caravans.add(slot.region_registry(), {"token": token, "faction": faction, "from_site": scope, "warehouse": warehouse, "to_site": to,
		"captain_ref": captain_ref, "goods": goods, "phase": "out", "day": int(float(slot.control.logical_game_seconds) / 86400.0)})
	if not added.ok:
		undo.call()
		return {"reason": "full"}
	Settlement.record_trade_payout(lab.terrain, warehouse, goods)
	var committed: Dictionary = slot.commit_npc_region_dispatch(prepared)
	if not committed.ok:
		Caravans.remove(slot.region_registry(), int(added.id))
		return {"reason": "dispatch_failed", "code": str(committed.get("code", ""))}
	if lab.terrain.site.get("notices") is Array: lab.terrain.site.notices.append("商隊出發前往 %s" % to)
	return {"sent": {"token": token, "to": to, "goods": goods, "team": int(team.team_id)}}

## Each Region evaluation of `lab`'s Site: turns arrived caravans back and ends the ones that came home. Returns
## {turned: [id], home: [id]}.
static func evaluate(slot: Variant, lab: Variant) -> Dictionary:
	var result := {"turned": [], "home": []}
	var ledger: Dictionary = slot.region_registry()
	if Caravans.missions(ledger).is_empty() or lab.site_controller == null: return result
	var controller: Variant = lab.site_controller
	var scope := str(lab.terrain.site.id)
	for mission: Dictionary in Caravans.missions(ledger).duplicate(true):
		var captain := RegionPeerage.world_person_id(mission.captain_ref)
		if captain <= 0 or lab._original_person_target(captain).is_empty(): continue
		if str(mission.phase) == "out" and str(mission.to_site) == scope:
			if not mission.has("sold"):
				var sold := sell_here(lab, controller, mission, captain)
				var stored: Dictionary = Caravans.find(ledger, int(mission.id))
				if not stored.is_empty(): stored["sold"] = sold.get("got", {}).duplicate()
				mission = stored if not stored.is_empty() else mission
				result["sold"] = sold
			if _send_home(slot, lab, controller, mission, captain).ok: result.turned.append(int(mission.id))
		elif str(mission.phase) == "back" and str(mission.from_site) == scope:
			if _unload(slot, lab, controller, mission, captain).ok: result.home.append(int(mission.id))
	return result

## Slice 2: the caravan's best-loaded member barters his share of the mission's goods with this settlement. Returns
## {ok, decision, gave {item: n}, got {item: n}, warehouse} or {ok false, code, tried}.
static func sell_here(lab: Variant, controller: Variant, mission: Dictionary, captain: int) -> Dictionary:
	var data: TerrainData = lab.terrain
	var settlement: Dictionary = Settlement.record(data)
	if settlement.is_empty() or (settlement.get("trade_sources", {}) as Dictionary).is_empty(): return {"ok": false, "code": "NO_MARKET"}
	var team_id := _team_of_person(lab, captain)
	if team_id < 0: return {"ok": false, "code": "NO_TEAM"}
	# The seller: the member carrying most of the mission's goods (one endpoint per side).
	var seller := -1
	var carried := {}
	for team: Variant in lab.team_owners():
		if int(team.team_id) != team_id: continue
		for index: Variant in (team.combat_units.keys() if team.combat_units is Dictionary else range(team.combat_units.size())):
			var identity: int = team.combat_identity(int(index))
			var body: Dictionary = controller.person_actions._person(identity, false)
			if body.is_empty(): continue
			var share := {}
			for resource: String in mission.goods:
				if int(body.cargo.get(resource, 0)) > 0: share[resource] = mini(int(mission.goods[resource]), int(body.cargo[resource]))
			if Trade._unit_count(TradeSession.goods(share)) > Trade._unit_count(TradeSession.goods(carried)):
				seller = identity
				carried = share
	if seller < 0 or carried.is_empty(): return {"ok": false, "code": "NOTHING_TO_SELL"}
	var warehouses: Array = settlement.trade_sources.keys()
	warehouses.sort()
	var tried: Array = []
	for key: String in warehouses:
		var limits: Dictionary = settlement.trade_sources[key].get("limits", {})
		var endpoint: Dictionary = Runtime.trade_endpoint(data, Stockpiles.identity(key))
		if not endpoint.get("ok", false): continue
		# Barter (T2 values carry no coin): the caravan asks for the first bound resource the warehouse holds that it
		# does not bring, half as many units as it offers.
		var wanted := ""
		var names: Array = limits.keys()
		names.sort()
		for resource: String in names:
			if resource == "coin" or carried.has(resource) or int(limits[resource].per_trade) <= 0 or int(endpoint.cargo.get(resource, 0)) <= 0: continue
			wanted = resource
			break
		if wanted.is_empty(): continue
		var receive := TradeSession.goods(carried)
		var ask := mini(mini(maxi(1, Trade._unit_count(receive) / 2), int(endpoint.cargo[wanted])), int(limits[wanted].per_trade))
		var give := TradeSession.goods({wanted: ask})
		var targets := {"food": float(Settlement.residents(lab).size() * TradeSession.SETTLEMENT_FOOD_DAYS)}
		var seller_ref := {"holder": "person:%d" % seller, "expected_version": int(Runtime.trade_endpoint(data, "person:%d" % seller).holder.version)}
		var warehouse_ref := {"holder": Stockpiles.identity(key), "expected_version": int(endpoint.holder.version)}
		var legal := func(r: Dictionary, g: Dictionary) -> bool:
			if not Settlement.trade_quota_refusal(data, key, g.resources).is_empty(): return false
			return bool(Runtime.exchange_items(data, seller_ref, warehouse_ref, r, g, true).ok)
		var answer: Dictionary = Trade.counter_offer(receive, give, endpoint.cargo, targets, controller.person_actions._person(seller, false).cargo, legal, 50.0, 0, data.site)
		tried.append([key, str(answer.get("decision", answer.get("code", "")))])
		if not answer.ok or str(answer.decision) == "REJECT": continue
		if Trade._unit_count(answer.receive) == 0 or Trade._unit_count(answer.give) == 0: continue
		var done: Dictionary = Runtime.exchange_items(data, seller_ref, warehouse_ref, answer.receive, answer.give)
		if not done.ok:
			tried.append([key, str(done.get("code", ""))])
			continue
		Settlement.record_trade_payout(data, key, answer.give.resources)
		if data.site.get("notices") is Array: data.site.notices.append("外來商隊在此成交")
		return {"ok": true, "decision": str(answer.decision), "gave": answer.receive.resources.duplicate(), "got": answer.give.resources.duplicate(), "warehouse": key}
	return {"ok": false, "code": "NO_DEAL", "tried": tried}

static func _team_of_person(lab: Variant, person: int) -> int:
	for team: Variant in lab.team_owners():
		for index: Variant in (team.combat_units.keys() if team.combat_units is Dictionary else range(team.combat_units.size())):
			if team.combat_identity(int(index)) == person: return int(team.team_id)
	return -1

static func _send_home(slot: Variant, lab: Variant, controller: Variant, mission: Dictionary, captain: int) -> Dictionary:
	var team_id := _team_of_person(lab, captain)
	if team_id < 0: return {"ok": false}
	var here: Dictionary = slot._coordinate(lab.terrain)
	var person: Dictionary = lab._original_person_target(captain)
	var component: int = RegionTravelSite.start_component(slot, here.site, person.cell, lab.terrain)
	var token := "caravan_back_%s" % Crypto.new().generate_random_bytes(12).hex_encode()
	var prepared: Dictionary = slot.prepare_npc_region_dispatch(lab, "captain:trade", team_id, _coordinate(str(mission.from_site)), component, [], token)
	if not prepared.ok: return prepared
	var stored: Dictionary = Caravans.find(slot.region_registry(), int(mission.id))
	if stored.is_empty(): return {"ok": false}
	var before := stored.duplicate(true)
	stored["phase"] = "back"
	stored["token"] = token
	var committed: Dictionary = slot.commit_npc_region_dispatch(prepared)
	if not committed.ok:
		stored.merge(before, true)
		return committed
	return {"ok": true}

static func _unload(slot: Variant, lab: Variant, controller: Variant, mission: Dictionary, captain: int) -> Dictionary:
	var stock: Dictionary = Payroll.source_of(lab, {"kind": "stock", "site_id": str(mission.from_site), "feature_id": str(mission.warehouse)})
	var team_id := _team_of_person(lab, captain)
	if stock.is_empty() or team_id < 0: return {"ok": false}
	var owing: Dictionary = mission.goods.duplicate()
	for resource: Variant in mission.get("sold", {}): owing[str(resource)] = int(owing.get(str(resource), 0)) + int(mission.sold[resource])
	var returned := {}
	for team: Variant in lab.team_owners():
		if int(team.team_id) != team_id: continue
		for index: Variant in (team.combat_units.keys() if team.combat_units is Dictionary else range(team.combat_units.size())):
			var body: Dictionary = controller.person_actions._person(team.combat_identity(int(index)), false)
			if body.is_empty(): continue
			var share := {}
			for resource: String in owing.keys():
				var n := mini(int(owing[resource]), int(body.cargo.get(resource, 0)))
				if n > 0: share[resource] = n
			if share.is_empty(): continue
			var moved: Dictionary = Runtime.transfer_items(lab.terrain, body.holder, body.cargo, stock.holder, stock.cargo, share, [], int(body.holder.version), int(stock.holder.version), 2000000000)
			if not moved.ok: continue
			for resource: String in share:
				owing[resource] = int(owing[resource]) - int(share[resource])
				returned[resource] = int(returned.get(resource, 0)) + int(share[resource])
				if int(owing[resource]) <= 0: owing.erase(resource)
	# The reservation of the goods that came back unsold is given back; what was sold stays used. What it got is unloaded too.
	var source: Dictionary = Settlement.record(lab.terrain).get("trade_sources", {}).get(str(mission.warehouse), {})
	for resource: String in returned:
		if not mission.goods.has(resource) or not source.get("used", {}).has(resource): continue
		source.used[resource] = maxi(0, int(source.used[resource]) - mini(int(returned[resource]), int(mission.goods[resource])))
	Caravans.remove(slot.region_registry(), int(mission.id))
	if lab.terrain.site.get("notices") is Array: lab.terrain.site.notices.append("商隊返回並卸貨")
	return {"ok": true, "returned": returned}
