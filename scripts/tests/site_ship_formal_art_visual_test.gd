extends SceneTree
## Candidate only until human approves v3 art and root leases formal integration.
## Strict GPU proof using original main scene, VehicleView/Transport/Army rows.
const OUT := "res://output/site_ship_close_20261004/formal_art_visual"
const MANIFEST := "res://assets/vehicles/ships/v1/ship_art.json"
const Ships = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Contract = preload("res://scripts/ui/character_render_contract.gd")
var deadline: int = 0
var run_completed: bool = false
var lab: TerrainLab
var team: TerrainArmy
var ids: Array[int] = []
var rows: Array[Dictionary] = []
var holders: Array[Dictionary] = []
var items: Array[Array] = []
var cargos: Array[Dictionary] = []
var boat_id: String = ""
var captures: Array[Dictionary] = []
var frames_checked: Dictionary = {}
var case_kind: String = "tower"
var boat_ids: Array[String] = []
var port_rows: Array[int] = []
const HULL_COUNTS := {"ferry":10, "river":5, "coastal":4, "troop":2, "patrol":4, "tower":1}

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 95000
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--ship-type="): case_kind = argument.trim_prefix("--ship-type=")
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not run_completed and Time.get_ticks_msec() > deadline:
		push_error("SHIP_FORMAL_ART_FAIL: GPU proof deadline")
		quit(1)
	return false

func _must(condition: bool, reason: String) -> bool:
	if condition: return true
	push_error("SHIP_FORMAL_ART_FAIL: " + reason)
	quit(1)
	return false

func _fixture() -> TerrainData:
	var data: TerrainData = Helper.build_flat_map(96, 96)
	data.resource_base.clear()
	data.spawn_cell = Vector2i(4, 4)
	data.site.player_cell = data.index(data.spawn_cell)
	data.site.manual.cell = data.site.player_cell
	data.site.worker.cell = data.index(Vector2i(4, 3))
	data.site.depot_cell = data.index(Vector2i(3, 4))
	data.surface_types.fill(TerrainData.Surface.GRASS)
	var navigable: Array[int] = []
	var spec: Dictionary = Ships.definition(case_kind)
	var radius: int = ceili(Vector2(float(spec.width) - 0.5, float(spec.length) - 0.5).length())
	for hull: int in range(int(HULL_COUNTS[case_kind])): port_rows.append(radius * 2 + 6 + hull * (int(spec.length) + 4))
	for y: int in data.size.y:
		for x: int in range(32, data.size.x):
			if x <= 49 and port_rows.has(y): continue # Real connected land piers, not remote boarding.
			var index: int = data.index(Vector2i(x, y))
			data.flags[index] = TerrainData.Flag.BLOCKED | TerrainData.Flag.WET
			data.surface_types[index] = TerrainData.Surface.WATER
			data.water_kind[index] = 1
			data.water_body[index] = 10
			navigable.append(index)
	data.parameters.navigable_water_version = 1
	data.parameters.navigable_water_cells = navigable
	Env.rebuild_indexes(data)
	Runtime.rebuild_terrain_edges(data)
	return data

func _art_fixture() -> TerrainData:
	# Art-only initial staging: legal connected pier pads, before deploy_at.
	# Perf deliberately retains its original _fixture / super._fixture chain.
	var data: TerrainData = _fixture()
	var spec: Dictionary = Ships.definition(case_kind)
	var staging_rows: int = ceili(float(spec.max_people) / 5.0)
	for port_y: int in port_rows:
		for y: int in range(port_y, port_y + staging_rows):
			for x: int in range(44, 49):
				var index: int = data.index(Vector2i(x, y))
				data.flags[index] = TerrainData.Flag.WALKABLE
				data.surface_types[index] = TerrainData.Surface.GRASS
				data.water_kind[index] = 0
				data.water_body[index] = 0
	var navigable: Array[int] = []
	for index: int in data.water_kind.size():
		if data.water_kind[index] == 1: navigable.append(index)
	data.parameters.navigable_water_cells = navigable
	Env.rebuild_indexes(data)
	Runtime.rebuild_terrain_edges(data)
	return data

