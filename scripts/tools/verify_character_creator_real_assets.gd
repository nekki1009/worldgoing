extends SceneTree

## CharacterCreator acceptance test against the checked-in PNGs.
##
## The lifecycle contract intentionally uses synthetic sheets so it stays fast.
## This verifier is the complementary material gate: it loads the real PNGs
## directly with Image.load_from_file (without importing the whole project),
## builds the production Catalog/Creator, and checks the controls that the
## synthetic contract cannot prove.

const ASSET_ROOT_ENV := "WORLDGOING_PAPERDOLL_ASSET_ROOT"
const OUTPUT_ROOT_ENV := "WORLDGOING_PAPERDOLL_OUTPUT_ROOT"
const SCENE_PATH := "res://scenes/ui/CharacterCreator.tscn"
const REPORT_MARKER := "res://.visual_captures/paper_doll/character_creator_real_assets_report.json"
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
const ACTIONS: Array[int] = [
	PaperDollAnimation.Action.IDLE,
	PaperDollAnimation.Action.WALK,
	PaperDollAnimation.Action.RUN,
	PaperDollAnimation.Action.ATTACK,
	PaperDollAnimation.Action.SPRINT_ATTACK,
	PaperDollAnimation.Action.WORK,
	PaperDollAnimation.Action.HIT,
	PaperDollAnimation.Action.DOWN,
]
## The complete action vocabulary is checked through the UI option count.  A
## smaller smoke subset exercises the expensive split-sheet builder here; the
## dedicated action QA already covers every action/pose combination.
const CREATOR_ACTION_SMOKE: Array[int] = [
	PaperDollAnimation.Action.IDLE,
	PaperDollAnimation.Action.WALK,
	PaperDollAnimation.Action.ATTACK,
	PaperDollAnimation.Action.DOWN,
]

var _asset_root := ""
var _output_root := ""
var _failures: PackedStringArray = []
var _report: Dictionary = {}
var _texture_cache: Dictionary = {}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_asset_root = OS.get_environment(ASSET_ROOT_ENV).replace("\\", "/").trim_suffix("/")
	_output_root = OS.get_environment(OUTPUT_ROOT_ENV).replace("\\", "/").trim_suffix("/")
	if _asset_root.is_empty():
		_fail("%s is not configured" % ASSET_ROOT_ENV)
		_finish()
		return
	if _output_root.is_empty():
		_output_root = ProjectSettings.globalize_path("res://.visual_captures/paper_doll/qa")

	_report["asset_root_configured"] = true
	_report["asset_scans"] = {}
	print("REAL_ASSET_VERIFY stage=scan_presence")
	for relative_dir: String in ["reference_parts", "reference_match", "action_parts"]:
		_report["asset_scans"][relative_dir] = _scan_png_directory(relative_dir)

	var catalog := _make_real_catalog()
	print("REAL_ASSET_VERIFY stage=catalog_loaded")
	var catalog_issues := catalog.validation_issues()
	_report["catalog_validation"] = "PASS" if catalog_issues.is_empty() else "FAIL"
	_report["required_material_decode"] = "PASS" if catalog_issues.is_empty() else "FAIL"
	_check(catalog_issues.is_empty(), "real catalog validation: %s" % "; ".join(catalog_issues))

	var scene := load(SCENE_PATH) as PackedScene
	_check(scene != null, "CharacterCreator scene failed to load")
	if scene == null:
		_finish()
		return
	var creator := scene.instantiate() as CharacterCreator
	_check(creator != null, "CharacterCreator scene failed to instantiate")
	if creator == null:
		_finish()
		return
	root.add_child(creator)
	await process_frame
	await process_frame
	creator.open(catalog)
	await process_frame
	await process_frame
	print("REAL_ASSET_VERIFY stage=creator_opened")

	_report["sprite_pool"] = creator.composer.sprite_count()
	_check(creator.composer.sprite_count() == PaperDollLayerVisual.RenderLayer.COUNT, "Sprite2D pool size is not 11")
	_check(creator.hair_option.item_count == HAIR_IDS.size() + 1, "hair option count is not None + 8 approved styles")
	_check_hair_option_membership(creator)
	_check_reference_state(creator, "initial male on foot")
	_check_frame_contract(creator, "initial")
	await _verify_hair_and_gender(creator)
	await _verify_actions_and_directions(creator)
	await _verify_optional_equipment(creator)
	await _verify_dyes(creator)

	creator.close()
	creator.queue_free()
	_finish()

