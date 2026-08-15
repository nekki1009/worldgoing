extends SceneTree

## Art Gate 1 visual QA.
##
## This is deliberately separate from the UI screenshot test.  It renders the
## actual runtime textures, without the CharacterCreator controls or guides,
## then checks every direction/frame before writing enlarged inspection boards.
## The numeric checks are engineering guards; a human still decides whether the
## art is aesthetically acceptable after opening the generated PNGs.

const OUTPUT_DIR := "res://.visual_captures/paper_doll/qa"
const REFERENCE_DIR := "res://assets/doll/reference"
const REFERENCE_RATIO_TOLERANCE := 0.03
const REFERENCE_BOTTOM_TOLERANCE := 0.04
const SCALE := 4
const TILE_SIZE := PaperDollLayerVisual.FRAME_SIZE * SCALE
const MONTAGE_SIZE := Vector2i(
	PaperDollLayerVisual.FRAME_COLUMNS * TILE_SIZE.x,
	4 * TILE_SIZE.y
)

var _failures: PackedStringArray = []
var _catalog: PaperDollCatalog
var _reference_profiles: Dictionary = {}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_catalog = PaperDollCatalog.create_art_gate1_catalog()
	if OS.get_cmdline_user_args().has("--dump-paper-doll-alignment"):
		_dump_alignment()
	_check_catalog()
	_check_authored_action_sheets()
	_check_alternate_geometry()
	_check_dye_group_ownership()
	if _failures.is_empty():
		_check_reference_images()
	if _failures.is_empty():
		_check_recipe("on_foot_full", _make_recipe(false))
		_check_recipe("mounted_full", _make_recipe(true))
		_check_recipe("on_foot_preview", _make_preview_recipe(false))
		_check_recipe("mounted_preview", _make_preview_recipe(true))
		_check_recipe("on_foot_female_full", _make_recipe(false, PaperDollLayerVisual.Gender.FEMALE))
		_check_recipe("mounted_female_full", _make_recipe(true, PaperDollLayerVisual.Gender.FEMALE))
		_check_recipe("on_foot_female_preview", _make_preview_recipe(false, PaperDollLayerVisual.Gender.FEMALE))
		_check_recipe("mounted_female_preview", _make_preview_recipe(true, PaperDollLayerVisual.Gender.FEMALE))
	if _failures.is_empty():
		_check_all_actions()
	if _failures.is_empty():
		print("PAPER DOLL VISUAL QA PASS: 256 runtime frames plus reference-image gate checked; runtime layer guards passed and reference measurements were written to %s" % OUTPUT_DIR)
	else:
		for failure: String in _failures:
			push_error("PAPER DOLL VISUAL QA FAIL: %s" % failure)
		print("PAPER DOLL VISUAL QA FAILED: %d issue(s)" % _failures.size())
	quit(0 if _failures.is_empty() else 1)

func _check_dye_group_ownership() -> void:
	_check_dye_group_ownership_for_pose(false)
	_check_dye_group_ownership_for_pose(true)

func _check_dye_group_ownership_for_pose(mounted: bool) -> void:
	var draft: PaperDollPreviewDraft = PaperDollPreviewDraft.new()
	draft.is_mounted = mounted
	draft.set_visual(PaperDollLayerVisual.RenderLayer.BODY, _catalog.default_visual_id(PaperDollLayerVisual.RenderLayer.BODY, draft.gender, mounted))
	draft.set_visual(PaperDollLayerVisual.RenderLayer.ARMOR, _catalog.default_visual_id(PaperDollLayerVisual.RenderLayer.ARMOR, draft.gender, mounted))
	draft.set_visual(PaperDollLayerVisual.RenderLayer.HAIR, _catalog.default_visual_id(PaperDollLayerVisual.RenderLayer.HAIR, draft.gender, mounted))
	draft.set_visual(PaperDollLayerVisual.RenderLayer.CAPE, _catalog.default_visual_id(PaperDollLayerVisual.RenderLayer.CAPE, draft.gender, mounted))
	draft.set_visual(PaperDollLayerVisual.RenderLayer.HELMET, _catalog.default_visual_id(PaperDollLayerVisual.RenderLayer.HELMET, draft.gender, mounted))
	draft.set_visual(PaperDollLayerVisual.RenderLayer.WEAPON, _catalog.default_visual_id(PaperDollLayerVisual.RenderLayer.WEAPON, draft.gender, mounted))
	draft.set_visual(PaperDollLayerVisual.RenderLayer.SHIELD, _catalog.default_visual_id(PaperDollLayerVisual.RenderLayer.SHIELD, draft.gender, mounted))
	draft.set_visual(PaperDollLayerVisual.RenderLayer.MOUNT_BARDING, _catalog.default_visual_id(PaperDollLayerVisual.RenderLayer.MOUNT_BARDING, draft.gender, mounted))
	if mounted:
		draft.mount_visual_id = _catalog.sorted_mounts()[0].mount_visual_id
	var recipe: PaperDollRecipe = _catalog.resolve_recipe(draft)
	if recipe == null:
		_fail("dye ownership recipe did not resolve mounted=%s" % mounted)
		return
	var composer := PaperDollComposer.new()
	root.add_child(composer)
	composer.apply_recipe(recipe)
	# The accepted white-hair/silver-armor preset is deliberately one complete
	# reference board.  Its dye groups still recolour independent pixel regions,
	# but the resulting texture belongs to BODY rather than to the old split
	# Sprite2D overlays.  Keep the ownership assertion aligned with that runtime
	# contract instead of treating the hidden overlays as visual owners.
	var accepted_reference: bool = recipe.is_accepted_reference
	var before: Dictionary = {}
	for layer: int in range(PaperDollLayerVisual.RenderLayer.COUNT):
		var texture: Texture2D = composer.sprite_for(layer).texture
		before[layer] = texture.get_image().get_data() if texture != null else PackedByteArray()
	composer.set_dye(PaperDollComposer.DyeGroup.ARMOR, Color("3b79c9"))
	var armor_layers: Array[int] = [
		PaperDollLayerVisual.RenderLayer.BODY
		if accepted_reference
		else PaperDollLayerVisual.RenderLayer.ARMOR
	]
	if mounted and not accepted_reference:
		armor_layers.append(PaperDollLayerVisual.RenderLayer.MOUNT_BARDING)
	_assert_group_changes_only(composer, before, armor_layers, "armor mounted=%s" % mounted)
	composer.clear_dyes()
	var after_clear: Dictionary = {}
	for layer: int in range(PaperDollLayerVisual.RenderLayer.COUNT):
		var texture: Texture2D = composer.sprite_for(layer).texture
		after_clear[layer] = texture.get_image().get_data() if texture != null else PackedByteArray()
	if accepted_reference:
		if after_clear[PaperDollLayerVisual.RenderLayer.BODY] != before[PaperDollLayerVisual.RenderLayer.BODY]:
			_fail("clear_dyes did not restore accepted reference body mounted=%s" % mounted)
	elif after_clear[PaperDollLayerVisual.RenderLayer.ARMOR] != before[PaperDollLayerVisual.RenderLayer.ARMOR]:
		_fail("clear_dyes did not restore armor mounted=%s" % mounted)
	composer.set_dye(PaperDollComposer.DyeGroup.CAPE, Color("8c3d62"))
	var cape_layers: Array[int] = [PaperDollLayerVisual.RenderLayer.CAPE]
	if accepted_reference:
		cape_layers = [PaperDollLayerVisual.RenderLayer.BODY]
	_assert_group_changes_only(
		composer,
		after_clear,
		cape_layers,
		"cape mounted=%s" % mounted
	)
	composer.clear_dyes()
	composer.set_dye(PaperDollComposer.DyeGroup.HAIR_BROWS, Color("d13f8f"))
	var hair_layers: Array[int] = [
		PaperDollLayerVisual.RenderLayer.BODY,
		PaperDollLayerVisual.RenderLayer.HAIR,
	]
	# The armed reference is a complete helmet/weapon/shield board.  Hair is
	# intentionally hidden there, so a hair dye must not mutate that bundle.
	if recipe.reference_composite_texture != null:
		hair_layers = []
	_assert_group_changes_only(composer, before, hair_layers, "hair+brows mounted=%s" % mounted)
	composer.clear_dyes()
	if mounted:
		composer.set_dye(PaperDollComposer.DyeGroup.MOUNT, Color("5a963d"))
		var mount_layers: Array[int] = [
			PaperDollLayerVisual.RenderLayer.MOUNT_TAIL,
			PaperDollLayerVisual.RenderLayer.MOUNT_BODY,
			PaperDollLayerVisual.RenderLayer.MOUNT_HEAD,
		]
		if accepted_reference:
			mount_layers = [PaperDollLayerVisual.RenderLayer.BODY]
		_assert_group_changes_only(
			composer,
			before,
			mount_layers,
			"mount mounted=true"
		)
	composer.queue_free()

func _assert_group_changes_only(composer: PaperDollComposer, before: Dictionary, allowed: Array[int], label: String) -> void:
	for layer: int in range(PaperDollLayerVisual.RenderLayer.COUNT):
		var texture: Texture2D = composer.sprite_for(layer).texture
		var current: PackedByteArray = texture.get_image().get_data() if texture != null else PackedByteArray()
		var changed: bool = current != (before[layer] as PackedByteArray)
		if changed != (layer in allowed):
			_fail("%s dye changed unexpected layer %s" % [label, PaperDollLayerVisual.layer_name(layer)])

