extends Control
## Formal game entry: Continue, New Game (map → start Site → character →
## confirm), Load World and Quit. The start Site is picked on RegionLab in
## "pick_start" mode; RegionEntry carries the draft across the scene change.

const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const TechnologyArtisans = preload("res://scripts/terrain_lab/site_technology_artisans.gd")
## Menu background: the Taiwan overview classes (R8) and content scope (R8) drawn with the RegionLab palette.
## Two single-channel textures replace the RG8 interleave loop over 4.56 M cells; display only, no validation.
const BACKGROUND_FOLDER := "res://assets/region_lab/earth_tw_tm2_121_v1_r4"
const BACKGROUND_SIZE := Vector2i(1900, 2400) # manifest.json summary.size; checked against the file length below.
const BACKGROUND_SHADER := """
shader_type canvas_item;
uniform sampler2D scope_texture : filter_nearest;
uniform bool has_scope = true;
void fragment() {
    float kind = floor(texture(TEXTURE, UV).r * 255.0 + 0.5);
    float scope = has_scope ? floor(texture(scope_texture, UV).r * 255.0 + 0.5) : 1.0;
    vec3 color = vec3(0.28, 0.23, 0.32);
    if (kind == 1.0) { color = vec3(0.10, 0.27, 0.40); }
    else if (kind == 2.0) { color = vec3(0.39, 0.57, 0.34); }
    else if (kind == 3.0) { color = vec3(0.27, 0.63, 0.72); }
    else if (kind == 4.0) { color = vec3(0.73, 0.73, 0.48); }
    if (scope == 0.0) { color = mix(color, vec3(0.14, 0.16, 0.19), 0.72); }
    COLOR = vec4(color, 1.0);
}
"""
const PersonPersonality = preload("res://scripts/terrain_lab/person_personality.gd")
const ABILITIES := [["combat_ability", "武力"], ["tactics", "戰術"], ["leadership", "統御"], ["coach", "教練"]]
const PersonSkills = preload("res://scripts/terrain_lab/person_skills.gd") # 技能 K5: the start template's points
const DEFAULT_HAIR_DYE := "9b775dff"
## The project renders at 2560×1440 and scales to the window; size UI for that.
const UI := 1.6

var _pages: Dictionary = {}
var _message: Label
var _continue_button: Button
var _continue_note: Label
var _world_list: ItemList
var _worlds: Array[Dictionary] = []
var _load_button: Button
# Character page controls.
var _name_input: LineEdit
var _body_select: OptionButton
var _hair_select: OptionButton
var _face_select: OptionButton
var _dye_toggle: CheckBox
var _dye_picker: ColorPickerButton
var _ability_inputs: Dictionary = {}
var _personality_sliders: Dictionary = {}
var _learning_slider: HSlider
var _line_sliders: Dictionary = {}
var _aptitude_sliders: Dictionary = {}
var _free_points: CheckBox
var _points_label: Label
var _character_error: Label
var _preview_host: Node
var _preview_editor: HumanCharacter3DEditor
var _preview_window: Window
var _preview_rect: TextureRect
# Confirm page controls.
var _world_name: LineEdit
var _initial_scenario: OptionButton
var _start_faction: OptionButton
var _start_faction_name: LineEdit
var _summary: Label

func _ready() -> void:
	get_tree().paused = false
	get_tree().auto_accept_quit = true
	theme = Theme.new()
	theme.default_font_size = roundi(17 * UI)
	_build_background()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.11, 0.13, 0.9)
	style.border_color = Color("526b5d")
	style.set_border_width_all(1)
	style.set_content_margin_all(24 * UI)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var title := Label.new()
	title.text = "Worldgoing"
	title.add_theme_font_size_override("font_size", roundi(40 * UI))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_message = Label.new()
	_message.name = "MenuMessage"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size.x = 420 * UI
	_message.modulate = Color("f0d7a0")
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.text = RegionEntry.menu_message
	_message.visible = not _message.text.is_empty()
	RegionEntry.menu_message = ""
	column.add_child(_message)
	_build_main_page(column)
	_build_load_page(column)
	_build_map_page(column)
	_build_character_page(column)
	_build_confirm_page(column)
	var step := str(RegionEntry.draft.get("step", ""))
	if step == "character" and RegionEntry.draft.get("site") is Vector2i: show_page("character")
	else:
		RegionEntry.draft = {}
		show_page("main")

