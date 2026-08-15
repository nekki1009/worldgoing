class_name PaperDollComposer
extends Node2D

## Dye groups intentionally describe visual regions, not gameplay equipment.
## The composer receives already split, 64x64-cell sheets and recolors only
## the selected layer pool.  The old complete-sheet path remains only as a
## compatibility path for offline reference fixtures.
enum DyeGroup {
	HAIR_BROWS,
	ARMOR,
	CAPE,
	MOUNT,
}

var current_facing: int = PaperDollLayerVisual.Facing.DOWN
var current_frame_x: int = 0
var current_action: int = PaperDollAnimation.Action.IDLE
var _sprites: Array[Sprite2D] = []
var _base_textures: Array[Texture2D] = []
var _last_recipe: PaperDollRecipe
var _reference_body_texture: Texture2D
var _dye_colors: Dictionary = {}
var _dye_cache: Dictionary = {}

## Complete accepted Art Gate 1 boards are the only trustworthy visual source
## for the default white-hair/silver-armor preset.  They are still consumed by
## this same Composer and frame controller; the distinction is that no
## independently packed, not-yet-approved overlays are allowed to cover them.
const ACCEPTED_REFERENCE_ON_FOOT := "res://assets/paper_doll/reference_match/reference_match_body_on_foot_unisex.png"
const ACCEPTED_REFERENCE_MOUNTED := "res://assets/paper_doll/reference_match/reference_match_body_mounted_unisex.png"

func _ready() -> void:
	_ensure_layers()
	update_frame(current_facing, current_frame_x)

func apply_recipe(recipe: PaperDollRecipe) -> void:
	_ensure_layers()
	_last_recipe = recipe
	_reference_body_texture = null
	current_action = recipe.action if recipe != null else PaperDollAnimation.Action.IDLE
	_base_textures.resize(PaperDollLayerVisual.RenderLayer.COUNT)
	for layer: int in range(PaperDollLayerVisual.RenderLayer.COUNT):
		var texture: Texture2D = recipe.texture_for(layer) if recipe != null else null
		_base_textures[layer] = texture
		var sprite: Sprite2D = _sprites[layer]
		sprite.texture = texture
		sprite.visible = texture != null
		sprite.modulate = Color.WHITE
	# A recipe carrying an accepted reference board is intentionally flattened:
	# independent rider parts are not aligned enough to be layered over it.
	# MountBarding is the one deliberate exception: it is an authored horse-only
	# sheet and must remain an independent overlay above MountHead.
	if _is_accepted_reference_recipe(recipe):
		_reference_body_texture = _build_reference_body_texture(recipe)
		for layer: int in range(PaperDollLayerVisual.RenderLayer.COUNT):
			_sprites[layer].visible = _base_textures[layer] != null
			var keep_layer: bool = layer == PaperDollLayerVisual.RenderLayer.BODY \
				or layer == PaperDollLayerVisual.RenderLayer.MOUNT_BARDING
			_sprites[layer].modulate = Color.WHITE if keep_layer \
				else Color(1.0, 1.0, 1.0, 0.0)
			if layer == PaperDollLayerVisual.RenderLayer.BODY:
				_sprites[layer].texture = _reference_body_texture
	_refresh_dyed_textures()
	update_frame(current_facing, current_frame_x)

## Change only the action metadata.  The caller normally resolves a new
## recipe so every layer can swap to its action sheet atomically.
func set_action(action: int) -> bool:
	if not PaperDollAnimation.is_valid_action(action):
		return false
	current_action = action
	return true

## Apply one dye to the complete approved reference. Hair and eyebrows share
## one group by contract; armor, cape and mount are independent groups.
func set_dye(group: int, color: Color) -> bool:
	if group < DyeGroup.HAIR_BROWS or group > DyeGroup.MOUNT:
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

func has_dye(group: int) -> bool:
	return _dye_colors.has(group)

func dye_color(group: int) -> Color:
	return _dye_colors.get(group, Color.WHITE) as Color

func active_dye_count() -> int:
	return _dye_colors.size()

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

func visible_sprite_count() -> int:
	# Report the pool's effective visual output, not the number of textures in
	# the immutable recipe. Hair is independently selectable, while a helmet
	# intentionally suppresses the hair silhouette to prevent crown leakage.
	_ensure_layers()
	var result: int = 0
	for sprite: Sprite2D in _sprites:
		if sprite.visible and sprite.texture != null:
			result += 1
	return result

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

