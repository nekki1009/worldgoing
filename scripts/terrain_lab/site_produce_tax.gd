extends RefCounted
## Production tax (軍餉與稅收 P2, reports/pay-and-tax-plan.md §4.1–§4.2, §6; PT-07, PT-08; Nekki 2026-11-09 都依建議).
## A founded settlement's 度支 (settlement.finance; the head acts while it is vacant) levies a rate of 0/5/10/15/20% and
## binds a tax source: a completed stockpile of the settlement's faction on this Site. Rates above 10% need N09 (稅籍與
## 財政制度) known by the settlement's nation. Then every batch a building of the settlement's faction inside its
## jurisdiction delivers is taxed as it is published: amount × rate accumulates per building and resource in hundredths
## and each full hundred is one whole unit moved into the tax source; the producer keeps the rest. Equipment items are
## not taxed. Units the tax source has no room for stay with the producer. Each levy adds to the settlement's season
## receipts (produce_tax, in tenths of a value point). Residents (people registered in a house of the settlement's
## faction inside its jurisdiction) gain G +1 a day at 15% and +2 at 20% (§4.2), recorded once per day.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Finance = preload("res://scripts/terrain_lab/site_finance.gd")
const PayTable = preload("res://scripts/terrain_lab/site_pay_table.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Stocks = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const TradeValues = preload("res://scripts/terrain_lab/site_trade_values.gd")
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")
const Payroll = preload("res://scripts/terrain_lab/site_payroll.gd")

const DUTY := "settlement.finance"
const HIGH_RATE_TECH := "N09"
const UNHAPPY := {15: 1, 20: 2}
const DAY_MINUTES := 1440

static var _done := {}

static func settlement_ref(data: TerrainData) -> Dictionary:
	var settlement: Variant = data.site.get("settlement", {})
	if not settlement is Dictionary or str(settlement.get("settlement_id", "")).is_empty(): return {}
	return {"kind": "settlement", "site_id": str(data.site.get("id", "")), "org_id": str(settlement.settlement_id)}

static func record_of(data: TerrainData) -> Dictionary:
	var ref := settlement_ref(data)
	if ref.is_empty(): return {}
	var found: Variant = Finance.records(data).get(Finance.org_key(ref))
	return found if found is Dictionary else {}

## Value of `count` units of `resource` in tenths of a point.
static func value_tenths(resource: String, count: int) -> int:
	var points := float(PayTable.COIN_POINTS) if resource == "coin" else float(TradeValues.RESOURCE_VALUES.get(resource, 0.0))
	return roundi(points * PayTable.TENTHS * count)

## The data-layer levy, called by SiteRuntime.publish_feature_output before the output is added: returns what the
## producer keeps and moves the taxed units into the tax source. Untaxed output comes back unchanged.
static func levy(data: TerrainData, feature_key: String, feature: Dictionary, output: Dictionary) -> Dictionary:
	if output.is_empty(): return output
	var record := record_of(data)
	if record.is_empty() or int(record.tax_rate) <= 0 or (record.tax_source as Dictionary).is_empty(): return output
	var settlement: Dictionary = data.site.settlement
	if int(feature.get("owner_faction", -1)) != int(settlement.get("owner_faction", -2)) or not Settlement.feature_in_jurisdiction(data, feature): return output
	var source: Dictionary = record.tax_source
	if str(source.kind) != "stock" or str(source.site_id) != str(data.site.get("id", "")): return output
	var stock := Stocks.storage(data, str(source.feature_id))
	var stock_feature: Dictionary = data.site.get("features", {}).get(str(source.feature_id), {})
	if stock.is_empty() or stock_feature.is_empty(): return output
	var room := Stocks.capacity(stock_feature) - Runtime.carried_size(stock.cargo, stock.holder)
	var rate := int(record.tax_rate)
	var kept := output.duplicate()
	var taken := {}
	var carry: Dictionary = (record.tax_carry.get(feature_key, {}) as Dictionary).duplicate()
	var resources: Array = output.keys()
	resources.sort()
	for resource: String in resources:
		var amount := int(output[resource])
		if amount <= 0: continue
		var total := int(carry.get(resource, 0)) + amount * rate
		var units := mini(total / 100, amount)
		carry[resource] = total % 100
		if carry[resource] == 0: carry.erase(resource)
		units = mini(units, maxi(0, room))
		if units <= 0: continue
		taken[resource] = units
		kept[resource] = amount - units
		if int(kept[resource]) == 0: kept.erase(resource)
		room -= units
	if carry.is_empty(): record.tax_carry.erase(feature_key)
	elif record.tax_carry.has(feature_key) or record.tax_carry.size() < Finance.MAX_CARRY_FEATURES: record.tax_carry[feature_key] = carry
	if taken.is_empty(): return kept
	Runtime.add_items(stock.cargo, taken)
	stock.holder.version = int(stock.holder.version) + 1
	var tenths := 0
	for resource: String in taken: tenths += value_tenths(resource, int(taken[resource]))
	var today := Calendar.day_index(float(data.site.get("minute", 0)))
	Finance.add_receipt(record, "produce_tax", tenths, PayTable.season_index(today))
	return kept

# --- Commands ------------------------------------------------------------------------------------------------------

## The person who decides the settlement's tax: its 度支, or the head while the seat is vacant. -1 when none.
static func decider(lab: Variant) -> int:
	var resolved: Dictionary = Settlement.duty_resolve(lab, DUTY, true)
	return int(resolved.get("decider", -1)) if resolved.get("ok", false) else -1

static func high_rate_allowed(data: TerrainData) -> bool:
	var nation: Dictionary = Runtime.settlement_nation(data)
	return not nation.is_empty() and Technology.scope_known(nation.get("technology", {}), HIGH_RATE_TECH)

## Sets the settlement's production tax rate and (when given) its tax source. `source` {} leaves the source as is.
static func set_tax(lab: Variant, requester_id: int, rate: int, source: Dictionary = {}) -> Dictionary:
	var ref := settlement_ref(lab.terrain)
	if ref.is_empty(): return Runtime.fail("UNESTABLISHED", "尚未建制聚落")
	if requester_id <= 0 or requester_id != decider(lab): return Runtime.fail("NO_AUTHORITY", "只有度支（空缺時由聚落長代行）能定稅率")
	if not PayTable.valid_tax_rate(rate): return Runtime.fail("INVALID", "稅率只能是 0／5／10／15／20%")
	if rate > PayTable.FREE_TAX_MAX and not high_rate_allowed(lab.terrain): return Runtime.fail("NO_TECHNOLOGY", "15% 以上需要國家已知「稅籍與財政制度」（N09）")
	var day := Calendar.day_index(float(lab.terrain.site.get("minute", 0)))
	if not source.is_empty():
		if str(source.get("kind", "")) != "stock": return Runtime.fail("UNSUPPORTED", "稅源須是本聚落的倉庫或設施庫存")
		var checked := Payroll.source_check(lab, ref, source)
		if not checked.ok: return checked
	var current := Finance.record_of(lab.terrain, ref, day)
	if rate > 0 and source.is_empty() and (current.tax_source as Dictionary).is_empty(): return Runtime.fail("NO_TARGET", "開徵前須綁定稅源")
	var made := Finance.ensure(lab.terrain, ref, day)
	if not made.ok: return made
	made.record.tax_rate = rate
	if not source.is_empty(): made.record.tax_source = source.duplicate()
	return Runtime.ok("稅率已定為 %d%%" % rate if rate > 0 else "已停徵產出稅", {"record": made.record})

# --- Residents' discontent -----------------------------------------------------------------------------------------

## Registered residents: people housed in a completed house of the settlement's faction inside its jurisdiction.
static func residents(data: TerrainData) -> Array[int]:
	var result: Array[int] = []
	var settlement: Variant = data.site.get("settlement", {})
	if not settlement is Dictionary or settlement.is_empty(): return result
	for identity: Variant in data.site.get("housing", {}):
		var registration: Variant = data.site.housing[identity]
		var house: Dictionary = data.site.get("features", {}).get(str(registration.get("house_id", "")), {}) if registration is Dictionary else {}
		if house.is_empty() or int(house.get("owner_faction", -1)) != int(settlement.get("owner_faction", -2)) or not Settlement.feature_in_jurisdiction(data, house): continue
		result.append(int(identity))
	result.sort()
	return result

## Once a calendar day: at 15% / 20% each registered resident records G +1 / +2 against the settlement.
static func day(lab: Variant) -> Dictionary:
	if lab == null or lab.terrain == null or lab.site_controller == null: return {}
	var minute := int(lab.terrain.site.get("minute", 0))
	var today := Calendar.day_index(float(minute))
	var key: int = lab.get_instance_id()
	if int(_done.get(key, -1)) == today: return {}
	_done[key] = today
	var record := record_of(lab.terrain)
	var amount := int(UNHAPPY.get(int(record.get("tax_rate", 0)), 0)) if not record.is_empty() else 0
	if amount <= 0: return {"residents": 0}
	var ref := settlement_ref(lab.terrain)
	var count := 0
	for identity: int in residents(lab.terrain):
		var person: Dictionary = lab.site_controller.person_actions._person(identity, false)
		if person.is_empty() or person.get("body") == null or float(person.get("hp", 0.0)) <= 0.0: continue
		if SiteSocial.record(person.body, ref, "tax", amount, "tax:%s:%d" % [Finance.org_key(ref), today], minute): count += 1
	return {"residents": count, "amount": amount}

static func reset() -> void:
	_done.clear()
