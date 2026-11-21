extends SceneTree
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Trade = preload("res://scripts/terrain_lab/site_trade.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Stocks = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const Tent = preload("res://scripts/tests/site_tent_logistics_test.gd")

## Nekki 2026-11-06 "A": a crowd person may trade in peace; a crowd person in a fight may not (BUSY).
class FightingCrowd extends Tent.CrowdFixture:
	func person_fighting(_identity: int) -> bool: return true
var fixture: Variant

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> bool:
	if condition: return true
	push_error("SITE_TRADE_EXCHANGE_FAIL: " + message)
	quit(1)
	return false

func _goods(resources: Dictionary = {}, ids: Array = []) -> Dictionary:
	return {"resources": resources, "item_ids": ids}

func _ref(data: TerrainData, holder_id: String) -> Dictionary:
	var endpoint: Dictionary = Runtime.trade_endpoint(data, holder_id)
	return {"holder": holder_id, "expected_version": int(endpoint.holder.version)} if endpoint.ok else {"holder": holder_id, "expected_version": 0}

func _snapshot() -> String:
	return JSON.stringify([fixture.terrain.site, fixture.holder(), fixture.cargo(), fixture.character.item_state], "", true)

func _reject(a: Dictionary, b: Dictionary, a_gives: Dictionary, b_gives: Dictionary, code: String = "") -> bool:
	var original_holder: Dictionary = fixture.holder()
	var original_cargo: Dictionary = fixture.cargo()
	var actor_holder: Dictionary = fixture.character.item_state
	var actor_cargo: Dictionary = fixture.terrain.site.manual.cargo
	var endpoints: Array[Dictionary] = []
	for ref: Dictionary in [a, b]:
		var endpoint: Dictionary = Runtime.trade_endpoint(fixture.terrain, str(ref.get("holder", "")))
		if endpoint.get("ok", false): endpoints.append({"id": ref.holder, "holder": endpoint.holder, "cargo": endpoint.cargo})
	var before: String = _snapshot()
	var result: Dictionary = Runtime.exchange_items(fixture.terrain, a, b, a_gives, b_gives)
	var unchanged: bool = _snapshot() == before
	var references_unchanged: bool = is_same(original_holder, fixture.holder()) and is_same(original_cargo, fixture.cargo()) \
		and is_same(actor_holder, fixture.character.item_state) and is_same(actor_cargo, fixture.terrain.site.manual.cargo)
	for endpoint: Dictionary in endpoints:
		var current: Dictionary = Runtime.trade_endpoint(fixture.terrain, str(endpoint.id))
		references_unchanged = references_unchanged and current.get("ok", false) \
			and is_same(endpoint.holder, current.get("holder")) and is_same(endpoint.cargo, current.get("cargo"))
	return _check(not result.ok and (code.is_empty() or result.code == code) and unchanged and references_unchanged, "rejection atomicity %s (ok=%s actual=%s unchanged=%s references=%s)" % [code, result.ok, result.get("code", ""), unchanged, references_unchanged])

func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: push_error("SITE_TRADE_EXCHANGE_TIMEOUT"); quit(1))
	fixture = Tent.Fixture.new()
	root.add_child(fixture)
	var data: TerrainData = fixture.terrain
	fixture.character.item_state = Runtime.new_item_state("person:1")
	fixture.npc.item_state = Runtime.new_item_state("person:2")
	fixture.army.combat_units[0].item_state = Runtime.new_item_state("person:3")
	var a_cargo: Dictionary = fixture.cargo()
	var b_cargo: Dictionary = data.site.manual.cargo
	a_cargo.clear()
	a_cargo.merge({"wood": 5})
	b_cargo.clear()
	b_cargo.merge({"grain": 2})
	if not _check(fixture.actions._person(3).body is Dictionary and fixture.actions._person(1).body is TerrainTestCharacter and Runtime.trade_endpoint(data, "person:1").ok and Runtime.trade_endpoint(data, "person:2").ok, "original Army Dictionary and Actor Node endpoints"): return
	var a: Dictionary = _ref(data, "person:3")
	var b: Dictionary = _ref(data, "person:1")
	var original_a: Dictionary = fixture.holder()
	var original_b: Dictionary = fixture.character.item_state
	var before: String = _snapshot()
	var guard_calls: Array[int] = [0]
	data.item_transfer_guard = func(source: Dictionary, destination: Dictionary, _resources: Dictionary, _ids: Array) -> Dictionary:
		if not is_same(source, original_a) and not is_same(source, original_b): return Runtime.fail("INVALID")
		if not is_same(destination, original_a) and not is_same(destination, original_b): return Runtime.fail("INVALID")
		guard_calls[0] += 1
		return Runtime.ok()
	var preview: Dictionary = Runtime.exchange_items(data, a, b, _goods({"wood": 5}), _goods({"grain": 2}), true)
	if not _check(preview.ok and guard_calls[0] == 2 and _snapshot() == before, "TR01/70 preview original dictionaries and two pure guards"): return
	guard_calls[0] = 0
	var moved: Dictionary = Runtime.exchange_items(data, a, b, _goods({"wood": 5}), _goods({"grain": 2}))
	if not _check(moved.ok and guard_calls[0] == 2 and a_cargo == {"grain": 2} and b_cargo == {"wood": 5}, "TR01 simultaneous true resources"): return
	if not _check(is_same(a_cargo, fixture.cargo()) and is_same(b_cargo, data.site.manual.cargo) and fixture.holder().version == int(a.expected_version) + 1 and fixture.character.item_state.version == int(b.expected_version) + 1, "TR01 original identity and each version+1"): return
	data.item_transfer_guard = Callable()
	if not _reject(a, b, _goods({"grain": 1}), _goods({"wood": 1}), "STALE_SOURCE"): return
	a_cargo.clear()
	a_cargo.merge({"wood": 20})
	b_cargo.clear()
	b_cargo.merge({"grain": 6})
	a = _ref(data, "person:3")
	b = _ref(data, "person:1")
	before = _snapshot()
	var old_preview: Dictionary = Runtime.transfer_items(data, original_b, b_cargo, original_a, a_cargo, {"grain": 5}, [], int(b.expected_version), int(a.expected_version), 20, false, true)
	if not _check(not old_preview.ok and old_preview.code == "STORAGE_FULL" and _snapshot() == before, "TR02 retain one-way full-holder refusal"): return
	if not _reject(a, b, _goods({"wood": 5}), _goods({"grain": 6}), "STORAGE_FULL"): return
	if not _check(Runtime.exchange_items(data, a, b, _goods({"wood": 5}), _goods({"grain": 5})).ok and Runtime.carried_load(data.site, a_cargo, original_a) == 20.0, "TR02 full-holder net exchange"): return
	a = _ref(data, "person:3")
	b = _ref(data, "person:1")
	if not _reject(a, b, _goods({"wood": 100}), _goods({"grain": 1}), "EMPTY"): return
	if not _reject(a, b, _goods({"wood": 0}), _goods({"grain": 1}), "INVALID"): return
	if not _reject(a, b, _goods({"wood": 1.0}), _goods({"grain": 1}), "INVALID"): return
	if not _reject(a, b, _goods({"wood": 1000001}), _goods({"grain": 1}), "INVALID"): return
	if not _reject(a, b, _goods({"unknown": 1}), _goods({"grain": 1}), "INVALID"): return
	if not _reject(a, b, _goods({"coin": 1}), _goods({"grain": 1}), "INVALID"): return
	if not _check(Runtime.Env.ITEM_NAMES.has("coin"), "TR78 real R4 coin registration context"): return
	var wood_before_coin: int = int(a_cargo.wood)
	a_cargo["wood"] = wood_before_coin - 1
	a_cargo[&"coin"] = 1
	b_cargo["coin"] = 1
	if not _reject(a, b, _goods({&"coin": 1}), _goods({"grain": 1}), "INVALID"): return
	if not _reject(a, b, _goods({"wood": 1, &"coin": 1}), _goods({"grain": 1}), "INVALID"): return
	if not _reject(a, b, _goods({"wood": 1}), _goods({"coin": 1}), "INVALID"): return
	a_cargo.erase(&"coin")
	b_cargo.erase("coin")
	a_cargo["wood"] = wood_before_coin
	if not _reject(a, b, _goods(), _goods({"grain": 1}), "EMPTY"): return
	if not _reject(a, a, _goods({"wood": 1}), _goods({"wood": 1}), "INVALID"): return
	var fake: Dictionary = a.duplicate()
	fake.capacity = 1000000
	fake.cargo = a_cargo.duplicate()
	fake.item_state = original_a.duplicate(true)
	if not _reject(fake, b, _goods({"wood": 1}), _goods({"grain": 1}), "INVALID"): return
	var saved_b: Dictionary = data.site.manual.cargo
	data.site.manual.cargo = a_cargo
	if not _reject(a, b, _goods({"wood": 1}), _goods({"wood": 1}), "INVALID"): return
	data.site.manual.cargo = saved_b
	fixture.character.ammo_inventory = saved_b
	a_cargo.clear()
	a_cargo.merge({"wood": 19})
	b_cargo.clear()
	b_cargo.merge({"grain": 2})
	data.site.person_supply = {"3": {"open_rations": 0.5}}
	if not _reject(a, b, _goods({"wood": 1}), _goods({"grain": 2}), "STORAGE_FULL"): return
	data.site.erase("person_supply")
	data.item_transfer_guard = func(_source: Dictionary, _destination: Dictionary, _resources: Dictionary, _ids: Array) -> Dictionary: return Runtime.fail("GUARD_REFUSED")
	if not _reject(a, b, _goods({"wood": 1}), _goods({"grain": 1}), "GUARD_REFUSED"): return
	var mutated: Array[bool] = [false]
	data.item_transfer_guard = func(_source: Dictionary, _destination: Dictionary, _resources: Dictionary, _ids: Array) -> Dictionary:
		if not mutated[0]:
			original_b.version = int(original_b.version) + 1
			mutated[0] = true
		return Runtime.ok()
	var old_goods: Array = [a_cargo.duplicate(), b_cargo.duplicate()]
	var stale: Dictionary = Runtime.exchange_items(data, a, b, _goods({"wood": 1}), _goods({"grain": 1}))
	if not _check(not stale.ok and stale.code == "STALE_SOURCE" and [a_cargo, b_cargo] == old_goods, "TR70 guard version change refuses exchange (external guard change retained)"): return
	data.item_transfer_guard = Callable()
	a = _ref(data, "person:3")
	b = _ref(data, "person:1")
	var prepared: Dictionary = Runtime.prepare_item_exchange(data, a, b, _goods({"wood": 1}), _goods({"grain": 1}))
	if not _check(prepared.ok, "prepare original exchange"): return
	fixture.army.combat_units[0].item_state = original_a.duplicate(true)
	before = _snapshot()
	if not _check(not Runtime.publish_item_exchange(prepared).ok and _snapshot() == before, "TR70 replaced same-version original holder refused"): return
	fixture.army.combat_units[0].item_state = original_a
	prepared = Runtime.prepare_item_exchange(data, a, b, _goods({"wood": 1}), _goods({"grain": 1}))
	if not _check(prepared.ok, "prepare immutable selected resources"): return
	prepared.a_gives.resources.wood = 2
	before = _snapshot()
	if not _check(not Runtime.publish_item_exchange(prepared).ok and _snapshot() == before, "TR70 changed prepared selection refused"): return
	before = _snapshot()
	var all_resources: Dictionary = a_cargo
	var take_all: Dictionary = Runtime.exchange_items(data, a, b, _goods(all_resources), _goods({"grain": 1}), true)
	if not _check(take_all.ok and is_same(all_resources, a_cargo) and _snapshot() == before, "TR70 source take-all alias preview preserves original data"): return
	if not _physical_endpoint_checks(data): return
	a_cargo.clear()
	b_cargo.clear()
	b_cargo.merge({"grain": 6})
	var bow: Dictionary = Runtime.create_equipment(data, original_a, "weapon:bow_01", {"slot": "weapon", "asset": "bow_01", "tint": [1.0, 1.0, 1.0, 1.0]}, 3)
	if not _check(bow.ok, "TR03 original un-equipped bow"): return
	a = _ref(data, "person:3")
	b = _ref(data, "person:1")
	if not _reject(a, b, _goods({}, [bow.item_id, bow.item_id]), _goods({"grain": 6}), "INVALID"): return
	if not _reject(a, b, _goods({}, ["missing"]), _goods({"grain": 6}), "INVALID"): return
	# The original holder contract requires String slot keys, not dot-assigned StringName keys.
	original_a.equipped["weapon"] = bow.item_id
	if not _check(original_a.equipped.keys()[0] is String and Runtime._item_holder_shape(original_a) and Runtime.trade_endpoint(data, "person:3").ok, "TR07 legal original equipped holder before unsupported rejection"): return
	if not _reject(a, b, _goods({}, [bow.item_id]), _goods({"grain": 6}), "UNSUPPORTED"): return
	original_a.equipped.clear()
	if not _check(Runtime.exchange_items(data, a, b, _goods({}, [bow.item_id]), _goods({"grain": 6})).ok and data.site.item_records[bow.item_id].holder == "person:1" and original_b.item_ids.has(bow.item_id) and not original_a.item_ids.has(bow.item_id), "TR03 one real item ownership commit"): return
	a = _ref(data, "person:3")
	b = _ref(data, "person:1")
	data.site.vehicles["1"] = {"id": "1", "kind": "ship", "holder": Runtime.new_item_state("vehicle:1"), "cargo": {}}
	if not _reject(a, {"holder": "vehicle:1", "expected_version": 0}, _goods({"grain": 1}), _goods({"wood": 1}), "UNSUPPORTED"): return
	data.site.vehicles.erase("1")
	fixture.army.combat_units[0].embarked_vehicle_id = "missing"
	if not _reject(a, b, _goods({"grain": 1}), _goods({}, [bow.item_id]), "UNSUPPORTED"): return
	fixture.army.combat_units[0].erase("embarked_vehicle_id")
	fixture.crowd_site = FightingCrowd.new()
	if not _reject(a, b, _goods({"grain": 1}), _goods({}, [bow.item_id]), "BUSY"): return
	fixture.crowd_site = null
	if not _reject(a, {"holder": "team_supply:1", "expected_version": 0}, _goods({"grain": 1}), _goods({"grain": 1}), "UNSUPPORTED"): return
	if not _schema_checks(data): return
	fixture.close()
	fixture = null
	if not _save_checks(): return
	print("SITE_TRADE_EXCHANGE_PASS: TR01-08/TR70; real original people, net capacity/open food, immutable preview, guards/rebinding, unique items, passive Store schema and preserved legacy save; no T1 action/UI admission")
	quit(0)

