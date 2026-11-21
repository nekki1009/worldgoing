extends SceneTree
const Gate = preload("res://scripts/terrain_lab/site_trade_nation_source.gd")

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> bool:
	if condition: return true
	push_error("SITE_TRADE_NATION_SOURCE_FAIL: " + message)
	quit(1)
	return false

func _site() -> Dictionary:
	return {
		"id": "site_a",
		"equipment_nations": {
			"n1": {"ransom_data": {"treasury": {"site_id": "site_a", "feature_id": "wh1", "holder": "feature:wh1"}}},
		},
		"stockpiles": {
			"wh1": {"nation_id": "n1", "cargo": {"coin": 40}},
			"wh2": {"cargo": {"grain": 5}},
			"wh3": {"nation_id": "n1", "cargo": {}},
		},
	}

func _code(result: Dictionary) -> String:
	return str(result.get("code", ""))

func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: push_error("SITE_TRADE_NATION_SOURCE_TIMEOUT"); quit(1))
	var site: Dictionary = _site()
	var before: String = JSON.stringify(site)

	# TR-64: the bound treasury of its own nation may sell.
	var bound: Dictionary = Gate.nation_source(site, "n1", "feature:wh1")
	if not _check(bound.ok and bound.holder == "feature:wh1", "bound treasury sells: " + _code(bound)): return

	# TR-64: a general warehouse may not act as a nation source, even in the same Site.
	if not _check(_code(Gate.nation_source(site, "n1", "feature:wh2")) == "NOT_NATION_SOURCE", "general warehouse refused"): return

	# TR-64: a second warehouse that claims the nation but is not the bound treasury is refused.
	if not _check(_code(Gate.nation_source(site, "n1", "feature:wh3")) == "NOT_NATION_SOURCE", "unbound claimed warehouse refused"): return

	# TR-64: persons, depot and vehicles are never nation sources.
	for holder_id: String in ["person:1", "depot", "vehicle:v1"]:
		if not _check(_code(Gate.nation_source(site, "n1", holder_id)) == "NOT_NATION_SOURCE", "%s refused as nation source" % holder_id): return

	# Unknown or empty nation is refused as missing target.
	if not _check(_code(Gate.nation_source(site, "n2", "feature:wh1")) == "NO_TARGET", "unknown nation refused"): return
	if not _check(_code(Gate.nation_source(site, "", "feature:wh1")) == "NO_TARGET", "empty nation refused"): return
	if not _check(_code(Gate.nation_source({}, "n1", "feature:wh1")) == "NO_TARGET", "empty site refused"): return

	# Treasury bound in another Site is refused.
	var elsewhere: Dictionary = _site()
	elsewhere.equipment_nations.n1.ransom_data.treasury.site_id = "elsewhere"
	if not _check(_code(Gate.nation_source(elsewhere, "n1", "feature:wh1")) == "NO_TREASURY", "treasury from another Site refused"): return

	# A nation without a bound treasury is refused.
	var unbound: Dictionary = _site()
	unbound.equipment_nations.n1.ransom_data = {}
	if not _check(_code(Gate.nation_source(unbound, "n1", "feature:wh1")) == "NO_TREASURY", "unbound nation refused"): return

	# The bound stock must still name its nation.
	var unnamed: Dictionary = _site()
	unnamed.stockpiles.wh1.erase("nation_id")
	if not _check(_code(Gate.nation_source(unnamed, "n1", "feature:wh1")) == "NO_TREASURY", "unnamed bound stock refused"): return

	# Pure: no call changes the Site.
	if not _check(JSON.stringify(site) == before, "gate leaves the Site unchanged"): return

	print("SITE_TRADE_NATION_SOURCE_OK")
	quit(0)
