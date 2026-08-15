extends SceneTree

## Exports five deterministic samples from the already accepted white-hair /
## silver-armor reference contact sheet.  This is a truth-board exporter for
## manual comparison; it deliberately does not run the unfinished split-layer
## compositor or procedural action fallback.

const SOURCE := "res://.visual_captures/paper_doll/reference_runtime_contact_sheet.png"
const OUTPUT_DIR := "res://.visual_captures/paper_doll/manual_accepted_reference"
const SOURCE_CELL := Vector2i(384, 384)
const SOURCE_GRID := Vector2i(4, 2)
const OUTPUT_SIZE := Vector2i(768, 768)
const SAMPLE_COUNT := 5
const RANDOM_SEED := 2026081303

var rng := RandomNumberGenerator.new()

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	rng.seed = RANDOM_SEED
	var source := Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	assert(source != null and source.get_size() == SOURCE_CELL * SOURCE_GRID,
		"Accepted reference contact sheet is missing or has an unexpected size")
	var output_dir := ProjectSettings.globalize_path(OUTPUT_DIR)
	assert(DirAccess.make_dir_recursive_absolute(output_dir) == OK)
	var remaining: Array[int] = []
	for cell_index: int in range(SOURCE_GRID.x * SOURCE_GRID.y):
		remaining.append(cell_index)
	var manifest := PackedStringArray([
		"seed=%d" % RANDOM_SEED,
		"source=%s" % SOURCE,
		"preset=accepted white hair / silver armor / navy cape / brown horse",
		"mode=reference truth board; no split-layer or procedural fallback involved",
		"",
	])
	for sample_index: int in range(SAMPLE_COUNT):
		var remaining_index: int = rng.randi_range(0, remaining.size() - 1)
		var cell_index: int = remaining[remaining_index]
		remaining.remove_at(remaining_index)
		var cell_origin := Vector2i(
			(cell_index % SOURCE_GRID.x) * SOURCE_CELL.x,
			(cell_index / SOURCE_GRID.x) * SOURCE_CELL.y
		)
		var frame := source.get_region(Rect2i(cell_origin, SOURCE_CELL))
		frame.resize(OUTPUT_SIZE.x, OUTPUT_SIZE.y, Image.INTERPOLATE_NEAREST)
		_draw_guides(frame)
		var file_name := "accepted_reference_%02d.png" % (sample_index + 1)
		assert(frame.save_png(output_dir.path_join(file_name)) == OK)
		manifest.append("%02d %s | %s" % [sample_index + 1, file_name, _cell_label(cell_index)])

	var manifest_file := FileAccess.open(output_dir.path_join("manifest.txt"), FileAccess.WRITE)
	assert(manifest_file != null)
	manifest_file.store_string("\n".join(manifest) + "\n")
	manifest_file.close()
	print("ACCEPTED REFERENCE PREVIEWS PASS: %d images" % SAMPLE_COUNT)
	print("OUTPUT_DIR=%s" % OUTPUT_DIR)
	quit()

func _cell_label(cell_index: int) -> String:
	var mounted := cell_index / SOURCE_GRID.x == 1
	var column: int = cell_index % SOURCE_GRID.x
	var facing: String = ["DOWN", "UP", "RIGHT", "LEFT"][column]
	return "%s %s" % ["MOUNTED" if mounted else "ON_FOOT", facing]

func _draw_guides(image: Image) -> void:
	# The cross is intentionally subtle and outside the character silhouette;
	# it marks the 64x64 contract's (32,56) anchor at the 6x source scale.
	var anchor := Vector2i(32 * 12, 56 * 12)
	var cyan := Color(0.0, 1.0, 1.0, 0.75)
	for offset: Vector2i in [
		Vector2i(-12, 0), Vector2i(-6, 0), Vector2i.ZERO,
		Vector2i(6, 0), Vector2i(12, 0), Vector2i(0, -12),
		Vector2i(0, -6), Vector2i(0, 6), Vector2i(0, 12),
	]:
		image.set_pixelv(anchor + offset, cyan)