func _refresh_dyed_textures() -> void:
	if _sprites.size() != PaperDollLayerVisual.RenderLayer.COUNT:
		return
	if _is_accepted_reference_recipe(_last_recipe):
		var body: Texture2D = _reference_body_texture
		if body == null:
			body = _base_textures[PaperDollLayerVisual.RenderLayer.BODY]
		_sprites[PaperDollLayerVisual.RenderLayer.BODY].texture = _tint_reference_sheet(
			body,
			_last_recipe.is_mounted
		)
		_sprites[PaperDollLayerVisual.RenderLayer.BODY].visible = body != null
		_sprites[PaperDollLayerVisual.RenderLayer.BODY].modulate = Color.WHITE
		for layer: int in range(PaperDollLayerVisual.RenderLayer.COUNT):
			if layer == PaperDollLayerVisual.RenderLayer.BODY:
				continue
			if layer == PaperDollLayerVisual.RenderLayer.MOUNT_BARDING:
				var barding: Texture2D = _base_textures[layer]
				var barding_tinted: Texture2D = barding
				if barding != null and _dye_colors.has(DyeGroup.ARMOR):
					barding_tinted = _tint_layer_sheet(barding, DyeGroup.ARMOR)
				_sprites[layer].texture = barding_tinted
				_sprites[layer].visible = barding_tinted != null
				_sprites[layer].modulate = Color.WHITE
				continue
			_sprites[layer].visible = false
			_sprites[layer].modulate = Color(1.0, 1.0, 1.0, 0.0)
		return
	var reference_body: bool = _is_flat_reference_recipe()
	for layer: int in range(PaperDollLayerVisual.RenderLayer.COUNT):
		var base: Texture2D = _base_textures[layer] if layer < _base_textures.size() else null
		var tinted: Texture2D = base
		if base != null and reference_body and layer == PaperDollLayerVisual.RenderLayer.BODY:
			tinted = _tint_reference_sheet(base, _last_recipe.is_mounted)
		elif base != null:
			var group: int = _dye_group_for_layer(layer)
			if layer == PaperDollLayerVisual.RenderLayer.HAIR:
				# The imported hair sheets are complete little heads, not transparent
				# hair-only overlays.  Normalize them at the composition boundary so
				# Body remains the single face/skin authority for every gender/pose.
				tinted = _prepare_hair_overlay(base)
				if group >= 0 and _dye_colors.has(group):
					tinted = _tint_hair_sheet(tinted, group)
			elif group >= 0 and _dye_colors.has(group):
				tinted = _tint_layer_sheet(base, group)
			elif layer == PaperDollLayerVisual.RenderLayer.BODY \
					and _dye_colors.has(DyeGroup.HAIR_BROWS):
				# Body is the skin authority, but its brow pixels must move with
				# action fallback transforms.  Derive them from the same frame-local
				# face mask instead of painting one fixed idle coordinate.
				tinted = _tint_brows_on_body(base)
		_sprites[layer].texture = tinted
		_sprites[layer].visible = tinted != null and not (
			layer == PaperDollLayerVisual.RenderLayer.HAIR
			and _base_textures[PaperDollLayerVisual.RenderLayer.HELMET] != null
		)
	# Mount-head clearance is authored once by the reference packer.  Do not run
	# a second runtime crop here: the old crop removed the entire frontal horse
	# head after the packer's rider-clearance pass, leaving only two pixels in
	# the DOWN preview.  The packer already keeps the rider face clear and the
	# z-order contract intentionally allows the horse neck below the chest.

func _is_flat_reference_recipe() -> bool:
	if _last_recipe == null:
		return false
	var visible: int = 0
	for texture: Texture2D in _base_textures:
		if texture != null:
			visible += 1
	return visible == 1 and _base_textures[PaperDollLayerVisual.RenderLayer.BODY] != null

func _is_accepted_reference_recipe(recipe: PaperDollRecipe) -> bool:
	return recipe != null and recipe.is_accepted_reference

## Keep the calibrated reference board as the single authority for the face,
## armor, cape, mount, and anchor.  Only the selected hairstyle silhouette is
## replaced; clearing the old mask first prevents a second head or white fringe.
func _build_reference_body_texture(recipe: PaperDollRecipe) -> Texture2D:
	return build_reference_body_texture(recipe)

## Public only for the pure Image contact-sheet exporter.  It performs the
## same replacement as the live Sprite2D Composer without creating scene
## nodes, so a saved sheet cannot silently revert to the white default hair.
static func build_reference_body_texture(recipe: PaperDollRecipe) -> Texture2D:
	if recipe == null:
		return null
	var body: Texture2D = recipe.reference_composite_texture
	if body == null:
		body = recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY)
	var hair: Texture2D = recipe.reference_hair_texture
	# A complete armed reference already contains the helmet, weapon and shield.
	# Never put a second hairstyle on top of that board; the helmet is the
	# authored head silhouette for this bundle.
	if recipe.reference_composite_texture != null:
		return body
	if body == null or hair == null:
		return body
	# The approved board already contains this exact hairstyle.  Do not rebuild
	# it from the legacy split sheet, whose palette is intentionally different.
	if recipe.reference_hair_visual_id in [&"hair_male_default", &"hair_female_default"] \
		or str(hair.resource_path).contains("hair_male_default_") \
		or str(hair.resource_path).contains("hair_female_default_"):
		return body
	var body_image: Image = body.get_image()
	var new_hair_image: Image = _reference_hair_image(
		hair,
		recipe.reference_hair_is_hair_only
	)
	if body_image == null or new_hair_image == null \
			or body_image.is_empty() or new_hair_image.is_empty():
		return body
	if body_image.get_size() != new_hair_image.get_size():
		return body
	body_image = body_image.duplicate()
	for row: int in range(PaperDollLayerVisual.SOURCE_ROWS):
		for frame_x: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
			var origin := Vector2i(
				frame_x * PaperDollLayerVisual.FRAME_SIZE.x,
				row * PaperDollLayerVisual.FRAME_SIZE.y
			)
			var body_frame: Image = body_image.get_region(
				Rect2i(origin, PaperDollLayerVisual.FRAME_SIZE)
			)
			var original_body_frame: Image = body_frame.duplicate()
			var replacement_frame: Image = new_hair_image.get_region(
				Rect2i(origin, PaperDollLayerVisual.FRAME_SIZE)
			)
			var replacement_rect: Rect2i = replacement_frame.get_used_rect()
			if replacement_rect.size.x <= 0 or replacement_rect.size.y <= 0:
				continue
			var hair_rect: Rect2i = _reference_hair_target_rect(
				body_frame,
				recipe.reference_hair_is_hair_only,
				replacement_rect.size,
				recipe.is_mounted
			)
			if hair_rect.size.x <= 0 or hair_rect.size.y <= 0:
				continue
			var replacement: Image = replacement_frame.get_region(replacement_rect)
			replacement.resize(
				hair_rect.size.x,
				hair_rect.size.y,
				Image.INTERPOLATE_NEAREST
			)
			# Front and profile rows can have an asymmetric ponytail/braid.  Align
			# their face opening to the calibrated head as well; otherwise the used
			# rectangle's centre moves with the tail and the hairstyle appears slanted
			# in the Asset Lab.  The UP row has no face opening and deliberately keeps
			# the measured rear-of-head placement.
			if row != PaperDollLayerVisual.Facing.UP:
				hair_rect = _align_reference_hair_rect(
					body_frame,
					hair_rect,
					replacement,
					recipe.is_mounted
				)
			var mounted_hair_component: Dictionary = _mounted_reference_hair_component(
				original_body_frame
			) if recipe.is_mounted else {}
			_clear_reference_hair(body_frame, recipe.is_mounted)
			# Do not blit the transparent face opening as an opaque clear.  Copy
			# only authored hair pixels so Body's eyes, nose and skin survive.
			for replacement_y: int in range(replacement.get_height()):
				for replacement_x: int in range(replacement.get_width()):
					var replacement_pixel: Color = replacement.get_pixel(
						replacement_x,
						replacement_y
					)
					if replacement_pixel.a <= 0.05:
						continue
					var target_position := hair_rect.position + Vector2i(
						replacement_x,
						replacement_y
					)
					if target_position.x >= 0 and target_position.x < body_frame.get_width() \
						and target_position.y >= 0 and target_position.y < body_frame.get_height():
						if _reference_replacement_blocked(
							original_body_frame.get_pixelv(target_position),
							target_position,
							recipe.is_mounted,
							mounted_hair_component
						):
							continue
						body_frame.set_pixelv(target_position, replacement_pixel)
			body_image.blit_rect(
				body_frame,
				Rect2i(Vector2i.ZERO, PaperDollLayerVisual.FRAME_SIZE),
				origin
			)
	return ImageTexture.create_from_image(body_image)

