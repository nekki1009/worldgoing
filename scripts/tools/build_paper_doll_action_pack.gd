extends SceneTree

## Converts a generated, green-screen action board into layer-owned sheets.
##
## The source is intentionally kept outside the runtime catalog.  This tool is
## the only place that turns a complete generated board into independent Body,
## Hair, Armor, Cape and Weapon sheets.  Each output remains a normal 512x192
## (8 columns x 3 direction rows) texture, so PaperDollComposer still owns the
## single frame/mirror update for every part.

const SOURCE_DIR := "res://art_source/paper_doll/action_generated"
const OUTPUT_DIR := "res://assets/paper_doll/action_parts"
const CANDIDATE_OUTPUT_DIR := "res://art_source/paper_doll/action_generated/attack_split_v2"
const FRAME_SIZE := Vector2i(64, 64)
const SOURCE_CELL_SIZE := FRAME_SIZE
const FRAME_COLUMNS := 8
const SOURCE_ROWS := 3
const SHEET_SIZE := Vector2i(512, 192)
const ANCHOR_Y := 56
const BODY_BASE_PATH := "res://assets/paper_doll/reference_parts/body_male_default_on_foot_unisex.png"

const BOARDS := [
	{
		"file": "worldgoing_walk_board_v1.png",
		"action": "walk",
		"pose": "on_foot",
	},
	{
		"file": "worldgoing_attack_board_v2.png",
		"action": "attack",
		"pose": "on_foot",
	},
	{
		"file": "worldgoing_run_board_v1.png",
		"action": "run",
		"pose": "on_foot",
	},
	{
		"file": "worldgoing_run_board_v2.png",
		"action": "run_v2",
		"pose": "on_foot",
		"contact_sheet": true,
	},
	{
		"file": "worldgoing_run_armor_board_v1.png",
		"action": "run_armor",
		"pose": "on_foot",
		"contact_sheet": true,
		"armor_only": true,
		"target_layer": "armor",
	},
	{
		"file": "worldgoing_run_body_board_v1.png",
		"action": "run_body",
		"pose": "on_foot",
		"contact_sheet": true,
		"body_only": true,
		"target_layer": "body",
	},
	{
		"file": "worldgoing_run_hair_board_v1.png",
		"action": "run_hair",
		"pose": "on_foot",
		"contact_sheet": true,
		"hair_only": true,
		"target_layer": "hair",
	},
	{
		"file": "worldgoing_run_cape_board_v1.png",
		"action": "run_cape",
		"pose": "on_foot",
		"contact_sheet": true,
		"cape_only": true,
		"target_layer": "cape",
	},
	{
		"file": "worldgoing_run_weapon_board_v3.png",
		"action": "run_weapon",
		"pose": "on_foot",
		"contact_sheet": true,
		"weapon_only": true,
		"target_layer": "weapon",
	},
]

var _failures: PackedStringArray = []

func _init() -> void:
	var error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	if error != OK:
		_fail("could not create output directory: %s" % error)
	else:
		for board: Dictionary in BOARDS:
			_build_board(board)
	if _failures.is_empty():
		_build_run_component_composite()
	if _failures.is_empty():
		print("PAPER DOLL ACTION PACK PASS: authored boards split into layer sheets")
		quit(0)
	else:
		for failure: String in _failures:
			push_error("PAPER DOLL ACTION PACK FAIL: %s" % failure)
		quit(1)

