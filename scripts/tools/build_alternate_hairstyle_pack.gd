extends SceneTree

## Extracts the real braided hairstyle from the checked-in alternate art board.
## The board's magenta is a key colour, not part of the hair.  Each extracted
## direction is packed into the normal 8-column x 3-row 64x64 sheet; Composer
## then fits that transparent silhouette into the accepted face anchor.

const SOURCE_PATH := "res://art_source/paper_doll/reference_generated/worldgoing_alternate_parts_v1.png"
const OUTPUT_DIR := "res://assets/paper_doll/reference_parts"
const OUTPUT_NAMES := [
	"alt_braided_hair_on_foot_unisex.png",
	"alt_braided_hair_mounted_unisex.png",
]
const FRAME_SIZE := Vector2i(64, 64)
const SHEET_SIZE := Vector2i(512, 192)
const FRAME_COLUMNS := 8
const SOURCE_ROWS := 3

## The first row of the art board contains front, back, and side braids.  The
## lower rows are armour/cape/weapon assets and are intentionally excluded.
const SOURCE_RECTS := [
	Rect2i(80, 0, 230, 280),
	Rect2i(350, 0, 240, 280),
	Rect2i(625, 0, 255, 280),
]

func _init() -> void:
	var source: Image = Image.load_from_file(ProjectSettings.globalize_path(SOURCE_PATH))
	if source == null or source.is_empty():
		push_error("Missing alternate hairstyle board: %s" % SOURCE_PATH)
		quit(1)
		return
	if source.get_format() != Image.FORMAT_RGBA8:
		source.convert(Image.FORMAT_RGBA8)
	var output_path: String = ProjectSettings.globalize_path(OUTPUT_DIR)
	if DirAccess.make_dir_recursive_absolute(output_path) != OK:
		push_error("Could not create alternate hairstyle directory")
		quit(1)
		return
	for output_name: String in OUTPUT_NAMES:
		var error: Error = _write_sheet(source, output_path.path_join(output_name))
		if error != OK:
			push_error("Could not write %s: %s" % [output_name, error_string(error)])
			quit(1)
			return
	print("ALTERNATE HAIRSTYLE PASS: true braided silhouettes exported")
	quit(0)

func _write_sheet(source: Image, output_path: String) -> Error:
	var sheet: Image = Image.create(
		SHEET_SIZE.x,
		SHEET_SIZE.y,
		false,
		Image.FORMAT_RGBA8
	)
	sheet.fill(Color.TRANSPARENT)
	for direction: int in range(SOURCE_ROWS):
		var crop: Image = source.get_region(SOURCE_RECTS[direction])
		_remove_magenta(crop)
		var used: Rect2i = crop.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			return ERR_FILE_CORRUPT
		crop = crop.get_region(used)
		# The board's side drawing faces left.  Runtime RIGHT is canonical and
		# LEFT is supplied by Sprite2D.flip_h in the unified frame controller.
		if direction == PaperDollLayerVisual.Facing.RIGHT:
			crop.flip_x()
		var scale: float = minf(
			60.0 / float(crop.get_width()),
			60.0 / float(crop.get_height())
		)
		crop.resize(
			maxi(1, int(round(crop.get_width() * scale))),
			maxi(1, int(round(crop.get_height() * scale))),
			Image.INTERPOLATE_NEAREST
		)
		var position := Vector2i(
			int((FRAME_SIZE.x - crop.get_width()) / 2),
			0
		)
		for frame_x: int in range(FRAME_COLUMNS):
			_blit_clipped(
				sheet,
				crop,
				Vector2i(frame_x * FRAME_SIZE.x, direction * FRAME_SIZE.y),
				position
			)
	return sheet.save_png(output_path)

func _remove_magenta(image: Image) -> void:
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var color: Color = image.get_pixel(x, y)
			# Include antialiased key-colour fringes while leaving brown/gold hair
			# highlights untouched.
			if color.r >= 0.65 and color.b >= 0.55 and color.g <= 0.35:
				image.set_pixel(x, y, Color.TRANSPARENT)

func _blit_clipped(
		sheet: Image,
		source: Image,
		frame_origin: Vector2i,
		position: Vector2i
	) -> void:
	var source_rect := Rect2i(Vector2i.ZERO, source.get_size())
	var destination := position
	if destination.x < 0:
		source_rect.position.x -= destination.x
		source_rect.size.x += destination.x
		destination.x = 0
	if destination.y < 0:
		source_rect.position.y -= destination.y
		source_rect.size.y += destination.y
		destination.y = 0
	if destination.x + source_rect.size.x > FRAME_SIZE.x:
		source_rect.size.x = FRAME_SIZE.x - destination.x
	if destination.y + source_rect.size.y > FRAME_SIZE.y:
		source_rect.size.y = FRAME_SIZE.y - destination.y
	if source_rect.size.x <= 0 or source_rect.size.y <= 0:
		return
	sheet.blit_rect(source, source_rect, frame_origin + destination)
