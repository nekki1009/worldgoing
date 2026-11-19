extends "res://scripts/tests/site_building_ui_test.gd"
## 軍餉與稅收 P3 follow-up (pay-and-tax plan §3.4): a lord funds the teams of his fief. A level 2 settlement of faction 1
## headed by a baron (titled in the test registry) with a bound treasury; a four-person team of faction 1 with a bound pay
## source. Checks:
## - with the settlement's auto_fund off nothing moves; the finance page lets only the head or 度支 switch it;
## - the day before a payday the lord tops up the team's 9-coin bill, keeping a 20-coin reserve; on another day nothing;
## - a team already filled is not short and gets nothing more;
## - an untitled head funds nothing.
## Output: SITE_LORD_FUND_PASS on success; quit(1) on failure.

const LordFund = preload("res://scripts/terrain_lab/site_lord_fund.gd")
const Tribute = preload("res://scripts/terrain_lab/site_tribute.gd")
const Payroll = preload("res://scripts/terrain_lab/site_payroll.gd")
const Finance = preload("res://scripts/terrain_lab/site_finance.gd")
const FinancePage = preload("res://scripts/terrain_lab/site_finance_page.gd")
const ProduceTax = preload("res://scripts/terrain_lab/site_produce_tax.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const Stocks = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const KING := 999

var checks := 0
var ctx := {}

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_LORD_FUND OK ", checks, ": ", message)
		return true
	push_error("SITE_LORD_FUND_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _ref(identity: int) -> Dictionary:
	return RegionPeerage.world_person_ref("w1", identity)

func _registry(baron: int, titled: bool) -> Dictionary:
	var king := _ref(KING)
	var peerage := {RegionPeerage.key_of(king): {"person_ref": king, "faction_id": 1, "rank": "king", "liege_ref": null, "granted_at": 0.0}}
	if titled: peerage[RegionPeerage.key_of(_ref(baron))] = {"person_ref": _ref(baron), "faction_id": 1, "rank": "baron", "liege_ref": king, "granted_at": 0.0}
	return {"version": RegionFactionQuery.VERSION, "revision": 1, "next_faction_id": 2, "migration_complete": true,
		"entries": {"1": {"faction_id": 1, "name": "甲國", "color": "336699ff", "kind": "player", "leader_ref": king, "nation_ref": null,
			"status": "active", "merged_into": null, "founded_at": 0.0, "ended_at": null, "duty_ai": false}},
		"coverage": {"complete": false, "sources": [], "counts": null}, "peerage": peerage}

func _commit(candidate: Dictionary) -> Dictionary:
	var checked := RegionFactionQuery.validate(candidate, 1.0e12)
	if not checked.ok: return checked
	ctx.registry = candidate
	return SiteRuntime.ok()

func _run() -> void:
	var data := _building_fixture()
	var tax_stock := _formal_feature(data, "warehouse", Vector2i(14, 14))
	var treasury_stock := _formal_feature(data, "warehouse", Vector2i(20, 14))
	var team_stock := _formal_feature(data, "warehouse", Vector2i(32, 14))
	var lab := _building_lab(data)
	var team: TerrainArmy = lab.army
	team.roster_size = 4
	team.faction_id = 1
	if not _ok(team.deploy_at(data, null, null, [Vector2i(30, 26), Vector2i(31, 26), Vector2i(32, 26), Vector2i(33, 26)]) and team.enable_combat(false), "a four-person team deploys"): return
	team.set_process(false)
	team.settle_combat_command()
	var head := team.combat_identity(0)
	var clerk := team.combat_identity(1)
	for index: int in range(1, 4): team.combat_units[index]["military_role"] = "officer"
	for key: String in [tax_stock, treasury_stock, team_stock]:
		if not _ok(Stocks.ensure_storage(data, key, 1).ok, "warehouse %s holds a stock" % key): return
		data.site.stockpiles[key].cargo.clear()
	var site_id := str(data.site.id)
	data.site["settlement"] = {"settlement_id": "s1", "owner_faction": 1, "level": 2, "center_id": tax_stock, "offices": SiteOffices.default_offices("settlement", head, false)}
	ctx = {"registry": _registry(head, true), "world": "w1", "commit": _commit}
	var treasury := {"kind": "stock", "site_id": site_id, "feature_id": treasury_stock}
	if not _ok(Tribute.bind_treasury(lab, head, treasury, ctx).ok, "the baron binds his treasury"): return
	var team_ref := SiteSocial.team_ref(site_id, team.team_id)
	if not _ok(Payroll.bind_pay_source(lab, head, team_ref, {"kind": "stock", "site_id": site_id, "feature_id": team_stock}).ok, "the captain binds the team's pay source"): return
	data.site.stockpiles[treasury_stock].cargo["coin"] = 100
	var eve := Calendar.day_of(2, 1, 1) - 1
	data.site.minute = Calendar.day_start_minute(eve) + 600
	if not _ok(LordFund.fund(lab, eve, ctx).is_empty() and int(data.site.stockpiles[team_stock].cargo.get("coin", 0)) == 0, "with auto_fund off nothing moves"): return

	var settlement := {"ref": ProduceTax.settlement_ref(data)}
	var me := int(lab.controlled_person_id())
	var switched: Dictionary = FinancePage.set_auto_fund(lab, settlement, true)
	var allowed: bool = me == head or me == ProduceTax.decider(lab)
	if not _ok(switched.ok == allowed and (allowed or str(switched.code) == "NO_AUTHORITY"), "the finance page lets only the head or 度支 switch a settlement's funding", [me, head, switched]): return
	Finance.ensure(data, settlement.ref, eve).record.auto_fund = true
	var funded := LordFund.fund(lab, eve, ctx)
	if not _ok(int(funded.get("coin", 0)) == 9 and int(data.site.stockpiles[team_stock].cargo.coin) == 9 and int(data.site.stockpiles[treasury_stock].cargo.coin) == 91, "the lord tops up the team's 9-coin bill", funded): return
	if not _ok(LordFund.fund(lab, eve, ctx).get("coin", 0) == 0, "a filled team is not short"): return
	if not _ok(LordFund.fund(lab, eve - 3, ctx).is_empty(), "on another day nothing moves"): return
	data.site.stockpiles[team_stock].cargo.clear()
	data.site.stockpiles[treasury_stock].cargo["coin"] = 25
	funded = LordFund.fund(lab, eve, ctx)
	if not _ok(int(funded.get("coin", 0)) == 5 and int(data.site.stockpiles[treasury_stock].cargo.coin) == 20, "the lord keeps a 20-coin reserve", funded): return
	ctx.registry = _registry(head, false)
	data.site.stockpiles[team_stock].cargo.clear()
	if not _ok(LordFund.fund(lab, eve, ctx).is_empty(), "an untitled head funds nothing"): return
	print("SITE_LORD_FUND_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
