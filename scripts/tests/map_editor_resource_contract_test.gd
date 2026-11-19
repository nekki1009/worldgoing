extends SceneTree
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
var _failed := false
var folder := ""

func _initialize() -> void:
	_logger = ScriptFailureLogger.new()
	_logger.host = weakref(self)
	OS.add_logger(_logger)
	_run.call_deferred()

func _check(value: bool, message: String) -> bool:
	if _failed: return false
	if value: return true
	_failed = true
	push_error("MAP_EDITOR_RESOURCE_CONTRACT_FAIL: " + message)
	quit(1)
	return false

func _map() -> TerrainData:
	var data: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345, {"size": Vector2i(32,32)})
	Env.initialize(data, "p2b_resource_fixture")
	data.resource_base.clear()
	data.height_levels.fill(1)
	data.surface_types.fill(TerrainData.Surface.GRASS)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.ramp_edges.fill(0)
	data.cliff_drops.fill(0)
	data.water_kind.fill(0)
	data.water_body.fill(-1)
	data.site.changes.clear()
	data.site.minute = 20
	for index: int in [500,501]:
		data.surface_types[index] = TerrainData.Surface.WATER
		data.flags[index] = 0
		data.water_kind[index] = 1
		data.water_body[index] = 9
	for index: int in [600,601]: data.water_kind[index] = 3
	Env.rebuild_indexes(data)
	var captured: Dictionary = Store.save(data, "", null, false, {}, true)
	if not _check(captured.ok, "original Store capture of fixture"): return data
	data.site = captured.state
	return data

func _row(data: TerrainData, kind: int, index: int) -> Dictionary:
	var value: Dictionary = {"kind": kind, "cell": index, "cells": [index], "capacity": 2 if kind == Env.Kind.SALT else 24, "variant": 0,
		"water": int(data.water_body[index]), "blocks": kind in [Env.Kind.TIMBER, Env.Kind.STONE], "recover": int(Env.RECOVERY[kind])}
	if kind == Env.Kind.WILDLIFE: value.identity_cell = index
	return value

func _source(data: TerrainData) -> TerrainData:
	return Env.navigation_for_state(data, {})

