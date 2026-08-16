class_name CharacterCreator
extends CanvasLayer

signal closed

const CAPTURE_DIR: String = "user://paper_doll_captures"
# This is the one deterministic acceptance preset.  Alternate hair, armor,
# cape, weapon, shield, barding, and mounts stay selectable below, but opening
# the lab must never silently fall back to the old gold/purple generated look.
const REFERENCE_HAIR_COLOR := Color("e8e9ef")
const REFERENCE_ARMOR_COLOR := Color("b7c1d2")
const REFERENCE_CAPE_COLOR := Color("263653")
const REFERENCE_MOUNT_COLOR := Color("9a704d")
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
@onready var action_option: OptionButton = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/ActionSelectRow/ActionOption
@onready var hair_dye: ColorPickerButton = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/HairDyeRow/HairDye
@onready var armor_dye: ColorPickerButton = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/ArmorDyeRow/ArmorDye
@onready var cape_dye: ColorPickerButton = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/CapeDyeRow/CapeDye
@onready var mount_dye: ColorPickerButton = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/MountDyeRow/MountDye
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
@onready var check_all_button: Button = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/QAActionRow/CheckAllButton
@onready var export_all_button: Button = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/QAActionRow/ExportAllButton
@onready var previous_failure_button: Button = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/FailureRow/PreviousFailureButton
@onready var next_failure_button: Button = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/FailureRow/NextFailureButton
@onready var status_label: Label = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/Status
@onready var crafting_label: Label = $Center/Panel/Margin/Layout/Tabs/AssetLab/Controls/ControlLayout/CraftingRequirements
@onready var direction_label: Label = $Center/Panel/Margin/Layout/Tabs/AssetLab/Preview/Direction
@onready var composer: PaperDollComposer = $Center/Panel/Margin/Layout/Tabs/AssetLab/Preview/PreviewFrame/PreviewViewport/SubViewport/PaperDollComposer
@onready var animation_timer: Timer = $AnimationTimer

var catalog: PaperDollCatalog
var preview_draft: PaperDollPreviewDraft
var current_recipe: PaperDollRecipe
var current_facing: int = PaperDollLayerVisual.Facing.DOWN
var current_frame_x: int = 0
var current_action: int = PaperDollAnimation.Action.IDLE
var is_playing: bool = true
var failure_ids: Array[StringName] = []
var failure_index: int = -1
var _layer_options: Dictionary = {}
var _dye_groups_active: Dictionary = {}

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
	tabs.set_tab_title(0, "PC Appearance")
	tabs.set_tab_title(1, "Asset Lab")
	close_button.pressed.connect(close)
	gender_option.item_selected.connect(_on_gender_selected)
	mounted_toggle.toggled.connect(_on_mounted_toggled)
	action_option.item_selected.connect(_on_action_selected)
	hair_dye.color_changed.connect(_on_hair_dye_changed)
	armor_dye.color_changed.connect(_on_armor_dye_changed)
	cape_dye.color_changed.connect(_on_cape_dye_changed)
	mount_dye.color_changed.connect(_on_mount_dye_changed)
	mount_option.item_selected.connect(_on_mount_selected)
	for render_layer: int in SELECTABLE_LAYERS:
		var option: OptionButton = _layer_options[render_layer] as OptionButton
		option.item_selected.connect(_on_layer_selected.bind(render_layer, option))
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
	# CharacterCreator is normally an overlay instantiated by Main.tscn. When
	# this scene is run directly with Godot's F6, however, there is no Main node
	# to call open(). Defer the check until the scene is registered so direct
	# preview runs use the exact same catalog and refresh path as the modal.
	call_deferred("_open_when_run_as_scene")

func _open_when_run_as_scene() -> void:
	if get_tree().current_scene == self:
		open()