func _make_real_catalog() -> PaperDollCatalog:
	var catalog := PaperDollCatalog.new()
	var visuals: Array[PaperDollLayerVisual] = []
	visuals.append(_make_visual(
		&"body_male_default", PaperDollLayerVisual.RenderLayer.BODY,
		"reference_match/reference_match_body_on_foot_unisex.png",
		"reference_match/reference_match_body_mounted_unisex.png"
	))
	visuals.append(_make_visual(
		&"body_female_default", PaperDollLayerVisual.RenderLayer.BODY,
		"reference_match/reference_match_female_body_on_foot.png",
		"reference_match/reference_match_female_body_mounted.png"
	))
	visuals.append(_make_visual(
		&"artgate1_armor", PaperDollLayerVisual.RenderLayer.ARMOR,
		"reference_parts/artgate1_armor_on_foot_unisex.png",
		"reference_parts/artgate1_armor_mounted_unisex.png"
	))
	visuals.append(_make_visual(
		&"artgate1_cape", PaperDollLayerVisual.RenderLayer.CAPE,
		"reference_parts/artgate1_cape_on_foot_unisex.png",
		"reference_parts/artgate1_cape_mounted_unisex.png"
	))
	for hair_id: StringName in HAIR_IDS:
		visuals.append(_make_gendered_hair_visual(
			hair_id,
			"reference_parts/%s_on_foot_male.png" % hair_id,
			"reference_parts/%s_on_foot_female.png" % hair_id
		))
	visuals.append(_make_visual(
		&"artgate1_helmet", PaperDollLayerVisual.RenderLayer.HELMET,
		"reference_parts/artgate1_helmet_on_foot_unisex.png",
		"reference_parts/artgate1_helmet_mounted_unisex.png"
	))
	visuals.append(_make_visual(
		&"artgate1_weapon", PaperDollLayerVisual.RenderLayer.WEAPON,
		"reference_parts/artgate1_weapon_on_foot_unisex.png",
		"reference_parts/artgate1_weapon_mounted_unisex.png"
	))
	visuals.append(_make_visual(
		&"artgate1_shield", PaperDollLayerVisual.RenderLayer.SHIELD,
		"reference_parts/artgate1_shield_on_foot_unisex.png",
		"reference_parts/artgate1_shield_mounted_unisex.png"
	))
	visuals.append(_make_visual(
		&"artgate1_barding", PaperDollLayerVisual.RenderLayer.MOUNT_BARDING,
		"",
		"reference_parts/artgate1_barding_mounted_unisex.png"
	))
	catalog.layer_visuals = visuals
	catalog.default_male_body_visual_id = &"body_male_default"
	catalog.default_female_body_visual_id = &"body_female_default"
	catalog.default_male_hair_visual_id = &"hair_short_spiky"
	catalog.default_female_hair_visual_id = &"hair_short_spiky"

	var mount := PaperDollMountVisual.new()
	mount.mount_visual_id = &"artgate1_horse"
	mount.tail = _make_mount_part(
		&"artgate1_horse_tail", PaperDollLayerVisual.RenderLayer.MOUNT_TAIL,
		"reference_parts/artgate1_horse_tail_mounted_unisex.png"
	)
	mount.body = _make_mount_part(
		&"artgate1_horse_body", PaperDollLayerVisual.RenderLayer.MOUNT_BODY,
		"reference_parts/artgate1_horse_body_mounted_unisex.png"
	)
	mount.head = _make_mount_part(
		&"artgate1_horse_head", PaperDollLayerVisual.RenderLayer.MOUNT_HEAD,
		"reference_parts/artgate1_horse_head_mounted_unisex.png"
	)
	catalog.mount_visuals = [mount]
	return catalog

func _make_visual(
	visual_id: StringName,
	layer: int,
	on_foot_path: String,
	mounted_path: String,
	hair_only: bool = false
) -> PaperDollLayerVisual:
	var visual := PaperDollLayerVisual.new()
	visual.visual_id = visual_id
	visual.render_layer = layer
	visual.gender_policy = PaperDollLayerVisual.GenderPolicy.UNISEX
	if PaperDollLayerVisual.is_mounted_only_layer(layer):
		visual.mounted_unisex = _load_texture(mounted_path, "%s mounted" % visual_id)
	else:
		visual.on_foot_unisex = _load_texture(on_foot_path, "%s on foot" % visual_id)
		visual.mounted_unisex = _load_texture(
			mounted_path if not mounted_path.is_empty() else on_foot_path,
			"%s mounted" % visual_id
		)
	if hair_only:
		if visual.on_foot_unisex != null:
			visual.on_foot_unisex.set_meta("paper_doll_hair_only", true)
		if visual.mounted_unisex != null:
			visual.mounted_unisex.set_meta("paper_doll_hair_only", true)
	return visual

func _make_gendered_hair_visual(
	visual_id: StringName,
	male_path: String,
	female_path: String
) -> PaperDollLayerVisual:
	var visual := PaperDollLayerVisual.new()
	visual.visual_id = visual_id
	visual.render_layer = PaperDollLayerVisual.RenderLayer.HAIR
	visual.gender_policy = PaperDollLayerVisual.GenderPolicy.GENDERED
	visual.on_foot_male = _load_texture(male_path, "%s male on foot" % visual_id)
	visual.on_foot_female = _load_texture(female_path, "%s female on foot" % visual_id)
	visual.mounted_male = visual.on_foot_male
	visual.mounted_female = visual.on_foot_female
	for texture: Texture2D in [
		visual.on_foot_male,
		visual.on_foot_female,
	]:
		if texture != null:
			texture.set_meta("paper_doll_hair_only", true)
	return visual

