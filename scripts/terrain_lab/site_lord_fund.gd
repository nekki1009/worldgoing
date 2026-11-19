extends RefCounted
## 軍餉與稅收 P3 follow-up (pay-and-tax plan §3.4, second bullet): a lord funds the teams in his fief. The day before a
## payday, after the nation's funding (SiteTribute.fund), a settlement whose finance record has auto_fund on, a bound
## treasury and a titled head (a peerage record) tops up the pay source of every team on this Site whose captain is of
## the settlement's faction: the coming wage bill less what the source holds, in coin, at most FUND_DAILY a day in all and
## never below FUND_RESERVE in the treasury. Teams the nation already filled are not short and get nothing.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Finance = preload("res://scripts/terrain_lab/site_finance.gd")
const PayTable = preload("res://scripts/terrain_lab/site_pay_table.gd")
const Payroll = preload("res://scripts/terrain_lab/site_payroll.gd")
const ProduceTax = preload("res://scripts/terrain_lab/site_produce_tax.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Tribute = preload("res://scripts/terrain_lab/site_tribute.gd")

## Returns {teams, coin} (or {} when today is not the eve of a payday or nothing qualifies).
static func fund(lab: Variant, today: int, ctx: Dictionary) -> Dictionary:
	if not PayTable.is_payday(today + 1): return {}
	var settlement_ref := ProduceTax.settlement_ref(lab.terrain)
	if settlement_ref.is_empty(): return {}
	var record: Dictionary = Finance.records(lab.terrain).get(Finance.org_key(settlement_ref), {})
	if record.is_empty() or not bool(record.get("auto_fund", false)) or (record.get("treasury", {}) as Dictionary).is_empty(): return {}
	var head := int(Settlement.head_executor(lab, true))
	var registry: Dictionary = ctx.get("registry", {})
	if head <= 0 or registry.is_empty() or RegionPeerage.record_of(registry, Tribute._person_ref(ctx, head)).is_empty(): return {}
	var treasury: Dictionary = Payroll.source_of(lab, record.treasury)
	if treasury.is_empty(): return {}
	var faction := int(Settlement.record(lab.terrain).get("owner_faction", -1))
	var site_id := str(lab.terrain.site.get("id", ""))
	var budget := Tribute.FUND_DAILY
	var moved := 0
	var teams := 0
	var records := Finance.records(lab.terrain)
	var keys: Array = records.keys()
	keys.sort()
	for key: String in keys:
		var team_record: Dictionary = records[key]
		if str(team_record.ref.kind) != "team" or str(team_record.ref.site_id) != site_id or (team_record.pay_source as Dictionary).is_empty(): continue
		var captain := Payroll.authority(lab, team_record.ref)
		if captain <= 0: continue
		var person: Dictionary = lab.site_controller.person_actions._person(captain, false)
		if person.is_empty() or int(person.get("faction", -1)) != faction: continue
		var source := Payroll.source_of(lab, team_record.pay_source)
		if source.is_empty(): continue
		var short := Tribute.bill(lab, team_record) - Tribute.goods_tenths(Tribute.pick_goods(source.cargo, 2000000000))
		var coins := mini(mini(ceili(float(short) / float(PayTable.COIN_POINTS * PayTable.TENTHS)), budget), int(treasury.cargo.get("coin", 0)) - Tribute.FUND_RESERVE)
		if coins <= 0: continue
		var sent := Runtime.transfer_items(lab.terrain, treasury.holder, treasury.cargo, source.holder, source.cargo, {"coin": coins}, [], int(treasury.holder.version), int(source.holder.version), Tribute._capacity(lab, source))
		if not sent.ok: continue
		budget -= coins
		moved += coins
		teams += 1
		Finance.add_receipt(Finance.ensure(lab.terrain, settlement_ref, today).record, "fund", coins * PayTable.COIN_POINTS * PayTable.TENTHS, PayTable.season_index(today))
		if budget <= 0: break
	return {"teams": teams, "coin": moved}