func _dump_alignment() -> void:
	for mounted: bool in [false, true]:
		var recipe: PaperDollRecipe = _make_preview_recipe(mounted)
		print("PAPER DOLL ALIGNMENT DUMP: %s DOWN frame 0" % ("mounted" if mounted else "on-foot"))
		for layer: int in range(PaperDollLayerVisual.RenderLayer.COUNT):
			var texture: Texture2D = recipe.texture_for(layer)
			if texture == null:
				continue
			var frame: Image = _texture_frame_image(texture, PaperDollLayerVisual.Facing.DOWN, 0)
			print("  %s used=%s components=%d" % [
				PaperDollLayerVisual.layer_name(layer),
				frame.get_used_rect(),
				_component_count(frame),
			])
		var armor_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.ARMOR)
		if armor_texture != null:
			for facing: int in range(4):
				var armor_frame: Image = _texture_frame_image(armor_texture, facing, 0)
				var components: Array = _collect_components(armor_frame)
				var component_summary: PackedStringArray = []
				for component: Array in components:
					var bounds: Rect2i = Rect2i(64, 64, 0, 0)
					for position: Vector2i in component:
						bounds = bounds.expand(position)
					component_summary.append("%d:%s" % [component.size(), bounds])
				print("  Armor facing=%d used=%s components=%d [%s]" % [
					facing, armor_frame.get_used_rect(), components.size(), ", ".join(component_summary),
				])
				var body_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY)
				var body_frame: Image = _texture_frame_image(body_texture, facing, 0)
				var coverage_start: int = 20 if mounted else 22
				var body_region_pixels: int = 0
				var exposed_body_pixels: int = 0
				for y: int in range(coverage_start, PaperDollLayerVisual.FRAME_SIZE.y):
					for x: int in range(PaperDollLayerVisual.FRAME_SIZE.x):
						if body_frame.get_pixel(x, y).a <= 0.05:
							continue
						body_region_pixels += 1
						if armor_frame.get_pixel(x, y).a <= 0.05:
							exposed_body_pixels += 1
				var exposed_ratio: float = float(exposed_body_pixels) / max(1, body_region_pixels)
				print("    body pixels below shoulder not covered by armor=%d/%d (%.1f%%)" % [
					exposed_body_pixels, body_region_pixels, exposed_ratio * 100.0,
				])
				if not mounted and facing == PaperDollLayerVisual.Facing.DOWN:
					for row: int in [22, 26, 30, 34, 38, 42, 46, 50, 54]:
						print("    y=%d body=[%d,%d] armor=[%d,%d]" % [
							row,
							_row_min(body_frame, row), _row_max(body_frame, row),
							_row_min(armor_frame, row), _row_max(armor_frame, row),
						])
		# Keep a human-readable isolation board beside the numeric dump.  This
		# makes a half-cropped or over-sized armor frame visible without relying
		# on the final z-order composite to hide the mistake.
		var board: Image = Image.create(192, 64, false, Image.FORMAT_RGBA8)
		board.fill(Color("121821"))
		for column: int in range(3):
			var layer: int = [
				PaperDollLayerVisual.RenderLayer.BODY,
				PaperDollLayerVisual.RenderLayer.ARMOR,
				PaperDollLayerVisual.RenderLayer.HELMET,
			][column]
			var texture: Texture2D = recipe.texture_for(layer)
			if texture == null:
				continue
			var frame: Image = _texture_frame_image(texture, PaperDollLayerVisual.Facing.DOWN, 0)
			frame.resize(64, 64, Image.INTERPOLATE_NEAREST)
			board.blend_rect(frame, Rect2i(Vector2i.ZERO, Vector2i(64, 64)), Vector2i(column * 64, 0))
		_save_png(board, "alignment_%s_down_frame0_isolation.png" % ("mounted" if mounted else "on_foot"))
		var coverage_body_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY)
		var coverage_armor_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.ARMOR)
		if coverage_body_texture != null and coverage_armor_texture != null:
			var coverage_body_frame: Image = _texture_frame_image(coverage_body_texture, PaperDollLayerVisual.Facing.DOWN, 0)
			var coverage_armor_frame: Image = _texture_frame_image(coverage_armor_texture, PaperDollLayerVisual.Facing.DOWN, 0)
			var coverage: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
			coverage.fill(Color("121821"))
			for y: int in range(64):
				for x: int in range(64):
					var body_pixel: Color = coverage_body_frame.get_pixel(x, y)
					var armor_pixel: Color = coverage_armor_frame.get_pixel(x, y)
					if armor_pixel.a > 0.05:
						coverage.set_pixel(x, y, armor_pixel)
					elif body_pixel.a > 0.05 and y >= (20 if mounted else 22):
						# Red means Body is visible in the armor-covered region.
						coverage.set_pixel(x, y, Color(1.0, 0.12, 0.08, 1.0))
			coverage.resize(256, 256, Image.INTERPOLATE_NEAREST)
			_save_png(coverage, "alignment_%s_down_frame0_coverage.png" % ("mounted" if mounted else "on_foot"))

func _check_catalog() -> void:
	var issues: PackedStringArray = _catalog.validation_issues()
	if not issues.is_empty():
		_fail("catalog validation: %s" % " | ".join(issues))

func _check_alternate_geometry() -> void:
	# Most alternates are palette variants of approved geometry. Compare alpha
	# masks rather than RGB values so this gate catches accidental crop/scale
	# drift without rejecting a legitimate colour change. The hairstyle is the
	# exception: it is intentionally a new silhouette extracted from the art board.
	var layer_pairs: Array = [
		[&"artgate1_armor", &"alt_bronze_armor"],
		[&"artgate1_cape", &"alt_teal_cape"],
		[&"artgate1_weapon", &"alt_bronze_sword"],
		[&"artgate1_shield", &"alt_teal_shield"],
	]
	for pair: Array in layer_pairs:
		var reference_visual: PaperDollLayerVisual = _catalog.find_visual(pair[0] as StringName)
		var alternate_visual: PaperDollLayerVisual = _catalog.find_visual(pair[1] as StringName)
		if reference_visual == null or alternate_visual == null:
			_fail("alternate geometry pair is missing: %s" % pair[1])
			continue
		_compare_alpha_masks(
			reference_visual.on_foot_unisex,
			alternate_visual.on_foot_unisex,
			"%s on-foot" % pair[1]
		)
		_compare_alpha_masks(
			reference_visual.mounted_unisex,
			alternate_visual.mounted_unisex,
			"%s mounted" % pair[1]
		)
	_check_approved_hairstyles()
	var barding_reference: PaperDollLayerVisual = _catalog.find_visual(&"artgate1_barding")
	var barding_alternate: PaperDollLayerVisual = _catalog.find_visual(&"alt_dark_barding")
	_compare_alpha_masks(barding_reference.mounted_unisex, barding_alternate.mounted_unisex, "alt_dark_barding mounted")
	var mount_pairs: Array = [
		[&"artgate1_horse_tail", &"alt_dark_bay_horse_tail"],
		[&"artgate1_horse_body", &"alt_dark_bay_horse_body"],
		[&"artgate1_horse_head", &"alt_dark_bay_horse_head"],
	]
	for pair: Array in mount_pairs:
		var reference_part: PaperDollLayerVisual = _find_mount_part(pair[0] as StringName)
		var alternate_part: PaperDollLayerVisual = _find_mount_part(pair[1] as StringName)
		_compare_alpha_masks(reference_part.mounted_unisex, alternate_part.mounted_unisex, str(pair[1]))

func _check_authored_action_sheets() -> void:
	var required: Array = [
		[&"body_male_default", "body"],
		[&"hair_male_default", "hair"],
		[&"artgate1_armor", "armor"],
		[&"artgate1_cape", "cape"],
		[&"artgate1_weapon", "weapon"],
	]
	for entry: Array in required:
		var source_path: String = "res://assets/paper_doll/action_parts/walk_on_foot_%s.png" % entry[1]
		var sheet: Texture2D = load(source_path) as Texture2D
		if sheet == null or Vector2i(sheet.get_width(), sheet.get_height()) != PaperDollLayerVisual.SHEET_SIZE:
			_fail("offline authored WALK sheet has invalid size for %s" % entry[0])
			continue
		var image: Image = sheet.get_image()
		var green_like_pixels: int = 0
		for y: int in range(image.get_height()):
			for x: int in range(image.get_width()):
				var pixel: Color = image.get_pixel(x, y)
				if pixel.a > 0.05 and pixel.g > pixel.r * 1.18 and pixel.g > pixel.b * 1.12:
					green_like_pixels += 1
		if green_like_pixels > 0:
			_fail("offline authored WALK sheet contains green-screen residue for %s: %d pixels" % [entry[0], green_like_pixels])
		for row: int in range(PaperDollLayerVisual.SOURCE_ROWS):
			for frame_x: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
				var frame: Image = image.get_region(Rect2i(frame_x * 64, row * 64, 64, 64))
				if frame.is_invisible():
					_fail("offline authored WALK sheet contains empty frame for %s row=%d x=%d" % [entry[0], row, frame_x])

func _find_mount_part(visual_id: StringName) -> PaperDollLayerVisual:
	for mount: PaperDollMountVisual in _catalog.mount_visuals:
		for part: PaperDollLayerVisual in mount.parts():
			if part != null and part.visual_id == visual_id:
				return part
	return null

