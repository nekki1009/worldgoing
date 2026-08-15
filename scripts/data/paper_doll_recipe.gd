class_name PaperDollRecipe
extends RefCounted

var is_mounted: bool = false
var action: int = PaperDollAnimation.Action.IDLE
## The deterministic white-hair/silver-armor preset uses a complete accepted
## board for pixels; alternate hairstyles may be composited into that same
## calibrated board without changing its anchor or armor/cape silhouette.
var is_accepted_reference: bool = false
## Optional complete reference bundle (helmet/weapon/shield or another
## explicitly approved combination).  When present it replaces the Body
## texture for this snapshot; the fixed Sprite2D pool and frame controller are
## unchanged, but no misaligned prop sheet is allowed to cover it.
var reference_composite_texture: Texture2D
## The selected hair source used when the accepted board needs a hairstyle
## replacement.  The field is a snapshot value; Composer never mutates it.
var reference_hair_texture: Texture2D
## True for a transparent hair-only sheet.  Complete-head legacy sheets need
## the face-clearing normalizer; hair-only sheets must keep their authored
## braid silhouette intact.
var reference_hair_is_hair_only: bool = false
## Stable catalog identity for the selected hair.  Direct PNG-backed
## ImageTextures intentionally have no resource_path, so the Composer must
## not infer whether the calibrated default hair is selected from a path.
var reference_hair_visual_id: StringName = &""
var _textures: Array[Texture2D] = []

func _init(
		p_is_mounted: bool = false,
		p_action: int = PaperDollAnimation.Action.IDLE
	) -> void:
	is_mounted = p_is_mounted
	action = p_action if PaperDollAnimation.is_valid_action(p_action) else PaperDollAnimation.Action.IDLE
	_textures.resize(PaperDollLayerVisual.RenderLayer.COUNT)

func set_layer_texture(layer: int, texture: Texture2D) -> bool:
	if not PaperDollLayerVisual.is_valid_layer(layer):
		return false
	_textures[layer] = texture
	return true

func texture_for(layer: int) -> Texture2D:
	if not PaperDollLayerVisual.is_valid_layer(layer):
		return null
	return _textures[layer]

func visible_layer_count() -> int:
	var result: int = 0
	for texture: Texture2D in _textures:
		if texture != null:
			result += 1
	return result