func open(p_catalog: PaperDollCatalog = null) -> void:
	catalog = p_catalog if p_catalog != null else PaperDollCatalog.create_art_gate1_catalog()
	preview_draft = _make_full_draft(PaperDollLayerVisual.Gender.MALE, false)
	current_facing = PaperDollLayerVisual.Facing.DOWN
	current_frame_x = 0
	current_action = PaperDollAnimation.Action.IDLE
	_dye_groups_active.clear()
	# Keep the accepted reference look deterministic while retaining the live
	# dye path used by the pickers.  The old generated gold-hair/purple-cape
	# combination is intentionally not the default anymore.
	hair_dye.color = REFERENCE_HAIR_COLOR
	armor_dye.color = REFERENCE_ARMOR_COLOR
	cape_dye.color = REFERENCE_CAPE_COLOR
	mount_dye.color = REFERENCE_MOUNT_COLOR
	_dye_groups_active[PaperDollComposer.DyeGroup.HAIR_BROWS] = true
	_dye_groups_active[PaperDollComposer.DyeGroup.ARMOR] = true
	_dye_groups_active[PaperDollComposer.DyeGroup.CAPE] = true
	composer.clear_dyes()
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
	_refresh_crafting_requirements()
	failure_ids = catalog.failing_ids()
	failure_index = -1
	if issues.is_empty():
		status_label.text = "PASS ??%d layer visuals, %d mounts" % [
			catalog.layer_visuals.size(),
			catalog.mount_visuals.size(),
		]
	else:
		status_label.text = "FAIL ??%d issue(s)\n%s" % [issues.size(), "\n".join(issues)]
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

func _unhandled_input(event: InputEvent) -> void:
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
	for render_layer: int in SELECTABLE_LAYERS:
		var allow_none: bool = render_layer != PaperDollLayerVisual.RenderLayer.BODY
		_populate_layer_option(_layer_options[render_layer] as OptionButton, render_layer, allow_none)
	_populate_mount_option()
	_populate_action_option()
	mounted_toggle.set_pressed_no_signal(preview_draft.is_mounted)
	frame_slider.set_value_no_signal(current_frame_x)
	frame_label.text = "%d / 7" % current_frame_x
	_on_fps_changed(fps_spin.value)

func _populate_layer_option(option: OptionButton, render_layer: int, allow_none: bool) -> void:
	var selected_id: StringName = preview_draft.visual_id_for(render_layer)
	option.clear()
	if allow_none:
		option.add_item("None")
		option.set_item_metadata(0, &"")
	for visual: PaperDollLayerVisual in catalog.visuals_for_layer(render_layer):
		if render_layer == PaperDollLayerVisual.RenderLayer.HAIR \
				and visual.visual_id not in PaperDollCatalog.APPROVED_HAIR_IDS:
			continue
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

func _populate_action_option() -> void:
	action_option.clear()
	for action: int in range(PaperDollAnimation.Action.COUNT):
		action_option.add_item(PaperDollAnimation.action_name(action), action)
	action_option.select(preview_draft.action)

func _on_gender_selected(index: int) -> void:
	preview_draft.gender = gender_option.get_item_id(index)
	# Body is a gender-owned slot, not a generic unisex fallback.  The old
	# resolver kept `body_male_default` because that sheet was technically valid
	# for both genders, so the UI said Female while the mounted preview still
	# rendered the male head (and therefore appeared to lose the female eyes).
	# Resolve the canonical body ID explicitly before repairing optional slots.
	var body_id: StringName = catalog.default_visual_id(
		PaperDollLayerVisual.RenderLayer.BODY,
		preview_draft.gender,
		preview_draft.is_mounted
	)
	if not body_id.is_empty():
		preview_draft.set_visual(PaperDollLayerVisual.RenderLayer.BODY, body_id)
	for render_layer: int in SELECTABLE_LAYERS:
		var selected_id: StringName = preview_draft.visual_id_for(render_layer)
		# An empty optional slot is an intentional None choice.  Gender changes
		# must not silently equip the catalog's helmet/weapon/shield defaults, or
		# an armed composite would cover every hairstyle in the next preview.
		if selected_id.is_empty() \
			and render_layer != PaperDollLayerVisual.RenderLayer.BODY \
			and render_layer != PaperDollLayerVisual.RenderLayer.MOUNT_BARDING:
			continue
		var selected: PaperDollLayerVisual = catalog.find_visual(selected_id)
		if selected != null and selected.resolve(preview_draft.gender, preview_draft.is_mounted) != null:
			continue
		var replacement: StringName = catalog.default_visual_id(
			render_layer,
			preview_draft.gender,
			preview_draft.is_mounted
		)
		if render_layer != PaperDollLayerVisual.RenderLayer.BODY and replacement.is_empty():
			preview_draft.set_visual(render_layer, &"")
		else:
			preview_draft.set_visual(render_layer, replacement)
	_populate_controls()
	_refresh_preview()

