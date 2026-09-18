extends SceneTree
## Formal unchanged map, original controls and original Lab clock only.
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const OUT := "res://output/npc_ai_acceptance_20260918/work"
var lab: TerrainLab
var ui: SiteController
var deadline := 0
var deliveries := {}
var cargo_seen := {}
var last_cargo := {}
var steps := {}
var frames := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 110000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("WORK_AI_MAIN deadline")
		quit(1)
	return false

func _press(name: String) -> void:
	var button := lab.find_child(name, true, false) as Button
	assert(button != null, "Original control missing: " + name)
	button.pressed.emit()

func _role(prefix: String, value: int) -> void:
	ui.trial_roles[prefix].select(value)
	ui.trial_roles[prefix].item_selected.emit(value)

func _zone(key: String, mode: int = 2) -> void:
	var source := Env.resource(lab.terrain, key)
	var cell := lab.terrain.cell_from_index(int(source.cell))
	ui.modes.select(mode)
	ui.kinds.select(int(source.kind) + 1)
	var before: int = lab.terrain.site.zones.size()
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = lab.renderer.get_global_transform_with_canvas() * lab.renderer.cell_center(cell)
		assert(ui.handle_input(event))
	assert(lab.terrain.site.zones.size() == before + 1, "The original drag handler must create the work zone")
	# Zone drawing enables the original camp worker as well. Stop that worker
	# through its original control so depot attribution is only these Army IDs.
	_press("StopWorker")
	ui.update_ui()

func _disable_zones() -> void:
	ui.update_ui()
	for toggle: CheckButton in ui.zones.get_children():
		toggle.button_pressed = false
	for zone: Dictionary in lab.terrain.site.zones: assert(not zone.active)

func _tick() -> void:
	var inventory_before := Runtime.inventory_size(lab.terrain.site.inventory)
	lab._process(0.05)
	frames += 1
	for index in range(1, lab.army.combat_units.size()):
		var row: Dictionary = lab.army.combat_units[index]
		var identity := int(row.person_id)
		var cargo := Runtime.inventory_size(row.cargo)
		if cargo > 0: cargo_seen[identity] = true
		if int(last_cargo.get(identity, 0)) > 0 and cargo == 0:
			assert(Runtime.inventory_size(lab.terrain.site.inventory) > inventory_before, "Cargo disappearance must be an actual depot deposit")
			deliveries[identity] = int(deliveries.get(identity, 0)) + 1
		last_cargo[identity] = cargo
		if lab.army.moving_to[index] != TerrainArmy.INVALID_CELL: steps[identity] = true

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for team: TerrainArmy in lab.combat_armies: team.advance_frame(0.0)
	ui.vehicle_view.refresh()
	ui.update_ui()
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUT + "/" + name + ".png") == OK)

func _sources(kind: int, amount: int) -> Array[String]:
	var result: Array[String] = []
	var keys := lab.terrain.resource_base.keys()
	var origin := lab.army.cells[1]
	keys.sort_custom(func(a: String, b: String) -> bool:
		return lab.terrain.cell_from_index(int(lab.terrain.resource_base[a].cell)).distance_squared_to(origin) < lab.terrain.cell_from_index(int(lab.terrain.resource_base[b].cell)).distance_squared_to(origin))
	var threats := {}
	var blocked := func(cell: Vector2i) -> bool:
		return ui.work_team._occupied(cell, lab.army, 1) or lab._fatigue_threat(cell, lab.army.faction_id, lab.army, 1, threats)
	var depot := lab.terrain.cell_from_index(int(lab.terrain.site.depot_cell))
	var unloading: Array[Vector2i] = [depot]
	for direction: Vector2i in TerrainData.DIRECTIONS: unloading.append(depot + direction)
	var started := Time.get_ticks_msec()
	for key: String in keys:
		if Time.get_ticks_msec() - started > 8000: break
		var source := Env.resource(lab.terrain, key)
		if int(source.kind) != kind or int(source.remaining) < int(Env.BATCH[kind]) * 3: continue
		var target := Runtime._reachable_work(lab.terrain, origin, Env.work_cells(lab.terrain, key), blocked)
		if target == TerrainArmy.INVALID_CELL: continue
		var route := lab.terrain.path_between(origin, target, blocked)
		if route.size() > 24: continue
		if Runtime._reachable_work(lab.terrain, target, unloading, blocked) == TerrainArmy.INVALID_CELL: continue
		result.append(key)
		if result.size() == amount: break
	return result

