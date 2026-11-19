extends RefCounted
## Trade T1-a (reports/trade-plan.md §5.1, §6.2): face-to-face personal trade between the controlled person and an NPC in
## the same Site. Offers, the per-pair daily concession count and delivery jobs live in the saved projection
## `site.trade` (SiteTrade schema); this owner reads and writes it, and SiteController drives advance() once per frame.
## - The NPC values with SiteTrade.accept / counter_offer: personal food target 3 days (1 ration a day), other targets 0,
##   required margin from its thrift axis, one concession per failed round per pair per game day (at most 4).
## - A crowd person trades in peace only (Nekki 2026-11-06 "A"; the endpoint guard in SiteRuntime.trade_endpoint).
## - Delivery: 2 action s + 0.1 per unit (at most 30); both representatives are busy; a move, an effective hit, KO,
##   capture, death, or a holder version change cancels it with nothing moved; completion commits once through
##   SiteRuntime.exchange_items.
## T2 (first slice): a settlement trades from one of its warehouses through whoever SiteOffices resolves for
## `settlement.trade` (市正; the head acts when it is vacant). The decider stands at the warehouse entrance and the
## outsider face to face with him (TR-26); the settlement values with its own food target (residents × 14 days).
const Trade = preload("res://scripts/terrain_lab/site_trade.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const PersonPersonality = preload("res://scripts/terrain_lab/person_personality.gd")
const FOOD_TARGET_DAYS := 3
const OFFER_SECONDS := 60.0
const MAX_CONCESSIONS := 4
const SETTLEMENT_FOOD_DAYS := 14
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Stockpiles = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const Market = preload("res://scripts/terrain_lab/site_market.gd")
const REACH := 2.0 # cells between the two representatives (face to face; crowd bodies keep about one cell apart)

var controller: Variant
## The results of the last advance() that ended deliveries (for the UI and tests).
var last_results: Array[Dictionary] = []

func _init(owner: Variant = null) -> void:
	controller = owner

func _lab() -> Variant:
	return controller.lab

func now() -> float:
	return float(_lab().fire_action_cursor)

func game_day() -> int:
	var site: Dictionary = _lab().terrain.site
	return floori((float(site.get("minute", 0)) + float(site.get("phase", 0.0))) / 1440.0)

## The saved projection, created on first use; its action cursor follows the Site's action clock.
func state() -> Dictionary:
	var site: Dictionary = _lab().terrain.site
	if not site.has("trade"): site["trade"] = Trade.new_snapshot(str(site.get("id", "")), now())
	site.trade["action_cursor"] = now()
	return site.trade

func sync_cursor() -> void:
	var site: Dictionary = _lab().terrain.site
	if site.has("trade"): site.trade["action_cursor"] = now()

static func goods(resources: Dictionary, item_ids: Array = []) -> Dictionary:
	var clean := {}
	for resource: Variant in resources:
		if int(resources[resource]) > 0: clean[str(resource)] = int(resources[resource])
	return {"resources": clean, "item_ids": item_ids.duplicate()}

func _person(identity: int) -> Dictionary:
	return controller.person_actions._person(identity)

func _holder_id(identity: int) -> String:
	return "person:%d" % identity

func _holder_version(holder_id: String) -> int:
	var endpoint: Dictionary = Runtime.trade_endpoint(_lab().terrain, holder_id)
	return int(endpoint.holder.version) if endpoint.ok else -1

func _ref(identity: int) -> Dictionary:
	return _holder_ref(_holder_id(identity))

func _holder_ref(holder_id: String) -> Dictionary:
	return {"holder": holder_id, "expected_version": maxi(0, _holder_version(holder_id))}

func _concession_key(npc_holder: String, player_holder: String, day: int) -> String:
	return JSON.stringify([npc_holder, player_holder, day])

func concessions(npc: int, player: int) -> int:
	return holder_concessions(_holder_id(npc), _holder_id(player))

func holder_concessions(npc_holder: String, player_holder: String) -> int:
	var entry: Variant = state().concessions.get(_concession_key(npc_holder, player_holder, game_day()))
	return int(entry.count) if entry is Dictionary else 0

func _concede(npc_holder: String, player_holder: String) -> void:
	var trade := state()
	var day := game_day()
	# Yesterday's counts reset: only today's entries are kept.
	for key: Variant in trade.concessions.keys():
		if int(trade.concessions[key].day) != day: trade.concessions.erase(key)
	var key := _concession_key(npc_holder, player_holder, day)
	var entry: Dictionary = trade.concessions.get(key, {"a": npc_holder, "b": player_holder, "day": day, "count": 0})
	entry["count"] = mini(MAX_CONCESSIONS, int(entry.count) + 1)
	trade.concessions[key] = entry

func _face_to_face(a: Dictionary, b: Dictionary) -> bool:
	return Vector2(a.cell).distance_to(Vector2(b.cell)) <= REACH

func _able(person: Dictionary) -> bool:
	return not person.is_empty() and float(person.get("hp", 0.0)) > 0.0 and float(person.get("ko", 0.0)) <= 0.0 \
		and not bool(person.get("captive", false)) and not bool(person.get("surrender_pending", false))

## A job key for a representative, or "" (busy lookup for SitePersonActions.is_busy).
func job_of(identity: int) -> String:
	var site: Dictionary = _lab().terrain.site
	if not site.has("trade"): return ""
	for key: Variant in site.trade.jobs:
		var offer: Dictionary = site.trade.offers.get(site.trade.jobs[key].offer_id, {})
		if int(offer.get("a_representative", -1)) == identity or int(offer.get("b_representative", -1)) == identity: return str(key)
	return ""

func busy(identity: int) -> bool:
	return not job_of(identity).is_empty()

func _check_pair(player: int, npc: int, npc_holder: String = "") -> Dictionary:
	if player == npc: return Runtime.fail("INVALID", "不能和自己交易")
	var a := _person(player)
	var b := _person(npc)
	if a.is_empty() or b.is_empty(): return Runtime.fail("NO_TARGET", "交易對象不在此地")
	if bool(b.get("player", false)): return Runtime.fail("INVALID", "對方是受控人物")
	if not _able(a) or not _able(b): return Runtime.fail("BUSY", "交易雙方須清醒、自由")
	if not _face_to_face(a, b): return Runtime.fail("TOO_FAR", "須當面交易（兩格內）")
	if controller.person_actions.is_busy(player) or controller.person_actions.is_busy(npc): return Runtime.fail("BUSY", "交易雙方須空閒")
	if hostile(a, b): return Runtime.fail("HOSTILE", "敵對勢力之間不能交易")
	for holder: String in [_holder_id(player), npc_holder if not npc_holder.is_empty() else _holder_id(npc)]:
		var endpoint: Dictionary = Runtime.trade_endpoint(_lab().terrain, holder)
		if not endpoint.ok: return endpoint
	if npc_holder.begins_with("feature:") or npc_holder.begins_with("vehicle:"):
		var party := source_party(npc_holder)
		if not party.ok: return party
		if int(party.decider) != npc: return Runtime.fail("NO_AUTHORITY", "此貨由「%s」負責交易" % str(party.position_name))
		if Vector2(b.cell).distance_to(Vector2(party.cell)) > REACH: return Runtime.fail("TOO_FAR", "代表須站在倉庫門口或車旁")
	return Runtime.ok("", {"a": a, "b": b})

## The organization side of a trade by its holder: a settlement warehouse or a team's stopped cart / wagon.
func source_party(holder: String) -> Dictionary:
	if holder.begins_with("feature:") and Stockpiles.family_estate(_lab().terrain, holder.trim_prefix("feature:")): return family_party(holder.trim_prefix("feature:"))
	if holder.begins_with("feature:"): return settlement_party(holder.trim_prefix("feature:"))
	if holder.begins_with("vehicle:"): return vehicle_party(holder.trim_prefix("vehicle:"))
	return Runtime.fail("UNSUPPORTED")

## T2 §4.1: the family estate trades through whoever SiteOffices resolves for `family.estate` (管家; the family head
## acts when it is vacant), a family member standing at the estate's door; the family values with its local members
## × 14 days of food.
func family_party(key: String) -> Dictionary:
	var data: TerrainData = _lab().terrain
	var family: Variant = data.site.get("family")
	if not family is Dictionary or not family.has("offices") or not Stockpiles.family_estate(data, key): return Runtime.fail("NO_TARGET", "不是家產倉庫")
	var endpoint: Dictionary = Stockpiles.stock_endpoint(data, key)
	if endpoint.is_empty(): return Runtime.fail("NO_TARGET", "家產倉庫尚無庫存")
	SiteOffices.ensure_catalog(family.offices, "family")
	var head := int(SiteOffices.head_position(family.offices).get("holder", 0))
	var resolved: Dictionary = SiteOffices.resolve(family.offices, "family.estate", head,
		func(identity: int) -> bool: return Stockpiles.estate_access(data, key, identity) and _able(_person(identity)), true)
	if not resolved.ok: return Runtime.fail(str(resolved.code), str(resolved.get("message", "職責暫停")))
	if not Stockpiles.estate_access(data, key, int(resolved.decider)): return Runtime.fail("NO_AUTHORITY", "管家須是族人")
	var members := 0
	for member: Variant in family.get("members", []):
		if member is Dictionary and str(member.get("site_id", "")) == str(data.site.get("id", "")): members += 1
	return Runtime.ok("", {"decider": int(resolved.decider), "position_name": str(resolved.position_name), "cell": endpoint.cell,
		"holder": Stockpiles.identity(key), "cargo": endpoint.cargo, "members": members})

## T2 TR-27: a team's stopped cart or wagon trades through the team's current commander standing beside it; the
## team values with its members × 3 days of food (the personal target per member).
func vehicle_party(key: String) -> Dictionary:
	var data: TerrainData = _lab().terrain
	var vehicle: Dictionary = data.site.get("vehicles", {}).get(key, {})
	if vehicle.is_empty() or str(vehicle.get("kind", "")) not in ["cart", "wagon"]: return Runtime.fail("NO_TARGET", "只有停穩的陸車能交易")
	var endpoint: Dictionary = Runtime.trade_endpoint(data, "vehicle:" + key)
	if not endpoint.ok: return endpoint
	var crowd: Variant = _lab().crowd_site
	if crowd == null or not crowd.active: return Runtime.fail("UNSUPPORTED", "車輛交易需要群眾隊伍")
	var team: Dictionary = crowd._team_by_id(int(vehicle.get("team_id", -1)))
	if team.is_empty(): return Runtime.fail("NO_TARGET", "車輛沒有所屬隊伍")
	var decider := int(crowd.formation_state(int(team.formation)).get("current_person", -1))
	if decider <= 0 or not _able(_person(decider)): return Runtime.fail("OFFICE_PAUSED", "隊伍目前無人指揮")
	return Runtime.ok("", {"decider": decider, "position_name": "隊伍指揮者", "cell": data.cell_from_index(int(vehicle.cell)),
		"holder": "vehicle:" + key, "cargo": endpoint.cargo, "members": int(team.person_ids.size())})

## T2: the settlement side of a warehouse trade. The warehouse lies in the jurisdiction, belongs to the settlement's
## faction and has its stock; the decider is SiteOffices' `settlement.trade` (the head acts when it is vacant).
func settlement_party(key: String) -> Dictionary:
	var data: TerrainData = _lab().terrain
	var settlement: Dictionary = Settlement.record(data)
	if settlement.is_empty() or int(settlement.get("level", 0)) <= 0: return Runtime.fail("NO_TARGET", "此地沒有聚落")
	var feature: Dictionary = data.site.get("features", {}).get(key, {})
	if str(feature.get("kind", "")) not in Settlement.TRADE_SOURCE_KINDS or not Settlement.feature_in_jurisdiction(data, feature) \
		or int(feature.get("owner_faction", -1)) != int(settlement.owner_faction): return Runtime.fail("NO_TARGET", "不是聚落管轄內的倉庫或市集")
	var endpoint: Dictionary = Stockpiles.stock_endpoint(data, key)
	if endpoint.is_empty(): return Runtime.fail("NO_TARGET", "倉庫尚無庫存")
	if not settlement.get("trade_sources", {}).has(key): return Runtime.fail("NOT_BOUND", "此倉未經首長綁給市正")
	var offices: Dictionary = settlement.get("offices", {})
	SiteOffices.ensure_catalog(offices, "settlement")
	var head := int(SiteOffices.head_position(offices).get("holder", 0))
	var resolved: Dictionary = SiteOffices.resolve(offices, "settlement.trade", head, func(identity: int) -> bool: return _able(_person(identity)), true)
	if not resolved.ok: return Runtime.fail(str(resolved.code), str(resolved.get("message", "職責暫停")))
	return Runtime.ok("", {"decider": int(resolved.decider), "position_name": str(resolved.position_name), "cell": endpoint.cell,
		"holder": Stockpiles.identity(key), "cargo": endpoint.cargo, "faction": int(settlement.owner_faction)})

## T1-b (§5.5 with the diplomacy table): people of one side trade freely; different factions only when not hostile
## (peace or truce in RegionDiplomacy). A Site without a Region slot keeps every other faction hostile.
func hostile(a: Dictionary, b: Dictionary) -> bool:
	var fa := int(a.get("faction", -1))
	var fb := int(b.get("faction", -1))
	if RegionFactionQuery.same_side(fa, fb): return false
	# One team is one side, the neutral player's own start team included (neutral is not an alliance across teams).
	if a.get("owner") != null and a.owner == b.get("owner"): return false
	if controller.region_slot == null: return true
	return RegionDiplomacy.hostile(controller.region_slot.control.get("faction_registry", {}), fa, fb, float(controller.region_slot.control.logical_game_seconds))

func _npc_terms(npc: Dictionary) -> Dictionary:
	var axes: Dictionary = PersonPersonality.read(npc.body.get("personality") if npc.body is Dictionary else npc.body.get("personality"))
	return {"stock": npc.cargo, "targets": {"food": float(FOOD_TARGET_DAYS)}, "thrift": float(axes.get("thrift", 50))}

func _legal(player: int, npc_holder: String) -> Callable:
	var data: TerrainData = _lab().terrain
	var a_ref := _ref(player)
	var b_ref := _holder_ref(npc_holder)
	# Only a settlement warehouse has trade limits (a family estate has none).
	var source := npc_holder.trim_prefix("feature:") if npc_holder.begins_with("feature:") and not Stockpiles.family_estate(data, npc_holder.trim_prefix("feature:")) else ""
	# receive = what the NPC receives (the player gives), give = what the NPC gives.
	return func(receive: Dictionary, give: Dictionary) -> bool:
		if not source.is_empty() and not Settlement.trade_quota_refusal(data, source, give.resources).is_empty(): return false
		return bool(Runtime.exchange_items(data, a_ref, b_ref, receive, give, true).ok)

func _drop_offers_of(identities: Array) -> void:
	var trade := state()
	for key: Variant in trade.offers.keys():
		if trade.jobs.values().any(func(job: Dictionary) -> bool: return job.offer_id == key): continue
		var offer: Dictionary = trade.offers[key]
		if identities.has(int(offer.a_representative)) or identities.has(int(offer.b_representative)): trade.offers.erase(key)

## TR-25: open offers and deliveries from these warehouses end (a fall changed their owner); nothing moves.
func drop_sources(feature_keys: Array) -> int:
	var site: Dictionary = _lab().terrain.site
	if not site.has("trade"): return 0
	var trade := state()
	var dropped := 0
	for key: Variant in trade.jobs.keys():
		var offer: Dictionary = trade.offers.get(trade.jobs[key].offer_id, {})
		if feature_keys.has(str(offer.get("b", {}).get("holder", "")).trim_prefix("feature:")):
			_end(str(key), Runtime.fail("CANCELLED", "交易中止：聚落易主；未轉移任何物品"))
			dropped += 1
	for key: Variant in trade.offers.keys():
		if feature_keys.has(str(trade.offers[key].b.holder).trim_prefix("feature:")):
			trade.offers.erase(key)
			dropped += 1
	return dropped

## One round: the player offers `player_gives` for `npc_gives`. The NPC answers ACCEPT (the offer stands as given),
## COUNTER (an offer the NPC accepts, changed by the deterministic counter rule) or REJECT. A round that does not
## stand as given costs one concession for today (at most 4: five rounds). Moves no goods.
func propose(player: int, npc: int, player_gives: Dictionary, npc_gives: Dictionary) -> Dictionary:
	return _propose(player, npc, "", player_gives, npc_gives)

## T2: trade with the settlement's warehouse `key` through its decider `npc`.
func propose_settlement(player: int, npc: int, key: String, player_gives: Dictionary, npc_gives: Dictionary) -> Dictionary:
	return _propose(player, npc, Stockpiles.identity(key), player_gives, npc_gives)

## T2 TR-27: trade with a team's stopped cart or wagon `key` through its commander `npc`.
func propose_vehicle(player: int, npc: int, key: String, player_gives: Dictionary, npc_gives: Dictionary) -> Dictionary:
	return _propose(player, npc, "vehicle:" + key, player_gives, npc_gives)

## 貿易 T3 (§5.2 掛牌, TR-30): the player takes `lots` lots of market listing `row_id` from the settlement's trade decider
## `npc` standing at the market: no valuation or bargaining (a listing is a pre-approved offer); the delivery starts at
## once and commits once like any trade. Refused while the market is closed (TR-31), past the listing's lots for the
## day, or past the trade source's limits (TR-21).
func take_listing(player: int, npc: int, row_id: String, lots: int) -> Dictionary:
	var data: TerrainData = _lab().terrain
	var lot := Market.take_guard(data, row_id, lots)
	if not lot.ok: return lot
	var holder := Stockpiles.identity(str(lot.key))
	var pair := _check_pair(player, npc, holder)
	if not pair.ok: return pair
	var quota := Settlement.trade_quota_refusal(data, str(lot.key), lot.give.resources)
	if not quota.is_empty(): return Runtime.fail("QUOTA", quota)
	var preview: Dictionary = Runtime.exchange_items(data, _ref(player), _holder_ref(holder), lot.want, lot.give, true)
	if not preview.ok: return preview
	_drop_offers_of([player, npc])
	var trade := state()
	var offer_id := "%s:%d" % [str(trade.site_id), int(trade.next_seq)]
	trade["next_seq"] = int(trade.next_seq) + 1
	var at := now()
	trade.offers[offer_id] = {"revision": 1, "a": _ref(player), "b": _holder_ref(holder), "a_gives": lot.want.duplicate(true), "b_gives": lot.give.duplicate(true),
		"a_representative": player, "b_representative": npc, "created_action": at, "expires_action": at + OFFER_SECONDS,
		"accepted_a": false, "accepted_b": true}
	var started := accept(offer_id)
	if not started.ok:
		trade.offers.erase(offer_id)
		return started
	Market.reserve(data, offer_id, row_id, lots)
	return Runtime.ok("按掛牌成交：%s" % str(started.message), {"offer_id": offer_id, "job_id": str(started.job_id)})

func _propose(player: int, npc: int, npc_holder: String, player_gives: Dictionary, npc_gives: Dictionary) -> Dictionary:
	var pair := _check_pair(player, npc, npc_holder)
	if not pair.ok: return pair
	if Trade._unit_count(player_gives) == 0 or Trade._unit_count(npc_gives) == 0: return Runtime.fail("EMPTY", "雙方都要有付出的東西")
	var holder := npc_holder if not npc_holder.is_empty() else _holder_id(npc)
	if npc_holder.begins_with("feature:") and not Stockpiles.family_estate(_lab().terrain, npc_holder.trim_prefix("feature:")):
		var quota := Settlement.trade_quota_refusal(_lab().terrain, npc_holder.trim_prefix("feature:"), npc_gives.resources)
		if not quota.is_empty(): return Runtime.fail("QUOTA", quota)
	var preview: Dictionary = Runtime.exchange_items(_lab().terrain, _ref(player), _holder_ref(holder), player_gives, npc_gives, true)
	if not preview.ok: return preview
	var used := holder_concessions(holder, _holder_id(player))
	var terms := _npc_terms(pair.b)
	if not npc_holder.is_empty():
		# An organization values its own stock: a warehouse with residents × 14 days of food, a team vehicle with
		# its members × 3 days.
		terms["stock"] = Runtime.trade_endpoint(_lab().terrain, holder).cargo
		if npc_holder.begins_with("vehicle:"):
			terms["targets"] = {"food": float(int(vehicle_party(npc_holder.trim_prefix("vehicle:")).get("members", 1)) * FOOD_TARGET_DAYS)}
		elif Stockpiles.family_estate(_lab().terrain, npc_holder.trim_prefix("feature:")):
			terms["targets"] = {"food": float(int(family_party(npc_holder.trim_prefix("feature:")).get("members", 1)) * SETTLEMENT_FOOD_DAYS)}
		else:
			terms["targets"] = {"food": float(Settlement.residents(_lab()).size() * SETTLEMENT_FOOD_DAYS)}
	var answer: Dictionary = Trade.counter_offer(player_gives, npc_gives, terms.stock, terms.targets, pair.a.cargo, _legal(player, holder),
		float(terms.thrift), used, _lab().terrain.site)
	if not answer.ok: return answer
	var decision := str(answer.decision)
	if decision == "ACCEPT" and (answer.receive != player_gives or answer.give != npc_gives): decision = "COUNTER"
	if decision != "ACCEPT": _concede(holder, _holder_id(player))
	_drop_offers_of([player, npc])
	var result := {"decision": decision, "concessions": holder_concessions(holder, _holder_id(player))}
	if decision == "REJECT":
		var last := used >= MAX_CONCESSIONS
		return Runtime.ok("對方拒絕%s" % ("；今日議價已到底" if last else ""), result)
	var trade := state()
	var key := "%s:%d" % [str(trade.site_id), int(trade.next_seq)]
	trade["next_seq"] = int(trade.next_seq) + 1
	var at := now()
	trade.offers[key] = {"revision": 1, "a": _ref(player), "b": _holder_ref(holder), "a_gives": answer.receive.duplicate(true), "b_gives": answer.give.duplicate(true),
		"a_representative": player, "b_representative": npc, "created_action": at, "expires_action": at + OFFER_SECONDS,
		"accepted_a": false, "accepted_b": true}
	result["offer_id"] = key
	result["player_gives"] = answer.receive.duplicate(true)
	result["npc_gives"] = answer.give.duplicate(true)
	return Runtime.ok("對方接受" if decision == "ACCEPT" else "對方還價", result)

## The player accepts a standing offer: the delivery job starts (nothing moves until it completes).
func accept(offer_id: String) -> Dictionary:
	var trade := state()
	var offer: Dictionary = trade.offers.get(offer_id, {})
	if offer.is_empty(): return Runtime.fail("NO_TARGET", "報價不存在或已失效")
	if now() > float(offer.expires_action):
		trade.offers.erase(offer_id)
		return Runtime.fail("EXPIRED", "報價已過期")
	var player := int(offer.a_representative)
	var npc := int(offer.b_representative)
	var b_holder := str(offer.b.holder)
	var pair := _check_pair(player, npc, b_holder if b_holder != _holder_id(npc) else "")
	if not pair.ok: return pair
	if _holder_version(str(offer.a.holder)) != int(offer.a.expected_version) or _holder_version(b_holder) != int(offer.b.expected_version):
		trade.offers.erase(offer_id)
		return Runtime.fail("STALE", "持物已改變，請重新報價")
	var preview: Dictionary = Runtime.exchange_items(_lab().terrain, offer.a, offer.b, offer.a_gives, offer.b_gives, true)
	if not preview.ok: return preview
	offer["accepted_a"] = true
	var units := Trade.job_unit_count(offer.a_gives) + Trade.job_unit_count(offer.b_gives)
	var key := "%s:%d" % [str(trade.site_id), int(trade.next_seq)]
	trade["next_seq"] = int(trade.next_seq) + 1
	trade.jobs[key] = {"offer_id": offer_id, "offer_revision": int(offer.revision), "started_action": now(), "elapsed": 0.0,
		"required": minf(30.0, 2.0 + units * 0.1), "pending": false, "a_cell": [int(pair.a.cell.x), int(pair.a.cell.y)],
		"b_cell": [int(pair.b.cell.x), int(pair.b.cell.y)], "a_hit": int(pair.a.hit), "b_hit": int(pair.b.hit)}
	return Runtime.ok("開始交付（%.1f 秒）" % float(trade.jobs[key].required), {"job_id": key})

func _end(key: String, result: Dictionary) -> Dictionary:
	var trade := state()
	var job: Dictionary = trade.jobs.get(key, {})
	trade.jobs.erase(key)
	if not job.is_empty():
		trade.offers.erase(job.offer_id)
		Market.release(_lab().terrain, str(job.offer_id)) # a listed delivery that ended uncommitted frees its lots
	return result

## Once per frame: advance each delivery on the action clock, cancel on any interruption, commit when due.
func advance() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var site: Dictionary = _lab().terrain.site
	if not site.has("trade"): return results
	var trade := state()
	var at := now()
	# Expired offers that never became a job are dropped.
	for key: Variant in trade.offers.keys():
		var offer: Dictionary = trade.offers[key]
		var in_job: bool = trade.jobs.values().any(func(job: Dictionary) -> bool: return job.offer_id == key)
		if not in_job and at > float(offer.expires_action): trade.offers.erase(key)
	var keys: Array = trade.jobs.keys()
	keys.sort()
	for key: Variant in keys:
		var job: Dictionary = trade.jobs[key]
		var offer: Dictionary = trade.offers[job.offer_id]
		var reason := ""
		for side: String in ["a", "b"]:
			var person := _person(int(offer[side + "_representative"]))
			var cell: Array = job[side + "_cell"]
			if not _able(person): reason = "交易一方失去行動能力"
			# A crowd body settles within its cell neighbourhood while standing; leaving it (or the face-to-face reach)
			# is moving away.
			elif absi(person.cell.x - int(cell[0])) > 1 or absi(person.cell.y - int(cell[1])) > 1: reason = "交易一方離開位置"
			elif int(person.hit) != int(job[side + "_hit"]): reason = "交易一方受擊"
			elif _holder_version(str(offer[side].holder)) != int(offer[side].expected_version): reason = "持物已改變"
			if not reason.is_empty(): break
		if reason.is_empty() and hostile(_person(int(offer.a_representative)), _person(int(offer.b_representative))): reason = "雙方勢力已敵對"
		if reason.is_empty() and (str(offer.b.holder).begins_with("feature:") or str(offer.b.holder).begins_with("vehicle:")):
			var party := source_party(str(offer.b.holder))
			if not party.ok or int(party.decider) != int(offer.b_representative): reason = "組織交易負責人已變更"
		# TR-31: a market damaged, or under construction or repair, pauses its trades; nothing is made up later.
		var market_key := str(offer.b.holder).trim_prefix("feature:") if str(offer.b.holder).begins_with("feature:") else ""
		if reason.is_empty() and not market_key.is_empty() and str(_lab().terrain.site.get("features", {}).get(market_key, {}).get("kind", "")) == Market.KIND:
			var market_open: Dictionary = Market.open_state(_lab().terrain, market_key)
			if not bool(market_open.open): reason = str(Market.CLOSED_TEXT.get(str(market_open.reason), "市集暫停"))
		if reason.is_empty() and not _face_to_face(_person(int(offer.a_representative)), _person(int(offer.b_representative))): reason = "雙方已不在面前"
		if not reason.is_empty():
			results.append(_end(str(key), Runtime.fail("CANCELLED", "交易中止：%s；未轉移任何物品" % reason)))
			continue
		job["elapsed"] = minf(float(job.required), at - float(job.started_action))
		job["pending"] = float(job.elapsed) >= float(job.required)
		if not bool(job.pending): continue
		var source := str(offer.b.holder).trim_prefix("feature:") if str(offer.b.holder).begins_with("feature:") else ""
		if Stockpiles.family_estate(_lab().terrain, source): source = "" # an estate has no trade limits
		if not source.is_empty():
			var quota := Settlement.trade_quota_refusal(_lab().terrain, source, offer.b_gives.resources)
			if not quota.is_empty():
				results.append(_end(str(key), Runtime.fail("QUOTA", "交易中止：%s；未轉移任何物品" % quota)))
				continue
		var committed: Dictionary = Runtime.exchange_items(_lab().terrain, offer.a, offer.b, offer.a_gives, offer.b_gives)
		if committed.ok and not source.is_empty(): Settlement.record_trade_payout(_lab().terrain, source, offer.b_gives.resources)
		if committed.ok: Market.commit(_lab().terrain, str(job.offer_id)) # a listed delivery counts its lots for the day
		results.append(_end(str(key), Runtime.ok("交易完成") if committed.ok else committed))
	if not results.is_empty(): last_results = results.duplicate()
	return results
