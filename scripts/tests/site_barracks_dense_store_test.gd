extends "res://scripts/tests/site_military_building_contract_test.gd"
## Real SiteStore files in an isolated test directory; no formal saves are used.
const DENSE_SAVE_ROOT := "res://.godot-temp/site_barracks_dense_store"
var rejected_files := 0

func _run() -> void:
	create_timer(80.0).timeout.connect(func() -> void: quit(1))
	completed = 0
	assert(DirAccess.make_dir_recursive_absolute(DENSE_SAVE_ROOT) == OK)
	for quarter: int in range(4):
		_check_dense_legacy_store(quarter)
	for side: int in [10, 50]:
		_check_dense_current_store(side)
	_check_dense_pending_store()
	if completed != 7 or rejected_files != 23:
		push_error("A dense Store acceptance group stopped before completion")
		quit(1)
		return
	print("SITE_BARRACKS_DENSE_STORE_PASS: missing-version legacy geometry/capacity preserved in four directions; v2 10x10 and 50x50 roundtrips; paid expansion resume; 23 invalid-version files rejected without changing live state or valid saves")
	quit(0)

func _dense_geometry(data: TerrainData, key: String) -> Dictionary:
	var feature: Dictionary = data.site.features[key]
	var modules: Array = []
	for module: Dictionary in SiteRuntime.military_modules(data, feature):
		modules.append({"kind": module.kind, "variant": module.variant, "quarter": module.quarter, "cells": module.cells})
	return {"modules": JSON.parse_string(JSON.stringify(modules)),
		"blocked": SiteRuntime.feature_geometry(data, feature).blocked,
		"standing": SiteRuntime.military_walkable_cells(data, feature),
		"capacity": SiteRuntime.military_capacity(data, feature)}

func _check_dense_legacy_store(quarter: int) -> void:
	var data := _military_store_fixture("dense-legacy-q%d" % quarter)
	var key := _build(data, "barracks", Vector2i(10, 10), Vector2i(10, 10), {"barracks_layout_version": 1, "quarter": quarter})
	var feature: Dictionary = data.site.features[key]
	assert(int(feature.barracks_layout_version) == 1)
	var original := _dense_geometry(data, key)
	assert(original.modules.size() == 3 and original.blocked.size() == 28 and original.capacity == 72)
	feature.erase("barracks_layout_version") # Exact pre-redesign serialized feature shape.
	assert(_dense_geometry(data, key) == original)
	var path := DENSE_SAVE_ROOT.path_join("legacy_q%d.json" % quarter)
	var saved := SiteStore.save(data, path)
	assert(saved.ok, str(saved))
	var loaded := SiteStore.load_site(path)
	assert(loaded.ok, str(loaded))
	var restored: TerrainData = loaded.data
	assert(int(restored.site.features[key].get("barracks_layout_version", 1)) == 1)
	assert(_dense_geometry(restored, key) == original, "Loading a missing-version barracks silently rearranged its original occupied cells/capacity")
	assert(restored.static_blocked == data.static_blocked and restored.feature_at == data.feature_at)
	# An old unfinished expansion also keeps its original geometry after resume.
	var expansion := _cells(restored, "barracks", Vector2i(10, 10), Vector2i(11, 10), {"barracks_layout_version": 1, "quarter": quarter})
	assert(SiteRuntime.request_resize(restored, key, expansion, Callable(), 1).ok)
	assert(int(restored.site.features[key].pending_build.get("barracks_layout_version", 1)) == 1)
	assert(SiteStore.save(restored, path + ".pending").ok)
	loaded = SiteStore.load_site(path + ".pending")
	assert(loaded.ok, str(loaded))
	restored = loaded.data
	_finish_military(restored, key)
	assert(str(restored.site.features[key].stage) == "complete" and not restored.site.features[key].has("pending_build") and SiteRuntime.validate_feature_layout(restored, restored.site.features[key]).ok)
	assert(int(restored.site.features[key].get("barracks_layout_version", 1)) == 1)
	for module: Dictionary in SiteRuntime.military_modules(restored, restored.site.features[key]):
		assert(str(module.kind) == "house", "Resuming an old paid job upgraded its module layout")
	completed += 1

