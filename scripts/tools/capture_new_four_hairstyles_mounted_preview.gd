extends SceneTree

## Mounted counterpart of the new-hairstyle preview.  The same hair-only
## sheets are intentionally reused for mounted recipes; this capture proves
## the Composer's mounted body anchor and side mirroring still hold.

const OUTPUT_PATH := "res://.visual_captures/paper_doll/material_lab_new_four_hairstyles_mounted_preview.png"
const BODY_PATH := "res://assets/paper_doll/reference_match/reference_match_body_mounted_unisex.png"
const HAIR_IDS := [
	&"hair_long_side_ponytail",
	&"hair_crown_braid",
	&"hair_low_bun",
	&"hair_undercut_sweep",
]
const CELL_SIZE := Vector2i(256, 256)
const BOARD_SIZE := Vector2i(1024, 1024)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var body_image: Image = Image.load_from_file(ProjectSettings.globalize_path(BODY_PATH))
	if body_image == null or body_image.is_empty():
		push_error("Missing accepted mounted body reference")
		quit(1)
		return
	var body_texture := ImageTexture.create_from_image(body_image)
	var board: Image = Image.create(BOARD_SIZE.x, BOARD_SIZE.y, false, Image.FORMAT_RGBA8)
	board.fill(Color("121821"))
	for style_index: int in range(HAIR_IDS.size()):
		var hair_path := "res://assets/paper_doll/reference_parts/%s_on_foot_unisex.png" % HAIR_IDS[style_index]
		var hair_image: Image = Image.load_from_file(ProjectSettings.globalize_path(hair_path))
		if hair_image == null or hair_image.is_empty():
			push_error("Missing new hairstyle sheet: %s" % HAIR_IDS[style_index])
			quit(1)
			return
		var recipe := PaperDollRecipe.new(true)
		recipe.is_accepted_reference = true
		recipe.reference_hair_is_hair_only = true
		recipe.reference_hair_texture = ImageTexture.create_from_image(hair_image)
		recipe.set_layer_texture(
			PaperDollLayerVisual.RenderLayer.BODY,
			body_texture
		)
		var composer := PaperDollComposer.new()
		root.add_child(composer)
		composer.apply_recipe(recipe)
		composer.update_frame(PaperDollLayerVisual.Facing.DOWN, 0)
		var down: Image = _current_frame(composer)
		if _count_protected_mount_changes(_source_frame(body_image, PaperDollLayerVisual.Facing.DOWN), down) != 0:
			push_error("Mounted DOWN replaced horse/face pixels for %s" % HAIR_IDS[style_index])
			quit(1)
			return
		_blit_frame(board, down, Vector2i(style_index * CELL_SIZE.x, 0))
		composer.update_frame(PaperDollLayerVisual.Facing.RIGHT, 0)
		var right: Image = _current_frame(composer)
		if _count_protected_mount_changes(_source_frame(body_image, PaperDollLayerVisual.Facing.RIGHT), right) != 0:
			push_error("Mounted RIGHT replaced horse/face pixels for %s" % HAIR_IDS[style_index])
			quit(1)
			return
		_blit_frame(board, right, Vector2i(style_index * CELL_SIZE.x, CELL_SIZE.y))
		composer.update_frame(PaperDollLayerVisual.Facing.LEFT, 0)
		var left: Image = _current_frame(composer)
		if _count_protected_mount_changes(_source_frame(body_image, PaperDollLayerVisual.Facing.LEFT), left) != 0:
			push_error("Mounted LEFT replaced horse/face pixels for %s" % HAIR_IDS[style_index])
			quit(1)
			return
		var expected_left: Image = right.duplicate()
		expected_left.flip_x()
		if expected_left.get_data() != left.get_data():
			push_error("Mounted LEFT is not the mirrored RIGHT frame for %s" % HAIR_IDS[style_index])
			quit(1)
			return
		_blit_frame(board, left, Vector2i(style_index * CELL_SIZE.x, 2 * CELL_SIZE.y))
		composer.set_dye(PaperDollComposer.DyeGroup.HAIR_BROWS, Color("9a4de3"))
		composer.update_frame(PaperDollLayerVisual.Facing.DOWN, 0)
		var dyed_down: Image = _current_frame(composer)
		if _count_protected_mount_changes(
				_source_frame(body_image, PaperDollLayerVisual.Facing.DOWN),
				dyed_down
			) != 0:
			print("MOUNTED_DYE_PROTECTED_CHANGES %s" % _protected_change_locations(
				_source_frame(body_image, PaperDollLayerVisual.Facing.DOWN),
				dyed_down
			))
			push_error("Mounted dye touched horse/face pixels for %s" % HAIR_IDS[style_index])
			quit(1)
			return
		_blit_frame(board, dyed_down, Vector2i(style_index * CELL_SIZE.x, 3 * CELL_SIZE.y))
		composer.queue_free()
	var output_path: String = ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.visual_captures/paper_doll"))
	if board.save_png(output_path) != OK:
		push_error("Could not save mounted hairstyle preview")
		quit(1)
		return
	print("COMPOSER NEW FOUR MOUNTED PREVIEW PASS: %s" % OUTPUT_PATH)
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

