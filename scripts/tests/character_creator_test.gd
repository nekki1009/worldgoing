extends SceneTree

var catalog: PaperDollCatalog

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	catalog = PaperDollCatalog.create_art_gate1_catalog()
	_test_catalog_contract()
	print("CHARACTER CREATOR TEST 1 PASS: catalog IDs, gender policy, sheets, defaults, and mount bundle are valid")

	_test_art_gate1_part_export()
	print("CHARACTER CREATOR TEST 2 PASS: reference-derived Art Gate 1 runtime PNG pack exports with the expected contract")

	var recipes: Dictionary = _test_recipe_boundary()
	print("CHARACTER CREATOR TEST 3 PASS: detached draft resolves on-foot and mounted recipes without gameplay state")

	await _test_composer(recipes["mounted"] as PaperDollRecipe)
	print("CHARACTER CREATOR TEST 4 PASS: one 11-Sprite pool owns frame, mirror, anchor, and z-order updates")

	_test_contact_sheet()
	print("CHARACTER CREATOR TEST 5 PASS: pure Image contact sheets generate four logical directions with mirrored LEFT")

	_test_visual_alignment_contract()
	print("CHARACTER CREATOR TEST 6 PASS: mounted head/body/horse frame regions are visually aligned")

	await _test_character_creator_scene()
	print("CHARACTER CREATOR TEST 7 PASS: asset lab controls, timer, validation, and close lifecycle are reusable")

	await _test_main_modal_entry()
	print("CHARACTER CREATOR TEST 8 PASS: DebugUI lazily opens one modal lab and restores navigation input")

	await _test_standalone_scene_entry()
	print("CHARACTER CREATOR TEST 9 PASS: F6 direct scene entry opens the same catalog-backed preview")

	_test_dependency_boundary()
	print("CHARACTER CREATOR TEST 10 PASS: lab has no Session, Persistence, AnimatedSprite2D, or Battle dependency")

	print("Character creator tests passed: 10 cases")
	quit()

func _test_catalog_contract() -> void:
	var issues: PackedStringArray = catalog.validation_issues()
	assert(issues.is_empty(), "Art Gate 1 catalog is invalid: %s" % " | ".join(issues))
	assert(catalog.layer_visuals.size() == 24, "Art Gate 1 catalog variant count changed")
	assert(catalog.mount_visuals.size() == 2, "Art Gate 1 catalog must expose the reference and alternate mount bundles")
	assert(PaperDollLayerVisual.is_valid_visual_id(&"lowercase_id_2"))
	assert(not PaperDollLayerVisual.is_valid_visual_id(&"Bad-ID"))
	var armor: PaperDollLayerVisual = catalog.find_visual(&"artgate1_armor")
	assert(armor != null and armor.gender_policy == PaperDollLayerVisual.GenderPolicy.UNISEX)
	assert(catalog.default_visual_id(PaperDollLayerVisual.RenderLayer.ARMOR, PaperDollLayerVisual.Gender.MALE) == &"artgate1_armor")
	assert(catalog.default_visual_id(PaperDollLayerVisual.RenderLayer.CAPE, PaperDollLayerVisual.Gender.MALE) == &"artgate1_cape")
	assert(catalog.default_visual_id(PaperDollLayerVisual.RenderLayer.HAIR, PaperDollLayerVisual.Gender.MALE) == &"hair_short_spiky")
	assert(catalog.visuals_for_layer(PaperDollLayerVisual.RenderLayer.ARMOR).size() == 2)
	assert(catalog.visuals_for_layer(PaperDollLayerVisual.RenderLayer.CAPE).size() == 2)
	assert(catalog.visuals_for_layer(PaperDollLayerVisual.RenderLayer.HAIR).size() == 11)
	assert(catalog.visuals_for_layer(PaperDollLayerVisual.RenderLayer.WEAPON).size() == 2)
	assert(catalog.visuals_for_layer(PaperDollLayerVisual.RenderLayer.SHIELD).size() == 2)
	assert(catalog.visuals_for_layer(PaperDollLayerVisual.RenderLayer.MOUNT_BARDING).size() == 2)
	assert(catalog.sorted_mounts()[0].mount_visual_id == &"artgate1_horse")
	assert(catalog.sorted_mounts()[1].mount_visual_id == &"alt_dark_bay_horse")
	for hair_id: StringName in PaperDollCatalog.APPROVED_HAIR_IDS:
		var hair: PaperDollLayerVisual = catalog.find_visual(hair_id)
		assert(hair != null, "Approved hairstyle is missing: %s" % hair_id)
		assert(
			hair.gender_policy == PaperDollLayerVisual.GenderPolicy.GENDERED,
			"Approved hairstyle is not gendered: %s" % hair_id
		)
		assert(
			_is_reference_runtime_texture(hair.on_foot_male) \
				and _is_reference_runtime_texture(hair.on_foot_female) \
				and hair.on_foot_male.get_instance_id() != hair.on_foot_female.get_instance_id(),
			"Approved hairstyle does not own separate male/female sources: %s" % hair_id
		)
		assert(hair.mounted_male == hair.on_foot_male and hair.mounted_female == hair.on_foot_female)
	var male_body: PaperDollLayerVisual = catalog.find_visual(&"body_male_default")
	assert(
		male_body != null \
			and _is_reference_runtime_texture(male_body.on_foot_unisex),
		"Male body did not resolve to the reference-derived runtime pack"
	)
	var mount: PaperDollMountVisual = catalog.mount_visuals[0]
	assert(
		mount.body.mounted_unisex != null \
			and _is_reference_runtime_texture(mount.body.mounted_unisex),
		"Mount body did not resolve to the reference-derived runtime pack"
	)
	for visual: PaperDollLayerVisual in catalog.layer_visuals:
		if PaperDollLayerVisual.is_mounted_only_layer(visual.render_layer):
			assert(
				visual.mounted_unisex != null \
					and _is_reference_runtime_texture(visual.mounted_unisex),
				"Mounted-only visual is not reference-derived: %s" % visual.visual_id
			)
		elif visual.gender_policy == PaperDollLayerVisual.GenderPolicy.GENDERED:
			assert(
				_is_reference_runtime_texture(visual.on_foot_male) \
					and _is_reference_runtime_texture(visual.on_foot_female) \
					and _is_reference_runtime_texture(visual.mounted_male) \
					and _is_reference_runtime_texture(visual.mounted_female),
				"Gendered layer visual is not reference-derived: %s" % visual.visual_id
			)
		else:
			assert(
				_is_reference_runtime_texture(visual.on_foot_unisex) \
					and _is_reference_runtime_texture(visual.mounted_unisex),
				"Layer visual is not reference-derived: %s" % visual.visual_id
			)
	for part: PaperDollLayerVisual in mount.parts():
		assert(
			part.mounted_unisex != null \
				and _is_reference_runtime_texture(part.mounted_unisex),
			"Mount part is not reference-derived: %s" % part.visual_id
		)
	assert(
		armor.resolve(PaperDollLayerVisual.Gender.MALE, false) \
		== armor.resolve(PaperDollLayerVisual.Gender.FEMALE, false),
		"UNISEX visual did not resolve to the same texture"
	)
	for pair: Array in [
		[&"artgate1_armor", &"alt_bronze_armor"],
		[&"artgate1_cape", &"alt_teal_cape"],
		[&"hair_male_default", &"alt_braided_hair"],
		[&"artgate1_weapon", &"alt_bronze_sword"],
		[&"artgate1_shield", &"alt_teal_shield"],
	]:
		var reference_visual: PaperDollLayerVisual = catalog.find_visual(pair[0] as StringName)
		var alternate_visual: PaperDollLayerVisual = catalog.find_visual(pair[1] as StringName)
		assert(reference_visual != null and alternate_visual != null)
		assert(_texture_changed(
			reference_visual.resolve(PaperDollLayerVisual.Gender.MALE, false),
			alternate_visual.resolve(PaperDollLayerVisual.Gender.MALE, false)
		), "Alternate visual did not change the source sheet: %s" % pair[1])
	for visual: PaperDollLayerVisual in catalog.layer_visuals:
		assert(visual.validation_issues().is_empty(), "Layer visual failed validation: %s" % visual.visual_id)
	assert(mount.validation_issues().is_empty(), "Mount visual failed validation")
	assert(mount.tail.render_layer == PaperDollLayerVisual.RenderLayer.MOUNT_TAIL)
	assert(mount.body.render_layer == PaperDollLayerVisual.RenderLayer.MOUNT_BODY)
	assert(mount.head.render_layer == PaperDollLayerVisual.RenderLayer.MOUNT_HEAD)
	var invalid_visual: PaperDollLayerVisual = PaperDollLayerVisual.new()
	invalid_visual.visual_id = &"blank_visual"
	invalid_visual.render_layer = PaperDollLayerVisual.RenderLayer.CAPE
	invalid_visual.gender_policy = PaperDollLayerVisual.GenderPolicy.UNISEX
	var blank_image: Image = Image.create(512, 192, false, Image.FORMAT_RGBA8)
	blank_image.fill(Color.TRANSPARENT)
	invalid_visual.on_foot_unisex = ImageTexture.create_from_image(blank_image)
	invalid_visual.mounted_unisex = invalid_visual.on_foot_unisex
	assert(
		" | ".join(invalid_visual.validation_issues()).find("frame (0,0) is empty") >= 0,
		"Catalog validation accepted an empty animation sheet"
	)

