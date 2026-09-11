class_name CrowdBenchmarkHUD
extends CanvasLayer

signal count_requested(soldier_count: int)
signal mode_requested(mode: int)
signal near_budget_requested(actor_budget: int)
signal reset_requested

var _stats_label: Label
var _status_label: Label
var _count_buttons: Array[Button] = []
var _mode_buttons: Array[Button] = []
var _near_budget_buttons: Array[Button] = []

func _ready() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(20.0, 20.0)
	panel.custom_minimum_size = Vector2(575.0, 500.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.045, 0.07, 0.94)
	panel_style.border_color = Color(0.25, 0.55, 0.72, 0.8)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	margin.add_child(column)

	var title := Label.new()
	title.text = "Worldgoing 3D Soldier Visual Benchmark"
	title.add_theme_font_size_override("font_size", 20)
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "HumanRig_v1  |  Archetype MultiMesh  |  Near Actor Pool  |  LOD"
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.78, 0.86))
	column.add_child(subtitle)

	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 15)
	_stats_label.text = "Initializing..."
	column.add_child(_stats_label)

	var count_label := Label.new()
	count_label.text = "Soldier count"
	count_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.88))
	column.add_child(count_label)
	var count_row := HBoxContainer.new()
	count_row.add_theme_constant_override("separation", 6)
	column.add_child(count_row)
	for option: Dictionary in [
		{"label": "1,000", "count": 1000},
		{"label": "2,500", "count": 2500},
		{"label": "5,000", "count": 5000},
		{"label": "10,000", "count": 10000}
	]:
		var button := Button.new()
		button.text = option.label
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(92.0, 30.0)
		button.pressed.connect(_on_count_button_pressed.bind(int(option.count)))
		count_row.add_child(button)
		_count_buttons.append(button)

	var mode_label := Label.new()
	mode_label.text = "Visual mode"
	mode_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.88))
	column.add_child(mode_label)
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 6)
	column.add_child(mode_row)
	for option: Dictionary in [
		{"label": "[1] Placeholder", "mode": 0},
		{"label": "[2] Humanoid Static", "mode": 1},
		{"label": "[3] Humanoid Animated", "mode": 2},
		{"label": "[4] Humanoid LOD", "mode": 3}
	]:
		var button := Button.new()
		button.text = option.label
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(128.0, 30.0)
		button.pressed.connect(_on_mode_button_pressed.bind(int(option.mode)))
		mode_row.add_child(button)
		_mode_buttons.append(button)

	var near_label := Label.new()
	near_label.text = "MAX_FULL_ACTORS / Near actor budget"
	near_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.88))
	column.add_child(near_label)
	var near_row := HBoxContainer.new()
	near_row.add_theme_constant_override("separation", 6)
	column.add_child(near_row)
	for budget: int in [0, 64, 128, 256]:
		var button := Button.new()
		button.text = str(budget)
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(70.0, 30.0)
		button.pressed.connect(_on_near_budget_button_pressed.bind(budget))
		near_row.add_child(button)
		_near_budget_buttons.append(button)

	var reset_button := Button.new()
	reset_button.text = "Reset deterministic seed"
	reset_button.custom_minimum_size = Vector2(190.0, 28.0)
	reset_button.pressed.connect(func() -> void: reset_requested.emit())
	column.add_child(reset_button)

	_status_label = Label.new()
	_status_label.text = "WASD pan  |  Mouse wheel zoom  |  F1-F4 counts  |  B cycles Near budget"
	_status_label.add_theme_color_override("font_color", Color(0.58, 0.68, 0.74))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status_label)