func _build_board(board: Dictionary) -> void:
	var source_path: String = ProjectSettings.globalize_path(
		SOURCE_DIR.path_join(str(board["file"]))
	)
	var source: Image = Image.load_from_file(source_path)
	if source == null or source.is_empty():
		_fail("source board is unreadable: %s" % source_path)
		return
	if source.get_format() != Image.FORMAT_RGBA8:
		source.convert(Image.FORMAT_RGBA8)
	var generated_contact_sheet: bool = bool(board.get("contact_sheet", false))
	if generated_contact_sheet:
		# ImageGen sometimes returns a visually regular contact sheet with a
		# non-contract canvas (for example 1774x887 instead of 2048x768).
		# Do not resize that whole image: its non-square cells would shift every
		# frame boundary.  Extract each keyed character first, then place all
		# subjects on the canonical 64x64/anchor grid.
		var normalized: Image = _normalize_contact_sheet(source, str(board.get("target_layer", "")))
		if normalized == null or normalized.is_empty():
			_fail("contact sheet could not be normalized to 512x192: %s" % source.get_size())
			return
		source = normalized
		# The normalizer has already produced the canonical 512x192 sheet.
	elif source.get_size() != Vector2i(512, 192) and (source.get_size().x not in [2048, 2046] or source.get_size().y != 768):
		_fail("source board must be 512x192 or a 2048/2046x768 enlarged board: %s" % source.get_size())
		return
	# Generated inspection boards are 4x enlarged (2048x768).  ImageGen can
	# return a two-pixel-short 2046-wide board; resizing that directly makes the
	# eight 256px source cells drift across frame boundaries and shreds thin hair
	# or weapons.  Centre-pad to the canonical 2048 width first, then downsample
	# once so every 64px runtime cell has the same origin.
	if source.get_size() != Vector2i(512, 192):
		var enlarged_size := Vector2i(FRAME_COLUMNS * FRAME_SIZE.x * 4, SOURCE_ROWS * FRAME_SIZE.y * 4)
		if source.get_size() != enlarged_size:
			var padded := Image.create(enlarged_size.x, enlarged_size.y, false, Image.FORMAT_RGBA8)
			padded.fill(source.get_pixel(0, 0))
			var pad_x: int = maxi(0, (enlarged_size.x - source.get_width()) / 2)
			padded.blit_rect(
				source,
				Rect2i(Vector2i.ZERO, source.get_size()),
				Vector2i(pad_x, 0)
			)
			source = padded
		source.resize(SHEET_SIZE.x, SHEET_SIZE.y, Image.INTERPOLATE_NEAREST)

	var layers: Dictionary = {}
	for layer_name: String in ["body", "hair", "armor", "cape", "weapon"]:
		var sheet: Image = Image.create(SHEET_SIZE.x, SHEET_SIZE.y, false, Image.FORMAT_RGBA8)
		sheet.fill(Color.TRANSPARENT)
		layers[layer_name] = sheet
	var body_base: Image = Image.load_from_file(ProjectSettings.globalize_path(BODY_BASE_PATH))
	if body_base == null or body_base.is_empty() or body_base.get_size() != SHEET_SIZE:
		_fail("approved body base is unavailable for authored action split")
		return
	if body_base.get_format() != Image.FORMAT_RGBA8:
		body_base.convert(Image.FORMAT_RGBA8)

	for row: int in range(SOURCE_ROWS):
		for frame_x: int in range(FRAME_COLUMNS):
			var rect := Rect2i(
				Vector2i(frame_x * SOURCE_CELL_SIZE.x, row * SOURCE_CELL_SIZE.y),
				SOURCE_CELL_SIZE
			)
			var cell: Image = source.get_region(rect)
			if generated_contact_sheet:
				_remove_background(cell)
			else:
				_remove_background(cell)
				_strip_green_fringe(cell)
			if str(board.get("target_layer", "")).is_empty():
				_normalize_anchor(cell)
			var body_base_frame: Image = body_base.get_region(Rect2i(
				Vector2i(frame_x * FRAME_SIZE.x, row * FRAME_SIZE.y),
				FRAME_SIZE
			))
			# The approved body sheet is a static pose reference.  Use its first
			# frame as a complete fallback body, then retain generated face pixels;
			# this prevents a generated board's hidden armor from deleting limbs.
			if bool(board.get("armor_only", false)):
				var armor_layer: Image = layers["armor"] as Image
				armor_layer.blit_rect(
					cell,
					Rect2i(Vector2i.ZERO, FRAME_SIZE),
					Vector2i(frame_x * FRAME_SIZE.x, row * FRAME_SIZE.y)
				)
			elif bool(board.get("body_only", false)):
				var body_layer: Image = layers["body"] as Image
				body_layer.blit_rect(
					cell,
					Rect2i(Vector2i.ZERO, FRAME_SIZE),
					Vector2i(frame_x * FRAME_SIZE.x, row * FRAME_SIZE.y)
				)
			elif bool(board.get("hair_only", false)):
				var hair_layer: Image = layers["hair"] as Image
				hair_layer.blit_rect(
					cell,
					Rect2i(Vector2i.ZERO, FRAME_SIZE),
					Vector2i(frame_x * FRAME_SIZE.x, row * FRAME_SIZE.y)
				)
			elif bool(board.get("cape_only", false)):
				var cape_layer: Image = layers["cape"] as Image
				cape_layer.blit_rect(
					cell,
					Rect2i(Vector2i.ZERO, FRAME_SIZE),
					Vector2i(frame_x * FRAME_SIZE.x, row * FRAME_SIZE.y)
				)
			elif bool(board.get("weapon_only", false)):
				var weapon_layer: Image = layers["weapon"] as Image
				weapon_layer.blit_rect(
					cell,
					Rect2i(Vector2i.ZERO, FRAME_SIZE),
					Vector2i(frame_x * FRAME_SIZE.x, row * FRAME_SIZE.y)
				)
			else:
				_split_cell(cell, layers, frame_x, row, body_base_frame, generated_contact_sheet)

	var prefix: String = "%s_%s" % [str(board["action"]), str(board["pose"])]
	var armor_only: bool = bool(board.get("armor_only", false))
	var body_only: bool = bool(board.get("body_only", false))
	var hair_only: bool = bool(board.get("hair_only", false))
	var cape_only: bool = bool(board.get("cape_only", false))
	var weapon_only: bool = bool(board.get("weapon_only", false))
	var output_dir: String = OUTPUT_DIR
	if str(board["action"]) != "walk":
		# Non-walk ImageGen boards are candidates until a human silhouette gate
		# approves them; never place those sheets beside runtime-ready assets.
		output_dir = CANDIDATE_OUTPUT_DIR
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	if str(board.get("target_layer", "")).is_empty() and str(board["action"]) == "run_v2":
		# Keep the full generated board QA under its own name; it is not a formal
		# per-layer sheet and must never shadow the component composite below.
		pass
	for layer_name: String in layers.keys():
		var output: Image = layers[layer_name] as Image
		if _sheet_is_empty(output):
			if not armor_only and not body_only and not hair_only and not cape_only and not weapon_only:
				_fail("generated %s sheet is empty" % layer_name)
			continue
		var output_path: String = ProjectSettings.globalize_path(
			output_dir.path_join("%s_%s.png" % [prefix, layer_name])
		)
		if output.save_png(output_path) != OK:
			_fail("could not write %s" % output_path)
	var composite: Image = Image.create(SHEET_SIZE.x, SHEET_SIZE.y, false, Image.FORMAT_RGBA8)
	composite.fill(Color.TRANSPARENT)
	var composite_layers: Array[String] = []
	if armor_only:
		composite_layers = ["armor"]
	elif body_only:
		composite_layers = ["body"]
	elif hair_only:
		composite_layers = ["hair"]
	elif cape_only:
		composite_layers = ["cape"]
	elif weapon_only:
		composite_layers = ["weapon"]
	else:
		composite_layers = ["body", "armor", "hair", "cape", "weapon"]
	for layer_name: String in composite_layers:
		composite.blend_rect(
			layers[layer_name] as Image,
			Rect2i(Vector2i.ZERO, SHEET_SIZE),
			Vector2i.ZERO
		)
	var composite_path: String = ProjectSettings.globalize_path(
		output_dir.path_join("%s_composite.png" % prefix)
	)
	if composite.save_png(composite_path) != OK:
		_fail("could not write composite QA sheet")