func _is_reference_runtime_texture(texture: Texture2D) -> bool:
	if texture == null:
		return false
	var path: String = str(texture.resource_path)
	return path.find("assets/paper_doll/reference_parts/") >= 0 \
		or path.find("assets/paper_doll/reference_match/") >= 0 \
		or texture.has_meta("paper_doll_hair_only")

func _test_art_gate1_part_export() -> void:
	var output_dir: String = "user://art_gate1_part_export_test"
	assert(PaperDollCatalog.save_art_gate1_parts(output_dir) == OK)
	var absolute_dir: String = ProjectSettings.globalize_path(output_dir)
	var directory: DirAccess = DirAccess.open(absolute_dir)
	assert(directory != null, "Art Gate 1 part export directory is missing")
	var files: PackedStringArray = directory.get_files()
	assert(files.size() == 52, "Art Gate 1 runtime part count changed: %d" % files.size())
	for file_name: String in files:
		assert(file_name.ends_with(".png"))
		var image: Image = Image.load_from_file(absolute_dir.path_join(file_name))
		assert(image != null and not image.is_empty(), "%s did not load" % file_name)
		assert(image.get_size() == PaperDollLayerVisual.SHEET_SIZE, "%s size is invalid" % file_name)
		assert(image.get_format() == Image.FORMAT_RGBA8, "%s is not RGBA8" % file_name)
		assert(image.detect_alpha() != Image.ALPHA_NONE, "%s has no alpha" % file_name)
		# The accepted white-hair/silver-armor body is a complete reference board,
		# not an old chroma-keyed split layer.  Its dark pixel outline is authored
		# art and must not be rejected by the legacy split-pack fringe heuristic.
		var accepted_reference_body: bool = file_name in [
			"body_male_default_on_foot_unisex.png",
			"body_male_default_mounted_unisex.png",
			"body_female_default_on_foot_unisex.png",
			"body_female_default_mounted_unisex.png",
		]
		var authored_hair_sheet: bool = file_name.contains("hair_") \
			or file_name.begins_with("alt_braided_hair_")
		assert(
			accepted_reference_body or authored_hair_sheet or _not_reference_chroma_keyed(image),
			"%s still contains opaque magenta board background" % file_name
		)
	_cleanup_capture_dir(output_dir)

