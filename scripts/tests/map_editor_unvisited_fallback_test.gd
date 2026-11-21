extends "res://scripts/tests/map_editor_terrain_contract_test.gd"
## Real RegionData package/Store/Runtime/navigation APIs; no author-world birth.
var deadline: int
var checks := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 90000
	super._initialize()

func _check(value: bool, message: String) -> bool:
	checks += 1
	return super._check(value and Time.get_ticks_msec() <= deadline, message)

func _build_initial(data: TerrainData, kind: String, anchor: Vector2i, extent: Vector2i) -> bool:
	var options := {"layout_version": 1, "quarter": 0, "material": "wood", "owner_faction": 1}
	var layout: Dictionary = Runtime.building_cells(data, kind, anchor, extent, options)
	if not _check(layout.ok, "original " + kind + " layout"): return false
	var cells: Array[int] = []
	for value: Variant in layout.cells: cells.append(int(value))
	if kind == "bridge":
		var banks: Dictionary = Runtime.bridge_layout(data, cells, int(options.quarter))
		if not _check(banks.ok, "original bridge banks: " + str(banks)): return false
		data.site.inventory.tools = 0
		var before_missing: PackedByteArray = var_to_bytes(data.site)
		var missing: Dictionary = Runtime.preview_build(data, kind, cells, Callable(), options)
		if _failed: return false
		if not _check(not missing.ok and missing.code == "MATERIALS" and var_to_bytes(data.site) == before_missing, "original missing tool refuses without mutation: " + str(missing)): return false
		data.site.inventory.tools = 1
	if kind == "palisade":
		for index: int in cells:
			if not _check(int(data.foundation[index]) == 35, "original author land survives initialize on every wall cell"): return false
		var weak: TerrainData = Env.navigation_for_state(data, data.site.duplicate(true))
		weak.foundation = data.foundation.duplicate()
		weak.foundation[cells[0]] = 34
		var weak_before: PackedByteArray = var_to_bytes(weak.site)
		var original_before: PackedByteArray = var_to_bytes(data.site)
		var refused: Dictionary = Runtime.preview_build(weak, kind, cells, Callable(), options)
		if _failed: return false
		if not _check(not refused.ok and refused.code == "TERRAIN" and str(refused.message).contains("地基不足") and var_to_bytes(weak.site) == weak_before and var_to_bytes(data.site) == original_before and int(data.foundation[cells[0]]) == 35, "original foundation34 preview refuses without mutation: " + str(refused)): return false
	var preview: Dictionary = Runtime.preview_build(data, kind, cells, Callable(), options)
	if _failed: return false
	if not _check(preview.ok, "original paid preview " + kind + ": " + str(preview)): return false
	var before_paid: Dictionary = data.site.inventory.duplicate(true)
	var built: Dictionary = Runtime.request_build(data, kind, cells, Callable(), options)
	if not _check(built.ok, "original paid " + kind + ": " + str(built)): return false
	for item: String in preview.cost:
		if not _check(int(data.site.inventory.get(item, 0)) == int(before_paid.get(item, 0)) - int(preview.cost[item]), "original depot cost deducted once " + kind + ": " + item): return false
	var feature: Dictionary = data.site.features[str(built.feature)]
	var task: Dictionary = {"target": "feature:" + str(built.feature), "action": "construct", "cell": int(feature.entrance), "mode": "work", "status": "", "progress": 0.0}
	Runtime._feature_work(data, str(built.feature), float(feature.work), Callable(), Callable(), task, {}, 20, 1)
	if _failed: return false
	return _check(feature.stage == "complete", "original completed " + kind)

