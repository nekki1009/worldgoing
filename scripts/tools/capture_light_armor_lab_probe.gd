extends SceneTree

## Focused GPU/data proof for the Asset Lab's craftable light armor pair.
## This deliberately runs against the production Catalog and CharacterCreator
## scene, but is launched from the small isolated probe project so a full
## Dropbox project startup timeout cannot be mistaken for a feature result.

const LIGHT_ARMOR_ID: StringName = &"light_armor"
const LIGHT_HELMET_ID: StringName = &"light_armor_helmet"
const OUTPUT_DIR := "res://.visual_captures/light_armor_lab"

var _creator: CharacterCreator

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://scenes/ui/CharacterCreator.tscn") as PackedScene
	assert(scene != null, "CharacterCreator scene failed to load")
	_creator = scene.instantiate() as CharacterCreator
	assert(_creator != null, "CharacterCreator scene failed to instantiate")
	root.add_child(_creator)
	await _settle()

	var catalog := PaperDollCatalog.create_art_gate1_catalog()
	var catalog_issues := catalog.validation_issues()
	assert(catalog_issues.is_empty(), "Production catalog invalid: %s" % "; ".join(catalog_issues))
	_creator.open(catalog)
	await _settle()

	var armor_visual := catalog.find_visual(LIGHT_ARMOR_ID)
	var helmet_visual := catalog.find_visual(LIGHT_HELMET_ID)
	assert(armor_visual != null, "Light armor visual is missing from production catalog")
	assert(helmet_visual != null, "Light armor helmet visual is missing from production catalog")
	assert(armor_visual.render_layer == PaperDollLayerVisual.RenderLayer.ARMOR)
	assert(helmet_visual.render_layer == PaperDollLayerVisual.RenderLayer.HELMET)
	assert(_valid_sheet(armor_visual.on_foot_unisex), "Light armor on-foot sheet failed image contract")
	assert(_valid_sheet(armor_visual.mounted_unisex), "Light armor mounted sheet failed image contract")
	assert(_valid_sheet(helmet_visual.on_foot_unisex), "Light helmet on-foot sheet failed image contract")
	assert(_valid_sheet(helmet_visual.mounted_unisex), "Light helmet mounted sheet failed image contract")

	var armor_recipe: Resource = catalog.crafting_recipe_for(LIGHT_ARMOR_ID)
	var helmet_recipe: Resource = catalog.crafting_recipe_for(LIGHT_HELMET_ID)
	assert(armor_recipe != null, "Light armor crafting recipe is missing")
	assert(helmet_recipe != null, "Light helmet crafting recipe is missing")
	assert(armor_recipe.call("can_craft", {"forest": 6, "grass": 4, "iron_ore": 2}))
	assert(not armor_recipe.call("can_craft", {"forest": 5, "grass": 4, "iron_ore": 2}))
	assert(helmet_recipe.call("can_craft", {"forest": 2, "grass": 1, "iron_ore": 2}))
	assert(not helmet_recipe.call("can_craft", {"forest": 2, "grass": 0, "iron_ore": 2}))

	_select_option(_creator.armor_option, LIGHT_ARMOR_ID)
	_select_option(_creator.helmet_option, LIGHT_HELMET_ID)
	await _settle()
	assert(_creator.preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.ARMOR) == LIGHT_ARMOR_ID)
	assert(_creator.preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.HELMET) == LIGHT_HELMET_ID)
	assert(_creator.current_recipe != null, "On-foot light armor recipe did not resolve")
	assert(_creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.ARMOR).texture != null)
	assert(_creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.HELMET).texture != null)
	assert(_creator.crafting_label.text.find("Light armor:") >= 0)
	assert(_creator.crafting_label.text.find("Light armor helmet:") >= 0)
	# Armor and helmet remain independently removable/reselectable; this guards
	# against a selector that only works when both generated layers are present.
	_select_option(_creator.helmet_option, &"")
	await _settle()
	assert(_creator.preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.HELMET).is_empty())
	assert(not _creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.HELMET).visible)
	_select_option(_creator.helmet_option, LIGHT_HELMET_ID)
	await _settle()
	_select_option(_creator.armor_option, &"")
	await _settle()
	assert(_creator.preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.ARMOR).is_empty())
	assert(not _creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.ARMOR).visible)
	_select_option(_creator.armor_option, LIGHT_ARMOR_ID)
	await _settle()
	_creator.current_facing = PaperDollLayerVisual.Facing.DOWN
	_creator.current_frame_x = 0
	_creator._refresh_frame()
	await _settle()
	_save("light_armor_on_foot_down.png")
	_creator.current_facing = PaperDollLayerVisual.Facing.RIGHT
	_creator._refresh_frame()
	await _settle()
	_save("light_armor_on_foot_right.png")

	_creator.mounted_toggle.set_pressed_no_signal(true)
	_creator.mounted_toggle.toggled.emit(true)
	await _settle()
	assert(_creator.preview_draft.is_mounted, "Mounted toggle did not update the draft")
	assert(_creator.preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.ARMOR) == LIGHT_ARMOR_ID)
	assert(_creator.preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.HELMET) == LIGHT_HELMET_ID)
	assert(_creator.current_recipe != null, "Mounted light armor recipe did not resolve")
	assert(_creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.ARMOR).texture != null)
	assert(_creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.HELMET).texture != null)
	_creator.current_facing = PaperDollLayerVisual.Facing.DOWN
	_creator.current_frame_x = 0
	_creator._refresh_frame()
	await _settle()
	_save("light_armor_mounted_down.png")
	_creator.current_facing = PaperDollLayerVisual.Facing.RIGHT
	_creator._refresh_frame()
	await _settle()
	_save("light_armor_mounted_right.png")

	var report := {
		"catalog": "production PaperDollCatalog.create_art_gate1_catalog",
		"armor_visual": str(LIGHT_ARMOR_ID),
		"helmet_visual": str(LIGHT_HELMET_ID),
		"armor_option_visible": _find_option(_creator.armor_option, LIGHT_ARMOR_ID) >= 0,
		"helmet_option_visible": _find_option(_creator.helmet_option, LIGHT_HELMET_ID) >= 0,
		"armor_recipe": armor_recipe.call("requirements_text"),
		"helmet_recipe": helmet_recipe.call("requirements_text"),
		"on_foot_preview": "PASS",
		"mounted_preview": "PASS",
		"crafting_queries": "PASS",
		"captures": [
			"light_armor_on_foot_down.png",
			"light_armor_on_foot_right.png",
			"light_armor_mounted_down.png",
			"light_armor_mounted_right.png",
		],
	}
	var report_path := ProjectSettings.globalize_path(OUTPUT_DIR).path_join("report.json")
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	assert(file != null, "Could not write light armor report")
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("LIGHT_ARMOR_LAB_PASS armor=light_armor helmet=light_armor_helmet mounted=PASS")
	_creator.close()
	_creator.queue_free()
	quit()