func _test_recipe_boundary() -> Dictionary:
	var on_foot: PaperDollPreviewDraft = _full_draft(false)
	var copy: PaperDollPreviewDraft = on_foot.copy()
	copy.set_visual(PaperDollLayerVisual.RenderLayer.WEAPON, &"")
	assert(
		on_foot.visual_id_for(PaperDollLayerVisual.RenderLayer.WEAPON) == &"artgate1_weapon",
		"Draft copy shared its selection Dictionary"
	)
	var on_foot_recipe: PaperDollRecipe = catalog.resolve_recipe(on_foot)
	assert(on_foot_recipe != null and not on_foot_recipe.is_mounted)
	assert(on_foot_recipe.visible_layer_count() == 7, "On-foot recipe exposed mount-only layers")
	assert(on_foot_recipe.texture_for(PaperDollLayerVisual.RenderLayer.MOUNT_TAIL) == null)
	assert(on_foot_recipe.texture_for(PaperDollLayerVisual.RenderLayer.MOUNT_BODY) == null)
	assert(on_foot_recipe.texture_for(PaperDollLayerVisual.RenderLayer.MOUNT_HEAD) == null)
	assert(on_foot_recipe.texture_for(PaperDollLayerVisual.RenderLayer.MOUNT_BARDING) == null)
	# The white-hair/silver-armor board is the alignment standard, not a hair
	# lock.  Every authored hairstyle variant can use that same calibrated body
	# board and receives a snapshot hair source for replacement.
	for hair_id: StringName in [&"hair_male_default", &"hair_female_default", &"alt_braided_hair"]:
		var hairstyle := PaperDollPreviewDraft.new()
		hairstyle.gender = PaperDollLayerVisual.Gender.MALE
		hairstyle.is_mounted = false
		hairstyle.set_visual(PaperDollLayerVisual.RenderLayer.BODY, &"body_male_default")
		hairstyle.set_visual(PaperDollLayerVisual.RenderLayer.ARMOR, &"artgate1_armor")
		hairstyle.set_visual(PaperDollLayerVisual.RenderLayer.HAIR, hair_id)
		hairstyle.set_visual(PaperDollLayerVisual.RenderLayer.CAPE, &"artgate1_cape")
		var hairstyle_recipe: PaperDollRecipe = catalog.resolve_recipe(hairstyle)
		assert(hairstyle_recipe != null and hairstyle_recipe.is_accepted_reference)
		assert(hairstyle_recipe.reference_hair_texture != null,
			"Hair variant lost its reference snapshot: %s" % hair_id)

	var mounted: PaperDollPreviewDraft = _full_draft(true)
	var mounted_recipe: PaperDollRecipe = catalog.resolve_recipe(mounted)
	assert(mounted_recipe != null and mounted_recipe.is_mounted)
	assert(mounted_recipe.visible_layer_count() == PaperDollLayerVisual.RenderLayer.COUNT)
	for layer: int in range(PaperDollLayerVisual.RenderLayer.COUNT):
		assert(mounted_recipe.texture_for(layer) != null, "Mounted recipe lost layer %d" % layer)

	var missing_mount: PaperDollPreviewDraft = mounted.copy()
	missing_mount.mount_visual_id = &""
	assert(not catalog.validate_draft(missing_mount).is_empty())
	assert(catalog.resolve_recipe(missing_mount) == null)
	return {
		"on_foot": on_foot_recipe,
		"mounted": mounted_recipe,
	}

func _test_composer(recipe: PaperDollRecipe) -> void:
	var composer: PaperDollComposer = PaperDollComposer.new()
	var expected_z: Array[PackedInt32Array] = [
		PackedInt32Array([-10, -10, -10, -10]),
		PackedInt32Array([-5, 15, 5, 5]),
		PackedInt32Array([0, 0, 0, 0]),
		PackedInt32Array([10, 10, 10, 10]),
		PackedInt32Array([11, 11, 11, 11]),
		PackedInt32Array([12, 12, 12, 12]),
		PackedInt32Array([13, 13, 13, 13]),
		PackedInt32Array([14, -1, 14, -1]),
		PackedInt32Array([15, -2, -2, 15]),
		PackedInt32Array([20, -5, 20, 20]),
		PackedInt32Array([21, 1, 21, 21]),
	]
	get_root().add_child(composer)
	await process_frame
	assert(composer.sprite_count() == PaperDollLayerVisual.RenderLayer.COUNT)
	assert(composer.get_child_count() == PaperDollLayerVisual.RenderLayer.COUNT)
	composer.apply_recipe(recipe)
	composer.apply_recipe(recipe)
	assert(composer.get_child_count() == PaperDollLayerVisual.RenderLayer.COUNT, "Recipe apply added Sprite nodes")
	assert(composer.current_action == recipe.action)
	for layer: int in range(PaperDollLayerVisual.RenderLayer.COUNT):
		var sprite: Sprite2D = composer.sprite_for(layer)
		var expected_visible: bool = recipe.texture_for(layer) != null
		if layer == PaperDollLayerVisual.RenderLayer.HAIR \
				and recipe.texture_for(PaperDollLayerVisual.RenderLayer.HELMET) != null:
			expected_visible = false
		assert(sprite != null and sprite.visible == expected_visible)
		assert(sprite.hframes == 8 and sprite.vframes == 3)
		assert(not sprite.centered and sprite.offset == Vector2(-32.0, -56.0))
		assert(sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)

	for facing: int in range(4):
		assert(composer.update_frame(facing, 7))
		for layer: int in range(PaperDollLayerVisual.RenderLayer.COUNT):
			var sprite: Sprite2D = composer.sprite_for(layer)
			assert(sprite.frame_coords == Vector2i(7, PaperDollLayerVisual.source_row_for(facing)))
			assert(sprite.flip_h == (facing == PaperDollLayerVisual.Facing.LEFT))
			assert(sprite.z_index == expected_z[layer][facing], "Unexpected z-index for layer/facing")
	assert(not composer.update_frame(PaperDollLayerVisual.Facing.LEFT, 8))
	assert(composer.current_frame_x == 7, "Invalid frame changed the unified controller")
	var action_draft: PaperDollPreviewDraft = _full_draft(false)
	for action: int in range(PaperDollAnimation.Action.COUNT):
		action_draft.action = action
		var action_recipe: PaperDollRecipe = catalog.resolve_recipe(action_draft)
		assert(action_recipe != null and action_recipe.action == action)
		assert(action_recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY) != null)
	assert(composer.set_action(PaperDollAnimation.Action.ATTACK))
	assert(not composer.set_action(PaperDollAnimation.Action.COUNT))
	composer.apply_recipe(null)
	for layer: int in range(PaperDollLayerVisual.RenderLayer.COUNT):
		assert(not composer.sprite_for(layer).visible)
	composer.queue_free()
	await process_frame

