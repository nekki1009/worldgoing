extends SceneTree
## Data-only persistence/price contract. No R3, payment, release or actor transfer.
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Stocks = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Orders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
const Offices = preload("res://scripts/terrain_lab/site_offices.gd")
const Ransom = preload("res://scripts/terrain_lab/site_ransom_data.gd")
const OUT := "res://.godot-temp/site_r4_data_layer/contract.json"
var _failed := false
var _deadline := 0

class Errors extends Logger:
	var _mutex: Mutex = Mutex.new()
	var _first := ""
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _traces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING: return
		_mutex.lock()
		if _first.is_empty(): _first = "%s:%d %s %s %s" % [file, line, function, code, rationale]
		_mutex.unlock()
	func first_error() -> String:
		_mutex.lock()
		var result: String = _first
		_mutex.unlock()
		return result

var _errors: Errors = Errors.new()

func _initialize() -> void:
	OS.add_logger(_errors)
	_deadline = Time.get_ticks_msec() + 90000
	_run.call_deferred()

func _finalize() -> void:
	OS.remove_logger(_errors)

func _check(condition: bool, message: String = "") -> bool:
	if _failed: return false
	var error: String = _errors.first_error()
	if condition and error.is_empty() and Time.get_ticks_msec() <= _deadline: return true
	_failed = true
	push_error("SITE_R4_DATA_FAIL: " + message + " " + error)
	quit(1)
	return false

func _process(_delta: float) -> bool:
	_check(true, "original first-error/time guard")
	return false

func _data() -> TerrainData:
	var data: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.FOREST, 12345, {"size": Vector2i(48, 48)})
	if not _check(data != null, "terrain generation"): return null
	Env.initialize(data, "r4-data-contract")
	if not _check(true, "original environment initialize"): return null
	if not _check(int(data.site.inventory.get("coin", 0)) == 0, "initialization cannot mint coin"): return null
	for key: String in data.resource_base:
		Env.change(data, key, {"cleared": true, "remaining": 0})
		if not _check(true, "original resource change"): return null
	for y: int in range(2, 46):
		for x: int in range(2, 46):
			var index: int = data.index(Vector2i(x, y))
			data.height_levels[index] = 0
			data.site.terrain_changes[str(index)] = 0
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.ramp_edges.fill(0)
	data.water_kind.fill(0)
	data.water_body.fill(-1)
	data.surface_types.fill(TerrainData.Surface.GRASS)
	data.foundation.fill(80)
	data.groundwater.fill(80)
	data.site.inventory = {"wood": 300, "stone": 300, "tools": 4, "rope": 2}
	data.site.capacity = 5000
	data.site.depot_cell = data.index(Vector2i(4, 4))
	data.site.worker.cell = data.index(Vector2i(3, 4))
	data.site.worker_enabled = false
	var initialized: Dictionary = Runtime.initialize_item_storage(data.site)
	if not _check(initialized.ok, str(initialized)): return null
	Runtime.rebuild_terrain_edges(data)
	if not _check(true, "original terrain edge rebuild"): return null
	Env.rebuild_indexes(data)
	if not _check(true, "original derived indexes"): return null
	return data

