extends SceneTree

## Captures the four newly added hairstyles through the real Composer.  The
## board is deliberately made from the accepted white-hair/silver-armor body
## reference so the review image answers the only relevant question: do these
## new silhouettes land on the same head, survive all directions, and dye as a
## complete hairstyle without touching the face?

const OUTPUT_PATH := "res://.visual_captures/paper_doll/material_lab_new_four_hairstyles_preview.png"
const BODY_PATH := "res://assets/paper_doll/reference_match/reference_match_body_on_foot_unisex.png"
const HAIR_IDS := [
	&"hair_long_side_ponytail",
	&"hair_crown_braid",
	&"hair_low_bun",
	&"hair_undercut_sweep",
]
const CELL_SIZE := Vector2i(128, 128)
const BOARD_SIZE := Vector2i(512, 512)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var body_image: Image = Image.load_from_file(ProjectSettings.globalize_path(BODY_PATH))
	if body_image == null or body_image.is_empty():
		push_error("Missing accepted body reference for new hairstyle preview")
		quit(1)
		return
	var body_texture := ImageTexture.create_from_image(body_image)
	var board: Image = Image.create(BOARD_SIZE.x, BOARD_SIZE.y, false, Image.FORMAT_RGBA8)
	board.fill(Color("121821"))
	var baseline_by_style: Dictionary = {}
	for style_index: int in range(HAIR_IDS.size()):
		var hair_path := "res://assets/paper_doll/reference_parts/%s_on_foot_unisex.png" % HAIR_IDS[style_index]
		var hair_image: Image = Image.load_from_file(ProjectSettings.globalize_path(hair_path))
		if hair_image == null or hair_image.is_empty():
			push_error("Missing new hairstyle sheet: %s" % HAIR_IDS[style_index])
			quit(1)
			return
		var hair_texture := ImageTexture.create_from_image(hair_image)
		var recipe := PaperDollRecipe.new(false)
		recipe.is_accepted_reference = true
		recipe.reference_hair_is_hair_only = true
		recipe.reference_hair_texture = hair_texture
		recipe.set_layer_texture(PaperDollLayerVisual.RenderLayer.BODY, body_texture)
		var composer := PaperDollComposer.new()
		root.add_child(composer)
		composer.apply_recipe(recipe)
		composer.update_frame(PaperDollLayerVisual.Facing.DOWN, 0)
		var normal_down: Image = _current_frame(composer)
		_blit_frame(board, normal_down, Vector2i(style_index * CELL_SIZE.x, 0))
		composer.update_frame(PaperDollLayerVisual.Facing.RIGHT, 0)
		var normal_right: Image = _current_frame(composer)
		_blit_frame(board, normal_right, Vector2i(style_index * CELL_SIZE.x, CELL_SIZE.y))
		composer.update_frame(PaperDollLayerVisual.Facing.LEFT, 0)
		var normal_left: Image = _current_frame(composer)
		var expected_left: Image = normal_right.duplicate()
		expected_left.flip_x()
		if expected_left.get_data() != normal_left.get_data():
			push_error("LEFT is not the mirrored RIGHT frame for %s" % HAIR_IDS[style_index])
			quit(1)
			return
		_blit_frame(board, normal_left, Vector2i(style_index * CELL_SIZE.x, 2 * CELL_SIZE.y))
		composer.set_dye(PaperDollComposer.DyeGroup.HAIR_BROWS, Color("9a4de3"))
		composer.update_frame(PaperDollLayerVisual.Facing.DOWN, 0)
		var dyed: Image = _current_frame(composer)
		var full_mask: Image = PaperDollComposer._build_reference_hair_mask(
			body_texture,
			hair_texture,
			true
		)
		var authority_frame: Image = body_image.get_region(Rect2i(
			Vector2i.ZERO,
			PaperDollLayerVisual.FRAME_SIZE
		))
		var mask_frame: Image = full_mask.get_region(Rect2i(
			Vector2i.ZERO,
			PaperDollLayerVisual.FRAME_SIZE
		))
		var skin_changes: int = _count_reference_face_changes(
			authority_frame,
			normal_down,
			dyed,
			mask_frame
		)
		var hair_changes: int = _count_hair_changes(
			full_mask,
			normal_down,
			dyed
		)
		var unapplied_hair: int = _count_unapplied_hair_pixels(
			mask_frame,
			normal_down,
			dyed
		)
		if skin_changes != 0:
			print("SKIN_CHANGE %s count=%d coords=%s" % [HAIR_IDS[style_index], skin_changes, _skin_change_locations(normal_down, dyed)])
			push_error("Hair dye changed face skin for %s (%d)" % [HAIR_IDS[style_index], skin_changes])
			quit(1)
			return
		if hair_changes <= 0:
			push_error("Hair dye changed no hair pixels for %s" % HAIR_IDS[style_index])
			quit(1)
			return
		if unapplied_hair != 0:
			push_error("Hair dye left %d pixels unchanged for %s" % [unapplied_hair, HAIR_IDS[style_index]])
			quit(1)
			return
		if _count_colours(dyed) < 5:
			push_error("Hair dye flattened authored shading for %s" % HAIR_IDS[style_index])
			quit(1)
			return
		_blit_frame(board, dyed, Vector2i(style_index * CELL_SIZE.x, 3 * CELL_SIZE.y))
		baseline_by_style[HAIR_IDS[style_index]] = normal_down.get_data()
		composer.queue_free()
	for left: int in range(HAIR_IDS.size()):
		for right: int in range(left + 1, HAIR_IDS.size()):
			if baseline_by_style[HAIR_IDS[left]] == baseline_by_style[HAIR_IDS[right]]:
				push_error("New hairstyles compose identically: %s/%s" % [HAIR_IDS[left], HAIR_IDS[right]])
				quit(1)
				return
	var output_path: String = ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.visual_captures/paper_doll"))
	if board.save_png(output_path) != OK:
		push_error("Could not save new hairstyle Composer preview")
		quit(1)
		return
	print("COMPOSER NEW FOUR HAIRSTYLE PREVIEW PASS: %s" % OUTPUT_PATH)
	quit(0)

