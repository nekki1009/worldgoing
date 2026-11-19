extends "res://scripts/tests/site_building_ui_test.gd"
## 軍餉與稅收 P2 (reports/pay-and-tax-plan.md §4.1–§4.2, §6; PT-07, PT-08). A level 2 settlement of faction 1 whose
## center is a warehouse; the warehouse is also the tax source; a farm and a house stand inside the jurisdiction.
## Checks:
## - authority: the head acts while 度支 (settlement.finance) is vacant; once seated, only the 度支 sets the rate; a rate
##   outside 0/5/10/15/20 is refused, 15%+ needs N09 known by the settlement's nation, levying needs a tax source;
## - PT-07: 10% of a 50-grain harvest: 5 grain into the tax source, 45 kept, a produce_tax receipt of 5 points;
## - remainders: four 3-grain batches at 10% tax one grain on the fourth and carry 20 hundredths;
## - a building of another faction, one outside the jurisdiction, a full tax source: nothing taken;
## - the real batch path (SiteRuntime.publish_feature_output) pays the tax;
## - PT-08: at 20% for 10 days a registered resident records G +2 a day (+20); a non-resident nothing; at 10% nothing.
## Output: SITE_PRODUCE_TAX_P2_PASS on success; quit(1) on failure.

const ProduceTax = preload("res://scripts/terrain_lab/site_produce_tax.gd")
const Finance = preload("res://scripts/terrain_lab/site_finance.gd")
const PayTable = preload("res://scripts/terrain_lab/site_pay_table.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const Stocks = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const PersonSocial = preload("res://scripts/terrain_lab/person_social.gd")

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_PRODUCE_TAX_P2 OK ", checks, ": ", message)
		return true
	push_error("SITE_PRODUCE_TAX_P2_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _tax_events(body: Variant) -> int:
	var total := 0
	for event: Dictionary in SiteSocial.state_of(body).pending:
		if str(event.kind) == "tax": total += int(event.amount)
	return total

func _run() -> void:
	var data := _building_fixture()
	var warehouse := _formal_feature(data, "warehouse", Vector2i(20, 20))
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
	var steward := team.combat_identity(1)
	var resident := team.combat_identity(2)
	PersonSocial.set_civil_role(team.combat_units[1], "clerk")
	if not _ok(Stocks.ensure_storage(data, warehouse, 1).ok, "the warehouse holds a stock"): return
	var stock: Dictionary = data.site.stockpiles[warehouse]
	stock.cargo.clear()
	data.site["settlement"] = {"settlement_id": "s1", "owner_faction": 1, "level": 2, "center_id": warehouse, "offices": SiteOffices.default_offices("settlement", head, false)}
	var offices: Dictionary = data.site.settlement.offices
	if not _ok(offices.duties.has("settlement.finance") and ProduceTax.decider(lab) == head, "度支 is a settlement duty; the head acts while it is vacant", offices.duties): return
	data.site.minute = Calendar.day_start_minute(Calendar.day_of(1, 3, 1)) + 600
	var source := {"kind": "stock", "site_id": str(data.site.id), "feature_id": warehouse}
	if not _ok(ProduceTax.set_tax(lab, resident, 10, source).code == "NO_AUTHORITY", "a resident may not set the rate"): return
	if not _ok(ProduceTax.set_tax(lab, head, 10).code == "NO_TARGET", "levying needs a tax source"): return
	if not _ok(ProduceTax.set_tax(lab, head, 7, source).code == "INVALID", "7% is not a rate"): return
	if not _ok(ProduceTax.set_tax(lab, head, 15, source).code == "NO_TECHNOLOGY", "15% needs N09"): return
	if not _ok(ProduceTax.set_tax(lab, head, 10, source).ok and int(ProduceTax.record_of(data).tax_rate) == 10, "the acting head levies 10% into the warehouse"): return
	SiteOffices.position(offices, str(offices.duties["settlement.finance"])).holder = steward
	if not _ok(ProduceTax.decider(lab) == steward and ProduceTax.set_tax(lab, head, 5).code == "NO_AUTHORITY" and ProduceTax.set_tax(lab, steward, 10).ok, "once seated only the 度支 decides"): return
	# PT-07.
	var farm_feature: Dictionary = data.site.features[farm]
	var kept: Dictionary = ProduceTax.levy(data, farm, farm_feature, {"grain": 50})
	var record: Dictionary = ProduceTax.record_of(data)
	var season := PayTable.season_index(Calendar.day_index(float(data.site.minute)))
	if not _ok(kept == {"grain": 45} and int(stock.cargo.get("grain", 0)) == 5 and Finance.receipts_of(record, "produce_tax", season) == 50, "PT-07: 5 of 50 grain taxed, a 5-point receipt", [kept, stock.cargo, record.receipts]): return
	# Remainders.
	var small: Array = []
	for _batch: int in range(4): small.append(ProduceTax.levy(data, farm, farm_feature, {"grain": 3}))
	if not _ok(small == [{"grain": 3}, {"grain": 3}, {"grain": 3}, {"grain": 2}] and int(stock.cargo.grain) == 6 and record.tax_carry == {farm: {"grain": 20}}, "a fraction carries until a whole unit is due", [small, record.tax_carry]): return
	# Untaxed cases.
	var foreign := farm_feature.duplicate(true)
	foreign.owner_faction = 2
	var far := farm_feature.duplicate(true)
	far.cells = [data.index(Vector2i(55, 55))]
	if not _ok(ProduceTax.levy(data, "x1", foreign, {"grain": 50}) == {"grain": 50} and ProduceTax.levy(data, "x2", far, {"grain": 50}) == {"grain": 50} and int(stock.cargo.grain) == 6, "another faction's building and one outside the jurisdiction pay nothing"): return
	stock.cargo["stone"] = Stocks.capacity(data.site.features[warehouse]) - Runtime.carried_size(stock.cargo, stock.holder)
	if not _ok(ProduceTax.levy(data, farm, farm_feature, {"grain": 50}) == {"grain": 50}, "a full tax source takes nothing"): return
	stock.cargo.erase("stone")
	# The real batch path.
	record.tax_carry.clear()
	var recipe: Dictionary = Runtime.feature_recipe(farm_feature)
	farm_feature.batch_paid = true
	farm_feature.production = float(recipe.cycle)
	var cargo := {}
	var before := int(stock.cargo.get("grain", 0))
	var prepared := Runtime.prepare_feature_output(data, farm_feature, data.site.worker, cargo, 100000)
	if not _ok(prepared.ok and str(prepared.get("feature_key", "")) == farm, "the farm's batch is ready", prepared.get("code", "")): return
	Runtime.publish_feature_output(data, prepared)
	var grown := 0
	for item: String in recipe.output: grown += int(recipe.output[item])
	var taxed := int(stock.cargo.get("grain", 0)) - before
	if not _ok(taxed == int(recipe.output.get("grain", 0)) * 10 / 100 and Runtime.inventory_size(cargo) == grown - taxed, "the published batch pays its tax", [recipe.output, cargo, taxed]): return
	# PT-08.
	data.site.equipment_nations = {"n1": {"faction_id": 1, "technology": Technology.empty_scope_record(str(data.site.id))}}
	data.site.equipment_nations.n1.technology.known.append("N09")
	if not _ok(ProduceTax.set_tax(lab, steward, 20).ok, "with N09 the 度支 levies 20%"): return
	data.site["housing"] = {str(resident): {"version": 1, "house_id": house, "cell": 0}}
	if not _ok(ProduceTax.residents(data) == [resident], "the housed person is the registered resident", ProduceTax.residents(data)): return
	for day: int in range(10):
		data.site.minute = Calendar.day_start_minute(Calendar.day_of(1, 3, 2) + day) + 600
		ProduceTax.day(lab)
	if not _ok(_tax_events(team.combat_units[2]) == 20 and _tax_events(team.combat_units[0]) == 0, "PT-08: 20% for 10 days: the resident G +20, a non-resident 0", [_tax_events(team.combat_units[2]), _tax_events(team.combat_units[0])]): return
	ProduceTax.set_tax(lab, steward, 10)
	data.site.minute = Calendar.day_start_minute(Calendar.day_of(1, 3, 20)) + 600
	ProduceTax.day(lab)
	if not _ok(_tax_events(team.combat_units[2]) == 20, "at 10% no grievance"): return
	if not _ok(Finance.validate(data.site).ok, "the settlement's finance record validates", Finance.validate(data.site)): return
	data.site.erase("housing")
	print("SITE_PRODUCE_TAX_P2_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
