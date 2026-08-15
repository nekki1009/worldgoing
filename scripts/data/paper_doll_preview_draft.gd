class_name PaperDollPreviewDraft
extends RefCounted

var gender: int = PaperDollLayerVisual.Gender.MALE
var is_mounted: bool = false
var action: int = PaperDollAnimation.Action.IDLE
var mount_visual_id: StringName = &""
var layer_visual_ids: Dictionary = {}

func set_visual(layer: int, visual_id: StringName) -> bool:
	if not PaperDollLayerVisual.is_valid_layer(layer) \
			or PaperDollLayerVisual.is_mount_intrinsic_layer(layer):
		return false
	if visual_id.is_empty():
		layer_visual_ids.erase(layer)
	else:
		layer_visual_ids[layer] = visual_id
	return true

func visual_id_for(layer: int) -> StringName:
	var stored: Variant = layer_visual_ids.get(layer, &"")
	return stored as StringName if stored is StringName else StringName(str(stored))

func selected_layers() -> Array[int]:
	var result: Array[int] = []
	for key: Variant in layer_visual_ids.keys():
		if key is int and PaperDollLayerVisual.is_valid_layer(key as int):
			result.append(key as int)
	result.sort()
	return result

func copy() -> PaperDollPreviewDraft:
	var result: PaperDollPreviewDraft = PaperDollPreviewDraft.new()
	result.gender = gender
	result.is_mounted = is_mounted
	result.action = action
	result.mount_visual_id = mount_visual_id
	result.layer_visual_ids = layer_visual_ids.duplicate()
	return result
