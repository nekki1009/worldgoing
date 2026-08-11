class_name PaperDollRecipe
extends RefCounted

var is_mounted: bool = false
var _textures: Array[Texture2D] = []

func _init(p_is_mounted: bool = false) -> void:
	is_mounted = p_is_mounted
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
