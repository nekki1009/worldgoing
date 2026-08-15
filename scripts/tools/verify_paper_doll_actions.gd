extends SceneTree

## Focused action QA for the presentation-only character creator.
##
## This verifier intentionally resolves every action through the real catalog
## and the real split-layer composer contract.  It does not create gameplay
## units, persist a profile, or use a second animation implementation.

const ACTIONS: Array[int] = [
	PaperDollAnimation.Action.IDLE,
	PaperDollAnimation.Action.WALK,
	PaperDollAnimation.Action.RUN,
	PaperDollAnimation.Action.ATTACK,
	PaperDollAnimation.Action.SPRINT_ATTACK,
	PaperDollAnimation.Action.WORK,
	PaperDollAnimation.Action.HIT,
	PaperDollAnimation.Action.DOWN,
]

var catalog: PaperDollCatalog
var _failures: PackedStringArray = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	catalog = PaperDollCatalog.create_art_gate1_catalog()
	assert(catalog.validation_issues().is_empty(), "Catalog validation failed")
	var on_foot: PaperDollPreviewDraft = _full_draft(false)
	var mounted: PaperDollPreviewDraft = _full_draft(true)
	var idle_on_foot: PaperDollRecipe = catalog.resolve_recipe(on_foot)
	var idle_mounted: PaperDollRecipe = catalog.resolve_recipe(mounted)
	assert(idle_on_foot != null and idle_mounted != null, "Idle recipes did not resolve")

	await _validate_action_set(on_foot, idle_on_foot, false)
	await _validate_action_set(mounted, idle_mounted, true)
	if OS.get_cmdline_user_args().has("--check-authored-candidates"):
		_check_reference_layer_bounds()
	_save_montage(on_foot, false, "action_montage_on_foot.png")
	_save_montage(mounted, true, "action_montage_mounted.png")
	_save_frame_montage(on_foot, false, "action_frames_on_foot.png")
	_save_frame_montage(mounted, true, "action_frames_mounted.png")
	_save_layer_montage(on_foot, false, PaperDollLayerVisual.RenderLayer.WEAPON, "action_weapon_on_foot.png")
	_save_layer_montage(on_foot, false, PaperDollLayerVisual.RenderLayer.BODY, "action_body_on_foot.png")
	_save_layer_montage(mounted, true, PaperDollLayerVisual.RenderLayer.MOUNT_HEAD, "action_mount_head_mounted.png")

	if _failures.is_empty():
		print("PAPER DOLL ACTION QA PASS: 8 actions x 2 poses resolved, changed sheets, fixed pool sync, and montages written")
	else:
		for failure: String in _failures:
			push_error("PAPER DOLL ACTION QA FAIL: %s" % failure)
		quit(1)
		return
	quit()