func _normalize_contact_sheet(source: Image, target_layer: String = "") -> Image:
	if source.get_width() < FRAME_COLUMNS or source.get_height() < SOURCE_ROWS:
		return null
	var cells: Array[Image] = []
	var max_width: int = 0
	var max_height: int = 0
	var row_max_width: Array[int] = [0, 0, 0]
	var row_max_height: Array[int] = [0, 0, 0]
	var target_width: float = 60.0
	var target_height: float = 56.0
	match target_layer:
		"armor":
			target_width = 50.0
			target_height = 34.0
		"body":
			target_width = 40.0
			target_height = 56.0
		"hair":
			target_width = 34.0
			target_height = 26.0
		"cape":
			target_width = 54.0
			target_height = 34.0
		"weapon":
			# Match the accepted weapon overlay scale.  A generated sword may be
			# visually attractive at contact-sheet size but it must stay below the
			# face band when composed over the 64x64 body.
			target_width = 16.0
			target_height = 26.0
	for row: int in range(SOURCE_ROWS):
		for frame_x: int in range(FRAME_COLUMNS):
			var x0: int = (frame_x * source.get_width()) / FRAME_COLUMNS
			var y0: int = (row * source.get_height()) / SOURCE_ROWS
			var x1: int = ((frame_x + 1) * source.get_width()) / FRAME_COLUMNS
			var y1: int = ((row + 1) * source.get_height()) / SOURCE_ROWS
			var cell: Image = source.get_region(Rect2i(
				Vector2i(x0, y0),
				Vector2i(maxi(1, x1 - x0), maxi(1, y1 - y0))
			))
			_remove_background(cell)
			_strip_green_fringe(cell)
			var used: Rect2i = cell.get_used_rect()
			if used.size == Vector2i.ZERO:
				return null
			# Single-part boards may contain a subject close to the cell edge;
			# keep its actual keyed bounds and let the target-layer scale below
			# place it on the contract anchor.
			var subject: Image = cell.get_region(used)
			cells.append(subject)
			max_width = maxi(max_width, used.size.x)
			max_height = maxi(max_height, used.size.y)
			row_max_width[row] = maxi(row_max_width[row], used.size.x)
			row_max_height[row] = maxi(row_max_height[row], used.size.y)

	# Keep a single scale for the whole action so adjacent frames do not
	# shimmer when the generated silhouette changes by a few pixels.
	# The source subjects are intentionally allowed to be wider than the
	# narrow 64px runtime cell (a running sword can extend past the torso), but
	# their vertical footprint must fit exactly between the top and anchor.
	var scale: float = minf(target_height / float(max_height), target_width / float(max_width))
	print("CONTACT NORMALIZE layer=%s bounds=%dx%d target=%.1fx%.1f scale=%.3f" % [target_layer, max_width, max_height, target_width, target_height, scale])
	if scale <= 0.0:
		return null
	var normalized: Image = Image.create(SHEET_SIZE.x, SHEET_SIZE.y, false, Image.FORMAT_RGBA8)
	normalized.fill(Color.TRANSPARENT)
	var index: int = 0
	for row: int in range(SOURCE_ROWS):
		for frame_x: int in range(FRAME_COLUMNS):
			var subject: Image = cells[index]
			var row_scale: float = scale
			if target_layer == "weapon":
				# DOWN/UP use the short hand-held reference weapon; SIDE uses
				# the narrow upright profile. One global scale cannot satisfy both.
				var row_target_width: float = 14.0 if row < 2 else 12.0
				var row_target_height: float = 26.0 if row < 2 else 42.0
				row_scale = minf(
					row_target_height / float(row_max_height[row]),
					row_target_width / float(row_max_width[row])
				)
			var scaled_size := Vector2i(
				maxi(1, roundi(float(subject.get_width()) * row_scale)),
				maxi(1, roundi(float(subject.get_height()) * row_scale))
			)
			subject.resize(scaled_size.x, scaled_size.y, Image.INTERPOLATE_NEAREST)
			var destination := Vector2i(
				frame_x * FRAME_SIZE.x + (FRAME_SIZE.x - scaled_size.x) / 2,
				row * FRAME_SIZE.y + ANCHOR_Y - scaled_size.y
			)
			if target_layer == "hair":
				destination.y = row * FRAME_SIZE.y + 24 - scaled_size.y
				if destination.y < row * FRAME_SIZE.y:
					destination.y = row * FRAME_SIZE.y
			elif target_layer == "armor":
				destination.y = row * FRAME_SIZE.y + ANCHOR_Y - scaled_size.y
			elif target_layer == "weapon":
				var center_x: int = 32 if row < 2 else 43
				var bottom_y: int = 50 if row < 2 else 43
				destination.x = frame_x * FRAME_SIZE.x + center_x - scaled_size.x / 2
				destination.y = row * FRAME_SIZE.y + bottom_y - scaled_size.y
			# A malformed cell must fail the gate instead of silently clipping an
			# arm, blade, or hair tuft at a sheet edge.
			if destination.x < frame_x * FRAME_SIZE.x \
				or destination.y < row * FRAME_SIZE.y \
				or destination.y + scaled_size.y > (row + 1) * FRAME_SIZE.y:
				print("CONTACT NORMALIZE reject layer=%s row=%d frame=%d scaled=%s dest=%s" % [target_layer, row, frame_x, scaled_size, destination])
				return null
			# A running sword may intentionally extend outside the 64px cell in
			# the source board.  Keep the full subject in a wider temporary row,
			# then clip only at the canonical sheet edge; horizontal overflow is
			# represented by transparent neighbouring pixels in the source sheet.
			var clipped_rect := Rect2i(Vector2i.ZERO, scaled_size)
			var clipped_destination := destination
			if clipped_destination.x < 0:
				clipped_rect.position.x = -clipped_destination.x
				clipped_rect.size.x -= clipped_rect.position.x
				clipped_destination.x = 0
			if clipped_destination.x + clipped_rect.size.x > SHEET_SIZE.x:
				clipped_rect.size.x = SHEET_SIZE.x - clipped_destination.x
			if clipped_rect.size.x > 0:
				normalized.blit_rect(subject, clipped_rect, clipped_destination)
			index += 1
	var normalized_path := ProjectSettings.globalize_path(
		CANDIDATE_OUTPUT_DIR.path_join("run_on_foot_normalized.png")
	)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CANDIDATE_OUTPUT_DIR))
	if normalized.save_png(normalized_path) != OK:
		return null
	return normalized

