extends "res://scripts/tests/site_building_runtime_contract_test.gd"

var dense_cases := 0

func _run() -> void:
	create_timer(80.0).timeout.connect(func() -> void: quit(1))
	await _check_dense_geometry()
	_check_dense_versions()
	_check_dense_construction_and_resize()
	if dense_cases != 492 or completed != 2:
		push_error("Dense barracks contract stopped before every acceptance group completed")
		quit(1)
		return
	print("SITE_BARRACKS_DENSE_CONTRACT_PASS: 492 width/depth/rotation cases, fixed 3x2 dormitories, original shared blocked cells and connected standing capacity, 10x10 seven modules/60 capacity and 50x50 193 modules/1344 capacity, strict API versions, legacy geometry and same-feature resize version preservation; headless geometry only")
	quit(0)

func _dense_fixture() -> TerrainData:
	var data := _fixture()
	data.site.inventory.wood = 10000
	data.site.inventory.stone = 10000
	return data

func _check_dense_geometry() -> void:
	var data := _dense_fixture()
	for extent: int in range(10, 51):
		for size: Vector2i in [Vector2i(extent, 10), Vector2i(10, extent), Vector2i(extent, extent)]:
			for quarter: int in range(4):
				var cells := _cells(data, "barracks", Vector2i(10, 10), size, {"quarter": quarter})
				var feature := {"kind": "barracks", "cells": cells, "quarter": quarter, "barracks_layout_version": 2,
					"layout_version": 1, "stage": "complete", "level": 0, "entrance": -1}
				var modules := SiteRuntime.military_modules(data, feature)
				var blocked := {}
				var dormitories := 0
				var headquarters := 0
				for module: Dictionary in modules:
					assert(int(module.quarter) == quarter, "Approved dormitories and HQ face the compound entrance")
					var module_size := SiteRuntime._cell_bounds(data, module.cells).size
					if str(module.kind) == "barracks_dormitory":
						dormitories += 1
						assert(module.base_size == Vector2i(3, 2) and module.base_origin is Vector2i)
						assert(module_size == (Vector2i(2, 3) if quarter % 2 else Vector2i(3, 2)))
						assert(module.cells.size() == 6)
					else:
						headquarters += 1
						assert(str(module.kind) == "house" and str(module.variant) == "small" and module_size == Vector2i(2, 2))
					for index: int in module.cells:
						assert(cells.has(index) and not blocked.has(index), "A derived module overlaps or leaves its original feature")
						blocked[index] = true
				assert(headquarters == 1 and dormitories >= 6)
				var standing := SiteRuntime.military_walkable_cells(data, feature)
				assert(standing.size() + blocked.size() == size.x * size.y)
				assert(SiteRuntime.military_capacity(data, feature) == standing.size())
				var physical: Array = SiteRuntime.feature_geometry(data, feature).blocked
				assert(physical.size() == blocked.size())
				for index: int in physical: assert(blocked.has(index))
				assert(_assert_dense_access(data, feature, standing), "Dense access acceptance did not complete")
				if size == Vector2i(10, 10):
					assert(modules.size() == 7 and standing.size() == 60)
					for module: Dictionary in modules:
						if str(module.kind) == "barracks_dormitory":
							assert(module.base_origin.x in [0, 7] and module.base_origin.y in [1, 4, 7])
				if size == Vector2i(50, 50):
					assert(modules.size() == 193 and standing.size() == 1344)
				dense_cases += 1
		await process_frame

func _assert_dense_access(data: TerrainData, feature: Dictionary, standing: Array[int]) -> bool:
	var available := {}
	for index: int in standing: available[index] = true
	var bounds := SiteRuntime._cell_bounds(data, feature.cells)
	var quarter := int(feature.quarter)
	var base_size := Vector2i(bounds.size.y, bounds.size.x) if quarter % 2 else bounds.size
	var left := floori(float(base_size.x - 4) / 2.0)
	for y: int in range(2, base_size.y):
		for x: int in range(left, left + 4):
			assert(available.has(data.index(SiteRuntime._layout_cell(Vector2i(x, y), base_size, quarter, bounds.position))), "Central four-cell route must stay clear")
	for x: int in range(base_size.x):
		assert(available.has(data.index(SiteRuntime._layout_cell(Vector2i(x, base_size.y - 1), base_size, quarter, bounds.position))), "South entry lane must stay clear")
	var entry: Dictionary = SiteRuntime._building_entrances(data, feature.cells, quarter)[0]
	var first := data.index(entry.inner)
	assert(available.has(first) and data.can_terrain_step(entry.cell, entry.inner))
	var reached := {first: true}
	var queue: Array[int] = [first]
	var head := 0
	while head < queue.size():
		var cell := data.cell_from_index(queue[head])
		head += 1
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cell + direction
			if not data.contains(next): continue
			var index := data.index(next)
			if available.has(index) and not reached.has(index) and data.can_terrain_step(cell, next):
				reached[index] = true
				queue.append(index)
	assert(reached.size() == standing.size(), "Every counted standing cell must connect to the entrance and HQ")
	return true