func _check_reference_layer_bounds() -> void:
	# The authored-action pack is staged outside Catalog.  Compare its generated
	# component sheets against the accepted reference masks before any future
	# integration can be approved.  This catches the exact failures that a
	# complete composite can hide: armor shoulder drift and a sword crossing the
	# face band.
	var candidate_dir := ProjectSettings.globalize_path(
		"res://art_source/paper_doll/action_generated/attack_split_v2"
	)
	var checks: Array = [
		["run_armor_on_foot_armor.png", "artgate1_armor_on_foot_unisex.png", 18, 56, 8],
		["run_cape_on_foot_cape.png", "artgate1_cape_on_foot_unisex.png", 18, 56, 12],
		["run_hair_on_foot_hair.png", "hair_male_default_on_foot_unisex.png", 0, 24, 8],
		["run_weapon_on_foot_weapon.png", "artgate1_weapon_on_foot_unisex.png", 0, 56, 10],
	]
	for entry: Array in checks:
		var candidate_path: String = candidate_dir.path_join(str(entry[0]))
		var reference_path: String = ProjectSettings.globalize_path(
			"res://assets/paper_doll/reference_parts".path_join(str(entry[1]))
		)
		var candidate: Image = Image.load_from_file(candidate_path)
		var reference: Image = Image.load_from_file(reference_path)
		if candidate == null or reference == null or candidate.is_empty() or reference.is_empty():
			continue
		var min_y: int = int(entry[2])
		var max_y: int = int(entry[3])
		var allowed_width_delta: int = int(entry[4])
		for row: int in range(3):
			var candidate_bounds: Rect2i = _sheet_union_bounds(candidate, row, min_y, max_y)
			var reference_bounds: Rect2i = _sheet_union_bounds(reference, row, min_y, max_y)
			if candidate_bounds.size == Vector2i.ZERO or reference_bounds.size == Vector2i.ZERO:
				continue
			if abs(candidate_bounds.size.x - reference_bounds.size.x) > allowed_width_delta:
				_fail("authored candidate %s width drift row=%d candidate=%s reference=%s" % [entry[0], row, candidate_bounds, reference_bounds])
			if str(entry[0]).begins_with("run_weapon") and row < 2:
				for frame_x: int in range(8):
					var frame: Image = candidate.get_region(Rect2i(frame_x * 64, row * 64, 64, 64))
					var used := frame.get_used_rect()
					if used.position.y < 22:
						_fail("authored candidate weapon crosses head band row=%d frame=%d used=%s" % [row, frame_x, used])

func _sheet_union_bounds(sheet: Image, row: int, min_y: int, max_y: int) -> Rect2i:
	var result := Rect2i(64, 64, 0, 0)
	for frame_x: int in range(8):
		var frame := sheet.get_region(Rect2i(frame_x * 64, row * 64, 64, 64))
		for y: int in range(min_y, mini(max_y + 1, 64)):
			for x: int in range(64):
				if frame.get_pixel(x, y).a > 0.05:
					result = result.expand(Vector2i(x, y))
	return result

func _fail(message: String) -> void:
	_failures.append(message)

func _validate_action_set(
		draft: PaperDollPreviewDraft,
		idle_recipe: PaperDollRecipe,
		mounted: bool
	) -> void:
	var composer: PaperDollComposer = PaperDollComposer.new()
	root.add_child(composer)
	await process_frame
	for action: int in ACTIONS:
		draft.action = action
		var recipe: PaperDollRecipe = catalog.resolve_recipe(draft)
		assert(recipe != null, "Action did not resolve: %s mounted=%s" % [PaperDollAnimation.action_name(action), mounted])
		assert(recipe.action == action)
		assert(recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY) != null)
		if action != PaperDollAnimation.Action.IDLE:
			assert(
				_texture_changed(
					recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY),
					idle_recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY)
				),
				"Action %s did not produce a distinct body sheet mounted=%s" % [PaperDollAnimation.action_name(action), mounted]
			)
		var clip: PackedInt32Array = PaperDollAnimation.frames_for(action)
		if clip.size() > 1:
			assert(_distinct_body_frames(recipe, clip) >= 2,
				"Action %s has no visible frame change mounted=%s" % [PaperDollAnimation.action_name(action), mounted])
		composer.apply_recipe(recipe)
		for facing: int in range(4):
			assert(composer.update_frame(facing, 7))
			for layer: int in range(PaperDollLayerVisual.RenderLayer.COUNT):
				var sprite: Sprite2D = composer.sprite_for(layer)
				assert(sprite.frame_coords == Vector2i(7, PaperDollLayerVisual.source_row_for(facing)))
				assert(sprite.flip_h == (facing == PaperDollLayerVisual.Facing.LEFT))
				assert(sprite.z_index == PaperDollComposer.z_index_for(layer, facing))
	composer.queue_free()
	await process_frame

func _texture_changed(left: Texture2D, right: Texture2D) -> bool:
	if left == null or right == null:
		return left != right
	var left_image: Image = left.get_image()
	var right_image: Image = right.get_image()
	if left_image == null or right_image == null or left_image.is_empty() or right_image.is_empty():
		return left.get_instance_id() != right.get_instance_id()
	return left_image.get_data() != right_image.get_data()