func show_page(page: String) -> void:
	for id: String in _pages:
		_pages[id].visible = id == page
	if page == "main": _refresh_continue()
	elif page == "load": _refresh_worlds()
	elif page == "character": _restore_character_draft()
	elif page == "confirm": _refresh_summary()
	_set_preview_active(page == "character")

func _page(parent: Node, id: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = "Page_" + id
	page.add_theme_constant_override("separation", 10)
	page.visible = false
	parent.add_child(page)
	_pages[id] = page
	return page

func _button(parent: Node, text: String, node_name: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.add_theme_font_size_override("font_size", roundi(20 * UI))
	button.custom_minimum_size = Vector2(280, 44) * UI
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _label(parent: Node, text: String, text_size: int = 16) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", roundi(text_size * UI))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _row(parent: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	return row

# --- Background: the fixed Taiwan overview with the RegionLab palette.

func _build_background() -> void:
	var base := ColorRect.new()
	base.color = Color("101b24")
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	# The map texture is built after the first frame so the menu appears at once.
	_build_background_map.call_deferred()

# Reads the two raw overview layers directly. The full RegionData load (manifest JSON, SHA-256 of every
# layer, per-cell range checks) stays with RegionLab and the Site, which need the verified data; the menu
# background is decoration, so a missing or odd-sized file only leaves the plain colour.
func _build_background_map() -> void:
	if not is_inside_tree(): return
	var classes := FileAccess.get_file_as_bytes(BACKGROUND_FOLDER.path_join("summary.u8"))
	if classes.size() != BACKGROUND_SIZE.x * BACKGROUND_SIZE.y: return
	var scopes := FileAccess.get_file_as_bytes(BACKGROUND_FOLDER.path_join("content_scope.u8"))
	var map := TextureRect.new()
	map.name = "TaiwanBackground"
	map.texture = ImageTexture.create_from_image(Image.create_from_data(BACKGROUND_SIZE.x, BACKGROUND_SIZE.y, false, Image.FORMAT_R8, classes))
	map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map.modulate = Color(1, 1, 1, 0.55)
	var shader := Shader.new()
	shader.code = BACKGROUND_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var has_scope := scopes.size() == classes.size()
	mat.set_shader_parameter("has_scope", has_scope)
	if has_scope:
		mat.set_shader_parameter("scope_texture", ImageTexture.create_from_image(Image.create_from_data(BACKGROUND_SIZE.x, BACKGROUND_SIZE.y, false, Image.FORMAT_R8, scopes)))
	map.material = mat
	add_child(map)
	move_child(map, 1) # Right above the base colour, below the menu panel.

# --- Main page.

func _build_main_page(parent: Node) -> void:
	var page := _page(parent, "main")
	_continue_button = _button(page, "繼續遊戲", "ContinueGame", _continue_game)
	_continue_note = _label(page, "", 14)
	_continue_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(page, "新遊戲", "NewGame", func() -> void:
		RegionEntry.draft = {"step": "map", "map": "taiwan"}
		show_page("map"))
	_button(page, "載入世界", "LoadWorld", func() -> void: show_page("load"))
	_button(page, "地圖編輯器", "MapEditor", _open_map_editor)
	_button(page, "離開", "QuitGame", func() -> void: get_tree().quit())

func _open_map_editor() -> void:
	RegionEntry.request_author_editor()
	get_tree().change_scene_to_file(RegionEntry.MAP_EDITOR_SCENE)

func _refresh_continue() -> void:
	var last := RegionEntry.last_world()
	var meta := RegionEntry.read_world(str(last.get("world_id", "")))
	_continue_button.disabled = meta.is_empty()
	_continue_note.text = "尚無世界" if meta.is_empty() else _world_line(meta)

func _continue_game() -> void:
	if RegionEntry.request_resume(): get_tree().change_scene_to_file(RegionEntry.SITE_SCENE)

func _world_line(meta: Dictionary) -> String:
	var site: Array = meta.get("active_site", [])
	var at := "(%d, %d)" % [int(site[0]), int(site[1])] if site.size() == 2 else "—"
	return "%s · 地點 %s · 第 %d 日 · 最後保存 %s" % [str(meta.get("name", meta.world_id)), at, int(meta.get("day", 1)),
		Time.get_datetime_string_from_unix_time(int(meta.get("saved_unix", 0)) + _timezone_seconds(), true)]

static func _timezone_seconds() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60

# --- Load World page.

func _build_load_page(parent: Node) -> void:
	var page := _page(parent, "load")
	_label(page, "載入世界", 24)
	_world_list = ItemList.new()
	_world_list.name = "WorldList"
	_world_list.custom_minimum_size = Vector2(620, 280) * UI
	_world_list.item_selected.connect(func(_index: int) -> void: _load_button.disabled = false)
	_world_list.item_activated.connect(func(_index: int) -> void: _load_selected())
	page.add_child(_world_list)
	var row := _row(page)
	_load_button = _button(row, "載入", "LoadSelectedWorld", _load_selected)
	_button(row, "返回", "LoadBack", func() -> void: show_page("main"))

func _refresh_worlds() -> void:
	_worlds = RegionEntry.list_worlds()
	_world_list.clear()
	for meta: Dictionary in _worlds:
		_world_list.add_item(_world_line(meta))
	if _worlds.is_empty(): _world_list.add_item("尚無已保存的世界", null, false)
	_load_button.disabled = true

func _load_selected() -> void:
	var selected := _world_list.get_selected_items()
	if selected.is_empty() or selected[0] >= _worlds.size(): return
	if RegionEntry.request_world(str(_worlds[selected[0]].world_id)):
		get_tree().change_scene_to_file(RegionEntry.SITE_SCENE)

# --- New Game: map choice.

func _build_map_page(parent: Node) -> void:
	var page := _page(parent, "map")
	_label(page, "新遊戲：選擇地圖", 24)
	var taiwan := Button.new()
	taiwan.name = "MapTaiwan"
	taiwan.toggle_mode = true
	taiwan.button_pressed = true
	taiwan.text = "台灣\n內政部 20 公尺數值地形・Site 200 × 200 公尺"
	taiwan.add_theme_font_size_override("font_size", roundi(18 * UI))
	taiwan.custom_minimum_size = Vector2(420, 72) * UI
	page.add_child(taiwan)
	var sources := OptionButton.new()
	sources.name = "TaiwanSourceRule"
	var choices: Array[Dictionary] = RegionEntry.new_world_source_choices()
	var selected_path := str(RegionEntry.draft.get("manifest", RegionData.DEFAULT_MANIFEST))
	for choice: Dictionary in choices:
		sources.add_item(str(choice.label))
		sources.set_item_metadata(sources.item_count - 1, str(choice.path))
		if str(choice.path) == selected_path: sources.select(sources.item_count - 1)
	page.add_child(sources)
	sources.item_selected.connect(func(index: int) -> void:
		RegionEntry.draft["manifest"] = str(sources.get_item_metadata(index))
		RegionEntry.draft.erase("site")) # A source change requires a fresh original start pick.
	_label(page, "地形、水源與資源保持所選來源；舊世界沿原保存來源繼續。", 14)
	_label(page, "隨機地圖與其他地圖之後加入。", 14)
	var row := _row(page)
	_button(row, "返回", "MapBack", func() -> void: show_page("main"))
	_button(row, "下一步：選擇起點", "PickStart", _pick_start)


func _pick_start() -> void:
	RegionEntry.draft["step"] = "pick"
	RegionEntry.region_mode = "pick_start"
	get_tree().change_scene_to_file(RegionEntry.REGION_SCENE)

# --- New Game: character.

func _build_character_page(parent: Node) -> void:
	var page := _page(parent, "character")
	_label(page, "建立人物", 24)
	var body := _row(page)
	_preview_host = Node.new()
	_preview_host.name = "CharacterPreviewHost"
	add_child(_preview_host)
	_preview_rect = TextureRect.new()
	_preview_rect.name = "CharacterPreview"
	_preview_rect.custom_minimum_size = Vector2(320, 420) * UI
	_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	body.add_child(_preview_rect)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 520) * UI
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 8)
	scroll.add_child(form)
	_label(form, "外觀", 20)
	var row := _row(form)
	_label(row, "名字", 16).custom_minimum_size.x = 72 * UI
	_name_input = LineEdit.new()
	_name_input.name = "CharacterName"
	_name_input.max_length = TerrainTestCharacter.MAX_NAME_LENGTH
	_name_input.placeholder_text = "必填"
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_name_input)
	_body_select = _option_row(form, "性別", "CharacterBody")
	_body_select.add_item("男")
	_body_select.add_item("女")
	_body_select.item_selected.connect(func(_index: int) -> void:
		_fill_hair(0)
		_update_preview())
	_hair_select = _option_row(form, "髮型", "CharacterHair")
	_hair_select.item_selected.connect(func(_index: int) -> void: _update_preview())
	_face_select = _option_row(form, "臉", "CharacterFace")
	for option: Dictionary in HumanCharacter3DEditor.PART_SLOTS[0].options:
		if str(option.id) == "none": continue
		_face_select.add_item(str(option.label))
		_face_select.set_item_metadata(_face_select.item_count - 1, str(option.id))
	_face_select.item_selected.connect(func(_index: int) -> void: _update_preview())
	row = _row(form)
	_label(row, "髮色", 16).custom_minimum_size.x = 72 * UI
	_dye_toggle = CheckBox.new()
	_dye_toggle.name = "CharacterHairDyed"
	_dye_toggle.text = "染色"
	_dye_toggle.toggled.connect(func(_on: bool) -> void: _update_preview())
	row.add_child(_dye_toggle)
	_dye_picker = ColorPickerButton.new()
	_dye_picker.name = "CharacterHairDye"
	_dye_picker.color = Color(DEFAULT_HAIR_DYE)
	_dye_picker.edit_alpha = false
	_dye_picker.custom_minimum_size = Vector2(80, 32) * UI
	_dye_picker.color_changed.connect(func(_color: Color) -> void:
		_dye_toggle.button_pressed = true
		_update_preview())
	row.add_child(_dye_picker)
	form.add_child(HSeparator.new())
	_label(form, "能力（0–100）", 20)
	# 技能 K5 (reports/skill-system-plan.md §5.5): one budget of START_POINTS for the four abilities, 學業, the eight lines
	# (counted from 50) and the two aptitudes (counted from 50); 自由分配 lifts the cap.
	row = _row(form)
	_points_label = _label(row, "", 16)
	_points_label.name = "CharacterPoints"
	_free_points = CheckBox.new()
	_free_points.name = "CharacterFreePoints"
	_free_points.text = "自由分配（不設上限）"
	_free_points.toggled.connect(func(_on: bool) -> void: _update_points())
	row.add_child(_free_points)
	for ability: Array in ABILITIES:
		_ability_inputs[ability[0]] = _slider_row(form, str(ability[1]), "", "Ability_" + str(ability[0]))
	_learning_slider = _slider_row(form, "學業", "", "Skill_learning")
	_learning_slider.value = 0
	_label(form, "熟練（50 為尋常）", 17)
	for line: String in PersonSkills.LINES:
		_line_sliders[line] = _slider_row(form, str(PersonSkills.LINE_LABELS[line]), "", "Skill_" + line)
	_label(form, "資質（50 為尋常）", 17)
	for kind: String in PersonSkills.APTITUDES:
		_aptitude_sliders[kind] = _slider_row(form, str(PersonSkills.APTITUDE_LABELS[kind]), "", "Aptitude_" + kind)
	for slider: HSlider in _point_sliders(): slider.value_changed.connect(func(_v: float) -> void: _update_points())
	_update_points()
	form.add_child(HSeparator.new())
	_label(form, "性格（50 為中性）", 20)
	for group: Array in PersonPersonality.GROUPS:
		_label(form, str(group[0]), 17)
		for axis: String in group[1]:
			var names: Array = PersonPersonality.LABELS[axis]
			_personality_sliders[axis] = _slider_row(form, str(names[1]), str(names[0]), "Personality_" + axis)
	_character_error = _label(page, "", 15)
	_character_error.modulate = Color("f0a0a0")
	var buttons := _row(page)
	_button(buttons, "上一步：重選起點", "CharacterBack", _pick_start)
	_button(buttons, "下一步", "CharacterNext", _character_next)
	_fill_hair(0)