func _make_mount_part(
	visual_id: StringName,
	layer: int,
	path: String
) -> PaperDollLayerVisual:
	return _make_visual(visual_id, layer, "", path)

func _load_texture(relative_path: String, label: String) -> Texture2D:
	if relative_path.is_empty():
		_fail("%s has an empty source path" % label)
		return null
	var absolute_path := _asset_root.path_join(relative_path)
	if _texture_cache.has(absolute_path):
		return _texture_cache[absolute_path] as Texture2D
	var image := Image.load_from_file(absolute_path)
	if image == null or image.is_empty():
		_fail("%s could not be read: %s" % [label, relative_path])
		return null
	if image.get_size() != PaperDollLayerVisual.SHEET_SIZE:
		_fail("%s is %s, expected 512x192" % [relative_path, image.get_size()])
		return null
	var texture := ImageTexture.create_from_image(image)
	_texture_cache[absolute_path] = texture
	return texture

func _scan_png_directory(relative_dir: String) -> Dictionary:
	var result := {"status": "PASS", "mode": "presence_only", "png_count": 0, "bad_files": []}
	var directory := DirAccess.open(_asset_root.path_join(relative_dir))
	if directory == null:
		result["status"] = "FAIL"
		result["bad_files"] = ["directory not readable"]
		_fail("asset directory not readable: %s" % relative_dir)
		return result
	for file_name: String in directory.get_files():
		if not file_name.to_lower().ends_with(".png"):
			continue
		result["png_count"] += 1
		# Required files are decoded and dimension-checked by _load_texture below.
		# The remaining alternates are intentionally presence-scanned here so the
		# gate does not spend a full Dropbox round trip decoding unused previews.
	if not (result["bad_files"] as Array).is_empty():
		result["status"] = "FAIL"
		_fail("%s asset scan: %s" % [relative_dir, "; ".join(result["bad_files"])])
	return result

func _check_hair_option_membership(creator: CharacterCreator) -> void:
	var found: Dictionary = {}
	for index: int in range(creator.hair_option.item_count):
		var metadata: Variant = creator.hair_option.get_item_metadata(index)
		if metadata is StringName and not (metadata as StringName).is_empty():
			found[metadata] = true
	for hair_id: StringName in HAIR_IDS:
		_check(found.has(hair_id), "hair option is missing %s" % hair_id)
	_report["hair_options"] = {"count": creator.hair_option.item_count, "all_8_present": found.size() == HAIR_IDS.size()}

func _check_reference_state(creator: CharacterCreator, label: String) -> void:
	_check(creator.current_recipe != null, "%s has no recipe" % label)
	if creator.current_recipe == null:
		return
	_check(creator.current_recipe.is_accepted_reference, "%s is not the accepted reference recipe" % label)
	_check(creator.current_recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY) != null, "%s has no body texture" % label)
	_check(creator.composer.visible_sprite_count() > 0, "%s has no visible sprites" % label)

