extends SceneTree

## Converts the generated female reference boards into the same deterministic
## 8-column x 3-row sheets used by the V2 reference gate.
##
## The source boards are intentionally ordinary art references (white
## background, three complete views).  This tool is the only place where they
## become runtime sheets: it removes only border-connected white pixels,
## detects the three silhouettes, mirrors the authored side view into the
## canonical RIGHT row, and places every view on the shared 64x64 contract.
## Mounted sheets remain 512x192 at rest; PaperDollV2Catalog pads each row to
## a 64x96 cell when it loads them.

const SOURCE_DIR := "res://assets/doll/reference"
const OUTPUT_DIR := "res://assets/paper_doll/reference_match"
const FRAME_SIZE := Vector2i(64, 64)
const SHEET_SIZE := Vector2i(512, 192)
const FRAME_COLUMNS := 8
const FOOT_ANCHOR_Y := 56
const FIT_HEIGHT := 56
const MAX_WIDTH := 60
# Source-space eye components measured on the accepted female mounted front
# drawing.  They are sampled and enlarged only for the mounted body sheet so
# the authored shape remains intact while surviving the 64px runtime cell.
const MOUNT_FRONT_EYE_RECTS := [
	Rect2i(310, 162, 20, 26),
	Rect2i(363, 162, 21, 26),
]
# The authored female side view faces left in the source board.  Composer
# mirrors this row into RIGHT/LEFT, so one source-space eye sample is enough.
const MOUNT_SIDE_EYE_RECTS := [
	Rect2i(1373, 157, 15, 27),
]
func _init() -> void:
	var error := _build()
	if error != OK:
		push_error("Female calibrated sheet build failed: %s" % error_string(error))
		quit(1)
		return
	print("FEMALE_REFERENCE_SHEETS_PASS sheets=4")
	quit(0)

func _build() -> Error:
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	var error := DirAccess.make_dir_recursive_absolute(output_path)
	if error != OK:
		return error
	var jobs: Array[Dictionary] = [
		{"source": "female_unarmed_on_foot_source.png", "output": "reference_match_female_body_on_foot.png"},
		{"source": "female_armed_on_foot_source.png", "output": "reference_match_female_armed_on_foot.png"},
		{"source": "female_unarmed_mounted_source.png", "output": "reference_match_female_body_mounted.png"},
		{"source": "female_armed_mounted_source.png", "output": "reference_match_female_armed_mounted.png"},
	]
	for job: Dictionary in jobs:
		print("female sheet job start: %s" % job["source"])
		var source := _load_source(String(job["source"]))
		if source == null:
			return ERR_FILE_NOT_FOUND
		print("female source loaded: %sx%s" % [source.get_width(), source.get_height()])
		var mounted_eye_rects: Array = MOUNT_FRONT_EYE_RECTS \
			if String(job["output"]) == "reference_match_female_body_mounted.png" else []
		var mounted_side_eye_rects: Array = MOUNT_SIDE_EYE_RECTS \
			if String(job["output"]) == "reference_match_female_body_mounted.png" else []
		error = _write_sheet(
			source,
			String(job["output"]),
			output_path,
			mounted_eye_rects,
			mounted_side_eye_rects
		)
		if error != OK:
			return error
	# Keep the eyes exactly as authored in the accepted female references.
	# Replacement eye strokes change the source style and are not allowed.
	return OK

func _load_source(file_name: String) -> Image:
	var path := ProjectSettings.globalize_path(SOURCE_DIR.path_join(file_name))
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		push_error("Missing female reference source: %s" % path)
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	_remove_white_background(image)
	return image

