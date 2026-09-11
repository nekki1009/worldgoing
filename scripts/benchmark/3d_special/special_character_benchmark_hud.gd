class_name SpecialCharacterBenchmarkHUD
extends CanvasLayer

const DefinitionType = preload("res://scripts/benchmark/3d_special/special_visual_definition.gd")
const AppearanceType = preload("res://scripts/benchmark/3d_special/special_character_appearance.gd")
const AnimationStateType = preload("res://scripts/benchmark/3d_special/special_character_animation_state.gd")

var controller: SpecialCharacterBenchmarkController
var registry: SpecialCharacterVisualRegistry
var stats_label: Label
var target_label: Label
var selector_options: Dictionary = {}
var target_buttons: Array[Button] = []
var animation_buttons: Array[Button] = []
var count_buttons: Array[Button] = []
var target_appearance: SpecialCharacterAppearance
var built: bool = false

func setup(
	target_controller: SpecialCharacterBenchmarkController,
	target_registry: SpecialCharacterVisualRegistry
) -> void:
	controller = target_controller
	registry = target_registry
	if not built:
		_build_ui()
		built = true
	_populate_selectors()

func update_metrics(
	fps: float,
	frame_ms: float,
	worst_frame_ms: float,
	special_count: int,
	skeleton_count: int,
	skinned_mesh_count: int,
	character_node_count: int,
	animation_cpu_ms: float,
	draw_calls: int,
	triangles: int,
	animation_name: StringName,
	material_count: int
) -> void:
	if stats_label == null:
		return
	stats_label.text = (
		"SPECIAL NPC 3D MODULAR VERTICAL SLICE\n"
		+ "FPS %7.2f    Frame %7.3f ms    Worst %7.3f ms\n"
		+ "SPECIAL NPCs %3d    Skeleton3D %3d    Skinned Mesh %3d\n"
		+ "Character Nodes %4d    Materials %2d    Animation %s\n"
		+ "Animation CPU %7.3f ms    Draw Calls %4d    Triangles %8d\n"
		+ "Shared HumanRig_v1 / socket attachments / registry-driven modules"
	) % [
		fps, frame_ms, worst_frame_ms, special_count, skeleton_count,
		skinned_mesh_count, character_node_count, material_count, animation_name,
		animation_cpu_ms, draw_calls, triangles
	]

func set_target_character(index: int, appearance: SpecialCharacterAppearance) -> void:
	target_appearance = appearance.duplicate_data() if appearance != null else AppearanceType.new()
	if target_label != null:
		target_label.text = "Target Character: NPC %s" % char(65 + index)
	for slot: int in selector_options.keys():
		var option: OptionButton = selector_options[slot]
		var wanted_id: StringName = _appearance_id_for_slot(target_appearance, slot)
		for item_index: int in range(option.item_count):
			if option.get_item_metadata(item_index) == wanted_id:
				option.select(item_index)
				break

func set_count_selection(selected_count: int) -> void:
	for button: Button in count_buttons:
		button.button_pressed = int(button.get_meta("count", 0)) == selected_count

func set_animation_selection(selected_state: int) -> void:
	for button: Button in animation_buttons:
		button.button_pressed = int(button.get_meta("state", 0)) == selected_state

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.name = "ControlPanel"
	panel.position = Vector2(18.0, 18.0)
	panel.custom_minimum_size = Vector2(360.0, 0.0)
	add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)
	stats_label = Label.new()
	stats_label.add_theme_font_size_override("font_size", 14)
	column.add_child(stats_label)
	target_label = Label.new()
	target_label.text = "Target Character: NPC A"
	column.add_child(target_label)

	var target_row := HBoxContainer.new()
	target_row.add_child(_label("Characters"))
	for index: int in range(4):
		var button := Button.new()
		button.text = "NPC %s" % char(65 + index)
		button.toggle_mode = true
		button.set_meta("target", index)
		button.pressed.connect(_on_target_pressed.bind(index))
		target_row.add_child(button)
		target_buttons.append(button)
	target_buttons[0].button_pressed = true
	column.add_child(target_row)

	for slot: int in [
		DefinitionType.Slot.BODY, DefinitionType.Slot.HEAD, DefinitionType.Slot.HAIR,
		DefinitionType.Slot.ARMOR, DefinitionType.Slot.HELMET, DefinitionType.Slot.WEAPON,
		DefinitionType.Slot.SHIELD
	]:
		column.add_child(_create_selector_row(column, slot))

	var randomize_button := Button.new()
	randomize_button.text = "Randomize Appearance"
	randomize_button.pressed.connect(_on_randomize_pressed)
	column.add_child(randomize_button)

	column.add_child(_label("Animation"))
	var animation_row := HBoxContainer.new()
	for state: int in range(AnimationStateType.State.BLOCK + 1):
		var button := Button.new()
		button.text = AnimationStateType.state_name(state)
		button.toggle_mode = true
		button.set_meta("state", state)
		button.pressed.connect(_on_animation_pressed.bind(state))
		animation_row.add_child(button)
		animation_buttons.append(button)
	animation_buttons[0].button_pressed = true
	column.add_child(animation_row)

	column.add_child(_label("SPECIAL NPC Count"))
	var count_row := HBoxContainer.new()
	for count: int in [1, 16, 32, 64, 128]:
		var button := Button.new()
		button.text = str(count)
		button.toggle_mode = true
		button.set_meta("count", count)
		button.pressed.connect(_on_count_pressed.bind(count))
		count_row.add_child(button)
		count_buttons.append(button)
	count_buttons[0].button_pressed = true
	column.add_child(count_row)
	column.add_child(_label("Keys: 1-5 animation, F1-F5 count, R randomize, WASD pan, wheel zoom"))

