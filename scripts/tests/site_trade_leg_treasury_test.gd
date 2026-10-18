extends "res://scripts/tests/site_r3_prison_interface_test.gd"
## T6 S5C: positive nation-leg commit through the real lab path. A complete warehouse is bound as the nation's
## treasury by the head (R4b-1), the head authorizes ransom spending (R4b-2), and the treasury pays coin to the depot
## for wood (TR-64 gate, D-T8 shared daily ledger). Then the daily ceiling and the reserve refuse with nothing changed,
## a new day resets the ledger, and the leg receipts and ledger survive save and reload.
const StockPure = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const Leg = preload("res://scripts/terrain_lab/site_trade_nation_leg.gd")
const OUT := "res://.godot-temp/site_trade_leg_treasury/contract.json"

func _check(condition: bool, message: String, details: Variant = null) -> bool:
	if _r3_failed: return false
	var engine_error: String = _r3_errors.first_error()
	if condition and engine_error.is_empty(): return true
	_r3_failed = true
	push_error("SITE_TRADE_LEG_TREASURY_FAIL: %s %s %s" % [message, str(details), engine_error])
	quit(1)
	return false

func _ref(data: TerrainData, holder_id: String) -> Dictionary:
	var endpoint: Dictionary = Runtime.trade_endpoint(data, holder_id)
	return {"holder": holder_id, "expected_version": int(endpoint.holder.version) if endpoint.ok else -1}

func _cargo(data: TerrainData, holder_id: String) -> Dictionary:
	return Runtime.trade_endpoint(data, holder_id).cargo

func _snapshot(data: TerrainData, collector: String) -> String:
	return JSON.stringify([data.site, _cargo(data, "depot"), _cargo(data, collector)])

