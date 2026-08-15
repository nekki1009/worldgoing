extends SceneTree

## One focused visual regression set for the six reported creator failures.
## The images are intentionally named by the acceptance question, not by an
## internal implementation detail, so a human can compare them to
## assets/doll/reference directly.

const OUTPUT_DIR := "res://.visual_captures/paper_doll/report_fix"
const VIEW_SIZE := Vector2i(256, 256)
const SCALE := 4

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
	background.size = Vector2(VIEW_SIZE)
	_viewport.add_child(background)
	_composer = PaperDollComposer.new()
	_composer.position = Vector2(128, 224)
	_composer.scale = Vector2(SCALE, SCALE)
	_viewport.add_child(_composer)

	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(output_path)
	await _capture(_draft(false, false, PaperDollLayerVisual.Gender.MALE, &"hair_male_default"),
		PaperDollLayerVisual.Facing.DOWN, "01_male_reference_down.png", output_path)
	await _capture(_draft(false, false, PaperDollLayerVisual.Gender.FEMALE, &"hair_female_default"),
		PaperDollLayerVisual.Facing.DOWN, "02_female_heavy_armor_down.png", output_path)
	await _capture(_draft(false, true, PaperDollLayerVisual.Gender.MALE, &"hair_male_default"),
		PaperDollLayerVisual.Facing.DOWN, "03_armed_reference_down.png", output_path)
	await _capture(_draft(false, true, PaperDollLayerVisual.Gender.MALE, &"hair_male_default"),
		PaperDollLayerVisual.Facing.RIGHT, "04_armed_reference_right.png", output_path)
	await _capture(_draft(true, false, PaperDollLayerVisual.Gender.MALE, &"hair_male_default"),
		PaperDollLayerVisual.Facing.RIGHT, "05_mounted_reference_right.png", output_path)
	await _capture(_draft(true, true, PaperDollLayerVisual.Gender.MALE, &"hair_male_default"),
		PaperDollLayerVisual.Facing.RIGHT, "06_mounted_armed_reference_right.png", output_path)
	await _capture(_draft(false, false, PaperDollLayerVisual.Gender.MALE, &"alt_braided_hair"),
		PaperDollLayerVisual.Facing.DOWN, "07_alternate_hair_down.png", output_path)
	var approved_hair_styles: Array[StringName] = PaperDollCatalog.APPROVED_HAIR_IDS
	for style_index: int in range(approved_hair_styles.size()):
		var style_id: StringName = approved_hair_styles[style_index]
		var style_draft := _draft(false, false, PaperDollLayerVisual.Gender.MALE, style_id)
		await _capture(
			style_draft,
			PaperDollLayerVisual.Facing.DOWN,
			"hair_%02d_%s_down.png" % [style_index + 1, style_id],
			output_path
		)
		await _capture(
			style_draft,
			PaperDollLayerVisual.Facing.RIGHT,
			"hair_%02d_%s_right.png" % [style_index + 1, style_id],
			output_path
		)
		_composer.set_dye(PaperDollComposer.DyeGroup.HAIR_BROWS, Color("9a4de3"))
		_composer.update_frame(PaperDollLayerVisual.Facing.DOWN, 0)
		await _save_frame("hair_%02d_%s_dyed_down.png" % [style_index + 1, style_id], output_path)

	var dyed := _draft(false, false, PaperDollLayerVisual.Gender.MALE, &"alt_braided_hair")
	await _capture(dyed, PaperDollLayerVisual.Facing.DOWN, "08_alternate_hair_before_dye.png", output_path)
	_composer.set_dye(PaperDollComposer.DyeGroup.HAIR_BROWS, Color("9a4de3"))
	_composer.update_frame(PaperDollLayerVisual.Facing.DOWN, 0)
	await _save_frame("09_hair_brows_dyed_only.png", output_path)
	_composer.clear_dyes()
	_composer.set_dye(PaperDollComposer.DyeGroup.ARMOR, Color("58a9d8"))
	_composer.set_dye(PaperDollComposer.DyeGroup.CAPE, Color("4d70d9"))
	_composer.set_dye(PaperDollComposer.DyeGroup.MOUNT, Color("7f4b2a"))
	_composer.update_frame(PaperDollLayerVisual.Facing.RIGHT, 0)
	await _save_frame("10_armor_cape_mount_dyed.png", output_path)
	print("REPORTED_FAILURE_CASES=%s" % output_path)
	quit()

func _capture(draft: PaperDollPreviewDraft, facing: int, file_name: String, output_path: String) -> void:
	var recipe: PaperDollRecipe = _catalog.resolve_recipe(draft)
	assert(recipe != null, "Recipe did not resolve: %s" % file_name)
	assert(recipe.is_accepted_reference, "Reference bundle was not selected: %s" % file_name)
	if PaperDollCatalog.is_approved_hair_id(
			draft.visual_id_for(PaperDollLayerVisual.RenderLayer.HAIR)
		) or draft.visual_id_for(PaperDollLayerVisual.RenderLayer.HAIR) == &"alt_braided_hair":
		assert(recipe.reference_hair_is_hair_only, "Braided hair did not load as a hair-only silhouette: %s" % file_name)
	if draft.visual_id_for(PaperDollLayerVisual.RenderLayer.HELMET).is_empty():
		assert(recipe.reference_composite_texture == null, "Unexpected armed bundle: %s" % file_name)
	else:
		assert(recipe.reference_composite_texture != null, "Armed reference bundle missing: %s" % file_name)
	_composer.clear_dyes()
	_composer.apply_recipe(recipe)
	_composer.update_frame(facing, 0)
	await process_frame
	await process_frame
	assert(_viewport.get_texture().get_image().save_png(output_path.path_join(file_name)) == OK)

func _save_frame(file_name: String, output_path: String) -> void:
	await process_frame
	await process_frame
	assert(_viewport.get_texture().get_image().save_png(output_path.path_join(file_name)) == OK)

func _draft(
		mounted: bool,
		armed: bool,
		gender: int,
		hair_id: StringName
) -> PaperDollPreviewDraft:
	var draft := PaperDollPreviewDraft.new()
	draft.is_mounted = mounted
	draft.gender = gender
	draft.set_visual(
		PaperDollLayerVisual.RenderLayer.BODY,
		&"body_female_default" if gender == PaperDollLayerVisual.Gender.FEMALE else &"body_male_default"
	)
	draft.set_visual(PaperDollLayerVisual.RenderLayer.ARMOR, &"artgate1_armor")
	draft.set_visual(PaperDollLayerVisual.RenderLayer.HAIR, hair_id)
	draft.set_visual(PaperDollLayerVisual.RenderLayer.CAPE, &"artgate1_cape")
	if armed:
		draft.set_visual(PaperDollLayerVisual.RenderLayer.HELMET, &"artgate1_helmet")
		draft.set_visual(PaperDollLayerVisual.RenderLayer.WEAPON, &"artgate1_weapon")
		draft.set_visual(PaperDollLayerVisual.RenderLayer.SHIELD, &"artgate1_shield")
	draft.mount_visual_id = &"artgate1_horse" if mounted else &""
	return draft
