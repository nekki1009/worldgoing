extends SceneTree
## GPU integration proof using the original main scene, Army and VehicleView.
const OUT := "res://output/site_siege_generated_art_20261003/integration/visual"
const MANIFEST := "res://assets/vehicles/siege/v1/siege_art.json"
const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const SiegeMask = preload("res://assets/vehicles/siege/v1/siege_art_mask.gdshader")
const KINDS := ["ram", "ballista", "traction_trebuchet", "counterweight_trebuchet", "siege_ladder", "siege_tower"]
const FACINGS := [Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT]
const DIRECTIONS := ["down", "left", "up", "right"]
const TITLES := ["衝車", "固定重弩", "牽引投石機", "配重投石機", "攻城梯", "攻城塔"]
var deadline: int = 0
var failed: bool = false
var finished: bool = false
var lab: TerrainLab
var team: TerrainArmy
var view: SiteVehicleView
var identity: String = ""
var anchor := Vector2i(24, 22)
var captures: Array[Dictionary] = []
var asset_checks: Array[Dictionary] = []
var completed := {"frames": 0, "paid_build": 0, "ready": 0, "turning": 0, "damage": 0, "flight": 0, "wreck": 0, "gallery": 0}
var _image_cache: Dictionary = {}
var _frame_keys: Dictionary = {}
var sprite_mask_checks: Dictionary = {}
var muzzle_checks: Dictionary = {}

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 120000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not finished and not failed and Time.get_ticks_msec() > deadline:
		_check(false, "120-second GPU integration deadline", {"completed": completed, "captures": captures.size()})
	return false

func _check(condition: bool, message: String, details: Dictionary = {}) -> bool:
	if failed: return false
	if condition: return true
	failed = true
	push_error("SIEGE_GENERATED_ART_FAIL " + message + " " + JSON.stringify(details))
	quit(1)
	return false

func _rect_array(value: Rect2) -> Array:
	return [value.position.x, value.position.y, value.size.x, value.size.y]

func _masked(point: Vector2, exclusions: Array) -> bool:
	for exclusion: Rect2 in exclusions:
		if exclusion.has_point(point): return true
	return false

func _reference_is_excluded(region: Rect2, reference: Rect2, exclusions: Array) -> bool:
	# Split the overlap at every mask boundary; each positive-area tile must be covered.
	var overlap: Rect2 = region.intersection(reference)
	if not overlap.has_area(): return true
	var xs: Array[float] = [overlap.position.x, overlap.end.x]
	var ys: Array[float] = [overlap.position.y, overlap.end.y]
	for exclusion: Rect2 in exclusions:
		var clipped: Rect2 = overlap.intersection(exclusion)
		if not clipped.has_area(): continue
		xs.append(clipped.position.x)
		xs.append(clipped.end.x)
		ys.append(clipped.position.y)
		ys.append(clipped.end.y)
	xs.sort()
	ys.sort()
	for x in range(xs.size() - 1):
		if xs[x + 1] <= xs[x]: continue
		for y in range(ys.size() - 1):
			if ys[y + 1] <= ys[y]: continue
			if not _masked(Vector2((xs[x] + xs[x + 1]) * 0.5, (ys[y] + ys[y + 1]) * 0.5), exclusions): return false
	return true