func _on_action_selected(index: int) -> void:
	var selected: int = action_option.get_item_id(index)
	if not PaperDollAnimation.is_valid_action(selected):
		return
	current_action = selected
	preview_draft.action = selected
	var frames: PackedInt32Array = PaperDollAnimation.frames_for(selected)
	current_frame_x = frames[0] if not frames.is_empty() else 0
	fps_spin.set_value_no_signal(PaperDollAnimation.default_fps(selected))
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
	for render_layer: int in SELECTABLE_LAYERS:
		var selected_id: StringName = preview_draft.visual_id_for(render_layer)
		# An empty optional slot is an intentional "None" choice.  Preserve it
		# across pose changes; only the required body and mounted-only barding
		# receive an automatic default.
		if selected_id.is_empty() \
			and render_layer != PaperDollLayerVisual.RenderLayer.BODY \
			and render_layer != PaperDollLayerVisual.RenderLayer.MOUNT_BARDING:
			continue
		# The accepted mounted reference already contains the horse and rider in
		# one aligned board.  Do not silently add a separate barding overlay when
		# the user merely toggles the reference character onto the horse.
		if selected_id.is_empty() \
			and render_layer == PaperDollLayerVisual.RenderLayer.MOUNT_BARDING \
			and _is_reference_default_selection():
			continue
		var selected: PaperDollLayerVisual = catalog.find_visual(selected_id)
		if selected != null and selected.resolve(preview_draft.gender, enabled) != null:
			continue
		var replacement: StringName = catalog.default_visual_id(
			render_layer,
			preview_draft.gender,
			enabled
		)
		if render_layer != PaperDollLayerVisual.RenderLayer.BODY and replacement.is_empty():
			preview_draft.set_visual(render_layer, &"")
		else:
			preview_draft.set_visual(render_layer, replacement)
	_populate_controls()
	_refresh_preview()

func _on_mount_selected(index: int) -> void:
	preview_draft.mount_visual_id = _option_visual_id(mount_option, index)
	if preview_draft.is_mounted and preview_draft.mount_visual_id.is_empty():
		preview_draft.is_mounted = false
		mounted_toggle.set_pressed_no_signal(false)
	_refresh_preview()

func _on_layer_selected(index: int, render_layer: int, option: OptionButton) -> void:
	preview_draft.set_visual(render_layer, _option_visual_id(option, index))
	_refresh_preview()

func _set_facing(facing: int) -> void:
	current_facing = facing
	_refresh_frame()

func _step_frame(step: int) -> void:
	var frames: PackedInt32Array = PaperDollAnimation.frames_for(current_action)
	var current_index: int = frames.find(current_frame_x)
	if current_index < 0:
		current_index = 0
	current_frame_x = frames[posmod(current_index + step, frames.size())] if not frames.is_empty() else 0
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
	_refresh_crafting_requirements()
	var issues: PackedStringArray = catalog.validate_draft(preview_draft)
	if not issues.is_empty():
		current_recipe = null
		composer.apply_recipe(null)
		status_label.text = "Preview invalid\n%s" % "\n".join(issues)
		return
	current_recipe = catalog.resolve_recipe(preview_draft)
	if current_recipe == null:
		composer.apply_recipe(null)
		status_label.text = "Preview could not resolve selected parts"
		return
	composer.apply_recipe(current_recipe)
	_apply_dyes()
	_update_playback_availability()
	status_label.text = "Alignment standard: white hair / silver armor / navy cape | %d selected layers | %s | hair+brows / armor / cape / mount dyes" % [
		current_recipe.visible_layer_count(),
		PaperDollAnimation.action_name(current_action),
	]
	if current_recipe.texture_for(PaperDollLayerVisual.RenderLayer.MOUNT_BARDING) != null:
		status_label.text += " | MountBarding overlay"
	if _is_accepted_reference_body(current_recipe):
		status_label.text += " | calibrated base set; selected hair composited"
	elif _recipe_uses_procedural_action(current_recipe):
		status_label.text += " | reference-locked split layers + synchronized fallback"
	elif current_action != PaperDollAnimation.Action.IDLE:
		status_label.text += " | authored split action"
	else:
		status_label.text += " | reference split layers"
	_refresh_frame()

