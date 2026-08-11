class_name CharacterCreator
extends CanvasLayer

signal closed

const CAPTURE_DIR: String = "user://paper_doll_captures"
const SELECTABLE_LAYERS: Array[int] = [
	PaperDollLayerVisual.RenderLayer.BODY,
	PaperDollLayerVisual.RenderLayer.ARMOR,
	PaperDollLayerVisual.RenderLayer.HAIR,
	PaperDollLayerVisual.RenderLayer.HELMET,
	PaperDollLayerVisual.RenderLayer.CAPE,
	PaperDollLayerVisual.RenderLayer.WEAPON,
	PaperDollLayerVisual.RenderLayer.SHIELD,
	PaperDollLayerVisual.RenderLayer.MOUNT_BARDING,
]

@onready var tabs: TabContainer = $Center/Panel/Margin/Layout/Tabs
@onready var close_button: Button = $Center/Panel/Margin/Layout/Header/CloseButton
@onready var gender_option: OptionButton = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/GenderRow/GenderOption
@onready var mounted_toggle: CheckBox = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/MountedToggle
@onready var mount_option: OptionButton = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/MountRow/MountOption
@onready var body_option: OptionButton = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/BodyRow/BodyOption
@onready var armor_option: OptionButton = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/ArmorRow/ArmorOption
@onready var hair_option: OptionButton = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/HairRow/HairOption
@onready var helmet_option: OptionButton = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/HelmetRow/HelmetOption
@onready var cape_option: OptionButton = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/CapeRow/CapeOption
@onready var weapon_option: OptionButton = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/WeaponRow/WeaponOption
@onready var shield_option: OptionButton = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/ShieldRow/ShieldOption
@onready var barding_option: OptionButton = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/BardingRow/BardingOption
@onready var down_button: Button = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/DirectionGrid/DownButton
@onready var up_button: Button = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/DirectionGrid/UpButton
@onready var right_button: Button = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/DirectionGrid/RightButton
@onready var left_button: Button = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/DirectionGrid/LeftButton
@onready var previous_frame_button: Button = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/FrameRow/PreviousFrameButton
@onready var frame_slider: HSlider = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/FrameRow/FrameSlider
@onready var next_frame_button: Button = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/FrameRow/NextFrameButton
@onready var frame_label: Label = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/FrameRow/FrameLabel
@onready var play_pause_button: Button = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/PlaybackRow/PlayPauseButton
@onready var fps_spin: SpinBox = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/PlaybackRow/FPSSpin
@onready var check_all_button: Button = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/ActionRow/CheckAllButton
@onready var export_all_button: Button = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/ActionRow/ExportAllButton
@onready var previous_failure_button: Button = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/FailureRow/PreviousFailureButton
@onready var next_failure_button: Button = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/FailureRow/NextFailureButton
@onready var status_label: Label = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/Status
@onready var direction_label: Label = $Center/Panel/Margin/Layout/Tabs/AssetLab/Preview/Direction
@onready var composer: PaperDollComposer = $Center/Panel/Margin/Layout/Tabs/AssetLab/Preview/PreviewFrame/PreviewViewport/SubViewport/PaperDollComposer
@onready var animation_timer: Timer = $AnimationTimer

var catalog: PaperDollCatalog
var preview_draft: PaperDollPreviewDraft
var current_recipe: PaperDollRecipe
var current_facing: int = PaperDollLayerVisual.Facing.DOWN
var current_frame_x: int = 0
var is_playing: bool = true
var failure_ids: Array[StringName] = []
var failure_index: int = -1
var _layer_options: Dictionary = {}

func _ready() -> void:
	_layer_options = {
		PaperDollLayerVisual.RenderLayer.BODY: body_option,
		PaperDollLayerVisual.RenderLayer.ARMOR: armor_option,
		PaperDollLayerVisual.RenderLayer.HAIR: hair_option,
		PaperDollLayerVisual.RenderLayer.HELMET: helmet_option,
		PaperDollLayerVisual.RenderLayer.CAPE: cape_option,
		PaperDollLayerVisual.RenderLayer.WEAPON: weapon_option,
		PaperDollLayerVisual.RenderLayer.SHIELD: shield_option,
		PaperDollLayerVisual.RenderLayer.MOUNT_BARDING: barding_option,
	}
	tabs.set_tab_title(0, "PC 外觀")
	tabs.set_tab_title(1, "素材實驗室")
	close_button.pressed.connect(close)
	gender_option.item_selected.connect(_on_gender_selected)
	mounted_toggle.toggled.connect(_on_mounted_toggled)
	mount_option.item_selected.connect(_on_mount_selected)
	for layer: int in SELECTABLE_LAYERS:
		var option: OptionButton = _layer_options[layer] as OptionButton
		option.item_selected.connect(_on_layer_selected.bind(layer, option))
	down_button.pressed.connect(_set_facing.bind(PaperDollLayerVisual.Facing.DOWN))
	up_button.pressed.connect(_set_facing.bind(PaperDollLayerVisual.Facing.UP))
	right_button.pressed.connect(_set_facing.bind(PaperDollLayerVisual.Facing.RIGHT))
	left_button.pressed.connect(_set_facing.bind(PaperDollLayerVisual.Facing.LEFT))
	previous_frame_button.pressed.connect(_step_frame.bind(-1))
	next_frame_button.pressed.connect(_step_frame.bind(1))
	frame_slider.value_changed.connect(_on_frame_changed)
	play_pause_button.pressed.connect(_toggle_playback)
	fps_spin.value_changed.connect(_on_fps_changed)
	check_all_button.pressed.connect(run_check_all)
	export_all_button.pressed.connect(export_all_contact_sheets)
	previous_failure_button.pressed.connect(_show_failure.bind(-1))
	next_failure_button.pressed.connect(_show_failure.bind(1))
	animation_timer.timeout.connect(_on_animation_tick)
	hide()

