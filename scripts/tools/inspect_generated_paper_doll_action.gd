extends SceneTree

## Offline gate for ImageGen action candidates.  It never changes the formal
## split catalog: a candidate must first be a real 512x192 RGBA sheet with
## eight 64x64 cells per row and transparent empty pixels.

const CANDIDATE := "res://assets/paper_doll/action_candidates/worldgoing_attack_candidate.png"
const DERIVED := "res://assets/paper_doll/action_candidates/worldgoing_attack_candidate_rgba.png"
const RUNTIME_CANDIDATE := "res://assets/paper_doll/action_candidates/worldgoing_attack_candidate_512x192.png"
const FRAME_SIZE := Vector2i(64, 64)
const SHEET_SIZE := Vector2i(512, 192)

func _init() -> void:
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(CANDIDATE))
	assert(image != null and not image.is_empty(), "generated action candidate is unreadable")
	print("ACTION CANDIDATE SOURCE size=%dx%d format=%s" % [
		image.get_width(), image.get_height(), image.get_format()
	])
	assert(image.get_width() == 2048 and image.get_height() == 768,
		"candidate source must remain the authored 4x inspection board")
	var rgba: Image = Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			rgba.set_pixel(x, y, image.get_pixel(x, y))
	var source_cell_size := Vector2i(256, 256)
	var non_empty_cells: int = 0
	for row: int in range(3):
		for frame_x: int in range(8):
			var cell_rect := Rect2i(
				Vector2i(frame_x * source_cell_size.x, row * source_cell_size.y),
				source_cell_size
			)
			_remove_connected_background(rgba, cell_rect)
			var cell: Image = rgba.get_region(cell_rect)
			assert(cell.get_used_rect().size != Vector2i.ZERO,
				"candidate cell is empty row=%d frame=%d" % [row, frame_x])
			non_empty_cells += 1
	var transparent_pixels: int = 0
	for y: int in range(rgba.get_height()):
		for x: int in range(rgba.get_width()):
			if rgba.get_pixel(x, y).a < 0.5:
				transparent_pixels += 1
	assert(transparent_pixels > 0, "candidate background was not removed")
	assert(rgba.save_png(ProjectSettings.globalize_path(DERIVED)) == OK)
	assert(Vector2i(rgba.get_width(), rgba.get_height()) == Vector2i(2048, 768))
	var runtime: Image = rgba.duplicate()
	runtime.resize(SHEET_SIZE.x, SHEET_SIZE.y, Image.INTERPOLATE_NEAREST)
	assert(runtime.save_png(ProjectSettings.globalize_path(RUNTIME_CANDIDATE)) == OK)
	assert(Vector2i(runtime.get_width(), runtime.get_height()) == SHEET_SIZE)
	print("ACTION CANDIDATE GATE PASS cells=%d target=%dx%d transparent=%d outputs=%s,%s" % [
		non_empty_cells, SHEET_SIZE.x, SHEET_SIZE.y, transparent_pixels, DERIVED, RUNTIME_CANDIDATE
	])
	quit()

func _remove_connected_background(image: Image, rect: Rect2i) -> void:
	var queue: Array[Vector2i] = []
	var seen: Dictionary = {}
	for x: int in range(rect.position.x, rect.end.x):
		queue.append(Vector2i(x, rect.position.y))
		queue.append(Vector2i(x, rect.end.y - 1))
	for y: int in range(rect.position.y, rect.end.y):
		queue.append(Vector2i(rect.position.x, y))
		queue.append(Vector2i(rect.end.x - 1, y))
	while not queue.is_empty():
		var position: Vector2i = queue.pop_back()
		if seen.has(position) or not rect.has_point(position):
			continue
		seen[position] = true
		if not _is_background(image.get_pixelv(position)):
			continue
		image.set_pixelv(position, Color.TRANSPARENT)
		queue.append(position + Vector2i.LEFT)
		queue.append(position + Vector2i.RIGHT)
		queue.append(position + Vector2i.UP)
		queue.append(position + Vector2i.DOWN)

func _is_background(color: Color) -> bool:
	return color.a > 0.5 and color.r > 0.88 and color.g > 0.88 and color.b > 0.88 \
		and maxf(color.r, maxf(color.g, color.b)) - minf(color.r, minf(color.g, color.b)) < 0.10
