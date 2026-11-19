extends "res://scripts/tests/site_market_t3_test.gd"
## 貿易 T3 slice 3 (reports/trade-plan.md §5.2, §6; TR-32, TR-33): the 市正's listings by the settlement's duty AI
## (SiteMarket.day, run by SiteDutyAI.review). Fixture: a level 2 settlement with a market bound as a trade source
## (salt and grain limits), a house in the jurisdiction where the NPC and the player are registered (2 residents: a
## food target of 28), the NPC as head (acting as 市正) and the settlement's duty AI on.
## Checks:
## - food 0 (below 28): the market lists 1 salt for 1 grain, 10 lots a day (grade 1); the next review leaves it as is;
## - food 100 (above 56): it lists 1 grain for 1 salt; food 40 (between): it takes the listings down;
## - TR-33: with the duty AI off nothing changes and a standing listing stays (trades on it are still answered);
## - the controlled person as the trader: the AI never lists for him; a binding without a salt limit lists no buying.
## Output: SITE_MARKET_AI_T3_PASS on success; push_error + quit(1) on failure.

var ai_checks := 0

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	ai_checks += 1
	if condition:
		print("SITE_MARKET_AI_T3 OK ", ai_checks, ": ", message)
		return true
	push_error("SITE_MARKET_AI_T3_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _rows(data: TerrainData) -> Array:
	return Market.listings(data).get("rows", [])

func _set_food(data: TerrainData, grain: int) -> void:
	for resource: String in Market.FOODS: data.site.inventory[resource] = 0
	data.site.inventory["grain"] = grain

func _run() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var player := int(lab.character.person_id)
	var npc := int(lab.npc.person_id)
	var placed: bool = lab.character.place(Vector2i(20, 18), true)
	if not _check(placed, "the founder stands beside the center site"): return
	var layout := Runtime.building_cells(data, "settlement_center", Vector2i(20, 20), Vector2i(5, 5), OPTIONS)
	var center_cells: Array[int] = []
	center_cells.assign(layout.get("cells", []))
	var founded := Settlement.found(lab, player, center_cells, {"layout_version": 1, "quarter": 0}, Callable(), "市正村")
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
	data.site.stockpiles[key].cargo["salt"] = 20
	var bound := Settlement.bind_trade_source(lab, player, key, {"salt": {"per_trade": 10, "total": 1000}, "grain": {"per_trade": 10, "total": 1000}})
	if not _check(bound.ok, "the head binds the market stock with salt and grain limits", bound): return
	var house := _formal_feature(data, "house", Vector2i(34, 20), Vector2i(3, 3))
	if not data.site.has("housing"): data.site["housing"] = {}
	data.site.housing[str(npc)] = {"house_id": house}
	data.site.housing[str(player)] = {"house_id": house}
	if not _check(Settlement.residents(lab).size() == 2, "two residents: a food target of 28", Settlement.residents(lab)): return
	var offices: Dictionary = data.site.settlement.offices
	SiteOffices.head_position(offices)["holder"] = npc
	offices["duty_ai"] = true

	# TR-32: food against the target.
	_set_food(data, 0)
	var low := Market.day(lab)
	var rows := _rows(data)
	if not _check(str(low.get("reason", "")) == "set" and rows.size() == 1 and _same_counts(rows[0].give, {"salt": 1}) and _same_counts(rows[0].want, {"grain": 1}) and int(rows[0].daily) == 10,
		"food 0 below 28: the market buys grain 1 for salt 1, 10 lots a day", low): return
	var revision := int(Market.listings(data).revision)
	var again := Market.day(lab)
	if not _check(str(again.get("reason", "")) == "unchanged" and int(Market.listings(data).revision) == revision, "the next review leaves the same listing as it is", again): return
	_set_food(data, 100)
	var high := Market.day(lab)
	rows = _rows(data)
	if not _check(str(high.get("reason", "")) == "set" and rows.size() == 1 and _same_counts(rows[0].give, {"grain": 1}) and _same_counts(rows[0].want, {"salt": 1}),
		"food 100 above 56: the market sells grain 1 for salt 1", high): return
	_set_food(data, 40)
	var middle := Market.day(lab)
	if not _check(str(middle.get("reason", "")) == "set" and not data.site.settlement.has("market_listings"), "food 40 between: the listings come down", middle): return

	# TR-33: the duty AI off.
	_set_food(data, 0)
	if not _check(str(Market.day(lab).get("reason", "")) == "set" and _rows(data).size() == 1, "fixture: a buying listing stands"): return
	offices["duty_ai"] = false
	_set_food(data, 100)
	var off := Market.day(lab)
	rows = _rows(data)
	if not _check(str(off.get("reason", "")) == "duty_ai_off" and rows.size() == 1 and _same_counts(rows[0].give, {"salt": 1}), "with the duty AI off nothing changes; the standing listing stays", off): return

	# The controlled person trades himself; a binding without a salt limit lists no buying.
	offices["duty_ai"] = true
	SiteOffices.head_position(offices)["holder"] = player
	var own := Market.day(lab)
	if not _check(str(own.get("reason", "")) == "no_npc_trader" and _rows(data).size() == 1, "the AI never lists for the controlled person", own): return
	var cleared := Market.set_listings(lab, player, [])
	var rebound := Settlement.bind_trade_source(lab, player, key, {"grain": {"per_trade": 10, "total": 1000}})
	SiteOffices.head_position(offices)["holder"] = npc
	_set_food(data, 0)
	var no_salt := Market.day(lab)
	if not _check(cleared.ok and rebound.ok and str(no_salt.get("reason", "")) == "unchanged" and _rows(data).is_empty(), "a binding without a salt limit lists no buying", no_salt): return

	print("SITE_MARKET_AI_T3_PASS checks=", ai_checks, "; buy below the target, sell above twice it, down between, unchanged stands, duty AI off, controlled trader, no salt limit")
	_finish_workflow_body()
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
