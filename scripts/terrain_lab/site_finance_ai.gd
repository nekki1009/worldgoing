extends RefCounted
## NPC finance (軍餉與稅收 P6, reports/pay-and-tax-plan.md §9, §4.4; Nekki 2026-11-09 都依建議). Once a calendar day at
## peace, for organizations whose decider is not the controlled person:
## - an NPC captain whose team has no pay source binds the first holder it may: one of the team's own vehicles, else a
##   stockpile of its faction no other organization holds. A team with no such holder stays off the payroll (it would
##   only fall into arrears; the plan's NPC captain pays from goods it can reach).
## - an NPC 度支 (or head) of a settlement with no levy binds a tax source the same way and levies 10%. On the first day
##   of each month it reviews the rate: residents' mean grievance above 60 → one step down (never while the decider's
##   ambition is 70 or more, the plan's 「貪婪」); two unpaid tribute seasons → one step up; a thrifty decider (節儉 70+)
##   raises a step whenever the tax source holds less than one season's tribute. NPCs never go above 15%, and 15% needs
##   N09. So an NPC settlement settles its rate within 90 days.
## - recruit_cap: the 可養兵額 × 1.2 an NPC recruiter must stay under (§4.4, §9). Nothing recruits by AI yet; the cap
##   is ready for the recruit duty.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Finance = preload("res://scripts/terrain_lab/site_finance.gd")
const PayTable = preload("res://scripts/terrain_lab/site_pay_table.gd")
const Payroll = preload("res://scripts/terrain_lab/site_payroll.gd")
const ProduceTax = preload("res://scripts/terrain_lab/site_produce_tax.gd")
const Tribute = preload("res://scripts/terrain_lab/site_tribute.gd")
const FinancePage = preload("res://scripts/terrain_lab/site_finance_page.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")

const NPC_START_RATE := 10
const NPC_MAX_RATE := 15
const GRIEVANCE_LOWER := 60
const UNPAID_RAISE := 2
const TRAIT := 70
const RECRUIT_MARGIN := 1.2

static var _done := {}

static func reset() -> void:
	_done.clear()

static func day(lab: Variant) -> Dictionary:
	if lab == null or lab.terrain == null or lab.site_controller == null: return {}
	var today := Calendar.day_index(float(lab.terrain.site.get("minute", 0)))
	var key: int = lab.get_instance_id()
	if int(_done.get(key, -1)) == today: return {}
	_done[key] = today
	return {"teams": bind_npc_teams(lab), "tax": settlement_tax(lab, today)}

static func _axis(lab: Variant, identity: int, axis: String) -> int:
	var person: Dictionary = lab.site_controller.person_actions._person(identity, false)
	return SiteSocial._axis(person.body, axis) if not person.is_empty() and person.get("body") != null else 50

static func _first_holder(lab: Variant, ref: Dictionary, stock_only: bool) -> Dictionary:
	var choices := FinancePage.holders(lab, ref)
	if not stock_only:
		for entry: Dictionary in choices:
			if str(entry.source.kind) == "vehicle": return entry.source
	for entry: Dictionary in choices:
		if str(entry.source.kind) == "stock": return entry.source
	return {}

## NPC captains bind a pay source. Returns the number bound.
static func bind_npc_teams(lab: Variant) -> int:
	var bound := 0
	var controlled := int(lab.controlled_person_id())
	var site_id := str(lab.terrain.site.get("id", ""))
	var teams: Array = lab.team_owners() if lab.crowd_site != null and lab.crowd_site.active else lab.combat_armies
	for team: Variant in teams:
		if not is_instance_valid(team): continue
		var ref := SiteSocial.team_ref(site_id, int(team.team_id))
		var captain := Payroll.authority(lab, ref)
		if captain <= 0 or captain == controlled: continue
		var record: Dictionary = Finance.records(lab.terrain).get(Finance.org_key(ref), {})
		if not record.is_empty() and not (record.pay_source as Dictionary).is_empty(): continue
		var source := _first_holder(lab, ref, false)
		if source.is_empty(): continue
		if Payroll.bind_pay_source(lab, captain, ref, source).ok: bound += 1
	return bound

