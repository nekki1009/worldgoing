extends SceneTree

## Converts the ChatGPT reference boards into the runtime contract used by the
## existing PaperDollCatalog.  The boards are source art; this script is only
## deterministic packing (keyed source -> trimmed cell -> nearest 64x64 frame).

const SOURCE_DIR := "res://art_source/paper_doll/reference_generated"
const OUTPUT_DIR := "res://assets/paper_doll/reference_parts"
## Provenance gate: the generated boards must never be rebuilt in a checkout
## that no longer contains the project art used as their visual reference.
## ImageGen creates the boards; this tool only performs deterministic packing.
const SOURCE_REFERENCE_FILES := [
	"res://assets/doll/ChatGPT Image 2026年8月10日 下午05_44_46.png",
	"res://assets/doll/ChatGPT Image 2026年8月10日 下午07_15_14.png",
	"res://assets/doll/ChatGPT Image 2026年8月10日 下午07_15_19.png",
	"res://assets/doll/ChatGPT Image 2026年8月10日 下午07_22_46.png",
	"res://assets/doll/ChatGPT Image 2026年8月10日 下午07_34_58.png",
	"res://assets/doll/Gemini_Generated_Image_gq5s2dgq5s2dgq5s.png",
]
const FRAME_SIZE := Vector2i(64, 64)
const SHEET_SIZE := Vector2i(512, 192)
const MIN_COMPONENT_PIXELS := 128
const FRAME_MOTION: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 0),
	Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 0),
]
const FOOT_X_BOUNDS := [240, 540, 825, 1100]

func _init() -> void:
	var err: Error = _build()
	if err != OK:
		push_error("Reference paper-doll pack failed: %s" % error_string(err))
		quit(1)
		return
	print("Reference paper-doll runtime pack exported")
	quit()

func _build() -> Error:
	if not _source_references_present():
		return ERR_FILE_NOT_FOUND
	var foot_board: Image = _load_board("worldgoing_reference_board_v1.png")
	var equipment_board: Image = _load_board("worldgoing_equipment_reference_board_v1.png")
	var mount_board: Image = _load_board("worldgoing_mount_parts_reference_board_v1.png")
	if foot_board == null or equipment_board == null or mount_board == null:
		return ERR_FILE_NOT_FOUND

	var output_path: String = ProjectSettings.globalize_path(OUTPUT_DIR)
	var err: Error = DirAccess.make_dir_recursive_absolute(output_path)
	if err != OK:
		return err

	# Base bodies use the first reference board's male/female rows.
	err = _write_foot_sheet(foot_board, 0, Vector2i(54, 58), _center_anchors(56),
		"body_male_default_on_foot_unisex.png")
	if err != OK:
		return err
	err = _write_foot_sheet(foot_board, 1, Vector2i(54, 58), _center_anchors(56),
		"body_female_default_on_foot_unisex.png")
	if err != OK:
		return err
	err = _write_foot_sheet(foot_board, 0, Vector2i(42, 40), _center_anchors(44),
		"body_male_default_mounted_unisex.png")
	if err != OK:
		return err
	err = _write_foot_sheet(foot_board, 1, Vector2i(42, 40), _center_anchors(44),
		"body_female_default_mounted_unisex.png")
	if err != OK:
		return err

	# The equipment board rows are hair, helmet, armor, cape, weapon, shield,
	# and horse barding.  Each item is isolated in its own three-view row.
	err = _write_equipment_pair(equipment_board, 0, Vector2i(38, 30), 34,
		"hair_male_default", output_path)
	if err != OK:
		return err
	err = _copy_pair(output_path, "hair_male_default", "hair_female_default")
	if err != OK:
		return err
	err = _align_hair_to_body(output_path)
	if err != OK:
		return err
	err = _write_equipment_pair(equipment_board, 1, Vector2i(38, 30), 34,
		"artgate1_helmet", output_path)
	if err != OK:
		return err
	# A helmet is a head-slot replacement, not a small sticker positioned near
	# the head.  Align its crown to the generated Body head union before any
	# other layer is packed.  This closes the exact failure that bounding-box
	# checks missed: Body/Hair pixels peeking above the helmet crown.
	err = _align_helmet_to_body(output_path)
	if err != OK:
		return err
	# Armor is bottom-anchored like the body, but its source shoulder plates are
	# materially wider/taller than the reference body at the previous 56x54 fit.
	# Keep the shared (32,56) anchor and reduce only the armor fit so the top
	# silhouette stays below the hair crown in DOWN/SIDE views.
	err = _write_equipment_pair(equipment_board, 2, Vector2i(42, 40), 56,
		"artgate1_armor", output_path)
	if err != OK:
		return err
	# The armor source contains a collar band that intersects the body's face
	# pixels after fitting.  Remove the head spill and disconnected source
	# islands after fitting; both operations keep the common body skeleton as
	# the alignment reference.
	err = _clear_armor_face_overlap(output_path)
	if err != OK:
		return err
	err = _align_armor_to_body(output_path)
	if err != OK:
		return err
	# The body-silhouette clip can split a source-row remnant at a frame edge;
	# clean each 64x64 cell once more after that operation so the runtime sheet
	# contains exactly one authored armor component per direction/frame.
	err = _clean_equipment_pair(output_path, "artgate1_armor", 2)
	if err != OK:
		return err
	err = _fill_armor_body_coverage(output_path)
	if err != OK:
		return err
	err = _write_equipment_pair(equipment_board, 3, Vector2i(56, 56), 56,
		"artgate1_cape", output_path)
	if err != OK:
		return err
	err = _align_cape_to_shoulders(output_path)
	if err != OK:
		return err
	err = _write_equipment_pair(equipment_board, 4, Vector2i(16, 52), 56,
		"artgate1_weapon", output_path)
	if err != OK:
		return err
	err = _write_equipment_pair(equipment_board, 5, Vector2i(30, 36), 56,
		"artgate1_shield", output_path)
	if err != OK:
		return err
	err = _write_mounted_only(equipment_board, 6, Vector2i(58, 44), 56,
		"artgate1_barding", output_path)
	if err != OK:
		return err
	# Keep a coherent full-horse variant from the same reference cell.  The
	# separate tail/head/barding files remain available for layer tests, but the
	# default preview can consume this single source-consistent silhouette when
	# the generated part anchors do not agree.
	err = _write_full_mount_sheet(equipment_board, output_path)
	if err != OK:
		return err

	# Mount board is explicitly separated into tail/body/head rows, so the
	# Composer can retain its existing z-order contract without duplicating a
	# full horse in three different layers.
	err = _write_mount_part(mount_board, 0, Vector2i(28, 34),
		[Vector2i(20, 55), Vector2i(40, 55), Vector2i(11, 55)],
		"artgate1_horse_tail_mounted_unisex.png", output_path)
	if err != OK:
		return err
	err = _write_mount_part(mount_board, 1, Vector2i(58, 38),
		_center_anchors(56), "artgate1_horse_body_mounted_unisex.png", output_path)
	if err != OK:
		return err
	err = _write_mount_part(mount_board, 2, Vector2i(36, 38),
		# Keep the rider's head above the frontal horse head, and move the
		# side-facing horse muzzle clear of the rider's head.  These are source
		# anchors inside the shared 64x64 frame; z-order remains unchanged.
		[Vector2i(32, 53), Vector2i(32, 53), Vector2i(55, 37)],
		"artgate1_horse_head_mounted_unisex.png", output_path)
	if err != OK:
		return err
	# MountBarding and MountHead are horse-only silhouettes.  Their mandated
	# z-order is above the rider, so the horse sheets must carry a transparent
	# rider-clearance hole; otherwise a full horse cloth/neck hides Body and the
	# preview degenerates into a floating head above horse legs.  This is a
	# deterministic source-pack operation, not a runtime Node or state change.
	return _clear_mount_rider_overlap(output_path)

