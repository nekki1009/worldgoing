extends "res://scripts/tests/site_market_t3_test.gd"
## 貿易 T6 S7 (TR-61, Q12 A) at a real settlement: a trade treaty lowers the trade tax for its partner. Fixture as
## site_trade_tax_live_t6_test (a level 2 settlement of nation n1, faction 1, trade tax raised to 20%, the treasury bound); the
## Region slot is a stand-in RegionSaveSlot holding a faction registry where faction 1 and faction 2 are at peace. The
## NPC is moved to faction 2. Checks:
## - with no trade treaty, a face-to-face trade between the player (faction 1) and the NPC (faction 2) pays 20%;
## - with a 10% trade treaty it pays 10% (the lower of the two rates); the treasury gets exactly that, in kind;
## - once the treaty's term has passed, 20% again;
## - a treaty rate above the base (30%) never raises it: still 20%.
## Output: SITE_TRADE_TREATY_LIVE_T6_PASS on success; push_error + quit(1) on failure.

var treaty_checks := 0

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	treaty_checks += 1
	if condition:
		print("SITE_TRADE_TREATY_LIVE_T6 OK ", treaty_checks, ": ", message)
		return true
	push_error("SITE_TRADE_TREATY_LIVE_T6_FAIL: %s %s" % [message, str(detail)])
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

	# The stand-in Region slot: factions 1 and 2 at peace (allocated as in region_trade_treaty_t6_test).
	var reg: Dictionary = {"version": 1, "revision": 0, "next_faction_id": 1, "migration_complete": true, "entries": {}, "coverage": {"complete": false, "sources": [], "counts": null}}
	var made: Dictionary = RegionFactionQuery.allocate(reg, 0, 0.0, {"name": "甲", "kind": "player", "leader_ref": {"type": "person", "namespace": "treaty_live", "lineage": 1}, "founded_at": 0.0})
	reg = made.registry
	var f1 := int(made.faction_id)
	made = RegionFactionQuery.allocate(reg, int(reg.revision), 0.0, {"name": "乙", "kind": "npc", "leader_ref": {"type": "person", "namespace": "treaty_live", "lineage": 2}, "founded_at": 0.0})
	reg = made.registry
	var f2 := int(made.faction_id)
	if not _check(f1 == 1 and f2 == 2, "the registry's factions are 1 and 2 (the fixture's people)", [f1, f2]): return
	var t := 1000.0
	var peace: Dictionary = RegionDiplomacy.propose(reg, f1, f2, "peace", 0, {"type": "person", "namespace": "treaty_live", "lineage": 1}, 0.0, t)
	reg = RegionDiplomacy.settle(peace.registry, t).registry
	reg = RegionDiplomacy.reply(reg, int(peace.proposal_id), true, {"type": "person", "namespace": "treaty_live", "lineage": 2}, 0.0, t).registry
	reg = RegionDiplomacy.settle(reg, t).registry
	if not _check(RegionDiplomacy.at_peace(reg, f1, f2, t), "factions 1 and 2 are at peace"): return
	var slot := RegionSaveSlot.new()
	slot.control = {"logical_game_seconds": t, "active_site_id": "", "fire_clock": {}, "faction_registry": reg}
	controller.region_slot = slot
	lab.npc.faction_id = 2
	var actions: SitePersonActions = controller.person_actions
	var stand: bool = _face_at(Stockpiles.stock_endpoint(data, treasury_key).cell + Vector2i(0, 2), lab.npc, lab.character)
	if not _check(stand and int(actions._person(npc).faction) == 2 and int(actions._person(player).faction) == 1, "the player (faction 1) stands before the NPC (faction 2)"): return
	var treasury: Dictionary = data.site.stockpiles[treasury_key]
	if not _check(Settlement.set_trade_tax_percent(data, player, 20).ok and int(Runtime.trade_tax_terms(data).percent) == 20, "the head raises the trade tax to 20%"): return

	# A trade: the player gives 15 grain for the NPC's 10 salt (a person carries 20; the NPC keeps its own food); the treasury takes floor(rate) of each side.
	# The rate is raised to 20% so a 10% treaty shows on these small lots.
	var trade_once := func(label: String) -> Array:
		data.site.manual.cargo.clear()
		data.site.manual.cargo["grain"] = 15
		var seller: Dictionary = actions._person(npc)
		seller.cargo.clear()
		seller.cargo["salt"] = 10
		var before := [int(treasury.cargo.get("grain", 0)), int(treasury.cargo.get("salt", 0))]
		var offer: Dictionary = controller.trade_propose(npc, {"grain": 15}, {"salt": 10})
		if not offer.get("ok", false) or str(offer.get("decision", "")) != "ACCEPT": return [false, offer]
		if not controller.trade_accept(str(offer.offer_id)).ok: return [false, "accept"]
		lab.fire_action_cursor += 31.0
		var results: Array[Dictionary] = controller._trade().advance()
		if results.size() != 1 or not results[0].ok: return [false, results]
		return [true, int(treasury.cargo.get("grain", 0)) - before[0], int(treasury.cargo.get("salt", 0)) - before[1]]
	var base_trade: Array = trade_once.call("base")
	if not _check(base_trade[0] and base_trade[1] == 3 and base_trade[2] == 2, "with no treaty the partner's trade pays 20%", base_trade): return
	var signed: Dictionary = RegionDiplomacy.propose(reg, f1, f2, "trade", 30, {"type": "person", "namespace": "treaty_live", "lineage": 1}, 0.0, t, 10)
	if not _check(signed.ok, "a 10% trade treaty is proposed", signed): return
	reg = RegionDiplomacy.settle(signed.registry, t).registry
	reg = RegionDiplomacy.reply(reg, int(signed.proposal_id), true, {"type": "person", "namespace": "treaty_live", "lineage": 2}, 0.0, t).registry
	reg = RegionDiplomacy.settle(reg, t).registry
	slot.control["faction_registry"] = reg
	if not _check(not RegionDiplomacy.trade_treaty_between(reg, f1, f2, t).is_empty(), "the trade treaty stands"): return
	var treaty_trade: Array = trade_once.call("treaty")
	if not _check(treaty_trade[0] and treaty_trade[1] == 1 and treaty_trade[2] == 1, "under the 10% treaty the partner's trade pays 10% (the lower rate)", treaty_trade): return
	slot.control["logical_game_seconds"] = t + 31.0 * 86400.0
	var expired_trade: Array = trade_once.call("expired")
	if not _check(expired_trade[0] and expired_trade[1] == 3 and expired_trade[2] == 2, "after the treaty's term the trade pays 20% again", expired_trade): return
	# A treaty only lowers the tax: a 30% treaty above the 20% base still pays 20%.
	var t2 := t + 31.0 * 86400.0
	var high: Dictionary = RegionDiplomacy.propose(reg, f1, f2, "trade", 30, {"type": "person", "namespace": "treaty_live", "lineage": 1}, 0.0, t2, 30)
	if not _check(high.ok, "a 30% trade treaty is proposed after the first one ended", high): return
	reg = RegionDiplomacy.settle(high.registry, t2).registry
	reg = RegionDiplomacy.reply(reg, int(high.proposal_id), true, {"type": "person", "namespace": "treaty_live", "lineage": 2}, 0.0, t2).registry
	reg = RegionDiplomacy.settle(reg, t2).registry
	slot.control["faction_registry"] = reg
	if not _check(int(RegionDiplomacy.trade_treaty_between(reg, f1, f2, t2).get("tax_percent", -1)) == 30, "the 30% trade treaty stands"): return
	var high_trade: Array = trade_once.call("high")
	if not _check(high_trade[0] and high_trade[1] == 3 and high_trade[2] == 2, "a 30% treaty above the 20% base still pays 20% (a treaty only lowers)", high_trade): return

	controller.region_slot = null
	print("SITE_TRADE_TREATY_LIVE_T6_PASS checks=", treaty_checks, "; base 20%, treaty 10% (the lower), expired back to 20%, a 30% treaty still 20%")
	_finish_workflow_body()
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
