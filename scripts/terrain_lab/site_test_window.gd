extends Window

# Optional UI only. Original Lab, Controller and runtime owners accept commands.
const TAB_NAMES := {
	"scenario": "場景與人物", "deployment": "隊伍部署", "command": "軍令與 AI",
	"stock": "裝備與物資", "logistics": "後勤與車輛",
	"relationships": "人物關係與接續", "diagnostics": "診斷與顯示",
}
var lab: Node2D
var tabs: TabContainer
var pages: Dictionary = {}
var editor_slot: Control
var editor_actor: TerrainTestCharacter
var placement_toggle: CheckButton
var result_label: Label
var _opened := false
var legacy_column: VBoxContainer
var _preview_input_accept: Callable

func _init() -> void:
	visible = false

func setup(scene: Node2D) -> void:
	lab = scene
	hide()
	name = "SiteTestWindow"
	title = "Site 測試工具"
	force_native = true
	gui_embed_subwindows = true
	exclusive = false
	size = Vector2i(1280, 850)
	min_size = Vector2i(720, 480)
	close_requested.connect(hide_window)
	focus_entered.connect(_focus_entered)
	focus_exited.connect(func() -> void:
		if is_instance_valid(editor_actor) and editor_actor.editor != null:
			editor_actor.editor._dragging_preview = false
			editor_actor.editor._panning_preview = false)
	visibility_changed.connect(func() -> void:
		if not visible:
			_close_character_editor()
			lab.test_placement_enabled = false
			if placement_toggle != null: placement_toggle.set_pressed_no_signal(false))
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)
	tabs = TabContainer.new()
	tabs.name = "TestTabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(tabs)
	for key: String in TAB_NAMES:
		var scroll := ScrollContainer.new()
		scroll.name = key.to_pascal_case()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		tabs.add_child(scroll)
		tabs.set_tab_title(tabs.get_tab_count() - 1, TAB_NAMES[key])
		var page := VBoxContainer.new()
		page.name = key.to_pascal_case() + "Controls"
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation", 8)
		scroll.add_child(page)
		pages[key] = page
	tabs.tab_changed.connect(func(_index: int) -> void: _close_character_editor())
	legacy_column = lab._build_ui(pages.scenario)
	_move_legacy_controls(legacy_column)
	placement_toggle = CheckButton.new()
	placement_toggle.name = "TestPlacement"
	placement_toggle.text = "測試放置：左鍵搬動獨立角色"
	placement_toggle.toggled.connect(func(enabled: bool) -> void:
		lab.test_placement_enabled = enabled)
	pages.scenario.add_child(placement_toggle)
	editor_slot = Control.new()
	editor_slot.name = "CharacterEditorHost"
	editor_slot.custom_minimum_size = Vector2(1300, 920)
	editor_slot.hide()
	pages.scenario.add_child(editor_slot)
	lab.site_controller.install_test_window(self, pages)
	result_label = Label.new()
	result_label.name = "TestResult"
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(result_label)
	hide()

func _move_legacy_controls(column: VBoxContainer) -> void:
	for node: Control in [lab.debug_toggle, lab.parameters_label, lab.info, lab.combat_info, lab.army_info]:
		if node != null: node.reparent(pages.diagnostics, false)
	for node: Control in [lab.deploy_army_button, lab.clear_army_button]:
		if node != null: node.reparent(pages.deployment, false)
	for node: Control in [lab.follow_army_button, lab.edge_army_button]:
		if node != null: node.reparent(pages.command, false)
	for node: Node in column.get_children():
		if node is CheckButton and node.text == "Show weapon / body hitboxes":
			node.reparent(pages.diagnostics, false)
		elif node is Button and node.text == "Player parts / animation":
			for connection: Dictionary in node.pressed.get_connections():
				node.pressed.disconnect(connection.callable)
			node.pressed.connect(_open_character_editor)
		elif node is Label and node.text.begins_with("Click ground:"):
			node.text = "WASD／方向鍵：移動；Shift：跑步；Space：攻擊；G：防禦；F：上下馬。\n測試放置須明確啟用；一般地圖點選維持正式操作。"
		elif node is Label and node.text.begins_with("ARMY TEST"):
			node.reparent(pages.deployment, false)
	if lab.terrain != null:
		lab.preset_dropdown.select(lab.terrain.preset)
		lab.seed_input.text = str(lab.terrain.seed_value)

