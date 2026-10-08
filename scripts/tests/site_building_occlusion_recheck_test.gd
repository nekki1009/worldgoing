extends "res://scripts/tests/site_building_visual_test.gd"
## Narrow original GPU capture only. No artwork, renderer or person is replaced.
var occlusion_output: String = ""
var occlusion_captures: Array[Dictionary] = []
var occlusion_edges: Array[Dictionary] = []
var occlusion_sources: Dictionary = {}
var occlusion_finished: bool = false
var occlusion_actor: TerrainTestCharacter
var occlusion_actor_id: int = -1

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 210000
	_launch_occlusion.call_deferred()

func _launch_occlusion() -> void:
	await _run()
	if not occlusion_finished:
		push_error("SITE_BUILDING_OCCLUSION_RECHECK_FAILED: incomplete capture; count=%d" % occlusion_captures.size())
		quit(1)

func _new_original_scene() -> TerrainData:
	var data: TerrainData = _building_fixture()
	var scene: PackedScene = load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	assert(scene != null)
	_visual_lab = scene.instantiate() as TerrainLab
	assert(_visual_lab != null)
	_visual_lab.restore_only = true
	_visual_lab.npc = TerrainTestNPC.new() # Existing construction fixture's original worker type.
	_visual_lab.pause_when_unfocused = false
	root.add_child(_visual_lab)
	assert(_visual_lab.terrain == null)
	_visual_lab.bind_terrain(data)
	_visual_lab.restore_only = false
	_visual_lab.show()
	_visual_lab.set_process(false)
	_visual_lab.set_process_input(false)
	_visual_lab.set_process_unhandled_input(false)
	_visual_lab.character.set_process(false)
	_visual_lab.npc.set_process(false)
	_visual_lab.site_controller._auto_save_blocked = true
	_visual_lab.site_controller.release_worker()
	_visual_lab.character.faction_id = 1
	_visual_lab.npc.faction_id = 1
	assert(_visual_lab.character.place(Vector2i(10, 10), true))
	assert(_visual_lab.npc.place(Vector2i(10, 9), true))
	_visual_lab.get_node("SiteUI").hide()
	_visual_lab.site_controller.hide_tool_windows()
	if _visual_lab.has_node("UI"): _visual_lab.get_node("UI").hide()
	occlusion_actor = _visual_lab.character
	occlusion_actor_id = occlusion_actor.person_id
	occlusion_edges.clear()
	return data

func _walk_original(destination: Vector2i) -> void:
	assert(is_same(occlusion_actor, _visual_lab.character) and occlusion_actor.person_id == occlusion_actor_id)
	assert(occlusion_actor.data.is_walkable(destination), "Capture position must be physically walkable")
	var route: Array[Vector2i] = occlusion_actor.data.path_between(occlusion_actor.terrain_cell, destination)
	assert(not route.is_empty() or occlusion_actor.terrain_cell == destination)
	for cell: Vector2i in route: _recorded_step(cell)

func _recorded_step(destination: Vector2i) -> void:
	var from_cell: Vector2i = occlusion_actor.terrain_cell
	var from_position: Vector2 = occlusion_actor.position
	assert(occlusion_actor.data.can_step(from_cell, destination))
	_step(occlusion_actor, destination) # Original Actor.step and original body completion.
	occlusion_edges.append({"from_cell": _point(Vector2(from_cell)), "to_cell": _point(Vector2(destination)),
		"from_ground_position": _point(from_position), "to_ground_position": _point(occlusion_actor.position),
		"can_step_before": true, "completed_original_step": true})

func _point(value: Vector2) -> Array:
	return [value.x, value.y]

func _rectangle(value: Rect2) -> Array:
	return [value.position.x, value.position.y, value.size.x, value.size.y]

func _transform(value: Transform2D) -> Array:
	return [_point(value.x), _point(value.y), _point(value.origin)]

func _rectangle_corners(value: Rect2, transform: Transform2D) -> Array:
	return [_point(transform * value.position), _point(transform * Vector2(value.end.x, value.position.y)),
		_point(transform * value.end), _point(transform * Vector2(value.position.x, value.end.y))]