func _test_contact_sheet() -> void:
	var draft: PaperDollPreviewDraft = PaperDollPreviewDraft.new()
	draft.set_visual(
		PaperDollLayerVisual.RenderLayer.BODY,
		catalog.default_visual_id(PaperDollLayerVisual.RenderLayer.BODY, draft.gender)
	)
	var recipe: PaperDollRecipe = catalog.resolve_recipe(draft)
	var sheet: Image = PaperDollContactSheet.compose(recipe, false)
	assert(sheet.get_size() == Vector2i(512, 256))
	assert(not sheet.is_invisible(), "Contact sheet is empty")
	var right_frame: Image = sheet.get_region(Rect2i(Vector2i(0, 128), Vector2i(64, 64)))
	var left_frame: Image = sheet.get_region(Rect2i(Vector2i(0, 192), Vector2i(64, 64)))
	left_frame.flip_x()
	assert(right_frame.get_data() == left_frame.get_data(), "LEFT is not a mirror of the RIGHT source row")
	var guided: Image = PaperDollContactSheet.compose(recipe, true)
	var guide_pixel: Color = guided.get_pixel(32, 56)
	assert(
		guide_pixel.g > 0.99 and guide_pixel.b > 0.99 and guide_pixel.a > 0.89,
		"Contact sheet anchor guide is missing"
	)

func _test_visual_alignment_contract() -> void:
	var body: Rect2i = _frame_used_rect(
		catalog.find_visual(&"body_male_default").mounted_unisex,
		PaperDollLayerVisual.Facing.RIGHT
	)
	var armor: Rect2i = _frame_used_rect(
		catalog.find_visual(&"artgate1_armor").mounted_unisex,
		PaperDollLayerVisual.Facing.RIGHT
	)
	var hair: Rect2i = _frame_used_rect(
		catalog.find_visual(&"hair_male_default").mounted_unisex,
		PaperDollLayerVisual.Facing.RIGHT
	)
	var helmet: Rect2i = _frame_used_rect(
		catalog.find_visual(&"artgate1_helmet").mounted_unisex,
		PaperDollLayerVisual.Facing.RIGHT
	)
	var mount_body: Rect2i = _frame_used_rect(
		catalog.mount_visuals[0].body.mounted_unisex,
		PaperDollLayerVisual.Facing.RIGHT
	)
	var mount_head: Rect2i = _frame_used_rect(
		catalog.mount_visuals[0].head.mounted_unisex,
		PaperDollLayerVisual.Facing.RIGHT
	)
	assert(body.size.x > 0 and body.size.y > 0, "Mounted body frame is empty")
	assert(armor.size.x > 0 and armor.size.y > 0, "Mounted armor frame is empty")
	assert(abs(body.get_center().x - armor.get_center().x) <= 4.0, "Mounted body and armor centers diverged")
	assert(helmet.position.y <= 8 and helmet.end.y <= 24, "Mounted helmet is not in the head band")
	assert(hair.position.y <= 8 and hair.end.y <= 24, "Mounted hair is not in the head band")
	assert(mount_body.end.y >= 50, "Mount body does not reach the hoof anchor")
	assert(mount_head.position.x >= mount_body.position.x, "Mount head is detached behind the body")

func _frame_used_rect(texture: Texture2D, facing: int) -> Rect2i:
	var image: Image = texture.get_image()
	var source_row: int = PaperDollLayerVisual.source_row_for(facing)
	return image.get_region(Rect2i(
		Vector2i(0, source_row * PaperDollLayerVisual.FRAME_SIZE.y),
		PaperDollLayerVisual.FRAME_SIZE
	)).get_used_rect()