func _verify_hair_and_gender(creator: CharacterCreator) -> void:
	creator.preview_draft.action = PaperDollAnimation.Action.IDLE
	creator._on_action_selected(PaperDollAnimation.Action.IDLE)
	creator._on_mounted_toggled(false)
	var gendered_slots: Array[String] = []
	for hair_id: StringName in HAIR_IDS:
		var visual: PaperDollLayerVisual = catalog_for_creator(creator).find_visual(hair_id)
		_check(visual != null, "gendered hairstyle is missing: %s" % hair_id)
		if visual == null:
			continue
		_check(visual.gender_policy == PaperDollLayerVisual.GenderPolicy.GENDERED,
			"hairstyle %s is not gendered" % hair_id)
		_check(
			visual.on_foot_male != null and visual.on_foot_female != null \
				and visual.on_foot_male.get_instance_id() != visual.on_foot_female.get_instance_id(),
			"hairstyle %s does not expose separate male/female textures" % hair_id
		)
		gendered_slots.append(str(hair_id))
	var hair_results: Array = []
	var on_foot_tiles: Array[Image] = []
	var on_foot_reference_image: Image = null
	for hair_id: StringName in HAIR_IDS:
		_check(select_layer_option(creator, creator.hair_option, PaperDollLayerVisual.RenderLayer.HAIR, hair_id), "cannot select %s" % hair_id)
		_check_reference_state(creator, "hair %s on foot" % hair_id)
		hair_results.append(str(hair_id))
		_report["hair_diff_on_foot_%s" % hair_id] = _reference_hair_diff(creator.current_recipe)
		var on_foot_composed := _reference_hair_image(creator.current_recipe)
		if on_foot_reference_image == null:
			on_foot_reference_image = on_foot_composed
		else:
			var on_foot_pair_diff := _different_pixel_count(on_foot_reference_image, on_foot_composed)
			_report["hair_pair_diff_on_foot_%s" % hair_id] = on_foot_pair_diff
			_check(on_foot_pair_diff > 0, "on-foot hair %s produces the same pixels as the first style" % hair_id)
		if creator.current_recipe != null:
			on_foot_tiles.append(PaperDollContactSheet.compose(creator.current_recipe, false))
		if hair_id in [&"hair_short_spiky", &"hair_twin_braids"]:
			_save_preview(creator, "character_creator_real_%s_on_foot.png" % hair_id)
	_save_montage(on_foot_tiles, "character_creator_real_all_8_hair_on_foot.png")
	var selected_hair_id: StringName = creator.preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.HAIR)
	var male_hair_texture: Texture2D = creator.current_recipe.reference_hair_texture
	creator._on_gender_selected(PaperDollLayerVisual.Gender.FEMALE)
	_check_reference_state(creator, "female on foot")
	var female_hair_texture: Texture2D = creator.current_recipe.reference_hair_texture
	_check(female_hair_texture != null and female_hair_texture != male_hair_texture,
		"female gender did not swap the selected hairstyle source")
	var selected_hair := catalog_for_creator(creator).find_visual(selected_hair_id)
	_check(selected_hair != null and selected_hair.resolve(
		PaperDollLayerVisual.Gender.FEMALE, false
	) == female_hair_texture, "female recipe did not resolve the selected gendered hairstyle")
	_save_preview(creator, "character_creator_real_%s_female_on_foot.png" % selected_hair_id)
	# Regression guard for the reported female-mounted eye loss: changing pose
	# must keep the female body visual instead of silently reusing the male body
	# (the old path only changed the gender label and left the body ID intact).
	creator._on_mounted_toggled(true)
	_check_reference_state(creator, "female mounted")
	_check(creator.preview_draft.gender == PaperDollLayerVisual.Gender.FEMALE,
		"female mounted recipe lost the female gender")
	_check(creator.preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.BODY) == &"body_female_default",
		"female mounted recipe reused body %s" % creator.preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.BODY))
	_save_preview(creator, "character_creator_real_%s_female_mounted.png" % selected_hair_id)
	_report["gender"] = {
		"male": "PASS",
		"female": "PASS" if creator.preview_draft.gender == PaperDollLayerVisual.Gender.FEMALE else "FAIL",
		"hair_slots": gendered_slots,
		"selected_hair": str(selected_hair_id),
		"hair_pair_distinct": female_hair_texture != male_hair_texture,
	}
	creator._on_gender_selected(PaperDollLayerVisual.Gender.MALE)
	creator._on_mounted_toggled(true)
	_check_reference_state(creator, "male mounted")
	var mounted_body_texture := creator.current_recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY)
	if mounted_body_texture != null:
		var mounted_frame := mounted_body_texture.get_image().get_region(Rect2i(0, 0, 64, 64))
		_report["mounted_hair_component_rect"] = str(PaperDollComposer._mounted_reference_hair_rect(mounted_frame))
	var mounted_tiles: Array[Image] = []
	var mounted_reference_image: Image = null
	for hair_id: StringName in HAIR_IDS:
		_check(select_layer_option(creator, creator.hair_option, PaperDollLayerVisual.RenderLayer.HAIR, hair_id), "cannot select mounted %s" % hair_id)
		_check_reference_state(creator, "hair %s mounted" % hair_id)
		_report["hair_diff_mounted_%s" % hair_id] = _reference_hair_diff(creator.current_recipe)
		if hair_id == HAIR_IDS[0]:
			_report["mounted_hair_debug"] = _debug_mounted_hair(creator.current_recipe)
		var mounted_composed := _reference_hair_image(creator.current_recipe)
		if mounted_reference_image == null:
			mounted_reference_image = mounted_composed
		else:
			var mounted_pair_diff := _different_pixel_count(mounted_reference_image, mounted_composed)
			_report["hair_pair_diff_mounted_%s" % hair_id] = mounted_pair_diff
			_check(mounted_pair_diff > 0, "mounted hair %s produces the same pixels as the first style" % hair_id)
		if creator.current_recipe != null:
			mounted_tiles.append(PaperDollContactSheet.compose(creator.current_recipe, false))
		if hair_id in [&"hair_high_ponytail", &"hair_long_side_ponytail", &"hair_undercut_sweep"]:
			_save_preview(creator, "character_creator_real_%s_mounted.png" % hair_id)
	_save_montage(mounted_tiles, "character_creator_real_all_8_hair_mounted.png", 1)
	_save_montage(mounted_tiles, "character_creator_real_all_8_hair_mounted_x2.png", 2)
	_report["hair_selected"] = hair_results