static func _reference_hair_rect(frame: Image, mounted: bool = false) -> Rect2i:
	if mounted:
		return _mounted_reference_hair_rect(frame)
	var min_x: int = frame.get_width()
	var min_y: int = frame.get_height()
	var max_x: int = -1
	var max_y: int = -1
	for y: int in range(mini(27, frame.get_height())):
		for x: int in range(frame.get_width()):
			if not _looks_like_reference_hair(frame.get_pixel(x, y), Vector2i(x, y)):
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)

static func _mounted_reference_hair_component(frame: Image) -> Dictionary:
	# A mounted reference frame contains the rider and the horse in one 64x64
	# body sheet.  A union of every hair-like pixel therefore also catches horse
	# ears/mane.  Use the largest connected component in the top head band: the
	# rider's crown is one component, while the horse fragments are separate.
	if frame == null or frame.is_empty():
		return {}
	var visited: Dictionary = {}
	var best_count: int = 0
	var best_component: Dictionary = {}
	var neighbours: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
	]
	for y: int in range(mini(27, frame.get_height())):
		for x: int in range(frame.get_width()):
			var start := Vector2i(x, y)
			if visited.has(start) or not _looks_like_reference_hair(frame.get_pixelv(start), start):
				continue
			var queue: Array[Vector2i] = [start]
			var component: Dictionary = {start: true}
			visited[start] = true
			var cursor: int = 0
			var count: int = 0
			var min_x: int = frame.get_width()
			var min_y: int = frame.get_height()
			var max_x: int = -1
			var max_y: int = -1
			while cursor < queue.size():
				var position: Vector2i = queue[cursor]
				cursor += 1
				count += 1
				component[position] = true
				min_x = mini(min_x, position.x)
				min_y = mini(min_y, position.y)
				max_x = maxi(max_x, position.x)
				max_y = maxi(max_y, position.y)
				for delta: Vector2i in neighbours:
					var next: Vector2i = position + delta
					if next.x < 0 or next.x >= frame.get_width() \
						or next.y < 0 or next.y >= mini(27, frame.get_height()):
						continue
					if visited.has(next) \
						or not _looks_like_reference_hair(frame.get_pixelv(next), next):
						continue
					visited[next] = true
					queue.append(next)
			if count > best_count and max_x >= min_x and max_y >= min_y:
				best_count = count
				best_component = component
	return best_component

static func _mounted_reference_hair_rect(frame: Image) -> Rect2i:
	var component: Dictionary = _mounted_reference_hair_component(frame)
	if component.is_empty():
		return Rect2i()
	var min_x: int = frame.get_width()
	var min_y: int = frame.get_height()
	var max_x: int = -1
	var max_y: int = -1
	for value: Variant in component.keys():
		var position: Vector2i = value as Vector2i
		min_x = mini(min_x, position.x)
		min_y = mini(min_y, position.y)
		max_x = maxi(max_x, position.x)
		max_y = maxi(max_y, position.y)
	if max_x < min_x or max_y < min_y:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)

