extends "res://scripts/tests/site_bridge_contract_test.gd"
## ECO05 supplement; inherits the original bridge -> building UI -> workflow fixtures.
## Staged only. Policy v3, its ECO01/ECO16 checks, and all formal sources stay separate.

const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 90000
	_run.call_deferred()

func _border_state(data: TerrainData) -> String:
	return JSON.stringify(data.site, "", true, true)

func _run() -> void:
	assert(_check_protected_bridge_store())
	assert(_check_protected_resize_added_cells())
	TerrainArmy.release_contact_source()
	print("SITE_ECOLOGY_POLICY_BORDER_PASS: bridge early refusal before payment; resize protects added cells and retains existing protected footprint; real half-paid protected bridge Store roundtrip, resume without repayment, completed demolition without construction refund, paused cancellation floors unused payment once. ECO05 supplement only; no GPU, Region replay or performance claim")
	quit(0)

func _check_protected_bridge_store() -> bool:
	var data := _bridge_fixture(0, 4, 0)
	var fish_cell := data.index(Vector2i(20, 20))
	Env._add_resource(data, Env.Kind.FISH, fish_cell, 20, 0)
	Env.rebuild_indexes(data)
	var source := "%d:%d" % [Env.Kind.FISH, fish_cell]
	var base := _bridge_base(data)
	var lab := _building_lab(data)
	var cells := _bridge_cells(data, 0, 4)
	var options := _bridge_options(0, "wood")
	var preview := Runtime.preview_build(data, "bridge", cells, Callable(), options)
	assert(preview.ok and preview.cost == {"wood": 24}, str(preview))
	assert(Settlement.set_ecology_modes(lab, lab.controlled_person_id(), [source], "protected").ok)
	var before := _border_state(data)
	assert(Runtime.preview_build(data, "bridge", cells, Callable(), options).code == "ECOLOGY_PROTECTED")
	assert(Runtime.request_build(data, "bridge", cells, Callable(), options).code == "ECOLOGY_PROTECTED")
	assert(_border_state(data) == before, "Bridge early-return rejection changed payment, holder, feature, zone or source")

	assert(Settlement.set_ecology_modes(lab, lab.controlled_person_id(), [source], "general").ok)
	var expected_stock: Dictionary = data.site.inventory.duplicate(true)
	expected_stock.wood = int(expected_stock.wood) - 24
	var accepted := Runtime.request_build(data, "bridge", cells, Callable(), options)
	assert(accepted.ok, str(accepted))
	var key := str(accepted.feature)
	var feature: Dictionary = data.site.features[key]
	assert(data.site.inventory == expected_stock and feature.cost == {"wood": 24})
	var task := _bridge_task(data, key)
	Runtime._feature_work(data, key, float(feature.work) * 0.5, Callable(), Callable(), task, {}, Runtime.CARRY_CAPACITY, 1)
	var paid_progress := float(feature.progress)
	assert(paid_progress > 0.0 and is_equal_approx(paid_progress, float(feature.work) * 0.5))
	assert(Settlement.set_ecology_modes(lab, lab.controlled_person_id(), [source], "protected").ok)
	before = _border_state(data)
	assert(Runtime.work_preflight(data, task, {}, Runtime.CARRY_CAPACITY, 1).code == "ECOLOGY_PROTECTED")
	Runtime._feature_work(data, key, float(feature.work), Callable(), Callable(), task, {}, Runtime.CARRY_CAPACITY, 1)
	assert(_border_state(data) == before, "Protection must preserve the already-paid half-work state")
	assert(lab.site_controller._capture_for_save().ok)
	var folder := "res://output/ecology_implementation_20261008/policy_border_runs/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) == OK)
	var path := folder.path_join("paid_protected_bridge.json")
	var saved := Store.save(data, path)
	assert(saved.ok, str(saved))
	var original_save := FileAccess.get_file_as_string(path)
	var loaded := Store.load_site(path, _bridge_loader(base))
	assert(loaded.ok, str(loaded))
	var resumed: TerrainData = loaded.data
	var restored: Dictionary = resumed.site.features[key]
	assert(restored.stage == "building" and is_equal_approx(float(restored.progress), paid_progress))
	assert(restored.cost == {"wood": 24} and restored.cells == cells and resumed.site.inventory == expected_stock)
	assert(Env.ecology_info(resumed, source).mode == "protected")
	var restored_task := _bridge_task(resumed, key)
	before = _border_state(resumed)
	assert(Runtime.work_preflight(resumed, restored_task, {}, Runtime.CARRY_CAPACITY, 1).code == "ECOLOGY_PROTECTED")
	Runtime._feature_work(resumed, key, float(restored.work), Callable(), Callable(), restored_task, {}, Runtime.CARRY_CAPACITY, 1)
	assert(_border_state(resumed) == before, "Loaded protection cannot finish work, charge again or refund payment")

	lab.bind_terrain(resumed)
	assert(is_same(lab.terrain, resumed))
	assert(Settlement.set_ecology_modes(lab, lab.controlled_person_id(), [source], "general").ok)
	Runtime._feature_work(resumed, key, float(restored.work) - float(restored.progress), Callable(), Callable(), restored_task, {}, Runtime.CARRY_CAPACITY, 1)
	assert(restored.stage == "complete" and resumed.site.inventory == expected_stock, "Resume charged the accepted bridge twice")
	assert(Runtime.cancel_feature(resumed, key, Callable(), 1).ok)
	assert(resumed.site.inventory == expected_stock, "Completed demolition refunded already-used construction materials")
	before = _border_state(resumed)
	assert(Runtime.cancel_feature(resumed, key, Callable(), 1).code == "NO_TARGET" and _border_state(resumed) == before)

	loaded = Store.load_site(path, _bridge_loader(base))
	assert(loaded.ok, str(loaded))
	var cancelled: TerrainData = loaded.data
	lab.bind_terrain(cancelled)
	assert(is_same(lab.terrain, cancelled))
	assert(Env.ecology_info(cancelled, source).mode == "protected")
	assert(is_equal_approx(float(cancelled.site.features[key].progress), paid_progress))
	var refund_stock := expected_stock.duplicate(true)
	refund_stock.wood = int(refund_stock.wood) + 12 # floor(24 * unused half); no new policy refund.
	assert(Runtime.cancel_feature(cancelled, key, Callable(), 1).ok)
	assert(not cancelled.site.features.has(key) and cancelled.site.inventory == refund_stock, "Protected cancellation must refund only original unused payment")
	assert(Env.ecology_info(cancelled, source).mode == "protected", "Cancellation reset the original source policy")
	before = _border_state(cancelled)
	assert(Runtime.cancel_feature(cancelled, key, Callable(), 1).code == "NO_TARGET" and _border_state(cancelled) == before, "Repeated cancel refunded twice")
	assert(FileAccess.get_file_as_string(path) == original_save, "Resuming or cancelling rewrote the saved source")
	lab.free()
	return true

