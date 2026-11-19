extends SceneTree
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Tent = preload("res://scripts/tests/site_tent_logistics_test.gd")
var fixture: Variant
var guard_calls: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> bool:
	if condition: return true
	push_error("SITE_TRADE_CANDIDATE_N_FAIL: " + message)
	quit(1)
	return false

func _goods(resources: Dictionary = {}, ids: Array = []) -> Dictionary:
	return {"resources": resources, "item_ids": ids}

func _move(source: String, destination: String, resources: Dictionary = {}, ids: Array = []) -> Dictionary:
	return {"from": source, "to": destination, "resources": resources, "item_ids": ids}

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

func _reset(data: TerrainData) -> void:
	_set_cargo(data, "person:1", {"grain": 2})
	_set_cargo(data, "person:2", {"stone": 1})
	_set_cargo(data, "person:3", {"wood": 1})

func _snapshot(data: TerrainData) -> String:
	var rows: Array = []
	for holder_id: String in ["person:1", "person:2", "person:3"]:
		var endpoint: Dictionary = Runtime.trade_endpoint(data, holder_id)
		rows.append([holder_id, endpoint.get("holder", {}), endpoint.get("cargo", {})])
	return JSON.stringify([data.site, rows], "", true)

func _identity_holders(data: TerrainData) -> Array:
	var kept: Array = []
	for holder_id: String in ["person:1", "person:2", "person:3"]:
		var endpoint: Dictionary = Runtime.trade_endpoint(data, holder_id)
		kept.append([endpoint.holder, endpoint.cargo])
	return kept

func _reject(data: TerrainData, refs: Array, transfers: Array, code: String) -> bool:
	var before: String = _snapshot(data)
	var kept: Array = _identity_holders(data)
	var result: Dictionary = Runtime.exchange_candidate(data, refs, transfers)
	var unchanged: bool = _snapshot(data) == before
	var same_objects: bool = true
	var after: Array = _identity_holders(data)
	for index: int in range(kept.size()):
		same_objects = same_objects and is_same(kept[index][0], after[index][0]) and is_same(kept[index][1], after[index][1])
	return _check(not result.ok and (code.is_empty() or result.code == code) and unchanged and same_objects,
		"rejection %s (ok=%s actual=%s unchanged=%s identity=%s)" % [code, result.ok, result.get("code", ""), unchanged, same_objects])