func _physical_endpoint_checks(data: TerrainData) -> bool:
	data.site.inventory.merge({"wood": 100, "stone": 20, "rope": 20}, true)
	var options: Dictionary = {"owner_faction": 0}
	var layout: Dictionary = Runtime.building_cells(data, "warehouse", Vector2i(7, 2), Vector2i.ONE, options)
	if not _check(layout.ok, "TR70 original warehouse layout"): return false
	var cells: Array[int] = []
	cells.assign(layout.cells)
	var built: Dictionary = Runtime.request_build(data, "warehouse", cells, Callable(), options)
	if not _check(built.ok, "TR70 original warehouse creation"): return false
	var key: String = str(built.feature)
	var feature: Dictionary = data.site.features[key]
	var task: Dictionary = {"target": "", "action": "construct", "cell": int(feature.entrance), "mode": "work", "status": "", "progress": 0.0, "work_slot": -1}
	Runtime._feature_work(data, key, float(feature.work), Callable(), Callable(), task, {}, 20, 0)
	if not _check(feature.stage == "complete" and Runtime.validate_feature_layout(data, feature).ok and Stocks.ensure_storage(data, key, 0).ok, "TR70 original complete storage owner"): return false
	var stock: Dictionary = Stocks.storage(data, key)
	stock.cargo.grain = 4
	var a: Dictionary = _ref(data, "person:3")
	var b: Dictionary = _ref(data, "feature:" + key)
	var endpoint: Dictionary = Runtime.trade_endpoint(data, str(b.holder))
	if not _check(endpoint.ok and endpoint.capacity == Stocks.capacity(feature) and is_same(endpoint.holder, stock.holder) and is_same(endpoint.cargo, stock.cargo), "TR70 real feature dictionaries/capacity"): return false
	if not _check(Runtime.exchange_items(data, a, b, _goods({"wood": 1}), _goods({"grain": 1}), true).ok, "TR70 usable feature preview"): return false
	var hp: float = float(feature.parts.body.hp)
	feature.parts.body.hp = 0.0
	if not _check(Stocks.stock_endpoint(data, key).withdraw_only, "TR70 damaged original endpoint is withdraw_only"): return false
	if not _reject(a, b, _goods({"wood": 1}), _goods({"grain": 1}), "BUSY"): return false
	feature.parts.body.hp = hp
	feature.pending_build = {}
	if not _reject(a, b, _goods({"wood": 1}), _goods({"grain": 1}), "BUSY"): return false
	feature.erase("pending_build")
	feature.repair = {}
	if not _reject(a, b, _goods({"wood": 1}), _goods({"grain": 1}), "BUSY"): return false
	feature.erase("repair")
	feature.stage = "construct"
	if not _reject(a, b, _goods({"wood": 1}), _goods({"grain": 1}), "NO_TARGET"): return false
	feature.stage = "complete"
	data.site.vehicles["2"] = {"id": "2", "kind": "cart", "cell": data.index(Vector2i(3, 5)), "facing": [1, 0],
		"team_id": 1, "operator_id": 0, "holder": Runtime.new_item_state("vehicle:2"), "cargo": {"wood": 50}, "move": {}, "stop_pending": false,
		"travel_patients": {"version": 1, "person_ids": [3], "reserved_capacity": 50}}
	var cart: Dictionary = data.site.vehicles["2"]
	fixture.army.combat_units[0].ko = 10.0
	var original_patients: Dictionary = {3: {"team": 1, "body": fixture.army.combat_units[0]}}
	if not _check(Store._validate_travel_patients(cart, original_patients, {}).ok, "TR70 original complete one-patient manifest"): return false
	endpoint = Runtime.trade_endpoint(data, "vehicle:2")
	if not _check(endpoint.ok and endpoint.capacity == SiteVehicleTransport.capacity_of(cart) - 50 and endpoint.capacity == 50 \
		and is_same(endpoint.holder, cart.holder) and is_same(endpoint.cargo, cart.cargo), "TR70 real cart capacity preserves patient reserve"): return false
	data.site.inventory.clear()
	data.site.inventory.grain = 10
	a = _ref(data, "vehicle:2")
	b = _ref(data, "depot")
	if not _reject(a, b, _goods({"wood": 5}), _goods({"grain": 6}), "STORAGE_FULL"): return false
	if not _check(Runtime.exchange_items(data, a, b, _goods({"wood": 5}), _goods({"grain": 5})).ok \
		and Runtime.carried_load(data.site, cart.cargo, cart.holder) == 50.0 and cart.travel_patients.reserved_capacity == 50, "TR70 equal net cart exchange preserves real reserve"): return false
	a = _ref(data, "vehicle:2")
	b = _ref(data, "depot")
	cart.move = {"fixture_move": true}
	if not _reject(a, b, _goods({"wood": 1}), _goods({"grain": 1}), "BUSY"): return false
	cart.move = {}
	cart.stop_pending = true
	if not _reject(a, b, _goods({"wood": 1}), _goods({"grain": 1}), "BUSY"): return false
	cart.stop_pending = false
	cart.kind = "wagon"
	cart.erase("travel_patients")
	fixture.army.combat_units[0].ko = 0.0
	endpoint = Runtime.trade_endpoint(data, "vehicle:2")
	if not _check(endpoint.ok and endpoint.capacity == SiteVehicleTransport.capacity_of(cart) and endpoint.capacity == 300, "TR70 original wagon capacity"): return false
	return true