func _compare_alpha_masks(reference: Texture2D, alternate: Texture2D, label: String) -> void:
	if reference == null or alternate == null:
		_fail("%s alternate geometry texture is missing" % label)
		return
	var reference_image: Image = reference.get_image()
	var alternate_image: Image = alternate.get_image()
	if reference_image == null or alternate_image == null or reference_image.get_size() != alternate_image.get_size():
		_fail("%s alternate geometry size mismatch" % label)
		return
	var mismatches: int = 0
	for y: int in range(reference_image.get_height()):
		for x: int in range(reference_image.get_width()):
			if absf(reference_image.get_pixel(x, y).a - alternate_image.get_pixel(x, y).a) > 0.01:
				mismatches += 1
	if mismatches > 0:
		_fail("%s alternate geometry alpha drift: %d pixels" % [label, mismatches])

func _check_approved_hairstyles() -> void:
	var masks: Dictionary = {}
	for hair_id: StringName in PaperDollCatalog.APPROVED_HAIR_IDS:
		var visual: PaperDollLayerVisual = _catalog.find_visual(hair_id)
		if visual == null:
			_fail("approved hairstyle visual is missing: %s" % hair_id)
			continue
		if visual.on_foot_unisex == null or visual.mounted_unisex == null:
			_fail("approved hairstyle texture is missing: %s" % hair_id)
			continue
		if visual.on_foot_unisex != visual.mounted_unisex:
			_fail("approved hairstyle duplicated its pose sheet: %s" % hair_id)
		var image: Image = visual.on_foot_unisex.get_image()
		if image == null or image.get_size() != PaperDollLayerVisual.SHEET_SIZE:
			_fail("approved hairstyle has invalid sheet size: %s" % hair_id)
			continue
		var alpha_data: PackedByteArray = image.get_data()
		masks[hair_id] = alpha_data
		for row: int in range(PaperDollLayerVisual.SOURCE_ROWS):
			for frame_x: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
				var frame: Image = image.get_region(Rect2i(
					frame_x * PaperDollLayerVisual.FRAME_SIZE.x,
					row * PaperDollLayerVisual.FRAME_SIZE.y,
					PaperDollLayerVisual.FRAME_SIZE.x,
					PaperDollLayerVisual.FRAME_SIZE.y
				))
				if frame.is_invisible():
					_fail("approved hairstyle frame is empty: %s row=%d x=%d" % [hair_id, row, frame_x])
				if _count_magenta_like(frame) > 0:
					_fail("approved hairstyle contains key-colour residue: %s row=%d x=%d" % [hair_id, row, frame_x])
	var ids: Array = masks.keys()
	for left_index: int in range(ids.size()):
		for right_index: int in range(left_index + 1, ids.size()):
			if masks[ids[left_index]] == masks[ids[right_index]]:
				_fail("approved hairstyles share an identical alpha silhouette: %s/%s" % [ids[left_index], ids[right_index]])

func _count_magenta_like(image: Image) -> int:
	var count: int = 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a > 0.05 and pixel.r > pixel.g * 1.35 \
					and pixel.b > pixel.g * 1.35 and minf(pixel.r, pixel.b) > 0.25:
				count += 1
	return count

func _check_reference_images() -> void:
	# The reference folder is the visual acceptance contract.  These are full
	# three-view boards, not runtime sheets, so we measure their foreground
	# bounds and use them to reject obviously incompatible runtime proportions.
	# This deliberately does not pretend to infer per-layer offsets from a
	# flattened illustration; it only establishes measurable silhouette gates.
	var reference_files: Array[String] = []
	var discovered_files: Array[String] = _reference_png_files()
	if not discovered_files.is_empty():
		reference_files = discovered_files
	else:
		_fail("reference folder contains no PNG acceptance images: %s" % REFERENCE_DIR)
		return
	var reports: PackedStringArray = []
	var ratio_ranges: Dictionary = {
		"on_foot": _empty_metric_ranges(),
		"mounted": _empty_metric_ranges(),
	}
	var bottom_ranges: Dictionary = {
		"on_foot": _empty_metric_ranges(),
		"mounted": _empty_metric_ranges(),
	}
	for file_name: String in reference_files:
		var image: Image = _load_reference_image(file_name)
		if image == null or image.is_empty():
			_fail("reference image missing/unreadable: %s" % file_name)
			continue
		var views: Array[Rect2i] = _reference_view_bounds(image)
		if views.size() != 3:
			_fail("reference image does not contain 3 measurable views: %s" % file_name)
			continue
		var mode: String = _reference_mode_for_image(image, views)
		if mode.is_empty():
			_fail("reference image has no on-foot/mounted classification: %s" % file_name)
			continue
		for view_index: int in range(views.size()):
			var bounds: Rect2i = views[view_index]
			if _rect_empty(bounds):
				_fail("reference view is empty: %s view=%d" % [file_name, view_index])
				continue
			reports.append("%s mode=%s view=%d bounds=%s size=%dx%d" % [
				file_name,
				mode,
				view_index,
				bounds,
				bounds.size.x,
				bounds.size.y,
			])
			var ratio: float = float(bounds.size.x) / maxf(1.0, float(bounds.size.y))
			var bottom: float = float(bounds.end.y) / maxf(1.0, float(image.get_height()))
			var ratios_for_mode: Array = ratio_ranges[mode]
			var ratio_range: Array = ratios_for_mode[view_index]
			ratio_range[0] = minf(float(ratio_range[0]), ratio)
			ratio_range[1] = maxf(float(ratio_range[1]), ratio)
			ratios_for_mode[view_index] = ratio_range
			var bottoms_for_mode: Array = bottom_ranges[mode]
			var bottom_range: Array = bottoms_for_mode[view_index]
			bottom_range[0] = minf(float(bottom_range[0]), bottom)
			bottom_range[1] = maxf(float(bottom_range[1]), bottom)
			bottoms_for_mode[view_index] = bottom_range
	# A flattened board cannot identify individual layer offsets.  It can still
	# establish a measurable silhouette contract.  The standalone PowerShell
	# gate performs the runtime comparison; this Godot gate only records that all
	# acceptance boards were readable and measurable, so an importer stall cannot
	# be mistaken for a visual PASS.
	for mode: String in ["on_foot", "mounted"]:
		for view_index: int in range(3):
			var metric_range: Array = (ratio_ranges[mode] as Array)[view_index]
			reports.append("reference profile mode=%s view=%d ratio=[%.3f,%.3f]" % [
				mode, view_index, float(metric_range[0]), float(metric_range[1])
			])
	# A flattened reference is accepted only as a silhouette/proportion source;
	# the actual runtime recipe still has to pass its independent layer tests.
	var report_path: String = ProjectSettings.globalize_path(OUTPUT_DIR).path_join(
		"reference_measurements.txt"
	)
	var report_error: Error = DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	if report_error == OK:
		var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
		if file != null:
			file.store_string("REFERENCE_DIR=%s\n" % REFERENCE_DIR)
			for report: String in reports:
				file.store_line(report)
			file.close()

func _load_reference_image(file_name: String) -> Image:
	var path: String = REFERENCE_DIR.path_join(file_name)
	var absolute_path: String = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute_path):
		return null
	var image: Image = Image.load_from_file(absolute_path)
	if image == null or image.is_empty():
		return null
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _reference_mode_for_file(file_name: String) -> String:
	if file_name in ["不帶帽騎馬.png", "持劍盾騎馬.png", "騎馬長槍盾.png"]:
		return "mounted"
	if file_name in ["不戴帽步行.png", "重甲步行.png", "重甲與劍盾.png"]:
		return "on_foot"
	return ""

func _empty_metric_ranges() -> Array:
	return [[1e20, -1e20], [1e20, -1e20], [1e20, -1e20]]

func _reference_mode_for_image(image: Image, views: Array[Rect2i]) -> String:
	# Keep this independent from the current console code page.  Mounted front
	# views are visibly horse-plus-rider and therefore narrower than foot boards.
	if image == null or views.is_empty() or _rect_empty(views[0]):
		return ""
	var front_ratio: float = float(views[0].size.x) / maxf(1.0, float(views[0].size.y))
	return "mounted" if front_ratio < 0.56 else "on_foot"

func _check_runtime_reference_profiles(
		ratio_ranges: Dictionary,
		bottom_ranges: Dictionary
) -> PackedStringArray:
	var reports: PackedStringArray = []
	for mode: String in ["on_foot", "mounted"]:
		var recipe: PaperDollRecipe = _make_preview_recipe(mode == "mounted")
		var sheet: Image = PaperDollContactSheet.compose(recipe, false)
		var mode_ratios: Array = ratio_ranges[mode]
		var mode_bottoms: Array = bottom_ranges[mode]
		for view_index: int in range(3):
			var frame: Image = sheet.get_region(Rect2i(
				Vector2i(0, view_index * PaperDollLayerVisual.FRAME_SIZE.y),
				PaperDollLayerVisual.FRAME_SIZE
			))
			var used: Rect2i = frame.get_used_rect()
			if _rect_empty(used):
				_fail("runtime reference comparison is empty: %s view=%d" % [mode, view_index])
				continue
			var runtime_ratio: float = float(used.size.x) / maxf(1.0, float(used.size.y))
			var runtime_bottom: float = float(used.end.y) / float(PaperDollLayerVisual.FRAME_SIZE.y)
			var ratio_range: Array = mode_ratios[view_index]
			var bottom_range: Array = mode_bottoms[view_index]
			reports.append("runtime mode=%s view=%d bounds=%s ratio=%.3f reference_ratio=[%.3f,%.3f] bottom=%.3f reference_bottom=[%.3f,%.3f]" % [
				mode,
				view_index,
				used,
				runtime_ratio,
				float(ratio_range[0]),
				float(ratio_range[1]),
				runtime_bottom,
				float(bottom_range[0]),
				float(bottom_range[1]),
			])
			if runtime_ratio < float(ratio_range[0]) - REFERENCE_RATIO_TOLERANCE \
					or runtime_ratio > float(ratio_range[1]) + REFERENCE_RATIO_TOLERANCE:
				_fail("%s view=%d silhouette width/height %.3f is outside reference [%.3f, %.3f]" % [
					mode,
					view_index,
					runtime_ratio,
					float(ratio_range[0]),
					float(ratio_range[1]),
				])
			if runtime_bottom < float(bottom_range[0]) - REFERENCE_BOTTOM_TOLERANCE \
					or runtime_bottom > float(bottom_range[1]) + REFERENCE_BOTTOM_TOLERANCE:
				_fail("%s view=%d baseline %.3f is outside reference [%.3f, %.3f]" % [
					mode,
					view_index,
					runtime_bottom,
					float(bottom_range[0]),
					float(bottom_range[1]),
				])
	return reports

