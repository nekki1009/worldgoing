extends SceneTree

## Focused material-lab contract: exercise the original four approved
## hairstyles.  The four newly authored variants have their own bounded
## verifier so this legacy regression remains fast and deterministic.
## through Catalog -> immutable Recipe -> real PaperDollComposer.  It avoids
## the expensive full reference-board scan so a Dropbox editor stall cannot
## hide a hairstyle or dye regression.

func _init() -> void:
	call_deferred("_run")

const LEGACY_HAIR_IDS := [
	&"hair_short_spiky",
	&"hair_high_ponytail",
	&"hair_bob",
	&"hair_twin_braids",
]

func _run() -> void:
	var catalog: PaperDollCatalog = PaperDollCatalog.create_art_gate1_catalog()
	var failures: PackedStringArray = PackedStringArray()
	var baseline_by_style: Dictionary = {}
	for hair_id: StringName in LEGACY_HAIR_IDS:
		var draft := PaperDollPreviewDraft.new()
		draft.gender = PaperDollLayerVisual.Gender.MALE
		draft.set_visual(PaperDollLayerVisual.RenderLayer.BODY, &"body_male_default")
		draft.set_visual(PaperDollLayerVisual.RenderLayer.ARMOR, &"artgate1_armor")
		draft.set_visual(PaperDollLayerVisual.RenderLayer.HAIR, hair_id)
		draft.set_visual(PaperDollLayerVisual.RenderLayer.CAPE, &"artgate1_cape")
		var recipe: PaperDollRecipe = catalog.resolve_recipe(draft)
		if recipe == null:
			failures.append("recipe did not resolve: %s" % hair_id)
			continue
		if not recipe.is_accepted_reference or not recipe.reference_hair_is_hair_only:
			failures.append("recipe is not accepted hair-only: %s" % hair_id)
			continue
		var composer := PaperDollComposer.new()
		root.add_child(composer)
		composer.apply_recipe(recipe)
		if composer.sprite_for(PaperDollLayerVisual.RenderLayer.BODY).texture == null:
			failures.append("composed body is missing: %s" % hair_id)
			composer.queue_free()
			continue
		composer.update_frame(PaperDollLayerVisual.Facing.DOWN, 0)
		var before: Image = composer.sprite_for(PaperDollLayerVisual.RenderLayer.BODY).texture.get_image()
		var source_body: Image = recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY).get_image()
		# The selected hairstyle may replace the old crown, but it must never
		# overwrite the accepted face landmarks.  These two small windows cover
		# the authored eye pixels in the DOWN reference frame.
		for eye_window: Rect2i in [Rect2i(25, 15, 5, 7), Rect2i(33, 15, 5, 7)]:
			for y: int in range(eye_window.position.y, eye_window.end.y):
				for x: int in range(eye_window.position.x, eye_window.end.x):
					var source_pixel := source_body.get_pixel(x, y)
					if source_pixel.a > 0.05 and source_pixel.v < 0.15 \
							and before.get_pixel(x, y) != source_pixel:
						failures.append("hairstyle replaced a DOWN face landmark at (%d,%d): %s" % [x, y, hair_id])
		baseline_by_style[hair_id] = before.get_data()
		composer.update_frame(PaperDollLayerVisual.Facing.RIGHT, 0)
		var right_sprite: Sprite2D = composer.sprite_for(PaperDollLayerVisual.RenderLayer.BODY)
		if right_sprite.flip_h:
			failures.append("RIGHT frame unexpectedly mirrored: %s" % hair_id)
		var right_frame: Image = _frame_image(right_sprite.texture, PaperDollLayerVisual.Facing.RIGHT)
		composer.update_frame(PaperDollLayerVisual.Facing.LEFT, 0)
		var left_sprite: Sprite2D = composer.sprite_for(PaperDollLayerVisual.RenderLayer.BODY)
		if not left_sprite.flip_h:
			failures.append("LEFT frame did not mirror the complete body+hair composite: %s" % hair_id)
		var left_frame: Image = _frame_image(left_sprite.texture, PaperDollLayerVisual.Facing.LEFT)
		var expected_left := right_frame.duplicate()
		expected_left.flip_x()
		if expected_left.get_data() != left_frame.get_data():
			failures.append("LEFT frame is not the horizontal mirror of RIGHT: %s" % hair_id)
		composer.set_dye(PaperDollComposer.DyeGroup.HAIR_BROWS, Color("9a4de3"))
		var dyed: Image = composer.sprite_for(PaperDollLayerVisual.RenderLayer.BODY).texture.get_image()
		if before.get_data() == dyed.get_data():
			failures.append("hair dye changed no pixels: %s" % hair_id)
		var hair_mask: Image = PaperDollComposer._build_reference_hair_mask(
			recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY),
			recipe.reference_hair_texture,
			recipe.reference_hair_is_hair_only
		)
		var skin_changes: int = _count_reference_face_changes(source_body, before, dyed, hair_mask)
		if skin_changes > 0:
			failures.append("hair dye changed %d protected face pixels: %s" % [skin_changes, hair_id])
		var missed_hair: int = _count_unapplied_hair_pixels(hair_mask, before, dyed)
		if missed_hair > 0:
			failures.append("hair dye left %d selected-hair pixels unchanged: %s" % [missed_hair, hair_id])
		if _count_hair_band_magenta(dyed) > 0:
			failures.append("hair dye left key-colour pixels: %s" % hair_id)
		composer.queue_free()
	var style_ids: Array = baseline_by_style.keys()
	for left: int in range(style_ids.size()):
		for right: int in range(left + 1, style_ids.size()):
			if baseline_by_style[style_ids[left]] == baseline_by_style[style_ids[right]]:
				failures.append("two approved hairstyles compose identically: %s/%s" % [style_ids[left], style_ids[right]])
	if failures.is_empty():
		print("FOUR HAIRSTYLES MATERIAL LAB PASS: %d silhouettes resolve, compose, and dye" % baseline_by_style.size())
	else:
		for failure: String in failures:
			push_error(failure)
		print("FOUR HAIRSTYLES MATERIAL LAB FAIL: %d issue(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _frame_image(texture: Texture2D, facing: int) -> Image:
	var image := texture.get_image().get_region(Rect2i(
		0,
		PaperDollLayerVisual.source_row_for(facing) * PaperDollLayerVisual.FRAME_SIZE.y,
		PaperDollLayerVisual.FRAME_SIZE.x,
		PaperDollLayerVisual.FRAME_SIZE.y
	))
	if facing == PaperDollLayerVisual.Facing.LEFT:
		image.flip_x()
	return image

func _count_reference_face_changes(
		authority: Image,
		before: Image,
		dyed: Image,
		hair_mask: Image
	) -> int:
	var changed: int = 0
	for y: int in range(mini(before.get_height(), dyed.get_height())):
		for x: int in range(mini(before.get_width(), dyed.get_width())):
			# A selected hairstyle owns these pixels, even when a dark anti-aliased
			# hair edge happens to satisfy the warm skin colour heuristic.
			if hair_mask != null and hair_mask.get_pixel(x, y).a > 0.05:
				continue
			var local := Vector2i(
				posmod(x, PaperDollLayerVisual.FRAME_SIZE.x),
				posmod(y, PaperDollLayerVisual.FRAME_SIZE.y)
			)
			var frame_origin := Vector2i(
				(x / PaperDollLayerVisual.FRAME_SIZE.x) * PaperDollLayerVisual.FRAME_SIZE.x,
				(y / PaperDollLayerVisual.FRAME_SIZE.y) * PaperDollLayerVisual.FRAME_SIZE.y
			)
			var brow_targets: Array[Vector2i] = PaperDollComposer._brow_targets_for_frame(
				authority,
				frame_origin,
				y / PaperDollLayerVisual.FRAME_SIZE.y
			)
			# Brows intentionally share the hair dye group; they are not face-skin
			# pixels and must not make this protected-face assertion fail.
			if local in brow_targets:
				continue
			if not PaperDollComposer._reference_replacement_blocked(
					authority.get_pixel(x, y),
					local
				):
				continue
			if before.get_pixel(x, y) != dyed.get_pixel(x, y):
				changed += 1
	return changed

func _count_unapplied_hair_pixels(mask: Image, before: Image, dyed: Image) -> int:
	if mask == null:
		return 0
	var missed: int = 0
	var height: int = mini(mask.get_height(), mini(before.get_height(), dyed.get_height()))
	var width: int = mini(mask.get_width(), mini(before.get_width(), dyed.get_width()))
	for y: int in range(height):
		for x: int in range(width):
			if mask.get_pixel(x, y).a > 0.05 \
					and before.get_pixel(x, y) == dyed.get_pixel(x, y):
				missed += 1
	return missed

func _count_hair_band_magenta(image: Image) -> int:
	var count: int = 0
	for y: int in range(mini(32, image.get_height())):
		for x: int in range(image.get_width()):
			var pixel: Color = image.get_pixel(x, y)
			# The test image intentionally dyes the hair purple (9a4de3),
			# so the broad "red and blue" predicate used for source-board
			# chroma-key cleanup would falsely flag the requested dye.  Only
			# count an actual near-key-colour remnant here: saturated magenta
			# with almost no green and both channels near full intensity.
			if pixel.a > 0.05 and pixel.r > 0.85 and pixel.g < 0.12 \
					and pixel.b > 0.85:
				count += 1
	return count