func _option_row(parent: Node, text: String, node_name: String) -> OptionButton:
	var row := _row(parent)
	_label(row, text, 16).custom_minimum_size.x = 72 * UI
	var select := OptionButton.new()
	select.name = node_name
	select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(select)
	return select

## Slider 0..100 with value readout. A left label reads 0, a right label 100.
func _slider_row(parent: Node, left: String, right: String, node_name: String) -> HSlider:
	var row := _row(parent)
	_label(row, left, 15).custom_minimum_size.x = 72 * UI
	var slider := HSlider.new()
	slider.name = node_name
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = 50
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 220 * UI
	row.add_child(slider)
	if not right.is_empty(): _label(row, right, 15).custom_minimum_size.x = 72 * UI
	var value := _label(row, "50", 15)
	value.custom_minimum_size.x = 32 * UI
	slider.value_changed.connect(func(v: float) -> void: value.text = str(int(v)))
	return slider

func _fill_hair(selected: int) -> void:
	_hair_select.clear()
	for option: Dictionary in HumanCharacter3DEditor.HAIR_OPTIONS[_body_select.selected]:
		if str(option.id) == "none": continue
		_hair_select.add_item(str(option.label))
		_hair_select.set_item_metadata(_hair_select.item_count - 1, str(option.id))
	_hair_select.select(clampi(selected, 0, _hair_select.item_count - 1))

