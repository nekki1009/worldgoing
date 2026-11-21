extends "res://scripts/tests/site_building_ui_test.gd"
## 軍餉與稅收 P1 (reports/pay-and-tax-plan.md §3.1–§3.3, §6 rows 1–2; PT-01..06). A captain and five 幹部 (four officers,
## one officer in a civil seat holding 文官, so one wage of 40) on a grid team; the pay source is a warehouse stockpile.
## Paydays fall on the 1st of the month. Checks:
## - binding: only the captain binds; another faction's or another Site's holder and a foreign vehicle are refused;
## - PT-01: coin 20 pays 3+3+3+3+4 = 16 coin after a full month; no arrears, no events;
## - PT-02 (order): coin 7, grain 100: the 文官 takes 4 coin first, then one officer 3 coin; the others take grain up
##   to their 20-item load (20 of 30 points) and are owed the rest;
## - PT-03: an empty source: each is owed 30/40 points with one G +6 / L −200 event; the third unpaid payday in a row
##   adds the streak event (G +10 / L −500);
## - PT-04: a full load receives nothing and owes it all while the others are paid;
## - PT-05: a soldier's 10 days of a 30-day month owe 3.3 points: grain 3, 0.3 carried, no event;
## - PT-06: captive days are not served; a captive at the payday carries his debt without an event;
## - grace: a record in its first 30 days raises no events and grows no streak; Payroll.day runs once a day.
## The plan's PT-02 numbers (coin 5, grain 100, no arrears) do not add up under its own 20-item load rule: a 30-point
## officer cannot carry 30 grain. The order is checked with the load applied.
## Output: SITE_PAYROLL_P1_PASS on success; quit(1) on failure.

