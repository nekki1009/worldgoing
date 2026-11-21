extends "res://scripts/tests/site_r3_prison_interface_test.gd"
## T6 S4b-C: derived taxed trade through the real production path. A lab fixture founds a real settlement
## (Settlement.found, centre completed), the head sets nation n1 and trade tax 10 (Settlement setters), the
## R4b-1 treasury is bound by the head, and the trade uses derived terms (trade_tax_terms), so the publish
## re-check (site_runtime.gd publish_taxed_candidate) reads the same rate and collector. Then save / reload
## of the taxed receipt (D-T4) and the validator refusals.
const StockPure = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const OUT := "res://.godot-temp/site_trade_tax_treasury/contract.json"
const TRADE_ID := "t6c-1"
const CENTER := Vector2i(20, 20)

func _check(condition: bool, message: String, details: Variant = null) -> bool:
	if _r3_failed: return false
	var engine_error: String = _r3_errors.first_error()
	if condition and engine_error.is_empty(): return true
	_r3_failed = true
	push_error("SITE_TRADE_TAX_TREASURY_FAIL: %s %s %s" % [message, str(details), engine_error])
	quit(1)
	return false

func _ref(data: TerrainData, holder_id: String) -> Dictionary:
	var endpoint: Dictionary = Runtime.trade_endpoint(data, holder_id)
	return {"holder": holder_id, "expected_version": int(endpoint.holder.version) if endpoint.ok else -1}

func _cargo(data: TerrainData, holder_id: String) -> Dictionary:
	return Runtime.trade_endpoint(data, holder_id).cargo

