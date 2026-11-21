extends "res://scripts/tests/site_market_t3_test.gd"
## 貿易 T3 slice 2 (reports/trade-plan.md §5.2 掛牌; TR-30, TR-31, TR-35 listings end with the fall). Fixture: the player
## founds a level 2 settlement (as site_market_t3_test), builds a market, stocks it with 30 grain and binds it as a trade
## source (grain: 4 per trade, 100 in total); the listing pays 2 grain for 1 salt, 3 lots a day.
## Checks:
## - setting listings: refused while the market is not bound (NOT_BOUND), past the market's daily lots (10 at grade 1),
##   with one resource on both sides; the 市正 (here the head acting) sets them; once the NPC is head, the player cannot;
## - TR-30: the player, face to face with the NPC 市正 standing at the market, takes 2 lots with no bargaining: the
##   delivery runs and commits once (2 salt to the market, 4 grain to the player, both versions raised once), 2 of the
##   day's 3 lots used; 3 lots in one take pass the binding's per-trade limit (QUOTA); 2 more pass the day's lots
##   (DAILY_LIMIT) with nothing changed; the next game day the lots are free again;
## - TR-31: the 市正 away from the market refuses (TOO_FAR); a market under repair refuses (MARKET_CLOSED); a delivery
##   under way when the market's body falls to 0 HP is cancelled with nothing moved and its lot freed;
## - the listings save-validate, survive a JSON round trip (normalized), and a listing over its day's lots is refused
##   CORRUPT_SAVE; the settlement's fall ends them.
## Output: SITE_MARKET_LISTING_T3_PASS on success; push_error + quit(1) on failure.

