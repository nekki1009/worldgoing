extends SceneTree
## Original RegionSaveSlot static contracts. Actual Lab replay and UI are tested separately.
## Run only after ORIGINAL SiteStore._read exposes its verified checksum metadata.
const Candidate = preload("res://scripts/region_lab/region_save_slot.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Grid = preload("res://scripts/region_lab/region_grid.gd")
const SITE := Vector2i(2, 3)
var _root := ""
var _started := false
var _finished := false
var _groups := 0

class ClockSlot:
	extends RefCounted
	var control := {"logical_game_seconds": 120.0, "active_site_id": "A"}
	var calls := 0
	func advance_world_time(delta: float) -> float:
		calls += 1
		control.logical_game_seconds = float(control.logical_game_seconds) + delta
		return float(control.logical_game_seconds)

class MapSource:
	extends RefCounted
	var summary_calls := 0
	var generated_sites := 0
	func get_site_summary(x: int, y: int) -> Dictionary:
		summary_calls += 1
		return {"ok": true, "site_id": RegionGrid.site_id(RegionGrid.ATLAS_ID, Vector2i(x, y)), "status": "land"}
	func make_terrain_data(_x: int, _y: int) -> Dictionary:
		generated_sites += 1
		return {"ok": false, "code": "MAP_READ_MUST_NOT_GENERATE"}

class SummarySlot:
	extends RefCounted
	var pin := {"world_instance_id": "test_world", "slot_id": "test_slot", "atlas_id": RegionGrid.ATLAS_ID}
	var source := MapSource.new()
	var folder := ""
	var expected_base := {}
	func _matches_base(base: Dictionary, site: Vector2i) -> bool:
		# The real Store reader returns the entire JSON representation.
		var stored_expected: Dictionary = JSON.parse_string(JSON.stringify(expected_base, "", true, true))
		var coordinates: Variant = base.get("site")
		return base == stored_expected and coordinates is Array and coordinates.size() == 2 \
			and SiteStore._integer(coordinates[0], -10000000, 10000000) and SiteStore._integer(coordinates[1], -10000000, 10000000) \
			and int(coordinates[0]) == site.x and int(coordinates[1]) == site.y

func _init() -> void:
	_root = "res://output/site_building_close_20261004/region_candidate/runs/run-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	call_deferred("_run")

func _process(_delta: float) -> bool:
	if _started and not _finished:
		printerr("SITE_REGION_BUILDING_SUMMARY_FAILED: assertion interrupted the synchronous candidate test")
		quit(1)
	return false

func _run() -> void:
	_started = true
	create_timer(90.0).timeout.connect(func() -> void: quit(1))
	assert(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_root)), "Fresh evidence path required")
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_root)) == OK)
	assert(_legacy_and_shape())
	assert(_active_clock())
	assert(_replay_clock())
	assert(_summary_contract())
	assert(_groups == 4, "Candidate groups incomplete")
	_finished = true
	print("SITE_REGION_BUILDING_SUMMARY_PASS: strict legacy/watermark rules, one active publisher, bounded replay bookkeeping, checksum-derived scoped summaries; no production caller, actual replay, ship transaction, GPU or performance claim")
	quit(0)

func _legacy_and_shape() -> bool:
	var state := {"id": "A", "paused": false, "features": {"17": {"kind": "house"}}}
	var before := JSON.stringify(state)
	var checked := Candidate.validate_settlement(state, 120.0)
	assert(checked.ok and checked.legacy and checked.pending == 0.0 and JSON.stringify(state) == before)
	assert(Candidate.attach_settlement(state, 120.0).ok)
	assert(state.simulation_settlement == {"version": 1, "last_settled_game_seconds": 120.0})
	assert(state.features == {"17": {"kind": "house"}}, "Attaching time changed original feature identity")
	var window := Candidate.replay_window(state, 300.0)
	assert(window.ok and not window.legacy and window.from == 120.0 and window.pending == 180.0)
	for malformed: Variant in [null, true, 1, [], {}, {"version": 1}, {"version": true, "last_settled_game_seconds": 0.0},
			{"version": 2, "last_settled_game_seconds": 0.0}, {"version": 1.5, "last_settled_game_seconds": 0.0},
			{"version": 1, "last_settled_game_seconds": "0"}, {"version": 1, "last_settled_game_seconds": -1.0},
			{"version": 1, "last_settled_game_seconds": INF}, {"version": 1, "last_settled_game_seconds": NAN},
			{"version": 1, "last_settled_game_seconds": 301.0},
			{"version": 1, "last_settled_game_seconds": 0.0, "now": 300.0}]:
		var bad := {"id": "A", "simulation_settlement": malformed}
		var unchanged := JSON.stringify(bad)
		assert(not Candidate.attach_settlement(bad, 300.0).ok and JSON.stringify(bad) == unchanged)
	for bad_now: Variant in [null, true, "300", -1.0, INF, NAN]:
		var legacy := {"id": "A"}
		assert(not Candidate.attach_settlement(legacy, bad_now).ok and not legacy.has("simulation_settlement"))
	_groups += 1
	return true

