extends "res://scripts/tests/site_building_ui_test.gd"
## Initial learned-skill fixture tests the actual public caller, not first-earned.
## Existing site_f09_family_first_earned_test retains genuine unknown-to-earned gates.
const FamilyTech = preload("res://scripts/terrain_lab/site_technology.gd")
const Presenter = preload("res://scripts/terrain_lab/site_resource_view.gd")
const SURVEY_SAVE := "res://.godot-temp/site_survey_stakes/roundtrip.json"

func _options(data: TerrainData, quarter: int, operator_id: int) -> Dictionary:
	var plan_cells: Array[int] = []
	var marks: Array[int] = []
	if quarter % 2 == 0:
		plan_cells.assign([data.index(Vector2i(24, 24)), data.index(Vector2i(25, 24)), data.index(Vector2i(24, 25)), data.index(Vector2i(25, 25))])
		marks.assign([data.index(Vector2i(24, 23)), data.index(Vector2i(25, 23))])
	else:
		plan_cells.assign([data.index(Vector2i(24, 24)), data.index(Vector2i(25, 24)), data.index(Vector2i(24, 25)), data.index(Vector2i(25, 25))])
		marks.assign([data.index(Vector2i(23, 24)), data.index(Vector2i(23, 25))])
	return {"marks": marks, "options": {"layout_version": 1, "quarter": quarter, "owner_faction": 1,
		"survey_plan": {"kind": "house", "cells": plan_cells, "options": {"layout_version": 1, "quarter": 0, "variant": "small", "owner_faction": 1}},
		"survey_operator": {"site_id": str(data.site.id), "person_id": operator_id}}}