func _warehouse(data: TerrainData) -> String:
	var options := {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	var layout: Dictionary = Runtime.building_cells(data, "warehouse", Vector2i(20, 20), Vector2i.ONE, options)
	if not _check(layout.ok, str(layout)): return ""
	var cells: Array[int] = []
	cells.assign(layout.cells)
	var cost: Dictionary = Runtime._building_cost(data, "warehouse", cells, options)
	if not _check(true, "original warehouse material quote"): return ""
	var inventory_before: Dictionary = data.site.inventory.duplicate(true)
	if not _check(Runtime.can_pay(inventory_before, cost) and Runtime.can_pay(inventory_before, {"tools": 1}), "authored warehouse materials and tool are sufficient"): return ""
	var built: Dictionary = Runtime.request_build(data, "warehouse", cells, Callable(), options)
	if not _check(built.ok, str(built)): return ""
	var inventory_expected: Dictionary = inventory_before.duplicate(true)
	for resource: String in cost:
		inventory_expected[resource] = int(inventory_before.get(resource, 0)) - int(cost[resource])
		if not _check(true, "warehouse debit expectation"): return ""
	if not _check(data.site.inventory == inventory_expected, "original request_build debits exactly the recipe once, preserving tools and unrelated stock"): return ""
	var key: String = str(built.feature)
	var feature: Dictionary = data.site.features[key]
	var worker: Dictionary = {"target": "", "action": "construct", "cell": int(feature.entrance), "mode": "work", "status": "", "progress": 0.0, "work_slot": -1}
	Runtime._feature_work(data, key, float(feature.work) + 1.0, Callable(), Callable(), worker, {}, 20, 1)
	if not _check(feature.stage == "complete", "original construction completes"): return ""
	var valid: Dictionary = Runtime.validate_feature_layout(data, feature)
	if not _check(valid.ok, str(valid)): return ""
	var storage: Dictionary = Stocks.ensure_storage(data, key, 1)
	if not _check(storage.ok, str(storage)): return ""
	return key

func _prices() -> bool:
	var decider := {"duty_id": "settlement.prison", "person_ref": {"site_id": "r4-data-contract", "person_id": 1}, "thrift": 50, "mercy": 50}
	for pair: Array in [["commoner", 10], ["officer", 15], ["head", 25], ["unknown", 10]]:
		var custody: Dictionary = {"version": 3, "rank_snapshot": str(pair[0])}
		var bytes: PackedByteArray = var_to_bytes([custody, decider])
		var price: Dictionary = Ransom.quote(custody, decider)
		if not _check(price.ok and price.coin == int(pair[1]), str(price)): return false
		if not _check(bytes == var_to_bytes([custody, decider]), "pure quote does not mutate input"): return false
	var legacy: Dictionary = Ransom.quote({"version": 1}, decider)
	if not _check(legacy.ok and legacy.coin == 10 and legacy.rank_source == "legacy_unknown", "legacy rank never backfilled"): return false
	for triple: Array in [[100, 0, 35], [0, 100, 15], [55, 50, 26], [45, 50, 24], [50, 55, 24], [50, 45, 26], [54, 50, 25], [46, 50, 25]]:
		decider.thrift = int(triple[0]); decider.mercy = int(triple[1])
		var quote: Dictionary = Ransom.quote({"version": 3, "rank_snapshot": "head"}, decider)
		if not _check(quote.ok and quote.coin == int(triple[2]), "endpoints and half-away rounding: " + str(quote)): return false
	decider.thrift = 0; decider.mercy = 100
	var low: Dictionary = Ransom.quote({"version": 3, "rank_snapshot": "commoner"}, decider)
	if not _check(low.ok and low.coin == 5, "lower clamp"): return false
	decider.thrift = 50; decider.mercy = 50
	var bad: Dictionary = Ransom.quote({"version": 3, "rank_snapshot": "forged"}, decider)
	if not _check(not bad.ok, "invalid saved capture tier rejected"): return false
	decider.person_ref.person_id = 1.5
	bad = Ransom.quote({"version": 3, "rank_snapshot": "head"}, decider)
	if not _check(not bad.ok, "fractional PersonRef rejected"): return false
	decider.person_ref.person_id = 1
	decider.duty_id = 7
	bad = Ransom.quote({"version": 3, "rank_snapshot": "head"}, decider)
	if not _check(not bad.ok, "integer duty_id is rejected before String comparison"): return false
	decider.duty_id = "captor"
	bad = Ransom.quote({"version": 3, "rank_snapshot": "head"}, decider)
	if not _check(not bad.ok, "initial captor is not current warden provenance"): return false
	return _check(true)

func _departure_boundary() -> bool:
	# Pure original preparation shape, not a created live Actor or travel commit.
	var nation: Dictionary = {"offices": Offices.default_offices("nation", 1, false), "members": [1], "standards": {}, "ransom_data": Ransom.empty_record()}
	nation.ransom_data.treasury = {"site_id": "source", "feature_id": "1", "holder": "feature:1"}
	var state: Dictionary = {"id": "source", "actors": {"p": {"person_id": 1, "faction_id": 1}}, "equipment_nations": {"n1": nation}}
	var identity := {"refs": {"person": {"1": {"type": "person", "namespace": "original", "lineage": 1}}}}
	var bytes: PackedByteArray = var_to_bytes(state)
	var refused: Dictionary = Orders.prepare_region_departure(state, {1: true}, {}, "r4-data-transfer", identity)
	if not _check(not refused.ok and str(refused.get("code", "")) == "TREASURY_TRANSFER_UNSUPPORTED" and var_to_bytes(state) == bytes, "bound treasury whole-nation departure refuses before publication"): return false
	var malformed: Dictionary = state.duplicate(true)
	malformed.equipment_nations.n1.ransom_data.treasury = 7
	refused = Orders.prepare_region_departure(malformed, {1: true}, {}, "r4-data-transfer", identity)
	if not _check(not refused.ok and str(refused.get("code", "")) == "CORRUPT_STATE", "malformed departure treasury is rejected before Dictionary access"): return false
	nation.erase("ransom_data")
	var ordinary: Dictionary = Orders.prepare_region_departure(state, {1: true}, {}, "r4-data-transfer", identity)
	if not _check(ordinary.ok and ordinary.moving_nations.has("n1") and ordinary.source_nations.is_empty(), "original nation without treasury still prepares departure"): return false
	var trial := {"military_head": 1, "members": [1], "standards": {}}
	return _check(Orders.valid_nations({"trial_team_r4": trial}, {}, {1: true}), "legacy unbound trial nation still validates")

func _run() -> void:
	if not _prices(): return
	if not _departure_boundary(): return
	var data: TerrainData = _data()
	if not _check(data != null and not _failed, "fixture propagation"): return
	var made: int = DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	if not _check(made == OK, "create bounded test output"): return
	var saved: Dictionary = Store.save(data, OUT)
	if not _check(saved.ok, "legacy no-coin no-nation save: " + str(saved)): return
	var loaded: Dictionary = Store.load_site(OUT)
	if not _check(loaded.ok, str(loaded)): return
	var legacy: TerrainData = loaded.data
	if not _check(int(legacy.site.inventory.get("coin", 0)) == 0 and legacy.site.get("equipment_nations", {}).is_empty(), "legacy unchanged and unauthorized"): return
	var key: String = _warehouse(data)
	if not _check(not key.is_empty() and not _failed, "warehouse helper propagation"): return
	var record: Dictionary = Ransom.empty_record()
	if not _check(not record.policy.authorized and record.treasury.is_empty(), "defaults create neither authority nor balance"): return
	# Explicit authored scenario data, not a runtime treasury-binding permission.
	Runtime.add_items(data.site.stockpiles[key].cargo, {"coin": 35})
	if not _check(true, "original String-indexed resource writer"): return
	for resource: Variant in data.site.stockpiles[key].cargo:
		if not _check(resource is String, "original writer stores canonical String resource keys"): return
	data.site.stockpiles[key].nation_id = "n1"
	record.treasury = {"site_id": str(data.site.id), "feature_id": key, "holder": Stocks.identity(key)}
	record.spent_day = floori(float(data.site.minute) / 1440.0)
	record.spent = 7
	data.site.equipment_nations = {"n1": {"offices": Offices.default_offices("nation", -1, false), "members": [], "standards": {}, "ransom_data": record}}
	var nation_bytes: PackedByteArray = var_to_bytes(data.site.equipment_nations)
	if not Orders.valid_nations(data.site.equipment_nations, data.site.item_definitions, {}, data.site):
		if not _treasury_diagnostic(data, key): return
	if not _check(Orders.valid_nations(data.site.equipment_nations, data.site.item_definitions, {}, data.site), "explicit reciprocal treasury schema"): return
	if not _check(nation_bytes == var_to_bytes(data.site.equipment_nations), "validation is read-only"): return
	saved = Store.save(data, OUT)
	if not _check(saved.ok, str(saved)): return
	loaded = Store.load_site(OUT)
	if not _check(loaded.ok, str(loaded)): return
	var restored: TerrainData = loaded.data
	if not _check(restored.site.stockpiles[key].cargo.coin == 35 and restored.site.equipment_nations.n1.ransom_data.spent == 7, "real coin and spending survive roundtrip without duplication/reset"): return
	if not _check(not restored.site.equipment_nations.n1.ransom_data.policy.authorized, "load cannot authorize spend"): return
	if not _check(restored.site.equipment_nations.n1.ransom_data.spent is int and restored.site.equipment_nations.n1.ransom_data.spent_day is int, "validated JSON counters normalize to integers"): return
	data.site.stockpiles[key].cargo["coin"] = 0
	var removal_before: PackedByteArray = var_to_bytes(data.site)
	var removed: Dictionary = Runtime.cancel_feature(data, key, Callable(), 1)
	if not _check(not removed.ok and str(removed.get("code", "")) == "BUSY" and var_to_bytes(data.site) == removal_before, "empty bound treasury cannot be demolished or orphan its saved reference"): return
	data.site.stockpiles[key].cargo["coin"] = 35
	var ordinary: TerrainData = _data()
	if not _check(ordinary != null and not _failed, "ordinary fixture propagation"): return
	var ordinary_key: String = _warehouse(ordinary)
	if not _check(not ordinary_key.is_empty() and not _failed, "ordinary warehouse propagation"): return
	removed = Runtime.cancel_feature(ordinary, ordinary_key, Callable(), 1)
	if not _check(removed.ok and not ordinary.site.features.has(ordinary_key) and not ordinary.site.stockpiles.has(ordinary_key), "ordinary empty warehouse remains removable"): return
	var pristine: Dictionary = data.site.duplicate(true)
	var file_before: PackedByteArray = FileAccess.get_file_as_bytes(OUT)
	for mode: String in ["missing_stock", "private_holder", "wrong_site", "orphan_claim", "two_nations", "trial_treasury", "dot_insert_key", "negative_coin", "fractional_coin", "over_capacity", "malformed_holder", "integer_claim", "integer_holder", "integer_feature", "authorized_policy", "fractional_day", "virtual_balance"]:
		data.site = pristine.duplicate(true)
		var nation: Dictionary = data.site.equipment_nations.n1
		match mode:
			"missing_stock": data.site.stockpiles.erase(key)
			"private_holder": nation.ransom_data.treasury.holder = "person:1"
			"wrong_site": nation.ransom_data.treasury.site_id = "other"
			"orphan_claim": data.site.equipment_nations = {}
			"two_nations": data.site.equipment_nations.n2 = nation.duplicate(true)
			"trial_treasury":
				data.site.equipment_nations = {"trial_team_r4": nation}
				data.site.stockpiles[key].nation_id = "trial_team_r4"
			"dot_insert_key":
				data.site.stockpiles[key].cargo = {}
				# Reproduce the diagnosed invalid producer; do not admit this key type.
				data.site.stockpiles[key].cargo.coin = 35
			"negative_coin": data.site.stockpiles[key].cargo["coin"] = -1
			"fractional_coin": data.site.stockpiles[key].cargo["coin"] = 1.5
			"over_capacity": data.site.stockpiles[key].cargo["coin"] = 1000000
			"malformed_holder": data.site.stockpiles[key].holder.holder = "feature:forged"
			"integer_claim": data.site.stockpiles[key].nation_id = 7
			"integer_holder": data.site.stockpiles[key].holder.holder = 7
			"integer_feature": nation.ransom_data.treasury.feature_id = 7
			"authorized_policy": nation.ransom_data.policy.authorized = true
			"fractional_day": nation.ransom_data.spent_day = 0.5
			"virtual_balance": nation.balance = 100
		var bytes: PackedByteArray = var_to_bytes(data.site)
		saved = Store.save(data, OUT)
		if not _check(not saved.ok, "original Store refuses " + mode + ": " + str(saved)): return
		if not _check(FileAccess.get_file_as_bytes(OUT) == file_before, "failed save retains valid file " + mode): return
		if not _check(var_to_bytes(data.site) == bytes, "failed preflight never mutates original state " + mode): return
	data.site = pristine
	var envelope: Variant = JSON.parse_string(file_before.get_string_from_utf8())
	if not _check(envelope is Dictionary and envelope.get("payload") is String, "original saved envelope"): return
	var payload: Variant = JSON.parse_string(envelope.payload)
	if not _check(payload is Dictionary and payload.get("state") is Dictionary, "original saved state"): return
	for mode: String in ["missing_stock", "integer_claim", "fractional_coin"]:
		var corrupt: Dictionary = payload.duplicate(true)
		match mode:
			"missing_stock": corrupt.state.stockpiles.erase(key)
			"integer_claim": corrupt.state.stockpiles[key].nation_id = 7
			"fractional_coin": corrupt.state.stockpiles[key].cargo["coin"] = 0.5
		var body: String = JSON.stringify(corrupt, "", true, true)
		var bad_path: String = OUT + "." + mode
		var file: FileAccess = FileAccess.open(bad_path, FileAccess.WRITE)
		if not _check(file != null, "open negative JSON fixture"): return
		file.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}))
		file.close()
		if not _check(true, "write negative JSON fixture"): return
		var refused: Dictionary = Store.load_site(bad_path)
		if not _check(not refused.ok and str(refused.get("code", "")) == "CORRUPT_SAVE", "checksum-valid corrupt load " + mode + ": " + str(refused)): return
		if not _check(FileAccess.get_file_as_bytes(OUT) == file_before and var_to_bytes(data.site) == var_to_bytes(pristine), "failed load preserves valid archive and original state"): return
	if not _check(Runtime.inventory_size({"coin": 21}) == 21 and Runtime.CARRY_CAPACITY == 20, "coin has ordinary finite carry load"): return
	await process_frame
	if not _check(true, "await and PASS propagation"): return
	print("SITE_R4_DATA_LAYER_PASS: no minted coin; original Store/stock/capacity and reciprocal single treasury references; unauthorized policy/spending persistence; immutable capture tier and pure half-away quote; corrupt save refusal preserves archive")
	quit(0)