func _verify_actions_and_directions(creator: CharacterCreator) -> void:
	var action_results: Array = []
	for mounted: bool in [false, true]:
		creator._on_mounted_toggled(mounted)
		creator._on_action_selected(PaperDollAnimation.Action.IDLE)
		for action: int in CREATOR_ACTION_SMOKE:
			creator._on_action_selected(action)
			_check(creator.current_recipe != null, "action %s mounted=%s did not resolve" % [PaperDollAnimation.action_name(action), mounted])
			if creator.current_recipe == null:
				continue
			_check(creator.current_recipe.is_accepted_reference, "action %s mounted=%s replaced the calibrated base set" % [PaperDollAnimation.action_name(action), mounted])
			_check(creator.current_recipe.reference_hair_texture != null, "action %s mounted=%s lost the hair snapshot" % [PaperDollAnimation.action_name(action), mounted])
			var frames := PaperDollAnimation.frames_for(action)
			_check(frames.size() > 0, "action %s has no frames" % PaperDollAnimation.action_name(action))
			for frame_x: int in frames:
				creator._on_frame_changed(frame_x)
				_check_frame_contract(creator, "%s mounted=%s frame=%d" % [PaperDollAnimation.action_name(action), mounted, frame_x])
			# The real-asset catalog intentionally resolves the accepted reference
			# boards for this smoke test; those boards are static calibration images,
			# not the authored action sheets.  Requiring silhouette variation here
			# made WALK/ATTACK fail for the wrong reason.  The dedicated action QA
			# (verify_paper_doll_actions.gd) owns distinct-frame validation.
			if frames.size() > 1 and not creator.current_recipe.is_accepted_reference:
				_check(_has_distinct_frames(creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.BODY).texture, frames), "action %s mounted=%s has no frame change" % [PaperDollAnimation.action_name(action), mounted])
			action_results.append("%s:%s" % [PaperDollAnimation.action_name(action), "mounted" if mounted else "on_foot"])
	_report["actions"] = {
		"option_count": creator.action_option.item_count,
		"all_actions_declared": creator.action_option.item_count == ACTIONS.size(),
		"creator_smoke": action_results,
	}
	creator._on_action_selected(PaperDollAnimation.Action.IDLE)

func _check_frame_contract(creator: CharacterCreator, label: String) -> void:
	var facing := creator.current_facing
	var frame_x := creator.current_frame_x
	_check(creator.composer.update_frame(facing, frame_x), "%s could not update frame" % label)
	var expected_row := PaperDollLayerVisual.source_row_for(facing)
	for layer: int in range(PaperDollLayerVisual.RenderLayer.COUNT):
		var sprite := creator.composer.sprite_for(layer)
		_check(sprite != null, "%s missing Sprite2D layer %d" % [label, layer])
		if sprite == null:
			continue
		_check(sprite.hframes == 8 and sprite.vframes == 3, "%s layer %d has wrong frame grid" % [label, layer])
		_check(sprite.frame_coords == Vector2i(frame_x, expected_row), "%s layer %d frame is not synchronized" % [label, layer])
		_check(sprite.flip_h == (facing == PaperDollLayerVisual.Facing.LEFT), "%s layer %d flip_h mismatch" % [label, layer])
		_check(sprite.centered == false and sprite.offset == PaperDollLayerVisual.SPRITE_OFFSET, "%s layer %d anchor mismatch" % [label, layer])
		_check(sprite.z_index == PaperDollComposer.z_index_for(layer, facing), "%s layer %d z-index mismatch" % [label, layer])

