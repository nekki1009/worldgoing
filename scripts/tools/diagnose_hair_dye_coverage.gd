extends SceneTree

## Diagnostic board for the accepted hair-only reference path.
##
## Rows per hairstyle are:
##   0 - composed hair before dye
##   1 - composed hair after dye
##   2 - exact hair mask (magenta = pixels eligible for dye)
##   3 - mask coverage (green = changed, red = eligible but unchanged)
##
## This intentionally measures the mask against the actual Composer output;
## a check that only looks for white pixels can miss an entire undyed fringe.

const OUTPUT_PATH := "res://.visual_captures/paper_doll/hair_dye_coverage_debug.png"
const HAIR_IDS := [
	&"hair_short_spiky",
	&"hair_high_ponytail",
	&"hair_bob",
	&"hair_twin_braids",
]
const CELL_SIZE := Vector2i(64, 64)
const BOARD_SIZE := Vector2i(256, 256)
const DYE_COLOR := Color("9a4de3")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var catalog: PaperDollCatalog = PaperDollCatalog.create_art_gate1_catalog()
	var board: Image = Image.create(BOARD_SIZE.x, BOARD_SIZE.y, false, Image.FORMAT_RGBA8)
	board.fill(Color("121821"))
	for style_index: int in range(HAIR_IDS.size()):
		var draft := PaperDollPreviewDraft.new()
		draft.gender = PaperDollLayerVisual.Gender.MALE
		draft.set_visual(PaperDollLayerVisual.RenderLayer.BODY, &"body_male_default")
		draft.set_visual(PaperDollLayerVisual.RenderLayer.ARMOR, &"artgate1_armor")
		draft.set_visual(PaperDollLayerVisual.RenderLayer.HAIR, HAIR_IDS[style_index])
		draft.set_visual(PaperDollLayerVisual.RenderLayer.CAPE, &"artgate1_cape")
		var recipe: PaperDollRecipe = catalog.resolve_recipe(draft)
		if recipe == null:
			push_error("Could not resolve hairstyle: %s" % HAIR_IDS[style_index])
			quit(1)
			return
		var composer := PaperDollComposer.new()
		root.add_child(composer)
		composer.apply_recipe(recipe)
		composer.update_frame(PaperDollLayerVisual.Facing.DOWN, 0)
		var before: Image = _current_frame(composer)
		var mask_sheet: Image = PaperDollComposer._build_reference_hair_mask(
			recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY),
			recipe.reference_hair_texture,
			recipe.reference_hair_is_hair_only
		)
		var mask: Image = _frame_from_sheet(mask_sheet, PaperDollLayerVisual.Facing.DOWN)
		composer.set_dye(PaperDollComposer.DyeGroup.HAIR_BROWS, DYE_COLOR)
		var dyed: Image = _current_frame(composer)
		var mask_count: int = 0
		var changed_count: int = 0
		var missed_count: int = 0
		for y: int in range(CELL_SIZE.y):
			for x: int in range(CELL_SIZE.x):
				if mask.get_pixel(x, y).a <= 0.05:
					continue
				mask_count += 1
				if before.get_pixel(x, y) == dyed.get_pixel(x, y):
					missed_count += 1
				else:
					changed_count += 1
				var mask_pixel := Color("d33bff") if mask.get_pixel(x, y).a > 0.05 else Color("121821")
				var coverage_pixel := Color("e83d4f") if before.get_pixel(x, y) == dyed.get_pixel(x, y) else Color("38d978")
				board.set_pixel(style_index * CELL_SIZE.x + x, 2 * CELL_SIZE.y + y, mask_pixel)
				board.set_pixel(style_index * CELL_SIZE.x + x, 3 * CELL_SIZE.y + y, coverage_pixel)
		_blit(board, before, Vector2i(style_index * CELL_SIZE.x, 0))
		_blit(board, dyed, Vector2i(style_index * CELL_SIZE.x, CELL_SIZE.y))
		print("HAIR=%s MASK=%d CHANGED=%d MISSED=%d" % [HAIR_IDS[style_index], mask_count, changed_count, missed_count])
		composer.queue_free()
	var output_path: String = ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.visual_captures/paper_doll"))
	var enlarged := board.duplicate()
	enlarged.resize(BOARD_SIZE.x * 4, BOARD_SIZE.y * 4, Image.INTERPOLATE_NEAREST)
	if enlarged.save_png(output_path) != OK:
		push_error("Could not save hair dye coverage diagnostic")
		quit(1)
		return
	print("HAIR DYE COVERAGE DIAGNOSTIC: %s" % OUTPUT_PATH)
	quit(0)

func _current_frame(composer: PaperDollComposer) -> Image:
	var sprite: Sprite2D = composer.sprite_for(PaperDollLayerVisual.RenderLayer.BODY)
	var image: Image = sprite.texture.get_image().get_region(Rect2i(
		composer.current_frame_x * PaperDollLayerVisual.FRAME_SIZE.x,
		PaperDollLayerVisual.source_row_for(composer.current_facing) * PaperDollLayerVisual.FRAME_SIZE.y,
		PaperDollLayerVisual.FRAME_SIZE.x,
		PaperDollLayerVisual.FRAME_SIZE.y
	))
	if sprite.flip_h:
		image.flip_x()
	return image

func _frame_from_sheet(sheet: Image, facing: int) -> Image:
	if sheet == null:
		return Image.create(CELL_SIZE.x, CELL_SIZE.y, false, Image.FORMAT_RGBA8)
	return sheet.get_region(Rect2i(
		0,
		PaperDollLayerVisual.source_row_for(facing) * PaperDollLayerVisual.FRAME_SIZE.y,
		CELL_SIZE.x,
		CELL_SIZE.y
	))

func _blit(board: Image, frame: Image, position: Vector2i) -> void:
	board.blit_rect(frame, Rect2i(Vector2i.ZERO, CELL_SIZE), position)
