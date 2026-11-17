extends RefCounted
## 軍餉與稅收 P3 follow-up (reports/pay-and-tax-plan.md §3.4): funding across Sites. A team's faction head funds it from
## his fief treasury (the settlement treasury at his RegionFinance seat). When that seat is another Site:
## - request (the team's Site, the day before a payday): a team with a bound pay source that is short of the coming wage
##   bill, whose faction (not neutral, not a band) has a head with a seat elsewhere, files one request in the world's
##   finance (`requests`) per team and payday: the coins it lacks.
## - serve (the seat's Site, every day it is live): each request addressed here is paid from the treasury, at most
##   FUND_DAILY a day in all and never below FUND_RESERVE, as "fund" goods on the road (RegionFinance transit) to the
##   team's Site; SiteTribute.deliver puts them in the team's pay source on arrival. A request is served once (paid in
##   part when the treasury is short) and dropped; one older than STALE_DAYS is dropped unpaid.
## While the seat's Site is not loaded a request waits and the team's payroll records what it cannot pay.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Finance = preload("res://scripts/terrain_lab/site_finance.gd")
const PayTable = preload("res://scripts/terrain_lab/site_pay_table.gd")
const Payroll = preload("res://scripts/terrain_lab/site_payroll.gd")
const ProduceTax = preload("res://scripts/terrain_lab/site_produce_tax.gd")
const RegionFinance = preload("res://scripts/region_lab/region_finance.gd")
const Tribute = preload("res://scripts/terrain_lab/site_tribute.gd")

const STALE_DAYS := 30

static func _faction_of(lab: Variant, identity: int) -> int:
	var person: Dictionary = lab.site_controller.person_actions._person(identity, false)
	return int(person.get("faction", RegionFactionQuery.NEUTRAL_FACTION_ID)) if not person.is_empty() else RegionFactionQuery.NEUTRAL_FACTION_ID

## The day before a payday: files the requests of this Site's short teams. Returns {filed: [{team, coins, to}], retry}.
static func request(lab: Variant, today: int, ctx: Dictionary) -> Dictionary:
	var result := {"filed": []}
	if not PayTable.is_payday(today + 1) or ctx.get("registry", {}).is_empty(): return result
	var registry: Dictionary = ctx.registry
	var site_id := str(lab.terrain.site.get("id", ""))
	var open := {}
	for entry: Dictionary in RegionFinance.requests(registry):
		open["%s|%d|%d" % [str(entry.to_site), int(entry.team), int(entry.payday)]] = true
	var candidate := {}
	var records := Finance.records(lab.terrain)
	var keys: Array = records.keys()
	keys.sort()
	for key: String in keys:
		var record: Dictionary = records[key]
		if str(record.ref.kind) != "team" or str(record.ref.site_id) != site_id or (record.pay_source as Dictionary).is_empty(): continue
		var team_id := int(record.ref.org_id)
		if open.has("%s|%d|%d" % [site_id, team_id, today + 1]): continue
		var captain := Payroll.authority(lab, record.ref)
		if captain <= 0: continue
		var faction := _faction_of(lab, captain)
		if faction == RegionFactionQuery.NEUTRAL_FACTION_ID or RegionFactionQuery.is_bandit(registry, faction): continue
		var head: Dictionary = RegionPeerage.head_of(registry, faction)
		if not head.get("ok", false): continue
		var payer := RegionPeerage.key_of(head.person_ref)
		var seat := RegionFinance.seat_of(registry, payer)
		if seat.is_empty() or seat == site_id: continue
		var source := Payroll.source_of(lab, record.pay_source)
		if source.is_empty(): continue
		var short := Tribute.bill(lab, record) - Tribute.goods_tenths(Tribute.pick_goods(source.cargo, 2000000000))
		var coins := ceili(float(short) / float(PayTable.COIN_POINTS * PayTable.TENTHS))
		if coins <= 0: continue
		if candidate.is_empty(): candidate = RegionFinance.candidate(registry)
		var added := RegionFinance.add_request(candidate, {"from_site": seat, "to_site": site_id, "team": team_id, "coins": coins, "payday": today + 1, "payer": payer})
		if not added.ok: break
		result.filed.append({"team": team_id, "coins": coins, "to": seat})
	if candidate.is_empty(): return result
	var committed: Dictionary = ctx.commit.call(candidate)
	if not committed.ok:
		result.filed = []
		result["retry"] = true
		result["error"] = committed
	return result

## Serves the requests addressed to this Site from its settlement treasury. Returns {sent: [{team, coins, to}], dropped,
## retry}.
static func serve(lab: Variant, today: int, ctx: Dictionary) -> Dictionary:
	var result := {"sent": [], "dropped": 0}
	if ctx.get("registry", {}).is_empty(): return result
	var registry: Dictionary = ctx.registry
	var site_id := str(lab.terrain.site.get("id", ""))
	var mine: Array = RegionFinance.requests(registry).filter(func(entry: Dictionary) -> bool: return str(entry.from_site) == site_id)
	if mine.is_empty(): return result
	var settlement_ref := ProduceTax.settlement_ref(lab.terrain)
	var record: Dictionary = Finance.records(lab.terrain).get(Finance.org_key(settlement_ref), {}) if not settlement_ref.is_empty() else {}
	var treasury: Dictionary = Payroll.source_of(lab, record.treasury) if not record.is_empty() and not (record.get("treasury", {}) as Dictionary).is_empty() else {}
	var candidate := RegionFinance.candidate(registry)
	var served: Array = []
	var budget := Tribute.FUND_DAILY
	var taken := 0
	for entry: Dictionary in mine:
		if today - int(entry.payday) > STALE_DAYS:
			served.append(int(entry.id))
			result.dropped = int(result.dropped) + 1
			continue
		if treasury.is_empty(): continue # no treasury bound here yet: the request waits
		var coins := mini(mini(int(entry.coins), budget), int(treasury.cargo.get("coin", 0)) - taken - Tribute.FUND_RESERVE)
		served.append(int(entry.id))
		if coins <= 0: continue
		var added := RegionFinance.add_transit(candidate, {"kind": "fund", "from_site": site_id, "to_site": str(entry.to_site), "to": "team:%d" % int(entry.team),
			"items": {"coin": coins}, "tenths": coins * PayTable.COIN_POINTS * PayTable.TENTHS, "arrive_day": today + RegionFinance.travel_days(site_id, str(entry.to_site)),
			"season": PayTable.season_index(today), "payer": str(entry.payer)})
		if not added.ok: break
		budget -= coins
		taken += coins
		result.sent.append({"team": int(entry.team), "coins": coins, "to": str(entry.to_site)})
		if budget <= 0: break
	if served.is_empty(): return result
	RegionFinance.remove_requests(candidate, served)
	if taken > 0:
		treasury.cargo["coin"] = int(treasury.cargo.coin) - taken
		treasury.holder.version = int(treasury.holder.version) + 1
	var committed: Dictionary = ctx.commit.call(candidate)
	if not committed.ok:
		if taken > 0: treasury.cargo["coin"] = int(treasury.cargo.coin) + taken
		result.sent = []
		result["retry"] = true
		result["error"] = committed
		return result
	if taken > 0 and not record.is_empty(): Finance.add_receipt(Finance.ensure(lab.terrain, settlement_ref, today).record, "fund", taken * PayTable.COIN_POINTS * PayTable.TENTHS, PayTable.season_index(today))
	return result
