extends SceneTree
const Data = preload("res://scripts/region_lab/region_data.gd")
const Grid = preload("res://scripts/region_lab/region_grid.gd")
var _failed := false
var folder := ""
var natural_record: Dictionary = {}

func _initialize() -> void:
	_logger = ScriptFailureLogger.new()
	_logger.host = weakref(self)
	OS.add_logger(_logger)
	_run.call_deferred()

func _check(value: bool, message: String) -> bool:
	if _failed: return false
	if value: return true
	_failed = true
	push_error("MAP_EDITOR_UNDO_CONTRACT_FAIL: " + message)
	quit(1)
	return false

class DraftFixtureSource:
	extends RegionData
	static var natural_path := ""
	var builds := 0
	func load_manifest(_path: String = DEFAULT_MANIFEST) -> Dictionary:
		return super.load_manifest(natural_path)
	func make_author_draft(site: Vector2i, raw: Dictionary, revision: int) -> Dictionary:
		builds += 1
		return super.make_author_draft(site, raw, revision)

func _state(editor: Variant) -> Dictionary:
	return {"draft": var_to_bytes(editor.draft), "terrain": editor.terrain.fingerprint(),
		"cursor": editor._history_cursor, "native_cursor": editor._history.get_current_action(),
		"version": editor._history.get_version(), "redo": editor._history.has_redo(),
		"dirty": editor.is_dirty(), "path": editor._saved_path, "checkpoint": editor._saved_content,
		"records": var_to_bytes(editor._history_records)}

func _run() -> void:
	if "--script-error-probe" in OS.get_cmdline_user_args():
		_intentional_script_fault()
		if _failed: return
		if not _check(false, "script logger failed"): return
	if "--fail-fast-probe" in OS.get_cmdline_user_args():
		if not _check(false, "intentional first failure"): return
	folder = "user://map_editor_undo_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _check(DirAccess.make_dir_recursive_absolute(folder) == OK, "fixture folder"): return
	if not _natural(): return
	DraftFixtureSource.natural_path = str(natural_record.path)
	var editor: Variant = load("res://scripts/map_editor/map_editor.gd").new()
	editor.source = DraftFixtureSource.new()
	root.add_child(editor)
	if not _check(not editor.draft.is_empty(), "real editor uses fixed-source fixture"): return
	editor._file.text = "p2b_undo_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var saved: bool = editor.save_work()
	if not _check(saved and not editor.is_dirty(), "real saved checkpoint"): return
	var original: Dictionary = editor.draft.duplicate(true)
	var path: String = editor._saved_path
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var builds: int = editor.source.builds
	var changed: bool = editor.set_cell_patch(Vector2i(49,49), {"height": 2, "fertility": 19})
	if not _check(changed and editor.source.builds == builds + 1 and editor._history_cursor == 1 and editor.is_dirty(), "one source initialization for commit(false)"): return
	var after: Dictionary = editor.draft.duplicate(true)
	var undone: bool = editor.undo_work()
	if not _check(undone and editor.draft == original and not editor.draft.has("terrain_static") and not editor.is_dirty(), "undo restores absent keys and saved checkpoint"): return
	var baseline: Dictionary = _state(editor)
	var rejected: bool = editor.set_cell_patch(Vector2i(50,50), {"height": 6})
	if not _check(not rejected and _state(editor) == baseline and FileAccess.get_file_as_bytes(path) == bytes, "failed edit retains redo/native cursor/dirty/file"): return
	var old_hash: String = editor.source.manifest_hash
	editor.source.manifest_hash = "0".repeat(64)
	var denied_redo: bool = editor.redo_work()
	if not _check(not denied_redo and _state(editor) == baseline, "redo preflight source mismatch preserves all history"): return
	editor.source.manifest_hash = old_hash
	builds = editor.source.builds
	var redone: bool = editor.redo_work()
	if not _check(redone and editor.draft == after and editor.source.builds == builds + 1, "redo preflights once then only swaps candidate"): return
	baseline = _state(editor)
	editor.source.manifest_hash = "0".repeat(64)
	var denied_undo: bool = editor.undo_work()
	if not _check(not denied_undo and _state(editor) == baseline, "undo failure preserves state/cursor/redo/checkpoint"): return
	editor.source.manifest_hash = old_hash
	undone = editor.undo_work()
	if not _check(undone, "undo before branching"): return
	var branch: bool = editor.set_cell_patch(Vector2i(50,50), {"height": 3})
	if not _check(branch and not editor._history.has_redo() and not editor.redo_work() and not editor.draft.terrain_static.terrain.has("4949"), "valid branch drops redo and restores original missing key"): return
	editor._rename_work("Undo名稱")
	if not _check(str(editor.draft.name) == "Undo名稱", "rename enters same history"): return
	undone = editor.undo_work()
	if not _check(undone and str(editor.draft.name) == str(original.name), "name undo"): return
	baseline = _state(editor)
	var bad: Dictionary = original.duplicate(true)
	bad.source_sha256 = "f".repeat(64)
	var accepted: bool = editor._accept_work(bad, true)
	if not _check(not accepted and _state(editor) == baseline, "bad load leaves existing history"): return
	accepted = editor._accept_work(original, true)
	if not _check(accepted and editor._history_cursor == 0 and not editor._history.has_redo() and not editor._history.has_undo(), "new/open clears history only after successful admission"): return
	if not _check(FileAccess.get_file_as_bytes(path) == bytes, "undo callbacks never write files"): return
	if not _resource_commands(editor): return
	editor.free()
	if not _natural_restore_controls(): return
	if _failed: return
	print("MAP_EDITOR_UNDO_CONTRACT_PASS")
	quit(0)