func _run() -> void:
	if "--script-error-probe" in OS.get_cmdline_user_args():
		_intentional_script_fault()
		if _failed: return
		if not _check(false, "script logger failed"): return
	if "--fail-fast-probe" in OS.get_cmdline_user_args():
		if not _check(false, "intentional first failure"): return
	folder = "user://map_editor_resource_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _check(DirAccess.make_dir_recursive_absolute(folder) == OK, "fixture folder"): return
	var data: TerrainData = _map()
	if _failed: return
	var definitions := {}
	for kind: int in range(Env.NAMES.size()):
		var index: int = 500 if kind == Env.Kind.FISH else (600 if kind == Env.Kind.SALT else 100 + kind * 20)
		definitions["author_resource:%d" % (kind + 1)] = _row(data, kind, index)
	var original: PackedByteArray = var_to_bytes(data.site)
	var prepared: Dictionary = Env.prepare_author_resource_source(_source(data), definitions)
	if not _check(prepared.ok and prepared.data.resource_base.size() == 9 and data.resource_base.is_empty() and var_to_bytes(data.site) == original, "nine definitions with no original mutation"): return
	var candidate: TerrainData = Env.navigation_for_state(prepared.data, data.site.duplicate(true))
	for key: String in candidate.resource_base:
		if not _check(not Env.work_cells(candidate, key).is_empty(), "original work cells " + key): return
		var pure: TerrainData = _source(candidate)
		var removed: Dictionary = Env.prepare_author_resource_source(pure, {key: null})
		if not _check(removed.ok and not removed.data.resource_base.has(key) and candidate.resource_base.has(key), "each kind remove is isolated"): return
		var moved: Dictionary = candidate.resource_base[key].duplicate(true)
		moved.cell = int(moved.cell) + 1
		moved.cells = [int(moved.cell)]
		var moved_result: Dictionary = Env.prepare_author_resource_source(pure, {key: moved})
		if not _check(moved_result.ok and moved_result.data.resource_base[key].cell == moved.cell, "move stable source key " + key): return
	var forbidden: Array[Dictionary] = []
	for field: String in ["kind", "capacity", "variant", "recover", "cell"]:
		var row: Dictionary = definitions["author_resource:1"].duplicate(true)
		row[field] = 0.5
		forbidden.append(row)
	for invalid: Dictionary in [{"kind": 9}, {"capacity": 0}, {"variant": 3}, {"recover": -1}, {"capacity": NAN}]:
		var invalid_row: Dictionary = definitions["author_resource:1"].duplicate(true)
		invalid_row.merge(invalid, true)
		forbidden.append(invalid_row)
	var empty: Dictionary = definitions["author_resource:1"].duplicate(true)
	empty.cells = []
	forbidden.append(empty)
	var duplicate: Dictionary = definitions["author_resource:1"].duplicate(true)
	duplicate.cells.append(duplicate.cell)
	forbidden.append(duplicate)
	var unknown: Dictionary = definitions["author_resource:1"].duplicate(true)
	unknown.extra = true
	forbidden.append(unknown)
	var blocks: Dictionary = definitions["author_resource:1"].duplicate(true)
	blocks.blocks = false
	forbidden.append(blocks)
	var excess: Dictionary = definitions["author_resource:1"].duplicate(true)
	excess.capacity = 1000001
	forbidden.append(excess)
	var wrong_fish: Dictionary = definitions["author_resource:8"].duplicate(true)
	wrong_fish.cell = 501
	wrong_fish.cells = [501]
	wrong_fish.water = -1
	forbidden.append(wrong_fish)
	for row: Dictionary in forbidden:
		var denied: Dictionary = Env.prepare_author_resource_source(_source(data), {"author_resource:40": row})
		if not _check(not denied.ok and var_to_bytes(data.site) == original and data.resource_base.is_empty(), "invalid definition leaves source bytes"): return
	if not _check(not Env.prepare_author_resource_source(_source(data), {"depot": definitions["author_resource:1"]}).ok, "reserved key"): return
	# Legacy identity is frozen before changing the original anchor across parity.
	var legacy: TerrainData = _source(data)
	var animal: Dictionary = definitions["author_resource:9"].duplicate(true)
	animal.erase("identity_cell")
	legacy.resource_base = {"8:260": animal}
	var moved_animal: Dictionary = animal.duplicate(true)
	moved_animal.cell = 261
	moved_animal.cells = [261]
	var moved: Dictionary = Env.prepare_author_resource_source(legacy, {"8:260": moved_animal})
	if not _check(moved.ok and int(moved.data.resource_base["8:260"].identity_cell) == 260 and Env.resource_species(moved.data.resource_base["8:260"]) == Env.resource_species(animal), "legacy parity identity"): return
	var changed_identity: Dictionary = moved.data.resource_base["8:260"].duplicate(true)
	changed_identity.identity_cell = 261
	if not _check(not Env.prepare_author_resource_source(_source(moved.data), {"8:260": changed_identity}).ok, "identity mutation rejected"): return
	var decoded: Variant = JSON.parse_string(JSON.stringify(moved.data.resource_base, "", true, true))
	if not _check(Env.validate_resource_definitions(moved.data, decoded).ok and Env.resource_species(decoded["8:260"]) == "stag" and Runtime.capturable_species(decoded["8:260"]).is_empty(), "JSON identity and capture agree"): return
	var art_before: int = SiteResourceView.resource_art_index(animal)
	var art_after: int = SiteResourceView.resource_art_index(decoded["8:260"])
	if not _check(art_before == art_after, "original View and capture share immutable resolver"): return
	if not _finite_restore(candidate): return
	if not _clock_and_reset(candidate): return
	if not _store_boundary(): return
	if _failed: return
	print("MAP_EDITOR_RESOURCE_CONTRACT_PASS")
	quit(0)