static func _reference_hair_target_rect(
		frame: Image,
		hair_only: bool,
		source_size: Vector2i = Vector2i.ZERO,
		mounted: bool = false
) -> Rect2i:
	var base: Rect2i = _reference_hair_rect(frame, mounted)
	if not hair_only or base.size.x <= 0 or base.size.y <= 0:
		return base
	# Keep the crown width tied to the approved reference head.  Long styles gain
	# height from their own source aspect ratio, never a blanket rectangle that
	# can swallow the face or make every hairstyle look equally huge.
	# The accepted mounted board is a compact rider+horse frame: the rider's
	# head is intentionally much smaller than the 64x64 on-foot head.  Reusing
	# the on-foot minimum (18x18) places every alternate hairstyle over horse
	# pixels, after which the mounted safety mask correctly rejects the entire
	# replacement.  Fit mounted hair to the measured rider component instead.
	var minimum_width: int = 8 if mounted else 24
	var maximum_width: int = 16 if mounted else 34
	var minimum_height: int = 10 if mounted else 28
	var maximum_height: int = 20 if mounted else 44
	var target_width: int = clampi(base.size.x + 1, minimum_width, maximum_width)
	var target_height: int = maxi(base.size.y, minimum_height)
	if source_size.x > 0 and source_size.y > 0:
		var source_aspect: float = float(source_size.x) / float(source_size.y)
		target_height = clampi(
			int(round(float(target_width) / source_aspect)),
			target_height,
			maximum_height
		)
	var center_x: int = base.position.x + int(round(base.size.x * 0.5))
	var target_x: int = clampi(center_x - int(round(target_width * 0.5)), 0, frame.get_width() - target_width)
	var target_y: int = maxi(0, base.position.y)
	if target_y + target_height > frame.get_height():
		target_height = frame.get_height() - target_y
	return Rect2i(target_x, target_y, target_width, target_height)

static func _align_reference_hair_rect(
		frame: Image,
		hair_rect: Rect2i,
		replacement: Image,
		mounted: bool = false
) -> Rect2i:
	# A long ponytail/braid makes the total used-rect centre different from the
	# face opening centre.  Align the opening to the accepted head centre so the
	# eyes stay under the hairstyle, while the tail is allowed to extend behind
	# the head.  If a source has no detectable opening (for example a back row),
	# retain the ordinary bounding-box placement.
	var base: Rect2i = _reference_hair_rect(frame, mounted)
	var opening_center: float = _reference_hair_opening_center(replacement)
	if base.size.x <= 0 or opening_center < 0.0:
		return hair_rect
	var desired_center: float = float(base.position.x) + float(base.size.x - 1) * 0.5
	var current_center: float = float(hair_rect.position.x) + opening_center
	var shift: int = int(round(desired_center - current_center))
	var aligned_x: int = clampi(
		hair_rect.position.x + shift,
		0,
		maxi(0, frame.get_width() - hair_rect.size.x)
	)
	return Rect2i(aligned_x, hair_rect.position.y, hair_rect.size.x, hair_rect.size.y)

static func _reference_hair_opening_center(image: Image) -> float:
	if image == null or image.is_empty():
		return -1.0
	var best_length: int = 2
	var best_center: float = -1.0
	# Face openings are internal transparent runs bounded by authored hair on
	# both sides.  Ignore the outside background and the high ponytail knot.
	for y: int in range(8, mini(34, image.get_height())):
		var x: int = 1
		while x < image.get_width() - 1:
			if image.get_pixel(x, y).a > 0.05:
				x += 1
				continue
			var start: int = x
			while x < image.get_width() - 1 and image.get_pixel(x, y).a <= 0.05:
				x += 1
			var length: int = x - start
			if length > best_length \
					and image.get_pixel(start - 1, y).a > 0.05 \
					and image.get_pixel(x, y).a > 0.05:
				best_length = length
				best_center = (float(start) + float(x - 1)) * 0.5
	return best_center

static func _clear_reference_hair(frame: Image, mounted: bool = false) -> void:
	if mounted:
		for value: Variant in _mounted_reference_hair_component(frame).keys():
			frame.set_pixelv(value as Vector2i, Color.TRANSPARENT)
		return
	for y: int in range(mini(27, frame.get_height())):
		for x: int in range(frame.get_width()):
			if _looks_like_reference_hair(frame.get_pixel(x, y), Vector2i(x, y)):
				frame.set_pixel(x, y, Color.TRANSPARENT)

static func _looks_like_reference_hair(source: Color, local: Vector2i) -> bool:
	if source.a <= 0.05 or local.y > 26:
		return false
	# The face is warm gold; keeping it explicitly out prevents hair replacement
	# and hair dye from touching the nose or cheeks.
	var skin: bool = source.h >= 0.045 and source.h <= 0.18 \
		and source.s >= 0.20 and source.v >= 0.30
	if skin:
		return false
	# Navy cape pixels can enter the top band in the mounted side view.
	var navy: bool = source.h >= 0.55 and source.h <= 0.82 \
		and source.s >= 0.16 and source.v <= 0.60
	if navy:
		return false
	# Eyes are dark, but they are not eyebrows.  Keep the face eye columns
	# intact; the brow pass below handles only pixels immediately above them.
	if local.y >= 16 and local.y <= 25 \
		and ((local.x >= 19 and local.x <= 31) or (local.x >= 34 and local.x <= 45)) \
		and source.v <= 0.34:
		return false
	return source.s <= 0.48 or source.v <= 0.22

static func _is_reference_skin_pixel(source: Color) -> bool:
	return source.a > 0.05 \
		and source.h >= 0.045 and source.h <= 0.18 \
		and source.s >= 0.20 and source.v >= 0.30

static func _is_reference_face_pixel(source: Color, local: Vector2i) -> bool:
	# Body owns the face. After the old hair silhouette is cleared, every
	# remaining non-transparent pixel in this inner front-face window is an eye,
	# brow, skin edge, nose or mouth and must survive hairstyle replacement.
	# Hair strands remain selectable outside the window (side locks and braids).
	return source.a > 0.05 \
		and local.x >= 19 and local.x <= 44 \
		and local.y >= 12 and local.y <= 26