func _check_dense_versions() -> void:
	var data := _dense_fixture()
	var cells := _cells(data, "barracks", Vector2i(10, 10), Vector2i(10, 10))
	assert(int(SiteRuntime.building_spec("barracks").options.barracks_layout_version) == 2)
	for version: Variant in [-1, 0, 3, 1.0, 2.0, 1.5, true, false, "2", null]:
		var options := {"barracks_layout_version": version}
		assert(not SiteRuntime.building_spec("barracks", options).ok)
		assert(not SiteRuntime.preview_build(data, "barracks", cells, Callable(), options).ok)
		var before := JSON.stringify(data.site)
		assert(not SiteRuntime.request_build(data, "barracks", cells, Callable(), options).ok)
		assert(JSON.stringify(data.site) == before, "Rejected versions must preserve materials and original features")
	assert(not SiteRuntime.building_spec("training_ground", {"barracks_layout_version": 2}).ok)
	assert(not SiteRuntime.building_spec("barracks_dormitory").ok, "A derived dormitory must not become a second buildable feature")
	for quarter: int in range(4):
		var legacy := {"kind": "barracks", "cells": cells, "quarter": quarter}
		var explicit := legacy.duplicate()
		explicit.barracks_layout_version = 1
		assert(SiteRuntime.military_modules(data, legacy) == SiteRuntime.military_modules(data, explicit))
		assert(SiteRuntime.military_modules(data, legacy).size() == 3 and SiteRuntime.military_capacity(data, legacy) == 72)
		assert(int(SiteRuntime._feature_options(legacy).barracks_layout_version) == 1)
	completed += 1

func _check_dense_construction_and_resize() -> void:
	var registration_failure := SiteRuntime.fail("BUSY", "尚有人員登記，無法調整密集軍營布局")
	for version: int in [1, 2]:
		var data := _dense_fixture()
		var options: Dictionary = {"barracks_layout_version": 1} if version == 1 else {}
		var key := _build(data, "barracks", Vector2i(10, 10), Vector2i(10, 10), options)
		var feature: Dictionary = data.site.features[key]
		assert(int(feature.barracks_layout_version) == version)
		if version == 1: feature.erase("barracks_layout_version")
		var small: Array[int] = feature.cells.duplicate()
		var large := _cells(data, "barracks", Vector2i(10, 10), Vector2i(14, 13))
		if version == 2:
			data.site.armies = [{"garrison_feature_id": key, "units": [{"person_id": 77, "hp": 100.0, "slot": [15, 15], "cell": [65, 65]}]}]
			var before := JSON.stringify(data.site)
			var denied := SiteRuntime.request_resize(data, key, large, Callable(), 1)
			assert(denied == registration_failure, str(denied))
			assert(JSON.stringify(data.site) == before, "Registered people outside still reserve their original return slots")
			data.site.armies = []
		var preview := SiteRuntime.preview_resize(data, key, large)
		assert(preview.ok and int(preview.options.barracks_layout_version) == version)
		assert(preview.candidate.has("barracks_layout_version") == (version == 2))
		assert(SiteRuntime.request_resize(data, key, large, Callable(), 1).ok)
		assert(is_same(feature, data.site.features[key]) and feature.cells == small)
		assert(SiteRuntime.validate_feature_layout(data, feature).ok)
		var job: Dictionary = feature.pending_build
		var task := _task(key, "construct", int(job.entrance))
		if version == 2:
			data.site.armies = [{"garrison_feature_id": key, "units": [{"person_id": 77, "hp": 100.0, "slot": [15, 15], "cell": [65, 65]}]}]
			var registered := JSON.stringify(data.site.armies)
			SiteRuntime._feature_work(data, key, float(job.work), Callable(), Callable(), task, {}, 20, 1)
			assert(feature.cells == small and feature.has("pending_build") and JSON.stringify(data.site.armies) == registered)
			assert(str(task.status) == str(registration_failure.message), "Completion must recheck registrations added after the resize request")
			data.site.armies = []
		SiteRuntime._feature_work(data, key, float(job.work), Callable(), Callable(), task, {}, 20, 1)
		assert(feature.cells == large and not feature.has("pending_build"))
		assert(feature.has("barracks_layout_version") == (version == 2))
		assert(int(SiteRuntime._feature_options(feature).barracks_layout_version) == version)
		assert(SiteRuntime.validate_feature_layout(data, feature).ok)
		assert(SiteRuntime.request_resize(data, key, small, Callable(), 1).ok)
		assert(is_same(feature, data.site.features[key]) and feature.cells == small)
		assert(SiteRuntime.military_capacity(data, feature) == (72 if version == 1 else 60))
		assert(feature.has("barracks_layout_version") == (version == 2))
	completed += 1
