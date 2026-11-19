extends SceneTree
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Trade = preload("res://scripts/terrain_lab/site_trade.gd")
const Values = preload("res://scripts/terrain_lab/site_trade_values.gd")

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> bool:
	if condition: return true
	push_error("SITE_TRADE_VALUES_FAIL: " + message)
	quit(1)
	return false

func _goods(resources: Dictionary = {}, item_ids: Array = []) -> Dictionary:
	return {"resources": resources, "item_ids": item_ids}

func _decision(receive: Dictionary, give: Dictionary, stock: Dictionary, targets: Dictionary, thrift: float = 50.0) -> String:
	var result: Dictionary = Trade.accept(_goods(receive), _goods(give), stock, targets, thrift)
	return str(result.get("decision", "ERROR")) if result.ok else "ERROR"

func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: push_error("SITE_TRADE_VALUES_TIMEOUT"); quit(1))
	if not _check(Runtime.Env.ITEM_NAMES.has("coin") and not Values.RESOURCE_VALUES.has("coin") and Values.validate_table().ok and Values.resource_value("coin") == -1.0, "TR78 registered coin is excluded from the complete resource table and cannot be valued"): return
	if not _check(Values.validate_table().ok, "TR04 current recipes and versioned table"): return
	if not _check(Values.derive_resources() == Values.RESOURCE_VALUES and Values.derive_equipment() == Values.EQUIPMENT_VALUES, "TR04 all original recipe alternatives"): return
	if not _check(Values.resource_value("coin") < 0.0 and Values.resource_value("bow") < 0.0, "TR78 namespaces and inactive coin"): return
	var margins: Array[float] = [0.10, 0.08, 0.06, 0.05, 0.05, 0.05]
	for concessions: int in range(6):
		if not _check(absf(Trade.margin(50.0, concessions) - margins[concessions]) < 0.000000001, "appendix margin vector"): return
	if not _check(Trade.margin(0.0) == 0.0 and Trade.margin(100.0) == 0.20 and absf(Trade.margin(100.0, 4) - 0.12) < 0.000000001, "appendix thrift bounds"): return
	var need: Dictionary = {"food": 140.0}
	var village: Dictionary = {"grain": 40, "tools": 20}
	if not _check(_decision({"tools": 10}, {"grain": 100}, village, need) == "REJECT", "appendix hard food floor"): return
	if not _check(_decision({"grain": 100}, {"tools": 10}, village, need) == "ACCEPT", "appendix food shortage"): return
	var average: float = (Trade.primitive(140.0, 140.0) - Trade.primitive(40.0, 140.0)) / 100.0
	if not _check(absf(average - 1.17857) < 0.0001, "appendix average scarcity"): return
	var rich: Dictionary = {"grain": 400}
	if not _check(_decision({"tools": 10}, {"grain": 60}, rich, need) == "ACCEPT" and _decision({"tools": 10}, {"grain": 60}, rich, need, 100.0) == "ACCEPT", "appendix surplus"): return
	if not _check(_decision({"tools": 10}, {"grain": 170}, rich, need) == "REJECT", "appendix insufficient value"): return
	var fish_value: Dictionary = Trade.side_value(_goods({"grain": 20}), {"fish": 400}, need, true)
	if not _check(fish_value.ok and float(fish_value.value) == 10.0, "appendix shared food category"): return
	var allow: Callable = func(_receive: Dictionary, _give: Dictionary) -> bool: return true
	for concessions: int in [0, 4]:
		var quoted: Dictionary = Trade.counter_offer(_goods({"tools": 4}), _goods({"grain": 100}), rich, need, {"tools": 4}, allow, 50.0, concessions)
		if not _check(quoted.ok and quoted.decision == "ACCEPT" and quoted.give.resources == {"grain": 49 if concessions == 0 else 51}, "appendix counter49/51"): return
	for pair: Array in [[40, 34.0], [50, 39.0], [56, 42.0]]:
		var value: Dictionary = Trade.side_value(_goods({"grain": int(pair[0])}), {}, {"food": 14.0}, true)
		if not _check(value.ok and absf(float(value.value) - float(pair[1])) < 0.000000001, "TR77 clamp transition"): return
	var mixed: Dictionary = Trade.side_value(_goods({"grain": 2, "fish": 3}), {"meat": 5}, {"food": 14.0}, true)
	var combined: Dictionary = Trade.side_value(_goods({"grain": 5}), {"meat": 5}, {"food": 14.0}, true)
	if not _check(mixed.ok and combined.ok and absf(float(mixed.value) - float(combined.value)) < 0.000000001, "appendix mixed food equality"): return
	var zero_target: Dictionary = Trade.side_value(_goods({"wood": 1}), {"wood": 1}, {}, false)
	if not _check(zero_target.ok and float(zero_target.value) == 0.375, "appendix T0 interval0.75"): return
	for target: float in [0.0, 0.5, 3.0, 14.0, 168.0, 560.0]:
		for stock: int in [0, 1, 40, 80, 240, 400]:
			var previous: float = 0.0
			for quantity: int in range(1, 301):
				var value: Dictionary = Trade.side_value(_goods({"grain": quantity}), {"grain": stock}, {"food": target}, true)
				if not _check(value.ok and float(value.value) >= previous, "TR77 total value monotonic"): return
				previous = float(value.value)
	if not _check(_decision({"tools": 1}, {"grain": 1}, {"grain": 80}, {"food": 168.0}) == "REJECT", "appendix market alone below floor"): return
	if not _check(_decision({"tools": 1}, {"grain": 1}, {"grain": 280}, {"food": 168.0}) == "ACCEPT" and _decision({"tools": 1}, {"grain": 1}, {"grain": 320}, {"food": 560.0}) == "ACCEPT", "appendix authorized aggregate12/40 residents"): return
	if not _check(Trade._floor_ok(_goods({"fish": 2}), _goods({"grain": 2}), {"grain": 2}, {"food": 4.0}, {}), "appendix net food floor exact fixed vector"): return
	var reserve: Dictionary = Trade.accept(_goods({"tools": 1}), _goods({"wood": 1}), {"wood": 3}, {}, 50.0, 0, {}, {"wood": 3})
	if not _check(reserve.ok and reserve.decision == "REJECT" and reserve.reason == "RESERVE", "appendix construction floor"): return
	var subjective: Dictionary = Trade.counter_offer(_goods({"grain": 1}), _goods({"cloth": 1, "wood": 1}), {"cloth": 10, "wood": 1}, {"wood": 10.0}, {"grain": 1}, allow)
	if not _check(subjective.ok and subjective.decision == "ACCEPT" and subjective.give.resources == {"cloth": 1}, "TR77 subjective ordering"): return
	var hard_floor: Dictionary = Trade.counter_offer(_goods({"tools": 1}), _goods({"grain": 2}), {"grain": 3}, {"food": 3.0}, {"tools": 1}, allow)
	if not _check(hard_floor.ok and hard_floor.decision == "REJECT" and hard_floor.evaluations == 0, "TR77 no counter past hard floor"): return
	var raised: Dictionary = Trade.counter_offer(_goods({"wood": 3}), _goods({"cloth": 1}), {"cloth": 1}, {}, {"wood": 4}, allow, 100.0)
	if not _check(raised.ok and raised.decision == "ACCEPT" and raised.receive.resources == {"wood": 4}, "TR77 floor50pct of3 is1"): return
	var one: Dictionary = Trade.counter_offer(_goods({"wood": 1}), _goods({"cloth": 1}), {"cloth": 1}, {}, {"wood": 100}, allow)
	if not _check(one.ok and one.decision == "REJECT", "TR77 floor50pct of1 is0"): return
	var unavailable: Dictionary = Trade.counter_offer(_goods({"wood": 3}), _goods({"cloth": 1}), {"cloth": 1}, {}, {"wood": 3}, allow, 100.0)
	if not _check(unavailable.ok and unavailable.decision == "REJECT", "TR77 cannot request unavailable amount"): return
	var cap_three: Callable = func(receive: Dictionary, _give: Dictionary) -> bool: return int(receive.resources.get("wood", 0)) <= 3
	var capacity: Dictionary = Trade.counter_offer(_goods({"wood": 3}), _goods({"cloth": 1}), {"cloth": 1}, {}, {"wood": 4}, cap_three, 100.0)
	if not _check(capacity.ok and capacity.decision == "REJECT", "TR77 owner capacity refusal"): return
	var grain_limit: Callable = func(receive: Dictionary, _give: Dictionary) -> bool: return int(receive.resources.grain) <= 3
	var alternative: Dictionary = Trade.counter_offer(_goods({"grain": 3, "wood": 10}), _goods({"iron": 1}), {"iron": 1}, {}, {"grain": 4, "wood": 15}, grain_limit, 100.0)
	if not _check(alternative.ok and alternative.decision == "ACCEPT" and alternative.receive.resources == {"grain": 3, "wood": 13}, "TR77 skip illegal high-price increment"): return
	if not _check(alternative.evaluations == 7, "TR77 each illegal/legal candidate counted once"): return
	var last: Dictionary = Trade.counter_offer(_goods({"wood": 2}), _goods({"grain": 2048}), {"grain": 2048}, {}, {"wood": 2}, allow)
	if not _check(last.ok and last.decision == "ACCEPT" and last.evaluations == 2048 and last.give.resources == {"grain": 1}, "TR77 evaluate final legal candidate at2048"): return
	var limited: Dictionary = Trade.counter_offer(_goods({"wood": 1}), _goods({"grain": 1000000}), {"grain": 1000000}, {}, {"wood": 1}, allow)
	if not _check(not limited.ok and limited.code == "NEGOTIATION_LIMIT" and limited.evaluations == 2048, "TR77 finite evaluation budget"): return
	var invalid: Dictionary = Trade.side_value(_goods({"wood": 1.5}), {}, {}, true)
	# Nekki 2026-11-19 「好」: coin is valued at one grain (it moves as a payment leg, never as goods).
	var coin_value: Dictionary = Trade.side_value(_goods({"coin": 3}), {}, {}, true)
	var grain_value: Dictionary = Trade.side_value(_goods({"grain": 3}), {}, {}, true)
	if not _check(not invalid.ok and coin_value.ok and grain_value.ok and is_equal_approx(float(coin_value.value), float(grain_value.value)) and not Trade.side_value(_goods({"wood": 1}), {}, {"wood": INF}, true).ok, "TR77 trust boundaries; coin is worth a grain"): return
	var interned: Dictionary = {&"wood": 1}
	var live_value: Dictionary = Trade.side_value(_goods(interned), {&"wood": 1}, {&"wood": 0.0}, false)
	if not _check(live_value.ok and float(live_value.value) == 0.375, "TR77 original interned resource keys"): return
	var data: TerrainData = TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "trade-values-fixture")
	if not _check(Runtime.initialize_item_storage(data.site).ok, "TR78 original item registry"): return
	var holder: Dictionary = Runtime.new_item_state("person:21")
	var bow: Dictionary = Runtime.create_equipment(data, holder, "weapon:bow_01", {"slot": "weapon", "asset": "bow_01", "tint": [1.0, 1.0, 1.0, 1.0]}, 21)
	var crossbow: Dictionary = Runtime.create_equipment(data, holder, "weapon:crossbow_01", {"slot": "weapon", "asset": "crossbow_01", "tint": [1.0, 1.0, 1.0, 1.0]}, 21)
	var sword: Dictionary = Runtime.create_equipment(data, holder, "test-sword", {"slot": "weapon", "asset": "longsword_01", "tint": [1.0, 1.0, 1.0, 1.0]}, 21)
	if not _check(bow.ok and crossbow.ok and sword.ok, "TR78 create true records"): return
	if not _check(Values.item_value(data.site, str(bow.item_id)) == 4.0 and Values.item_value(data.site, str(crossbow.item_id)) == 17.0 and Values.item_value(data.site, str(sword.item_id)) == 8.0, "TR78 original asset lookup and slot fallback"): return
	var item_offer: Dictionary = Trade.side_value(_goods({}, [bow.item_id]), {"item:weapon:bow_01": 1}, {}, false, data.site)
	if not _check(item_offer.ok and float(item_offer.value) == 3.0, "TR78 per-definition item category"): return
	if not _check(not Trade.side_value(_goods({}, [bow.item_id, bow.item_id]), {}, {}, true, data.site).ok, "TR78 repeated item ID"): return
	data.site.item_records[bow.item_id].definition = "missing"
	if not _check(Values.item_value(data.site, str(bow.item_id)) < 0.0, "TR78 unknown definition"): return
	print("SITE_TRADE_VALUES_PASS: TR04/TR77/TR78; frozen appendix vectors, real item registry, current recipe derivation, monotonic scarcity and bounded legal counteroffers; T0 only")
	quit(0)