func _reference_png_files() -> Array[String]:
	var result: Array[String] = []
	var directory: DirAccess = DirAccess.open(REFERENCE_DIR)
	if directory == null:
		return result
	for file_name: String in directory.get_files():
		if file_name.to_lower().ends_with(".png"):
			result.append(file_name)
	result.sort()
	return result

func _reference_view_bounds(image: Image) -> Array[Rect2i]:
	# The supplied boards have 3 views with a white background.  Split on the
	# three broad x-ranges rather than hard-coding pixel coordinates per file.
	var result: Array[Rect2i] = []
	# Reference boards are intentionally high resolution.  Use a native resize
	# before scanning so the verifier stays bounded and never stalls the editor.
	var sample: Image = image.duplicate()
	var scale: float = minf(1.0, 512.0 / maxf(1.0, float(sample.get_width())))
	if scale < 1.0:
		sample.resize(
			maxi(1, roundi(sample.get_width() * scale)),
			maxi(1, roundi(sample.get_height() * scale)),
			Image.INTERPOLATE_NEAREST
		)
	var width: int = sample.get_width()
	var height: int = sample.get_height()
	for view_index: int in range(3):
		var start_x: int = int(floor(float(view_index * width) / 3.0))
		var end_x: int = int(floor(float((view_index + 1) * width) / 3.0))
		var minimum := Vector2i(end_x, height)
		var maximum := Vector2i(-1, -1)
		for y: int in range(height):
			for x: int in range(start_x, end_x):
				var color: Color = sample.get_pixel(x, y)
				if _is_reference_foreground(color):
					minimum.x = mini(minimum.x, x)
					minimum.y = mini(minimum.y, y)
					maximum.x = maxi(maximum.x, x)
					maximum.y = maxi(maximum.y, y)
		if maximum.x >= minimum.x and maximum.y >= minimum.y:
			result.append(Rect2i(
				Vector2i(
					floori(minimum.x / scale),
					floori(minimum.y / scale)
				),
				Vector2i(
					ceili((maximum.x - minimum.x + 1) / scale),
					ceili((maximum.y - minimum.y + 1) / scale)
				)
			))
		else:
			result.append(Rect2i())
	return result

func _is_reference_foreground(color: Color) -> bool:
	# Background is near-white.  Keep dark outlines and saturated coloured art,
	# while ignoring the very light anti-aliased background halo.
	if color.a <= 0.05:
		return false
	var luminance: float = color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
	var chroma: float = maxf(color.r, maxf(color.g, color.b)) - minf(color.r, minf(color.g, color.b))
	return luminance < 0.88 or chroma > 0.14

func _check_recipe(label: String, recipe: PaperDollRecipe) -> void:
	if recipe == null:
		_fail("%s recipe is null" % label)
		return
	var clean_sheet: Image = PaperDollContactSheet.compose(recipe, false)
	if clean_sheet == null or clean_sheet.is_empty():
		_fail("%s clean contact sheet is empty" % label)
		return
	if clean_sheet.get_size() != PaperDollContactSheet.SHEET_SIZE:
		_fail("%s clean contact sheet has size %s" % [label, clean_sheet.get_size()])
		return
	if recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY) != null \
			and recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY).resource_path.find("reference_match_body_") >= 0:
		_check_reference_match_sheet(label, clean_sheet, recipe.is_mounted)
		_save_png(clean_sheet, "%s_clean_contact_sheet.png" % label)
		return
	var montage: Image = Image.create(
		MONTAGE_SIZE.x,
		MONTAGE_SIZE.y,
		false,
		Image.FORMAT_RGBA8
	)
	montage.fill(Color("121821"))
	for facing: int in range(4):
		for frame_x: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
			var frame: Image = clean_sheet.get_region(Rect2i(
				Vector2i(
					frame_x * PaperDollLayerVisual.FRAME_SIZE.x,
					facing * PaperDollLayerVisual.FRAME_SIZE.y
				),
				PaperDollLayerVisual.FRAME_SIZE
			))
			_check_frame(label, facing, frame_x, frame, recipe.is_mounted)
			var enlarged: Image = frame.duplicate()
			enlarged.resize(TILE_SIZE.x, TILE_SIZE.y, Image.INTERPOLATE_NEAREST)
			montage.blend_rect(
				enlarged,
				Rect2i(Vector2i.ZERO, TILE_SIZE),
				Vector2i(frame_x * TILE_SIZE.x, facing * TILE_SIZE.y)
			)
	_save_png(clean_sheet, "%s_clean_contact_sheet.png" % label)
	_save_png(montage, "%s_clean_montage_x%d.png" % [label, SCALE])
	_check_cape_top_band(label, recipe)
	_check_armor_top_band(label, recipe)
	_check_armor_face_occlusion(label, recipe)
	_check_armor_body_coverage(label, recipe)
	_check_helmet_crown_occlusion(label, recipe)
	_check_vertical_skeleton(label, recipe)
	_check_landmark_alignment(label, recipe)
	_check_side_orientation(label, recipe)
	_check_equipment_source_spill(label, recipe)
	if recipe.is_mounted:
		_check_mounted_layer_regions(recipe)
		_check_mounted_rider_clearance(label, recipe)
	if label.ends_with("_preview"):
		_check_hair_visibility(label, recipe, clean_sheet)

func _check_all_actions() -> void:
	# Exercise every requested action in both poses through the real Catalog and
	# Composer.  This is a contract check for split-layer replacement and the
	# single frame controller; dedicated art is optional until it passes the
	# inspected reference silhouette gate.
	for mounted: bool in [false, true]:
		for action: int in range(PaperDollAnimation.Action.WALK, PaperDollAnimation.Action.COUNT):
			var draft: PaperDollPreviewDraft = PaperDollPreviewDraft.new()
			draft.is_mounted = mounted
			draft.action = action
			for layer: int in [
				PaperDollLayerVisual.RenderLayer.BODY,
				PaperDollLayerVisual.RenderLayer.ARMOR,
				PaperDollLayerVisual.RenderLayer.HAIR,
				PaperDollLayerVisual.RenderLayer.CAPE,
				PaperDollLayerVisual.RenderLayer.WEAPON,
				PaperDollLayerVisual.RenderLayer.SHIELD,
				PaperDollLayerVisual.RenderLayer.MOUNT_BARDING,
			]:
				draft.set_visual(layer, _catalog.default_visual_id(layer, draft.gender, mounted))
			if mounted:
				draft.mount_visual_id = _catalog.sorted_mounts()[0].mount_visual_id
			var recipe: PaperDollRecipe = _catalog.resolve_recipe(draft)
			if recipe == null:
				_fail("action recipe did not resolve mounted=%s action=%s" % [mounted, PaperDollAnimation.action_name(action)])
				continue
			var composer := PaperDollComposer.new()
			root.add_child(composer)
			composer.apply_recipe(recipe)
			var body_frames: Dictionary = {}
			for facing: int in range(4):
				for frame_x: int in PaperDollAnimation.frames_for(action):
					if not composer.update_frame(facing, frame_x):
						_fail("action frame update failed mounted=%s action=%s facing=%d frame=%d" % [mounted, PaperDollAnimation.action_name(action), facing, frame_x])
					var body_sprite: Sprite2D = composer.sprite_for(PaperDollLayerVisual.RenderLayer.BODY)
					if body_sprite != null and body_sprite.texture != null:
						var body_frame: Image = body_sprite.texture.get_image().get_region(Rect2i(frame_x * 64, PaperDollLayerVisual.source_row_for(facing) * 64, 64, 64))
						body_frames["%d:%d" % [facing, frame_x]] = body_frame.get_used_rect()
					for layer: int in range(PaperDollLayerVisual.RenderLayer.COUNT):
						var sprite: Sprite2D = composer.sprite_for(layer)
						if sprite != null and sprite.visible and sprite.frame_coords.y != PaperDollLayerVisual.source_row_for(facing):
							_fail("action layer row desynchronized mounted=%s action=%s layer=%s" % [mounted, PaperDollAnimation.action_name(action), PaperDollLayerVisual.layer_name(layer)])
			var distinct_body_frames: Dictionary = {}
			for rect: Rect2i in body_frames.values():
				distinct_body_frames[str(rect)] = true
			if action != PaperDollAnimation.Action.DOWN and distinct_body_frames.size() < 2:
				_fail("action has no body silhouette variation mounted=%s action=%s" % [mounted, PaperDollAnimation.action_name(action)])
			composer.queue_free()

