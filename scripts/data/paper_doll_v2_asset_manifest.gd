class_name PaperDollV2AssetManifest
extends Resource

## A manifest is the admission ticket for a normalized part.  Runtime code
## receives the texture only after this contract has passed.

@export var visual_id: StringName = &""
@export var render_layer: int = PaperDollV2Contract.RenderLayer.BODY
@export var state: int = PaperDollV2Contract.RenderState.ON_FOOT
@export var gender_policy: int = PaperDollV2Contract.GenderPolicy.UNISEX
@export var gender: int = PaperDollV2Contract.Gender.MALE
@export var symmetry_policy: int = PaperDollV2Contract.SymmetryPolicy.MIRROR_RIGHT
@export var texture: Texture2D
@export var source_path: String = ""
@export var template_id: StringName = &""
@export var normalization_version: StringName = &"v2_1"
@export var required: bool = false
@export var dye_mask_id: StringName = &""

func is_compatible_with(gender_value: int) -> bool:
	if gender_policy == PaperDollV2Contract.GenderPolicy.UNISEX:
		return PaperDollV2Contract.is_valid_gender(gender_value)
	return gender_policy == PaperDollV2Contract.GenderPolicy.GENDERED and gender == gender_value

func validation_issues(template: PaperDollV2BodyTemplate = null) -> PackedStringArray:
	var issues := PackedStringArray()
	if not PaperDollV2Contract.is_valid_visual_id(visual_id):
		issues.append("%s: invalid visual_id" % visual_id)
	if not PaperDollV2Contract.is_valid_layer(render_layer):
		issues.append("%s: invalid render_layer" % visual_id)
	if not PaperDollV2Contract.is_valid_state(state):
		issues.append("%s: invalid state" % visual_id)
	if gender_policy < PaperDollV2Contract.GenderPolicy.GENDERED \
			or gender_policy > PaperDollV2Contract.GenderPolicy.UNISEX:
		issues.append("%s: invalid gender_policy" % visual_id)
	if gender_policy == PaperDollV2Contract.GenderPolicy.GENDERED \
			and not PaperDollV2Contract.is_valid_gender(gender):
		issues.append("%s: invalid gender" % visual_id)
	if symmetry_policy < PaperDollV2Contract.SymmetryPolicy.MIRROR_RIGHT \
			or symmetry_policy > PaperDollV2Contract.SymmetryPolicy.ASYMMETRIC_ALLOWED:
		issues.append("%s: invalid symmetry_policy" % visual_id)
	if template != null:
		if template.state != state:
			issues.append("%s: state does not match template" % visual_id)
		if template_id != template.template_id:
			issues.append("%s: template_id does not match body template" % visual_id)
	if texture == null:
		if required:
			issues.append("%s: required texture is missing" % visual_id)
		return issues
	var expected := PaperDollV2Contract.sheet_size(state)
	if Vector2i(texture.get_width(), texture.get_height()) != expected:
		issues.append("%s: texture must be %s" % [visual_id, expected])
		return issues
	var image := texture.get_image()
	if image == null or image.is_empty():
		issues.append("%s: texture is unreadable" % visual_id)
		return issues
	if image.is_compressed() and image.decompress() != OK:
		issues.append("%s: texture cannot be decompressed" % visual_id)
	if image.get_format() != Image.FORMAT_RGBA8:
		issues.append("%s: texture must use RGBA8" % visual_id)
	if image.detect_alpha() == Image.ALPHA_NONE:
		issues.append("%s: texture must contain transparent pixels" % visual_id)
	if template != null and template.anchor_px != PaperDollV2Contract.anchor_px(state):
		issues.append("%s: template Anchor is not the V2 state Anchor" % visual_id)
	return issues
