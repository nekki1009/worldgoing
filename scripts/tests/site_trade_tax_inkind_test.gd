extends SceneTree
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Tent = preload("res://scripts/tests/site_tent_logistics_test.gd")
var fixture: Variant

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> bool:
	if condition: return true
	push_error("SITE_TRADE_TAX_INKIND_FAIL: " + message)
	quit(1)
	return false

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

func _terms(percent: int, collector: String) -> Dictionary:
	return {"percent": percent, "collector": collector, "derived": false}

func _set_cargo(data: TerrainData, holder_id: String, resources: Dictionary) -> void:
	var endpoint: Dictionary = Runtime.trade_endpoint(data, holder_id)
	endpoint.cargo.clear()
	endpoint.cargo.merge(resources)

func _cargo(data: TerrainData, holder_id: String) -> Dictionary:
	return Runtime.trade_endpoint(data, holder_id).cargo

func _version(data: TerrainData, holder_id: String) -> int:
	return int(Runtime.trade_endpoint(data, holder_id).holder.version)

func _versions(data: TerrainData, ids: Array) -> Dictionary:
	var versions: Dictionary = {}
	for holder_id: String in ids:
		versions[holder_id] = _version(data, holder_id)
	return versions

func _restore_versions(data: TerrainData, versions: Dictionary) -> void:
	for holder_id: Variant in versions.keys():
		Runtime.trade_endpoint(data, str(holder_id)).holder.version = int(versions[holder_id])

# Diagnostic only, enabled by the user argument --t6s4-diag. It prints sizes and the first differing position with context.
func _diag_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--t6s4-diag")

func _diag(left: String, right: String) -> void:
	var first: int = mini(left.length(), right.length())
	for index: int in range(mini(left.length(), right.length())):
		if left[index] != right[index]:
			first = index
			break
	print("T6S4_DIAG var_to_bytes left=%d right=%d chars left=%d right=%d first_diff_char=%d" % [var_to_bytes(left).size(), var_to_bytes(right).size(), left.length(), right.length(), first])
	print("T6S4_DIAG left: " + left.substr(maxi(0, first - 120), 240))
	print("T6S4_DIAG right: " + right.substr(maxi(0, first - 120), 240))

func _reset(data: TerrainData) -> void:
	_set_cargo(data, "person:1", {})
	_set_cargo(data, "person:2", {})
	_set_cargo(data, "person:3", {"wood": 1})

func _set_settlement(data: TerrainData, percent: Variant, nation: Variant) -> void:
	data.site["settlement"] = {"version": 4, "settlement_id": "t6s4", "trade_tax_percent": percent, "nation_id": nation}

func _snapshot(data: TerrainData) -> String:
	var rows: Array = []
	for holder_id: String in ["person:1", "person:2", "person:3"]:
		var endpoint: Dictionary = Runtime.trade_endpoint(data, holder_id)
		rows.append([holder_id, endpoint.get("holder", {}), endpoint.get("cargo", {})])
	return JSON.stringify([data.site, rows], "", true)

func _totals(data: TerrainData) -> Dictionary:
	var totals: Dictionary = {}
	for holder_id: String in ["person:1", "person:2", "person:3"]:
		for resource: Variant in _cargo(data, holder_id):
			totals[str(resource)] = int(totals.get(str(resource), 0)) + int(_cargo(data, holder_id)[resource])
	return totals

func _receipt_count(data: TerrainData) -> int:
	var store: Variant = data.site.get("trade_tax_receipts", {})
	return store.size() if store is Dictionary else 0

func _has_receipt_prefix(data: TerrainData, prefix: String) -> bool:
	var store: Variant = data.site.get("trade_tax_receipts", {})
	if not store is Dictionary: return false
	for key: Variant in store.keys():
		if str(key).begins_with(prefix): return true
	return false

func _reject_taxed(data: TerrainData, refs: Array, transfers: Array, trade_id: String, terms: Dictionary, code: String) -> bool:
	var before: String = _snapshot(data)
	var receipts_before: int = _receipt_count(data)
	var result: Dictionary = Runtime.commit_taxed_candidate(data, refs, transfers, trade_id, terms)
	var unchanged: bool = _snapshot(data) == before and _receipt_count(data) == receipts_before
	return _check(not result.ok and result.code == code and unchanged,
		"rejection %s (ok=%s actual=%s unchanged=%s)" % [code, result.ok, result.get("code", ""), unchanged])