func _effective_z(node: CanvasItem) -> int:
	var value: int = node.z_index
	var cursor: CanvasItem = node
	while cursor.z_as_relative and cursor.get_parent() is CanvasItem:
		cursor = cursor.get_parent() as CanvasItem
		value += cursor.z_index
	return value

func _part_metadata(part: Dictionary, view: SiteResourceView, world_to_capture: Transform2D, capture_rect: Rect2) -> Dictionary:
	var art: Dictionary = view._building_asset(str(part.asset_key), str(part.component))
	var source_file: String = str(part.file)
	var source_path: String = SiteResourceView.BUILDING_ART_ROOT.path_join(source_file)
	if not occlusion_sources.has(source_file):
		var texture: Texture2D = part.texture
		var source_image: Image = texture.get_image()
		assert(not source_image.is_empty())
		var source_sha256: String = FileAccess.get_sha256(source_path)
		assert(source_sha256.length() == 64, "The exact original source PNG hash is required")
		if art.has("sha256"): assert(source_sha256 == str(art.sha256).to_lower(), "Source PNG differs from its original manifest")
		occlusion_sources[source_file] = {"file": source_file, "path": source_path, "sha256": source_sha256,
			"texture_size_pixels": [source_image.get_width(), source_image.get_height()],
			"source_alpha_bbox_pixels": _rectangle(Rect2(source_image.get_used_rect()))}
	var region: Rect2 = part.region
	var full_region: Rect2 = art.region
	var draw_rect: Rect2 = part.rect
	var projected: Rect2 = world_to_capture * draw_rect
	assert(region.has_area() and draw_rect.has_area())
	assert(region.position.x + 0.01 >= full_region.position.x and region.position.y + 0.01 >= full_region.position.y)
	assert(region.end.x <= full_region.end.x + 0.01 and region.end.y <= full_region.end.y + 0.01)
	assert(capture_rect.grow(0.1).encloses(projected), "A building target rectangle was clipped by the capture")
	var row: int = int(part.row)
	var foreground: bool = bool(part.foreground)
	var run: Node2D = view.get_node("BuildingGround") as Node2D
	if row >= 0:
		assert(row < view.rows.size())
		run = view.rows[row].get_node("BuildingForeground" if foreground else "BuildingArt") as Node2D
	assert(run != null)
	var scale: Vector2 = draw_rect.size / region.size
	return {"part_id": str(part.part_id), "frame_part_id": str(part.get("frame_part_id", "")),
		"asset_key": str(part.asset_key), "component": str(part.component), "source_file": source_file, "source_path": source_path,
		"source_asset_bbox_pixels": _rectangle(full_region), "part_source_region_pixels": _rectangle(region),
		"crop_fraction_start": _point((region.position - full_region.position) / full_region.size),
		"crop_fraction_end": _point((region.end - full_region.position) / full_region.size),
		"source_to_world_scale": _point(scale), "source_scale_is_uniform": is_equal_approx(scale.x, scale.y),
		"world_rect": _rectangle(draw_rect), "capture_target_bbox_pixels": _rectangle(projected),
		"capture_target_polygon_pixels": _rectangle_corners(draw_rect, world_to_capture),
		"row": row, "foreground": foreground, "draw_node": str(run.get_path()),
		"draw_node_z_index": run.z_index, "draw_node_z_as_relative": run.z_as_relative,
		"effective_z_index": _effective_z(run), "state": str(part.get("state", "")),
		"frame_state": str(part.get("frame_state", "")), "color": Color(part.color).to_html(true),
		"source_calibration": art.get("source_calibration", {}).duplicate(true),
		"door_clear_height_source_pixels": null, "door_clear_height_world_pixels": null, "door_clear_height_capture_pixels": null}

