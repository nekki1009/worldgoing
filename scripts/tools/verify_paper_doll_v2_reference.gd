extends SceneTree

## Strict reference acceptance for Paper Doll V2.
##
## The ordinary V2 capture only proves the Composer contract (non-empty,
## in-bounds, synchronized frames).  This verifier compares the actual V2
## output against sheets calibrated from assets/doll/reference.  It therefore
## rejects a visually wrong composition even when its dimensions are valid.

const OUTPUT_DIR := "res://.visual_captures/paper_doll_v2"
const REFERENCE_MATCH_DIR := "res://assets/paper_doll/reference_match"
const SCALE := 4
const IOU_MIN := 0.85
const BBOX_TOLERANCE_PX := 2

var _catalog: PaperDollV2Catalog
var _viewport: SubViewport
var _composer: PaperDollV2Composer
var _failures := PackedStringArray()
var _cases: Array[Dictionary] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_catalog = PaperDollV2Catalog.load_generated_pack()
	_failures.append_array(_catalog.last_issues)
	_failures.append_array(_catalog.validation_issues())
	if _failures.is_empty():
		_create_viewport(PaperDollV2Contract.RenderState.ON_FOOT)
		await _settle()
		await _audit_case(
			"on_foot_default",
			PaperDollV2Contract.Gender.MALE,
			PaperDollV2Contract.RenderState.ON_FOOT,
			false,
			"reference_match_body_on_foot_unisex.png"
		)
		await _audit_case(
			"on_foot_armed",
			PaperDollV2Contract.Gender.MALE,
			PaperDollV2Contract.RenderState.ON_FOOT,
			true,
			"reference_match_armed_on_foot_unisex.png"
		)
		_create_viewport(PaperDollV2Contract.RenderState.MOUNTED)
		await _settle()
		await _audit_case(
			"mounted_default",
			PaperDollV2Contract.Gender.MALE,
			PaperDollV2Contract.RenderState.MOUNTED,
			false,
			"reference_match_body_mounted_unisex.png"
		)
		await _audit_case(
			"mounted_armed",
			PaperDollV2Contract.Gender.MALE,
			PaperDollV2Contract.RenderState.MOUNTED,
			true,
			"reference_match_armed_mounted_unisex.png"
		)
		_create_viewport(PaperDollV2Contract.RenderState.ON_FOOT)
		await _settle()
		await _audit_case(
			"female_on_foot_default",
			PaperDollV2Contract.Gender.FEMALE,
			PaperDollV2Contract.RenderState.ON_FOOT,
			false,
			"reference_match_female_body_on_foot.png"
		)
		await _audit_case(
			"female_on_foot_armed",
			PaperDollV2Contract.Gender.FEMALE,
			PaperDollV2Contract.RenderState.ON_FOOT,
			true,
			"reference_match_female_armed_on_foot.png"
		)
		_create_viewport(PaperDollV2Contract.RenderState.MOUNTED)
		await _settle()
		await _audit_case(
			"female_mounted_default",
			PaperDollV2Contract.Gender.FEMALE,
			PaperDollV2Contract.RenderState.MOUNTED,
			false,
			"reference_match_female_body_mounted.png"
		)
		await _audit_case(
			"female_mounted_armed",
			PaperDollV2Contract.Gender.FEMALE,
			PaperDollV2Contract.RenderState.MOUNTED,
			true,
			"reference_match_female_armed_mounted.png"
		)
	_write_report()
	_finish()

func _create_viewport(state: int) -> void:
	if _viewport != null:
		_viewport.queue_free()
	_viewport = SubViewport.new()
	_viewport.size = PaperDollV2Contract.frame_size(state)
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	get_root().add_child(_viewport)
	_composer = PaperDollV2Composer.new()
	_composer.position = Vector2(PaperDollV2Contract.anchor_px(state))
	_viewport.add_child(_composer)

func _audit_case(case_id: String, gender: int, state: int, armed: bool, reference_file: String) -> void:
	# Reference acceptance intentionally exercises the same calibrated preset
	# path used by the material lab.  Split-part assets remain a separate
	# staging concern; they must not be allowed to hide a wrong silhouette in
	# the reference gate.
	var reference_id := _reference_id(gender, state, armed)
	var recipe := _catalog.resolve_reference_recipe(gender, state, reference_id)
	if recipe == null:
		_failures.append("%s recipe: %s" % [case_id, _catalog.last_issues])
		return
	if not _composer.apply_recipe(recipe):
		_failures.append("%s composer: %s" % [case_id, _composer.last_error])
		return
	_composer.clear_dyes()
	# Check every authored row, the mirrored LEFT row, and every animation
	# column.  A single DOWN/frame-0 screenshot is not enough to catch a side
	# facing, flip, or frame-offset regression.
	for facing: int in range(4):
		for frame_x: int in range(PaperDollV2Contract.FRAME_COLUMNS):
			var check_id := "%s facing=%s frame=%d" % [
				case_id,
				PaperDollV2Contract.Facing.keys()[facing],
				frame_x,
			]
			if not _composer.update_frame(facing, frame_x):
				_failures.append("%s update failed: %s" % [check_id, _composer.last_error])
				continue
			await _settle()
			var actual := _viewport.get_texture().get_image()
			var expected := _load_reference_frame(reference_file, state, facing, frame_x)
			if actual == null or actual.is_empty() or expected == null or expected.is_empty():
				_failures.append("%s: actual or reference image is empty" % check_id)
				continue
			if facing == PaperDollV2Contract.Facing.DOWN and frame_x == 0 \
					and not _face_matches_reference(actual, expected, state):
				_failures.append("%s: rendered face/eyes differ from accepted reference pixels" % check_id)
			var actual_bbox := actual.get_used_rect()
			var expected_bbox := expected.get_used_rect()
			var iou := _mask_iou(actual, expected)
			var bbox_delta := Vector2i(
				abs(actual_bbox.position.x - expected_bbox.position.x),
				abs(actual_bbox.position.y - expected_bbox.position.y)
			)
			_cases.append({
				"case": case_id,
				"gender": PaperDollV2Contract.gender_name(gender),
				"facing": PaperDollV2Contract.Facing.keys()[facing],
				"frame": frame_x,
				"state": PaperDollV2Contract.state_name(state),
				"reference": REFERENCE_MATCH_DIR.path_join(reference_file),
				"reference_origin": "assets/doll/reference/*.png",
				"actual_bbox": str(actual_bbox),
				"reference_bbox": str(expected_bbox),
				"bbox_delta": [bbox_delta.x, bbox_delta.y],
				"mask_iou": iou,
				"iou_threshold": IOU_MIN,
				"bbox_tolerance_px": BBOX_TOLERANCE_PX,
			})
			if iou < IOU_MIN:
				_failures.append("%s: silhouette IoU %.3f < %.3f" % [check_id, iou, IOU_MIN])
			if bbox_delta.x > BBOX_TOLERANCE_PX or bbox_delta.y > BBOX_TOLERANCE_PX:
				_failures.append("%s: bbox origin delta=%s > %d px" % [check_id, bbox_delta, BBOX_TOLERANCE_PX])