func _treasury_diagnostic(data: TerrainData, key: String) -> bool:
	var original: PackedByteArray = var_to_bytes(data.site)
	var nation: Dictionary = data.site.equipment_nations.n1
	var stock: Dictionary = data.site.stockpiles[key]
	var feature: Dictionary = data.site.features[key]
	var offices_ok: bool = Offices.validate(nation.offices, "nation")
	if not _check(true, "diagnostic original office validator"): return false
	var refs_ok: bool = Orders.valid_organization_refs(data.site)
	if not _check(true, "diagnostic original organization refs"): return false
	var record_ok: bool = Ransom.valid_record(nation.ransom_data)
	if not _check(true, "diagnostic original ransom record validator"): return false
	var treasury_ok: bool = Ransom.valid_nations(data.site.equipment_nations, data.site)
	if not _check(true, "diagnostic original reciprocal validator"): return false
	var stocks_result: Dictionary = Stocks.validate(data.site)
	if not _check(true, "diagnostic original stock validator"): return false
	var resource_checks: Array[Dictionary] = []
	for resource: Variant in stock.cargo:
		resource_checks.append({"key": resource, "key_type": type_string(typeof(resource)),
			"key_is_String": resource is String, "key_is_StringName": resource is StringName,
			"value": stock.cargo[resource], "value_type": type_string(typeof(stock.cargo[resource])),
			"stock_runtime_whitelisted": Runtime.Env.ITEM_NAMES.has(resource),
			"stock_runtime_coin_whitelisted": Runtime.Env.ITEM_NAMES.has("coin"),
			"direct_env_whitelisted": Env.ITEM_NAMES.has(resource),
			"integer_0_to_1000000": Runtime._building_integer(stock.cargo[resource], 0, 1000000)})
		if not _check(true, "diagnostic original resource predicates"): return false
	var source_hashes := {}
	for path: String in ["res://scripts/terrain_lab/site_environment.gd", "res://scripts/terrain_lab/site_runtime.gd", "res://scripts/terrain_lab/site_equipment_orders.gd", "res://scripts/terrain_lab/site_stockpiles.gd", "res://scripts/terrain_lab/site_ransom_data.gd", "res://scripts/terrain_lab/site_offices.gd"]:
		var text: String = FileAccess.get_file_as_string(path)
		if not _check(not text.is_empty(), "diagnostic source read " + path): return false
		source_hashes[path] = text.sha256_text()
	var report: Dictionary = {"tag": "DIAG_ONLY_R4_TREASURY", "no_root_fix": true,
		"offices_ok": offices_ok, "organization_refs_ok": refs_ok, "ransom_record_ok": record_ok,
		"ransom_nations_ok": treasury_ok, "stocks_result": stocks_result,
		"nation_keys": nation.keys(), "members": nation.members, "offices": nation.offices,
		"record": nation.ransom_data, "site_id": data.site.id, "minute": data.site.minute,
		"stock": stock, "feature_id": key, "feature_kind": feature.kind, "feature_stage": feature.stage,
		"owner_faction": feature.get("owner_faction"), "building_grade": feature.get("building_grade"),
		"stock_capacity": Stocks.capacity(feature), "combined_load": Runtime.carried_size(stock.cargo, stock.holder),
		"resource_checks": resource_checks, "source_text_sha256": source_hashes}
	if not _check(var_to_bytes(data.site) == original, "diagnostic validators changed no original state"): return false
	print("DIAG_ONLY_R4_TREASURY " + JSON.stringify(report))
	return _check(true, "diagnostic output complete; original assertion still follows")