func _capture_original(label: String, feature_key: String, bounds: Rect2, details: Dictionary) -> void:
	var data: TerrainData = _visual_lab.terrain
	var feature: Dictionary = data.site.features[feature_key]
	var actor: TerrainTestCharacter = occlusion_actor
	var view: SiteResourceView = _visual_lab.site_controller.view
	assert(_visual_lab.is_visible_in_tree() and actor.is_visible_in_tree() and view.is_visible_in_tree(), "The original restore fixture must be visible for GPU acceptance")
	assert(is_same(actor, _visual_lab.character) and actor.person_id == occlusion_actor_id and not actor.is_moving())
	assert(data.is_walkable(actor.terrain_cell))
	actor._process(0.0)
	view.refresh()
	_visual_lab.camera.position = bounds.get_center()
	_visual_lab.camera.zoom = Vector2.ONE * minf(2.0, minf(1100.0 / maxf(300.0, bounds.size.x + 180.0), 740.0 / maxf(240.0, bounds.size.y + 180.0)))
	_visual_lab.camera.reset_smoothing()
	for frame: int in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	assert(not picture.is_empty())
	var capture_rect: Rect2 = Rect2(Vector2.ZERO, Vector2(picture.get_width(), picture.get_height()))
	var viewport_final: Transform2D = root.get_final_transform()
	var world_to_capture: Transform2D = viewport_final * view.get_global_transform_with_canvas()
	var sprite: Sprite2D = actor.player_sprite
	assert(sprite != null and sprite.texture != null and actor.editor != null)
	var actor_image: Image = sprite.texture.get_image()
	var used: Rect2i = actor_image.get_used_rect()
	assert(used.has_area())
	var sprite_rect: Rect2 = sprite.get_rect()
	var used_in_sprite: Rect2 = Rect2(Vector2(used.position) + sprite_rect.position, Vector2(used.size))
	var sprite_to_capture: Transform2D = viewport_final * sprite.get_global_transform_with_canvas()
	var used_in_capture: Rect2 = sprite_to_capture * used_in_sprite
	assert(capture_rect.grow(0.1).encloses(used_in_capture), "The original actor silhouette was clipped by the capture")
	var surface: Vector2 = data.surface_visual_offset_at(actor.position)
	var foot_source: Vector2 = Vector2(actor_image.get_width(), actor_image.get_height()) * 0.5 + actor.editor.get_map_ground_offset_pixels()
	var foot_in_sprite: Vector2 = foot_source + sprite_rect.position
	var foot_capture: Vector2 = sprite_to_capture * foot_in_sprite
	var visual_offset: Vector2 = actor._attack_offset + actor._stance_offset
	var expected_foot_capture: Vector2 = world_to_capture * (actor.position + surface + visual_offset)
	assert(foot_capture.distance_to(expected_foot_capture) < 0.05, "Original source foot anchor and actual projected ground contact diverged")
	var parts: Array[Dictionary] = []
	for part: Dictionary in view.building_part_draws(feature): parts.append(_part_metadata(part, view, world_to_capture, capture_rect))
	assert(not parts.is_empty())
	assert(picture.save_png(occlusion_output.path_join(label + ".png")) == OK)
	details.merge({"file": label + ".png", "png_sha256": FileAccess.get_sha256(occlusion_output.path_join(label + ".png")),
		"feature_id": feature_key, "kind": str(feature.kind), "quarter": int(feature.quarter),
		"building_grade": Runtime.building_grade(feature), "feature_parts": feature.parts.duplicate(true),
		"physical_feature_bounds_cells": _rectangle(Rect2(Runtime._cell_bounds(data, feature.cells))),
		"gate": feature.get("gate", {}).duplicate(true), "person_id": actor.person_id,
		"actor_instance_id": actor.get_instance_id(), "actor_node": str(actor.get_path()),
		"cell": _point(Vector2(actor.terrain_cell)), "ground_position": _point(actor.position),
		"surface_offset": _point(surface), "surface_foot_world": _point(actor.position + surface),
		"surface_foot_capture_pixels": _point(world_to_capture * (actor.position + surface)),
		"actor_visual_offset_world": _point(visual_offset), "actor_row": int(actor.position.y / 64.0),
		"actor_z_index": actor.z_index, "actor_effective_z_index": _effective_z(actor), "actor_facing": _point(Vector2(actor.facing)),
		"physical_walkable": true, "actual_original_edges_since_previous_capture": occlusion_edges.duplicate(true),
		"fixed_camera_bounds_world": _rectangle(bounds), "camera_position": _point(_visual_lab.camera.position),
		"camera_zoom": _point(_visual_lab.camera.zoom), "capture_size_pixels": [picture.get_width(), picture.get_height()],
		"viewport_final_transform": _transform(viewport_final), "world_to_capture_transform": _transform(world_to_capture),
		"actor_sprite": {"texture_size_pixels": [actor_image.get_width(), actor_image.get_height()],
			"source_alpha_bbox_pixels": _rectangle(Rect2(used)), "texture_origin_in_sprite": _point(sprite_rect.position),
			"sprite_scale": _point(sprite.scale), "sprite_to_capture_transform": _transform(sprite_to_capture),
			"source_alpha_capture_bbox_pixels": _rectangle(used_in_capture),
			"source_alpha_capture_polygon_pixels": _rectangle_corners(used_in_sprite, sprite_to_capture),
			"foot_source_pixels": _point(foot_source), "foot_capture_pixels": _point(foot_capture),
			"expected_foot_capture_pixels": _point(expected_foot_capture), "foot_projection_error_pixels": foot_capture.distance_to(expected_foot_capture),
			"bounds_basis": "Original actor rendered alpha includes equipment and all sprite/ancestor/camera/viewport transforms; it is not anatomical height or the visible remainder after building occlusion."},
		"building_draws": parts, "manual_appearance_review": "PENDING",
		"occlusion_basis": "Physical gate-normal sides and painter rows are separately recorded. A head above a frame can remain visible; these captures do not assert full-person hiding."}, true)
	occlusion_captures.append(details)
	occlusion_edges.clear()
	assert(Time.get_ticks_msec() < deadline)

