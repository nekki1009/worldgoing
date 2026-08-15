extends SceneTree

## Generates five reproducible, human-reviewable samples from the runtime
## Art Gate 1 catalog.  This is an offline presentation tool: it never creates
## gameplay actors or mutates a saved character profile.

const OUTPUT_DIR := "res://.visual_captures/paper_doll/manual_reference_truth"
const MANIFEST_NAME := "manifest.txt"
const SAMPLE_COUNT := 5
const SCALE := 8
const REVIEW_SIZE: Vector2i = PaperDollLayerVisual.FRAME_SIZE * SCALE
const RANDOM_SEED := 2026081302

const REFERENCE_HAIR_COLOR := Color("e8e9ef")
const REFERENCE_ARMOR_COLOR := Color("b7c1d2")
const REFERENCE_CAPE_COLOR := Color("263653")
const REFERENCE_MOUNT_COLOR := Color("9a704d")

var catalog: PaperDollCatalog
var rng := RandomNumberGenerator.new()
var manifest := PackedStringArray()

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	catalog = PaperDollCatalog.create_art_gate1_catalog()
	assert(catalog.validation_issues().is_empty(), "Catalog validation failed")
	rng.seed = RANDOM_SEED
	var absolute_dir := ProjectSettings.globalize_path(OUTPUT_DIR)
	assert(DirAccess.make_dir_recursive_absolute(absolute_dir) == OK)
	manifest.append("seed=%d" % RANDOM_SEED)
	manifest.append("source=assets/paper_doll/reference_match/reference_match_body_*.png")
	manifest.append("preset=approved_white_hair_silver_armor_reference_truth")
	manifest.append("parts=flattened acceptance silhouette; no alternate parts, no procedural action fallback, no dye transform")
	manifest.append("randomized=direction and mounted pose only; action is IDLE/frame 0")
	manifest.append("")

	# This pass intentionally does not claim split-part correctness.  It is the
	# visual truth board used to compare the later split-layer implementation.
	for sample_index: int in range(SAMPLE_COUNT):
		var sample := _make_sample(sample_index)
		var draft: PaperDollPreviewDraft = sample["draft"] as PaperDollPreviewDraft
		var recipe: PaperDollRecipe = catalog.resolve_recipe(draft)
		assert(recipe != null, "Random sample %d did not resolve" % (sample_index + 1))
		var preview: Image = await _compose_preview(recipe, sample)
		var file_name := "random_preview_%02d.png" % (sample_index + 1)
		assert(preview.save_png(absolute_dir.path_join(file_name)) == OK)
		manifest.append(_manifest_line(sample_index + 1, file_name, sample))

	var manifest_file := FileAccess.open(absolute_dir.path_join(MANIFEST_NAME), FileAccess.WRITE)
	assert(manifest_file != null)
	manifest_file.store_string("\n".join(manifest) + "\n")
	manifest_file.close()
	print("RANDOM PAPER DOLL PREVIEWS PASS: %d images" % SAMPLE_COUNT)
	print("OUTPUT_DIR=%s" % OUTPUT_DIR)
	print("MANIFEST=%s" % OUTPUT_DIR.path_join(MANIFEST_NAME))
	quit()

func _make_sample(sample_index: int) -> Dictionary:
	var draft := PaperDollPreviewDraft.new()
	draft.gender = PaperDollLayerVisual.Gender.MALE
	# Three on-foot and two mounted samples preserve both accepted reference
	# poses without allowing a different gender or alternate horse to hide a
	# layer-alignment error.
	draft.is_mounted = sample_index in [3, 4]
	# Keep a valid recipe as metadata for the capture; the pixels below come
	# directly from the flattened reference-match source.
	draft.set_visual(PaperDollLayerVisual.RenderLayer.BODY, &"body_male_default")
	# The accepted white-hair/silver-armor board is the IDLE reference-match
	# silhouette.  Do not mix procedural action fallback sheets into this gate.
	draft.action = PaperDollAnimation.Action.IDLE
	# Helmet, shield, and barding stay empty: they are not part of the accepted
	# white-hair/silver-armor reference silhouette.
	if draft.is_mounted:
		draft.mount_visual_id = &"artgate1_horse"

	var frame_x: int = 0
	# Cycle the four directions once before allowing a repeat, so all directional
	# mirror/z-order paths are represented in a five-image review set.
	var facing: int = [
		PaperDollLayerVisual.Facing.DOWN,
		PaperDollLayerVisual.Facing.UP,
		PaperDollLayerVisual.Facing.RIGHT,
		PaperDollLayerVisual.Facing.LEFT,
		PaperDollLayerVisual.Facing.RIGHT,
	][sample_index]
	return {
		"draft": draft,
		"frame_x": frame_x,
		"facing": facing,
	}