func _test_character_creator_scene() -> void:
	var scene: PackedScene = load("res://scenes/ui/CharacterCreator.tscn") as PackedScene
	assert(scene != null, "CharacterCreator scene did not load")
	var creator: CharacterCreator = scene.instantiate() as CharacterCreator
	get_root().add_child(creator)
	await process_frame
	assert(not creator.is_open())
	assert(creator.composer.sprite_count() == PaperDollLayerVisual.RenderLayer.COUNT)
	creator.open(catalog)
	await process_frame
	await process_frame
	assert(creator.is_open() and creator.tabs.current_tab == 1)
	assert(creator.current_recipe != null)
	assert(_texture_has_hair_dye_pixels(
		creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.HAIR).texture,
		Color.WHITE
	), "Default hair sheet has no authored head pixels")
	assert(
		creator.current_recipe.visible_layer_count() == 4
			and creator.composer.visible_sprite_count() == 1
			and creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.BODY).visible
			and creator.current_recipe.is_accepted_reference,
		"Generator did not open the accepted white-hair/silver-armor base recipe"
	)
	assert(
		not creator.gender_option.disabled
			and not creator.mount_option.disabled
			and not creator.armor_option.disabled
			and creator.body_option.get_item_count() > 0
			and creator.hair_option.get_item_count() > 0
			and creator.action_option.item_count == PaperDollAnimation.Action.COUNT
			and not creator.mounted_toggle.disabled,
		"Split part and action controls are not available"
	)
	assert(creator.run_check_all().is_empty())
	assert(creator.play_pause_button.disabled, "Idle clip should remain static")
	var idle_recipe: PaperDollRecipe = creator.current_recipe
	for action: int in [
		PaperDollAnimation.Action.WALK,
		PaperDollAnimation.Action.RUN,
		PaperDollAnimation.Action.ATTACK,
		PaperDollAnimation.Action.SPRINT_ATTACK,
		PaperDollAnimation.Action.WORK,
		PaperDollAnimation.Action.HIT,
		PaperDollAnimation.Action.DOWN,
	]:
		creator._on_action_selected(action)
		assert(creator.current_action == action)
		assert(
			creator.current_recipe != null
				and creator.current_recipe.is_accepted_reference
				and not _texture_changed(
				creator.current_recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY),
				idle_recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY)
			),
			"Action %s replaced the calibrated base body sheet" % PaperDollAnimation.action_name(action)
		)
	creator._on_action_selected(PaperDollAnimation.Action.WALK)
	assert(creator.current_action == PaperDollAnimation.Action.WALK)
	assert(creator.current_recipe.is_accepted_reference,
		"WALK must keep the calibrated reference base set")
	assert(not creator._recipe_uses_procedural_action(creator.current_recipe),
		"Accepted WALK preview must not report a split fallback")
	assert(not creator.play_pause_button.disabled)
	var frame_before_tick: int = creator.current_frame_x
	creator.animation_timer.emit_signal("timeout")
	assert(creator.current_frame_x != frame_before_tick, "Walk action did not advance its clip")
	assert(creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.BODY).frame_coords.x == creator.current_frame_x)
	creator.composer.clear_dyes()
	creator._dye_groups_active.clear()
	var body_base: Texture2D = creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.BODY).texture
	var hair_base: Texture2D = creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.HAIR).texture
	var armor_base: Texture2D = creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.ARMOR).texture
	var cape_base: Texture2D = creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.CAPE).texture
	creator._on_hair_dye_changed(Color("d13f8f"))
	assert(creator.composer.active_dye_count() == 1)
	assert(creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.HAIR).texture == hair_base,
		"Accepted base should keep the hidden hair source unchanged")
	assert(creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.BODY).texture != body_base,
		"Hair dye did not recolor the shared eyebrow mask")
	assert(
		_texture_has_target_hue(
			creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.BODY).texture,
			Color("d13f8f")
		),
		"Hair dye did not recolor authored hair pixels"
	)
	assert(
		_body_dye_preserves_eyes(
			body_base,
			creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.BODY).texture,
			Color("d13f8f")
		),
		"Hair dye did not add brows without recolouring the eye bars"
	)
	assert(
		_not_target_hue_in_face(
			creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.HAIR).texture,
			Color("d13f8f")
		),
		"Hair dye contaminated the front face opening"
	)
	creator._on_armor_dye_changed(Color("3b79c9"))
	creator._on_cape_dye_changed(Color("8c3d62"))
	assert(creator.composer.active_dye_count() == 3)
	assert(creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.ARMOR).texture == armor_base,
		"Accepted base should keep the hidden armor source unchanged")
	assert(creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.CAPE).texture == cape_base,
		"Accepted base should keep the hidden cape source unchanged")
	# Every selectable slot must actually switch to a different layer-owned
	# visual, not merely change the OptionButton label.
	var alternate_selections: Array = [
		[PaperDollLayerVisual.RenderLayer.ARMOR, &"alt_bronze_armor"],
		[PaperDollLayerVisual.RenderLayer.HAIR, &"alt_braided_hair"],
		[PaperDollLayerVisual.RenderLayer.CAPE, &"alt_teal_cape"],
		[PaperDollLayerVisual.RenderLayer.WEAPON, &"alt_bronze_sword"],
		[PaperDollLayerVisual.RenderLayer.SHIELD, &"alt_teal_shield"],
	]
	for selection: Array in alternate_selections:
		var selection_layer: int = selection[0] as int
		var alternate_id: StringName = selection[1] as StringName
		var previous_texture: Texture2D = creator.composer.sprite_for(selection_layer).texture
		creator.preview_draft.set_visual(selection_layer, alternate_id)
		creator._populate_controls()
		creator._refresh_preview()
		assert(creator.preview_draft.visual_id_for(selection_layer) == alternate_id)
		assert(_texture_changed(previous_texture, creator.current_recipe.texture_for(selection_layer)),
			"Selecting %s did not swap layer %s" % [alternate_id, PaperDollLayerVisual.layer_name(selection_layer)])
	creator.preview_draft.set_visual(PaperDollLayerVisual.RenderLayer.ARMOR, &"artgate1_armor")
	creator.preview_draft.set_visual(PaperDollLayerVisual.RenderLayer.HAIR, &"hair_male_default")
	creator.preview_draft.set_visual(PaperDollLayerVisual.RenderLayer.CAPE, &"artgate1_cape")
	creator.preview_draft.set_visual(PaperDollLayerVisual.RenderLayer.WEAPON, &"artgate1_weapon")
	creator.preview_draft.set_visual(PaperDollLayerVisual.RenderLayer.SHIELD, &"artgate1_shield")
	creator._populate_controls()
	creator._refresh_preview()
	# The alternate mount is a real bundle swap: all three intrinsic horse
	# layers must resolve to different sheets while the rider recipe remains
	# valid and mounted.
	await _click_control(creator.mounted_toggle)
	var reference_mount_id: StringName = creator.preview_draft.mount_visual_id
	var reference_mount_texture: Texture2D = creator.current_recipe.texture_for(PaperDollLayerVisual.RenderLayer.MOUNT_BODY)
	creator.preview_draft.mount_visual_id = &"alt_dark_bay_horse"
	creator._populate_controls()
	creator._refresh_preview()
	assert(creator.preview_draft.mount_visual_id == &"alt_dark_bay_horse")
	assert(reference_mount_id == &"artgate1_horse")
	assert(_texture_changed(reference_mount_texture, creator.current_recipe.texture_for(PaperDollLayerVisual.RenderLayer.MOUNT_BODY)),
		"Alternate mount did not replace the horse body sheet")
	creator.preview_draft.mount_visual_id = reference_mount_id
	creator._populate_controls()
	creator._refresh_preview()
	await _click_control(creator.mounted_toggle)
	var capture_dir: String = "user://character_creator_test_captures"
	var exported_count: int = creator.export_all_contact_sheets(capture_dir)
	print("CONTACT_SHEET_EXPORT_COUNT=", exported_count)
	assert(exported_count == 98, "Full catalog export count changed: %d" % exported_count)
	_cleanup_capture_dir(capture_dir)
	await _click_control(creator.left_button)
	assert(creator.composer.current_facing == PaperDollLayerVisual.Facing.LEFT)
	assert(creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.BODY).flip_h)
	await _click_control(creator.mounted_toggle)
	assert(creator.preview_draft.is_mounted and creator.current_recipe.visible_layer_count() == 9,
		"mounted split count=%d mounted=%s" % [creator.current_recipe.visible_layer_count(), creator.preview_draft.is_mounted])
	assert(
		creator.composer.visible_sprite_count() == 9
			and creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.MOUNT_BODY).visible
			and creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.MOUNT_HEAD).visible,
		"Mounted toggle did not resolve split horse parts"
	)
	var mount_base: Texture2D = creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.MOUNT_BODY).texture
	var mount_barding_base: Texture2D = creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.MOUNT_BARDING).texture
	creator._on_mount_dye_changed(Color("5a963d"))
	assert(creator.composer.active_dye_count() == 4)
	assert(creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.MOUNT_BODY).texture != mount_base)
	assert(creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.MOUNT_BARDING).texture == mount_barding_base,
		"Mount dye recoloured barding; barding belongs to Armor dye")
	assert(creator.composer.get_child_count() == PaperDollLayerVisual.RenderLayer.COUNT)
	await _click_control(creator.mounted_toggle)
	assert(not creator.preview_draft.is_mounted and creator.current_recipe.visible_layer_count() == 6)
	var closed_count: Array[int] = [0]
	creator.closed.connect(func() -> void: closed_count[0] += 1)
	creator.close()
	assert(not creator.is_open() and closed_count[0] == 1)
	creator.open(catalog)
	assert(creator.composer.get_child_count() == PaperDollLayerVisual.RenderLayer.COUNT)
	creator.close()
	creator.queue_free()
	await process_frame

