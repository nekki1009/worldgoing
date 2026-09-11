class_name TerrainLab
extends Node2D

const MIN_ZOOM := 0.1
const MAX_ZOOM := 10.0
const ZOOM_STEP := 1.20
const Site = preload("res://scripts/terrain_lab/site_controller.gd")
const SiteEnv = preload("res://scripts/terrain_lab/site_environment.gd")
var site_controller: Node
var pause_when_unfocused := true

var terrain: TerrainData
var renderer: TerrainRenderer
var character: TerrainTestCharacter
var npc: TerrainTestNPC
var army: TerrainArmy
var camera: Camera2D
var preset_dropdown: OptionButton
var seed_input: LineEdit
var generate_button: Button
var debug_toggle: CheckButton
var movement_toggle: CheckButton
var npc_command_dropdown: OptionButton
var npc_command_button: Button
var info: Label
var parameters_label: Label
var status: Label
var generation_ms: float = 0.0
var _dragging: bool = false
var _info_time: float = 0.0
var _held_directions: Dictionary = {}
var _last_direction_key: int = -1
var _move_cooldown: float = 0.0
var _run_held: bool = false
var _npc_target_pending := false
var npc_retaliates := false
var combat_info: Label
var army_info: Label
var deploy_army_button: Button
var follow_army_button: Button
var edge_army_button: Button
var clear_army_button: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RenderingServer.set_default_clear_color(Color("1d242b"))
	renderer = TerrainRenderer.new()
	renderer.name = "TerrainRenderer"
	add_child(renderer)
	character = TerrainTestCharacter.new()
	character.name = "MovementTestCharacter"
	character.process_mode = Node.PROCESS_MODE_PAUSABLE
	character.z_index = 10
	add_child(character)
	character.initialize_visual()
	npc = TerrainTestNPC.new()
	npc.name = "CommandTestNPC"
	npc.process_mode = Node.PROCESS_MODE_PAUSABLE
	npc.z_index = 11
	add_child(npc)
	npc.initialize_visual()
	character.opponent = npc
	npc.opponent = character
	army = TerrainArmy.new()
	army.name = "DemoArmy"
	army.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(army)
	army.player = character
	army.npc = npc
	character.cell_blocker = Callable(army, "blocks_cell")
	npc.cell_blocker = Callable(army, "blocks_cell")
	camera = Camera2D.new()
	camera.name = "LabCamera"
	add_child(camera)
	_build_ui()
	site_controller = Site.new()
	site_controller.name = "SiteController"
	add_child(site_controller)
	site_controller.setup(self)
	generate_from_ui()
	if FileAccess.file_exists(site_controller.save_path):
		site_controller.load_current()
	site_controller.focus_camp()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED] and pause_when_unfocused:
		if site_controller != null and terrain != null and not terrain.site.is_empty() and not site_controller._exit_pending and not bool(terrain.site.paused):
			site_controller.toggle_pause()
			site_controller.message.text = "離開遊玩視窗，時間已暫停；按「繼續」恢復。"

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "TerrainLabUI"
	add_child(ui)
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 20)
	panel.size = Vector2(450, get_viewport_rect().size.y - 40)
	var background := StyleBoxFlat.new()
	background.bg_color = Color("20272f")
	panel.add_theme_stylebox_override("panel", background)
	ui.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.add_theme_font_size_override("font_size", 22)
	margin.add_child(column)
	_label(column, "TERRAIN GENERATOR LAB", 25)
	_label(column, "100 x 100 cells | 64 px per cell\nStandalone terrain / no world integration", 18)
	preset_dropdown = OptionButton.new()
	preset_dropdown.add_theme_font_size_override("font_size", 22)
	for preset_name: String in TerrainPreset.NAMES:
		preset_dropdown.add_item(preset_name)
	preset_dropdown.select(TerrainPreset.Kind.TERRACED_HIGHLAND)
	column.add_child(preset_dropdown)
	seed_input = LineEdit.new()
	seed_input.text = "12345"
	seed_input.placeholder_text = "Integer seed"
	seed_input.add_theme_font_size_override("font_size", 22)
	column.add_child(seed_input)
	seed_input.text_submitted.connect(func(_text: String) -> void: generate_from_ui())
	var seed_row := HBoxContainer.new()
	column.add_child(seed_row)
	_button(seed_row, "Previous", func() -> void: _change_seed(-1))
	_button(seed_row, "Next", func() -> void: _change_seed(1))
	_button(seed_row, "Random", func() -> void:
		seed_input.text = str(randi_range(0, 2147483647))
		generate_from_ui())
	generate_button = _button(column, "Generate", generate_from_ui)
	parameters_label = _label(column, "", 18)
	parameters_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parameters_label.custom_minimum_size.x = 380
	debug_toggle = CheckButton.new()
	debug_toggle.text = "Debug: grid + height labels"
	debug_toggle.add_theme_font_size_override("font_size", 20)
	column.add_child(debug_toggle)
	debug_toggle.toggled.connect(func(enabled: bool) -> void:
		renderer.debug_enabled = enabled
		renderer.redraw())
	movement_toggle = CheckButton.new()
	movement_toggle.text = "Movement test"
	movement_toggle.button_pressed = true
	movement_toggle.add_theme_font_size_override("font_size", 20)
	column.add_child(movement_toggle)
	movement_toggle.toggled.connect(func(enabled: bool) -> void:
		character.visible = enabled
		npc.visible = enabled
		npc.set_process(enabled)
		if not enabled:
			_clear_movement_input())
	_label(column, "NPC command test", 20)
	npc_command_dropdown = OptionButton.new()
	npc_command_dropdown.add_theme_font_size_override("font_size", 19)
	for command_name: String in TerrainTestNPC.COMMAND_NAMES:
		npc_command_dropdown.add_item(command_name)
	npc_command_dropdown.select(TerrainTestNPC.Command.MOVE_TO_CELL)
	column.add_child(npc_command_dropdown)
	npc_command_button = _button(column, "Issue NPC command", issue_npc_command)
	_label(column, "Move: issue command, then click a destination.", 16)
	_button(column, "NPC female parts / animation", npc.open_editor)
	_label(column, "COMBAT TEST | Space: attack | G: guard", 18)
	_button(column, "Attack NPC (equipped weapon)", func() -> void: character.start_attack(npc))
	_button(column, "NPC attacks player", func() -> void:
		npc.issue_command(TerrainTestNPC.Command.STOP)
		npc.start_attack(character))
	var retaliate := CheckButton.new()
	retaliate.text = "NPC auto counterattack (in reach)"
	column.add_child(retaliate)
	retaliate.toggled.connect(func(enabled: bool) -> void: npc_retaliates = enabled)
	_button(column, "Reset health / revive", func() -> void:
		character.reset_combat()
		npc.reset_combat())
	combat_info = _label(column, "", 18)
	_label(column, "ARMY TEST | 1 captain + 99 soldiers", 18)
	deploy_army_button = _button(column, "Deploy 100-person army", deploy_army)
	follow_army_button = _button(column, "Army: follow PLAYER", func() -> void: issue_army_command(TerrainArmy.Command.FOLLOW_PLAYER))
	edge_army_button = _button(column, "Army: formation march to map edge", func() -> void: issue_army_command(TerrainArmy.Command.MOVE_TO_EDGE))
	clear_army_button = _button(column, "Clear army", clear_army)
	army_info = _label(column, "No army / 尚未部署", 18)
	army_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	army_info.custom_minimum_size.x = 380
	var collision_toggle := CheckButton.new()
	collision_toggle.text = "Show weapon / body hitboxes"
	column.add_child(collision_toggle)
	collision_toggle.toggled.connect(func(enabled: bool) -> void:
		character.collision_debug = enabled
		npc.collision_debug = enabled)
	var camera_row := HBoxContainer.new()
	_button(column, "Player parts / animation", character.open_editor)
	column.add_child(camera_row)
	_button(camera_row, "Fit map", fit_map)
	_button(camera_row, "64px / cell", func() -> void:
		camera.zoom = Vector2.ONE
		camera.position = character.position - Vector2(220, 0)
		camera.force_update_scroll())
	_label(column, "Click ground: place test character\nHold WASD / arrows: walk\nHold Shift + WASD: run\nF: mount / dismount\nWheel: mouse-centred zoom (up to 10x)\nHold right / middle mouse: drag camera\nBright arrow: ramp (points uphill)\nRock edge: blocked crossing", 18)
	info = _label(column, "", 20)
	status = _label(column, "", 18)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 380

