extends "res://scripts/tests/site_building_ui_test.gd"
## 軍餉與稅收 P3 (reports/pay-and-tax-plan.md §3.4, §4.3; PT-09..11). A level 2 settlement of faction 1 headed by a
## baron whose liege is the king (person 999, elsewhere); the world registry is a test context whose commit records the
## candidate (the Region checkpoint itself is the existing peerage/diplomacy path). Checks:
## - the registry's new finance section validates, and a broken one is refused;
## - binding the fief treasury: only the head (or 度支); a titled head's seat moves to this Site;
## - the tax day: with no seat for the liege nothing is due; with a seat elsewhere 10% of last season's receipts goes
##   on the road (coin first, then grain) to arrive after the travel days, the head +1 credit (PT-09); short → −2
##   credit and the unpaid streak (PT-10); an exempt season is free;
## - delivery: tribute due here enters the settlement treasury as tribute_in and leaves the road;
## - funding (PT-11): the day before a payday the nation's treasury tops up its member team's pay source, never below
##   the 20-coin reserve.
## Output: SITE_TRIBUTE_P3_PASS on success; quit(1) on failure.

const Tribute = preload("res://scripts/terrain_lab/site_tribute.gd")
const Payroll = preload("res://scripts/terrain_lab/site_payroll.gd")
const ProduceTax = preload("res://scripts/terrain_lab/site_produce_tax.gd")
const Finance = preload("res://scripts/terrain_lab/site_finance.gd")
const PayTable = preload("res://scripts/terrain_lab/site_pay_table.gd")
const RegionFinance = preload("res://scripts/region_lab/region_finance.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const Stocks = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const Reputation = preload("res://scripts/terrain_lab/person_reputation.gd")
const KING := 999
const ELSEWHERE := "atlas:900:900"

var checks := 0
var ctx := {}
var commits := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_TRIBUTE_P3 OK ", checks, ": ", message)
		return true
	push_error("SITE_TRIBUTE_P3_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _ref(identity: int) -> Dictionary:
	return RegionPeerage.world_person_ref("w1", identity)

func _registry(baron: int) -> Dictionary:
	var king := _ref(KING)
	return {"version": RegionFactionQuery.VERSION, "revision": 1, "next_faction_id": 2, "migration_complete": true,
		"entries": {"1": {"faction_id": 1, "name": "甲國", "color": "336699ff", "kind": "player", "leader_ref": king, "nation_ref": null,
			"status": "active", "merged_into": null, "founded_at": 0.0, "ended_at": null, "duty_ai": false}},
		"coverage": {"complete": false, "sources": [], "counts": null},
		"peerage": {RegionPeerage.key_of(king): {"person_ref": king, "faction_id": 1, "rank": "king", "liege_ref": null, "granted_at": 0.0},
			RegionPeerage.key_of(_ref(baron)): {"person_ref": _ref(baron), "faction_id": 1, "rank": "baron", "liege_ref": king, "granted_at": 0.0}}}

## The test world's commit: the candidate must validate, then it becomes the registry.
func _commit(candidate: Dictionary) -> Dictionary:
	var checked := RegionFactionQuery.validate(candidate, 1.0e12)
	if not checked.ok: return checked
	ctx.registry = candidate
	commits += 1
	return SiteRuntime.ok()

func _day_minute(day: int) -> int:
	return Calendar.day_start_minute(day) + 600

func _run() -> void:
	var data := _building_fixture()
	var tax_stock := _formal_feature(data, "warehouse", Vector2i(14, 14))
	var treasury_stock := _formal_feature(data, "warehouse", Vector2i(20, 14))
	var nation_stock := _formal_feature(data, "warehouse", Vector2i(26, 14))
	var team_stock := _formal_feature(data, "warehouse", Vector2i(32, 14))
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var team: TerrainArmy = lab.army
	team.roster_size = 4
	team.faction_id = 1
	if not _ok(team.deploy_at(data, null, null, [Vector2i(30, 26), Vector2i(31, 26), Vector2i(32, 26), Vector2i(33, 26)]) and team.enable_combat(false), "a four-person team deploys"): return
	team.set_process(false)
	team.settle_combat_command()
	var head := team.combat_identity(0)
	var clerk := team.combat_identity(1)
	for index: int in range(1, 4): team.combat_units[index]["military_role"] = "officer"
	for key: String in [tax_stock, treasury_stock, nation_stock, team_stock]:
		if not _ok(Stocks.ensure_storage(data, key, 1).ok, "warehouse %s holds a stock" % key): return
		data.site.stockpiles[key].cargo.clear()
	var site_id := str(data.site.id)
	data.site["settlement"] = {"settlement_id": "s1", "owner_faction": 1, "level": 2, "center_id": tax_stock, "offices": SiteOffices.default_offices("settlement", head, false)}
	ctx = {"registry": _registry(head), "world": "w1", "commit": _commit}
	# The registry section.
	var with_finance: Dictionary = RegionFinance.candidate(ctx.registry)
	if not _ok(RegionFactionQuery.validate(with_finance, 1.0e12).ok, "the registry's finance section validates", RegionFactionQuery.validate(with_finance, 1.0e12)): return
	with_finance.finance.transit.append({"id": 7, "kind": "gift"})
	if not _ok(not RegionFactionQuery.validate(with_finance, 1.0e12).ok, "a broken finance section is refused"): return
	# The fief treasury.
	var march := Calendar.day_of(1, 3, 1)
	data.site.minute = _day_minute(march - 20)
	var tax_source := {"kind": "stock", "site_id": site_id, "feature_id": tax_stock}
	if not _ok(ProduceTax.set_tax(lab, head, 10, tax_source).ok, "the head levies 10% into the tax warehouse"): return
	var treasury := {"kind": "stock", "site_id": site_id, "feature_id": treasury_stock}
	if not _ok(Tribute.bind_treasury(lab, clerk, treasury, ctx).code == "NO_AUTHORITY", "a clerk may not bind the fief treasury"): return
	var bound := Tribute.bind_treasury(lab, head, treasury, ctx)
	if not _ok(bound.ok and commits == 1 and RegionFinance.seat_of(ctx.registry, RegionPeerage.key_of(_ref(head))) == site_id, "the baron binds his treasury; his seat is this Site", bound): return
	var record: Dictionary = ProduceTax.record_of(data)
	# No seat for the king: nothing due.
	var spring := PayTable.season_index(march)
	Finance.add_receipt(record, "produce_tax", 500, spring - 1)
	data.site.minute = _day_minute(march)
	var none := Tribute.tax_day(lab, march, ctx)
	if not _ok(int(none.get("due", -1)) == 0 and str(none.get("reason", "")) == "no_seat" and int(record.last_taxday) == spring, "the king has no seat: nothing is due", none): return
	# PT-09: the king's seat elsewhere.
	var seated := RegionFinance.candidate(ctx.registry)
	seated.finance.seats[RegionPeerage.key_of(_ref(KING))] = ELSEWHERE
	ctx.commit.call(seated)
	var summer := Calendar.day_of(1, 6, 1)
	Finance.add_receipt(record, "produce_tax", 500, spring)
	data.site.stockpiles[tax_stock].cargo["grain"] = 50
	var credit_before := int(controller.reputation_of(head).credit)
	data.site.minute = _day_minute(summer)
	var paid := Tribute.tax_day(lab, summer, ctx)
	var transit: Array = RegionFinance.section(ctx.registry).transit
	if not _ok(bool(paid.get("on_time", false)) and int(paid.due) == 50 and transit.size() == 1 and transit[0].items == {"grain": 5} and str(transit[0].to_site) == ELSEWHERE \
		and int(transit[0].arrive_day) > summer and int(data.site.stockpiles[tax_stock].cargo.grain) == 45 and int(controller.reputation_of(head).credit) - credit_before == Reputation.SCALE, "PT-09: 10% of 50 points goes on the road as 5 grain; the head +1 credit", [paid, transit]): return
	# PT-10: short.
	var autumn := Calendar.day_of(1, 9, 1)
	Finance.add_receipt(record, "produce_tax", 500, PayTable.season_index(summer))
	data.site.stockpiles[tax_stock].cargo.clear()
	credit_before = int(controller.reputation_of(head).credit)
	data.site.minute = _day_minute(autumn)
	var short := Tribute.tax_day(lab, autumn, ctx)
	if not _ok(not bool(short.get("on_time", true)) and int(record.unpaid_seasons) == 1 and int(controller.reputation_of(head).credit) - credit_before == -2 * Reputation.SCALE and RegionFinance.section(ctx.registry).transit.size() == 1, "PT-10: nothing to pay: −2 credit, one unpaid season, nothing on the road", short): return
	# Exemption.
	var winter := Calendar.day_of(1, 12, 1)
	if not _ok(Tribute.exempt(lab, head, site_id, PayTable.season_index(winter), ctx).code == "NO_AUTHORITY" and Tribute.exempt(lab, KING, site_id, PayTable.season_index(winter), ctx).ok, "only the faction head exempts"): return
	Finance.add_receipt(record, "produce_tax", 500, PayTable.season_index(autumn))
	data.site.minute = _day_minute(winter)
	var exempt := Tribute.tax_day(lab, winter, ctx)
	if not _ok(str(exempt.get("reason", "")) == "exempt" and int(record.unpaid_seasons) == 1, "an exempt season is free and the streak stands", exempt): return
	# Delivery.
	var incoming := RegionFinance.candidate(ctx.registry)
	RegionFinance.add_transit(incoming, {"kind": "tribute", "from_site": ELSEWHERE, "to_site": site_id, "to": RegionPeerage.key_of(_ref(head)), "items": {"coin": 2},
		"tenths": 200, "arrive_day": winter + 3, "season": PayTable.season_index(winter), "payer": "x"})
	ctx.commit.call(incoming)
	if not _ok(int(Tribute.deliver(lab, winter + 2, ctx).count) == 0, "goods on the road do not arrive early"): return
	var delivered := Tribute.deliver(lab, winter + 3, ctx)
	if not _ok(int(delivered.count) == 1 and int(data.site.stockpiles[treasury_stock].cargo.get("coin", 0)) == 2 and Finance.receipts_of(record, "tribute_in", PayTable.season_index(winter)) == 200 \
		and RegionFinance.section(ctx.registry).transit.size() == 1, "tribute arrives in the treasury as tribute_in and leaves the road", delivered): return
	# PT-11: funding.
	data.site.equipment_nations = {"n1": {"faction_id": 1, "members": [head], "ransom_data": {"treasury": {"site_id": site_id, "feature_id": nation_stock}}}}
	data.site.stockpiles[nation_stock].cargo["coin"] = 25
	var team_ref := SiteSocial.team_ref(site_id, team.team_id)
	if not _ok(Payroll.bind_pay_source(lab, head, team_ref, {"kind": "stock", "site_id": site_id, "feature_id": team_stock}).ok, "the captain binds the team's pay source"): return
	var eve := Calendar.day_of(2, 1, 1) - 1
	data.site.minute = _day_minute(eve)
	var funded := Tribute.fund(lab, eve)
	if not _ok(int(funded.get("coin", 0)) == 5 and int(data.site.stockpiles[team_stock].cargo.get("coin", 0)) == 5 and int(data.site.stockpiles[nation_stock].cargo.coin) == 20, "PT-11: the nation tops up 5 coin, keeping its 20-coin reserve", funded): return
	data.site.stockpiles[nation_stock].cargo["coin"] = 100
	data.site.stockpiles[team_stock].cargo.clear()
	funded = Tribute.fund(lab, eve)
	if not _ok(int(funded.get("coin", 0)) == 9 and int(data.site.stockpiles[team_stock].cargo.coin) == 9, "PT-11: three officers' month (90 points) is 9 coin", funded): return
	if not _ok(Finance.validate(data.site).ok, "the finance records validate", Finance.validate(data.site)): return
	data.site.erase("equipment_nations")
	print("SITE_TRIBUTE_P3_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
