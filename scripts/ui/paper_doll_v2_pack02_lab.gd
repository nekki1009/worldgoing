class_name PaperDollV2Pack02Lab
extends Control

## Isolated V2 variable-slot laboratory.
##
## This scene never writes to the formal V2 manifest.  It asks the catalog for
## a detached Pack 02 staging view, then feeds a PaperDollV2Recipe to the same
## fixed Sprite2D pool used by the production V2 composer.

const PREVIEW_SIZE := Vector2i(560, 620)
const PREVIEW_SCALE := 6.0
const SLOT_LAYERS: Array[int] = [
	PaperDollV2Contract.RenderLayer.HAIR,
	PaperDollV2Contract.RenderLayer.ARMOR,
	PaperDollV2Contract.RenderLayer.BOOTS,
	PaperDollV2Contract.RenderLayer.HELMET,
	PaperDollV2Contract.RenderLayer.CAPE,
	PaperDollV2Contract.RenderLayer.WEAPON,
	PaperDollV2Contract.RenderLayer.SHIELD,
	PaperDollV2Contract.RenderLayer.MOUNT_TAIL,
	PaperDollV2Contract.RenderLayer.MOUNT_BODY,
	PaperDollV2Contract.RenderLayer.MOUNT_HEAD,
	PaperDollV2Contract.RenderLayer.MOUNT_BARDING,
]
const DEFAULT_PACK02: Dictionary = {
	PaperDollV2Contract.RenderLayer.HAIR: &"pack02_hair_short_braid_01",
	PaperDollV2Contract.RenderLayer.ARMOR: &"pack02_leather_scale_armor_01",
	PaperDollV2Contract.RenderLayer.BOOTS: &"pack02_riding_boots_01",
	# Keep the default preview face-readable.  Helmet/weapon/shield remain fully
	# selectable below; they are intentionally opt-in because this staging art
	# is not yet the accepted visual composite.
	PaperDollV2Contract.RenderLayer.HELMET: &"",
	PaperDollV2Contract.RenderLayer.CAPE: &"pack02_forest_cape_01",
	PaperDollV2Contract.RenderLayer.WEAPON: &"",
	PaperDollV2Contract.RenderLayer.SHIELD: &"",
	PaperDollV2Contract.RenderLayer.MOUNT_TAIL: &"pack02_chestnut_horse_tail_01",
	PaperDollV2Contract.RenderLayer.MOUNT_BODY: &"pack02_chestnut_horse_body_01",
	PaperDollV2Contract.RenderLayer.MOUNT_HEAD: &"pack02_chestnut_horse_head_01",
	PaperDollV2Contract.RenderLayer.MOUNT_BARDING: &"pack02_forest_barding_01",
}

var catalog: PaperDollV2Catalog
var composer: PaperDollV2Composer
var viewport: SubViewport
var gender_option: OptionButton
var mounted_toggle: CheckBox
var play_button: Button
var frame_slider: HSlider
var frame_label: Label
var status_label: Label
var direction_buttons: Array[Button] = []
var slot_options: Dictionary = {}
var state := PaperDollV2Contract.RenderState.ON_FOOT
var gender := PaperDollV2Contract.Gender.MALE
var facing := PaperDollV2Contract.Facing.DOWN
var frame_x := 0
var playing := true
var timer: Timer