func character_data() -> Dictionary:
	var personality := PersonPersonality.neutral()
	for axis: String in PersonPersonality.AXES:
		personality[axis] = int(_personality_sliders[axis].value)
	var command := _command_values()
	return {"name": _name_input.text.strip_edges(), "body": _body_select.selected,
		"face": str(_face_select.get_item_metadata(_face_select.selected)),
		"hair": str(_hair_select.get_item_metadata(_hair_select.selected)),
		"hair_dye": _dye_picker.color.to_html(true), "hair_dyed": _dye_toggle.button_pressed,
		"combat_ability": int(_ability_inputs.combat_ability.value),
		"command_abilities": command,
		"personality": personality,
		# 技能 K5: 學業, the chosen lines and aptitude (with titles for 100s), and whether 自由分配 lifted the cap.
		"learning": int(_learning_slider.value),
		"skills": PersonSkills.start_packet(_line_values(), _aptitude_values(), int(_ability_inputs.combat_ability.value), command, int(_learning_slider.value)),
		"free_points": _free_points.button_pressed}

func _command_values() -> Dictionary:
	return {"tactics": int(_ability_inputs.tactics.value), "leadership": int(_ability_inputs.leadership.value), "coach": int(_ability_inputs.coach.value)}

func _line_values() -> Dictionary:
	var values := {}
	for line: String in _line_sliders: values[line] = int(_line_sliders[line].value)
	return values

