extends SceneTree

## Previews a hair-only overlay mask without touching the catalog assets.  Body
## remains the face/brow authority; the final pass can be promoted only after
## all three rows remain aligned in the generated image.

const SOURCE := "res://assets/paper_doll/reference_parts/hair_male_default_on_foot_unisex.png"
const OUTPUT := "res://.godot-temp/hair_overlay_preview.png"
const FRAME_SIZE := Vector2i(64, 64)

func _init() -> void:
	var source: Image = Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	assert(source != null and not source.is_empty())
	var output: Image = Image.create(512, 192, false, Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)
	for row: int in range(3):
		for frame_x: int in range(8):
			var origin := Vector2i(frame_x * 64, row * 64)
			var frame: Image = source.get_region(Rect2i(origin, FRAME_SIZE))
			for y: int in range(64):
				for x: int in range(64):
					if _keep_pixel(row, x, y):
						continue
					frame.set_pixel(x, y, Color.TRANSPARENT)
			output.blend_rect(frame, Rect2i(Vector2i.ZERO, FRAME_SIZE), origin)
			# Keep the preview self-describing: every cell must contain the
			# resulting overlay, not an opaque copied face.
			assert(output.get_region(Rect2i(origin, FRAME_SIZE)).get_used_rect().size.y <= 24)
	assert(output.save_png(ProjectSettings.globalize_path(OUTPUT)) == OK)
	print("HAIR OVERLAY PREVIEW PASS output=%s" % OUTPUT)
	quit()

func _keep_pixel(row: int, x: int, y: int) -> bool:
	if row == PaperDollLayerVisual.Facing.UP:
		return y <= 22
	if y <= 12:
		return true
	if y > 23:
		return false
	if row == PaperDollLayerVisual.Facing.RIGHT:
		return x <= 34
	return x <= 23 or x >= 41
