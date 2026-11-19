extends "res://scripts/tests/site_building_ui_test.gd"
## Formal renderer and original actor acceptance. Construction is completed by
## the existing work owner; every observed stair/gate traversal uses actor.step.

const OUTPUT := "res://output/site_building_implementation_20261003/visual/"
var _visual_lab: TerrainLab
var _captures: Array[Dictionary] = []

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 170000
	_run.call_deferred()

func _capture(label: String, bounds: Rect2, details: Dictionary = {}) -> void:
	var actor := _visual_lab.character
	actor._process(0.0)
	_visual_lab.site_controller.view.refresh()
	_visual_lab.camera.position = bounds.get_center()
	_visual_lab.camera.zoom = Vector2.ONE * minf(2.0, minf(1100.0 / maxf(300.0, bounds.size.x + 180.0), 740.0 / maxf(240.0, bounds.size.y + 180.0)))
	_visual_lab.camera.reset_smoothing()
	for _frame: int in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	assert(not picture.is_empty() and picture.save_png(OUTPUT + label + ".png") == OK)
	details.merge({"file": label + ".png", "person_id": actor.person_id, "cell": [actor.terrain_cell.x, actor.terrain_cell.y],
		"ground_position": [actor.position.x, actor.position.y], "surface_offset": [0, _visual_lab.terrain.surface_visual_offset_at(actor.position).y]})
	_captures.append(details)
	assert(Time.get_ticks_msec() < deadline)

func _step(actor: TerrainTestCharacter, destination: Vector2i) -> void:
	var old_cell := actor.terrain_cell
	assert(actor.data.can_step(old_cell, destination))
	assert(actor.step(destination - old_cell), "Original actor refused a formal edge %s -> %s" % [old_cell, destination])
	for _tick: int in range(100):
		actor.advance_combat(0.025, false, 0.0)
		if not actor.is_moving(): break
	assert(not actor.is_moving() and actor.terrain_cell == destination)
	assert(actor.position.is_equal_approx((Vector2(destination) + Vector2.ONE * 0.5) * 64.0))
	actor._process(0.0)

func _walk(actor: TerrainTestCharacter, destination: Vector2i) -> void:
	var route := actor.data.path_between(actor.terrain_cell, destination)
	assert(not route.is_empty() or actor.terrain_cell == destination)
	for cell: Vector2i in route: _step(actor, cell)

func _reset() -> TerrainData:
	var data := _building_fixture()
	_visual_lab.bind_terrain(data)
	_visual_lab.site_controller._auto_save_blocked = true
	_visual_lab.site_controller.release_worker()
	assert(_visual_lab.character.place(Vector2i(10, 10), true))
	assert(_visual_lab.npc.place(Vector2i(10, 9), true))
	_visual_lab.get_node("SiteUI").hide()
	_visual_lab.site_controller.hide_tool_windows()
	return data

func _construction_window() -> void:
	_reset()
	var controller: SiteController = _visual_lab.site_controller
	_visual_lab.get_node("SiteUI").show()
	_choose(controller, "house", Vector2i(24, 24), Vector2i.ONE)
	controller.building_variant.select(2)
	controller.building_variant.item_selected.emit(2)
	controller.building_direction.select(1)
	controller.building_direction.item_selected.emit(1)
	controller.open_window("construction")
	var window: Window = controller.formal_windows.construction
	var scroll := controller._formal_columns.construction.get_parent().get_parent() as ScrollContainer
	assert(scroll != null)
	for section: String in ["top", "actions"]:
		scroll.scroll_vertical = 0 if section == "top" else 10000
		for _frame: int in range(3): await process_frame
		await RenderingServer.frame_post_draw
		var picture := window.get_texture().get_image()
		var file := "construction_ui_" + section + ".png"
		assert(not picture.is_empty() and picture.save_png(OUTPUT + file) == OK)
		_captures.append({"file": file, "case": "actual formal construction window"})
	controller._cancel_building_draft()
	controller.hide_tool_windows()
	_visual_lab.get_node("SiteUI").hide()