func _code(result: Dictionary) -> String:
	return str(result.get("code", ""))

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
	# The ledger is validated against the game clock (RansomData.valid_nations: spent_day <= minute / 1440), so spend on today.
	var day: int = floori(float(data.site.minute) / 1440.0)

	# 1. A complete warehouse is the national treasury.
	var treasury_key: String = _formal_feature(data, "warehouse", Vector2i(30, 20))
	if not _check(not _r3_failed and not treasury_key.is_empty(), "complete warehouse"): return
	if not _check(StockPure.ensure_storage(data, treasury_key, 1).ok, "warehouse stock"): return

	# 2. Formal nation n1, the R4b-1 binding and the R4b-2 authorization, all by the acting head.
	data.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", requester, false), "members": [requester, keeper], "standards": {}}}
	controller._capture_positions()
	var prepared: Dictionary = SiteEquipmentOrders.prepare_faction_nation(data.site, "n1", 1)
	if not _check(bool(prepared.ok), "formal nation binds to faction 1: " + str(prepared)): return
	data.site = prepared.state
	var bound: Dictionary = orders.bind_nation_treasury(requester, "n1", treasury_key)
	if not _check(bool(bound.ok), "the head binds the national treasury: " + str(bound)): return
	var collector: String = "feature:" + treasury_key
	var authorized: Dictionary = orders.authorize_nation_ransom(requester, "n1", true)
	if not _check(bool(authorized.ok) and data.site.equipment_nations.n1.ransom_data.policy.authorized == true, "the head authorizes ransom spending: " + str(authorized)): return

	# 3. The treasury holds 60 coin (its real stock cargo); the depot holds wood. Deltas are checked below.
	var treasury_cargo: Dictionary = _cargo(data, collector)
	treasury_cargo["coin"] = 60
	var depot_wood_before: int = int(_cargo(data, "depot").get("wood", 0))
	var depot_coin_before: int = int(_cargo(data, "depot").get("coin", 0))
	if not _check(depot_wood_before >= 5, "depot has wood to sell"): return

	# 4. The depot gives 5 wood to the nation's treasury, and the treasury pays 30 coin to the depot (nation spend).
	var refs: Array = [_ref(data, "depot"), _ref(data, collector)]
	var goods: Array = [{"from": "depot", "to": collector, "resources": {"wood": 5}, "item_ids": []}]
	var pays: Array = [{"from": collector, "to": "depot", "amount": 30}]
	var paid: Dictionary = Leg.commit(data, refs, goods, pays, "t6s5-1", "n1", collector, day)
	if not _check(bool(paid.ok), "treasury pays 30 coin for 5 wood: " + str(paid)): return
	if not _check(int(_cargo(data, collector).get("coin", 0)) == 30 and int(_cargo(data, collector).get("wood", 0)) == 5, "treasury: coin 60 to 30, wood 5 received", [int(_cargo(data, collector).get("coin", 0)), int(_cargo(data, collector).get("wood", 0))]): return
	if not _check(int(_cargo(data, "depot").get("coin", 0)) == depot_coin_before + 30 and int(_cargo(data, "depot").get("wood", 0)) == depot_wood_before - 5, "depot: coin +30, wood -5"): return
	var ledger: Dictionary = data.site.equipment_nations.n1.ransom_data
	if not _check(int(ledger.spent_day) == day and int(ledger.spent) == 30, "shared ledger records 30 on the current game day", [int(ledger.spent_day), int(ledger.spent), day]): return
	var receipt_key: String = "t6s5-1:" + collector
	var receipt: Dictionary = data.site.trade_leg_receipts[receipt_key]
	if not _check(receipt.kind == "nation_leg" and int(receipt.treasury_spend) == 30 and receipt.nation_id == "n1", "treasury receipt: nation leg, treasury spend 30"): return
	if not _check(SiteStore.validate_trade_leg_receipts(data.site).ok, "live leg receipts validate"): return

	# 5. Daily ceiling: 30 spent + 25 > 50 daily. Refused, nothing changes.
	var before_ceiling: String = _snapshot(data, collector)
	var ceiling: Dictionary = Leg.commit(data, [_ref(data, "depot"), _ref(data, collector)], [], [{"from": collector, "to": "depot", "amount": 25}], "t6s5-2", "n1", collector, day)
	if not _check(_code(ceiling) == "DAILY_CEILING" and _snapshot(data, collector) == before_ceiling and not data.site.trade_leg_receipts.has("t6s5-2:" + collector), "daily ceiling refused, nothing changes", [_code(ceiling)]): return

	# 6. Reserve: a same-day spend of 15 leaves 15 under the reserve of 20. Refused, nothing changes.
	var before_reserve: String = _snapshot(data, collector)
	var reserve: Dictionary = Leg.commit(data, [_ref(data, "depot"), _ref(data, collector)], [], [{"from": collector, "to": "depot", "amount": 15}], "t6s5-3", "n1", collector, day)
	if not _check(_code(reserve) == "RESERVE" and _snapshot(data, collector) == before_reserve, "reserve refused, nothing changes", [_code(reserve)]): return

	# 7. A same-day spend of 10 leaves exactly the reserve (30 - 10 = 20), and the ledger adds up (30 + 10 = 40 <= 50).
	var next_day: Dictionary = Leg.commit(data, [_ref(data, "depot"), _ref(data, collector)], [], [{"from": collector, "to": "depot", "amount": 10}], "t6s5-4", "n1", collector, day)
	if not _check(bool(next_day.ok), "same-day spend of 10 commits: " + str(next_day)): return
	if not _check(int(_cargo(data, collector).get("coin", 0)) == 20 and int(data.site.equipment_nations.n1.ransom_data.spent_day) == day and int(data.site.equipment_nations.n1.ransom_data.spent) == 40, "same day: coin 20, ledger spent 40", [int(_cargo(data, collector).get("coin", 0)), int(data.site.equipment_nations.n1.ransom_data.spent), int(data.site.equipment_nations.n1.ransom_data.spent_day)]): return

	# 8. Save and reload: leg receipts, the shared ledger and the treasury stock survive with integer types.
	var captured: Dictionary = controller._capture_for_save()
	if not _check(bool(captured.ok), "capture for save: " + str(captured)): return
	var saved: Dictionary = SiteStore.save(data, OUT)
	if not _check(bool(saved.ok), "save: " + str(saved)): return
	var loaded: Dictionary = SiteStore.load_site(OUT)
	if not _check(bool(loaded.ok), "reload: " + str(loaded)): return
	var kept: Dictionary = loaded.data.site.trade_leg_receipts[receipt_key]
	if not _check(kept == data.site.trade_leg_receipts[receipt_key] and typeof(kept.day) == TYPE_INT and typeof(kept.treasury_spend) == TYPE_INT, "leg receipt survives save and reload with int types"): return
	if not _check(loaded.data.site.trade_leg_receipts == data.site.trade_leg_receipts and SiteStore.validate_trade_leg_receipts(loaded.data.site).ok, "whole leg store equal after reload"): return
	var loaded_ledger: Dictionary = loaded.data.site.equipment_nations.n1.ransom_data
	if not _check(int(loaded_ledger.spent) == 40 and int(loaded_ledger.spent_day) == day, "shared ledger survives reload", [int(loaded_ledger.spent), int(loaded_ledger.spent_day)]): return
	if not _check(int(_cargo(loaded.data, collector).get("coin", 0)) == 20, "treasury coin survives reload", [int(_cargo(loaded.data, collector).get("coin", 0))]): return

	print("SITE_TRADE_LEG_TREASURY_OK: bound treasury pays 30 coin for 5 wood; shared ledger caps and resets; leg receipts survive save and reload")
	quit(0)
