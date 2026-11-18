extends RefCounted
## 軍餉與稅收 P3b slice 1 (reports/pay-and-tax-plan.md §4.5; PT-16, PT-19 rules): the nation's tax team, its rules only.
## The trip itself (dispatch from the capital, stop by stop, home to the treasury) is slice 2.
## - The team: an ordinary team whose formal captain is an officer and whose 稅使 seat (team.tax_envoy) is held by a
##   present member who is a 文吏 or better. Otherwise "派收稅" is refused (CAPTAIN_NOT_OFFICER, NO_TAX_ENVOY).
## - The stops: the direct fiefs of the faction head (his vassals' seats), nearest to the capital first, without the
##   capital itself and without a fief already planned this season by another team of the faction.
## - The handover at a stop: the fief owes TRIBUTE_PERCENT of last season's receipts (§4.3) less what tax teams took
##   from it this season already (RegionTaxRoutes.collected). The head pays all, half ("partial") or nothing
##   ("refuse"), coin first, then food, from its tax source. What the team cannot carry stays owed as pending, not
##   arrears (PT-19). Outcomes: "full" (all paid), "room" (all offered, part did not fit), "partial" (paid less than
##   owed), "refused", "none" (nothing owed).
## - An NPC head refuses when he is both lawless and ambitious (lawful <= REFUSE_LAWFUL and ambition >= REFUSE_AMBITION:
##   the plan's "by his L to the nation and his character"; L to the nation is not kept per person, so character
##   decides); otherwise he pays what he can.
## - Consequences on the fief's finance record, as on a tax day (SiteTribute.tax_day): full or room: +1 credit, every
##   fourth season in a row +2 prestige; partial or refused: -2 credit and one more unpaid season.
const Tribute = preload("res://scripts/terrain_lab/site_tribute.gd")
const PayTable = preload("res://scripts/terrain_lab/site_pay_table.gd")
const Finance = preload("res://scripts/terrain_lab/site_finance.gd")
const Reputation = preload("res://scripts/terrain_lab/person_reputation.gd")
const RegionFinance = preload("res://scripts/region_lab/region_finance.gd")
const TaxRoutes = preload("res://scripts/region_lab/region_tax_routes.gd")
const Personality = preload("res://scripts/terrain_lab/person_personality.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")

const DUTY := "team.tax_envoy"
const DECISIONS := ["pay", "partial", "refuse"]
const REFUSE_LAWFUL := 25
const REFUSE_AMBITION := 75

## The team's 稅使: the person holding the seat, a present member who is a 文吏 or better; -1 when there is none.
static func envoy_of(army: Variant) -> int:
	if army == null or not army.has_method("team_offices"): return -1
	var offices: Dictionary = army.team_offices(true)
	if offices.is_empty(): return -1
	var position: Dictionary = SiteOffices.position(offices, str(offices.get("duties", {}).get(DUTY, "")))
	var holder := int(position.get("holder", -1))
	if holder <= 0: return -1
	var index: int = army.index_for_identity(holder)
	if index < 0 or army.member_gone(index) or not army.civil_role(index) in ["clerk", "official"]: return -1
	return holder

## {} when the team may collect tax, else {ok false, code, message} (PT-16).
static func dispatch_refusal(army: Variant) -> Dictionary:
	if army == null: return Runtime.fail("NO_TEAM", "沒有這支隊伍")
	var captain := int(army.formal_commander)
	if captain < 0 or army.military_role(captain) != "officer": return Runtime.fail("CAPTAIN_NOT_OFFICER", "稅隊隊長須為軍官")
	if envoy_of(army) <= 0: return Runtime.fail("NO_TAX_ENVOY", "隊中沒有稅使（文吏以上）")
	return {}