func _label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = text.to_pascal_case()
	button.text = text
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _change_seed(delta: int) -> void:
	if seed_input.text.is_valid_int():
		seed_input.text = str(seed_input.text.to_int() + delta)
		generate_from_ui()

func generate_from_ui() -> void:
	if not seed_input.text.is_valid_int():
		status.text = "Seed must be an integer. Existing terrain was not changed."
		return
	if site_controller != null and not site_controller.archive_before_replace():
		return
	var started: int = Time.get_ticks_usec()
	var generated := TerrainGenerator.generate(preset_dropdown.selected, seed_input.text.to_int())
	SiteEnv.initialize(generated)
	generation_ms = float(Time.get_ticks_usec() - started) / 1000.0
	bind_terrain(generated)

func bind_terrain(value: TerrainData) -> void:
	army.clear()
	_clear_movement_input()
	_npc_target_pending = false
	terrain = value
	character.terrain_cell = Vector2i(-1, -1)
	npc.terrain_cell = Vector2i(-1, -1)
	renderer.display(terrain)
	character.data = terrain
	character.place(terrain.cell_from_index(int(terrain.site.get("player_cell", terrain.index(terrain.spawn_cell)))), true)
	character.reset_combat()
	npc.set_data(terrain)
	var worker_cell := terrain.cell_from_index(int(terrain.site.worker.cell))
	if not terrain.is_walkable(worker_cell) or worker_cell == character.terrain_cell:
		worker_cell = _find_npc_spawn_cell()
	npc.place(worker_cell, true)
	npc.issue_command(TerrainTestNPC.Command.STOP)
	npc.reset_combat()
	seed_input.text = str(terrain.seed_value)
	preset_dropdown.select(terrain.preset)
	site_controller.bind()
	parameters_label.text = "PARAMETERS\n%s\nMax height: %d | Micro: %.3f" % [terrain.parameters["composition"], terrain.parameters["max_height"], terrain.parameters["micro_strength"]]
	status.text = "Ready. Click a platform to place the test character."
	fit_map()
	get_viewport().gui_release_focus()
	_update_info()
	_update_army_controls()