const Payroll = preload("res://scripts/terrain_lab/site_payroll.gd")
const Finance = preload("res://scripts/terrain_lab/site_finance.gd")
const PayTable = preload("res://scripts/terrain_lab/site_pay_table.gd")
const PersonSocial = preload("res://scripts/terrain_lab/person_social.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const Stocks = preload("res://scripts/terrain_lab/site_stockpiles.gd")

var checks := 0
var lab: TerrainLab
var team: TerrainArmy
var ref := {}
var key := ""
var stock: Dictionary = {}
var ids: Array[int] = []
var official := -1

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_PAYROLL_P1 OK ", checks, ": ", message)
		return true
	push_error("SITE_PAYROLL_P1_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _body(identity: int) -> Variant:
	return lab.site_controller.person_actions._person(identity, false).body

func _cargo(identity: int) -> Dictionary:
	return lab.site_controller.person_actions._person(identity, false).cargo

func _record() -> Dictionary:
	return lab.terrain.site.finance[key]

func _events(identity: int, kind: String) -> Array:
	var found: Array = []
	for event: Dictionary in SiteSocial.state_of(_body(identity)).pending:
		if str(event.kind) == kind and str(event.org) == key: found.append(event)
	return found

## A fresh period: empty personal loads, the stock set to `goods`, `days` served by everyone, nothing owed.
func _period(goods: Dictionary, days: int) -> void:
	for identity: int in ids:
		_cargo(identity).clear()
		PersonSocial.set_arrears(_body(identity), key, 0, 0)
		SiteSocial.state_of(_body(identity)).pending.clear()
	stock.cargo.clear()
	for good: String in goods: stock.cargo[good] = int(goods[good])
	var record := _record()
	record.served = {}
	if days > 0:
		for identity: int in ids: record.served[str(identity)] = days

func _payday(month: int) -> Dictionary:
	var at := Calendar.day_of(1, month, 1)
	lab.terrain.site.minute = Calendar.day_start_minute(at) + 600
	_record().accrued_day = at - 1
	_record().last_payday = PayTable.payday_index(at) - 1
	var result := Payroll.run(lab, at)
	return result.paydays[0] if (result.paydays as Array).size() == 1 else {}

func _run() -> void:
	var data := _building_fixture()
	var warehouse := _formal_feature(data, "warehouse", Vector2i(20, 20))
	lab = _building_lab(data)
	team = lab.army
	team.roster_size = 6
	team.faction_id = 1
	var cells: Array[Vector2i] = []
	for index: int in range(6): cells.append(Vector2i(30 + index, 26))
	if not _ok(team.deploy_at(data, null, null, cells) and team.enable_combat(false), "a six-person team deploys"): return
	team.set_process(false)
	team.settle_combat_command()
	if not _ok(Stocks.ensure_storage(data, warehouse, 1).ok, "the warehouse holds a stock"): return
	stock = data.site.stockpiles[warehouse]
	var site_id := str(data.site.id)
	ref = SiteSocial.team_ref(site_id, team.team_id)
	key = Finance.org_key(ref)
	var captain := Payroll.authority(lab, ref)
	if not _ok(captain > 0 and captain == team.combat_identity(int(team.formal_commander)), "the captain holds the pay authority", captain): return
	for index: int in range(team.combat_units.size()):
		var identity := team.combat_identity(index)
		if identity == captain: continue
		team.combat_units[index]["military_role"] = "officer"
		ids.append(identity)
	ids.sort()
	if not _ok(ids.size() == 5, "five 幹部", ids): return
	official = ids[4]
	var offices: Dictionary = team.team_offices()
	var seated := false
	for entry: Dictionary in offices.positions:
		if not bool(entry.get("head", false)) and str(entry.get("office_class", "")) == "civil":
			entry.holder = official
			seated = true
			break
	PersonSocial.set_civil_role(_body(official), "official")
	if not _ok(seated, "one 幹部 sits in a civil seat"): return
	# Binding.
	data.site.minute = Calendar.day_start_minute(Calendar.day_of(1, 3, 1)) + 600
	var source := {"kind": "stock", "site_id": site_id, "feature_id": warehouse}
	var refused := Payroll.bind_pay_source(lab, ids[0], ref, source)
	if not _ok(not refused.ok and refused.code == "NO_AUTHORITY", "an officer may not bind", refused): return
	refused = Payroll.bind_pay_source(lab, captain, ref, {"kind": "stock", "site_id": "elsewhere", "feature_id": warehouse})
	if not _ok(not refused.ok and refused.code == "UNSUPPORTED", "another Site's holder is refused", refused): return
	data.site.features[warehouse].owner_faction = 2
	refused = Payroll.bind_pay_source(lab, captain, ref, source)
	data.site.features[warehouse].owner_faction = 1
	if not _ok(not refused.ok and refused.code == "NO_AUTHORITY", "another faction's warehouse is refused", refused): return
	if not _ok(not data.site.has("finance") or data.site.finance.is_empty(), "refusals store no record"): return
	var bound := Payroll.bind_pay_source(lab, captain, ref, source)
	if not _ok(bound.ok and _record().pay_source == source and int(_record().since_day) == Calendar.day_of(1, 3, 1), "the captain binds the warehouse; the record starts today", bound): return
	if not _ok(Finance.validate(data.site).ok, "the stored record validates"): return
	# Grace: a payday inside the record's first 30 days raises no events.
	_record().since_day = Calendar.day_of(1, 3, 20)
	_period({}, 31)
	var graced := _payday(4)
	if not _ok(graced.get("grace") == true and (graced.unpaid as Array).size() == 5 and _events(ids[0], "pay").is_empty() and int(PersonSocial.arrears_for(_body(ids[0]), key).periods) == 0 and int(PersonSocial.arrears_for(_body(ids[0]), key).tenths) == 300, "in the grace month the debt carries with no event and no streak", graced): return
	_record().since_day = Calendar.day_of(1, 3, 1) - 40
	# PT-01: a full month through the real day count.
	_period({"coin": 20}, 0)
	_record().served = {}
	lab.terrain.site.minute = Calendar.day_start_minute(Calendar.day_of(1, 3, 1)) + 600
	_record().accrued_day = -1
	_record().last_payday = PayTable.payday_index(Calendar.day_of(1, 3, 1))
	Payroll.run(lab, Calendar.day_of(1, 3, 1))
	var april := Calendar.day_of(1, 4, 1)
	lab.terrain.site.minute = Calendar.day_start_minute(april) + 600
	var full: Dictionary = Payroll.run(lab, april).paydays[0]
	var coins: Array = []
	for identity: int in ids: coins.append(int(_cargo(identity).get("coin", 0)))
	if not _ok(coins == [3, 3, 3, 3, 4] and int(stock.cargo.get("coin", 0)) == 4 and int(full.paid_full) == 5, "PT-01: 16 coin paid, 4 left", [coins, full]): return
	var clean := true
	for identity: int in ids: clean = clean and PersonSocial.arrears(_body(identity)).is_empty() and _events(identity, "pay").is_empty()
	if not _ok(clean and _record().served.size() == 5 and int(_record().served[str(ids[0])]) == 1 and int(_record().last_payday) == PayTable.payday_index(april), "PT-01: no arrears, no events; the new month counts its first day"): return
	if not _ok(Payroll.day(lab).has("paydays") and Payroll.day(lab).is_empty(), "the day hook runs once a calendar day"): return
	# PT-02: the order.
	_period({"coin": 7, "grain": 100}, 31)
	var ordered := _payday(5)
	var got: Array = []
	for identity: int in ids: got.append(_cargo(identity).duplicate())
	if not _ok(got[4] == {"coin": 4} and got[0] == {"coin": 3} and got[1] == {"grain": 20} and got[3] == {"grain": 20} and int(stock.cargo.grain) == 40 and int(ordered.paid_full) == 2 		and PersonSocial.arrears_for(_body(ids[1]), key) == {"periods": 1, "tenths": 100}, "PT-02: 文官 first, then officers; coin before grain; grain stops at the 20-item load and the rest is owed", [got, ordered]): return
	# PT-03: an empty source, three paydays.
	_period({}, 31)
	_payday(6)
	var first := _events(ids[0], "pay")
	if not _ok(first.size() == 1 and int(first[0].amount) == 6 and int(first[0].l) == -200 and PersonSocial.arrears_for(_body(ids[0]), key) == {"periods": 1, "tenths": 300} and PersonSocial.arrears_for(_body(official), key) == {"periods": 1, "tenths": 400}, "PT-03: one unpaid payday: G +6, L −200, 30/40 points owed", [first, PersonSocial.arrears(_body(ids[0]))]): return
	_record().served = {}
	for identity: int in ids: _record().served[str(identity)] = 31
	_payday(7)
	_record().served = {}
	for identity: int in ids: _record().served[str(identity)] = 31
	_payday(8)
	var streak := _events(ids[0], "pay_streak")
	if not _ok(_events(ids[0], "pay").size() == 3 and streak.size() == 1 and int(streak[0].amount) == 10 and int(streak[0].l) == -500 and PersonSocial.arrears_for(_body(ids[0]), key) == {"periods": 3, "tenths": 900}, "PT-03: the third unpaid payday adds the streak event", [streak, PersonSocial.arrears(_body(ids[0]))]): return
	# PT-04: a full load.
	_period({"coin": 20}, 31)
	_cargo(ids[1])["grain"] = Runtime.CARRY_CAPACITY
	var loaded := _payday(9)
	if not _ok(int(_cargo(ids[1]).get("coin", 0)) == 0 and PersonSocial.arrears_for(_body(ids[1]), key) == {"periods": 1, "tenths": 300} and int(_cargo(ids[2]).get("coin", 0)) == 3 and (loaded.unpaid as Array) == [ids[1]], "PT-04: a full load receives nothing, the others are paid", loaded): return
	# PT-05: a soldier's ten days of a thirty-day month.
	_period({"grain": 100}, 0)
	team.combat_units[team.index_for_identity(ids[2])]["military_role"] = "soldier"
	_record().served = {str(ids[2]): 10}
	_payday(10)
	if not _ok(_cargo(ids[2]) == {"grain": 3} and PersonSocial.arrears_for(_body(ids[2]), key) == {"periods": 0, "tenths": 3} and _events(ids[2], "pay").is_empty(), "PT-05: 3.3 points: grain 3, 0.3 carried, no event", [_cargo(ids[2]), PersonSocial.arrears(_body(ids[2]))]): return
	team.combat_units[team.index_for_identity(ids[2])]["military_role"] = "officer"
	# PT-06: captivity.
	_period({"coin": 20}, 0)
	_record().served = {}
	var october := Calendar.day_of(1, 10, 1)
	lab.terrain.site.minute = Calendar.day_start_minute(october) + 600
	_record().accrued_day = october - 1
	_record().last_payday = PayTable.payday_index(october)
	data.site.captivity[str(ids[3])] = {}
	Payroll.run(lab, october + 14)
	data.site.captivity.erase(str(ids[3]))
	if not _ok(int(_record().served.get(str(ids[0]), 0)) == 15 and not _record().served.has(str(ids[3])), "PT-06: captive days are not served", _record().served): return
	Payroll.run(lab, october + 29)
	if not _ok(int(_record().served.get(str(ids[3]), 0)) == 15 and int(_record().served.get(str(ids[0]), 0)) == 30, "PT-06: after release the days count again", _record().served): return
	data.site.captivity[str(ids[3])] = {}
	var november := Calendar.day_of(1, 11, 1)
	lab.terrain.site.minute = Calendar.day_start_minute(november) + 600
	var held: Dictionary = Payroll.run(lab, november).paydays[0]
	data.site.captivity.erase(str(ids[3]))
	if not _ok(int(_cargo(ids[3]).get("coin", 0)) == 0 and PersonSocial.arrears_for(_body(ids[3]), key) == {"periods": 0, "tenths": 145} and _events(ids[3], "pay").is_empty() and int(_cargo(ids[0]).get("coin", 0)) == 3, "PT-06: a captive at the payday carries 15/31 of his wage without an event", [held, PersonSocial.arrears(_body(ids[3])), _cargo(ids[0])]): return
	if not _ok(Finance.validate(data.site).ok and PersonSocial.valid(SiteSocial.state_of(_body(ids[3]))), "the record and the packets still validate"): return
	print("SITE_PAYROLL_P1_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
