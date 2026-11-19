extends "res://scripts/tests/site_building_runtime_contract_test.gd"

const MILITARY_SAVE_ROOT := "res://.godot-temp/site_military_contract"

func _run() -> void:
	create_timer(80.0).timeout.connect(func() -> void: quit(1))
	completed = 0
	_check_military_sizes_and_terms()
	_check_military_construction_and_cancel()
	_check_military_resize_and_guards()
	_check_military_large_store()
	_check_military_people_and_training_store()
	assert(completed == 5, "Military building contract did not finish")
	print("SITE_MILITARY_BUILDING_CONTRACT_PASS: 10..50 rectangular bounds, area-scaled materials/work, original construction and cancellation, same-feature pending resize and occupied/garrison guards, complete 2500-cell barracks and training-ground Store roundtrips with unfinished expansion resume and corrupt-layout rejection; headless contract only")
	quit(0)

func _military_fixture() -> TerrainData:
	var data := _fixture()
	data.site.inventory.wood = 10000
	data.site.inventory.stone = 10000
	return data

func _build(data: TerrainData, kind: String, anchor: Vector2i, size: Vector2i = Vector2i.ONE, options: Dictionary = {}) -> String:
	# Preserve this pre-redesign suite's named geometry/capacity regression.
	# The dense contract and Store suites explicitly exercise v2 and new defaults.
	var chosen := options.duplicate()
	if kind == "barracks" and not chosen.has("barracks_layout_version"):
		chosen["barracks_layout_version"] = 1
	return super._build(data, kind, anchor, size, chosen)

func _finish_military(data: TerrainData, key: String) -> void:
	var feature: Dictionary = data.site.features[key]
	var job: Dictionary = feature.get("pending_build", feature)
	var task := _task(key, "construct", int(job.entrance))
	SiteRuntime._feature_work(data, key, float(job.work), Callable(), Callable(), task, {}, 20, 1)
	assert(str(feature.stage) == "complete" and not feature.has("pending_build"), str(task))
	assert(SiteRuntime.validate_feature_layout(data, feature).ok)

func _check_military_sizes_and_terms() -> void:
	for kind: String in SiteRuntime.MILITARY_KINDS:
		var data := _military_fixture()
		var small := _cells(data, kind, Vector2i(10, 10), Vector2i(10, 10))
		var large := _cells(data, kind, Vector2i(10, 10), Vector2i(50, 50))
		var small_preview := SiteRuntime.preview_build(data, kind, small, Callable(), {"owner_faction": 1})
		var large_preview := SiteRuntime.preview_build(data, kind, large, Callable(), {"owner_faction": 1})
		assert(small_preview.ok and large_preview.ok)
		assert(int(small_preview.cost.wood) == 100 and int(large_preview.cost.wood) == 2500)
		assert(float(large_preview.work) == float(small_preview.work) * 25.0, "50x50 cannot cost the same work as 10x10")
		assert(float(small_preview.work) == (200.0 if kind == "barracks" else 50.0))
		assert(int(large_preview.cost.get("stone", 0)) == (2500 if kind == "barracks" else 0))
		for size: Vector2i in [Vector2i(10, 50), Vector2i(50, 10), Vector2i(10, 10), Vector2i(50, 50)]:
			assert(SiteRuntime.preview_build(data, kind, _cells(data, kind, Vector2i(10, 10), size)).ok)
		for size: Vector2i in [Vector2i(9, 10), Vector2i(10, 9), Vector2i(51, 10), Vector2i(10, 51)]:
			var invalid: Array[int] = []
			for y: int in range(10, 10 + size.y):
				for x: int in range(10, 10 + size.x):
					invalid.append(data.index(Vector2i(x, y)))
			var before := JSON.stringify(data.site)
			assert(not SiteRuntime.request_build(data, kind, invalid).ok)
			assert(JSON.stringify(data.site) == before, "Rejected dimensions changed Site/materials/ID")
		var missing := small.duplicate()
		missing.remove_at(44)
		assert(not SiteRuntime.validate_building_layout(data, kind, missing).ok)
		var duplicate := small.duplicate()
		duplicate[44] = duplicate[43]
		assert(not SiteRuntime.validate_building_layout(data, kind, duplicate).ok)
		for quarter: int in range(4):
			var legacy_options := {"quarter": quarter, "owner_faction": 1}
			if kind == "barracks": legacy_options["barracks_layout_version"] = 1
			var preview := SiteRuntime.preview_build(data, kind, small, Callable(), legacy_options)
			assert(preview.ok)
			var candidate := {"kind": kind, "cells": small, "quarter": quarter}
			if kind == "barracks": candidate["barracks_layout_version"] = 1
			var occupied := {}
			for module: Dictionary in SiteRuntime.military_modules(data, candidate):
				if str(module.kind) == "house":
					var spec := SiteRuntime.building_spec("house", {"variant": module.variant, "quarter": module.quarter})
					assert(SiteRuntime._cell_bounds(data, module.cells).size == spec.size, "Barracks stretched an original house module")
				else:
					assert(module.cells.size() == 2 and SiteRuntime._cell_bounds(data, module.cells).size == Vector2i(2, 1))
				for index: int in module.cells:
					assert(small.has(index) and not occupied.has(index), "Physical modules overlap or leave the original footprint")
					occupied[index] = true
			assert(occupied.size() == (28 if kind == "barracks" else 8))
			assert(preview.geometry.blocked.size() == occupied.size())
	completed += 1