func _finite_restore(data: TerrainData) -> bool:
	var candidate: TerrainData = Env.navigation_for_state(data, data.site.duplicate(true))
	candidate.resource_base = data.resource_base.duplicate(true)
	var key := "author_resource:6"
	candidate.resource_base[key].recover = 0
	var anchor: int = int(candidate.resource_base[key].cell)
	candidate.resource_base[key].cells = [anchor, anchor + 1]
	Env.change(candidate, key, {"remaining": int(candidate.resource_base[key].capacity), "cleared": false, "next_recovery": -1, "eco_mode": "general"})
	Env.rebuild_indexes(candidate)
	var finite_info: Dictionary = Env.ecology_info(candidate, key)
	if not _check(finite_info.recovery_blocked == "FINITE" and int(finite_info.takeable) > 0, "recover0 unobstructed stock remains harvestable"): return false
	# Derived occupancy is the input to the original habitat/info query; no live feature owner is edited.
	candidate.feature_at[anchor] = 1
	var occupied_info: Dictionary = Env.ecology_info(candidate, key)
	if not _check(occupied_info.recovery_blocked == "OCCUPIED" and int(occupied_info.takeable) == 0, "recover0 keeps occupancy ahead of finite reason"): return false
	candidate.feature_at[anchor + 1] = 1
	var habitat_info: Dictionary = Env.ecology_info(candidate, key)
	if not _check(habitat_info.recovery_blocked == "NO_HABITAT" and int(habitat_info.takeable) == 0, "recover0 keeps habitat denial ahead of finite reason"): return false
	candidate.feature_at.fill(0)
	Env.change(candidate, key, {"remaining": 0, "cleared": true, "next_recovery": -1, "eco_mode": "general"})
	var info: Dictionary = Env.ecology_info(candidate, key)
	if not _check(not info.renewable and not info.recoverable and not info.restorable, "recover0 information does not promise regeneration"): return false
	var before: PackedByteArray = var_to_bytes(candidate.site)
	var cargo := {}
	var result: Dictionary = Runtime.harvest(candidate, key, Env.work_cells(candidate, key)[0], cargo, "restore")
	if not _check(not result.ok and var_to_bytes(candidate.site) == before and cargo.is_empty() and Env.validate_resource_deltas(candidate, candidate.site).ok, "restore recover0 rejected without stale schedule"): return false
	return true

func _clock_and_reset(data: TerrainData) -> bool:
	var food := "author_resource:6"
	Env.change(data, food, {"remaining": 0, "eco_mode": "protected", "next_recovery": int(data.site.minute) + int(data.resource_base[food].recover)})
	var finite := "author_resource:2"
	Env.change(data, finite, {"remaining": 0})
	var malformed: Dictionary = data.site.duplicate(true)
	malformed.changes[finite].next_recovery = 21
	if not _check(not Env.validate_resource_deltas(data, malformed).ok, "recover0 stale schedule rejected"): return false
	# A defensive regenerate guard must not execute even an invalid legacy schedule.
	var defensive: TerrainData = Env.navigation_for_state(data, malformed)
	defensive.site.minute = 21
	Runtime._regenerate(defensive, Callable())
	if not _check(int(Env.resource(defensive, finite).remaining) == 0, "recover0 never regenerates"): return false
	var salt := "author_resource:5"
	var actor: Vector2i = Env.work_cells(data, salt)[0]
	var cargo := {}
	var first: Dictionary = Runtime.harvest(data, salt, actor, cargo)
	if not _check(first.ok, "salt first quota"): return false
	var before_remaining: int = int(Env.resource(data, salt).remaining)
	var reset: Dictionary = Env.prepare_author_resource_state(data, data.site, salt)
	if not _check(reset.ok and int(Env.resource(reset.data, salt).used) == 2 and int(Env.resource(reset.data, salt).remaining) == before_remaining, "reset retains salt minute usage"): return false
	var quota: Dictionary = Runtime.harvest(data, salt, actor, cargo)
	if not _check(not quota.ok and int(Env.resource(data, salt).used) == 2, "same minute exhausted"): return false
	data.site.minute = int(data.site.minute) + 1
	var next: Dictionary = Runtime.harvest(data, salt, actor, cargo)
	if not _check(next.ok and int(Env.resource(data, salt).remaining) == before_remaining, "next minute quota renews without stock decrement"): return false
	var fractional: Dictionary = data.site.duplicate(true)
	fractional.changes[salt].used = 0.5
	if not _check(Env.validate_resource_deltas(data, fractional).ok, "legacy finite float salt usage remains admitted"): return false
	var orphan_source: Dictionary = Env.prepare_author_resource_source(_source(data), {food: null})
	if not _check(orphan_source.ok, "private deletion source preflight"): return false
	var orphan: Dictionary = Env.prepare_author_resource_state(orphan_source.data, data.site)
	if not _check(not orphan.ok and data.site.changes[food].eco_mode == "protected", "deletion cannot erase ecology management history"): return false
	var source_bytes: PackedByteArray = var_to_bytes(data.site)
	var food_reset: Dictionary = Env.prepare_author_resource_state(data, data.site, food)
	if not _check(food_reset.ok and food_reset.state.ecology_version == data.site.ecology_version and food_reset.state.changes[food].eco_mode == "protected" and var_to_bytes(data.site) == source_bytes, "reset preserves management and source history"): return false
	var due: TerrainData = Env.navigation_for_state(data, data.site.duplicate(true))
	due.site.minute = int(due.site.changes[food].next_recovery)
	Runtime._regenerate(due, Callable())
	if not _check(int(Env.resource(due, food).remaining) > 0 and int(Env.resource(due, finite).remaining) == 0, "renewable versus finite schedule"): return false
	for field: String in ["crowd", "world_pin", "region_snapshot", "fire", "travel_identity"]:
		var unsafe: Dictionary = data.site.duplicate(true)
		unsafe[field] = {"retained": true}
		var bytes: PackedByteArray = var_to_bytes(unsafe)
		var denied: Dictionary = Env.prepare_author_resource_state(data, unsafe, food)
		if not _check(not denied.ok and var_to_bytes(unsafe) == bytes and var_to_bytes(data.site) == source_bytes, "unsafe import unchanged " + field): return false
	return true

