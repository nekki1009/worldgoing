extends SceneTree

## Diagnostic only: print the mounted replacement rectangles and pixel-change
## bounds for each new hairstyle.  A mounted body contains both rider and horse,
## so the target rectangle must be anchored to the rider head, never to horse
## ears/muzzle pixels.

const BODY_PATH := "res://assets/paper_doll/reference_match/reference_match_body_mounted_unisex.png"
const HORSE_BODY_PATH := "res://assets/paper_doll/parts/artgate1_horse_body_mounted_unisex.png"
const HAIR_IDS := [
	&"hair_long_side_ponytail",
	&"hair_crown_braid",
	&"hair_low_bun",
	&"hair_undercut_sweep",
]

func _init() -> void:
	var body_image: Image = Image.load_from_file(ProjectSettings.globalize_path(BODY_PATH))
	if body_image == null or body_image.is_empty():
		push_error("missing mounted body")
		quit(1)
		return
	var body_texture := ImageTexture.create_from_image(body_image)
	var horse_body_image: Image = Image.load_from_file(ProjectSettings.globalize_path(HORSE_BODY_PATH))
	if horse_body_image == null or horse_body_image.is_empty():
		push_error("missing mounted horse body")
		quit(1)
		return
	var white_leg_pixels: int = _count_white_pixels_inside_horse_leg_mask(
		body_image,
		horse_body_image
	)
	print("MOUNTED HORSE LEG WHITE PIXELS=%d" % white_leg_pixels)
	if white_leg_pixels != 0:
		push_error("mounted composite still contains white pixels inside the horse leg mask")
		quit(1)
		return
	for hair_id: StringName in HAIR_IDS:
		var hair_path := "res://assets/paper_doll/reference_parts/%s_on_foot_unisex.png" % hair_id
		var hair_image: Image = Image.load_from_file(ProjectSettings.globalize_path(hair_path))
		var hair_texture := ImageTexture.create_from_image(hair_image)
		var normalized: Image = PaperDollComposer._reference_hair_image(hair_texture, true)
		var recipe := PaperDollRecipe.new(true)
		recipe.is_accepted_reference = true
		recipe.reference_hair_is_hair_only = true
		recipe.reference_hair_texture = hair_texture
		recipe.set_layer_texture(PaperDollLayerVisual.RenderLayer.BODY, body_texture)
		var composed: Image = PaperDollComposer.build_reference_body_texture(recipe).get_image()
		print("HAIR=%s" % hair_id)
		for row: int in range(PaperDollLayerVisual.SOURCE_ROWS):
			var origin := Vector2i(0, row * PaperDollLayerVisual.FRAME_SIZE.y)
			var body_frame: Image = body_image.get_region(Rect2i(origin, PaperDollLayerVisual.FRAME_SIZE))
			var source_frame: Image = normalized.get_region(Rect2i(origin, PaperDollLayerVisual.FRAME_SIZE))
			var source_rect: Rect2i = source_frame.get_used_rect()
			var base: Rect2i = PaperDollComposer._reference_hair_rect(body_frame, true)
			var target: Rect2i = PaperDollComposer._reference_hair_target_rect(body_frame, true, source_rect.size, true)
			var changed: Rect2i = _changed_rect(
				body_frame,
				composed.get_region(Rect2i(origin, PaperDollLayerVisual.FRAME_SIZE))
			)
			var warm_changed: int = _count_warm_changed(
				body_frame,
				composed.get_region(Rect2i(origin, PaperDollLayerVisual.FRAME_SIZE))
			)
			var warm_locations: PackedStringArray = _warm_change_locations(
				body_frame,
				composed.get_region(Rect2i(origin, PaperDollLayerVisual.FRAME_SIZE))
			)
			print(" row=%d source=%s base=%s target=%s changed=%s warm_changed=%d sample=%s" % [row, source_rect, base, target, changed, warm_changed, warm_locations])
			if warm_changed != 0:
				push_error("mounted hairstyle overwrote protected warm pixels: %s row=%d" % [hair_id, row])
				quit(1)
				return
	quit(0)

func _count_white_pixels_inside_horse_leg_mask(composite: Image, horse: Image) -> int:
	var result: int = 0
	for row: int in range(PaperDollLayerVisual.SOURCE_ROWS):
		# The accepted composite repeats its calibrated view in all eight columns;
		# compare each column with the horse mask from frame 0, matching the packer.
		var horse_origin := Vector2i(0, row * PaperDollLayerVisual.FRAME_SIZE.y)
		for frame_x: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
			var composite_origin := Vector2i(
				frame_x * PaperDollLayerVisual.FRAME_SIZE.x,
				row * PaperDollLayerVisual.FRAME_SIZE.y
			)
			for y: int in range(44, 56):
				for x: int in range(PaperDollLayerVisual.FRAME_SIZE.x):
					var source: Color = composite.get_pixelv(composite_origin + Vector2i(x, y))
					var horse_pixel: Color = horse.get_pixelv(horse_origin + Vector2i(x, y))
					if source.a <= 0.05 or horse_pixel.a <= 0.05:
						continue
					var minimum: float = minf(source.r, minf(source.g, source.b))
					var maximum: float = maxf(source.r, maxf(source.g, source.b))
					var white_foreground: bool = minimum >= 0.72 and maximum - minimum <= 0.16
					var warm_horse: bool = horse_pixel.h >= 0.015 \
						and horse_pixel.h <= 0.16 \
						and horse_pixel.s >= 0.20 \
						and horse_pixel.v >= 0.10
					if white_foreground and warm_horse:
						result += 1
	return result

func _changed_rect(before: Image, after: Image) -> Rect2i:
	var used := Rect2i()
	var min_x: int = before.get_width()
	var min_y: int = before.get_height()
	var max_x: int = -1
	var max_y: int = -1
	for y: int in range(before.get_height()):
		for x: int in range(before.get_width()):
			if before.get_pixel(x, y) == after.get_pixel(x, y):
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return used
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)

func _count_warm_changed(before: Image, after: Image) -> int:
	var count: int = 0
	var allowed_hair: Dictionary = PaperDollComposer._mounted_reference_hair_component(before)
	for y: int in range(before.get_height()):
		for x: int in range(before.get_width()):
			var source: Color = before.get_pixel(x, y)
			if source == after.get_pixel(x, y):
				continue
			if allowed_hair.has(Vector2i(x, y)):
				continue
			if source.h >= 0.015 and source.h <= 0.16 \
				and source.s >= 0.24 and source.v >= 0.10:
				count += 1
	return count

func _warm_change_locations(before: Image, after: Image) -> PackedStringArray:
	var result: PackedStringArray = []
	var allowed_hair: Dictionary = PaperDollComposer._mounted_reference_hair_component(before)
	for y: int in range(before.get_height()):
		for x: int in range(before.get_width()):
			var source: Color = before.get_pixel(x, y)
			if source == after.get_pixel(x, y):
				continue
			if allowed_hair.has(Vector2i(x, y)):
				continue
			if source.h >= 0.015 and source.h <= 0.16 \
				and source.s >= 0.24 and source.v >= 0.10:
				result.append("(%d,%d):%s" % [x, y, source.to_html(false)])
				if result.size() >= 12:
					return result
	return result
