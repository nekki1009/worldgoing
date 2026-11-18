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