func _create_selector_row(_column: VBoxContainer, slot: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label_text := _slot_name(slot)
	var label := _label(label_text)
	label.custom_minimum_size.x = 82.0
	row.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.item_selected.connect(_on_selector_selected.bind(slot))
	selector_options[slot] = option
	row.add_child(option)
	return row

func _populate_selectors() -> void:
	for slot: int in selector_options.keys():
		var option: OptionButton = selector_options[slot]
		option.clear()
		var allow_none: bool = slot in [
			DefinitionType.Slot.ARMOR, DefinitionType.Slot.HELMET,
			DefinitionType.Slot.WEAPON, DefinitionType.Slot.SHIELD
		]
		if allow_none:
			option.add_item("None")
			option.set_item_metadata(0, &"")
		var ids := registry.ids_for_slot(slot)
		for visual_id: StringName in ids:
			var item_index := option.item_count
			option.add_item(String(visual_id))
			option.set_item_metadata(item_index, visual_id)

func _on_target_pressed(index: int) -> void:
	for button: Button in target_buttons:
		button.button_pressed = int(button.get_meta("target", 0)) == index
	if controller != null:
		controller.set_target_character(index)

func _on_selector_selected(item_index: int, slot: int) -> void:
	if controller == null:
		return
	var option: OptionButton = selector_options[slot]
	var appearance := target_appearance.duplicate_data() if target_appearance != null else AppearanceType.new()
	var visual_id: StringName = option.get_item_metadata(item_index)
	_set_appearance_id(appearance, slot, visual_id)
	controller.apply_target_appearance(appearance)

func _on_animation_pressed(state: int) -> void:
	if controller != null:
		controller.set_animation_state(state)

func _on_count_pressed(count: int) -> void:
	if controller != null:
		controller.set_active_special_count(count)

func _on_randomize_pressed() -> void:
	if controller != null:
		controller.randomize_target_appearance()

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or controller == null:
		return
	var key_event: InputEventKey = event as InputEventKey
	match key_event.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			controller.set_animation_state(key_event.keycode - KEY_1)
		KEY_F1:
			controller.set_active_special_count(1)
		KEY_F2:
			controller.set_active_special_count(16)
		KEY_F3:
			controller.set_active_special_count(32)
		KEY_F4:
			controller.set_active_special_count(64)
		KEY_F5:
			controller.set_active_special_count(128)
		KEY_R:
			controller.randomize_target_appearance()

func _appearance_id_for_slot(appearance: SpecialCharacterAppearance, slot: int) -> StringName:
	match slot:
		DefinitionType.Slot.BODY:
			return appearance.body_id
		DefinitionType.Slot.HEAD:
			return appearance.head_id
		DefinitionType.Slot.HAIR:
			return appearance.hair_id
		DefinitionType.Slot.ARMOR:
			return appearance.armor_id
		DefinitionType.Slot.HELMET:
			return appearance.helmet_id
		DefinitionType.Slot.WEAPON:
			return appearance.weapon_id
		_:
			return appearance.shield_id

func _set_appearance_id(appearance: SpecialCharacterAppearance, slot: int, visual_id: StringName) -> void:
	match slot:
		DefinitionType.Slot.BODY:
			appearance.body_id = visual_id
		DefinitionType.Slot.HEAD:
			appearance.head_id = visual_id
		DefinitionType.Slot.HAIR:
			appearance.hair_id = visual_id
		DefinitionType.Slot.ARMOR:
			appearance.armor_id = visual_id
		DefinitionType.Slot.HELMET:
			appearance.helmet_id = visual_id
		DefinitionType.Slot.WEAPON:
			appearance.weapon_id = visual_id
		DefinitionType.Slot.SHIELD:
			appearance.shield_id = visual_id

func _slot_name(slot: int) -> String:
	match slot:
		DefinitionType.Slot.BODY:
			return "Body"
		DefinitionType.Slot.HEAD:
			return "Head"
		DefinitionType.Slot.HAIR:
			return "Hair"
		DefinitionType.Slot.ARMOR:
			return "Armor"
		DefinitionType.Slot.HELMET:
			return "Helmet"
		DefinitionType.Slot.WEAPON:
			return "Weapon"
		_:
			return "Shield"

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label