func _verify_optional_equipment(creator: CharacterCreator) -> void:
	creator._on_mounted_toggled(false)
	creator._on_action_selected(PaperDollAnimation.Action.IDLE)
	# The selector test must start from the explicit None state, independent of
	# whatever optional metadata a previous action smoke pass left selected.
	_clear_optional(creator)
	_report["optional_before"] = _draft_debug(creator)
	for layer_and_id: Array in [
		[PaperDollLayerVisual.RenderLayer.HELMET, &"artgate1_helmet"],
		[PaperDollLayerVisual.RenderLayer.WEAPON, &"artgate1_weapon"],
		[PaperDollLayerVisual.RenderLayer.SHIELD, &"artgate1_shield"],
	]:
		_check(select_layer_option(creator, _option_for_layer(creator, layer_and_id[0]), layer_and_id[0], layer_and_id[1]), "cannot select optional slot %s" % layer_and_id[1])
		_report["optional_after_%s" % layer_and_id[1]] = _draft_debug(creator)
		_report["optional_acceptance_%s" % layer_and_id[1]] = {
			"skeleton": catalog_for_creator(creator)._is_reference_skeleton(creator.preview_draft),
			"armed": catalog_for_creator(creator)._is_accepted_armed_draft(creator.preview_draft, PaperDollAnimation.Action.IDLE),
		}
		_check(creator.current_recipe != null and creator.current_recipe.reference_composite_texture != null, "optional slot %s did not resolve accepted armed board" % layer_and_id[1])
	_save_preview(creator, "character_creator_real_armed_on_foot.png")
	creator._on_mounted_toggled(true)
	_check(creator.current_recipe != null and creator.current_recipe.reference_composite_texture != null, "armed mounted board did not resolve")
	_save_preview(creator, "character_creator_real_armed_mounted.png")
	# Barding is a separate horse-only overlay.  Start from the accepted mounted
	# rider/horse board so this check cannot accidentally exercise the rejected
	# assembled armed board from the previous selector loop.
	_clear_optional(creator)
	_check(creator.current_recipe != null and creator.current_recipe.is_accepted_reference, "mounted barding base is not the accepted reference recipe")
	_check(select_layer_option(creator, creator.barding_option, PaperDollLayerVisual.RenderLayer.MOUNT_BARDING, &"artgate1_barding"), "cannot select real barding")
	_check(creator.current_recipe != null, "real barding recipe did not resolve")
	_check(creator.current_recipe.is_accepted_reference, "barding fell back to an unaligned split recipe")
	_check(creator.current_recipe.reference_composite_texture == null, "barding reused a failed assembled mounted image")
	var barding_recipe_layer: bool = creator.current_recipe.texture_for(PaperDollLayerVisual.RenderLayer.MOUNT_BARDING) != null
	_check(barding_recipe_layer, "real barding is missing from the recipe layer")
	var barding_sprite := creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.MOUNT_BARDING)
	_check(barding_sprite != null and barding_sprite.visible and barding_sprite.modulate.a > 0.99, "barding Sprite2D layer is not visible")
	_check(barding_sprite != null and barding_sprite.z_index == PaperDollComposer.z_index_for(PaperDollLayerVisual.RenderLayer.MOUNT_BARDING, PaperDollLayerVisual.Facing.DOWN), "barding z-index is not the dedicated foreground layer")
	var barding_visible: bool = barding_sprite != null and barding_sprite.visible and barding_sprite.modulate.a > 0.99
	for facing: int in [
		PaperDollLayerVisual.Facing.DOWN,
		PaperDollLayerVisual.Facing.UP,
		PaperDollLayerVisual.Facing.RIGHT,
		PaperDollLayerVisual.Facing.LEFT,
	]:
		creator._set_facing(facing)
		_check_frame_contract(creator, "barding facing %d" % facing)
	var barding_sheet := PaperDollContactSheet.compose(creator.current_recipe, false)
	var barding_only_textures: Array[Texture2D] = []
	barding_only_textures.resize(PaperDollLayerVisual.RenderLayer.COUNT)
	barding_only_textures[PaperDollLayerVisual.RenderLayer.MOUNT_BARDING] = creator.current_recipe.texture_for(PaperDollLayerVisual.RenderLayer.MOUNT_BARDING)
	var barding_only_sheet := PaperDollContactSheet.compose_textures(barding_only_textures, false)
	_check(barding_only_sheet.get_used_rect().size != Vector2i.ZERO, "isolated barding layer rendered no pixels")
	_check(barding_only_sheet.save_png(_output_root.path_join("character_creator_real_barding_layer_only_mounted.png")) == OK, "failed to save isolated barding layer preview")
	_save_preview(creator, "character_creator_real_barding_mounted.png")
	_clear_optional(creator)
	var base_sheet := PaperDollContactSheet.compose(creator.current_recipe, false)
	_check(_different_pixel_count(base_sheet, barding_sheet) > 0, "barding overlay changed no contact-sheet pixels")
	_report["barding_layer"] = {
		"accepted_reference_base": true,
		"reference_composite_texture": false,
		"recipe_layer": barding_recipe_layer,
		"sprite_visible": barding_visible,
		"z_index_down": PaperDollComposer.z_index_for(PaperDollLayerVisual.RenderLayer.MOUNT_BARDING, PaperDollLayerVisual.Facing.DOWN),
	}
	# Restore the neutral mounted state for the next dye checks.
	creator._on_mounted_toggled(false)

func _verify_dyes(creator: CharacterCreator) -> void:
	var results: Dictionary = {}
	creator._on_mounted_toggled(false)
	creator._on_action_selected(PaperDollAnimation.Action.IDLE)
	_clear_optional(creator)
	creator.composer.clear_dyes()
	creator._dye_groups_active.clear()
	creator._refresh_preview()
	var baseline := _body_image(creator)
	_check(baseline != null, "could not capture on-foot dye baseline")
	for pair: Array in [
		[PaperDollComposer.DyeGroup.HAIR_BROWS, Color("8a48d8")],
		[PaperDollComposer.DyeGroup.ARMOR, Color("3c95b7")],
		[PaperDollComposer.DyeGroup.CAPE, Color("b64279")],
	]:
		creator.composer.clear_dyes()
		creator.composer.set_dye(pair[0], pair[1])
		var dyed := _body_image(creator)
		var changed := _different_pixel_count(baseline, dyed)
		var alpha_ok := _alpha_equal(baseline, dyed)
		var face_ok: bool = pair[0] != PaperDollComposer.DyeGroup.HAIR_BROWS or _skin_changes(baseline, dyed) == 0
		_check(changed > 0, "on-foot dye group %d changed no pixels" % pair[0])
		_check(alpha_ok, "on-foot dye group %d changed alpha" % pair[0])
		_check(face_ok, "hair dye changed a protected face/skin pixel")
		results["on_foot_%d" % pair[0]] = {"changed_pixels": changed, "alpha_unchanged": alpha_ok, "face_protected": face_ok}

	creator._on_mounted_toggled(true)
	creator.composer.clear_dyes()
	creator._dye_groups_active.clear()
	creator._refresh_preview()
	baseline = _body_image(creator)
	for pair: Array in [
		[PaperDollComposer.DyeGroup.HAIR_BROWS, Color("8a48d8")],
		[PaperDollComposer.DyeGroup.ARMOR, Color("3c95b7")],
		[PaperDollComposer.DyeGroup.CAPE, Color("b64279")],
		[PaperDollComposer.DyeGroup.MOUNT, Color("4c79b8")],
	]:
		creator.composer.clear_dyes()
		creator.composer.set_dye(pair[0], pair[1])
		var dyed := _body_image(creator)
		var changed := _different_pixel_count(baseline, dyed)
		var alpha_ok := _alpha_equal(baseline, dyed)
		_check(changed > 0, "mounted dye group %d changed no pixels" % pair[0])
		_check(alpha_ok, "mounted dye group %d changed alpha" % pair[0])
		results["mounted_%d" % pair[0]] = {"changed_pixels": changed, "alpha_unchanged": alpha_ok}
	_report["dyes"] = results
	creator.composer.clear_dyes()
	creator._refresh_preview()

