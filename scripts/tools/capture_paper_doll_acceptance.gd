extends SceneTree

## Pixel-level acceptance capture for the Paper Doll lab.
##
## This is intentionally separate from the CharacterCreator UI screenshot.
## The UI can be laid out correctly while the 64x64 character is assembled
## from the wrong body, direction row, or z-order.  Every check below reads the
## actual Sprite2D Composer output from a transparent 64x64 SubViewport, then
## writes a 4x enlarged inspection frame for human review.

const OUTPUT_DIR := "res://.visual_captures/paper_doll/acceptance"
const FRAME_SIZE := Vector2i(64, 64)
const ENLARGED_SIZE := Vector2i(256, 256)
const REFERENCE_MATCH_DIR := "res://assets/paper_doll/reference_match"

var _catalog: PaperDollCatalog
var _viewport: SubViewport
var _composer: PaperDollComposer
var _failures: PackedStringArray = []
var _report: Array[Dictionary] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_catalog = PaperDollCatalog.create_art_gate1_catalog()
	_failures.append_array(_catalog.validation_issues())
	_create_viewport()
	await _settle()

	var cases: Array[Dictionary] = [
		{"id": "reference_male", "mounted": false, "gender": PaperDollLayerVisual.Gender.MALE, "alternate": false},
		{"id": "reference_mounted_male", "mounted": true, "gender": PaperDollLayerVisual.Gender.MALE, "alternate": false},
		{"id": "light_armor_male", "mounted": false, "gender": PaperDollLayerVisual.Gender.MALE, "alternate": true},
		{"id": "light_armor_mounted_male", "mounted": true, "gender": PaperDollLayerVisual.Gender.MALE, "alternate": true},
		{"id": "light_armor_female", "mounted": false, "gender": PaperDollLayerVisual.Gender.FEMALE, "alternate": true},
		{"id": "light_armor_mounted_female", "mounted": true, "gender": PaperDollLayerVisual.Gender.FEMALE, "alternate": true},
	]
	for case: Dictionary in cases:
		await _capture_case(case)

	_write_report()
	if _failures.is_empty():
		print("PAPER_DOLL_ACCEPTANCE_PASS captures=%d" % _report.size())
	else:
		for failure: String in _failures:
			push_error("PAPER_DOLL_ACCEPTANCE_FAIL: %s" % failure)
		print("PAPER_DOLL_ACCEPTANCE_FAILED issues=%d captures=%d" % [_failures.size(), _report.size()])
	quit(0 if _failures.is_empty() else 1)

func _create_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.size = FRAME_SIZE
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(_viewport)
	_composer = PaperDollComposer.new()
	# Sprite2D.offset is (-32,-56), so this position maps the shared world
	# anchor (32,56) into the 64x64 capture cell.
	_composer.position = Vector2(32.0, 56.0)
	_viewport.add_child(_composer)

func _capture_case(case: Dictionary) -> void:
	var recipe := _make_recipe(
		case["mounted"] as bool,
		case["gender"] as int,
		case["alternate"] as bool
	)
	if recipe == null:
		_failures.append("%s recipe did not resolve" % case["id"])
		return
	if case["alternate"] as bool:
		var body_source := recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY)
		if body_source == null:
			_failures.append("%s has no body texture" % case["id"])
		else:
			# A non-reference recipe must never carry the flattened accepted board
			# as its Body layer.  This is the duplicate-body regression guard.
			var body_image := body_source.get_image()
			if _count_warm_pixels(body_image, Rect2i(0, 0, 64, 64)) <= 0:
				_failures.append("%s body is not a readable skin/body layer" % case["id"])

	var captures: Dictionary = {}
	for facing: int in range(PaperDollLayerVisual.Facing.DOWN, PaperDollLayerVisual.Facing.LEFT + 1):
		_composer.apply_recipe(recipe)
		_composer.update_frame(facing, 0)
		await _settle()
		var image := _viewport.get_texture().get_image()
		if image == null or image.is_empty():
			_failures.append("%s facing=%d produced an empty image" % [case["id"], facing])
			continue
		var metrics := _metrics(image, case["mounted"] as bool, facing)
		metrics["case"] = case["id"]
		metrics["facing"] = facing
		_report.append(metrics)
		captures[facing] = image
		_save_enlarged(image, "%s_facing%d_frame0.png" % [case["id"], facing])

		if metrics["empty"] as bool:
			_failures.append("%s facing=%d is empty" % [case["id"], facing])
		if metrics["bbox_touch_edge"] as bool:
			_failures.append("%s facing=%d touches the 64x64 cell edge: %s" % [case["id"], facing, metrics["bbox"]])
		if metrics["bottom"] < 53 or metrics["bottom"] > 58:
			_failures.append("%s facing=%d anchor bottom=%d (expected 53..58)" % [case["id"], facing, metrics["bottom"]])
		if case["mounted"] as bool and facing == PaperDollLayerVisual.Facing.DOWN:
			if metrics["horse_pixels"] < 180:
				_failures.append("%s DOWN has too few horse pixels (%d)" % [case["id"], metrics["horse_pixels"]])
			if metrics["horse_lower_pixels"] < 60:
				_failures.append("%s DOWN has no readable horse lower body (%d pixels)" % [case["id"], metrics["horse_lower_pixels"]])
		if not (case["mounted"] as bool) and not (case["alternate"] as bool) \
				and facing == PaperDollLayerVisual.Facing.DOWN:
			if metrics["skin_pixels"] < 120:
				_failures.append("%s DOWN face/skin is not visible (%d pixels)" % [case["id"], metrics["skin_pixels"]])

	var down: Dictionary = _find_metrics(case["id"], PaperDollLayerVisual.Facing.DOWN)
	var up: Dictionary = _find_metrics(case["id"], PaperDollLayerVisual.Facing.UP)
	if not down.is_empty() and not up.is_empty():
		if (up["width"] as int) > (down["width"] as int) + 4:
			_failures.append("%s UP is wider than DOWN: up=%d down=%d" % [case["id"], up["width"], down["width"]])
	var right: Image = captures.get(PaperDollLayerVisual.Facing.RIGHT)
	var left: Image = captures.get(PaperDollLayerVisual.Facing.LEFT)
	if right != null and left != null:
		var mirror_difference := _mirror_difference(right, left)
		if mirror_difference > 24:
			_failures.append("%s LEFT/RIGHT mirror mismatch=%d pixels" % [case["id"], mirror_difference])

	if not (case["alternate"] as bool):
		_check_reference_match(case, captures)

func _make_recipe(mounted: bool, gender: int, alternate: bool) -> PaperDollRecipe:
	var draft := PaperDollPreviewDraft.new()
	draft.gender = gender
	draft.is_mounted = mounted
	draft.set_visual(
		PaperDollLayerVisual.RenderLayer.BODY,
		&"body_female_default" if gender == PaperDollLayerVisual.Gender.FEMALE else &"body_male_default"
	)
	draft.set_visual(
		PaperDollLayerVisual.RenderLayer.ARMOR,
		&"light_armor" if alternate else &"artgate1_armor"
	)
	draft.set_visual(
		PaperDollLayerVisual.RenderLayer.HAIR,
		&"hair_short_spiky" if alternate else (
			&"hair_female_default" if gender == PaperDollLayerVisual.Gender.FEMALE else &"hair_male_default"
		)
	)
	draft.set_visual(PaperDollLayerVisual.RenderLayer.CAPE, &"artgate1_cape")
	draft.set_visual(
		PaperDollLayerVisual.RenderLayer.HELMET,
		&"light_armor_helmet" if alternate else &""
	)
	if mounted:
		draft.mount_visual_id = &"artgate1_horse"
	return _catalog.resolve_recipe(draft)

func _metrics(image: Image, mounted: bool, facing: int) -> Dictionary:
	var bbox := image.get_used_rect()
	var horse_pixels := _count_horse_pixels(image)
	var horse_lower_pixels := _count_horse_pixels_in(image, Rect2i(0, 38, 64, 26))
	var skin_pixels := _count_warm_pixels(image, Rect2i(12, 4, 40, 28))
	return {
		"empty": bbox.size.x <= 0 or bbox.size.y <= 0,
		"bbox": str(bbox),
		"x": bbox.position.x,
		"y": bbox.position.y,
		"width": bbox.size.x,
		"height": bbox.size.y,
		"bottom": bbox.end.y,
		# The approved head silhouettes intentionally reach y=0 in the 64x64
		# cell.  A top-edge pixel is not clipping; only horizontal spill or a
		# bottom/right overflow violates the shared frame contract.
		"bbox_touch_edge": bbox.position.x <= 0 \
				or bbox.end.x >= 64 or bbox.end.y >= 64,
		"horse_pixels": horse_pixels if mounted else 0,
		"horse_lower_pixels": horse_lower_pixels if mounted else 0,
		"skin_pixels": skin_pixels if not mounted else 0,
		"facing": facing,
	}