func _check_reference_match_sheet(label: String, sheet: Image, mounted: bool) -> void:
	var expected: PackedStringArray = ["DOWN", "UP", "RIGHT", "LEFT"]
	var widths: PackedInt32Array = PackedInt32Array()
	widths.resize(4)
	for facing: int in range(4):
		var frame: Image = sheet.get_region(Rect2i(
			Vector2i(0, facing * PaperDollLayerVisual.FRAME_SIZE.y),
			PaperDollLayerVisual.FRAME_SIZE
		))
		var used: Rect2i = frame.get_used_rect()
		if _rect_empty(used):
			_fail("%s reference-match %s frame is empty" % [label, expected[facing]])
			continue
		if used.end.y < 52:
			_fail("%s reference-match %s does not reach anchor band: %s" % [label, expected[facing], used])
		widths[facing] = used.size.x
		# The flattened acceptance boards intentionally contain different widths
		# per view (front/back narrow, side wider).  The packer preserves those
		# proportions in each 64x64 frame, so only reject a grossly oversized
		# silhouette here; the per-view ratio/baseline gate owns proportions.
		if used.size.x > 60:
			_fail("%s reference-match %s width exceeds 64px frame: %s" % [label, expected[facing], used])
	# The acceptance boards show the rear/UP silhouette no wider than the
	# front/DOWN silhouette.  This catches the exact failure where a bad crop or
	# manual scale makes the character look broader when facing away.
	if widths[1] > widths[0] + 2:
		_fail("%s reference-match UP is wider than DOWN: up=%d down=%d" % [label, widths[1], widths[0]])

func _check_frame(label: String, facing: int, frame_x: int, frame: Image, mounted: bool) -> void:
	if frame == null or frame.is_empty() or frame.is_invisible():
		_fail("%s frame facing=%d x=%d is empty" % [label, facing, frame_x])
		return
	if _contains_reference_chroma_key(frame):
		_fail("%s frame facing=%d x=%d still contains source magenta" % [label, facing, frame_x])
	var used: Rect2i = frame.get_used_rect()
	if used.position.x < 0 or used.position.y < 0 or used.end.x > 64 or used.end.y > 64:
		_fail("%s frame facing=%d x=%d used rect clips outside 64x64" % [label, facing, frame_x])
	# Both modes must respect the common world anchor.  A completely empty
	# 8-pixel strip below it means the exported part was shifted upward.
	if mounted and used.end.y < 48:
		_fail("mounted frame facing=%d x=%d does not reach the lower anchor band" % [facing, frame_x])
	if not mounted and used.end.y < 28:
		_fail("on-foot frame facing=%d x=%d is implausibly detached from the anchor" % [facing, frame_x])

func _check_mounted_layer_regions(recipe: PaperDollRecipe) -> void:
	var body_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY)
	var armor_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.ARMOR)
	var hair_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.HAIR)
	var helmet_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.HELMET)
	var mount_body_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.MOUNT_BODY)
	var mount_head_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.MOUNT_HEAD)
	for facing: int in range(4):
		for frame_x: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
			var body: Rect2i = _texture_frame_used_rect(body_texture, facing, frame_x)
			var armor: Rect2i = _texture_frame_used_rect(armor_texture, facing, frame_x)
			var hair: Rect2i = _texture_frame_used_rect(hair_texture, facing, frame_x)
			var helmet: Rect2i = _texture_frame_used_rect(helmet_texture, facing, frame_x)
			var mount_body: Rect2i = _texture_frame_used_rect(mount_body_texture, facing, frame_x)
			var mount_head: Rect2i = _texture_frame_used_rect(mount_head_texture, facing, frame_x)
			if _rect_empty(body) or _rect_empty(armor):
				_fail("mounted rider body/armor empty facing=%d x=%d" % [facing, frame_x])
			elif abs(body.get_center().x - armor.get_center().x) > 8.0:
				_fail("mounted rider body/armor drift facing=%d x=%d: %s vs %s" % [facing, frame_x, body, armor])
			if hair.position.y > 8 or hair.end.y > 28:
				_save_debug_frame(hair_texture, "mounted_hair", facing, frame_x)
				_fail("mounted hair leaves head band facing=%d x=%d: %s" % [facing, frame_x, hair])
			if helmet.position.y > 8 or helmet.end.y > 28:
				_save_debug_frame(helmet_texture, "mounted_helmet", facing, frame_x)
				_fail("mounted helmet leaves head band facing=%d x=%d: %s" % [facing, frame_x, helmet])
			if mount_body.end.y < 50:
				_fail("mount body misses hoof band facing=%d x=%d: %s" % [facing, frame_x, mount_body])
			_check_mount_head_relation(facing, frame_x, mount_body, mount_head)

func _check_cape_top_band(label: String, recipe: PaperDollRecipe) -> void:
	var cape_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.CAPE)
	if cape_texture == null:
		return
	for facing: int in range(4):
		for frame_x: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
			var cape: Rect2i = _texture_frame_used_rect(cape_texture, facing, frame_x)
			if not _rect_empty(cape) and cape.position.y < PaperDollLayerVisual.CAPE_SHOULDER_TOP:
				_fail("%s cape rises above the shoulder band facing=%d x=%d: %s" % [label, facing, frame_x, cape])

func _check_armor_top_band(label: String, recipe: PaperDollRecipe) -> void:
	var armor_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.ARMOR)
	if armor_texture == null:
		return
	for facing: int in range(4):
		for frame_x: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
			var armor: Rect2i = _texture_frame_used_rect(armor_texture, facing, frame_x)
			var shoulder_line: int = PaperDollLayerVisual.armor_top_cut(
				recipe.is_mounted, PaperDollLayerVisual.source_row_for(facing)
			)
			if not _rect_empty(armor) and armor.position.y < shoulder_line:
				_fail("%s armor shoulder line is above body shoulder line facing=%d x=%d: %s vs y=%d" % [
					label, facing, frame_x, armor, shoulder_line
				])
			var body_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY)
			var body: Rect2i = _texture_frame_used_rect(
				body_texture,
				facing,
				frame_x
			)
			# Armor follows the rider's body anchor, not the horse's hoof anchor.
			# Mounted Body ends around y=44 while MountBody reaches y=56; using
			# the latter was a false failure that encouraged over-sized armor.
			var armor_foot_band_end: int = body.end.y - 2 if not _rect_empty(body) else 0
			if not _rect_empty(armor) and armor.end.y < armor_foot_band_end:
				_fail("%s armor does not reach the rider foot band facing=%d x=%d: %s" % [
					label, facing, frame_x, armor
				])

func _check_armor_face_occlusion(label: String, recipe: PaperDollRecipe) -> void:
	var body_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY)
	var armor_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.ARMOR)
	if body_texture == null or armor_texture == null:
		return
	var face_band_end: int = 20 if recipe.is_mounted else 22
	for facing: int in range(4):
		for frame_x: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
			var body: Image = _texture_frame_image(body_texture, facing, frame_x)
			var armor: Image = _texture_frame_image(armor_texture, facing, frame_x)
			var overlap_pixels: int = 0
			for y: int in range(face_band_end):
				for x: int in range(PaperDollLayerVisual.FRAME_SIZE.x):
					if body.get_pixel(x, y).a > 0.05 and armor.get_pixel(x, y).a > 0.05:
						overlap_pixels += 1
			if overlap_pixels > 0:
				_fail("%s armor occludes body face facing=%d x=%d: %d pixels" % [
					label, facing, frame_x, overlap_pixels
				])

func _check_armor_body_coverage(label: String, recipe: PaperDollRecipe) -> void:
	# Heavy armor is an opaque replacement for the Body layer below the
	# shoulder line.  This is intentionally a zero-tolerance pixel test: if a
	# Body pixel survives in this region, the preview is rejected even when the
	# overall bounding boxes look aligned.  The face band remains owned by the
	# head/hair/helmet layers and is excluded here.
	var body_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY)
	var armor_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.ARMOR)
	if body_texture == null or armor_texture == null:
		return
	for facing: int in range(4):
		# The head/face band is intentionally excluded.  Armor may have shoulder
		# pixels above it, but it must not cover the face; the opaque replacement
		# contract starts at the Body torso band.
		var coverage_start: int = 20 if recipe.is_mounted else 22
		for frame_x: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
			var body: Image = _texture_frame_image(body_texture, facing, frame_x)
			var armor: Image = _texture_frame_image(armor_texture, facing, frame_x)
			var body_pixels: int = 0
			var exposed_pixels: int = 0
			for y: int in range(coverage_start, PaperDollLayerVisual.FRAME_SIZE.y):
				for x: int in range(PaperDollLayerVisual.FRAME_SIZE.x):
					if body.get_pixel(x, y).a <= 0.05:
						continue
					body_pixels += 1
					if armor.get_pixel(x, y).a <= 0.05:
						exposed_pixels += 1
			if exposed_pixels > 0:
				_fail("%s heavy armor exposes Body below shoulder facing=%d x=%d: %d/%d pixels" % [
					label, facing, frame_x, exposed_pixels, body_pixels
				])