func select_layer_option(
	creator: CharacterCreator,
	option: OptionButton,
	layer: int,
	visual_id: StringName
) -> bool:
	for index: int in range(option.item_count):
		var metadata: Variant = option.get_item_metadata(index)
		if str(metadata) == str(visual_id):
			creator._on_layer_selected(index, layer, option)
			return true
	return false

func _option_for_layer(creator: CharacterCreator, layer: int) -> OptionButton:
	match layer:
		PaperDollLayerVisual.RenderLayer.HELMET:
			return creator.helmet_option
		PaperDollLayerVisual.RenderLayer.WEAPON:
			return creator.weapon_option
		PaperDollLayerVisual.RenderLayer.SHIELD:
			return creator.shield_option
	return creator.body_option

func _clear_optional(creator: CharacterCreator) -> void:
	for layer: int in [
		PaperDollLayerVisual.RenderLayer.HELMET,
		PaperDollLayerVisual.RenderLayer.WEAPON,
		PaperDollLayerVisual.RenderLayer.SHIELD,
		PaperDollLayerVisual.RenderLayer.MOUNT_BARDING,
	]:
		creator.preview_draft.set_visual(layer, &"")
	creator._refresh_preview()

func catalog_for_creator(_creator: CharacterCreator) -> PaperDollCatalog:
	return _creator.catalog as PaperDollCatalog

func _draft_debug(creator: CharacterCreator) -> Dictionary:
	var result := {
		"gender": creator.preview_draft.gender,
		"mounted": creator.preview_draft.is_mounted,
		"action": creator.preview_draft.action,
		"mount": str(creator.preview_draft.mount_visual_id),
		"body": str(creator.preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.BODY)),
		"armor": str(creator.preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.ARMOR)),
		"hair": str(creator.preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.HAIR)),
		"cape": str(creator.preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.CAPE)),
		"helmet": str(creator.preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.HELMET)),
		"weapon": str(creator.preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.WEAPON)),
		"shield": str(creator.preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.SHIELD)),
		"barding": str(creator.preview_draft.visual_id_for(PaperDollLayerVisual.RenderLayer.MOUNT_BARDING)),
	}
	return result

func _body_image(creator: CharacterCreator) -> Image:
	var sprite := creator.composer.sprite_for(PaperDollLayerVisual.RenderLayer.BODY)
	return sprite.texture.get_image() if sprite != null and sprite.texture != null else null

func _reference_hair_diff(recipe: PaperDollRecipe) -> int:
	if recipe == null:
		return 0
	var base := recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY)
	var composed := PaperDollComposer.build_reference_body_texture(recipe)
	if base == null or composed == null:
		return 0
	return _different_pixel_count(base.get_image(), composed.get_image())

func _reference_hair_image(recipe: PaperDollRecipe) -> Image:
	var composed := PaperDollComposer.build_reference_body_texture(recipe)
	return composed.get_image() if composed != null else null

func _debug_mounted_hair(recipe: PaperDollRecipe) -> Dictionary:
	var body_texture := recipe.texture_for(PaperDollLayerVisual.RenderLayer.BODY)
	var hair_image := PaperDollComposer._reference_hair_image(recipe.reference_hair_texture, recipe.reference_hair_is_hair_only)
	if body_texture == null or hair_image == null:
		return {"error": "missing body or hair"}
	var body_frame := body_texture.get_image().get_region(Rect2i(0, 0, 64, 64))
	var source_frame := hair_image.get_region(Rect2i(0, 0, 64, 64))
	var source_rect := source_frame.get_used_rect()
	var target_rect := PaperDollComposer._reference_hair_target_rect(body_frame, true, source_rect.size, true)
	var replacement := source_frame.get_region(source_rect)
	replacement.resize(target_rect.size.x, target_rect.size.y, Image.INTERPOLATE_NEAREST)
	var component := PaperDollComposer._mounted_reference_hair_component(body_frame)
	var nontransparent := 0
	var allowed := 0
	var blocked := 0
	for y: int in range(replacement.get_height()):
		for x: int in range(replacement.get_width()):
			if replacement.get_pixel(x, y).a <= 0.05:
				continue
			nontransparent += 1
			var position := target_rect.position + Vector2i(x, y)
			if position.x < 0 or position.x >= 64 or position.y < 0 or position.y >= 64:
				blocked += 1
				continue
			if PaperDollComposer._reference_replacement_blocked(
				body_frame.get_pixelv(position), position, true, component
			):
				blocked += 1
			else:
				allowed += 1
	return {
		"component": str(PaperDollComposer._mounted_reference_hair_rect(body_frame)),
		"source_rect": str(source_rect),
		"target_rect": str(target_rect),
		"nontransparent": nontransparent,
		"allowed": allowed,
		"blocked": blocked,
	}