func _check_military_people_and_training_store() -> void:
	var data := _military_store_fixture("people")
	var barracks := _build(data, "barracks", Vector2i(10, 10), Vector2i(10, 10))
	var ground := _build(data, "training_ground", Vector2i(25, 10), Vector2i(10, 10))
	var fixture := CrewFixture.new()
	fixture.army.exchange_enabled = true # The formal Lab uses this rule; do not instantiate historical 3D contact scenes headless.
	fixture.setup(root, data, [Vector2i(15, 15), Vector2i(16, 15), Vector2i(15, 16)])
	fixture.army.training = 37.0
	var originals := {}
	var ids: Array[int] = []
	for row: Dictionary in fixture.army.combat_units:
		ids.append(int(row.person_id))
		originals[int(row.person_id)] = row
	var sustain := SiteSustain.create()
	assert(SiteSustain.add_members(sustain, originals, ids).ok)
	var life := {}
	for identity: int in ids: life[str(identity)] = 0
	var supply := {"version": 2, "sustain": sustain, "inventory": {"grain": 3}, "training_order": true,
		"training_requester": ids[0], "training_feature_id": ground, "revision": 0, "delivery": {}, "life_checkpoint": life}
	data.site.team_supply = {str(fixture.army.team_id): supply}
	data.site.actors = {}
	data.site.army_trial_active = true
	data.site.army_next_team = fixture.army.team_id + 1
	data.site.armies = [fixture.army.capture_combat_state()]
	assert(SiteStore._validate_supply(data.site).ok)
	for fault: String in ["missing", "non_training_camp", "garrison", "unfinished", "faction", "stopped_reference"]:
		var bad: Dictionary = data.site.duplicate(true)
		var bad_supply: Dictionary = bad.team_supply[str(fixture.army.team_id)]
		match fault:
			"missing": bad_supply.training_feature_id = "99999"
			"non_training_camp":
				bad_supply.training_feature_id = barracks
				bad.features[barracks].camp_type = "chinese"
			"garrison": bad.armies[0].garrison_feature_id = barracks
			"unfinished": bad.features[ground].stage = "planned"
			"faction": bad.features[ground].owner_faction = 2
			"stopped_reference":
				bad_supply.training_order = false
				bad_supply.training_requester = -1
		assert(not SiteStore._validate_supply(bad).ok, "Invalid school-ground command accepted: " + fault)
	var path := MILITARY_SAVE_ROOT.path_join("people.json")
	var saved := SiteStore.save(data, path)
	assert(saved.ok, str(saved))
	var wrapper: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var legacy: Dictionary = JSON.parse_string(wrapper.payload)
	legacy.state.armies[0].erase("garrison_feature_id")
	for row: Dictionary in legacy.state.armies[0].units: row.erase("military_role")
	var old_supply: Dictionary = legacy.state.team_supply[str(fixture.army.team_id)]
	old_supply.version = 1
	old_supply.erase("training_feature_id")
	var before_training: float = legacy.state.armies[0].training
	var before_sustain := JSON.stringify(old_supply.sustain)
	var body := JSON.stringify(legacy, "", true, true)
	var legacy_file := FileAccess.open(path + ".legacy", FileAccess.WRITE)
	assert(legacy_file != null)
	legacy_file.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}))
	legacy_file.close()
	var loaded := SiteStore.load_site(path + ".legacy")
	assert(loaded.ok, str(loaded))
	var migrated: Dictionary = loaded.data.site.team_supply[str(fixture.army.team_id)]
	assert(migrated.version == 2 and not migrated.training_order and migrated.training_requester == -1 and migrated.training_feature_id == "")
	assert(float(loaded.data.site.armies[0].training) == before_training)
	assert(JSON.parse_string(JSON.stringify(migrated.sustain)) == JSON.parse_string(before_sustain), "Migration changed original food/hunger history")
	assert(loaded.data.site.armies[0].units[0].military_role == "officer" and loaded.data.site.armies[0].units[1].military_role == "soldier")
	var before := JSON.stringify(data.site)
	assert(not SiteRuntime.request_resize(data, ground, _cells(data, "training_ground", Vector2i(25, 10), Vector2i(11, 10)), Callable(), 1).ok)
	assert(JSON.stringify(data.site) == before, "Rejected active-school resize changed its command or work clock")
	assert(SiteRuntime.cancel_feature(data, ground, Callable(), 1).ok)
	assert(not supply.training_order and supply.training_requester == -1 and supply.training_feature_id == "" and fixture.army.training == 37.0)
	fixture.army.set_garrison(barracks)
	data.site.armies = [fixture.army.capture_combat_state()]
	assert(SiteStore._validate_military(data, data.site).ok)
	for fault: String in ["missing", "faction", "commander", "home_outside", "home_blocked", "cell_invalid", "departed", "moving", "role", "capacity"]:
		var bad: Dictionary = data.site.duplicate(true)
		match fault:
			"missing": bad.armies[0].garrison_feature_id = "99999"
			"faction": bad.features[barracks].owner_faction = 2
			"commander": bad.armies[0].current_commander = 0
			"home_outside": bad.armies[0].units[0].slot = [40, 40]
			"home_blocked": bad.armies[0].units[0].slot = [10, 11]
			"cell_invalid": bad.armies[0].units[0].cell = [-1, -1]
			"departed": bad.armies[0].units[0].departed = true
			"moving": bad.armies[0].units[0].destination = [13, 12]
			"role": bad.armies[0].units[0].military_role = "invented"
			"capacity":
				while bad.armies[0].units.size() <= 100: bad.armies[0].units.append(bad.armies[0].units[0].duplicate(true))
		assert(not SiteStore._validate_military(data, bad).ok, "Invalid garrison reference accepted: " + fault)
	var outside: Dictionary = data.site.duplicate(true)
	outside.armies[0].units[0].cell = [40, 40]
	assert(SiteStore._validate_military(data, outside).ok, "A registered original person may be outside while preserving their original home")
	outside.armies[0].units[0].destination = [39, 40]
	assert(SiteStore._validate_military(data, outside).ok, "A legal original return step must retain garrison registration")
	outside.armies[0].units[0].captive = true
	assert(SiteStore._validate_military(data, outside).ok, "Registration survives captivity; full Store separately validates the original captivity relation")
	# Isolate the capacity validator at its exact boundary. The full Store
	# roundtrip below still uses real original Army people and unique positions.
	var boundary: Dictionary = data.site.duplicate(true)
	var boundary_rows: Array = boundary.armies[0].units
	var capacity := SiteRuntime.military_capacity(data, data.site.features[barracks])
	while boundary_rows.size() < capacity + 1:
		var row: Dictionary = boundary_rows[0].duplicate(true)
		row.person_id = 10000 + boundary_rows.size()
		boundary_rows.append(row)
	boundary_rows[-1].hp = 0.0
	assert(SiteStore._validate_military(data, boundary).ok, "Dead original rows must not consume living garrison capacity")
	boundary_rows[-1].hp = 1.0
	boundary_rows[-1].ko = 20.0
	assert(not SiteStore._validate_military(data, boundary).ok, "Living KO people still count toward garrison capacity")
	boundary_rows[-1].captive = true
	boundary_rows[-1].cell = [40, 40]
	assert(not SiteStore._validate_military(data, boundary).ok, "A living captive outside still reserves their original garrison capacity")
	saved = SiteStore.save(data, path + ".garrison")
	assert(saved.ok, str(saved))
	loaded = SiteStore.load_site(path + ".garrison")
	assert(loaded.ok, str(loaded))
	assert(loaded.data.site.armies[0].garrison_feature_id == barracks)
	for index in range(ids.size()):
		assert(int(loaded.data.site.armies[0].units[index].person_id) == ids[index])
		assert(loaded.data.site.armies[0].units[index].military_role == fixture.army.combat_units[index].military_role)
	assert(not SiteRuntime.cancel_feature(loaded.data, barracks, Callable(), 1).ok)
	var casualty: Dictionary = fixture.army.combat_units[2]
	casualty.cargo["wood"] = 1 # Explicit original-person fixture property.
	fixture.army.apply_unit_contact(2, {"environmental": true, "shield": false,
		"result": {"hp": 1000.0, "stun": 0.0, "guard_break": false}})
	assert(float(casualty.hp) == 0.0 and is_same(casualty, fixture.army.combat_units[2]))
	fixture.army.settle_combat_command() # Formal Lab settles commands after contacts before a save can occur.
	assert(not bool(casualty.present), "Dead original garrison row retained active presence after formal settlement")
	supply.life_checkpoint[str(ids[2])] = 2
	data.site.armies = [fixture.army.capture_combat_state()]
	assert(TerrainArmy.valid_combat_state(data.site.armies[0], data, {}, data.site), "Settled garrison death must preserve the original Army save contract")
	saved = SiteStore.save(data, path + ".garrison_dead")
	assert(saved.ok, str(saved))
	loaded = SiteStore.load_site(path + ".garrison_dead")
	assert(loaded.ok, str(loaded))
	var dead_saved: Dictionary = loaded.data.site.armies[0].units[2]
	assert(loaded.data.site.armies[0].units.size() == ids.size() and int(dead_saved.person_id) == ids[2])
	assert(float(dead_saved.hp) == 0.0 and dead_saved.cargo == {"wood": 1} and loaded.data.site.armies[0].garrison_feature_id == barracks)
	fixture.close()
	completed += 1

