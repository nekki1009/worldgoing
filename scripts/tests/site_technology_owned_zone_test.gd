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
	# Dormant player zone: the operation re-activates it, owns it for the phase and
	# returns it to its prior inactive state at completion.
	var dormant := {"cells": [5], "kind": -1, "action": "operate", "feature": "9", "active": false}
	data.site.zones.append(dormant)
	Runtime._technology_activate_zone(data, dormant, true)
	_check(bool(dormant.active) and dormant.get("technology_owned") == true, "A dormant zone the operation re-activates becomes the operation's own")
	Runtime._stop_technology_owned_zones(data, "9")
	_check(not bool(dormant.active) and not dormant.has("technology_owned"), "At completion the dormant zone returns to inactive")
	# Running player zone: re-used by the operation, never marked, never stopped.
	var running := {"cells": [6], "kind": -1, "action": "operate", "feature": "10", "active": true}
	data.site.zones.append(running)
	Runtime._technology_activate_zone(data, running, true)
	Runtime._stop_technology_owned_zones(data, "10")
	_check(bool(running.active) and not running.has("technology_owned"), "A zone the player already runs stays unmarked and keeps running")
	# New zone: appended exactly as created (marked by begin_technology_operation).
	var created := {"cells": [7], "kind": -1, "action": "operate", "feature": "11", "active": true, "technology_owned": true}
	var count_before: int = data.site.zones.size()
	Runtime._technology_activate_zone(data, created, false)
	_check(data.site.zones.size() == count_before + 1 and is_same(data.site.zones[-1], created), "A new operation zone is appended as the same marked dictionary")
	print("SITE_TECHNOLOGY_OWNED_ZONE_%s: checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