func _aptitude_values() -> Dictionary:
	var values := {}
	for kind: String in _aptitude_sliders: values[kind] = int(_aptitude_sliders[kind].value)
	return values

func _point_sliders() -> Array:
	return _ability_inputs.values() + [_learning_slider] + _line_sliders.values() + _aptitude_sliders.values()

## 技能 K5 (§5.5): the points the page uses now.
func start_points() -> int:
	return PersonSkills.start_points(int(_ability_inputs.combat_ability.value), _command_values(), int(_learning_slider.value), _line_values(), _aptitude_values())

func points_within_limit() -> bool:
	return _free_points.button_pressed or start_points() <= PersonSkills.START_POINTS

func _update_points() -> void:
	if _points_label == null: return
	var used := start_points()
	if _free_points.button_pressed: _points_label.text = "能力點：已用 %d（自由分配，不設上限）" % used
	else: _points_label.text = "能力點：已用 %d／%d" % [used, PersonSkills.START_POINTS]
	_points_label.modulate = Color.WHITE if points_within_limit() else Color("f0a0a0")

func _restore_character_draft() -> void:
	var data: Dictionary = RegionEntry.draft.get("character", {})
	if data.is_empty():
		_update_preview()
		return
	_name_input.text = str(data.name)
	_body_select.select(int(data.body))
	_fill_hair(0)
	_select_metadata(_hair_select, str(data.hair))
	_select_metadata(_face_select, str(data.face))
	_dye_picker.color = Color(str(data.hair_dye))
	_dye_toggle.button_pressed = bool(data.hair_dyed)
	_ability_inputs.combat_ability.value = int(data.combat_ability)
	for kind: String in ["tactics", "leadership", "coach"]:
		_ability_inputs[kind].value = int(data.command_abilities[kind])
	# 技能 K5: a draft from before K5 has none of these and keeps the defaults.
	_learning_slider.value = int(data.get("learning", 0))
	var packet: Dictionary = data.get("skills", {}) if data.get("skills") is Dictionary else {}
	for line: String in _line_sliders: _line_sliders[line].value = int(PersonSkills.level(packet, line))
	var aptitude: Dictionary = packet.get("aptitude", {}) if packet.get("aptitude") is Dictionary else {}
	for kind: String in _aptitude_sliders: _aptitude_sliders[kind].value = int(aptitude.get(kind, PersonSkills.APTITUDE_MEAN))
	_free_points.button_pressed = bool(data.get("free_points", false))
	_update_points()
	for axis: String in PersonPersonality.AXES:
		_personality_sliders[axis].value = int(data.personality[axis])
	_update_preview()