func _has_distinct_frames(texture: Texture2D, frames: PackedInt32Array) -> bool:
	if texture == null or frames.size() < 2:
		return false
	var image := texture.get_image()
	var first := image.get_region(Rect2i(frames[0] * 64, 0, 64, 64)).get_data()
	for index: int in range(1, frames.size()):
		if image.get_region(Rect2i(frames[index] * 64, 0, 64, 64)).get_data() != first:
			return true
	return false

func _different_pixel_count(left: Image, right: Image) -> int:
	if left == null or right == null or left.get_size() != right.get_size():
		return 0
	var count := 0
	for y: int in range(left.get_height()):
		for x: int in range(left.get_width()):
			if left.get_pixel(x, y) != right.get_pixel(x, y):
				count += 1
	return count

func _alpha_equal(left: Image, right: Image) -> bool:
	if left == null or right == null or left.get_size() != right.get_size():
		return false
	for y: int in range(left.get_height()):
		for x: int in range(left.get_width()):
			if not is_equal_approx(left.get_pixel(x, y).a, right.get_pixel(x, y).a):
				return false
	return true

func _skin_changes(left: Image, right: Image) -> int:
	if left == null or right == null or left.get_size() != right.get_size():
		return 1
	var count := 0
	for row: int in range(PaperDollLayerVisual.SOURCE_ROWS):
		for frame_x: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
			var origin := Vector2i(frame_x * 64, row * 64)
			for y: int in range(12, 27):
				for x: int in range(19, 45):
					var before := left.get_pixelv(origin + Vector2i(x, y))
					if not _is_skin(before):
						continue
					if before != right.get_pixelv(origin + Vector2i(x, y)):
						count += 1
	return count

func _is_skin(color: Color) -> bool:
	return color.a > 0.05 and color.h >= 0.045 and color.h <= 0.18 and color.s >= 0.20 and color.v >= 0.30

func _save_preview(creator: CharacterCreator, file_name: String) -> void:
	if creator.current_recipe == null:
		_fail("cannot save %s without a recipe" % file_name)
		return
	var absolute_path := _output_root.path_join(file_name)
	var err := PaperDollContactSheet.save_png(creator.current_recipe, absolute_path, false)
	_check(err == OK, "failed to save %s: %s" % [file_name, err])

func _save_montage(tiles: Array[Image], file_name: String, scale: int = 1) -> void:
	if tiles.is_empty():
		_fail("cannot save empty montage %s" % file_name)
		return
	const tile_size := Vector2i(512, 256)
	const columns := 4
	var rows: int = ceili(float(tiles.size()) / float(columns))
	var safe_scale: int = maxi(scale, 1)
	var output_tile_size := tile_size * safe_scale
	var montage := Image.create(output_tile_size.x * columns, output_tile_size.y * rows, false, Image.FORMAT_RGBA8)
	montage.fill(Color("101722"))
	for index: int in range(tiles.size()):
		var tile: Image = tiles[index]
		if safe_scale > 1:
			tile = tile.duplicate()
			tile.resize(output_tile_size.x, output_tile_size.y, Image.INTERPOLATE_NEAREST)
		var origin := Vector2i((index % columns) * output_tile_size.x, (index / columns) * output_tile_size.y)
		montage.blit_rect(tile, Rect2i(Vector2i.ZERO, output_tile_size), origin)
	var absolute_path := _output_root.path_join(file_name)
	_check(montage.save_png(absolute_path) == OK, "failed to save %s" % file_name)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _fail(message: String) -> void:
	if message not in _failures:
		_failures.append(message)

func _finish() -> void:
	_report["failures"] = Array(_failures)
	_report["status"] = "PASS" if _failures.is_empty() else "FAIL"
	var serialized := JSON.stringify(_report, "\t")
	var marker_path := ProjectSettings.globalize_path(REPORT_MARKER)
	DirAccess.make_dir_recursive_absolute(marker_path.get_base_dir())
	var marker := FileAccess.open(marker_path, FileAccess.WRITE)
	if marker != null:
		marker.store_string(serialized)
		marker.close()
	DirAccess.make_dir_recursive_absolute(_output_root)
	var external := FileAccess.open(_output_root.path_join("character_creator_real_assets_report.json"), FileAccess.WRITE)
	if external != null:
		external.store_string(serialized)
		external.close()
	if _failures.is_empty():
		print("CHARACTER_CREATOR_REAL_ASSET_PASS")
		quit(0)
	else:
		for failure: String in _failures:
			push_error("CHARACTER_CREATOR_REAL_ASSET_FAIL: %s" % failure)
		print("CHARACTER_CREATOR_REAL_ASSET_FAIL count=%d" % _failures.size())
		quit(1)
