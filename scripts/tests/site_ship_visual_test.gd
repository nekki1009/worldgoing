extends SceneTree
## GPU-only: real main scene, original Army people, Transport and VehicleView.
const OUT := "res://output/site_ship_implementation_20261003/visual"
const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Data = preload("res://scripts/terrain_lab/terrain_data.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")

var deadline := 0
var lab: TerrainLab
var team: TerrainArmy
var people: Array[int] = []
var original_holders: Array[Dictionary] = []
var original_items: Array = []
var captures: Array[Dictionary] = []
var first_id := ""
var second_id := ""

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 75000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("Ship real main scene visual deadline")
		quit(1)
	return false

func _water_fixture() -> TerrainData:
	# Explicit test geography and permission; this does not claim real water data.
	var data := Helper.build_flat_map(64, 52)
	# The shared helper generates resources before clearing its obstacle cache.
	# This explicit empty test geography must stay empty when indexes rebuild.
	data.resource_base.clear()
	data.spawn_cell = Vector2i(4, 4)
	data.site.player_cell = data.index(data.spawn_cell)
	data.site.manual.cell = data.site.player_cell
	data.site.worker.cell = data.index(Vector2i(4, 3))
	data.site.depot_cell = data.index(Vector2i(3, 4))
	data.surface_types.fill(Data.Surface.GRASS)
	var permissions: Array[int] = []
	for y in range(data.size.y):
		for x in range(20, data.size.x):
			var cell := Vector2i(x, y)
			# Two connected land piers. Each actual vessel departs before rotating.
			if y in [18, 38] and x <= 24: continue
			var i := data.index(cell)
			data.flags[i] = Data.Flag.BLOCKED | Data.Flag.WET
			data.surface_types[i] = Data.Surface.WATER
			data.water_kind[i] = 1
			data.water_body[i] = 10
			permissions.append(i)
	data.parameters.navigable_water_version = 1
	data.parameters.navigable_water_cells = permissions
	Env.rebuild_indexes(data)
	Runtime.rebuild_terrain_edges(data)
	return data

func _require(condition: bool, message: String) -> bool:
	if condition: return true
	push_error("SHIP_VISUAL_FAIL: " + message)
	quit(1)
	return false

func _walk(index: int, goal: Vector2i) -> bool:
	var identity := people[index]
	var start := team.cells[index]
	# Query the existing terrain with the real people/vehicle blockers. Army's
	# tactical local-query budget is owned by its AI tick, not this setup loop.
	var route: Array[Vector2i] = team.data.path_between(start, goal, func(cell: Vector2i) -> bool:
		return team.blocks_cell(cell) or team._is_external_cell(cell, identity))
	var query := {"person_id": identity, "index": index, "start": [start.x, start.y], "goal": [goal.x, goal.y],
		"steps": route.size(), "outcome": "already_at_goal" if start == goal else ("route" if not route.is_empty() else "unreachable")}
	print("SHIP_VISUAL_SHORE_ROUTE " + JSON.stringify(query))
	if not _require(not route.is_empty() or start == goal, "Original terrain needs a legal pier route: " + str(query)): return false
	if not _require(route.size() <= 256, "Original route exceeds the finite fixture budget: " + str(query)): return false
	# TerrainData.path_between returns destination steps; the start is excluded.
	for next: Vector2i in route:
		if not _require(not team._formation_step_units.has(index) and not team._combat_batch_members.has(identity), "Fixture walker belongs to an unfinished original movement batch: " + str(query)): return false
		var accepted := team._reserve_combat_step(index, next)
		if not _require(accepted, "Original reservation rejected the next shore step: " + str({"person_id": identity,
			"from": team.cells[index], "next": next, "goal": goal, "terrain_step": team.data.can_step(team.cells[index], next),
			"occupied": team.blocks_cell(next), "external": team._is_external_cell(next, identity),
			"moving_to": team.moving_to[index], "pose": team.combat_hot_get(index, &"pose")})): return false
		team.prepare_combat(float(team.move_duration[index]) + 0.01)
		if not _require(team.cells[index] == next and team.moving_to[index] == TerrainArmy.INVALID_CELL, "Original non-batch shore step did not commit: " + str({"person_id": identity, "cell": team.cells[index], "next": next, "moving_to": team.moving_to[index], "goal": goal})): return false
		if not _require(Time.get_ticks_msec() < deadline, "Original shore walking exceeded the deadline"): return false
	return true

