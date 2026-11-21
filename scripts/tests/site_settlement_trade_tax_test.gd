extends SceneTree
## T6 S2: settlement trade tax percent (version 4). Schema, pure validators, JSON round trip
## and the head-only setter. A bare TerrainData carries only the settlement record; no Site fixture.

const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")

const SITE := "t6s2_site"
const HEAD_ID := 7

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> bool:
	if condition: return true
	push_error("SITE_SETTLEMENT_TRADE_TAX_FAIL: " + message)
	quit(1)
	return false

func _record(version: int, head_holder: int) -> Dictionary:
	var offices: Dictionary = SiteOffices.default_offices("settlement")
	for entry: Dictionary in offices.positions:
		if bool(entry.head): entry.holder = head_holder
	var record: Dictionary = {"version": version, "settlement_id": "settlement_t6s2", "center_id": "c1", "level": 0, "name": "甲",
		"owner_faction": 1, "offices": offices, "fall_record": Settlement.empty_fall_record(), "technology": Technology.empty_scope_record(SITE)}
	if version >= 3: record.nation_id = null
	if version >= 4: record.trade_tax_percent = 0
	return record

func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: push_error("SITE_SETTLEMENT_TRADE_TAX_TIMEOUT"); quit(1))

	# Constants and field sets.
	if not _check(Settlement.VERSION == 1 and Settlement.VERSION_MAX == 4 and Settlement.TRADE_TAX_MAX == 50, "version constants"): return
	if not _check(Settlement.FIELDS_V4.has("trade_tax_percent") and Settlement.FIELDS_V4.has("nation_id") and not Settlement.FIELDS_V3.has("trade_tax_percent"), "only v4 carries the rate"): return

	# Pure percent validator: integer 0..50, integer-valued floats allowed (JSON loads floats).
	for good: Variant in [0, 50, 25, 25.0]:
		if not _check(Settlement.valid_trade_tax_percent(good), "percent %s accepted" % str(good)): return
	for bad: Variant in [-1, 51, 2.5, NAN, "5", null, true]:
		if not _check(not Settlement.valid_trade_tax_percent(bad), "percent %s refused" % str(bad)): return

	# Strict load: a v4 record with a vacant head validates; an out-of-range rate is refused.
	var data := TerrainData.new()
	var state: Dictionary = {"id": SITE, "features": {"c1": {"kind": "settlement_center", "stage": "pending", "owner_faction": 1}},
		"equipment_nations": {}, "minute": 0}
	state.settlement = _record(4, -1)
	var loaded: Dictionary = Settlement.validate(data, state, {})
	if not _check(loaded.ok, "v4 record with rate 0 loads: " + str(loaded)): return
	state.settlement.trade_tax_percent = 51
	if not _check(not Settlement.validate(data, state, {}).ok, "v4 rate 51 refused on load"): return
	state.settlement.trade_tax_percent = 30
	if not _check(Settlement.validate(data, state, {}).ok, "v4 rate 30 loads"): return

	# Setter refusals: nothing changes.
	var site := TerrainData.new()
	site.site = {"id": SITE, "settlement": _record(4, HEAD_ID)}
	var before: String = JSON.stringify(site.site)
	var record_ref: Dictionary = site.site.settlement
	if not _check(Settlement.set_trade_tax_percent(site, 3, 30).code == "NO_AUTHORITY" and JSON.stringify(site.site) == before, "non-head refused, unchanged"): return
	if not _check(Settlement.set_trade_tax_percent(site, HEAD_ID, 51).code == "INVALID" and JSON.stringify(site.site) == before, "rate 51 refused, unchanged"): return
	if not _check(Settlement.set_trade_tax_percent(site, HEAD_ID, 2.5).code == "INVALID" and JSON.stringify(site.site) == before, "rate 2.5 refused, unchanged"): return
	if not _check(Settlement.set_trade_tax_percent(site, HEAD_ID, "5").code == "INVALID" and JSON.stringify(site.site) == before, "rate string refused, unchanged"): return
	var vacant := TerrainData.new()
	vacant.site = {"id": SITE, "settlement": _record(4, -1)}
	var vacant_before: String = JSON.stringify(vacant.site)
	if not _check(Settlement.set_trade_tax_percent(vacant, HEAD_ID, 10).code == "NO_AUTHORITY" and JSON.stringify(vacant.site) == vacant_before, "vacant head refused, unchanged"): return
	var v1 := TerrainData.new()
	var v1_record: Dictionary = _record(1, HEAD_ID)
	v1_record.erase("technology")
	v1.site = {"id": SITE, "settlement": v1_record}
	if not _check(Settlement.set_trade_tax_percent(v1, HEAD_ID, 10).ok, "founded v1 settlement upgraded by head"): return
	if not _check(int(v1.site.settlement.version) == 4 and v1.site.settlement.has("technology") and Technology.valid_scope_record(v1.site.settlement.technology, "settlement") and int(v1.site.settlement.trade_tax_percent) == 10, "v1 upgrade adds empty technology record and rate"): return
	var none := TerrainData.new()
	if not _check(Settlement.set_trade_tax_percent(none, HEAD_ID, 10).code == "NO_TARGET", "no settlement refused"): return

	# Accepted by the head: same record object, version 4, integer rate.
	var result: Dictionary = Settlement.set_trade_tax_percent(site, HEAD_ID, 30)
	if not _check(result.ok, "head sets rate 30: " + str(result)): return
	if not _check(is_same(record_ref, site.site.settlement) and int(site.site.settlement.version) == 4, "same record object, version 4"): return
	if not _check(site.site.settlement.trade_tax_percent is int and int(site.site.settlement.trade_tax_percent) == 30, "rate stored as integer 30"): return
	if not _check(site.site.settlement.keys().size() == Settlement.FIELDS_V4.size() + 1, "v4 key set (FIELDS_V4 + technology)"): return

	# v2 record is upgraded to v4 in the same candidate; nation_id becomes null when absent.
	var upgraded := TerrainData.new()
	var v2_record: Dictionary = _record(2, HEAD_ID)
	upgraded.site = {"id": SITE, "settlement": v2_record}
	if not _check(Settlement.set_trade_tax_percent(upgraded, HEAD_ID, 12).ok, "v2 upgraded to v4 by head"): return
	if not _check(int(upgraded.site.settlement.version) == 4 and upgraded.site.settlement.has("nation_id") and upgraded.site.settlement.nation_id == null and int(upgraded.site.settlement.trade_tax_percent) == 12, "v2 upgrade fields"): return

	# JSON round trip: loaded numbers are floats; normalize restores the integer rate.
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(site.site.settlement))
	if not _check(parsed.trade_tax_percent is float, "JSON loads the rate as a float"): return
	var reloaded: Dictionary = {"id": SITE, "settlement": parsed}
	Settlement.normalize(reloaded)
	if not _check(parsed.trade_tax_percent is int and int(parsed.trade_tax_percent) == 30, "normalize restores integer rate"): return
	if not _check(Settlement.valid_trade_tax_candidate(parsed, {"id": SITE, "equipment_nations": {}}), "round-tripped v4 candidate is valid"): return
	if not _check(not Settlement.valid_trade_tax_candidate(parsed, {"id": "other_site", "equipment_nations": {}}), "technology owner must be this Site"): return

	print("SITE_SETTLEMENT_TRADE_TAX_OK")
	quit(0)