## The NPC settlement's levy and its monthly review. Returns {rate, changed} or {}.
static func settlement_tax(lab: Variant, today: int) -> Dictionary:
	var ref := ProduceTax.settlement_ref(lab.terrain)
	if ref.is_empty(): return {}
	var decider := ProduceTax.decider(lab)
	if decider <= 0 or decider == int(lab.controlled_person_id()): return {}
	var record: Dictionary = Finance.records(lab.terrain).get(Finance.org_key(ref), {})
	if record.is_empty() or (record.tax_source as Dictionary).is_empty():
		var source := _first_holder(lab, ref, true)
		if source.is_empty(): return {}
		var levied := ProduceTax.set_tax(lab, decider, NPC_START_RATE, source)
		return {"rate": NPC_START_RATE, "changed": levied.ok}
	if not PayTable.is_payday(today): return {"rate": int(record.tax_rate), "changed": false}
	var rate := int(record.tax_rate)
	var target := rate
	var grievance := mean_grievance(lab, ref)
	if grievance > GRIEVANCE_LOWER and _axis(lab, decider, "ambition") < TRAIT: target = _step(rate, -1)
	elif int(record.unpaid_seasons) >= UNPAID_RAISE: target = _step(rate, 1)
	elif _axis(lab, decider, "thrift") >= TRAIT and _short(lab, record, today): target = _step(rate, 1)
	if target > PayTable.FREE_TAX_MAX and not ProduceTax.high_rate_allowed(lab.terrain): target = PayTable.FREE_TAX_MAX
	target = mini(target, NPC_MAX_RATE)
	if target == rate: return {"rate": rate, "changed": false, "grievance": grievance}
	var result := ProduceTax.set_tax(lab, decider, target)
	return {"rate": target if result.ok else rate, "changed": result.ok, "grievance": grievance}

static func _step(rate: int, direction: int) -> int:
	var at := PayTable.TAX_RATES.find(rate)
	return int(PayTable.TAX_RATES[clampi(at + direction, 0, PayTable.TAX_RATES.size() - 1)])

## The tax source holds less than one season's tribute at the current receipts.
static func _short(lab: Variant, record: Dictionary, today: int) -> bool:
	var season := PayTable.season_index(today)
	var base := 0
	for kind: String in Tribute.TRIBUTE_KINDS: base += Finance.receipts_of(record, kind, season, true)
	var source := Payroll.source_of(lab, record.tax_source)
	var held := Tribute.goods_tenths(Tribute.pick_goods(source.cargo, 2000000000)) if not source.is_empty() else 0
	return held < base * Tribute.TRIBUTE_PERCENT / 100

## Registered residents' mean grievance (G) against the settlement.
static func mean_grievance(lab: Variant, ref: Dictionary) -> float:
	var total := 0
	var count := 0
	for identity: int in ProduceTax.residents(lab.terrain):
		var person: Dictionary = lab.site_controller.person_actions._person(identity, false)
		if person.is_empty() or person.get("body") == null: continue
		var status: Dictionary = SiteSocial.status(person.body, ref)
		total += int(status.get("G", 0))
		count += 1
	return float(total) / float(count) if count > 0 else 0.0

## §4.4 可養兵額 × 1.2: how many soldiers the settlement's receipts can keep, for an NPC recruiter.
static func recruit_cap(lab: Variant) -> int:
	var record := ProduceTax.record_of(lab.terrain)
	if record.is_empty(): return 0
	var today := Calendar.day_index(float(lab.terrain.site.get("minute", 0)))
	var season := PayTable.season_index(today)
	var last := 0
	for kind: String in Tribute.TRIBUTE_KINDS: last += Finance.receipts_of(record, kind, season, true)
	var treasury := Payroll.source_of(lab, record.treasury)
	var stored := Tribute.goods_tenths(Tribute.pick_goods(treasury.cargo, 2000000000)) if not treasury.is_empty() else 0
	return floori((float(last) + float(stored) * 0.5) / PayTable.TENTHS / float(FinancePage.SOLDIER_SEASON) * RECRUIT_MARGIN)
