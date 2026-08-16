class_name PaperDollV2Composer
extends Node2D

## V2 Composer is presentation-only.  It owns a fixed Sprite2D pool and
## transient frame/dye state; it never loads source files or edits gameplay data.

enum DyeGroup {
	HAIR_BROWS,
	ARMOR,
	CAPE,
	MOUNT,
}

var current_facing: int = PaperDollV2Contract.Facing.DOWN
var current_frame_x: int = 0
var render_state: int = PaperDollV2Contract.RenderState.ON_FOOT
var last_error: String = ""

var _sprites: Array[Sprite2D] = []
var _base_textures: Array[Texture2D] = []
var _last_recipe: PaperDollV2Recipe
var _dye_colors: Dictionary = {}
var _dye_cache: Dictionary = {}

func _ready() -> void:
	_ensure_layers()
	update_frame(current_facing, current_frame_x)

func apply_recipe(recipe: PaperDollV2Recipe) -> bool:
	_ensure_layers()
	last_error = ""
	if recipe == null:
		return _reject("recipe is null")
	var recipe_issues := recipe.validation_issues()
	if not recipe_issues.is_empty():
		return _reject("; ".join(recipe_issues))
	_last_recipe = recipe
	render_state = recipe.state
	_base_textures.resize(PaperDollV2Contract.RenderLayer.COUNT)
	_configure_state()
	for layer: int in range(PaperDollV2Contract.RenderLayer.COUNT):
		var texture := recipe.texture_for(layer)
		_base_textures[layer] = texture
		_sprites[layer].visible = texture != null \
			and (render_state == PaperDollV2Contract.RenderState.MOUNTED \
			or not PaperDollV2Contract.is_mount_layer(layer))
	_refresh_dyed_textures()
	return update_frame(current_facing, current_frame_x)

func update_frame(facing: int, frame_x: int) -> bool:
	if not PaperDollV2Contract.is_valid_facing(facing):
		return _reject("invalid facing %d" % facing)
	if frame_x < 0 or frame_x >= PaperDollV2Contract.FRAME_COLUMNS:
		return _reject("invalid frame_x %d" % frame_x)
	_ensure_layers()
	current_facing = facing
	current_frame_x = frame_x
	var source_row := PaperDollV2Contract.source_row_for(facing)
	var flip_left := facing == PaperDollV2Contract.Facing.LEFT
	for layer: int in range(PaperDollV2Contract.RenderLayer.COUNT):
		var sprite := _sprites[layer]
		sprite.frame_coords = Vector2i(frame_x, source_row)
		sprite.flip_h = flip_left
		sprite.z_index = PaperDollV2Contract.z_index_for(layer, facing)
	last_error = ""
	return true

func set_dye(group: int, color: Color) -> bool:
	if group < DyeGroup.HAIR_BROWS or group > DyeGroup.MOUNT:
		last_error = "invalid dye group"
		return false
	_dye_colors[group] = Color(color.r, color.g, color.b, 1.0)
	_refresh_dyed_textures()
	return true

func clear_dye(group: int) -> bool:
	if not _dye_colors.has(group):
		return false
	_dye_colors.erase(group)
	_refresh_dyed_textures()
	return true

func clear_dyes() -> void:
	_dye_colors.clear()
	_refresh_dyed_textures()

func sprite_for(layer: int) -> Sprite2D:
	if not PaperDollV2Contract.is_valid_layer(layer):
		return null
	_ensure_layers()
	return _sprites[layer]

func sprite_count() -> int:
	_ensure_layers()
	return _sprites.size()

func visible_sprite_count() -> int:
	_ensure_layers()
	var count := 0
	for sprite in _sprites:
		if sprite.visible and sprite.texture != null:
			count += 1
	return count

func frame_size() -> Vector2i:
	return PaperDollV2Contract.frame_size(render_state)

func anchor_px() -> Vector2i:
	return PaperDollV2Contract.anchor_px(render_state)

func _ensure_layers() -> void:
	if _sprites.size() == PaperDollV2Contract.RenderLayer.COUNT:
		return
	for child in get_children():
		child.queue_free()
	_sprites.clear()
	_base_textures.resize(PaperDollV2Contract.RenderLayer.COUNT)
	for layer: int in range(PaperDollV2Contract.RenderLayer.COUNT):
		var sprite := Sprite2D.new()
		sprite.name = PaperDollV2Contract.layer_name(layer)
		sprite.hframes = PaperDollV2Contract.FRAME_COLUMNS
		sprite.vframes = PaperDollV2Contract.SOURCE_ROWS
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.visible = false
		add_child(sprite)
		_sprites.append(sprite)
	_configure_state()

func _configure_state() -> void:
	var anchor := PaperDollV2Contract.anchor_px(render_state)
	for sprite in _sprites:
		sprite.hframes = PaperDollV2Contract.FRAME_COLUMNS
		sprite.vframes = PaperDollV2Contract.SOURCE_ROWS
		sprite.centered = false
		sprite.offset = Vector2(-anchor.x, -anchor.y)

func _refresh_dyed_textures() -> void:
	if _sprites.size() != PaperDollV2Contract.RenderLayer.COUNT:
		return
	for layer: int in range(PaperDollV2Contract.RenderLayer.COUNT):
		var source := _base_textures[layer]
		var group := _dye_group_for_layer(layer)
		var tinted := source
		if source != null and group >= 0 and _dye_colors.has(group):
			tinted = _tint_texture(source, _dye_colors[group] as Color)
		_sprites[layer].texture = tinted

func _dye_group_for_layer(layer: int) -> int:
	match layer:
		PaperDollV2Contract.RenderLayer.HAIR:
			return DyeGroup.HAIR_BROWS
		PaperDollV2Contract.RenderLayer.ARMOR, PaperDollV2Contract.RenderLayer.BOOTS, PaperDollV2Contract.RenderLayer.HELMET, PaperDollV2Contract.RenderLayer.MOUNT_BARDING:
			return DyeGroup.ARMOR
		PaperDollV2Contract.RenderLayer.CAPE:
			return DyeGroup.CAPE
		PaperDollV2Contract.RenderLayer.MOUNT_TAIL, PaperDollV2Contract.RenderLayer.MOUNT_BODY, PaperDollV2Contract.RenderLayer.MOUNT_HEAD:
			return DyeGroup.MOUNT
		_:
			return -1

func _tint_texture(source: Texture2D, target: Color) -> Texture2D:
	var key := "%d:%s" % [source.get_instance_id(), target.to_html(false)]
	if _dye_cache.has(key):
		return _dye_cache[key] as Texture2D
	var image := source.get_image()
	if image == null or image.is_empty():
		return source
	image = image.duplicate()
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.05:
				continue
			var luminance := clampf(pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114, 0.0, 1.0)
			var value := clampf(lerpf(maxf(target.v * 0.35, 0.05), maxf(target.v, 0.20), luminance), 0.05, 1.0)
			image.set_pixel(x, y, Color.from_hsv(target.h, target.s, value, pixel.a))
	var result := ImageTexture.create_from_image(image)
	_dye_cache[key] = result
	return result

func _reject(message: String) -> bool:
	last_error = message
	return false