## The direct fiefs of `faction`'s head to visit from `home_site` this season: [site_id], nearest first.
static func fief_stops(registry: Dictionary, faction: int, home_site: String, season: int, ledger: Dictionary = {}) -> Array:
	var head: Dictionary = RegionPeerage.head_of(registry, faction)
	if not head.get("ok", false) or head.get("person_ref") == null: return []
	var sites: Array = []
	for vassal: Variant in RegionPeerage.vassals_of(registry, head.person_ref):
		var site := RegionFinance.seat_of(registry, RegionPeerage.key_of(vassal))
		if site.is_empty() or site == home_site or sites.has(site): continue
		if not ledger.is_empty() and TaxRoutes.planned(ledger, faction, site, season): continue
		sites.append(site)
	sites.sort_custom(func(a: String, b: String) -> bool:
		var da := RegionFinance.travel_days(home_site, a)
		var db := RegionFinance.travel_days(home_site, b)
		return da < db or da == db and a < b)
	return sites.slice(0, TaxRoutes.MAX_STOPS)

## What the fief owes this visit in tenths: TRIBUTE_PERCENT of last season's receipts, less what was taken already.
static func owed(record: Dictionary, season: int, already_paid: int) -> Dictionary:
	var base := 0
	for kind: String in Tribute.TRIBUTE_KINDS: base += Finance.receipts_of(record, kind, season, true)
	var due := base * Tribute.TRIBUTE_PERCENT / 100
	return {"due": due, "owed": maxi(0, due - maxi(0, already_paid))}

## Whole units of `goods` (in the order coin, then food) that fit in `room` units.
static func fit(goods: Dictionary, room: int) -> Dictionary:
	var result := {}
	var left := maxi(0, room)
	var order: Array = ["coin"]
	order.append_array(PayTable.FOOD_ORDER)
	for item: Variant in order:
		if left <= 0 or not goods.has(item): continue
		var n := mini(int(goods[item]), left)
		if n <= 0: continue
		result[item] = n
		left -= n
	return result

## The handover at a stop (pure): {outcome, goods, paid, pending, unpaid} in tenths of a point. `cargo` is the fief's
## tax source (not changed); `room` the units the team can still carry.
static func handover(owed_tenths: int, cargo: Dictionary, room: int, decision: String) -> Dictionary:
	if owed_tenths <= 0: return {"outcome": "none", "goods": {}, "paid": 0, "pending": 0, "unpaid": 0}
	if decision == "refuse": return {"outcome": "refused", "goods": {}, "paid": 0, "pending": 0, "unpaid": owed_tenths}
	var promised := owed_tenths if decision == "pay" else owed_tenths / 2
	var offered: Dictionary = Tribute.pick_goods(cargo, promised)
	var offered_tenths := Tribute.goods_tenths(offered)
	var goods := fit(offered, room)
	var paid := Tribute.goods_tenths(goods)
	var pending := offered_tenths - paid
	var unpaid := owed_tenths - offered_tenths
	var outcome := "partial"
	if unpaid < PayTable.TENTHS: outcome = "full" if pending < PayTable.TENTHS else "room"
	return {"outcome": outcome, "goods": goods, "paid": paid, "pending": pending, "unpaid": unpaid}

## An NPC head's answer to the tax team.
static func npc_decision(personality: Variant) -> String:
	var axes: Dictionary = Personality.read(personality)
	return "refuse" if int(axes.get("lawful", Personality.NEUTRAL)) <= REFUSE_LAWFUL and int(axes.get("ambition", Personality.NEUTRAL)) >= REFUSE_AMBITION else "pay"

## The handover's consequences on the fief's record and its head (as SiteTribute.tax_day): returns the notice.
static func settle(controller: Variant, head: int, record: Dictionary, result: Dictionary) -> String:
	match str(result.outcome):
		"full", "room":
			record.paid_seasons = int(record.get("paid_seasons", 0)) + 1
			record.unpaid_seasons = 0
			if head > 0: controller.adjust_reputation(head, Tribute.ON_TIME_PRESTIGE if int(record.paid_seasons) % Tribute.ON_TIME_PRESTIGE_EVERY == 0 else 0.0, float(Reputation.TAX_SEASON))
			return "稅隊收取本季上繳 %.1f 點%s" % [float(result.paid) / PayTable.TENTHS, "（車載不足，餘 %.1f 點待收）" % (float(result.pending) / PayTable.TENTHS) if str(result.outcome) == "room" else ""]
		"partial", "refused":
			record.paid_seasons = 0
			record.unpaid_seasons = int(record.get("unpaid_seasons", 0)) + 1
			if head > 0: controller.adjust_reputation(head, 0.0, Tribute.LATE_CREDIT)
			return ("聚落拒繳本季上繳" if str(result.outcome) == "refused" else "本季上繳不足（只交 %.1f 點）" % (float(result.paid) / PayTable.TENTHS)) + "，聚落長信譽 −2"
	return ""