func _save_montage(base_draft: PaperDollPreviewDraft, mounted: bool, file_name: String) -> void:
	const TILE_SIZE := Vector2i(512, 256)
	const COLUMNS := 4
	const ROWS := 2
	var montage: Image = Image.create(
		TILE_SIZE.x * COLUMNS,
		TILE_SIZE.y * ROWS,
		false,
		Image.FORMAT_RGBA8
	)
	montage.fill(Color("101722"))
	for index: int in range(ACTIONS.size()):
		var draft: PaperDollPreviewDraft = base_draft.copy()
		draft.action = ACTIONS[index]
		var recipe: PaperDollRecipe = catalog.resolve_recipe(draft)
		var tile: Image = PaperDollContactSheet.compose(recipe, false)
		var origin := Vector2i((index % COLUMNS) * TILE_SIZE.x, (index / COLUMNS) * TILE_SIZE.y)
		montage.blit_rect(tile, Rect2i(Vector2i.ZERO, TILE_SIZE), origin)
		var border := Color("3d536d") if index == 0 else Color("6f8fb2")
		for x: int in range(TILE_SIZE.x):
			montage.set_pixelv(origin + Vector2i(x, 0), border)
			montage.set_pixelv(origin + Vector2i(x, TILE_SIZE.y - 1), border)
		for y: int in range(TILE_SIZE.y):
			montage.set_pixelv(origin + Vector2i(0, y), border)
			montage.set_pixelv(origin + Vector2i(TILE_SIZE.x - 1, y), border)
	var output_dir := ProjectSettings.globalize_path("res://.visual_captures/paper_doll/qa")
	assert(DirAccess.make_dir_recursive_absolute(output_dir) == OK)
	assert(montage.save_png(output_dir.path_join(file_name)) == OK)

func _save_frame_montage(base_draft: PaperDollPreviewDraft, mounted: bool, file_name: String) -> void:
	# One direction, eight logical animation slots per row.  This is the visual
	# gate: it is much easier to spot a detached weapon or an unfallen rider
	# here than in the 8x4 source-sheet contact sheet.
	const TILE := 192
	var montage := Image.create(TILE * 8, TILE * ACTIONS.size(), false, Image.FORMAT_RGBA8)
	montage.fill(Color("101722"))
	for action_index: int in range(ACTIONS.size()):
		var draft := base_draft.copy()
		draft.action = ACTIONS[action_index]
		var recipe := catalog.resolve_recipe(draft)
		var sheet := _dyed_composed_sheet(recipe)
		var clip := PaperDollAnimation.frames_for(ACTIONS[action_index])
		for frame_index: int in range(8):
			var source_x: int = clip[mini(frame_index, clip.size() - 1)]
			var frame := sheet.get_region(Rect2i(source_x * 64, 0, 64, 64))
			frame.resize(TILE, TILE, Image.INTERPOLATE_NEAREST)
			var origin := Vector2i(frame_index * TILE, action_index * TILE)
			montage.blit_rect(frame, Rect2i(Vector2i.ZERO, Vector2i(TILE, TILE)), origin)
			for x: int in range(TILE):
				montage.set_pixelv(origin + Vector2i(x, 0), Color("6f8fb2"))
				montage.set_pixelv(origin + Vector2i(x, TILE - 1), Color("6f8fb2"))
			for y: int in range(TILE):
				montage.set_pixelv(origin + Vector2i(0, y), Color("6f8fb2"))
				montage.set_pixelv(origin + Vector2i(TILE - 1, y), Color("6f8fb2"))
	var output_dir := ProjectSettings.globalize_path("res://.visual_captures/paper_doll/qa")
	assert(DirAccess.make_dir_recursive_absolute(output_dir) == OK)
	assert(montage.save_png(output_dir.path_join(file_name)) == OK)