static func _select_metadata(select: OptionButton, id: String) -> void:
	for index: int in range(select.item_count):
		if str(select.get_item_metadata(index)) == id:
			select.select(index)
			return

func _character_next() -> void:
	var data := character_data()
	if str(data.name).is_empty():
		_character_error.text = "請輸入名字。"
		return
	if not points_within_limit():
		_character_error.text = "能力點已用 %d，超過 %d；請調低某些項目（熟練、資質可壓到 50 以下換回點數），或勾選「自由分配」。" % [start_points(), PersonSkills.START_POINTS]
		return
	_character_error.text = ""
	RegionEntry.draft["character"] = data
	RegionEntry.draft["step"] = "confirm"
	show_page("confirm")

# Preview: one hidden HumanCharacter3DEditor; only its viewport texture is shown.
func _set_preview_active(active: bool) -> void:
	if DisplayServer.get_name() == "headless": return
	if active and _preview_editor == null:
		_preview_window = Window.new()
		_preview_window.visible = false
		add_child(_preview_window)
		_preview_editor = HumanCharacter3DEditor.new()
		_preview_editor.preview_host = _preview_host
		_preview_window.add_child(_preview_editor)
		_preview_editor.open()
		_preview_editor.preview_viewport.size = Vector2i(640, 840)
		_preview_rect.texture = _preview_editor.preview_viewport.get_texture()
		_update_preview()
	if _preview_editor != null:
		_preview_editor.preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED

func _update_preview() -> void:
	if _preview_editor == null or _hair_select.item_count == 0: return
	var data := character_data()
	var appearance := HumanCharacter3DEditor.default_appearance(int(data.body))
	# Plain clothes and no helmet or gear, so face and hair stay visible.
	for slot: String in ["helmet", "cape", "weapon", "shield"]:
		appearance.parts[slot] = "none"
	appearance.parts.armor = "outfit_medieval_chinese_01"
	appearance.parts.face = str(data.face)
	appearance.parts.hair = str(data.hair)
	appearance.hair_dye = str(data.hair_dye)
	appearance.hair_dyed = bool(data.hair_dyed)
	if not _preview_editor.restore_appearance(appearance):
		appearance = HumanCharacter3DEditor.default_appearance(int(data.body))
		appearance.parts.face = str(data.face)
		appearance.parts.hair = str(data.hair)
		_preview_editor.restore_appearance(appearance)
	# Portrait framing instead of the map-sprite profile: whole body, larger.
	var camera: Camera3D = _preview_editor.camera
	if camera != null:
		camera.size = 2.1
		camera.position = Vector3(0.0, 1.0, -4.0) # The model faces -Z.
		camera.look_at_from_position(camera.position, Vector3(0.0, 0.85, 0.0), Vector3.UP)