func _finish_job(identity: int) -> bool:
	var actions: SitePersonActions = lab.site_controller.person_actions
	if not _require(actions.is_busy(identity), "Expected original ship job is absent"): return false
	var job: Dictionary = actions._jobs[str(identity)]
	actions.advance_ship_jobs(maxf(0.01, float(job.duration) - float(job.elapsed) + 0.01))
	actions.settle_after_contacts()
	return _require(not actions.is_busy(identity), "Original ship job must commit before capture")

func _board(index: int, vehicle_id: String, berth: int, shore: Vector2i) -> bool:
	if not _walk(index, shore): return false
	var result: Dictionary = lab.site_controller.person_actions.begin_ship_board(people[index], vehicle_id, people[index], berth, true)
	if not _require(result.ok, str(result)): return false
	if not _finish_job(people[index]): return false
	return _require(str(team.combat_units[index].embarked_vehicle_id) == vehicle_id and int(team.combat_units[index].berth_id) == berth and not team._cell_owners.values().has(index), "Original boarding relation or released shore claim differs")

func _focus(boat: Dictionary, zoom: float = 1.65) -> void:
	lab.camera.zoom = Vector2.ONE * zoom
	lab.camera.position = lab.site_controller.vehicles.ship_local_ground(boat, Vector2(0.5, 1.5))
	lab.camera.reset_smoothing()
	lab.camera.force_update_scroll()