func deploy_army() -> void:
	if army == null or terrain == null:
		return
	var deployed := army.deploy(terrain, character, npc)
	status.text = army.command_status
	_update_army_controls()
	_update_info()
	if not deployed:
		return

func clear_army() -> void:
	if army == null:
		return
	army.clear()
	status.text = "Army cleared."
	_update_army_controls()
	_update_info()

func issue_army_command(command_id: int) -> bool:
	if army == null:
		return false
	var accepted := army.issue_command(command_id)
	status.text = army.command_status
	_update_army_controls()
	_update_info()
	return accepted

func _update_army_controls() -> void:
	var active := army != null and army.has_army()
	if deploy_army_button != null:
		deploy_army_button.disabled = active
	if follow_army_button != null:
		follow_army_button.disabled = not active
	if edge_army_button != null:
		edge_army_button.disabled = not active
	if clear_army_button != null:
		clear_army_button.disabled = not active

func _find_npc_spawn_cell() -> Vector2i:
	if terrain == null:
		return Vector2i(-1, -1)
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var candidate := terrain.spawn_cell + direction
		if terrain.can_step(terrain.spawn_cell, candidate):
			return candidate
	for radius: int in range(2, 12):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				var candidate := terrain.spawn_cell + Vector2i(x, y)
				if terrain.is_walkable(candidate):
					return candidate
	return terrain.spawn_cell

func fit_map() -> void:
	if terrain == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var extent := Vector2(terrain.size) * TerrainRenderer.CELL_PIXELS
	var left := 500.0 if get_node("TerrainLabUI").visible else 0.0
	var right := Site.PANEL_SPACE if site_controller != null else 0.0
	var fit: float = minf((viewport_size.x - left - right) / extent.x, (viewport_size.y - 80.0) / extent.y)
	camera.zoom = Vector2.ONE * maxf(0.1, fit)
	camera.position = extent * 0.5 - Vector2((left - right) * 0.5 / camera.zoom.x, 0)
	camera.force_update_scroll()