func _dyed_composed_sheet(recipe: PaperDollRecipe) -> Image:
	var composer := PaperDollComposer.new()
	root.add_child(composer)
	composer.apply_recipe(recipe)
	# Match the generator's approved visual preset so this QA image is the same
	# sample a human sees in the UI, rather than the catalog's raw warm source.
	composer.set_dye(PaperDollComposer.DyeGroup.HAIR_BROWS, Color("e8e9ef"))
	composer.set_dye(PaperDollComposer.DyeGroup.ARMOR, Color("b7c1d2"))
	composer.set_dye(PaperDollComposer.DyeGroup.CAPE, Color("263653"))
	if recipe.is_mounted:
		composer.set_dye(PaperDollComposer.DyeGroup.MOUNT, Color("9a704d"))
	var textures: Array[Texture2D] = []
	for layer: int in range(PaperDollLayerVisual.RenderLayer.COUNT):
		var sprite := composer.sprite_for(layer)
		textures.append(sprite.texture if sprite.visible else null)
	var result := PaperDollContactSheet.compose_textures(textures, false)
	composer.queue_free()
	return result

func _save_layer_montage(base_draft: PaperDollPreviewDraft, mounted: bool, layer: int, file_name: String) -> void:
	const TILE := 256
	var montage := Image.create(TILE * 8, TILE * ACTIONS.size(), false, Image.FORMAT_RGBA8)
	montage.fill(Color("101722"))
	for action_index: int in range(ACTIONS.size()):
		var draft := base_draft.copy()
		draft.action = ACTIONS[action_index]
		var recipe := catalog.resolve_recipe(draft)
		var texture := recipe.texture_for(layer)
		if texture == null:
			continue
		var sheet := texture.get_image()
		var clip := PaperDollAnimation.frames_for(ACTIONS[action_index])
		for frame_index: int in range(8):
			var source_x: int = clip[mini(frame_index, clip.size() - 1)]
			var frame := sheet.get_region(Rect2i(source_x * 64, 0, 64, 64))
			frame.resize(TILE, TILE, Image.INTERPOLATE_NEAREST)
			montage.blit_rect(frame, Rect2i(Vector2i.ZERO, Vector2i(TILE, TILE)), Vector2i(frame_index * TILE, action_index * TILE))
	var output_dir := ProjectSettings.globalize_path("res://.visual_captures/paper_doll/qa")
	assert(DirAccess.make_dir_recursive_absolute(output_dir) == OK)
	assert(montage.save_png(output_dir.path_join(file_name)) == OK)

func _distinct_body_frames(recipe: PaperDollRecipe, clip: PackedInt32Array) -> int:
	var texture := recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY)
	if texture == null:
		return 0
	var image := texture.get_image()
	var signatures: Dictionary = {}
	for frame_x: int in clip:
		var frame := image.get_region(Rect2i(frame_x * 64, 0, 64, 64))
		signatures[frame.get_data()] = true
	return signatures.size()

func _full_draft(mounted: bool) -> PaperDollPreviewDraft:
	var result := PaperDollPreviewDraft.new()
	result.is_mounted = mounted
	for layer: int in [
		PaperDollLayerVisual.RenderLayer.BODY,
		PaperDollLayerVisual.RenderLayer.ARMOR,
		PaperDollLayerVisual.RenderLayer.HAIR,
		PaperDollLayerVisual.RenderLayer.CAPE,
		PaperDollLayerVisual.RenderLayer.WEAPON,
	]:
		result.set_visual(layer, catalog.default_visual_id(layer, result.gender, mounted))
	if mounted:
		result.mount_visual_id = catalog.mount_visuals[0].mount_visual_id
		result.set_visual(
			PaperDollLayerVisual.RenderLayer.MOUNT_BARDING,
			catalog.default_visual_id(PaperDollLayerVisual.RenderLayer.MOUNT_BARDING, result.gender, true)
		)
	return result
