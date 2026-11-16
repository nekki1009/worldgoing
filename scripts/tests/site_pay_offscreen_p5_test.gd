extends "res://scripts/tests/site_building_ui_test.gd"
## 軍餉與稅收 P5 (reports/pay-and-tax-plan.md §6.1, §8.1; PT-12, PT-13 adapted). Checks:
## - the start-of-battle morale factor: ×(1 − 0.1 × unpaid paydays), at least ×0.7 (crowd morale is per team: the
##   team's mean is used);
## - PT-13: a Site away 120 days settles its four paydays on return, each once (a second run pays nothing);
## - a season that began while the Site was away is settled on its first live day, once;
## - the long-absence catch-up's household batch pays the production tax into the tax source.
## Output: SITE_PAY_OFFSCREEN_P5_PASS on success; quit(1) on failure.

const Payroll = preload("res://scripts/terrain_lab/site_payroll.gd")
const Tribute = preload("res://scripts/terrain_lab/site_tribute.gd")
const ProduceTax = preload("res://scripts/terrain_lab/site_produce_tax.gd")
const ResidentWork = preload("res://scripts/terrain_lab/site_resident_work.gd")
const Finance = preload("res://scripts/terrain_lab/site_finance.gd")
const PayTable = preload("res://scripts/terrain_lab/site_pay_table.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const Stocks = preload("res://scripts/terrain_lab/site_stockpiles.gd")

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_PAY_OFFSCREEN_P5 OK ", checks, ": ", message)
		return true
	push_error("SITE_PAY_OFFSCREEN_P5_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _run() -> void:
	if not _ok(Payroll.morale_factor(0) == 1.0 and is_equal_approx(Payroll.morale_factor(2), 0.8) and is_equal_approx(Payroll.morale_factor(5), 0.7) and is_equal_approx(Payroll.morale_factor(9), 0.7) and is_equal_approx(Payroll.morale_factor(1.5), 0.85), "the morale factor: ×0.9 a payday, at least ×0.7"): return
	var data := _building_fixture()
	var stock_key := _formal_feature(data, "warehouse", Vector2i(14, 14))
	var tax_key := _formal_feature(data, "warehouse", Vector2i(20, 14))
	var farm := _formal_feature(data, "farm", Vector2i(26, 14), Vector2i(6, 6))
	var house := _formal_feature(data, "house", Vector2i(16, 26), Vector2i.ONE, {"variant": "small"})
	var lab := _building_lab(data)
	var team: TerrainArmy = lab.army
	team.roster_size = 3
	team.faction_id = 1
	if not _ok(team.deploy_at(data, null, null, [Vector2i(30, 26), Vector2i(31, 26), Vector2i(32, 26)]) and team.enable_combat(false), "a three-person team deploys"): return
	team.set_process(false)
	team.settle_combat_command()
	var head := team.combat_identity(0)
	if not _ok(Stocks.ensure_storage(data, stock_key, 1).ok and Stocks.ensure_storage(data, tax_key, 1).ok, "the warehouses hold stocks"): return
	var stock: Dictionary = data.site.stockpiles[tax_key]
	stock.cargo.clear()
	data.site.stockpiles[stock_key].cargo.clear()
	var site_id := str(data.site.id)
	var source := {"kind": "stock", "site_id": site_id, "feature_id": stock_key}
	# PT-13: 120 days away.
	var team_ref := SiteSocial.team_ref(site_id, team.team_id)
	var start := Calendar.day_of(1, 3, 15)
	data.site.minute = Calendar.day_start_minute(start) + 600
	if not _ok(Payroll.bind_pay_source(lab, head, team_ref, source).ok, "the captain binds a pay source"): return
	var record: Dictionary = data.site.finance[Finance.org_key(team_ref)]
	record.accrued_day = start
	var back := start + 120
	data.site.minute = Calendar.day_start_minute(back) + 600
	var settled: Array = Payroll.run(lab, back).paydays
	var indexes: Array = []
	for payday: Dictionary in settled: indexes.append(int(payday.payday))
	if not _ok(settled.size() == 4 and indexes == [PayTable.payday_index(Calendar.day_of(1, 4, 1)), PayTable.payday_index(Calendar.day_of(1, 5, 1)), PayTable.payday_index(Calendar.day_of(1, 6, 1)), PayTable.payday_index(Calendar.day_of(1, 7, 1))], "PT-13: four paydays settle on return", indexes): return
	if not _ok((Payroll.run(lab, back).paydays as Array).is_empty(), "PT-13: a second run pays nothing again"): return
	# A season that began away.
	data.site["settlement"] = {"settlement_id": "s1", "owner_faction": 1, "level": 2, "center_id": stock_key, "offices": SiteOffices.default_offices("settlement", head, false)}
	var tax_source := {"kind": "stock", "site_id": site_id, "feature_id": tax_key}
	if not _ok(ProduceTax.set_tax(lab, head, 10, tax_source).ok, "the head levies 10%"): return
	var settlement_record: Dictionary = ProduceTax.record_of(data)
	var mid_summer := Calendar.day_of(1, 7, 20)
	data.site.minute = Calendar.day_start_minute(mid_summer) + 600
	var first := Tribute.tax_day(lab, mid_summer)
	var again := Tribute.tax_day(lab, mid_summer + 1)
	if not _ok(not first.is_empty() and int(settlement_record.last_taxday) == PayTable.season_index(mid_summer) and again.is_empty(), "a season begun away is settled on the first live day, once", [first, again]): return
	# The catch-up's household batch pays the tax.
	var resident := team.combat_identity(2)
	data.site["housing"] = {str(resident): {"version": 1, "house_id": house, "cell": 0}}
	data.site["households"] = {house: {"job": {"feature": farm}}}
	var before := int(stock.cargo.get("grain", 0))
	var minutes := {}
	var made := ResidentWork.daily_production(data.site, minutes, data)
	var recipe: Dictionary = Runtime.feature_recipe(data.site.features[farm])
	var grain_out := int(recipe.get("output", {}).get("grain", 0))
	if not _ok(made >= 1 and grain_out > 0 and int(stock.cargo.get("grain", 0)) - before == (grain_out * made * 10) / 100, "a catch-up batch pays 10% of its grain into the tax source", [made, recipe.get("output"), int(stock.cargo.get("grain", 0)) - before]): return
	data.site.erase("housing")
	data.site.erase("households")
	print("SITE_PAY_OFFSCREEN_P5_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