func _write(name: String, bytes: PackedByteArray) -> Dictionary:
	var path: String = folder.path_join(name)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if not _check(file != null, "fixture open " + name): return {}
	file.store_buffer(bytes)
	file.flush()
	var status: int = file.get_error()
	file.close()
	if not _check(status == OK and FileAccess.get_file_as_bytes(path) == bytes, "fixture readback " + name): return {}
	return {"path": name, "bytes": bytes.size(), "sha256": FileAccess.get_sha256(path)}

func _json(name: String, value: Dictionary) -> Dictionary:
	return _write(name, JSON.stringify(value, "", true, true).to_utf8_buffer())


func _natural() -> bool:
	var classes: PackedByteArray = PackedByteArray()
	classes.resize(49); classes.fill(2)
	var summary: Dictionary = _write("summary.bin", classes)
	if _failed: return false
	summary.erase("bytes")
	summary.merge({"size": [7,7], "site_origin": [-3,-3], "encoding": "u8", "row_order": "north_to_south", "nodata": 0})
	var elevations: PackedFloat32Array = PackedFloat32Array()
	elevations.resize(121); elevations.fill(20.0)
	var tile: Dictionary = _write("elevation.bin", elevations.to_byte_array())
	if _failed: return false
	tile.erase("bytes")
	tile.merge({"id": "p2a", "size": [11,11], "origin": [-1000,-1000], "spacing_m": 200,
		"encoding": "float32_le", "row_order": "north_to_south", "nodata": -9999})
	var levels: PackedByteArray = PackedByteArray()
	levels.resize(121); levels.fill(1)
	var waters: PackedByteArray = PackedByteArray()
	waters.resize(121); waters.fill(0)
	var l: Dictionary = _write("levels.bin", levels)
	if _failed: return false
	var w: Dictionary = _write("water.bin", waters)
	if _failed: return false
	tile.derived = {"levels_path": l.path, "levels_sha256": l.sha256, "water_path": w.path, "water_sha256": w.sha256, "encoding": "u8"}
	var manifest: Dictionary = {"format": 1, "atlas_id": Grid.ATLAS_ID, "grid_contract_version": Grid.CONTRACT_VERSION,
		"crs": "EPSG:3826", "base_revision": "p2a_fixture", "sources": [], "synthetic_fixture": true,
		"grid": {"origin": [0,0], "cell_m": 2, "site_cells": 100, "region_sites": 100}, "summary": summary, "elevation_tiles": [tile], "preview_sites": [{"label": "fixture", "site": [0,0]}]}
	natural_record = _json("natural.json", manifest)
	if _failed: return false
	natural_record.path = folder.path_join("natural.json")
	natural_record.id = "natural"
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
	printerr("MAP_EDITOR_UNDO_SCRIPT_FAIL: %s:%d %s" % [file, line, message])
	quit(1)

func _intentional_script_fault() -> void:
	var missing: Dictionary = {}
	var value: Variant = missing["intentional_missing_key"]
	print("SCRIPT_FAIL_UNREACHABLE", value)



func _resource_row(kind: int, index: int, water: int = -1) -> Dictionary:
	var row: Dictionary = {"kind": kind, "cell": index, "cells": [index], "capacity": 24, "variant": 0,
		"water": water, "blocks": kind in [SiteEnvironment.Kind.TIMBER, SiteEnvironment.Kind.STONE],
		"recover": int(SiteEnvironment.RECOVERY[kind])}
	if kind == SiteEnvironment.Kind.WILDLIFE: row.identity_cell = index
	return row