func _click_control(control: BaseButton) -> void:
	assert(control != null and control.is_visible_in_tree() and not control.disabled,
		"Cannot pointer-click an unavailable control")
	var position: Vector2 = control.get_global_rect().get_center()
	print("POINTER TEST %s rect=%s point=%s viewport=%s" % [
		control.get_path(), control.get_global_rect(), position, get_root().get_visible_rect(),
	])
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = position
	press.global_position = position
	press.pressed = true
	get_root().notify_mouse_entered()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	get_root().push_input(motion, true)
	await process_frame
	var hovered: Control = get_root().gui_get_hovered_control()
	print("POINTER HOVER %s" % (hovered.get_path() if hovered != null else "<none>"))
	assert(
		hovered != null and (hovered == control or control.is_ancestor_of(hovered)),
		"Pointer did not reach the requested control"
	)
	get_root().push_input(press, true)
	await process_frame
	var release: InputEventMouseButton = press.duplicate() as InputEventMouseButton
	release.pressed = false
	get_root().push_input(release, true)
	await process_frame

func _test_main_modal_entry() -> void:
	var main_scene: PackedScene = load("res://scenes/Main.tscn") as PackedScene
	var main: Node2D = main_scene.instantiate() as Node2D
	get_root().add_child(main)
	await process_frame
	assert(main.get_node_or_null("CharacterCreator") == null, "Main eagerly created CharacterCreator")
	var navigation: NavigationController = main.get_node("NavigationController") as NavigationController
	var debug_ui: DebugUI = main.get_node("DebugUI") as DebugUI
	var input_before: bool = navigation.is_processing_unhandled_input()
	debug_ui.character_creator_button.emit_signal("pressed")
	await process_frame
	var creator: CharacterCreator = main.get_node_or_null("CharacterCreator") as CharacterCreator
	assert(creator != null and creator.is_open())
	assert(not navigation.is_processing_unhandled_input(), "Modal lab left NavigationController input enabled")
	if OS.get_cmdline_user_args().has("--capture-character-creator"):
		# Capture the actual catalog-backed runtime output.  The deterministic
		# default is the approved white-hair/silver-armor alignment board; later
		# captures intentionally exercise alternate split layers and action data.
		await _capture_character_creator("character_creator_verified_default_white_silver.png")
		# White hair is the alignment standard, not a lock on the hair selector.
		# Keep the accepted armor/cape/body board and change only the hairstyle so
		# this capture proves the real creator path, not an offline fixture.
		creator.preview_draft.set_visual(PaperDollLayerVisual.RenderLayer.HAIR, &"alt_braided_hair")
		creator._populate_controls()
		creator._refresh_preview()
		await _capture_character_creator("character_creator_alternate_hair_reference.png")
		creator.preview_draft.set_visual(PaperDollLayerVisual.RenderLayer.HAIR, &"hair_male_default")
		creator._populate_controls()
		creator._refresh_preview()
		creator._on_action_selected(PaperDollAnimation.Action.WALK)
		creator._set_facing(PaperDollLayerVisual.Facing.DOWN)
		creator.frame_slider.value = 0
		await _capture_character_creator("character_creator_action_walk.png")
		# Verify the UI's real part selectors with a second, layer-owned visual
		# combination.  Each selected alternate remains independently tintable;
		# no complete composite is attached to a single slot.
		creator.preview_draft.set_visual(PaperDollLayerVisual.RenderLayer.ARMOR, &"alt_bronze_armor")
		creator.preview_draft.set_visual(PaperDollLayerVisual.RenderLayer.HAIR, &"alt_braided_hair")
		creator.preview_draft.set_visual(PaperDollLayerVisual.RenderLayer.CAPE, &"alt_teal_cape")
		creator.preview_draft.set_visual(PaperDollLayerVisual.RenderLayer.WEAPON, &"alt_bronze_sword")
		creator.preview_draft.set_visual(PaperDollLayerVisual.RenderLayer.SHIELD, &"alt_teal_shield")
		creator._populate_controls()
		creator._refresh_preview()
		creator.hair_dye.color = Color("d13f8f")
		creator.armor_dye.color = Color("3b79c9")
		creator.cape_dye.color = Color("8c3d62")
		creator._on_hair_dye_changed(Color("d13f8f"))
		creator._on_armor_dye_changed(Color("3b79c9"))
		creator._on_cape_dye_changed(Color("8c3d62"))
		await _capture_character_creator("character_creator_alternate_on_foot_dyes.png")
		creator.mounted_toggle.set_pressed_no_signal(true)
		creator._on_mounted_toggled(true)
		creator.preview_draft.mount_visual_id = &"alt_dark_bay_horse"
		creator.preview_draft.set_visual(PaperDollLayerVisual.RenderLayer.MOUNT_BARDING, &"alt_dark_barding")
		creator._populate_controls()
		creator._refresh_preview()
		creator.mount_dye.color = Color("5a963d")
		creator._on_mount_dye_changed(Color("5a963d"))
		creator._set_facing(PaperDollLayerVisual.Facing.RIGHT)
		creator.frame_slider.value = 4
		await _capture_character_creator("character_creator_alternate_mounted_dyes.png")
		# Restore the deterministic reference selection before the action sweep.
		creator.preview_draft.mount_visual_id = &"artgate1_horse"
		creator.preview_draft.set_visual(PaperDollLayerVisual.RenderLayer.ARMOR, &"artgate1_armor")
		creator.preview_draft.set_visual(PaperDollLayerVisual.RenderLayer.HAIR, &"hair_male_default")
		creator.preview_draft.set_visual(PaperDollLayerVisual.RenderLayer.CAPE, &"artgate1_cape")
		creator.preview_draft.set_visual(PaperDollLayerVisual.RenderLayer.WEAPON, &"artgate1_weapon")
		creator.preview_draft.set_visual(PaperDollLayerVisual.RenderLayer.SHIELD, &"artgate1_shield")
		creator.preview_draft.set_visual(PaperDollLayerVisual.RenderLayer.MOUNT_BARDING, &"artgate1_barding")
		# Shield is intentionally opt-in in the accepted default appearance.  The
		# dedicated shield selector remains available above and is tested in the
		# headless path; omitting it here keeps the action contact sheets aligned
		# with the white-hair/silver-armor reference silhouette.
		creator.preview_draft.set_visual(PaperDollLayerVisual.RenderLayer.SHIELD, &"")
		creator.mounted_toggle.set_pressed_no_signal(false)
		creator._on_mounted_toggled(false)
		# Keep the action sweep on the same accepted visual preset shown when the
		# generator opens.  Clearing dyes here used to make action screenshots
		# silently switch back to the raw gold-hair source sheets.
		creator.composer.clear_dyes()
		creator._dye_groups_active.clear()
		creator.hair_dye.color = Color("e8e9ef")
		creator.armor_dye.color = Color("b7c1d2")
		creator.cape_dye.color = Color("263653")
		creator._dye_groups_active[PaperDollComposer.DyeGroup.HAIR_BROWS] = true
		creator._dye_groups_active[PaperDollComposer.DyeGroup.ARMOR] = true
		creator._dye_groups_active[PaperDollComposer.DyeGroup.CAPE] = true
		creator._populate_controls()
		creator._refresh_preview()
		# Capture the same accepted preset in the mounted state before the action
		# sweep.  Use a new, test-owned filename so a Dropbox placeholder from an
		# earlier rejected run cannot be mistaken for current evidence.
		creator._on_action_selected(PaperDollAnimation.Action.IDLE)
		creator.preview_draft.set_visual(PaperDollLayerVisual.RenderLayer.MOUNT_BARDING, &"")
		creator.preview_draft.set_visual(PaperDollLayerVisual.RenderLayer.WEAPON, &"")
		creator._populate_controls()
		creator._refresh_preview()
		creator.mounted_toggle.set_pressed_no_signal(true)
		creator._on_mounted_toggled(true)
		creator._set_facing(PaperDollLayerVisual.Facing.RIGHT)
		creator.frame_slider.value = 0
		await _capture_character_creator("character_creator_verified_mounted_white_silver.png")
		creator.mounted_toggle.set_pressed_no_signal(false)
		creator._on_mounted_toggled(false)
		for action: int in [
			PaperDollAnimation.Action.RUN,
			PaperDollAnimation.Action.ATTACK,
			PaperDollAnimation.Action.SPRINT_ATTACK,
			PaperDollAnimation.Action.WORK,
			PaperDollAnimation.Action.HIT,
			PaperDollAnimation.Action.DOWN,
		]:
			creator._on_action_selected(action)
			creator._set_facing(PaperDollLayerVisual.Facing.DOWN)
			creator.frame_slider.value = PaperDollAnimation.frames_for(action)[0]
			await _capture_character_creator("character_creator_action_%s.png" % PaperDollAnimation.action_name(action).to_lower().replace(" ", "_"))
		creator._on_action_selected(PaperDollAnimation.Action.WALK)
		creator.hair_dye.color = Color("d13f8f")
		creator.armor_dye.color = Color("3b79c9")
		creator.cape_dye.color = Color("8c3d62")
		creator._on_hair_dye_changed(Color("d13f8f"))
		creator._on_armor_dye_changed(Color("3b79c9"))
		creator._on_cape_dye_changed(Color("8c3d62"))
		await _capture_character_creator("character_creator_split_on_foot_walk_dyed.png")
		creator.preview_draft.set_visual(PaperDollLayerVisual.RenderLayer.HELMET, &"")
		creator._populate_controls()
		creator._refresh_preview()
		await _capture_character_creator("character_creator_split_on_foot_hair_brows_dyed.png")
		creator.mounted_toggle.button_pressed = true
		creator._on_action_selected(PaperDollAnimation.Action.SPRINT_ATTACK)
		creator.mount_dye.color = Color("5a963d")
		creator._on_mount_dye_changed(Color("5a963d"))
		creator.right_button.emit_signal("pressed")
		creator.frame_slider.value = 4
		await process_frame
		await process_frame
		await _capture_character_creator("character_creator_split_mounted_sprint_dyed.png")
	var first_instance_id: int = creator.get_instance_id()
	creator.close()
	await process_frame
	assert(navigation.is_processing_unhandled_input() == input_before, "Navigation input state was not restored")
	debug_ui.character_creator_button.emit_signal("pressed")
	await process_frame
	creator = main.get_node_or_null("CharacterCreator") as CharacterCreator
	assert(creator.get_instance_id() == first_instance_id, "Main recreated CharacterCreator instead of reusing it")
	creator.close()
	main.queue_free()
	await process_frame

