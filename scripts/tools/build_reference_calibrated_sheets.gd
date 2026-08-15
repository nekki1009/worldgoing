extends SceneTree

## Builds the runtime paper-doll sheets from the accepted art references.
##
## The old reference pack was made from isolated prop rows.  Those rows are
## useful as an art inventory, but they do not contain the relationship between
## a hand, a helmet, a horse and the rider.  This pack keeps the complete
## reference character intact and only normalises it to the 64x64 runtime
## contract.  It is therefore the source of truth for the calibrated presets;
## the Composer still consumes ordinary Texture2D Sprite2D sheets.

const SOURCE_DIR := "res://assets/doll/reference"
const OUTPUT_DIR := "res://assets/paper_doll/reference_match"
const FRAME_SIZE := Vector2i(64, 64)
const SHEET_SIZE := Vector2i(512, 192)
const FRAME_COLUMNS := 8
const FOOT_ANCHOR_Y := 56
const FIT_HEIGHT := 56
const MOUNT_BODY_PART := "res://assets/paper_doll/parts/artgate1_horse_body_mounted_unisex.png"

# Rectangles are the connected character silhouettes measured from the
# checked-in reference boards.  They are ordered DOWN, UP, SIDE (the source
# side drawings face left and are mirrored once below to become canonical
# RIGHT rows; Composer.flip_h supplies LEFT).
const FOOT_REFERENCE_RECTS := [
	Rect2i(312, 40, 410, 604),
	Rect2i(907, 47, 328, 597),
	Rect2i(1468, 49, 282, 595),
]
const FOOT_ARMED_RECTS := [
	Rect2i(152, 184, 409, 540),
	Rect2i(669, 180, 436, 544),
	Rect2i(1219, 199, 332, 524),
]
const MOUNT_REFERENCE_RECTS := [
	Rect2i(198, 39, 304, 742),
	Rect2i(669, 36, 301, 745),
	Rect2i(1095, 39, 586, 742),
]
const MOUNT_ARMED_RECTS := [
	Rect2i(177, 108, 328, 634),
	Rect2i(684, 102, 349, 640),
	Rect2i(1122, 117, 511, 622),
]
const MOUNT_LANCE_RECTS := [
	Rect2i(360, 30, 286, 586),
	Rect2i(906, 21, 286, 595),
	Rect2i(1425, 57, 499, 559),
]

func _init() -> void:
	var error: Error = _build()
	if error != OK:
		push_error("Calibrated paper-doll sheet build failed: %s" % error_string(error))
		quit(1)
		return
	print("Calibrated paper-doll reference sheets exported")
	quit()

func _build() -> Error:
	var output_path: String = ProjectSettings.globalize_path(OUTPUT_DIR)
	var error: Error = DirAccess.make_dir_recursive_absolute(output_path)
	if error != OK:
		return error
	var jobs := [
		["不戴帽步行.png", FOOT_REFERENCE_RECTS, "reference_match_body_on_foot_unisex.png"],
		["重甲與劍盾.png", FOOT_ARMED_RECTS, "reference_match_armed_on_foot_unisex.png"],
		["不帶帽騎馬.png", MOUNT_REFERENCE_RECTS, "reference_match_body_mounted_unisex.png"],
		["持劍盾騎馬.png", MOUNT_ARMED_RECTS, "reference_match_armed_mounted_unisex.png"],
		["騎馬長槍盾.png", MOUNT_LANCE_RECTS, "reference_match_lance_mounted_unisex.png"],
	]
	for job: Array in jobs:
		var source: Image = _load_source(str(job[0]))
		if source == null:
			return ERR_FILE_NOT_FOUND
		error = _write_sheet(source, job[1] as Array, str(job[2]), output_path)
		if error != OK:
			return error
	# The accepted mounted board is a flattened rider+horse silhouette.  Its
	# rider's silver boot/highlight can land on the horse's lower-leg pixels when
	# the high-resolution board is reduced to 64x64.  Restore only those exact
	# warm horse pixels from the authoritative split horse-body sheet; pixels
	# outside the horse mask (for example the rider's boot beside the saddle)
	# remain untouched.
	error = _restore_mounted_leg_highlights(output_path)
	if error != OK:
		return error
	return OK

func _restore_mounted_leg_highlights(output_path: String) -> Error:
	var composite_path := output_path.path_join("reference_match_body_mounted_unisex.png")
	var composite: Image = Image.load_from_file(composite_path)
	var horse: Image = Image.load_from_file(ProjectSettings.globalize_path(MOUNT_BODY_PART))
	if composite == null or composite.is_empty() or horse == null or horse.is_empty():
		push_error("Mounted leg cleanup could not load composite or horse body")
		return ERR_FILE_NOT_FOUND
	var restored: int = 0
	for row: int in range(3):
		# The accepted composite board repeats one calibrated view across its
		# eight animation columns.  Use the same frame-0 horse mask for every
		# column; using the independently animated horse sheet per column would
		# move the mask under the static rider boot and erase valid boot pixels.
		var horse_row_origin := Vector2i(0, row * FRAME_SIZE.y)
		for frame_x: int in range(FRAME_COLUMNS):
			var origin := Vector2i(frame_x * FRAME_SIZE.x, row * FRAME_SIZE.y)
			# y=44..55 is the lower leg/hoof band in the calibrated mounted
			# reference.  Do not touch the rider's torso or silver boot above it.
			for y: int in range(44, 56):
				for x: int in range(FRAME_SIZE.x):
					var position := origin + Vector2i(x, y)
					var source := composite.get_pixelv(position)
					var horse_pixel := horse.get_pixelv(horse_row_origin + Vector2i(x, y))
					if not _is_white_foreground(source) or not _is_warm_horse_pixel(horse_pixel):
						continue
					composite.set_pixelv(position, horse_pixel)
					restored += 1
	if composite.save_png(composite_path) != OK:
		return ERR_CANT_CREATE
	print("MOUNTED LEG HIGHLIGHT CLEANUP: restored %d horse pixels" % restored)
	return OK

