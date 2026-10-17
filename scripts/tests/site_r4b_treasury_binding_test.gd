extends SceneTree
## R4b-1 treasury binding (pure candidates + command-level state, save/restore). No payment, coin movement or release.
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Stocks = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Orders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
const Offices = preload("res://scripts/terrain_lab/site_offices.gd")
const Ransom = preload("res://scripts/terrain_lab/site_ransom_data.gd")
const OUT := "res://.godot-temp/site_r4b_treasury_binding/contract.json"
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
	push_error("SITE_R4B_FAIL: " + message + " " + error)
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

func _run() -> void:
	var data: TerrainData = _data()
	if not _check(data != null and not _failed, "fixture propagation"): return
	var made: int = DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	if not _check(made == OK, "create bounded test output"): return
	var key: String = _warehouse(data)
	if not _check(not key.is_empty() and not _failed, "warehouse helper propagation"): return
	# Catalog: wired duty, civil by default, and a later duty so old saves gain a vacant seat.
	if not _check(Offices.duty_ids("nation").has("nation.ransom"), "nation.ransom is in the catalog"): return
	if not _check(Offices.default_class("nation.ransom") == "civil", "nation.ransom defaults to civil"): return
	if not _check(Offices.LATER_DUTIES.nation.has("nation.ransom"), "old saves lack the seat and still validate"): return
	var legacy: Dictionary = Offices.default_offices("nation", -1)
	var legacy_seat: String = str(legacy.duties["nation.ransom"])
	legacy.duties.erase("nation.ransom")
	var kept: Array = []
	for entry: Dictionary in legacy.positions:
		if str(entry.id) != legacy_seat: kept.append(entry)
	legacy.positions = kept
	legacy.revision = 3
	if not _check(Offices.validate(legacy, "nation"), "pre-R4b nation offices still validate"): return
	if not _check(Offices.ensure_catalog(legacy, "nation"), "catalog adds the vacant seat"): return
	var added: Dictionary = Offices.position(legacy, str(legacy.duties["nation.ransom"]))
	if not _check(not added.is_empty() and not bool(added.head) and int(added.holder) == -1 and str(added.office_class) == "civil", "vacant civil seat for nation.ransom"): return
	# A formal nation bound to the warehouse's faction (faction 1).
	data.site.equipment_nations = {"n1": {"offices": Offices.default_offices("nation", -1), "members": [], "standards": {}}}
	var prepared: Dictionary = Orders.prepare_faction_nation(data.site, "n1", 1)
	if not _check(bool(prepared.ok), "formal nation binds to faction 1: " + str(prepared)): return
	data.site = prepared.state
	var nation: Dictionary = data.site.equipment_nations.n1
	if not _check(not nation.has("ransom_data") and not data.site.stockpiles[key].has("nation_id"), "fresh formal nation has no treasury or claimed stock"): return
	# Authority: the nation.ransom seat is vacant and nobody is eligible; the head acts only when resolved so.
	var nobody := func(_person_id: int) -> bool: return false
	var vacant: Dictionary = Offices.resolve(nation.offices, "nation.ransom", -1, nobody)
	if not _check(not bool(vacant.ok) and str(vacant.code) == "OFFICE_PAUSED", "vacant nation.ransom with no acting head is refused: " + str(vacant)): return
	var acting: Dictionary = Offices.resolve(nation.offices, "nation.ransom", 5, nobody, true)
	if not _check(bool(acting.ok) and int(acting.decider) == 5, "head acts for vacant nation.ransom"): return
	# Candidate binding: exact identity, no live mutation, and each refusal.
	var bound: Dictionary = Ransom.bind_candidate(data.site, "n1", nation, key)
	if not _check(bool(bound.ok), "complete own warehouse binds: " + str(bound)): return
	var record: Dictionary = bound.nation.ransom_data
	if not _check(record.treasury.size() == 3 and str(record.treasury.feature_id) == key and str(record.treasury.holder) == "feature:" + key, "exact holder identity"): return
	if not _check(not data.site.stockpiles[key].has("nation_id") and not nation.has("ransom_data"), "candidate never mutates the live state"): return
	var foreign: Dictionary = nation.duplicate(true)
	foreign.faction_id = 2
	if not _check(str(Ransom.bind_candidate(data.site, "n1", foreign, key).code) == "FOREIGN_FACTION", "foreign faction warehouse refused"): return
	if not _check(str(Ransom.bind_candidate(data.site, "trial_team_1", nation, key).code) == "NO_FORMAL_NATION", "trial team nation refused"): return
	var nofaction: Dictionary = nation.duplicate(true)
	nofaction.erase("faction_id")
	if not _check(str(Ransom.bind_candidate(data.site, "n1", nofaction, key).code) == "NO_FORMAL_NATION", "nation without faction refused"): return
	var staged: Dictionary = data.site.duplicate(true)
	staged.features[key].stage = "build"
	if not _check(str(Ransom.bind_candidate(staged, "n1", nation, key).code) == "NOT_WAREHOUSE", "incomplete warehouse refused"): return
	staged = data.site.duplicate(true)
	staged.features[key].kind = "barracks"
	if not _check(str(Ransom.bind_candidate(staged, "n1", nation, key).code) == "NOT_WAREHOUSE", "non-warehouse refused"): return
	staged = data.site.duplicate(true)
	staged.stockpiles[key].nation_id = "n2"
	if not _check(str(Ransom.bind_candidate(staged, "n1", nation, key).code) == "STOCK_CLAIMED", "second nation cannot claim the same stock"): return
	var already: Dictionary = nation.duplicate(true)
	already.ransom_data = record.duplicate(true)
	if not _check(str(Ransom.bind_candidate(data.site, "n1", already, key).code) == "TREASURY_BOUND", "bound treasury is not rebound"): return
	# Commit the candidate, then save and restore through Store.
	nation.ransom_data = record
	data.site.stockpiles[key].nation_id = "n1"
	var saved: Dictionary = Store.save(data, OUT)
	if not _check(saved.ok, str(saved)): return
	var loaded: Dictionary = Store.load_site(OUT)
	if not _check(loaded.ok, str(loaded)): return
	var live: Dictionary = loaded.data.site.equipment_nations.n1
	if not _check(str(live.ransom_data.treasury.feature_id) == key and str(live.ransom_data.treasury.holder) == "feature:" + key, "treasury binding survives Store save/load"): return
	if not _check(str(loaded.data.site.stockpiles[key].nation_id) == "n1", "claimed stock survives Store save/load"): return
	if not _check(int(live.ransom_data.spent) == 0 and int(live.ransom_data.spent_day) == -1, "binding spends nothing"): return
	# Policy: ceilings only, bounded, and authorized is never set by this command.
	var rejected: Array = [[36, 50, 20], [0, 50, 20], [35, 0, 20], [35, 50, -1], [35, 1000001, 20]]
	for values: Array in rejected:
		var refused: Dictionary = Ransom.policy_candidate(loaded.data.site, "n1", live, int(values[0]), int(values[1]), int(values[2]))
		if not _check(not bool(refused.ok) and str(refused.code) == "INVALID_POLICY", "out-of-range policy refused: %s" % str(values)): return
	var policy: Dictionary = Ransom.policy_candidate(loaded.data.site, "n1", live, 20, 60, 10)
	if not _check(bool(policy.ok), "in-range policy accepted: " + str(policy)): return
	var policy_record: Dictionary = policy.nation.ransom_data
	if not _check(int(policy_record.policy.per_person) == 20 and int(policy_record.policy.daily) == 60 and int(policy_record.policy.reserve) == 10 and not bool(policy_record.policy.authorized), "policy stores numbers only; authorized stays false"): return
	if not _check(policy_record.treasury == live.ransom_data.treasury and policy_record.keys().size() == 5 and not policy.nation.has("balance"), "no virtual balance; treasury untouched"): return
	var forged: Dictionary = live.ransom_data.duplicate(true)
	forged.policy.authorized = true
	if not _check(not Ransom.valid_record(forged), "raw authorized=true is still refused without a command"): return
	# Every refused candidate leaves the state byte-identical.
	var before: PackedByteArray = var_to_bytes(loaded.data.site.equipment_nations)
	Ransom.bind_candidate(loaded.data.site, "trial_team_1", live, key)
	Ransom.policy_candidate(loaded.data.site, "n1", live, 36, 50, 20)
	if not _check(before == var_to_bytes(loaded.data.site.equipment_nations), "refused candidates leave the state byte-identical"): return
	print("SITE R4B TREASURY BINDING PASS: nation.ransom wired (civil, later duty); head acts for vacant seat; exact holder bound to one complete own warehouse; foreign/trial/unformal/incomplete/non-warehouse/claimed/rebound refused; Store save/load keeps binding with no payment; policy bounded with authorized false; refusals byte-identical.")
	quit(0)