func _check_frame(kind: String, facing: Vector2i, direction: String) -> bool:
	var frame: Dictionary = view.siege_art_frame(kind, facing)
	if not _check(not frame.is_empty(), "Missing original View frame", {"kind": kind, "direction": direction}): return false
	for key: String in ["texture", "region", "pivot", "scale", "direction", "source", "exclusions", "reference_region", "image_size"]:
		if not _check(frame.has(key), "Frame contract field missing", {"kind": kind, "direction": direction, "field": key}): return false
	if not _check(frame.texture is Texture2D and frame.region is Rect2 and frame.pivot is Vector2 and frame.exclusions is Array and frame.reference_region is Rect2 and frame.image_size is Vector2i, "Frame contract types", {"kind": kind, "direction": direction}): return false
	var texture: Texture2D = frame.texture
	var region: Rect2 = frame.region
	var reference: Rect2 = frame.reference_region
	var exclusions: Array = frame.exclusions
	if not _check(exclusions.size() <= 4, "Shader supports four exclusion rectangles", {"kind": kind, "direction": direction}): return false
	if not _check(str(frame.direction) == direction and is_finite(float(frame.scale)) and float(frame.scale) > 0.0, "Directional frame/scale", {"kind": kind, "direction": direction}): return false
	if not _check(FileAccess.file_exists(str(frame.source)) and region.has_area() and Rect2(Vector2.ZERO, Vector2(texture.get_size())).encloses(region), "Frame region exceeds its own source", {"source": frame.source, "region": _rect_array(region)}): return false
	for exclusion: Variant in exclusions:
		if not _check(exclusion is Rect2 and exclusion.has_area(), "Malformed exclusion rectangle", {"source": frame.source}): return false
	if not _check(_reference_is_excluded(region, reference, exclusions), "Proportion reference overlaps unmasked art", {"kind": kind, "direction": direction, "region": _rect_array(region), "reference": _rect_array(reference)}): return false
	var frame_key: String = str(frame.source) + "/" + JSON.stringify(_rect_array(region))
	if not _check(not _frame_keys.has(frame_key), "Two kind/direction entries alias the same source region", {"kind": kind, "direction": direction, "source": frame.source}): return false
	_frame_keys[frame_key] = true
	var image_value: Image = _image_cache.get(str(frame.source))
	if image_value == null:
		image_value = texture.get_image()
		if not _check(image_value != null and not image_value.is_empty(), "Texture has no readable source image", {"source": frame.source}): return false
		if image_value.is_compressed() and not _check(image_value.decompress() == OK, "Cannot inspect imported texture", {"source": frame.source}): return false
		_image_cache[str(frame.source)] = image_value
	if not _check(image_value.get_size() == frame.image_size and image_value.get_size() == Vector2i(texture.get_size()), "Imported texture dimensions differ from manifest", {"source": frame.source}): return false
	var visible_samples: int = 0
	for y in range(ceili(region.position.y), floori(region.end.y), 4):
		for x in range(ceili(region.position.x), floori(region.end.x), 4):
			if not _masked(Vector2(x + 0.5, y + 0.5), exclusions) and image_value.get_pixel(x, y).a > 0.01: visible_samples += 1
	if not _check(visible_samples > 0, "Mask removes all visible art", {"kind": kind, "direction": direction}): return false
	var mask_rows: Array = []
	for exclusion: Rect2 in exclusions: mask_rows.append(_rect_array(exclusion))
	asset_checks.append({"kind": kind, "direction": direction, "source": frame.source, "region": _rect_array(region),
		"pivot": [frame.pivot.x, frame.pivot.y], "scale": frame.scale, "reference_region": _rect_array(reference),
		"exclusions": mask_rows, "masked_alpha_samples_step4": visible_samples, "reference_fully_excluded": true})
	completed.frames += 1
	return true

func _check_sprite(sprite: Sprite2D, kind: String, facing: Vector2i) -> bool:
	if not _check(sprite != null and sprite.is_visible_in_tree(), "Original View did not publish a visible art Sprite", {"kind": kind}): return false
	var frame: Dictionary = view.siege_art_frame(kind, facing)
	if not _check(not frame.is_empty(), "Sprite lost source frame", {"kind": kind}): return false
	if not _check(sprite.texture == frame.texture and sprite.region_enabled and sprite.region_rect == frame.region and not sprite.centered and sprite.offset == -frame.pivot and sprite.scale.is_equal_approx(Vector2.ONE * float(frame.scale)) and is_zero_approx(sprite.rotation), "Sprite differs from the shared View frame", {"kind": kind, "direction": frame.direction}): return false
	if not _check(str(sprite.get_meta("siege_art_frame", "")) == kind + "/" + str(frame.direction), "Sprite frame metadata", {"kind": kind}): return false
	if not _check(sprite.get_meta("siege_art_exclusions", null) == frame.exclusions, "Sprite mask metadata differs from frame", {"kind": kind}): return false
	if frame.exclusions.is_empty():
		if not _check(sprite.material == null, "Unmasked frame must have no mask material", {"kind": kind}): return false
	else:
		if not _check(sprite.material is ShaderMaterial, "Excluded source requires the shared View shader", {"kind": kind}): return false
		var material: ShaderMaterial = sprite.material as ShaderMaterial
		if not _check(material.shader == SiegeMask, "Sprite bypassed the original exclusion shader", {"kind": kind}): return false
		var image_size := Vector2(frame.image_size)
		for index in range(4):
			var actual: Variant = material.get_shader_parameter("exclude_%d" % index)
			var expected := Vector4.ZERO
			if index < frame.exclusions.size():
				var exclusion: Rect2 = frame.exclusions[index]
				expected = Vector4(exclusion.position.x / image_size.x, exclusion.position.y / image_size.y, exclusion.end.x / image_size.x, exclusion.end.y / image_size.y)
				if not _check(actual is Vector4 and actual.is_equal_approx(expected), "Shader uniform differs from source mask metadata", {"kind": kind, "direction": frame.direction, "uniform": index, "expected": str(expected), "actual": str(actual)}): return false
			elif actual != null:
				# An unset slot uses the shared shader's vec4(0.0) default.
				if not _check(actual is Vector4 and actual.is_equal_approx(Vector4.ZERO), "Unused shader mask slot is active", {"kind": kind, "uniform": index}): return false
	sprite_mask_checks[kind + "/" + str(frame.direction)] = true
	return true

