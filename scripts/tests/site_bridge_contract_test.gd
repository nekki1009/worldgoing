extends "res://scripts/tests/site_building_ui_test.gd"
## Candidate: run only after bridge_v1.patch is merged. No engine run claimed.
var bridge_output := ""
var bridge_groups := 0
var bridge_rejected := 0

func _run() -> void:
	deadline = Time.get_ticks_msec() + 150000
	_bridge_output("contract")
	assert(_check_bridge_builds())
	assert(_check_bridge_invalid())
	assert(_check_bridge_store())
	assert(_check_bridge_actor())
	assert(bridge_groups == 4 and bridge_rejected == 18)
	TerrainArmy.release_contact_source()
	print("SITE_BRIDGE_CONTRACT_PASS: 24 wood/stone four-direction spans, paid construction, same XY deck and side guards, zero ship clearance, protected reservations, fixed-base partial/complete/demolished Store, 18 corrupt snapshots rejected, original Actor half-step/resume/crossing; no native/GPU/travel/performance claim")
	quit(0)

func _bridge_output(suffix: String) -> void:
	bridge_output = "res://output/site_building_close_20261004/region_candidate/bridge/runs/%s-%d-%d" % [suffix, OS.get_process_id(), Time.get_ticks_usec()]
	assert(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(bridge_output)))
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(bridge_output)) == OK)

func _bridge_fixture(quarter: int = 0, span: int = 4, deck: int = 1) -> TerrainData:
	var data := _building_fixture()
	data.resource_base.clear()
	data.site.changes.clear()
	data.site.terrain_changes.clear()
	data.site.id = RegionGrid.site_id(RegionGrid.ATLAS_ID, Vector2i.ZERO)
	data.height_levels.fill(deck)
	data.surface_types.fill(TerrainData.Surface.GRASS)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.ramp_edges.fill(0)
	data.cliff_drops.fill(0)
	data.water_kind.fill(0)
	data.water_body.fill(-1)
	data.spawn_cell = Vector2i(10, 10)
	for y: int in range(data.size.y):
		for x: int in range(data.size.x):
			var cross := y if quarter % 2 == 0 else x
			if cross < 20 or cross >= 20 + span: continue
			var index := data.index(Vector2i(x, y))
			data.height_levels[index] = 0
			data.surface_types[index] = TerrainData.Surface.WATER
			data.flags[index] = TerrainData.Flag.WET | TerrainData.Flag.BLOCKED
			data.water_kind[index] = 1
			data.water_body[index] = 0
	data.parameters["composition"] = "fixed_geography"
	data.parameters["navigable_water_version"] = 1
	data.parameters["navigable_water_bodies"] = [0]
	Runtime.rebuild_terrain_edges(data)
	data.parameters["fixed_base"] = {"base_kind": "fixed_geography", "atlas_id": RegionGrid.ATLAS_ID,
		"site_id": str(data.site.id), "site": [0, 0], "grid_contract_version": 1,
		"base_revision": "bridge_contract_v1", "manifest_sha256": "b".repeat(64),
		"terrain_fingerprint": data.fingerprint(), "ramp_rule_revision": RegionTerrainAdapter.RAMP_RULE_REVISION}
	Env.rebuild_indexes(data)
	return data

func _bridge_base(data: TerrainData) -> TerrainData:
	var result := TerrainData.new()
	result.allocate(data.size)
	for field: String in ["height_levels", "surface_types", "flags", "cliff_drops", "ramp_edges", "detail_variation",
		"water_kind", "water_body", "fertility", "moisture", "drainage", "foundation", "groundwater"]:
		result.set(field, data.get(field).duplicate())
	result.spawn_cell = data.spawn_cell
	result.preset = data.preset
	result.seed_value = data.seed_value
	result.parameters = data.parameters.duplicate(true)
	result.resource_base = data.resource_base.duplicate(true)
	return result

func _bridge_loader(base: TerrainData) -> Callable:
	return func(saved: Dictionary) -> Dictionary:
		if not Store._same_fixed_base(saved, base.parameters.fixed_base): return Runtime.fail("SAVE_VERSION")
		return {"ok": true, "data": _bridge_base(base), "base": base.parameters.fixed_base.duplicate(true)}

func _bridge_options(quarter: int, material: String) -> Dictionary:
	return {"layout_version": 1, "quarter": quarter, "material": material, "owner_faction": 1}