func _refresh_crafting_requirements() -> void:
	if crafting_label == null:
		return
	if catalog == null or preview_draft == null:
		crafting_label.text = "Crafting materials: catalog not loaded"
		return
	var lines: PackedStringArray = ["Crafting materials (world resources)"]
	var found_recipe: bool = false
	for render_layer: int in [
		PaperDollLayerVisual.RenderLayer.ARMOR,
		PaperDollLayerVisual.RenderLayer.HELMET,
	]:
		var visual_id: StringName = preview_draft.visual_id_for(render_layer)
		var recipe: Resource = catalog.crafting_recipe_for(visual_id)
		if recipe == null:
			continue
		found_recipe = true
		lines.append("%s: %s" % [recipe.get("display_name"), recipe.call("requirements_text")])
	if not found_recipe:
		lines.append("Select Light armor or Light armor helmet to see requirements")
	crafting_label.text = "\n".join(lines)

func _is_accepted_reference_body(recipe: PaperDollRecipe) -> bool:
	return recipe != null and recipe.is_accepted_reference

func _is_reference_default_selection() -> bool:
	if preview_draft == null:
		return false
	return preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.BODY) in [
		&"body_male_default", &"body_female_default"
	] \
		and preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.ARMOR) == &"artgate1_armor" \
		and (preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.HAIR) \
			in PaperDollCatalog.APPROVED_HAIR_IDS \
			or preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.HAIR) in [
				&"hair_male_default", &"hair_female_default", &"alt_braided_hair"
			]) \
		and preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.CAPE) == &"artgate1_cape" \
		and preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.HELMET) in [
			&"", &"artgate1_helmet"
		] \
		and preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.WEAPON) in [
			&"", &"artgate1_weapon"
		] \
		and preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.SHIELD) in [
			&"", &"artgate1_shield"
		] \
		and preview_draft.mount_visual_id == &"artgate1_horse"

func _apply_dyes() -> void:
	var controls: Dictionary = {
		PaperDollComposer.DyeGroup.HAIR_BROWS: hair_dye,
		PaperDollComposer.DyeGroup.ARMOR: armor_dye,
		PaperDollComposer.DyeGroup.CAPE: cape_dye,
		PaperDollComposer.DyeGroup.MOUNT: mount_dye,
	}
	for group: int in _dye_groups_active.keys():
		if _dye_groups_active[group] and controls.has(group):
			composer.set_dye(group, (controls[group] as ColorPickerButton).color)

func _on_hair_dye_changed(color: Color) -> void:
	_dye_groups_active[PaperDollComposer.DyeGroup.HAIR_BROWS] = true
	composer.set_dye(PaperDollComposer.DyeGroup.HAIR_BROWS, color)

func _on_armor_dye_changed(color: Color) -> void:
	_dye_groups_active[PaperDollComposer.DyeGroup.ARMOR] = true
	composer.set_dye(PaperDollComposer.DyeGroup.ARMOR, color)

func _on_cape_dye_changed(color: Color) -> void:
	_dye_groups_active[PaperDollComposer.DyeGroup.CAPE] = true
	composer.set_dye(PaperDollComposer.DyeGroup.CAPE, color)

