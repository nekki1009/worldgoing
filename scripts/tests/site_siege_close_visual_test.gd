extends "res://scripts/tests/site_building_runtime_contract_test.gd"
## GPU-only original PackedScene, original presenter and original shared clock.
## Run each case/direction separately; all initial geometry/materials are fixtures.
const WorkAppend = preload("res://scripts/terrain_lab/site_siege_work_append.gd")
const DT := 1.0 / 120.0
const OUTPUT := "res://output/site_siege_close_20261004/gpu_integration"
const DIRECTIONS := {"right": Vector2i.RIGHT, "down": Vector2i.DOWN, "left": Vector2i.LEFT, "up": Vector2i.UP}
const KINDS := ["ballista", "ram", "traction_trebuchet", "counterweight_trebuchet", "siege_ladder", "siege_tower"]
var visual_case := "art"
var visual_kind := "ballista"
var visual_direction := "right"
var visual_mode := "gd"
var visual_deadline := 0
var visual_failed := false
var visual_finished := false
var visual_checks := 0
var shared_steps := 0
var captures: Array[Dictionary] = []
var checks: Array[Dictionary] = []
var folder := ""
var lab: TerrainLab
var ui: SiteController
var team: TerrainArmy
var key := ""
var anchor := Vector2i(32, 32)
var facing := Vector2i.RIGHT
var original_ids: Array[int] = []
var original_ladder_support_id := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for pair: Array in [["--siege-visual-case", "visual_case"], ["--siege-kind", "visual_kind"], ["--siege-facing", "visual_direction"], ["--siege-mode", "visual_mode"]]:
		var index := args.find(str(pair[0]))
		if index >= 0 and index + 1 < args.size(): set(str(pair[1]), args[index + 1])
	visual_deadline = Time.get_ticks_msec() + 600000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not visual_finished and Time.get_ticks_msec() >= visual_deadline:
		_fail("Bounded GPU case exceeded 600 seconds; no acceptance result")
	return false

func _expect(value: bool, label: String, detail: Variant = null) -> bool:
	visual_checks += 1
	checks.append({"ok": value, "label": label, "detail": str(detail)})
	if not value: _fail(label + " / " + str(detail))
	return value

func _fail(message: String) -> void:
	if visual_failed: return
	visual_failed = true
	_report()
	printerr("SIEGE GPU FAIL: ", message)
	quit(2)

func _report() -> void:
	if folder.is_empty(): return
	var report := FileAccess.open(folder.path_join("report.json"), FileAccess.WRITE)
	if report == null: return
	report.store_string(JSON.stringify({"status": "FAIL" if visual_failed else ("PASS" if visual_finished else "INCOMPLETE"),
		"case": visual_case, "kind": visual_kind, "direction": visual_direction, "mode": visual_mode,
		"checks": checks, "check_count": visual_checks, "captures": captures, "original_shared_steps": shared_steps,
		"original_person_ids": original_ids, "manual_visual_review": "PENDING",
		"scope": "Original TerrainLab PackedScene, original owner queries/steps and generated art. Explicit flat-map/material/initial stable art fixtures. Art-only fixtures do not prove deployment timing. No FPS/export/full-release acceptance."}, "\t"))
	report.close()