func open(p_catalog: PaperDollCatalog = null) -> void:
	catalog = p_catalog if p_catalog != null else PaperDollCatalog.create_debug_catalog()
	preview_draft = _make_full_draft(PaperDollLayerVisual.Gender.MALE, false)
	current_facing = PaperDollLayerVisual.Facing.DOWN
	current_frame_x = 0
	failure_ids.clear()
	failure_index = -1
	_populate_controls()
	tabs.current_tab = 1
	show()
	_set_playing(true)
	_refresh_preview()

func close() -> void:
	if not visible:
		return
	animation_timer.stop()
	hide()
	closed.emit()

func is_open() -> bool:
	return visible

func draft_copy() -> PaperDollPreviewDraft:
	return preview_draft.copy() if preview_draft != null else null

func run_check_all() -> PackedStringArray:
	if catalog == null:
		return PackedStringArray(["catalog is not loaded"])
	var issues: PackedStringArray = catalog.validation_issues()
	failure_ids = catalog.failing_ids()
	failure_index = -1
	if issues.is_empty():
		status_label.text = "PASS — %d layer visuals, %d mounts" % [
			catalog.layer_visuals.size(),
			catalog.mount_visuals.size(),
		]
	else:
		status_label.text = "FAIL — %d issue(s)\n%s" % [issues.size(), "\n".join(issues)]
	return issues

func export_all_contact_sheets(output_dir: String = CAPTURE_DIR) -> int:
	if catalog == null:
		return 0
	var saved_count: int = 0
	var failed_count: int = 0
	for visual: PaperDollLayerVisual in catalog.layer_visuals:
		if visual == null:
			continue
		for gender: int in [PaperDollLayerVisual.Gender.MALE, PaperDollLayerVisual.Gender.FEMALE]:
			for mounted: bool in [false, true]:
				if visual.render_layer == PaperDollLayerVisual.RenderLayer.MOUNT_BARDING and not mounted:
					continue
				var draft: PaperDollPreviewDraft = _make_isolated_draft(visual, gender, mounted)
				var recipe: PaperDollRecipe = catalog.resolve_recipe(draft)
				if recipe == null:
					failed_count += 1
					continue
				var file_name: String = "%s_%s_%s.png" % [
					visual.visual_id,
					PaperDollLayerVisual.gender_name(gender),
					PaperDollLayerVisual.pose_name(mounted),
				]
				if PaperDollContactSheet.save_png(
						recipe,
						output_dir.path_join(file_name),
						true
					) == OK:
					saved_count += 1
				else:
					failed_count += 1

	for mount: PaperDollMountVisual in catalog.sorted_mounts():
		for gender: int in [PaperDollLayerVisual.Gender.MALE, PaperDollLayerVisual.Gender.FEMALE]:
			var draft: PaperDollPreviewDraft = _make_isolated_mount_draft(mount, gender)
			var recipe: PaperDollRecipe = catalog.resolve_recipe(draft)
			var file_name: String = "%s_%s_mounted.png" % [
				mount.mount_visual_id,
				PaperDollLayerVisual.gender_name(gender),
			]
			if recipe != null and PaperDollContactSheet.save_png(
					recipe,
					output_dir.path_join(file_name),
					true
				) == OK:
				saved_count += 1
			else:
				failed_count += 1

	for mounted: bool in [false, true]:
		var stress_recipe: PaperDollRecipe = catalog.resolve_recipe(
			_make_full_draft(PaperDollLayerVisual.Gender.MALE, mounted)
		)
		if stress_recipe != null and PaperDollContactSheet.save_png(
				stress_recipe,
				output_dir.path_join("stress_%s.png" % PaperDollLayerVisual.pose_name(mounted)),
				true
			) == OK:
			saved_count += 1
		else:
			failed_count += 1
	status_label.text = "Exported %d contact sheets to %s%s" % [
		saved_count,
		ProjectSettings.globalize_path(output_dir),
		"; %d failed" % failed_count if failed_count > 0 else "",
	]
	return saved_count

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
			close()
	get_viewport().set_input_as_handled()

