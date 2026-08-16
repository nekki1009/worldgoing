class_name PaperDollV2Lab
extends Control

## Standalone V2 material lab.  It deliberately does not share the V1
## CharacterCreator catalog or Composer, so the state-sized contract is visible
## and testable on its own while migration is in progress.

@onready var gender_option: OptionButton = $Layout/Toolbar/Gender
@onready var mounted_toggle: CheckBox = $Layout/Toolbar/Mounted
@onready var play_button: Button = $Layout/Toolbar/Play
@onready var direction_buttons: Array[Button] = [
	$Layout/DirectionBar/Down,
	$Layout/DirectionBar/Up,
	$Layout/DirectionBar/Right,
	$Layout/DirectionBar/Left,
]
@onready var frame_slider: HSlider = $Layout/FrameBar/Slider
@onready var frame_label: Label = $Layout/FrameBar/Label
@onready var status_label: Label = $Layout/Status
@onready var contract_label: Label = $Layout/PreviewColumn/Contract
@onready var viewport: SubViewport = $Layout/PreviewColumn/Preview/ViewportHost/Viewport
@onready var composer: PaperDollV2Composer = $Layout/PreviewColumn/Preview/ViewportHost/Viewport/PaperDollV2Composer
@onready var animation_timer: Timer = $AnimationTimer

var catalog: PaperDollV2Catalog
var gender: int = PaperDollV2Contract.Gender.MALE
var state: int = PaperDollV2Contract.RenderState.ON_FOOT
var facing: int = PaperDollV2Contract.Facing.DOWN
var frame_x: int = 0
var playing := true

# The preview viewport is deliberately larger than one source frame.  The
# composer is placed at a screen-space anchor inside this area so the
# calibrated character is centered in the lab instead of appearing at the
# container's top-left corner.
const PREVIEW_SIZE := Vector2i(640, 580)
const PREVIEW_SCALE := 8.0

func _ready() -> void:
	catalog = PaperDollV2Catalog.load_generated_pack()
	gender_option.add_item("Male", PaperDollV2Contract.Gender.MALE)
	gender_option.add_item("Female", PaperDollV2Contract.Gender.FEMALE)
	gender_option.select(gender)
	gender_option.item_selected.connect(_on_gender_selected)
	mounted_toggle.toggled.connect(_on_mounted_toggled)
	play_button.pressed.connect(_toggle_play)
	for index: int in range(direction_buttons.size()):
		direction_buttons[index].pressed.connect(_set_facing.bind(index))
	frame_slider.value_changed.connect(_on_frame_changed)
	animation_timer.timeout.connect(_on_animation_tick)
	_refresh()

func _on_gender_selected(index: int) -> void:
	gender = index
	# Keep programmatic Recipe changes (used by captures/tests) visually in
	# sync with the controls; OptionButton.item_selected is not re-emitted by
	# `select()`.
	if gender_option != null and gender_option.selected != gender:
		gender_option.select(gender)
	_refresh()

func _on_mounted_toggled(value: bool) -> void:
	state = PaperDollV2Contract.RenderState.MOUNTED if value else PaperDollV2Contract.RenderState.ON_FOOT
	if mounted_toggle != null and mounted_toggle.button_pressed != value:
		mounted_toggle.button_pressed = value
	frame_x = 0
	_refresh()

func _set_facing(value: int) -> void:
	facing = value
	_refresh_frame()

func _on_frame_changed(value: float) -> void:
	frame_x = clampi(roundi(value), 0, PaperDollV2Contract.FRAME_COLUMNS - 1)
	_refresh_frame()

func _toggle_play() -> void:
	playing = not playing
	animation_timer.paused = not playing
	play_button.text = "Pause" if playing else "Play"

func _on_animation_tick() -> void:
	if not playing:
		return
	frame_x = PaperDollV2Animation.next_frame(PaperDollV2Animation.Action.WALK, frame_x)
	frame_slider.value = frame_x
	_refresh_frame()

func _refresh() -> void:
	# The lab is a reference-calibration surface.  Do not leave the previous
	# split-part recipe visible while a new gender/state is being resolved: a
	# stale composition is much worse than an explicit unavailable state.
	composer.visible = false
	var frame_size := PaperDollV2Contract.frame_size(state)
	var anchor := PaperDollV2Contract.anchor_px(state)
	viewport.size = PREVIEW_SIZE
	composer.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	# Calibrated boards use a 56 px visible silhouette height.  Place the
	# contact point so that that silhouette, not the transparent frame padding,
	# is vertically centered for both 64x64 and 64x96 states.
	var content_height := 56.0 * PREVIEW_SCALE
	composer.position = Vector2(PREVIEW_SIZE.x * 0.5, (PREVIEW_SIZE.y + content_height) * 0.5)
	frame_slider.max_value = PaperDollV2Contract.FRAME_COLUMNS - 1
	frame_slider.value = frame_x
	contract_label.text = "REFERENCE CALIBRATED  |  %s  |  frame %s  |  Anchor %s  |  8×3 + LEFT mirror" % [
		"MOUNTED 64×96" if state == PaperDollV2Contract.RenderState.MOUNTED else "ON FOOT 64×64",
		Vector2i(frame_size),
		anchor,
	]
	var reference_id: StringName
	if gender == PaperDollV2Contract.Gender.FEMALE:
		reference_id = &"reference_female_body_mounted" if state == PaperDollV2Contract.RenderState.MOUNTED else &"reference_female_body_on_foot"
	else:
		reference_id = &"reference_body_mounted" if state == PaperDollV2Contract.RenderState.MOUNTED else &"reference_body_on_foot"
	var recipe := catalog.resolve_reference_recipe(gender, state, reference_id) if catalog != null else null
	if recipe == null:
		status_label.text = "REFERENCE FAIL: %s" % catalog.last_issues if catalog != null else "REFERENCE FAIL: catalog unavailable"
		return
	if not composer.apply_recipe(recipe):
		status_label.text = "REFERENCE FAIL: %s" % composer.last_error
		return
	# A calibrated board is already the exact white-hair/silver-armor/navy-
	# cape reference.  Palette dyes are intentionally disabled here because a
	# flattened reference image has no safe per-layer mask; applying a global
	# tint would recreate the old "染到鼻子／披風" failure.
	composer.clear_dyes()
	composer.visible = true
	_refresh_frame()
	status_label.text = "REFERENCE PASS: calibrated %s board | %s | static art baseline" % [
		PaperDollV2Contract.gender_name(gender),
		reference_id,
	]

func _refresh_frame() -> void:
	if composer != null:
		composer.update_frame(facing, frame_x)
	frame_label.text = "Frame %d / %d" % [frame_x, PaperDollV2Contract.FRAME_COLUMNS - 1]