func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: push_error("SITE_TRADE_TAX_INKIND_TIMEOUT"); quit(1))
	fixture = Tent.Fixture.new()
	root.add_child(fixture)
	var data: TerrainData = fixture.terrain
	fixture.character.item_state = Runtime.new_item_state("person:1")
	fixture.npc.item_state = Runtime.new_item_state("person:2")
	fixture.army.combat_units[0].item_state = Runtime.new_item_state("person:3")
	if not _check(Runtime.trade_endpoint(data, "person:1").ok and Runtime.trade_endpoint(data, "person:2").ok and Runtime.trade_endpoint(data, "person:3").ok, "three original endpoints"): return
	_set_settlement(data, 10, null)
	var line: Array = ["person:1", "person:2", "person:3"]

	# S4 floor per item: 9 grain at 10 percent is tax 0.
	_reset(data)
	_set_cargo(data, "person:1", {"grain": 9})
	var floor_nine: Dictionary = Runtime.commit_taxed_candidate(data, _refs(data, line), [_move("person:1", "person:2", {"grain": 9})], "t-floor9", _terms(10, "person:3"))
	if not _check(floor_nine.ok and _cargo(data, "person:2") == {"grain": 9} and _cargo(data, "person:3") == {"wood": 1}, "S4 floor: 9 grain at 10 percent is tax 0"): return

	# S4 floor per item: 19 grain at 10 percent is tax 1; the taxed side receives 18.
	_reset(data)
	_set_cargo(data, "person:1", {"grain": 19})
	var floor_nineteen: Dictionary = Runtime.commit_taxed_candidate(data, _refs(data, line), [_move("person:1", "person:2", {"grain": 19})], "t-floor19", _terms(10, "person:3"))
	if not _check(floor_nineteen.ok and _cargo(data, "person:2") == {"grain": 18} and _cargo(data, "person:3") == {"wood": 1, "grain": 1}, "S4 floor: 19 grain at 10 percent gives tax 1, receives 18"): return
	if not _check(data.site.trade_tax_receipts["t-floor19:person:2"].tax == {"grain": 1} and data.site.trade_tax_receipts["t-floor19:person:2"].received == {"grain": 19}, "S4 receipt records received and tax for the side"): return

	# S4 mixed stacks: wood 15 gives tax 1, grain 5 gives tax 0, each floored separately. Totals are conserved.
	_reset(data)
	_set_cargo(data, "person:1", {"wood": 15, "grain": 5})
	var before_totals: Dictionary = _totals(data)
	var mixed: Dictionary = Runtime.commit_taxed_candidate(data, _refs(data, line), [_move("person:1", "person:2", {"wood": 15, "grain": 5})], "t-mixed", _terms(10, "person:3"))
	if not _check(mixed.ok and _cargo(data, "person:2") == {"wood": 14, "grain": 5} and _cargo(data, "person:3") == {"wood": 2}, "S4 mixed stacks floored per resource"): return
	if not _check(_totals(data) == before_totals, "S4 no virtual balance: resource totals conserved"): return

	# S4 equipment untaxed: the bow moves, the collector gets no item and no resource tax.
	_reset(data)
	var bow: Dictionary = Runtime.create_equipment(data, Runtime.trade_endpoint(data, "person:1").holder, "weapon:bow_01", {"slot": "weapon", "asset": "bow_01", "tint": [1.0, 1.0, 1.0, 1.0]}, 3)
	if not _check(bow.ok, "S4 bow fixture"): return
	var bow_move: Dictionary = Runtime.commit_taxed_candidate(data, _refs(data, line), [_move("person:1", "person:2", {}, [bow.item_id])], "t-bow", _terms(10, "person:3"))
	if not _check(bow_move.ok and data.site.item_records[bow.item_id].holder == "person:2" and Runtime.trade_endpoint(data, "person:2").holder.item_ids.has(bow.item_id), "S4 equipment moves untaxed"): return
	if not _check(not Runtime.trade_endpoint(data, "person:3").holder.item_ids.has(bow.item_id) and _cargo(data, "person:3") == {"wood": 1}, "S4 collector gets no item and no tax"): return

	# S4 coin untaxed and refused: coin in goods is refused and no tax or receipt is created.
	_reset(data)
	_set_cargo(data, "person:1", {"coin": 5})
	if not _reject_taxed(data, _refs(data, line), [_move("person:1", "person:2", {"coin": 5})], "t-coin", _terms(10, "person:3"), "INVALID"): return

	# S4 zero rate equals S1: the public path with rate 0 gives the same state as the S1 candidate.
	_set_settlement(data, 0, null)
	_reset(data)
	_set_cargo(data, "person:1", {"grain": 2})
	_set_cargo(data, "person:2", {"stone": 1})
	var start_versions: Dictionary = _versions(data, line)
	var cycle: Array = [_move("person:1", "person:2", {"grain": 2}), _move("person:2", "person:3", {"stone": 1}), _move("person:3", "person:1", {"wood": 1})]
	var s1_result: Dictionary = Runtime.exchange_candidate(data, _refs(data, line), cycle)
	var s1_state: String = _snapshot(data)
	# Both runs must start from the same state: the S1 run bumped each holder's version, so restore them first.
	_reset(data)
	_set_cargo(data, "person:1", {"grain": 2})
	_set_cargo(data, "person:2", {"stone": 1})
	_restore_versions(data, start_versions)
	# The fixture Site is shared by earlier cases, so receipts from them already exist: count them instead of testing for the key.
	var receipts_before_zero: int = _receipt_count(data)
	var zero_result: Dictionary = Runtime.exchange_taxed_candidate(data, _refs(data, line), cycle, "t-zero")
	var zero_state: String = _snapshot(data)
	if zero_state != s1_state and _diag_enabled(): _diag(s1_state, zero_state)
	if not _check(s1_result.ok and zero_result.ok and zero_state == s1_state, "S4 zero rate equals S1 byte for byte"): return
	if not _check(_receipt_count(data) == receipts_before_zero and not _has_receipt_prefix(data, "t-zero:"), "S4 zero rate writes no receipt"): return
	_set_settlement(data, 10, null)

	# S4 all-or-nothing on collector capacity: the collector is full, so the tax overflows and nothing changes.
	_reset(data)
	_set_cargo(data, "person:3", {"grain": 20})
	_set_cargo(data, "person:1", {"grain": 10})
	if not _reject_taxed(data, _refs(data, line), [_move("person:1", "person:2", {"grain": 10})], "t-full", _terms(10, "person:3"), "STORAGE_FULL"): return

	# S4 all-or-nothing on collector stale version.
	_reset(data)
	_set_cargo(data, "person:1", {"grain": 10})
	var stale_refs: Array = _refs(data, line)
	stale_refs[2].expected_version = int(stale_refs[2].expected_version) + 1
	if not _reject_taxed(data, stale_refs, [_move("person:1", "person:2", {"grain": 10})], "t-stale", _terms(10, "person:3"), "STALE_SOURCE"): return

	# S4 collector equals seller: merged once, the tax comes back to the same holder, version bumped once.
	_reset(data)
	_set_cargo(data, "person:1", {"grain": 15})
	var self_refs: Array = [_ref(data, "person:1"), _ref(data, "person:2")]
	var self_version: int = _version(data, "person:1")
	var self_result: Dictionary = Runtime.commit_taxed_candidate(data, self_refs, [_move("person:1", "person:2", {"grain": 15})], "t-self", _terms(10, "person:1"))
	if not _check(self_result.ok and _cargo(data, "person:1") == {"grain": 1} and _cargo(data, "person:2") == {"grain": 14}, "S4 collector equals seller: net per holder"): return
	if not _check(_version(data, "person:1") == self_version + 1, "S4 collector equals seller: version bumped once"): return

	# S4 replay is idempotent: the same trade_id returns the stored receipt and taxes nothing again.
	_reset(data)
	_set_cargo(data, "person:1", {"grain": 19})
	var replay_refs: Array = _refs(data, line)
	var replay_moves: Array = [_move("person:1", "person:2", {"grain": 19})]
	var first: Dictionary = Runtime.commit_taxed_candidate(data, replay_refs, replay_moves, "t-replay", _terms(10, "person:3"))
	var after_first: String = _snapshot(data)
	var second: Dictionary = Runtime.commit_taxed_candidate(data, replay_refs, replay_moves, "t-replay", _terms(10, "person:3"))
	if not _check(first.ok and second.ok and second.get("replayed", false) == true and _snapshot(data) == after_first, "S4 replay returns stored receipt, nothing changes"): return
	if not _check(_cargo(data, "person:3") == {"wood": 1, "grain": 1}, "S4 replay did not tax twice"): return
	# A different request under the same trade_id is refused.
	if not _reject_taxed(data, replay_refs, [_move("person:1", "person:2", {"grain": 1})], "t-replay", _terms(10, "person:3"), "INVALID"): return

	# S4 receipt written atomically: a refused candidate writes no receipt.
	_reset(data)
	_set_cargo(data, "person:3", {"grain": 20})
	_set_cargo(data, "person:1", {"grain": 10})
	if not _reject_taxed(data, _refs(data, line), [_move("person:1", "person:2", {"grain": 10})], "t-none", _terms(10, "person:3"), "STORAGE_FULL"): return
	var store_after_refusal: Variant = data.site.get("trade_tax_receipts", {})
	if not _check(not store_after_refusal is Dictionary or not store_after_refusal.has("t-none:person:2"), "S4 receipt not written on refusal"): return

	# S4 rate change is effective at commit only: a rate changed after prepare makes publish STALE and changes nothing.
	_reset(data)
	_set_cargo(data, "person:1", {"grain": 19})
	var prepared: Dictionary = Runtime.prepare_taxed_candidate(data, _refs(data, line), [_move("person:1", "person:2", {"grain": 19})], "t-rate", _terms(10, "person:3"))
	if not _check(prepared.ok, "S4 prepare with rate 10"): return
	_set_settlement(data, 20, null)
	var before_publish: String = _snapshot(data)
	var stale_rate: Dictionary = Runtime.publish_taxed_candidate(prepared)
	if not _check(not stale_rate.ok and stale_rate.code == "STALE_SOURCE" and _snapshot(data) == before_publish, "S4 rate changed before publish is STALE_SOURCE, unchanged"): return
	_set_settlement(data, 10, null)

	# S4 collector refusals from the settlement's nation (derived terms): no nation, unbound treasury, other Site.
	var derived_none: Dictionary = Runtime.trade_tax_terms(data)
	if not _check(not derived_none.ok and derived_none.code == "NO_COLLECTOR", "S4 derived terms: no nation refused NO_COLLECTOR"): return
	_reset(data)
	_set_cargo(data, "person:1", {"grain": 19})
	var no_collector: Dictionary = Runtime.exchange_taxed_candidate(data, _refs(data, line), [_move("person:1", "person:2", {"grain": 19})], "t-nocoll")
	if not _check(not no_collector.ok and no_collector.code == "NO_COLLECTOR" and _cargo(data, "person:1") == {"grain": 19}, "S4 NO_COLLECTOR with no nation: nothing changes"): return
	data.site["equipment_nations"] = {"n1": {"ransom_data": {"treasury": {"site_id": "elsewhere", "feature_id": "x", "holder": "feature:x"}}}}
	_set_settlement(data, 10, "n1")
	var other_site: Dictionary = Runtime.exchange_taxed_candidate(data, _refs(data, line), [_move("person:1", "person:2", {"grain": 19})], "t-other")
	if not _check(not other_site.ok and other_site.code == "NO_COLLECTOR" and _cargo(data, "person:1") == {"grain": 19}, "S4 NO_COLLECTOR for a treasury in another Site: nothing changes"): return
	data.site["equipment_nations"] = {"n1": {"ransom_data": {}}}
	var unbound: Dictionary = Runtime.exchange_taxed_candidate(data, _refs(data, line), [_move("person:1", "person:2", {"grain": 19})], "t-unbound")
	if not _check(not unbound.ok and unbound.code == "NO_COLLECTOR", "S4 NO_COLLECTOR for an unbound treasury"): return
	# Rate 0 never needs a collector, even with a nation set.
	_set_settlement(data, 0, "n1")
	var zero_no_collector: Dictionary = Runtime.trade_tax_terms(data)
	if not _check(zero_no_collector.ok and int(zero_no_collector.percent) == 0 and str(zero_no_collector.collector) == "", "S4 rate 0 needs no collector"): return
	# A rate outside the S2 range is refused by the terms.
	_set_settlement(data, 51, null)
	if not _check(Runtime.trade_tax_terms(data).code == "INVALID", "S4 rate 51 refused by terms"): return
	_set_settlement(data, "10", null)
	if not _check(Runtime.trade_tax_terms(data).code == "INVALID", "S4 string rate refused by terms"): return

	fixture.close()
	fixture = null
	print("SITE_TRADE_TAX_INKIND_OK")
	quit(0)