func _write_sheet(
		source: Image,
		file_name: String,
		output_path: String,
		mounted_eye_rects: Array = [],
		mounted_side_eye_rects: Array = []
) -> Error:
	var used := source.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		push_error("Female reference has no foreground: %s" % file_name)
		return ERR_FILE_CORRUPT
	var spans := _find_view_spans(source, used)
	if spans.size() != 3:
		push_error("Female reference requires exactly three views: %s spans=%d" % [file_name, spans.size()])
		return ERR_FILE_CORRUPT

	var sheet := Image.create(SHEET_SIZE.x, SHEET_SIZE.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.TRANSPARENT)
	for direction: int in range(3):
		var span: Vector2i = spans[direction]
		var rect := Rect2i(
			Vector2i(span.x, used.position.y),
			Vector2i(span.y - span.x + 1, used.size.y)
		)
		var crop := source.get_region(rect)
		var crop_used := crop.get_used_rect()
		if crop_used.size.x <= 0 or crop_used.size.y <= 0:
			push_error("Female view is empty: %s row=%d" % [file_name, direction])
			return ERR_FILE_CORRUPT
		crop = crop.get_region(crop_used)
		var source_crop: Image = crop.duplicate()
		var scale := minf(
			float(FIT_HEIGHT) / float(crop.get_height()),
			float(MAX_WIDTH) / float(crop.get_width())
		)
		var fitted_size := Vector2i(
			maxi(1, int(round(crop.get_width() * scale))),
			maxi(1, int(round(crop.get_height() * scale)))
		)
		crop.resize(fitted_size.x, fitted_size.y, Image.INTERPOLATE_NEAREST)
		# The source side drawing faces LEFT.  Sample its eye before the
		# canonical RIGHT-row flip so Composer's normal flip_h mirrors the same
		# calibrated pixel into LEFT.
		if direction == PaperDollV2Contract.Facing.RIGHT and not mounted_side_eye_rects.is_empty():
			_apply_mounted_reference_eyes(
				crop,
				source_crop,
				mounted_side_eye_rects,
				rect.position,
				crop_used,
				scale
			)
		# The generated boards intentionally show the side character facing
		# left.  V2 stores RIGHT as the authored row and mirrors LEFT at render.
		if direction == PaperDollV2Contract.Facing.RIGHT:
			crop.flip_x()
		if direction == PaperDollV2Contract.Facing.DOWN and not mounted_eye_rects.is_empty():
			_apply_mounted_reference_eyes(
				crop,
				source_crop,
				mounted_eye_rects,
				rect.position,
				crop_used,
				scale
			)
		var position := Vector2i(
			int((FRAME_SIZE.x - crop.get_width()) / 2),
			FOOT_ANCHOR_Y - crop.get_height()
		)
		for frame_x: int in range(FRAME_COLUMNS):
			_blit_clipped(sheet, crop, Vector2i(frame_x * FRAME_SIZE.x, direction * FRAME_SIZE.y), position)
	# Do not run a connected-component cleanup here.  Mounted eyes and hair
	# tips can be intentional 1-8 px components after nearest-neighbour fit;
	# removing them makes the accepted reference lose authored features.  The
	# source border flood-fill above is the only background-removal authority.
	var path := output_path.path_join(file_name)
	return sheet.save_png(path)

func _apply_mounted_reference_eyes(
		fitted: Image,
		source_crop: Image,
		eye_rects: Array,
		view_origin: Vector2i,
		used: Rect2i,
		scale: float
) -> void:
	# Preserve the actual source eye pixels.  The target height is derived from
	# the measured source component (female reference: 20x26/21x26 -> 3x4), so
	# this is a source calibration step, not a new hand-drawn eye style.
	for full_rect_value: Variant in eye_rects:
		var full_rect: Rect2i = full_rect_value
		var local_rect := Rect2i(
			full_rect.position - view_origin - used.position,
			full_rect.size
		)
		if local_rect.position.x < 0 or local_rect.position.y < 0 \
				or local_rect.end.x > source_crop.get_width() \
				or local_rect.end.y > source_crop.get_height():
			push_warning("Mounted female eye sample outside source crop: %s" % local_rect)
			continue
		var target_height := 4
		# The source bbox includes the broad anti-aliased eye core.  At the
		# mounted 64px face scale, two solid pixels preserves the reference's
		# visual weight without merging into the hair contour.
		var target_width := 2
		var patch: Image = source_crop.get_region(local_rect)
		patch.resize(target_width, target_height, Image.INTERPOLATE_NEAREST)
		var source_center := Vector2(local_rect.position) + Vector2(local_rect.size) * 0.5
		var target_center := source_center * scale
		var target_position := Vector2i(
			int(round(target_center.x - float(target_width) * 0.5)),
			int(round(target_center.y - float(target_height) * 0.5))
		)
		_blit_clipped(fitted, patch, Vector2i.ZERO, target_position)

