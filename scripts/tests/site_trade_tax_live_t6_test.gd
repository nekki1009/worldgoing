extends "res://scripts/tests/site_market_t3_test.gd"
## 貿易 T6 S6 (reports/trade-plan.md §5.6, TR-62, Q13 A): live trades pay the settlement's trade tax. Fixture: the player
## heads a level 2 settlement of nation n1 (the R4b-1 treasury, a warehouse, bound by him before founding, as in
## site_trade_tax_treasury_test), trade tax 10%; a market lists 10 grain for 10 salt; the NPC is head and stands at the
## market as 市正. Checks:
## - a lot taken by listing commits through the taxed candidate: the player receives 9 grain, the market 9 salt, the
##   treasury 1 grain and 1 salt (floor(10 x 10 / 100) of each side's received stack); every holder's version rises once;
##   two per-side receipts are written under the trade's id;
## - with the treasury unbound a positive rate refuses the take (NO_COLLECTOR) and nothing moves;
## - at rate 0 the original two-holder exchange stands: no receipt, the treasury untouched.
## Output: SITE_TRADE_TAX_LIVE_T6_PASS on success; push_error + quit(1) on failure.

var tax_checks := 0

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	tax_checks += 1
	if condition:
		print("SITE_TRADE_TAX_LIVE_T6 OK ", tax_checks, ": ", message)
		return true
	push_error("SITE_TRADE_TAX_LIVE_T6_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _face_at(entrance: Vector2i, at_market: Variant, other: Variant) -> bool:
	var stand := Vector2i(-1, -1)
	for offset: Vector2i in [Vector2i.ZERO, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
		if stand == Vector2i(-1, -1) and at_market.place(entrance + offset, true): stand = entrance + offset
	if stand == Vector2i(-1, -1): return false
	for offset: Vector2i in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i(1, 1), Vector2i(-1, 1)]:
		if stand + offset != entrance and other.place(stand + offset, true): return true
	return false

func _run() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var player := int(lab.controlled_person_id())
	var npc := int(lab.npc.person_id)
	# The national treasury (R4b-1), bound by the head before the settlement exists.
	var treasury_key: String = _formal_feature(data, "warehouse", Vector2i(34, 26))
	if not _check(Stockpiles.ensure_storage(data, treasury_key, 1).ok, "the treasury warehouse has its stock"): return
	data.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", player, false), "members": [player, npc], "standards": {}}}
	controller._capture_positions()
	var nation_made: Dictionary = SiteEquipmentOrders.prepare_faction_nation(data.site, "n1", 1)
	if not _check(nation_made.ok, "nation n1 binds to faction 1", nation_made): return
	data.site = nation_made.state
	var bound_treasury: Dictionary = controller.equipment_orders.bind_nation_treasury(player, "n1", treasury_key)
	if not _check(bound_treasury.ok, "the head binds the national treasury", bound_treasury): return
	var collector := "feature:" + treasury_key
	# The settlement (level 2), its nation and its trade tax.
	var placed: bool = lab.character.place(Vector2i(20, 18), true)
	if not _check(placed, "the founder stands beside the center site"): return
	var layout := Runtime.building_cells(data, "settlement_center", Vector2i(20, 20), Vector2i(5, 5), OPTIONS)
	var center_cells: Array[int] = []
	center_cells.assign(layout.get("cells", []))
	var founded := Settlement.found(lab, player, center_cells, {"layout_version": 1, "quarter": 0}, Callable(), "稅市村")
	if not _check(founded.ok, "the player founds the settlement", founded): return
	var center_key := str(founded.feature)
	_complete_key(data, center_key)
	var center: Dictionary = data.site.features[center_key]
	var terms := Runtime.civil_investment_terms(data, center, 2)
	center["cost"] = terms.cost
	center["work"] = terms.work
	center["progress"] = terms.work
	data.site.settlement["level"] = 2
	var set_nation: Dictionary = Settlement.set_nation(data, player, "n1")
	var set_rate: Dictionary = Settlement.set_trade_tax_percent(data, player, 10)
	var tax_terms: Dictionary = Runtime.trade_tax_terms(data)
	if not _check(set_nation.ok and set_rate.ok and tax_terms.ok and int(tax_terms.percent) == 10 and str(tax_terms.collector) == collector, "the settlement of n1 taxes trades 10% into the treasury", [set_nation, set_rate, tax_terms]): return
	# The market, its stock bound as a trade source, and one listing.
	var built := Runtime.request_build(data, "market", _cells(data, Vector2i(27, 20)), Callable(), OPTIONS)
	if not _check(built.ok, "the market is planned", built): return
	var key := str(built.feature)
	_complete_key(data, key)
	var stocked := Stockpiles.ensure_storage(data, key, 1)
	if not _check(stocked.ok, "the market stock opens", stocked): return
	var stock: Dictionary = data.site.stockpiles[key]
	stock.cargo["grain"] = 30
	var bound := Settlement.bind_trade_source(lab, player, key, {"grain": {"per_trade": 10, "total": 100}})
	var listed := Market.set_listings(lab, player, [{"give": {"grain": 10}, "want": {"salt": 10}, "daily": 3}])
	if not _check(bound.ok and listed.ok, "the market lists 10 grain for 10 salt", [bound, listed]): return
	SiteOffices.head_position(data.site.settlement.offices)["holder"] = npc
	var entrance: Vector2i = Stockpiles.stock_endpoint(data, key).cell
	if not _check(_face_at(entrance, lab.npc, lab.character), "the NPC 市正 stands at the market and the player before him"): return
	data.site.manual.cargo.clear()
	data.site.manual.cargo["salt"] = 20
	var treasury: Dictionary = data.site.stockpiles[treasury_key]

	# TR-62: a lot by listing pays the tax in kind in the same commit.
	var versions := [int(lab.character.item_state.version), int(stock.holder.version), int(treasury.holder.version)]
	var take: Dictionary = controller.market_take("1", 1)
	if not _check(take.ok, "a lot is taken at the taxed market", take): return
	lab.fire_action_cursor += 31.0
	var results: Array[Dictionary] = controller._trade().advance()
	if not _check(results.size() == 1 and results[0].ok, "the delivery commits through the taxed candidate", results): return
	if not _check(int(data.site.manual.cargo.get("grain", 0)) == 9 and int(data.site.manual.cargo.get("salt", 0)) == 10 and int(stock.cargo.get("salt", 0)) == 9 and int(stock.cargo.get("grain", 0)) == 20
		and int(treasury.cargo.get("grain", 0)) == 1 and int(treasury.cargo.get("salt", 0)) == 1, "the player gets 9 grain, the market 9 salt, the treasury 1 of each", [data.site.manual.cargo, stock.cargo, treasury.cargo]): return
	if not _check(int(lab.character.item_state.version) == versions[0] + 1 and int(stock.holder.version) == versions[1] + 1 and int(treasury.holder.version) == versions[2] + 1, "every holder's version rose once"): return
	var receipts: Dictionary = data.site.get("trade_tax_receipts", {})
	if not _check(receipts.size() == 2, "two per-side tax receipts are written", receipts.keys()): return

	# A positive rate with no collector refuses before anything moves.
	var saved_treasury: Dictionary = data.site.equipment_nations.n1.ransom_data.treasury.duplicate(true)
	data.site.equipment_nations.n1.ransom_data["treasury"] = {}
	var before := JSON.stringify([data.site.manual.cargo, stock.cargo, treasury.cargo], "", true)
	var refused: Dictionary = controller.market_take("1", 1)
	data.site.equipment_nations.n1.ransom_data["treasury"] = saved_treasury
	if not _check(not refused.ok and str(refused.code) == "NO_COLLECTOR" and JSON.stringify([data.site.manual.cargo, stock.cargo, treasury.cargo], "", true) == before, "with no treasury a taxed trade is refused and nothing moves", refused): return

	# Rate 0: the original exchange, no receipt.
	# The head (the NPC now) sets it; a bound trade source and the listings stay (they used to make the setter refuse).
	var zero: Dictionary = Settlement.set_trade_tax_percent(data, npc, 0)
	if not _check(zero.ok and data.site.settlement.has("trade_sources") and data.site.settlement.has("market_listings"), "the head sets the rate to 0 with a trade source bound and listings up", zero): return
	var treasury_before := JSON.stringify(treasury.cargo, "", true)
	var plain: Dictionary = controller.market_take("1", 1)
	if not _check(plain.ok, "a lot is taken at rate 0", plain): return
	lab.fire_action_cursor += 31.0
	results = controller._trade().advance()
	if not _check(results.size() == 1 and results[0].ok and int(data.site.manual.cargo.get("grain", 0)) == 19 and JSON.stringify(treasury.cargo, "", true) == treasury_before
		and data.site.get("trade_tax_receipts", {}).size() == 2, "at rate 0 the full 10 grain arrive, no tax, no new receipt", [data.site.manual.cargo, treasury.cargo]): return

	print("SITE_TRADE_TAX_LIVE_T6_PASS checks=", tax_checks, "; taxed take in kind to the treasury with receipts, no collector refused, rate 0 untaxed")
	_finish_workflow_body()
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