func _ready() -> void:
	_build_ui()
	catalog = PaperDollV2Catalog.load_staging_pack_02()
	if catalog == null or not catalog.last_issues.is_empty():
		status_label.text = "PACK 02 LOAD FAIL\n%s" % "; ".join(catalog.last_issues)
		return
	_populate_slot_options()
	_refresh()

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("0b1018")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var root_column := VBoxContainer.new()
	root_column.add_theme_constant_override("separation", 10)
	margin.add_child(root_column)
	var title := Label.new()
	title.text = "WORLDGOING — Paper Doll V2 / Pack 02 Staging Lab"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	root_column.add_child(title)

	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 16)
	root_column.add_child(split)

	var controls := VBoxContainer.new()
	controls.custom_minimum_size = Vector2(360, 0)
	controls.add_theme_constant_override("separation", 6)
	split.add_child(controls)
	var warning := Label.new()
	warning.text = "STAGING ONLY — formal V2 manifest untouched"
	warning.modulate = Color("ffcf66")
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(warning)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	controls.add_child(toolbar)
	gender_option = OptionButton.new()
	gender_option.custom_minimum_size = Vector2(150, 34)
	gender_option.add_item("Male", PaperDollV2Contract.Gender.MALE)
	gender_option.add_item("Female", PaperDollV2Contract.Gender.FEMALE)
	gender_option.select(gender)
	gender_option.item_selected.connect(_on_gender_selected)
	toolbar.add_child(gender_option)
	mounted_toggle = CheckBox.new()
	mounted_toggle.text = "Mounted 64×96"
	mounted_toggle.toggled.connect(_on_mounted_toggled)
	toolbar.add_child(mounted_toggle)

	for layer: int in SLOT_LAYERS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		controls.add_child(row)
		var label := Label.new()
		label.text = "%s" % PaperDollV2Contract.layer_name(layer)
		label.custom_minimum_size = Vector2(120, 30)
		row.add_child(label)
		var option := OptionButton.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.custom_minimum_size = Vector2(220, 30)
		option.set_meta("render_layer", layer)
		option.item_selected.connect(_on_slot_selected.bind(layer))
		row.add_child(option)
		slot_options[layer] = option

	var direction_label := Label.new()
	direction_label.text = "Direction"
	controls.add_child(direction_label)
	var direction_bar := HBoxContainer.new()
	direction_bar.add_theme_constant_override("separation", 5)
	controls.add_child(direction_bar)
	for direction: int in range(4):
		var button := Button.new()
		button.text = ["DOWN", "UP", "RIGHT", "LEFT"][direction]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_set_facing.bind(direction))
		direction_bar.add_child(button)
		direction_buttons.append(button)

	var frame_bar := HBoxContainer.new()
	frame_bar.add_theme_constant_override("separation", 8)
	controls.add_child(frame_bar)
	frame_slider = HSlider.new()
	frame_slider.min_value = 0
	frame_slider.max_value = PaperDollV2Contract.FRAME_COLUMNS - 1
	frame_slider.step = 1
	frame_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame_slider.value_changed.connect(_on_frame_changed)
	frame_bar.add_child(frame_slider)
	frame_label = Label.new()
	frame_label.custom_minimum_size = Vector2(80, 0)
	frame_bar.add_child(frame_label)
	play_button = Button.new()
	play_button.text = "Pause"
	play_button.pressed.connect(_toggle_play)
	controls.add_child(play_button)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(0, 80)
	controls.add_child(status_label)

	var preview_column := VBoxContainer.new()
	preview_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(preview_column)
	var preview_title := Label.new()
	preview_title.text = "Pack 02 variable-slot preview — Anchor cross is cyan"
	preview_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_column.add_child(preview_title)
	var host := SubViewportContainer.new()
	host.custom_minimum_size = Vector2(PREVIEW_SIZE)
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.stretch = false
	preview_column.add_child(host)
	viewport = SubViewport.new()
	viewport.size = PREVIEW_SIZE
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	host.add_child(viewport)
	composer = PaperDollV2Composer.new()
	viewport.add_child(composer)

	timer = Timer.new()
	timer.wait_time = 0.125
	timer.autostart = true
	timer.timeout.connect(_on_animation_tick)
	add_child(timer)

func _populate_slot_options() -> void:
	for layer: int in SLOT_LAYERS:
		var option: OptionButton = slot_options[layer] as OptionButton
		option.clear()
		option.add_item("None")
		option.set_item_metadata(0, StringName(""))
		var seen: Dictionary = {}
		for manifest: PaperDollV2AssetManifest in catalog.manifests:
			if manifest == null or not str(manifest.visual_id).begins_with("pack02_") \
					or manifest.render_layer != layer or seen.has(manifest.visual_id):
				continue
			seen[manifest.visual_id] = true
			var index := option.item_count
			option.add_item(str(manifest.visual_id).trim_prefix("pack02_"))
			option.set_item_metadata(index, manifest.visual_id)
		_select_slot(layer, DEFAULT_PACK02.get(layer, StringName("")))