static func _reference_replacement_blocked(
		source: Color,
		local: Vector2i,
		mounted: bool = false,
		mounted_hair_component: Dictionary = {}
) -> bool:
	# The replacement decision must use the original body pixel, not the copy
	# after old hair has been cleared.  Old neutral hair is allowed to be
	# replaced; skin, eyes and warm anti-aliased face edges remain protected.
	if mounted:
		# The mounted body sheet is a combined rider+horse image.  Keep the
		# original rider-hair component authoritative, reject warm horse/skin
		# pixels and dark face landmarks, but allow neutral/navy pixels in the
		# rider envelope so long styles can trail over the cape instead of being
		# collapsed into the same short cap.
		if source.a <= 0.05 or mounted_hair_component.has(local):
			return false
		var warm_mount_or_skin: bool = source.h >= 0.015 \
			and source.h <= 0.16 \
			and source.s >= 0.24 \
			and source.v >= 0.10
		if warm_mount_or_skin:
			return true
		var dark_face_landmark: bool = local.y >= 4 and local.y <= 22 \
			and local.x >= 19 and local.x <= 45 \
			and source.v <= 0.34
		return dark_face_landmark
	if not _is_reference_face_pixel(source, local):
		return false
	if _is_reference_skin_pixel(source):
		return true
	var warm_face_edge: bool = source.a > 0.05 \
		and source.h >= 0.02 and source.h <= 0.20 \
		and source.s >= 0.08 and source.v >= 0.22
	if warm_face_edge:
		return true
	var eye_pixel: bool = local.y >= 16 and local.y <= 25 \
		and ((local.x >= 19 and local.x <= 31) or (local.x >= 34 and local.x <= 45)) \
		and source.a > 0.05 and source.v <= 0.34
	return eye_pixel

func _dye_group_for_layer(layer: int) -> int:
	match layer:
		PaperDollLayerVisual.RenderLayer.HAIR:
			return DyeGroup.HAIR_BROWS
		PaperDollLayerVisual.RenderLayer.ARMOR:
			return DyeGroup.ARMOR
		PaperDollLayerVisual.RenderLayer.CAPE:
			return DyeGroup.CAPE
		PaperDollLayerVisual.RenderLayer.MOUNT_TAIL:
			return DyeGroup.MOUNT
		PaperDollLayerVisual.RenderLayer.MOUNT_BODY:
			return DyeGroup.MOUNT
		PaperDollLayerVisual.RenderLayer.MOUNT_HEAD:
			return DyeGroup.MOUNT
		PaperDollLayerVisual.RenderLayer.MOUNT_BARDING:
			# Barding is equipment, not the horse's coat.  Keep its dye tied to
			# the armor group so changing the horse colour never recolours it.
			return DyeGroup.ARMOR
	return -1

func _tint_layer_sheet(texture: Texture2D, group: int) -> Texture2D:
	var target: Color = _dye_colors[group] as Color
	var key: String = "layer:%d:%d:%s" % [texture.get_instance_id(), group, target.to_html(false)]
	if _dye_cache.has(key):
		return _dye_cache[key] as Texture2D
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return texture
	image = image.duplicate()
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var source: Color = image.get_pixel(x, y)
			if source.a > 0.05 and _layer_pixel_belongs_to_group(source, Vector2i(x % PaperDollLayerVisual.FRAME_SIZE.x, y % PaperDollLayerVisual.FRAME_SIZE.y), group):
				var dyed: Color = _dye_hair_pixel(source, target) \
					if group == DyeGroup.HAIR_BROWS else _dye_pixel(source, target)
				image.set_pixel(x, y, dyed)
	var result: ImageTexture = ImageTexture.create_from_image(image)
	_dye_cache[key] = result
	return result

func _tint_hair_sheet(texture: Texture2D, group: int) -> Texture2D:
	# The input has already been normalized by _prepare_hair_overlay.  Keep the
	# dye path separate so the same normalized texture is used with or without a
	# color picker value.
	return _tint_layer_sheet(texture, group)

func _prepare_hair_overlay(texture: Texture2D) -> Texture2D:
	var key: String = "hair-overlay:%d" % texture.get_instance_id()
	if _dye_cache.has(key):
		return _dye_cache[key] as Texture2D
	var image: Image = _reference_hair_image(texture, _is_hair_only_texture(texture))
	if image == null or image.is_empty():
		return texture
	var result: ImageTexture = ImageTexture.create_from_image(image)
	_dye_cache[key] = result
	return result

static func _normalized_hair_image(texture: Texture2D) -> Image:
	if texture == null:
		return null
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return image
	image = image.duplicate()
	for y: int in range(image.get_height()):
		var row: int = y / PaperDollLayerVisual.FRAME_SIZE.y
		var local_y: int = y % PaperDollLayerVisual.FRAME_SIZE.y
		for x: int in range(image.get_width()):
			var local_x: int = x % PaperDollLayerVisual.FRAME_SIZE.x
			var source: Color = image.get_pixel(x, y)
			var clear_face: bool = false
			if row == PaperDollLayerVisual.Facing.DOWN:
				# Front: preserve the crown and side locks only. The source art is a
				# complete head, so every lower central pixel belongs to Body's face.
				clear_face = local_y > 12 \
					and not (local_x <= 23 or local_x >= 41)
				clear_face = clear_face or local_y > 23
			elif row == PaperDollLayerVisual.Facing.RIGHT:
				# Side: the profile points right; keep the rear/crown half and clear
				# the face half. LEFT reuses this row and flip_h mirrors it.
				clear_face = local_y > 23 or local_x > 34
			elif row == PaperDollLayerVisual.Facing.UP:
				# Back hair is a solid rear-of-head silhouette, with no face opening.
				clear_face = local_y > 22
			# Alternate head sources contain a painted skin/eye area as well as
			# the hairstyle.  It is never allowed to replace Body's face authority.
			var warm_skin: bool = source.a > 0.05 \
				and source.h >= 0.045 and source.h <= 0.18 \
				and source.s >= 0.35 and source.v >= 0.55
			if warm_skin:
				clear_face = true
			if clear_face:
				image.set_pixel(x, y, Color.TRANSPARENT)
	return image