func _source_references_present() -> bool:
	for relative_path: String in SOURCE_REFERENCE_FILES:
		var absolute_path: String = ProjectSettings.globalize_path(relative_path)
		if not FileAccess.file_exists(absolute_path):
			push_error("Missing project art reference: %s" % relative_path)
			return false
	return true

func _write_equipment_pair(
		board: Image,
		row: int,
		foot_fit: Vector2i,
		foot_bottom: int,
		base_name: String,
		output_path: String
) -> Error:
	# Keep the complete armor crop.  Trimming the bottom here cuts the boot
	# pixels away before the shared (32,56) anchor is applied, which makes the
	# armor stop above the body's feet.  Shoulder spill is removed after fitting.
	var clip_bottom: float = 1.0
	# Mounted rider body is fitted with its feet at y=44. Hair and helmet are
	# head-anchored assets, however; using the rider-foot anchor put both parts
	# over the torso. Keep the other equipment on the rider-foot anchor.
	var mounted_bottom: int = 22 if row <= 1 else 44
	# Hair is a single head silhouette.  A 16-pixel threshold leaves the small
	# dark strip from the next source row attached to the crop; keep only real
	# head pixels by using a stricter threshold.  Helmet remains permissive
	# because its grille/ear guards can be intentionally disconnected.
	var cleanup_min_pixels: int = 64 if row == 0 else (16 if row == 1 else 0)
	var clear_cape_head_spill: bool = row == 3
	var foot_anchors: Array[Vector2i] = _center_anchors(foot_bottom)
	var mounted_anchors: Array[Vector2i] = _center_anchors(mounted_bottom)
	# The side-view weapon/shield references are held beside the rider, not
	# through the face centerline.  DOWN/UP remain centered; LEFT is produced by
	# the runtime horizontal mirror of the RIGHT source row.
	if row == 4:
		foot_anchors[2] += Vector2i(10, 0)
		mounted_anchors[2] += Vector2i(10, 0)
	elif row == 5:
		# Shield is the rear hand for RIGHT and the front hand after the
		# runtime LEFT mirror.  Keep a clear one-pixel gap from the body
		# centreline in both mirrored views.
		foot_anchors[2] -= Vector2i(11, 0)
		mounted_anchors[2] -= Vector2i(11, 0)
	var err: Error = _write_sheet(board, 3, 7, row, foot_fit, foot_anchors,
		"%s_on_foot_unisex.png" % base_name, output_path, clip_bottom, cleanup_min_pixels,
		clear_cape_head_spill, row, true)
	if err != OK:
		return err
	err = _write_sheet(board, 3, 7, row, _mounted_fit(foot_fit), mounted_anchors,
		"%s_mounted_unisex.png" % base_name, output_path, clip_bottom, cleanup_min_pixels,
		clear_cape_head_spill, row, true)
	if err != OK:
		return err
	# Equipment rows in the source board are adjacent.  The crop/scale step can
	# therefore retain a disconnected fragment from the next row (for example a
	# sword pommel below a cape, or horse barding below a shield).  Those pixels
	# are not a valid part of the item and must be removed before the texture is
	# handed to the runtime catalog.  Clean both pose sheets while they are still
	# ordinary Images; Composer remains a texture consumer only.
	return _clean_equipment_pair(output_path, base_name, row)

func _clean_equipment_pair(output_path: String, base_name: String, row: int) -> Error:
	if row == 0 or row > 5:
		return OK
	for pose: String in ["on_foot", "mounted"]:
		var path: String = output_path.path_join(
			"%s_%s_unisex.png" % [base_name, pose]
		)
		var sheet: Image = Image.load_from_file(path)
		if sheet == null or sheet.is_empty():
			return ERR_FILE_CORRUPT
		for direction: int in range(3):
			for frame_x: int in range(8):
				var origin := Vector2i(frame_x * FRAME_SIZE.x, direction * FRAME_SIZE.y)
				var frame: Image = sheet.get_region(Rect2i(origin, FRAME_SIZE))
				if row == 1 or row == 2 or row == 4:
					# Helmet and armor crops can include a large, disconnected
					# slice of the following source row; Weapon has the same
					# problem with the following shield row.  Each authored
					# silhouette is the largest remaining island.
					_keep_largest_component(frame)
				elif row == 3:
						# Cape UP intentionally has separate purple side/center
						# pieces after the head opening, so largest-component cleanup
						# would destroy valid art.  Remove only components that have
						# no purple cape pixels (the gold next-row pommel).
						_remove_non_cape_components(frame)
				elif row == 5:
						# Shield is deliberately compact and its lower band is always
						# occupied by the next source row.  Keep the authored shield
						# above the pose-specific cutoff and clear the foreign pixels.
						_clear_shield_bottom_spill(frame, pose == "mounted", direction)
						# Antialiased source-row remnants can sit one or two pixels
						# above the cutoff.  After the band cut the authored shield is
						# the largest remaining island in every direction.
						_keep_largest_component(frame)
				sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, FRAME_SIZE), origin)
		if sheet.save_png(path) != OK:
			return ERR_CANT_CREATE
	return OK