func _resource_commands(editor: Variant) -> bool:
	var env: GDScript = preload("res://scripts/terrain_lab/site_environment.gd")
	var original_source: String = JSON.stringify(editor.source._author_static, "", true, true)
	# Exercise the actual button signal and form, not a replacement editor fixture.
	editor._cell_x.value = 0
	editor._cell_y.value = 10
	editor._resource_kind.select(env.Kind.FOOD)
	editor._resource_fields.capacity.value = 24
	editor._resource_fields.recover.value = 720
	editor._resource_cells.text = "1000"
	editor.get_node("AuthorColumn").find_child("AddResource", true, false).pressed.emit()
	var key: String = "author_resource:1"
	if not _check(editor.terrain.resource_base.has(key) and int(editor.draft.resource_highwater) == 1, "E04 resource UI button creates stable ID"): return false
	if not _check(int(editor.draft.initial_state.get("item_storage_version", -1)) == SiteRuntime.ITEM_STORAGE_VERSION and editor.draft.initial_state.get("actors") is Dictionary and editor.draft.initial_state.get("armies") is Array and not editor.draft.initial_state.has("world_pin"), "standard initial state retains original item/holder schemas without world binding"): return false
	var species_rows: Dictionary = editor.terrain.resource_base.duplicate(true)
	if not _check(editor.undo_work() and editor.terrain.resource_base.is_empty() and int(editor.draft.resource_highwater) == 1, "E16 resource undo removes definition without rewinding highwater"): return false
	var baseline: Dictionary = _state(editor)
	if not _check(editor.add_resource(_resource_row(env.Kind.FISH, 1000)).is_empty() and _state(editor) == baseline, "E05 land fish fails without consuming ID/cursor/redo/dirty"): return false
	if not _check(editor.redo_work() and editor.terrain.resource_base == species_rows and int(editor.draft.resource_highwater) == 1, "E16 redo restores same stable ID"): return false
	if not _check(editor.undo_work(), "undo before ID branch"): return false
	key = editor.add_resource(_resource_row(env.Kind.FOOD, 1000))
	if not _check(key == "author_resource:2" and not editor._history.has_redo(), "discarded branch never reuses ID"): return false
	if not _check(editor.move_resource(key, Vector2i(1,10)) and int(editor.terrain.resource_base[key].cell) == 1001, "resource movement keeps original key"): return false
	if not _check(editor.undo_work() and int(editor.terrain.resource_base[key].cell) == 1000 and editor.redo_work(), "resource move native undo/redo"): return false
	if not _check(editor.set_cell_patch(Vector2i(0,20), {"surface": TerrainData.Surface.WATER, "water_kind": 2, "water_body": 1000000000}, {"1000000000": {"id": "resource_sea", "kind": 2}}), "E05 original authored water owner"): return false
	# All nine kinds enter through real editor commands and the original RegionData compiler.
	for kind: int in range(9):
		if kind == env.Kind.FOOD: continue
		var index: int = 2000 if kind in [env.Kind.FISH, env.Kind.SALT] else 1100 + kind * 10
		var added: String = editor.add_resource(_resource_row(kind, index, 1000000000 if kind in [env.Kind.FISH, env.Kind.SALT] else -1))
		if not _check(not added.is_empty() and int(editor.terrain.resource_base[added].kind) == kind, "E04 compiled resource kind %d" % kind): return false
		if kind == env.Kind.WILDLIFE:
			var animal: Dictionary = editor.terrain.resource_base[added].duplicate(true)
			var before_species: String = env.resource_species(animal)
			if not _check(editor.move_resource(added, editor.terrain.cell_from_index(index + 1)) and env.resource_species(editor.terrain.resource_base[added]) == before_species, "immutable wildlife identity across parity"): return false
	if not _check(editor.terrain.resource_base.size() == 9 and editor.terrain.static_blocked[1100] == 1 and not env.work_cells(editor.terrain, key).is_empty(), "original indexes/blocking/work cells rebuilt"): return false
	var raw: Dictionary = editor.draft.terrain_static.duplicate(true)
	var source_bytes: PackedByteArray = var_to_bytes(editor.source._author_static)
	var compiled: Dictionary = editor.source.make_author_draft(Vector2i.ZERO, raw, int(editor.draft.revision))
	if not _check(compiled.ok and compiled.data.resource_base == editor.terrain.resource_base and var_to_bytes(editor.source._author_static) == source_bytes and JSON.stringify(editor.source._author_static, "", true, true) == original_source, "E04 isolated original source compiler"): return false
	if not _check(str(compiled.base.effective_environment_sha256) == RegionTerrainAdapter.author_environment_fingerprint(compiled.data), "environment fingerprint follows definitions"): return false
	var archive: String = folder.path_join("authored_resources.json")
	var fixed: TerrainData = SiteEnvironment.navigation_for_state(editor.terrain, editor.terrain.site.duplicate(true))
	fixed.site.world_pin = Data.author_projection_pin(compiled.base)
	var saved: Dictionary = SiteStore.save(fixed, archive)
	if not _check(saved.ok, "E04 original authored Store write"): return false
	var loaded: Dictionary = SiteStore.load_site(archive, func(_base: Dictionary) -> Dictionary: return editor.source.make_author_draft(Vector2i.ZERO, raw, int(editor.draft.revision)))
	if not _check(loaded.ok and loaded.data.resource_base == fixed.resource_base and loaded.data.site.changes == fixed.site.changes, "E04 original fixed-loader Store reload"): return false
	var file_bytes: PackedByteArray = FileAccess.get_file_as_bytes(archive)
	var invalid_source: Dictionary = raw.duplicate(true)
	invalid_source.resources[key].capacity = 0.5
	if not _check(not editor.source.author_static_valid(invalid_source), "untrusted resource parser rejects fractional capacity"): return false
	var invalid_load: Dictionary = SiteStore.load_site(archive, func(_base: Dictionary) -> Dictionary: return editor.source.make_author_draft(Vector2i.ZERO, invalid_source, int(editor.draft.revision)))
	if not _check(not invalid_load.ok and FileAccess.get_file_as_bytes(archive) == file_bytes, "invalid fixed loader preserves archive bytes"): return false
	# A changed water cell and removal of its fish/salt must validate as one candidate.
	var combined: Dictionary = raw.duplicate(true)
	combined.terrain["2000"] = {"surface": 0, "water_kind": 0, "water_body": -1}
	var conflict: Dictionary = editor.source.make_author_draft(Vector2i.ZERO, combined, int(editor.draft.revision))
	if not _check(not conflict.ok, "E05 terrain-only removal of fish water rejected"): return false
	for resource_key: String in combined.resources.keys():
		if combined.resources[resource_key] is Dictionary and int(combined.resources[resource_key].kind) in [env.Kind.FISH, env.Kind.SALT]: combined.resources.erase(resource_key)
	var removed_water: Dictionary = editor.source.make_author_draft(Vector2i.ZERO, combined, int(editor.draft.revision))
	if not _check(removed_water.ok, "E05 simultaneous water/resource removal uses same closure"): return false
	if not _initial_state_controls(editor, key): return false
	var preserved_family: Dictionary = editor.draft.duplicate(true)
	preserved_family.initial_state.family = {"version": 3, "complete": false, "members": [],
		"offices": SiteOffices.default_offices("family"), "family_id": "0123456789abcdef0123456789abcdef",
		"technology": SiteTechnology.empty_scope_record(str(preserved_family.initial_state.id))}
	preserved_family.revision = int(preserved_family.revision) + 1
	if not _check(editor._commit_work(preserved_family, "family v3 retained"), "E30 original empty family v3/office schema admitted"): return false
	var family_snapshot: PackedByteArray = var_to_bytes(editor.draft.initial_state.family)
	var retained: Dictionary = editor.draft.duplicate(true)
	retained.initial_state.changes[key] = {"remaining": 3, "eco_mode": "protected", "next_recovery": int(retained.initial_state.minute) + 720}
	retained.revision = int(retained.revision) + 1
	if not _check(editor._commit_work(retained, "E30 admitted management"), "original Store admits management state"): return false
	var history: Dictionary = editor.draft.initial_state.changes[key].duplicate(true)
	if not _check(editor.reset_resource(key) and editor.draft.initial_state.changes[key].eco_mode == "protected" and int(editor.draft.initial_state.changes[key].remaining) == 24, "E30 reset stock preserves ecology management"): return false
	if not _check(var_to_bytes(editor.draft.initial_state.family) == family_snapshot, "E30 reset does not downgrade family/office/technology schema"): return false
	if not _check(editor.undo_work() and editor.draft.initial_state.changes.has(key) and editor.draft.initial_state.changes[key] == history and editor.redo_work(), "E16 resource reset undo restores exact ecology history"): return false
	var reset_history: PackedByteArray = var_to_bytes(editor.draft.initial_state.changes[key])
	if not _check(editor.restore_resource_definition(key) and editor.draft.initial_state.changes[key].eco_mode == "protected" and var_to_bytes(editor.draft.initial_state.family) == family_snapshot, "E30 definition restore retains management/family/office schemas"): return false
	var restored_history: PackedByteArray = var_to_bytes(editor.draft.initial_state.changes[key])
	if not _check(editor.undo_work() and editor.draft.initial_state.changes.has(key) and var_to_bytes(editor.draft.initial_state.changes[key]) == reset_history, "definition restore Undo recovers exact operational history"): return false
	if not _check(editor.redo_work() and editor.draft.initial_state.changes.has(key) and var_to_bytes(editor.draft.initial_state.changes[key]) == restored_history and editor.undo_work() and editor.draft.initial_state.changes.has(key) and var_to_bytes(editor.draft.initial_state.changes[key]) == reset_history, "definition restore Redo and second Undo preserve exact operational history"): return false
	baseline = _state(editor)
	if not _check(not editor.remove_resource(key) and _state(editor) == baseline, "E30 source deletion cannot erase retained history"): return false
	for field: String in ["crowd", "fire", "world_pin", "region_snapshot"]:
		var busy: Dictionary = editor.draft.duplicate(true)
		busy.initial_state[field] = {"retained": true}
		busy.revision = int(busy.revision) + 1
		if not _check(not editor._commit_work(busy, "must refuse") and _state(editor) == baseline, "E22 unsafe source retains bytes " + field): return false
	var external: Dictionary = editor.draft.duplicate(true)
	external.initial_state.family.technology = {"version": 3, "holder_site_id": "external_site", "epoch": 1}
	external.revision = int(external.revision) + 1
	var external_bytes: PackedByteArray = var_to_bytes(external)
	if not _check(not editor._commit_work(external, "unbound holder") and var_to_bytes(external) == external_bytes and _state(editor) == baseline, "E30 external earned-holder refuses without local regrant"): return false
	var family: Dictionary = editor.draft.duplicate(true)
	family.initial_state.family = {"version": 3, "technology": {"first_earned": {"F01": {"retained": true}}}, "members": []}
	family.revision = int(family.revision) + 1
	var family_bytes: PackedByteArray = var_to_bytes(family)
	if not _check(not editor._commit_work(family, "unsupported earned binding") and var_to_bytes(family) == family_bytes and _state(editor) == baseline, "E30 unsupported family/first-earned refuses without downgrade/grant/clear"): return false
	var pin: String = editor.source.manifest_hash
	editor.source.manifest_hash = "f".repeat(64)
	if not _check(not editor.undo_work() and _state(editor) == baseline, "E16 resource undo preflight failure retains native cursor/redo/highwater"): return false
	editor.source.manifest_hash = pin
	editor._file.text = "p2b_resources_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _check(editor.save_work(), "resource draft save with allocator/state"): return false
	var path: String = editor._saved_path
	var saved_work: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var before_load: Dictionary = editor.draft.duplicate(true)
	var highwater: int = int(editor.draft.resource_highwater)
	editor._open_work(path)
	if not _check(editor.draft == before_load and not editor.is_dirty() and editor._history_cursor == 0, "save/reload preserves authored definitions and initial closure"): return false
	for field: String in ["minute", "next_feature", "depot_cell", "capacity"]:
		if not _check(editor.draft.initial_state[field] is int, "original Store integral field restored after author JSON reload: " + field): return false
	var last: String = editor.add_resource(_resource_row(env.Kind.CLAY, 1500))
	if not _check(last == "author_resource:%d" % (highwater + 1) and FileAccess.get_file_as_bytes(path) == saved_work, "persisted highwater prevents ID reuse after reload"): return false
	if not _check(editor.undo_work() and editor.redo_work() and editor.terrain.resource_base.has(last), "resource history remains connected after reload"): return false
	return true