func _bridge_cells(data: TerrainData, quarter: int, span: int, material: String = "wood") -> Array[int]:
	var extent := Vector2i(1, span) if quarter % 2 == 0 else Vector2i(span, 1)
	var layout := Runtime.building_cells(data, "bridge", Vector2i(20, 20), extent, _bridge_options(quarter, material))
	assert(layout.ok, str(layout))
	var result: Array[int] = []
	result.assign(layout.cells)
	return result

func _bridge_task(data: TerrainData, key: String) -> Dictionary:
	return {"target": "feature:" + key, "action": "construct", "cell": int(data.site.features[key].entrance), "mode": "work", "status": "", "progress": 0.0}

func _bridge_finish(data: TerrainData, key: String, occupied: Callable = Callable()) -> Dictionary:
	var task := _bridge_task(data, key)
	Runtime._feature_work(data, key, float(data.site.features[key].work), occupied, Callable(), task, {}, 20, 1)
	return task

func _check_bridge_builds() -> bool:
	for quarter: int in range(4):
		for material: String in ["wood", "stone"]:
			for span: int in [2, 6, 12]:
				var data := _bridge_fixture(quarter, span, 0 if span == 2 else 1)
				var natural_flags := data.flags.duplicate()
				var natural_heights := data.height_levels.duplicate()
				var cells := _bridge_cells(data, quarter, span, material)
				var options := _bridge_options(quarter, material)
				var before := JSON.stringify(data.site)
				var preview := Runtime.preview_build(data, "bridge", cells, Callable(), options)
				assert(preview.ok and JSON.stringify(data.site) == before, str(preview))
				assert(preview.cost == ({"wood": 6 * span} if material == "wood" else {"stone": 8 * span, "wood": 2 * span}))
				assert(float(preview.work) == (10.0 if material == "wood" else 18.0) * span)
				var built := Runtime.request_build(data, "bridge", cells, Callable(), options)
				assert(built.ok, str(built))
				var key := str(built.feature)
				var feature: Dictionary = data.site.features[key]
				var paid: Dictionary = data.site.inventory.duplicate(true)
				assert(str(feature.stage) == "planned" and not feature.has("parts") and Runtime.feature_geometry(data, feature).parts.is_empty())
				assert(not data.is_walkable(data.cell_from_index(cells[0])) and not data.can_navigate_water(data.cell_from_index(cells[0])))
				var task := _bridge_task(data, key)
				Runtime._feature_work(data, key, float(feature.work) * 0.5, Callable(), Callable(), task, {}, 20, 1)
				assert(feature.stage == "building" and float(feature.progress) == float(feature.work) * 0.5 and data.bridge_navigation_flags.is_empty())
				var blocked_cell := data.cell_from_index(cells[0])
				_bridge_finish(data, key, func(cell: Vector2i) -> bool: return cell == blocked_cell)
				assert(feature.stage == "building" and data.site.inventory == paid)
				_bridge_finish(data, key)
				assert(feature.stage == "complete" and data.site.inventory == paid)
				assert(Runtime.validate_feature_layout(data, feature).ok)
				var bridge := Runtime.bridge_layout(data, cells, quarter)
				assert(bridge.ok and data.effective_height(data.cell_from_index(cells[0])) == int(bridge.level))
				var entry := data.cell_from_index(int(bridge.entrance))
				var exit_bank := data.cell_from_index(int(bridge.exit))
				var direction := Vector2i(signi(exit_bank.x - entry.x), signi(exit_bank.y - entry.y))
				var cursor := entry
				while cursor != exit_bank:
					assert(data.can_step(cursor, cursor + direction) and data.can_step(cursor + direction, cursor))
					cursor += direction
				for index: int in cells:
					var cell := data.cell_from_index(index)
					assert(data.is_walkable(cell) and not data.can_navigate_water(cell))
					assert((data.flags[index] & TerrainData.Flag.WALKABLE) == 0 and (data.navigation_flags()[index] & TerrainData.Flag.WALKABLE) != 0)
					for side: Vector2i in TerrainData.DIRECTIONS:
						if side == direction or side == -direction: continue
						var side_id := TerrainData.DIRECTIONS.find(side)
						assert((data.navigation_ramps()[index] & (1 << (side_id + 4))) != 0)
				assert(Runtime.damage_structure_part(data, key, "c:" + str(cells[0]), 100.0).code == "NO_TARGET")
				assert(Runtime.request_repair(data, key, "c:" + str(cells[0]), 1).code == "NO_TARGET")
				var immutable := JSON.stringify(data.site)
				assert(not Runtime.cancel_feature(data, key, func(cell: Vector2i) -> bool: return cell == blocked_cell, 1).ok)
				assert(JSON.stringify(data.site) == immutable)
				assert(Runtime.cancel_feature(data, key, Callable(), 1).ok)
				assert(not data.site.features.has(key) and data.site.next_feature == int(key) + 1)
				assert(data.flags == natural_flags and data.height_levels == natural_heights and data.navigation_flags() == natural_flags)
				assert(not data.is_walkable(blocked_cell) and data.can_navigate_water(blocked_cell))
	bridge_groups += 1
	return true