func _clear_shield_bottom_spill(frame: Image, mounted: bool, direction: int) -> void:
	# Measured from the packed source silhouettes.  The cut is below the real
	# shield in every direction and above the horse/barding fragment that follows
	# it in the reference board.  Keep this explicit per pose so a future art
	# refresh cannot silently move a shield into a different anchor contract.
	var on_foot_cutoffs: Array[int] = [44, 46, 46]
	var mounted_cutoffs: Array[int] = [35, 37, 37]
	var cutoff: int = (mounted_cutoffs if mounted else on_foot_cutoffs)[direction]
	for y: int in range(cutoff, FRAME_SIZE.y):
		for x: int in range(FRAME_SIZE.x):
			frame.set_pixel(x, y, Color.TRANSPARENT)

func _remove_non_cape_components(frame: Image) -> void:
	for component: Array in _collect_components(frame):
		var purple_pixels: int = 0
		for position: Vector2i in component:
			var color: Color = frame.get_pixelv(position)
			# Purple cape pixels occupy the 0.62..0.86 hue band.  Black
			# outlines are intentionally ignored here; a valid outline remains
			# attached to the purple component.  The leaked gold handle has no
			# purple pixels and is consequently removed as one island.
			if color.a > 0.05 and color.s > 0.15 and color.v > 0.10 \
					and color.h >= 0.62 and color.h <= 0.86:
				purple_pixels += 1
		if purple_pixels == 0:
			for position: Vector2i in component:
				frame.set_pixelv(position, Color.TRANSPARENT)

func _write_foot_sheet(
		board: Image,
		source_row: int,
		fit_size: Vector2i,
		anchors: Array[Vector2i],
		file_name: String
) -> Error:
	var sheet: Image = Image.create(SHEET_SIZE.x, SHEET_SIZE.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.TRANSPARENT)
	for direction: int in range(3):
		# The generated reference board has occasional previous-row feet at the
		# top of the female crop.  A body frame is one connected silhouette, so
		# discard every component except its largest one before fitting.
		var body_cell: Image = _foot_cell(board, source_row, direction)
		_keep_largest_component(body_cell)
		var source: Image = _trim(body_cell)
		if source == null or source.is_empty():
			return ERR_FILE_CORRUPT
		var fitted: Image = _fit(source, fit_size)
		# The generated reference board's SIDE cell is authored looking left.
		# Runtime SIDE is a canonical RIGHT row; LEFT is produced exactly once by
		# Sprite2D.flip_h.  Normalize every body row at pack time so the rider,
		# equipment, and the full-horse source share the same direction contract.
		if direction == PaperDollLayerVisual.Facing.RIGHT:
			fitted.flip_x()
		for frame_x: int in range(8):
			var position: Vector2i = anchors[direction] \
				+ FRAME_MOTION[frame_x] \
				- Vector2i(int(fitted.get_width() / 2), fitted.get_height())
			_blit_frame(sheet, fitted, Vector2i(frame_x * FRAME_SIZE.x, direction * FRAME_SIZE.y), position)
	var absolute_path: String = ProjectSettings.globalize_path(OUTPUT_DIR).path_join(file_name)
	return sheet.save_png(absolute_path)

func _write_mounted_only(
		board: Image,
		row: int,
		fit_size: Vector2i,
		bottom: int,
		base_name: String,
		output_path: String
) -> Error:
	return _write_sheet(board, 3, 7, row, fit_size, _center_anchors(bottom),
		"%s_mounted_unisex.png" % base_name, output_path, 1.0, 0, false, row, true)

func _write_full_mount_sheet(board: Image, output_path: String) -> Error:
	# The complete horse at the bottom of the equipment board is wider than
	# the board's three nominal columns: the side-facing head crosses the
	# column boundary, and the front/back heads begin just above the last grid
	# row.  A normal _cell(board, 3, 7, ...) crop therefore amputates the head.
	# Use measured source rectangles for the one coherent horse silhouette,
	# then fit each view independently while preserving its own perspective.
	var source_rects: Array[Rect2i] = [
		Rect2i(116, 1218, 224, 284),
		Rect2i(386, 1218, 214, 284),
		Rect2i(598, 1210, 356, 292),
	]
	var fit_sizes: Array[Vector2i] = [
		Vector2i(40, 44),
		Vector2i(40, 44),
		Vector2i(58, 44),
	]
	var sheet: Image = Image.create(SHEET_SIZE.x, SHEET_SIZE.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.TRANSPARENT)
	for direction: int in range(3):
		var source: Image = board.get_region(source_rects[direction])
		_keep_largest_component(source)
		source = _trim(source)
		if source == null or source.is_empty():
			return ERR_FILE_CORRUPT
		var fitted: Image = _fit(source, fit_sizes[direction])
		# The source board's side horse faces left, while the runtime SIDE row is
		# the canonical RIGHT-facing row (LEFT is produced by Composer.flip_h).
		# Normalize that source orientation once here so rider and mount share the
		# same direction contract.
		if direction == PaperDollLayerVisual.Facing.RIGHT:
			fitted.flip_x()
		for frame_x: int in range(8):
			var origin := Vector2i(frame_x * FRAME_SIZE.x, direction * FRAME_SIZE.y)
			var position := Vector2i(
				32 - int(fitted.get_width() / 2) + FRAME_MOTION[frame_x].x,
				56 - fitted.get_height() + FRAME_MOTION[frame_x].y
			)
			_blit_frame(sheet, fitted, origin, position)
	var path: String = output_path.path_join("artgate1_horse_full_mounted_unisex.png")
	return sheet.save_png(path)

func _write_mount_part(
		board: Image,
		row: int,
		fit_size: Vector2i,
		anchors: Array[Vector2i],
		file_name: String,
		output_path: String
) -> Error:
	return _write_sheet(board, 3, 3, row, fit_size, anchors, file_name, output_path)