func _fleet_focus() -> void:
	lab.camera.zoom = Vector2.ONE * 0.5
	lab.camera.position = (Vector2(25.5, 26.5) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	lab.camera.reset_smoothing()
	lab.camera.force_update_scroll()

func _capture(name_value: String, details: Dictionary = {}) -> bool:
	for army: TerrainArmy in lab.combat_armies: army.advance_frame(0.0)
	lab.site_controller.view.refresh()
	lab.site_controller.vehicle_view.refresh()
	for _frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	if not _require(team.combat_units.size() == 21 and team._sprites.size() == 21, "Capture must retain all 21 original people and sprites"): return false
	var textured := 0
	for index in range(people.size()):
		if not _require(team.combat_identity(index) == people[index], "Capture changed an original person identity"): return false
		if not _require(is_same(team.combat_units[index].item_state, original_holders[index]), "Ship operations must keep the original person holder"): return false
		if float(team.combat_hot_get(index, &"hp")) > 0.0:
			if not _require(team.combat_units[index].item_state.item_ids == original_items[index], "Living passengers keep their actual original equipment IDs"): return false
		var sprite: Sprite2D = team._sprites[index]
		if sprite != null and sprite.texture != null: textured += 1
	if not _require(textured > 0, "Original Army texture presentation must be present"): return false
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	for vehicle_id: String in [first_id, second_id]:
		var node: Node2D = lab.site_controller.vehicle_view._ship_nodes.get(vehicle_id)
		if not _require(node != null and node.has_meta("ship_debug_geometry") and node.get_node("Hull") is Polygon2D, "Capture requires both actual original boat presenters"): return false
		var hull: Polygon2D = node.get_node("Hull")
		if not _require(hull.is_visible_in_tree() and node.z_index > 0 and hull.polygon.size() >= 3,
			"Original boat hull must be visible above terrain: " + str({"vehicle_id": vehicle_id, "visible": hull.is_visible_in_tree(), "z_index": node.z_index, "points": hull.polygon.size()})): return false
	var picture := root.get_texture().get_image()
	if not _require(not picture.is_empty() and picture.save_png(OUT + "/" + name_value + ".png") == OK, "GPU screenshot could not be saved: " + name_value): return false
	details.merge({"file": name_value + ".png", "original_army_ids": people.duplicate(),
		"original_textured_sprites": textured, "fleet": [
			{"id": first_id, "alive_people": vehicles.ship_people(vehicles.records()[first_id]).size(), "load": vehicles.ship_load(first_id)},
			{"id": second_id, "alive_people": vehicles.ship_people(vehicles.records()[second_id]).size(), "load": vehicles.ship_load(second_id)}]}, true)
	captures.append(details)
	return _require(Time.get_ticks_msec() < deadline, "GPU capture exceeded the deadline")

func _contact_sheet() -> bool:
	# Standard contact sheet of original screenshots: resize and tile only.
	var sheet := Image.create(1800, 1101, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("20262e"))
	for index in range(captures.size()):
		var picture := Image.load_from_file(OUT + "/" + str(captures[index].file))
		if not _require(not picture.is_empty(), "Contact sheet source screenshot is missing"): return false
		picture.convert(Image.FORMAT_RGBA8)
		picture.resize(600, 367, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(picture, Rect2i(0, 0, 600, 367), Vector2i((index % 3) * 600, floori(float(index) / 3.0) * 367))
	return _require(sheet.save_png(OUT + "/contact_sheet.png") == OK, "Contact sheet could not be saved")

func _run() -> void:
	if not _require(DisplayServer.get_name() != "headless", "This entrypoint requires the GPU viewport"): return
	if not _require(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/terrain_lab/TerrainLab.tscn", "Fixture requires the original TerrainLab main scene"): return
	if not _require(DirAccess.make_dir_recursive_absolute(OUT) == OK, "Visual output directory could not be created"): return
	root.size = Vector2i(1800, 1100)
	root.content_scale_size = root.size
	root.gui_embed_subwindows = true
	var main: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	lab = main.instantiate()
	lab.npc = TerrainTestNPC.new() # Original optional NPC, with its real visual initializer.
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	if lab.npc.editor == null: lab.npc.initialize_visual()
	if not _require(lab.character.editor != null and lab.npc.editor != null, "Original player and NPC model initialization is required"): return
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	lab.site_controller._auto_save_blocked = true
	var data := _water_fixture()
	lab.bind_terrain(data)
	if not _require(lab.terrain == data, "Original main scene rejected the explicit test Site"): return
	var ui: SiteController = lab.site_controller
	ui._auto_save_blocked = true
	ui.release_worker()
	ui.hide_tool_windows()
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for army: TerrainArmy in lab.combat_armies: army.set_process(false)
	team = lab.army
	team.role = "logistics"
	team.team_id = lab._next_army_identity()
	team.roster_size = 21
	var cells: Array[Vector2i] = [Vector2i(24, 18)]
	for y in range(19, 28): cells.append(Vector2i(18, y))
	cells.append(Vector2i(24, 38))
	for y in range(39, 48): cells.append(Vector2i(18, y))
	cells.append(Vector2i(17, 16))
	if not _require(cells.size() == 21 and team.roster_size == 21 and not team.has_army(), "Original deployment requires exactly 21 people and an empty original Army"): return
	var used := {}
	for cell: Vector2i in cells:
		var blocked: bool = team.external_blocker.is_valid() and bool(team.external_blocker.call(cell))
		var occupied: bool = lab.character.occupies_cell(cell) or lab.npc.occupies_cell(cell)
		if not _require(data.is_walkable(cell) and not used.has(cell) and not blocked and not occupied,
			"Original deployment cell rejected: " + str({"cell": cell, "walkable": data.is_walkable(cell),
			"static_blocked": int(data.static_blocked[data.index(cell)]), "resources": data.resources_at.get(data.index(cell), []),
			"other_army": blocked, "actor": occupied, "duplicate": used.has(cell)})): return
		used[cell] = true
	if not _require(team.deploy_at(data, lab.character, lab.npc, cells), "Original deploy_at rejected 21 preflighted cells"): return
	if not _require(TerrainArmy.load_combat_bake(), "Original Army combat atlas could not be loaded"): return
	if not _require(team.enable_combat(false, 0), "Original combat enable rejected deployed people: " + str({"has_army": team.has_army(), "moving": team.moving_count(), "command": team.command, "exchange": team.exchange_enabled, "allocator": team.person_id_allocator.is_valid()})): return
	data.site.army_next_team = team.team_id + 1
	data.site.army_trial_active = true
	for index in range(team.combat_units.size()):
		people.append(team.combat_identity(index))
		team.combat_units[index].logistics = true
		original_holders.append(team.combat_units[index].item_state)
		original_items.append(team.combat_units[index].item_state.item_ids.duplicate())
	var vehicles: SiteVehicleTransport = ui.vehicles
	var first: Dictionary = vehicles.deploy_ship(team, "ferry", Vector2i(25, 18), Vector2i.UP, true)
	var second: Dictionary = vehicles.deploy_ship(team, "ferry", Vector2i(25, 38), Vector2i.UP, true)
	if not _require(first.ok and second.ok, "Original two-boat deployment failed: " + str([first, second])): return
	first_id = str(first.vehicle_id)
	second_id = str(second.vehicle_id)
	var boat: Dictionary = vehicles.records()[first_id]
	for index in range(10):
		if not _board(index, first_id, index, Vector2i(24, 18)): return
	for index in range(10, 20):
		if not _board(index, second_id, index - 10, Vector2i(24, 38)): return
	if not _require(vehicles.ship_people(boat).size() == 10 and vehicles.ship_people(vehicles.records()[second_id]).size() == 10, "Both boats must carry ten original passengers"): return
	if not _require(not vehicles.is_embarked(people[20]) and team.combat_units.size() == 21, "The twenty-first original person must remain ashore"): return
	var helm: Dictionary = ui.person_actions.begin_ship_helm(people[0], first_id, people[0], true)
	if not _require(helm.ok, "Original initial helm job failed: " + str(helm)): return
	if not _finish_job(people[0]): return
	if not _require(int(boat.operator_id) == people[0], "Original initial helm job did not appoint its original person"): return
	_fleet_focus()
	if not await _capture("01_two_boats_twenty_original_passengers", {"shore_person": people[20]}): return
	# Real original movement takes this vessel away from its pier before rotation.
	for _step in range(6):
		var ordered: Dictionary = vehicles.ship_order(first_id, "forward", TerrainArmy.INVALID_CELL, people[0], true)
		if not _require(ordered.ok, "Original forward departure failed: " + str(ordered)): return
		vehicles.update_ships(float(boat.move.duration) + 0.01)
	if not _require(data.cell_from_index(int(boat.cell)) == Vector2i(25, 12), "Original boat departure did not reach the turn anchor"): return
	var rotation_anchor := int(boat.cell)
	for quarter in range(4):
		if quarter > 0:
			var turned: Dictionary = vehicles.ship_order(first_id, "turn_right", TerrainArmy.INVALID_CELL, people[0], true)
			if not _require(turned.ok, "Original quarter turn failed: " + str(turned)): return
			vehicles.update_ships(float(boat.move.duration) + 0.01)
		if not _require(int(boat.cell) == rotation_anchor and boat.move.is_empty(), "Quarter turn must keep the actual boat anchor"): return
		_focus(boat)
		if not await _capture("02_facing_q%d" % quarter, {"facing": boat.facing.duplicate(), "turn_anchor": rotation_anchor}): return
	var load_before := vehicles.ship_load(first_id)
	var forward: Dictionary = vehicles.ship_order(first_id, "forward", TerrainArmy.INVALID_CELL, people[0], true)
	if not _require(forward.ok, "Original half-step move failed: " + str(forward)): return
	var target_cell := int(boat.move.cell)
	var duration := float(boat.move.duration)
	vehicles.update_ships(duration * 0.5)
	var stopped: Dictionary = vehicles.ship_order(first_id, "stop", TerrainArmy.INVALID_CELL, people[0], true)
	if not _require(stopped.ok, "Original half-step stop request failed: " + str(stopped)): return
	if not _require(bool(boat.stop_pending) and not boat.move.is_empty(), "Stop must retain the committed original half-step"): return
	_focus(boat)
	if not await _capture("03_committed_half_step_stop", {"progress": vehicles.ship_render_pose(boat).progress, "stop_pending": true}): return
	vehicles.update_ships(duration)
	if not _require(boat.move.is_empty() and int(boat.cell) == target_cell and boat.command.is_empty(), "Original committed step must finish before stop"): return
	team.apply_unit_contact(0, {"result": {"hp": 10000.0, "stun": 0.0, "guard_break": false}, "shield": false})
	if not _require(vehicles.ship_people(boat).size() == 9 and is_equal_approx(vehicles.ship_load(first_id), load_before), "Original death must release N while keeping pending goods in Q"): return
	ui.settle_person_deaths(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"]) + 0.5)
	if not _require(team.combat_units[0].get("ship_death_settled", false) == true and not vehicles.is_embarked(people[0]), "Original ship death transfer did not settle and release the berth"): return
	if not _require(is_equal_approx(vehicles.ship_load(first_id), load_before), "Original death transfer must conserve Q"): return
	vehicles.update_ships(0.01) # Original stopped operator cleanup precedes replacement.
	if not _require(int(boat.operator_id) == 0, "Stopped boat must release the original dead operator"): return
	var remains_id := str(team.combat_units[0].remains_id)
	if not _require(data.site.ground_loot.has(remains_id), "Original equipped person's death must retain its actual goods container"): return
	var remains: Dictionary = data.site.ground_loot[remains_id]
	if not _require(str(remains.vehicle_id) == first_id and not remains.has("cell") and not remains.item_ids.is_empty(), "Original ground loot must retain goods at the actual boat location"): return
	_focus(boat)
	if not await _capture("04_death_releases_person_keeps_goods", {"dead_original_id": people[0], "remains_id": remains_id, "conserved_load": load_before}): return
	if not _require(ui.vehicle_view._ship_loot_nodes.has(remains_id), "Original ship goods presenter must be present"): return
	var replacement: Dictionary = ui.person_actions.begin_ship_helm(people[8], first_id, people[8], true)
	if not _require(replacement.ok, "Original replacement helm job failed: " + str(replacement)): return
	var job: Dictionary = ui.person_actions._jobs[str(people[8])]
	var starting_ground := vehicles.ship_person_ground(people[8])
	ui.person_actions.advance_ship_jobs(float(job.duration) * 0.5)
	var walking_ground := vehicles.ship_person_ground(people[8])
	if not _require(not walking_ground.is_equal_approx(starting_ground) and int(boat.operator_id) == 0, "Original replacement must actually walk before taking helm"): return
	if not _require(team.combat_ground(8).is_equal_approx(walking_ground) and ui.person_actions.save_guard().code == "BUSY", "Original Army ground and transient job save guard must follow the helm walk"): return
	if not await _capture("05_original_passenger_walks_to_helm", {"walking_original_id": people[8], "job_progress": float(job.elapsed) / float(job.duration)}): return
	if not _finish_job(people[8]): return
	if not _require(int(team.combat_units[8].berth_id) == 0 and int(boat.operator_id) == people[8], "Actual replacement walk must commit the original person to helm"): return
	if not _require(vehicles.ship_people(boat).size() == 9 and is_equal_approx(vehicles.ship_load(first_id), load_before), "Helm replacement must preserve N and Q"): return
	if not await _capture("06_original_passenger_takes_helm", {"operator_id": people[8], "conserved_load": load_before}): return
	if not _require(captures.size() == 9, "All nine original GPU captures are required"): return
	if not _contact_sheet(): return
	var report := FileAccess.open(OUT + "/captures.json", FileAccess.WRITE)
	if not _require(report != null, "GPU capture report could not be created"): return
	report.store_string(JSON.stringify({"status": "SITE_SHIP_VISUAL_PASS", "captures": captures,
		"contact_sheet": "contact_sheet.png", "scope": "Nine GPU screenshots of the real main scene, two actual ferry records, 21 unchanged original Army identities/holders, real shore reservation and boarding jobs, four legal hull orientations, committed half-step stop, original death transfer with N released and Q conserved, and actual helm path progress/commit. Terrain and water permission are explicit fixtures. Original grey hull/loot and original person presentation only; no substitute body, renderer or inventory. No gameplay performance, final art approval or real geographic navigation claim."}, "\t"))
	report.close()
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE_SHIP_VISUAL_PASS: nine real main-scene GPU captures, original 21-person fleet, real movement/helm/death owners and screenshot contact sheet")
	quit(0)