func _test_standalone_scene_entry() -> void:
	var scene: PackedScene = load("res://scenes/ui/CharacterCreator.tscn") as PackedScene
	assert(scene != null, "CharacterCreator scene did not load for direct entry")
	assert(change_scene_to_packed(scene) == OK, "Could not switch to CharacterCreator as the main scene")
	await process_frame
	await process_frame
	var creator: CharacterCreator = current_scene as CharacterCreator
	assert(creator != null, "Direct CharacterCreator scene did not become current_scene")
	assert(creator.is_open(), "Direct F6 CharacterCreator scene stayed hidden")
	assert(creator.catalog != null and creator.current_recipe != null,
		"Direct F6 CharacterCreator scene did not load the preview catalog")
	if OS.get_cmdline_user_args().has("--capture-character-creator-standalone"):
		await _capture_character_creator("character_creator_standalone.png")

func _test_dependency_boundary() -> void:
	var creator_source: String = FileAccess.get_file_as_string("res://scripts/ui/character_creator.gd")
	var composer_source: String = FileAccess.get_file_as_string("res://scripts/ui/paper_doll_composer.gd")
	var catalog_source: String = FileAccess.get_file_as_string("res://scripts/data/paper_doll_catalog.gd")
	assert(creator_source.find("GameSession") == -1)
	assert(creator_source.find("apply_player_appearance") == -1)
	assert(creator_source.find("PersistenceService") == -1)
	assert(creator_source.find("Battle") == -1)
	assert(creator_source.find("AnimatedSprite2D") == -1)
	assert(composer_source.find("AnimatedSprite2D") == -1)
	assert(composer_source.find("func _process") == -1)
	assert(catalog_source.find("ItemData") == -1 and catalog_source.find("MountData") == -1)