func _check_people() -> bool:
	if not _must(team.combat_units.size() == 100 and team.roster_size == 100 and team._sprites.size() == 100, "Keep the actual hundred original Army people"): return false
	for index: int in range(100):
		var row: Dictionary = team.combat_units[index]
		var sprite: Sprite2D = team._sprites[index]
		if not _must(team.combat_identity(index) == ids[index] and is_same(row, rows[index]) and is_same(row.item_state, holders[index]) and row.item_state.item_ids == items[index] and row.cargo == cargos[index] and float(team.combat_hot_get(index, &"hp", 0.0)) == 100.0, "Rendering changed an original person/body/holder/cargo/HP"): return false
		if not _must(sprite != null and sprite.texture != null, "Original Army human texture must remain present"): return false
	return true

func _walk(index: int, destination: Vector2i) -> bool:
	var identity: int = ids[index]
	var path: Array[Vector2i] = lab.terrain.path_between(team.cells[index], destination, func(cell: Vector2i) -> bool:
		return team.blocks_cell(cell) or team._is_external_cell(cell, identity))
	if not _must(not path.is_empty() or team.cells[index] == destination, "Original connected shore route for real boarding"): return false
	if not _must(path.size() <= 256, "Explicit finite original walking route budget"): return false
	for next: Vector2i in path:
		if next == team.cells[index]: continue
		if not _must(team._reserve_combat_step(index, next), "Original shore reservation to boarding contact"): return false
		team.prepare_combat(float(team.move_duration[index]) + 0.01)
		if not _must(team.cells[index] == next and team.moving_to[index] == TerrainArmy.INVALID_CELL, "Real non-batch original step must commit"): return false
	return _must(Time.get_ticks_msec() < deadline, "Real boarding route fits deadline")

func _finish_job(identity: int) -> bool:
	var ui: SiteController = lab.site_controller
	if not _must(ui.person_actions.is_busy(identity), "Original timed ship job must exist before completion"): return false
	var job: Dictionary = ui.person_actions.job_for(identity)
	ui.person_actions.advance_ship_jobs(maxf(0.01, float(job.duration) - float(job.elapsed) + 0.01))
	ui.person_actions.settle_after_contacts()
	return _must(not ui.person_actions.is_busy(identity), "Original timed ship job must finish")

func _prepare_fleet() -> bool:
	var ui: SiteController = lab.site_controller
	var spec: Dictionary = Ships.definition(case_kind)
	for hull: int in range(int(HULL_COUNTS[case_kind])):
		var created: Dictionary = ui.vehicles.deploy_ship(team, case_kind, Vector2i(50, port_rows[hull]), Vector2i.UP, true)
		if not _must(created.ok, "Legal real pier-contact original fleet deployment: " + str(created)): return false
		boat_ids.append(str(created.vehicle_id))
	for index: int in range(100):
		var hull: int = floori(float(index) / float(spec.max_people))
		var vessel: String = boat_ids[hull]
		var port: Vector2i = Vector2i(49, port_rows[hull])
		if not _must(team.cells[index] != port, "Every original art passenger must walk at least one real reserved shore step"): return false
		if not _walk(index, port): return false
		var row: Dictionary = rows[index]
		var holder: Dictionary = holders[index]
		var board: Dictionary = ui.person_actions.begin_ship_board(ids[index], vessel, ids[index], index % int(spec.max_people), true)
		if not _must(board.ok and not row.has("embarked_vehicle_id") and team._cell_owners.get(port, -1) == index, "Original board must retain shore claim before timed commit: " + str(board)): return false
		if not _finish_job(ids[index]): return false
		if not _must(is_same(row, team.combat_units[index]) and is_same(holder, row.item_state) and str(row.embarked_vehicle_id) == vessel and int(row.berth_id) == index % int(spec.max_people) and not team._cell_owners.values().has(index), "Original timed boarding body/holder/berth and released ground claim"): return false
		if index % int(spec.max_people) == 0:
			var helm: Dictionary = ui.person_actions.begin_ship_helm(ids[index], vessel, ids[index], true)
			if not _must(helm.ok, "Original physical helm job starts") or not _finish_job(ids[index]): return false
	boat_id = boat_ids[0]
	if not _must(ui._control_family_person(null, ids[0]).ok and lab.controlled_person_id() == ids[0], "Use original control-switch caller, not a surrogate actor"): return false
	var boat: Dictionary = ui.vehicles.records()[boat_id]
	if not _must(not ui.person_actions.is_busy(ids[0]) and boat.operator_id == ids[0] and ui.vehicles.ship_driver_ready(boat) and ui.vehicles.ship_crew_count(boat) == int(spec.standard_crew), "Original helm/crew roles and timed job completion"): return false
	var total: int = 0
	for vessel: String in boat_ids:
		var current: Dictionary = ui.vehicles.records()[vessel]
		total += ui.vehicles.ship_people(current).size()
		if not _must(ui.vehicles.ship_load(vessel) <= float(spec.capacity) and ui.vehicles.ship_people(current).size() == int(spec.max_people) and ui.vehicles.ship_driver_ready(current), "Every real fleet hull keeps full original people and legal equipment Q"): return false
	if not _must(total == 100 and team._cell_owners.is_empty(), "All hundred original people truly boarded, without passenger copies"): return false
	if not _must(lab.select_army_target(ui.vehicles.ship_person_cell(ids[1])) and lab.selected_army_target == ids[1], "Original selection must find the actual embarked person via effective position"): return false
	return _check_people()

