extends SceneTree

## Verifies the real CharacterCreator control path, including the mounted
## checkbox. This deliberately calls the same handler as the UI signal. The
## saved artifacts use the pure Image contact-sheet path instead of a
## synchronous SubViewport GPU readback, which is not a valid headless test.

const SCENE_PATH := "res://scenes/ui/CharacterCreator.tscn"
const OUTPUT_DIR := "res://.visual_captures/paper_doll/report_fix"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load(SCENE_PATH) as PackedScene
	assert(scene != null, "CharacterCreator scene failed to load")
	var creator: CharacterCreator = scene.instantiate() as CharacterCreator
	root.add_child(creator)
	await process_frame
	await process_frame
	creator.open(PaperDollCatalog.create_art_gate1_catalog())
	await process_frame
	await process_frame
	assert(not creator.preview_draft.is_mounted, "Creator opened mounted unexpectedly")
	assert(creator.current_recipe != null and creator.current_recipe.is_accepted_reference)
	# The material-lab dropdown intentionally exposes only the four approved
	# hairstyles (plus the explicit None entry).  Assert the visible UI order,
	# not just the catalog constant, so a filtering regression cannot make the
	# preview silently fall back to a legacy/generated hair.
	var approved_hair_ids: Array[StringName] = [
		&"hair_short_spiky",
		&"hair_high_ponytail",
		&"hair_bob",
		&"hair_twin_braids",
	]
	assert(creator.hair_option.item_count == approved_hair_ids.size() + 1, "Hair option count is not four styles plus None")
	for index: int in range(approved_hair_ids.size()):
		assert(creator.hair_option.get_item_metadata(index + 1) == approved_hair_ids[index], "Hair option order/id mismatch at %d" % index)
	_save_preview(creator, "11_creator_on_foot.png")

	creator.mounted_toggle.set_pressed_no_signal(true)
	creator._on_mounted_toggled(true)
	await process_frame
	await process_frame
	assert(creator.preview_draft.is_mounted, "Mounted toggle did not update the draft")
	assert(creator.current_recipe != null and creator.current_recipe.is_mounted)
	assert(creator.current_recipe.is_accepted_reference, "Mounted toggle left the calibrated reference path")
	assert(creator.current_recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY) != null)
	_save_preview(creator, "12_creator_mounted.png")

	print("CHARACTER_CREATOR_MOUNT_TOGGLE_PASS")
	creator.close()
	creator.queue_free()
	quit()

func _save_preview(creator: CharacterCreator, file_name: String) -> void:
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(output_path)
	assert(creator.current_recipe != null)
	assert(PaperDollContactSheet.save_png(
		creator.current_recipe,
		output_path.path_join(file_name),
		true
	) == OK)