func _load_reference_frame(file_name: String, state: int, facing: int, frame_x: int) -> Image:
	var path := ProjectSettings.globalize_path(REFERENCE_MATCH_DIR.path_join(file_name))
	var source := Image.load_from_file(path)
	if source == null or source.is_empty():
		return null
	var source_row := PaperDollV2Contract.source_row_for(facing)
	var frame := source.get_region(Rect2i(
		Vector2i(frame_x * 64, source_row * 64),
		Vector2i(64, 64)
	))
	if facing == PaperDollV2Contract.Facing.LEFT:
		frame.flip_x()
	if state == PaperDollV2Contract.RenderState.ON_FOOT:
		return frame
	# The calibrated reference sheet uses a 64x64 frame.  Place its fixed
	# foot/hoof anchor at the V2 mounted anchor before comparing to 64x96.
	var mounted := Image.create(64, 96, false, Image.FORMAT_RGBA8)
	mounted.fill(Color.TRANSPARENT)
	mounted.blit_rect(frame, Rect2i(Vector2i.ZERO, Vector2i(64, 64)), Vector2i(0, 32))
	return mounted

func _face_matches_reference(actual: Image, expected: Image, state: int) -> bool:
	# The accepted reference composite is the body texture for these QA
	# presets.  Compare the complete 32 px face band, rather than a hand-written
	# eye mask, so the original eye width, spacing, highlights, and contour are
	# preserved exactly.
	var face_y := 32 if state == PaperDollV2Contract.RenderState.MOUNTED else 0
	for y: int in range(face_y, face_y + 32):
		for x: int in range(64):
			if not _color_close(actual.get_pixel(x, y), expected.get_pixel(x, y)):
				return false
	return true

func _color_close(actual: Color, expected: Color) -> bool:
	if actual.a <= 0.05 and expected.a <= 0.05:
		return true
	return absf(actual.r - expected.r) <= 0.02 \
		and absf(actual.g - expected.g) <= 0.02 \
		and absf(actual.b - expected.b) <= 0.02 \
		and absf(actual.a - expected.a) <= 0.02

func _mask_iou(left: Image, right: Image) -> float:
	var intersection := 0
	var union := 0
	for y: int in range(mini(left.get_height(), right.get_height())):
		for x: int in range(mini(left.get_width(), right.get_width())):
			var a := left.get_pixel(x, y).a > 0.05
			var b := right.get_pixel(x, y).a > 0.05
			if a and b:
				intersection += 1
			if a or b:
				union += 1
	return float(intersection) / float(union) if union > 0 else 0.0

func _write_report() -> void:
	var path := ProjectSettings.globalize_path(OUTPUT_DIR.path_join("reference_acceptance.json"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("could not write reference acceptance report")
		return
	file.store_string(JSON.stringify({
		"result": "PASS" if _failures.is_empty() else "FAIL",
		"reference_origin": "assets/doll/reference/*.png",
		"reference_match_dir": REFERENCE_MATCH_DIR,
		"cases": _cases,
		"failures": Array(_failures),
	}, "\t"))
	file.close()

func _finish() -> void:
	if _failures.is_empty():
		print("PAPER_DOLL_V2_REFERENCE_PASS checks=%d groups=8 front_reference_pixels" % _cases.size())
	else:
		for failure: String in _failures:
			push_error("PAPER_DOLL_V2_REFERENCE_FAIL: %s" % failure)
		print("PAPER_DOLL_V2_REFERENCE_FAIL failures=%d checks=%d groups=8" % [_failures.size(), _cases.size()])
	quit(0 if _failures.is_empty() else 1)

func _reference_id(gender: int, state: int, armed: bool) -> StringName:
	var prefix := "reference_female_" if gender == PaperDollV2Contract.Gender.FEMALE else "reference_"
	var pose := "armed_" if armed else "body_"
	var state_name := "mounted" if state == PaperDollV2Contract.RenderState.MOUNTED else "on_foot"
	return StringName(prefix + pose + state_name)

func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame
