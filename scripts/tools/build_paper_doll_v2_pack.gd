extends SceneTree

## Deterministic V2 packer.  It only accepts the existing normalized V1
## reference-part sheets, pads mounted cells to 64x96, and emits a manifest.
## It never guesses a crop or performs a non-integer resize.

const SOURCE_DIR := "res://assets/paper_doll/reference_parts"
const OUTPUT_DIR := "res://assets/paper_doll/v2/parts"
const REPORT_PATH := "res://assets/paper_doll/v2/manifest.json"
const EYE_INK := Color("160904")
const EYE_SHADE := Color("291006")
const FRAME_MOTION: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 0),
	Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 0),
]

var _files_written := 0
var _skipped := PackedStringArray()
var _failures := PackedStringArray()
var _entries: Array[Dictionary] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_clear_generated_pngs()
	var directory := DirAccess.open(ProjectSettings.globalize_path(SOURCE_DIR))
	if directory == null:
		_failures.append("source directory is missing")
		_finish()
		return
	for file_name: String in directory.get_files():
		if not file_name.to_lower().ends_with(".png"):
			continue
		_normalize_file(file_name)
	_build_boots_from_armor()
	_write_report()
	_finish()

func _clear_generated_pngs() -> void:
	# Keep the pack deterministic: a skipped legacy board from an earlier run
	# must not remain beside the manifest and look like an admitted V2 asset.
	var output := DirAccess.open(ProjectSettings.globalize_path(OUTPUT_DIR))
	if output == null:
		return
	output.list_dir_begin()
	var file_name := output.get_next()
	while not file_name.is_empty():
		if not output.current_is_dir() and file_name.to_lower().ends_with(".png"):
			output.remove(file_name)
		file_name = output.get_next()
	output.list_dir_end()

func _normalize_file(file_name: String) -> void:
	var lower := file_name.to_lower()
	if lower.find("horse_full") >= 0:
		_skipped.append(file_name)
		return
	if lower.find("_mounted_") < 0 and lower.find("_on_foot_") < 0:
		_skipped.append(file_name)
		return
	var state := PaperDollV2Contract.RenderState.MOUNTED if lower.find("_mounted_") >= 0 else PaperDollV2Contract.RenderState.ON_FOOT
	var source_path := ProjectSettings.globalize_path(SOURCE_DIR.path_join(file_name))
	var image := Image.load_from_file(source_path)
	if image == null or image.is_empty():
		_failures.append("%s: unreadable" % file_name)
		return
	var source_size := Vector2i(image.get_width(), image.get_height())
	var expected_source := Vector2i(512, 192)
	var expected_mounted := PaperDollV2Contract.sheet_size(PaperDollV2Contract.RenderState.MOUNTED)
	if source_size != expected_source and source_size != expected_mounted:
		_failures.append("%s: source size %s is not 512x192 or 512x288" % [file_name, source_size])
		return
	if state == PaperDollV2Contract.RenderState.MOUNTED and source_size == expected_source:
		image = _pad_mounted(image)
	else:
		image = image.duplicate()
	if lower.find("_armor_") >= 0 and lower.find("_helmet_") < 0:
		image = _clear_boot_band(image, state)
	# Normalize the front-facing eye landmark for both body templates.  The old
	# patch only touched the female mounted sheet and left source anti-aliasing
	# tails in place; that is why the female DOWN frame and male MOUNTED frame
	# could still look asymmetric.  This pass is deliberately limited to the
	# Body source layer and the front (DOWN) row.  Hair/helmet/face art remains
	# owned by its own layer, while all four gender/state body variants receive
	# the same pixel-level symmetry contract.
	if lower.find("body_female_default_") >= 0 or lower.find("body_male_default_") >= 0:
		image = _canonicalize_body_eyes(image, state, lower.find("body_female_default_") >= 0)
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR.path_join(file_name))
	if image.save_png(output_path) != OK:
		_failures.append("%s: save failed" % file_name)
		return
	_files_written += 1
	_entries.append(_entry(file_name, state, "part"))

func _canonicalize_body_eyes(source: Image, state: int, is_female: bool) -> Image:
	var result := source.duplicate()
	var cell := PaperDollV2Contract.frame_size(state)
	var mounted := state == PaperDollV2Contract.RenderState.MOUNTED
	# These coordinates are measured in the normalized frame, not in source
	# board pixels.  Female on-foot has a half-pixel face centre at 31.5; male
	# on-foot and both mounted templates are centred at 32.  The resulting eye
	# rectangles are mirrored around their actual template centre instead of
	# forcing both genders into a visibly shifted position.
	var eye_y := 48 if mounted else 15
	var left_x := 28 if mounted else (26 if is_female else 27)
	var right_x := 35 if mounted else 36
	var eye_height := 3 if mounted else 4
	var clear_height := eye_height + 2
	for frame_x: int in range(PaperDollV2Contract.FRAME_COLUMNS):
		var origin := Vector2i(frame_x * cell.x, 0)
		var motion := FRAME_MOTION[frame_x]
		var motion_origin := origin + motion
		for y: int in range(clear_height):
			# Use the untouched skin at the face centre to erase the source eye
			# tails/width differences without making a transparent hole.
			var skin := source.get_pixelv(motion_origin + Vector2i(32, eye_y + y))
			for eye_x: int in [left_x, right_x]:
				for x: int in range(2):
					result.set_pixelv(motion_origin + Vector2i(eye_x + x, eye_y + y), skin)
		_paint_eye(result, motion_origin + Vector2i(left_x, eye_y), eye_height)
		_paint_eye(result, motion_origin + Vector2i(right_x, eye_y), eye_height)
	return result

