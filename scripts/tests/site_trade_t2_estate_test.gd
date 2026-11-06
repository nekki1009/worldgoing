extends "res://scripts/tests/site_building_ui_test.gd"
## Trade T2 TR-23 (first slice): the family estate warehouse. Fixture: a family headed by the controlled person (the NPC
## is not a member) and a complete warehouse of their faction outside any settlement. Checks:
## - only the controlled family head registers it; a house cannot be an estate; a second estate is refused;
## - the estate validates in the saved stockpile schema;
## - a family member loads from it; a non-member's transfer is refused (NO_AUTHORITY) with nothing moved.
## Output: SITE_TRADE_T2_ESTATE_PASS on success; push_error + quit(1) on failure.

const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Stockpiles = preload("res://scripts/terrain_lab/site_stockpiles.gd")

func _fail_now(message: String) -> void:
	push_error("SITE_TRADE_T2_ESTATE_FAIL: " + message)
	quit(1)

func _run() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var player := int(lab.controlled_person_id())
	var npc := int(lab.npc.person_id)
	var site_id := str(data.site.id)
	data.site["family"] = {"version": 4, "name": "", "lineage_id": 1, "complete": true,
		"members": [{"site_id": site_id, "person_id": player, "path": "", "label": "estate head", "age_years": -1}],
		"offices": SiteOffices.default_offices("family", player, false)}
	var warehouse := _formal_feature(data, "warehouse", Vector2i(28, 20), Vector2i(3, 3))
	var second := _formal_feature(data, "warehouse", Vector2i(34, 20), Vector2i(3, 3))
	var house := _formal_feature(data, "house", Vector2i(28, 30))
	if Settlement.register_family_estate(lab, npc, warehouse).ok: return _fail_now("a non-head registered an estate")
	if Settlement.register_family_estate(lab, player, house).ok: return _fail_now("a house became an estate")
	# Through the launcher's selection entry, as the player does it.
	controller.selected = data.cell_from_index(int(data.site.features[warehouse].cells[0]))
	var registered: Dictionary = controller.register_estate_at_selection()
	if not registered.ok or not Stockpiles.family_estate(data, warehouse): return _fail_now("the family head registers the warehouse: " + str(registered))
	if Settlement.register_family_estate(lab, player, second).ok: return _fail_now("a second estate was registered")
	print("SITE_TRADE_T2_ESTATE OK 1: only the family head registers one warehouse as the estate")
	var checked: Dictionary = Stockpiles.validate(data.site)
	if not checked.ok: return _fail_now("the estate validates: " + str(checked))
	print("SITE_TRADE_T2_ESTATE OK 2: the estate validates in the stockpile schema")

	var stock: Dictionary = data.site.stockpiles[warehouse]
	stock.cargo["grain"] = 10
	if not Stockpiles.estate_access(data, warehouse, player) or Stockpiles.estate_access(data, warehouse, npc) or not Stockpiles.estate_access(data, second, npc):
		return _fail_now("estate access: members only, other warehouses unchanged")
	var entrance: Vector2i = Stockpiles.stock_endpoint(data, warehouse).cell
	var stood := false
	for offset: Vector2i in [Vector2i.ZERO, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
		if not stood and lab.character.place(entrance + offset, true): stood = true
	if not stood: return _fail_now("the player stands at the estate door")
	var npc_try: Dictionary = controller.vehicles.transfer("feature:" + warehouse, "person:%d" % npc, {"grain": 1}, [], int(stock.holder.version), int(lab.npc.item_state.version), npc, true)
	if npc_try.ok or int(stock.cargo.grain) != 10: return _fail_now("a non-member's transfer is refused with nothing moved: " + str(npc_try))
	print("SITE_TRADE_T2_ESTATE OK 3: a non-member cannot take from the estate")
	var person: Dictionary = controller.person_actions._person(player)
	var loaded: Dictionary = controller.vehicles.transfer("feature:" + warehouse, "person:%d" % player, {"grain": 2}, [], int(stock.holder.version), int(person.holder.version), player, false)
	if not loaded.ok or int(stock.cargo.grain) != 8: return _fail_now("a family member loads from the estate: " + str(loaded))
	print("SITE_TRADE_T2_ESTATE OK 4: a family member loads from the estate")
	# Trading the estate: the family passes to the NPC (head, and 管家 by acting); the player becomes an outsider.
	var family: Dictionary = data.site.family
	family.members = [{"site_id": site_id, "person_id": npc, "path": "", "label": "estate heir", "age_years": -1}]
	SiteOffices.head_position(family.offices)["holder"] = npc
	var stand := Vector2i(-1, -1)
	for offset: Vector2i in [Vector2i.ZERO, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
		if stand == Vector2i(-1, -1) and lab.npc.place(entrance + offset, true): stand = entrance + offset
	var beside := false
	for offset: Vector2i in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i(1, 1), Vector2i(-1, 1)]:
		if not beside and stand + offset != entrance and lab.character.place(stand + offset, true): beside = true
	if stand == Vector2i(-1, -1) or not beside: return _fail_now("the 管家 stands at the estate door and the player beside him")
	var party: Dictionary = controller._trade().source_party("feature:" + warehouse)
	if not party.ok or int(party.decider) != npc or not data.site.family.offices.duties.has("family.estate"): return _fail_now("the head acts as the vacant 管家: " + str(party))
	if controller.trade_source_of(npc) != "feature:" + warehouse: return _fail_now("the dialog finds the estate its 管家 stands at")
	data.site.manual.cargo.clear()
	data.site.manual.cargo["iron"] = 1
	var food_floor: Dictionary = controller.trade_propose_settlement(npc, warehouse, {"iron": 1}, {"grain": 2})
	if not food_floor.ok or str(food_floor.decision) != "REJECT": return _fail_now("8 grain against a 14-day target keeps its floor: " + str(food_floor))
	stock.cargo["grain"] = 30
	var offer: Dictionary = controller.trade_propose_settlement(npc, warehouse, {"iron": 1}, {"grain": 2})
	if not offer.ok or str(offer.decision) != "ACCEPT": return _fail_now("the family accepts 1 iron for 2 grain: " + str(offer))
	if not controller.trade_accept(str(offer.offer_id)).ok: return _fail_now("the estate delivery starts")
	lab.fire_action_cursor += 3.0
	var results: Array[Dictionary] = controller._trade().advance()
	if results.size() != 1 or not results[0].ok or int(stock.cargo.get("grain", 0)) != 28 or int(stock.cargo.get("iron", 0)) != 1: return _fail_now("the estate trade delivers once: %s %s" % [str(results), str(stock.cargo)])
	print("SITE_TRADE_T2_ESTATE OK 5: the 管家 trades the estate with an outsider")
	print("SITE_TRADE_T2_ESTATE_PASS: registration, schema, member-only access, estate trade")
	lab.free()
	quit(0)
