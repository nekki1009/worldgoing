extends SceneTree

## Converts the approved hair-only design board into four layer-owned sheets.
## The source has four hairstyle columns and three direction rows; each output
## remains a normal 512x192 (8 columns x 3 rows) Sprite2D sheet.  The runtime
## can therefore keep one unified frame controller while the material lab
## selects a genuinely different silhouette.

const SOURCE_PATH := "res://art_source/paper_doll/reference_generated/hairstyle_hair_only_board_v1.png"
const OUTPUT_DIR := "res://assets/paper_doll/reference_parts"
const SOURCE_SIZE := Vector2i(1448, 1086)
const SOURCE_CELL := Vector2i(362, 362)
const FRAME_SIZE := Vector2i(64, 64)
const SHEET_SIZE := Vector2i(512, 192)
const FRAME_COLUMNS := 8
const SOURCE_ROWS := 3
const FIT_HEIGHT := 52

const STYLES := [
	{"id": "hair_short_spiky", "column": 0},
	{"id": "hair_high_ponytail", "column": 1},
	{"id": "hair_bob", "column": 2},
	{"id": "hair_twin_braids", "column": 3},
]

func _init() -> void:
	var source: Image = Image.load_from_file(ProjectSettings.globalize_path(SOURCE_PATH))
	if source == null or source.is_empty() or source.get_size() != SOURCE_SIZE:
		push_error("Hairstyle source board is missing or has unexpected size")
		quit(1)
		return
	if source.get_format() != Image.FORMAT_RGBA8:
		source.convert(Image.FORMAT_RGBA8)
	var output_path: String = ProjectSettings.globalize_path(OUTPUT_DIR)
	if DirAccess.make_dir_recursive_absolute(output_path) != OK:
		push_error("Could not create hairstyle output directory")
		quit(1)
		return
	for style: Dictionary in STYLES:
		var sheet: Image = _build_style_sheet(source, int(style["column"]))
		if sheet == null or sheet.is_empty():
			push_error("Could not build hairstyle %s" % style["id"])
			quit(1)
			return
		var file_name := "%s_on_foot_unisex.png" % style["id"]
		if sheet.save_png(output_path.path_join(file_name)) != OK:
			push_error("Could not write hairstyle %s" % style["id"])
			quit(1)
			return
	print("FOUR HAIRSTYLE PACK PASS: %d distinct silhouettes exported" % STYLES.size())
	quit(0)

func _build_style_sheet(source: Image, column: int) -> Image:
	var sheet: Image = Image.create(
		SHEET_SIZE.x,
		SHEET_SIZE.y,
		false,
		Image.FORMAT_RGBA8
	)
	sheet.fill(Color.TRANSPARENT)
	for row: int in range(SOURCE_ROWS):
		var crop: Image = source.get_region(Rect2i(
			column * SOURCE_CELL.x,
			row * SOURCE_CELL.y,
			SOURCE_CELL.x,
			SOURCE_CELL.y
		))
		_remove_magenta(crop)
		var used: Rect2i = crop.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			return null
		crop = crop.get_region(used)
		var scale: float = minf(
			float(FIT_HEIGHT) / float(crop.get_height()),
			58.0 / float(crop.get_width())
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
				Vector2i(frame_x * FRAME_SIZE.x, row * FRAME_SIZE.y),
				position
			)
	return sheet

func _remove_magenta(image: Image) -> void:
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var color: Color = image.get_pixel(x, y)
			# Remove the flat key and its antialiased pink fringe.  The generated
			# hair is white/grey, so a saturated magenta hue cannot be authored hair.
			var magenta_value: bool = color.r > color.g * 1.35 \
				and color.b > color.g * 1.35 \
				and minf(color.r, color.b) > 0.25
			if color.s > 0.16 and magenta_value:
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