func _on_gender_selected(index: int) -> void:
	if gender_option != null:
		gender_option.select(index)
	gender = gender_option.get_item_id(index)
	_populate_slot_options()
	_refresh()

func _on_mounted_toggled(value: bool) -> void:
	if mounted_toggle != null:
		mounted_toggle.set_pressed_no_signal(value)
	state = PaperDollV2Contract.RenderState.MOUNTED if value else PaperDollV2Contract.RenderState.ON_FOOT
	frame_x = 0
	_refresh()

func _on_slot_selected(index: int, layer: int) -> void:
	_refresh()

func _set_facing(value: int) -> void:
	facing = value
	_refresh_frame()

func _on_frame_changed(value: float) -> void:
	frame_x = clampi(roundi(value), 0, PaperDollV2Contract.FRAME_COLUMNS - 1)
	_refresh_frame()

func _toggle_play() -> void:
	playing = not playing
	play_button.text = "Pause" if playing else "Play"

func _on_animation_tick() -> void:
	if not playing:
		return
	frame_x = posmod(frame_x + 1, PaperDollV2Contract.FRAME_COLUMNS)
	frame_slider.set_value_no_signal(frame_x)
	_refresh_frame()

func _refresh() -> void:
	if catalog == null or composer == null:
		return
	for layer: int in SLOT_LAYERS:
		var option: OptionButton = slot_options[layer] as OptionButton
		option.disabled = state == PaperDollV2Contract.RenderState.ON_FOOT \
			and PaperDollV2Contract.is_mount_layer(layer)
	var selection := _selection()
	var body_id := _body_visual_id()
	var recipe := catalog.resolve_recipe(gender, state, selection, body_id, true)
	if recipe == null:
		composer.visible = false
		status_label.text = "RECIPE FAIL\n%s" % "; ".join(catalog.last_issues)
		return
	if not composer.apply_recipe(recipe):
		composer.visible = false
		status_label.text = "COMPOSER FAIL\n%s" % composer.last_error
		return
	composer.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	composer.position = Vector2(PREVIEW_SIZE.x * 0.5, 500)
	composer.visible = true
	status_label.text = "STAGING PASS | 11 variable slots selectable | visible layers=%d | %s | %s | baseline manifest untouched" % [
		composer.visible_sprite_count(),
		PaperDollV2Contract.gender_name(gender),
		PaperDollV2Contract.state_name(state),
	]
	_refresh_frame()

func _refresh_frame() -> void:
	if composer != null:
		composer.update_frame(facing, frame_x)
	if frame_label != null:
		frame_label.text = "Frame %d/7" % frame_x

func _selection() -> Dictionary:
	var result: Dictionary = {}
	for layer: int in SLOT_LAYERS:
		if state == PaperDollV2Contract.RenderState.ON_FOOT and PaperDollV2Contract.is_mount_layer(layer):
			continue
		var option: OptionButton = slot_options[layer] as OptionButton
		if option.selected < 0:
			continue
		var value: Variant = option.get_item_metadata(option.selected)
		if value is StringName and not StringName(value).is_empty():
			result[layer] = value
	return result

func _body_visual_id() -> StringName:
	var prefix := "body_female_default" if gender == PaperDollV2Contract.Gender.FEMALE else "body_male_default"
	var pose := "mounted" if state == PaperDollV2Contract.RenderState.MOUNTED else "on_foot"
	return StringName("%s_%s_unisex" % [prefix, pose])

func _select_slot(layer: int, visual_id: StringName) -> void:
	var option: OptionButton = slot_options[layer] as OptionButton
	for index: int in range(option.item_count):
		if option.get_item_metadata(index) == visual_id:
			option.select(index)
			return
	option.select(0)