func _store_boundary() -> bool:
	var data: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345)
	Env.initialize(data, "p2b_natural_store")
	var path: String = folder.path_join("natural.json")
	var saved: Dictionary = Store.save(data, path)
	if not _check(saved.ok, "original natural Store save"): return false
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var loaded: Dictionary = Store.load_site(path)
	if not _check(loaded.ok and loaded.data.resource_base == data.resource_base, "natural definition reload unchanged"): return false
	var finite := ""
	for source_key: String in data.resource_base:
		if int(data.resource_base[source_key].recover) == 0:
			finite = source_key
			break
	if not _check(not finite.is_empty(), "finite original source fixture"): return false
	Env.change(data, finite, {"remaining": 0, "next_recovery": 0})
	var stale: Dictionary = Store.save(data, path)
	if not _check(not stale.ok and FileAccess.get_file_as_bytes(path) == bytes, "Store save rejects recover0 stale schedule before file replacement"): return false
	data.site.changes.erase(finite)
	var key: String = data.resource_base.keys()[0]
	data.resource_base[key].cells = []
	var denied: Dictionary = Store.save(data, path)
	if not _check(not denied.ok and FileAccess.get_file_as_bytes(path) == bytes, "Store rejects malformed source before replacing file"): return false
	return true


class ScriptFailureLogger:
	extends Logger
	var host: WeakRef
	var mutex: Mutex = Mutex.new()
	var seen := false
	func _log_error(_function: String, file: String, line: int, _code: String, rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != Logger.ERROR_TYPE_SCRIPT: return
		mutex.lock()
		var first: bool = not seen
		seen = true
		mutex.unlock()
		if not first: return
		var target: Variant = host.get_ref()
		if not is_instance_valid(target): return
		if Thread.is_main_thread(): target._script_failure(file, line, rationale)
		else: target.call_deferred("_script_failure", file, line, rationale)

var _logger: ScriptFailureLogger

func _script_failure(file: String, line: int, message: String) -> void:
	_failed = true
	printerr("MAP_EDITOR_RESOURCE_SCRIPT_FAIL: %s:%d %s" % [file, line, message])
	quit(1)

func _intentional_script_fault() -> void:
	var missing: Dictionary = {}
	var value: Variant = missing["intentional_missing_key"]
	print("SCRIPT_FAIL_UNREACHABLE", value)