func _check_no_greybox(node: Node) -> bool:
	if node is CanvasItem and (node is Polygon2D or node is Line2D) and (node as CanvasItem).is_visible_in_tree():
		return _check(false, "Generated ballista still renders geometry greybox", {"node": str(node.get_path())})
	for child: Node in node.get_children():
		if not _check_no_greybox(child): return false
	return true

func _check_ballista(vehicle: Dictionary, turning: bool = false) -> bool:
	view.refresh()
	var node: Node2D = view._siege_nodes.get(identity)
	if not _check(node != null and bool(node.get_meta("siege_generated_art", false)) and not bool(node.get_meta("siege_greybox", false)), "Real ballista is not generated-art presentation"): return false
	if not _check_no_greybox(node): return false
	var facing := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
	var body: Sprite2D = node.get_node_or_null("Body") as Sprite2D
	if not _check_sprite(body, "ballista", facing): return false
	var ground := (Vector2(lab.terrain.cell_from_index(int(vehicle.cell))) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	if not _check(node.position.is_equal_approx(ground + lab.terrain.surface_visual_offset_at(ground)) and is_zero_approx(node.rotation), "Generated art moved the real ground pivot"): return false
	if turning:
		var target := Vector2i(int(vehicle.action.facing[0]), int(vehicle.action.facing[1]))
		var next: Sprite2D = node.get_node_or_null("TurnTarget") as Sprite2D
		if not _check_sprite(next, "ballista", target): return false
		if not _check(str(vehicle.action.get("stage", "")) == "rotate" and float(vehicle.action.elapsed) > 0.0 and float(vehicle.action.elapsed) < 3.0, "Turn capture must be a real committed midpoint"): return false
		var blend: float = float(vehicle.action.elapsed) / 3.0
		if not _check(is_equal_approx(body.modulate.a, 1.0 - blend) and is_equal_approx(next.modulate.a, blend) and body.position.is_equal_approx(next.position), "Turn images do not share the original clock and presentation centre", {"elapsed": vehicle.action.elapsed, "body_alpha": body.modulate.a, "target_alpha": next.modulate.a}): return false
	else:
		var frame: Dictionary = view.siege_art_frame("ballista", facing)
		if not _check(str(node.get_meta("siege_art_direction", "")) == str(frame.direction), "Real node directional publication"): return false
		if not _check(frame.has("muzzle") and frame.muzzle is Vector2, "Ballista frame has no calibrated terminal point"): return false
		var screen_muzzle: Vector2 = body.to_global(frame.muzzle + body.offset)
		var expected_muzzle: Vector2 = lab.siege_muzzle(vehicle) * TerrainRenderer.CELL_PIXELS + lab.terrain.surface_visual_offset_at(ground) - Vector2(0.0, 48.0)
		var error_pixels: float = screen_muzzle.distance_to(expected_muzzle)
		if not _check(error_pixels < 0.01, "Art terminal differs from the original shot origin", {"direction": frame.direction, "error_pixels": error_pixels, "actual": str(screen_muzzle), "expected": str(expected_muzzle)}): return false
		muzzle_checks[str(frame.direction)] = {"source": frame.source, "error_pixels": error_pixels, "screen_point": [screen_muzzle.x, screen_muzzle.y]}
	return true

func _check_bolt(flight: Dictionary) -> bool:
	view.refresh()
	var bolt: Sprite2D = view._bolt_nodes.get(str(flight.attack_id)) as Sprite2D
	if not _check(bolt != null and bool(bolt.get_meta("siege_generated_bolt", false)) and bolt.get_parent() == view, "Original flight did not publish generated bolt art"): return false
	if not _check(bolt.texture == view._bolt_texture and bolt.region_enabled and bolt.region_rect == view._bolt_region and bolt.position.is_equal_approx(flight.position) and is_equal_approx(bolt.rotation, (flight.screen_goal - flight.screen_origin).angle()), "Bolt art differs from original flight publication"): return false
	return true

func _tick(seconds: float = 1.0 / 30.0) -> bool:
	if not _check(Time.get_ticks_msec() < deadline, "Tick deadline"): return false
	lab._process(seconds)
	return not failed

func _walk(index: int, goal: Vector2i) -> bool:
	var route: Array[Vector2i] = team._find_local_route(team.cells[index], goal, 256, false, index)
	if not _check(not route.is_empty() or team.cells[index] == goal, "Original worker has no legal route"): return false
	for next: Vector2i in route.slice(1):
		if not _check(team._reserve_combat_step(index, next), "Original worker single-step reservation"): return false
		for _step in range(60):
			if not _tick(): return false
			if team.moving_to[index] == TerrainArmy.INVALID_CELL: break
		if not _check(team.cells[index] == next and team.moving_to[index] == TerrainArmy.INVALID_CELL, "Original worker did not commit adjacent step"): return false
	return true

func _focus(point: Vector2, zoom: float = 1.1) -> void:
	lab.camera.zoom = Vector2.ONE * zoom
	lab.camera.position = point
	lab.camera.reset_smoothing()
	lab.camera.force_update_scroll()

func _capture(name_value: String, details: Dictionary = {}, gallery: bool = false) -> bool:
	if not _check(Time.get_ticks_msec() < deadline, "Capture deadline"): return false
	var records_before: Dictionary = lab.terrain.site.vehicles.duplicate(true)
	var units_before: Array = team.combat_units.duplicate(true)
	var cells_before: Array[Vector2i] = team.cells.duplicate()
	for army: TerrainArmy in lab.combat_armies: army.advance_frame(0.0)
	lab.site_controller.view.refresh()
	view.refresh()
	var formal_node: Node2D = view._siege_nodes.get(identity)
	var environment_visible: bool = lab.site_controller.view.visible
	if gallery:
		if formal_node != null: formal_node.hide()
		# Isolated art gallery: keep resource records and formal occlusion unchanged.
		lab.site_controller.view.hide()
	for _frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	if not _check(picture != null and not picture.is_empty() and picture.save_png(OUT + "/" + name_value + ".png") == OK, "GPU capture failed", {"file": name_value}): return false
	if gallery:
		if formal_node != null: formal_node.show()
		lab.site_controller.view.visible = environment_visible
	if not _check(lab.terrain.site.vehicles == records_before and team.combat_units == units_before and team.cells == cells_before, "Presentation mutated original records or people"): return false
	details.merge({"file": name_value + ".png", "original_people": team.combat_units.size(), "vehicle_id": identity, "anchor": [anchor.x, anchor.y], "gallery_resource_layer_hidden": gallery}, true)
	captures.append(details)
	return true

func _gallery(kind: String, title: String, number: int) -> bool:
	var records_before: Dictionary = lab.terrain.site.vehicles.duplicate(true)
	var gallery := Node2D.new()
	gallery.name = "GeneratedArtGallery_" + kind
	lab.add_child(gallery)
	var offsets: Array[Vector2] = [Vector2(-7, -4), Vector2(6, -4), Vector2(-7, 5), Vector2(6, 5)]
	for quarter in range(4):
		var position_value: Vector2 = (Vector2(anchor) + offsets[quarter] + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
		var sprite: Sprite2D = view.show_pure_preview(kind, FACINGS[quarter], gallery, position_value)
		if not _check_sprite(sprite, kind, FACINGS[quarter]): return false
		var label := Label.new()
		label.text = title + " · " + DIRECTIONS[quarter]
		label.position = position_value + Vector2(-160, 65)
		label.add_theme_font_override("font", lab.site_controller.details.get_theme_font("font"))
		label.add_theme_font_size_override("font_size", 22)
		label.z_index = 200
		gallery.add_child(label)
	var caption := Label.new()
	caption.text = title + " · 核准圖稿接入／原人物比例參考\n六類均沿原 VehicleView 呈現；只有固定重弩已有玩法。其他五類純展示。"
	caption.position = (Vector2(anchor) + Vector2(-10, -9)) * TerrainRenderer.CELL_PIXELS
	caption.add_theme_font_override("font", lab.site_controller.details.get_theme_font("font"))
	caption.add_theme_font_size_override("font_size", 23)
	caption.z_index = 200
	gallery.add_child(caption)
	_focus((Vector2(anchor) + Vector2(0, 0.5)) * TerrainRenderer.CELL_PIXELS, 0.7)
	if not await _capture("%02d_gallery_%s" % [number, kind], {"kind": kind, "directions": DIRECTIONS, "presentation_only": true, "creates_vehicle_records": false}, true): return false
	if not _check(lab.terrain.site.vehicles == records_before and lab.terrain.site.vehicles.size() == 1, "Pure gallery created or changed gameplay assets"): return false
	completed.gallery += 1
	gallery.queue_free()
	await process_frame
	return true

func _run() -> void:
	if not _check(DisplayServer.get_name() != "headless", "GPU viewport required"): return
	if not _check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/terrain_lab/TerrainLab.tscn", "Original main scene required"): return
	if not _check(DirAccess.make_dir_recursive_absolute(OUT) == OK and FileAccess.file_exists(MANIFEST), "Missing output directory or formal art manifest"): return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not _check(manifest is Dictionary and int(manifest.get("schema_version", 0)) == 1, "Art manifest schema"): return
	root.size = Vector2i(1800, 1100)
	root.content_scale_size = root.size
	root.gui_embed_subwindows = true
	var main: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	lab = main.instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	lab.site_controller._auto_save_blocked = true
	# Explicit flat terrain/material/deployment fixtures; gameplay uses original owners.
	var data: TerrainData = Helper.build_flat_map(60, 44)
	data.spawn_cell = Vector2i(4, 4)
	data.site.player_cell = data.index(data.spawn_cell)
	data.site.manual.cell = data.site.player_cell
	data.site.worker.cell = data.index(Vector2i(4, 3))
	data.site.depot_cell = data.index(Vector2i(3, 4))
	data.site.capacity = 1000000
	data.site.inventory = {"wood": 240, "iron": 120, "fiber": 100, "tools": 20, "siege_bolt": 20}
	lab.bind_terrain(data)
	var ui: SiteController = lab.site_controller
	ui._auto_save_blocked = true
	ui.release_worker()
	ui.hide_tool_windows()
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	view = ui.vehicle_view
	view.set_process(false) # Render explicitly; never add an independent animation clock.
	for kind: String in KINDS:
		for quarter in range(4):
			if not _check_frame(kind, FACINGS[quarter], DIRECTIONS[quarter]): return
	team = lab.army
	team.team_id = lab._next_army_identity()
	team.roster_size = 2
	var initial: Array[Vector2i] = [anchor - Vector2i(3, 0), anchor - Vector2i(3, -1)]
	if not _check(team.deploy_at(data, lab.character, lab.npc, initial) and team.enable_combat(false, 0), "Original two-person Army fixture"): return
	team.set_process(false)
	var original_ids: Array[int] = [team.combat_identity(0), team.combat_identity(1)]
	var built: Dictionary = Runtime.begin_siege_build(data, "ballista", anchor, Vector2i.RIGHT, team.team_id, original_ids[0], ui.reserves_cell)
	if not _check(built.ok and int(data.site.inventory.wood) == 216 and int(data.site.inventory.iron) == 108 and int(data.site.inventory.fiber) == 90, "Paid original Runtime construction", built): return
	identity = str(built.vehicle)
	var vehicle: Dictionary = data.site.vehicles[identity]
	_focus((Vector2(anchor) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS)
	if not _check_ballista(vehicle) or not await _capture("01_building", {"phase": vehicle.phase, "paid_materials": true}): return
	completed.paid_build += 1
	var station: Dictionary = Runtime.siege_work_slots(data, vehicle)[0]
	if not _walk(0, data.cell_from_index(int(station.cell))): return
	var worked: Dictionary = Runtime.advance_siege_work(data, identity, "construct", float(vehicle.build.total_work), team.cells[0], int(station.slot), team.team_id)
	if not _check(worked.ok and vehicle.phase == "idle" and vehicle.build.is_empty(), "Original worker completion", worked): return
	for slot in range(2):
		var assigned: Dictionary = ui.vehicles.assign_crew(identity, original_ids[slot], str(slot), original_ids[0], true)
		if not _check(assigned.ok, "Original Army crew assignment", assigned): return
	for _step in range(800):
		if not _tick(): return
		if ui.vehicles.crew_ready(vehicle) and vehicle.phase == "ready" and vehicle.action.is_empty(): break
	if not _check(ui.vehicles.crew_ready(vehicle) and vehicle.phase == "ready" and team.combat_units.size() == 2 and team.combat_identity(0) == original_ids[0] and team.combat_identity(1) == original_ids[1], "Original crew never reached legal stations"): return
	var ready_names: Array[String] = ["02_ready_right", "04_ready_down", "05_ready_left", "06_ready_up"]
	for quarter in range(4):
		if quarter > 0:
			var previous := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
			var next := Vector2i(-previous.y, previous.x)
			var ordered: Dictionary = ui.vehicles.order_siege(identity, "turn", {"facing": [next.x, next.y]}, original_ids[0], true)
			if not _check(ordered.ok, "Real original crew turn", ordered): return
			for _step in range(1200):
				if not _tick(): return
				if quarter == 1 and completed.turning == 0 and str(vehicle.action.get("stage", "")) == "rotate" and float(vehicle.action.get("elapsed", 0.0)) >= 1.0:
					if not _check_ballista(vehicle, true) or not await _capture("03_turning", {"phase": vehicle.phase, "stage": vehicle.action.stage, "elapsed": vehicle.action.elapsed}): return
					completed.turning += 1
				if vehicle.action.is_empty() and vehicle.phase == "ready": break
			if not _check(vehicle.action.is_empty() and vehicle.phase == "ready" and vehicle.facing == [next.x, next.y], "Original turn did not settle"): return
		if not _check(ui.vehicles.crew_ready(vehicle) and int(vehicle.cell) == data.index(anchor) and Runtime.siege_cells(data, vehicle).size() == 6, "Original footprint/pivot/crew changed"): return
		if not _check_ballista(vehicle) or not await _capture(ready_names[quarter], {"phase": vehicle.phase, "facing": vehicle.facing.duplicate(), "crew_ids": original_ids, "solid_cells": 6}): return
		completed.ready += 1
	var damaged: Dictionary = Runtime.damage_siege_vehicle(data, identity, 70.0)
	if not _check(damaged.ok and float(vehicle.hp) == 70.0 and bool(vehicle.ever_hp_damaged), "Original damage", damaged): return
	if not _check_ballista(vehicle) or not await _capture("07_damaged", {"hp": vehicle.hp, "ever_hp_damaged": vehicle.ever_hp_damaged}): return
	completed.damage += 1
	# Initial rounds are explicit fixtures; the original release owner must debit exactly one.
	vehicle.cargo = {"siege_bolt": 2}
	vehicle.holder.version = int(vehicle.holder.version) + 1
	var holder_version: int = int(vehicle.holder.version)
	var sequence: int = int(vehicle.next_attack_seq)
	var shots: int = int(lab.siege_shots)
	var target := {"type": "ground", "cell": [anchor.x, anchor.y - 16]}
	var preview: Dictionary = lab.siege_fire_preview(vehicle, target)
	if not _check(preview.ok, "Original ground aim preview", preview): return
	var attack: Dictionary = ui.vehicles.order_siege(identity, "attack", target, original_ids[0], true)
	if not _check(attack.ok, "Original single shot order", attack): return
	for _step in range(800):
		if not _tick(): return
		if lab.has_siege_projectiles(): break
	if not _check(lab.siege_projectiles.size() == 1 and int(vehicle.cargo.get("siege_bolt", 0)) == 1 and int(vehicle.holder.version) == holder_version + 1 and int(vehicle.next_attack_seq) == sequence + 1 and int(lab.siege_shots) == shots + 1, "Release must debit exactly one original round", {"cargo": vehicle.cargo, "version": vehicle.holder.version, "sequence": vehicle.next_attack_seq, "shots": lab.siege_shots}): return
	var stop: Dictionary = ui.vehicles.order_siege(identity, "stop", {}, original_ids[0], true)
	if not _check(stop.ok, "Stop after the committed release", stop): return
	var flight: Dictionary = lab.siege_projectiles[0]
	lab._advance_siege_projectiles(float(flight.total) * 0.35)
	if not _check(lab.has_siege_projectiles(), "Original flight ended before its art capture") or not _check_bolt(flight): return
	_focus((Vector2(anchor) + Vector2(0, -7)) * TerrainRenderer.CELL_PIXELS, 0.85)
	if not await _capture("08_released_flight", {"attack_id": flight.attack_id, "original_round_debited_once": true, "holder_version_delta": 1, "sequence_delta": 1, "generated_bolt_sprite": true}): return
	completed.flight += 1
	var wrecked: Dictionary = Runtime.damage_siege_vehicle(data, identity, 999.0)
	if not _check(wrecked.ok, "Original wreck transition", wrecked) or not _tick(): return
	if not _check(vehicle.phase == "wrecked" and float(vehicle.hp) == 0.0 and vehicle.crew_slots.is_empty() and lab.has_siege_projectiles(), "Original wreck did not release crew/preserve flight"): return
	_focus((Vector2(anchor) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS)
	if not _check_ballista(vehicle) or not await _capture("09_wreck", {"phase": vehicle.phase, "hp": vehicle.hp, "original_crew_released": true, "released_round_survives": true}): return
	completed.wreck += 1
	lab._advance_siege_projectiles(float(flight.total))
	if not _check(not lab.has_siege_projectiles(), "Original flight must settle before pure art galleries"): return
	view.refresh()
	await process_frame
	for kind_index in range(KINDS.size()):
		if not await _gallery(KINDS[kind_index], TITLES[kind_index], 10 + kind_index): return
	if not _check(completed == {"frames": 24, "paid_build": 1, "ready": 4, "turning": 1, "damage": 1, "flight": 1, "wreck": 1, "gallery": 6} and captures.size() == 15 and sprite_mask_checks.size() == 24 and muzzle_checks.size() == 4, "Incomplete integration acceptance", {"completed": completed, "captures": captures.size(), "sprite_masks": sprite_mask_checks.size(), "muzzles": muzzle_checks.size()}): return
	var report: FileAccess = FileAccess.open(OUT + "/captures.json", FileAccess.WRITE)
	if not _check(report != null, "Cannot write integration report"): return
	report.store_string(JSON.stringify({"status": "SITE_SIEGE_GENERATED_ART_VISUAL_PASS", "completed": completed, "captures": captures, "asset_checks": asset_checks, "sprite_mask_checks": sprite_mask_checks, "muzzle_checks": muzzle_checks,
		"scope": "Original TerrainLab/VehicleView/Army GPU: paid construction, four real crew-ready turns and sub-0.01px terminal alignment, original-clock turning crossfade, damage/wreck, one paid generated-bolt flight, and six pure four-direction galleries. 24 source regions/pivots/scales, actual shader uniforms and declared reference exclusions checked; masked alpha sampled every four pixels. No alternate renderer or non-ballista gameplay records. Flat terrain/material/deployment/initial-round fixtures are explicit; only galleries temporarily hide the original resource presentation layer to provide unobscured asset proof, then restore it without changing records. Terminal alignment is not proof of perfect base fit, calibrated perspective, mechanisms, other five kinds gameplay, semantic person detection, performance or export; GPU appearance requires visual review."}, "\t"))
	report.close()
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	finished = true
	print("SITE_SIEGE_GENERATED_ART_VISUAL_PASS: frames=24 captures=15 masks=24 muzzles=4 original_scene=true original_crew=true paid_flight=true pure_gallery=true no_greybox=true")
	quit(0)
