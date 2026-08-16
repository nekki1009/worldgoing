extends SceneTree

## Small-project GPU proof for the gendered hairstyle contract.  It uses the
## production CharacterCreator/Composer scene, but a deliberately tiny
## catalog so Dropbox's unrelated project files cannot mask this feature.

const HAIR_IDS: Array[StringName] = [
	&"hair_short_spiky",
	&"hair_high_ponytail",
	&"hair_bob",
	&"hair_twin_braids",
	&"hair_long_side_ponytail",
	&"hair_crown_braid",
	&"hair_low_bun",
	&"hair_undercut_sweep",
]
const OUTPUT_DIR := "res://.visual_captures/gendered_hair_lab"

var _creator: CharacterCreator
var _male_sources: Dictionary = {}
var _female_sources: Dictionary = {}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://scenes/ui/CharacterCreator.tscn") as PackedScene
	assert(scene != null, "CharacterCreator scene failed to load")
	_creator = scene.instantiate() as CharacterCreator
	assert(_creator != null, "CharacterCreator scene failed to instantiate")
	root.add_child(_creator)
	await _settle()

	var catalog := _make_probe_catalog()
	var catalog_issues := catalog.validation_issues()
	assert(catalog_issues.is_empty(), "Probe catalog is invalid: %s" % "; ".join(catalog_issues))
	_creator.open(catalog)
	await _settle()
	assert(_creator.hair_option.item_count == HAIR_IDS.size() + 1,
		"Asset Lab does not expose None + eight hairstyles")
	assert(_creator.preview_draft != null and not _creator.preview_draft.is_mounted)

	for gender: int in [PaperDollLayerVisual.Gender.MALE, PaperDollLayerVisual.Gender.FEMALE]:
		_creator.gender_option.select(gender)
		_creator.gender_option.item_selected.emit(gender)
		await _settle()
		assert(_creator.preview_draft.gender == gender,
			"GenderOption signal did not update the draft")
		for hair_id: StringName in HAIR_IDS:
			var index := _find_hair_option(hair_id)
			assert(index >= 0, "Hair option is missing %s" % hair_id)
			_creator.hair_option.select(index)
			_creator.hair_option.item_selected.emit(index)
			await _settle()
			assert(_creator.preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.HAIR) == hair_id,
				"Hair selection changed unexpectedly for %s" % hair_id)
			assert(_creator.current_recipe != null and _creator.current_recipe.reference_hair_texture != null,
				"No resolved hair source for %s/%s" % [PaperDollLayerVisual.gender_name(gender), hair_id])
			var source: Texture2D = _creator.current_recipe.reference_hair_texture
			if gender == PaperDollLayerVisual.Gender.MALE:
				_male_sources[hair_id] = source
			else:
				_female_sources[hair_id] = source
			_save("%s_%s.png" % [PaperDollLayerVisual.gender_name(gender), hair_id])
			if gender == PaperDollLayerVisual.Gender.FEMALE and hair_id in [
				&"hair_twin_braids", &"hair_long_side_ponytail", &"hair_low_bun"
			]:
				var body_texture: Texture2D = _creator.composer.sprite_for(
					PaperDollLayerVisual.RenderLayer.BODY
				).texture
				assert(body_texture != null)
				var body_debug_path := ProjectSettings.globalize_path(OUTPUT_DIR).path_join(
					"female_body_%s.png" % hair_id
				)
				assert(body_texture.get_image().save_png(body_debug_path) == OK)

	for hair_id: StringName in HAIR_IDS:
		var male_source: Texture2D = _male_sources[hair_id]
		var female_source: Texture2D = _female_sources[hair_id]
		assert(male_source.get_instance_id() != female_source.get_instance_id(),
			"Male/female source resources are still shared: %s" % hair_id)
		assert(_count_different_pixels(male_source, female_source) > 0,
			"Male/female files differ only by metadata, not pixels: %s" % hair_id)

	# The same lab control must also resolve the gendered hair while mounted.
	# This catches the common regression where the on-foot selector works but the
	# mounted recipe silently falls back to a unisex/default source.
	_creator.mounted_toggle.set_pressed_no_signal(true)
	_creator.mounted_toggle.toggled.emit(true)
	await _settle()
	assert(_creator.preview_draft.is_mounted, "Mounted toggle did not update draft")
	for gender: int in [PaperDollLayerVisual.Gender.MALE, PaperDollLayerVisual.Gender.FEMALE]:
		_creator.gender_option.select(gender)
		_creator.gender_option.item_selected.emit(gender)
		await _settle()
		for hair_id: StringName in HAIR_IDS:
			var index := _find_hair_option(hair_id)
			_creator.hair_option.select(index)
			_creator.hair_option.item_selected.emit(index)
			await _settle()
			assert(_creator.preview_draft.is_mounted)
			assert(_creator.current_recipe != null
				and _creator.current_recipe.reference_hair_texture != null,
				"Mounted recipe lost gendered hair source for %s/%s" % [
					PaperDollLayerVisual.gender_name(gender), hair_id
				])
			_save("mounted_%s_%s.png" % [PaperDollLayerVisual.gender_name(gender), hair_id])

	var report := {
		"male_styles": _male_sources.size(),
		"female_styles": _female_sources.size(),
		"hair_option_count": _creator.hair_option.item_count,
		"gender_signal": "PASS",
		"male_female_source_pairs_distinct": true,
		"male_female_pixel_pairs_distinct": true,
		"mounted_gendered_styles": 16,
		"mounted_signal": "PASS",
		"preview": "GPU capture",
	}
	var report_path := ProjectSettings.globalize_path(OUTPUT_DIR).path_join("report.json")
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	assert(file != null, "Could not write gendered hair report")
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("GENDERED_HAIR_LAB_PASS styles=8+8 pairs=8")
	_creator.close()
	_creator.queue_free()
	quit()