func _run() -> void:
	folder = "user://map_unvisited_fallback_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _check(DirAccess.make_dir_recursive_absolute(folder) == OK, "fixture folder"): return
	if not _natural(): return
	var natural: RegionData = Data.new()
	if not _check(natural.load_manifest(str(natural_record.path)).ok, "real natural loader"): return
	var raw: Dictionary = _static()
	raw.water_bodies["1000000000"] = {"id": "river", "kind": 1}
	for i: int in [2000,2100]: raw.terrain[str(i)] = {"height": 0, "surface": TerrainData.Surface.WATER, "water_kind": 1, "water_body": 1000000000}
	raw.water_permissions.cells = [2000,2100]
	# Original palisade preview requires foundation >=35, supplied by the author layer.
	for i: int in [3599,3699]: raw.terrain[str(i)] = {"foundation": 35}
	var drafted: Dictionary = natural.make_author_draft(Vector2i.ZERO, raw, 1)
	if not _check(drafted.ok, "original author static water fixture"): return
	var data: TerrainData = drafted.data
	Env.initialize(data, str(drafted.base.site_id))
	if _failed: return
	data.site.capacity = 100000
	data.site.inventory.wood = 1000
	data.site.inventory.tools = 1 # Same original paid-build prerequisite for bridge and palisade.
	if not _check(Runtime.initialize_item_storage(data.site).ok, "original fixture holder"): return
	if not _build_initial(data, "bridge", Vector2i(0,20), Vector2i(1,2)): return
	if not _build_initial(data, "palisade", Vector2i(99,35), Vector2i(1,2)): return
	data.site.terrain_changes["5000"] = 3
	var state: Dictionary = data.site.duplicate(true)
	state.erase("world_pin")
	var files: Array[Dictionary] = [_file("static.json", raw, "static", Vector2i.ZERO), _file("initial.json", state, "initial", Vector2i.ZERO)]
	if _failed: return
	var path: String = _package("package.json", files)
	if _failed: return
	var authored: RegionData = Data.new()
	if not _check(authored.load_author_package(path).ok, "original author package admission"): return
	var original: PackedByteArray = var_to_bytes(authored._author_initial)
	var calls: Array[int] = [0]
	var provider: Callable = func(_at: Vector2i) -> Dictionary:
		calls[0] += 1
		return {"ok": true, "data": null, "revision": "unvisited"}
	var current_context: Dictionary = {"projection_mode": "slot_current", "effective_terrain": provider}
	var initial_context := {"projection_mode": "author_initial"}
	var base_context := {"projection_mode": "base"}
	for reverse: bool in [false, true]:
		Route.clear_memory_cache()
		if reverse: Route.site_table(authored, Vector2i.ZERO, current_context)
		var base: Dictionary = Route.effective_terrain(authored, Vector2i.ZERO, base_context)
		var base_table: PackedByteArray = Route.site_table(authored, Vector2i.ZERO, base_context)
		var initial: Dictionary = Route.effective_terrain(authored, Vector2i.ZERO, initial_context)
		var current: Dictionary = Route.effective_terrain(authored, Vector2i.ZERO, current_context)
		if not _check(base.ok and initial.ok and current.ok and is_same(initial.data, current.data) and not is_same(base.data, current.data), "mode-separated memo in both access orders"): return
		if not _check(base.data.site.is_empty() and current.data.height_levels[5000] == 3 and current.data.site.features.size() == 2 and current.data.site.minute == state.minute and current.data.site.phase == state.phase and base.data.can_navigate_water(Vector2i(0,20)) and not current.data.can_navigate_water(Vector2i(0,20)), "real height/bridge/water initial effective surfaces"): return
		if not _check(current.data.feature_at[current.data.index(Vector2i(99,35))] >= 0 and (base.data.is_walkable(Vector2i(99,35)) != current.data.is_walkable(Vector2i(99,35)) or base.data.effective_height(Vector2i(99,35)) != current.data.effective_height(Vector2i(99,35))), "real initial wall changes effective navigation"): return
		var initial_table: PackedByteArray = Route.site_table(authored, Vector2i.ZERO, initial_context)
		var current_table: PackedByteArray = Route.site_table(authored, Vector2i.ZERO, current_context)
		var effective: Dictionary = Route.table_from_terrain(initial.data, Route._cover(authored, Vector2i.ZERO), true)
		if not _check(effective.ok and current_table == initial_table and current_table == effective.table and base_table != current_table, "unvisited table equals original effective initial; base distinct"): return
		if not _check(Route.table_cache_key(authored, "slot_current") == Route.table_cache_key(authored, "author_initial") and Route.table_cache_key(authored, "base") != Route.table_cache_key(authored, "slot_current"), "mode namespace keys"): return
		var search: RegionRoute.Search = Route.Search.new()
		search.source = authored; search.context = current_context
		if not _check(search._table(Vector2i.ZERO) == current_table and search.builds == 0 and search._table(Vector2i.ZERO) == current_table and search.builds == 0, "Search warm initial namespace build budget"): return
		Route.flush_cache()
		Route.clear_memory_cache()
		var disk_search: RegionRoute.Search = Route.Search.new()
		disk_search.source = authored; disk_search.context = current_context
		if not _check(disk_search._table(Vector2i.ZERO) == current_table and disk_search.builds == 0, "flush/read uses same hashed cache namespace"): return
		var override_base: Dictionary = authored.make_terrain_data(0,0)
		if not _check(override_base.ok, "real current override base"): return
		Env.initialize(override_base.data, str(override_base.base.site_id))
		if _failed: return
		var current_state: Dictionary = override_base.data.site.duplicate(true)
		current_state.terrain_changes["5000"] = 4
		override_base.data.height_levels[5000] = 4
		Runtime.rebuild_terrain_edges(override_base.data)
		if _failed: return
		var override: TerrainData = Env.navigation_for_state(override_base.data, current_state)
		var override_context: Dictionary = {"projection_mode": "slot_current", "effective_terrain": func(_at: Vector2i) -> Dictionary: return {"ok": true, "data": override, "revision": "actual-current"}}
		var supplied: Dictionary = Route.effective_terrain(authored, Vector2i.ZERO, override_context)
		if not _check(supplied.ok and is_same(supplied.data, override) and supplied.data.site.features.is_empty() and supplied.data.effective_height(Vector2i(0,50)) == 4, "current body wins warm initial cache; never initial overlay"): return
		var expected: Dictionary = Route.table_from_terrain(override, Route._cover(authored, Vector2i.ZERO), true)
		if not _check(expected.ok and Route.site_table(authored, Vector2i.ZERO, override_context) == expected.table, "current table wins warm initial cache"): return
	var natural_base: Dictionary = Route.effective_terrain(natural, Vector2i.ZERO)
	var natural_current: Dictionary = Route.effective_terrain(natural, Vector2i.ZERO, current_context)
	if not _check(natural_base.ok and natural_current.ok and is_same(natural_base.data, natural_current.data) and Route.table_cache_key(natural, "slot_current") == Route.cache_key(natural) and Route.site_table(natural, Vector2i.ZERO) == Route.site_table(natural, Vector2i.ZERO, current_context), "natural body/table/key original base branch unchanged"): return
	var null_without_revision: Dictionary = {"projection_mode": "slot_current", "effective_terrain": func(_at: Vector2i) -> Dictionary: return {"ok": true, "data": null, "visited": false}}
	if not _check(Route.effective_terrain(natural, Vector2i.ZERO, null_without_revision).ok and is_same(Route.effective_terrain(natural, Vector2i.ZERO, null_without_revision).data, natural_base.data) and Route.site_table(natural, Vector2i.ZERO, null_without_revision) == Route.site_table(natural, Vector2i.ZERO), "original natural null provider without revision remains legal"): return
	if not _check(Route.effective_terrain(authored, Vector2i.ZERO, null_without_revision).ok and Route.site_table(authored, Vector2i.ZERO, null_without_revision) == Route.site_table(authored, Vector2i.ZERO, initial_context), "authored null provider without revision is valid unvisited"): return
	var natural_empty_provider: Dictionary = {"projection_mode": "slot_current", "effective_terrain": func(_at: Vector2i) -> Dictionary: return {}}
	if not _check(Route.effective_terrain(natural, Vector2i.ZERO, natural_empty_provider) == {} and Route.site_table(natural, Vector2i.ZERO, natural_empty_provider).is_empty(), "original natural empty-provider refusal remains get-safe without fallback"): return
	var refusal := {"ok": false, "code": "CORRUPT_SAVE", "message": "original current source refusal"}
	var cases: Array = [refusal, null, {}, {"ok": true, "revision": "missing-data"}, {"ok": true, "data": 5, "revision": "bad"}, {"ok": true, "data": null, "revision": 5}, {"ok": true, "data": natural_base.data, "revision": ""}, {"ok": true, "data": natural_base.data, "revision": 7}, {"ok": true, "data": TerrainData.new(), "revision": "bad-size"}]
	var case_names: Array[String] = ["original_refusal", "null_response", "empty_response", "missing_data", "non_terrain_data", "null_bad_revision", "empty_revision", "non_string_revision", "unallocated_default_size"]
	var wrong_size: TerrainData = TerrainData.new()
	wrong_size.size = Vector2i(99,100)
	cases.append({"ok": true, "data": wrong_size, "revision": "wrong-size"}); case_names.append("actual_wrong_size")
	for field: String in ["height_levels", "surface_types", "flags", "ramp_edges", "water_kind", "water_body", "static_blocked", "feature_at", "bridge_navigation_flags", "bridge_walkable"]:
		var broken: TerrainData = Env.navigation_for_state(natural_base.data, {})
		if field in ["water_body", "feature_at"]: broken.set(field, PackedInt32Array([0]))
		else: broken.set(field, PackedByteArray([0]))
		cases.append({"ok": true, "data": broken, "revision": "short-" + field}); case_names.append("short_" + field)
	for raised: bool in [true, false]:
		var broken: TerrainData = Env.navigation_for_state(natural_base.data, {})
		if raised: broken.has_raised_surfaces = true; broken.walk_height_levels = PackedByteArray()
		else: broken.has_navigation_overrides = true; broken.walk_ramp_edges = PackedByteArray()
		cases.append({"ok": true, "data": broken, "revision": "missing-selected-layer"}); case_names.append("missing_walk_heights" if raised else "missing_walk_ramps")
	cases.append({"ok": 1, "data": null}); case_names.append("non_boolean_status")
	Route.flush_cache()
	var case_index: int = 0
	for response: Variant in cases:
		var cache_before: Dictionary = _route_cache_state()
		var case_name: String = case_names[case_index]
		case_index += 1
		var failed_context: Dictionary = {"projection_mode": "slot_current", "effective_terrain": func(_at: Vector2i) -> Variant: return response}
		var failed: Dictionary = Route.effective_terrain(authored, Vector2i.ZERO, failed_context)
		if not _check(not failed.ok and Route.site_table(authored, Vector2i.ZERO, failed_context).is_empty(), "refusal/invalid response never initial/base fallback: %s result=%s" % [case_name, failed]): return
		var search: RegionRoute.Search = Route.Search.new()
		search.source = authored; search.context = failed_context; search.start_site = Vector2i.ZERO; search.goal_site = Vector2i.RIGHT
		var solved: Dictionary = search.run()
		if not _check(not solved.ok and solved.code == failed.code and search.builds == 0, "Search retains provider error before generic NO_ROUTE: " + case_name): return
		if not _check(_route_cache_state() == cache_before and var_to_bytes(authored._author_initial) == original, "refused response leaves route caches and template untouched: " + case_name): return
		if not (response is Dictionary and response == refusal):
			if not _check(failed.code == "INVALID_PROVIDER", "invalid response has stable provider code: " + case_name): return
		if response is Dictionary and response == refusal:
			if not _check(failed == refusal, "exact original refusal dictionary preserved"): return
	if not _check(not Route.effective_terrain(authored, Vector2i.ZERO, {"projection_mode": "slot_current"}).ok and not Route.effective_terrain(authored, Vector2i.ZERO, {"projection_mode": "author_initial", "effective_terrain": provider}).ok, "original provider mode guards retained"): return
	if not _check(var_to_bytes(authored._author_initial) == original and calls[0] > 0 and Time.get_ticks_msec() <= deadline, "raw template/caller order/clock unchanged"): return
	print("MAP_EDITOR_UNVISITED_FALLBACK_PASS: ", checks, " original source/API fixtures; no author birth/current snapshot overlay/runtime-performance claim")
	quit(0)

func _route_cache_state() -> Dictionary:
	return {"memory": Route._memory.duplicate(true), "volatile": Route._volatile.duplicate(true),
		"terrain": Route._terrain_memo.duplicate(), "terrain_owner": Route._terrain_memo_owner.duplicate(),
		"table": Route._table_memo.duplicate(true), "loaded": Route._loaded_regions.duplicate(true),
		"dirty": Route._dirty_regions.duplicate(true), "terrain_order": Route._terrain_memo_order.duplicate(),
		"table_order": Route._table_memo_order.duplicate()}
