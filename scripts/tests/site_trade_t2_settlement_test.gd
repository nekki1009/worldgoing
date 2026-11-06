extends "res://scripts/tests/site_building_ui_test.gd"
## Trade T2 first slice: the player trades with a settlement warehouse through its `settlement.trade` decider.
## Fixture: a level-1 settlement of faction 1 with a complete warehouse in its jurisdiction; the NPC is the head.
## Checks:
## - a fresh settlement gets the 市正 seat (vacant); the head acts for it and is the warehouse's decider;
## - the decider must stand at the warehouse entrance (TR-26);
## - the settlement values with residents × 14 days of food and answers; the delivery moves the goods between the
##   player and the warehouse exactly once, with both versions raised once;
## - with someone else seated as 市正 the head is refused (NO_AUTHORITY).
## Output: SITE_TRADE_T2_SETTLEMENT_PASS on success; push_error + quit(1) on failure.

const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Stockpiles = preload("res://scripts/terrain_lab/site_stockpiles.gd")

func _fail_now(message: String) -> void:
	push_error("SITE_TRADE_T2_SETTLEMENT_FAIL: " + message)
	quit(1)

func _run() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var head := int(lab.npc.person_id)
	var player := int(lab.character.person_id)
	assert(lab.character.place(Vector2i(20, 18), true))
	var placement := Runtime.building_cells(data, "settlement_center", Vector2i(20, 20), Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	var cells: Array[int] = []
	cells.assign(placement.cells)
	var founded := Settlement.found(lab, player, cells, {"layout_version": 1, "quarter": 0}, Callable(), "交易村")
	if not founded.ok: return _fail_now("the settlement is founded: " + str(founded))
	_complete_key(data, str(founded.feature))
	if int(data.site.settlement.level) < 1: data.site.settlement["level"] = 1 # fixture: an effective village
	var warehouse := _formal_feature(data, "warehouse", Vector2i(28, 20), Vector2i(3, 3))
	# TR-21: the head (still the player) binds the warehouse to the 市正 with grain limits 2 per trade, 3 in total.
	if Settlement.bind_trade_source(lab, head, warehouse, {"grain": {"per_trade": 2, "total": 3}}).ok: return _fail_now("only the controlled head may bind a trade source")
	var bound: Dictionary = Settlement.bind_trade_source(lab, player, warehouse, {"grain": {"per_trade": 2, "total": 3}})
	if not bound.ok: return _fail_now("the head binds the warehouse: " + str(bound))
	print("SITE_TRADE_T2 OK 0: the controlled head binds the warehouse with limits")
	# The NPC is the settlement's head (the player founded it and hands the seat over).
	SiteOffices.head_position(data.site.settlement.offices)["holder"] = head
	var stocked: Dictionary = Stockpiles.ensure_storage(data, warehouse, 1)
	if not stocked.ok: return _fail_now("the warehouse stock opens: " + str(stocked))
	data.site.stockpiles[warehouse].cargo["grain"] = 50
	var entrance: Vector2i = Stockpiles.stock_endpoint(data, warehouse).cell
	var party: Dictionary = controller.trade_session.settlement_party(warehouse) if controller.trade_session.controller != null else controller._trade().settlement_party(warehouse)
	if not party.ok or int(party.decider) != head: return _fail_now("the head acts as the vacant 市正 and decides for the warehouse: " + str(party))
	if not data.site.settlement.offices.duties.has("settlement.trade"): return _fail_now("the settlement gained the 市正 seat")
	print("SITE_TRADE_T2 OK 1: the head acts for the vacant 市正")

	# The decider away from the entrance is refused (TR-26).
	assert(lab.npc.place(Vector2i(12, 12), true))
	assert(lab.character.place(Vector2i(12, 13), true))
	data.site.manual.cargo.clear()
	data.site.manual.cargo["iron"] = 2
	var away: Dictionary = controller.trade_propose_settlement(head, warehouse, {"iron": 1}, {"grain": 2})
	if away.ok or str(away.code) != "TOO_FAR": return _fail_now("the decider must stand at the warehouse: " + str(away))
	print("SITE_TRADE_T2 OK 2: a decider away from the warehouse is refused")

	var stand := Vector2i(-1, -1)
	for offset: Vector2i in [Vector2i.ZERO, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
		if stand == Vector2i(-1, -1) and lab.npc.place(entrance + offset, true): stand = entrance + offset
	if stand == Vector2i(-1, -1): return _fail_now("the decider can stand at the warehouse entrance %s" % str(entrance))
	var beside := false
	for offset: Vector2i in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i(1, 1), Vector2i(-1, 1)]:
		if not beside and stand + offset != entrance and lab.character.place(stand + offset, true): beside = true
	if not beside: return _fail_now("the player can stand beside the decider")
	if controller.trade_warehouse_of(head) != warehouse: return _fail_now("the dialog finds the warehouse its decider stands at")
	var stock: Dictionary = data.site.stockpiles[warehouse]
	var versions := [int(lab.character.item_state.version), int(stock.holder.version)]
	var offer: Dictionary = controller.trade_propose_settlement(head, warehouse, {"iron": 1}, {"grain": 2})
	if not offer.ok or str(offer.decision) != "ACCEPT": return _fail_now("the settlement accepts 1 iron for 2 grain: " + str(offer))
	var started: Dictionary = controller.trade_accept(str(offer.offer_id))
	if not started.ok or not controller.person_actions.is_busy(head) or not controller.person_actions.is_busy(player): return _fail_now("the delivery starts and both are busy: " + str(started))
	print("SITE_TRADE_T2 OK 3: the settlement accepts and the delivery starts")
	lab.fire_action_cursor += 3.0
	var results: Array[Dictionary] = controller._trade().advance()
	if results.size() != 1 or not results[0].ok: return _fail_now("the delivery completes: " + str(results))
	if int(data.site.manual.cargo.get("iron", 0)) != 1 or int(data.site.manual.cargo.get("grain", 0)) != 2 or int(stock.cargo.get("grain", 0)) != 48 or int(stock.cargo.get("iron", 0)) != 1:
		return _fail_now("the goods moved between the player and the warehouse: %s %s" % [str(data.site.manual.cargo), str(stock.cargo)])
	if int(lab.character.item_state.version) != versions[0] + 1 or int(stock.holder.version) != versions[1] + 1: return _fail_now("each version rose once")
	print("SITE_TRADE_T2 OK 4: the goods moved once between the player and the warehouse")
	if int(data.site.settlement.trade_sources[warehouse].used.get("grain", 0)) != 2: return _fail_now("the payout is recorded once: " + str(data.site.settlement.trade_sources))
	var over_total: Dictionary = controller.trade_propose_settlement(head, warehouse, {"iron": 1}, {"grain": 2})
	if over_total.ok or str(over_total.code) != "QUOTA": return _fail_now("2 more grain would pass the total of 3: " + str(over_total))
	var unlisted: Dictionary = controller.trade_propose_settlement(head, warehouse, {"grain": 1}, {"iron": 1})
	if unlisted.ok or str(unlisted.code) != "QUOTA": return _fail_now("iron has no limit and cannot be paid out: " + str(unlisted))
	if not Settlement.valid_trade_sources(data.site.settlement.trade_sources, data.site): return _fail_now("the bindings validate")
	print("SITE_TRADE_T2 OK 4b: the total limit and an unlisted resource refuse; the bindings validate")

	# A seated 市正 takes the duty from the head.
	var offices: Dictionary = data.site.settlement.offices
	var seat := SiteOffices.position(offices, str(offices.duties["settlement.trade"]))
	seat["holder"] = player # the player is seated as 市正
	var refused: Dictionary = controller.trade_propose_settlement(head, warehouse, {"iron": 1}, {"grain": 2})
	if refused.ok or str(refused.code) != "NO_AUTHORITY": return _fail_now("the head is refused once a 市正 is seated: " + str(refused))
	print("SITE_TRADE_T2 OK 5: a seated 市正 takes the duty from the head")
	print("SITE_TRADE_T2_SETTLEMENT_PASS: head acting, entrance rule, settlement valuation and delivery, seated 市正")
	lab.free()
	quit(0)