func _check_military_construction_and_cancel() -> void:
	for kind: String in SiteRuntime.MILITARY_KINDS:
		var data := _military_fixture()
		var cells := _cells(data, kind, Vector2i(10, 10), Vector2i(10, 10))
		var blocked := func(cell: Vector2i) -> bool: return cell == Vector2i(13, 13)
		var before := JSON.stringify(data.site)
		assert(not SiteRuntime.request_build(data, kind, cells, blocked, {"owner_faction": 1}).ok)
		assert(JSON.stringify(data.site) == before)
		var built := SiteRuntime.request_build(data, kind, cells, Callable(), {"owner_faction": 1})
		assert(built.ok, str(built))
		var key := str(built.feature)
		var feature: Dictionary = data.site.features[key]
		assert(int(data.site.inventory.wood) == 9900 and str(feature.stage) == "planned")
		var task := _task(key, "construct", int(feature.entrance))
		SiteRuntime._feature_work(data, key, float(feature.work) * 0.5, Callable(), Callable(), task, {}, 20, 1)
		assert(str(feature.stage) == "building" and float(feature.progress) == float(feature.work) * 0.5)
		var progress := float(feature.progress)
		SiteRuntime._feature_work(data, key, float(feature.work), blocked, Callable(), task, {}, 20, 1)
		assert(float(feature.progress) == progress, "Occupied construction continued")
		before = JSON.stringify(data.site)
		assert(not SiteRuntime.cancel_feature(data, key, Callable(), 2).ok)
		assert(JSON.stringify(data.site) == before)
		assert(SiteRuntime.cancel_feature(data, key, Callable(), 1).ok)
		assert(int(data.site.inventory.wood) == 9950 and not data.site.features.has(key), "Half-built cancellation must return only unused material")
		key = _build(data, kind, Vector2i(10, 10), Vector2i(10, 10))
		feature = data.site.features[key]
		var layout := SiteRuntime.military_layout(data, key)
		assert(layout.ok and layout.complete and int(layout.capacity) == (72 if kind == "barracks" else 92) and int(layout.owner_faction) == 1)
		var blocked_cells: Array = SiteRuntime.feature_geometry(data, feature).blocked
		assert(not blocked_cells.is_empty() and blocked_cells.size() + int(layout.capacity) == 100)
		for index: int in cells:
			assert(data.is_walkable(data.cell_from_index(index)) == (index not in blocked_cells) and int(data.feature_at[index]) == int(key))
		before = JSON.stringify(data.site)
		assert(not SiteRuntime.cancel_feature(data, key, blocked, 1).ok)
		assert(JSON.stringify(data.site) == before, "Demolition discarded an occupied courtyard")
		var wood := int(data.site.inventory.wood)
		assert(SiteRuntime.cancel_feature(data, key, Callable(), 1).ok and int(data.site.inventory.wood) == wood)
	completed += 1