var listing_checks := 0

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	listing_checks += 1
	if condition:
		print("SITE_MARKET_LISTING_T3 OK ", listing_checks, ": ", message)
		return true
	push_error("SITE_MARKET_LISTING_T3_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

## Puts `who` at the market entrance and `other` face to face with him; whether both stand.
func _face_at(lab: TerrainLab, entrance: Vector2i, at_market: Variant, other: Variant) -> bool:
	var stand := Vector2i(-1, -1)
	for offset: Vector2i in [Vector2i.ZERO, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
		if stand == Vector2i(-1, -1) and at_market.place(entrance + offset, true): stand = entrance + offset
	if stand == Vector2i(-1, -1): return false
	for offset: Vector2i in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i(1, 1), Vector2i(-1, 1)]:
		if stand + offset != entrance and other.place(stand + offset, true): return true
	return false

func _run() -> void:
	var data := _building_fixture()
	data.site.id = RegionGrid.site_id(RegionGrid.ATLAS_ID, Vector2i.ZERO)
	data.parameters["composition"] = "fixed_geography"
	data.parameters["fixed_base"] = {"base_kind": "fixed_geography", "atlas_id": RegionGrid.ATLAS_ID,
		"site_id": str(data.site.id), "site": [0, 0], "grid_contract_version": 1,
		"base_revision": "market_listing_t3_fixture_v1", "manifest_sha256": "e".repeat(64),
		"terrain_fingerprint": data.fingerprint(), "ramp_rule_revision": RegionTerrainAdapter.RAMP_RULE_REVISION}
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var player := int(lab.character.person_id)
	var npc := int(lab.npc.person_id)
	var placed: bool = lab.character.place(Vector2i(20, 18), true)
	if not _check(placed, "the founder stands beside the center site"): return
	var layout := Runtime.building_cells(data, "settlement_center", Vector2i(20, 20), Vector2i(5, 5), OPTIONS)
	var center_cells: Array[int] = []
	center_cells.assign(layout.get("cells", []))
	var founded := Settlement.found(lab, player, center_cells, {"layout_version": 1, "quarter": 0}, Callable(), "掛牌村")
	if not _check(founded.ok, "the player founds the settlement", founded): return
	var center_key := str(founded.feature)
	_complete_key(data, center_key)
	var center: Dictionary = data.site.features[center_key]
	var terms := Runtime.civil_investment_terms(data, center, 2)
	center["cost"] = terms.cost
	center["work"] = terms.work
	center["progress"] = terms.work
	data.site.settlement["level"] = 2
	var built := Runtime.request_build(data, "market", _cells(data, Vector2i(27, 20)), Callable(), OPTIONS)
	if not _check(built.ok, "the market is planned", built): return
	var key := str(built.feature)
	_complete_key(data, key)
	var stocked := Stockpiles.ensure_storage(data, key, 1)
	if not _check(stocked.ok, "the market stock opens", stocked): return
	var stock: Dictionary = data.site.stockpiles[key]
	stock.cargo["grain"] = 30
	var listing := [{"give": {"grain": 2}, "want": {"salt": 1}, "daily": 3}]

	# Setting listings.
	var unbound := Market.set_listings(lab, player, listing)
	if not _check(not unbound.ok and str(unbound.code) == "NOT_BOUND", "listings need the market bound as a trade source", unbound): return
	var bound := Settlement.bind_trade_source(lab, player, key, {"grain": {"per_trade": 4, "total": 100}})
	if not _check(bound.ok, "the head binds the market stock", bound): return
	var too_many := Market.set_listings(lab, player, [{"give": {"grain": 2}, "want": {"salt": 1}, "daily": 6}, {"give": {"grain": 1}, "want": {"wood": 1}, "daily": 5}])
	var both_sides := Market.set_listings(lab, player, [{"give": {"grain": 2}, "want": {"grain": 1, "salt": 1}, "daily": 1}])
	if not _check(str(too_many.get("code", "")) == "INVALID" and str(both_sides.get("code", "")) == "INVALID" and not data.site.settlement.has("market_listings"), "past the market's 10 daily lots, or one resource on both sides, is refused", [too_many, both_sides]): return
	var parsed := Market.parse_rows("grain:2>salt:1|3")
	var listed := Market.set_listings(lab, player, parsed.get("rows", []))
	if not _check(parsed.ok and listed.ok and Market.rows_text(Market.listings(data)) == "grain:2>salt:1|3", "the head acting as 市正 sets the listing from its text", listed): return
	SiteOffices.head_position(data.site.settlement.offices)["holder"] = npc
	var taken_over := Market.set_listings(lab, player, listing)
	if not _check(not taken_over.ok and str(taken_over.code) == "NO_AUTHORITY", "once the NPC is head the player cannot set listings", taken_over): return

	# TR-30: a take by listing.
	var entrance: Vector2i = Stockpiles.stock_endpoint(data, key).cell
	if not _check(_face_at(lab, entrance, lab.npc, lab.character), "the NPC 市正 stands at the market and the player before him"): return
	data.site.manual.cargo.clear()
	data.site.manual.cargo["salt"] = 10
	var before := var_to_bytes(data.site)
	var quota := controller.market_take("1", 3)
	if not _check(not quota.ok and str(quota.code) == "QUOTA" and var_to_bytes(data.site) == before, "3 lots (6 grain) pass the binding's 4 a trade: refused, nothing changed", quota): return
	var versions := [int(lab.character.item_state.version), int(stock.holder.version)]
	var take := controller.market_take("1", 2)
	if not _check(take.ok and controller.person_actions.is_busy(npc) and controller.person_actions.is_busy(player), "2 lots are taken with no bargaining; the delivery starts", take): return
	lab.fire_action_cursor += 3.0
	var results: Array[Dictionary] = controller._trade().advance()
	if not _check(results.size() == 1 and results[0].ok, "the delivery commits", results): return
	if not _check(int(data.site.manual.cargo.get("salt", 0)) == 8 and int(data.site.manual.cargo.get("grain", 0)) == 4 and int(stock.cargo.get("grain", 0)) == 26 and int(stock.cargo.get("salt", 0)) == 2,
		"2 salt went to the market and 4 grain to the player", [data.site.manual.cargo, stock.cargo]): return
	var record := Market.listings(data)
	if not _check(int(lab.character.item_state.version) == versions[0] + 1 and int(stock.holder.version) == versions[1] + 1 and int(record.rows[0].used) == 2 and record.jobs.is_empty(),
		"each holder's version rose once and 2 of the day's 3 lots are used", record): return
	before = var_to_bytes(data.site)
	var over := controller.market_take("1", 2)
	if not _check(not over.ok and str(over.code) == "DAILY_LIMIT" and var_to_bytes(data.site) == before, "2 more lots pass the day's 3: refused, nothing changed", over): return

	# TR-31: pauses.
	var away_cell := entrance + Vector2i(6, 6)
	var moved: bool = lab.npc.place(away_cell, true)
	var away := controller.market_take("1", 1)
	if not _check(moved and not away.ok and str(away.code) == "TOO_FAR", "the 市正 away from the market: refused", away): return
	if not _check(_face_at(lab, entrance, lab.npc, lab.character), "the 市正 comes back"): return
	var market: Dictionary = data.site.features[key]
	market["repair"] = {}
	var closed := controller.market_take("1", 1)
	market.erase("repair")
	if not _check(not closed.ok and str(closed.code) == "MARKET_CLOSED", "a market under repair does not trade", closed): return
	var cargo_before: String = JSON.stringify([data.site.manual.cargo, stock.cargo], "", true)
	var last := controller.market_take("1", 1)
	if not _check(last.ok and Market.listings(data).jobs.size() == 1, "the last lot of the day is taken", last): return
	market.parts.body["hp"] = 0.0
	results = controller._trade().advance()
	market.parts.body["hp"] = Runtime.civil_max_hp(market)
	if not _check(results.size() == 1 and not results[0].ok and str(results[0].code) == "CANCELLED" and JSON.stringify([data.site.manual.cargo, stock.cargo], "", true) == cargo_before \
		and Market.listings(data).jobs.is_empty() and int(Market.listings(data).rows[0].used) == 2, "the market falling to 0 HP cancels the delivery: nothing moved, its lot free again", results): return
	var again := controller.market_take("1", 1)
	if not _check(again.ok, "the freed lot can be taken once the market stands again", again): return
	lab.fire_action_cursor += 3.0
	results = controller._trade().advance()
	if not _check(results.size() == 1 and results[0].ok and int(Market.listings(data).rows[0].used) == 3, "it commits; the day's 3 lots are used", results): return
	data.site.minute = int(data.site.minute) + 1440
	var next_day := controller.market_take("1", 1)
	if not _check(next_day.ok, "the next game day the lots are free again", next_day): return
	lab.fire_action_cursor += 3.0
	results = controller._trade().advance()
	if not _check(results.size() == 1 and results[0].ok and int(Market.listings(data).rows[0].used) == 1, "the new day counts 1 lot", results): return

	# Saving: the listings validate, normalize from JSON, and a corrupt count is refused.
	var captured: Dictionary = controller._capture_for_save()
	if not _check(captured.get("ok", false) == true, "the Site captures", captured): return
	var state: Dictionary = data.site.duplicate(true)
	var saved: Dictionary = Store._validate_state(data, state)
	if not _check(saved.ok, "the Site with its listings validates", saved): return
	var wire: Dictionary = JSON.parse_string(JSON.stringify(state.settlement.market_listings))
	Market.normalize_listings(wire)
	if not _check(Market.valid_listings(wire, state) and wire.rows[0].used is int and wire.rows[0].give.grain is int, "the listings survive a JSON round trip"): return
	state.settlement.market_listings.rows[0]["used"] = 4
	var corrupt: Dictionary = Store._validate_state(data, state)
	if not _check(not corrupt.ok and str(corrupt.get("message", "")).contains("市集掛牌"), "a listing over its day's lots is refused CORRUPT_SAVE", corrupt): return

	# TR-35: the fall ends the listings.
	var fell: Dictionary = Settlement.fall_to(lab, 2, -1, false)
	if not _check(fell.get("ok", false) == true and not data.site.settlement.has("market_listings"), "the settlement's fall ends the listings", fell): return

	print("SITE_MARKET_LISTING_T3_PASS checks=", listing_checks, "; set guards, take by listing (no bargaining), quota, daily lots and the next day, 市正 away, closed market, cancel on damage, save validation, fall")
	_finish_workflow_body()
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