func _run() -> void:
	assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
	assert(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/terrain_lab/TerrainLab.tscn")
	root.size = Vector2i(1800, 1100)
	root.content_scale_size = root.size
	root.gui_embed_subwindows = true
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	lab = packed.instantiate()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	ui = lab.site_controller
	ui._auto_save_blocked = true
	assert(lab.npc.faction_id == lab.character.faction_id)
	_press("StopWorker")
	_role("friendly", 1)
	_role("enemy", 0)
	ui.trial_friendly_count.value = 4
	ui.trial_enemy_count.value = 1
	ui.trial_enemy_order.select(0)
	ui.trial_third_enabled.button_pressed = false
	_press("StartMeleeTrial")
	assert(lab.army.role == "work" and ui.work_team.active_ids().size() == 3, ui.message.text)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	_press("FasterSite")
	_press("FasterSite")
	assert(lab.simulation_speed == 4.0)
	var timber := _sources(Env.Kind.TIMBER, 3)
	assert(timber.size() == 3, "Unchanged map must provide three reachable timber sources")
	for key: String in timber: _zone(key)
	var stock_before: Dictionary = lab.terrain.site.inventory.duplicate(true)
	var produced_before := int(lab.terrain.site.total_produced)
	for attempt in range(2400):
		_tick()
		var complete := true
		for index in range(1, 4): complete = complete and int(deliveries.get(lab.army.combat_identity(index), 0)) >= 2
		if complete: break
		if attempt % 100 == 0: await process_frame
	print("WORK_AI_BATCHES ", deliveries, " frames=", frames, " tasks=", lab.army.combat_units.map(func(row: Dictionary) -> Variant: return row.get("work_task", {})))
	for index in range(1, 4):
		var identity := lab.army.combat_identity(index)
		assert(int(deliveries.get(identity, 0)) >= 2 and cargo_seen.has(identity) and steps.has(identity), "Every original worker must physically deliver at least two batches")
	assert(int(lab.terrain.site.inventory.get("wood", 0)) >= int(stock_before.get("wood", 0)) + 24)
	await _capture("work_multibatch")
	# Pause freezes original worker state, original clock, inventory and position.
	var frozen := JSON.stringify([lab.army.cells, lab.army.moving_to, lab.army.combat_units, lab.terrain.site.minute, lab.terrain.site.phase, lab.terrain.site.inventory])
	_press("PauseSite")
	lab._process(1.0)
	assert(frozen == JSON.stringify([lab.army.cells, lab.army.moving_to, lab.army.combat_units, lab.terrain.site.minute, lab.terrain.site.phase, lab.terrain.site.inventory]))
	_press("PauseSite")
	# Stop every original zone while a real row is en route/working. No new
	# source material may be extracted after the actual checkbox command.
	var active_source := false
	for attempt in range(150):
		_tick()
		for row: Dictionary in lab.army.combat_units:
			active_source = active_source or str(row.get("work_task", {}).get("target", "")) in timber
		if active_source: break
	assert(active_source)
	_disable_zones()
	_tick()
	for row: Dictionary in lab.army.combat_units:
		assert(str(row.get("work_task", {}).get("target", "")) not in timber, "Disabling a zone must release the Army worker's original source task")
	var stopped_production := int(lab.terrain.site.total_produced)
	for attempt in range(140): _tick()
	assert(int(lab.terrain.site.total_produced) == stopped_production)
	# A different resource through the same map drag controls, not injected stock.
	var herbs := _sources(Env.Kind.HERB, 1)
	assert(herbs.size() == 1, "Unchanged map must provide a reachable second resource type")
	_zone(herbs[0])
	var herb_item := str(Env.ITEMS[Env.Kind.HERB])
	var herb_before := int(lab.terrain.site.inventory.get(herb_item, 0))
	for attempt in range(1000):
		_tick()
		if int(lab.terrain.site.inventory.get(herb_item, 0)) > herb_before: break
		if attempt % 100 == 0: await process_frame
	assert(int(lab.terrain.site.inventory.get(herb_item, 0)) > herb_before, "Changed work area/resource must actually deliver the new output")
	# Clear the same real vegetation via the original clear-zone UI.
	_disable_zones()
	_zone(herbs[0], 3)
	for attempt in range(3000):
		_tick()
		if bool(Env.resource(lab.terrain, herbs[0]).cleared): break
		if attempt % 200 == 0:
			print("WORK_AI_CLEAR ", attempt, " source=", Env.resource(lab.terrain, herbs[0]), " tasks=", lab.army.combat_units.map(func(row: Dictionary) -> Variant: return row.get("work_task", {})))
			await process_frame
	assert(bool(Env.resource(lab.terrain, herbs[0]).cleared), "Original clear command must finish and mark the actual source")
	_disable_zones()
	# Explicit team movement owns the original workers while marching; HOLD
	# restores their original assignment rather than duplicating work people.
	for attempt in range(100): _tick()
	var before_move := lab.army.cells.duplicate()
	var move_goal := TerrainArmy.INVALID_CELL
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var displacement := direction * 2
		var valid := true
		for index in range(lab.army.cells.size()):
			var goal: Vector2i = lab.army.cells[index] + displacement
			valid = valid and lab.terrain.is_walkable(goal) and not ui.work_team._occupied(goal, lab.army, index)
			if valid: valid = not lab.terrain.path_between(lab.army.cells[index], goal, func(cell: Vector2i) -> bool: return ui.work_team._occupied(cell, lab.army, index)).is_empty()
		if valid:
			move_goal = Vector2i(lab.army.command_reference.floor()) + displacement
			break
	assert(move_goal != TerrainArmy.INVALID_CELL, "Original workers need a nearby legal MOVE destination")
	ui.trial_command_team.select(0)
	ui.select_cell(move_goal)
	_press("TrialTeamMove")
	assert(lab.army.combat_order == TerrainArmy.CombatOrder.MOVE)
	_tick()
	for index in range(1, 4): assert(lab.army.combat_units[index].work_task.mode == "paused")
	var move_produced := int(lab.terrain.site.total_produced)
	for attempt in range(300):
		_tick()
		if lab.army.combat_order == TerrainArmy.CombatOrder.HOLD: break
	assert(lab.army.combat_order == TerrainArmy.CombatOrder.HOLD and "到達" in lab.army.command_status, "MOVE must actually arrive rather than report blocked as success: " + lab.army.command_status)
	for index in range(4): assert(lab.army.cells[index] != before_move[index])
	assert(int(lab.terrain.site.total_produced) == move_produced)
	_press("TrialTeamHold")
	assert(ui.work_team.active_ids().size() == 3)
	for index in range(1, 4): assert(lab.army.combat_units[index].cargo.is_empty(), "Every produced batch must finish unloading")
	var wood_gain := int(lab.terrain.site.inventory.get("wood", 0)) - int(stock_before.get("wood", 0))
	var herb_gain := int(lab.terrain.site.inventory.get(herb_item, 0)) - herb_before
	assert(wood_gain + herb_gain == int(lab.terrain.site.total_produced) - produced_before, "Produced material must exactly equal real depot gain, without lost/phantom cargo")
	await _capture("work_complete")
	var report := {"main_scene": ProjectSettings.get_setting("application/run/main_scene"), "workers": 3, "minimum_batches_per_worker": 2,
		"deliveries": deliveries, "timber_sources": timber, "herb_source": herbs[0], "wood_depot_gain": wood_gain, "herb_depot_gain": herb_gain,
		"cleared_source": bool(Env.resource(lab.terrain, herbs[0]).cleared), "pause_frozen": true, "disabled_zone_stopped": true, "team_move_arrived": true, "hold_preserved_work_ids": true,
		"produced_gain": int(lab.terrain.site.total_produced) - produced_before, "simulation_seconds": frames * 0.05, "speed": lab.simulation_speed,
		"no_terrain_resource_or_person_patch": true}
	var output := FileAccess.open(OUT + ("/main_result.json" if DisplayServer.get_name() == "headless" else "/main_visual_result.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	print("SITE_WORK_AI_MAIN_PASS ", JSON.stringify(report))
	lab.queue_free()
	await process_frame
	quit(0)
