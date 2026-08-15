class_name PaperDollContactSheet
extends RefCounted

const SHEET_SIZE: Vector2i = Vector2i(
	PaperDollLayerVisual.FRAME_SIZE.x * PaperDollLayerVisual.FRAME_COLUMNS,
	PaperDollLayerVisual.FRAME_SIZE.y * 4
)

static func compose(recipe: PaperDollRecipe, include_guides: bool = true) -> Image:
	if recipe == null:
		return Image.create(SHEET_SIZE.x, SHEET_SIZE.y, false, Image.FORMAT_RGBA8)
	var images: Dictionary = {}
	for layer: int in range(PaperDollLayerVisual.RenderLayer.COUNT):
		var texture: Texture2D = recipe.texture_for(layer)
		if texture == null:
			continue
		var source: Image = texture.get_image()
		if source == null or source.is_empty():
			continue
		if source.is_compressed():
			source.decompress()
		if source.get_format() != Image.FORMAT_RGBA8:
			source.convert(Image.FORMAT_RGBA8)
		images[layer] = source
	var body_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY)
	if recipe.is_accepted_reference and body_texture != null:
		var reference_body: Texture2D = PaperDollComposer.build_reference_body_texture(recipe)
		if reference_body != null:
			images[PaperDollLayerVisual.RenderLayer.BODY] = reference_body.get_image()
	return _compose_images(images, include_guides, body_texture, recipe.is_accepted_reference)

static func compose_textures(textures: Array[Texture2D], include_guides: bool = true) -> Image:
	var images: Dictionary = {}
	for layer: int in range(mini(textures.size(), PaperDollLayerVisual.RenderLayer.COUNT)):
		var texture: Texture2D = textures[layer]
		if texture == null:
			continue
		var source: Image = texture.get_image()
		if source == null or source.is_empty():
			continue
		if source.is_compressed():
			source.decompress()
		if source.get_format() != Image.FORMAT_RGBA8:
			source.convert(Image.FORMAT_RGBA8)
		images[layer] = source
	return _compose_images(images, include_guides, textures[PaperDollLayerVisual.RenderLayer.BODY] if textures.size() > PaperDollLayerVisual.RenderLayer.BODY else null, false)

static func _compose_images(
		images: Dictionary,
		include_guides: bool,
		body_texture: Texture2D,
		accepted_reference: bool = false
) -> Image:
	var result: Image = Image.create(SHEET_SIZE.x, SHEET_SIZE.y, false, Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	# The reference-match body is already a complete aligned silhouette.  Do not
	# blend legacy rider parts over it: that would recreate the head/armor/mount
	# drift this acceptance pass is meant to remove.  MountBarding is different:
	# it is a horse-only overlay and must remain visible as its own layer.
	if accepted_reference or (body_texture != null and body_texture.resource_path.find("reference_match_body_") >= 0):
		var body_image: Image = images.get(PaperDollLayerVisual.RenderLayer.BODY, null) as Image
		var barding_image: Image = images.get(PaperDollLayerVisual.RenderLayer.MOUNT_BARDING, null) as Image
		images.clear()
		if body_image != null:
			images[PaperDollLayerVisual.RenderLayer.BODY] = body_image
		if barding_image != null:
			images[PaperDollLayerVisual.RenderLayer.MOUNT_BARDING] = barding_image
	# A helmet is an opaque head-slot owner in the Art Gate 1 contract.  Do not
	# composite the independent hair silhouette underneath it: pixels above
	# the helmet crown would otherwise read as a source-row leak in every full
	# stress sheet even though the layer z-index is valid.
	if images.has(PaperDollLayerVisual.RenderLayer.HELMET):
		images.erase(PaperDollLayerVisual.RenderLayer.HAIR)
	for facing: int in range(4):
		var ordered_layers: Array[int] = _ordered_layers(facing)
		var source_row: int = PaperDollLayerVisual.source_row_for(facing)
		for frame_x: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
			var destination: Vector2i = Vector2i(
				frame_x * PaperDollLayerVisual.FRAME_SIZE.x,
				facing * PaperDollLayerVisual.FRAME_SIZE.y
			)
			for layer: int in ordered_layers:
				if not images.has(layer):
					continue
				var source: Image = images[layer] as Image
				var frame: Image = source.get_region(Rect2i(
					Vector2i(
						frame_x * PaperDollLayerVisual.FRAME_SIZE.x,
						source_row * PaperDollLayerVisual.FRAME_SIZE.y
					),
					PaperDollLayerVisual.FRAME_SIZE
				))
				if facing == PaperDollLayerVisual.Facing.LEFT:
					frame.flip_x()
				result.blend_rect(
					frame,
					Rect2i(Vector2i.ZERO, PaperDollLayerVisual.FRAME_SIZE),
					destination
				)
			if include_guides:
				_draw_guides(result, destination)
	return result

static func save_png(recipe: PaperDollRecipe, path: String, include_guides: bool = true) -> Error:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK:
		return directory_error
	return compose(recipe, include_guides).save_png(absolute_path)

static func _ordered_layers(facing: int) -> Array[int]:
	var result: Array[int] = []
	for layer: int in range(PaperDollLayerVisual.RenderLayer.COUNT):
		result.append(layer)
	result.sort_custom(func(left: int, right: int) -> bool:
		var left_z: int = PaperDollComposer.z_index_for(left, facing)
		var right_z: int = PaperDollComposer.z_index_for(right, facing)
		return left_z < right_z if left_z != right_z else left < right
	)
	return result

static func _draw_guides(image: Image, origin: Vector2i) -> void:
	# Keep the QA frame guide neutral; magenta is the source-board chroma key
	# and would make a clean transparent export look like a background leak.
	var border: Color = Color(0.45, 0.52, 0.62, 0.8)
	var anchor: Color = Color(0.0, 1.0, 1.0, 0.9)
	var width: int = PaperDollLayerVisual.FRAME_SIZE.x
	var height: int = PaperDollLayerVisual.FRAME_SIZE.y
	for x: int in range(width):
		image.set_pixelv(origin + Vector2i(x, 0), border)
		image.set_pixelv(origin + Vector2i(x, height - 1), border)
	for y: int in range(height):
		image.set_pixelv(origin + Vector2i(0, y), border)
		image.set_pixelv(origin + Vector2i(width - 1, y), border)
	var anchor_point: Vector2i = origin + Vector2i(PaperDollLayerVisual.WORLD_ANCHOR)
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.ZERO, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		image.set_pixelv(anchor_point + offset, anchor)