func _write_sheet(
		board: Image,
		columns: int,
		rows: int,
		source_row: int,
		fit_size: Vector2i,
		anchors: Array[Vector2i],
	file_name: String,
	output_path: String = "",
	clip_bottom: float = 1.0,
	cleanup_min_pixels: int = 0,
	clear_cape_head_spill: bool = false,
	source_cleanup_row: int = -1,
	normalize_side: bool = false
) -> Error:
	var sheet: Image = Image.create(SHEET_SIZE.x, SHEET_SIZE.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.TRANSPARENT)
	for direction: int in range(3):
		var cell: Image = _cell(board, columns, rows, direction, source_row)
		if clip_bottom < 1.0:
			cell = cell.get_region(Rect2i(
				0,
				0,
				cell.get_width(),
				max(1, int(cell.get_height() * clip_bottom))
			))
		if source_cleanup_row == 1 or source_cleanup_row == 2:
			# Remove the following source row before trimming/scaling.  Doing
			# this after fitting leaves the real helmet/armor compressed above
			# the anchor and is the reason armor previously stopped at y=44.
			_keep_largest_component(cell)
		var source: Image = _trim(cell)
		if source == null or source.is_empty():
			return ERR_FILE_CORRUPT
		var fitted: Image = _fit(source, fit_size)
		if normalize_side and direction == PaperDollLayerVisual.Facing.RIGHT:
			# See _write_foot_sheet: source art is left-facing, while row 2 is
			# deliberately stored as RIGHT for the runtime mirror contract.
			fitted.flip_x()
		if cleanup_min_pixels > 0:
			# Head crops can include a few antialiased pixels from the next grid
			# row.  Remove only those tiny post-scale islands; preserve real
			# disconnected helmet/face-guard components.
			_remove_small_components(fitted, cleanup_min_pixels)
		for frame_x: int in range(8):
			var motion: Vector2i = FRAME_MOTION[frame_x]
			var anchor: Vector2i = anchors[direction] + motion
			var position: Vector2i = Vector2i(
				anchor.x - int(fitted.get_width() / 2),
				anchor.y - fitted.get_height()
			)
			var frame_origin := Vector2i(frame_x * FRAME_SIZE.x, direction * FRAME_SIZE.y)
			_blit_frame(sheet, fitted, frame_origin, position)
			if clear_cape_head_spill:
				_clear_cape_head_spill(sheet, frame_origin, direction)
	var target: String = output_path
	if target.is_empty():
		target = ProjectSettings.globalize_path(OUTPUT_DIR)
	else:
		target = output_path
	return sheet.save_png(target.path_join(file_name))

func _clear_cape_head_spill(sheet: Image, frame_origin: Vector2i, direction: int) -> void:
	# The reference cape crop starts at the top of the 64x64 cell.  That makes
	# the garment visibly taller than the head even when its mandated z-order
	# is correct.  Remove the top shoulder spill for every direction.  UP also
	# needs a central opening because Cape UP is intentionally above Hair/Helmet.
	sheet.fill_rect(
		Rect2i(frame_origin, Vector2i(FRAME_SIZE.x, 8)),
		Color.TRANSPARENT
	)
	if direction == 1:
		sheet.fill_rect(
			Rect2i(frame_origin + Vector2i(16, 8), Vector2i(32, 26)),
			Color.TRANSPARENT
		)

func _copy_pair(output_path: String, source_base: String, target_base: String) -> Error:
	for pose: String in ["on_foot", "mounted"]:
		var source: String = output_path.path_join("%s_%s_unisex.png" % [source_base, pose])
		var target: String = output_path.path_join("%s_%s_unisex.png" % [target_base, pose])
		var image: Image = Image.load_from_file(source)
		if image == null or image.is_empty():
			return ERR_FILE_NOT_FOUND
		var err: Error = image.save_png(target)
		if err != OK:
			return err
	return OK

func _align_hair_to_body(output_path: String) -> Error:
	# The reference hair art is a complete head sprite (skin and hair), not a
	# transparent strand-only overlay.  Body is the skeleton authority, so fit
	# each hair frame to Body's actual head alpha rect.  This makes Hair a head
	# replacement and prevents the bald Body head from peeking above or below it
	# as a second head in the composed preview.
	for gender: String in ["male", "female"]:
		for pose: String in ["on_foot", "mounted"]:
			var body_path: String = output_path.path_join(
				"body_%s_default_%s_unisex.png" % [gender, pose]
			)
			var hair_path: String = output_path.path_join(
				"hair_%s_default_%s_unisex.png" % [gender, pose]
			)
			var body: Image = Image.load_from_file(body_path)
			var hair: Image = Image.load_from_file(hair_path)
			if body == null or body.is_empty() or hair == null or hair.is_empty():
				return ERR_FILE_CORRUPT
			var head_band_end: int = 24 if pose == "on_foot" else 22
			for direction: int in range(3):
				for frame_x: int in range(8):
					var origin := Vector2i(frame_x * FRAME_SIZE.x, direction * FRAME_SIZE.y)
					var body_frame: Image = body.get_region(Rect2i(origin, FRAME_SIZE))
					var head: Rect2i = body_frame.get_region(Rect2i(
						Vector2i.ZERO,
						Vector2i(FRAME_SIZE.x, head_band_end)
					)).get_used_rect()
					var hair_frame: Image = hair.get_region(Rect2i(origin, FRAME_SIZE))
					var hair_used: Rect2i = hair_frame.get_used_rect()
					if head.size.x <= 0 or head.size.y <= 0 or hair_used.size.x <= 0 or hair_used.size.y <= 0:
						continue
					var fitted: Image = hair_frame.get_region(hair_used)
					fitted.resize(head.size.x, head.size.y, Image.INTERPOLATE_NEAREST)
					for y: int in range(FRAME_SIZE.y):
						for x: int in range(FRAME_SIZE.x):
							hair.set_pixelv(origin + Vector2i(x, y), Color.TRANSPARENT)
					hair.blit_rect(
						fitted,
						Rect2i(Vector2i.ZERO, fitted.get_size()),
						origin + head.position
					)
			if hair.save_png(hair_path) != OK:
				return ERR_CANT_CREATE
	return OK