static func _is_hair_only_texture(texture: Texture2D) -> bool:
	return texture != null and texture.has_meta("paper_doll_hair_only")

static func _reference_hair_image(texture: Texture2D, hair_only: bool = false) -> Image:
	if texture == null:
		return null
	if hair_only or _is_hair_only_texture(texture):
		var hair_only_image: Image = texture.get_image()
		if hair_only_image == null:
			return null
		hair_only_image = hair_only_image.duplicate()
		# The generated hair-only board's SIDE examples are authored in the
		# opposite profile from the accepted body sheet: the hair faces LEFT,
		# while the canonical body SIDE row faces RIGHT.  Align the source once
		# at the composition boundary.  LEFT is then produced by the unified
		# Sprite2D flip_h, so body and hair always turn together.
		_flip_reference_side_rows(hair_only_image)
		return hair_only_image
	return _normalized_hair_image(texture)

static func _flip_reference_side_rows(image: Image) -> void:
	if image == null or image.is_empty():
		return
	var side_row: int = PaperDollLayerVisual.source_row_for(
		PaperDollLayerVisual.Facing.RIGHT
	)
	for frame_x: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
		var origin := Vector2i(
			frame_x * PaperDollLayerVisual.FRAME_SIZE.x,
			side_row * PaperDollLayerVisual.FRAME_SIZE.y
		)
		var frame: Image = image.get_region(Rect2i(origin, PaperDollLayerVisual.FRAME_SIZE))
		frame.flip_x()
		image.blit_rect(
			frame,
			Rect2i(Vector2i.ZERO, PaperDollLayerVisual.FRAME_SIZE),
			origin
		)

## Build the exact mask used by the selected hairstyle replacement.  Dyeing a
## whole top band was the source of the reported "more hair" effect: brown
## braids, brows, nose and cape pixels all shared a heuristic colour range.
## Repeating the same crop/fit operation as the compositor makes alpha the
## authority, so only authored hairstyle pixels can receive hair dye.
static func _build_reference_hair_mask(
		body_texture: Texture2D,
		hair_texture: Texture2D,
		hair_only: bool = false,
		mounted: bool = false
) -> Image:
	if body_texture == null or hair_texture == null:
		return null
	var body_image: Image = body_texture.get_image()
	var hair_image: Image = _reference_hair_image(hair_texture, hair_only)
	if body_image == null or hair_image == null \
			or body_image.is_empty() or hair_image.is_empty() \
			or body_image.get_size() != hair_image.get_size():
		return null
	var mask: Image = Image.create(
		body_image.get_width(),
		body_image.get_height(),
		false,
		Image.FORMAT_RGBA8
	)
	mask.fill(Color.TRANSPARENT)
	for row: int in range(PaperDollLayerVisual.SOURCE_ROWS):
		for frame_x: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
			var origin := Vector2i(
				frame_x * PaperDollLayerVisual.FRAME_SIZE.x,
				row * PaperDollLayerVisual.FRAME_SIZE.y
			)
			var body_frame: Image = body_image.get_region(
				Rect2i(origin, PaperDollLayerVisual.FRAME_SIZE)
			)
			var original_body_frame: Image = body_frame.duplicate()
			var source_frame: Image = hair_image.get_region(
				Rect2i(origin, PaperDollLayerVisual.FRAME_SIZE)
			)
			var source_rect: Rect2i = source_frame.get_used_rect()
			if source_rect.size.x <= 0 or source_rect.size.y <= 0:
				continue
			var target_rect: Rect2i = _reference_hair_target_rect(
				body_frame,
				hair_only,
				source_rect.size,
				mounted
			)
			if target_rect.size.x <= 0 or target_rect.size.y <= 0:
				continue
			var replacement: Image = source_frame.get_region(source_rect)
			replacement.resize(
				target_rect.size.x,
				target_rect.size.y,
				Image.INTERPOLATE_NEAREST
			)
			if row != PaperDollLayerVisual.Facing.UP:
				target_rect = _align_reference_hair_rect(
					body_frame,
					target_rect,
					replacement,
					mounted
				)
			# The compositor clears the old body hair before it blits the selected
			# hairstyle.  Use that same cleared authority here; inspecting the raw
			# body made the mask reject new fringe pixels that overlapped the old
			# white hair, leaving those pixels visible but permanently undyed.
			var mounted_hair_component: Dictionary = _mounted_reference_hair_component(
				original_body_frame
			) if mounted else {}
			_clear_reference_hair(body_frame, mounted)
			for replacement_y: int in range(replacement.get_height()):
				for replacement_x: int in range(replacement.get_width()):
					var alpha: float = replacement.get_pixel(replacement_x, replacement_y).a
					if alpha <= 0.05:
						continue
					var target_position := target_rect.position + Vector2i(
						replacement_x,
						replacement_y
					)
					if target_position.x >= 0 and target_position.x < mask.get_width() \
						and target_position.y >= 0 and target_position.y < mask.get_height():
						if _reference_replacement_blocked(
							original_body_frame.get_pixelv(target_position),
							target_position,
							mounted,
							mounted_hair_component
						):
							continue
						# target_position is local to this 64x64 frame.  The mask is
						# the complete sheet, so include the frame origin; otherwise
						# every animation frame would overwrite the first frame's mask
						# and recolour unrelated face pixels during dyeing.
						mask.set_pixelv(origin + target_position, Color(1.0, 1.0, 1.0, alpha))
	return mask