func _is_white_foreground(color: Color) -> bool:
	if color.a <= 0.05:
		return false
	var minimum := minf(color.r, minf(color.g, color.b))
	var maximum := maxf(color.r, maxf(color.g, color.b))
	return minimum >= 0.72 and maximum - minimum <= 0.16

func _is_warm_horse_pixel(color: Color) -> bool:
	return color.a > 0.05 \
		and color.h >= 0.015 and color.h <= 0.16 \
		and color.s >= 0.20 and color.v >= 0.10

func _load_source(file_name: String) -> Image:
	var path: String = ProjectSettings.globalize_path(SOURCE_DIR.path_join(file_name))
	var image: Image = Image.load_from_file(path)
	if image == null or image.is_empty():
		push_error("Missing calibrated reference: %s" % path)
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _write_sheet(source: Image, rectangles: Array, file_name: String, output_path: String) -> Error:
	var sheet: Image = Image.create(
		SHEET_SIZE.x,
		SHEET_SIZE.y,
		false,
		Image.FORMAT_RGBA8
	)
	sheet.fill(Color.TRANSPARENT)
	var fitted_views: Array[Image] = []
	for direction: int in range(3):
		var rectangle: Rect2i = rectangles[direction]
		var crop: Image = source.get_region(rectangle)
		_remove_white_background(crop)
		var used: Rect2i = crop.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			push_error("Reference crop is empty: %s row %d" % [file_name, direction])
			return ERR_FILE_CORRUPT
		crop = crop.get_region(used)
		var scale: float = minf(
			float(FIT_HEIGHT) / float(crop.get_height()),
			60.0 / float(crop.get_width())
		)
		var fitted_size := Vector2i(
			maxi(1, int(round(crop.get_width() * scale))),
			maxi(1, int(round(crop.get_height() * scale)))
		)
		crop.resize(fitted_size.x, fitted_size.y, Image.INTERPOLATE_NEAREST)
		if direction == PaperDollLayerVisual.Facing.RIGHT:
			crop.flip_x()
		fitted_views.append(crop)
	# The front drawing is the facing footprint authority.  If the back drawing
	# is broader, reduce only UP so it cannot become wider than DOWN (the exact
	# visual regression reported by the user).  A naturally narrower back and
	# SIDE keep their authored proportions.
	var down_width: int = fitted_views[PaperDollLayerVisual.Facing.DOWN].get_width()
	var up_view: Image = fitted_views[PaperDollLayerVisual.Facing.UP]
	if up_view.get_width() > down_width:
		var resized_height: int = maxi(1, int(round(
			float(up_view.get_height()) * float(down_width) / float(up_view.get_width())
		)))
		up_view.resize(down_width, resized_height, Image.INTERPOLATE_NEAREST)
		fitted_views[PaperDollLayerVisual.Facing.UP] = up_view
	for direction: int in range(3):
		var crop: Image = fitted_views[direction]
		var position := Vector2i(
			int((FRAME_SIZE.x - crop.get_width()) / 2),
			FOOT_ANCHOR_Y - crop.get_height()
		)
		for frame_x: int in range(FRAME_COLUMNS):
			var frame_origin := Vector2i(frame_x * FRAME_SIZE.x, direction * FRAME_SIZE.y)
			_blit_clipped(sheet, crop, frame_origin, position)
	var path: String = output_path.path_join(file_name)
	return sheet.save_png(path)

func _blit_clipped(sheet: Image, source: Image, frame_origin: Vector2i, position: Vector2i) -> void:
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

func _remove_white_background(image: Image) -> void:
	# Flood-fill only from the crop border.  White hair/armor highlights inside
	# a black outline remain opaque; a global white-key would destroy them.
	var width: int = image.get_width()
	var height: int = image.get_height()
	var visited := PackedByteArray()
	visited.resize(width * height)
	var queue: Array[Vector2i] = []
	for x: int in range(width):
		_enqueue_background(image, visited, queue, Vector2i(x, 0))
		_enqueue_background(image, visited, queue, Vector2i(x, height - 1))
	for y: int in range(height):
		_enqueue_background(image, visited, queue, Vector2i(0, y))
		_enqueue_background(image, visited, queue, Vector2i(width - 1, y))
	var index: int = 0
	while index < queue.size():
		var position: Vector2i = queue[index]
		index += 1
		image.set_pixelv(position, Color.TRANSPARENT)
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := position + step
			if next.x < 0 or next.x >= width or next.y < 0 or next.y >= height:
				continue
			_enqueue_background(image, visited, queue, next)

func _enqueue_background(
		image: Image,
		visited: PackedByteArray,
		queue: Array[Vector2i],
		position: Vector2i
) -> void:
	var index: int = position.y * image.get_width() + position.x
	if visited[index] != 0 or not _is_background(image.get_pixelv(position)):
		return
	visited[index] = 1
	queue.append(position)

func _is_background(color: Color) -> bool:
	var minimum: float = minf(color.r, minf(color.g, color.b))
	var maximum: float = maxf(color.r, maxf(color.g, color.b))
	return minimum >= 0.91 and maximum - minimum <= 0.08 and color.a > 0.05