func _align_helmet_to_body(output_path: String) -> Error:
	# Body owns the skeleton.  Helmet source art is fitted independently and in
	# the current reference board starts several pixels below (or above, for
	# mounted views) that skeleton.  Translate each frame so the helmet's top
	# and centre follow the union of the male/female head masks.  Then fill only
	# the four-pixel crown band where the bald Body would otherwise remain
	# visible; the visor/face opening below that band remains transparent so the
	# face can still be seen through the authored grille.
	for pose: String in ["on_foot", "mounted"]:
		var helmet_path: String = output_path.path_join(
			"artgate1_helmet_%s_unisex.png" % pose
		)
		var helmet: Image = Image.load_from_file(helmet_path)
		if helmet == null or helmet.is_empty():
			return ERR_FILE_CORRUPT
		var bodies: Array[Image] = []
		for gender: String in ["male", "female"]:
			var body_path: String = output_path.path_join(
				"body_%s_default_%s_unisex.png" % [gender, pose]
			)
			var body: Image = Image.load_from_file(body_path)
			if body == null or body.is_empty():
				return ERR_FILE_CORRUPT
			bodies.append(body)
		var head_band_end: int = 24 if pose == "on_foot" else 22
		for direction: int in range(3):
			for frame_x: int in range(8):
				var origin := Vector2i(frame_x * FRAME_SIZE.x, direction * FRAME_SIZE.y)
				var head: Rect2i = Rect2i()
				var have_head: bool = false
				for body: Image in bodies:
					var body_frame: Image = body.get_region(Rect2i(origin, FRAME_SIZE))
					var body_head: Rect2i = body_frame.get_region(Rect2i(
						Vector2i.ZERO,
						Vector2i(FRAME_SIZE.x, head_band_end)
					)).get_used_rect()
					if body_head.size.x <= 0 or body_head.size.y <= 0:
						continue
					head = body_head if not have_head else head.merge(body_head)
					have_head = true
				if not have_head:
					continue
				var helmet_frame: Image = helmet.get_region(Rect2i(origin, FRAME_SIZE))
				var helmet_used: Rect2i = helmet_frame.get_used_rect()
				if helmet_used.size.x <= 0 or helmet_used.size.y <= 0:
					continue
				var delta := Vector2i(
					int(round(head.get_center().x - helmet_used.get_center().x)),
					head.position.y - helmet_used.position.y
				)
				var aligned: Image = Image.create(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
				aligned.fill(Color.TRANSPARENT)
				_blit_frame(aligned, helmet_frame, Vector2i.ZERO, delta)
				for body: Image in bodies:
					var body_frame: Image = body.get_region(Rect2i(origin, FRAME_SIZE))
					_fill_helmet_crown_gaps(aligned, body_frame, head)
				var helmet_end: int = mini(FRAME_SIZE.y, head.end.y + 2)
				for y: int in range(helmet_end, FRAME_SIZE.y):
					for x: int in range(FRAME_SIZE.x):
						aligned.set_pixel(x, y, Color.TRANSPARENT)
				helmet.blit_rect(aligned, Rect2i(Vector2i.ZERO, FRAME_SIZE), origin)
		if helmet.save_png(helmet_path) != OK:
			return ERR_CANT_CREATE
	return OK

func _fill_helmet_crown_gaps(helmet: Image, body: Image, head: Rect2i) -> void:
	var crown_end: int = mini(head.end.y, head.position.y + 4)
	for y: int in range(head.position.y, crown_end):
		for x: int in range(head.position.x, head.end.x):
			if body.get_pixel(x, y).a <= 0.05 or helmet.get_pixel(x, y).a > 0.05:
				continue
			var fill: Color = Color("5b6880")
			for radius: int in range(1, 8):
				var found: bool = false
				for offset_x: int in range(-radius, radius + 1):
					for offset_y: int in range(-radius, radius + 1):
						var sample := Vector2i(x + offset_x, y + offset_y)
						if sample.x < 0 or sample.x >= FRAME_SIZE.x \
							or sample.y < 0 or sample.y >= FRAME_SIZE.y:
							continue
						var sample_color: Color = helmet.get_pixelv(sample)
						if sample_color.a > 0.05:
							fill = sample_color
							found = true
							break
					if found:
						break
				if found:
					break
			helmet.set_pixel(x, y, fill)

func _align_cape_to_shoulders(output_path: String) -> Error:
	# Cape is authored as a long garment, but its source crop contains a few
	# pixels above the rider's shoulder line.  Move each frame only as far as
	# needed to put its first visible row at the shared shoulder contract; this
	# preserves frame motion and clips only pixels that would leave the 64x64
	# canvas.
	for pose: String in ["on_foot", "mounted"]:
		var path: String = output_path.path_join(
			"artgate1_cape_%s_unisex.png" % pose
		)
		var sheet: Image = Image.load_from_file(path)
		if sheet == null or sheet.is_empty():
			return ERR_FILE_CORRUPT
		for direction: int in range(3):
			for frame_x: int in range(8):
				var origin := Vector2i(frame_x * FRAME_SIZE.x, direction * FRAME_SIZE.y)
				var frame: Image = sheet.get_region(Rect2i(origin, FRAME_SIZE))
				var used: Rect2i = frame.get_used_rect()
				if used.size.x <= 0 or used.size.y <= 0 or used.position.y >= PaperDollLayerVisual.CAPE_SHOULDER_TOP:
					continue
				var delta: int = PaperDollLayerVisual.CAPE_SHOULDER_TOP - used.position.y
				var shifted: Image = Image.create(
					FRAME_SIZE.x,
					FRAME_SIZE.y,
					false,
					Image.FORMAT_RGBA8
				)
				shifted.fill(Color.TRANSPARENT)
				var source_height: int = FRAME_SIZE.y - delta
				if source_height > 0:
					shifted.blit_rect(
						frame,
						Rect2i(Vector2i.ZERO, Vector2i(FRAME_SIZE.x, source_height)),
						Vector2i(0, delta)
					)
				sheet.blit_rect(
					shifted,
					Rect2i(Vector2i.ZERO, FRAME_SIZE),
					origin
				)
		if sheet.save_png(path) != OK:
			return ERR_CANT_CREATE
	return OK

func _clear_armor_face_overlap(output_path: String) -> Error:
	for pose: String in ["on_foot", "mounted"]:
		var face_band_end: int = 22 if pose == "on_foot" else 20
		var armor_path: String = output_path.path_join(
			"artgate1_armor_%s_unisex.png" % pose
		)
		var armor: Image = Image.load_from_file(armor_path)
		if armor == null or armor.is_empty():
			return ERR_FILE_CORRUPT
		for gender: String in ["male", "female"]:
			var body_path: String = output_path.path_join(
				"body_%s_default_%s_unisex.png" % [gender, pose]
			)
			var body: Image = Image.load_from_file(body_path)
			if body == null or body.is_empty():
				return ERR_FILE_CORRUPT
			for direction: int in range(3):
				for frame_x: int in range(8):
					var origin := Vector2i(frame_x * FRAME_SIZE.x, direction * FRAME_SIZE.y)
					var armor_top_cut: int = PaperDollLayerVisual.armor_top_cut(
						pose == "mounted", direction
					)
					for y: int in range(armor_top_cut):
						for x: int in range(FRAME_SIZE.x):
							armor.set_pixelv(origin + Vector2i(x, y), Color.TRANSPARENT)
					for y: int in range(face_band_end):
						for x: int in range(FRAME_SIZE.x):
							var position := origin + Vector2i(x, y)
							if body.get_pixelv(position).a > 0.05 \
									and armor.get_pixelv(position).a > 0.05:
								armor.set_pixelv(position, Color.TRANSPARENT)
		if armor.save_png(armor_path) != OK:
			return ERR_CANT_CREATE
	return OK

func _align_armor_to_body(output_path: String) -> Error:
	# Armor is authored on a separate reference board, so its shoulder plates
	# can be disconnected from the torso after scaling.  Use the generated Body
	# silhouettes as the only horizontal skeleton authority: at every scanline,
	# keep armor within the body's silhouette plus a small, intentional margin.
	# This preserves the two real armor components (torso and greaves) while
	# removing detached shoulder/row-spill pixels that visually float beside the
	# head.  The same 64x64 frame contract is used by the runtime Sprite2D.
	for pose: String in ["on_foot", "mounted"]:
		var armor_path: String = output_path.path_join(
			"artgate1_armor_%s_unisex.png" % pose
		)
		var armor: Image = Image.load_from_file(armor_path)
		if armor == null or armor.is_empty():
			return ERR_FILE_CORRUPT
		var bodies: Array[Image] = []
		for gender: String in ["male", "female"]:
			var body_path: String = output_path.path_join(
				"body_%s_default_%s_unisex.png" % [gender, pose]
			)
			var body: Image = Image.load_from_file(body_path)
			if body == null or body.is_empty():
				return ERR_FILE_CORRUPT
			bodies.append(body)
		for direction: int in range(3):
			for frame_x: int in range(8):
				var origin := Vector2i(frame_x * FRAME_SIZE.x, direction * FRAME_SIZE.y)
				var row_min: Array[int] = []
				var row_max: Array[int] = []
				var global_min: int = FRAME_SIZE.x
				var global_max: int = -1
				for y: int in range(FRAME_SIZE.y):
					var minimum: int = FRAME_SIZE.x
					var maximum: int = -1
					for x: int in range(FRAME_SIZE.x):
						for body: Image in bodies:
							if body.get_pixelv(origin + Vector2i(x, y)).a > 0.05:
								minimum = mini(minimum, x)
								maximum = maxi(maximum, x)
								break
					row_min.append(minimum)
					row_max.append(maximum)
					if maximum >= 0:
						global_min = mini(global_min, minimum)
						global_max = maxi(global_max, maximum)
				for y: int in range(FRAME_SIZE.y):
					var minimum: int = row_min[y]
					var maximum: int = row_max[y]
					if maximum < 0:
						# A gap between the legs has no body pixels on that exact
						# row.  Use the nearest populated row so the armor opening
						# is not mistaken for detached geometry.
						for delta: int in range(1, FRAME_SIZE.y):
							var above: int = y - delta
							var below: int = y + delta
							if above >= 0 and row_max[above] >= 0:
								minimum = row_min[above]
								maximum = row_max[above]
								break
							if below < FRAME_SIZE.y and row_max[below] >= 0:
								minimum = row_min[below]
								maximum = row_max[below]
								break
					if maximum < 0:
						minimum = global_min
						maximum = global_max
					# Keep a small outline allowance so nearest-neighbour scaling does
					# not split the authored shoulder/torso silhouette into islands.
					# Keep only a one-pixel outline allowance around the union body
					# silhouette.  The previous 3/4-pixel margin made the shoulder
					# plates visibly float beside the torso while still passing alpha
					# coverage checks.
					var margin: int = 0 if y >= 48 else 1
					minimum = maxi(0, minimum - margin)
					maximum = mini(FRAME_SIZE.x - 1, maximum + margin)
					for x: int in range(FRAME_SIZE.x):
						if x < minimum or x > maximum:
							armor.set_pixelv(origin + Vector2i(x, y), Color.TRANSPARENT)
		# Nearest-neighbour fitting can leave a disconnected slice at the right
		# edge of the UP source cell.  It is a source-row leak, not a second
		# armor part (31 pixels in the current board); remove small components
		# after the silhouette clip while retaining the main 600+ pixel armor.
		_remove_small_components(armor, 64)
		if armor.save_png(armor_path) != OK:
			return ERR_CANT_CREATE
	return OK

func _fill_armor_body_coverage(output_path: String) -> Error:
	# Heavy armor is an opaque garment in the paper-doll contract.  The source
	# board contains transparent gaps between the authored steel plates, but
	# those gaps must not reveal the gold Body layer underneath at runtime.  Keep
	# every authored armor pixel and fill only the remaining pixels that belong
	# to either generated Body silhouette.  This is done once while packing the
	# source art; Composer remains a texture-only consumer and never invents
	# geometry at runtime.
	const UNDER_ARMOR := Color("283345")
	for pose: String in ["on_foot", "mounted"]:
		var armor_path: String = output_path.path_join(
			"artgate1_armor_%s_unisex.png" % pose
		)
		var armor: Image = Image.load_from_file(armor_path)
		if armor == null or armor.is_empty():
			return ERR_FILE_CORRUPT
		var bodies: Array[Image] = []
		for gender: String in ["male", "female"]:
			var body_path: String = output_path.path_join(
				"body_%s_default_%s_unisex.png" % [gender, pose]
			)
			var body: Image = Image.load_from_file(body_path)
			if body == null or body.is_empty():
				return ERR_FILE_CORRUPT
			bodies.append(body)
		# Keep the visual shoulder/collar band at armor_top_cut, but never paint
		# over the Body face.  Face ownership remains with Body/Hair/Helmet.
		var coverage_start: int = 20 if pose == "mounted" else 22
		for direction: int in range(3):
			for frame_x: int in range(8):
				var origin := Vector2i(frame_x * FRAME_SIZE.x, direction * FRAME_SIZE.y)
				for y: int in range(coverage_start, FRAME_SIZE.y):
					for x: int in range(FRAME_SIZE.x):
						var position := origin + Vector2i(x, y)
						var body_present: bool = false
						for body: Image in bodies:
							if body.get_pixelv(position).a > 0.05:
								body_present = true
								break
						if body_present and armor.get_pixelv(position).a <= 0.05:
							armor.set_pixelv(position, UNDER_ARMOR)
				_bridge_short_armor_gaps(armor, origin, coverage_start, UNDER_ARMOR)
		if armor.save_png(armor_path) != OK:
			return ERR_CANT_CREATE
	return OK

func _bridge_short_armor_gaps(
		armor: Image,
		origin: Vector2i,
		coverage_start: int,
		fill: Color
) -> void:
	# A one/two-pixel antialiased cut can leave a detached under-armor island at
	# a shoulder.  Bridge only short horizontal gaps; a larger gap is preserved
	# because it can be the intentional opening between greaves.
	for y: int in range(coverage_start, FRAME_SIZE.y):
		var x: int = 1
		while x < FRAME_SIZE.x - 1:
			if armor.get_pixelv(origin + Vector2i(x, y)).a > 0.05:
				x += 1
				continue
			var gap_start: int = x
			while x < FRAME_SIZE.x - 1 \
					and armor.get_pixelv(origin + Vector2i(x, y)).a <= 0.05:
				x += 1
			var gap_size: int = x - gap_start
			if gap_size <= 2 \
					and armor.get_pixelv(origin + Vector2i(gap_start - 1, y)).a > 0.05 \
					and armor.get_pixelv(origin + Vector2i(x, y)).a > 0.05:
				for gap_x: int in range(gap_start, x):
					armor.set_pixelv(origin + Vector2i(gap_x, y), fill)

func _clear_mount_rider_overlap(output_path: String) -> Error:
	var body_paths: Dictionary = {}
	for gender: String in ["male", "female"]:
		body_paths[gender] = {}
		for pose: String in ["mounted"]:
			body_paths[gender][pose] = output_path.path_join(
				"body_%s_default_%s_unisex.png" % [gender, pose]
			)
	var armor_path: String = output_path.path_join("artgate1_armor_mounted_unisex.png")
	var armor: Image = Image.load_from_file(armor_path)
	if armor == null or armor.is_empty():
		return ERR_FILE_CORRUPT
	var horse_paths: Array[String] = [
		output_path.path_join("artgate1_horse_head_mounted_unisex.png"),
		output_path.path_join("artgate1_barding_mounted_unisex.png"),
	]
	var horse_images: Array[Image] = []
	for path: String in horse_paths:
		var horse: Image = Image.load_from_file(path)
		if horse == null or horse.is_empty():
			return ERR_FILE_CORRUPT
		horse_images.append(horse)
	for gender: String in ["male", "female"]:
		var body: Image = Image.load_from_file(body_paths[gender]["mounted"])
		if body == null or body.is_empty():
			return ERR_FILE_CORRUPT
		for direction: int in range(3):
			for frame_x: int in range(8):
				var origin := Vector2i(frame_x * FRAME_SIZE.x, direction * FRAME_SIZE.y)
				for y: int in range(FRAME_SIZE.y):
					for x: int in range(FRAME_SIZE.x):
						var position := origin + Vector2i(x, y)
						var rider_present: bool = body.get_pixelv(position).a > 0.05 \
							or armor.get_pixelv(position).a > 0.05
						if not rider_present:
							continue
						# Preserve the horse muzzle above/alongside a side-facing
						# rider.  In DOWN/UP the neck belongs in front of the
						# rider's lower torso, but never cover the rider's head band.
						var preserve_front_neck: bool = direction != PaperDollLayerVisual.Facing.RIGHT \
							and y >= PaperDollLayerVisual.MOUNT_FRONT_HEAD_OVERLAP_START
						if not preserve_front_neck \
							and (direction != PaperDollLayerVisual.Facing.RIGHT \
							or y >= PaperDollLayerVisual.MOUNT_RIDER_CLEARANCE_HEAD_END):
							horse_images[0].set_pixelv(position, Color.TRANSPARENT)
						horse_images[1].set_pixelv(position, Color.TRANSPARENT)
	for horse_index: int in range(horse_images.size()):
		if horse_images[horse_index].save_png(horse_paths[horse_index]) != OK:
			return ERR_CANT_CREATE
	return OK

func _blit_frame(sheet: Image, source: Image, frame_origin: Vector2i, position: Vector2i) -> void:
	# Animation motion may move a sprite by one pixel.  Clip the source to its
	# own 64x64 cell so it can never leak into the adjacent direction row.
	var source_rect: Rect2i = Rect2i(Vector2i.ZERO, source.get_size())
	var destination: Vector2i = position
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

func _load_board(file_name: String) -> Image:
	var path: String = ProjectSettings.globalize_path(SOURCE_DIR.path_join(file_name))
	var image: Image = Image.load_from_file(path)
	if image == null or image.is_empty():
		push_error("Missing reference board: %s" % path)
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	_remove_magenta_background(image)
	return image

func _remove_magenta_background(image: Image) -> void:
	# The generated boards have a slight magenta gradient instead of a truly
	# flat key. Flood-fill only background-like pixels connected to the border;
	# this removes halos while preserving enclosed purple/red subject pixels.
	var width: int = image.get_width()
	var height: int = image.get_height()
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(width * height)
	var queue: Array[Vector2i] = []
	for x: int in range(width):
		_enqueue_background(image, visited, queue, Vector2i(x, 0), width)
		_enqueue_background(image, visited, queue, Vector2i(x, height - 1), width)
	for y: int in range(height):
		_enqueue_background(image, visited, queue, Vector2i(0, y), width)
		_enqueue_background(image, visited, queue, Vector2i(width - 1, y), width)
	var index: int = 0
	while index < queue.size():
		var position: Vector2i = queue[index]
		index += 1
		image.set_pixel(position.x, position.y, Color.TRANSPARENT)
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = position + step
			if next.x >= 0 and next.x < width and next.y >= 0 and next.y < height:
				_enqueue_background(image, visited, queue, next, width)
	# A generated board can contain a few disconnected islands of the same
	# chroma-key gradient inside a crop cell.  They are not reached by the
	# border flood-fill, but the hue gate is safe to apply globally: the source
	# subjects are yellow, steel-blue, purple, brown, or red—not this magenta.
	for y: int in range(height):
		for x: int in range(width):
			if _is_background_candidate(image.get_pixel(x, y)):
				image.set_pixel(x, y, Color.TRANSPARENT)

func _enqueue_background(
		image: Image,
		visited: PackedByteArray,
		queue: Array[Vector2i],
		position: Vector2i,
		width: int
) -> void:
	var offset: int = position.y * width + position.x
	if visited[offset] != 0 or not _is_background_candidate(image.get_pixelv(position)):
		return
	visited[offset] = 1
	queue.append(position)

func _is_background_candidate(color: Color) -> bool:
	# The key is a red/magenta gradient (hue ~= 0.90).  The old gate only
	# removed the bright background and left its dark anti-aliased fringe glued
	# to every sprite (visible as pink/purple one-pixel leaks around armor,
	# helmet, cape and weapons).  Remove the darker mixtures too, while keeping
	# the authored purple cape (hue ~= 0.74), black outlines (very low value),
	# and brown/red horse pixels (hue near 0.0).
	return color.h > 0.82 \
		and color.h < 0.99 \
		and color.s > 0.20 \
		and color.v > 0.01 \
		and color.g < 100.0 / 255.0 \
		and color.r > color.b * 1.15

func _cell(image: Image, columns: int, rows: int, column: int, row: int) -> Image:
	var left: int = int(float(image.get_width() * column) / columns)
	var right: int = int(float(image.get_width() * (column + 1)) / columns)
	var top: int = int(float(image.get_height() * row) / rows)
	var bottom: int = int(float(image.get_height() * (row + 1)) / rows)
	return image.get_region(Rect2i(left, top, right - left, bottom - top))

func _foot_cell(image: Image, row: int, direction: int) -> Image:
	var top: int = int(float(image.get_height() * row) / 4.0)
	var bottom: int = int(float(image.get_height() * (row + 1)) / 4.0)
	return image.get_region(Rect2i(
		FOOT_X_BOUNDS[direction],
		top,
		FOOT_X_BOUNDS[direction + 1] - FOOT_X_BOUNDS[direction],
		bottom - top
	))

func _trim(image: Image) -> Image:
	var cleaned: Image = image.duplicate()
	_remove_small_components(cleaned)
	var used: Rect2i = cleaned.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return Image.create(1, 1, false, Image.FORMAT_RGBA8)
	return cleaned.get_region(used)

func _remove_small_components(image: Image, minimum_pixels: int = MIN_COMPONENT_PIXELS) -> void:
	var width: int = image.get_width()
	var height: int = image.get_height()
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(width * height)
	for y: int in range(height):
		for x: int in range(width):
			var start: Vector2i = Vector2i(x, y)
			var start_index: int = y * width + x
			if visited[start_index] != 0 or image.get_pixelv(start).a <= 0.05:
				continue
			var queue: Array[Vector2i] = [start]
			var component: Array[Vector2i] = []
			visited[start_index] = 1
			var index: int = 0
			while index < queue.size():
				var position: Vector2i = queue[index]
				index += 1
				component.append(position)
				for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var next: Vector2i = position + step
					if next.x < 0 or next.x >= width or next.y < 0 or next.y >= height:
						continue
					var next_index: int = next.y * width + next.x
					if visited[next_index] != 0 or image.get_pixelv(next).a <= 0.05:
						continue
					visited[next_index] = 1
					queue.append(next)
			if component.size() < minimum_pixels:
				for position: Vector2i in component:
					image.set_pixelv(position, Color.TRANSPARENT)

func _keep_largest_component(image: Image) -> void:
	var largest: Array[Vector2i] = []
	for component: Array in _collect_components(image):
		if component.size() > largest.size():
			largest = component
	var keep: Dictionary = {}
	for position: Vector2i in largest:
		keep[position] = true
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if image.get_pixelv(Vector2i(x, y)).a > 0.05 \
					and not keep.has(Vector2i(x, y)):
				image.set_pixelv(Vector2i(x, y), Color.TRANSPARENT)

func _collect_components(image: Image) -> Array:
	var width: int = image.get_width()
	var height: int = image.get_height()
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(width * height)
	var components: Array = []
	for y: int in range(height):
		for x: int in range(width):
			var start := Vector2i(x, y)
			var start_index: int = y * width + x
			if visited[start_index] != 0 or image.get_pixelv(start).a <= 0.05:
				continue
			var queue: Array[Vector2i] = [start]
			var component: Array[Vector2i] = []
			visited[start_index] = 1
			var index: int = 0
			while index < queue.size():
				var position: Vector2i = queue[index]
				index += 1
				component.append(position)
				for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var next: Vector2i = position + step
					if next.x < 0 or next.x >= width or next.y < 0 or next.y >= height:
						continue
					var next_index: int = next.y * width + next.x
					if visited[next_index] != 0 or image.get_pixelv(next).a <= 0.05:
						continue
					visited[next_index] = 1
					queue.append(next)
			components.append(component)
	return components

func _fit(image: Image, max_size: Vector2i) -> Image:
	var scale: float = min(
		float(max_size.x) / max(1, image.get_width()),
		float(max_size.y) / max(1, image.get_height())
	)
	var size: Vector2i = Vector2i(
		max(1, int(round(image.get_width() * scale))),
		max(1, int(round(image.get_height() * scale)))
	)
	var result: Image = image.duplicate()
	result.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
	return result

func _center_anchors(bottom: int) -> Array[Vector2i]:
	return [Vector2i(32, bottom), Vector2i(32, bottom), Vector2i(32, bottom)]

func _mounted_fit(foot_fit: Vector2i) -> Vector2i:
	return Vector2i(max(1, int(foot_fit.x * 0.76)), max(1, int(foot_fit.y * 0.76)))