func _check_bridge_invalid() -> bool:
	var data := _bridge_fixture()
	var cells := _bridge_cells(data, 0, 4)
	var before := JSON.stringify(data.site)
	for options: Dictionary in [{"bridge_version": 2}, {"bridge_version": true}, {"bridge_clearance": 1}, {"bridge_clearance": false}, {"material": "iron"}]:
		assert(not Runtime.preview_build(data, "bridge", cells, Callable(), options).ok)
	assert(not Runtime.building_cells(data, "bridge", Vector2i(20, 20), Vector2i(2, 4)).ok)
	assert(not Runtime.building_cells(data, "bridge", Vector2i(20, 20), Vector2i(1, 13)).ok)
	var original := data.height_levels.duplicate()
	data.height_levels[data.index(Vector2i(20, 24))] = 2
	assert(not Runtime.preview_build(data, "bridge", cells).ok)
	data.height_levels = original
	data.surface_types[cells[1]] = TerrainData.Surface.GRASS
	assert(not Runtime.preview_build(data, "bridge", cells).ok)
	data.surface_types[cells[1]] = TerrainData.Surface.WATER
	var bank := data.index(Vector2i(20, 24))
	data.static_blocked[bank] = 1
	assert(not Runtime.preview_build(data, "bridge", cells).ok)
	data.static_blocked[bank] = 0
	assert(not Runtime.preview_build(data, "bridge", cells, func(cell: Vector2i) -> bool: return cell == Vector2i(20, 21)).ok)
	assert(JSON.stringify(data.site) == before)
	var built := Runtime.request_build(data, "bridge", cells, Callable(), _bridge_options(0, "wood"))
	assert(built.ok)
	_bridge_finish(data, str(built.feature))
	var ordinary := Runtime.building_cells(data, "house", Vector2i(20, 24), Vector2i.ONE, {"variant": "small"})
	assert(ordinary.ok and not Runtime.preview_build(data, "house", ordinary.cells, Callable(), {"variant": "small"}).ok)
	bridge_groups += 1
	return true

func _check_bridge_store() -> bool:
	for material: String in ["wood", "stone"]:
		var data := _bridge_fixture(1, 4)
		var base := _bridge_base(data)
		var path := bridge_output.path_join(material + "_bridge.json")
		var result := Runtime.request_build(data, "bridge", _bridge_cells(data, 1, 4, material), Callable(), _bridge_options(1, material))
		assert(result.ok, str(result))
		var key := str(result.feature)
		var task := _bridge_task(data, key)
		Runtime._feature_work(data, key, float(data.site.features[key].work) * 0.5, Callable(), Callable(), task, {}, 20, 1)
		assert(Store.save(data, path + ".partial").ok)
		var loaded := Store.load_site(path + ".partial", _bridge_loader(base))
		assert(loaded.ok, str(loaded))
		var partial: TerrainData = loaded.data
		assert(partial.site.features[key].stage == "building" and partial.site.inventory == data.site.inventory and partial.bridge_navigation_flags.is_empty())
		_bridge_finish(partial, key)
		assert(partial.site.features[key].stage == "complete" and partial.site.inventory == data.site.inventory)
		assert(Store.save(partial, path).ok)
		loaded = Store.load_site(path, _bridge_loader(base))
		assert(loaded.ok, str(loaded))
		var restored: TerrainData = loaded.data
		assert(restored.flags == base.flags and restored.navigation_flags() == partial.navigation_flags())
		assert(restored.site.features[key] == partial.site.features[key] and restored.site.next_feature == int(key) + 1, str({"restored": restored.site.features[key], "expected": partial.site.features[key]}))
		var clean := FileAccess.get_file_as_string(path)
		var envelope: Dictionary = JSON.parse_string(clean)
		var payload: Dictionary = JSON.parse_string(envelope.payload)
		for field: String in ["bridge_version", "bridge_clearance", "missing_version", "level", "entrance", "cost", "work", "parts", "non_bridge"]:
			var bad := payload.duplicate(true)
			var feature: Dictionary = bad.state.features[key]
			match field:
				"bridge_version": feature.bridge_version = 2
				"bridge_clearance": feature.bridge_clearance = 1
				"missing_version": feature.erase("bridge_version")
				"level": feature.level = int(feature.level) + 1
				"entrance": feature.entrance = feature.cells[0]
				"cost": feature.cost.wood = int(feature.cost.wood) + 1
				"work": feature.work = float(feature.work) + 1.0
				"parts": feature.parts = {}
				"non_bridge": feature.kind = "road"
			var bad_path := path + ".invalid_" + field
			_bridge_write_payload(bad_path, bad)
			var corrupted := FileAccess.get_file_as_string(bad_path)
			var rejected := Store.load_site(bad_path, _bridge_loader(base))
			assert(not rejected.ok and not rejected.has("data"), field + ": " + str(rejected))
			assert(FileAccess.get_file_as_string(path) == clean and FileAccess.get_file_as_string(bad_path) == corrupted)
			bridge_rejected += 1
		assert(Runtime.cancel_feature(restored, key, Callable(), 1).ok and Store.save(restored, path + ".removed").ok)
		loaded = Store.load_site(path + ".removed", _bridge_loader(base))
		assert(loaded.ok and loaded.data.site.features.is_empty() and loaded.data.navigation_flags() == base.flags)
		assert(loaded.data.can_navigate_water(Vector2i(21, 20)) and not loaded.data.is_walkable(Vector2i(21, 20)))
	bridge_groups += 1
	return true