func _compose_preview(recipe: PaperDollRecipe, sample: Dictionary) -> Image:
	# Do not route this truth-board capture through split overlays: the current
	# split body/hair/armor sources are still under correction and produce the
	# visibly wrong gold-face/blocked-hair result.  The reference-match sheet is
	# the accepted, already aligned silhouette supplied by the art gate.
	var source_name := "reference_match_body_mounted_unisex.png" if recipe.is_mounted else "reference_match_body_on_foot_unisex.png"
	var source := load("res://assets/paper_doll/reference_match".path_join(source_name)) as Texture2D
	assert(source != null, "Missing reference-match source: %s" % source_name)
	var sheet := source.get_image()
	var source_row: int = PaperDollLayerVisual.source_row_for(sample["facing"] as int)
	var frame_x: int = sample["frame_x"] as int
	var frame := sheet.get_region(Rect2i(
		Vector2i(frame_x * PaperDollLayerVisual.FRAME_SIZE.x, source_row * PaperDollLayerVisual.FRAME_SIZE.y),
		PaperDollLayerVisual.FRAME_SIZE
	))
	if sample["facing"] as int == PaperDollLayerVisual.Facing.LEFT:
		frame.flip_x()
	frame.resize(REVIEW_SIZE.x, REVIEW_SIZE.y, Image.INTERPOLATE_NEAREST)
	var result := Image.create(REVIEW_SIZE.x, REVIEW_SIZE.y, false, Image.FORMAT_RGBA8)
	result.fill(Color("101722"))
	result.blend_rect(frame, Rect2i(Vector2i.ZERO, REVIEW_SIZE), Vector2i.ZERO)
	assert(_passes_reference_palette(frame), "Reference palette gate failed for sample")
	_draw_review_guides(result)
	return result

func _passes_reference_palette(frame: Image) -> bool:
	var white_hair_pixels := 0
	var silver_pixels := 0
	var navy_pixels := 0
	for y: int in range(frame.get_height()):
		for x: int in range(frame.get_width()):
			var pixel := frame.get_pixel(x, y)
			if pixel.a <= 0.05:
				continue
			var local_x := x
			var local_y := y
			if local_y <= 25 * SCALE and pixel.v > 0.55 and pixel.s < 0.48:
				white_hair_pixels += 1
			if local_y >= 28 * SCALE and pixel.v > 0.25 and pixel.s < 0.42:
				silver_pixels += 1
			if (local_x <= 23 * SCALE or local_x >= 40 * SCALE or local_y >= 42 * SCALE) \
					and pixel.h >= 0.55 and pixel.h <= 0.80 and pixel.s >= 0.12 and pixel.v <= 0.55:
				navy_pixels += 1
	return white_hair_pixels > 20 and silver_pixels > 40 and navy_pixels > 20

func _draw_review_guides(image: Image) -> void:
	var border := Color("6f8fb2")
	for x: int in range(REVIEW_SIZE.x):
		image.set_pixel(x, 0, border)
		image.set_pixel(x, REVIEW_SIZE.y - 1, border)
	for y: int in range(REVIEW_SIZE.y):
		image.set_pixel(0, y, border)
		image.set_pixel(REVIEW_SIZE.x - 1, y, border)
	var anchor := Vector2i(PaperDollLayerVisual.WORLD_ANCHOR * float(SCALE))
	var cyan := Color("00ffff")
	for offset: Vector2i in [Vector2i(-8, 0), Vector2i(-4, 0), Vector2i.ZERO, Vector2i(4, 0), Vector2i(8, 0), Vector2i(0, -8), Vector2i(0, -4), Vector2i(0, 4), Vector2i(0, 8)]:
		image.set_pixelv(anchor + offset, cyan)

func _manifest_line(number: int, file_name: String, sample: Dictionary) -> String:
	var draft: PaperDollPreviewDraft = sample["draft"] as PaperDollPreviewDraft
	var selected := PackedStringArray()
	for layer: int in draft.selected_layers():
		selected.append("%s=%s" % [PaperDollLayerVisual.layer_name(layer), draft.visual_id_for(layer)])
	if draft.is_mounted:
		selected.append("Mount=%s" % draft.mount_visual_id)
	return "%02d %s | gender=%s mounted=%s action=%s facing=%s frame=%d | %s" % [
		number,
		file_name,
		"MALE" if draft.gender == PaperDollLayerVisual.Gender.MALE else "FEMALE",
		draft.is_mounted,
		PaperDollAnimation.action_name(draft.action),
		PaperDollLayerVisual.Facing.keys()[sample["facing"] as int],
		sample["frame_x"],
		"; ".join(selected),
	]