func _stairs(material: String, quarter: int) -> void:
	var data := _reset()
	var view: SiteResourceView = _visual_lab.site_controller.view
	var options := {"layout_version": 1, "quarter": quarter, "material": material, "owner_faction": 1}
	var placement := Runtime.building_cells(data, "wall_stairs", Vector2i(24, 24), Vector2i.ONE, options)
	assert(placement.ok)
	var draft: Dictionary = options.duplicate()
	draft.merge({"kind": "wall_stairs", "cells": placement.cells, "level": 0, "stage": "planned", "solid": false, "entrance": -1})
	var expected := Runtime.feature_geometry(data, draft)
	var upper: Vector2i = expected.stair_upper.cell
	var lower: Vector2i = expected.stair_lower.cell
	var axis := upper - lower
	var across := Vector2i(-axis.y, axis.x)
	var wall_cells: Array[int] = []
	for depth: int in range(3):
		for side: int in range(-1, 2): wall_cells.append(data.index(Vector2i(expected.external_upper.cell) + axis * depth + across * side))
	var wall_result := Runtime.request_build(data, "stone_wall" if material == "stone" else "palisade", wall_cells, Callable(), options)
	assert(wall_result.ok, str(wall_result))
	_complete_key(data, str(wall_result.feature))
	var key := _formal_feature(data, "wall_stairs", placement.bounds.position, Vector2i.ONE, options)
	var feature: Dictionary = data.site.features[key]
	var actor := _visual_lab.character
	assert(actor.place(expected.external_lower.cell, true))
	var draws := view.building_part_draws(feature)
	var feet_checked := false
	for part: Dictionary in draws:
		if not part.has("toe"): continue
		assert(Vector2(part.toe).is_equal_approx(actor.position))
		assert(Vector2(part.high_exit).is_equal_approx((Vector2(upper) + Vector2.ONE * 0.5) * 64.0 + data.surface_visual_offset(upper)))
		feet_checked = true
	assert(feet_checked)
	var bounds := view.building_art_bounds(feature).merge(view.building_art_bounds(data.site.features[str(wall_result.feature)]))
	var stem := "stairs_%s_%d" % [material, quarter]
	await _capture(stem + "_ground", bounds, {"case": "real actor before ascent"})
	_step(actor, lower)
	assert(data.surface_visual_offset(actor.terrain_cell).y == -48.0)
	await _capture(stem + "_lower", bounds, {"case": "real actor lower stair"})
	_step(actor, upper)
	assert(data.surface_visual_offset(actor.terrain_cell).y == -96.0)
	await _capture(stem + "_upper", bounds, {"case": "real actor upper landing"})
	_step(actor, expected.external_upper.cell)
	_step(actor, Vector2i(expected.external_upper.cell) + axis)
	await _capture(stem + "_wall", bounds, {"case": "real actor reached wall through connected stairs"})
	var lower_id := "c:%d" % data.index(lower)
	var upper_id := "c:%d" % data.index(upper)
	var maximum := Runtime.STONE_PART_HP if material == "stone" else Runtime.WOOD_PART_HP
	assert(Runtime.damage_structure_part(data, key, lower_id, maximum * 0.4).ok)
	await _capture(stem + "_damaged", bounds, {"case": "lower part damaged by runtime owner"})
	assert(Runtime.damage_structure_part(data, key, lower_id, maximum).ok)
	assert(data.effective_height(lower) == 0 and data.effective_height(upper) == 2)
	var upper_present := false
	for part: Dictionary in view.building_part_draws(feature):
		if str(part.part_id) == upper_id and part.has("walk_foot"): upper_present = true
	assert(upper_present, "Destroying lower stairs must preserve surviving upper landing")
	await _capture(stem + "_lower_destroyed", bounds, {"case": "lower destroyed, original upper landing retained"})
	assert(Runtime.damage_structure_part(data, key, upper_id, maximum).ok)
	await _capture(stem + "_destroyed", bounds, {"case": "both original stair parts destroyed"})
	if quarter == 0:
		var wall_part := "c:%d" % wall_cells[0]
		assert(Runtime.damage_structure_part(data, str(wall_result.feature), wall_part, maximum * 0.4).ok)
		await _capture("wall_" + material + "_damaged", bounds, {"case": "one wall cell damaged, other deck cells retained"})
		assert(Runtime.damage_structure_part(data, str(wall_result.feature), wall_part, maximum).ok)
		for part: Dictionary in view.building_part_draws(data.site.features[str(wall_result.feature)]):
			assert(str(part.part_id) != wall_part or str(part.component) != "floor")
		await _capture("wall_" + material + "_destroyed", bounds, {"case": "destroyed wall cell has no elevated floor"})