func _populate_controls() -> void:
	gender_option.clear()
	gender_option.add_item("Male", PaperDollLayerVisual.Gender.MALE)
	gender_option.add_item("Female", PaperDollLayerVisual.Gender.FEMALE)
	gender_option.select(preview_draft.gender)
	for layer: int in SELECTABLE_LAYERS:
		var allow_none: bool = layer != PaperDollLayerVisual.RenderLayer.BODY
		_populate_layer_option(_layer_options[layer] as OptionButton, layer, allow_none)
	_populate_mount_option()
	mounted_toggle.set_pressed_no_signal(preview_draft.is_mounted)
	frame_slider.set_value_no_signal(current_frame_x)
	frame_label.text = "%d / 7" % current_frame_x
	_on_fps_changed(fps_spin.value)

func _populate_layer_option(option: OptionButton, layer: int, allow_none: bool) -> void:
	var selected_id: StringName = preview_draft.visual_id_for(layer)
	option.clear()
	if allow_none:
		option.add_item("None")
		option.set_item_metadata(0, &"")
	for visual: PaperDollLayerVisual in catalog.visuals_for_layer(layer):
		var index: int = option.item_count
		option.add_item(_display_name(visual.visual_id))
		option.set_item_metadata(index, visual.visual_id)
	_select_option_metadata(option, selected_id)

func _populate_mount_option() -> void:
	var selected_id: StringName = preview_draft.mount_visual_id
	mount_option.clear()
	mount_option.add_item("None")
	mount_option.set_item_metadata(0, &"")
	for mount: PaperDollMountVisual in catalog.sorted_mounts():
		var index: int = mount_option.item_count
		mount_option.add_item(_display_name(mount.mount_visual_id))
		mount_option.set_item_metadata(index, mount.mount_visual_id)
	_select_option_metadata(mount_option, selected_id)

func _on_gender_selected(index: int) -> void:
	preview_draft.gender = gender_option.get_item_id(index)
	for layer: int in SELECTABLE_LAYERS:
		var selected: PaperDollLayerVisual = catalog.find_visual(preview_draft.visual_id_for(layer))
		if selected != null and selected.resolve(preview_draft.gender, preview_draft.is_mounted) != null:
			continue
		var replacement: StringName = catalog.default_visual_id(
			layer,
			preview_draft.gender,
			preview_draft.is_mounted
		)
		if layer != PaperDollLayerVisual.RenderLayer.BODY and replacement.is_empty():
			preview_draft.set_visual(layer, &"")
		else:
			preview_draft.set_visual(layer, replacement)
	_populate_controls()
	_refresh_preview()

func _on_mounted_toggled(enabled: bool) -> void:
	if enabled and catalog.find_mount(preview_draft.mount_visual_id) == null:
		var mounts: Array[PaperDollMountVisual] = catalog.sorted_mounts()
		if mounts.is_empty():
			mounted_toggle.set_pressed_no_signal(false)
			status_label.text = "Mounted preview requires a mount visual"
			return
		preview_draft.mount_visual_id = mounts[0].mount_visual_id
	preview_draft.is_mounted = enabled
	_populate_controls()
	_refresh_preview()

func _on_mount_selected(index: int) -> void:
	preview_draft.mount_visual_id = _option_visual_id(mount_option, index)
	if preview_draft.is_mounted and preview_draft.mount_visual_id.is_empty():
		preview_draft.is_mounted = false
		mounted_toggle.set_pressed_no_signal(false)
	_refresh_preview()

func _on_layer_selected(index: int, layer: int, option: OptionButton) -> void:
	preview_draft.set_visual(layer, _option_visual_id(option, index))
	_refresh_preview()

func _set_facing(facing: int) -> void:
	current_facing = facing
	_refresh_frame()

func _step_frame(step: int) -> void:
	current_frame_x = posmod(current_frame_x + step, PaperDollLayerVisual.FRAME_COLUMNS)
	frame_slider.set_value_no_signal(current_frame_x)
	_refresh_frame()

func _on_frame_changed(value: float) -> void:
	current_frame_x = clampi(roundi(value), 0, PaperDollLayerVisual.FRAME_COLUMNS - 1)
	_refresh_frame()

func _toggle_playback() -> void:
	_set_playing(not is_playing)