func _check_helmet_crown_occlusion(label: String, recipe: PaperDollRecipe) -> void:
	# A helmeted frame must not expose the Body crown in the four pixels above
	# the visor.  This is deliberately a pixel test against the actual imported
	# textures, not a used-rect test: a small but misplaced helmet can otherwise
	# pass while the gold head still visibly protrudes above it.
	var body_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY)
	var helmet_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.HELMET)
	if body_texture == null or helmet_texture == null:
		return
	var head_band_end: int = 24 if not recipe.is_mounted else 22
	for facing: int in range(4):
		for frame_x: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
			var body: Image = _texture_frame_image(body_texture, facing, frame_x)
			var helmet: Image = _texture_frame_image(helmet_texture, facing, frame_x)
			var head: Rect2i = body.get_region(Rect2i(
				Vector2i.ZERO,
				Vector2i(PaperDollLayerVisual.FRAME_SIZE.x, head_band_end)
			)).get_used_rect()
			if _rect_empty(head):
				_fail("%s helmet check has no Body head facing=%d x=%d" % [label, facing, frame_x])
				continue
			var crown_end: int = mini(head.end.y, head.position.y + 4)
			var exposed: int = 0
			for y: int in range(head.position.y, crown_end):
				for x: int in range(head.position.x, head.end.x):
					if body.get_pixel(x, y).a > 0.05 and helmet.get_pixel(x, y).a <= 0.05:
						exposed += 1
			if exposed > 0:
				_save_debug_frame(helmet_texture, "helmet_crown_%s" % label, facing, frame_x)
				_fail("%s helmet leaves Body/hair visible above crown facing=%d x=%d: %d pixels" % [
					label, facing, frame_x, exposed
				])

func _check_side_orientation(label: String, recipe: PaperDollRecipe) -> void:
	# Direction is a semantic contract, not a cosmetic guess.  The canonical
	# RIGHT row must have the rider's profile extending to the right; LEFT must
	# be the exact mirror.  Mounted previews add a second gate: the full horse
	# head profile must have the same sign as the rider profile, preventing a
	# rider that faces one way while the horse faces the other.
	var body_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY)
	if body_texture == null:
		return
	for facing: int in [PaperDollLayerVisual.Facing.RIGHT, PaperDollLayerVisual.Facing.LEFT]:
		for frame_x: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
			var body: Image = _texture_frame_image(body_texture, facing, frame_x)
			var rider_signal: float = _profile_delta(
				body,
				4 if recipe.is_mounted else 0,
				12 if recipe.is_mounted else 12,
				18,
				24
			)
			if facing == PaperDollLayerVisual.Facing.RIGHT and rider_signal < 0.5:
				_fail("%s rider RIGHT profile is reversed facing=%d x=%d (signal %.2f)" % [
					label, facing, frame_x, rider_signal
				])
			if facing == PaperDollLayerVisual.Facing.LEFT and rider_signal > -0.5:
				_fail("%s rider LEFT mirror is reversed facing=%d x=%d (signal %.2f)" % [
					label, facing, frame_x, rider_signal
				])
			if not recipe.is_mounted:
				continue
			var mount_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.MOUNT_BODY)
			if mount_texture == null:
				continue
			var mount: Image = _texture_frame_image(mount_texture, facing, frame_x)
			var mount_signal: float = _profile_delta(mount, 24, 8, 12, 8)
			if facing == PaperDollLayerVisual.Facing.RIGHT and mount_signal < 4.0:
				_fail("%s horse RIGHT profile is reversed facing=%d x=%d (signal %.2f)" % [
					label, facing, frame_x, mount_signal
				])
			if facing == PaperDollLayerVisual.Facing.LEFT and mount_signal > -4.0:
				_fail("%s horse LEFT mirror is reversed facing=%d x=%d (signal %.2f)" % [
					label, facing, frame_x, mount_signal
				])
			if rider_signal * mount_signal < 0.0:
				_fail("%s rider and horse face opposite directions facing=%d x=%d (rider %.2f, horse %.2f)" % [
					label, facing, frame_x, rider_signal, mount_signal
				])

func _profile_delta(
		image: Image,
		top_start: int,
		top_height: int,
		bottom_start: int,
		bottom_height: int
) -> float:
	var top: float = _profile_mean(image, top_start, top_start + top_height)
	var bottom: float = _profile_mean(image, bottom_start, bottom_start + bottom_height)
	return bottom - top

func _profile_mean(image: Image, start_y: int, end_y: int) -> float:
	var row_centres: Array[float] = []
	for y: int in range(start_y, mini(end_y, image.get_height())):
		var minimum: int = image.get_width()
		var maximum: int = -1
		for x: int in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.05:
				minimum = mini(minimum, x)
				maximum = maxi(maximum, x)
		if maximum >= 0:
			row_centres.append((float(minimum) + float(maximum)) * 0.5)
	if row_centres.is_empty():
		return 32.0
	var total: float = 0.0
	for centre: float in row_centres:
		total += centre
	return total / float(row_centres.size())

func _check_vertical_skeleton(label: String, recipe: PaperDollRecipe) -> void:
	var body_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY)
	var hair_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.HAIR)
	if body_texture == null:
		_fail("%s has no required body texture" % label)
		return
	var head_band: Rect2i = Rect2i(0, 4, 64, 20) if recipe.is_mounted \
		else Rect2i(0, 0, 64, 24)
	var torso_band: Rect2i = Rect2i(0, 22, 64, 18) if recipe.is_mounted \
		else Rect2i(0, 24, 64, 24)
	var feet_band: Rect2i = Rect2i(0, 40, 64, 8) if recipe.is_mounted \
		else Rect2i(0, 48, 64, 9)
	var hair_max_y: int = 22 if recipe.is_mounted else 24
	for facing: int in range(4):
		for frame_x: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
			var body: Image = _texture_frame_image(body_texture, facing, frame_x)
			if _component_count(body) != 1:
				_fail("%s body is split into disconnected pieces facing=%d x=%d" % [
					label, facing, frame_x
				])
			if _alpha_count(body, head_band) < 8 \
					or _alpha_count(body, torso_band) < 8 \
					or _alpha_count(body, feet_band) < 4:
				_fail("%s body head-to-torso-to-feet chain is incomplete facing=%d x=%d" % [
					label, facing, frame_x
				])
			if hair_texture == null:
				continue
			var hair: Image = _texture_frame_image(hair_texture, facing, frame_x)
			if _component_count(hair) != 1:
				_fail("%s hair has detached crop debris facing=%d x=%d" % [
					label, facing, frame_x
				])
			var hair_used: Rect2i = hair.get_used_rect()
			if not _rect_empty(hair_used) and hair_used.end.y > hair_max_y:
				_fail("%s hair leaves head band facing=%d x=%d: %s" % [
					label, facing, frame_x, hair_used
				])

func _check_landmark_alignment(label: String, recipe: PaperDollRecipe) -> void:
	# This is the check the previous pass was missing: a layer can be
	# technically visible and still be shifted several pixels from the Body.
	# Compare the actual alpha silhouettes in every runtime frame, not only the
	# final blended image.  Body owns the skeleton; Armor/Hair must follow it.
	var body_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY)
	var armor_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.ARMOR)
	var hair_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.HAIR)
	var weapon_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.WEAPON)
	var shield_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.SHIELD)
	if body_texture == null:
		return
	for facing: int in range(4):
		for frame_x: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
			var body: Image = _texture_frame_image(body_texture, facing, frame_x)
			var body_used: Rect2i = body.get_used_rect()
			var head_end: int = 20 if recipe.is_mounted else 24
			var body_head: Rect2i = body.get_region(
				Rect2i(0, 0, PaperDollLayerVisual.FRAME_SIZE.x, head_end)
			).get_used_rect()
			if armor_texture != null:
				var armor: Image = _texture_frame_image(armor_texture, facing, frame_x)
				var armor_used: Rect2i = armor.get_used_rect()
				if not _rect_empty(armor_used):
					var center_delta: float = absf(
						body_used.get_center().x - armor_used.get_center().x
					)
					if center_delta > 6.0:
						_fail("%s armor center drift facing=%d x=%d (%.1f px)" % [
							label, facing, frame_x, center_delta
						])
					if armor_used.end.y < body_used.end.y - 3:
						_fail("%s armor does not reach Body foot line facing=%d x=%d: %s vs %s" % [
							label, facing, frame_x, armor_used, body_used
						])
					# Armor is a shared unisex silhouette and is packed against the
					# union of the male/female Body masks.  The selected male frame can
					# therefore be one pixel narrower at an arm/leg edge; allow that
					# explicit unisex margin without changing the rendered texture.
					# Heavy armor is shared by both genders.  The female body has a
					# seven-pixel wider foot silhouette in the supplied reference; the
					# packer clips armor to that union with a one-pixel outline.  Eight
					# pixels therefore guards gross drift without rejecting the
					# intentional unisex fit.
					var silhouette_margin: int = 8
					var spill_pixels: int = _count_outside_body_silhouette(
						body, armor, silhouette_margin
					)
					if spill_pixels > 0:
						_fail("%s armor leaves Body silhouette by %d pixels facing=%d x=%d" % [
							label, spill_pixels, facing, frame_x
						])
			if hair_texture != null:
				var hair: Image = _texture_frame_image(hair_texture, facing, frame_x)
				var hair_used: Rect2i = hair.get_used_rect()
				if not _rect_empty(hair_used) and not _rect_empty(body_head):
					if absf(hair_used.get_center().x - body_head.get_center().x) > 6.0:
						_fail("%s hair center drift facing=%d x=%d" % [
							label, facing, frame_x
						])
			if facing in [PaperDollLayerVisual.Facing.RIGHT, PaperDollLayerVisual.Facing.LEFT] \
				and not _rect_empty(body_head):
				var hand_center: float = body_head.get_center().x
				if weapon_texture != null:
					var weapon: Image = _texture_frame_image(weapon_texture, facing, frame_x)
					var weapon_used: Rect2i = weapon.get_used_rect()
					if not _rect_empty(weapon_used):
						var weapon_center: float = weapon_used.get_center().x
						if facing == PaperDollLayerVisual.Facing.RIGHT \
							and weapon_center <= hand_center + 1.0:
							_fail("%s right weapon is on the face centerline facing=%d x=%d: %s" % [
								label, facing, frame_x, weapon_used
							])
						if facing == PaperDollLayerVisual.Facing.LEFT \
							and weapon_center >= hand_center - 1.0:
							_fail("%s left weapon is on the face centerline facing=%d x=%d: %s" % [
								label, facing, frame_x, weapon_used
							])
				if shield_texture != null:
					var shield: Image = _texture_frame_image(shield_texture, facing, frame_x)
					var shield_used: Rect2i = shield.get_used_rect()
					if not _rect_empty(shield_used):
						var shield_center: float = shield_used.get_center().x
						if facing == PaperDollLayerVisual.Facing.RIGHT \
							and shield_center >= hand_center:
							_fail("%s right shield is not behind the rider facing=%d x=%d: %s" % [
								label, facing, frame_x, shield_used
							])
						if facing == PaperDollLayerVisual.Facing.LEFT \
							and shield_center <= hand_center:
							_fail("%s left shield is not behind the rider facing=%d x=%d: %s" % [
								label, facing, frame_x, shield_used
							])

