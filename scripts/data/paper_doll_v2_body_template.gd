class_name PaperDollV2BodyTemplate
extends Resource

## The body template owns geometry.  Parts are valid only when they use the
## same state, frame size, Anchor and template version.

@export var template_id: StringName = &""
@export var state: int = PaperDollV2Contract.RenderState.ON_FOOT
@export var gender: int = PaperDollV2Contract.Gender.MALE
@export var texture: Texture2D
@export var anchor_px: Vector2i = PaperDollV2Contract.ON_FOOT_ANCHOR
@export var foot_or_hoof_line: int = 56
@export var template_version: StringName = &"v2_1"
@export var head_rect: Rect2i = Rect2i(8, 0, 48, 32)
@export var protected_rects: Array[Rect2i] = []

func validation_issues() -> PackedStringArray:
	var issues := PackedStringArray()
	if not PaperDollV2Contract.is_valid_visual_id(template_id):
		issues.append("template_id must use lowercase ASCII snake_case")
	if not PaperDollV2Contract.is_valid_state(state):
		issues.append("template state is invalid")
	if not PaperDollV2Contract.is_valid_gender(gender):
		issues.append("template gender is invalid")
	var expected_size := PaperDollV2Contract.frame_size(state)
	if anchor_px != PaperDollV2Contract.anchor_px(state):
		issues.append("template Anchor must be %s" % PaperDollV2Contract.anchor_px(state))
	if foot_or_hoof_line != anchor_px.y:
		issues.append("foot_or_hoof_line must equal anchor y")
	if texture == null:
		issues.append("template texture is missing")
		return issues
	if Vector2i(texture.get_width(), texture.get_height()) != PaperDollV2Contract.sheet_size(state):
		issues.append("template texture must be %s" % PaperDollV2Contract.sheet_size(state))
		return issues
	var image := texture.get_image()
	if image == null or image.is_empty():
		issues.append("template texture is unreadable")
		return issues
	if image.is_compressed() and image.decompress() != OK:
		issues.append("template texture cannot be decompressed")
	if image.get_format() != Image.FORMAT_RGBA8:
		issues.append("template texture must use RGBA8")
	if image.detect_alpha() == Image.ALPHA_NONE:
		issues.append("template texture must contain transparent pixels")
	for row: int in range(PaperDollV2Contract.SOURCE_ROWS):
		for frame_x: int in range(PaperDollV2Contract.FRAME_COLUMNS):
			var frame := image.get_region(Rect2i(
				Vector2i(frame_x * expected_size.x, row * expected_size.y),
				expected_size
			))
			if frame.is_invisible():
				issues.append("template frame (%d,%d) is empty" % [frame_x, row])
	return issues
