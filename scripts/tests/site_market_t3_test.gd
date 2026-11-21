extends "res://scripts/tests/site_bridge_contract_test.gd"
## 貿易 T3 slice 1 (reports/trade-plan.md §5.2, Q4 C; TR-35, TR-36, TR-37): the market building. Fixture: the player
## founds a settlement of faction 1 at (20, 20) on the building fixture (fixed geography, so the Site saves and loads).
## Checks:
## - TR-35: with no settlement, and at level 1, the market is refused REQUIREMENTS with no change; at level 2 a 4x4
##   market in the jurisdiction is planned at wood 20, stone 10, rope 4; a footprint outside the jurisdiction and a
##   second market (LIMIT) are refused with no change;
## - TR-36: with the market missing from the manifest's assets (an injected table) the guard refuses MISSING_ART, art for
##   one facing does not admit another; the real manifest has all four facings;
## - TR-37: built through the original construction, the market is an ordinary civil building (grade 1, body HP 100) with
##   a fire roof; its stock holds 20x(grade+1) and is never a processing supply; the head binds it as a trade source and
##   it is the settlement side of a trade; body HP 0 closes it, restored HP reopens it; an upgrade closes it while it is
##   built, then grade 2 holds 60, and grade 3 stays behind the settlement's grade cap; the Site saves and loads with the
##   market's grade and stock unchanged; a burnt-through roof lets the fire take one unit of its stock in one action
##   second; a Site with two markets is refused CORRUPT_SAVE by the store.
## Output: SITE_MARKET_T3_PASS on success; push_error + quit(1) on failure.

const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Stockpiles = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const Market = preload("res://scripts/terrain_lab/site_market.gd")
const SAVE_DIR := "res://.godot-temp/site_market_t3/"
const OPTIONS := {"layout_version": 1, "quarter": 0, "owner_faction": 1}

