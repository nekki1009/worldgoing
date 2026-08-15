extends SceneTree

## GPU-backed visual check for the actual CharacterCreator/Asset Lab scene.
## This intentionally drives the same mounted signal and layer callbacks as the
## UI, then captures the visible window rather than only exporting contact sheets.

const SCENE_PATH := "res://scenes/ui/CharacterCreator.tscn"
const OUTPUT_DIR := "res://.visual_captures/paper_doll/lab_visual"
const HAIR_ID := &"hair_high_ponytail"

var _creator: CharacterCreator

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load(SCENE_PATH) as PackedScene
	assert(scene != null, "CharacterCreator scene failed to load")
	_creator = scene.instantiate() as CharacterCreator
	assert(_creator != null, "CharacterCreator scene failed to instantiate")
	root.add_child(_creator)
	await process_frame
	await process_frame
	_creator.open(PaperDollCatalog.create_art_gate1_catalog())
	await _settle()
	assert(not _creator.preview_draft.is_mounted, "visual capture opened mounted unexpectedly")
	assert(_creator.current_recipe != null and not _creator.current_recipe.is_mounted)
	_save("01_asset_lab_on_foot.png")
	var on_foot_idle_body: Texture2D = _creator.current_recipe.texture_for(
		PaperDollLayerVisual.RenderLayer.BODY
	)
	_creator.action_option.select(PaperDollAnimation.Action.WALK)
	_creator.action_option.item_selected.emit(PaperDollAnimation.Action.WALK)
	await _settle()
	assert(_creator.current_recipe.is_accepted_reference,
		"on-foot WALK switched away from the calibrated shared base")
	assert(_creator.current_recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY) == on_foot_idle_body,
		"on-foot WALK replaced the calibrated body sheet")
	_creator.action_option.select(PaperDollAnimation.Action.IDLE)
	_creator.action_option.item_selected.emit(PaperDollAnimation.Action.IDLE)
	await _settle()

	# Drive the actual CheckBox signal path.  The handler must resolve a mounted
	# recipe and the embedded SubViewport must show the horse, not just update a
	# hidden draft field.
	_creator.mounted_toggle.set_pressed(true)
	await _settle()
	assert(_creator.preview_draft.is_mounted, "mounted checkbox did not update the draft")
	assert(_creator.current_recipe != null and _creator.current_recipe.is_mounted, "mounted checkbox did not resolve a mounted recipe")
	# The accepted mounted reference is a calibrated rider+horse body board, so
	# its MountBody Sprite2D is intentionally hidden to avoid drawing a second
	# horse.  The visible BODY Sprite2D is the mounted base authority.
	assert(_creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.BODY).visible, "mounted base Sprite2D is hidden")
	_save("02_asset_lab_mounted.png")

	var hair_index := _find_option_metadata(_creator.hair_option, HAIR_ID)
	assert(hair_index >= 0, "approved hair is not exposed in Asset Lab")
	# Use the real OptionButton signal path so the visible label and the recipe
	# cannot diverge (a direct callback invocation would leave the old label).
	_creator.hair_option.select(hair_index)
	_creator.hair_option.item_selected.emit(hair_index)
	await _settle()
	assert(_creator.current_recipe != null, "hair selection invalidated the mounted recipe")
	assert(_creator.preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.HAIR) == HAIR_ID,
		"hair selection did not persist in the mounted lab")
	_save("03_asset_lab_mounted_high_ponytail.png")
	var male_hair_source: Texture2D = _creator.current_recipe.reference_hair_texture
	# Use the actual GenderOption signal path.  The selected hairstyle ID must
	# stay stable while its resolved source changes from the male sheet to the
	# female sheet; this proves the UI is gender-aware rather than just relabelled.
	_creator.gender_option.select(PaperDollLayerVisual.Gender.FEMALE)
	_creator.gender_option.item_selected.emit(PaperDollLayerVisual.Gender.FEMALE)
	await _settle()
	assert(_creator.preview_draft.gender == PaperDollLayerVisual.Gender.FEMALE,
		"female gender signal did not update the draft")
	assert(_creator.preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.HAIR) == HAIR_ID,
		"gender switch changed the selected hairstyle ID")
	var female_hair_source: Texture2D = _creator.current_recipe.reference_hair_texture
	assert(female_hair_source != null and female_hair_source != male_hair_source,
		"female gender did not resolve a separate hairstyle source")
	_save("03a_asset_lab_mounted_high_ponytail_female.png")
	_creator.gender_option.select(PaperDollLayerVisual.Gender.MALE)
	_creator.gender_option.item_selected.emit(PaperDollLayerVisual.Gender.MALE)
	await _settle()
	assert(_creator.preview_draft.gender == PaperDollLayerVisual.Gender.MALE,
		"male gender signal did not restore the draft")
	_creator.right_button.pressed.emit()
	await _settle()
	assert(_creator.preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.HAIR) == HAIR_ID,
		"right-facing preview reset the selected hairstyle")
	_save("03b_asset_lab_mounted_high_ponytail_right.png")
	_creator.left_button.pressed.emit()
	await _settle()
	assert(_creator.preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.HAIR) == HAIR_ID,
		"left-facing preview reset the selected hairstyle")
	_save("03c_asset_lab_mounted_high_ponytail_left.png")
	_creator.up_button.pressed.emit()
	await _settle()
	assert(_creator.preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.HAIR) == HAIR_ID,
		"up-facing preview reset the selected hairstyle")
	_save("03d_asset_lab_mounted_high_ponytail_up.png")
	_creator.down_button.pressed.emit()

	_creator.action_option.select(PaperDollAnimation.Action.WALK)
	_creator.action_option.item_selected.emit(PaperDollAnimation.Action.WALK)
	_creator._on_frame_changed(1)
	await _settle()
	assert(_creator.current_recipe != null, "mounted walk preview did not resolve")
	assert(_creator.current_recipe.is_accepted_reference,
		"mounted walk switched away from the calibrated shared base")
	assert(not _creator._recipe_uses_procedural_action(_creator.current_recipe),
		"mounted walk used the legacy split/procedural fallback")
	_save("04_asset_lab_mounted_walk_hair.png")

	var report := {
		"on_foot": true,
		"mounted": _creator.current_recipe.is_mounted,
		"gender": PaperDollLayerVisual.gender_name(_creator.preview_draft.gender),
		"accepted_reference": _creator.current_recipe.is_accepted_reference,
		"mounted_body_visible": _creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.MOUNT_BODY).visible,
		"hair": str(_creator.preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.HAIR)),
		"gendered_hair_pair_distinct": female_hair_source != male_hair_source,
		"action": PaperDollAnimation.action_name(_creator.current_action),
	}
	var report_path := ProjectSettings.globalize_path(OUTPUT_DIR).path_join("asset_lab_visual_report.json")
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	assert(file != null, "could not write visual report")
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("CHARACTER_CREATOR_ASSET_LAB_VISUAL_PASS")
	_creator.close()
	_creator.queue_free()
	quit()

func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func _save(file_name: String) -> void:
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR).path_join(file_name)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var image := get_root().get_texture().get_image()
	assert(image != null and not image.is_empty(), "viewport capture is empty: %s" % file_name)
	assert(image.save_png(output_path) == OK, "failed to save %s" % file_name)

func _find_option_metadata(option: OptionButton, visual_id: StringName) -> int:
	for index: int in range(option.item_count):
		var metadata: Variant = option.get_item_metadata(index)
		if str(metadata) == str(visual_id):
			return index
	return -1
