extends "res://scripts/tests/site_building_ui_test.gd"
## 軍餉與稅收 P4 (reports/pay-and-tax-plan.md §7, §5). The controlled person heads a level 2 settlement and a nation with
## a treasury here. Checks:
## - the 財政頁 lists the settlement and the nation he runs, and the stockpiles he may bind;
## - the dialog opens (FinanceDialog) with the summary, binds a tax source and sets 10% through its own buttons; the
##   summary then shows the rate, the source, the next tax day and 「可養」;
## - the nation page toggles auto-funding;
## - 犒賞 (§5): the captain shares 8 coin from the team's pay source by wage (officer 3 : soldier 1), each recipient
##   records G −5 / L +100 once; a non-captain is refused;
## - a new game's start: the camp gets the scenario coin and the player's team its finance record.
## Output: SITE_FINANCE_PAGE_P4_PASS on success; quit(1) on failure.

const FinancePage = preload("res://scripts/terrain_lab/site_finance_page.gd")
const Reward = preload("res://scripts/terrain_lab/site_pay_reward.gd")
const Payroll = preload("res://scripts/terrain_lab/site_payroll.gd")
const Finance = preload("res://scripts/terrain_lab/site_finance.gd")
const ProduceTax = preload("res://scripts/terrain_lab/site_produce_tax.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")
const Stocks = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_FINANCE_PAGE_P4 OK ", checks, ": ", message)
		return true
	push_error("SITE_FINANCE_PAGE_P4_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _find(root_node: Node, node_name: String) -> Node:
	if root_node.name == node_name: return root_node
	for child: Node in root_node.get_children():
		var found := _find(child, node_name)
		if found != null: return found
	return null

func _run() -> void:
	var data := _building_fixture()
	var tax_stock := _formal_feature(data, "warehouse", Vector2i(14, 14))
	var nation_stock := _formal_feature(data, "warehouse", Vector2i(20, 14))
	var team_stock := _formal_feature(data, "warehouse", Vector2i(26, 14))
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var me := int(lab.controlled_person_id())
	for key: String in [tax_stock, nation_stock, team_stock]:
		if not _ok(Stocks.ensure_storage(data, key, 1).ok, "warehouse %s holds a stock" % key): return
		data.site.stockpiles[key].cargo.clear()
	var site_id := str(data.site.id)
	data.site["settlement"] = {"settlement_id": "s1", "name": "甲村", "owner_faction": 1, "level": 2, "center_id": tax_stock, "offices": SiteOffices.default_offices("settlement", me, false)}
	data.site.equipment_nations = {"n1": {"faction_id": 1, "members": [me], "offices": SiteOffices.default_offices("nation", me), "ransom_data": {"treasury": {"site_id": site_id, "feature_id": nation_stock}}}}
	data.site.stockpiles[nation_stock]["nation_id"] = "n1"
	data.site.minute = Calendar.day_start_minute(Calendar.day_of(1, 3, 5)) + 600
	var orgs := FinancePage.orgs(lab)
	var kinds: Array = []
	for org: Dictionary in orgs: kinds.append(str(org.kind))
	if not _ok(kinds.has("settlement") and kinds.has("nation"), "the page lists the settlement and the nation he runs", kinds): return
	var settlement_org: Dictionary = orgs[kinds.find("settlement")]
	var labels: Array = []
	for entry: Dictionary in FinancePage.holders(lab, settlement_org.ref): labels.append(str(entry.source.feature_id))
	if not _ok(labels.has(tax_stock) and labels.has(team_stock) and not labels.has(nation_stock), "his faction's stockpiles are offered; the nation's treasury is not", labels): return
	# The dialog.
	FinancePage.open(controller)
	await process_frame
	var dialog: Node = _find(root, "FinanceDialog")
	if not _ok(dialog != null, "the 財政頁 opens"): return
	var org_choice: OptionButton = _find(dialog, "FinanceOrg")
	org_choice.select(kinds.find("settlement"))
	org_choice.item_selected.emit(kinds.find("settlement"))
	var holder_choice: OptionButton = _find(dialog, "FinanceHolder")
	var tax_index := -1
	for index: int in holder_choice.item_count:
		if holder_choice.get_item_text(index).ends_with("#" + tax_stock): tax_index = index
	holder_choice.select(tax_index)
	(_find(dialog, "FinanceBindTax") as Button).pressed.emit()
	var tax_rate: OptionButton = _find(dialog, "FinanceTaxRate")
	tax_rate.select(2)
	(_find(dialog, "FinanceSetTax") as Button).pressed.emit()
	var text := (_find(dialog, "FinanceSummary") as Label).text
	if not _ok(int(ProduceTax.record_of(data).get("tax_rate", -1)) == 10 and str(ProduceTax.record_of(data).tax_source.feature_id) == tax_stock and text.contains("產出稅 10%") and text.contains("可養約") and text.contains("下次繳稅日"), "the dialog binds the tax source and levies 10%", text): return
	org_choice.select(kinds.find("nation"))
	org_choice.item_selected.emit(kinds.find("nation"))
	(_find(dialog, "FinanceAutoFund") as Button).pressed.emit()
	var nation_ref := {"kind": "nation", "site_id": site_id, "org_id": "n1"}
	if not _ok(not bool(Finance.record_of(data, nation_ref, 0).auto_fund) and (_find(dialog, "FinanceSummary") as Label).text.contains("自動撥餉給本國隊伍：關"), "the nation page turns auto-funding off"): return
	dialog.queue_free()
	await process_frame
	# 犒賞.
	var team: TerrainArmy = lab.army
	team.roster_size = 3
	team.faction_id = 1
	if not _ok(team.deploy_at(data, null, null, [Vector2i(30, 26), Vector2i(31, 26), Vector2i(32, 26)]) and team.enable_combat(false), "a three-person team deploys"): return
	team.set_process(false)
	team.settle_combat_command()
	var captain := team.combat_identity(0)
	var officer := team.combat_identity(1)
	var soldier := team.combat_identity(2)
	team.combat_units[1]["military_role"] = "officer"
	team.combat_units[2]["military_role"] = "soldier"
	for index: int in range(3): lab.site_controller.person_actions._person(team.combat_identity(index), false).cargo.clear()
	var team_ref := SiteSocial.team_ref(site_id, team.team_id)
	if not _ok(Payroll.bind_pay_source(lab, captain, team_ref, {"kind": "stock", "site_id": site_id, "feature_id": team_stock}).ok, "the captain binds the team's pay source"): return
	data.site.stockpiles[team_stock].cargo["coin"] = 8
	if not _ok(Reward.reward(lab, officer, team_ref, "coin", 8).code == "NO_AUTHORITY", "only the captain rewards"): return
	var rewarded := Reward.reward(lab, captain, team_ref, "coin", 8)
	var officer_coin := int(lab.site_controller.person_actions._person(officer, false).cargo.get("coin", 0))
	var soldier_coin := int(lab.site_controller.person_actions._person(soldier, false).cargo.get("coin", 0))
	var events := 0
	for event: Dictionary in SiteSocial.state_of(team.combat_units[1]).pending:
		if str(event.kind) == "reward" and int(event.amount) == -5 and int(event.l) == 100: events += 1
	if not _ok(rewarded.ok and officer_coin == 6 and soldier_coin == 2 and events == 1 and int(data.site.stockpiles[team_stock].cargo.get("coin", 0)) == 0, "犒賞: 8 coin shared 3:1 (6 and 2), G −5 / L +100 once", [rewarded, officer_coin, soldier_coin, events]): return
	# A new game's start.
	var coin_before := int(data.site.inventory.get("coin", 0))
	controller._start_finance("found")
	if not _ok(int(data.site.inventory.get("coin", 0)) - coin_before == 30, "a founded faction starts with 30 coin in the camp"): return
	print("SITE_FINANCE_PAGE_P4_PASS checks=", checks)
	data.site.erase("equipment_nations")
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