func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: push_error("SITE_TRADE_CANDIDATE_N_TIMEOUT"); quit(1))
	fixture = Tent.Fixture.new()
	root.add_child(fixture)
	var data: TerrainData = fixture.terrain
	fixture.character.item_state = Runtime.new_item_state("person:1")
	fixture.npc.item_state = Runtime.new_item_state("person:2")
	fixture.army.combat_units[0].item_state = Runtime.new_item_state("person:3")
	if not _check(Runtime.trade_endpoint(data, "person:1").ok and Runtime.trade_endpoint(data, "person:2").ok and Runtime.trade_endpoint(data, "person:3").ok, "three original endpoints"): return
	_reset(data)

	# S1 cycle: three holders, each gives and receives once. Preview is pure first.
	var ids: Array = ["person:1", "person:2", "person:3"]
	var cycle: Array = [_move("person:1", "person:2", {"grain": 2}), _move("person:2", "person:3", {"stone": 1}), _move("person:3", "person:1", {"wood": 1})]
	var refs: Array = _refs(data, ids)
	var before_preview: String = _snapshot(data)
	var kept: Array = _identity_holders(data)
	var preview: Dictionary = Runtime.exchange_candidate(data, refs, cycle, true)
	if not _check(preview.ok and _snapshot(data) == before_preview, "S1 preview is pure"): return
	var cycle_result: Dictionary = Runtime.exchange_candidate(data, refs, cycle)
	var after: Array = _identity_holders(data)
	if not _check(cycle_result.ok, "S1 three-holder cycle commits: " + str(cycle_result.get("code", ""))): return
	if not _check(Runtime.trade_endpoint(data, "person:1").cargo == {"wood": 1} and Runtime.trade_endpoint(data, "person:2").cargo == {"grain": 2} and Runtime.trade_endpoint(data, "person:3").cargo == {"stone": 1}, "S1 cycle net per holder"): return
	if not _check(Runtime.trade_endpoint(data, "person:1").holder.version == int(refs[0].expected_version) + 1 and Runtime.trade_endpoint(data, "person:2").holder.version == int(refs[1].expected_version) + 1 and Runtime.trade_endpoint(data, "person:3").holder.version == int(refs[2].expected_version) + 1, "S1 each holder version +1 exactly once"): return
	if not _check(is_same(kept[0][0], after[0][0]) and is_same(kept[0][1], after[0][1]) and is_same(kept[2][0], after[2][0]), "S1 original holder and cargo dictionaries keep identity"): return

	# S1 merged holder: person:1 is in four legs; its version is bumped exactly once.
	_reset(data)
	var merged_refs: Array = _refs(data, ids)
	var merged: Array = [_move("person:1", "person:2", {"grain": 1}), _move("person:1", "person:3", {"grain": 1}), _move("person:2", "person:1", {"stone": 1}), _move("person:3", "person:1", {"wood": 1})]
	var merged_result: Dictionary = Runtime.exchange_candidate(data, merged_refs, merged)
	if not _check(merged_result.ok, "S1 merged holder commits: " + str(merged_result.get("code", ""))): return
	if not _check(Runtime.trade_endpoint(data, "person:1").cargo == {"stone": 1, "wood": 1}, "S1 merged holder net cargo"): return
	if not _check(Runtime.trade_endpoint(data, "person:1").holder.version == int(merged_refs[0].expected_version) + 1, "S1 merged holder version bumped once"): return
	if not _check(Runtime.trade_endpoint(data, "person:2").cargo == {"grain": 1} and Runtime.trade_endpoint(data, "person:3").cargo == {"grain": 1}, "S1 merged holder other sides"): return

	# S1 net capacity: person:3 is at CARRY_CAPACITY, and a same-size swap is still legal.
	_reset(data)
	_set_cargo(data, "person:3", {"wood": 1, "grain": 19})
	var swap_refs: Array = [_ref(data, "person:1"), _ref(data, "person:3")]
	if not _check(Runtime.exchange_candidate(data, swap_refs, [_move("person:3", "person:1", {"wood": 1}), _move("person:1", "person:3", {"grain": 1})]).ok, "S1 net capacity exact swap at limit"): return
	if not _check(Runtime.trade_endpoint(data, "person:3").cargo == {"grain": 20}, "S1 net capacity result"): return

	# S1 all-or-nothing: receiver over capacity refuses the whole candidate.
	_reset(data)
	_set_cargo(data, "person:3", {"grain": 20})
	if not _reject(data, _refs(data, ids), [_move("person:1", "person:3", {"grain": 1}), _move("person:2", "person:1", {"stone": 1})], "STORAGE_FULL"): return

	# S1 all-or-nothing: stale version on one holder refuses the whole candidate.
	_reset(data)
	var stale_refs: Array = _refs(data, ids)
	stale_refs[1].expected_version = int(stale_refs[1].expected_version) + 1
	if not _reject(data, stale_refs, cycle, "STALE_SOURCE"): return

	# S1 no virtual balance: person:2 has no grain to pass on until it receives it in this candidate.
	_reset(data)
	_set_cargo(data, "person:2", {})
	if not _reject(data, _refs(data, ids), [_move("person:1", "person:2", {"grain": 1}), _move("person:2", "person:3", {"grain": 1})], "EMPTY"): return

	# S1 no coin: coin is a price unit, never a candidate resource.
	_reset(data)
	if not _reject(data, _refs(data, ids), [_move("person:1", "person:2", {"coin": 1}), _move("person:2", "person:3", {"stone": 1})], "INVALID"): return

	# S1 real items move with owner records; a second leg of the same item is refused.
	_reset(data)
	var bow: Dictionary = Runtime.create_equipment(data, Runtime.trade_endpoint(data, "person:3").holder, "weapon:bow_01", {"slot": "weapon", "asset": "bow_01", "tint": [1.0, 1.0, 1.0, 1.0]}, 3)
	var bow_two: Dictionary = Runtime.create_equipment(data, Runtime.trade_endpoint(data, "person:3").holder, "weapon:bow_01", {"slot": "weapon", "asset": "bow_01", "tint": [1.0, 1.0, 1.0, 1.0]}, 3)
	if not _check(bow.ok and bow_two.ok, "S1 real item fixtures"): return
	if not _reject(data, _refs(data, ids), [_move("person:3", "person:1", {}, [bow.item_id]), _move("person:3", "person:2", {}, [bow.item_id])], "INVALID"): return
	if not _reject(data, _refs(data, ids), [_move("person:2", "person:1", {}, [bow_two.item_id]), _move("person:1", "person:3", {"grain": 1})], "STALE_SOURCE"): return
	var moved: Dictionary = Runtime.exchange_candidate(data, _refs(data, ids), [_move("person:3", "person:1", {}, [bow.item_id]), _move("person:1", "person:2", {"grain": 2})])
	if not _check(moved.ok and data.site.item_records[bow.item_id].holder == "person:1" and Runtime.trade_endpoint(data, "person:1").holder.item_ids.has(bow.item_id) and not Runtime.trade_endpoint(data, "person:3").holder.item_ids.has(bow.item_id), "S1 item ownership moves once"): return

	# S1 structure: self transfer, unknown holder, duplicate ref, single ref, unused holder.
	_reset(data)
	if not _reject(data, _refs(data, ids), [_move("person:1", "person:1", {"grain": 1}), _move("person:2", "person:3", {"stone": 1})], "INVALID"): return
	if not _reject(data, [_ref(data, "person:1"), {"holder": "person:9", "expected_version": 0}], [_move("person:1", "person:9", {"grain": 1})], ""): return
	if not _reject(data, [_ref(data, "person:1"), _ref(data, "person:1"), _ref(data, "person:2")], [_move("person:1", "person:2", {"grain": 1})], "INVALID"): return
	if not _reject(data, [_ref(data, "person:1")], [_move("person:1", "person:2", {"grain": 1})], "INVALID"): return
	if not _reject(data, _refs(data, ids), [_move("person:1", "person:2", {"grain": 1})], "INVALID"): return

	# S1 guard: one read-only guard call per leg; a refusal stops everything.
	_reset(data)
	guard_calls = 0
	data.item_transfer_guard = func(_source: Dictionary, _destination: Dictionary, _resources: Dictionary, _ids: Array) -> Dictionary:
		guard_calls += 1
		return Runtime.ok()
	if not _check(Runtime.exchange_candidate(data, _refs(data, ids), cycle, true).ok and guard_calls == 3, "S1 guard once per leg on preview"): return
	data.item_transfer_guard = func(_source: Dictionary, _destination: Dictionary, _resources: Dictionary, _ids: Array) -> Dictionary:
		return Runtime.fail("BUSY")
	if not _reject(data, _refs(data, ids), cycle, "BUSY"): return
	data.item_transfer_guard = Callable()

	fixture.close()
	fixture = null
	print("SITE_TRADE_CANDIDATE_N_OK")
	quit(0)