func _run() -> void:
	if OS.get_cmdline_user_args().has("--fail-fast-probe"):
		var probe_ok: bool = _survey_fail_probe_outer()
		if not probe_ok: return
		_survey_check(false, "Fail-fast probe unexpectedly passed")
		return
	var data: TerrainData = _survey_building_fixture()
	if _survey_failed: return
	if not _survey_check(data != null, "Fixture helper must return its original TerrainData"): return
	var presenter: SiteResourceView = Presenter.new()
	presenter.data = data
	for quarter: int in range(4):
		var fixture: Dictionary = _options(data, quarter, 1)
		var marks: Array[int] = []
		marks.assign(fixture.marks)
		var spec: Dictionary = Runtime.building_spec("survey_stakes", fixture.options)
		var expected_size := Vector2i(2, 1)
		if quarter % 2: expected_size = Vector2i(1, 2)
		if not _survey_check(spec.ok and spec.size == expected_size and int(spec.max_cells) == 2): return
		if not _survey_check(spec.cost == {"wood": 2} and is_equal_approx(float(spec.work) * 60.0, 120.0) and not bool(spec.solid)): return
		var preview: Dictionary = Runtime.preview_build(data, "survey_stakes", marks, Callable(), fixture.options)
		if not _survey_check(preview.ok and preview.cost == {"wood": 2} and is_equal_approx(float(preview.work), 2.0), str(preview)): return
		var stock: int = int(data.site.inventory.wood)
		var built: Dictionary = Runtime.request_build(data, "survey_stakes", marks, Callable(), fixture.options)
		if not _survey_check(built.ok, str(built)): return
		var key: String = str(built.feature)
		var feature: Dictionary = data.site.features[key]
		if not _survey_check(int(data.site.inventory.wood) == stock - 2 and feature.survey_plan == fixture.options.survey_plan): return
		var checked: Dictionary = Runtime.validate_feature_layout(data, feature)
		if not _survey_check(checked.ok, str(checked)): return
		if not _survey_check(presenter.building_art_key(feature) == "survey_stakes" + ["", "_west", "_north", "_east"][quarter]): return
		var draws: Array[Dictionary] = presenter.building_part_draws(feature)
		if not _survey_check(draws.size() == 2, "Each real post uses one approved source component"): return
		for index: int in range(2):
			var draw: Dictionary = draws[index]
			if not _survey_check(is_equal_approx(float(draw.rect.size.y), float(Presenter.CELL) * 0.55), "Slender posts do not stretch the entire pair to one cell width"): return
			var contact_cell: Vector2i = data.cell_from_index(marks[index])
			if not _survey_check(int(draw.row) == contact_cell.y, "Far and near stakes retain their actual original draw rows"): return
			var sprite: Dictionary = presenter._building_asset(presenter.building_art_key(feature), "stake_%d" % index)
			var ground_anchor := Vector2(float(sprite.ground_anchor[0]), float(sprite.ground_anchor[1]))
			var expected_contact := (Vector2(contact_cell) + Vector2(0.5, 0.5)) * Presenter.CELL
			if not _survey_check((draw.rect.position + ground_anchor * draw.rect.size).is_equal_approx(expected_contact), "Source contact anchor lands in its own real cell"): return
		var raw: Variant = JSON.parse_string(JSON.stringify(feature))
		if not _survey_check(raw is Dictionary): return
		var json_checked: Dictionary = Runtime.validate_feature_layout(data, raw, false)
		if not _survey_check(json_checked.ok, "Integer identity must compare correctly before Store normalization: " + str(json_checked)): return
		var state: Dictionary = data.site.duplicate(true)
		state.features[key] = raw
		var store_checked: Dictionary = Store._validate_state(data, state)
		if not _survey_check(store_checked.ok, str(store_checked)): return
		Store._normalize_state(state)
		if not _survey_check(state.features[key].survey_operator.person_id is int and state.features[key].survey_plan.cells[0] is int): return
		var after: PackedByteArray = var_to_bytes(data.site)
		var bad: Dictionary = feature.duplicate(true)
		bad.survey_operator.site_id = "foreign"
		var rejected: Dictionary = Runtime.validate_feature_layout(data, bad)
		if not _survey_check(not rejected.ok and var_to_bytes(data.site) == after): return
		bad = feature.duplicate(true)
		bad.survey_plan.cells[0] = marks[0]
		rejected = Runtime.validate_feature_layout(data, bad)
		if not _survey_check(not rejected.ok): return
		bad = feature.duplicate(true)
		bad.work = 4.0
		rejected = Runtime.validate_feature_layout(data, bad)
		if not _survey_check(not rejected.ok): return
		var resize: Dictionary = Runtime.request_resize(data, key, marks, Callable(), 1)
		if not _survey_check(not resize.ok and var_to_bytes(data.site) == after): return
		var cancelled: Dictionary = Runtime.cancel_feature(data, key, Callable(), 1)
		if not _survey_check(cancelled.ok and int(data.site.inventory.wood) == stock and not data.site.features.has(key)): return
		built = Runtime.request_build(data, "survey_stakes", marks, Callable(), fixture.options)
		if not _survey_check(built.ok): return
		key = str(built.feature)
		var constructed: Variant = _survey_complete_key(data, key)
		if _survey_failed: return
		if not _survey_check(constructed is bool and bool(constructed), "Construction helper must explicitly return success"): return
		feature = data.site.features[key]
		if not _survey_check(feature.stage == "complete"): return
		var completed_stock: int = int(data.site.inventory.wood)
		var demolished: Dictionary = Runtime.cancel_feature(data, key, Callable(), 1)
		if not _survey_check(demolished.ok and not data.site.features.has(key) and int(data.site.inventory.wood) == completed_stock): return
	var missing_asset := {"file": "survey_stakes_missing_contract_fixture.png", "sprites": {}}
	var missing: bool = Runtime._survey_stakes_asset_readable(missing_asset)
	if not _survey_check(not missing, "Manifest membership cannot make an unreadable PNG available"): return
	var stray: Dictionary = {"kind": "house", "survey_operator": {"site_id": str(data.site.id), "person_id": 1}}
	var stray_check: Dictionary = Runtime.validate_survey_stakes_storage(data, stray)
	if not _survey_check(not stray_check.ok): return
	presenter.free()
	var completed: Variant = await _natural_public_caller_and_save()
	if _survey_failed: return
	if not _survey_check(completed is bool and bool(completed), "Cold caller must explicitly return success"): return
	print("SURVEY_STAKES_CONTRACT_PASS: four directions, real plan, 2 wood/120 seconds, strict JSON ids, original cancel/remove, per-cell art, actual request_survey_plan; engine evidence scoped to this test")
	quit(0)

