extends SceneTree

## Produces an inspection board from the real PaperDollComposer, without
## opening the full game scene.  Rows are DOWN normal, RIGHT normal, and DOWN
## with purple hair+brow dye.  This is the material-lab acceptance image.

const OUTPUT_PATH := "res://.visual_captures/paper_doll/material_lab_four_hairstyles_dye_preview.png"
const BODY_PATH := "res://assets/paper_doll/reference_match/reference_match_body_on_foot_unisex.png"
const HAIR_IDS := [
	&"hair_short_spiky",
	&"hair_high_ponytail",
	&"hair_bob",
	&"hair_twin_braids",
]
const CELL_SIZE := Vector2i(128, 128)
const BOARD_SIZE := Vector2i(512, 512)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var body_image: Image = Image.load_from_file(ProjectSettings.globalize_path(BODY_PATH))
	if body_image == null or body_image.is_empty():
		push_error("Missing accepted body reference for hairstyle preview")
		quit(1)
		return
	var board: Image = Image.create(BOARD_SIZE.x, BOARD_SIZE.y, false, Image.FORMAT_RGBA8)
	board.fill(Color("121821"))
	for style_index: int in range(HAIR_IDS.size()):
		var hair_path := "res://assets/paper_doll/reference_parts/%s_on_foot_unisex.png" % HAIR_IDS[style_index]
		var hair_image: Image = Image.load_from_file(ProjectSettings.globalize_path(hair_path))
		if hair_image == null or hair_image.is_empty():
			push_error("Missing approved hairstyle sheet: %s" % HAIR_IDS[style_index])
			quit(1)
			return
		var recipe := PaperDollRecipe.new(false)
		recipe.is_accepted_reference = true
		recipe.reference_hair_is_hair_only = true
		recipe.reference_hair_texture = ImageTexture.create_from_image(hair_image)
		recipe.set_layer_texture(PaperDollLayerVisual.RenderLayer.BODY, ImageTexture.create_from_image(body_image))
		var composer := PaperDollComposer.new()
		root.add_child(composer)
		composer.apply_recipe(recipe)
		composer.update_frame(PaperDollLayerVisual.Facing.DOWN, 0)
		var normal_down: Image = _current_frame(composer)
		_blit_frame(board, normal_down, Vector2i(style_index * CELL_SIZE.x, 0))
		composer.update_frame(PaperDollLayerVisual.Facing.RIGHT, 0)
		_blit_frame(board, _current_frame(composer), Vector2i(style_index * CELL_SIZE.x, CELL_SIZE.y))
		composer.update_frame(PaperDollLayerVisual.Facing.LEFT, 0)
		_blit_frame(board, _current_frame(composer), Vector2i(style_index * CELL_SIZE.x, 2 * CELL_SIZE.y))
		composer.set_dye(PaperDollComposer.DyeGroup.HAIR_BROWS, Color("9a4de3"))
		composer.update_frame(PaperDollLayerVisual.Facing.DOWN, 0)
		var dyed: Image = _current_frame(composer)
		assert(_count_skin_changes(normal_down, dyed) == 0, "Hair dye changed face skin for %s" % HAIR_IDS[style_index])
		assert(_count_colours(dyed) >= 5, "Hair dye flattened authored shading for %s" % HAIR_IDS[style_index])
		_blit_frame(board, dyed, Vector2i(style_index * CELL_SIZE.x, 3 * CELL_SIZE.y))
		composer.queue_free()
	var output_path: String = ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.visual_captures/paper_doll"))
	if board.save_png(output_path) != OK:
		push_error("Could not save hairstyle Composer preview")
		quit(1)
		return
	print("COMPOSER FOUR HAIRSTYLE PREVIEW PASS: %s" % OUTPUT_PATH)
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

func _count_skin_changes(before: Image, dyed: Image) -> int:
	var changed: int = 0
	for y: int in range(before.get_height()):
		for x: int in range(before.get_width()):
			var source := before.get_pixel(x, y)
			if not PaperDollComposer._is_reference_skin_pixel(source):
				continue
			if source != dyed.get_pixel(x, y):
				changed += 1
	return changed

func _count_colours(image: Image) -> int:
	var colours: Dictionary = {}
	for y: int in range(mini(image.get_height(), 32)):
		for x: int in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.05:
				colours[pixel.to_html(false)] = true
	return colours.size()