func update_metrics(
	fps: float,
	frame_ms: float,
	total_soldiers: int,
	active_formations: int,
	near_actors: int,
	mid_soldiers: int,
	far_soldiers: int,
	visible_chunks: int,
	visible_soldiers: int,
	skeletons: int,
	active_skeletons: int,
	animation_players: int,
	multimesh_groups: int,
	multimesh_instances: int,
	simulation_ms: float,
	renderer_ms: float,
	near_actor_cpu_ms: float,
	dirty_chunks: int,
	transform_dirty_instances: int,
	animation_dirty_instances: int,
	visual_dirty_instances: int,
	structural_changes: int,
	upload_calls: int,
	instances_uploaded: int,
	bytes_uploaded: int,
	draw_calls: int,
	triangles: int,
	mode_name: String,
	seed: int,
	chunk_size: float,
	near_budget: int
) -> void:
	if _stats_label == null:
		return
	_stats_label.text = "FPS %7.1f    Frame %6.2f ms\n" % [fps, frame_ms]
	_stats_label.text += "Total %5d    Formations %3d    Near %3d\n" % [total_soldiers, active_formations, near_actors]
	_stats_label.text += "Mid %5d    Far %5d    Visible %5d\n" % [mid_soldiers, far_soldiers, visible_soldiers]
	_stats_label.text += "Visible Chunks %3d    Skeleton3D %3d (active %3d)\n" % [visible_chunks, skeletons, active_skeletons]
	_stats_label.text += "AnimationPlayer %3d\n" % animation_players
	_stats_label.text += "MultiMesh Groups %4d    Instances %5d\n" % [multimesh_groups, multimesh_instances]
	_stats_label.text += "Simulation CPU %6.3f ms    Renderer CPU %6.3f ms\n" % [simulation_ms, renderer_ms]
	_stats_label.text += "Near Actor CPU %6.3f ms    Draw %4d    Tri %8d\n" % [near_actor_cpu_ms, draw_calls, triangles]
	_stats_label.text += "Dirty Chunks %3d    T/A/V %4d/%4d/%4d\n" % [dirty_chunks, transform_dirty_instances, animation_dirty_instances, visual_dirty_instances]
	_stats_label.text += "Structural %4d    Upload calls %4d    Instances %5d\n" % [structural_changes, upload_calls, instances_uploaded]
	_stats_label.text += "Upload bytes %.1f KB\n" % (float(bytes_uploaded) / 1024.0)
	_stats_label.text += "Mode: %s    Near budget: %d    Chunk: %.0fm    Seed: %d" % [mode_name, near_budget, chunk_size, seed]

func set_count_selection(soldier_count: int) -> void:
	for button: Button in _count_buttons:
		button.button_pressed = button.text.replace(",", "").to_int() == soldier_count

func set_mode_selection(mode: int) -> void:
	for index: int in range(_mode_buttons.size()):
		_mode_buttons[index].button_pressed = index == mode

func set_near_budget_selection(actor_budget: int) -> void:
	for index: int in range(_near_budget_buttons.size()):
		_near_budget_buttons[index].button_pressed = int(_near_budget_buttons[index].text) == actor_budget

func _on_count_button_pressed(soldier_count: int) -> void:
	count_requested.emit(soldier_count)

func _on_mode_button_pressed(mode: int) -> void:
	mode_requested.emit(mode)

func _on_near_budget_button_pressed(actor_budget: int) -> void:
	near_budget_requested.emit(actor_budget)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event as InputEventKey
		match key_event.keycode:
			KEY_1:
				mode_requested.emit(0)
			KEY_2:
				mode_requested.emit(1)
			KEY_3:
				mode_requested.emit(2)
			KEY_4:
				mode_requested.emit(3)
			KEY_F1:
				count_requested.emit(1000)
			KEY_F2:
				count_requested.emit(2500)
			KEY_F3:
				count_requested.emit(5000)
			KEY_F4:
				count_requested.emit(10000)
			KEY_B:
				var next_budget: int = 0
				for budget_index: int in range(_near_budget_buttons.size()):
					if _near_budget_buttons[budget_index].button_pressed:
						next_budget = int(_near_budget_buttons[(budget_index + 1) % _near_budget_buttons.size()].text)
						break
				near_budget_requested.emit(next_budget)
			KEY_R:
				reset_requested.emit()
