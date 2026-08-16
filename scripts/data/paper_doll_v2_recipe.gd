class_name PaperDollV2Recipe
extends RefCounted

## Detached display snapshot.  It contains no gameplay Resource references.

var gender: int = PaperDollV2Contract.Gender.MALE
var state: int = PaperDollV2Contract.RenderState.ON_FOOT
var template: PaperDollV2BodyTemplate
var animation_action: int = 0
## True only for a calibrated complete reference board.  Such a recipe is a
## QA/preset baseline, not a claim that the board has been split into runtime
## equipment layers.
var is_reference_composite: bool = false
var _textures: Array[Texture2D] = []

func _init(p_gender: int = PaperDollV2Contract.Gender.MALE, p_state: int = PaperDollV2Contract.RenderState.ON_FOOT) -> void:
	gender = p_gender
	state = p_state
	_textures.resize(PaperDollV2Contract.RenderLayer.COUNT)

func set_layer_texture(layer: int, texture: Texture2D) -> bool:
	if not PaperDollV2Contract.is_valid_layer(layer):
		return false
	_textures[layer] = texture
	return true

func texture_for(layer: int) -> Texture2D:
	if not PaperDollV2Contract.is_valid_layer(layer):
		return null
	return _textures[layer]

func visible_layer_count() -> int:
	var count := 0
	for texture in _textures:
		if texture != null:
			count += 1
	return count

func validation_issues() -> PackedStringArray:
	var issues := PackedStringArray()
	if not PaperDollV2Contract.is_valid_gender(gender):
		issues.append("recipe gender is invalid")
	if not PaperDollV2Contract.is_valid_state(state):
		issues.append("recipe state is invalid")
	if template == null:
		issues.append("recipe body template is missing")
	elif template.state != state or template.gender != gender:
		issues.append("recipe body template does not match gender/state")
	if texture_for(PaperDollV2Contract.RenderLayer.BODY) == null:
		issues.append("recipe Body is required")
	if state == PaperDollV2Contract.RenderState.MOUNTED and not is_reference_composite:
		for layer in [
			PaperDollV2Contract.RenderLayer.MOUNT_TAIL,
			PaperDollV2Contract.RenderLayer.MOUNT_BODY,
			PaperDollV2Contract.RenderLayer.MOUNT_HEAD,
		]:
			if texture_for(layer) == null:
				issues.append("mounted recipe is missing %s" % PaperDollV2Contract.layer_name(layer))
	return issues