func _schema_checks(data: TerrainData) -> bool:
	var state: Dictionary = data.site.duplicate(true)
	state.actors = {"player": {"person_id": 1, "item_state": fixture.character.item_state.duplicate(true)},
		"npc": {"person_id": 3, "item_state": fixture.holder().duplicate(true)}}
	state.armies = []
	state.trade = Trade.new_snapshot(str(state.id), 4.0)
	state.trade.next_seq = 3
	var offer_id: String = str(state.id) + ":1"
	state.trade.offers[offer_id] = {"revision": 1, "a": _ref(data, "person:3"), "b": _ref(data, "person:1"),
		"a_gives": _goods({"grain": 1}), "b_gives": _goods({}, [str(fixture.character.item_state.item_ids[0])]),
		"a_representative": 3, "b_representative": 1, "created_action": 0.0, "expires_action": 60.0, "accepted_a": true, "accepted_b": true}
	var job_id: String = str(state.id) + ":2"
	state.trade.jobs[job_id] = {"offer_id": offer_id, "offer_revision": 1, "started_action": 0.0,
		"elapsed": 2.2, "required": 2.2, "pending": true, "a_cell": [4, 5], "b_cell": [1, 1], "a_hit": 0, "b_hit": 0}
	if not _check(Trade.validate_snapshot(state, 4.0).ok, "T0 complete passive offer/job candidate"): return false
	var wire: Dictionary = JSON.parse_string(JSON.stringify(state))
	if not _check(Trade.validate_snapshot(wire, 4.0).ok, "T0 JSON integer-valued wire"): return false
	Trade.normalize_snapshot(wire)
	if not _check(wire.trade.jobs[job_id].offer_revision is int and wire.trade.offers[offer_id].a.expected_version is int, "T0 normalize only validated candidate"): return false
	for revision: Variant in [true, "1", 1.5, INF, -1]:
		var corrupt: Dictionary = state.duplicate(true)
		corrupt.trade.jobs[job_id].offer_revision = revision
		if not _check(not Trade.validate_snapshot(corrupt).ok, "job revision rejects bool/string/fraction/nonfinite/negative"): return false
	for reason: String in ["version", "future", "negative", "reference", "unknown_field", "duplicate_rep", "duplicate_job", "required"]:
		var corrupt: Dictionary = state.duplicate(true)
		match reason:
			"version": corrupt.trade.version = 99
			"future": corrupt.trade.jobs[job_id].started_action = 5.0
			"negative": corrupt.trade.jobs[job_id].elapsed = -1.0
			"reference": corrupt.trade.offers[offer_id].a.holder = "person:999"
			"unknown_field": corrupt.trade.balance = 99
			"duplicate_rep": corrupt.trade.offers[offer_id].b_representative = 3
			"duplicate_job": corrupt.trade.jobs[str(state.id) + ":1"] = corrupt.trade.jobs[job_id].duplicate(true)
			"required": corrupt.trade.jobs[job_id].required = 2.1
		if not _check(not Trade.validate_snapshot(corrupt).ok, "T0 schema refusal " + reason): return false
	var stale: Dictionary = state.duplicate(true)
	stale.actors.npc.item_state.version = int(stale.actors.npc.item_state.version) + 1
	if not _check(Trade.validate_snapshot(stale).ok, "legal stale offer remains passive; T1 rebind/cancel is not enabled"): return false
	var concessions: Dictionary = state.duplicate(true)
	for index: int in range(257):
		var key: String = JSON.stringify(["person:" + str(index + 10), "person:1", 0])
		concessions.trade.concessions[key] = {"a": "person:" + str(index + 10), "b": "person:1", "day": 0, "count": 4}
	if not _check(not Trade.validate_snapshot(concessions).ok, "TR77 bounded daily pair table"): return false
	return true

func _save_checks() -> bool:
	var data: TerrainData = TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(data, "trade-save-fixture")
	if not _check(Runtime.initialize_item_storage(data.site).ok, "TR05 old item state"): return false
	var path: String = "res://.godot-temp/site_trade_t0/legacy.json"
	if not _check(Store.save(data, path).ok, "TR05 save legacy without trade"): return false
	var loaded: Dictionary = Store.load_site(path)
	if not _check(loaded.ok and not loaded.data.site.has("trade"), "TR05 missing trade stays missing"): return false
	data.site.trade = Trade.new_snapshot(str(data.site.id), 0.0)
	if not _check(Store.save(data, path).ok, "T0 save empty passive trade"): return false
	var hash_before: String = FileAccess.get_sha256(path)
	loaded = Store.load_site(path)
	if not _check(loaded.ok and loaded.data.site.trade == data.site.trade, "T0 Store readback"): return false
	data.site.trade.version = 99
	if not _check(not Store.save(data, path).ok and FileAccess.get_sha256(path) == hash_before, "T0 invalid trade preserves existing save"): return false
	return true