func _set_playing(enabled: bool) -> void:
	is_playing = enabled
	play_pause_button.text = "Pause" if enabled else "Play"
	if enabled and visible:
		animation_timer.start()
	else:
		animation_timer.stop()

func _on_fps_changed(value: float) -> void:
	animation_timer.wait_time = 1.0 / maxf(value, 1.0)
	if is_playing and visible:
		animation_timer.start()

func _on_animation_tick() -> void:
	_step_frame(1)

func _refresh_preview() -> void:
	var issues: PackedStringArray = catalog.validate_draft(preview_draft)
	if not issues.is_empty():
		current_recipe = null
		composer.apply_recipe(null)
		status_label.text = "Preview invalid\n%s" % "\n".join(issues)
		return
	current_recipe = catalog.resolve_recipe(preview_draft)
	composer.apply_recipe(current_recipe)
	status_label.text = "Preview ready — %d visible layers" % current_recipe.visible_layer_count()
	_refresh_frame()

func _refresh_frame() -> void:
	composer.update_frame(current_facing, current_frame_x)
	frame_label.text = "%d / 7" % current_frame_x
	direction_label.text = "Direction: %s%s" % [
		["DOWN", "UP", "RIGHT", "LEFT"][current_facing],
		" (RIGHT row + flip_h)" if current_facing == PaperDollLayerVisual.Facing.LEFT else "",
	]

func _show_failure(step: int) -> void:
	if failure_ids.is_empty():
		status_label.text = "No failing visual entries"
		return
	failure_index = posmod(failure_index + step, failure_ids.size())
	var visual_id: StringName = failure_ids[failure_index]
	var visual: PaperDollLayerVisual = catalog.find_visual(visual_id)
	if visual != null:
		preview_draft.set_visual(visual.render_layer, visual_id)
		if visual.render_layer == PaperDollLayerVisual.RenderLayer.MOUNT_BARDING:
			preview_draft.is_mounted = true
	else:
		var mount: PaperDollMountVisual = catalog.find_mount(visual_id)
		if mount != null:
			preview_draft.mount_visual_id = mount.mount_visual_id
			preview_draft.is_mounted = true
	_populate_controls()
	_refresh_preview()
	status_label.text = "Failure %d/%d: %s\n%s" % [
		failure_index + 1,
		failure_ids.size(),
		visual_id,
		"\n".join(catalog.issues_for_id(visual_id)),
	]

func _make_full_draft(gender: int, mounted: bool) -> PaperDollPreviewDraft:
	var result: PaperDollPreviewDraft = PaperDollPreviewDraft.new()
	result.gender = gender
	result.is_mounted = mounted
	for layer: int in SELECTABLE_LAYERS:
		var visual_id: StringName = catalog.default_visual_id(layer, gender, mounted)
		if not visual_id.is_empty():
			result.set_visual(layer, visual_id)
	var mounts: Array[PaperDollMountVisual] = catalog.sorted_mounts()
	if not mounts.is_empty():
		result.mount_visual_id = mounts[0].mount_visual_id
	return result

func _make_isolated_draft(
		visual: PaperDollLayerVisual,
		gender: int,
		mounted: bool
	) -> PaperDollPreviewDraft:
	var result: PaperDollPreviewDraft = PaperDollPreviewDraft.new()
	result.gender = gender
	result.is_mounted = mounted
	result.set_visual(
		PaperDollLayerVisual.RenderLayer.BODY,
		catalog.default_visual_id(PaperDollLayerVisual.RenderLayer.BODY, gender)
	)
	result.set_visual(visual.render_layer, visual.visual_id)
	if mounted:
		var mounts: Array[PaperDollMountVisual] = catalog.sorted_mounts()
		if not mounts.is_empty():
			result.mount_visual_id = mounts[0].mount_visual_id
	return result

func _make_isolated_mount_draft(
		mount: PaperDollMountVisual,
		gender: int
	) -> PaperDollPreviewDraft:
	var result: PaperDollPreviewDraft = PaperDollPreviewDraft.new()
	result.gender = gender
	result.is_mounted = true
	result.mount_visual_id = mount.mount_visual_id
	result.set_visual(
		PaperDollLayerVisual.RenderLayer.BODY,
		catalog.default_visual_id(PaperDollLayerVisual.RenderLayer.BODY, gender)
	)
	return result

static func _option_visual_id(option: OptionButton, index: int) -> StringName:
	var value: Variant = option.get_item_metadata(index)
	return value as StringName if value is StringName else StringName(str(value))

static func _select_option_metadata(option: OptionButton, visual_id: StringName) -> void:
	for index: int in range(option.item_count):
		if _option_visual_id(option, index) == visual_id:
			option.select(index)
			return
	if option.item_count > 0:
		option.select(0)

static func _display_name(visual_id: StringName) -> String:
	return str(visual_id).replace("_", " ").capitalize()