# Candidate test helpers only; read original Transport pose and exact PNG pixels.
var _ship_source_images: Dictionary = {}

func _ship_expected_corners(kind: String, pose: Dictionary, surface: Vector2) -> PackedVector2Array:
	var spec: Dictionary = Ships.definition(kind)
	var direction: Vector2 = pose.direction
	var right: Vector2 = Vector2(-direction.y, direction.x)
	var corners: PackedVector2Array = PackedVector2Array()
	for local: Vector2 in [Vector2(-0.5, -0.5), Vector2(float(spec.width) - 0.5, -0.5), Vector2(float(spec.width) - 0.5, float(spec.length) - 0.5), Vector2(-0.5, float(spec.length) - 0.5)]:
		corners.append((Vector2(pose.anchor) + right * local.x + direction * local.y + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS + surface)
	return corners

func _ship_source_corners(body: Sprite2D, source: Rect2, region: Rect2) -> PackedVector2Array:
	var corners: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in [source.position, source.position + Vector2(source.size.x, 0), source.end, source.position + Vector2(0, source.size.y)]:
		corners.append(body.transform * (point - region.position))
	return corners

func _ship_corner_bounds(corners: PackedVector2Array) -> Rect2:
	var minimum: Vector2 = corners[0]
	var maximum: Vector2 = corners[0]
	for point: Vector2 in corners:
		minimum = Vector2(minf(minimum.x, point.x), minf(minimum.y, point.y))
		maximum = Vector2(maxf(maximum.x, point.x), maxf(maximum.y, point.y))
	return Rect2(minimum, maximum - minimum)

func _check_ship_frame_geometry(kind: String, pose: Dictionary, frame: Dictionary, source_facing: Vector2i, body: Sprite2D, front: Sprite2D) -> Dictionary:
	var ground: Vector2 = (Vector2(pose.anchor) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	var surface: Vector2 = lab.terrain.surface_visual_offset_at(ground)
	var rotation: float = Vector2(source_facing).angle_to(Vector2(pose.direction))
	var reference: Rect2 = frame.reference_region
	var region: Rect2 = frame.region
	var source_pose: Dictionary = {"anchor":Vector2.ZERO, "direction":Vector2(source_facing)}
	var source_bounds: Rect2 = _ship_corner_bounds(_ship_expected_corners(kind, source_pose, Vector2.ZERO))
	if not _must(absf(wrapf(body.rotation - rotation, -PI, PI)) < 0.000001 and absf(wrapf(front.rotation - rotation, -PI, PI)) < 0.000001 and body.scale.distance_to(source_bounds.size / reference.size) < 0.000001 and body.transform.is_equal_approx(front.transform), "Cardinal source retains its own hull scale and rotates with the original continuous boat basis"): return {}
	var expected_corners: PackedVector2Array = _ship_expected_corners(kind, pose, surface)
	var actual_corners: PackedVector2Array = _ship_source_corners(body, reference, region)
	for point: Vector2 in actual_corners:
		var nearest: float = INF
		for expected: Vector2 in expected_corners: nearest = minf(nearest, point.distance_to(expected))
		if not _must(nearest < 0.01, "Every transformed full-hull reference corner matches an actual physical corner within 0.01px, including halfway through turns"): return {}
	var mapped: Rect2 = _ship_corner_bounds(actual_corners)
	var expected_bounds: Rect2 = _ship_corner_bounds(expected_corners)
	if not _must(mapped.position.distance_to(expected_bounds.position) < 0.01 and mapped.size.distance_to(expected_bounds.size) < 0.01 and body.z_index == 1 and front.z_index > 10 + floori(expected_bounds.end.y / TerrainRenderer.CELL_PIXELS), "Actual rotated hull bounds and foreground depth follow the original physical corners"): return {}
	var art: Rect2 = _ship_corner_bounds(_ship_source_corners(body, region, region))
	return {"physical":mapped, "art":art, "surface":surface, "rotation":rotation, "corners":actual_corners}

func _check_ship_source_foot(body: Sprite2D, frame: Dictionary, ground: Vector2, surface: Vector2) -> bool:
	# to_local inverts the actual Sprite rotation, pivot and source-specific scale.
	var view: SiteVehicleView = lab.site_controller.vehicle_view
	var source_point: Vector2 = body.to_local(view.to_global(ground + surface)) + Vector2(frame.region.position)
	var reference: Rect2 = frame.reference_region
	if not _must(reference.has_point(source_point), "Original person foot inverse-maps inside this actual source hull, including both crossblend frames"): return false
	var source: String = str(frame.source)
	var image: Image = _ship_source_images.get(source)
	if image == null:
		image = Image.load_from_file(source)
		if not _must(image != null and not image.is_empty(), "Exact source PNG pixels must be readable for original foot checks"): return false
		_ship_source_images[source] = image
	var pixel: Vector2i = Vector2i(source_point.floor())
	if not _must(pixel.x >= 0 and pixel.y >= 0 and pixel.x < image.get_width() and pixel.y < image.get_height(), "Inverse foot source pixel must exist"): return false
	return _must(image.get_pixel(pixel.x, pixel.y).a >= 64.0 / 255.0, "Every actual original foot maps to opaque physical ship source pixels, not transparent padding or a stretched AABB")

func _check_render(kind: String, facing: Vector2i, vehicle_id: String = "") -> Dictionary:
	if vehicle_id.is_empty(): vehicle_id = boat_id
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var view: SiteVehicleView = lab.site_controller.vehicle_view
	view.refresh()
	var node: Node2D = view._ship_nodes.get(vehicle_id)
	if not _must(node != null and node.is_visible_in_tree() and node.get_meta("ship_formal_art", false) and not node.get_meta("ship_debug_geometry", true), "Actual VehicleView must render formal PNG, with no gray fallback"): return {}
	var body: Sprite2D = node.get_node_or_null("Body")
	var front: Sprite2D = node.get_node_or_null("Foreground")
	var frame: Dictionary = view.ship_art_frame(kind, facing)
	if not _must(body != null and front != null and not frame.is_empty() and body.material is ShaderMaterial and front.material is ShaderMaterial and body.texture == frame.texture and front.texture == frame.texture and body.texture_filter == Contract.TEXTURE_FILTER and front.texture_filter == Contract.TEXTURE_FILTER and not (node.get_node("Hull") as Polygon2D).visible, "Real source frame/material/filter and hidden debug shape"): return {}
	var boat: Dictionary = vehicles.records()[vehicle_id]
	var pose: Dictionary = vehicles.ship_render_pose(boat)
	var primary: Dictionary = _check_ship_frame_geometry(kind, pose, frame, facing, body, front)
	if primary.is_empty(): return {}
	var expected: Rect2 = view._ship_pose_rectangle(kind, pose)
	expected.position += Vector2(primary.surface)
	var mapped: Rect2 = primary.physical
	if not _must(mapped.position.distance_to(expected.position) < 0.01 and mapped.size.distance_to(expected.size) < 0.01, "Presenter footprint metadata matches independently checked rotated physical corners"): return {}
	var layers: Array[Dictionary] = [{"body":body, "front":front, "frame":frame, "geometry":primary}]
	var art: Rect2 = primary.art
	var move: Dictionary = boat.get("move", {})
	if not move.is_empty():
		var next_facing: Vector2i = Vector2i(int(move.facing[0]), int(move.facing[1]))
		if next_facing != facing:
			var next_frame: Dictionary = view.ship_art_frame(kind, next_facing)
			var next_body: Sprite2D = node.get_node_or_null("TurnBody")
			var next_front: Sprite2D = node.get_node_or_null("TurnForeground")
			if not _must(next_body != null and next_front != null and not next_frame.is_empty() and next_body.visible and next_front.visible and next_body.texture == next_frame.texture and next_front.texture == next_frame.texture and next_body.material is ShaderMaterial and next_front.material is ShaderMaterial and next_body.texture_filter == Contract.TEXTURE_FILTER and next_front.texture_filter == Contract.TEXTURE_FILTER, "Both actual cardinal source pairs exist during the real committed turn"): return {}
			if not _must(is_equal_approx(body.modulate.a, 1.0 - float(pose.progress)) and is_equal_approx(front.modulate.a, body.modulate.a) and is_equal_approx(next_body.modulate.a, float(pose.progress)) and is_equal_approx(next_front.modulate.a, next_body.modulate.a), "Original crossblend follows the actual committed turn progress"): return {}
			var target: Dictionary = _check_ship_frame_geometry(kind, pose, next_frame, next_facing, next_body, next_front)
			if target.is_empty(): return {}
			layers.append({"body":next_body, "front":next_front, "frame":next_frame, "geometry":target})
			art = art.merge(target.art)
	else:
		if not _must(absf(body.rotation) < 0.000001 and absf(front.rotation) < 0.000001, "Stopped cardinal source must not receive a second rotation"): return {}
	var rotations: Array[float] = []
	for layer: Dictionary in layers:
		var body_material: ShaderMaterial = layer.body.material
		var front_material: ShaderMaterial = layer.front.material
		if not _must(body_material.get_shader_parameter("foreground") == false and front_material.get_shader_parameter("foreground") == true and body_material.get_shader_parameter("polygon_counts") == front_material.get_shader_parameter("polygon_counts") and body_material.get_shader_parameter("polygon_points") == front_material.get_shader_parameter("polygon_points"), "Both actual layers use the same source-pixel mask after rotation"): return {}
		rotations.append(float(layer.geometry.rotation))
	var spec: Dictionary = Ships.definition(kind)
	var counted: int = 0
	for index: int in range(100):
		if str(rows[index].get("embarked_vehicle_id", "")) != vehicle_id: continue
		counted += 1
		var sprite: Sprite2D = team._sprites[index]
		if not _must(sprite != null and sprite.texture != null, "Every living original embarked human has its actual Sprite"): return {}
		var ground: Vector2 = vehicles.ship_person_ground(ids[index])
		var displayed: Vector2 = sprite.position + team._unit_anchor(index) - lab.terrain.surface_visual_offset_at(ground)
		if not _must(displayed.distance_to(ground) < 0.01, "Original human foot follows its actual unchanged berth and continuous boat basis"): return {}
		for layer: Dictionary in layers:
			if not _check_ship_source_foot(layer.body, layer.frame, ground, layer.geometry.surface): return {}
	if not _must(counted == int(spec.max_people), "Every real hull retains its full original physical-berth people"): return {}
	frames_checked[kind + "/" + str(frame.direction)] = true
	return {"physical":mapped, "art":art, "frame":frame, "source_layers":layers.size(), "source_rotations":rotations, "actual_original_feet":counted, "inverse_source_alpha_checked":true}

func _focus(bounds: Rect2) -> void:
	var space: Vector2 = Vector2(root.size) - Vector2(160, 200)
	lab.camera.zoom = Vector2.ONE * clampf(minf(space.x / maxf(1.0, bounds.size.x), space.y / maxf(1.0, bounds.size.y)), 0.08, 2.5)
	lab.camera.position = bounds.get_center() + Vector2(0, -20)
	lab.camera.reset_smoothing()
	lab.camera.force_update_scroll()

func _capture(file_name: String, kind: String, direction: String, empty: bool = false, ref: Dictionary = {}) -> bool:
	for _frame: int in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	if not _must(not picture.is_empty() and picture.save_png(OUT + "/" + case_kind + "/" + file_name + ".png") == OK, "Actual GPU screenshot must be retained: " + file_name): return false
	var boat: Dictionary = lab.site_controller.vehicles.records()[boat_id]
	var screen: Transform2D = lab.get_viewport().get_canvas_transform()
	var art: Rect2 = ref.get("art", Rect2())
	if art.has_area():
		var screen_min: Vector2 = screen * art.position
		var screen_max: Vector2 = screen * art.end
		if not _must(screen_min.x >= 0 and screen_min.y >= 0 and screen_max.x <= root.size.x and screen_max.y <= root.size.y, "Full original art must fit bounded camera, including oars/end flags"): return false
	captures.append({"file": file_name + ".png", "kind": kind, "direction": direction, "vehicle_id": boat_id,
		"actual_fleet_hulls":boat_ids.duplicate(), "all_hundred_truly_boarded":true,
		"owner": "original TerrainLab / SiteController.VehicleView / Transport / TerrainArmy", "crew_hidden_for_empty_asset_proof": empty,
		"actual_people": lab.site_controller.vehicles.ship_people(boat).size(), "original_roster": team.combat_units.size(),
		"operator_id": int(boat.operator_id), "controlled_person_id": lab.controlled_person_id(), "selected_person_id": lab.selected_army_target,
		"original_crew": lab.site_controller.vehicles.ship_crew_count(boat), "source_sha256": str(ref.get("frame", {}).get("source_sha256", "")),
		"actual_source_layers":int(ref.get("source_layers", 0)), "source_rotations":ref.get("source_rotations", []), "inverse_source_alpha_checked":bool(ref.get("inverse_source_alpha_checked", false)),
		"visual_form": "Elevated lookout tower with upper chamber/roof and open undercroft; source masks await original-owner GPU review" if kind == "tower" else "rectangular open hull"})
	return _must(Time.get_ticks_msec() < deadline, "Capture did not finish inside the bounded GPU run")

func _run() -> void:
	if not _must(DisplayServer.get_name() != "headless", "Requires real GPU viewport"): return
	if not _must(Ships.KINDS.has(case_kind), "Run one named real-boarding density case: --ship-type=ferry|river|coastal|troop|patrol|tower"): return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not _must(manifest is Dictionary and manifest.get("schema_version") == 1 and manifest.get("definition_version") == Ships.VERSION and manifest.get("entries") is Dictionary and manifest.entries.size() == 6, "Missing/invalid approved formal manifest is FAIL; never skip it"): return
	for kind: String in Ships.KINDS:
		var entry: Dictionary = manifest.entries.get(kind, {})
		if not _must(entry.get("frames", {}).size() == 4 and entry.get("no_baked_people", false) and entry.get("source_size", []).size() == 2, "All six empty sheets/four genuine frames must be admitted"): return
		var path: String = "res://assets/vehicles/ships/v1/" + str(entry.get("source", ""))
		if not _must(FileAccess.file_exists(path) and FileAccess.get_sha256(path).to_upper() == str(entry.get("source_sha256", "")), "Formal PNG must retain exact approved source bytes: " + kind): return
	if not _must(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "/" + case_kind)) == OK, "Output path creation"): return
	root.size = Vector2i(1800, 1100)
	root.content_scale_size = root.size
	root.gui_embed_subwindows = true
	var main: PackedScene = load("res://scenes/terrain_lab/TerrainLab.tscn")
	if not _must(main != null, "Original main scene"): return
	lab = main.instantiate()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	if lab.npc.editor == null: lab.npc.initialize_visual()
	if not _must(lab.character.editor != null and lab.npc.editor != null, "Original main-scene actor/NPC visual initialization"): return
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	lab.bind_terrain(_art_fixture())
	lab.site_controller.release_worker()
	lab.site_controller.hide_tool_windows()
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for army: TerrainArmy in lab.combat_armies: army.set_process(false)
	team = lab.army
	team.role = "logistics"
	team.team_id = lab._next_army_identity()
	team.roster_size = 100
	# Original Sprite reference branch, to inspect every real foot/material and
	# reversible empty-source proof. This is no native/batch/performance claim.
	team.batch_render_enabled = false
	var shore: Array[Vector2i] = []
	var staging_spec: Dictionary = Ships.definition(case_kind)
	for hull: int in range(int(HULL_COUNTS[case_kind])):
		for slot: int in range(int(staging_spec.max_people)):
			# Closest first: released cells form the next real original route.
			shore.append(Vector2i(48 - slot % 5, port_rows[hull] + floori(float(slot) / 5.0)))
	if not _must(team.deploy_at(lab.terrain, lab.character, lab.npc, shore), "Original hundred-person deployment"): return
	if not _must(TerrainArmy.load_combat_bake() and team.enable_combat(false, 0), "Original existing combat human atlas and bodies must enable"): return
	lab.terrain.site.army_next_team = team.team_id + 1
	lab.terrain.site.army_trial_active = true
	for index: int in range(100):
		var row: Dictionary = team.combat_units[index]
		row.logistics = true
		ids.append(team.combat_identity(index));rows.append(row);holders.append(row.item_state)
		items.append(row.item_state.item_ids.duplicate());cargos.append(row.cargo.duplicate(true))
	var ui: SiteController = lab.site_controller
	if not _prepare_fleet(): return
	team.advance_frame(0.0)
	var initial: Dictionary = _check_render(case_kind, Vector2i.UP)
	if initial.is_empty(): return
	_focus(initial.art.grow(60))
	if not await _capture("00_actual_first_full_hull_nearshore", case_kind, "up", false, initial): return
	var fleet_bounds: Rect2 = initial.art
	for vessel: String in boat_ids:
		var vessel_ref: Dictionary = _check_render(case_kind, Vector2i.UP, vessel)
		if vessel_ref.is_empty(): return
		fleet_bounds = fleet_bounds.merge(vessel_ref.art)
	_focus(fleet_bounds.grow(60))
	if not await _capture("00b_actual_whole_hundred_person_fleet", case_kind, "up", false, {"art":fleet_bounds,"frame":initial.frame}): return
	var boat: Dictionary = ui.vehicles.records()[boat_id]
	var spec: Dictionary = Ships.definition(case_kind)
	var radius: int = ceili(Vector2(float(spec.width) - 0.5, float(spec.length) - 0.5).length())
	for step: int in range(radius + 2):
		var departure: Dictionary = ui.vehicles.ship_order(boat_id, "forward", TerrainArmy.INVALID_CELL, ids[0])
		if not _must(departure.ok and not boat.move.is_empty(), "Original controlled helm departs connected pier before turning: " + str(departure)): return
		ui.vehicles.update_ships(float(boat.move.duration) + 0.01)
	var turn_anchor: int = int(boat.cell)
	for quarter: int in range(4):
		var facing: Vector2i = TerrainData.DIRECTIONS[quarter]
		if quarter > 0:
			var turn: Dictionary = ui.vehicles.ship_order(boat_id, "turn_right", TerrainArmy.INVALID_CELL, ids[0])
			if not _must(turn.ok and not boat.move.is_empty(), "Real full-hull quarter turn: " + str(turn)): return
			if quarter == 1:
				ui.vehicles.update_ships(float(boat.move.duration) * 0.5)
				var half_pose: Dictionary = ui.vehicles.ship_render_pose(boat)
				if not _must(not boat.move.is_empty() and int(boat.cell) == turn_anchor and is_equal_approx(float(half_pose.progress), 0.5) and not Vector2(half_pose.direction).is_equal_approx(Vector2.UP) and not Vector2(half_pose.direction).is_equal_approx(Vector2.RIGHT), "Committed original quarter turn is truly halfway and rotates its original people continuously"): return
				team.advance_frame(0.0)
				var midway: Dictionary = _check_render(case_kind, Vector2i.UP)
				if midway.is_empty(): return
				if not _must(int(midway.source_layers) == 2 and midway.source_rotations.size() == 2 and is_equal_approx(absf(float(midway.source_rotations[0])), PI * 0.25) and is_equal_approx(absf(float(midway.source_rotations[1])), PI * 0.25) and int(midway.actual_original_feet) == int(spec.max_people), "Both real source frames turn +/-45 degrees around the unchanged pivot and every original foot inverse-maps onto actual source pixels"): return
				_focus(midway.art.grow(60))
				if not await _capture("01_real_turn_half", case_kind, "up_to_right", false, midway): return
			ui.vehicles.update_ships(float(boat.move.duration) + 0.01)
		if not _must(int(boat.cell) == turn_anchor and boat.move.is_empty(), "Original quarter turn keeps stern pivot and finishes fully"): return
		team.advance_frame(0.0)
		var ref: Dictionary = _check_render(case_kind, facing)
		if ref.is_empty(): return
		_focus(ref.art.grow(60))
		var direction: String = str(ref.frame.direction)
		if not await _capture(case_kind + "_" + direction + "_original_people", case_kind, direction, false, ref): return
		var before: PackedByteArray = var_to_bytes(lab.terrain.site.vehicles)
		team.hide() # Presentation-only empty proof; no person/ship state removal.
		if not await _capture(case_kind + "_" + direction + "_empty_source", case_kind, direction, true, ref): return
		team.show()
		if not _must(before == var_to_bytes(lab.terrain.site.vehicles) and _check_people(), "Empty art proof never changes the source owner or real people"): return
	ui.open_window("transport")
	var form: Dictionary = ui._vehicle_forms.formal
	ui._refresh_vehicle_controls(form)
	if not _must(ui._selected_vehicle(form).id == boat_id and not bool(form.trial) and str(form.status.text).contains(boat_id), "Original formal transport window must display current original hull/crew"): return
	if not await _capture(case_kind + "_formal_transport_selected_controlled", case_kind, "left"): return
	ui.hide_tool_windows()
	var sail: Dictionary = ui.vehicles.ship_order(boat_id, "forward", TerrainArmy.INVALID_CELL, ids[0])
	if not _must(sail.ok and not boat.move.is_empty(), "Actual controlled helm must issue a formal ship move"): return
	ui.vehicles.update_ships(float(boat.move.duration) * 0.5)
	team.advance_frame(0.0)
	var moving: Dictionary = _check_render(case_kind, Vector2i.LEFT)
	if moving.is_empty(): return
	_focus(moving.art.grow(60))
	if not _must(ui.vehicles.ship_person_crew_work(ids[0]) and (int(spec.standard_crew) == 1 or ui.vehicles.ship_person_crew_work(ids[1])) and not ui.vehicles.ship_person_crew_work(ids[int(spec.standard_crew)]), "Only actual original assigned crew perform sailing work"): return
	if not await _capture(case_kind + "_real_hundred_half_step", case_kind, "left", false, moving): return
	if not _must(ui.vehicles.ship_order(boat_id, "stop", TerrainArmy.INVALID_CELL, ids[0]).ok, "Stop through original formal order owner"): return
	ui.vehicles.update_ships(float(boat.move.duration) + 0.01)
	if not _must(boat.move.is_empty() and boat.command.is_empty() and frames_checked.size() == 4 and captures.size() == 13 and _check_people(), "One named type: full real hundred-person fleet/four real frames/four empty sources/nearshore/whole fleet/UI/halfturn/halfstep must complete"): return
	var report: FileAccess = FileAccess.open(OUT + "/" + case_kind + "/visual_report.json", FileAccess.WRITE)
	if not _must(report != null, "GPU report write"): return
	report.store_string(JSON.stringify({"status":"SITE_SHIP_FORMAL_ART_VISUAL_PASS", "frames":frames_checked,
		"kind":case_kind,"captures":captures,"scope":"One named real hundred-person fleet per bounded GPU run; run all six --ship-type cases for 24 cardinal frames. Every original person truly walked the connected pier and committed the original timed boarding/helm job. Original main scene/VehicleView/Transport/Army Sprite reference path, exact formal PNG hashes, original max N/physical hull/berths, true turns/turn-half/step-half/nearshore, real control/selection/crew and UI query. Actual body/front materials and source mask uniforms; reversible original-team visibility gives four empty-source captures per case. 0.01px transformed physical-corner/actual-foot agreement; every original foot inverse-maps onto opaque source pixels in both actual turn-half frames. Source semantic empty content and occlusion aesthetics still require human inspection. No native/Crowd/batch performance or export claim; tower proportions and occlusion aesthetics require human review."}, "\t"))
	report.close()
	run_completed = true
	lab.queue_free()
	await process_frame
	print("SITE_SHIP_FORMAL_ART_VISUAL_PASS:" + case_kind + ":four formal frames/four empty hulls/TRUE hundred-person boarding/real UI/helm/crew/turnhalf/halfstep/nearshore/no gray fallback")
	quit(0)