func _bridge_write_payload(path: String, payload: Dictionary) -> void:
	assert(path.begins_with(bridge_output + "/"))
	var body := JSON.stringify(payload, "", true, true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}))
	file.close()

func _check_bridge_actor() -> bool:
	var data := _bridge_fixture()
	var base := _bridge_base(data)
	var lab := _building_lab(data)
	var controller := lab.site_controller
	var key := _formal_feature(data, "bridge", Vector2i(20, 20), Vector2i(1, 4))
	controller.feature_key = key
	controller.update_ui()
	assert(controller.building_actions.attack.disabled and controller.building_actions.repair.disabled and controller.building_actions.resize.disabled)
	assert(controller.building_selection.text.contains("橋下不通船"))
	var actor := lab.character
	assert(actor.place(Vector2i(20, 24), true) and actor.step(Vector2i.UP))
	var identity := actor.person_id
	var holder := actor.item_state
	var cargo: Dictionary = data.site.manual.cargo
	actor._advance_movement(TerrainTestCharacter.MOVE_DURATION * 0.5)
	assert(actor.is_moving() and actor.occupies_cell(Vector2i(20, 24)) and actor.occupies_cell(Vector2i(20, 23)))
	var before := actor.capture_state()
	var feature_before := JSON.stringify(data.site.features)
	assert(not Runtime.cancel_feature(data, key, controller.reserves_cell, 1).ok)
	assert(actor.capture_state() == before and is_same(actor.item_state, holder) and is_same(data.site.manual.cargo, cargo))
	assert(JSON.stringify(data.site.features) == feature_before)
	assert(controller._capture_for_save().ok)
	var path := bridge_output.path_join("actor_half_step.json")
	var saved := Store.save(data, path)
	assert(saved.ok, str(saved))
	var loaded := Store.load_site(path, _bridge_loader(base))
	assert(loaded.ok, str(loaded))
	lab.bind_terrain(loaded.data)
	actor = lab.character
	assert(actor.person_id == identity and actor.is_moving() and actor.capture_state().movement == before.movement)
	actor._advance_movement(TerrainTestCharacter.MOVE_DURATION * 0.5)
	assert(actor.terrain_cell == Vector2i(20, 23) and not actor.is_moving())
	while actor.terrain_cell != Vector2i(20, 19):
		assert(actor.step(Vector2i.UP))
		actor._advance_movement(TerrainTestCharacter.MOVE_DURATION)
	assert(actor.person_id == identity and not actor.is_moving())
	assert(Runtime.cancel_feature(lab.terrain, key, lab.site_controller.reserves_cell, 1).ok)
	assert(lab.terrain.can_navigate_water(Vector2i(20, 21)) and not lab.terrain.is_walkable(Vector2i(20, 21)))
	lab.free()
	bridge_groups += 1
	return true