func _select_resource(editor: Variant, key: String) -> bool:
	for index: int in range(editor._resource_list.item_count):
		if str(editor._resource_list.get_item_metadata(index)) == key:
			editor._resource_list.select(index)
			editor._resource_list.item_selected.emit(index)
			return true
	return false

func _initial_state_controls(editor: Variant, key: String) -> bool:
	var inventory: PackedByteArray = var_to_bytes(editor.draft.initial_state.inventory)
	if not _check(_select_resource(editor, key), "initial-state UI source selection"): return false
	editor._resource_state_fields.remaining.value = 5
	editor._resource_state_fields.next_recovery.value = 720
	editor._resource_cleared.button_pressed = false
	editor._resource_discovered.button_pressed = false
	editor.get_node("AuthorColumn").find_child("ApplyResourceInitialState", true, false).pressed.emit()
	var fields: Dictionary = editor.draft.initial_state.changes.get(key, {})
	if not _check(fields.get("remaining") == 5 and fields.get("discovered") == false and fields.get("next_recovery") == 720, "E04 actual initial-state button writes original changes"): return false
	var original_delta: PackedByteArray = var_to_bytes(fields)
	if not _check(editor.undo_work() and not editor.draft.initial_state.changes.has(key) and editor.redo_work() and editor.draft.initial_state.changes.has(key) and var_to_bytes(editor.draft.initial_state.changes[key]) == original_delta, "E16 initial-state Undo/Redo preserves exact delta"): return false
	var baseline: Dictionary = _state(editor)
	for invalid: Dictionary in [{"remaining": 0.5}, {"remaining": NAN}, {"remaining": 25}, {"cleared": 1}, {"discovered": "yes"}, {"recover": 0}, {"cleared": true, "next_recovery": 1}, {"used": 0.5}]:
		if not _check(not editor.set_resource_initial_state(key, invalid) and _state(editor) == baseline, "illegal initial fields preserve bytes/cursor/redo/dirty/highwater"): return false
	if not _check(_select_resource(editor, key), "definition restore selection"): return false
	editor.get_node("AuthorColumn").find_child("RestoreResourceDefinition", true, false).pressed.emit()
	var resource: Dictionary = SiteEnvironment.resource(editor.terrain, key)
	if not _check(int(resource.remaining) == 24 and bool(resource.discovered) and not bool(resource.cleared) and int(resource.next_recovery) == -1, "E04 distinct definition restore clears only initial operational overrides"): return false
	if not _check(editor.undo_work() and editor.draft.initial_state.changes.has(key) and var_to_bytes(editor.draft.initial_state.changes[key]) == original_delta and editor.redo_work(), "definition restore native Undo/Redo"): return false
	var salt: String = ""
	var stone: String = ""
	for resource_key: String in editor.terrain.resource_base:
		var kind: int = int(editor.terrain.resource_base[resource_key].kind)
		if kind == SiteEnvironment.Kind.SALT: salt = resource_key
		if kind == SiteEnvironment.Kind.STONE: stone = resource_key
	if not _check(not salt.is_empty() and not stone.is_empty(), "salt and finite source fixtures"): return false
	baseline = _state(editor)
	if not _check(not editor.set_resource_initial_state(stone, {"remaining": 0, "next_recovery": 1}) and _state(editor) == baseline, "recover0 initial stale schedule rejected"): return false
	if not _check(_select_resource(editor, salt), "salt initial UI selection"): return false
	if not _check(editor._selected_resource() == salt and editor.draft.initial_state.get("minute") == 0 and int(editor.terrain.resource_base[salt].kind) == SiteEnvironment.Kind.SALT and int(editor.terrain.resource_base[salt].capacity) == 24 and int(editor.terrain.resource_base[salt].recover) == 0, "salt UI fixture must be selected on the original zero-minute finite source"): return false
	editor._resource_state_fields.remaining.value = 1
	editor._resource_state_fields.next_recovery.value = -1
	editor._resource_state_fields.used.value = 0.125
	editor._resource_state_fields.used_minute.value = 0
	editor._resource_cleared.button_pressed = false
	editor._resource_discovered.button_pressed = false
	var salt_form: Dictionary = {"selected": editor._selected_resource(), "remaining": editor._resource_state_fields.remaining.value,
		"next_recovery": editor._resource_state_fields.next_recovery.value, "used": editor._resource_state_fields.used.value,
		"used_minute": editor._resource_state_fields.used_minute.value, "cleared": editor._resource_cleared.button_pressed,
		"discovered": editor._resource_discovered.button_pressed}
	if not _check(salt_form.selected == salt and salt_form.remaining == 1 and salt_form.next_recovery == -1 and salt_form.used == 0.125 and salt_form.used_minute == 0 and not salt_form.cleared and not salt_form.discovered, "salt UI input setup: " + JSON.stringify(salt_form)): return false
	var salt_before: Dictionary = _state(editor)
	editor.get_node("AuthorColumn").find_child("ApplyResourceInitialState", true, false).pressed.emit()
	var salt_delta: Variant = editor.draft.initial_state.changes.get(salt)
	if not _check(salt_delta is Dictionary and salt_delta.has("used") and salt_delta.has("used_minute"), "salt UI did not commit quota delta for %s; selected=%s; unchanged=%s; status=%s" % [salt, editor._selected_resource(), _state(editor) == salt_before, editor._status.text]): return false
	if not _check(salt_delta.used == 0.125 and int(salt_delta.used_minute) == 0, "E04 actual salt UI admits original finite float quota"): return false
	for field: Variant in salt_delta:
		if not _check(field is String, "salt UI emits original String field keys"): return false
	var salt_committed: PackedByteArray = var_to_bytes(editor.draft)
	if not _check(editor.undo_work() and var_to_bytes(editor.draft) == salt_before.draft and editor.redo_work() and var_to_bytes(editor.draft) == salt_committed, "E16 salt UI native Undo/Redo preserves exact draft and fractional quota"): return false
	for fraction: float in [0.25, 0.125]:
		if not _check(editor.set_resource_initial_state(salt, {"used": fraction, "used_minute": 0}) and _select_resource(editor, salt), "original finite float usage selected"): return false
		if not _check(float(editor._resource_state_fields.used.value) == fraction and editor._resource_state_fields.used.get_line_edit().text.to_float() == fraction, "salt UI displays unquantized non-half usage"): return false
		editor._resource_state_fields.remaining.value = 2
		editor._resource_discovered.button_pressed = true
		editor.get_node("AuthorColumn").find_child("ApplyResourceInitialState", true, false).pressed.emit()
		salt_delta = editor.draft.initial_state.changes.get(salt)
		if not _check(salt_delta is Dictionary and salt_delta.has("used") and salt_delta.has("used_minute"), "salt UI lost quota delta for %s; selected=%s; status=%s" % [salt, editor._selected_resource(), editor._status.text]): return false
		if not _check(salt_delta.used == fraction and int(salt_delta.used_minute) == 0, "editing other initial fields preserves exact original float quota"): return false
	baseline = _state(editor)
	for invalid: Dictionary in [{"used": NAN}, {"used": 25.0}, {"used_minute": 1}, {"next_recovery": 1}]:
		if not _check(not editor.set_resource_initial_state(salt, invalid) and _state(editor) == baseline, "salt quota/clock/recover0 guard cannot be bypassed"): return false
	if not _check(editor.restore_resource_definition(salt), "restore salt definition"): return false
	var restored: Dictionary = SiteEnvironment.resource(editor.terrain, salt)
	if not _check(int(restored.remaining) == 24 and bool(restored.discovered) and restored.has("used") and restored.has("used_minute") and restored.used == 0.125 and int(restored.used_minute) == 0, "E30 definition restore retains salt usage and same-minute quota"): return false
	baseline = _state(editor)
	if not _check(not editor.restore_natural_resource(key) and _state(editor) == baseline, "new author source has no invented natural counterpart"): return false
	if not _check(var_to_bytes(editor.draft.initial_state.inventory) == inventory, "initial resource stock never creates inventory items"): return false
	return true