func _gate_positions(data: TerrainData, feature: Dictionary) -> Dictionary:
	var geometry: Dictionary = Runtime.feature_geometry(data, feature)
	var operation: Vector2i = data.cell_from_index(int(geometry.operation[0]))
	var leaf: Vector2i = data.cell_from_index(int(geometry.parts["leaf:left"].cells[0]))
	var difference: Vector2i = leaf - operation
	assert(absi(difference.x) + absi(difference.y) == 2)
	var direction: Vector2i = Vector2i(difference.x / 2, difference.y / 2)
	var front: Vector2i = operation + direction
	var behind: Vector2i = leaf + direction
	assert(data.is_walkable(operation) and data.is_walkable(front) and data.is_walkable(behind))
	return {"operation": operation, "leaf": leaf, "direction": direction, "front": front, "behind": behind, "far_behind": leaf + direction * 2}

func _gate_details(positions: Dictionary, side: String, state: String) -> Dictionary:
	return {"case": "q1 %s gate / %s physical gate-normal side" % [state, side], "gate_state": state, "physical_side": side,
		"physical_side_basis": "front=original operation+normal; behind=original left leaf+normal. q1 differs in X while ground Y and Actor painter row stay equal.",
		"operation_cell": _point(Vector2(positions.operation)), "leaf_cell": _point(Vector2(positions.leaf)),
		"gate_normal_cells": _point(Vector2(positions.direction)), "front_cell": _point(Vector2(positions.front)), "behind_cell": _point(Vector2(positions.behind))}

func _gate_operation(key: String, positions: Dictionary, want_open: bool) -> void:
	_walk_original(positions.operation)
	var controller: SiteController = _visual_lab.site_controller
	assert(Runtime.request_gate(_visual_lab.terrain, key, want_open, occlusion_actor.person_id, controller._building_person_query, controller.reserves_cell).ok)
	_visual_lab._advance_action_time(Runtime.GATE_SECONDS + TerrainLab.ACTION_STEP)
	var feature: Dictionary = _visual_lab.terrain.site.features[key]
	assert(bool(feature.gate.open) == want_open and str(feature.gate.pending).is_empty())