func _layer_pixel_belongs_to_group(source: Color, local: Vector2i, group: int) -> bool:
	if group != DyeGroup.HAIR_BROWS:
		return true
	# The face opening has already been cleared by _prepare_hair_overlay.  The
	# remaining pixels are the crown/side-lock silhouette, so classify the
	# authored warm palette and dark outline without recoloring skin.
	if local.y > 23:
		return false
	# The accepted white/silver hair is intentionally low-saturation.  Treat
	# neutral pixels in the crown band as hair too; otherwise the dye control
	# would recolour only brown alternates while leaving the default white hair
	# unchanged.  The face opening has already been cleared above, so this band
	# cannot bleed into skin or eye pixels.
	var neutral_hair: bool = source.s <= 0.34 and source.v >= 0.48
	var warm_hair: bool = source.h >= 0.015 and source.h <= 0.18 \
		and source.s >= 0.20
	var dark_outline: bool = source.v <= 0.20 and source.s >= 0.25
	return neutral_hair or warm_hair or dark_outline

func _tint_brows_on_body(texture: Texture2D) -> Texture2D:
	var target: Color = _dye_colors[DyeGroup.HAIR_BROWS] as Color
	var key: String = "brows:%d:%s" % [texture.get_instance_id(), target.to_html(false)]
	if _dye_cache.has(key):
		return _dye_cache[key] as Texture2D
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return texture
	image = image.duplicate()
	_tint_brows_on_image(image, target)
	var result: ImageTexture = ImageTexture.create_from_image(image)
	_dye_cache[key] = result
	return result

static func _tint_brows_on_image(
		image: Image,
		target: Color,
		mounted: bool = false
) -> void:
	# The mounted reference is a compact rider+horse composite. Its brow pixels
	# are not separable from horse tack/armor at 64x64, so never infer brows there.
	if mounted:
		return
	for row: int in range(PaperDollLayerVisual.SOURCE_ROWS):
		for frame_x: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
			var frame_origin := Vector2i(
				frame_x * PaperDollLayerVisual.FRAME_SIZE.x,
				row * PaperDollLayerVisual.FRAME_SIZE.y
			)
			# Find authored dark brow pixels in this exact action frame.  Do not
			# synthesize a brow by painting two pixels above an eye: the accepted
			# reference has skin there, and that old heuristic produced purple
			# forehead/nose specks during hair dye.
			var brow_targets: Array[Vector2i] = _brow_targets_for_frame(image, frame_origin, row)
			for local: Vector2i in brow_targets:
				var position := frame_origin + local
				var source: Color = image.get_pixelv(position)
				if _is_existing_brow_pixel(source):
					image.set_pixelv(position, _dye_hair_pixel(source, target))