func _current_frame(composer: PaperDollComposer) -> Image:
	var body_sprite: Sprite2D = composer.sprite_for(PaperDollLayerVisual.RenderLayer.BODY)
	var texture: Texture2D = body_sprite.texture
	var source_row: int = PaperDollLayerVisual.source_row_for(composer.current_facing)
	var frame := texture.get_image().get_region(Rect2i(
		composer.current_frame_x * PaperDollLayerVisual.FRAME_SIZE.x,
		source_row * PaperDollLayerVisual.FRAME_SIZE.y,
		PaperDollLayerVisual.FRAME_SIZE.x,
		PaperDollLayerVisual.FRAME_SIZE.y
	))
	if body_sprite.flip_h:
		frame.flip_x()
	return frame

func _blit_frame(board: Image, frame: Image, position: Vector2i) -> void:
	var enlarged: Image = frame.duplicate()
	enlarged.resize(CELL_SIZE.x, CELL_SIZE.y, Image.INTERPOLATE_NEAREST)
	board.blend_rect(enlarged, Rect2i(Vector2i.ZERO, CELL_SIZE), position)

func _count_reference_face_changes(
	authority: Image,
	before: Image,
	dyed: Image,
	hair_mask: Image
) -> int:
	var changed: int = 0
	var brow_targets: Array[Vector2i] = PaperDollComposer._brow_targets_for_frame(
		 authority,
		 Vector2i.ZERO,
		 PaperDollLayerVisual.Facing.DOWN
	)
	for y: int in range(mini(before.get_height(), dyed.get_height())):
		for x: int in range(mini(before.get_width(), dyed.get_width())):
			var local := Vector2i(x, y)
			if hair_mask != null and hair_mask.get_pixel(x, y).a > 0.05:
				continue
			if local in brow_targets:
				continue
			if not PaperDollComposer._reference_replacement_blocked(
					authority.get_pixel(x, y),
					local
			):
				continue
			if before.get_pixel(x, y) != dyed.get_pixel(x, y):
				changed += 1
	return changed

func _skin_change_locations(before: Image, dyed: Image) -> PackedStringArray:
	var result: PackedStringArray = []
	for y: int in range(before.get_height()):
		for x: int in range(before.get_width()):
			var source := before.get_pixel(x, y)
			if PaperDollComposer._is_reference_skin_pixel(source) \
				and source != dyed.get_pixel(x, y):
				result.append("(%d,%d) %s->%s" % [x, y, source.to_html(false), dyed.get_pixel(x, y).to_html(false)])
	return result

func _count_hair_changes(mask: Image, before: Image, dyed: Image) -> int:
	if mask == null:
		return 0
	var changed: int = 0
	var width: int = mini(mask.get_width(), mini(before.get_width(), dyed.get_width()))
	var height: int = mini(mask.get_height(), mini(before.get_height(), dyed.get_height()))
	for y: int in range(height):
		for x: int in range(width):
			if mask.get_pixel(x, y).a > 0.05 and before.get_pixel(x, y) != dyed.get_pixel(x, y):
				changed += 1
	return changed

func _count_unapplied_hair_pixels(mask: Image, before: Image, dyed: Image) -> int:
	if mask == null:
		return 0
	var unchanged: int = 0
	var width: int = mini(mask.get_width(), mini(before.get_width(), dyed.get_width()))
	var height: int = mini(mask.get_height(), mini(before.get_height(), dyed.get_height()))
	for y: int in range(height):
		for x: int in range(width):
			if mask.get_pixel(x, y).a > 0.05 and before.get_pixel(x, y) == dyed.get_pixel(x, y):
				unchanged += 1
	return unchanged

func _count_colours(image: Image) -> int:
	var colours: Dictionary = {}
	for y: int in range(mini(image.get_height(), 32)):
		for x: int in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.05:
				colours[pixel.to_html(false)] = true
	return colours.size()