func _center_cells(data: TerrainData) -> Array[int]:
	var placement: Dictionary = Runtime.building_cells(data, "settlement_center", CENTER, Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	var cells: Array[int] = []
	if placement.ok: cells.assign(placement.cells)
	return cells

func _run() -> void:
	var data: TerrainData = _building_fixture()
	if not _check(not _r3_failed and data != null, "inherited terrain setup"): return
	var lab: TerrainLab = _building_lab(data)
	if not _check(not _r3_failed and lab != null, "inherited lab setup"): return
	var controller: SiteController = lab.site_controller
	var orders: SiteEquipmentOrders = controller.equipment_orders
	var requester: int = int(lab.controlled_person_id())
	var keeper: int = int(lab.npc.person_id)
	if not _check(requester > 0 and keeper > 0 and requester != keeper, "two distinct real people"): return

	# 1. Two complete warehouses, both inside the future jurisdiction (Chebyshev 12 from the centre footprint).
	var treasury_key: String = _formal_feature(data, "warehouse", Vector2i(30, 20))
	var buyer_key: String = _formal_feature(data, "warehouse", Vector2i(30, 26))
	if not _check(not _r3_failed and not treasury_key.is_empty() and not buyer_key.is_empty(), "two complete warehouses"): return
	if not _check(StockPure.ensure_storage(data, treasury_key, 1).ok and StockPure.ensure_storage(data, buyer_key, 1).ok, "warehouse stock"): return

	# 2. Formal nation n1 and the R4b-1 treasury binding by the acting head (same sequence as site_r4b2_authorization_test.gd).
	data.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", requester, false), "members": [requester, keeper], "standards": {}}}
	controller._capture_positions()
	var prepared: Dictionary = SiteEquipmentOrders.prepare_faction_nation(data.site, "n1", 1)
	if not _check(bool(prepared.ok), "formal nation binds to faction 1: " + str(prepared)): return
	data.site = prepared.state
	var nation: Dictionary = data.site.equipment_nations.n1
	var bound: Dictionary = orders.bind_nation_treasury(requester, "n1", treasury_key)
	if not _check(bool(bound.ok), "the head binds the national treasury: " + str(bound)): return
	var collector: String = "feature:" + treasury_key
	if not _check(str(nation.ransom_data.treasury.holder) == collector, "bound treasury is the collector holder"): return

	# 3. Found the settlement with the controlled founder (Settlement.found), then complete the centre.
	var founded: Dictionary = Settlement.found(lab, requester, _center_cells(data), {"layout_version": 1, "quarter": 0}, Callable(), "測試聚落")
	if not _check(bool(founded.ok), "settlement founded: " + str(founded)): return
	_complete_key(data, str(founded.feature))
	if not _check(not _r3_failed and int(data.site.settlement.level) == 1, "centre complete, settlement level 1"): return

	# 4. The head sets the nation and the trade tax (real setters, head authority).
	var set_nation: Dictionary = Settlement.set_nation(data, requester, "n1")
	if not _check(bool(set_nation.ok), "head sets nation n1: " + str(set_nation)): return
	var set_rate: Dictionary = Settlement.set_trade_tax_percent(data, requester, 10)
	if not _check(bool(set_rate.ok), "head sets trade tax 10: " + str(set_rate)): return
	var terms: Dictionary = Runtime.trade_tax_terms(data)
	if not _check(bool(terms.ok) and int(terms.percent) == 10 and str(terms.collector) == collector and bool(terms.derived), "derived terms: rate 10, collector is the bound treasury: " + str(terms)): return

	# 5. Derived taxed trade: depot sells 19 wood to the buyer warehouse; the bound treasury collects floor(19 * 10 / 100) = 1.
	var depot_before: int = int(_cargo(data, "depot").get("wood", 0))
	if not _check(depot_before >= 19, "depot has wood to trade"): return
	var refs: Array = [_ref(data, "depot"), _ref(data, "feature:" + buyer_key), _ref(data, collector)]
	var transfers: Array = [{"from": "depot", "to": "feature:" + buyer_key, "resources": {"wood": 19}, "item_ids": []}]
	var first: Dictionary = Runtime.exchange_taxed_candidate(data, refs, transfers, TRADE_ID)
	if not _check(bool(first.ok), "derived taxed trade commits: " + str(first)): return
	if not _check(_cargo(data, "feature:" + buyer_key) == {"wood": 18} and _cargo(data, collector) == {"wood": 1} and int(_cargo(data, "depot").get("wood", 0)) == depot_before - 19, "19 wood: 1 to the treasury, 18 received, 19 left the depot"): return
	var receipt_key: String = TRADE_ID + ":feature:" + buyer_key
	var receipt: Dictionary = data.site.trade_tax_receipts[receipt_key]
	if not _check(receipt.get("request") is String and receipt == {"trade_id": TRADE_ID, "side": "feature:" + buyer_key, "collector": collector, "percent": 10, "received": {"wood": 19}, "tax": {"wood": 1}, "items": [], "request": receipt.request}, "receipt holds received, tax and the collector"): return
	if not _check(SiteStore.validate_trade_tax_receipts(data.site).ok, "live receipts validate"): return

	# 6. Replay with the same trade_id: stored receipt, no second tax.
	var replay: Dictionary = Runtime.exchange_taxed_candidate(data, refs, transfers, TRADE_ID)
	if not _check(bool(replay.ok) and replay.get("replayed", false) == true and _cargo(data, collector) == {"wood": 1}, "replay does not tax twice"): return

	# 7. Save and reload (D-T4): the taxed receipt, the settlement and the treasury survive with exact integer types.
	var captured: Dictionary = controller._capture_for_save()
	if not _check(bool(captured.ok), "capture for save: " + str(captured)): return
	var saved: Dictionary = SiteStore.save(data, OUT)
	if not _check(bool(saved.ok), "save: " + str(saved)): return
	var loaded: Dictionary = SiteStore.load_site(OUT)
	if not _check(bool(loaded.ok), "reload: " + str(loaded)): return
	var kept: Dictionary = loaded.data.site.trade_tax_receipts[receipt_key]
	if not _check(kept == receipt and typeof(kept.percent) == TYPE_INT and typeof(kept.received.wood) == TYPE_INT and typeof(kept.tax.wood) == TYPE_INT, "receipt survives save and reload with int types"): return
	if not _check(loaded.data.site.trade_tax_receipts == data.site.trade_tax_receipts and SiteStore.validate_trade_tax_receipts(loaded.data.site).ok, "whole store equal after reload"): return
	if not _check(int(loaded.data.site.settlement.trade_tax_percent) == 10 and str(loaded.data.site.settlement.nation_id) == "n1", "settlement rate and nation survive reload"): return
	if not _check(_cargo(loaded.data, collector) == {"wood": 1}, "treasury stock survives reload"): return

	# 8. Publish re-check (D-T3): a rate change after prepare is STALE_SOURCE and changes nothing; then the head restores 10.
	var fresh_refs: Array = [_ref(data, "depot"), _ref(data, "feature:" + buyer_key), _ref(data, collector)]
	var fresh_transfers: Array = [{"from": "depot", "to": "feature:" + buyer_key, "resources": {"wood": 1}, "item_ids": []}]
	var prepared_rate: Dictionary = Runtime.prepare_taxed_candidate(data, fresh_refs, fresh_transfers, "t6c-2", Runtime.trade_tax_terms(data))
	if not _check(bool(prepared_rate.ok), "prepare at rate 10: " + str(prepared_rate)): return
	if not _check(bool(Settlement.set_trade_tax_percent(data, requester, 20).ok), "head changes the rate to 20"): return
	var before_publish: String = JSON.stringify([data.site.features.keys(), _cargo(data, collector), _cargo(data, "feature:" + buyer_key)])
	var stale: Dictionary = Runtime.publish_taxed_candidate(prepared_rate)
	if not _check(not bool(stale.ok) and str(stale.code) == "STALE_SOURCE" and JSON.stringify([data.site.features.keys(), _cargo(data, collector), _cargo(data, "feature:" + buyer_key)]) == before_publish, "rate changed before publish: STALE_SOURCE, unchanged"): return
	if not _check(bool(Settlement.set_trade_tax_percent(data, requester, 10).ok), "head restores the rate to 10"): return

	# 9. Old saves without the key stay valid; float JSON is admitted and normalized.
	var legacy: Dictionary = data.site.duplicate(true)
	legacy.erase("trade_tax_receipts")
	if not _check(SiteStore.validate_trade_tax_receipts(legacy).ok, "missing key is a valid old save"): return
	var floats: Dictionary = data.site.duplicate(true)
	var float_record: Dictionary = floats.trade_tax_receipts[receipt_key]
	float_record.percent = 10.0
	float_record.received.wood = 19.0
	float_record.tax.wood = 1.0
	if not _check(SiteStore.validate_trade_tax_receipts(floats).ok, "whole-number float JSON is admitted"): return
	SiteStore._normalize_trade_tax_receipts(floats)
	if not _check(typeof(float_record.percent) == TYPE_INT and typeof(float_record.tax.wood) == TYPE_INT, "normalization makes integers"): return

	# 10. Refusals: each corrupt receipt fails the validator and the whole-state validator used on load and save.
	if not _check(SiteStore._validate_state(data, data.site.duplicate(true)).ok, "baseline whole state with the taxed receipt validates"): return
	var cases: Dictionary = {
		"unknown_field": func(r: Dictionary) -> void: r["extra"] = 1,
		"missing_field": func(r: Dictionary) -> void: r.erase("request"),
		"percent_51": func(r: Dictionary) -> void: r.percent = 51,
		"percent_fraction": func(r: Dictionary) -> void: r.percent = 2.5,
		"tax_over_floor": func(r: Dictionary) -> void: r.tax.wood = 2,
		"tax_missing": func(r: Dictionary) -> void: r.tax = {},
		"tax_unknown_resource": func(r: Dictionary) -> void: r.tax.stone = 1,
		"received_string": func(r: Dictionary) -> void: r.received.wood = "19",
		"side_mismatch": func(r: Dictionary) -> void: r.side = "feature:other",
		"collector_is_side": func(r: Dictionary) -> void: r.collector = r.side,
		"items_not_strings": func(r: Dictionary) -> void: r["items"] = [3],
	}
	for case_name: String in cases:
		var corrupt: Dictionary = data.site.duplicate(true)
		cases[case_name].call(corrupt.trade_tax_receipts[receipt_key])
		if not _check(not SiteStore.validate_trade_tax_receipts(corrupt).ok, "refused by validator: " + case_name): return
		if not _check(not SiteStore._validate_state(data, corrupt).ok, "refused by whole-state validator: " + case_name): return
	var bad_store: Dictionary = data.site.duplicate(true)
	bad_store.trade_tax_receipts = []
	if not _check(not SiteStore.validate_trade_tax_receipts(bad_store).ok, "store that is not a dictionary is refused"): return
	var bad_key: Dictionary = data.site.duplicate(true)
	bad_key.trade_tax_receipts["no-colon"] = receipt
	if not _check(not SiteStore.validate_trade_tax_receipts(bad_key).ok, "key without side is refused"): return

	print("SITE_TRADE_TAX_TREASURY_OK: founded settlement at rate 10 with bound treasury; derived taxed trade collects 1 of 19 wood; receipt survives save and reload; rate change is STALE_SOURCE; refusals hold")
	quit(0)