func _check_military_resize_and_guards() -> void:
	for kind: String in SiteRuntime.MILITARY_KINDS:
		var data := _military_fixture()
		var small := _cells(data, kind, Vector2i(10, 10), Vector2i(10, 10))
		var large := _cells(data, kind, Vector2i(10, 10), Vector2i(11, 10))
		var key := _build(data, kind, Vector2i(10, 10), Vector2i(10, 10))
		var feature: Dictionary = data.site.features[key]
		var original_serial := int(data.site.next_feature)
		var wood := int(data.site.inventory.wood)
		assert(SiteRuntime.request_resize(data, key, large, Callable(), 1).ok)
		assert(is_same(feature, data.site.features[key]) and feature.cells == small and int(data.site.next_feature) == original_serial)
		assert(feature.pending_build.added_cells.size() == 10 and int(feature.pending_build.cost.wood) == 10)
		assert(float(feature.pending_build.work) == (20.0 if kind == "barracks" else 5.0))
		var task := _task(key, "construct", int(feature.pending_build.entrance))
		SiteRuntime._feature_work(data, key, float(feature.pending_build.work) * 0.5, Callable(), Callable(), task, {}, 20, 1)
		assert(SiteRuntime.cancel_feature(data, key, Callable(), 1).ok)
		assert(is_same(feature, data.site.features[key]) and feature.cells == small and not feature.has("pending_build"))
		assert(int(data.site.inventory.wood) == wood - 5, "Cancelled expansion refunds only its unused half")
		assert(SiteRuntime.request_resize(data, key, large, Callable(), 1).ok)
		_finish_military(data, key)
		assert(feature.cells == large and int(data.site.next_feature) == original_serial)
		if kind == "barracks":
			var courtyard_person := Vector2i(16, 10)
			assert(data.is_walkable(courtyard_person))
			var before_moved_module := JSON.stringify(data.site)
			var claim := func(cell: Vector2i) -> bool: return cell == courtyard_person
			assert(not SiteRuntime.request_resize(data, key, _cells(data, kind, Vector2i(10, 10), Vector2i(12, 10)), claim, 1).ok)
			assert(JSON.stringify(data.site) == before_moved_module and data.is_walkable(courtyard_person), "Expansion moved a building over a real courtyard person")
		var before := JSON.stringify(data.site)
		var occupied_removed := func(cell: Vector2i) -> bool: return cell == Vector2i(20, 15)
		assert(not SiteRuntime.request_resize(data, key, small, occupied_removed, 1).ok)
		assert(JSON.stringify(data.site) == before)
		if kind == "barracks":
			data.site.armies = [{"garrison_feature_id": key, "units": [{"person_id": 77, "hp": 0.0}]}]
			before = JSON.stringify(data.site)
			assert(not SiteRuntime.request_resize(data, key, small, Callable(), 1).ok)
			assert(not SiteRuntime.cancel_feature(data, key, Callable(), 1).ok)
			assert(JSON.stringify(data.site) == before, "Stored casualty retains its original garrison reference and property")
			data.site.armies = []
		wood = int(data.site.inventory.wood)
		assert(SiteRuntime.request_resize(data, key, small, Callable(), 1).ok)
		assert(is_same(feature, data.site.features[key]) and feature.cells == small and int(data.site.inventory.wood) == wood)
		assert(int(data.site.next_feature) == original_serial)
	completed += 1

