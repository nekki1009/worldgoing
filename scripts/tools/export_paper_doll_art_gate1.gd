extends SceneTree

func _init() -> void:
	var err: Error = PaperDollCatalog.save_art_gate1_parts()
	if err != OK:
		push_error("Art Gate 1 export failed: %s" % error_string(err))
		quit(1)
		return
	var count: int = _export_contact_sheets(PaperDollCatalog.create_art_gate1_catalog())
	if count != 42:
		push_error("Art Gate 1 contact sheet count changed: %d" % count)
		quit(1)
		return
	print("Reference-derived Art Gate 1 runtime parts and %d contact sheets exported" % count)
	quit()

func _export_contact_sheets(catalog: PaperDollCatalog) -> int:
	var output_dir: String = "res://.visual_captures/paper_doll/art_gate1"
	var absolute_dir: String = ProjectSettings.globalize_path(output_dir)
	if DirAccess.make_dir_recursive_absolute(absolute_dir) != OK:
		return 0
	var count: int = 0
	for visual: PaperDollLayerVisual in catalog.layer_visuals:
		for gender: int in [PaperDollLayerVisual.Gender.MALE, PaperDollLayerVisual.Gender.FEMALE]:
			for mounted: bool in [false, true]:
				if visual.render_layer == PaperDollLayerVisual.RenderLayer.MOUNT_BARDING and not mounted:
					continue
				var recipe: PaperDollRecipe = catalog.resolve_recipe(_isolated_draft(catalog, visual, gender, mounted))
				if recipe != null and PaperDollContactSheet.save_png(
						recipe,
						output_dir.path_join("%s_%s_%s.png" % [
							visual.visual_id,
							PaperDollLayerVisual.gender_name(gender),
							PaperDollLayerVisual.pose_name(mounted),
						])
					) == OK:
					count += 1
	for mount: PaperDollMountVisual in catalog.sorted_mounts():
		for gender: int in [PaperDollLayerVisual.Gender.MALE, PaperDollLayerVisual.Gender.FEMALE]:
			var draft: PaperDollPreviewDraft = PaperDollPreviewDraft.new()
			draft.gender = gender
			draft.is_mounted = true
			draft.mount_visual_id = mount.mount_visual_id
			draft.set_visual(
				PaperDollLayerVisual.RenderLayer.BODY,
				catalog.default_visual_id(PaperDollLayerVisual.RenderLayer.BODY, gender)
			)
			var recipe: PaperDollRecipe = catalog.resolve_recipe(draft)
			if recipe != null and PaperDollContactSheet.save_png(
					recipe,
					output_dir.path_join("%s_%s_mounted.png" % [
						mount.mount_visual_id,
						PaperDollLayerVisual.gender_name(gender),
					])
				) == OK:
				count += 1
	for mounted: bool in [false, true]:
		var recipe: PaperDollRecipe = catalog.resolve_recipe(_full_draft(catalog, mounted))
		if recipe != null and PaperDollContactSheet.save_png(
				recipe,
				output_dir.path_join("stress_%s.png" % PaperDollLayerVisual.pose_name(mounted))
			) == OK:
			count += 1
	return count

func _isolated_draft(
		catalog: PaperDollCatalog,
		visual: PaperDollLayerVisual,
		gender: int,
		mounted: bool
	) -> PaperDollPreviewDraft:
	var result: PaperDollPreviewDraft = PaperDollPreviewDraft.new()
	result.gender = gender
	result.is_mounted = mounted
	result.set_visual(
		PaperDollLayerVisual.RenderLayer.BODY,
		catalog.default_visual_id(PaperDollLayerVisual.RenderLayer.BODY, gender)
	)
	result.set_visual(visual.render_layer, visual.visual_id)
	if mounted:
		result.mount_visual_id = catalog.sorted_mounts()[0].mount_visual_id
	return result

func _full_draft(catalog: PaperDollCatalog, mounted: bool) -> PaperDollPreviewDraft:
	var result: PaperDollPreviewDraft = PaperDollPreviewDraft.new()
	result.is_mounted = mounted
	for layer: int in CharacterCreator.SELECTABLE_LAYERS:
		result.set_visual(layer, catalog.default_visual_id(layer, result.gender, mounted))
	if mounted:
		result.mount_visual_id = catalog.sorted_mounts()[0].mount_visual_id
	return result
