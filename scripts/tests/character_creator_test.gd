extends SceneTree

var catalog: PaperDollCatalog

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	catalog = PaperDollCatalog.create_debug_catalog()
	_test_catalog_contract()
	print("CHARACTER CREATOR TEST 1 PASS: catalog IDs, gender policy, sheets, defaults, and mount bundle are valid")

	var recipes: Dictionary = _test_recipe_boundary()
	print("CHARACTER CREATOR TEST 2 PASS: detached draft resolves on-foot and mounted recipes without gameplay state")

	await _test_composer(recipes["mounted"] as PaperDollRecipe)
	print("CHARACTER CREATOR TEST 3 PASS: one 11-Sprite pool owns frame, mirror, anchor, and z-order updates")

	_test_contact_sheet()
	print("CHARACTER CREATOR TEST 4 PASS: pure Image contact sheets generate four logical directions with mirrored LEFT")

	await _test_character_creator_scene()
	print("CHARACTER CREATOR TEST 5 PASS: asset lab controls, timer, validation, and close lifecycle are reusable")

	await _test_main_modal_entry()
	print("CHARACTER CREATOR TEST 6 PASS: DebugUI lazily opens one modal lab and restores navigation input")

	_test_dependency_boundary()
	print("CHARACTER CREATOR TEST 7 PASS: lab has no Session, Persistence, AnimatedSprite2D, or Battle dependency")

	print("Character creator tests passed: 7 cases")
	quit()

func _test_catalog_contract() -> void:
	var issues: PackedStringArray = catalog.validation_issues()
	assert(issues.is_empty(), "Debug catalog is invalid: %s" % " | ".join(issues))
	assert(catalog.layer_visuals.size() == 8, "Debug catalog does not cover all selectable layers")
	assert(catalog.mount_visuals.size() == 1, "Debug catalog does not contain one mount bundle")
	assert(PaperDollLayerVisual.is_valid_visual_id(&"lowercase_id_2"))
	assert(not PaperDollLayerVisual.is_valid_visual_id(&"Bad-ID"))
	var armor: PaperDollLayerVisual = catalog.find_visual(&"debug_armor")
	assert(armor != null and armor.gender_policy == PaperDollLayerVisual.GenderPolicy.UNISEX)
	assert(
		armor.resolve(PaperDollLayerVisual.Gender.MALE, false) \
		== armor.resolve(PaperDollLayerVisual.Gender.FEMALE, false),
		"UNISEX visual did not resolve to the same texture"
	)
	for visual: PaperDollLayerVisual in catalog.layer_visuals:
		assert(visual.validation_issues().is_empty(), "Layer visual failed validation: %s" % visual.visual_id)
	var mount: PaperDollMountVisual = catalog.mount_visuals[0]
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

func _test_recipe_boundary() -> Dictionary:
	var on_foot: PaperDollPreviewDraft = _full_draft(false)
	var copy: PaperDollPreviewDraft = on_foot.copy()
	copy.set_visual(PaperDollLayerVisual.RenderLayer.WEAPON, &"")
	assert(
		on_foot.visual_id_for(PaperDollLayerVisual.RenderLayer.WEAPON) == &"debug_weapon",
		"Draft copy shared its selection Dictionary"
	)
	var on_foot_recipe: PaperDollRecipe = catalog.resolve_recipe(on_foot)
	assert(on_foot_recipe != null and not on_foot_recipe.is_mounted)
	assert(on_foot_recipe.visible_layer_count() == 7, "On-foot recipe exposed mount-only layers")
	assert(on_foot_recipe.texture_for(PaperDollLayerVisual.RenderLayer.MOUNT_TAIL) == null)
	assert(on_foot_recipe.texture_for(PaperDollLayerVisual.RenderLayer.MOUNT_BODY) == null)
	assert(on_foot_recipe.texture_for(PaperDollLayerVisual.RenderLayer.MOUNT_HEAD) == null)
	assert(on_foot_recipe.texture_for(PaperDollLayerVisual.RenderLayer.MOUNT_BARDING) == null)

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
	for layer: int in range(PaperDollLayerVisual.RenderLayer.COUNT):
		var sprite: Sprite2D = composer.sprite_for(layer)
		assert(sprite != null and sprite.visible)
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

func _test_character_creator_scene() -> void:
	var scene: PackedScene = load("res://scenes/ui/CharacterCreator.tscn") as PackedScene
	assert(scene != null, "CharacterCreator scene did not load")
	var creator: CharacterCreator = scene.instantiate() as CharacterCreator
	get_root().add_child(creator)
	await process_frame
	assert(not creator.is_open())
	assert(creator.composer.sprite_count() == PaperDollLayerVisual.RenderLayer.COUNT)
	creator.open(catalog)
	assert(creator.is_open() and creator.tabs.current_tab == 1)
	assert(creator.current_recipe != null)
	assert(creator.run_check_all().is_empty())
	assert(not creator.animation_timer.is_stopped(), "Unified animation Timer did not start")
	var frame_before_tick: int = creator.current_frame_x
	creator.animation_timer.emit_signal("timeout")
	assert(
		creator.current_frame_x == posmod(frame_before_tick + 1, PaperDollLayerVisual.FRAME_COLUMNS),
		"Unified animation Timer did not advance the shared frame"
	)
	for layer: int in range(PaperDollLayerVisual.RenderLayer.COUNT):
		var sprite: Sprite2D = creator.composer.sprite_for(layer)
		if sprite.visible:
			assert(sprite.frame_coords.x == creator.current_frame_x, "Visible layer missed Timer frame update")
	var capture_dir: String = "user://character_creator_test_captures"
	assert(creator.export_all_contact_sheets(capture_dir) == 34, "Full catalog export count changed")
	_cleanup_capture_dir(capture_dir)
	creator.left_button.emit_signal("pressed")
	assert(creator.composer.current_facing == PaperDollLayerVisual.Facing.LEFT)
	assert(creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.BODY).flip_h)
	creator.mounted_toggle.button_pressed = true
	assert(creator.preview_draft.is_mounted and creator.current_recipe.visible_layer_count() == 11)
	var closed_count: Array[int] = [0]
	creator.closed.connect(func() -> void: closed_count[0] += 1)
	creator.close()
	assert(not creator.is_open() and closed_count[0] == 1)
	creator.open(catalog)
	assert(creator.composer.get_child_count() == PaperDollLayerVisual.RenderLayer.COUNT)
	creator.close()
	creator.queue_free()
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
		await _capture_character_creator()
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

static func _cleanup_capture_dir(path: String) -> void:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	var directory: DirAccess = DirAccess.open(absolute_path)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		DirAccess.remove_absolute(absolute_path.path_join(file_name))
	DirAccess.remove_absolute(absolute_path)

func _capture_character_creator() -> void:
	await process_frame
	await process_frame
	var capture_dir: String = ProjectSettings.globalize_path("res://.visual_captures/paper_doll")
	assert(DirAccess.make_dir_recursive_absolute(capture_dir) == OK)
	var image: Image = get_root().get_texture().get_image()
	assert(image != null and not image.is_empty(), "Viewport capture is empty")
	assert(
		image.save_png(capture_dir.path_join("character_creator_milestone_1.png")) == OK,
		"CharacterCreator capture could not be saved"
	)