func _source_frame(sheet: Image, facing: int) -> Image:
	var frame: Image = sheet.get_region(Rect2i(
		Vector2i(0, PaperDollLayerVisual.source_row_for(facing) * PaperDollLayerVisual.FRAME_SIZE.y),
		PaperDollLayerVisual.FRAME_SIZE
	))
	if facing == PaperDollLayerVisual.Facing.LEFT:
		frame.flip_x()
	return frame

func _count_protected_mount_changes(before: Image, after: Image) -> int:
	var protected: int = 0
	var hair_component: Dictionary = PaperDollComposer._mounted_reference_hair_component(before)
	for y: int in range(before.get_height()):
		for x: int in range(before.get_width()):
			if before.get_pixel(x, y) == after.get_pixel(x, y):
				continue
			var local := Vector2i(x, y)
			if hair_component.has(local):
				continue
			var source: Color = before.get_pixelv(local)
			var warm_mount_or_skin: bool = source.a > 0.05 \
				and source.h >= 0.015 and source.h <= 0.16 \
				and source.s >= 0.24 and source.v >= 0.10
			var dark_face_landmark: bool = source.a > 0.05 \
				and local.y >= 4 and local.y <= 22 \
				and local.x >= 19 and local.x <= 45 \
				and source.v <= 0.34
			if warm_mount_or_skin or dark_face_landmark:
				protected += 1
	return protected

func _protected_change_locations(before: Image, after: Image) -> PackedStringArray:
	var result: PackedStringArray = []
	var hair_component: Dictionary = PaperDollComposer._mounted_reference_hair_component(before)
	for y: int in range(before.get_height()):
		for x: int in range(before.get_width()):
			var local := Vector2i(x, y)
			if before.get_pixel(x, y) == after.get_pixel(x, y) or hair_component.has(local):
				continue
			var source: Color = before.get_pixelv(local)
			var warm_mount_or_skin: bool = source.a > 0.05 \
				and source.h >= 0.015 and source.h <= 0.16 \
				and source.s >= 0.24 and source.v >= 0.10
			var dark_face_landmark: bool = source.a > 0.05 \
				and local.y >= 4 and local.y <= 22 \
				and local.x >= 19 and local.x <= 45 \
				and source.v <= 0.34
			if warm_mount_or_skin or dark_face_landmark:
				result.append("(%d,%d):%s->%s" % [x, y, source.to_html(false), after.get_pixel(x, y).to_html(false)])
				if result.size() >= 20:
					return result
	return result

func _blit_frame(board: Image, frame: Image, position: Vector2i) -> void:
	var enlarged: Image = frame.duplicate()
	enlarged.resize(CELL_SIZE.x, CELL_SIZE.y, Image.INTERPOLATE_NEAREST)
	board.blend_rect(enlarged, Rect2i(Vector2i.ZERO, CELL_SIZE), position)