func _gate(material: String, quarter: int) -> void:
	var data := _reset()
	var controller: SiteController = _visual_lab.site_controller
	var view: SiteResourceView = controller.view
	var key := _formal_feature(data, "gate", Vector2i(24, 24), Vector2i.ONE, {"material": material, "quarter": quarter})
	var feature: Dictionary = data.site.features[key]
	var geometry := Runtime.feature_geometry(data, feature)
	var actor := _visual_lab.character
	var operator_cell := data.cell_from_index(int(geometry.operation[0]))
	var leaf_cell := data.cell_from_index(int(geometry.parts["leaf:left"].cells[0]))
	var direction := (leaf_cell - operator_cell) / 2
	var behind := leaf_cell + direction * 2
	assert(actor.place(behind, true))
	_step(actor, behind - direction)
	var bounds := view.building_art_bounds(feature).grow(70)
	var stem := "gate_%s_%d" % [material, quarter]
	await _capture(stem + "_closed_behind", bounds, {"case": "original actor walked behind closed gate"})
	_walk(actor, operator_cell)
	assert(Runtime.request_gate(data, key, true, actor.person_id, controller._building_person_query, controller.reserves_cell).ok)
	_visual_lab._advance_action_time(Runtime.GATE_SECONDS + TerrainLab.ACTION_STEP)
	assert(bool(feature.gate.open))
	_step(actor, operator_cell + direction)
	_step(actor, leaf_cell)
	_step(actor, leaf_cell + direction)
	await _capture(stem + "_open_passed", bounds, {"case": "original actor crossed opened leaf cell"})
	_walk(actor, operator_cell)
	assert(Runtime.request_gate(data, key, false, actor.person_id, controller._building_person_query, controller.reserves_cell).ok)
	_visual_lab._advance_action_time(Runtime.GATE_SECONDS + TerrainLab.ACTION_STEP)
	assert(not bool(feature.gate.open))
	assert(Runtime.damage_structure_part(data, key, "leaf:left", 40.0).ok)
	await _capture(stem + "_damaged_leaf", bounds, {"case": "only left leaf damaged"})
	assert(Runtime.damage_structure_part(data, key, "leaf:left", 100.0).ok)
	geometry = Runtime.feature_geometry(data, feature)
	assert(not geometry.blocked.has(data.index(leaf_cell)) and geometry.blocked.has(int(geometry.parts["leaf:right"].cells[0])))
	await _capture(stem + "_broken_leaf", bounds, {"case": "only destroyed left leaf passes, right remains closed"})
	assert(Runtime.damage_structure_part(data, key, "frame:left", Runtime.STONE_PART_HP).ok)
	await _capture(stem + "_ruined_frame", bounds, {"case": "one original frame destroyed, opposite frame retained"})

func _catalog() -> void:
	var data := _reset()
	var view: SiteResourceView = _visual_lab.site_controller.view
	_visual_lab.character.hide()
	var kinds: Array[String] = ["house", "well", "intake", "farm", "fiber_farm", "fodder_farm", "pasture", "horse_ranch", "saltworks", "kiln", "charcoal", "smelter", "smithy", "tannery", "weaver", "road", "prison", "fighting_position"]
	for kind: String in kinds:
		var variants: Array[String] = []
		variants.assign(["small", "standard", "long", "large"] if kind == "house" else [""])
		for variant: String in variants:
			for quarter: int in range(4):
				if kind == "well" and quarter == 0 or kind == "road" and quarter > 0 or kind in Runtime.FARM_KINDS and quarter > 1: continue
				var options := {"layout_version": 1, "quarter": quarter, "owner_faction": 1}
				if not variant.is_empty(): options.variant = variant
				var spec := Runtime.building_spec(kind, options)
				var placement := Runtime.building_cells(data, kind, Vector2i(24, 24), spec.min_size, options)
				assert(placement.ok, str(placement))
				var draft: Dictionary = spec.options.duplicate()
				draft.merge({"kind": kind, "cells": placement.cells, "stage": "complete", "level": 0, "solid": bool(Runtime.FEATURES[kind].solid), "entrance": data.index(Vector2i(24, 30))})
				view.set_building_preview({"feature": draft, "geometry": Runtime.feature_geometry(data, draft)})
				var key := view.building_art_key(draft)
				assert(not view.building_part_draws(draft).is_empty())
				await _capture("catalog_" + key, view.building_art_bounds(draft), {"case": "formal renderer art catalog only", "asset": key})
	view.set_building_preview({})
	_visual_lab.character.show()

func _run() -> void:
	assert(DisplayServer.get_name() != "headless", "Use the canonical GPU visual verifier")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1440, 960)
	root.content_scale_size = root.size
	_visual_lab = _building_lab(_building_fixture())
	_visual_lab.get_node("SiteUI").hide()
	if _visual_lab.has_node("UI"): _visual_lab.get_node("UI").hide()
	await _construction_window()
	for material: String in ["wood", "stone"]:
		for quarter: int in range(4):
			await _stairs(material, quarter)
			await _gate(material, quarter)
	await _catalog()
	assert(_captures.size() == 176, "All 100 traversal/damage, 74 catalog and 2 construction captures must finish")
	var report := FileAccess.open(OUTPUT + "summary.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"status": "SITE_BUILDING_VISUAL_PASS", "captures": _captures,
		"limits": "Original actor movement and formal rendering only; catalog cards do not establish production or placement legality; no scaled performance claim."}, "\t"))
	report.close()
	print("SITE_BUILDING_VISUAL_PASS ", _captures.size(), " captures; original actor traversals, geometry/feet, directional damaged parts, formal art catalog")
	_visual_lab.free()
	quit()
