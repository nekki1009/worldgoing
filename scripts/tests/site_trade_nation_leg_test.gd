extends SceneTree
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const SiteStore = preload("res://scripts/terrain_lab/site_store.gd")
const Leg = preload("res://scripts/terrain_lab/site_trade_nation_leg.gd")
const Tent = preload("res://scripts/tests/site_tent_logistics_test.gd")
var fixture: Variant

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> bool:
	if condition: return true
	push_error("SITE_TRADE_NATION_LEG_FAIL: " + message)
	quit(1)
	return false

func _move(source: String, destination: String, resources: Dictionary = {}, ids: Array = []) -> Dictionary:
	return {"from": source, "to": destination, "resources": resources, "item_ids": ids}

func _pay(source: String, destination: String, amount: Variant) -> Dictionary:
	return {"from": source, "to": destination, "amount": amount}

func _ref(data: TerrainData, holder_id: String) -> Dictionary:
	var endpoint: Dictionary = Runtime.trade_endpoint(data, holder_id)
	return {"holder": holder_id, "expected_version": int(endpoint.holder.version)} if endpoint.ok else {"holder": holder_id, "expected_version": 0}

func _refs(data: TerrainData, ids: Array) -> Array:
	var refs: Array = []
	for holder_id: String in ids:
		refs.append(_ref(data, holder_id))
	return refs

func _set_cargo(data: TerrainData, holder_id: String, resources: Dictionary) -> void:
	var endpoint: Dictionary = Runtime.trade_endpoint(data, holder_id)
	endpoint.cargo.clear()
	endpoint.cargo.merge(resources)

func _cargo(data: TerrainData, holder_id: String) -> Dictionary:
	return Runtime.trade_endpoint(data, holder_id).cargo

func _reset(data: TerrainData) -> void:
	_set_cargo(data, "person:1", {})
	_set_cargo(data, "person:2", {})
	_set_cargo(data, "person:3", {"wood": 1})

func _snapshot(data: TerrainData) -> String:
	var rows: Array = []
	for holder_id: String in ["person:1", "person:2", "person:3"]:
		var endpoint: Dictionary = Runtime.trade_endpoint(data, holder_id)
		rows.append([holder_id, endpoint.get("holder", {}), endpoint.get("cargo", {})])
	return JSON.stringify([data.site, rows], "", true)

func _receipt_count(data: TerrainData) -> int:
	var store: Variant = data.site.get("trade_leg_receipts", {})
	return store.size() if store is Dictionary else 0

func _code(result: Dictionary) -> String:
	return str(result.get("code", ""))