func _valid_sheet(texture: Texture2D) -> bool:
	if texture == null or texture.get_size() != Vector2(PaperDollLayerVisual.SHEET_SIZE):
		return false
	var image := texture.get_image()
	if image == null or image.is_empty():
		return false
	if image.get_pixel(0, 0).a > 0.0 or image.get_pixel(511, 191).a > 0.0:
		return false
	for row: int in range(PaperDollLayerVisual.SOURCE_ROWS):
		var found := false
		for y: int in range(row * 64, (row + 1) * 64):
			for x: int in range(512):
				if image.get_pixel(x, y).a > 0.0:
					found = true
					break
			if found:
				break
		if not found:
			return false
	return true

func _select_option(option: OptionButton, visual_id: StringName) -> void:
	var index := _find_option(option, visual_id)
	assert(index >= 0, "Option missing: %s" % visual_id)
	option.select(index)
	option.item_selected.emit(index)

func _find_option(option: OptionButton, visual_id: StringName) -> int:
	for index: int in range(option.item_count):
		if StringName(str(option.get_item_metadata(index))) == visual_id:
			return index
	return -1

func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func _save(file_name: String) -> void:
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR).path_join(file_name)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var image := get_root().get_texture().get_image()
	assert(image != null and not image.is_empty(), "Empty GPU capture: %s" % file_name)
	assert(image.save_png(output_path) == OK, "Could not save GPU capture: %s" % file_name)