# --- New Game: confirm.

func _build_confirm_page(parent: Node) -> void:
	var page := _page(parent, "confirm")
	_label(page, "確認新遊戲", 24)
	var row := _row(page)
	_label(row, "世界名稱", 16).custom_minimum_size.x = 96 * UI
	_world_name = LineEdit.new()
	_world_name.name = "WorldName"
	_world_name.max_length = RegionEntry.MAX_WORLD_NAME
	_world_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_world_name.custom_minimum_size.x = 360 * UI
	row.add_child(_world_name)
	_build_initial_scenario_choice(page)
	_summary = _label(page, "", 16)
	_summary.name = "NewGameSummary"
	_summary.custom_minimum_size.x = 560 * UI
	var buttons := _row(page)
	_button(buttons, "上一步", "ConfirmBack", func() -> void: show_page("character"))
	_button(buttons, "開始", "StartGame", start_new_game)

func _refresh_summary() -> void:
	var data: Dictionary = RegionEntry.draft.get("character", {})
	var site: Vector2i = RegionEntry.draft.get("site", Vector2i(-1, -1))
	if _world_name.text.is_empty():
		_world_name.text = "台灣 %s" % Time.get_date_string_from_system()
	var traits: Array[String] = []
	for axis: String in PersonPersonality.AXES:
		var value := int(data.personality[axis])
		if value != PersonPersonality.NEUTRAL:
			traits.append("%s %d" % [str(PersonPersonality.LABELS[axis][0 if value > 50 else 1]), value])
	# 技能 K5: 學業, the lines set away from 50 and the two aptitudes.
	var packet: Dictionary = data.get("skills", {}) if data.get("skills") is Dictionary else {}
	var lines: Array[String] = []
	for line: String in PersonSkills.LINES:
		if PersonSkills.level_milli(packet, line) != PersonSkills.NEUTRAL: lines.append("%s %d" % [str(PersonSkills.LINE_LABELS[line]), int(PersonSkills.level(packet, line))])
	var aptitude: Dictionary = packet.get("aptitude", {}) if packet.get("aptitude") is Dictionary else {}
	_summary.text = "地圖：台灣\n起點 Site：(%d, %d)\n人物：%s（%s）\n能力：武力 %d・戰術 %d・統御 %d・教練 %d・學業 %d\n熟練：%s\n資質：根骨 %d・悟性 %d\n性格：%s" % [
		site.x, site.y, str(data.name), "男" if int(data.body) == 0 else "女", int(data.combat_ability),
		int(data.command_abilities.tactics), int(data.command_abilities.leadership), int(data.command_abilities.coach),
		int(data.get("learning", 0)), "八行皆 50" if lines.is_empty() else "、".join(lines),
		int(aptitude.get("body", PersonSkills.APTITUDE_MEAN)), int(aptitude.get("mind", PersonSkills.APTITUDE_MEAN)),
		"中性" if traits.is_empty() else "、".join(traits)]

## The selected start faction for RegionEntry.request_new_world.
func start_faction_choice() -> Dictionary:
	var mode: String = str(_start_faction.get_item_metadata(_start_faction.selected)) if _start_faction != null and _start_faction.selected >= 0 else "neutral"
	if mode not in ["found", "bandit"]: return {"mode": "neutral"}
	return {"mode": mode, "name": _start_faction_name.text.strip_edges()}

## The 落草 start item is disabled (and left) when the selected scenario sets allow_bandit_start false.
func _refresh_bandit_start() -> void:
	if _start_faction == null or _initial_scenario == null: return
	var allowed := RegionEntry.bandit_start_allowed(str(_initial_scenario.get_item_metadata(_initial_scenario.selected)) if _initial_scenario.selected >= 0 else "")
	_start_faction.set_item_disabled(2, not allowed)
	if not allowed and _start_faction.selected == 2:
		_start_faction.select(0)
		_start_faction_name.visible = false

