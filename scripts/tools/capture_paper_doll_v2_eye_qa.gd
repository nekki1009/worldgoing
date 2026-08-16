extends SceneTree

## High-resolution front-pose evidence for the V2 eye landmark contract.
## The normal lab deliberately shows a complete 64 px frame; this capture
## renders the same Composer output at 8x so a human can inspect the eyes
## without relying on a tiny screenshot or a raw-pixel assertion.

const OUTPUT_DIR := "res://preview/paper_doll_v2"
const REFERENCE_MATCH_DIR := "res://assets/paper_doll/reference_match"
const SCALE := 8

const CASES: Array[Dictionary] = [
	{"name": "eye_qa_male_on_foot", "gender": PaperDollV2Contract.Gender.MALE, "state": PaperDollV2Contract.RenderState.ON_FOOT, "id": &"reference_body_on_foot", "reference_file": "reference_match_body_on_foot_unisex.png"},
	{"name": "eye_qa_female_on_foot", "gender": PaperDollV2Contract.Gender.FEMALE, "state": PaperDollV2Contract.RenderState.ON_FOOT, "id": &"reference_female_body_on_foot", "reference_file": "reference_match_female_body_on_foot.png"},
	{"name": "eye_qa_male_mounted", "gender": PaperDollV2Contract.Gender.MALE, "state": PaperDollV2Contract.RenderState.MOUNTED, "id": &"reference_body_mounted", "reference_file": "reference_match_body_mounted_unisex.png"},
	{"name": "eye_qa_female_mounted", "gender": PaperDollV2Contract.Gender.FEMALE, "state": PaperDollV2Contract.RenderState.MOUNTED, "id": &"reference_female_body_mounted", "reference_file": "reference_match_female_body_mounted.png"},
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var catalog := PaperDollV2Catalog.load_generated_pack()
	if catalog == null or not catalog.last_issues.is_empty():
		push_error("PAPER_DOLL_V2_EYE_QA_FAIL: catalog %s" % (catalog.last_issues if catalog != null else "null"))
		quit(1)
		return
	for entry: Dictionary in CASES:
		if not await _capture_case(catalog, entry):
			quit(1)
			return
	print("PAPER_DOLL_V2_EYE_QA_PASS outputs=%d scale=%d front=down_frame0 reference_pixels" % [CASES.size(), SCALE])
	quit(0)

func _capture_case(catalog: PaperDollV2Catalog, entry: Dictionary) -> bool:
	var state: int = entry["state"]
	var gender: int = entry["gender"]
	var frame_size := PaperDollV2Contract.frame_size(state)
	var viewport := SubViewport.new()
	viewport.transparent_bg = true
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.size = frame_size * SCALE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(viewport)
	var composer := PaperDollV2Composer.new()
	composer.scale = Vector2(SCALE, SCALE)
	var anchor := PaperDollV2Contract.anchor_px(state)
	composer.position = Vector2(anchor) * SCALE
	viewport.add_child(composer)
	var recipe := catalog.resolve_reference_recipe(gender, state, entry["id"])
	if recipe == null or not composer.apply_recipe(recipe):
		push_error("PAPER_DOLL_V2_EYE_QA_FAIL: recipe %s" % entry["name"])
		viewport.queue_free()
		return false
	composer.clear_dyes()
	composer.update_frame(PaperDollV2Contract.Facing.DOWN, 0)
	await process_frame
	await process_frame
	var image := viewport.get_texture().get_image()
	if not _validate_rendered_eyes(image, frame_size, entry):
		push_error("PAPER_DOLL_V2_EYE_QA_FAIL: rendered face differs from reference %s" % entry["name"])
		viewport.queue_free()
		return false
	var path := ProjectSettings.globalize_path(OUTPUT_DIR.path_join(String(entry["name"]) + ".png"))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var saved := image != null and not image.is_empty() and image.save_png(path) == OK
	viewport.queue_free()
	if not saved:
		push_error("PAPER_DOLL_V2_EYE_QA_FAIL: save %s" % entry["name"])
	return saved

func _validate_rendered_eyes(image: Image, frame_size: Vector2i, entry: Dictionary) -> bool:
	if image == null or image.is_empty():
		return false
	# The capture is rendered at 8x for human inspection.  Reduce it with
	# nearest-neighbour first, so the machine check observes the exact 64 px
	# Composer frame rather than anti-aliased screenshot pixels.
	var normalized := image.duplicate()
	normalized.resize(frame_size.x, frame_size.y, Image.INTERPOLATE_NEAREST)
	var expected := _load_reference_frame(String(entry["reference_file"]), frame_size)
	if expected == null or expected.is_empty():
		return false
	# The face occupies the top 32 px of an on-foot cell and the 32..64 band
	# of a mounted cell.  Comparing this whole band preserves the authored eye
	# width, spacing, highlights, and anti-aliased contour without inventing a
	# new coordinate mask.
	var face_y := 32 if frame_size.y == 96 else 0
	for y: int in range(face_y, face_y + 32):
		for x: int in range(64):
			if not _color_close(normalized.get_pixel(x, y), expected.get_pixel(x, y)):
				return false
	return true

func _load_reference_frame(file_name: String, frame_size: Vector2i) -> Image:
	var source := Image.load_from_file(ProjectSettings.globalize_path(REFERENCE_MATCH_DIR.path_join(file_name)))
	if source == null or source.is_empty() or source.get_width() != 512 or source.get_height() != 192:
		return null
	var frame := source.get_region(Rect2i(Vector2i.ZERO, Vector2i(64, 64)))
	if frame_size.y == 64:
		return frame
	var mounted := Image.create(64, 96, false, Image.FORMAT_RGBA8)
	mounted.fill(Color.TRANSPARENT)
	mounted.blit_rect(frame, Rect2i(Vector2i.ZERO, Vector2i(64, 64)), Vector2i(0, 32))
	return mounted

func _color_close(actual: Color, expected: Color) -> bool:
	if actual.a <= 0.05 and expected.a <= 0.05:
		return true
	return absf(actual.r - expected.r) <= 0.02 \
		and absf(actual.g - expected.g) <= 0.02 \
		and absf(actual.b - expected.b) <= 0.02 \
		and absf(actual.a - expected.a) <= 0.02
