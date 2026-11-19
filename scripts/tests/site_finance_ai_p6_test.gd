extends "res://scripts/tests/site_building_ui_test.gd"
## 軍餉與稅收 P6 (reports/pay-and-tax-plan.md §9, §4.4). An NPC captain heads both a team and the settlement here. Checks:
## - the NPC captain binds a pay source (a faction stockpile) for his team; the player's own team is left alone;
## - the NPC settlement levies 10% into a tax source; on the first of a month residents' grievance above 60 lowers it a
##   step, two unpaid tribute seasons raise it a step, and without N09 it stops at 10% (with N09 at 15%, never 20%);
## - recruit_cap follows §4.4 × 1.2.
## Output: SITE_FINANCE_AI_P6_PASS on success; quit(1) on failure.

const FinanceAI = preload("res://scripts/terrain_lab/site_finance_ai.gd")
const Finance = preload("res://scripts/terrain_lab/site_finance.gd")
const ProduceTax = preload("res://scripts/terrain_lab/site_produce_tax.gd")
const PayTable = preload("res://scripts/terrain_lab/site_pay_table.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const Stocks = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_FINANCE_AI_P6 OK ", checks, ": ", message)
		return true
	push_error("SITE_FINANCE_AI_P6_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _review(lab: TerrainLab, month: int) -> Dictionary:
	var day := Calendar.day_of(1, month, 1)
	lab.terrain.site.minute = Calendar.day_start_minute(day) + 600
	return FinanceAI.settlement_tax(lab, day)

func _run() -> void:
	var data := _building_fixture()
	var pay_stock := _formal_feature(data, "warehouse", Vector2i(14, 14))
	var tax_stock := _formal_feature(data, "warehouse", Vector2i(20, 14))
	var house := _formal_feature(data, "house", Vector2i(16, 26), Vector2i.ONE, {"variant": "small"})
	var lab := _building_lab(data)
	var team: TerrainArmy = lab.army
	team.roster_size = 3
	team.faction_id = 1
	if not _ok(team.deploy_at(data, null, null, [Vector2i(30, 26), Vector2i(31, 26), Vector2i(32, 26)]) and team.enable_combat(false), "a three-person NPC team deploys"): return
	team.set_process(false)
	team.settle_combat_command()
	var captain := team.combat_identity(0)
	var resident := team.combat_identity(2)
	for key: String in [pay_stock, tax_stock]:
		if not _ok(Stocks.ensure_storage(data, key, 1).ok, "warehouse %s holds a stock" % key): return
	var site_id := str(data.site.id)
	data.site.minute = Calendar.day_start_minute(Calendar.day_of(1, 2, 10)) + 600
	# The NPC team binds a pay source.
	var bound := FinanceAI.bind_npc_teams(lab)
	var team_ref := SiteSocial.team_ref(site_id, team.team_id)
	var record: Dictionary = Finance.records(data).get(Finance.org_key(team_ref), {})
	if not _ok(bound == 1 and not record.is_empty() and str(record.pay_source.feature_id) == pay_stock, "the NPC captain binds the first faction stockpile as the pay source", record): return
	if not _ok(FinanceAI.bind_npc_teams(lab) == 0, "a bound team is left alone"): return
	# The NPC settlement.
	data.site["settlement"] = {"settlement_id": "s1", "owner_faction": 1, "level": 2, "center_id": tax_stock, "offices": SiteOffices.default_offices("settlement", captain, false)}
	var first := FinanceAI.settlement_tax(lab, Calendar.day_of(1, 2, 10))
	var tax_record := ProduceTax.record_of(data)
	if not _ok(bool(first.get("changed", false)) and int(tax_record.tax_rate) == 10 and str(tax_record.tax_source.feature_id) == tax_stock, "the NPC 度支 levies 10% into the free stockpile", first): return
	if not _ok(not bool(FinanceAI.settlement_tax(lab, Calendar.day_of(1, 2, 11)).get("changed", true)), "no review between months"): return
	# Grievance lowers the rate.
	data.site["housing"] = {str(resident): {"version": 1, "house_id": house, "cell": 0}}
	var settlement_ref := ProduceTax.settlement_ref(data)
	var packet := SiteSocial.state_of(team.combat_units[2])
	SiteSocial.relation(packet, settlement_ref).G = 80
	var lowered := _review(lab, 3)
	if not _ok(int(tax_record.tax_rate) == 5 and float(lowered.get("grievance", 0.0)) > 60.0, "residents' grievance 80 lowers the rate to 5%", lowered): return
	SiteSocial.relation(packet, settlement_ref).G = 10
	tax_record.unpaid_seasons = 2
	_review(lab, 4)
	if not _ok(int(tax_record.tax_rate) == 10, "two unpaid tribute seasons raise it back to 10%"): return
	_review(lab, 5)
	if not _ok(int(tax_record.tax_rate) == 10, "without N09 it stops at 10%"): return
	data.site.equipment_nations = {"n1": {"faction_id": 1, "technology": Technology.empty_scope_record(site_id)}}
	data.site.equipment_nations.n1.technology.known.append("N09")
	_review(lab, 6)
	_review(lab, 7)
	if not _ok(int(tax_record.tax_rate) == 15, "with N09 an NPC goes to 15% and never 20%"): return
	# §4.4.
	Finance.add_receipt(tax_record, "produce_tax", 3600, PayTable.season_index(Calendar.day_of(1, 7, 1)) - 1)
	if not _ok(FinanceAI.recruit_cap(lab) == floori(360.0 / 120.0 * 1.2), "recruit cap: (last season 360 points) / 120 × 1.2", FinanceAI.recruit_cap(lab)): return
	data.site.erase("housing")
	data.site.erase("equipment_nations")
	print("SITE_FINANCE_AI_P6_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