func _active_clock() -> bool:
	var slot := ClockSlot.new()
	var state := {"id": "A", "paused": false}
	assert(Candidate.attach_settlement(state, 120.0).ok)
	assert(Candidate.record_completed_active_step(slot, state, 0.5).ok)
	assert(slot.calls == 1 and slot.control.logical_game_seconds == 120.5 and state.simulation_settlement.last_settled_game_seconds == 120.5)
	assert(Candidate.record_completed_active_step(slot, state, 0.0).ok and slot.calls == 1)
	var before := JSON.stringify({"state": state, "control": slot.control})
	for invalid: Variant in [null, true, "1", -1.0, INF, NAN]:
		assert(not Candidate.record_completed_active_step(slot, state, invalid).ok)
		assert(JSON.stringify({"state": state, "control": slot.control}) == before and slot.calls == 1)
	state.paused = true
	assert(Candidate.record_completed_active_step(slot, state, 1.0).code == "PAUSED" and slot.calls == 1)
	state.paused = false
	state.id = "inactive"
	assert(Candidate.record_completed_active_step(slot, state, 1.0).code == "NO_TARGET" and slot.calls == 1)
	state.id = "A"
	state.simulation_settlement.last_settled_game_seconds = 120.0
	assert(Candidate.record_completed_active_step(slot, state, 1.0).code == "UNSETTLED_SITE" and slot.calls == 1)
	state.erase("simulation_settlement")
	assert(Candidate.record_completed_active_step(slot, state, 1.0).code == "UNSETTLED_SITE" and slot.calls == 1)
	_groups += 1
	return true

func _replay_clock() -> bool:
	var slot := ClockSlot.new()
	var state := {"id": "A", "paused": false}
	assert(Candidate.attach_settlement(state, 100.0).ok)
	var window := Candidate.replay_window(state, slot.control.logical_game_seconds)
	assert(window.ok and window.pending == 20.0)
	assert(Candidate.record_completed_replay_step(state, window.target, 7.5).pending == 12.5)
	assert(slot.calls == 0 and slot.control.logical_game_seconds == 120.0, "Replay advanced global time twice")
	var before := JSON.stringify(state)
	assert(not Candidate.record_completed_replay_step(state, window.target, 13.0).ok and JSON.stringify(state) == before)
	assert(Candidate.record_completed_replay_step(state, window.target, 0.0).pending == 12.5 and JSON.stringify(state) == before)
	assert(Candidate.record_completed_replay_step(state, window.target, 12.5).pending == 0.0)
	assert(Candidate.replay_window(state, 120.0).pending == 0.0, "Revisit replayed settled time")
	assert(not Candidate.record_completed_replay_step(state, 119.0, 0.0).ok, "Rollback accepted a future Site watermark")
	assert(slot.calls == 0 and slot.control.logical_game_seconds == 120.0)
	_groups += 1
	return true

