extends SceneTree

const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Clear = preload("res://scripts/terrain_lab/crowd_clear_handoff.gd")

func _initialize() -> void:
	call_deferred("_run")

func _person(identity: int, cell: Vector2i, captive: bool) -> Dictionary:
	return {"person_id": identity, "hp": 100.0, "captive": captive, "cell": [cell.x, cell.y], "movement_left": 0.0}

func _relation(prison_id: String) -> Dictionary:
	return {"version": 2, "captor_id": 1, "guard_id": 1, "captor_faction": 1, "sealed_container": "", "prison_id": prison_id}

func _run() -> void:
	var data := TerrainData.new()
	data.allocate(Vector2i(18, 14))
	data.flags.fill(TerrainData.Flag.WALKABLE)
	var state := {"actors": {"guard": _person(1, Vector2i(1, 1), false)}, "armies": [], "captivity": {},
		"features": {}, "next_feature": 7, "item_definitions": {}, "ground_loot": {}, "next_loot": 1, "escort_orders": {}}
	for n: int in range(5):
		var key := str(n + 1)
		var cell := Vector2i(3 + n * 2, 5)
		state.features[key] = {"kind": "prison", "stage": "complete", "layout_version": 1, "quarter": 0, "cells": [data.index(cell)]}
		state.actors[str(n + 2)] = _person(n + 2, cell, true)
		state.captivity[str(n + 2)] = _relation(key)
	data.site = state
	assert(Store._validate_captivity(data, state).ok, "Five confined people do not consume the outdoor four-person guard capacity")
	var original := state.duplicate(true)
	for fault: String in ["missing", "unfinished", "wrong_owner", "wrong_cell", "alias", "extra", "moving", "dead", "duplicate", "occupied"]:
		var candidate := original.duplicate(true)
		match fault:
			"missing": candidate.features.erase("1")
			"unfinished": candidate.features["1"].stage = "building"
			"wrong_owner": candidate.features["1"].owner_faction = 2
			"wrong_cell": candidate.actors["2"].cell = [3, 6]
			"alias": candidate.captivity["2"].prison_id = "01"
			"extra": candidate.captivity["2"].residents = [2]
			"moving": candidate.actors["2"].movement_left = 0.1
			"dead": candidate.actors["2"].hp = 0.0
			"duplicate":
				candidate.actors["3"].cell = candidate.actors["2"].cell.duplicate()
				candidate.captivity["3"].prison_id = "1"
			"occupied": candidate.actors.guard.cell = candidate.actors["2"].cell.duplicate()
		assert(not Store._validate_captivity(data, candidate).ok, fault)
		assert(state == original, "Validation cannot mutate original bodies or relations")
	var outdoor := original.duplicate(true)
	for relation: Dictionary in outdoor.captivity.values(): relation.prison_id = ""
	assert(not Store._validate_captivity(data, outdoor).ok)
	outdoor.captivity.erase("6")
	outdoor.actors["6"].captive = false
	assert(Store._validate_captivity(data, outdoor).ok)
	for relation: Dictionary in outdoor.captivity.values():
		relation.version = 1
		relation.erase("prison_id")
	assert(Store._validate_captivity(data, outdoor).ok, "Legacy five-field relations remain readable")
	var pending := original.duplicate(true)
	var pending_cell := Vector2i(13, 5)
	pending.features["6"] = {"kind": "prison", "stage": "complete", "layout_version": 1, "quarter": 0, "cells": [data.index(pending_cell)]}
	pending.actors["7"] = _person(7, Vector2i(12, 6), true)
	pending.captivity["7"] = _relation("")
	pending.escort_orders["1"] = {"version": 2, "kind": "prison", "prison_id": "6", "destination": data.index(Vector2i(13, 6)), "captives": [7], "targets": {"7": data.index(pending_cell)}}
	assert(Store._validate_captivity(data, pending).ok)
	pending.escort_orders["1"].targets["7"] = data.index(Vector2i(12, 5))
	assert(not Store._validate_captivity(data, pending).ok, "Pending target must be an actual structural custody slot")
	pending.escort_orders["1"].targets["7"] = data.index(pending_cell)
	pending.escort_orders["1"].destination = data.index(Vector2i(13, 7))
	assert(not Store._validate_captivity(data, pending).ok, "Pending entrance cannot drift")
	var inmate := {"person_id": 2, "position": Vector2(3.5, 5.5), "standing": true, "prison_fixed": true}
	var layout := Clear.plan_legal_positions(data, [inmate], {})
	assert(layout.ok and layout.cells[2] == Vector2i(3, 5))
	assert(not Clear.plan_legal_positions(data, [inmate], {Vector2i(3, 5): true}).ok, "Clear must reject a conflicting prison slot rather than relocate the original inmate")
	print("SITE_PRISON_STORAGE_PASS legacy/v2 relations, outdoor-only guard capacity, invalid prison/slot/life/move/duplicate rejection, pending slots, fixed Clear handoff")
	quit(0)
