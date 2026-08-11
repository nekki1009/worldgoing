class_name PaperDollComposer
extends Node2D

var current_facing: int = PaperDollLayerVisual.Facing.DOWN
var current_frame_x: int = 0
var _sprites: Array[Sprite2D] = []

func _ready() -> void:
	_ensure_layers()
	update_frame(current_facing, current_frame_x)

func apply_recipe(recipe: PaperDollRecipe) -> void:
	_ensure_layers()
	for layer: int in range(PaperDollLayerVisual.RenderLayer.COUNT):
		var texture: Texture2D = recipe.texture_for(layer) if recipe != null else null
		var sprite: Sprite2D = _sprites[layer]
		sprite.texture = texture
		sprite.visible = texture != null
	update_frame(current_facing, current_frame_x)

func update_frame(facing: int, frame_x: int) -> bool:
	if not PaperDollLayerVisual.is_valid_facing(facing) \
			or frame_x < 0 \
			or frame_x >= PaperDollLayerVisual.FRAME_COLUMNS:
		return false
	_ensure_layers()
	current_facing = facing
	current_frame_x = frame_x
	var source_row: int = PaperDollLayerVisual.source_row_for(facing)
	var flip_left: bool = facing == PaperDollLayerVisual.Facing.LEFT
	for layer: int in range(PaperDollLayerVisual.RenderLayer.COUNT):
		var sprite: Sprite2D = _sprites[layer]
		sprite.frame_coords = Vector2i(frame_x, source_row)
		sprite.flip_h = flip_left
		sprite.z_index = z_index_for(layer, facing)
	return true

func sprite_for(layer: int) -> Sprite2D:
	if not PaperDollLayerVisual.is_valid_layer(layer):
		return null
	_ensure_layers()
	return _sprites[layer]

func sprite_count() -> int:
	_ensure_layers()
	return _sprites.size()

static func z_index_for(layer: int, facing: int) -> int:
	match layer:
		PaperDollLayerVisual.RenderLayer.MOUNT_TAIL:
			return -10
		PaperDollLayerVisual.RenderLayer.CAPE:
			if facing == PaperDollLayerVisual.Facing.DOWN:
				return -5
			return 15 if facing == PaperDollLayerVisual.Facing.UP else 5
		PaperDollLayerVisual.RenderLayer.MOUNT_BODY:
			return 0
		PaperDollLayerVisual.RenderLayer.BODY:
			return 10
		PaperDollLayerVisual.RenderLayer.ARMOR:
			return 11
		PaperDollLayerVisual.RenderLayer.HAIR:
			return 12
		PaperDollLayerVisual.RenderLayer.HELMET:
			return 13
		PaperDollLayerVisual.RenderLayer.WEAPON:
			return -1 if facing == PaperDollLayerVisual.Facing.UP \
				or facing == PaperDollLayerVisual.Facing.LEFT else 14
		PaperDollLayerVisual.RenderLayer.SHIELD:
			return -2 if facing == PaperDollLayerVisual.Facing.UP \
				or facing == PaperDollLayerVisual.Facing.RIGHT else 15
		PaperDollLayerVisual.RenderLayer.MOUNT_HEAD:
			return -5 if facing == PaperDollLayerVisual.Facing.UP else 20
		PaperDollLayerVisual.RenderLayer.MOUNT_BARDING:
			return 1 if facing == PaperDollLayerVisual.Facing.UP else 21
		_:
			return 0

func _ensure_layers() -> void:
	if _sprites.size() == PaperDollLayerVisual.RenderLayer.COUNT:
		return
	_sprites.clear()
	for layer: int in range(PaperDollLayerVisual.RenderLayer.COUNT):
		var sprite: Sprite2D = Sprite2D.new()
		sprite.name = PaperDollLayerVisual.layer_name(layer)
		sprite.hframes = PaperDollLayerVisual.FRAME_COLUMNS
		sprite.vframes = PaperDollLayerVisual.SOURCE_ROWS
		sprite.centered = false
		sprite.offset = PaperDollLayerVisual.SPRITE_OFFSET
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.visible = false
		add_child(sprite)
		_sprites.append(sprite)
