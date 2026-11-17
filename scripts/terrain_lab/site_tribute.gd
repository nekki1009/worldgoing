extends RefCounted
## Tribute and funding (軍餉與稅收 P3, reports/pay-and-tax-plan.md §3.4, §4.3, §9; PT-09..11; Nekki 2026-11-09 都依建議).
## - The fief treasury: a settlement head binds his settlement's treasury (a stockpile of its faction on this Site); a
##   titled head's seat (RegionFinance seats) then points tribute to this Site.
## - Tax day (the first day of each season): a settlement whose head has a liege pays him TRIBUTE_PERCENT of last
##   season's receipts (production tax, market, tariff and tribute received), coin first, then food, from its tax
##   source. The goods go on the road (RegionFinance transit) to the liege's seat and arrive after the travel days;
##   on arrival they enter that settlement's treasury as tribute_in, so the liege's own tribute includes them (the
##   chain climbs to the faction head). A full payment on the day: the head +1 credit (Reputation.TAX_SEASON), every
##   fourth season in a row +2 prestige; a shortfall: −2 credit, a second unpaid season warns that the liege stops
##   funding, a third is the rebellion omen (events only, §4.3 Q6-A). An exempt season, a liege without a seat, or a
##   head without a liege: nothing is due.
## - Funding (§3.4): the day before a payday a nation with a bound treasury here (R4) and auto_fund on tops up the pay
##   source of each team on this Site whose captain is a member: the coming wage bill less what the source holds, in
##   coin, at most FUND_DAILY a day and never below FUND_RESERVE in the treasury. Funding across Sites: SiteFundRequests
##   (the faction head's seat pays a request on the road). A lord's own funding is later work.
## Every registry change (transit, seats) commits with a Region checkpoint; a refused checkpoint rolls the Site
## change back and the day is retried.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Finance = preload("res://scripts/terrain_lab/site_finance.gd")
const PayTable = preload("res://scripts/terrain_lab/site_pay_table.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Stocks = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const Payroll = preload("res://scripts/terrain_lab/site_payroll.gd")
const ProduceTax = preload("res://scripts/terrain_lab/site_produce_tax.gd")
const EquipmentOrders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
const Reputation = preload("res://scripts/terrain_lab/person_reputation.gd")
const RegionFinance = preload("res://scripts/region_lab/region_finance.gd")
const PersonSocial = preload("res://scripts/terrain_lab/person_social.gd")

const TRIBUTE_PERCENT := 10
const TRIBUTE_KINDS := ["produce_tax", "market", "tariff", "tribute_in"]
const ON_TIME_PRESTIGE_EVERY := 4
const ON_TIME_PRESTIGE := 2.0
const LATE_CREDIT := -2.0
const FUND_DAILY := 50
const FUND_RESERVE := 20

static var _done := {}

static func reset() -> void:
	_done.clear()

## The world this Site belongs to: {registry, world, commit}. `commit` takes a registry candidate and publishes it with
## a Region checkpoint of this Site. Without a Region slot the registry is empty (nothing world-level happens).
static func context_of(lab: Variant) -> Dictionary:
	var slot: Variant = lab.site_controller.get("region_slot") if lab.site_controller != null else null
	if slot == null or not slot.get("control") is Dictionary: return {"registry": {}, "world": "", "commit": Callable()}
	var registry: Variant = slot.control.get("faction_registry", {})
	return {"registry": registry if registry is Dictionary else {}, "world": str(slot.pin.get("world_instance_id", "")) if slot.get("pin") is Dictionary else "",
		"commit": func(candidate: Dictionary) -> Dictionary: return _commit(lab, candidate)}

static func _person_ref(ctx: Dictionary, identity: int) -> Dictionary:
	return RegionPeerage.world_person_ref(str(ctx.world), identity)

## The head's liege as {key, ref}, or {} when there is none (no Region, no title, a faction head).
static func liege_of(ctx: Dictionary, head: int) -> Dictionary:
	var registry: Dictionary = ctx.registry
	if registry.is_empty() or head <= 0: return {}
	var liege: Variant = RegionPeerage.liege_of(registry, _person_ref(ctx, head))
	if liege == null: return {}
	return {"key": RegionPeerage.key_of(liege), "ref": liege}

## Value of goods in tenths of a point.
static func goods_tenths(goods: Dictionary) -> int:
	var total := 0
	for item: String in goods: total += ProduceTax.value_tenths(item, int(goods[item]))
	return total

## Whole units of coin, then grain, fish, meat worth at most `tenths`, taken from `cargo` (not changed).
static func pick_goods(cargo: Dictionary, tenths: int) -> Dictionary:
	var goods := {}
	var rest := tenths
	var coins := mini(int(cargo.get("coin", 0)), rest / (PayTable.COIN_POINTS * PayTable.TENTHS))
	if coins > 0:
		goods["coin"] = coins
		rest -= coins * PayTable.COIN_POINTS * PayTable.TENTHS
	for food: String in PayTable.FOOD_ORDER:
		var unit := int(roundf(float(PayTable.FOOD_POINTS[food]) * PayTable.TENTHS))
		var count := mini(int(cargo.get(food, 0)), rest / unit)
		if count <= 0: continue
		goods[food] = count
		rest -= count * unit
	return goods

static func _commit(lab: Variant, registry_candidate: Dictionary) -> Dictionary:
	var controller: Variant = lab.site_controller
	var captured: Dictionary = controller.capture_region_checkpoint("region_checkpoint", true)
	if not captured.ok: return captured
	return controller.region_slot.checkpoint_region_site(lab.terrain, captured.context, captured.owners, registry_candidate, false, captured)

# --- The fief treasury ---------------------------------------------------------------------------------------------

## The settlement's head (or its 度支) binds the settlement treasury; a titled head's seat moves here.
static func bind_treasury(lab: Variant, requester_id: int, source: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	if ctx.is_empty(): ctx = context_of(lab)
	var ref := ProduceTax.settlement_ref(lab.terrain)
	if ref.is_empty(): return Runtime.fail("UNESTABLISHED", "尚未建制聚落")
	var head := Settlement.head_executor(lab, true)
	if requester_id <= 0 or (requester_id != head and requester_id != ProduceTax.decider(lab)): return Runtime.fail("NO_AUTHORITY", "只有聚落長或度支能綁定封地庫")
	if str(source.get("kind", "")) != "stock": return Runtime.fail("UNSUPPORTED", "封地庫須是本聚落的倉庫或設施庫存")
	var checked := Payroll.source_check(lab, ref, source)
	if not checked.ok: return checked
	var today := Calendar.day_index(float(lab.terrain.site.get("minute", 0)))
	var registry: Dictionary = ctx.registry
	var seat_change := false
	var candidate := {}
	if not registry.is_empty() and head > 0 and not RegionPeerage.record_of(registry, _person_ref(ctx, head)).is_empty():
		var key := RegionPeerage.key_of(_person_ref(ctx, head))
		if RegionFinance.seat_of(registry, key) != str(lab.terrain.site.id):
			candidate = RegionFinance.candidate(registry)
			candidate.finance.seats[key] = str(lab.terrain.site.id)
			seat_change = true
	var made := Finance.ensure(lab.terrain, ref, today)
	if not made.ok: return made
	var before: Dictionary = made.record.treasury.duplicate()
	made.record.treasury = source.duplicate()
	if seat_change:
		var committed: Dictionary = ctx.commit.call(candidate)
		if not committed.ok:
			made.record.treasury = before
			return committed
	return Runtime.ok("已綁定封地庫" + ("，上繳將送到這裡" if seat_change else ""), {"record": made.record})

# --- The day -------------------------------------------------------------------------------------------------------

## Once a calendar day at peace: deliveries due here, the tax day, the funding the day before a payday.
static func day(lab: Variant) -> Dictionary:
	if lab == null or lab.terrain == null or lab.site_controller == null: return {}
	var today := Calendar.day_index(float(lab.terrain.site.get("minute", 0)))
	var key: int = lab.get_instance_id()
	if int(_done.get(key, -1)) == today: return {}
	# Each step reads the registry afresh: a commit replaces it.
	var result := {"delivered": deliver(lab, today, context_of(lab))}
	result["tribute"] = tax_day(lab, today, context_of(lab))
	result["funded"] = fund(lab, today)
	# Funding across Sites (SiteFundRequests): short teams here ask their faction head's seat; requests to this seat are paid.
	var Requests: Script = load("res://scripts/terrain_lab/site_fund_requests.gd")
	result["requested"] = Requests.call("request", lab, today, context_of(lab))
	result["served"] = Requests.call("serve", lab, today, context_of(lab))
	if not bool(result.delivered.get("retry", false)) and not bool(result.tribute.get("retry", false)) and not bool(result.requested.get("retry", false)) 		and not bool(result.served.get("retry", false)): _done[key] = today
	return result

## Delivers the transit due here: tribute into this settlement's treasury (as tribute_in), funds into a team's pay
## source. Goods with no bound holder here, or no room, wait.
static func deliver(lab: Variant, today: int, ctx: Dictionary = {}) -> Dictionary:
	if ctx.is_empty(): ctx = context_of(lab)
	var registry: Dictionary = ctx.registry
	if registry.is_empty(): return {"count": 0}
	var site_id := str(lab.terrain.site.get("id", ""))
	var entries := RegionFinance.due(registry, site_id, today)
	if entries.is_empty(): return {"count": 0}
	var settlement_ref := ProduceTax.settlement_ref(lab.terrain)
	var record: Dictionary = Finance.records(lab.terrain).get(Finance.org_key(settlement_ref), {}) if not settlement_ref.is_empty() else {}
	var applied: Array = []
	var undo: Array = []
	for entry: Dictionary in entries:
		var target := {}
		if str(entry.kind) == "tribute" and not record.is_empty(): target = Payroll.source_of(lab, record.treasury)
		elif str(entry.kind) == "fund" and str(entry.to).begins_with("team:"):
			var team_record: Dictionary = Finance.records(lab.terrain).get("team:%s:%s" % [site_id, str(entry.to).trim_prefix("team:")], {})
			if not team_record.is_empty(): target = Payroll.source_of(lab, team_record.pay_source)
		if target.is_empty() or not _fits(lab, target, entry.items): continue
		Runtime.add_items(target.cargo, entry.items)
		target.holder.version = int(target.holder.version) + 1
		undo.append({"target": target, "items": entry.items})
		if str(entry.kind) == "tribute": Finance.add_receipt(record, "tribute_in", int(entry.tenths), PayTable.season_index(today))
		applied.append(int(entry.id))
	if applied.is_empty(): return {"count": 0}
	var candidate := RegionFinance.candidate(registry)
	RegionFinance.remove_transit(candidate, applied)
	var committed: Dictionary = ctx.commit.call(candidate)
	if not committed.ok:
		for step: Dictionary in undo:
			for item: String in step.items: step.target.cargo[item] = int(step.target.cargo.get(item, 0)) - int(step.items[item])
		return {"count": 0, "retry": true, "error": committed}
	return {"count": applied.size(), "ids": applied}

static func _fits(lab: Variant, target: Dictionary, items: Dictionary) -> bool:
	var capacity := -1
	for key: String in lab.terrain.site.get("stockpiles", {}):
		if is_same(lab.terrain.site.stockpiles[key].cargo, target.cargo): capacity = Stocks.capacity(lab.terrain.site.features.get(key, {}))
	if capacity < 0:
		for vehicle: Variant in lab.terrain.site.get("vehicles", {}).values():
			if vehicle is Dictionary and is_same(vehicle.get("cargo"), target.cargo): capacity = int(SiteVehicleTransport.capacity_of(vehicle))
	return capacity >= 0 and Runtime.carried_size(target.cargo, target.holder) + Runtime.inventory_size(items) <= capacity

## The settlement's tax day. Returns {due, paid, transit, on_time} or {} when nothing is due.
static func tax_day(lab: Variant, today: int, ctx: Dictionary = {}) -> Dictionary:
	if ctx.is_empty(): ctx = context_of(lab)
	# P5 (§8.1): the first day of a season, or the first live day after a season began while the Site was away.
	var ref := ProduceTax.settlement_ref(lab.terrain)
	if ref.is_empty(): return {}
	var record: Dictionary = Finance.records(lab.terrain).get(Finance.org_key(ref), {})
	var season := PayTable.season_index(today)
	if record.is_empty() or int(record.last_taxday) >= season: return {}
	var registry: Dictionary = ctx.registry
	var head := Settlement.head_executor(lab, true)
	var liege := liege_of(ctx, head)
	var site_id := str(lab.terrain.site.get("id", ""))
	var seat := RegionFinance.seat_of(registry, str(liege.get("key", ""))) if not liege.is_empty() else ""
	if liege.is_empty() or seat.is_empty() or seat == site_id or RegionFinance.exempt(registry, site_id, season):
		record.last_taxday = season
		return {"due": 0, "reason": "none" if liege.is_empty() else ("exempt" if RegionFinance.exempt(registry, site_id, season) else "no_seat")}
	var base := 0
	for kind: String in TRIBUTE_KINDS: base += Finance.receipts_of(record, kind, season, true)
	var due := base * TRIBUTE_PERCENT / 100
	var source := Payroll.source_of(lab, record.tax_source)
	var goods := pick_goods(source.get("cargo", {}), due) if not source.is_empty() else {}
	var paid := goods_tenths(goods)
	var on_time := due - paid < PayTable.TENTHS
	var candidate := {}
	if not goods.is_empty():
		candidate = RegionFinance.candidate(registry)
		var added := RegionFinance.add_transit(candidate, {"kind": "tribute", "from_site": site_id, "to_site": seat, "to": str(liege.key),
			"items": goods, "tenths": paid, "arrive_day": today + RegionFinance.travel_days(site_id, seat), "season": season,
			"payer": RegionPeerage.key_of(_person_ref(ctx, head))})
		if not added.ok: return {"retry": true, "error": added}
		for item: String in goods: source.cargo[item] = int(source.cargo.get(item, 0)) - int(goods[item])
		source.holder.version = int(source.holder.version) + 1
		var committed: Dictionary = ctx.commit.call(candidate)
		if not committed.ok:
			for item: String in goods: source.cargo[item] = int(source.cargo.get(item, 0)) + int(goods[item])
			return {"retry": true, "error": committed}
		Finance.add_receipt(record, "tribute_out", paid, season)
	record.last_taxday = season
	if due <= 0: return {"due": 0, "reason": "no_receipts"}
	var controller: Variant = lab.site_controller
	var notice := ""
	if on_time:
		record.paid_seasons = int(record.paid_seasons) + 1
		record.unpaid_seasons = 0
		controller.adjust_reputation(head, ON_TIME_PRESTIGE if int(record.paid_seasons) % ON_TIME_PRESTIGE_EVERY == 0 else 0.0, float(Reputation.TAX_SEASON))
		notice = "本季上繳 %.1f 點已起運" % (float(paid) / PayTable.TENTHS)
	else:
		record.paid_seasons = 0
		record.unpaid_seasons = int(record.unpaid_seasons) + 1
		controller.adjust_reputation(head, 0.0, LATE_CREDIT)
		notice = "本季上繳不足（應繳 %.1f 點，只繳 %.1f 點），聚落長信譽 −2" % [float(due) / PayTable.TENTHS, float(paid) / PayTable.TENTHS]
		if int(record.unpaid_seasons) == 2: notice += "；連欠兩季，上級停撥本地隊伍"
		elif int(record.unpaid_seasons) >= 3: notice += "；連欠三季，已有叛離之兆"
	if lab.terrain.site.get("notices") is Array: lab.terrain.site.notices.append(notice)
	return {"due": due, "paid": paid, "on_time": on_time, "seat": seat}

# --- Funding -------------------------------------------------------------------------------------------------------

## The coming payday's bill of a team in tenths: a full month of each member's wage at the team's rate, plus arrears.
static func bill(lab: Variant, record: Dictionary) -> int:
	var roll := Payroll.roll_of(lab, record.ref)
	var total := 0
	var key := Finance.org_key(record.ref)
	for identity: Variant in roll.roles:
		total += PayTable.wage_tenths(roll.roles[identity], int(record.pay_rate))
		var person: Dictionary = lab.site_controller.person_actions._person(int(identity), false)
		if not person.is_empty() and person.get("body") != null: total += int(PersonSocial.arrears_for(person.body, key).tenths)
	return total

## The day before a payday: each nation here with a treasury and auto_fund tops up its members' teams. Returns
## {teams, coin}.
static func fund(lab: Variant, today: int) -> Dictionary:
	if not PayTable.is_payday(today + 1): return {}
	var site_id := str(lab.terrain.site.get("id", ""))
	var nations: Dictionary = lab.terrain.site.get("equipment_nations", {})
	var moved := 0
	var teams := 0
	var keys: Array = nations.keys()
	keys.sort()
	for nation_id: String in keys:
		var nation: Variant = nations[nation_id]
		if not nation is Dictionary or not nation.get("ransom_data") is Dictionary or (nation.ransom_data.treasury as Dictionary).is_empty(): continue
		var nation_ref := {"kind": "nation", "site_id": site_id, "org_id": nation_id}
		if not bool(Finance.record_of(lab.terrain, nation_ref, today).auto_fund): continue
		var treasury: Dictionary = Payroll.source_of(lab, {"kind": "stock", "site_id": site_id, "feature_id": str(nation.ransom_data.treasury.feature_id)})
		if treasury.is_empty(): continue
		var budget := FUND_DAILY
		var members: Array = nation.get("members", [])
		var records := Finance.records(lab.terrain)
		var team_keys: Array = records.keys()
		team_keys.sort()
		for key: String in team_keys:
			var record: Dictionary = records[key]
			if str(record.ref.kind) != "team" or str(record.ref.site_id) != site_id or (record.pay_source as Dictionary).is_empty(): continue
			var captain := Payroll.authority(lab, record.ref)
			if captain <= 0 or not (members.has(captain) or members.has(float(captain))): continue
			var source := Payroll.source_of(lab, record.pay_source)
			if source.is_empty(): continue
			var short := bill(lab, record) - goods_tenths(pick_goods(source.cargo, 2000000000))
			var coins := mini(mini(ceili(float(short) / float(PayTable.COIN_POINTS * PayTable.TENTHS)), budget), int(treasury.cargo.get("coin", 0)) - FUND_RESERVE)
			if coins <= 0: continue
			var sent := Runtime.transfer_items(lab.terrain, treasury.holder, treasury.cargo, source.holder, source.cargo, {"coin": coins}, [], int(treasury.holder.version), int(source.holder.version), _capacity(lab, source))
			if not sent.ok: continue
			budget -= coins
			moved += coins
			teams += 1
			var nation_record: Dictionary = Finance.ensure(lab.terrain, nation_ref, today).record
			Finance.add_receipt(nation_record, "fund", coins * PayTable.COIN_POINTS * PayTable.TENTHS, PayTable.season_index(today))
			if budget <= 0: break
	return {"teams": teams, "coin": moved}

static func _capacity(lab: Variant, target: Dictionary) -> int:
	for key: String in lab.terrain.site.get("stockpiles", {}):
		if is_same(lab.terrain.site.stockpiles[key].cargo, target.cargo): return Stocks.capacity(lab.terrain.site.features.get(key, {}))
	for vehicle: Variant in lab.terrain.site.get("vehicles", {}).values():
		if vehicle is Dictionary and is_same(vehicle.get("cargo"), target.cargo): return int(SiteVehicleTransport.capacity_of(vehicle))
	return 0

# --- Exemption -----------------------------------------------------------------------------------------------------

## A faction head waives `site_id`'s tribute for `season` (§4.3): no tribute is due and nobody's credit changes.
static func exempt(lab: Variant, requester_id: int, site_id: String, season: int, ctx: Dictionary = {}) -> Dictionary:
	if ctx.is_empty(): ctx = context_of(lab)
	var registry: Dictionary = ctx.registry
	if registry.is_empty(): return Runtime.fail("NO_REGION_SLOT")
	var record := RegionPeerage.record_of(registry, _person_ref(ctx, requester_id))
	if record.is_empty() or record.get("liege_ref") != null: return Runtime.fail("NO_AUTHORITY", "只有勢力首長能豁免上繳")
	if season < 0 or site_id.is_empty(): return Runtime.fail("INVALID")
	var candidate := RegionFinance.candidate(registry)
	var seasons: Array = candidate.finance.exemptions.get(site_id, [])
	if seasons.has(season): return Runtime.ok("已豁免")
	if seasons.size() >= RegionFinance.MAX_EXEMPTIONS: seasons.pop_front()
	seasons.append(season)
	seasons.sort()
	candidate.finance.exemptions[site_id] = seasons
	var committed: Dictionary = ctx.commit.call(candidate)
	return Runtime.ok("已豁免本季上繳") if committed.ok else committed