static func _brow_targets_for_frame(image: Image, origin: Vector2i, row: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if row == PaperDollLayerVisual.Facing.UP:
		return result
	var regions: Array[Vector2i] = []
	if row == PaperDollLayerVisual.Facing.DOWN:
		regions = [Vector2i(24, 31), Vector2i(33, 40)]
	else:
		regions = [Vector2i(25, 44)]
	for region: Vector2i in regions:
		for y: int in range(12, 16):
			for x: int in range(region.x, region.y + 1):
				var pixel: Color = image.get_pixel(origin.x + x, origin.y + y)
				if not _is_existing_brow_pixel(pixel):
					continue
				var eye_below: bool = false
				for eye_y: int in range(y + 1, mini(y + 6, 27)):
					var below: Color = image.get_pixel(origin.x + x, origin.y + eye_y)
					if below.a > 0.05 and below.v < 0.22:
						eye_below = true
						break
				if eye_below:
					result.append(Vector2i(x, y))
	return result

static func _is_existing_brow_pixel(source: Color) -> bool:
	# Brows are authored dark marks, not warm skin.  This deliberately returns
	# false for the accepted reference's golden forehead so dye never invents a
	# purple stripe above the eyes.
	return source.a > 0.05 and source.v <= 0.30 and source.s <= 0.70

func _tint_reference_sheet(texture: Texture2D, mounted: bool) -> Texture2D:
	if _dye_colors.is_empty():
		return texture
	var key_parts: PackedStringArray = [str(texture.get_instance_id()), "reference", str(mounted)]
	for group: int in [DyeGroup.HAIR_BROWS, DyeGroup.ARMOR, DyeGroup.CAPE, DyeGroup.MOUNT]:
		if _dye_colors.has(group):
			key_parts.append("%d=%s" % [group, (_dye_colors[group] as Color).to_html(false)])
	var key: String = ":".join(key_parts)
	if _dye_cache.has(key):
		return _dye_cache[key] as Texture2D
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return texture
	image = image.duplicate()
	var hair_dye_enabled: bool = _dye_colors.has(DyeGroup.HAIR_BROWS) \
		and (_last_recipe == null or _last_recipe.reference_composite_texture == null)
	var hair_mask: Image = null
	if hair_dye_enabled and _last_recipe != null:
		var mask_body: Texture2D = _base_textures[PaperDollLayerVisual.RenderLayer.BODY] \
			if _base_textures.size() > PaperDollLayerVisual.RenderLayer.BODY else texture
		hair_mask = _build_reference_hair_mask(
			mask_body,
			_last_recipe.reference_hair_texture,
			_last_recipe.reference_hair_is_hair_only,
			mounted
		)
	if hair_dye_enabled:
		# Keep the established on-foot brow pass. Mounted brows are too small to
		# distinguish safely from horse/tack pixels in the accepted composite.
		_tint_brows_on_image(
			image,
			_dye_colors[DyeGroup.HAIR_BROWS] as Color,
			mounted
		)
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var source: Color = image.get_pixel(x, y)
			if source.a <= 0.05:
				continue
			var local: Vector2i = Vector2i(posmod(x, PaperDollLayerVisual.FRAME_SIZE.x), posmod(y, PaperDollLayerVisual.FRAME_SIZE.y))
			var source_row: int = y / PaperDollLayerVisual.FRAME_SIZE.y
			var group: int = -1
			if hair_dye_enabled and hair_mask != null \
					and hair_mask.get_pixel(x, y).a > 0.05:
				group = DyeGroup.HAIR_BROWS
			else:
				group = _reference_group_for_pixel(source, local, mounted, source_row)
			if group >= 0 and _dye_colors.has(group):
				var dyed: Color = _dye_hair_pixel(source, _dye_colors[group] as Color) \
					if group == DyeGroup.HAIR_BROWS \
					else _dye_pixel(source, _dye_colors[group] as Color)
				image.set_pixel(x, y, dyed)
	var result: ImageTexture = ImageTexture.create_from_image(image)
	_dye_cache[key] = result
	return result

func _reference_group_for_pixel(
		source: Color,
		local: Vector2i,
		mounted: bool,
		source_row: int = -1
	) -> int:
	var x: int = local.x
	var y: int = local.y
	var saturation: float = source.s
	var value: float = source.v
	var hue: float = source.h
	if mounted and _is_mount_brown(source, x, y):
		return DyeGroup.MOUNT
	# Navy cloak pixels live on the silhouette edges.  Keeping the side-band
	# restriction avoids recoloring the silver torso as cape material.
	var navy: bool = hue >= 0.55 and hue <= 0.80 and saturation >= 0.18 and value <= 0.52
	# The UP row is the back of the character: the navy central panel is the
	# cape itself, not torso armor.  DOWN and SIDE retain the edge-band guard so
	# a navy-looking shoulder/torso pixel cannot turn the armor red.
	if navy and (
		source_row == PaperDollLayerVisual.Facing.UP
		or x <= 23
		or x >= 40
		or y >= 42
	):
		return DyeGroup.CAPE
	# Remaining low-saturation pixels in the torso/leg band are silver armor.
	if y >= 28 and saturation <= 0.42 and value >= 0.16:
		return DyeGroup.ARMOR
	return -1

func _is_mount_brown(source: Color, x: int, y: int) -> bool:
	var brown: bool = source.h >= 0.015 and source.h <= 0.16
	brown = brown and source.s >= 0.24 and source.v >= 0.10
	if not brown:
		return false
	# Exclude the rider's face/torso band while retaining horse head, body and
	# tail.  The mask is local to each 64x64 frame, so it works for all frames.
	return y >= 34 or x <= 25 or (x >= 43 and y >= 22)

static func _dye_pixel(source: Color, target: Color) -> Color:
	var luminance: float = clampf(
		source.r * 0.299 + source.g * 0.587 + source.b * 0.114,
		0.0,
		1.0
	)
	var target_luminance: float = maxf(
		target.r * 0.299 + target.g * 0.587 + target.b * 0.114,
		0.18
	)
	var value: float = clampf(luminance * maxf(target.v, 0.20) / target_luminance, 0.0, 1.0)
	var saturation: float = maxf(target.s, 0.08)
	return Color.from_hsv(target.h, saturation, value, source.a)

static func _dye_hair_pixel(source: Color, target: Color) -> Color:
	# Hair dye is a colour replacement, not a highlight generator.  The previous
	# pass mapped a white source strand all the way to value 1.0 and reduced its
	# saturation; on a purple dye that made the light strands read as white/pink
	# highlights (挑染) even though the mask was correct.  Keep one hue and one
	# saturation for the complete hairstyle, and compress the authored luminance
	# into a controlled range.  This preserves readable strand depth without
	# allowing any strand to revert to the original white/silver colour.
	var source_luminance: float = clampf(
		source.r * 0.299 + source.g * 0.587 + source.b * 0.114,
		0.0,
		1.0
	)
	var target_value: float = clampf(target.v, 0.16, 1.0)
	var low_value_ratio: float = 0.38 if target.s >= 0.18 else 0.52
	var high_value_ratio: float = 0.82 if target.s >= 0.18 else 1.0
	var value: float = clampf(
		lerpf(target_value * low_value_ratio, target_value * high_value_ratio, source_luminance),
		0.05,
		0.90
	)
	var saturation: float = clampf(target.s, 0.0, 1.0)
	return Color.from_hsv(target.h, saturation, value, source.a)

func _trim_mount_head_overlap(texture: Texture2D) -> Texture2D:
	if texture == null:
		return texture
	var key := "mount-head-clearance:%d" % texture.get_instance_id()
	if _dye_cache.has(key):
		return _dye_cache[key] as Texture2D
	var image := texture.get_image()
	if image == null or image.is_empty():
		return texture
	image = image.duplicate()
	for row: int in range(PaperDollLayerVisual.SOURCE_ROWS):
		if row != PaperDollLayerVisual.Facing.DOWN:
			continue
		for frame_x: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
			# DOWN only: keep the muzzle band while clearing deep centre-neck
			# pixels that would cover the rider's torso. SIDE and UP retain art.
			for y: int in range(30, 64):
				for x: int in range(22, 43):
					image.set_pixel(frame_x * 64 + x, row * 64 + y, Color.TRANSPARENT)
	var result := ImageTexture.create_from_image(image)
	_dye_cache[key] = result
	return result
