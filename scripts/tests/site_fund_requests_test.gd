extends "res://scripts/tests/site_building_ui_test.gd"
## 軍餉與稅收 P3 follow-up (pay-and-tax plan §3.4): funding across Sites. A level 2 settlement of faction 1 whose head is
## a baron; faction 1's head is the king (person 999) whose fief seat is first another Site, then this one. The world
## registry is a test context whose commit validates and records the candidate. Checks:
## - an old finance section without requests validates; a malformed request is refused;
## - the day before a payday a short team here files one request to the king's seat elsewhere (the coins it lacks);
##   the next pass does not file it twice; a team that is not short files nothing;
## - at the seat (this Site's bound treasury): a request is paid as "fund" goods on the road to the team's Site, within
##   the daily cap and above the reserve; the request leaves; one older than 30 days is dropped unpaid;
## - fund goods arriving here enter the team's pay source.
## Output: SITE_FUND_REQUESTS_PASS on success; quit(1) on failure.

const Requests = preload("res://scripts/terrain_lab/site_fund_requests.gd")
const Tribute = preload("res://scripts/terrain_lab/site_tribute.gd")
const Payroll = preload("res://scripts/terrain_lab/site_payroll.gd")
const ProduceTax = preload("res://scripts/terrain_lab/site_produce_tax.gd")
const Finance = preload("res://scripts/terrain_lab/site_finance.gd")
const PayTable = preload("res://scripts/terrain_lab/site_pay_table.gd")
const RegionFinance = preload("res://scripts/region_lab/region_finance.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const Stocks = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const KING := 999
const ELSEWHERE := "atlas:900:900"

var checks := 0
var ctx := {}

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_FUND_REQUESTS OK ", checks, ": ", message)
		return true
	push_error("SITE_FUND_REQUESTS_FAIL: %s %s" % [message, str(detail)])
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

func _commit(candidate: Dictionary) -> Dictionary:
	var checked := RegionFactionQuery.validate(candidate, 1.0e12)
	if not checked.ok: return checked
	ctx.registry = candidate
	return SiteRuntime.ok()

func _seat(site: String) -> void:
	var seated := RegionFinance.candidate(ctx.registry)
	seated.finance.seats[RegionPeerage.key_of(_ref(KING))] = site
	_commit(seated)

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
	for index: int in range(1, 4): team.combat_units[index]["military_role"] = "officer"
	for key: String in [tax_stock, treasury_stock, team_stock]:
		if not _ok(Stocks.ensure_storage(data, key, 1).ok, "warehouse %s holds a stock" % key): return
		data.site.stockpiles[key].cargo.clear()
	var site_id := str(data.site.id)
	data.site["settlement"] = {"settlement_id": "s1", "owner_faction": 1, "level": 2, "center_id": tax_stock, "offices": SiteOffices.default_offices("settlement", head, false)}
	ctx = {"registry": _registry(head), "world": "w1", "commit": _commit}

	var plain: Dictionary = RegionFinance.candidate(ctx.registry)
	if not _ok(RegionFactionQuery.validate(plain, 1.0e12).ok and not plain.finance.has("requests"), "an old finance section without requests validates"): return
	var broken: Dictionary = RegionFinance.candidate(ctx.registry)
	broken.finance["requests"] = [{"id": 1, "from_site": "x"}]
	if not _ok(not RegionFactionQuery.validate(broken, 1.0e12).ok, "a malformed request is refused"): return

	var team_ref := SiteSocial.team_ref(site_id, team.team_id)
	if not _ok(Payroll.bind_pay_source(lab, head, team_ref, {"kind": "stock", "site_id": site_id, "feature_id": team_stock}).ok, "the captain binds the team's pay source"): return
	_seat(ELSEWHERE)
	var eve := Calendar.day_of(2, 1, 1) - 1
	data.site.minute = Calendar.day_start_minute(eve) + 600
	var filed := Requests.request(lab, eve, ctx)
	var open: Array = RegionFinance.requests(ctx.registry)
	if not _ok(filed.filed.size() == 1 and open.size() == 1 and int(open[0].coins) == 9 and str(open[0].from_site) == ELSEWHERE and str(open[0].to_site) == site_id
		and int(open[0].team) == team.team_id and int(open[0].payday) == eve + 1, "a short team files one request (9 coin) to the king's seat elsewhere", [filed, open]): return
	if not _ok(Requests.request(lab, eve, ctx).filed.is_empty() and RegionFinance.requests(ctx.registry).size() == 1, "the next pass does not file it twice"): return
	if not _ok(RegionFactionQuery.validate(ctx.registry, 1.0e12).ok, "the registry with a request validates"): return

	# This Site becomes the seat: the baron's settlement treasury pays.
	var treasury := {"kind": "stock", "site_id": site_id, "feature_id": treasury_stock}
	if not _ok(Tribute.bind_treasury(lab, head, treasury, ctx).ok, "the head binds this settlement's treasury"): return
	var asked := RegionFinance.candidate(ctx.registry)
	RegionFinance.add_request(asked, {"from_site": site_id, "to_site": ELSEWHERE, "team": 7, "coins": 9, "payday": eve + 1, "payer": "k"})
	RegionFinance.add_request(asked, {"from_site": site_id, "to_site": ELSEWHERE, "team": 8, "coins": 4, "payday": eve - 40, "payer": "k"})
	_commit(asked)
	data.site.stockpiles[treasury_stock].cargo["coin"] = 25
	var served := Requests.serve(lab, eve, ctx)
	var road: Array = RegionFinance.section(ctx.registry).transit
	if not _ok(served.sent.size() == 1 and int(served.sent[0].coins) == 5 and int(served.dropped) == 1 and road.size() == 1 and str(road[0].kind) == "fund"
		and road[0].items == {"coin": 5} and str(road[0].to) == "team:7" and int(road[0].arrive_day) > eve and int(data.site.stockpiles[treasury_stock].cargo.coin) == 20,
		"the seat pays 5 coin on the road (keeping 20), drops the stale request", [served, road]): return
	var left: Array = RegionFinance.requests(ctx.registry).filter(func(e: Dictionary) -> bool: return str(e.from_site) == site_id)
	if not _ok(left.is_empty(), "served requests leave", left): return

	# Fund goods arriving here enter the team's pay source.
	var incoming := RegionFinance.candidate(ctx.registry)
	RegionFinance.add_transit(incoming, {"kind": "fund", "from_site": ELSEWHERE, "to_site": site_id, "to": "team:%d" % team.team_id, "items": {"coin": 9},
		"tenths": 900, "arrive_day": eve + 1, "season": PayTable.season_index(eve), "payer": "k"})
	_commit(incoming)
	var delivered := Tribute.deliver(lab, eve + 1, ctx)
	if not _ok(int(delivered.count) == 1 and int(data.site.stockpiles[team_stock].cargo.get("coin", 0)) == 9, "fund goods arrive in the team's pay source", delivered): return
	if not _ok(Requests.request(lab, eve, ctx).filed.is_empty(), "a team that is not short files nothing"): return
	print("SITE_FUND_REQUESTS_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
