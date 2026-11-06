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
const Trade = preload("res://scripts/terrain_lab/site_trade.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const PersonPersonality = preload("res://scripts/terrain_lab/person_personality.gd")
const FOOD_TARGET_DAYS := 3
const OFFER_SECONDS := 60.0
const MAX_CONCESSIONS := 4
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

func _ref(identity: int) -> Dictionary:
	var person := _person(identity)
	return {"holder": _holder_id(identity), "expected_version": int(person.holder.version) if not person.is_empty() else 0}

func _concession_key(npc: int, player: int, day: int) -> String:
	return JSON.stringify([_holder_id(npc), _holder_id(player), day])

func concessions(npc: int, player: int) -> int:
	var entry: Variant = state().concessions.get(_concession_key(npc, player, game_day()))
	return int(entry.count) if entry is Dictionary else 0

func _concede(npc: int, player: int) -> void:
	var trade := state()
	var day := game_day()
	# Yesterday's counts reset: only today's entries are kept.
	for key: Variant in trade.concessions.keys():
		if int(trade.concessions[key].day) != day: trade.concessions.erase(key)
	var key := _concession_key(npc, player, day)
	var entry: Dictionary = trade.concessions.get(key, {"a": _holder_id(npc), "b": _holder_id(player), "day": day, "count": 0})
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

func _check_pair(player: int, npc: int) -> Dictionary:
	if player == npc: return Runtime.fail("INVALID", "不能和自己交易")
	var a := _person(player)
	var b := _person(npc)
	if a.is_empty() or b.is_empty(): return Runtime.fail("NO_TARGET", "交易對象不在此地")
	if bool(b.get("player", false)): return Runtime.fail("INVALID", "對方是受控人物")
	if not _able(a) or not _able(b): return Runtime.fail("BUSY", "交易雙方須清醒、自由")
	if not _face_to_face(a, b): return Runtime.fail("TOO_FAR", "須當面交易（兩格內）")
	if controller.person_actions.is_busy(player) or controller.person_actions.is_busy(npc): return Runtime.fail("BUSY", "交易雙方須空閒")
	for side: Dictionary in [a, b]:
		var endpoint: Dictionary = Runtime.trade_endpoint(_lab().terrain, _holder_id(int(side.person_id)))
		if not endpoint.ok: return endpoint
	return Runtime.ok("", {"a": a, "b": b})

func _npc_terms(npc: Dictionary) -> Dictionary:
	var axes: Dictionary = PersonPersonality.read(npc.body.get("personality") if npc.body is Dictionary else npc.body.get("personality"))
	return {"stock": npc.cargo, "targets": {"food": float(FOOD_TARGET_DAYS)}, "thrift": float(axes.get("thrift", 50))}

func _legal(player: int, npc: int) -> Callable:
	var data: TerrainData = _lab().terrain
	var a_ref := _ref(player)
	var b_ref := _ref(npc)
	# receive = what the NPC receives (the player gives), give = what the NPC gives.
	return func(receive: Dictionary, give: Dictionary) -> bool:
		return bool(Runtime.exchange_items(data, a_ref, b_ref, receive, give, true).ok)

func _drop_offers_of(identities: Array) -> void:
	var trade := state()
	for key: Variant in trade.offers.keys():
		if trade.jobs.values().any(func(job: Dictionary) -> bool: return job.offer_id == key): continue
		var offer: Dictionary = trade.offers[key]
		if identities.has(int(offer.a_representative)) or identities.has(int(offer.b_representative)): trade.offers.erase(key)

## One round: the player offers `player_gives` for `npc_gives`. The NPC answers ACCEPT (the offer stands as given),
## COUNTER (an offer the NPC accepts, changed by the deterministic counter rule) or REJECT. A round that does not
## stand as given costs one concession for today (at most 4: five rounds). Moves no goods.
func propose(player: int, npc: int, player_gives: Dictionary, npc_gives: Dictionary) -> Dictionary:
	var pair := _check_pair(player, npc)
	if not pair.ok: return pair
	if Trade._unit_count(player_gives) == 0 or Trade._unit_count(npc_gives) == 0: return Runtime.fail("EMPTY", "雙方都要有付出的東西")
	var preview: Dictionary = Runtime.exchange_items(_lab().terrain, _ref(player), _ref(npc), player_gives, npc_gives, true)
	if not preview.ok: return preview
	var used := concessions(npc, player)
	var terms := _npc_terms(pair.b)
	var answer: Dictionary = Trade.counter_offer(player_gives, npc_gives, terms.stock, terms.targets, pair.a.cargo, _legal(player, npc),
		float(terms.thrift), used, _lab().terrain.site)
	if not answer.ok: return answer
	var decision := str(answer.decision)
	if decision == "ACCEPT" and (answer.receive != player_gives or answer.give != npc_gives): decision = "COUNTER"
	if decision != "ACCEPT": _concede(npc, player)
	_drop_offers_of([player, npc])
	var result := {"decision": decision, "concessions": concessions(npc, player)}
	if decision == "REJECT":
		var last := used >= MAX_CONCESSIONS
		return Runtime.ok("對方拒絕%s" % ("；今日議價已到底" if last else ""), result)
	var trade := state()
	var key := "%s:%d" % [str(trade.site_id), int(trade.next_seq)]
	trade["next_seq"] = int(trade.next_seq) + 1
	var at := now()
	trade.offers[key] = {"revision": 1, "a": _ref(player), "b": _ref(npc), "a_gives": answer.receive.duplicate(true), "b_gives": answer.give.duplicate(true),
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
	var pair := _check_pair(player, npc)
	if not pair.ok: return pair
	if int(pair.a.holder.version) != int(offer.a.expected_version) or int(pair.b.holder.version) != int(offer.b.expected_version):
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
	if not job.is_empty(): trade.offers.erase(job.offer_id)
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
			elif int(person.holder.version) != int(offer[side].expected_version): reason = "持物已改變"
			if not reason.is_empty(): break
		if reason.is_empty() and not _face_to_face(_person(int(offer.a_representative)), _person(int(offer.b_representative))): reason = "雙方已不在面前"
		if not reason.is_empty():
			results.append(_end(str(key), Runtime.fail("CANCELLED", "交易中止：%s；未轉移任何物品" % reason)))
			continue
		job["elapsed"] = minf(float(job.required), at - float(job.started_action))
		job["pending"] = float(job.elapsed) >= float(job.required)
		if not bool(job.pending): continue
		var committed: Dictionary = Runtime.exchange_items(_lab().terrain, offer.a, offer.b, offer.a_gives, offer.b_gives)
		results.append(_end(str(key), Runtime.ok("交易完成") if committed.ok else committed))
	if not results.is_empty(): last_results = results.duplicate()
	return results