func _on_mount_dye_changed(color: Color) -> void:
	_dye_groups_active[PaperDollComposer.DyeGroup.MOUNT] = true
	composer.set_dye(PaperDollComposer.DyeGroup.MOUNT, color)

func _update_playback_availability() -> void:
	var animated: bool = _recipe_has_frame_variation(current_recipe)
	gender_option.disabled = false
	mount_option.disabled = false
	mounted_toggle.disabled = false
	for render_layer: int in SELECTABLE_LAYERS:
		var option: OptionButton = _layer_options[render_layer] as OptionButton
		option.disabled = render_layer == PaperDollLayerVisual.RenderLayer.BODY \
			and option.item_count <= 0
	action_option.disabled = current_recipe == null
	play_pause_button.disabled = not animated
	fps_spin.editable = animated
	previous_frame_button.disabled = not animated
	next_frame_button.disabled = not animated
	frame_slider.editable = animated
	if not animated:
		_set_playing(false)
		play_pause_button.text = "Static clip"
	elif not is_playing:
		play_pause_button.text = "Play"

static func _recipe_has_frame_variation(recipe: PaperDollRecipe) -> bool:
	return recipe != null and PaperDollAnimation.frames_for(recipe.action).size() > 1

func _recipe_uses_procedural_action(recipe: PaperDollRecipe) -> bool:
	if recipe == null or recipe.is_accepted_reference \
		or recipe.action == PaperDollAnimation.Action.IDLE:
		return false
	# Catalog resolves a generated split action sheet when no authored sheet is
	# available. Keep this label explicit so the lab never claims a generated
	# clip is dedicated art, while still showing that the action is real and
	# synchronized across all selected parts.
	for render_layer: int in range(PaperDollLayerVisual.RenderLayer.COUNT):
		var texture: Texture2D = recipe.texture_for(render_layer)
		if texture == null:
			continue
		if render_layer == PaperDollLayerVisual.RenderLayer.MOUNT_TAIL \
				or render_layer == PaperDollLayerVisual.RenderLayer.MOUNT_BODY \
				or render_layer == PaperDollLayerVisual.RenderLayer.MOUNT_HEAD:
			continue
		var visual: PaperDollLayerVisual = catalog.find_visual(preview_draft.visual_id_for(render_layer))
		if visual != null and not visual.has_action_sheet(preview_draft.is_mounted, recipe.action):
			return true
	return false

func _refresh_frame() -> void:
	composer.update_frame(current_facing, current_frame_x)
	var clip: PackedInt32Array = PaperDollAnimation.frames_for(current_action)
	var clip_index: int = clip.find(current_frame_x)
	frame_label.text = "Frame %d | clip %d/%d" % [
		current_frame_x,
		clip_index + 1 if clip_index >= 0 else 0,
		clip.size(),
	]
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
	for render_layer: int in SELECTABLE_LAYERS:
		var visual_id: StringName = catalog.default_visual_id(render_layer, gender, mounted)
		# The default acceptance look is the requested white/silver-haired
		# silhouette.  Helmet remains an independently selectable part, but it is
		# intentionally opt-in so it cannot cover or leak over the default hair.
		if render_layer in [
			PaperDollLayerVisual.RenderLayer.HELMET,
			PaperDollLayerVisual.RenderLayer.SHIELD,
			PaperDollLayerVisual.RenderLayer.WEAPON,
		]:
			continue
		if not visual_id.is_empty():
			result.set_visual(render_layer, visual_id)
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
	match visual_id:
		&"hair_short_spiky":
			return "Short spiky hair"
		&"hair_high_ponytail":
			return "High ponytail"
		&"hair_bob":
			return "Shoulder-length bob"
		&"hair_twin_braids":
			return "Twin braids"
		&"hair_long_side_ponytail":
			return "Long side ponytail"
		&"hair_crown_braid":
			return "Crown braid"
		&"hair_low_bun":
			return "Low bun"
		&"hair_undercut_sweep":
			return "Swept undercut"
	if visual_id == &"alt_braided_hair":
		return "Braided hair"
	return str(visual_id).replace("_", " ").capitalize()