func _paint_eye(sheet: Image, top_left: Vector2i, height: int) -> void:
	for y: int in range(height):
		for x: int in range(2):
			# Keep a small warm lower edge so the repaired landmark belongs to the
			# existing pixel-art face instead of looking like a pure black decal.
			sheet.set_pixelv(top_left + Vector2i(x, y), EYE_INK if y < height - 1 else EYE_SHADE)

func _build_boots_from_armor() -> void:
	var pairs := [
		["artgate1_armor_on_foot_unisex.png", PaperDollV2Contract.RenderState.ON_FOOT, "boots_on_foot_unisex.png"],
		["artgate1_armor_mounted_unisex.png", PaperDollV2Contract.RenderState.MOUNTED, "boots_mounted_unisex.png"],
	]
	for pair: Array in pairs:
		var source_path := ProjectSettings.globalize_path(OUTPUT_DIR.path_join(pair[0] as String))
		var image := Image.load_from_file(source_path)
		if image == null or image.is_empty():
			_failures.append("boots source missing: %s" % pair[0])
			continue
		var boots := _extract_boot_band(image, pair[1] as int)
		var output_name := pair[2] as String
		var output_path := ProjectSettings.globalize_path(OUTPUT_DIR.path_join(output_name))
		if boots.save_png(output_path) != OK:
			_failures.append("boots save failed: %s" % output_name)
			continue
		_files_written += 1
		_entries.append(_entry(output_name, pair[1] as int, "boots"))

func _pad_mounted(source: Image) -> Image:
	var result := Image.create(512, 288, false, Image.FORMAT_RGBA8)
	result.fill(Color(0, 0, 0, 0))
	result.blend_rect(source, Rect2i(Vector2i.ZERO, Vector2i(512, 192)), Vector2i(0, 32))
	return result

func _clear_boot_band(source: Image, state: int) -> Image:
	var result := source.duplicate()
	var cell := PaperDollV2Contract.frame_size(state)
	var band_start := cell.y - 18
	for row: int in range(PaperDollV2Contract.SOURCE_ROWS):
		for frame_x: int in range(PaperDollV2Contract.FRAME_COLUMNS):
			for y: int in range(band_start, cell.y):
				for x: int in range(cell.x):
					result.set_pixel(frame_x * cell.x + x, row * cell.y + y, Color(0, 0, 0, 0))
	return result

func _extract_boot_band(source: Image, state: int) -> Image:
	var result := Image.create(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8)
	result.fill(Color(0, 0, 0, 0))
	var cell := PaperDollV2Contract.frame_size(state)
	var band_start := cell.y - 18
	for row: int in range(PaperDollV2Contract.SOURCE_ROWS):
		for frame_x: int in range(PaperDollV2Contract.FRAME_COLUMNS):
			for y: int in range(band_start, cell.y):
				for x: int in range(cell.x):
					var pixel := source.get_pixel(frame_x * cell.x + x, row * cell.y + y)
					if pixel.a > 0.05:
						result.set_pixel(frame_x * cell.x + x, row * cell.y + y, pixel)
	return result

func _entry(file_name: String, state: int, kind: String) -> Dictionary:
	return {
		"visual_id": file_name.get_basename(),
		"file": OUTPUT_DIR.path_join(file_name),
		"kind": kind,
		"state": PaperDollV2Contract.state_name(state),
		"frame_size": [PaperDollV2Contract.frame_size(state).x, PaperDollV2Contract.frame_size(state).y],
		"sheet_size": [PaperDollV2Contract.sheet_size(state).x, PaperDollV2Contract.sheet_size(state).y],
		"frame_columns": PaperDollV2Contract.FRAME_COLUMNS,
		"source_rows": PaperDollV2Contract.SOURCE_ROWS,
		"anchor": [PaperDollV2Contract.anchor_px(state).x, PaperDollV2Contract.anchor_px(state).y],
		"directions": ["DOWN", "UP", "RIGHT", "LEFT_MIRROR"],
		"normalization_version": "v2_1",
	}

func _write_report() -> void:
	var report := {
		"contract": "paper_doll_v2",
		"result": "PASS" if _failures.is_empty() else "FAIL",
		"files_written": _files_written,
		"entries": _entries,
		"skipped": Array(_skipped),
		"failures": Array(_failures),
	}
	var file := FileAccess.open(ProjectSettings.globalize_path(REPORT_PATH), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()

func _finish() -> void:
	if _failures.is_empty():
		print("PAPER_DOLL_V2_PACK_PASS files=%d entries=%d" % [_files_written, _entries.size()])
	else:
		for failure: String in _failures:
			push_error("PAPER_DOLL_V2_PACK_FAIL: %s" % failure)
		print("PAPER_DOLL_V2_PACK_FAIL failures=%d files=%d" % [_failures.size(), _files_written])
	quit(0 if _failures.is_empty() else 1)