func _surviving_half(view: SiteResourceView, feature: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for part: Dictionary in view.building_part_draws(feature):
		if str(part.part_id) in ["leaf:right", "frame:right"]:
			result[str(part.part_id) + ":" + str(part.component)] = [part.rect, part.region, part.file]
	return result

func _rubble_case(key: String, positions: Dictionary, bounds: Rect2, intact_half: Dictionary, stem: String, broken_capture: bool, whole_capture: bool = false) -> void:
	var data: TerrainData = _visual_lab.terrain
	var feature: Dictionary = data.site.features[key]
	assert(not bool(feature.gate.open))
	assert(Runtime.damage_structure_part(data, key, "leaf:left", Runtime.WOOD_PART_HP).ok)
	var geometry: Dictionary = Runtime.feature_geometry(data, feature)
	assert(not geometry.blocked.has(data.index(positions.leaf)) and geometry.blocked.has(int(geometry.parts["leaf:right"].cells[0])))
	_walk_original(positions.front)
	_recorded_step(positions.leaf)
	assert(_surviving_half(_visual_lab.site_controller.view, feature) == intact_half, "Destroying one leaf displaced the surviving original half")
	if broken_capture:
		await _capture_original(stem + "_broken_leaf", key, bounds, {"case": "original left leaf destroyed; Actor stepped into its actual newly walkable cell; opposite leaf/frame retained"})
	assert(Runtime.damage_structure_part(data, key, "frame:left", float(geometry.parts["frame:left"].max_hp)).ok)
	assert(_surviving_half(_visual_lab.site_controller.view, feature) == intact_half, "Destroying one frame displaced the surviving original half")
	var left: Rect2 = Rect2()
	var right: Rect2 = Rect2()
	for part: Dictionary in _visual_lab.site_controller.view.building_part_draws(feature):
		if str(part.part_id) == "leaf:left": left = part.rect
		elif str(part.part_id) == "leaf:right": right = part.rect
	assert(left.has_area() and right.has_area())
	var seam_x: float = minf(left.end.x, right.end.x)
	var gap: float = right.position.x - left.end.x if left.position.x < right.position.x else left.position.x - right.end.x
	assert(absf(gap) < 0.01, "Rubble and retained frame acquired a geometric split gap")
	await _capture_original(stem + "_partial_frame_destroyed", key, bounds, {"case": "only original left frame destroyed; opposite frame and its own top remain; original half-mask is intentional partial-part rendering",
		"frame_damage_scope": "left only", "rubble_split_x_world": seam_x, "split_gap_world_pixels": gap, "straight_crop_appearance_review": "PENDING"})
	if whole_capture:
		geometry = Runtime.feature_geometry(data, feature)
		assert(Runtime.damage_structure_part(data, key, "frame:right", float(geometry.parts["frame:right"].max_hp)).ok)
		var complete_rubble: Array[Dictionary] = _visual_lab.site_controller.view.building_part_draws(feature)
		assert(complete_rubble.size() == 2)
		var merged_region: Rect2 = Rect2()
		for part: Dictionary in complete_rubble:
			assert(str(part.component) == "ruined_frame" and not bool(part.foreground) and str(part.part_id).begins_with("leaf:"))
			merged_region = merged_region.merge(part.region) if merged_region.has_area() else part.region
		var art: Dictionary = _visual_lab.site_controller.view._building_asset(str(complete_rubble[0].asset_key), "ruined_frame")
		assert(merged_region.is_equal_approx(art.region), "Both destroyed frame sides must cover the complete original rubble source bbox")
		assert(float(feature.parts["frame:left"].hp) == 0.0 and float(feature.parts["frame:right"].hp) == 0.0)
		assert(float(feature.parts["leaf:left"].hp) == 0.0 and float(feature.parts["leaf:right"].hp) == 0.0)
		await _capture_original(stem + "_whole_frame_destroyed", key, bounds, {"case": "both original frames destroyed with consequential leaf loss; no surviving top; both UV halves cover the full original rubble source bbox",
			"frame_damage_scope": "both", "no_surviving_topcap": true, "combined_rubble_source_region_pixels": _rectangle(merged_region)})

func _q1_gate(material: String) -> void:
	var data: TerrainData = _new_original_scene()
	var view: SiteResourceView = _visual_lab.site_controller.view
	var key: String = _formal_feature(data, "gate", Vector2i(24, 24), Vector2i.ONE, {"material": material, "quarter": 1})
	var feature: Dictionary = data.site.features[key]
	var positions: Dictionary = _gate_positions(data, feature)
	var bounds: Rect2 = view.building_art_bounds(feature).grow(150.0)
	bounds = bounds.merge(Rect2((Vector2(positions.front) + Vector2.ONE * 0.5) * 64.0 - Vector2(80, 160), Vector2(160, 240)))
	bounds = bounds.merge(Rect2((Vector2(positions.behind) + Vector2.ONE * 0.5) * 64.0 - Vector2(80, 160), Vector2(160, 240)))
	var intact_half: Dictionary = _surviving_half(view, feature)
	var stem: String = "gate_%s_q1" % material
	_walk_original(positions.far_behind)
	_recorded_step(positions.behind)
	await _capture_original(stem + "_closed_behind", key, bounds, _gate_details(positions, "behind", "closed"))
	_walk_original(positions.operation)
	_recorded_step(positions.front)
	await _capture_original(stem + "_closed_front", key, bounds, _gate_details(positions, "front", "closed"))
	_gate_operation(key, positions, true)
	_recorded_step(positions.front)
	await _capture_original(stem + "_open_front", key, bounds, _gate_details(positions, "front", "open"))
	_recorded_step(positions.leaf)
	_recorded_step(positions.behind)
	_recorded_step(positions.far_behind)
	_recorded_step(positions.behind)
	await _capture_original(stem + "_open_behind", key, bounds, _gate_details(positions, "behind", "open"))
	_gate_operation(key, positions, false)
	await _rubble_case(key, positions, bounds, intact_half, stem, material == "wood", true)
	_visual_lab.free()
	await process_frame

func _other_rubble_directions() -> void:
	for quarter: int in [0, 2, 3]:
		var data: TerrainData = _new_original_scene()
		var view: SiteResourceView = _visual_lab.site_controller.view
		var key: String = _formal_feature(data, "gate", Vector2i(24, 24), Vector2i.ONE, {"material": "wood", "quarter": quarter})
		var feature: Dictionary = data.site.features[key]
		var positions: Dictionary = _gate_positions(data, feature)
		var bounds: Rect2 = view.building_art_bounds(feature).grow(150.0)
		await _rubble_case(key, positions, bounds, _surviving_half(view, feature), "gate_wood_q%d" % quarter, false)
		_visual_lab.free()
		await process_frame

func _civil_grade_damage_repair() -> void:
	var data: TerrainData = _new_original_scene()
	var controller: SiteController = _visual_lab.site_controller
	var view: SiteResourceView = controller.view
	var key: String = _formal_feature(data, "house", Vector2i(24, 24), Vector2i.ONE, {"variant": "standard", "quarter": 1})
	var feature: Dictionary = data.site.features[key]
	var original_cells: Array = feature.cells.duplicate()
	var original_entrance: int = int(feature.entrance)
	var original: Array[Dictionary] = view.building_part_draws(feature)
	assert(original.size() == 1 and original[0].color == Color.WHITE)
	assert(Runtime.damage_structure_part(data, key, "body", 40.0).ok)
	controller.feature_key = key
	controller.update_ui()
	_press(_visual_lab, "UpgradeFeatureGrade")
	assert(int(feature.pending_build.target_grade) == 2)
	_complete_key(data, key)
	controller.release_worker()
	controller.update_ui()
	assert(Runtime.building_grade(feature) == 2 and float(feature.parts.body.hp) == 90.0 and Runtime.civil_max_hp(feature) == 150.0)
	assert(feature.cells == original_cells and int(feature.entrance) == original_entrance)
	var damaged: Array[Dictionary] = view.building_part_draws(feature)
	assert(damaged.size() == 1 and damaged[0].color != Color.WHITE and damaged[0].rect == original[0].rect and damaged[0].file == original[0].file)
	_walk_original(data.cell_from_index(original_entrance))
	var bounds: Rect2 = view.building_art_bounds(feature).grow(150.0)
	await _capture_original("civil_q1_grade2_damaged", key, bounds, {"case": "original formal upgrade preserved damage fraction: grade 2 body 90/150; same cells, entrance and PNG"})
	controller.update_ui()
	_press(_visual_lab, "RepairFeaturePart")
	assert(feature.has("repair") and str(feature.repair.part) == "body")
	Runtime.assign_task(data, Runtime.ok("", {"target": "feature:" + key, "action": "repair", "cell": feature.repair.work_cell}))
	data.site.worker.cell = feature.repair.work_cell
	data.site.worker.mode = "work"
	Runtime._feature_work(data, key, float(feature.repair.work), Callable(), Callable(), data.site.worker, data.site.worker.cargo, 20, 1)
	assert(not feature.has("repair") and float(feature.parts.body.hp) == 150.0)
	controller.release_worker()
	var repaired: Array[Dictionary] = view.building_part_draws(feature)
	assert(repaired.size() == 1 and repaired[0].color == Color.WHITE and repaired[0].rect == damaged[0].rect and repaired[0].file == damaged[0].file)
	await _capture_original("civil_q1_grade2_repaired", key, bounds, {"case": "original paid body repair completed: grade 2 body 150/150; same PNG, cells and entrance"})
	assert(Runtime.damage_structure_part(data, key, "body", 150.0).ok)
	var rubble: Array[Dictionary] = view.building_part_draws(feature)
	assert(rubble.size() == feature.cells.size())
	for part: Dictionary in rubble: assert(int(part.row) == -1 and not bool(part.foreground) and part.rect.size.y <= 18.0 and part.file == original[0].file)
	var entered: bool = false
	for index: int in feature.cells:
		var next: Vector2i = data.cell_from_index(index)
		if data.can_step(occlusion_actor.terrain_cell, next):
			_recorded_step(next)
			entered = true
			break
	assert(entered, "Original Actor could not enter the actual collapsed body")
	await _capture_original("civil_q1_grade2_destroyed_ground", key, bounds, {"case": "original body collapsed into ground row; original Actor really stepped into former body"})
	_visual_lab.free()
	await process_frame

func _run() -> void:
	assert(DisplayServer.get_name() != "headless", "Use canonical bounded GPU verification")
	occlusion_output = "res://output/site_building_close_20261004/occlusion_recheck/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(occlusion_output)) == OK)
	root.size = Vector2i(1440, 960)
	root.content_scale_size = root.size
	await _q1_gate("wood")
	await _q1_gate("stone")
	await _other_rubble_directions()
	await _civil_grade_damage_repair()
	assert(occlusion_captures.size() == 19, "All 8 gate-side, 1 broken-leaf, 5 partial-frame, 2 whole-frame and 3 civil captures must complete")
	var report: FileAccess = FileAccess.open(occlusion_output.path_join("manifest.json"), FileAccess.WRITE)
	assert(report != null)
	report.store_string(JSON.stringify({"status": "SITE_BUILDING_OCCLUSION_RECHECK_CAPTURE_PASS", "captures": occlusion_captures,
		"source_assets": occlusion_sources, "manual_appearance_review": "PENDING",
		"scope": "19 original PackedScene/GPU captures with original Actor legal steps, real gate open/close and partial/whole frame damage, real civil upgrade/repair owners, source UV/alpha/foot/painter/camera/PNG coordinates. No renderer or source-art edit; no full-person hiding, all-route, performance or automatic appearance acceptance."}, "\t", true, true))
	report.close()
	TerrainArmy.release_contact_source()
	occlusion_finished = true
	print("SITE_BUILDING_OCCLUSION_RECHECK_CAPTURE_PASS: 19 original GPU captures; manual appearance review pending; source=", occlusion_output)
	quit(0)