func _natural_public_caller_and_save() -> bool:
	var data: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345)
	Env.initialize(data, "survey_natural")
	var items: Dictionary = Runtime.initialize_item_storage(data.site)
	if not _survey_check(items.ok): return false
	data.site.inventory = {"wood": 100, "stone": 100, "tools": 4}
	var lab: TerrainLab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.site_controller._auto_save_blocked = true
	lab.bind_terrain(data)
	lab.character.faction_id = 1
	var placed: bool = lab.character.place(data.spawn_cell, true)
	if not _survey_check(placed): return false
	var identity: int = int(lab.controlled_person_id())
	lab.character.technology = FamilyTech.learned_candidate({}, "F09")
	var selected: Dictionary = {}
	var marks: Array[int] = []
	for index: int in range(data.size.x * data.size.y):
		var anchor: Vector2i = data.cell_from_index(index)
		if not data.contains(anchor + Vector2i(1, -1)): continue
		var original: Dictionary = Runtime.building_cells(data, "house", anchor, Vector2i(2, 2), {"layout_version": 1, "variant": "small", "quarter": 0, "owner_faction": 1})
		if not original.ok: continue
		marks.assign([data.index(anchor + Vector2i(0, -1)), data.index(anchor + Vector2i(1, -1))])
		var plan := {"kind": "house", "cells": original.cells, "options": original.options}
		var preview: Dictionary = Runtime.request_survey_plan(data, identity, identity, marks, plan, lab.site_controller.reserves_cell, true)
		if not preview.ok or preview.get("cost") != {"wood": 2}: continue
		var station_options := {"layout_version": 1, "quarter": 0, "owner_faction": 1,
			"survey_plan": plan, "survey_operator": {"site_id": str(data.site.id), "person_id": identity}}
		var station_preview: Dictionary = Runtime.preview_build(data, "survey_stakes", marks, lab.site_controller.reserves_cell, station_options)
		if not station_preview.ok: continue
		var station: Vector2i = data.cell_from_index(int(station_preview.entrance))
		if not data.is_walkable(station) or lab.site_controller.reserves_cell(station): continue
		selected = plan
		break
	if not _survey_check(not selected.is_empty(), "Pure natural-source scan must find a valid original public survey plan"): return false
	var safe_cell: Vector2i = lab.character.terrain_cell
	var probe_options := {"layout_version": 1, "quarter": 0, "owner_faction": 1,
		"survey_plan": selected.duplicate(true), "survey_operator": {"site_id": str(data.site.id), "person_id": identity}}
	var original_preview: Dictionary = Runtime.preview_build(data, "survey_stakes", marks, lab.site_controller.reserves_cell, probe_options)
	if not _survey_check(original_preview.ok, str(original_preview)): return false
	var old_station: int = int(original_preview.entrance)
	if not _survey_check(selected.cells.has(old_station), "Original south entrance lies inside the surveyed house footprint"): return false
	var probe_placed: bool = lab.character.place(data.cell_from_index(old_station), true)
	if not _survey_check(probe_placed): return false
	var occupied_before: PackedByteArray = var_to_bytes(data.site)
	var occupied: Dictionary = Runtime.request_survey_plan(data, identity, identity, marks, selected, lab.site_controller.reserves_cell, true)
	if not _survey_check(not occupied.ok and str(occupied.get("code", "")) == "OCCUPIED"
		and var_to_bytes(data.site) == occupied_before, "A real Actor inside the original plan remains a genuine OCCUPIED failure: " + str(occupied)): return false
	var returned: bool = lab.character.place(safe_cell, true)
	if not _survey_check(returned): return false
	var before: PackedByteArray = var_to_bytes(data.site)
	lab.character.technology = {}
	var unlearned: Dictionary = Runtime.request_survey_plan(data, identity, identity, marks, selected, lab.site_controller.reserves_cell)
	if not _survey_check(not unlearned.ok and unlearned.code == "NO_TECHNOLOGY" and var_to_bytes(data.site) == before): return false
	lab.character.technology = FamilyTech.learned_candidate({}, "F09")
	var unauthorized: Dictionary = Runtime.request_survey_plan(data, identity + 10000, identity, marks, selected)
	if not _survey_check(not unauthorized.ok and unauthorized.code == "NO_AUTHORITY" and var_to_bytes(data.site) == before): return false
	var built: Dictionary = Runtime.request_survey_plan(data, identity, identity, marks, selected, lab.site_controller.reserves_cell)
	if not _survey_check(built.ok, str(built)): return false
	var key: String = str(built.feature)
	# A detached uncaptured scene must still fail the original unique-location guard.
	var unrecorded: Dictionary = data.site.duplicate(true)
	unrecorded.actors = {}
	var missing_holder: Dictionary = Store._validate_state(data, unrecorded)
	if not _survey_check(not missing_holder.ok and str(missing_holder.get("code", "")) == "CORRUPT_SAVE"
		and str(missing_holder.get("message", "")).contains("裝備沒有唯一實際位置"), str(missing_holder)): return false
	var original_holders := {}
	for actor: TerrainTestCharacter in lab.combat_actors: original_holders[int(actor.person_id)] = actor.item_state.duplicate(true)
	var original_records: Dictionary = data.site.item_records.duplicate(true)
	var saved: Dictionary = lab.site_controller.save_to(SURVEY_SAVE)
	if not _survey_check(saved.ok, str(saved)): return false
	var loaded: Dictionary = lab.site_controller.load_from(SURVEY_SAVE)
	if not _survey_check(loaded.ok, str(loaded)): return false
	var captured_check: Dictionary = Store._validate_state(lab.terrain, lab.terrain.site.duplicate(true))
	if not _survey_check(captured_check.ok, str(captured_check)): return false
	if not _survey_check(lab.terrain.site.item_records == original_records, "Controller capture/load preserves the same actual item records"): return false
	for actor: TerrainTestCharacter in lab.combat_actors:
		if not _survey_check(original_holders.get(int(actor.person_id)) == actor.item_state, "Same original person keeps the exact unique physical holder through cold bind"): return false
	var cold: Dictionary = lab.terrain.site.features[key]
	if not _survey_check(cold.survey_operator.person_id is int and int(cold.survey_operator.person_id) == identity): return false
	if not _survey_check(cold.survey_plan.cells == data.site.features[key].survey_plan.cells): return false
	lab.queue_free()
	await process_frame
	return true