func open() -> void:
	if not _opened:
		reset_position()
		_opened = true
	show()
	grab_focus()
	refresh()

func reset_position() -> void:
	if DisplayServer.get_name() == "headless":
		position = Vector2i(80, 80)
		return
	var screen := get_tree().root.current_screen
	var usable := DisplayServer.screen_get_usable_rect(screen)
	size = Vector2i(mini(1280, usable.size.x), mini(850, usable.size.y))
	position = usable.position + Vector2i(Vector2(usable.size - size) * 0.5)

func hide_window() -> void:
	_close_character_editor()
	lab.test_placement_enabled = false
	placement_toggle.set_pressed_no_signal(false)
	hide()

func handle_shortcut(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F12:
		if visible: hide_window()
		else: open()
		get_viewport().set_input_as_handled()
		return true
	return false

func _input(event: InputEvent) -> void:
	if handle_shortcut(event): return
	if is_instance_valid(editor_actor) and editor_actor.editor != null:
		editor_actor.editor._input(event)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if is_instance_valid(editor_actor): _close_character_editor()
		else: hide_window()
		get_viewport().set_input_as_handled()

func _focus_entered() -> void:
	lab._clear_movement_input()
	lab._dragging = false
	lab.site_controller._cancel_facing_move()

func _open_character_editor() -> void:
	_close_character_editor()
	var target: Dictionary = lab.controlled_target()
	var actor := target.get("owner") as TerrainTestCharacter
	if actor == null or actor.editor == null:
		lab.show_status("目前控制人物沒有可編輯的即時角色呈現。")
		return
	actor.open_editor(editor_slot)
	if actor.is_editor_open():
		editor_actor = actor
		actor.editor.closed.connect(_close_character_editor)
		_preview_input_accept = func(_event: InputEvent) -> void: actor.editor.preview_container.accept_event()
		actor.editor.preview_container.gui_input.connect(_preview_input_accept)
		legacy_column.hide()
		placement_toggle.hide()
		(pages.scenario.get_parent() as ScrollContainer).scroll_vertical = 0

func _close_character_editor() -> void:
	if is_instance_valid(editor_actor):
		if _preview_input_accept.is_valid() and editor_actor.editor.preview_container.gui_input.is_connected(_preview_input_accept):
			editor_actor.editor.preview_container.gui_input.disconnect(_preview_input_accept)
		if editor_actor.editor.closed.is_connected(_close_character_editor):
			editor_actor.editor.closed.disconnect(_close_character_editor)
		if editor_actor.is_editor_open(): editor_actor._close_editor()
	editor_actor = null
	_preview_input_accept = Callable()
	if editor_slot != null: editor_slot.hide()
	if legacy_column != null: legacy_column.show()
	if placement_toggle != null: placement_toggle.show()

func context_changed() -> void:
	_close_character_editor()
	lab.test_placement_enabled = false
	if placement_toggle != null: placement_toggle.set_pressed_no_signal(false)
	refresh()

func refresh() -> void:
	if not visible: return
	if is_instance_valid(editor_actor) and lab.controlled_person_id() != editor_actor.person_id:
		_close_character_editor()
	if result_label != null and lab.site_controller.message != null:
		result_label.text = lab.site_controller.message.text

func _exit_tree() -> void:
	_close_character_editor()
	if is_instance_valid(lab):
		lab.test_placement_enabled = false
		lab.movement_input_enabled = true