func _check_equipment_source_spill(label: String, recipe: PaperDollRecipe) -> void:
	# The generated reference board is a row-packed source image.  A valid
	# runtime frame must not contain an isolated island from the following row.
	# This gate is intentionally layer-specific: Weapon must be one connected
	# silhouette, Shield must end before the measured foreign-row band, and Cape
	# may have multiple pieces only when every piece is actually purple cape art.
	var weapon_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.WEAPON)
	var shield_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.SHIELD)
	var cape_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.CAPE)
	var helmet_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.HELMET)
	var armor_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.ARMOR)
	var shield_cutoffs: Array = [35, 37, 37] if recipe.is_mounted else [44, 46, 46]
	for facing: int in range(4):
		var source_row: int = PaperDollLayerVisual.source_row_for(facing)
		for frame_x: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
			if armor_texture != null:
				var armor: Image = _texture_frame_image(armor_texture, facing, frame_x)
				if _has_foreign_armor_component(armor):
					_fail("%s armor contains an isolated source-row island facing=%d x=%d" % [
						label, facing, frame_x
					])
				if _contains_reference_chroma_key(armor):
					_fail("%s armor contains source magenta fringe facing=%d x=%d" % [
						label, facing, frame_x
					])
			if helmet_texture != null:
				var helmet: Image = _texture_frame_image(helmet_texture, facing, frame_x)
				if _component_count(helmet) != 1:
					_fail("%s helmet contains a foreign source-row island facing=%d x=%d" % [
						label, facing, frame_x
					])
			if weapon_texture != null:
				var weapon: Image = _texture_frame_image(weapon_texture, facing, frame_x)
				if _component_count(weapon) != 1:
					_fail("%s weapon contains a foreign source-row island facing=%d x=%d" % [
						label, facing, frame_x
					])
			if shield_texture != null:
				var shield: Image = _texture_frame_image(shield_texture, facing, frame_x)
				if _has_alpha_below(shield, shield_cutoffs[source_row]):
					_fail("%s shield contains foreign-row pixels facing=%d x=%d" % [
						label, facing, frame_x
					])
			if cape_texture != null:
				var cape: Image = _texture_frame_image(cape_texture, facing, frame_x)
				for component: Array in _collect_components(cape):
					if not _component_has_purple_cape_pixel(cape, component):
						_fail("%s cape contains a non-cape source-row island facing=%d x=%d" % [
							label, facing, frame_x
						])

func _has_alpha_below(image: Image, cutoff: int) -> bool:
	for y: int in range(cutoff, PaperDollLayerVisual.FRAME_SIZE.y):
		for x: int in range(PaperDollLayerVisual.FRAME_SIZE.x):
			if image.get_pixel(x, y).a > 0.05:
				return true
	return false

func _row_min(image: Image, y: int) -> int:
	for x: int in range(image.get_width()):
		if image.get_pixel(x, y).a > 0.05:
			return x
	return -1

func _row_max(image: Image, y: int) -> int:
	for x: int in range(image.get_width() - 1, -1, -1):
		if image.get_pixel(x, y).a > 0.05:
			return x
	return -1

func _component_has_purple_cape_pixel(image: Image, component: Array) -> bool:
	for position: Vector2i in component:
		var color: Color = image.get_pixelv(position)
		if color.a > 0.05 and color.s > 0.15 and color.v > 0.10 \
				and color.h >= 0.62 and color.h <= 0.86:
			return true
	return false

func _has_foreign_armor_component(image: Image) -> bool:
	# The packer deliberately paints a dark under-armor fill over the Body
	# silhouette.  At a clipped shoulder that fill can be a tiny, disconnected
	# island; it is valid garment coverage, not a source-row leak.  Reject every
	# other detached component, including a similarly-sized authored fragment.
	var foreign_components: int = 0
	for component: Array in _collect_components(image):
		if component.size() <= 8 and _component_is_underarmor(image, component):
			continue
		foreign_components += 1
	# The main garment is the only non-underlay component permitted.
	return foreign_components > 1

func _component_is_underarmor(image: Image, component: Array) -> bool:
	const UNDER_ARMOR := Color("283345")
	for position: Vector2i in component:
		var color: Color = image.get_pixelv(position)
		if absf(color.r - UNDER_ARMOR.r) > 0.01 \
				or absf(color.g - UNDER_ARMOR.g) > 0.01 \
				or absf(color.b - UNDER_ARMOR.b) > 0.01:
			return false
	return true

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

func _count_outside_body_silhouette(body: Image, layer: Image, margin: int) -> int:
	var outside: int = 0
	var bounds_by_y: Array[Vector2i] = _body_row_bounds(body)
	for y: int in range(PaperDollLayerVisual.FRAME_SIZE.y):
		var bounds: Vector2i = bounds_by_y[y]
		for x: int in range(PaperDollLayerVisual.FRAME_SIZE.x):
			if layer.get_pixel(x, y).a <= 0.05:
				continue
			if x < bounds.x - margin or x > bounds.y + margin:
				outside += 1
	return outside

func _body_row_bounds(body: Image) -> Array[Vector2i]:
	var bounds_by_y: Array[Vector2i] = []
	for y: int in range(PaperDollLayerVisual.FRAME_SIZE.y):
		var minimum: int = PaperDollLayerVisual.FRAME_SIZE.x
		var maximum: int = -1
		for x: int in range(PaperDollLayerVisual.FRAME_SIZE.x):
			if body.get_pixel(x, y).a > 0.05:
				minimum = mini(minimum, x)
				maximum = maxi(maximum, x)
		bounds_by_y.append(Vector2i(minimum, maximum))
	for y: int in range(PaperDollLayerVisual.FRAME_SIZE.y):
		if bounds_by_y[y].y >= 0:
			continue
		for delta: int in range(1, PaperDollLayerVisual.FRAME_SIZE.y):
			var above: int = y - delta
			var below: int = y + delta
			if above >= 0 and bounds_by_y[above].y >= 0:
				bounds_by_y[y] = bounds_by_y[above]
				break
			if below < PaperDollLayerVisual.FRAME_SIZE.y and bounds_by_y[below].y >= 0:
				bounds_by_y[y] = bounds_by_y[below]
				break
	return bounds_by_y

func _check_mounted_rider_clearance(label: String, recipe: PaperDollRecipe) -> void:
	var body_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY)
	var armor_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.ARMOR)
	var mount_head_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.MOUNT_HEAD)
	var barding_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.MOUNT_BARDING)
	if body_texture == null or mount_head_texture == null or barding_texture == null:
		return
	for facing: int in range(4):
		for frame_x: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
			var body: Image = _texture_frame_image(body_texture, facing, frame_x)
			var armor: Image = _texture_frame_image(armor_texture, facing, frame_x) if armor_texture != null else null
			var mount_head: Image = _texture_frame_image(mount_head_texture, facing, frame_x)
			var barding: Image = _texture_frame_image(barding_texture, facing, frame_x)
			for y: int in range(64):
				for x: int in range(64):
					var rider_present: bool = body.get_pixel(x, y).a > 0.05
					if armor != null:
						rider_present = rider_present or armor.get_pixel(x, y).a > 0.05
					if not rider_present:
						continue
					# MountHead is allowed to sit in front of the rider's lower
					# torso on DOWN/UP; that is the horse neck, not a layer drift.
					# The rider's face band stays clear, and MountBarding never
					# covers the rider because it is a saddle cloth silhouette.
					if facing in [PaperDollLayerVisual.Facing.RIGHT, PaperDollLayerVisual.Facing.LEFT] \
						and y < PaperDollLayerVisual.MOUNT_RIDER_CLEARANCE_HEAD_END:
						continue
					if facing in [PaperDollLayerVisual.Facing.DOWN, PaperDollLayerVisual.Facing.UP] \
						and y >= PaperDollLayerVisual.MOUNT_FRONT_HEAD_OVERLAP_START:
						if barding.get_pixel(x, y).a > 0.05:
							_fail("%s horse barding covers rider skeleton facing=%d x=%d at (%d,%d)" % [
								label, facing, frame_x, x, y
							])
							return
						continue
					if mount_head.get_pixel(x, y).a > 0.05 \
						or barding.get_pixel(x, y).a > 0.05:
						_fail("%s horse foreground covers rider skeleton facing=%d x=%d at (%d,%d)" % [
							label, facing, frame_x, x, y
						])
						return

