extends SceneTree
## CANDIDATE / NOT_RUN. Copy to scripts/tests only after the P1 gate and root instruction.
## Original Runtime/Environment transactions; test profiles are fixture genesis only.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
var checks := 0
var failed := false
var finished := false

func _initialize() -> void:
	create_timer(45.0, true).timeout.connect(func() -> void: _finish(false, "bounded deadline"))
	_run.call_deferred()

func _check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failed = true
		push_error("FIRE_RUNTIME_FAIL: " + label)
	return value

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	print("SITE_FIRE_RUNTIME_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	quit(0 if ok else 1)

func _data() -> TerrainData:
	var data := TerrainData.new()
	data.allocate(Vector2i(64, 64))
	data.spawn_cell = Vector2i(3, 3)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	Env.initialize(data, "p2-runtime-test")
	data.resource_base.clear()
	data.site.changes.clear()
	data.height_levels.fill(0)
	data.ramp_edges.fill(0)
	data.water_kind.fill(0)
	data.water_body.fill(-1)
	data.surface_types.fill(TerrainData.Surface.GRASS)
	data.foundation.fill(80)
	data.fertility.fill(60)
	data.moisture.fill(0)
	data.groundwater.fill(80)
	data.drainage.fill(70)
	for item: String in Env.ITEM_NAMES: data.site.inventory[item] = 1000
	data.site.capacity = 100000
	_check(Runtime.initialize_item_storage(data.site).ok, "Original item registry")
	Env.rebuild_indexes(data)
	return data

func _timber(data: TerrainData, cell: Vector2i, capacity: int = 4) -> String:
	Env._add_resource(data, Env.Kind.TIMBER, data.index(cell), capacity, 0)
	Env.rebuild_indexes(data)
	return "%d:%d" % [Env.Kind.TIMBER, data.index(cell)]

func _payload(data: TerrainData, cell: Vector2i, id: int, at: float = 0.0, budget: float = 20.0, rate: float = 100.0, seconds: float = 0.2) -> Dictionary:
	return {"site_id": str(data.site.id), "projectile_id": id, "event_id": "arrow:%d" % id,
		"action_time": at, "type": "ground", "cell": cell, "remaining_heat_budget": budget,
		"heat_rate": rate, "max_seconds": seconds, "heat_transfer": 1.0, "contact_scale": 1.0}

func _unit(data: TerrainData, key: String) -> Dictionary:
	return data.site.get("fire", {}).get("units", {}).get("resource:" + key, {})

func _fuel(data: TerrainData, key: String) -> int:
	var unit := _unit(data, key)
	var resource := Env.resource(data, key)
	return int(unit.get("residue_q", 0)) if bool(resource.cleared) else int(resource.remaining) * 1024 + int(unit.get("fuel_remainder_q", 0))

func _stone_wall(data: TerrainData, cell: Vector2i) -> String:
	var options := {"owner_faction": 1}
	var layout := Runtime.building_cells(data, "stone_wall", cell, Vector2i.ONE, options)
	if not _check(layout.ok, "Original stone wall layout"): return ""
	var cells: Array[int] = []
	cells.assign(layout.cells)
	var requested := Runtime.request_build(data, "stone_wall", cells, Callable(), options)
	if not _check(requested.ok, "Original stone wall payment"): return ""
	var key := str(requested.feature)
	var feature: Dictionary = data.site.features[key]
	var task := {"version": 2, "zone": -1, "target": "feature:" + key, "action": "construct",
		"work_cell": int(feature.entrance), "cell": int(feature.entrance), "mode": "work", "progress": 0.0, "status": "", "work_slot": -1}
	Runtime._feature_work(data, key, float(feature.work), Callable(), Callable(), task, {}, 20, 1)
	return key if _check(feature.stage == "complete", "Original stone wall completes") else ""

func _advance(data: TerrainData, at: float, prefix: int = -1) -> bool:
	var closed_prefix := prefix if prefix >= 0 else int(data.site.get("fire", {}).get("receipt_floor", 0))
	var result := Runtime.fire_advance(data, at, closed_prefix)
	return _check(result.ok, "Completed original action endpoint advances exactly once: " + str({"action_end": at, "closed_prefix": closed_prefix, "result": result}))

func _prime(data: TerrainData, cell: Vector2i, key: String, profile: String = "TEST_HEAT_100") -> bool:
	if not _check(Runtime.fire_receive_impact(data, _payload(data, cell, 1)).ok, "Actual original target admits finite contact"): return false
	_unit(data, key).profile = profile # Explicit test genesis; never edits a flight or contact outcome.
	return true

func _heat_and_finite_contacts() -> bool:
	var data := _data()
	var cell := Vector2i(20, 20)
	var key := _timber(data, cell)
	if not _prime(data, cell, key): return false
	for index in range(5):
		if index > 0 and not _check(Runtime.fire_receive_impact(data, _payload(data, cell, index + 1, index * 0.2)).ok, "Sequential original terminal receipt"): return false
		var before := var_to_bytes(data.site.fire)
		if not _advance(data, index * 0.2 + 0.199): return false
		if not _check(_unit(data, key).heat == index * 20.0 and _fuel(data, key) == 4096, "No heat or fuel commit before exact 5 Hz boundary"): return false
		if not _advance(data, (index + 1) * 0.2, index + 1): return false
		var unit := _unit(data, key)
		if not _check(is_equal_approx(float(unit.heat), (index + 1) * 20.0)
			and (str(unit.state) == "BURNING") == (index == 4) and _fuel(data, key) == 4096,
			"FI-01 fifth 20-heat input ignites; newly ignited unit has not burned in the same boundary"): return false
		before = var_to_bytes(data.site.fire)
		if not _check(bool(Runtime.fire_receive_impact(data, _payload(data, cell, index + 1, index * 0.2)).get("duplicate", false))
			and var_to_bytes(data.site.fire) == before, "Closed-prefix terminal replay changes no receipt, heat, or fuel bytes"): return false
	if not _advance(data, 1.2, 5): return false
	if not _check(data.site.changes[key].remaining is int and int(Env.resource(data, key).remaining) == 3 and int(_unit(data, key).fuel_remainder_q) == 768
		and _fuel(data, key) == 3840 and data.site.fire.contacts.is_empty(), "FI-12 exact burn256 converts sole R4/r0 to R3/r768"): return false
	var cargo := {}
	var harvested := Runtime.harvest(data, key, Env.work_cells(data, key)[0], cargo)
	if not _check(harvested.ok and int(harvested.taken) == 3 and int(cargo.wood) == 3 and _fuel(data, key) == 768,
		"Actual harvest removes only three complete original products and 3072 fuel quanta"): return false
	if not _check(not Runtime.harvest(data, key, cell + Vector2i.LEFT, cargo).ok and int(cargo.wood) == 3,
		"Residual 768 quanta cannot produce a fourth wood"): return false
	var other := _data()
	var other_key := _timber(other, cell)
	var paid := {}
	if not _check(Runtime.harvest(other, other_key, Env.work_cells(other, other_key)[0], paid).ok and int(paid.wood) == 4,
		"Unburned original harvest still yields four"): return false
	if not _check(not Runtime.fire_receive_impact(other, _payload(other, cell, 1)).accepted and int(paid.wood) == 4,
		"Harvest-before-contact cannot burn or duplicate removed products"): return false
	var finite := _data()
	var finite_key := _timber(finite, cell)
	if not _check(Runtime.fire_receive_impact(finite, _payload(finite, cell, 1, 0.0, 21.0, 100.0, 20.0)).accepted, "Finite budget fixture"): return false
	_unit(finite, finite_key).profile = "TEST_HEAT_100"
	if not _advance(finite, 2.0, 1): return false
	if not _check(_unit(finite, finite_key).heat == 21.0 and finite.site.fire.contacts.is_empty() and _fuel(finite, finite_key) == 4096,
		"Long contact duration cannot recharge a 21-unit budget"): return false
	if not _check(Runtime.fire_receive_impact(finite, _payload(finite, cell, 2, 2.0, 1000.0, 1.0, 0.2)).accepted, "Finite expiry fixture retains a much larger unspent budget"): return false
	if not _advance(finite, 3.0, 2): return false
	return _check(is_equal_approx(float(_unit(finite, finite_key).heat), 21.2) and finite.site.fire.contacts.is_empty(),
		"Finite expiry drops unused budget after exact valid overlap rather than extending contact lifetime")

func _named_heat_500() -> bool:
	var data := _data()
	var cell := Vector2i(20, 20)
	var key := _timber(data, cell)
	var state := Runtime._fire_state(data, 0.0)
	var unit := Runtime._fire_unit(data, state, Runtime._fire_resource_descriptor(data, key))
	# FI-01's exact initial test condition:500 quanta, with no duplicate whole-fuel field.
	unit.profile = "TEST_HEAT_100"
	unit.fuel_remainder_q = 500
	Env.change(data, key, {"remaining": 0})
	Env.rebuild_indexes(data)
	for index in range(5):
		if not _check(Runtime.fire_receive_impact(data, _payload(data, cell, index + 1, index * 0.2)).accepted,
			"Named heat500 fixture accepts one finite20 input"): return false
		if not _advance(data, (index + 1) * 0.2, index + 1): return false
		if not _check(_fuel(data, key) == 500 and is_equal_approx(float(_unit(data, key).heat), (index + 1) * 20.0)
			and (str(_unit(data, key).state) == "BURNING") == (index == 4),
			"Exact named FI-01 fuel500 profile ignites only on fifth input and preserves fuel through ignition boundary"): return false
	return true

func _invalid_contact_inputs() -> bool:
	var data := _data()
	var cell := Vector2i(20, 20)
	_timber(data, cell)
	for field: String in ["action_time", "remaining_heat_budget", "heat_rate", "max_seconds", "heat_transfer", "contact_scale"]:
		for invalid: float in [-1.0, INF, NAN]:
			var payload := _payload(data, cell, 1)
			payload[field] = invalid
			var before := var_to_bytes(data.site)
			if not _check(not Runtime.fire_receive_impact(data, payload).ok and var_to_bytes(data.site) == before,
				"Invalid finite-contact input preserves every original Site byte: " + field): return false
	var overflow := _payload(data, cell, 1, 1e308, 20.0, 10.0, 1e308)
	var before := var_to_bytes(data.site)
	if not _check(not Runtime.fire_receive_impact(data, overflow).ok and var_to_bytes(data.site) == before,
		"Individually finite times whose sum/5 Hz index overflows cannot enter original fire state"): return false
	var metadata := var_to_bytes([data.has_meta(&"fire_completed_action_end"), data.get_meta(&"fire_completed_action_end", 0.0), data.has_meta(&"fire_boundary"), data.get_meta(&"fire_boundary", {})])
	return _check(not Runtime.fire_advance(data, 1e308, 0).ok and not Runtime.fire_begin_boundary(data, 1e308).ok
		and var_to_bytes(data.site) == before
		and var_to_bytes([data.has_meta(&"fire_completed_action_end"), data.get_meta(&"fire_completed_action_end", 0.0), data.has_meta(&"fire_boundary"), data.get_meta(&"fire_boundary", {})]) == metadata,
		"Unrepresentable fixed-step endpoints do not mutate original cursor or completion barrier metadata")

func _zero_budget_terminal() -> bool:
	var profile := SiteCombatRules.fire_ranged_profile("bow_01", "FIRE_ARROW")
	if not _check(maxf(0.0, float(profile.ember) - float(profile.air_decay) * float(profile.life)) == 12.0
		and maxf(0.0, float(profile.ember) - float(profile.air_decay) * 11.0) == 0.0,
		"AR-11 original profile/clamp arithmetic: exhaustion is INITIAL_PROFILE_UNREACHABLE_IN_FLIGHT; no released flight is modified"): return false
	var data := _data()
	var cell := Vector2i(20, 20)
	_timber(data, cell)
	var consumed := Runtime.fire_receive_impact(data, _payload(data, cell, 1, 0.0, 0.0, 10.0, 2.0))
	if not _check(consumed.ok and not consumed.accepted and data.site.fire.units.is_empty()
		and data.site.fire.contacts.is_empty(), "Spent ember terminal still records one receipt but cannot recharge target heat/fuel"): return false
	if not _advance(data, 0.2, 1): return false
	var before := var_to_bytes(data.site)
	var regressed := Runtime.fire_advance(data, 0.4, 0)
	if not _check(not regressed.ok and regressed.code == "STALE_FIRE_BOUNDARY" and var_to_bytes(data.site) == before,
		"A regressing closed prefix must still reject atomically; helper cannot weaken the original monotonic receipt guard"): return false
	return _check(data.site.fire.receipt_ids.is_empty() and data.site.fire.receipt_floor == 1,
		"Consumed zero-energy receipt retires into bounded closed prefix")

func _chain_and_order() -> bool:
	var results: Array[String] = []
	for reversed: bool in [false, true]:
		var data := _data()
		var cells: Array[Vector2i] = [Vector2i(20, 20), Vector2i(21, 20), Vector2i(22, 20)]
		var keys: Array[String] = []
		for cell: Vector2i in cells: keys.append(_timber(data, cell, 100))
		for i in range(3):
			if not _check(Runtime.fire_receive_impact(data, _payload(data, cells[i], i + 1, 0.0, 0.001, 0.005)).accepted, "Original neighboring timber registration"): return false
		data.site.fire.contacts.clear() # Test initial condition, before any measured step.
		for i in range(3):
			_unit(data, keys[i]).heat = [40.4, 39.8, 0.0][i]
			_unit(data, keys[i]).moisture = 0.0
		if reversed:
			var active := {}
			for i in [2, 1, 0]: active["resource:" + keys[i]] = true
			data.site.fire.active = active
		if not _advance(data, 0.2, 3): return false
		if not _check(_unit(data, keys[0]).state == "BURNING" and _unit(data, keys[1]).state != "BURNING"
			and _unit(data, keys[2]).heat == 0.0, "FI-02 newly ignited A does not transfer heat in its ignition tick"): return false
		if not _advance(data, 0.4, 3): return false
		if not _check(_unit(data, keys[1]).state == "BURNING" and _unit(data, keys[2]).heat == 0.0,
			"A ignites B next tick; B cannot chain to C in that same tick"): return false
		if not _advance(data, 0.6, 3): return false
		if not _check(float(_unit(data, keys[2]).heat) > 0.0, "Only a later old-burning B may warm C"): return false
		results.append(JSON.stringify(data.site.fire, "", true))
	return _check(results[0] == results[1], "FI-03 reversing active insertion order preserves authoritative state")

func _noncombustible_and_edges() -> bool:
	for barrier: String in ["height", "water", "surface"]:
		var data := _data()
		var a := Vector2i(20, 20)
		var b := a + Vector2i.RIGHT
		var key_a := _timber(data, a, 100)
		var key_b := _timber(data, b)
		if not _prime(data, a, key_a, "TIMBER"): return false
		data.site.fire.contacts.clear()
		_unit(data, key_a).heat = 100.0
		_unit(data, key_a).state = "BURNING"
		_unit(data, key_a).intensity = 1.0
		if barrier == "height": data.height_levels[data.index(b)] = 2
		elif barrier == "water": data.water_kind[data.index(b)] = 1
		else:
			var standing := Env.work_cells(data, key_b)[0]
			if not _check(Runtime.harvest(data, key_b, standing, {}).ok and Runtime.harvest(data, key_b, standing, {}, "clear").ok,
				"Original material extraction and clear make room for actual stone surface"): return false
			if _stone_wall(data, b).is_empty(): return false
		if not _advance(data, 0.2, 1): return false
		if not _check(_unit(data, key_b).is_empty() or float(_unit(data, key_b).heat) == 0.0, "FI-05 no fire edge through " + barrier): return false
	var bare := _data()
	for i in range(3):
		var p := _payload(bare, Vector2i(30 + i, 30), i + 1, 0.0, 1000000.0, 1000000.0)
		if i == 1: bare.water_kind[bare.index(p.cell)] = 1
		if i == 2:
			var stone := _stone_wall(bare, p.cell)
			if stone.is_empty(): return false
			p.type = "structure"
			p.feature = stone
			p.part = "c:%d" % bare.index(p.cell)
		if not _check(not Runtime.fire_receive_impact(bare, p).accepted, "Unadmitted bare/water/structure terminal cannot invent combustible owner"): return false
	return _check(bare.site.fire.units.is_empty() and bare.site.fire.contacts.is_empty(), "FI-04 noncombustible receipts create no fuel ledger")

func _boundary_work() -> bool:
	var data := _data()
	var cell := Vector2i(20, 20)
	var key := _timber(data, cell)
	if not _prime(data, cell, key): return false
	data.site.fire.contacts.clear()
	_unit(data, key).heat = 100.0
	_unit(data, key).state = "BURNING"
	_unit(data, key).intensity = 1.0
	var worker: Dictionary = data.site.worker
	var standing := Env.work_cells(data, key)[0]
	worker.merge({"mode": "work", "target": key, "action": "harvest", "cell": data.index(standing),
		"work_cell": data.index(standing), "progress": 0.0}, true)
	var cargo: Dictionary = worker.cargo
	if not _check(Runtime.fire_begin_boundary(data, 0.2).ok, "Original completion boundary opens before work"): return false
	Runtime._work(data, float(Env.WORK_MINUTES[Env.Kind.TIMBER]), true, false, Callable())
	var boundary: Dictionary = data.get_meta(&"fire_boundary", {})
	if not _check(boundary.resources.size() == 1 and is_same(boundary.resources[0].worker, worker)
		and is_same(boundary.resources[0].cargo, cargo) and cargo.is_empty() and Env.resource(data, key).remaining == 4,
		"Actual _work completion queues original references without harvesting before fire"): return false
	var earned := float(worker.progress)
	Runtime._work(data, 100.0, true, false, Callable())
	if not _check(worker.progress == earned and boundary.resources.size() == 1, "Reentrant original work adds no progress or second completion"): return false
	var guard := func(w: Dictionary, c: Dictionary, at: Vector2i, manual: bool) -> bool:
		return is_same(w, data.site.worker) and is_same(c, data.site.worker.cargo) and at == standing and not manual
	if not _check(Runtime.fire_finish_boundary(data, 0.2, 1, Callable(), guard).ok, "Burn commits before guarded original harvest"): return false
	if not _check(int(cargo.wood) == 3 and _fuel(data, key) == 768 and str(worker.target).is_empty()
		and data.get_meta(&"fire_boundary", {}).is_empty(), "Same-boundary worker receives three wood after burn256, with residue768"): return false
	var state := var_to_bytes([data.site, cargo])
	if not _check(Runtime.fire_finish_boundary(data, 0.2, 1, Callable(), guard).ok and var_to_bytes([data.site, cargo]) == state,
		"Completed boundary retry cannot repeat harvesting or fuel changes"): return false
	return true

func _stale_boundary_work() -> bool:
	var data := _data()
	var cell := Vector2i(20, 20)
	var key := _timber(data, cell)
	if not _prime(data, cell, key): return false
	data.site.fire.contacts.clear()
	_unit(data, key).merge({"heat": 100.0, "state": "BURNING", "intensity": 1.0}, true)
	var worker: Dictionary = data.site.worker
	var standing: Vector2i = Env.work_cells(data, key)[0]
	worker.merge({"mode": "work", "target": key, "action": "harvest", "cell": data.index(standing),
		"work_cell": data.index(standing), "progress": 0.0}, true)
	var previous_cargo: Dictionary = worker.cargo
	if not _check(Runtime.fire_begin_boundary(data, 0.2).ok, "Stale-holder fixture opens original completion boundary"): return false
	Runtime._work(data, float(Env.WORK_MINUTES[Env.Kind.TIMBER]), true, false, Callable())
	var earned := float(worker.progress)
	var before := var_to_bytes(data.site)
	if not _check(not Runtime.fire_finish_boundary(data, 0.2, 1).ok and var_to_bytes(data.site) == before
		and not data.get_meta(&"fire_boundary", {}).is_empty(), "Missing owner guard is BUSY before fire or queued original work changes"): return false
	worker.cargo = {} # Explicit original holder replacement after completion was queued.
	var guard := func(w: Dictionary, c: Dictionary, at: Vector2i, manual: bool) -> bool:
		return is_same(w, data.site.worker) and is_same(c, data.site.worker.cargo) and at == standing and not manual
	var result := Runtime.fire_finish_boundary(data, 0.2, 1, Callable(), guard)
	return _check(result.ok and result.resource_completions.size() == 1 and result.resource_completions[0].code == "STALE_WORK"
		and previous_cargo.is_empty() and worker.cargo.is_empty() and worker.progress == earned and worker.target == key
		and Env.resource(data, key).remaining == 3 and _fuel(data, key) == 3840 and data.get_meta(&"fire_boundary", {}).is_empty(),
		"Original fire commits burn256 while stale cargo receives no harvest and earned original task remains available")

func _run() -> void:
	if not _invalid_contact_inputs(): _finish(false, "Finite inputs and atomic rejection"); return
	if not _zero_budget_terminal(): _finish(false, "Spent terminal energy and bounded receipts"); return
	if not _named_heat_500(): _finish(false, "FI-01 exact named500-quanta fixture"); return
	if not _heat_and_finite_contacts(): _finish(false, "FI-01/FI-12 finite contacts"); return
	if not _chain_and_order(): _finish(false, "FI-02/FI-03 old snapshot"); return
	if not _noncombustible_and_edges(): _finish(false, "FI-04/FI-05 targets and edges"); return
	if not _boundary_work(): _finish(false, "Actual original _work completion barrier"); return
	if not _stale_boundary_work(): _finish(false, "Missing guard and replaced original cargo"); return
	_finish(not failed, "fixed 5 Hz, finite contacts, old-snapshot propagation, original fuel and work transactions")