func issue_npc_command(command_id: int = -1, requested_target: Vector2i = Vector2i(-1, -1)) -> bool:
	if npc == null or terrain == null:
		return false
	if site_controller != null:
		site_controller.release_worker()
	var selected_command := npc_command_dropdown.selected if command_id < 0 and npc_command_dropdown != null else command_id
	var target := requested_target
	if selected_command == TerrainTestNPC.Command.MOVE_TO_CELL and target == Vector2i(-1, -1):
		_npc_target_pending = true
		status.text = "Click map to choose NPC destination."
		get_viewport().gui_release_focus()
		return true
	_npc_target_pending = false
	if target == Vector2i(-1, -1):
		target = renderer.pick_cell(get_viewport().get_mouse_position())
	var accepted := npc.issue_command(selected_command, target, character)
	status.text = "NPC: %s" % npc.command_status
	return accepted

func zoom_at(viewport_point: Vector2, factor: float) -> void:
	var before: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * viewport_point
	camera.zoom = Vector2.ONE * clampf(camera.zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	camera.force_update_scroll()
	var after: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * viewport_point
	camera.position += before - after
	camera.force_update_scroll()

func _direction_for_key(key: int) -> Vector2i:
	match key:
		KEY_W, KEY_UP:
			return Vector2i.UP
		KEY_D, KEY_RIGHT:
			return Vector2i.RIGHT
		KEY_S, KEY_DOWN:
			return Vector2i.DOWN
		KEY_A, KEY_LEFT:
			return Vector2i.LEFT
	return Vector2i.ZERO

func _event_key(event: InputEventKey) -> int:
	return event.physical_keycode if event.physical_keycode != 0 else event.keycode

func _is_shift_key(event: InputEventKey) -> bool:
	return event.keycode == KEY_SHIFT or event.physical_keycode == KEY_SHIFT

func _held_direction() -> Vector2i:
	if _held_directions.has(_last_direction_key):
		return _held_directions[_last_direction_key]
	for direction: Variant in _held_directions.values():
		return direction
	return Vector2i.ZERO

func _clear_movement_input() -> void:
	_held_directions.clear()
	_last_direction_key = -1
	_move_cooldown = 0.0
	_run_held = false

func _report_move(moved: bool) -> void:
	if moved:
		var i: int = terrain.index(character.terrain_cell)
		status.text = "Moved to %s, height %d" % [character.terrain_cell, terrain.height_levels[i]]
	else:
		status.text = "Blocked: water, cliff edge or map boundary. Use a marked ramp."

func _try_move(direction: Vector2i) -> void:
	var running := _run_held
	_report_move(character.step(direction, running))
	_move_cooldown = character.get_move_interval(running)

func _unhandled_input(event: InputEvent) -> void:
	if (character.editor_window != null and character.editor_window.visible) or (npc.editor_window != null and npc.editor_window.visible):
		_clear_movement_input()
		return
	if site_controller != null and site_controller.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if get_tree().paused and event is InputEventKey:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_dragging = mouse.pressed
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at(mouse.position, ZOOM_STEP)
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(mouse.position, 1.0 / ZOOM_STEP)
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT and movement_toggle.button_pressed:
			if get_tree().paused:
				return
			get_viewport().gui_release_focus()
			var cell := renderer.pick_cell(mouse.position)
			if _npc_target_pending:
				issue_npc_command(TerrainTestNPC.Command.MOVE_TO_CELL, cell)
				return
			if cell == npc.terrain_cell or character.action_time > 0 or character.hp <= 0:
				return
			var placed: bool = character.place(renderer.pick_cell(mouse.position))
			status.text = "Placed on platform." if placed else "Cannot place on water / outside the map."
	elif event is InputEventMouseMotion and _dragging:
		camera.position -= (event as InputEventMouseMotion).relative / camera.zoom
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		var key := _event_key(key_event)
		if key == KEY_SPACE and key_event.pressed and not key_event.echo and movement_toggle.button_pressed:
			character.start_attack(npc)
			get_viewport().set_input_as_handled()
			return
		if key == KEY_G and not key_event.echo:
			character.set_guard(key_event.pressed)
			get_viewport().set_input_as_handled()
			return
		if _is_shift_key(key_event):
			_run_held = key_event.pressed
			get_viewport().set_input_as_handled()
			return
		var direction := _direction_for_key(key)
		if direction != Vector2i.ZERO:
			if key_event.pressed and not key_event.echo and movement_toggle.button_pressed:
				_held_directions[key] = direction
				_last_direction_key = key
				if _move_cooldown <= 0.0:
					_try_move(direction)
			elif not key_event.pressed:
				_held_directions.erase(key)
				if _held_directions.is_empty():
					_move_cooldown = 0.0
			get_viewport().set_input_as_handled()
			return
		if key == KEY_F and key_event.pressed and not key_event.echo and movement_toggle.button_pressed:
			var mounted := character.toggle_mount()
			status.text = "Mounted horse. Ride with WASD + Shift." if mounted else "Dismounted."
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if site_controller != null:
		site_controller.tick(delta)
	if get_tree().paused:
		return
	if npc_retaliates and movement_toggle != null and movement_toggle.button_pressed and npc.hp > 0 and character.hp > 0:
		var offset := character.terrain_cell - npc.terrain_cell
		if absi(offset.x) + absi(offset.y) == 1 and terrain.can_step(npc.terrain_cell, character.terrain_cell):
			npc.start_attack(character)
	if movement_toggle != null and movement_toggle.button_pressed:
		_move_cooldown = maxf(0.0, _move_cooldown - delta)
		var held_direction := _held_direction()
		if held_direction != Vector2i.ZERO and _move_cooldown <= 0.0:
			_try_move(held_direction)
	else:
		_clear_movement_input()
	_info_time += delta
	if _info_time >= 0.1:
		_info_time = 0.0
		_update_info()

func _update_info() -> void:
	if terrain == null or info == null:
		return
	combat_info.text = "Player HP %d | %s\nNPC HP %d | %s" % [character.hp, character.combat_status, npc.hp, npc.combat_status]
	if army_info != null and army != null:
		var captain_goal := "-"
		if army.has_army():
			captain_goal = str(army.desired_cells[0])
		army_info.text = "%s\nRender: %s | live 3D sources: %d\nFront goal: %s | guide: %s\nCaptain: %s -> local slot %s\nFormation: %s width=%d %d/99 | occupied: %d | moving: %d\nLegal lag: %d | unknown: %d | RUN: %d | front guards: %d\nSwaps: %d | completed steps: %d" % [army.command_status, army.visual_mode(), army.active_3d_source_count(), army._march_goal, army._formation_anchor_cell, str(army.cells[0]) if army.has_army() else "-", captain_goal, army.formation_mode_name(), army.formation_width(), army.formation_count(), army.occupied_count(), army.moving_count(), army.formation_cohesion.lag, army.formation_cohesion.unknown, army.formation_cohesion.runners, army.formation_cohesion.guards, army.swap_count(), army.completed_steps()]
		var passage := army.passage_summary()
		army_info.text += "\nPassage: waiting %d | core/egress %d | all cleared %d/99" % [passage.waiting, passage.clearing, passage.completed]
	var cell: Vector2i = renderer.pick_cell(get_viewport().get_mouse_position())
	var details: String = "Hovered: outside map"
	if terrain.contains(cell):
		var i: int = terrain.index(cell)
		details = "Hovered cell: %s\nHeight: %d | %s\nWalkable top: %s\nCliff edge: %s | Ramp: %s" % [cell, terrain.height_levels[i], TerrainData.SURFACE_NAMES[terrain.surface_types[i]], terrain.is_walkable(cell), (terrain.flags[i] & TerrainData.Flag.CLIFF) != 0, terrain.ramp_edges[i] != 0]
	info.text = "%s\nSeed: %d\n%s\nCharacter cell: %s\nNPC cell: %s\nNPC command: %s\nZoom: %.3f | FPS: %d\nGenerate: %.2f ms" % [TerrainPreset.NAMES[terrain.preset], terrain.seed_value, details, character.terrain_cell, npc.terrain_cell, npc.command_status, camera.zoom.x, Engine.get_frames_per_second(), generation_ms]
