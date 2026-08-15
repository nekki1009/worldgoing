extends SceneTree

## Produces a real Composer preview for cape dyeing.
##
## Columns: DOWN, RIGHT, UP, LEFT
## Row 0: accepted reference cape
## Row 1: the same recipe with a crimson cape dye
##
## The pixel contract is intentionally strict: every pixel that the Composer
## classifies as CAPE must change, and no pixel outside that group may change.

const OUTPUT_PATH := "res://.visual_captures/paper_doll/cape_dye_preview.png"
const BODY_PATH := "res://assets/paper_doll/reference_match/reference_match_body_on_foot_unisex.png"
const HAIR_PATH := "res://assets/paper_doll/reference_parts/hair_short_spiky_on_foot_unisex.png"
const CELL_SIZE := Vector2i(128, 128)
const BOARD_SIZE := Vector2i(512, 256)
const DYE_COLOR := Color("b74f5b")
const DIRECTIONS := [
	PaperDollLayerVisual.Facing.DOWN,
	PaperDollLayerVisual.Facing.RIGHT,
	PaperDollLayerVisual.Facing.UP,
	PaperDollLayerVisual.Facing.LEFT,
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var body_image: Image = Image.load_from_file(ProjectSettings.globalize_path(BODY_PATH))
	var hair_image: Image = Image.load_from_file(ProjectSettings.globalize_path(HAIR_PATH))
	if body_image == null or body_image.is_empty() or hair_image == null or hair_image.is_empty():
		push_error("Missing accepted body or hair source for cape dye preview")
		quit(1)
		return

	var recipe := PaperDollRecipe.new(false)
	recipe.is_accepted_reference = true
	recipe.reference_hair_is_hair_only = true
	recipe.reference_hair_texture = ImageTexture.create_from_image(hair_image)
	recipe.set_layer_texture(
		PaperDollLayerVisual.RenderLayer.BODY,
		ImageTexture.create_from_image(body_image)
	)
	var composer := PaperDollComposer.new()
	root.add_child(composer)
	composer.apply_recipe(recipe)
	var normal_frames: Array[Image] = []
	var board: Image = Image.create(BOARD_SIZE.x, BOARD_SIZE.y, false, Image.FORMAT_RGBA8)
	board.fill(Color("121821"))
	for index: int in range(DIRECTIONS.size()):
		composer.update_frame(DIRECTIONS[index], 0)
		var normal: Image = _current_frame(composer)
		normal_frames.append(normal)
		_blit_frame(board, normal, Vector2i(index * CELL_SIZE.x, 0))

	composer.set_dye(PaperDollComposer.DyeGroup.CAPE, DYE_COLOR)
	var failures: PackedStringArray = PackedStringArray()
	for index: int in range(DIRECTIONS.size()):
		composer.update_frame(DIRECTIONS[index], 0)
		var dyed: Image = _current_frame(composer)
		_blit_frame(board, dyed, Vector2i(index * CELL_SIZE.x, CELL_SIZE.y))
		var metrics: Dictionary = _cape_metrics(composer, normal_frames[index], dyed)
		print(
			"CAPE=%s EXPECTED=%d CHANGED=%d UNCHANGED=%d OTHER_CHANGED=%d" % [
				_direction_name(DIRECTIONS[index]),
				metrics.expected,
				metrics.changed,
				metrics.unchanged,
				metrics.other_changed,
			]
		)
		if metrics.expected <= 0:
			failures.append("no cape pixels classified: %s" % _direction_name(DIRECTIONS[index]))
		if metrics.unchanged > 0:
			failures.append("cape pixels left unchanged (%d): %s" % [metrics.unchanged, _direction_name(DIRECTIONS[index])])
		if metrics.other_changed > 0:
			failures.append("non-cape pixels changed (%d): %s" % [metrics.other_changed, _direction_name(DIRECTIONS[index])])
	composer.queue_free()

	var output_path: String = ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.visual_captures/paper_doll"))
	if board.save_png(output_path) != OK:
		failures.append("could not save preview")
	if failures.is_empty():
		print("CAPE DYE PREVIEW PASS: %s" % OUTPUT_PATH)
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		print("CAPE DYE PREVIEW FAIL: %d issue(s)" % failures.size())
		quit(1)

func _current_frame(composer: PaperDollComposer) -> Image:
	var sprite: Sprite2D = composer.sprite_for(PaperDollLayerVisual.RenderLayer.BODY)
	var texture: Texture2D = sprite.texture
	var frame := texture.get_image().get_region(Rect2i(
		composer.current_frame_x * PaperDollLayerVisual.FRAME_SIZE.x,
		PaperDollLayerVisual.source_row_for(composer.current_facing) * PaperDollLayerVisual.FRAME_SIZE.y,
		PaperDollLayerVisual.FRAME_SIZE.x,
		PaperDollLayerVisual.FRAME_SIZE.y
	))
	if sprite.flip_h:
		frame.flip_x()
	return frame

func _cape_metrics(composer: PaperDollComposer, before: Image, dyed: Image) -> Dictionary:
	var expected: int = 0
	var changed: int = 0
	var unchanged: int = 0
	var other_changed: int = 0
	for y: int in range(before.get_height()):
		for x: int in range(before.get_width()):
			var source: Color = before.get_pixel(x, y)
			var group: int = composer._reference_group_for_pixel(
				source,
				Vector2i(x, y),
				false,
			PaperDollLayerVisual.source_row_for(composer.current_facing)
			)
			var did_change: bool = source != dyed.get_pixel(x, y)
			if group == PaperDollComposer.DyeGroup.CAPE:
				expected += 1
				if did_change:
					changed += 1
				else:
					unchanged += 1
			elif did_change:
				other_changed += 1
	return {
		"expected": expected,
		"changed": changed,
		"unchanged": unchanged,
		"other_changed": other_changed,
	}

func _blit_frame(board: Image, frame: Image, position: Vector2i) -> void:
	var enlarged: Image = frame.duplicate()
	enlarged.resize(CELL_SIZE.x, CELL_SIZE.y, Image.INTERPOLATE_NEAREST)
	board.blend_rect(enlarged, Rect2i(Vector2i.ZERO, CELL_SIZE), position)

func _direction_name(direction: int) -> String:
	match direction:
		PaperDollLayerVisual.Facing.DOWN:
			return "DOWN"
		PaperDollLayerVisual.Facing.RIGHT:
			return "RIGHT"
		PaperDollLayerVisual.Facing.UP:
			return "UP"
		PaperDollLayerVisual.Facing.LEFT:
			return "LEFT"
	return "UNKNOWN"