func _make_probe_catalog() -> PaperDollCatalog:
	var catalog := PaperDollCatalog.new()
	var visuals: Array[PaperDollLayerVisual] = []
	visuals.append(_unisex_visual(
		&"body_male_default", PaperDollLayerVisual.RenderLayer.BODY,
		"reference_match/reference_match_body_on_foot_unisex.png",
		"reference_match/reference_match_body_mounted_unisex.png"
	))
	visuals.append(_unisex_visual(
		&"body_female_default", PaperDollLayerVisual.RenderLayer.BODY,
		"reference_match/reference_match_female_body_on_foot.png",
		"reference_match/reference_match_female_body_mounted.png"
	))
	visuals.append(_unisex_visual(
		&"artgate1_armor", PaperDollLayerVisual.RenderLayer.ARMOR,
		"reference_parts/artgate1_armor_on_foot_unisex.png",
		"reference_parts/artgate1_armor_mounted_unisex.png"
	))
	visuals.append(_unisex_visual(
		&"artgate1_cape", PaperDollLayerVisual.RenderLayer.CAPE,
		"reference_parts/artgate1_cape_on_foot_unisex.png",
		"reference_parts/artgate1_cape_mounted_unisex.png"
	))
	for hair_id: StringName in HAIR_IDS:
		# Exercise the production Catalog resolver rather than a test-only copy
		# of its gender policy.  The surrounding probe catalog stays deliberately
		# small so unrelated project assets cannot affect this test.
		visuals.append(PaperDollCatalog._gendered_hair_visual(hair_id))
	catalog.layer_visuals = visuals
	catalog.default_male_body_visual_id = &"body_male_default"
	catalog.default_female_body_visual_id = &"body_female_default"
	catalog.default_male_hair_visual_id = HAIR_IDS[0]
	catalog.default_female_hair_visual_id = HAIR_IDS[0]

	var mount := PaperDollMountVisual.new()
	mount.mount_visual_id = &"artgate1_horse"
	mount.tail = _mount_part(&"artgate1_horse_tail", PaperDollLayerVisual.RenderLayer.MOUNT_TAIL,
		"reference_parts/artgate1_horse_tail_mounted_unisex.png")
	mount.body = _mount_part(&"artgate1_horse_body", PaperDollLayerVisual.RenderLayer.MOUNT_BODY,
		"reference_parts/artgate1_horse_body_mounted_unisex.png")
	mount.head = _mount_part(&"artgate1_horse_head", PaperDollLayerVisual.RenderLayer.MOUNT_HEAD,
		"reference_parts/artgate1_horse_head_mounted_unisex.png")
	catalog.mount_visuals = [mount]
	return catalog

func _unisex_visual(
	visual_id: StringName,
	layer: int,
	on_foot_path: String,
	mounted_path: String
) -> PaperDollLayerVisual:
	var visual := PaperDollLayerVisual.new()
	visual.visual_id = visual_id
	visual.render_layer = layer
	visual.gender_policy = PaperDollLayerVisual.GenderPolicy.UNISEX
	visual.on_foot_unisex = _load_texture(on_foot_path)
	visual.mounted_unisex = _load_texture(mounted_path)
	return visual

func _mount_part(visual_id: StringName, layer: int, path: String) -> PaperDollLayerVisual:
	return _unisex_visual(visual_id, layer, path, path)

func _load_texture(relative_path: String) -> Texture2D:
	var path := ProjectSettings.globalize_path("res://assets/paper_doll/" + relative_path)
	var image := Image.load_from_file(path)
	assert(image != null and not image.is_empty(), "Missing probe texture: %s" % relative_path)
	return ImageTexture.create_from_image(image)

func _count_different_pixels(first: Texture2D, second: Texture2D) -> int:
	var first_image := first.get_image()
	var second_image := second.get_image()
	assert(first_image.get_size() == second_image.get_size(),
		"Gendered hair sheets have different dimensions")
	var different := 0
	for y: int in range(first_image.get_height()):
		for x: int in range(first_image.get_width()):
			if first_image.get_pixel(x, y) != second_image.get_pixel(x, y):
				different += 1
	return different

func _find_hair_option(hair_id: StringName) -> int:
	for index: int in range(_creator.hair_option.item_count):
		if str(_creator.hair_option.get_item_metadata(index)) == str(hair_id):
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