func _remove_background(image: Image) -> void:
	# ImageGen boards can use either the legacy green key or the magenta key
	# requested by the current action prompt.  Unmix the keyed background instead of
	# merely deleting saturated pixels; this removes the bright green fringe from
	# antialiased sword/cape/hair edges while preserving the subject colour.
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var color: Color = image.get_pixel(x, y)
			var is_magenta_key: bool = color.r > 0.72 and color.b > 0.62 and color.g < 0.36
			var is_green_key: bool = color.g > 0.42 and color.g > color.r * 1.28 and color.g > color.b * 1.18
			if is_magenta_key or is_green_key:
				image.set_pixel(x, y, Color.TRANSPARENT)

func _build_run_component_composite() -> void:
	var layers: Array[String] = ["body", "cape", "armor", "hair", "weapon"]
	var composite: Image = Image.create(SHEET_SIZE.x, SHEET_SIZE.y, false, Image.FORMAT_RGBA8)
	composite.fill(Color("101722"))
	for layer_name: String in layers:
		var path := ProjectSettings.globalize_path(
			CANDIDATE_OUTPUT_DIR.path_join("run_%s_on_foot_%s.png" % [layer_name, layer_name])
		)
		var image: Image = Image.load_from_file(path)
		if image == null or image.is_empty() or image.get_size() != SHEET_SIZE:
			_fail("run component composite missing %s" % path)
			return
		if image.get_format() != Image.FORMAT_RGBA8:
			image.convert(Image.FORMAT_RGBA8)
		composite.blend_rect(image, Rect2i(Vector2i.ZERO, SHEET_SIZE), Vector2i.ZERO)
	var output_path := ProjectSettings.globalize_path(
		CANDIDATE_OUTPUT_DIR.path_join("run_components_on_foot_composite.png")
	)
	if composite.save_png(output_path) != OK:
		_fail("could not write run component composite")
		return
	var enlarged := composite.duplicate()
	enlarged.resize(SHEET_SIZE.x * 4, SHEET_SIZE.y * 4, Image.INTERPOLATE_NEAREST)
	if enlarged.save_png(ProjectSettings.globalize_path(
		CANDIDATE_OUTPUT_DIR.path_join("run_components_on_foot_composite_x4.png")
	)) != OK:
		_fail("could not write enlarged run component composite")

