extends "res://scripts/tests/site_building_ui_test.gd"
## 貿易 T5 slice 2: a caravan sells at its destination. A level 2 settlement of faction 1 with a warehouse bound to its
## trade (wood limit) holding wood and no food, four registered residents; a visiting four-person team whose members
## carry the mission's grain. Checks:
## - the best-loaded member barters his grain for the warehouse's wood on the settlement's T2 terms: the goods change
##   hands one for one (nothing created or lost), the wood paid counts against the warehouse's quota, a notice is written;
## - with nothing bound to pay with, or no trade sources, nothing is sold (NO_DEAL / NO_MARKET).
## Output: SITE_CARAVAN_TRADE_T5_PASS on success; quit(1) on failure.

const Caravan = preload("res://scripts/terrain_lab/site_caravan.gd")
const Stocks = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const KING := 999

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_CARAVAN_TRADE_T5 OK ", checks, ": ", message)
		return true
	push_error("SITE_CARAVAN_TRADE_T5_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _run() -> void:
	var data := _building_fixture()
	var center := _formal_feature(data, "warehouse", Vector2i(14, 14))
	var market := _formal_feature(data, "warehouse", Vector2i(20, 14))
	var house := _formal_feature(data, "house", Vector2i(28, 20), Vector2i.ONE, {"variant": "long"})
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var team: TerrainArmy = lab.army
	team.roster_size = 4
	team.faction_id = 1
	if not _ok(team.deploy_at(data, null, null, [Vector2i(30, 26), Vector2i(31, 26), Vector2i(32, 26), Vector2i(33, 26)]) and team.enable_combat(false), "a four-person team deploys"): return
	team.set_process(false)
	team.settle_combat_command()
	var captain := team.combat_identity(0)
	var seller := team.combat_identity(1)
	if not _ok(Stocks.ensure_storage(data, market, 1).ok, "the market warehouse holds a stock"): return
	data.site.stockpiles[market].cargo.clear()
	data.site.stockpiles[market].cargo["wood"] = 40
	var layout: Dictionary = Runtime.house_layout(data, house)
	data.site["settlement"] = {"settlement_id": "s1", "owner_faction": 1, "level": 2, "center_id": center, "offices": SiteOffices.default_offices("settlement", captain, false),
		"trade_sources": {market: {"revision": 1, "limits": {"wood": {"per_trade": 40, "total": 400}, "grain": {"per_trade": 0, "total": 0}}, "used": {}}}}
	var housing := {}
	for index: int in range(4): housing[str(team.combat_identity(index))] = {"version": 1, "house_id": house, "cell": int(layout.slots[mini(index, layout.slots.size() - 1)])}
	data.site["housing"] = housing
	var body: Dictionary = controller.person_actions._person(seller, false)
	body.cargo["grain"] = 20
	body.holder.version = int(body.holder.version) + 1
	var mission := {"id": 1, "goods": {"grain": 20}}

	var grain_before := int(body.cargo.grain)
	var sold := Caravan.sell_here(lab, controller, mission, captain)
	if not _ok(sold.get("ok", false), "the caravan sells at the market", sold): return
	var gave := int(sold.gave.get("grain", 0))
	var got := int(sold.got.get("wood", 0))
	var stock: Dictionary = data.site.stockpiles[market].cargo
	if not _ok(gave > 0 and got > 0 and int(body.cargo.get("grain", 0)) == grain_before - gave and int(body.cargo.get("wood", 0)) == got
		and int(stock.get("grain", 0)) == gave and int(stock.wood) == 40 - got, "grain and wood change hands one for one", [sold, body.cargo, stock]): return
	if not _ok(int(data.site.settlement.trade_sources[market].used.get("wood", 0)) == got, "the wood paid counts against the quota"): return
	var noticed := false
	for notice: Variant in data.site.get("notices", []):
		if str(notice).contains("商隊在此成交"): noticed = true
	if not _ok(noticed, "a notice tells of the sale"): return
	body.cargo["grain"] = 20 # he has grain to offer again
	body.holder.version = int(body.holder.version) + 1
	data.site.settlement.trade_sources[market].limits.erase("wood")
	if not _ok(str(Caravan.sell_here(lab, controller, mission, captain).get("code", "")) == "NO_DEAL", "nothing bound to pay with: no deal"): return
	data.site.settlement.erase("trade_sources")
	if not _ok(str(Caravan.sell_here(lab, controller, mission, captain).get("code", "")) == "NO_MARKET", "no trade sources: no market"): return
	data.site.erase("housing")
	print("SITE_CARAVAN_TRADE_T5_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