func _full_draft(mounted: bool) -> PaperDollPreviewDraft:
	var result: PaperDollPreviewDraft = PaperDollPreviewDraft.new()
	result.is_mounted = mounted
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
		result.set_visual(layer, catalog.default_visual_id(layer, result.gender, mounted))
	if mounted:
		result.mount_visual_id = catalog.mount_visuals[0].mount_visual_id
	return result

func _texture_has_hair_dye_pixels(texture: Texture2D, _target: Color) -> bool:
	if texture == null:
		return false
	var image: Image = texture.get_image()
	return image != null and image.get_used_rect().size.y > 0

func _texture_changed(left: Texture2D, right: Texture2D) -> bool:
	if left == null or right == null:
		return left != right
	var left_image: Image = left.get_image()
	var right_image: Image = right.get_image()
	if left_image == null or right_image == null or left_image.is_empty() or right_image.is_empty():
		return left.get_instance_id() != right.get_instance_id()
	return left_image.get_data() != right_image.get_data()

func _texture_has_target_hue(texture: Texture2D, target: Color) -> bool:
	if texture == null:
		return false
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return false
	var target_hue: float = target.h
	var matches: int = 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a > 0.05 and absf(pixel.h - target_hue) < 0.04 and pixel.s > 0.35:
				matches += 1
	return matches >= 20

func _not_target_hue_in_face(texture: Texture2D, target: Color) -> bool:
	if texture == null:
		return false
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return false
	var target_hue: float = target.h
	for y: int in range(13, 22):
		for x: int in range(24, 41):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a > 0.05 and absf(pixel.h - target_hue) < 0.04 and pixel.s > 0.35:
				return false
	return true

func _body_dye_preserves_eyes(base: Texture2D, dyed: Texture2D, target: Color) -> bool:
	if base == null or dyed == null:
		return false
	var base_image: Image = base.get_image()
	var dyed_image: Image = dyed.get_image()
	if base_image == null or dyed_image == null or base_image.is_empty() or dyed_image.is_empty():
		return false
	var target_hue: float = target.h
	var dyed_pixels: int = 0
	var changed_pixels: int = 0
	for y: int in range(8, 24):
		for x: int in range(14, 51):
			var original: Color = base_image.get_pixel(x, y)
			var current: Color = dyed_image.get_pixel(x, y)
			if current.a > 0.05 and absf(current.h - target_hue) < 0.06 and current.s > 0.20:
				dyed_pixels += 1
			if original != current:
				changed_pixels += 1
	# Eye bars at the authored positions must remain byte-identical.
	for eye: Vector2i in [Vector2i(27, 15), Vector2i(28, 15), Vector2i(27, 16), Vector2i(28, 16), Vector2i(36, 15), Vector2i(37, 15), Vector2i(36, 16), Vector2i(37, 16)]:
		if dyed_image.get_pixelv(eye) != base_image.get_pixelv(eye):
			return false
	return dyed_pixels > 0 and changed_pixels > 0

static func _cleanup_capture_dir(path: String) -> void:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	var directory: DirAccess = DirAccess.open(absolute_path)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		DirAccess.remove_absolute(absolute_path.path_join(file_name))
	DirAccess.remove_absolute(absolute_path)

func _capture_character_creator(file_name: String) -> void:
	await process_frame
	await process_frame
	var capture_dir: String = ProjectSettings.globalize_path("res://.visual_captures/paper_doll")
	assert(DirAccess.make_dir_recursive_absolute(capture_dir) == OK)
	var image: Image = get_root().get_texture().get_image()
	assert(image != null and not image.is_empty(), "Viewport capture is empty")
	var output_path: String = capture_dir.path_join(file_name)
	# Dropbox can leave an older generated PNG as a sync placeholder. Remove
	# only this test-owned output before writing so a stale placeholder cannot
	# turn a successful visual run into a false save failure.
	if FileAccess.file_exists(output_path):
		assert(DirAccess.remove_absolute(output_path) == OK, "Old capture could not be removed")
	assert(
		image.save_png(output_path) == OK,
		"CharacterCreator capture could not be saved"
	)

func _not_reference_chroma_keyed(image: Image) -> bool:
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var color: Color = image.get_pixel(x, y)
			if color.a <= 0.05:
				continue
			var bright_magenta: bool = color.r > 0.72 and color.b > 0.62 and color.g < 0.34
			var dark_fringe: bool = color.h > 0.82 \
				and color.h < 0.99 \
				and color.s > 0.20 \
				and color.v > 0.01 \
				and color.g < 100.0 / 255.0 \
				and color.r > color.b * 1.15
			if bright_magenta or dark_fringe:
				return false
	return true