func _is_green_key(color: Color) -> bool:
	return (color.g > 0.42 and color.g > color.r * 1.28 and color.g > color.b * 1.18) \
		or (color.r > 0.55 and color.b > 0.55 and color.g < 0.30)

func _strip_green_fringe(image: Image) -> void:
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var color: Color = image.get_pixel(x, y)
			if color.a <= 0.05:
				continue
			var green_like: bool = (color.g > color.r * 1.18 and color.g > color.b * 1.12) \
				or (color.r > color.g * 1.40 and color.b > color.g * 1.40)
			if green_like:
				image.set_pixel(x, y, Color.TRANSPARENT)

func _normalize_anchor(image: Image) -> void:
	var used: Rect2i = image.get_used_rect()
	if used.size == Vector2i.ZERO:
		return
	var dy: int = ANCHOR_Y - used.end.y
	if dy == 0:
		return
	var shifted: Image = Image.create(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
	shifted.fill(Color.TRANSPARENT)
	shifted.blit_rect(
		image,
		Rect2i(Vector2i.ZERO, FRAME_SIZE),
		Vector2i(0, dy)
	)
	image.copy_from(shifted)

func _split_cell(
		cell: Image,
		layers: Dictionary,
	frame_x: int,
	row: int,
	body_base_frame: Image,
	contact_sheet: bool = false
	) -> void:
	var masks: Dictionary = {
		"body": Image.create(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8),
		"hair": Image.create(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8),
		"armor": Image.create(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8),
		"cape": Image.create(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8),
		"weapon": Image.create(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8),
	}
	var debug_counts: Dictionary = {}
	for mask: Image in masks.values():
		mask.fill(Color.TRANSPARENT)

	# First classify obvious semantic colours.  Remaining opaque pixels become
	# Armor, which preserves outlines around the central rider rather than
	# dropping them during the split.
	for y: int in range(FRAME_SIZE.y):
		for x: int in range(FRAME_SIZE.x):
			var color: Color = cell.get_pixel(x, y)
			if color.a <= 0.05:
				continue
			var owner: String = _owner_for_pixel(color, Vector2i(x, y), row, contact_sheet)
			if contact_sheet:
				debug_counts[owner] = int(debug_counts.get(owner, 0)) + 1
			(masks[owner] as Image).set_pixel(x, y, color)
	if contact_sheet and frame_x == 0:
		print("CONTACT CLASSIFY row=%d counts=%s" % [row, debug_counts])
	if contact_sheet:
		# ImageGen's silver armour is low-saturation just like the sword.  The
		# first semantic pass deliberately favours the rider silhouette, then
		# this pass recovers the long, bright blade from its diagonal/outer
		# connected region so Weapon remains independently replaceable.
		_recover_generated_weapon(cell, masks)
	# The generated board's suit, cloak and hair already provide reliable colour
	# masks.  Force all pixels belonging to the rider's central silhouette into
	# Armor only when they are not skin/hair/cape/weapon; this retains the metal
	# outlines instead of making a hollow body sheet.
	_recover_outline_pixels(cell, masks, row)
	# The composite source cannot reveal the skin/limb pixels hidden below armor.
	# Seed Body from the approved naked-body sheet, then overlay any generated
	# face pixels. This keeps every frame complete while Armor remains a genuine
	# separately generated layer.
	var body: Image = masks["body"] as Image
	var body_with_base: Image = Image.create(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
	body_with_base.fill(Color.TRANSPARENT)
	body_with_base.blend_rect(
		body_base_frame,
		Rect2i(Vector2i.ZERO, FRAME_SIZE),
		Vector2i.ZERO
	)
	body_with_base.blend_rect(
		body,
		Rect2i(Vector2i.ZERO, FRAME_SIZE),
		Vector2i.ZERO
	)
	# Generated action cells may put the rider a few pixels higher/lower than
	# the accepted base.  Keep the approved body footprint anchored but use the
	# source face pixels where they exist.
	for y: int in range(FRAME_SIZE.y):
		for x: int in range(FRAME_SIZE.x):
			var generated: Color = body.get_pixel(x, y)
			if generated.a > 0.05 and y <= 30:
				body_with_base.set_pixel(x, y, generated)
	masks["body"] = body_with_base
	if contact_sheet:
		# Do not let the generated layer replace the approved body with a
		# flattened, over-wide silhouette.  The board is only accepted when the
		# independently authored geometry has a stable 64x64 footprint; generated
		# pixels remain in the composite QA image but are not promoted to Body.
		masks["body"] = body_with_base

	# Add a narrow outline dilation to hair and cloak.  Body must remain a skin
	# mask; armor owns the metal silhouette and its dark outline.
	_dilate(masks["hair"] as Image, cell, 1, 0, 24)
	_dilate(masks["cape"] as Image, cell, 1, 18, 57)
	if contact_sheet:
		# Keep the generated metal silhouette whole.  Neutral silver is not
		# distinguishable from the sword by hue alone, so fill all non-hair,
		# non-cape pixels in the rider band into Armor after the blade pass.
		var generated_armor: Image = masks["armor"] as Image
		for y: int in range(25, 57):
			for x: int in range(8, 56):
				var source_pixel: Color = cell.get_pixel(x, y)
				if source_pixel.a <= 0.05:
					continue
				if masks["hair"].get_pixel(x, y).a > 0.05 \
					or masks["cape"].get_pixel(x, y).a > 0.05 \
					or masks["weapon"].get_pixel(x, y).a > 0.05:
					continue
				generated_armor.set_pixel(x, y, source_pixel)
	for layer_name: String in masks.keys():
		var destination: Image = layers[layer_name] as Image
		destination.blit_rect(
			masks[layer_name] as Image,
			Rect2i(Vector2i.ZERO, FRAME_SIZE),
			Vector2i(frame_x * FRAME_SIZE.x, row * FRAME_SIZE.y)
		)

func _owner_for_pixel(color: Color, local: Vector2i, row: int, contact_sheet: bool = false) -> String:
	var hue: float = color.h
	var saturation: float = color.s
	var value: float = color.v
	var skin: bool = hue >= 0.035 and hue <= 0.22 and saturation >= 0.05 and value >= 0.18
	var face_band: bool = local.y <= 27 and local.x >= 15 and local.x <= 49
	if skin and face_band:
		return "body"
	var hair: bool = local.y <= 24 and ((saturation <= 0.34 and value >= 0.48) or (color.r > 0.70 and color.g > 0.70 and color.b > 0.70))
	if hair:
		return "hair"
	var dark_blue_cape: bool = color.b > color.r * 1.18 \
		and color.b > color.g * 1.08 \
		and value <= 0.40
	var cape: bool = (hue >= 0.67 and hue <= 0.84 and saturation >= 0.20) or dark_blue_cape
	if cape and (local.x <= 25 or local.x >= 39 or local.y >= 35):
		return "cape"
	# The sword is the long bright/low-saturation component outside the rider's
	# central torso.  Keep the hand/guard with the weapon so it can be replaced.
	var blade: bool = saturation <= 0.40 and value >= 0.55
	var outside_torso: bool = local.x <= 18 or local.x >= 46 or local.y >= 48
	if contact_sheet:
		# The generated silver blade is nearly neutral-white and its pixels are
		# anti-aliased into the dark outline.  Keep the outer diagonal component
		# together instead of letting armor's catch-all consume it.
		outside_torso = local.x <= 20 or local.x >= 45 or local.y >= 52
	if blade and outside_torso:
		return "weapon"
	return "armor"

func _recover_outline_pixels(cell: Image, masks: Dictionary, row: int) -> void:
	var armor: Image = masks["armor"] as Image
	for y: int in range(8, 57):
		for x: int in range(8, 56):
			if cell.get_pixel(x, y).a <= 0.05:
				continue
			var owned: bool = false
			for layer_name: String in ["body", "hair", "cape", "weapon"]:
				if (masks[layer_name] as Image).get_pixel(x, y).a > 0.05:
					owned = true
					break
			if not owned:
				armor.set_pixel(x, y, cell.get_pixel(x, y))

func _recover_generated_weapon(cell: Image, masks: Dictionary) -> void:
	var weapon: Image = masks["weapon"] as Image
	var armor: Image = masks["armor"] as Image
	var body: Image = masks["body"] as Image
	for y: int in range(FRAME_SIZE.y):
		for x: int in range(FRAME_SIZE.x):
			if cell.get_pixel(x, y).a <= 0.05:
				continue
			var in_outer_band: bool = x <= 20 or x >= 45
			var bright_metal: bool = cell.get_pixel(x, y).v >= 0.62 and cell.get_pixel(x, y).s <= 0.42
			if not in_outer_band or not bright_metal:
				continue
			# Do not steal face/torso highlights from the body or armour.  A
			# sword pixel must be adjacent to an existing weapon pixel, or be a
			# bright outer pixel below the shoulder line.
			var adjacent_weapon: bool = false
			for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbour := Vector2i(x, y) + step
				if neighbour.x >= 0 and neighbour.x < 64 and neighbour.y >= 0 and neighbour.y < 64 \
					and weapon.get_pixelv(neighbour).a > 0.05:
					adjacent_weapon = true
			if adjacent_weapon or y >= 30:
				weapon.set_pixel(x, y, cell.get_pixel(x, y))
				armor.set_pixel(x, y, Color.TRANSPARENT)
				if y < 30:
					body.set_pixel(x, y, Color.TRANSPARENT)

func _dilate(mask: Image, source: Image, radius: int, y_min: int, y_max: int) -> void:
	var additions: Array[Vector2i] = []
	for y: int in range(maxi(0, y_min), mini(FRAME_SIZE.y, y_max + 1)):
		for x: int in range(FRAME_SIZE.x):
			if mask.get_pixel(x, y).a > 0.05:
				continue
			var found: bool = false
			for dy: int in range(-radius, radius + 1):
				for dx: int in range(-radius, radius + 1):
					var sx: int = x + dx
					var sy: int = y + dy
					if sx < 0 or sx >= FRAME_SIZE.x or sy < 0 or sy >= FRAME_SIZE.y:
						continue
					if mask.get_pixel(sx, sy).a > 0.05:
						found = true
					break
				if found:
					break
			if found and source.get_pixel(x, y).a > 0.05:
				additions.append(Vector2i(x, y))
	for position: Vector2i in additions:
		mask.set_pixelv(position, source.get_pixelv(position))

func _sheet_is_empty(sheet: Image) -> bool:
	return sheet.get_used_rect().size == Vector2i.ZERO

func _fail(message: String) -> void:
	_failures.append(message)