func _military_store_fixture(kind: String) -> TerrainData:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.FOREST, 12345, {"size": Vector2i(72, 72)})
	SiteEnvironment.initialize(data, "military-building-store-" + kind)
	for y: int in range(5, 70):
		for x: int in range(5, 70):
			var index := data.index(Vector2i(x, y))
			data.site.terrain_changes[str(index)] = 0
			data.height_levels[index] = 0
	for source: String in data.resource_base:
		SiteEnvironment.change(data, source, {"cleared": true, "remaining": 0})
	data.site.depot_cell = data.index(Vector2i(3, 3))
	data.site.worker.cell = data.index(Vector2i(3, 4))
	data.site.worker_enabled = false
	data.site.inventory = {"wood": 10000, "stone": 10000, "tools": 10}
	data.site.capacity = 100000
	assert(SiteRuntime.initialize_item_storage(data.site).ok)
	SiteRuntime.rebuild_terrain_edges(data)
	SiteEnvironment.rebuild_indexes(data)
	return data

func _check_military_large_store() -> void:
	for kind: String in SiteRuntime.MILITARY_KINDS:
		var data := _military_store_fixture(kind)
		var large := _build(data, kind, Vector2i(5, 5), Vector2i(50, 50))
		var expanding := _build(data, kind, Vector2i(58, 10), Vector2i(10, 10))
		var enlarged := _cells(data, kind, Vector2i(58, 10), Vector2i(11, 10))
		assert(SiteRuntime.request_resize(data, expanding, enlarged, Callable(), 1).ok)
		var job: Dictionary = data.site.features[expanding].pending_build
		var task := _task(expanding, "construct", int(job.entrance))
		SiteRuntime._feature_work(data, expanding, float(job.work) * 0.25, Callable(), Callable(), task, {}, 20, 1)
		var planned := SiteRuntime.request_build(data, kind, _cells(data, kind, Vector2i(58, 35), Vector2i(10, 10)), Callable(), {"owner_faction": 1})
		assert(planned.ok)
		var path := MILITARY_SAVE_ROOT.path_join(kind + ".json")
		var saved := SiteStore.save(data, path)
		assert(saved.ok, str(saved))
		var encoded := FileAccess.get_file_as_string(path)
		var loaded := SiteStore.load_site(path)
		assert(loaded.ok, str(loaded))
		var restored: TerrainData = loaded.data
		assert(restored.fingerprint() == data.fingerprint())
		assert(JSON.parse_string(JSON.stringify(restored.site.features)) == JSON.parse_string(JSON.stringify(data.site.features)))
		assert(restored.site.features[large].cells.size() == 2500)
		assert(restored.site.features[expanding].pending_build.cost.wood is int)
		assert(is_equal_approx(float(restored.site.features[expanding].pending_build.progress), float(job.progress)))
		var blocked_cells: Array = SiteRuntime.feature_geometry(restored, restored.site.features[large]).blocked
		assert(SiteRuntime.military_capacity(restored, restored.site.features[large]) == (2280 if kind == "barracks" else 2452))
		for index: int in restored.site.features[large].cells:
			assert(int(restored.feature_at[index]) == int(large) and restored.is_walkable(restored.cell_from_index(index)) == (index not in blocked_cells))
		var inventory := JSON.stringify(restored.site.inventory)
		_finish_military(restored, expanding)
		assert(restored.site.features[expanding].cells == enlarged and JSON.stringify(restored.site.inventory) == inventory, "Resumed paid expansion charged its materials twice")
		assert(SiteRuntime.cancel_feature(restored, str(planned.feature), Callable(), 1).ok)
		assert(SiteStore.save(restored, path + ".resumed").ok)
		assert(SiteStore.load_site(path + ".resumed").ok)
		for corruption: String in ["legacy", "fraction", "size", "work", "paid_area"]:
			var wrapper: Dictionary = JSON.parse_string(encoded)
			var payload: Dictionary = JSON.parse_string(wrapper.payload)
			var broken: Dictionary = payload.state.features[large]
			match corruption:
				"legacy": broken.erase("layout_version")
				"fraction": payload.state.features[expanding].pending_build.cost.wood += 0.25
				"size": broken.cells.remove_at(100)
				"work": payload.state.features[expanding].pending_build.work += 1.0
				"paid_area": broken.cost.wood = 100
			var body := JSON.stringify(payload, "", true, true)
			var file := FileAccess.open(path + "." + corruption, FileAccess.WRITE)
			assert(file != null)
			file.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}))
			file.close()
			assert(not SiteStore.load_site(path + "." + corruption).ok, "Corrupt military building was accepted: " + corruption)
		assert(FileAccess.get_file_as_string(path) == encoded, "A failed load changed the valid original save")
	completed += 1