func _natural_restore_controls() -> bool:
	# Use the same verified Taiwan forest site as the original Region resource contract.
	# The test whitelist admits that real source Site; production chooser rules stay unchanged.
	var editor: Variant = load("res://scripts/map_editor/map_editor.gd").new()
	root.add_child(editor)
	if not _check(not editor.draft.is_empty() and not editor.source.resource_manifest_hash.is_empty(), "original paired Taiwan source admitted"): return false
	var forest: Vector2i = Vector2i(1170,13252)
	var summary: Dictionary = editor.source.get_site_summary(forest.x, forest.y)
	if not _check(summary.ok and summary.has_terrain, "verified original forest Site"): return false
	if forest not in editor._samples: editor._samples.append(forest)
	if not _check(editor.new_work(forest), "real natural resource candidate"): return false
	var originals: Dictionary = editor.terrain.resource_base.duplicate(true)
	var food: String = ""
	var wildlife: String = ""
	for key: String in originals:
		var row: Dictionary = originals[key]
		if int(row.kind) in [SiteEnvironment.Kind.FOOD, SiteEnvironment.Kind.HERB] and food.is_empty(): food = key
		var cell: Vector2i = editor.terrain.cell_from_index(int(row.cell))
		if int(row.kind) == SiteEnvironment.Kind.WILDLIFE and cell.x > 1 and cell.x < 98 and cell.y > 1 and cell.y < 98 and wildlife.is_empty(): wildlife = key
	if not _check(not food.is_empty() and not wildlife.is_empty(), "original generated food and legacy wildlife fixtures"): return false
	var animal: Dictionary = originals[wildlife]
	var species: String = SiteEnvironment.resource_species(animal)
	var anchor: Vector2i = editor.terrain.cell_from_index(int(animal.cell))
	if not _check(not animal.has("identity_cell") and editor.move_resource(wildlife, anchor + Vector2i.RIGHT), "legacy first move through real editor/compiler"): return false
	if not _check(int(editor.terrain.resource_base[wildlife].identity_cell) == int(animal.cell) and SiteEnvironment.resource_species(editor.terrain.resource_base[wildlife]) == species, "legacy first move freezes identity before parity change"): return false
	var moved: Dictionary = editor.terrain.resource_base[wildlife].duplicate(true)
	if not _check(editor.undo_work() and not editor.terrain.resource_base[wildlife].has("identity_cell") and editor.terrain.resource_base[wildlife] == animal and editor.redo_work() and editor.terrain.resource_base[wildlife] == moved, "E04/E16 legacy natural key Undo/Redo preserves absent identity and same species"): return false
	if not _check(editor.restore_natural_resource(wildlife) and editor.terrain.resource_base[wildlife] == animal and not editor.draft.terrain_static.resources.has(wildlife), "natural restore removes only static override"): return false
	if not _check(editor.undo_work() and editor.terrain.resource_base[wildlife] == moved and editor.redo_work(), "natural restore native Undo/Redo"): return false
	var edited: Dictionary = originals[food].duplicate(true)
	edited.capacity = int(edited.capacity) + 10
	if not _check(editor.set_resource(food, edited) and editor.set_resource_initial_state(food, {"remaining": int(edited.capacity) - 1, "discovered": false}), "natural override and explicit initial delta admitted"): return false
	var baseline: Dictionary = _state(editor)
	if not _check(not editor.restore_natural_resource(food) and _state(editor) == baseline, "natural restoration refuses incompatible initial capacity without clearing history"): return false
	if not _check(editor.set_resource_initial_state(food, {"remaining": int(originals[food].capacity)}), "explicitly reconcile retained delta before restoring natural source"): return false
	var history: PackedByteArray = var_to_bytes(editor.draft.initial_state.changes[food])
	if not _check(_select_resource(editor, food), "natural restore UI selection"): return false
	editor.get_node("AuthorColumn").find_child("RestoreNaturalResource", true, false).pressed.emit()
	if not _check(editor.terrain.resource_base[food] == originals[food] and var_to_bytes(editor.draft.initial_state.changes[food]) == history, "E30 natural restore UI preserves every initial delta field"): return false
	# Deleted natural keys remain selectable so the UI can remove a tombstone.
	if not _check(editor.undo_work(), "undo natural restore before tombstone case"): return false
	if not _check(editor.undo_work(), "undo retained initial reconciliation"): return false
	if not _check(editor.undo_work(), "undo explicit initial delta"): return false
	if not _check(editor.undo_work(), "undo author definition override"): return false
	if not _check(editor.remove_resource(food) and not editor.terrain.resource_base.has(food) and _select_resource(editor, food), "deleted natural source remains selectable"): return false
	editor.get_node("AuthorColumn").find_child("RestoreNaturalResource", true, false).pressed.emit()
	if not _check(editor.terrain.resource_base[food] == originals[food] and not editor.draft.terrain_static.resources.has(food), "restore natural UI removes tombstone"): return false
	if not _check(editor.move_resource(wildlife, anchor + Vector2i.RIGHT), "legacy move before persisted reload"): return false
	editor._file.text = "p2b_natural_restore_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _check(editor.save_work(), "legacy definition draft persisted"): return false
	var path: String = editor._saved_path
	var before_reload: Dictionary = editor.terrain.resource_base.duplicate(true)
	editor._open_work(path)
	if not _check(editor.terrain.resource_base == before_reload and SiteEnvironment.resource_species(editor.terrain.resource_base[wildlife]) == species, "E04 legacy identity survives real source reload"): return false
	var base: Dictionary = editor.terrain.parameters.fixed_base
	if not _check(base.resource_fingerprint == JSON.stringify(editor.terrain.resource_base, "", true, true).sha256_text(), "actual paired resource fingerprint follows author override"): return false
	var archive: String = folder.path_join("natural_override_store.json")
	var data: TerrainData = SiteEnvironment.navigation_for_state(editor.terrain, editor.terrain.site.duplicate(true))
	data.site.world_pin = Data.author_projection_pin(base)
	if not _check(SiteStore.save(data, archive).ok, "actual paired authored Store save"): return false
	var raw: Dictionary = editor.draft.terrain_static.duplicate(true)
	var restored: Dictionary = SiteStore.load_site(archive, func(_base: Dictionary) -> Dictionary: return editor.source.make_author_draft(forest, raw, int(editor.draft.revision)))
	if not _check(restored.ok and restored.data.resource_base == before_reload and SiteEnvironment.resource_species(restored.data.resource_base[wildlife]) == species, "actual paired fixed-loader reload preserves legacy identity/resource fingerprint"): return false
	editor.free()
	return true