# --- Slice 2: the round (dispatch from the capital, stop by stop, home to the treasury) -------------------------------
const Caravan = preload("res://scripts/terrain_lab/site_caravan.gd")
const JoinFaction = preload("res://scripts/terrain_lab/site_join_faction.gd")
const ProduceTax = preload("res://scripts/terrain_lab/site_produce_tax.gd")
const Payroll = preload("res://scripts/terrain_lab/site_payroll.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const CARRY := Runtime.CARRY_CAPACITY

## The last round decision or handover (read by tests and diagnostics only; never saved).
static var last_event := {}

static func _army_of(lab: Variant, team_id: int) -> Variant:
	for army: Variant in lab.combat_armies:
		if is_instance_valid(army) and int(army.team_id) == team_id: return army
	return null

static func _crowd_team(lab: Variant, team_id: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if int(team.team_id) == team_id and not bool(team.get("departed", false)): return team
	return {}

static func _season(lab: Variant) -> int:
	return PayTable.season_index(Calendar.day_index(float(lab.terrain.site.get("minute", 0))))

## The faction head's seat: the capital, where the treasury is.
static func capital_of(registry: Dictionary, faction: int) -> String:
	var head: Dictionary = RegionPeerage.head_of(registry, faction)
	if not head.get("ok", false) or head.get("person_ref") == null: return ""
	return RegionFinance.seat_of(registry, RegionPeerage.key_of(head.person_ref))

## The direct fiefs still to visit this season: not planned by another team and not collected in full (PT-19: a fief
## that paid only part, or whose goods did not all fit, may be visited again).
static func due_stops(registry: Dictionary, ledger: Dictionary, faction: int, home: String, season: int) -> Array:
	return fief_stops(registry, faction, home, season, ledger).filter(func(site: String) -> bool:
		var taken: Dictionary = TaxRoutes.collected_of(ledger, faction, site, season)
		return taken.is_empty() or int(taken.paid) < int(taken.due))

## 派收稅: `team_id` on this live Site (the capital) sets out on this season's round of the direct fiefs.
## Returns {ok, token, stops, route} or a refusal.
static func dispatch(controller: Variant, team_id: int) -> Dictionary:
	var lab: Variant = controller.lab
	var slot: Variant = controller.region_slot
	if slot == null or lab.crowd_site == null or not lab.crowd_site.active: return Runtime.fail("UNSUPPORTED", "沒有世界或群眾")
	var crowd_team := _crowd_team(lab, team_id)
	var army: Variant = _army_of(lab, team_id)
	if crowd_team.is_empty() or army == null: return Runtime.fail("NO_TEAM", "沒有這支隊伍")
	var refused := dispatch_refusal(army)
	if not refused.is_empty(): return refused
	if crowd_team.get("person_ids", []).has(int(lab.controlled_person_id())): return Runtime.fail("PLAYER_PARTY", "受控人物不隨稅隊出發")
	var faction := int(crowd_team.get("faction", -1))
	var registry: Dictionary = slot.control.get("faction_registry", {})
	var home := str(lab.terrain.site.id)
	if capital_of(registry, faction) != home: return Runtime.fail("NOT_CAPITAL", "稅隊須從國都出發")
	var season := _season(lab)
	var ledger: Dictionary = slot.region_registry()
	var stops := due_stops(registry, ledger, faction, home, season)
	if stops.is_empty(): return Runtime.fail("NO_FIEFS", "本季沒有要巡收的直屬封地")
	if not Caravan._team_ready(lab, crowd_team): return Runtime.fail("NOT_READY", "稅隊須停在守位、可以出發")
	var captain := int(army.combat_identity(int(army.formal_commander)))
	var captain_ref: Dictionary = JoinFaction._world_ref(controller, captain)
	var envoy_ref: Dictionary = JoinFaction._world_ref(controller, envoy_of(army))
	if captain_ref.is_empty() or envoy_ref.is_empty(): return Runtime.fail("NO_REFERENCE", "稅隊人物沒有世界參照")
	var token := "tax_%s" % Crypto.new().generate_random_bytes(12).hex_encode()
	# The route is in the ledger before the departure is prepared (nothing on the Site changes between the preparation
	# and the commit: a changed Site is refused STALE_BIND).
	var added := TaxRoutes.add(ledger, {"token": token, "faction": faction, "season": season, "home_site": home, "captain_ref": captain_ref,
		"envoy_ref": envoy_ref, "stops": stops, "done": {}, "phase": "out", "day": int(float(slot.control.logical_game_seconds) / 86400.0)})
	if not added.ok: return added
	var sent := _send(slot, lab, team_id, captain, str(stops[0]), token)
	if not sent.ok:
		TaxRoutes.remove(ledger, int(added.id))
		return sent
	# From now on its direct fiefs owe no tribute on the road (slice 3). The departure's publication replaced the ledger:
	# the mark goes into the current one.
	TaxRoutes.mark_faction(slot.region_registry(), faction)
	last_event = {"dispatched": token, "stops": stops}
	return {"ok": true, "token": token, "stops": stops, "route": int(added.id)}

static func _send(slot: Variant, lab: Variant, team_id: int, captain: int, to_site: String, token: String) -> Dictionary:
	var here: Dictionary = slot._coordinate(lab.terrain)
	var person: Dictionary = lab._original_person_target(captain)
	if person.is_empty(): return Runtime.fail("NO_CAPTAIN", "隊長不在此地")
	var component: int = RegionTravelSite.start_component(slot, here.site, person.cell, lab.terrain)
	var prepared: Dictionary = slot.prepare_npc_region_dispatch(lab, "captain:tax", team_id, Caravan._coordinate(to_site), component, [], token)
	if not prepared.ok: return prepared
	return slot.commit_npc_region_dispatch(prepared)

## The room the team's people still have for tax goods (units).
static func _room(lab: Variant, controller: Variant, team_id: int) -> int:
	var room := 0
	for team: Variant in lab.team_owners():
		if int(team.team_id) != team_id: continue
		for index: Variant in (team.combat_units.keys() if team.combat_units is Dictionary else range(team.combat_units.size())):
			var body: Dictionary = controller.person_actions._person(team.combat_identity(int(index)), false)
			if not body.is_empty(): room += maxi(0, CARRY - Runtime.carried_size(body.cargo, body.holder))
	return room

## Moves `goods` between the team's people and `stock` (to the people when `to_people`), member by member.
static func _move(lab: Variant, controller: Variant, team_id: int, stock: Dictionary, goods: Dictionary, to_people: bool) -> Dictionary:
	var left := goods.duplicate()
	var moved := {}
	for team: Variant in lab.team_owners():
		if int(team.team_id) != team_id: continue
		for index: Variant in (team.combat_units.keys() if team.combat_units is Dictionary else range(team.combat_units.size())):
			var body: Dictionary = controller.person_actions._person(team.combat_identity(int(index)), false)
			if body.is_empty(): continue
			var share := {}
			var room := CARRY - Runtime.carried_size(body.cargo, body.holder)
			for item: String in left.keys():
				var n := mini(int(left[item]), room) if to_people else mini(int(left[item]), int(body.cargo.get(item, 0)))
				if n <= 0: continue
				share[item] = n
				if to_people: room -= n
			if share.is_empty(): continue
			var done: Dictionary
			if to_people: done = Runtime.transfer_items(lab.terrain, stock.holder, stock.cargo, body.holder, body.cargo, share, [], int(stock.holder.version), int(body.holder.version))
			else: done = Runtime.transfer_items(lab.terrain, body.holder, body.cargo, stock.holder, stock.cargo, share, [], int(body.holder.version), int(stock.holder.version), 2000000000)
			if not done.ok: continue
			for item: String in share:
				moved[item] = int(moved.get(item, 0)) + int(share[item])
				left[item] = int(left[item]) - int(share[item])
				if int(left[item]) <= 0: left.erase(item)
	return moved

## Each Region evaluation of `lab`'s Site: a tax team standing on its next stop collects and moves on; one standing
## home unloads into the treasury and its round ends. Returns {collected: [{site, outcome, paid}], home: [token]}.
static func evaluate(slot: Variant, lab: Variant) -> Dictionary:
	var result := {"collected": [], "home": []}
	var ledger: Dictionary = slot.region_registry()
	if TaxRoutes.routes(ledger).is_empty() or lab.site_controller == null or lab.crowd_site == null or not lab.crowd_site.active: return result
	var controller: Variant = lab.site_controller
	var scope := str(lab.terrain.site.id)
	var beaten := sweep_lost(slot, lab) # PT-17: a team with nobody left standing here ends its round
	if not beaten.is_empty(): result["lost"] = beaten
	for route: Dictionary in TaxRoutes.routes(slot.region_registry()).duplicate(true):
		var captain: int = slot.person_id_of_ref(route.captain_ref)
		if captain <= 0 or lab._original_person_target(captain).is_empty(): continue
		var team_id := Caravan._team_of_person(lab, captain)
		if team_id < 0: continue
		if str(route.phase) == "out" and route.stops.has(scope) and not route.done.has(scope):
			var collected := _collect(slot, lab, controller, route, team_id)
			result.collected.append({"site": scope, "outcome": str(collected.get("outcome", "")), "paid": int(collected.get("paid", 0))})
			var stored: Dictionary = TaxRoutes.find(slot.region_registry(), int(route.id)) # a publication may have replaced it
			if stored.is_empty(): continue
			var next := ""
			for stop: Variant in stored.stops:
				if not stored.done.has(stop):
					next = str(stop)
					break
			var going_home := next.is_empty()
			if going_home: next = str(stored.home_site)
			var before := str(stored.token)
			stored["token"] = "tax_%s" % Crypto.new().generate_random_bytes(12).hex_encode()
			if going_home: stored["phase"] = "back"
			var sent := _send(slot, lab, team_id, captain, next, str(stored.token))
			if not sent.ok:
				# Collected here already; the team waits and the next evaluation sends it on.
				stored["token"] = before
				if going_home: stored["phase"] = "out"
				result["refused"] = {"code": str(sent.get("code", "")), "message": str(sent.get("message", ""))}
		elif str(route.phase) == "out" and route.stops.has(scope) and route.done.has(scope):
			# Collected here, but the way on was refused: try again.
			var stored_again: Dictionary = TaxRoutes.find(slot.region_registry(), int(route.id))
			var next_again := ""
			for stop: Variant in stored_again.stops:
				if not stored_again.done.has(stop):
					next_again = str(stop)
					break
			var home_again := next_again.is_empty()
			if home_again: next_again = str(stored_again.home_site)
			var before_again := str(stored_again.token)
			stored_again["token"] = "tax_%s" % Crypto.new().generate_random_bytes(12).hex_encode()
			if home_again: stored_again["phase"] = "back"
			if not _send(slot, lab, team_id, captain, next_again, str(stored_again.token)).ok:
				stored_again["token"] = before_again
				if home_again: stored_again["phase"] = "out"
		elif str(route.phase) == "back" and str(route.home_site) == scope:
			var unloaded := _unload(slot, lab, controller, route, team_id)
			if unloaded.ok: result.home.append(str(route.token))
	if not result.collected.is_empty() or not result.home.is_empty() or result.has("refused"): last_event = result.duplicate(true)
	return result

## The handover at this stop (the fief's head answers; an NPC by character; the player's own answer is slice 3).
static func _collect(slot: Variant, lab: Variant, controller: Variant, route: Dictionary, team_id: int) -> Dictionary:
	var ledger: Dictionary = slot.region_registry()
	var scope := str(lab.terrain.site.id)
	var stored: Dictionary = TaxRoutes.find(ledger, int(route.id))
	var record: Dictionary = ProduceTax.record_of(lab.terrain)
	var source: Dictionary = {}
	if not record.is_empty() and record.get("tax_source") is Dictionary and not record.tax_source.is_empty(): source = Payroll.source_of(lab, record.tax_source)
	var settlement: Dictionary = Settlement.record(lab.terrain)
	if record.is_empty() or source.is_empty() or int(settlement.get("owner_faction", -1)) != int(route.faction):
		stored.done[scope] = "none"
		return {"outcome": "none", "paid": 0}
	var season := int(route.season)
	var taken: Dictionary = TaxRoutes.collected_of(ledger, int(route.faction), scope, season)
	var owing := owed(record, season, int(taken.get("paid", 0)))
	var head := int(Settlement.head_executor(lab, true))
	var person: Dictionary = controller.person_actions._person(head, false) if head > 0 else {}
	# PT-18: the player's settlement answers as its finance page says (tax_answer, default pay); an NPC by character.
	var decision := str(record.get("tax_answer", "pay"))
	if not person.is_empty() and not bool(person.get("player", false)): decision = npc_decision(person.body.get("personality") if person.get("body") is Dictionary else null)
	var answer := handover(int(owing.owed), source.cargo, _room(lab, controller, team_id), decision)
	var moved: Dictionary = _move(lab, controller, team_id, source, answer.goods, true) if not answer.goods.is_empty() else {}
	var paid := Tribute.goods_tenths(moved)
	if moved != answer.goods: answer["pending"] = int(answer.pending) + int(answer.paid) - paid
	answer["paid"] = paid
	answer["goods"] = moved
	TaxRoutes.record_collection(ledger, int(route.faction), scope, season, int(owing.due), paid)
	if paid > 0: Finance.add_receipt(record, "tribute_out", paid, season)
	var carried: Dictionary = stored.get("carried", {})
	for item: String in moved: carried[item] = int(carried.get(item, 0)) + int(moved[item])
	if not carried.is_empty(): stored["carried"] = carried
	stored.done[scope] = str(answer.outcome)
	var notice := settle(controller, head, record, answer) if str(answer.outcome) != "none" else ""
	if not notice.is_empty() and lab.terrain.site.get("notices") is Array: lab.terrain.site.notices.append(notice)
	return answer

## Home: the carried tax goods go into the capital's treasury as tribute_in; the round ends.
static func _unload(slot: Variant, lab: Variant, controller: Variant, route: Dictionary, team_id: int) -> Dictionary:
	var record: Dictionary = ProduceTax.record_of(lab.terrain)
	var treasury: Dictionary = {}
	if not record.is_empty() and record.get("treasury") is Dictionary and not record.treasury.is_empty(): treasury = Payroll.source_of(lab, record.treasury)
	if treasury.is_empty(): return Runtime.fail("NO_TREASURY", "國都沒有國庫")
	var carried: Dictionary = route.get("carried", {})
	var moved: Dictionary = _move(lab, controller, team_id, treasury, carried, false) if not carried.is_empty() else {}
	if not moved.is_empty(): Finance.add_receipt(record, "tribute_in", Tribute.goods_tenths(moved), _season(lab))
	TaxRoutes.remove(slot.region_registry(), int(route.id))
	if lab.terrain.site.get("notices") is Array: lab.terrain.site.notices.append("稅隊返回國都，入庫 %.1f 點" % (float(Tribute.goods_tenths(moved)) / PayTable.TENTHS))
	return {"ok": true, "moved": moved}

# --- Slice 3: the player's answer, the road's risks, the NPC nation's season --------------------------------------

## PT-18: the settlement's standing answer to the tax team (the head or the settlement's 度支).
static func set_answer(lab: Variant, requester_id: int, answer: String) -> Dictionary:
	if not answer in Finance.TAX_ANSWERS: return Runtime.fail("INVALID", "只能是交、部分或拒")
	var record: Dictionary = ProduceTax.record_of(lab.terrain)
	if record.is_empty(): return Runtime.fail("UNESTABLISHED", "聚落尚未建立財政紀錄")
	if requester_id <= 0 or (requester_id != int(Settlement.head_executor(lab, true)) and requester_id != int(ProduceTax.decider(lab))): return Runtime.fail("NO_AUTHORITY", "只有聚落長或度支能決定")
	if answer == "pay": record.erase("tax_answer")
	else: record["tax_answer"] = answer
	return Runtime.ok({"pay": "稅隊到時足額交付", "partial": "稅隊到時只交一半", "refuse": "稅隊到時拒繳"}[answer])

## PT-17: the tax teams beaten on this Site. A round whose people are all dead or captive here ends: what it collected
## lies with the bodies for whoever picks it up, the stops already visited stay paid on time, the stops not reached owe
## nothing this season (it is the nation's own loss). Returns [{token, at_site}].
static func sweep_lost(slot: Variant, lab: Variant) -> Array:
	var result: Array = []
	if slot == null or lab == null or lab.crowd_site == null or not lab.crowd_site.active: return result
	var ledger: Dictionary = slot.region_registry()
	if TaxRoutes.routes(ledger).is_empty(): return result
	var scope := str(lab.terrain.site.id)
	for route: Dictionary in TaxRoutes.routes(ledger).duplicate(true):
		var captain: int = slot.person_id_of_ref(route.captain_ref)
		if captain <= 0: continue
		var own: Dictionary = {}
		for team: Dictionary in lab.crowd_site.teams:
			if not bool(team.get("departed", false)) and team.get("person_ids", []).has(captain): own = team
		if own.is_empty() or Caravan._able(lab, own) > 0: continue
		TaxRoutes.remove(ledger, int(route.id))
		if lab.terrain.site.get("notices") is Array: lab.terrain.site.notices.append("稅隊在此覆沒，稅款散落原地")
		result.append({"token": str(route.token), "at_site": scope})
	if not result.is_empty(): last_event = {"lost": result}
	return result

## The NPC nation's season (a daily hook of the capital): on any day of a season with fiefs still owing, a capital
## whose faction head is not the player sends its first team able to collect (an officer captain, a 稅使, at hold, not
## the head's own team) unless one of its rounds is already out this season. Returns {sent} or {reason}.
static func day(controller: Variant) -> Dictionary:
	var lab: Variant = controller.lab
	var slot: Variant = controller.region_slot
	if slot == null or lab == null or lab.crowd_site == null or not lab.crowd_site.active: return {"reason": "no_crowd"}
	var registry: Dictionary = slot.control.get("faction_registry", {})
	var home := str(lab.terrain.site.id)
	var player := int(lab.controlled_person_id())
	var settlement: Dictionary = Settlement.record(lab.terrain)
	if settlement.is_empty(): return {"reason": "no_settlement"}
	var faction := int(settlement.get("owner_faction", -1))
	if capital_of(registry, faction) != home: return {"reason": "not_capital"}
	var head: Dictionary = RegionPeerage.head_of(registry, faction)
	if RegionPeerage.world_person_id(head.get("person_ref")) == player or slot.person_id_of_ref(head.get("person_ref")) == player: return {"reason": "player_head"}
	var season := _season(lab)
	var ledger: Dictionary = slot.region_registry()
	for route: Dictionary in TaxRoutes.routes(ledger):
		if int(route.faction) == faction and int(route.season) == season: return {"reason": "out"}
	if due_stops(registry, ledger, faction, home, season).is_empty(): return {"reason": "nothing_due"}
	var head_id: int = slot.person_id_of_ref(head.get("person_ref"))
	for team: Dictionary in lab.crowd_site.teams:
		if bool(team.get("departed", false)) or int(team.get("faction", -1)) != faction or team.get("person_ids", []).has(player) or team.get("person_ids", []).has(head_id): continue
		var army: Variant = _army_of(lab, int(team.team_id))
		if army == null or not dispatch_refusal(army).is_empty() or not Caravan._team_ready(lab, team): continue
		var sent := dispatch(controller, int(team.team_id))
		return {"sent": sent} if sent.get("ok", false) else {"reason": "refused", "code": str(sent.get("code", ""))}
	return {"reason": "no_team"}
