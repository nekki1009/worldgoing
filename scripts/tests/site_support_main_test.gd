extends SceneTree
## Formal scene and actual test-menu deployment; no terrain/resource/people patching.
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const OUT := "res://output/site_support_teams_20260918/main"
var deadline := 0
var lab: TerrainLab
var visual := false

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 95000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("Support main-scene deadline")
		quit(1)
	return false

func _press(ui: SiteController, name: String) -> void:
	var button := ui.combat_window.find_child(name, true, false) as Button
	assert(button != null, name)
	button.pressed.emit()

func _role(ui: SiteController, prefix: String, value: int) -> void:
	ui.trial_roles[prefix].select(value)
	ui.trial_roles[prefix].item_selected.emit(value)

func _capture(name: String) -> void:
	if not visual: return
	for team: TerrainArmy in lab.combat_armies: team.advance_frame(0.0)
	lab.site_controller.vehicle_view.refresh()
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUT + "/" + name + ".png") == OK)

func _run() -> void:
	visual = DisplayServer.get_name() != "headless"
	assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
	assert(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/terrain_lab/TerrainLab.tscn")
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
	var ui: SiteController = lab.site_controller
	ui._auto_save_blocked = true
	assert(lab.npc.faction_id == lab.character.faction_id, "Original camp worker must not be an invisible hostile threat")
	ui.release_worker()
	_role(ui, "friendly", 1)
	_role(ui, "enemy", 2)
	ui.trial_friendly_count.value = 4
	ui.trial_enemy_count.value = 4
	ui.trial_carts.enemy.value = 1
	ui.trial_wagons.enemy.value = 1
	ui.trial_third_enabled.button_pressed = true
	ui.trial_third_count.value = 2
	ui.trial_third_faction.select(0)
	ui.trial_third_order.select(0)
	_press(ui, "StartMeleeTrial")
	assert(lab.army.role == "work" and lab.opposing_army.role == "logistics" and lab.third_army.role == "combat", ui.message.text)
	assert(ui.vehicles.records().size() == 2 and ui.work_team.active_ids().size() == 3)
	var open_depot_approaches := 0
	var deployment_threats := {}
	for cell: Vector2i in lab._trial_camp_access():
		assert(not ui.vehicles.blocks_cell(cell), "Automatic vehicles must leave original depot approaches open")
		for team: TerrainArmy in lab.combat_armies:
			assert(not team.cells.has(cell), "Automatic support configuration must not fill original depot approaches")
		if not ui.reserves_cell(cell) and not lab._fatigue_threat(cell, lab.army.faction_id, lab.army, 1, deployment_threats):
			open_depot_approaches += 1
	assert(open_depot_approaches > 0, "At least one safe original unloading approach must remain usable")
	for team: TerrainArmy in lab.combat_armies:
		team.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors:
		actor.set_process(false)
	ui._refresh_vehicle_controls()
	assert(ui.vehicle_choice.item_count == 2)
	print("SUPPORT_MAIN_DEPLOY ", ui.message.text)
	await _capture("three_roles")
	ui._open_combat_window()
	await _capture("menu_roles")
	var control := ui.combat_window.find_child("TrialVehicleControls", true, false) as Control
	var parent: Node = control.get_parent()
	while parent != null and not parent is ScrollContainer: parent = parent.get_parent()
	var scroll := parent as ScrollContainer
	assert(scroll != null)
	scroll.ensure_control_visible(control)
	await _capture("menu_vehicles")
	ui.combat_window.hide()
	# Choose an existing generated non-food source near the original work team.
	var keys := lab.terrain.resource_base.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		var ac := lab.terrain.cell_from_index(int(Env.resource(lab.terrain, a).cell))
		var bc := lab.terrain.cell_from_index(int(Env.resource(lab.terrain, b).cell))
		return ac.distance_squared_to(lab.army.cells[1]) < bc.distance_squared_to(lab.army.cells[1]))
	var source := ""
	var source_route: Array[Vector2i] = []
	var threats := {}
	var occupied := func(cell: Vector2i) -> bool:
		return ui.work_team._occupied(cell, lab.army, 1) or lab._fatigue_threat(cell, lab.army.faction_id, lab.army, 1, threats)
	var depot := lab.terrain.cell_from_index(int(lab.terrain.site.depot_cell))
	var depot_cells: Array[Vector2i] = [depot]
	for direction: Vector2i in TerrainData.DIRECTIONS: depot_cells.append(depot + direction)
	print("SUPPORT_CAMP ", {"work": lab.army.cells, "logistics": lab.opposing_army.cells, "third": lab.third_army.cells, "depot": depot})
	for cell: Vector2i in depot_cells:
		print("SUPPORT_DEPOT_OPTION ", cell, " occupied=", occupied.call(cell), " threat=", lab._fatigue_threat(cell, lab.army.faction_id, lab.army, 1, threats), " access=", cell == depot or lab.terrain.can_step(cell, depot))
	var search_started := Time.get_ticks_msec()
	for key: String in keys:
		if Time.get_ticks_msec() - search_started > 10000: break
		var resource := Env.resource(lab.terrain, key)
		if int(resource.kind) not in [Env.Kind.TIMBER, Env.Kind.HERB, Env.Kind.STONE] or int(resource.remaining) < int(Env.BATCH[int(resource.kind)]): continue
		var cell := Runtime._reachable_work(lab.terrain, lab.army.cells[1], Env.work_cells(lab.terrain, key), occupied)
		if cell == TerrainArmy.INVALID_CELL: continue
		var route := lab.terrain.path_between(lab.army.cells[1], cell, occupied)
		var safe := not lab._fatigue_threat(cell, lab.army.faction_id, lab.army, 1, threats)
		for step: Vector2i in route:
			safe = safe and not lab._fatigue_threat(step, lab.army.faction_id, lab.army, 1, threats)
		var return_cell := Runtime._reachable_work(lab.terrain, cell, depot_cells, occupied)
		if return_cell == TerrainArmy.INVALID_CELL: continue
		for step: Vector2i in lab.terrain.path_between(cell, return_cell, occupied):
			safe = safe and not lab._fatigue_threat(step, lab.army.faction_id, lab.army, 1, threats)
		if safe:
			source = key
			source_route = route
			break
	print("SUPPORT_SOURCE ", {"team": lab.army.cells, "logistics": lab.opposing_army.cells, "third": lab.third_army.cells, "depot": depot, "source": source, "route": source_route})
	if source.is_empty():
		push_error("Bounded original-map search found no safe reachable supplies for original worker")
		quit(1)
		return
	# This real main-scene case has safe endpoints but a dangerous shortest
	# return route. The existing pathfinder must take a longer safe route.
	var source_work_cell: Vector2i = source_route.back() if not source_route.is_empty() else lab.army.cells[1]
	var depot_goal := Runtime._reachable_work(lab.terrain, source_work_cell, depot_cells, occupied)
	var raw_occupied := func(cell: Vector2i) -> bool: return ui.work_team._occupied(cell, lab.army, 1)
	var direct_route := lab.terrain.path_between(source_work_cell, depot_goal, raw_occupied)
	var safe_route := lab.terrain.path_between(source_work_cell, depot_goal, occupied)
	var direct_threat := false
	for cell: Vector2i in direct_route:
		direct_threat = direct_threat or lab._fatigue_threat(cell, lab.army.faction_id, lab.army, 1, threats)
	assert(not lab._fatigue_threat(source_work_cell, lab.army.faction_id, lab.army, 1, threats) and not lab._fatigue_threat(depot_goal, lab.army.faction_id, lab.army, 1, threats))
	assert(direct_threat and safe_route.size() > direct_route.size(), "Regression must expose unsafe middle cells between safe source/depot endpoints")
	for cell: Vector2i in safe_route:
		assert(not lab._fatigue_threat(cell, lab.army.faction_id, lab.army, 1, threats))
	var resource := Env.resource(lab.terrain, source)
	var source_cell := lab.terrain.cell_from_index(int(resource.cell))
	assert(Runtime.add_zone(lab.terrain, Rect2i(source_cell, Vector2i.ONE), int(resource.kind)).ok)
	var item := str(Env.ITEMS[int(resource.kind)])
	var inventory_before := int(lab.terrain.site.inventory.get(item, 0))
	var produced_before := int(lab.terrain.site.total_produced)
	var remaining_before := int(resource.remaining)
	var observed_cargo := false
	var observed_steps := false
	var frames := 0
	while frames < 1800 and int(lab.terrain.site.inventory.get(item, 0)) <= inventory_before:
		lab._process(0.05)
		var step_threats := {}
		for index in range(1, lab.army.combat_units.size()):
			assert(not lab._fatigue_threat(lab.army.cells[index], lab.army.faction_id, lab.army, index, step_threats), "Original worker walked into a known hostile threat")
			observed_cargo = observed_cargo or int(lab.army.combat_units[index].cargo.get(item, 0)) > 0
			observed_steps = observed_steps or lab.army.moving_to[index] != TerrainArmy.INVALID_CELL
		frames += 1
		if frames % 100 == 0:
			print("SUPPORT_WORK ", frames, " ", lab.army.combat_units[1].work_task)
			await process_frame
	if not observed_cargo or not observed_steps or int(lab.terrain.site.inventory.get(item, 0)) <= inventory_before:
		push_error("Original work crew must harvest and physically deposit: " + str(lab.army.combat_units))
		quit(1)
		return
	assert(int(lab.terrain.site.total_produced) > produced_before and int(Env.resource(lab.terrain, source).remaining) < remaining_before)
	var report := {"main_scene": ProjectSettings.get_setting("application/run/main_scene"), "visual": visual,
		"roles": [lab.army.role, lab.opposing_army.role, lab.third_army.role], "people": 8, "vehicles": 2,
		"item": item, "source": source, "source_route_cells": source_route.size(), "source_before": remaining_before, "source_after": Env.resource(lab.terrain, source).remaining,
		"depot_gain": int(lab.terrain.site.inventory.get(item, 0)) - inventory_before, "original_steps": observed_steps,
		"original_cargo": observed_cargo, "simulation_seconds": frames * 0.05,
		"unsafe_direct_route_cells": direct_route.size(), "safe_detour_cells": safe_route.size(), "safe_depot_approaches": open_depot_approaches}
	ui.update_ui()
	await _capture("work_deposited")
	var file := FileAccess.open(OUT + ("/visual_result.json" if visual else "/headless_result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SITE_SUPPORT_MAIN_PASS ", JSON.stringify(report))
	lab.queue_free()
	await process_frame
	quit(0)
