extends SceneTree

## Fast, deterministic CharacterCreator lifecycle contract.
##
## This test intentionally uses in-memory 512x192 sheets.  It verifies the
## production CharacterCreator scene, PaperDollCatalog, PaperDollRecipe and
## PaperDollComposer paths without importing the whole Worldgoing project or
## synchronously reading a SubViewport texture (both are inappropriate for a
## headless state test).  Visual pixel acceptance remains covered by the
## dedicated Composer/reference-image tests.

const SCENE_PATH := "res://scenes/ui/CharacterCreator.tscn"
const OUTPUT_PATH := "res://.visual_captures/paper_doll/character_creator_lifecycle_contract.txt"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load(SCENE_PATH) as PackedScene
	assert(scene != null, "CharacterCreator scene failed to load")
	var creator = scene.instantiate()
	assert(creator != null, "CharacterCreator scene failed to instantiate")
	root.add_child(creator)
	await process_frame
	await process_frame

	var catalog: PaperDollCatalog = _make_contract_catalog()
	creator.open(catalog)
	await process_frame
	await process_frame
	assert(creator.preview_draft != null, "CharacterCreator did not create a draft")
	assert(creator.current_recipe != null, "CharacterCreator did not resolve the initial recipe")
	assert(not creator.preview_draft.is_mounted, "CharacterCreator opened mounted unexpectedly")
	assert(creator.hair_option.item_count == PaperDollCatalog.APPROVED_HAIR_IDS.size() + 1)
	assert(creator.composer.sprite_count() == PaperDollLayerVisual.RenderLayer.COUNT)
	assert(creator.composer.visible_sprite_count() > 0)
	print("CHARACTER_CREATOR_CHECKPOINT initial_state_verified")

	creator.mounted_toggle.set_pressed_no_signal(true)
	creator._on_mounted_toggled(true)
	await process_frame
	await process_frame
	assert(creator.preview_draft.is_mounted, "Mounted toggle did not update the draft")
	assert(creator.current_recipe != null and creator.current_recipe.is_mounted)
	assert(creator.composer.visible_sprite_count() > 0)
	print("CHARACTER_CREATOR_CHECKPOINT mounted_state_verified")

	var output_path := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var report := FileAccess.open(output_path, FileAccess.WRITE)
	assert(report != null)
	report.store_line("initial=PASS")
	report.store_line("mounted_toggle=PASS")
	report.store_line("sprite_pool=%d" % creator.composer.sprite_count())
	report.store_line("visible_mounted_sprites=%d" % creator.composer.visible_sprite_count())
	report.close()

	creator.close()
	creator.queue_free()
	print("CHARACTER_CREATOR_LIFECYCLE_PASS")
	quit(0)

func _make_contract_catalog() -> PaperDollCatalog:
	var catalog := PaperDollCatalog.new()
	var visuals: Array[PaperDollLayerVisual] = []
	visuals.append(_make_visual(&"body_contract", PaperDollLayerVisual.RenderLayer.BODY, Color("d99d67"), true))
	visuals.append(_make_visual(&"armor_contract", PaperDollLayerVisual.RenderLayer.ARMOR, Color("b7c1d2"), true))
	for hair_id: StringName in PaperDollCatalog.APPROVED_HAIR_IDS:
		visuals.append(_make_visual(hair_id, PaperDollLayerVisual.RenderLayer.HAIR, Color("e8e9ef"), true))
	visuals.append(_make_visual(&"cape_contract", PaperDollLayerVisual.RenderLayer.CAPE, Color("263653"), true))
	visuals.append(_make_visual(&"barding_contract", PaperDollLayerVisual.RenderLayer.MOUNT_BARDING, Color("9c3f3f"), false))
	catalog.layer_visuals = visuals
	catalog.default_male_body_visual_id = &"body_contract"
	catalog.default_female_body_visual_id = &"body_contract"
	catalog.default_male_hair_visual_id = &"hair_short_spiky"
	catalog.default_female_hair_visual_id = &"hair_short_spiky"

	var mount := PaperDollMountVisual.new()
	mount.mount_visual_id = &"mount_contract"
	mount.tail = _make_visual(&"mount_tail_contract", PaperDollLayerVisual.RenderLayer.MOUNT_TAIL, Color("604631"), false)
	mount.body = _make_visual(&"mount_body_contract", PaperDollLayerVisual.RenderLayer.MOUNT_BODY, Color("9a704d"), false)
	mount.head = _make_visual(&"mount_head_contract", PaperDollLayerVisual.RenderLayer.MOUNT_HEAD, Color("a87a55"), false)
	catalog.mount_visuals = [mount]
	return catalog

func _make_visual(
	visual_id: StringName,
	layer: int,
	color: Color,
	is_character_layer: bool
) -> PaperDollLayerVisual:
	var visual := PaperDollLayerVisual.new()
	visual.visual_id = visual_id
	visual.render_layer = layer
	visual.gender_policy = PaperDollLayerVisual.GenderPolicy.UNISEX
	var sheet := _make_sheet(color, layer)
	if PaperDollLayerVisual.is_mounted_only_layer(layer):
		visual.mounted_unisex = sheet
	else:
		visual.on_foot_unisex = sheet
		visual.mounted_unisex = _make_sheet(color.lightened(0.04), layer)
	return visual

func _make_sheet(color: Color, layer: int) -> Texture2D:
	var image := Image.create(
		PaperDollLayerVisual.SHEET_SIZE.x,
		PaperDollLayerVisual.SHEET_SIZE.y,
		false,
		Image.FORMAT_RGBA8
	)
	image.fill(Color.TRANSPARENT)
	for row: int in range(PaperDollLayerVisual.SOURCE_ROWS):
		for frame_x: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
			var origin := Vector2i(
				frame_x * PaperDollLayerVisual.FRAME_SIZE.x,
				row * PaperDollLayerVisual.FRAME_SIZE.y
			)
			var inset: int = 8 + posmod(layer * 3 + frame_x, 4)
			var height: int = 16 + posmod(layer + row, 5)
			image.fill_rect(
				Rect2i(origin + Vector2i(inset, 18 + row * 2), Vector2i(48 - inset * 2, height)),
				color
			)
	return ImageTexture.create_from_image(image)