func _check_protected_resize_added_cells() -> bool:
	var data := _building_fixture()
	var source := ""
	var keys := data.resource_base.keys()
	keys.sort()
	for key: String in keys:
		var resource := Env.resource(data, key)
		if int(resource.kind) in Env.RESTORABLE_KINDS and Rect2i(13, 13, 18, 18).has_point(data.cell_from_index(int(resource.cell))):
			source = key
			break
	assert(not source.is_empty(), "Original generated and fixture-cleared plant required for resize border")
	var anchor := data.cell_from_index(int(data.resource_base[source].cell))
	var lab := _building_lab(data)
	var key := _formal_feature(data, "palisade", anchor + Vector2i.LEFT)
	assert(str(data.site.features[key].stage) == "complete" and not data.site.features[key].has("pending_build"), "Original construction fixture did not reach its complete feature exit")
	assert(int(data.site.worker.cell) == data.index(Vector2i(10, 9)) and str(data.site.worker.mode) == "idle", "Original construction fixture did not restore its worker exit")
	var feature: Dictionary = data.site.features[key]
	var expanded: Array[int] = [data.index(anchor + Vector2i.LEFT), data.index(anchor)]
	var preview := Runtime.preview_resize(data, key, expanded)
	assert(preview.ok and preview.added_cells == [data.index(anchor)], str(preview))
	assert(Settlement.set_ecology_modes(lab, lab.controlled_person_id(), [source], "protected").ok)
	var before := _border_state(data)
	assert(Runtime.preview_resize(data, key, expanded).code == "ECOLOGY_PROTECTED")
	assert(Runtime.request_resize(data, key, expanded, Callable(), 1).code == "ECOLOGY_PROTECTED")
	assert(_border_state(data) == before and not feature.has("pending_build"), "Protected added cells published a paid resize or changed the original feature")
	assert(Settlement.set_ecology_modes(lab, lab.controlled_person_id(), [source], "general").ok)
	var expected_stock: Dictionary = data.site.inventory.duplicate(true)
	expected_stock.wood = int(expected_stock.wood) - 4
	assert(Runtime.request_resize(data, key, expanded, Callable(), 1).ok)
	assert(data.site.inventory == expected_stock and feature.pending_build.added_cells == [data.index(anchor)])
	_complete_key(data, key)
	assert(str(data.site.features[key].stage) == "complete" and not data.site.features[key].has("pending_build"), "Original construction fixture did not reach its complete feature exit")
	assert(int(data.site.worker.cell) == data.index(Vector2i(10, 9)) and str(data.site.worker.mode) == "idle", "Original construction fixture did not restore its worker exit")
	assert(feature.cells == expanded and data.site.inventory == expected_stock)

	# Once occupied by the completed original feature, protection applies only
	# to later added cells; it does not reject the retained footprint itself.
	assert(Settlement.set_ecology_modes(lab, lab.controlled_person_id(), [source], "protected").ok)
	var further: Array[int] = expanded.duplicate()
	further.append(data.index(anchor + Vector2i.RIGHT))
	before = _border_state(data)
	preview = Runtime.preview_resize(data, key, further)
	assert(preview.ok and preview.added_cells == [data.index(anchor + Vector2i.RIGHT)], str(preview))
	assert(_border_state(data) == before)
	expected_stock.wood = int(expected_stock.wood) - 4
	assert(Runtime.request_resize(data, key, further, Callable(), 1).ok)
	_complete_key(data, key)
	assert(str(data.site.features[key].stage) == "complete" and not data.site.features[key].has("pending_build"), "Original construction fixture did not reach its complete feature exit")
	assert(int(data.site.worker.cell) == data.index(Vector2i(10, 9)) and str(data.site.worker.mode) == "idle", "Original construction fixture did not restore its worker exit")
	assert(feature.cells == further and data.site.inventory == expected_stock, "Retained protected footprint blocked or double-paid an unrelated expansion")
	assert(Env.ecology_info(data, source).mode == "protected")
	lab.free()
	return true