func _find_view_spans(image: Image, used: Rect2i) -> Array[Vector2i]:
	# A connected silhouette can still contain small horizontal gaps (a sword
	# or shield beside an arm).  First collect foreground runs, then merge the
	# nearest runs until the board has exactly three view spans.  The large
	# whitespace between the three authored figures is always the last gaps.
	var runs: Array[Vector2i] = []
	var in_run := false
	var run_start := 0
	for x: int in range(used.position.x, used.end.x):
		var has_pixel := false
		for y: int in range(used.position.y, used.end.y):
			if image.get_pixel(x, y).a > 0.05:
				has_pixel = true
				break
		if has_pixel and not in_run:
			in_run = true
			run_start = x
		elif not has_pixel and in_run:
			runs.append(Vector2i(run_start, x - 1))
			in_run = false
	if in_run:
		runs.append(Vector2i(run_start, used.end.x - 1))
	if runs.size() < 3:
		return _fallback_equal_spans(used)
	while runs.size() > 3:
		var nearest_index := 0
		var nearest_gap := 2147483647
		for index: int in range(runs.size() - 1):
			var gap := runs[index + 1].x - runs[index].y - 1
			if gap < nearest_gap:
				nearest_gap = gap
				nearest_index = index
		runs[nearest_index] = Vector2i(runs[nearest_index].x, runs[nearest_index + 1].y)
		runs.remove_at(nearest_index + 1)
	return runs

func _fallback_equal_spans(used: Rect2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for index: int in range(3):
		var left := used.position.x + int(floor(float(used.size.x * index) / 3.0))
		var right := used.position.x + int(floor(float(used.size.x * (index + 1)) / 3.0)) - 1
		result.append(Vector2i(left, right))
	return result

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
	# Flood-fill only from the border.  Include the neutral anti-aliased pixels
	# of the white source matte, but keep enclosed white hair and silver armor.
	var width := image.get_width()
	var height := image.get_height()
	var visited := PackedByteArray()
	visited.resize(width * height)
	# Keep the flood-fill queue as packed integer pixel indices.  A Variant
	# Array[Vector2i] multiplies memory for a 1700x900 generated board and can
	# make the headless Mono process unstable on the project checkout.
	var queue := PackedInt32Array()
	for x: int in range(width):
		_enqueue_background(image, visited, queue, x, 0)
		_enqueue_background(image, visited, queue, x, height - 1)
	for y: int in range(height):
		_enqueue_background(image, visited, queue, 0, y)
		_enqueue_background(image, visited, queue, width - 1, y)
	var index := 0
	while index < queue.size():
		var pixel_index: int = queue[index]
		index += 1
		var position := Vector2i(pixel_index % width, pixel_index / width)
		image.set_pixelv(position, Color.TRANSPARENT)
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := position + step
			if next.x < 0 or next.x >= width or next.y < 0 or next.y >= height:
				continue
			_enqueue_background(image, visited, queue, next.x, next.y)

func _enqueue_background(image: Image, visited: PackedByteArray, queue: PackedInt32Array, x: int, y: int) -> void:
	var index := y * image.get_width() + x
	if visited[index] != 0 or not _is_background(image.get_pixel(x, y)):
		return
	visited[index] = 1
	queue.append(index)

func _is_background(color: Color) -> bool:
	# Use the authored dark outline as the silhouette barrier.  Expanding the
	# neutral matte tolerance removes the gray/white fringe outside that outline
	# while keeping enclosed white hair and silver armor unreachable from the
	# border flood-fill.
	var minimum := minf(color.r, minf(color.g, color.b))
	var maximum := maxf(color.r, maxf(color.g, color.b))
	return minimum >= 0.72 and maximum - minimum <= 0.22 and color.a > 0.05