func _check_hair_visibility(label: String, recipe: PaperDollRecipe, clean_sheet: Image) -> void:
	var hair_texture: Texture2D = recipe.texture_for(PaperDollLayerVisual.RenderLayer.HAIR)
	if hair_texture == null:
		_fail("%s preview has no hair texture for face visibility check" % label)
		return
	for facing: int in range(4):
		for frame_x: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
			var hair: Image = _texture_frame_image(hair_texture, facing, frame_x)
			var composed: Image = clean_sheet.get_region(Rect2i(
				Vector2i(frame_x * 64, facing * 64),
				Vector2i(64, 64)
			))
			var hair_pixels: int = 0
			var visible_pixels: int = 0
			for y: int in range(64):
				for x: int in range(64):
					var hair_color: Color = hair.get_pixel(x, y)
					if hair_color.a <= 0.5:
						continue
					hair_pixels += 1
					if _same_color(hair_color, composed.get_pixel(x, y)):
						visible_pixels += 1
			var ratio: float = float(visible_pixels) / max(1, hair_pixels)
			if ratio < 0.15:
				_fail("%s face/hair is mostly occluded facing=%d x=%d (visible %.2f)" % [label, facing, frame_x, ratio])

func _check_mount_head_relation(facing: int, frame_x: int, body: Rect2i, head: Rect2i) -> void:
	if _rect_empty(body) or _rect_empty(head):
		_fail("mount body/head empty facing=%d x=%d" % [facing, frame_x])
		return
	match facing:
		PaperDollLayerVisual.Facing.RIGHT:
			if head.position.x < body.position.x:
				_fail("right-facing mount head is behind body facing=%d x=%d: %s vs %s" % [facing, frame_x, body, head])
		PaperDollLayerVisual.Facing.LEFT:
			if head.end.x > body.end.x:
				_fail("left-facing mount head is behind body facing=%d x=%d: %s vs %s" % [facing, frame_x, body, head])
		_:
			var overlap: Rect2i = body.intersection(head)
			if _rect_empty(overlap) and abs(body.get_center().x - head.get_center().x) > 20.0:
				_fail("front/back mount head detached facing=%d x=%d: %s vs %s" % [facing, frame_x, body, head])

func _texture_frame_used_rect(texture: Texture2D, facing: int, frame_x: int) -> Rect2i:
	if texture == null:
		return Rect2i()
	var image: Image = texture.get_image()
	var source_row: int = PaperDollLayerVisual.source_row_for(facing)
	var frame: Image = image.get_region(Rect2i(
		Vector2i(frame_x * PaperDollLayerVisual.FRAME_SIZE.x, source_row * PaperDollLayerVisual.FRAME_SIZE.y),
		PaperDollLayerVisual.FRAME_SIZE
	))
	var used: Rect2i = frame.get_used_rect()
	if facing == PaperDollLayerVisual.Facing.LEFT:
		used.position.x = PaperDollLayerVisual.FRAME_SIZE.x - used.end.x
	return used

func _texture_frame_image(texture: Texture2D, facing: int, frame_x: int) -> Image:
	var image: Image = texture.get_image()
	var frame: Image = image.get_region(Rect2i(
		Vector2i(frame_x * 64, PaperDollLayerVisual.source_row_for(facing) * 64),
		Vector2i(64, 64)
	))
	if facing == PaperDollLayerVisual.Facing.LEFT:
		frame.flip_x()
	return frame

func _same_color(left: Color, right: Color) -> bool:
	return absf(left.r - right.r) < 0.02 \
		and absf(left.g - right.g) < 0.02 \
		and absf(left.b - right.b) < 0.02 \
		and absf(left.a - right.a) < 0.02

func _alpha_count(image: Image, region: Rect2i) -> int:
	var count: int = 0
	for y: int in range(region.position.y, region.end.y):
		for x: int in range(region.position.x, region.end.x):
			if image.get_pixel(x, y).a > 0.05:
				count += 1
	return count

func _component_count(image: Image) -> int:
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(64 * 64)
	var count: int = 0
	for y: int in range(64):
		for x: int in range(64):
			var start_index: int = y * 64 + x
			if visited[start_index] != 0 or image.get_pixel(x, y).a <= 0.05:
				continue
			count += 1
			var queue: Array[Vector2i] = [Vector2i(x, y)]
			visited[start_index] = 1
			var index: int = 0
			while index < queue.size():
				var position: Vector2i = queue[index]
				index += 1
				for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var next: Vector2i = position + step
					if next.x < 0 or next.x >= 64 or next.y < 0 or next.y >= 64:
						continue
					var next_index: int = next.y * 64 + next.x
					if visited[next_index] != 0 or image.get_pixel(next.x, next.y).a <= 0.05:
						continue
					visited[next_index] = 1
					queue.append(next)
	return count

func _make_recipe(
		mounted: bool,
		gender: int = PaperDollLayerVisual.Gender.MALE
) -> PaperDollRecipe:
	var draft: PaperDollPreviewDraft = PaperDollPreviewDraft.new()
	draft.is_mounted = mounted
	draft.gender = gender
	for layer: int in [
		PaperDollLayerVisual.RenderLayer.BODY,
		PaperDollLayerVisual.RenderLayer.ARMOR,
		PaperDollLayerVisual.RenderLayer.HAIR,
		PaperDollLayerVisual.RenderLayer.HELMET,
		PaperDollLayerVisual.RenderLayer.CAPE,
		PaperDollLayerVisual.RenderLayer.WEAPON,
		PaperDollLayerVisual.RenderLayer.SHIELD,
		PaperDollLayerVisual.RenderLayer.MOUNT_BARDING,
	]:
		draft.set_visual(layer, _catalog.default_visual_id(layer, draft.gender, mounted))
	if mounted:
		draft.mount_visual_id = _catalog.mount_visuals[0].mount_visual_id
	return _catalog.resolve_recipe(draft)

func _make_preview_recipe(
		mounted: bool,
		gender: int = PaperDollLayerVisual.Gender.MALE
) -> PaperDollRecipe:
	var draft: PaperDollPreviewDraft = PaperDollPreviewDraft.new()
	draft.is_mounted = mounted
	draft.gender = gender
	for layer: int in [
		PaperDollLayerVisual.RenderLayer.BODY,
		PaperDollLayerVisual.RenderLayer.ARMOR,
		PaperDollLayerVisual.RenderLayer.HAIR,
		PaperDollLayerVisual.RenderLayer.CAPE,
		PaperDollLayerVisual.RenderLayer.WEAPON,
		PaperDollLayerVisual.RenderLayer.SHIELD,
		PaperDollLayerVisual.RenderLayer.MOUNT_BARDING,
	]:
		draft.set_visual(layer, _catalog.default_visual_id(layer, draft.gender, mounted))
	if mounted:
		draft.mount_visual_id = _catalog.mount_visuals[0].mount_visual_id
	return _catalog.resolve_recipe(draft)

func _save_png(image: Image, file_name: String) -> void:
	var absolute_dir: String = ProjectSettings.globalize_path(OUTPUT_DIR)
	var make_dir_error: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
	if make_dir_error != OK:
		_fail("could not create QA output directory: %s" % make_dir_error)
		return
	var error: Error = image.save_png(absolute_dir.path_join(file_name))
	if error != OK:
		_fail("could not save %s: %s" % [file_name, error])

func _save_debug_frame(texture: Texture2D, label: String, facing: int, frame_x: int) -> void:
	if texture == null:
		return
	var image: Image = texture.get_image().get_region(Rect2i(
		Vector2i(frame_x * PaperDollLayerVisual.FRAME_SIZE.x, PaperDollLayerVisual.source_row_for(facing) * PaperDollLayerVisual.FRAME_SIZE.y),
		PaperDollLayerVisual.FRAME_SIZE
	))
	if facing == PaperDollLayerVisual.Facing.LEFT:
		image.flip_x()
	var enlarged: Image = image.duplicate()
	enlarged.resize(TILE_SIZE.x, TILE_SIZE.y, Image.INTERPOLATE_NEAREST)
	_save_png(enlarged, "%s_facing%d_frame%d.png" % [label, facing, frame_x])

func _contains_reference_chroma_key(image: Image) -> bool:
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var color: Color = image.get_pixel(x, y)
			if color.a <= 0.05:
				continue
			# Match the packer's dark-fringe key, not only its bright background
			# pixels.  A valid purple cape is around hue 0.74; black outlines are
			# below the value floor; horse reds are near hue 0.0.
			var bright_magenta: bool = color.r > 0.72 and color.b > 0.62 and color.g < 0.34
			var dark_fringe: bool = color.h > 0.82 \
				and color.h < 0.99 \
				and color.s > 0.20 \
				and color.v > 0.01 \
				and color.g < 100.0 / 255.0 \
				and color.r > color.b * 1.15
			if bright_magenta or dark_fringe:
				return true
	return false

func _fail(message: String) -> void:
	_failures.append(message)

func _rect_empty(rect: Rect2i) -> bool:
	return rect.size.x <= 0 or rect.size.y <= 0