func start_new_game() -> void:
	var data: Dictionary = RegionEntry.draft.get("character", {})
	var site: Variant = RegionEntry.draft.get("site")
	if data.is_empty() or not site is Vector2i:
		show_page("main")
		return
	var scenario_id := str(_initial_scenario.get_item_metadata(_initial_scenario.selected))
	var start_faction := start_faction_choice()
	if not RegionEntry.request_new_world(site, data, _world_name.text, scenario_id, str(RegionEntry.draft.get("manifest", RegionData.DEFAULT_MANIFEST)), start_faction):
		_message.text = RegionEntry.menu_message
		_message.visible = true
		return
	RegionEntry.draft = {}
	get_tree().change_scene_to_file(RegionEntry.SITE_SCENE)


func _build_initial_scenario_choice(parent: Node) -> void:
	_label(parent, "開局情境", 16)
	_initial_scenario = OptionButton.new()
	_initial_scenario.name = "InitialArtisanScenario"
	_initial_scenario.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Nekki 2026-11-03: a new game starts with cadres, not artisans. The player captains a neutral team with
	# TerrainLab.INITIAL_CADRES cadres. The artisan scenarios stay available to tests only, not in the menu.
	_initial_scenario.add_item("玩家與 %d 名幹部" % TerrainLab.INITIAL_CADRES)
	_initial_scenario.set_item_metadata(0, "")
	parent.add_child(_initial_scenario)
	var draft_id := str(RegionEntry.draft.get("initial_scenario_id", TechnologyArtisans.PRIMARY))
	for index: int in _initial_scenario.item_count:
		if str(_initial_scenario.get_item_metadata(index)) == draft_id: _initial_scenario.select(index)
	_initial_scenario.item_selected.connect(func(index: int) -> void:
		RegionEntry.draft["initial_scenario_id"] = str(_initial_scenario.get_item_metadata(index)))
	_label(parent, "你是隊長；幹部都是軍官，可以各自帶人分隊。起點須能合法安置整隊。", 14)
	# Nekki 2026-11-04 (C): start neutral, or found your own faction (you are its head; hostile to all by default).
	# Joining a scenario faction appears once the world has scenario factions.
	_label(parent, "開局勢力", 16)
	_start_faction = OptionButton.new()
	_start_faction.name = "StartFaction"
	_start_faction.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_faction.add_item("中立（不屬於任何勢力；建國前不能外交或佔領聚落）")
	_start_faction.set_item_metadata(0, "neutral")
	_start_faction.add_item("自建勢力（你是首長；預設與所有勢力敵對）")
	_start_faction.set_item_metadata(1, "found")
	# Bandit spec §10: 落草 start, only when the scenario allows it.
	_start_faction.add_item("落草（你是土匪頭目；與所有人敵對，不能外交、佔領或受封，信譽 −20）")
	_start_faction.set_item_metadata(2, "bandit")
	parent.add_child(_start_faction)
	_start_faction_name = LineEdit.new()
	_start_faction_name.name = "StartFactionName"
	_start_faction_name.placeholder_text = "勢力或山寨名稱（1–32 字）"
	_start_faction_name.max_length = 32
	_start_faction_name.visible = false
	parent.add_child(_start_faction_name)
	var draft_faction: Dictionary = RegionEntry.draft.get("start_faction", {})
	if str(draft_faction.get("mode", "neutral")) in ["found", "bandit"]:
		_start_faction.select(1 if str(draft_faction.mode) == "found" else 2)
		_start_faction_name.text = str(draft_faction.get("name", ""))
		_start_faction_name.visible = true
	_start_faction.item_selected.connect(func(index: int) -> void:
		_start_faction_name.visible = str(_start_faction.get_item_metadata(index)) in ["found", "bandit"])
	_refresh_bandit_start()
	_initial_scenario.item_selected.connect(func(_index: int) -> void: _refresh_bandit_start())