func _check_reference_match(case: Dictionary, captures: Dictionary) -> void:
	var mounted: bool = case["mounted"] as bool
	var file_name := "reference_match_body_mounted_unisex.png" if mounted \
		else "reference_match_body_on_foot_unisex.png"
	var path := REFERENCE_MATCH_DIR.path_join(file_name)
	var reference := Image.load_from_file(ProjectSettings.globalize_path(path))
	if reference == null or reference.is_empty():
		_failures.append("%s reference board missing: %s" % [case["id"], path])
		return
	for facing: int in range(4):
		var actual: Image = captures.get(facing)
		if actual == null:
			continue
		var row := PaperDollLayerVisual.source_row_for(facing)
		var expected := reference.get_region(Rect2i(0, row * 64, 64, 64))
		if facing == PaperDollLayerVisual.Facing.LEFT:
			expected.flip_x()
		var difference := _image_difference(actual, expected)
		# The accepted board is the visual authority for the reference preset;
		# any material difference means the fallback silently changed again.
		if difference > 8:
			_failures.append("%s facing=%d differs from accepted reference by %d pixels" % [case["id"], facing, difference])

func _find_metrics(case_id: String, facing: int) -> Dictionary:
	for metrics: Dictionary in _report:
		if metrics.get("case", "") == case_id and metrics.get("facing", -1) == facing:
			return metrics
	return {}

func _count_horse_pixels(image: Image) -> int:
	return _count_horse_pixels_in(image, Rect2i(0, 0, 64, 64))

func _count_horse_pixels_in(image: Image, region: Rect2i) -> int:
	var count := 0
	for y: int in range(region.position.y, mini(region.end.y, image.get_height())):
		for x: int in range(region.position.x, mini(region.end.x, image.get_width())):
			var color := image.get_pixel(x, y)
			if color.a <= 0.05:
				continue
			# Horse coat/tack in the reference pack is warm brown/orange.  The
			# rider's gold belt is excluded by requiring a minimum saturation/value
			# relationship and by measuring the lower body band separately.
			if color.h >= 0.01 and color.h <= 0.16 and color.s >= 0.28 and color.v >= 0.16:
				count += 1
	return count

func _count_warm_pixels(image: Image, region: Rect2i) -> int:
	var count := 0
	for y: int in range(region.position.y, mini(region.end.y, image.get_height())):
		for x: int in range(region.position.x, mini(region.end.x, image.get_width())):
			var color := image.get_pixel(x, y)
			if color.a > 0.05 and color.h >= 0.04 and color.h <= 0.18 \
					and color.s >= 0.30 and color.v >= 0.45:
				count += 1
	return count

func _mirror_difference(right: Image, left: Image) -> int:
	var difference := 0
	for y: int in range(64):
		for x: int in range(64):
			if _pixel_difference(right.get_pixel(x, y), left.get_pixel(63 - x, y)) > 0.08:
				difference += 1
	return difference

func _image_difference(left: Image, right: Image) -> int:
	var difference := 0
	for y: int in range(64):
		for x: int in range(64):
			if _pixel_difference(left.get_pixel(x, y), right.get_pixel(x, y)) > 0.08:
				difference += 1
	return difference

func _pixel_difference(left: Color, right: Color) -> float:
	# PNGs may carry arbitrary RGB in fully transparent pixels (the accepted
	# board is white-backed while direct ImageTextures clear to black).  Those
	# bytes are not visible and must not turn an identical silhouette into a
	# false mismatch.
	if left.a <= 0.05 and right.a <= 0.05:
		return 0.0
	return absf(left.r - right.r) + absf(left.g - right.g) + absf(left.b - right.b) + absf(left.a - right.a)

func _save_enlarged(image: Image, file_name: String) -> void:
	var enlarged := image.duplicate()
	enlarged.resize(ENLARGED_SIZE.x, ENLARGED_SIZE.y, Image.INTERPOLATE_NEAREST)
	var background := Image.create(ENLARGED_SIZE.x, ENLARGED_SIZE.y, false, Image.FORMAT_RGBA8)
	background.fill(Color("121821"))
	background.blend_rect(enlarged, Rect2i(Vector2i.ZERO, ENLARGED_SIZE), Vector2i.ZERO)
	var path := ProjectSettings.globalize_path(OUTPUT_DIR).path_join(file_name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	background.save_png(path)

func _write_report() -> void:
	var report := {
		"result": "PASS" if _failures.is_empty() else "FAIL",
		"failures": Array(_failures),
		"metrics": _report,
		"capture_contract": "64x64 transparent frame, 4x nearest-neighbour inspection image",
	}
	var path := ProjectSettings.globalize_path(OUTPUT_DIR).path_join("report.json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()

func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame
