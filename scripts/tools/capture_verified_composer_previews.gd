extends SceneTree

## Captures the current Composer output, not an offline contact-sheet fixture.
## Every image below is produced by the same Sprite2D pool used by the lab.

const OUTPUT_DIR := "res://.visual_captures/paper_doll/verified_composer"
const SCALE := 4
const VIEW_SIZE := Vector2i(256, 256)

var _viewport: SubViewport
var _composer: PaperDollComposer
var _catalog: PaperDollCatalog

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_catalog = PaperDollCatalog.create_art_gate1_catalog()
	_viewport = SubViewport.new()
	_viewport.size = VIEW_SIZE
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(_viewport)
	var background := ColorRect.new()
	background.color = Color("121821")
	background.position = Vector2.ZERO
	background.size = Vector2(VIEW_SIZE)
	_viewport.add_child(background)
	_composer = PaperDollComposer.new()
	_composer.position = Vector2(128, 224)
	_composer.scale = Vector2(SCALE, SCALE)
	_viewport.add_child(_composer)

	var output_dir := ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(output_dir)
	var captures: Array = [
		[false, PaperDollLayerVisual.Facing.DOWN, 0, "01_on_foot_down.png", &"hair_male_default"],
		[false, PaperDollLayerVisual.Facing.UP, 0, "02_on_foot_up.png", &"hair_male_default"],
		[false, PaperDollLayerVisual.Facing.RIGHT, 0, "03_on_foot_right.png", &"hair_male_default"],
		[false, PaperDollLayerVisual.Facing.LEFT, 0, "04_on_foot_left.png", &"hair_male_default"],
		[true, PaperDollLayerVisual.Facing.RIGHT, 0, "05_mounted_right.png", &"hair_male_default"],
		[false, PaperDollLayerVisual.Facing.DOWN, 0, "06_alt_braided_on_foot.png", &"alt_braided_hair"],
		[true, PaperDollLayerVisual.Facing.RIGHT, 0, "07_alt_braided_mounted.png", &"alt_braided_hair"],
	]
	for capture: Array in captures:
		var recipe := _recipe(capture[0] as bool, capture[4] as StringName)
		assert(recipe != null and recipe.is_accepted_reference, "Accepted reference recipe did not resolve")
		_composer.apply_recipe(recipe)
		_composer.update_frame(capture[1] as int, capture[2] as int)
		await process_frame
		await process_frame
		var image := _viewport.get_texture().get_image()
		assert(image != null and not image.is_empty())
		var path: String = output_dir.path_join(capture[3] as String)
		assert(image.save_png(path) == OK, "Could not save %s" % path)
		print("VERIFIED_COMPOSER_CAPTURE=%s" % path)
	# The alternate hairstyle must still belong to the shared hair+brows dye
	# group while the body/armor/cape pixels remain untouched.
	var dyed_recipe := _recipe(false, &"alt_braided_hair")
	_composer.apply_recipe(dyed_recipe)
	_composer.set_dye(PaperDollComposer.DyeGroup.HAIR_BROWS, Color("9a4de3"))
	_composer.update_frame(PaperDollLayerVisual.Facing.DOWN, 0)
	await process_frame
	await process_frame
	var dyed_image := _viewport.get_texture().get_image()
	assert(dyed_image.save_png(output_dir.path_join("08_alt_braided_hair_dyed.png")) == OK)
	print("VERIFIED_COMPOSER_CAPTURE=%s" % output_dir.path_join("08_alt_braided_hair_dyed.png"))
	quit()

func _recipe(mounted: bool, hair_id: StringName = &"hair_male_default") -> PaperDollRecipe:
	var draft := PaperDollPreviewDraft.new()
	draft.is_mounted = mounted
	draft.gender = PaperDollLayerVisual.Gender.MALE
	draft.set_visual(PaperDollLayerVisual.RenderLayer.BODY, &"body_male_default")
	draft.set_visual(PaperDollLayerVisual.RenderLayer.ARMOR, &"artgate1_armor")
	draft.set_visual(PaperDollLayerVisual.RenderLayer.HAIR, hair_id)
	draft.set_visual(PaperDollLayerVisual.RenderLayer.CAPE, &"artgate1_cape")
	# The accepted board is the no-weapon white-hair/silver-armor reference.
	# Weapon, shield, helmet, and barding remain opt-in lab variants.
	draft.mount_visual_id = &"artgate1_horse" if mounted else &""
	return _catalog.resolve_recipe(draft)