func _summary_contract() -> bool:
	var slot := SummarySlot.new()
	slot.folder = _root.path_join("world_a")
	var absent := Candidate.read_site_building_summary(slot, SITE, "")
	assert(absent.ok and not absent.visited and absent.buildings.is_empty() and absent.counts.is_empty())
	assert(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(slot.folder)) and slot.source.generated_sites == 0,
		"Unvisited summary created a Site, file, people or starting stock")
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(slot.folder)) == OK)
	slot.expected_base = {"base_kind": "fixed_geography", "site": [SITE.x, SITE.y], "site_id": Grid.site_id(Grid.ATLAS_ID, SITE)}
	var payload := _summary_payload(slot.expected_base)
	var path := slot.folder.path_join("generation_0001/site.json")
	var checksum := _write_payload(path, payload)
	var before := FileAccess.get_file_as_string(path)
	var first := Candidate.read_site_building_summary(slot, SITE, path)
	assert(first.ok, str(first))
	assert(first.visited and first.source_checksum == checksum and first.buildings.size() == 2)
	assert(first.buildings[0].feature_id == "2" and first.buildings[1].feature_id == "7")
	assert(first.counts.house.complete == 1 and first.counts.well.building == 1)
	assert(FileAccess.get_file_as_string(path) == before and slot.source.generated_sites == 0)
	assert(Candidate.read_site_building_summary(slot, SITE, slot.folder.path_join("missing.json")).code == "NO_SAVE")
	var aggregate := Candidate.aggregate_building_summaries([first])
	assert(aggregate.ok and aggregate.visited_sites == 1 and aggregate.regions[first.region_id].counts.house.complete == 1)
	assert(not Candidate.aggregate_building_summaries([first, first]).ok, "Duplicate Site was counted twice")
	var second_world := first.duplicate(true)
	second_world.world_instance_id = "different_world"
	assert(not Candidate.aggregate_building_summaries([first, second_world]).ok)
	var other_slot := SummarySlot.new()
	other_slot.folder = _root.path_join("world_b")
	other_slot.expected_base = slot.expected_base
	assert(Candidate.read_site_building_summary(other_slot, SITE, path).code == "INVALID_SLOT")
	# A later committed generation changes version without changing stable feature IDs.
	payload.state.features["7"].progress = 8.0
	var next_path := slot.folder.path_join("generation_0002/site.json")
	var next_checksum := _write_payload(next_path, payload)
	var second := Candidate.read_site_building_summary(slot, SITE, next_path)
	assert(second.ok and second.source_checksum == next_checksum and second.source_checksum != first.source_checksum)
	assert(second.buildings[0].feature_id == "2" and second.buildings[1].feature_id == "7")
	assert(Candidate.aggregate_building_summaries([second]).source_checksum != aggregate.source_checksum)
	assert(FileAccess.get_file_as_string(path) == before, "Summary rewrote the earlier committed generation")
	# Preserve both checksum-invalid and checksum-valid/malformed evidence.
	var corrupt_path := slot.folder.path_join("invalid_checksum.json")
	_write_text(corrupt_path, before.replace(checksum, "0".repeat(64)))
	var corrupt_before := FileAccess.get_file_as_string(corrupt_path)
	assert(Candidate.read_site_building_summary(slot, SITE, corrupt_path).code == "CORRUPT_SAVE")
	assert(FileAccess.get_file_as_string(corrupt_path) == corrupt_before)
	for field: String in ["id", "feature_id", "stage", "cells", "production"]:
		var bad := payload.duplicate(true)
		match field:
			"id": bad.state.id = "another-site"
			"feature_id": bad.state.features["0"] = bad.state.features["7"].duplicate(true)
			"stage": bad.state.features["7"].stage = "invented"
			"cells": bad.state.features["7"].cells = [12, 12]
			"production": bad.state.features["7"].production = -1
		var bad_path := slot.folder.path_join("invalid_%s.json" % field)
		_write_payload(bad_path, bad)
		var bad_before := FileAccess.get_file_as_string(bad_path)
		assert(not Candidate.read_site_building_summary(slot, SITE, bad_path).ok)
		assert(FileAccess.get_file_as_string(bad_path) == bad_before)
	assert(slot.source.generated_sites == 0 and FileAccess.get_file_as_string(path) == before)
	_groups += 1
	return true

func _summary_payload(base: Dictionary) -> Dictionary:
	# Original Store envelope-reader fixture ONLY; not a playable full Site save.
	var state := {"id": base.site_id, "actors": {}, "armies": [], "next_feature": 8,
		"features": {"7": {"kind": "well", "stage": "building", "cells": [12], "progress": 3.0,
			"work": 12.0, "production": 0.0, "batch_paid": false, "status": "施工中"},
		"2": {"kind": "house", "stage": "complete", "cells": [20, 21, 120, 121], "progress": 10.0,
			"work": 10.0, "production": 0.0, "batch_paid": false, "status": "完成"}}}
	return {"format": Store.FORMAT, "terrain_version": Store.TERRAIN_VERSION, "environment_version": SiteEnvironment.VERSION,
		"preset": 0, "seed": 5, "parameters": {"size": [100, 100], "max_height": 5, "micro_strength": 0.0, "fixed_base": base}, "state": state}

func _write_payload(path: String, payload: Dictionary) -> String:
	var body := JSON.stringify(payload, "", true, true)
	var checksum := body.sha256_text()
	_write_text(path, JSON.stringify({"checksum": checksum, "payload": body}))
	return checksum

func _write_text(path: String, value: String) -> void:
	assert(path.begins_with(_root + "/"), "Candidate evidence escaped its output root")
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) == OK)
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(value)
	file.flush()
	assert(file.get_error() == OK)
	file.close()