var _survey_failed := false

func _survey_check(condition: bool, message: String = "Survey contract failed") -> bool:
	if _survey_failed: return false
	if condition: return true
	_survey_failed = true
	push_error(message)
	quit(1)
	return false

func _survey_fail_probe_inner() -> bool:
	if not _survey_check(false, "SURVEY_FAIL_FAST_EXPECTED"): return false
	print("SURVEY_FAIL_FAST_UNREACHABLE")
	return true

func _survey_fail_probe_outer() -> bool:
	var inner_ok: bool = _survey_fail_probe_inner()
	if not inner_ok: return false
	print("SURVEY_FAIL_FAST_UNREACHABLE")
	return true

func _survey_complete_key(data: TerrainData, key: String) -> bool:
	var feature: Dictionary = data.site.features[key]
	var entrance: int = int(feature.get("pending_build", feature).get("entrance", feature.entrance))
	Runtime.assign_task(data, Runtime.ok("", {"target": "feature:" + key, "action": "construct", "cell": entrance}))
	data.site.worker.cell = entrance
	data.site.worker.mode = "work"
	Runtime.advance(data, float(feature.get("pending_build", feature).work) + 1.0, true, false, Callable(), Callable(), Callable(), Runtime.CARRY_CAPACITY, Runtime.CARRY_CAPACITY, 1.0, 1)
	if not _survey_check(str(feature.stage) == "complete" and not feature.has("pending_build"), str(feature)): return false
	data.site.worker.cell = data.index(Vector2i(10, 9))
	data.site.worker.mode = "idle"
	return true

func _survey_building_fixture() -> TerrainData:
	var data: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345)
	Env.initialize(data, "workflow")
	var initialized: Dictionary = Runtime.initialize_item_storage(data.site)
	if not _survey_check(initialized.ok, str(initialized)): return null
	for y: int in range(8, 52):
		for x: int in range(8, 52):
			var index: int = data.index(Vector2i(x, y))
			data.height_levels[index] = 0
			data.flags[index] = TerrainData.Flag.WALKABLE
			data.ramp_edges[index] = 0
			data.surface_types[index] = TerrainData.Surface.GRASS
			data.groundwater[index] = 80
			data.foundation[index] = 80
			data.fertility[index] = 60
			data.drainage[index] = 70
			data.moisture[index] = 70
			for key: String in data.resources_at.get(index, []): Env.change(data, key, {"cleared": true, "remaining": 0})
	data.site.depot_cell = data.index(Vector2i(9, 9))
	data.site.worker.cell = data.index(Vector2i(10, 9))
	data.site.manual.cell = data.index(Vector2i(10, 10))
	for item: String in Env.ITEM_NAMES: data.site.inventory[item] = 10000
	data.site.capacity = 1000000
	Env.rebuild_indexes(data)
	Runtime.rebuild_terrain_edges(data)
	return data
