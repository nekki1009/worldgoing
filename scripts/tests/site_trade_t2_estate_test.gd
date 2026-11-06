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
	var registered: Dictionary = Settlement.register_family_estate(lab, player, warehouse)
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
	print("SITE_TRADE_T2_ESTATE_PASS: registration, schema, member-only access")
	lab.free()
	quit(0)
