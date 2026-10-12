extends SceneTree
## A completed named phase stops only the operate zone its own operation created.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
var checks := 0
var failures := 0

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SITE_TECHNOLOGY_OWNED_ZONE_FAIL: " + message)

func _initialize() -> void:
	var data := TerrainData.new()
	data.site = {"zones": [
		{"cells": [1, 2], "kind": -1, "action": "operate", "feature": "7", "active": true, "technology_owned": true},
		{"cells": [3, 4], "kind": -1, "action": "operate", "feature": "8", "active": true},
		{"cells": [1, 2], "kind": -1, "action": "construct", "feature": "7", "active": true}],
		"worker": {"target": "", "mode": "idle"}, "manual": {"target": "", "mode": "idle"}}
	# A mid-phase save keeps the marker exactly (a JSON bool round-trips).
	var parser := JSON.new()
	_check(parser.parse(JSON.stringify(data.site.zones, "", true, true)) == OK and parser.data[0].get("technology_owned") is bool and parser.data[0].technology_owned == true
		and not parser.data[1].has("technology_owned"), "The ownership marker survives the Store's JSON round trip as the same bool, and only where it was set")
	data.site.zones = parser.data
	Runtime._stop_technology_owned_zones(data, "7")
	var owned: Dictionary = data.site.zones[0]
	_check(not bool(owned.active) and not owned.has("technology_owned"), "The technology-created operate zone stops at phase completion and drops its marker")
	_check(bool(data.site.zones[2].active), "The same feature's other actions are untouched")
	Runtime._stop_technology_owned_zones(data, "8")
	_check(bool(data.site.zones[1].active), "A player's own pre-existing ordinary operate zone is kept")
	Runtime._stop_technology_owned_zones(data, "7")
	_check(not bool(owned.active) and not owned.has("technology_owned"), "Stopping is idempotent")
	print("SITE_TECHNOLOGY_OWNED_ZONE_%s: checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