var checks := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 120000
	_run.call_deferred()

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_MARKET_T3 OK ", checks, ": ", message)
		return true
	push_error("SITE_MARKET_T3_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _cells(data: TerrainData, anchor: Vector2i) -> Array[int]:
	var placement := Runtime.building_cells(data, "market", anchor, Vector2i(4, 4), OPTIONS)
	var cells: Array[int] = []
	if bool(placement.get("ok", false)): cells.assign(placement.cells)
	return cells

func _same_counts(found: Variant, expected: Dictionary) -> bool:
	if not found is Dictionary or found.size() != expected.size(): return false
	for key: String in expected:
		if int(found.get(key, -1)) != int(expected[key]): return false
	return true

func _stock_total(stock: Dictionary) -> int:
	var total := 0
	for resource: Variant in stock.cargo: total += int(stock.cargo[resource])
	return total

func _save_and_load(lab: TerrainLab, base: TerrainData, suffix: String) -> Dictionary:
	var captured: Dictionary = lab.site_controller._capture_for_save()
	if not captured.get("ok", false): return captured
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var saved: Dictionary = Store.save(lab.terrain, SAVE_DIR + suffix + ".json")
	if not saved.get("ok", false): return saved
	return Store.load_site(SAVE_DIR + suffix + ".json", _bridge_loader(base), 1, true)

func _run() -> void:
	var data := _building_fixture()
	data.site.id = RegionGrid.site_id(RegionGrid.ATLAS_ID, Vector2i.ZERO)
	data.parameters["composition"] = "fixed_geography"
	data.parameters["fixed_base"] = {"base_kind": "fixed_geography", "atlas_id": RegionGrid.ATLAS_ID,
		"site_id": str(data.site.id), "site": [0, 0], "grid_contract_version": 1,
		"base_revision": "market_t3_fixture_v1", "manifest_sha256": "e".repeat(64),
		"terrain_fingerprint": data.fingerprint(), "ramp_rule_revision": RegionTerrainAdapter.RAMP_RULE_REVISION}
	var base := _bridge_base(data)
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var player := int(lab.character.person_id)
	var inside := _cells(data, Vector2i(27, 20))
	if not _ok(Runtime.FEATURES.has("market") and inside.size() == 16, "the market is a fixed 4x4 building kind", inside.size()): return

	# TR-35: no settlement, then a level 1 settlement.
	var before := var_to_bytes(data.site)
	var refused := Runtime.request_build(data, "market", inside, Callable(), OPTIONS)
	if not _ok(not refused.ok and str(refused.code) == "REQUIREMENTS" and var_to_bytes(data.site) == before, "no settlement: the market is refused with no change", refused): return
	var placed: bool = lab.character.place(Vector2i(20, 18), true)
	if not _ok(placed, "the founder stands beside the center site"): return
	var layout := Runtime.building_cells(data, "settlement_center", Vector2i(20, 20), Vector2i(5, 5), OPTIONS)
	var center_cells: Array[int] = []
	center_cells.assign(layout.get("cells", []))
	var founded := Settlement.found(lab, player, center_cells, {"layout_version": 1, "quarter": 0}, Callable(), "市集村")
	if not _ok(founded.ok, "the player founds the settlement", founded): return
	var center_key := str(founded.feature)
	_complete_key(data, center_key)
	if int(data.site.settlement.get("level", 0)) < 1: data.site.settlement["level"] = 1 # fixture: an effective village
	before = var_to_bytes(data.site)
	refused = Runtime.request_build(data, "market", inside, Callable(), OPTIONS)
	if not _ok(not refused.ok and str(refused.code) == "REQUIREMENTS" and var_to_bytes(data.site) == before, "a level 1 settlement cannot build a market", refused): return
	# Fixture: the center is raised to level 2 (its paid investment agrees with the level, as the store requires).
	var center: Dictionary = data.site.features[center_key]
	var terms := Runtime.civil_investment_terms(data, center, 2)
	center["cost"] = terms.cost
	center["work"] = terms.work
	center["progress"] = terms.work
	data.site.settlement["level"] = 2
	if not _ok(Runtime.settlement_center_invested_level(data, center) == 2, "fixture: a level 2 center"): return

	# TR-36: missing art refuses; the real manifest has every facing.
	var no_art := Market.build_guard(data, inside, 0, {})
	var one_facing := Market.build_guard(data, inside, 1, {"market": {}})
	if not _ok(str(no_art.get("code", "")) == "MISSING_ART" and str(one_facing.get("code", "")) == "MISSING_ART", "missing market art refuses MISSING_ART; art for one facing does not admit another", [no_art, one_facing]): return
	var facings := true
	for quarter: int in range(4): facings = facings and Market.art_available(quarter)
	if not _ok(facings and Market.build_guard(data, inside, 0).ok, "the real manifest has all four market facings and the guard passes"): return

	# TR-35: outside the jurisdiction, then the real build, then a second market.
	var outside := _cells(data, Vector2i(46, 46))
	before = var_to_bytes(data.site)
	refused = Runtime.request_build(data, "market", outside, Callable(), OPTIONS)
	if not _ok(outside.size() == 16 and not refused.ok and str(refused.code) == "REQUIREMENTS" and var_to_bytes(data.site) == before, "a market outside the jurisdiction is refused with no change", refused): return
	var built := Runtime.request_build(data, "market", inside, Callable(), OPTIONS)
	if not _ok(built.ok, "a level 2 settlement plans a market in its jurisdiction", built): return
	var key := str(built.feature)
	var market: Dictionary = data.site.features[key]
	if not _ok(_same_counts(market.get("cost"), {"wood": 20, "stone": 10, "rope": 4}) and is_equal_approx(float(market.get("work", 0.0)), 30.0), "the market costs wood 20, stone 10, rope 4 and 30 minutes", [market.get("cost"), market.get("work")]): return
	if not _ok(Market.open_state(data, key).reason == "BUILDING", "a planned market does not trade"): return
	var second := _cells(data, Vector2i(33, 26))
	before = var_to_bytes(data.site)
	refused = Runtime.request_build(data, "market", second, Callable(), OPTIONS)
	if not _ok(second.size() == 16 and not refused.ok and str(refused.code) == "LIMIT" and var_to_bytes(data.site) == before, "a second market is refused LIMIT with no change", refused): return

	# TR-37: an ordinary civil building with a fire roof.
	_complete_key(data, key)
	market = data.site.features[key]
	var parts: Dictionary = market.get("parts", {})
	if not _ok(str(market.stage) == "complete" and int(market.get("building_grade", 0)) == 1 and int(market.get("civil_version", 0)) == Runtime.CIVIL_VERSION \
		and is_equal_approx(float(parts.get("body", {}).get("hp", 0.0)), 100.0) and parts.has("roof") and int(market.get("fire_layout_version", 0)) == Runtime.FIRE_LAYOUT_VERSION,
		"the completed market is a grade 1 civil building with body HP 100 and a fire roof", market): return
	if not _ok(Market.open_state(data, key).open, "the completed market trades"): return
	var stocked := Stockpiles.ensure_storage(data, key, 1)
	if not _ok(stocked.ok and Stockpiles.capacity(market) == 40, "its stock opens and holds 20x(1+1)", stocked): return
	var supply := Stockpiles.set_local_supply(data, key, true, 1)
	if not _ok(not supply.ok and str(supply.code) == "NO_TARGET" and not market.has("supply_mode"), "the market stock never feeds processing", supply): return
	var stock: Dictionary = data.site.stockpiles[key]
	stock.cargo["grain"] = 30
	stock.cargo["wood"] = 5
	var bound := Settlement.bind_trade_source(lab, player, key, {"grain": {"per_trade": 2, "total": 10}})
	if not _ok(bound.ok and Settlement.valid_trade_sources(data.site.settlement.trade_sources, data.site), "the head binds the market stock as a trade source", bound): return
	var party: Dictionary = controller._trade().settlement_party(key)
	if not _ok(party.get("ok", false) == true, "the bound market is the settlement side of a trade", party): return
	parts.body["hp"] = 0.0
	var closed := Market.open_state(data, key)
	parts.body["hp"] = Runtime.civil_max_hp(market)
	if not _ok(closed.reason == "DAMAGED" and Market.open_state(data, key).open, "body HP 0 closes the market; restored HP reopens it", closed): return

	# Upgrade under the settlement's grade cap (the fixture's cap is 2: a level 2 settlement in effect).
	data.set_meta(&"settlement_grade_cap", func(_feature: Dictionary) -> int: return 2)
	var preview := Runtime.request_upgrade(data, key, 1, Callable(), true)
	if not _ok(preview.ok and int(preview.get("target_grade", 0)) == 2, "the market may rise to grade 2", preview): return
	var upgrading := Runtime.request_upgrade(data, key, 1)
	if not _ok(upgrading.ok and Market.open_state(data, key).reason == "BUILDING", "an upgrade under way closes the market", upgrading): return
	_complete_key(data, key)
	market = data.site.features[key]
	if not _ok(int(market.get("building_grade", 0)) == 2 and Stockpiles.capacity(market) == 60 and Market.open_state(data, key).open, "grade 2: the stock holds 60 and the market reopens", market.get("building_grade")): return
	var third := Runtime.request_upgrade(data, key, 1, Callable(), true)
	if not _ok(not third.ok and str(third.code) == "SETTLEMENT_LEVEL", "grade 3 waits for the settlement's grade cap", third): return

	# Save and load: the market keeps its grade and stock.
	var stock_bytes := JSON.stringify(stock.cargo, "", true)
	var loaded := _save_and_load(lab, base, "market")
	if not _ok(loaded.get("ok", false) == true, "the Site with its market saves and loads", loaded): return
	var loaded_data: TerrainData = loaded.data
	var loaded_market: Dictionary = loaded_data.site.features.get(key, {})
	var loaded_stock: Dictionary = loaded_data.site.get("stockpiles", {}).get(key, {})
	if not _ok(str(loaded_market.get("kind", "")) == "market" and int(loaded_market.get("building_grade", 0)) == 2 and not loaded_stock.is_empty() and JSON.stringify(loaded_stock.cargo, "", true) == stock_bytes \
		and loaded_data.site.settlement.get("trade_sources", {}).has(key), "after the round trip the market is grade 2 with the same stock and binding", [loaded_market.get("building_grade"), loaded_stock.get("cargo")]): return

	# The store refuses a Site with two markets (a second one planned while the first was not a market).
	market["kind"] = "warehouse"
	var doubled: Dictionary = Runtime.request_build(data, "market", second, Callable(), OPTIONS)
	market["kind"] = "market"
	if not _ok(doubled.ok, "fixture: a second market planned", doubled): return
	var two: Dictionary = data.site.duplicate(true)
	var store_refused: Dictionary = Store._validate_state(data, two)
	if not _ok(str(Market.validate(two).get("code", "")) == "CORRUPT_SAVE" and not store_refused.ok and str(store_refused.get("message", "")).contains("市集"), "a Site with two markets is refused CORRUPT_SAVE", store_refused): return

	# Fire: a burnt-through roof exposes the stock; one action second at full intensity takes one unit.
	var roof := float(market.parts.roof.hp)
	lab.siege_apply_damage_batch({key + "|roof": {"feature": key, "part": "roof", "damage": roof}}, {})
	if not _ok(float(market.parts.roof.hp) <= 0.0, "the roof burns through", market.parts.roof): return
	var descriptor := Runtime._fire_feature_descriptor(data, key, "roof")
	if not _ok(not descriptor.is_empty(), "the market roof is a fire component"): return
	var fire_state := Runtime._fire_state(data, lab.fire_action_cursor)
	var unit := Runtime._fire_unit(data, fire_state, descriptor)
	unit.merge({"profile": "TEST_HEAT_100", "heat": 100.0, "state": "BURNING", "intensity": 1.0, "moisture": 0.0}, true)
	fire_state.active[str(descriptor.key)] = true
	Runtime.fire_hazard_invalidate(data)
	var total := _stock_total(stock)
	var burned: Dictionary = Runtime.fire_advance(data, 1.0, 0, lab.siege_queue_damage)
	if not _ok(burned.ok and _stock_total(stock) == total - 1 and data.site.fire.get("inventory_receipts", {}).size() == 1, "the fire takes one unit of the market stock", [burned, stock.cargo]): return

	print("SITE_MARKET_T3_PASS checks=", checks, "; build guard (level, jurisdiction, one, art), civil grade/body/roof, stock 20x(grade+1) never a supply, trade source, closed when damaged or building, grade cap, save/load, fire on stock, store limit")
	_finish_workflow_body()
	data.remove_meta(&"settlement_grade_cap")
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