func _check_dense_current_store(side: int) -> void:
	var data := _military_store_fixture("dense-current-%d" % side)
	var key := _build(data, "barracks", Vector2i(5, 5), Vector2i(side, side), {"barracks_layout_version": 2})
	assert(data.site.features[key].barracks_layout_version is int and int(data.site.features[key].barracks_layout_version) == 2)
	var original := _dense_geometry(data, key)
	assert(original.modules.size() == (7 if side == 10 else 193))
	assert(original.capacity == (60 if side == 10 else 1344))
	var path := DENSE_SAVE_ROOT.path_join("dense_%d.json" % side)
	var saved := SiteStore.save(data, path)
	assert(saved.ok, str(saved))
	var loaded := SiteStore.load_site(path)
	assert(loaded.ok, str(loaded))
	var restored: TerrainData = loaded.data
	assert(restored.site.features[key].barracks_layout_version is int and int(restored.site.features[key].barracks_layout_version) == 2)
	assert(_dense_geometry(restored, key) == original and restored.static_blocked == data.static_blocked and restored.feature_at == data.feature_at)
	assert(restored.fingerprint() == data.fingerprint())
	for bad_version: Variant in [-1, 0, 3, 1.25, true, "2", null]:
		_reject_dense_file(data, path, key, bad_version, false)
	completed += 1

func _check_dense_pending_store() -> void:
	var data := _military_store_fixture("dense-pending")
	var key := _build(data, "barracks", Vector2i(10, 10), Vector2i(10, 10), {"barracks_layout_version": 2})
	var cells := _cells(data, "barracks", Vector2i(10, 10), Vector2i(11, 10), {"barracks_layout_version": 2})
	assert(SiteRuntime.request_resize(data, key, cells, Callable(), 1).ok)
	var feature: Dictionary = data.site.features[key]
	var job: Dictionary = feature.pending_build
	assert(not job.has("barracks_layout_version"), "Pending work must reference the parent feature's single layout version")
	var task := _task(key, "construct", int(job.entrance))
	SiteRuntime._feature_work(data, key, float(job.work) * 0.25, Callable(), Callable(), task, {}, 20, 1)
	var path := DENSE_SAVE_ROOT.path_join("dense_pending.json")
	assert(SiteStore.save(data, path).ok)
	for bad_version: Variant in [-1, 0, 1, 2, 3, 1.25, true, "2", null]:
		_reject_dense_file(data, path, key, bad_version, true)
	var loaded := SiteStore.load_site(path)
	assert(loaded.ok, str(loaded))
	var restored: TerrainData = loaded.data
	assert(is_equal_approx(float(restored.site.features[key].pending_build.progress), float(job.progress)))
	var inventory := JSON.stringify(restored.site.inventory)
	_finish_military(restored, key)
	assert(str(restored.site.features[key].stage) == "complete" and not restored.site.features[key].has("pending_build") and SiteRuntime.validate_feature_layout(restored, restored.site.features[key]).ok)
	assert(int(restored.site.features[key].barracks_layout_version) == 2 and restored.site.features[key].cells == cells)
	assert(JSON.stringify(restored.site.inventory) == inventory, "Reloading a paid dense expansion charged its materials twice")
	assert(SiteStore.save(restored, path + ".resumed").ok and SiteStore.load_site(path + ".resumed").ok)
	completed += 1

func _reject_dense_file(data: TerrainData, path: String, key: String, value: Variant, pending: bool) -> void:
	var valid_save := FileAccess.get_file_as_string(path)
	var wrapper: Dictionary = JSON.parse_string(valid_save)
	var payload: Dictionary = JSON.parse_string(wrapper.payload)
	var broken: Dictionary = payload.state.features[key]
	if pending: broken = broken.pending_build
	broken.barracks_layout_version = value
	var body := JSON.stringify(payload, "", true, true)
	var bad_path := path + ".invalid_%02d" % rejected_files
	var file := FileAccess.open(bad_path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}))
	file.close()
	var bad_save := FileAccess.get_file_as_string(bad_path)
	var before := JSON.stringify(data.site)
	var blocked_before := data.static_blocked.duplicate()
	var features_before := data.feature_at.duplicate()
	var rejected := SiteStore.load_site(bad_path)
	assert(not rejected.ok and not rejected.has("data"), "Invalid barracks layout version produced a candidate Site: " + str({"value": value, "pending": pending, "result": rejected}))
	assert(JSON.stringify(data.site) == before and data.static_blocked == blocked_before and data.feature_at == features_before, "Rejected load changed the current Site or navigation")
	assert(FileAccess.get_file_as_string(path) == valid_save and FileAccess.get_file_as_string(bad_path) == bad_save, "Rejected load overwrote the valid save or its corrupt evidence")
	rejected_files += 1