func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: push_error("SITE_TRADE_NATION_LEG_TIMEOUT"); quit(1))
	fixture = Tent.Fixture.new()
	root.add_child(fixture)
	var data: TerrainData = fixture.terrain
	fixture.character.item_state = Runtime.new_item_state("person:1")
	fixture.npc.item_state = Runtime.new_item_state("person:2")
	fixture.army.combat_units[0].item_state = Runtime.new_item_state("person:3")
	if not _check(Runtime.trade_endpoint(data, "person:1").ok and Runtime.trade_endpoint(data, "person:2").ok and Runtime.trade_endpoint(data, "person:3").ok, "three original endpoints"): return
	var line: Array = ["person:1", "person:2", "person:3"]
	var pair: Array = ["person:1", "person:2"]

	# D-T9 / D-T7: a person pays coin it carries, for goods (positive person-to-person coin trade with receipts).
	_reset(data)
	_set_cargo(data, "person:1", {"coin": 5})
	_set_cargo(data, "person:2", {"grain": 2})
	var paid: Dictionary = Leg.commit(data, _refs(data, pair), [_move("person:2", "person:1", {"grain": 2})], [_pay("person:1", "person:2", 3)], "t-coin1", "", "", 10)
	if not _check(paid.ok, "carried coin pays for goods: " + _code(paid)): return
	if not _check(_cargo(data, "person:1") == {"coin": 2, "grain": 2} and _cargo(data, "person:2") == {"coin": 3}, "coin and goods move atomically"): return
	var store: Dictionary = data.site.trade_leg_receipts
	if not _check(store.has("t-coin1:person:1") and store.has("t-coin1:person:2"), "receipt per side written"): return
	if not _check(store["t-coin1:person:1"].kind == "trade" and store["t-coin1:person:1"].given == {"coin": 3} and store["t-coin1:person:1"].received == {"grain": 2}, "payer receipt records given coin and received goods"): return

	# Replay: the same trade_id returns the stored receipt and changes nothing.
	var before_replay: String = _snapshot(data)
	var replay: Dictionary = Leg.commit(data, _refs(data, pair), [_move("person:2", "person:1", {"grain": 2})], [_pay("person:1", "person:2", 3)], "t-coin1", "", "", 10)
	if not _check(replay.ok and replay.get("replayed", false) == true and _snapshot(data) == before_replay, "replay changes nothing"): return

	# D-T9 refusal: coin not carried (in no cargo) cannot be paid, and nothing changes.
	_reset(data)
	_set_cargo(data, "person:2", {"grain": 2})
	var before_uncarried: String = _snapshot(data)
	var uncarried: Dictionary = Leg.commit(data, _refs(data, pair), [_move("person:2", "person:1", {"grain": 2})], [_pay("person:1", "person:2", 3)], "t-coin2", "", "", 10)
	if not _check(_code(uncarried) == "EMPTY" and _snapshot(data) == before_uncarried and not _has_prefix(data, "t-coin2:"), "uncarried coin refused EMPTY, nothing changes, no receipt"): return

	# D-T7: coin inside goods is still refused (T0 rule).
	_set_cargo(data, "person:1", {"coin": 5})
	var before_goods: String = _snapshot(data)
	var coin_goods: Dictionary = Leg.commit(data, _refs(data, pair), [_move("person:1", "person:2", {"coin": 1})], [], "t-coin3", "", "", 10)
	if not _check(_code(coin_goods) == "INVALID" and _snapshot(data) == before_goods, "coin in goods refused, nothing changes"): return

	# Payers other than a carrying person (and the nation treasury) are refused before any state is read.
	var depot_pays: Dictionary = Leg.commit(data, _refs(data, pair), [_move("person:2", "person:1", {"grain": 2})], [_pay("depot", "person:1", 1)], "t-coin4", "", "", 10)
	if not _check(_code(depot_pays) == "COIN_PAYER" and _snapshot(data) == before_goods, "non-person coin payer refused"): return

	# Coin leg shape: zero amount and extra fields are refused.
	var zero_amount: Dictionary = Leg.commit(data, _refs(data, pair), [_move("person:2", "person:1", {"grain": 2})], [_pay("person:1", "person:2", 0)], "t-coin5", "", "", 10)
	var extra_field: Dictionary = Leg.commit(data, _refs(data, pair), [_move("person:2", "person:1", {"grain": 2})], [{"from": "person:1", "to": "person:2", "amount": 1, "x": 1}], "t-coin6", "", "", 10)
	if not _check(_code(zero_amount) == "INVALID" and _code(extra_field) == "INVALID" and _snapshot(data) == before_goods, "malformed coin legs refused, nothing changes"): return

	# TR-64 wiring: a nation side must be the bound treasury; a person named as the nation is refused.
	var site_id: String = str(data.site.get("id", ""))
	data.site["equipment_nations"] = {"n1": {"ransom_data": {"version": 1, "treasury": {"site_id": site_id, "feature_id": "wh1", "holder": "feature:wh1"}, "policy": {"authorized": true, "per_person": 35, "daily": 50, "reserve": 20, "authorized_by": 3}, "spent_day": -1, "spent": 0}}}
	data.site["stockpiles"] = {"wh1": {"nation_id": "n1", "cargo": {"coin": 60}}}
	var before_nation: String = _snapshot(data)
	var person_as_nation: Dictionary = Leg.commit(data, _refs(data, pair), [_move("person:2", "person:1", {"grain": 2})], [], "t-nation1", "n1", "person:1", 10)
	if not _check(_code(person_as_nation) == "NOT_NATION_SOURCE" and _snapshot(data) == before_nation, "person refused as nation side"): return
	var unlisted: Dictionary = Leg.commit(data, _refs(data, pair), [_move("person:2", "person:1", {"grain": 2})], [], "t-nation2", "n1", "feature:wh1", 10)
	if not _check(_code(unlisted) == "INVALID" and _snapshot(data) == before_nation, "treasury must be listed in refs"): return

	# Ledger rule (pure): the same daily ceiling as the ransom spend, reserve, authorization and day reset.
	var record: Dictionary = {"version": 1, "treasury": {"site_id": site_id, "feature_id": "wh1", "holder": "feature:wh1"}, "policy": {"authorized": true, "per_person": 35, "daily": 50, "reserve": 20, "authorized_by": 3}, "spent_day": -1, "spent": 0}
	var first: Dictionary = Leg.ledger_candidate(record, 10, 30, 60)
	if not _check(first.ok and int(first.spent) == 30 and int(first.spent_day) == 10, "ledger spend 30 of 60 on day 10"): return
	record.spent_day = 10
	record.spent = 30
	var daily_case: Dictionary = Leg.ledger_candidate(record, 10, 25, 60)
	if not _check(_code(daily_case) == "DAILY_CEILING", "daily ceiling is shared: 30 + 25 > 50; got code " + _code(daily_case)): return
	var reserve_case: Dictionary = Leg.ledger_candidate(record, 11, 45, 60)
	if not _check(_code(reserve_case) == "RESERVE", "reserve blocks a spend that leaves 15 under 20; got code " + _code(reserve_case)): return
	var reserve_edge: Dictionary = Leg.ledger_candidate(record, 11, 40, 60)
	if not _check(reserve_edge.ok, "reserve is inclusive: 60 - 40 = 20 is allowed; got code " + _code(reserve_edge)): return
	var next_day: Dictionary = Leg.ledger_candidate(record, 11, 25, 60)
	if not _check(next_day.ok and int(next_day.spent) == 25 and int(next_day.spent_day) == 11, "a new day resets the spend"): return
	var unauthorized: Dictionary = record.duplicate(true)
	unauthorized.policy.authorized = false
	unauthorized.policy.erase("authorized_by")
	if not _check(_code(Leg.ledger_candidate(unauthorized, 10, 1, 60)) == "NOT_AUTHORIZED", "unauthorized treasury spends nothing"): return
	if not _check(_code(Leg.ledger_candidate(record, 10, -1, 60)) == "INVALID", "negative spend refused"): return
	if not _check(_code(Leg.ledger_candidate({}, 10, 1, 60)) == "CORRUPT_STATE", "corrupt record refused"): return
	if not _check(Leg.ledger_candidate(unauthorized, 10, 0, 60).ok, "zero spend needs no authorization"): return

	# Store shape: the leg receipts validate, and an unknown field is refused (own validator, not the S4 one).
	if not _check(SiteStore.validate_trade_leg_receipts(data.site).ok, "leg receipts validate"): return
	var corrupt_leg: Dictionary = data.site.duplicate(true)
	corrupt_leg.trade_leg_receipts["t-coin1:person:1"]["extra"] = 1
	if not _check(not SiteStore.validate_trade_leg_receipts(corrupt_leg).ok, "unknown leg receipt field refused"): return
	if not _check(SiteStore.validate_trade_tax_receipts(data.site).ok, "legacy S4 store unaffected by leg receipts"): return

	fixture.close()
	fixture = null
	print("SITE_TRADE_NATION_LEG_OK")
	quit(0)

func _has_prefix(data: TerrainData, prefix: String) -> bool:
	var store: Variant = data.site.get("trade_leg_receipts", {})
	if not store is Dictionary: return false
	for key: Variant in store.keys():
		if str(key).begins_with(prefix): return true
	return false