func _preflight() -> bool:
	if not _expect(DisplayServer.get_name() != "headless", "GPU viewport is required; no headless visual fallback"): return false
	if not _expect(visual_case in ["art", "tower", "ram", "ui"] and visual_mode in ["gd", "native"] and DIRECTIONS.has(visual_direction) and KINDS.has(visual_kind), "known isolated visual arguments"): return false
	if not _expect(visual_mode == "gd" or visual_case == "ui", "native visual scope is explicit UI owner proof; movement has independent native contracts"): return false
	facing = DIRECTIONS[visual_direction]
	var args := OS.get_cmdline_user_args()
	var paths := SiteController.new()
	var configured := paths.configure_test_paths(args)
	var named: bool = configured.ok and not paths.crowd_test_run_id.is_empty()
	var run_name := str(paths.crowd_test_run_id)
	var protected: bool = not paths._save_path_guard(SiteStore.DEFAULT_PATH).ok
	paths.free()
	if not _expect(named and protected, "named --crowd-test isolation protects formal saves", configured): return false
	folder = OUTPUT.path_join(run_name)
	if not _expect(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(folder)), "fresh GPU output folder", folder): return false
	if not _expect(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) == OK, "create isolated capture folder"): return false
	# The formal entry point is the main menu since ef39140 (World / Region / Site layers); the test
	# still drives the original TerrainLab scene directly and must not have changed the entry.
	return _expect(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/main_menu/MainMenu.tscn", "formal main scene remains the entry point")

var original_npc_fixture := false

func _scene() -> bool:
	root.size = Vector2i(1800, 1100)
	root.content_scale_size = root.size
	root.gui_embed_subwindows = true
	var packed: PackedScene = load("res://scenes/terrain_lab/TerrainLab.tscn")
	lab = packed.instantiate()
	if original_npc_fixture: lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	lab.movement_input_enabled = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	lab.site_controller._auto_save_blocked = true
	var data := _fixture()
	if not _expect(data != null, "explicit flat original terrain fixture exists"): return false
	data.site.player_cell = data.index(Vector2i(4, 4))
	data.site.manual.cell = data.site.player_cell
	data.site.worker.cell = data.index(Vector2i(4, 3))
	lab.bind_terrain(data)
	if original_npc_fixture and lab.npc.editor == null: lab.npc.initialize_visual()
	ui = lab.site_controller
	ui.set_process(false)
	ui._auto_save_blocked = true
	ui.release_worker()
	ui.hide_tool_windows()
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	return _expect(lab.terrain == data and ui.vehicle_view != null and ui.vehicles != null, "actual main scene binds original terrain/transport/view")

func _paid_vehicle(kind: String) -> bool:
	var created := SiteRuntime.begin_siege_build(lab.terrain, kind, anchor, facing, 1, 1)
	if not _expect(created.ok, "original paid vehicle build " + kind, created): return false
	key = str(created.vehicle)
	var vehicle: Dictionary = lab.terrain.site.vehicles[key]
	var station: Dictionary = SiteRuntime.siege_work_slots(lab.terrain, vehicle)[0]
	var result := SiteRuntime.advance_siege_work(lab.terrain, key, "construct", float(vehicle.build.total_work), lab.terrain.cell_from_index(int(station.cell)), int(station.slot), 1)
	return _expect(result.ok and vehicle.build.is_empty(), "original paid construction completes", result)

func _wall_supports() -> bool:
	var side := Vector2i(-facing.y, facing.x)
	for index in range(3):
		var wall := _build(lab.terrain, "palisade", anchor + facing * 5 + side * index)
		if not _expect(not wall.is_empty(), "original supporting wall exists"): return false
	return true

func _ladder_fixture() -> bool:
	var quarter: int = {"up": 0, "right": 1, "down": 2, "left": 3}[visual_direction]
	var support := SiteRuntime._layout_cell(Vector2i(0, -1), Vector2i(1, 2), quarter, anchor)
	original_ladder_support_id = _build(lab.terrain, "palisade", support)
	if not _expect(not original_ladder_support_id.is_empty(), "original ladder upper support"): return false
	key = _build(lab.terrain, "siege_ladder", anchor, Vector2i.ONE, {"quarter": quarter})
	return _expect(not key.is_empty() and SiteRuntime.validate_siege_ladder(lab.terrain.site.features[key]).ok, "original paid folded ladder fixture")

func _army(positions: Array[Vector2i]) -> bool:
	team = lab.army
	team.team_id = 1
	team.roster_size = positions.size()
	if not _expect(team.deploy_at(lab.terrain, lab.character, lab.npc, positions) and team.enable_combat(false, 1), "original Army owns all visual people"): return false
	team.set_process(false)
	team.tactical_ai_enabled = false
	ui.initialize_team_items(team)
	lab.terrain.site.army_next_team = 2
	for index in range(positions.size()): original_ids.append(team.combat_identity(index))
	return _expect(team._sprites.size() == positions.size(), "original person renderer has every roster slot")

func _step() -> bool:
	if Time.get_ticks_msec() >= visual_deadline: return _expect(false, "bounded original shared clock")
	var result := lab._advance_original_shared_step(DT)
	if not result.ok or not bool(result.get("completed", false)): return _expect(false, "one original shared step completes", result)
	shared_steps += 1
	return true

func _seconds(seconds: float) -> bool:
	for _tick_index in range(roundi(seconds / DT)):
		if not _step(): return false
	return true

func _focus() -> void:
	var centre := (Vector2(anchor) + Vector2.ONE * 0.5 + Vector2(facing) * 1.5) * TerrainRenderer.CELL_PIXELS
	lab.camera.zoom = Vector2.ONE * (1.05 if visual_kind == "counterweight_trebuchet" else 1.35)
	lab.camera.position = centre - Vector2(0, 75)
	lab.camera.reset_smoothing()
	lab.camera.force_update_scroll()

func _capture(label: String, detail: Dictionary = {}) -> bool:
	if lab.crowd_site != null and lab.crowd_site.active: lab.crowd_site.render(0.0)
	else:
		for _retry in range(240):
			team.advance_frame(0.0)
			var ready := true
			for index in range(team.combat_units.size()):
				if not _person_pixels_ready(index): ready = false; break
			if ready: break
			await process_frame
		for index in range(team.combat_units.size()):
			if not _expect(_person_pixels_ready(index), "original person has actual Sprite or admitted batch pixels", original_ids[index]): return false
	ui.vehicle_view.refresh()
	ui.view.refresh()
	# The original feature view must remain visible for supporting walls. The
	# explicit flat fixture already has an empty natural-resource base.
	for _frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	if not _expect(not picture.is_empty() and picture.get_size() == root.size, "real viewport image exists", label): return false
	var filename := label + ".png"
	if not _expect(picture.save_png(folder.path_join(filename)) == OK, "capture saved", filename): return false
	detail.merge({"file": filename, "sha256": FileAccess.get_sha256(folder.path_join(filename)), "vehicle_or_feature": key, "direction": visual_direction}, true)
	captures.append(detail)
	_report()
	return true

func _person_pixels_ready(index: int) -> bool:
	var sprite: Sprite2D = team._sprites[index]
	if sprite != null and sprite.visible and sprite.texture != null and sprite.texture.get_width() > 0: return true
	var batch: Variant = team._batch_view
	return batch != null and index < batch._page.size() and int(batch._page[index]) >= 0 and int(batch.rendered_count) > 0

func _sprite(state: String) -> Sprite2D:
	ui.vehicle_view.refresh()
	if visual_kind == "siege_ladder": return ui.vehicle_view._ladder_nodes.get(key)
	var node: Node2D = ui.vehicle_view._siege_nodes.get(key)
	if not _expect(node != null and str(node.get_meta("siege_art_state")) == state, "formal original presenter selects state " + state): return null
	return node.get_node("Body") as Sprite2D

func _verify_sprite(state: String) -> bool:
	var sprite := _sprite(state)
	if not _expect(sprite != null and sprite.texture != null and sprite.visible and sprite.region_enabled and is_zero_approx(sprite.rotation), "real generated-art Sprite is visible and unrotated", state): return false
	var definition: Dictionary = ui.vehicle_view._siege_art.get(visual_kind, {})
	# HP damage uses the exact normal source; collapsed wrecks stay explicit art.
	var art_state: String = "" if state == "damaged" else state
	if state == "damaged" and visual_kind == "siege_tower" and lab.terrain.site.vehicles[key].get("deployed_pose", {}).is_empty(): art_state = "mobile"
	var raw: Dictionary = definition.get("frames", {}).get(visual_direction, {}) if art_state.is_empty() else definition.get("states", {}).get(art_state, {}).get("frames", {}).get(visual_direction, {})
	var expected: String = visual_kind + "/" + visual_direction + ("/" + art_state if not art_state.is_empty() else "")
	if visual_kind == "ram" and art_state.is_empty():
		expected = "ram/chassis/" + visual_direction
		raw = definition.get("components", {}).get("chassis", {}).get("frames", {}).get(visual_direction, {})
	if not _expect(not raw.is_empty(), "exact authored normal or collapsed source exists", expected): return false
	if state == "damaged":
		var actual_tint: Color = sprite.modulate if visual_kind == "siege_ladder" else (sprite.get_parent() as Node2D).modulate
		if not _expect(actual_tint == SiteVehicleView.DAMAGED_TINT and actual_tint.a == 1.0, "actual HP damage tints the same normal footprint without altering opacity", actual_tint): return false
		if visual_kind == "ram":
			var beam: Sprite2D = sprite.get_parent().get_node_or_null("RamBeam")
			if not _expect(beam != null and beam.visible and beam.texture != null and str(beam.get_meta("siege_art_frame")) == "ram/beam/" + visual_direction, "damaged ram retains the original four-way contact head and mechanism"): return false
	var source := SiteVehicleView.SIEGE_ASSETS + str(raw.source)
	var region := Rect2(float(raw.region[0]), float(raw.region[1]), float(raw.region[2]), float(raw.region[3]))
	var scale_values: Array = raw.get("scale_xy", [raw.scale, raw.scale])
	var digest := str(raw.get("source_sha256", raw.get("calibration", {}).get("source_sha256", "")))
	if not _expect(digest.length() == 64 and sprite.texture.resource_path == source and FileAccess.get_sha256(source) == digest, "Sprite reads exact immutable authored source", expected): return false
	if not _expect(Rect2(Vector2.ZERO, sprite.texture.get_size()).encloses(region), "authored crop stays inside source pixels", expected): return false
	if not _expect(sprite.region_rect == region and sprite.offset == -Vector2(float(raw.pivot[0]), float(raw.pivot[1])) and sprite.scale.is_equal_approx(Vector2(float(scale_values[0]), float(scale_values[1]))), "Sprite applies exact source crop/pivot/scales", expected): return false
	if not raw.get("exclude_rects", []).is_empty():
		var mask := sprite.material as ShaderMaterial
		if not _expect(mask != null and mask.shader == SiteVehicleView.SiegeMask, "original SiegeMask is actually bound to masked sprite", expected): return false
	return _expect(str(sprite.get_meta("siege_art_frame", "")) == expected, "exact four-way state frame selected", sprite.get_meta("siege_art_frame", ""))

func _ladder_art_geometry() -> bool:
	var sprite: Sprite2D = ui.vehicle_view._ladder_nodes[key]
	var feature: Dictionary = lab.terrain.site.features[key]
	var geometry: Dictionary = SiteRuntime.feature_geometry(lab.terrain, feature)
	var raw: Dictionary = ui.vehicle_view._siege_art.siege_ladder.frames[visual_direction]
	if not _expect(raw.has("lower_attachment") and raw.has("upper_attachment"), "original ladder image has explicit toe and hook landmarks"): return false
	var entry_cell: Vector2i = geometry.external_lower.cell
	var exit_cell: Vector2i = geometry.stair_upper.cell
	var entry_height: int = int(geometry.external_lower.height)
	var exit_height: int = int(geometry.stair_upper.height)
	var entry: Vector2 = (Vector2(entry_cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS - Vector2(0, entry_height * 48)
	var exit: Vector2 = (Vector2(exit_cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS - Vector2(0, exit_height * 48)
	if not _expect(exit_cell - entry_cell == facing * 2 and exit_height - entry_height == 2 and lab.terrain.effective_height(entry_cell) == entry_height and lab.terrain.effective_height(exit_cell) == exit_height, "unchanged original ladder entry/exit cells and actual navigation heights", geometry): return false
	if not _expect((exit - entry).is_equal_approx(Vector2(facing) * 128.0 - Vector2(0, 96)), "independent original 64XY/48rise ladder endpoint projection", exit - entry): return false
	var support_cell: Vector2i = geometry.external_upper.cell
	if not _expect(support_cell == exit_cell + facing and int(geometry.external_upper.height) == exit_height and lab.terrain.effective_height(support_cell) == exit_height and lab.terrain.can_step(exit_cell, support_cell), "original adjacent supporting wall and level upper navigation edge", {"upper_cell": exit_cell, "wall_cell": support_cell, "height": exit_height}): return false
	# The real neighbouring wall near edge is not the upper navigation centre.
	var support_edge: Vector2 = (Vector2(support_cell) + Vector2.ONE * 0.5 - Vector2(facing) * 0.5) * TerrainRenderer.CELL_PIXELS - Vector2(0, exit_height * 48)
	if not _expect((support_edge - exit).is_equal_approx(Vector2(facing) * 32.0), "painted bearing target reaches the actual wall half-cell edge", support_edge - exit): return false
	var toe: Vector2 = Vector2(float(raw.lower_attachment[0]), float(raw.lower_attachment[1]))
	var hook: Vector2 = Vector2(float(raw.upper_attachment[0]), float(raw.upper_attachment[1]))
	var actual_entry: Vector2 = sprite.to_global(toe + sprite.offset)
	var actual_exit: Vector2 = sprite.to_global(hook + sprite.offset)
	var expected_entry: Vector2 = ui.vehicle_view.to_global(entry)
	var expected_exit: Vector2 = ui.vehicle_view.to_global(support_edge)
	return _expect(sprite.scale.x > 0.0 and sprite.scale.y > 0.0 and is_zero_approx(sprite.rotation) and not sprite.flip_h and not sprite.flip_v and actual_entry.distance_to(expected_entry) < 0.02 and actual_exit.distance_to(expected_exit) < 0.02, "painted ladder toe/hook reaches original entry/support-wall edge", {"source_toe": toe, "source_hook": hook, "actual_entry": actual_entry, "expected_entry": expected_entry, "actual_exit": actual_exit, "expected_exit": expected_exit, "source_scale": sprite.scale, "upper_navigation_centre": ui.vehicle_view.to_global(exit), "support_wall_edge": expected_exit, "manual_source_uncertainty_pixels": 12, "manual_alpha_review": "PENDING"})

func _tower_art_geometry() -> bool:
	var vehicle: Dictionary = lab.terrain.site.vehicles[key]
	var node: Node2D = ui.vehicle_view._siege_nodes[key]
	var body: Sprite2D = node.get_node("Body")
	var state: String = str(node.get_meta("siege_art_state"))
	var frame: Dictionary = ui.vehicle_view.siege_art_frame("siege_tower", facing, "" if state == "damaged" else state)
	var geometry := SiteRuntime.siege_tower_geometry(lab.terrain, vehicle)
	var centre := Vector2.ZERO
	for cell: Vector2i in geometry.top: centre += (Vector2(cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	centre /= float(geometry.top.size())
	var deck: Rect2 = frame.deck_region
	var projected := body.to_global(deck.get_center() + body.offset)
	if not _expect(projected.distance_to(centre - Vector2(0, 96)) < 0.02, "visible deck centre equals original top at minus 96 px", {"actual": projected, "expected": centre - Vector2(0, 96)}): return false
	for name_value: String in ["Entry0", "Entry1", "Bridge"]:
		var part: Sprite2D = node.get_node_or_null(name_value)
		if not _expect(part != null and part.visible and part.texture != null, "visible original tower part " + name_value): return false
		var cell: Vector2i = part.get_meta("original_surface_cell")
		var height: int = int(part.get_meta("original_surface_height"))
		var platform: Vector2 = (Vector2(cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS - Vector2(0, 48 * height)
		var expected: Vector2 = platform
		if name_value != "Bridge":
			var previous: Vector2i = cell - facing
			var lower_height: int = int(geometry.heights.get(lab.terrain.index(previous), int(vehicle.deployed_pose.level)))
			# Independent oracle: union the four original ramp corners with the
			# full upper landing cell supporting the unchanged original foot point.
			var centre_cell: Vector2 = Vector2(cell) + Vector2.ONE * 0.5
			var forward: Vector2 = Vector2(facing) * 0.5
			var side: Vector2 = Vector2(-facing.y, facing.x) * 0.5
			var corners: Array[Vector2] = []
			for cross: float in [-1.0, 1.0]:
				corners.append((centre_cell + forward + side * cross) * TerrainRenderer.CELL_PIXELS - Vector2(0, height * 48))
				corners.append((centre_cell - forward + side * cross) * TerrainRenderer.CELL_PIXELS - Vector2(0, lower_height * 48))
			var ramp_bounds: Rect2 = Rect2(corners[0], Vector2.ZERO)
			for point: Vector2 in corners: ramp_bounds = ramp_bounds.expand(point)
			ramp_bounds = ramp_bounds.merge(Rect2(platform - Vector2.ONE * TerrainRenderer.CELL_PIXELS * 0.5, Vector2.ONE * TerrainRenderer.CELL_PIXELS))
			expected = ramp_bounds.get_center()
			var rect: Rect2 = part.get_rect()
			var actual_bounds: Rect2 = Rect2(part.to_global(rect.position), part.to_global(rect.end) - part.to_global(rect.position))
			if not _expect(actual_bounds.position.distance_to(ramp_bounds.position) < 0.02 and actual_bounds.size.distance_to(ramp_bounds.size) < 0.02, "generated stair exactly spans original ramp corners and upper landing " + name_value, {"corners": corners, "expected": ramp_bounds, "actual": actual_bounds}): return false
		if not _expect(part.global_position.distance_to(expected) < 0.02 and lab.terrain.effective_height(cell) == height and int(geometry.heights[lab.terrain.index(cell)]) == height, "tower part preserves actual navigation platform and projected Sprite centre " + name_value, {"cell": cell, "height": height, "platform": platform, "sprite_centre": part.global_position}): return false
	# Count source pixels, respecting the exact material exclusions. This prevents
	# painting bridge/stairs twice through the body and the separate original part.
	var source := Image.load_from_file(str(frame.source))
	if not _expect(source != null and not source.is_empty(), "tower source pixels can be audited"): return false
	for raw: Dictionary in frame.parts.values():
		var part_rect := Rect2(float(raw.region[0]), float(raw.region[1]), float(raw.region[2]), float(raw.region[3]))
		var overlap: Rect2 = frame.region.intersection(part_rect)
		var effective_overlap := 0
		for y in range(int(overlap.position.y), int(overlap.end.y)):
			for x in range(int(overlap.position.x), int(overlap.end.x)):
				if source.get_pixel(x, y).a < 8.0 / 255.0: continue
				var excluded := false
				for mask: Rect2 in frame.exclusions:
					if mask.has_point(Vector2(x, y)): excluded = true; break
				if not excluded: effective_overlap += 1
		if not _expect(effective_overlap == 0 and raw.get("exclude_rects", []).is_empty(), "no opaque tower source pixel is drawn by both body and part", effective_overlap): return false
	return true

func _art() -> bool:
	if visual_kind == "siege_ladder":
		if not _ladder_fixture(): return false
	else:
		if not _paid_vehicle(visual_kind): return false
		if visual_kind == "siege_tower" and not _wall_supports(): return false
	var side := Vector2i(-facing.y, facing.x)
	if not _army([anchor - facing * 5 - side * 2, anchor - facing * 5 - side, anchor - facing * 5]): return false
	_focus()
	if visual_kind == "siege_ladder":
		var folded_detail := {"initial_stable_fixture": true, "timed_action_proof": false}
		var support_part_id := ""
		if visual_direction == "down":
			# The intact foreground wall physically covers this folded PNG. Break
			# its real paid part for this explicit art fixture; never hide its view.
			var support_wall: Dictionary = lab.terrain.site.features[original_ladder_support_id]
			var support_part_ids: Array = support_wall.parts.keys()
			support_part_ids.sort()
			if not _expect(support_part_ids.size() == 1, "original one-cell support has one real part", support_part_ids): return false
			support_part_id = str(support_part_ids[0])
			var damage_result: Dictionary = lab.siege_apply_damage_batch({original_ladder_support_id + "|" + support_part_id: {"feature": original_ladder_support_id, "part": support_part_id, "damage": 9999.0}}, {})
			var folded_geometry: Dictionary = SiteRuntime.feature_geometry(lab.terrain, lab.terrain.site.features[key])
			if not _expect(damage_result.ok and is_same(support_wall, lab.terrain.site.features[original_ladder_support_id]) and float(support_wall.parts[support_part_id].hp) == 0.0 and str(lab.terrain.site.features[key].ladder.phase) == "folded" and lab.terrain.effective_height(folded_geometry.stair_lower.cell) == 0 and lab.terrain.effective_height(folded_geometry.stair_upper.cell) == 0, "same paid support really becomes rubble while original ladder stays folded on ground", damage_result): return false
			folded_detail.merge({"real_support_wreck": true, "support_feature_id": original_ladder_support_id, "support_part_id": support_part_id, "intact_wall_occlusion_proof": false, "caption": "Same paid folded ladder shown after original support-part destruction; intact DOWN support wall physically occludes this source."})
		if not _verify_sprite("folded") or not await _capture("00_folded", folded_detail): return false
		if visual_direction == "down":
			var support_wall: Dictionary = lab.terrain.site.features[original_ladder_support_id]
			var inventory_before: Dictionary = lab.terrain.site.inventory.duplicate(true)
			var repaired: Dictionary = SiteRuntime.request_repair(lab.terrain, original_ladder_support_id, support_part_id, int(support_wall.owner_faction), Callable(ui, "_siege_people_occupied"))
			if not _expect(repaired.ok and support_wall.has("repair"), "same original support admits a real paid repair fixture", repaired): return false
			var repair_job: Dictionary = support_wall.repair
			for item: String in repair_job.cost:
				if not _expect(int(lab.terrain.site.inventory[item]) == int(inventory_before[item]) - int(repair_job.cost[item]), "support repair really debits original materials", {"item": item, "before": inventory_before[item], "after": lab.terrain.site.inventory[item], "cost": repair_job.cost[item]}): return false
			# Match the inherited paid initial-construction fixture. This is not
			# a live worker, action-clock repair or a12/8-second deployment proof.
			var repair_task: Dictionary = _task(original_ladder_support_id, "repair", int(repair_job.work_cell))
			SiteRuntime._feature_work(lab.terrain, original_ladder_support_id, float(repair_job.work), Callable(ui, "_siege_people_occupied"), Callable(), repair_task, {}, 20, int(support_wall.owner_faction))
			var restored_geometry: Dictionary = SiteRuntime.feature_geometry(lab.terrain, support_wall)
			var ladder_geometry: Dictionary = SiteRuntime.feature_geometry(lab.terrain, lab.terrain.site.features[key])
			if not _expect(is_same(support_wall, lab.terrain.site.features[original_ladder_support_id]) and not support_wall.has("repair") and is_equal_approx(float(support_wall.parts[support_part_id].hp), float(restored_geometry.parts[support_part_id].max_hp)) and lab.terrain.effective_height(ladder_geometry.external_upper.cell) == int(ladder_geometry.external_upper.height) and str(lab.terrain.site.features[key].ladder.phase) == "folded", "same support ID restores maxHP and true upper surface through original repair guard", {"support": original_ladder_support_id, "part": support_part_id, "hp": support_wall.parts[support_part_id].hp, "task": repair_task}): return false
		lab.terrain.site.features[key].ladder.phase = "deployed"
		SiteEnvironment.rebuild_indexes(lab.terrain)
	elif visual_kind == "siege_tower":
		if not _verify_sprite("mobile") or not await _capture("00_mobile", {"initial_stable_fixture": true}): return false
		var vehicle: Dictionary = lab.terrain.site.vehicles[key]
		vehicle.deployed_pose = SiteRuntime.siege_tower_pose(lab.terrain, vehicle)
		vehicle.phase = "deployed"
		SiteEnvironment.rebuild_indexes(lab.terrain)
	if not _verify_sprite(""): return false
	if visual_kind == "siege_tower" and not _tower_art_geometry(): return false
	if visual_kind == "siege_ladder" and not _ladder_art_geometry(): return false
	if not await _capture("01_normal", {"initial_stable_fixture": true, "timed_action_proof": false}): return false
	if visual_kind == "siege_ladder":
		if not await _ladder_walk_art(): return false
	if visual_kind == "siege_ladder":
		var feature: Dictionary = lab.terrain.site.features[key]
		var part_id := str(feature.parts.keys()[0])
		var result := lab.siege_apply_damage_batch({key + "|" + part_id: {"feature": key, "part": part_id, "damage": 49.0}}, {})
		if not _expect(result.ok and is_equal_approx(float(feature.parts[part_id].hp), 31.0), "actual original ladder part HP takes damage", result): return false
	else:
		if not _expect(lab.siege_apply_damage_batch({}, {key: float(SiteRuntime.SIEGE_DEFINITIONS[visual_kind].max_hp) * 0.6}).ok, "actual original vehicle HP takes damage"): return false
	if not _verify_sprite("damaged"): return false
	if visual_kind == "siege_tower" and not _tower_art_geometry(): return false
	if visual_kind == "siege_ladder" and not _ladder_art_geometry(): return false
	if not await _capture("02_damaged", {"actual_original_damage": true, "presentation": "normal_four_way_footprint_with_damage_tint"}): return false
	if visual_kind == "siege_ladder":
		var feature: Dictionary = lab.terrain.site.features[key]
		var part_id := str(feature.parts.keys()[0])
		if not _expect(lab.siege_apply_damage_batch({key + "|" + part_id: {"feature": key, "part": part_id, "damage": 9999.0}}, {}).ok, "actual original ladder part breaks"): return false
	else:
		if not _expect(lab.siege_apply_damage_batch({}, {key: 9999.0}).ok, "actual original vehicle becomes wreck"): return false
	if not _verify_sprite("wrecked") or not await _capture("03_wrecked", {"actual_original_damage": true}): return false
	return _expect(captures.size() == (7 if visual_kind == "siege_ladder" else (4 if visual_kind == "siege_tower" else 3)), "all required original art states and ladder person-step captures")

func _ladder_walk_art() -> bool:
	var geometry: Dictionary = SiteRuntime.feature_geometry(lab.terrain, lab.terrain.site.features[key])
	var entry: Vector2i = geometry.external_lower.cell
	var goal: Vector2i = geometry.external_upper.cell
	var identity: int = original_ids[2]
	var delta: Vector2i = entry - team.cells[2]
	var approach_steps: int = absi(delta.x) + absi(delta.y)
	if not _expect(delta == facing * approach_steps and approach_steps + 3 <= 8, "original axis member has bounded cardinal approach to real ladder entry", {"person_id": identity, "from": team.cells[2], "entry": entry, "steps": approach_steps + 3}): return false
	for _index in range(approach_steps):
		if not _walk_one(2, team.cells[2] + facing, goal): return false
		if not _expect(team.combat_identity(2) == identity and lab.terrain.effective_height(team.cells[2]) == int(geometry.external_lower.height), "same original Army identity reaches the natural-ground entry"): return false
	var landings: Array[Dictionary] = [
		{"cell": geometry.stair_lower.cell, "height": int(geometry.stair_lower.height), "rise": 1, "capture": "01a_ladder_lower"},
		{"cell": geometry.stair_upper.cell, "height": int(geometry.stair_upper.height), "rise": 2, "capture": "01b_ladder_upper"},
		{"cell": geometry.external_upper.cell, "height": int(geometry.external_upper.height), "rise": 2, "capture": "01c_ladder_wall"}]
	for landing: Dictionary in landings:
		var destination: Vector2i = landing.cell
		if not _walk_one(2, destination, goal): return false
		if not _expect(team.combat_identity(2) == identity and team.cells[2] == destination and team.moving_to[2] == TerrainArmy.INVALID_CELL and int(landing.height) - int(geometry.external_lower.height) == int(landing.rise) and lab.terrain.effective_height(team.cells[2]) == int(landing.height), "same original person settles on the true ladder/wall surface", {"person_id": identity, "cell": team.cells[2], "height": lab.terrain.effective_height(team.cells[2])}): return false
		if not await _capture(str(landing.capture), {"true_nav_movement": true, "timed_action_proof": false, "person_id": identity, "cell": [team.cells[2].x, team.cells[2].y], "original_surface_height": lab.terrain.effective_height(team.cells[2]), "final_goal": [goal.x, goal.y]}): return false
	return true

func _prepare_crew(count: int, with_walker: bool) -> bool:
	var vehicle: Dictionary = lab.terrain.site.vehicles[key]
	var side := Vector2i(-facing.y, facing.x)
	var positions: Array[Vector2i] = [anchor - facing * 3 - side * 2]
	for slot in range(count): positions.append(SiteRuntime.siege_crew_cell(lab.terrain, vehicle, str(slot)))
	if with_walker: positions.append(anchor - facing * 3 + side)
	if not _army(positions): return false
	for index in range(1, count + 1):
		var identity: int = original_ids[index]
		if not _expect(await WorkAppend.ensure(ui, ui.person_appearance(identity)), "complete original work-animation append is admitted", identity): return false
		var result := ui.vehicles.assign_crew(key, identity, str(index - 1), original_ids[0], true)
		if not _expect(result.ok, "real original crew assigned", result): return false
	for _step_index in range(120):
		if ui.vehicles.crew_ready(vehicle): break
		if not _step(): return false
	return _expect(ui.vehicles.crew_ready(vehicle), "all original crew stand at their actual stations")

func _walk_one(index: int, to: Vector2i, final_goal: Vector2i) -> bool:
	var source: Vector2i = team.cells[index]
	if not _expect(absi(to.x - source.x) + absi(to.y - source.y) == 1 and lab.terrain.can_step(source, to), "one actual original navigable edge", {"from": source, "to": to}): return false
	if not _expect(team._reserve_combat_step(index, to, 0, false, false, false, final_goal), "original Army reservation accepts edge with true final goal"): return false
	for _step_index in range(240):
		if not _step(): return false
		if team.moving_to[index] == TerrainArmy.INVALID_CELL: break
	return _expect(team.cells[index] == to and team.moving_to[index] == TerrainArmy.INVALID_CELL, "same original person settles one edge without teleport")

func _tower() -> bool:
	visual_kind = "siege_tower"
	if not _paid_vehicle(visual_kind) or not _wall_supports() or not await _prepare_crew(8, true): return false
	var vehicle: Dictionary = lab.terrain.site.vehicles[key]
	var roof := anchor + facing + Vector2i(-facing.y, facing.x)
	var command := ui.vehicles.order_siege(key, "deploy", {}, original_ids[0], true)
	if not _expect(command.ok, "actual tower deploy command admitted", command): return false
	if not _seconds(14.9): return false
	if not _expect(vehicle.deployed_pose.is_empty() and lab.terrain.effective_height(roof) == 0, "no roof before original 15-second deployment commit"): return false
	_focus()
	if not await _capture("01_deploying_14_9s", {"elapsed_action_seconds": 14.9, "height": 0}): return false
	if not _seconds(0.1): return false
	if not _expect(str(vehicle.phase) == "deployed" and lab.terrain.effective_height(roof) == 2, "actual original 15-second deployment committed"): return false
	if not _verify_sprite("") or not _tower_art_geometry(): return false
	if not await _capture("02_deployed", {"original_action_seconds": 15.0}): return false
	var side := Vector2i(-facing.y, facing.x)
	var goal := anchor + facing * 5 + side
	for forward in range(-2, 6):
		if not _walk_one(9, anchor + facing * forward + side, goal): return false
		if forward in [-2, -1, 1, 4, 5]:
			if not await _capture("03_walk_%d" % (forward + 2), {"person_id": original_ids[9], "cell": [team.cells[9].x, team.cells[9].y], "original_surface_height": lab.terrain.effective_height(team.cells[9])}): return false
	for forward in range(4, 0, -1):
		if not _walk_one(9, anchor + facing * forward + side, roof): return false
	var source: Vector2i = team.cells[9]
	var hp := float(team.combat_hot_get(9, &"hp"))
	var person_before: Dictionary = ui.person_actions._person(original_ids[9])
	var holder: Dictionary = person_before.holder
	var cargo: Dictionary = person_before.cargo
	if not _expect(lab.siege_apply_damage_batch({}, {key: 9999.0}).ok, "actual original HP destruction withdraws tower surface"): return false
	var person_after: Dictionary = ui.person_actions._person(original_ids[9])
	if not _expect(team.cells[9] == source and is_equal_approx(float(person_after.hp), hp - 30.0) and float(person_after.ko) > 0.0 and lab.terrain.effective_height(source) == 0, "one original two-layer fall preserves exact source/identity", person_after): return false
	if not _expect(is_same(holder, person_after.holder) and is_same(cargo, person_after.cargo), "fall preserves original holder and cargo authority"): return false
	if not _seconds(3.0): return false
	if not _expect(team.cells[9] == source and is_equal_approx(float(team.combat_hot_get(9, &"hp")), hp - 30.0), "later original steps cannot repeat the settled fall"): return false
	if not _verify_sprite("wrecked"): return false
	if not _expect(str(team.combat_hot_get(9, &"pose")) == "unconscious" and float(team.combat_hot_get(9, &"ko")) > 0.0, "original down animation reaches unconscious before settled-fall capture", {"pose": team.combat_hot_get(9, &"pose"), "age": team.combat_hot_get(9, &"age"), "ko": team.combat_hot_get(9, &"ko")}): return false
	return await _capture("04_original_fall_source", {"person_id": original_ids[9], "source": [source.x, source.y], "hp_loss": 30, "original_owner_preserved": true, "elapsed_fall_action_seconds": 3.0, "original_pose": str(team.combat_hot_get(9, &"pose")), "original_pose_age": float(team.combat_hot_get(9, &"age"))})

func _ram() -> bool:
	visual_kind = "ram"
	if not _paid_vehicle(visual_kind) or not await _prepare_crew(4, false): return false
	var vehicle: Dictionary = lab.terrain.site.vehicles[key]
	var source_cell := int(vehicle.cell)
	var source_people: Array[Vector2i] = team.cells.duplicate()
	ui.vehicle_view.refresh()
	var node: Node2D = ui.vehicle_view._siege_nodes[key]
	var beam: Sprite2D = node.get_node("RamBeam")
	var first_beam := beam.global_position
	var first_body := (node.get_node("Body") as Sprite2D).global_position
	var goal := anchor + facing
	var command := ui.vehicles.order_siege(key, "move", {"type": "ground", "cell": [goal.x, goal.y]}, original_ids[0], true)
	if not _expect(command.ok, "actual original ram compound command", command): return false
	for _step_index in range(240):
		if not _step(): return false
		if not vehicle.move.is_empty(): break
	if not _expect(not vehicle.move.is_empty(), "whole original ram group committed"): return false
	for _step_index in range(600):
		if float(team.move_progress[1]) >= 0.5: break
		if not _step(): return false
	ui.vehicle_view.refresh()
	var displacement := (node.get_node("Body") as Sprite2D).global_position - first_body
	if not _expect(int(vehicle.cell) == source_cell and team.cells == source_people and float(team.move_progress[1]) >= 0.5 and float(team.move_progress[1]) < 1.0, "original compound half step retains all source cells"): return false
	if not _expect(displacement.length() > 10.0 and (beam.global_position - first_beam).distance_to(displacement) < 0.02, "generated ram timber follows exact original moving chassis", displacement): return false
	_focus()
	if not await _capture("01_compound_half_move", {"source_cells_preserved": true, "progress": team.move_progress[1], "beam_and_body_translation": [displacement.x, displacement.y]}): return false
	for _step_index in range(600):
		if vehicle.move.is_empty(): break
		if not _step(): return false
	if not _expect(vehicle.move.is_empty() and int(vehicle.cell) == lab.terrain.index(goal), "whole original compound arrives before ram strike"): return false
	anchor = goal
	var wall_cell := anchor + facing * 3
	var wall := _build(lab.terrain, "palisade", wall_cell)
	var part := "c:" + str(lab.terrain.index(wall_cell))
	var target := {"type": "structure", "feature_id": wall, "part_id": part}
	command = ui.vehicles.order_siege(key, "attack", target, original_ids[0], true)
	if not _expect(command.ok, "actual original ram attack accepted", command): return false
	for _step_index in range(600):
		if str(vehicle.action.get("stage", "")) == "collision" and float(vehicle.action.get("elapsed", 0.0)) > 0.0: break
		if not _step(): return false
	if not _expect(str(vehicle.action.get("stage", "")) == "collision", "real original action reached collision stage"): return false
	ui.vehicle_view.refresh()
	var fraction := float(beam.get_meta("original_collision_fraction", -1.0))
	var shapes: Array[PackedVector2Array] = lab._siege_ram_shapes(vehicle, fraction)
	var centre := Vector2.ZERO
	for point: Vector2 in shapes[0]: centre += point
	centre /= float(shapes[0].size())
	if not _expect(fraction >= 0.0 and beam.global_position.distance_to(centre) < 0.02 and Vector2(beam.get_meta("original_contact_center")).distance_to(centre) < 0.02, "visible timber head equals original collision polygon centre", {"visual": beam.global_position, "contact": centre}): return false
	return await _capture("02_real_collision_head", {"original_action": vehicle.action.duplicate(true), "same_collision_head": true})

func _ui_case() -> bool:
	visual_kind = "ballista"
	if not _paid_vehicle(visual_kind): return false
	if not _army([anchor - Vector2i(4, 1), anchor - Vector2i(3, 0), anchor - Vector2i(3, -1)]): return false
	if visual_mode == "native":
		if not _expect(OS.get_cmdline_user_args().has("--crowd") and lab.crowd_site != null, "native UI requires original CrowdSite flag/ABI"): return false
		var parsed: Dictionary = lab._trial_side_settings({"friendly_count": 1, "friendly_training": 0, "friendly_female_percent": 0, "friendly_attack": false, "friendly_ai_enabled": false}, "friendly")
		if not _expect(parsed.ok, "original native UI side settings accepted", parsed): return false
		var settings: Dictionary = parsed.side
		settings.faction = 2
		var entered: Dictionary = lab.crowd_site.deploy([settings], [[Vector2i(65, 65)]])
		if not _expect(entered.ok and lab.crowd_site.active, "native UI imports same original Army people", entered): return false
	var controlled := ui._control_family_person(null, original_ids[0])
	if not _expect(controlled.ok and lab.controlled_person_id() == original_ids[0], "original owner changes control to actual commander", controlled): return false
	var form: Dictionary = ui._vehicle_forms.formal
	ui._refresh_vehicle_controls(form)
	var found := false
	for index in range(form.choice.item_count):
		if str(form.choice.get_item_metadata(index)) == key: form.choice.select(index); found = true; break
	if not _expect(found, "formal vehicle dropdown contains actual original vehicle"): return false
	ui._refresh_vehicle_details(form)
	var listed: Array[int] = []
	for index in range(form.operator.item_count): listed.append(int(form.operator.get_item_metadata(index)))
	for identity: int in original_ids:
		if not _expect(listed.has(identity), "formal operator dropdown contains original person", identity): return false
		var person: Dictionary = ui.person_actions._person(identity)
		if not _expect(not person.is_empty() and ui._can_command_siege_person(person), "actual original commander authority reaches siege UI person", identity): return false
		if visual_mode == "native" and not _expect(person.owner is CrowdPersonOwner, "native UI resolves true original native owner instead of disabled Army shadow", identity): return false
	ui.open_window("transport")
	await process_frame
	var scroll_parent: Node = form.operator.get_parent()
	while scroll_parent != null and not scroll_parent is ScrollContainer: scroll_parent = scroll_parent.get_parent()
	if not _expect(scroll_parent is ScrollContainer, "original transport operator has a visible scroll owner"): return false
	(scroll_parent as ScrollContainer).ensure_control_visible(form.operator)
	await process_frame
	if not _expect(form.operator.is_visible_in_tree(), "original operator control is visibly open"): return false
	_focus()
	form.operator.get_popup().popup(Rect2i(1150, 180, 420, 230))
	if not await _capture("01_formal_transport_owner_dropdown", {"listed_original_ids": listed, "mode": visual_mode, "controlled_original_commander": lab.controlled_person_id()}): return false
	form.operator.get_popup().hide()
	ui.hide_tool_windows()
	# Use the controls already created by the actual formal construction window.
	var construction: Window = ui.formal_windows.construction
	var first := construction.find_child("LadderFirstCrew", true, false) as OptionButton
	var second := construction.find_child("LadderSecondCrew", true, false) as OptionButton
	var refresh_button := construction.find_child("RefreshLadderCrew", true, false) as Button
	if not _expect(refresh_button != null, "formal construction owns the original ladder refresh action"): return false
	refresh_button.pressed.emit()
	if not _expect(first != null and second != null and first.item_count >= 2 and second.item_count >= 2, "real original ladder worker dropdowns populate from backend"): return false
	for identity: int in original_ids:
		var appears := false
		for index in range(first.item_count):
			if int(first.get_item_metadata(index)) == identity: appears = true
		if not _expect(appears, "ladder choice retains original identity", identity): return false
	ui.open_window("construction")
	await process_frame
	scroll_parent = first.get_parent()
	while scroll_parent != null and not scroll_parent is ScrollContainer: scroll_parent = scroll_parent.get_parent()
	if not _expect(scroll_parent is ScrollContainer, "formal ladder choices retain original scroll owner"): return false
	(scroll_parent as ScrollContainer).ensure_control_visible(first)
	await process_frame
	if not _expect(first.is_visible_in_tree(), "formal ladder choice is visibly open"): return false
	first.get_popup().popup(Rect2i(1150, 180, 420, 230))
	if not await _capture("02_formal_ladder_owner_dropdown", {"original_authority": true, "mode": visual_mode}): return false
	first.get_popup().hide()
	var switch_result := ui._control_family_person(null, lab.character.person_id)
	if not _expect(switch_result.ok, "switch to existing original non-commander actor", switch_result): return false
	if not _expect(not ui._can_command_siege_person(ui.person_actions._person(original_ids[1])), "non-commander cannot command another original siege worker"): return false
	ui.hide_tool_windows()
	return true

func _run() -> void:
	if not _preflight() or not _scene(): return
	var passed := false
	match visual_case:
		"art": passed = await _art()
		"tower": passed = await _tower()
		"ram": passed = await _ram()
		"ui": passed = await _ui_case()
	if not passed or visual_failed: return
	if not _expect(not captures.is_empty(), "successful visual case has actual saved GPU pixels"): return
	visual_finished = true
	_report()
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE_SIEGE_CLOSE_VISUAL_PASS: ", visual_case, " / ", visual_kind, " / ", visual_direction, " / ", visual_mode, " / ", captures.size(), " captures; manual pixel review remains separate")
	quit(0)
