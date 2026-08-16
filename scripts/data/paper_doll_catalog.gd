class_name PaperDollCatalog
extends Resource

const REFERENCE_ART_DIR := "res://assets/paper_doll/reference_parts"
const REFERENCE_MATCH_DIR := "res://assets/paper_doll/reference_match"
const ACCEPTED_REFERENCE_ARMED_ON_FOOT := "reference_match_armed_on_foot_unisex.png"
const ACCEPTED_REFERENCE_ARMED_MOUNTED := "reference_match_armed_mounted_unisex.png"
## The authored side-facing horse parts occupy x=0..63 when the three
## independent layers are composed.  Compress only that source row around the
## shared x=32 anchor; front/rear rows retain their calibrated pixels.
const MOUNT_SIDE_HORIZONTAL_SCALE := 0.72
## These are the user-approved material-lab hairstyles.  Each is a
## genuine silhouette from the approved hair-only board; legacy IDs remain in
## the catalog only for old saved drafts and are hidden by CharacterCreator.
const APPROVED_HAIR_IDS := [
	&"hair_short_spiky",
	&"hair_high_ponytail",
	&"hair_bob",
	&"hair_twin_braids",
	&"hair_long_side_ponytail",
	&"hair_crown_braid",
	&"hair_low_bun",
	&"hair_undercut_sweep",
]
const ACTION_ART_DIR := "res://assets/paper_doll/action_parts"
const ACTION_SHEET_SCRIPT = preload("res://scripts/data/paper_doll_action_sheet.gd")
const CRAFTING_RECIPE_SCRIPT = preload("res://scripts/data/paper_doll_crafting_recipe.gd")
# The first generated WALK board is retained for offline QA only.  It passed
# the pixel/size gate but failed the inspected white-hair/silver-armor
# silhouette gate, so it must not enter the runtime Catalog until replaced and
# explicitly approved.
const APPROVED_AUTHORED_ACTIONS := false

@export var layer_visuals: Array[PaperDollLayerVisual] = []
@export var mount_visuals: Array[PaperDollMountVisual] = []
## Presentation-side crafting recipes shown by the Asset Lab.  This is kept
## on the same catalog as the visual IDs so a recipe can never point at an
## unselectable or missing part.  It is intentionally not an inventory owner:
## gameplay resource deduction belongs to the future equipment/economy domain.
@export var crafting_recipes: Array[Resource] = []
@export var default_male_body_visual_id: StringName = &""
@export var default_female_body_visual_id: StringName = &""
@export var default_male_hair_visual_id: StringName = &""
@export var default_female_hair_visual_id: StringName = &""

func find_visual(visual_id: StringName) -> PaperDollLayerVisual:
	for visual: PaperDollLayerVisual in layer_visuals:
		if visual != null and visual.visual_id == visual_id:
			return visual
	return null

func find_mount(mount_visual_id: StringName) -> PaperDollMountVisual:
	for mount: PaperDollMountVisual in mount_visuals:
		if mount != null and mount.mount_visual_id == mount_visual_id:
			return mount
	return null

func visuals_for_layer(layer: int) -> Array[PaperDollLayerVisual]:
	var result: Array[PaperDollLayerVisual] = []
	for visual: PaperDollLayerVisual in layer_visuals:
		if visual != null and visual.render_layer == layer:
			result.append(visual)
	result.sort_custom(_visual_less)
	return result

func sorted_mounts() -> Array[PaperDollMountVisual]:
	var result: Array[PaperDollMountVisual] = mount_visuals.duplicate()
	result.sort_custom(_mount_less)
	return result

func crafting_recipe_for(visual_id: StringName) -> Resource:
	for recipe: Resource in crafting_recipes:
		if recipe != null and StringName(str(recipe.get("output_visual_id"))) == visual_id:
			return recipe
	return null

func crafting_validation_issues() -> PackedStringArray:
	var issues: PackedStringArray = []
	var used_ids: Dictionary = {}
	for recipe: Resource in crafting_recipes:
		if recipe == null:
			issues.append("catalog contains a null crafting recipe")
			continue
		var recipe_id: String = str(recipe.get("recipe_id"))
		if used_ids.has(recipe_id):
			issues.append("%s: duplicate crafting recipe id" % recipe_id)
		else:
			used_ids[recipe_id] = true
		var output_id := StringName(str(recipe.get("output_visual_id")))
		issues.append_array(recipe.call("validation_issues", find_visual(output_id)))
	return issues

func default_visual_id(layer: int, gender: int, is_mounted: bool = false) -> StringName:
	if layer == PaperDollLayerVisual.RenderLayer.BODY:
		return default_male_body_visual_id \
			if gender == PaperDollLayerVisual.Gender.MALE \
			else default_female_body_visual_id
	if layer == PaperDollLayerVisual.RenderLayer.HAIR:
		return default_male_hair_visual_id \
			if gender == PaperDollLayerVisual.Gender.MALE \
			else default_female_hair_visual_id
	# Keep the accepted Art Gate 1 reference as the stable default even when
	# additional generated variants are present.  Variant IDs intentionally use
	# the `alt_` prefix, so a plain lexical sort must never silently replace the
	# reference look in the creator's first frame.
	var candidates: Array[PaperDollLayerVisual] = visuals_for_layer(layer)
	for visual: PaperDollLayerVisual in candidates:
		if not str(visual.visual_id).begins_with("artgate1_"):
			continue
		if visual.resolve(gender, is_mounted) != null:
			return visual.visual_id
	for visual: PaperDollLayerVisual in candidates:
		if visual.resolve(gender, is_mounted) != null:
			return visual.visual_id
	return &""

func validation_issues() -> PackedStringArray:
	var issues: PackedStringArray = []
	var used_ids: Dictionary = {}
	for visual: PaperDollLayerVisual in layer_visuals:
		if visual == null:
			issues.append("catalog contains a null layer visual")
			continue
		_append_duplicate_issue(issues, used_ids, visual.visual_id)
		issues.append_array(visual.validation_issues())
	for mount: PaperDollMountVisual in mount_visuals:
		if mount == null:
			issues.append("catalog contains a null mount visual")
			continue
		_append_duplicate_issue(issues, used_ids, mount.mount_visual_id)
		issues.append_array(mount.validation_issues())
		for part: PaperDollLayerVisual in mount.parts():
			if part != null:
				_append_duplicate_issue(issues, used_ids, part.visual_id)
	issues.append_array(crafting_validation_issues())

	_append_default_issue(
		issues,
		default_male_body_visual_id,
		PaperDollLayerVisual.RenderLayer.BODY,
		PaperDollLayerVisual.Gender.MALE,
		"default male body"
	)
	_append_default_issue(
		issues,
		default_female_body_visual_id,
		PaperDollLayerVisual.RenderLayer.BODY,
		PaperDollLayerVisual.Gender.FEMALE,
		"default female body"
	)
	_append_default_issue(
		issues,
		default_male_hair_visual_id,
		PaperDollLayerVisual.RenderLayer.HAIR,
		PaperDollLayerVisual.Gender.MALE,
		"default male hair"
	)
	_append_default_issue(
		issues,
		default_female_hair_visual_id,
		PaperDollLayerVisual.RenderLayer.HAIR,
		PaperDollLayerVisual.Gender.FEMALE,
		"default female hair"
	)
	return issues

func validate_draft(draft: PaperDollPreviewDraft) -> PackedStringArray:
	var issues: PackedStringArray = []
	if draft == null:
		issues.append("preview draft is null")
		return issues
	if not PaperDollLayerVisual.is_valid_gender(draft.gender):
		issues.append("preview gender is invalid")
		return issues
	if not PaperDollAnimation.is_valid_action(draft.action):
		issues.append("preview action is invalid")

	var body_id: StringName = draft.visual_id_for(PaperDollLayerVisual.RenderLayer.BODY)
	if body_id.is_empty():
		issues.append("preview requires a body visual")
	for layer: int in draft.selected_layers():
		var visual_id: StringName = draft.visual_id_for(layer)
		var visual: PaperDollLayerVisual = find_visual(visual_id)
		if visual == null:
			issues.append("%s: selected visual is not in the catalog" % visual_id)
			continue
		if visual.render_layer != layer:
			issues.append("%s: selected visual uses the wrong layer" % visual_id)
			continue
		if layer == PaperDollLayerVisual.RenderLayer.MOUNT_BARDING and not draft.is_mounted:
			continue
		if visual.resolve(draft.gender, draft.is_mounted) == null:
			issues.append("%s: selected pose/gender texture is missing" % visual_id)

	if draft.is_mounted:
		if draft.mount_visual_id.is_empty():
			issues.append("mounted preview requires a mount visual")
		elif find_mount(draft.mount_visual_id) == null:
			issues.append("%s: selected mount is not in the catalog" % draft.mount_visual_id)
	return issues

func resolve_recipe(
		draft: PaperDollPreviewDraft,
		action: int = -1
	) -> PaperDollRecipe:
	if not validate_draft(draft).is_empty():
		return null
	var resolved_action: int = draft.action if action < 0 else action
	if not PaperDollAnimation.is_valid_action(resolved_action):
		return null
	var result: PaperDollRecipe = PaperDollRecipe.new(draft.is_mounted, resolved_action)
	var accepted_reference_base: bool = _is_accepted_reference_draft(draft, resolved_action)
	result.is_accepted_reference = accepted_reference_base \
		or _is_accepted_armed_draft(draft, resolved_action)
	if result.is_accepted_reference:
		var reference_hair := find_visual(
			draft.visual_id_for(PaperDollLayerVisual.RenderLayer.HAIR)
		)
		if reference_hair != null:
			result.reference_hair_visual_id = draft.visual_id_for(
				PaperDollLayerVisual.RenderLayer.HAIR
			)
			result.reference_hair_texture = reference_hair.resolve(
				draft.gender, draft.is_mounted
			) if accepted_reference_base else reference_hair.resolve_action(
				draft.gender, draft.is_mounted, resolved_action
			)
			result.reference_hair_is_hair_only = is_approved_hair_id(
				draft.visual_id_for(PaperDollLayerVisual.RenderLayer.HAIR)
			)
		if _is_accepted_armed_draft(draft, resolved_action):
			result.reference_composite_texture = _load_reference_match_texture(
				ACCEPTED_REFERENCE_ARMED_MOUNTED
					if draft.is_mounted
					else ACCEPTED_REFERENCE_ARMED_ON_FOOT
			)
	for layer: int in draft.selected_layers():
		if layer == PaperDollLayerVisual.RenderLayer.MOUNT_BARDING and not draft.is_mounted:
			continue
		var visual: PaperDollLayerVisual = find_visual(draft.visual_id_for(layer))
		var texture: Texture2D = visual.resolve_action(
			draft.gender,
			draft.is_mounted,
			resolved_action
		)
		var has_dedicated_sheet: bool = visual.has_action_sheet(draft.is_mounted, resolved_action)
		# The default body Resource also owns the calibrated, complete white-hair /
		# silver-armor reference board for the accepted preset.  That board is not
		# a composable naked body: using it underneath an alternate armor or helmet
		# would render two torsos and two head silhouettes.  Any non-reference
		# recipe must therefore switch this layer back to the authored skin-only
		# body sheet before the normal action-sheet fallback is resolved.
		if layer == PaperDollLayerVisual.RenderLayer.BODY \
				and not accepted_reference_base \
				and draft.visual_id_for(PaperDollLayerVisual.RenderLayer.BODY) in [
					&"body_male_default", &"body_female_default"
				]:
			texture = _load_layered_body_texture(draft.gender, draft.is_mounted)
			has_dedicated_sheet = false
		# Accepted reference actions keep the same calibrated base sheet.  The
		# eight source columns provide the synchronized frame selection; generating
		# a split action sheet here would replace the whole base and put hair back
		# on the legacy 64x64 coordinates.
		if accepted_reference_base and layer == PaperDollLayerVisual.RenderLayer.BODY:
			texture = visual.resolve(draft.gender, draft.is_mounted)
			has_dedicated_sheet = false
		if not (accepted_reference_base and layer == PaperDollLayerVisual.RenderLayer.BODY):
			texture = _resolve_action_texture(
				texture, layer, resolved_action, draft.is_mounted, has_dedicated_sheet
			)
		if layer == PaperDollLayerVisual.RenderLayer.HAIR \
				and is_approved_hair_id(draft.visual_id_for(layer)) \
				and texture != null:
			texture.set_meta("paper_doll_hair_only", true)
		result.set_layer_texture(layer, texture)
	if draft.is_mounted:
		var mount: PaperDollMountVisual = find_mount(draft.mount_visual_id)
		result.set_layer_texture(
			PaperDollLayerVisual.RenderLayer.MOUNT_TAIL,
			_resolve_mount_action_texture(mount.tail, draft.gender, resolved_action, PaperDollLayerVisual.RenderLayer.MOUNT_TAIL)
		)
		result.set_layer_texture(
			PaperDollLayerVisual.RenderLayer.MOUNT_BODY,
			_resolve_mount_action_texture(mount.body, draft.gender, resolved_action, PaperDollLayerVisual.RenderLayer.MOUNT_BODY)
		)
		result.set_layer_texture(
			PaperDollLayerVisual.RenderLayer.MOUNT_HEAD,
			_resolve_mount_action_texture(mount.head, draft.gender, resolved_action, PaperDollLayerVisual.RenderLayer.MOUNT_HEAD)
		)
	return result

func _is_accepted_reference_draft(
		draft: PaperDollPreviewDraft,
		action: int
	) -> bool:
	# The calibrated body sheet is the shared base for every Asset Lab action.
	# Actions select its existing columns; they must not switch to a generated
	# split sheet that uses a different hair/body coordinate system.
	if draft == null or not PaperDollAnimation.is_valid_action(action):
		return false
	if not _is_reference_skeleton(draft):
		return false
	if not _is_empty_optional_slot(draft, PaperDollLayerVisual.RenderLayer.HELMET) \
		or not _is_empty_optional_slot(draft, PaperDollLayerVisual.RenderLayer.SHIELD):
		return false
	# MountBarding is intentionally allowed here.  It is a dedicated horse
	# overlay, not part of the accepted rider/horse board.  Keeping it in the
	# recipe lets the Composer layer the authored barding sheet without falling
	# back to the rejected assembled mounted image.
	if draft.is_mounted and draft.mount_visual_id != &"artgate1_horse":
		return false
	var weapon_id := draft.visual_id_for(PaperDollLayerVisual.RenderLayer.WEAPON)
	return weapon_id.is_empty()

func _is_accepted_armed_draft(
		draft: PaperDollPreviewDraft,
		action: int
	) -> bool:
	if draft == null or action != PaperDollAnimation.Action.IDLE:
		return false
	if not _is_reference_skeleton(draft):
		return false
	var has_reference_equipment: bool = false
	for selection: Array in [
		[PaperDollLayerVisual.RenderLayer.HELMET, &"artgate1_helmet"],
		[PaperDollLayerVisual.RenderLayer.WEAPON, &"artgate1_weapon"],
		[PaperDollLayerVisual.RenderLayer.SHIELD, &"artgate1_shield"],
	]:
		var selected_id: StringName = draft.visual_id_for(selection[0] as int)
		if selected_id.is_empty():
			continue
		# Array literals may widen StringName constants to String when they are
		# stored as Variants.  Normalize explicitly instead of using `as`, which
		# raises an invalid-cast error in Godot 4.6 during armed-preview selection.
		if selected_id != StringName(str(selection[1])):
			return false
		has_reference_equipment = true
	if not has_reference_equipment:
		return false
	if not _is_empty_optional_slot(draft, PaperDollLayerVisual.RenderLayer.MOUNT_BARDING):
		return false
	return not draft.is_mounted or draft.mount_visual_id == &"artgate1_horse"

func _is_reference_skeleton(draft: PaperDollPreviewDraft) -> bool:
	var body_id: StringName = draft.visual_id_for(PaperDollLayerVisual.RenderLayer.BODY)
	var hair_id: StringName = draft.visual_id_for(PaperDollLayerVisual.RenderLayer.HAIR)
	return draft.gender >= PaperDollLayerVisual.Gender.MALE \
		and draft.gender <= PaperDollLayerVisual.Gender.FEMALE \
		and body_id in [&"body_male_default", &"body_female_default"] \
		and draft.visual_id_for(PaperDollLayerVisual.RenderLayer.ARMOR) == &"artgate1_armor" \
		and (hair_id in [&"hair_male_default", &"hair_female_default", &"alt_braided_hair"] \
			or is_approved_hair_id(hair_id)) \
		and draft.visual_id_for(PaperDollLayerVisual.RenderLayer.CAPE) == &"artgate1_cape"

func _is_empty_optional_slot(draft: PaperDollPreviewDraft, layer: int) -> bool:
	return draft.visual_id_for(layer).is_empty()

static func _resolve_mount_action_texture(
		visual: PaperDollLayerVisual,
		gender: int,
		action: int,
		layer: int
	) -> Texture2D:
	var texture: Texture2D = visual.resolve_action(gender, true, action)
	return _resolve_action_texture(texture, layer, action, true, visual.has_action_sheet(true, action))

static func _resolve_action_texture(
		texture: Texture2D,
		layer: int,
		action: int,
		mounted: bool,
		has_dedicated_sheet: bool
	) -> Texture2D:
	if texture == null or has_dedicated_sheet or action == PaperDollAnimation.Action.IDLE:
		return texture
	return ACTION_SHEET_SCRIPT.build(texture, layer, action, mounted)

func failing_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for visual: PaperDollLayerVisual in layer_visuals:
		if visual == null:
			continue
		if not visual.validation_issues().is_empty():
			result.append(visual.visual_id)
	for mount: PaperDollMountVisual in mount_visuals:
		if mount == null:
			continue
		if not mount.validation_issues().is_empty():
			result.append(mount.mount_visual_id)
	return result

static func is_approved_hair_id(visual_id: StringName) -> bool:
	return visual_id in APPROVED_HAIR_IDS

func issues_for_id(visual_id: StringName) -> PackedStringArray:
	var visual: PaperDollLayerVisual = find_visual(visual_id)
	if visual != null:
		return visual.validation_issues()
	var mount: PaperDollMountVisual = find_mount(visual_id)
	return mount.validation_issues() if mount != null else PackedStringArray(["unknown visual id"])

static func create_art_gate1_catalog() -> PaperDollCatalog:
	var result: PaperDollCatalog = PaperDollCatalog.new()
	result.layer_visuals = [
		_art_visual(&"artgate1_cape", PaperDollLayerVisual.RenderLayer.CAPE, PaperDollLayerVisual.GenderPolicy.UNISEX, Color("5f336f")),
		_alternate_visual(&"alt_teal_cape", PaperDollLayerVisual.RenderLayer.CAPE),
		_art_visual(&"body_male_default", PaperDollLayerVisual.RenderLayer.BODY, PaperDollLayerVisual.GenderPolicy.UNISEX, Color("d99d67")),
		_art_visual(&"body_female_default", PaperDollLayerVisual.RenderLayer.BODY, PaperDollLayerVisual.GenderPolicy.UNISEX, Color("e1ad7b")),
		_art_visual(&"artgate1_armor", PaperDollLayerVisual.RenderLayer.ARMOR, PaperDollLayerVisual.GenderPolicy.UNISEX, Color("7e8791")),
		_alternate_visual(&"alt_bronze_armor", PaperDollLayerVisual.RenderLayer.ARMOR),
		_alternate_visual(&"light_armor", PaperDollLayerVisual.RenderLayer.ARMOR),
		_art_visual(&"hair_male_default", PaperDollLayerVisual.RenderLayer.HAIR, PaperDollLayerVisual.GenderPolicy.UNISEX, Color("3a2118")),
		_art_visual(&"hair_female_default", PaperDollLayerVisual.RenderLayer.HAIR, PaperDollLayerVisual.GenderPolicy.UNISEX, Color("5a3020")),
		_alternate_visual(&"alt_braided_hair", PaperDollLayerVisual.RenderLayer.HAIR),
		_alternate_visual(&"hair_short_spiky", PaperDollLayerVisual.RenderLayer.HAIR),
		_alternate_visual(&"hair_high_ponytail", PaperDollLayerVisual.RenderLayer.HAIR),
		_alternate_visual(&"hair_bob", PaperDollLayerVisual.RenderLayer.HAIR),
		_alternate_visual(&"hair_twin_braids", PaperDollLayerVisual.RenderLayer.HAIR),
		_alternate_visual(&"hair_long_side_ponytail", PaperDollLayerVisual.RenderLayer.HAIR),
		_alternate_visual(&"hair_crown_braid", PaperDollLayerVisual.RenderLayer.HAIR),
		_alternate_visual(&"hair_low_bun", PaperDollLayerVisual.RenderLayer.HAIR),
		_alternate_visual(&"hair_undercut_sweep", PaperDollLayerVisual.RenderLayer.HAIR),
		_art_visual(&"artgate1_helmet", PaperDollLayerVisual.RenderLayer.HELMET, PaperDollLayerVisual.GenderPolicy.UNISEX, Color("a7b1ba")),
		_alternate_visual(&"light_armor_helmet", PaperDollLayerVisual.RenderLayer.HELMET),
		_art_visual(&"artgate1_weapon", PaperDollLayerVisual.RenderLayer.WEAPON, PaperDollLayerVisual.GenderPolicy.UNISEX, Color("d0b45a")),
		_alternate_visual(&"alt_bronze_sword", PaperDollLayerVisual.RenderLayer.WEAPON),
		_art_visual(&"artgate1_shield", PaperDollLayerVisual.RenderLayer.SHIELD, PaperDollLayerVisual.GenderPolicy.UNISEX, Color("476f9f")),
		_alternate_visual(&"alt_teal_shield", PaperDollLayerVisual.RenderLayer.SHIELD),
		_art_visual(&"artgate1_barding", PaperDollLayerVisual.RenderLayer.MOUNT_BARDING, PaperDollLayerVisual.GenderPolicy.UNISEX, Color("9c3f3f")),
		_alternate_visual(&"alt_dark_barding", PaperDollLayerVisual.RenderLayer.MOUNT_BARDING),
	]
	var mount: PaperDollMountVisual = PaperDollMountVisual.new()
	mount.mount_visual_id = &"artgate1_horse"
	mount.tail = _art_mount_part(&"artgate1_horse_tail", PaperDollLayerVisual.RenderLayer.MOUNT_TAIL, Color("604631"))
	mount.body = _art_mount_part(&"artgate1_horse_body", PaperDollLayerVisual.RenderLayer.MOUNT_BODY, Color("9a704d"))
	mount.head = _art_mount_part(&"artgate1_horse_head", PaperDollLayerVisual.RenderLayer.MOUNT_HEAD, Color("a87a55"))
	var alternate_mount: PaperDollMountVisual = PaperDollMountVisual.new()
	alternate_mount.mount_visual_id = &"alt_dark_bay_horse"
	alternate_mount.tail = _alternate_visual(&"alt_dark_bay_horse_tail", PaperDollLayerVisual.RenderLayer.MOUNT_TAIL)
	alternate_mount.body = _alternate_visual(&"alt_dark_bay_horse_body", PaperDollLayerVisual.RenderLayer.MOUNT_BODY)
	alternate_mount.head = _alternate_visual(&"alt_dark_bay_horse_head", PaperDollLayerVisual.RenderLayer.MOUNT_HEAD)
	result.mount_visuals = [mount, alternate_mount]
	result.crafting_recipes = [
		CRAFTING_RECIPE_SCRIPT.make_recipe(
			&"craft_light_armor",
			&"light_armor",
			"Light armor",
			{
				"forest": 6,
				"grass": 4,
				"iron_ore": 2,
			}
		),
		CRAFTING_RECIPE_SCRIPT.make_recipe(
			&"craft_light_armor_helmet",
			&"light_armor_helmet",
			"Light armor helmet",
			{
				"forest": 2,
				"grass": 1,
				"iron_ore": 2,
			}
		),
	]
	result.default_male_body_visual_id = &"body_male_default"
	result.default_female_body_visual_id = &"body_female_default"
	result.default_male_hair_visual_id = &"hair_short_spiky"
	result.default_female_hair_visual_id = &"hair_short_spiky"
	return result

static func save_art_gate1_parts(output_dir: String = "res://assets/paper_doll/parts") -> Error:
	var absolute_dir: String = ProjectSettings.globalize_path(output_dir)
	var err: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
	if err != OK:
		return err
	var catalog: PaperDollCatalog = create_art_gate1_catalog()
	for visual: PaperDollLayerVisual in catalog.layer_visuals:
		err = _save_visual_parts(absolute_dir, visual)
		if err != OK:
			return err
	for mount: PaperDollMountVisual in catalog.mount_visuals:
		for part: PaperDollLayerVisual in mount.parts():
			err = _save_texture_png(
				absolute_dir.path_join("%s_mounted_unisex.png" % part.visual_id),
				part.mounted_unisex
			)
			if err != OK:
				return err
	return OK

static func create_debug_catalog() -> PaperDollCatalog:
	var result: PaperDollCatalog = PaperDollCatalog.new()
	result.layer_visuals = [
		_debug_visual(&"debug_cape", PaperDollLayerVisual.RenderLayer.CAPE, PaperDollLayerVisual.GenderPolicy.UNISEX, Color("7d4db3")),
		_debug_visual(&"debug_body", PaperDollLayerVisual.RenderLayer.BODY, PaperDollLayerVisual.GenderPolicy.GENDERED, Color("d6a276")),
		_debug_visual(&"debug_armor", PaperDollLayerVisual.RenderLayer.ARMOR, PaperDollLayerVisual.GenderPolicy.UNISEX, Color("6f8296")),
		_debug_visual(&"debug_hair", PaperDollLayerVisual.RenderLayer.HAIR, PaperDollLayerVisual.GenderPolicy.GENDERED, Color("4f2f20")),
		_debug_visual(&"debug_helmet", PaperDollLayerVisual.RenderLayer.HELMET, PaperDollLayerVisual.GenderPolicy.UNISEX, Color("a7b0b8")),
		_debug_visual(&"debug_weapon", PaperDollLayerVisual.RenderLayer.WEAPON, PaperDollLayerVisual.GenderPolicy.UNISEX, Color("d4c36a")),
		_debug_visual(&"debug_shield", PaperDollLayerVisual.RenderLayer.SHIELD, PaperDollLayerVisual.GenderPolicy.UNISEX, Color("4979a8")),
		_debug_visual(&"debug_barding", PaperDollLayerVisual.RenderLayer.MOUNT_BARDING, PaperDollLayerVisual.GenderPolicy.UNISEX, Color("a84848")),
	]
	var mount: PaperDollMountVisual = PaperDollMountVisual.new()
	mount.mount_visual_id = &"debug_mount"
	mount.tail = _debug_mount_part(&"debug_mount_tail", PaperDollLayerVisual.RenderLayer.MOUNT_TAIL, Color("795c46"))
	mount.body = _debug_mount_part(&"debug_mount_body", PaperDollLayerVisual.RenderLayer.MOUNT_BODY, Color("8f6d50"))
	mount.head = _debug_mount_part(&"debug_mount_head", PaperDollLayerVisual.RenderLayer.MOUNT_HEAD, Color("9f7959"))
	result.mount_visuals = [mount]
	result.default_male_body_visual_id = &"debug_body"
	result.default_female_body_visual_id = &"debug_body"
	result.default_male_hair_visual_id = &"debug_hair"
	result.default_female_hair_visual_id = &"debug_hair"
	return result

static func _visual_less(left: PaperDollLayerVisual, right: PaperDollLayerVisual) -> bool:
	var left_reference: bool = str(left.visual_id).begins_with("artgate1_")
	var right_reference: bool = str(right.visual_id).begins_with("artgate1_")
	if left_reference != right_reference:
		return left_reference
	return str(left.visual_id) < str(right.visual_id)

static func _mount_less(left: PaperDollMountVisual, right: PaperDollMountVisual) -> bool:
	var left_reference: bool = str(left.mount_visual_id).begins_with("artgate1_")
	var right_reference: bool = str(right.mount_visual_id).begins_with("artgate1_")
	if left_reference != right_reference:
		return left_reference
	return str(left.mount_visual_id) < str(right.mount_visual_id)

static func _append_duplicate_issue(
		issues: PackedStringArray,
		used_ids: Dictionary,
		visual_id: StringName
	) -> void:
	var key: String = str(visual_id)
	if used_ids.has(key):
		issues.append("%s: duplicate visual id" % key)
	else:
		used_ids[key] = true

func _append_default_issue(
		issues: PackedStringArray,
		visual_id: StringName,
		expected_layer: int,
		gender: int,
		label: String
	) -> void:
	var visual: PaperDollLayerVisual = find_visual(visual_id)
	if visual == null:
		issues.append("%s is missing" % label)
	elif visual.render_layer != expected_layer or visual.resolve(gender, false) == null:
		issues.append("%s is incompatible" % label)

static func _debug_visual(
		visual_id: StringName,
		layer: int,
		policy: int,
		color: Color
	) -> PaperDollLayerVisual:
	var result: PaperDollLayerVisual = PaperDollLayerVisual.new()
	result.visual_id = visual_id
	result.render_layer = layer
	result.gender_policy = policy
	if policy == PaperDollLayerVisual.GenderPolicy.UNISEX:
		result.on_foot_unisex = _debug_texture(color, layer, false)
		result.mounted_unisex = _debug_texture(color.lightened(0.08), layer, true)
	else:
		result.on_foot_male = _debug_texture(color, layer, false)
		result.on_foot_female = _debug_texture(color.lightened(0.16), layer, false)
		result.mounted_male = _debug_texture(color.darkened(0.06), layer, true)
		result.mounted_female = _debug_texture(color.lightened(0.10), layer, true)
	return result

static func _art_visual(
		visual_id: StringName,
		layer: int,
		policy: int,
		color: Color
	) -> PaperDollLayerVisual:
	var reference_visual: PaperDollLayerVisual = _reference_visual(visual_id, layer, policy)
	if reference_visual != null:
		return reference_visual
	var result: PaperDollLayerVisual = PaperDollLayerVisual.new()
	result.visual_id = visual_id
	result.render_layer = layer
	result.gender_policy = policy
	if policy == PaperDollLayerVisual.GenderPolicy.UNISEX:
		var gender_hint: int = _gender_hint_for_visual_id(visual_id)
		result.on_foot_unisex = _art_texture(color, layer, false, gender_hint)
		result.mounted_unisex = _art_texture(color.lightened(0.06), layer, true, gender_hint)
	else:
		result.on_foot_male = _art_texture(color, layer, false, PaperDollLayerVisual.Gender.MALE)
		result.on_foot_female = _art_texture(color.lightened(0.14), layer, false, PaperDollLayerVisual.Gender.FEMALE)
		result.mounted_male = _art_texture(color.darkened(0.05), layer, true, PaperDollLayerVisual.Gender.MALE)
		result.mounted_female = _art_texture(color.lightened(0.08), layer, true, PaperDollLayerVisual.Gender.FEMALE)
	_attach_authored_walk_sheet(result)
	return result

static func _gender_hint_for_visual_id(visual_id: StringName) -> int:
	var text: String = str(visual_id)
	if text.find("_female_") >= 0:
		return PaperDollLayerVisual.Gender.FEMALE
	if text.find("_male_") >= 0:
		return PaperDollLayerVisual.Gender.MALE
	return -1

static func _art_mount_part(
		visual_id: StringName,
		layer: int,
		color: Color
	) -> PaperDollLayerVisual:
	var reference_visual: PaperDollLayerVisual = _reference_visual(
			visual_id,
			layer,
			PaperDollLayerVisual.GenderPolicy.UNISEX
		)
	if reference_visual != null:
		if reference_visual.mounted_unisex != null \
				and PaperDollLayerVisual.is_mounted_only_layer(layer):
			reference_visual.mounted_unisex = _calibrate_mount_side_rows(
				reference_visual.mounted_unisex
			)
		return reference_visual
	var result: PaperDollLayerVisual = PaperDollLayerVisual.new()
	result.visual_id = visual_id
	result.render_layer = layer
	result.gender_policy = PaperDollLayerVisual.GenderPolicy.UNISEX
	result.mounted_unisex = _art_texture(color, layer, true, -1)
	return result

static func _reference_visual(
		visual_id: StringName,
		layer: int,
		policy: int
	) -> PaperDollLayerVisual:
	var result: PaperDollLayerVisual = PaperDollLayerVisual.new()
	result.visual_id = visual_id
	result.render_layer = layer
	result.gender_policy = policy
	var prefix: String = str(visual_id)
	# The accepted body boards are complete, already aligned silhouettes.  Keep
	# the female board separate: reusing the male mounted board for the female
	# ID makes the female face/eyes disappear behind the wrong rider geometry.
	if visual_id in [&"body_male_default", &"body_female_default"]:
		var gender_prefix := "female" if visual_id == &"body_female_default" else "body"
		var foot_file := "reference_match_female_body_on_foot.png" \
			if gender_prefix == "female" else "reference_match_body_on_foot_unisex.png"
		var mounted_file := "reference_match_female_body_mounted.png" \
			if gender_prefix == "female" else "reference_match_body_mounted_unisex.png"
		result.on_foot_unisex = _load_reference_match_texture(
			foot_file
		)
		result.mounted_unisex = _load_reference_match_texture(
			mounted_file
		)
		_attach_authored_walk_sheet(result)
		return result if result.validation_issues().is_empty() else null
	if PaperDollLayerVisual.is_mounted_only_layer(layer):
		result.mounted_unisex = _load_reference_texture(
			"%s_mounted_unisex.png" % prefix
		)
	elif policy == PaperDollLayerVisual.GenderPolicy.UNISEX:
		result.on_foot_unisex = _load_reference_texture(
			"%s_on_foot_unisex.png" % prefix
		)
		result.mounted_unisex = _load_reference_texture(
			"%s_mounted_unisex.png" % prefix
		)
	else:
		return null
	_attach_authored_walk_sheet(result)
	return result if result.validation_issues().is_empty() else null

static func _alternate_visual(
	visual_id: StringName,
	layer: int
) -> PaperDollLayerVisual:
	"""Load a generated, layer-owned alternate without merging it into another slot.

	The generated board is split by `build_paper_doll_alternate_pack.gd` into
	standard 512x192 RGBA sheets before this catalog is constructed.  Keeping
	this loader separate from `_art_visual` makes provenance explicit and avoids
	accidentally falling back to a procedural rectangle when an alternate file
	is missing.
	"""
	# The eight approved styles now own separate male/female source sheets.
	# Keep the visual IDs stable so saved drafts and existing UI references do not
	# change; only the gender policy and resolved texture fields become gendered.
	if layer == PaperDollLayerVisual.RenderLayer.HAIR and visual_id in APPROVED_HAIR_IDS:
		return _gendered_hair_visual(visual_id)
	# The light-armor helmet uses the same calibrated visor silhouette as the
	# accepted Art Gate helmet.  The generated light-helmet sheet had a solid
	# lower band that covered the entire face and therefore could not satisfy
	# the head/face alignment contract.  Keep the light-helmet ID and crafting
	# recipe, but source its pixels from the proven helmet alignment.
	if visual_id == &"light_armor_helmet":
		var helmet := PaperDollLayerVisual.new()
		helmet.visual_id = visual_id
		helmet.render_layer = layer
		helmet.gender_policy = PaperDollLayerVisual.GenderPolicy.UNISEX
		helmet.on_foot_unisex = _load_reference_texture("artgate1_helmet_on_foot_unisex.png")
		helmet.mounted_unisex = _load_reference_texture("artgate1_helmet_mounted_unisex.png")
		_attach_authored_walk_sheet(helmet)
		return helmet
	var result: PaperDollLayerVisual = PaperDollLayerVisual.new()
	result.visual_id = visual_id
	result.render_layer = layer
	result.gender_policy = PaperDollLayerVisual.GenderPolicy.UNISEX
	var prefix: String = str(visual_id)
	if PaperDollLayerVisual.is_mounted_only_layer(layer):
		result.mounted_unisex = _load_alternate_texture(
			"%s_mounted_unisex.png" % prefix
		)
		result.mounted_unisex = _calibrate_mount_side_rows(result.mounted_unisex)
	else:
		result.on_foot_unisex = _load_alternate_texture(
			"%s_on_foot_unisex.png" % prefix
		)
		# Hair has no pose-specific anchor change. Reuse one approved sheet for
		# both modes instead of creating a second byte-identical PNG.
		if is_approved_hair_id(visual_id):
			result.mounted_unisex = result.on_foot_unisex
		else:
			result.mounted_unisex = _load_alternate_texture(
				"%s_mounted_unisex.png" % prefix
			)
	_attach_authored_walk_sheet(result)
	return result

static func _calibrate_mount_side_rows(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var source := texture.get_image()
	if source == null or source.is_empty():
		return texture
	var calibrated := source.duplicate()
	for frame_x: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
		var origin := Vector2i(frame_x * PaperDollLayerVisual.FRAME_SIZE.x, 2 * PaperDollLayerVisual.FRAME_SIZE.y)
		var source_frame := source.get_region(Rect2i(origin, PaperDollLayerVisual.FRAME_SIZE))
		var side_frame := Image.create(
			PaperDollLayerVisual.FRAME_SIZE.x,
			PaperDollLayerVisual.FRAME_SIZE.y,
			false,
			Image.FORMAT_RGBA8
		)
		side_frame.fill(Color.TRANSPARENT)
		for output_y: int in range(PaperDollLayerVisual.FRAME_SIZE.y):
			for output_x: int in range(PaperDollLayerVisual.FRAME_SIZE.x):
				var source_x := roundi((float(output_x) - 32.0) / MOUNT_SIDE_HORIZONTAL_SCALE + 32.0)
				if source_x < 0 or source_x >= PaperDollLayerVisual.FRAME_SIZE.x:
					continue
				var pixel := source_frame.get_pixel(source_x, output_y)
				if pixel.a > 0.05:
					side_frame.set_pixel(output_x, output_y, pixel)
		calibrated.blit_rect(
			side_frame,
			Rect2i(Vector2i.ZERO, PaperDollLayerVisual.FRAME_SIZE),
			origin
		)
	return ImageTexture.create_from_image(calibrated)

static func _gendered_hair_visual(visual_id: StringName) -> PaperDollLayerVisual:
	var result: PaperDollLayerVisual = PaperDollLayerVisual.new()
	result.visual_id = visual_id
	result.render_layer = PaperDollLayerVisual.RenderLayer.HAIR
	result.gender_policy = PaperDollLayerVisual.GenderPolicy.GENDERED
	var prefix: String = str(visual_id)
	# Hair has no pose-specific anchor change. Reuse each gender's validated
	# 8x3 sheet for both on-foot and mounted recipes while keeping male/female
	# ownership explicit in the Resource.
	result.on_foot_male = _load_alternate_texture("%s_on_foot_male.png" % prefix)
	result.on_foot_female = _load_alternate_texture("%s_on_foot_female.png" % prefix)
	result.mounted_male = result.on_foot_male
	result.mounted_female = result.on_foot_female
	_attach_authored_walk_sheet(result)
	return result

static func _attach_authored_walk_sheet(visual: PaperDollLayerVisual) -> void:
	if not APPROVED_AUTHORED_ACTIONS:
		return
	if visual == null or visual.render_layer in [
		PaperDollLayerVisual.RenderLayer.MOUNT_TAIL,
		PaperDollLayerVisual.RenderLayer.MOUNT_BODY,
		PaperDollLayerVisual.RenderLayer.MOUNT_HEAD,
		PaperDollLayerVisual.RenderLayer.HELMET,
		PaperDollLayerVisual.RenderLayer.SHIELD,
	]:
		return
	var visual_id: String = str(visual.visual_id)
	if visual.render_layer == PaperDollLayerVisual.RenderLayer.BODY \
		and visual_id != "body_male_default":
		return
	if visual.render_layer == PaperDollLayerVisual.RenderLayer.HAIR \
		and visual_id != "hair_male_default":
		return
	var suffix: String = _action_layer_suffix(visual.render_layer)
	var path: String = ACTION_ART_DIR.path_join("walk_on_foot_%s.png" % suffix)
	if not ResourceLoader.exists(path):
		return
	var texture: Texture2D = load(path) as Texture2D
	if texture == null:
		return
	if visual_id.begins_with("alt_"):
		texture = _recolor_authored_action(texture, visual_id)
	visual.on_foot_action_sheets.resize(PaperDollAnimation.Action.COUNT)
	visual.on_foot_action_sheets[PaperDollAnimation.Action.WALK] = texture

static func _action_layer_suffix(layer: int) -> String:
	match layer:
		PaperDollLayerVisual.RenderLayer.BODY:
			return "body"
		PaperDollLayerVisual.RenderLayer.HAIR:
			return "hair"
		PaperDollLayerVisual.RenderLayer.ARMOR:
			return "armor"
		PaperDollLayerVisual.RenderLayer.CAPE:
			return "cape"
		PaperDollLayerVisual.RenderLayer.WEAPON:
			return "weapon"
	return ""

static func _recolor_authored_action(texture: Texture2D, visual_id: String) -> Texture2D:
	var palette: Vector3 = Vector3(-1.0, -1.0, -1.0)
	match visual_id:
		"alt_braided_hair":
			palette = Vector3(0.08, 0.62, 0.86)
		"alt_bronze_armor", "alt_bronze_sword":
			palette = Vector3(0.075, 0.66, 0.82)
		"alt_teal_cape":
			palette = Vector3(0.49, 0.64, 0.72)
		_:
			return texture
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return texture
	image = image.duplicate()
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a <= 0.05:
				continue
			var luminance: float = pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114
			var value: float = clampf(luminance * palette.z / 0.72, 0.0, 1.0)
			var saturation: float = clampf(palette.y * (0.55 + pixel.s * 0.45), 0.04, 1.0)
			image.set_pixel(x, y, Color.from_hsv(palette.x, saturation, value, pixel.a))
	return ImageTexture.create_from_image(image)

static func _load_alternate_texture(file_name: String) -> Texture2D:
	var path: String = REFERENCE_ART_DIR.path_join(file_name)
	if not FileAccess.file_exists(ProjectSettings.globalize_path(path)):
		return null
	# The braided sheet is regenerated from the checked-in art board. Read its
	# PNG directly so a stale editor import cannot resurrect the old palette-only
	# placeholder during a creator preview.
	if _is_hair_only_file(file_name):
		var hair_image: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
		if hair_image == null or hair_image.is_empty():
			return null
		var hair_texture := ImageTexture.create_from_image(hair_image)
		hair_texture.set_meta("paper_doll_hair_only", true)
		return hair_texture
	return _load_png_texture(path)

static func _is_hair_only_file(file_name: String) -> bool:
	for hair_id: StringName in APPROVED_HAIR_IDS:
		if file_name.begins_with("%s_" % hair_id):
			return true
	return file_name.begins_with("alt_braided_hair_")

static func _load_reference_texture(file_name: String) -> Texture2D:
	var path: String = REFERENCE_ART_DIR.path_join(file_name)
	return _load_png_texture(path)

static func _load_layered_body_texture(gender: int, mounted: bool) -> Texture2D:
	var gender_name := "female" if gender == PaperDollLayerVisual.Gender.FEMALE else "male"
	var pose_name := "mounted" if mounted else "on_foot"
	return _load_reference_texture("body_%s_default_%s_unisex.png" % [gender_name, pose_name])

static func _load_reference_match_texture(file_name: String) -> Texture2D:
	var path: String = REFERENCE_MATCH_DIR.path_join(file_name)
	if not FileAccess.file_exists(ProjectSettings.globalize_path(path)):
		return null
	return _load_png_texture(path)

static func _load_png_texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(ProjectSettings.globalize_path(path)):
		return null
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
	if image != null and not image.is_empty():
		return ImageTexture.create_from_image(image)
	# Keep a ResourceLoader fallback for projects that provide an imported
	# texture but no readable source file.  Normal checked-in paper-doll PNGs
	# take the direct path above, so stale .ctex files cannot break the lab.
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

static func _art_texture(color: Color, layer: int, mounted: bool, gender: int) -> Texture2D:
	var image: Image = Image.create(
		PaperDollLayerVisual.SHEET_SIZE.x,
		PaperDollLayerVisual.SHEET_SIZE.y,
		false,
		Image.FORMAT_RGBA8
	)
	image.fill(Color.TRANSPARENT)
	for row: int in range(PaperDollLayerVisual.SOURCE_ROWS):
		for frame: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
			var origin: Vector2i = Vector2i(
				frame * PaperDollLayerVisual.FRAME_SIZE.x,
				row * PaperDollLayerVisual.FRAME_SIZE.y
			)
			_paint_art_frame(image, origin, layer, color, mounted, gender, row, frame)
	return ImageTexture.create_from_image(image)

static func _paint_art_frame(
		image: Image,
		origin: Vector2i,
		layer: int,
		color: Color,
		mounted: bool,
		gender: int,
		row: int,
		frame: int
	) -> void:
	var sway: int = (frame % 4) - 1
	var step: int = -1 if frame % 2 == 1 else 0
	var rider_lift: int = -15 if mounted else 0
	var side: bool = row == PaperDollLayerVisual.Facing.RIGHT
	var back: bool = row == PaperDollLayerVisual.Facing.UP
	var base: Color = color.lightened(0.08 if row == PaperDollLayerVisual.Facing.DOWN else 0.0)
	var shade: Color = color.darkened(0.45)
	var hi: Color = color.lightened(0.35)
	match layer:
		PaperDollLayerVisual.RenderLayer.BODY:
			_draw_body(image, origin, base, shade, hi, rider_lift, sway, step, side, back, gender)
		PaperDollLayerVisual.RenderLayer.HAIR:
			_draw_hair(image, origin, base, shade, rider_lift, sway, side, back, gender)
		PaperDollLayerVisual.RenderLayer.ARMOR:
			_draw_armor(image, origin, base, shade, hi, rider_lift, sway, side)
		PaperDollLayerVisual.RenderLayer.HELMET:
			_draw_helmet(image, origin, base, shade, hi, rider_lift, sway, side)
		PaperDollLayerVisual.RenderLayer.CAPE:
			_draw_cape(image, origin, base, shade, rider_lift, sway, step, side)
		PaperDollLayerVisual.RenderLayer.WEAPON:
			_draw_weapon(image, origin, base, shade, rider_lift, sway, step, side)
		PaperDollLayerVisual.RenderLayer.SHIELD:
			_draw_shield(image, origin, base, shade, rider_lift, sway, step, side)
		PaperDollLayerVisual.RenderLayer.MOUNT_TAIL:
			_draw_rect(image, origin + Vector2i(6 + sway, 38 + step), Vector2i(12, 5), shade)
			_draw_rect(image, origin + Vector2i(4 + sway, 42 + step), Vector2i(10, 4), base)
		PaperDollLayerVisual.RenderLayer.MOUNT_BODY:
			_draw_rect(image, origin + Vector2i(14 + sway, 36 + step), Vector2i(36, 16), shade)
			_draw_rect(image, origin + Vector2i(16 + sway, 33 + step), Vector2i(31, 16), base)
			_draw_rect(image, origin + Vector2i(20 + sway, 30 + step), Vector2i(18, 6), hi)
			_draw_rect(image, origin + Vector2i(18 + sway, 49 + step), Vector2i(5, 8), shade)
			_draw_rect(image, origin + Vector2i(41 + sway, 49 + step), Vector2i(5, 8), shade)
		PaperDollLayerVisual.RenderLayer.MOUNT_HEAD:
			_draw_rect(image, origin + Vector2i(46 + sway, 27 + step), Vector2i(11, 14), shade)
			_draw_rect(image, origin + Vector2i(45 + sway, 25 + step), Vector2i(10, 14), base)
			_draw_rect(image, origin + Vector2i(53 + sway, 31 + step), Vector2i(5, 4), base)
			_draw_rect(image, origin + Vector2i(48 + sway, 23 + step), Vector2i(3, 5), hi)
			_draw_rect(image, origin + Vector2i(53 + sway, 23 + step), Vector2i(3, 5), hi)
		PaperDollLayerVisual.RenderLayer.MOUNT_BARDING:
			_draw_rect(image, origin + Vector2i(18 + sway, 37 + step), Vector2i(28, 12), shade)
			_draw_rect(image, origin + Vector2i(19 + sway, 35 + step), Vector2i(26, 11), base)
			_draw_rect(image, origin + Vector2i(27 + sway, 35 + step), Vector2i(3, 11), hi)

static func _draw_body(
		image: Image,
		origin: Vector2i,
		base: Color,
		shade: Color,
		hi: Color,
		lift: int,
		sway: int,
		step: int,
		side: bool,
		back: bool,
		gender: int
	) -> void:
	var hip: int = 1 if gender == PaperDollLayerVisual.Gender.FEMALE else 0
	_draw_rect(image, origin + Vector2i(24 + sway, 17 + lift + step), Vector2i(17, 17), shade)
	_draw_rect(image, origin + Vector2i(25 + sway, 16 + lift + step), Vector2i(15, 16), base)
	_draw_rect(image, origin + Vector2i(27 + sway, 32 + lift + step), Vector2i(11 + hip, 17), base)
	_draw_rect(image, origin + Vector2i(22 + sway, 34 + lift + step), Vector2i(5, 13), shade)
	_draw_rect(image, origin + Vector2i(39 + sway, 34 + lift + step), Vector2i(5, 13), shade)
	_draw_rect(image, origin + Vector2i(26 + sway, 48 + lift + step), Vector2i(5, 8), shade)
	_draw_rect(image, origin + Vector2i(35 + sway, 48 + lift + step), Vector2i(5, 8), shade)
	if not back and not side:
		_draw_rect(image, origin + Vector2i(29 + sway, 23 + lift + step), Vector2i(2, 5), Color("22180f"))
		_draw_rect(image, origin + Vector2i(35 + sway, 23 + lift + step), Vector2i(2, 5), Color("22180f"))
	_draw_rect(image, origin + Vector2i(28 + sway, 18 + lift + step), Vector2i(5, 3), hi)

static func _draw_hair(
		image: Image,
		origin: Vector2i,
		base: Color,
		shade: Color,
		lift: int,
		sway: int,
		side: bool,
		back: bool,
		gender: int
	) -> void:
	var length: int = 7 if gender == PaperDollLayerVisual.Gender.FEMALE else 3
	_draw_rect(image, origin + Vector2i(24 + sway, 15 + lift), Vector2i(17, 6), shade)
	_draw_rect(image, origin + Vector2i(26 + sway, 14 + lift), Vector2i(13, 5), base)
	if side:
		_draw_rect(image, origin + Vector2i(38 + sway, 20 + lift), Vector2i(4, length + 3), shade)
	elif back:
		_draw_rect(image, origin + Vector2i(25 + sway, 20 + lift), Vector2i(15, length + 5), shade)
	else:
		_draw_rect(image, origin + Vector2i(23 + sway, 20 + lift), Vector2i(4, length), shade)
		_draw_rect(image, origin + Vector2i(39 + sway, 20 + lift), Vector2i(4, length), shade)

static func _draw_armor(image: Image, origin: Vector2i, base: Color, shade: Color, hi: Color, lift: int, sway: int, side: bool) -> void:
	_draw_rect(image, origin + Vector2i(23 + sway, 31 + lift), Vector2i(20, 18), shade)
	_draw_rect(image, origin + Vector2i(25 + sway, 29 + lift), Vector2i(16, 17), base)
	_draw_rect(image, origin + Vector2i(31 + sway, 29 + lift), Vector2i(3, 17), hi)
	if side:
		_draw_rect(image, origin + Vector2i(39 + sway, 33 + lift), Vector2i(4, 13), shade)

static func _draw_helmet(image: Image, origin: Vector2i, base: Color, shade: Color, hi: Color, lift: int, sway: int, side: bool) -> void:
	_draw_rect(image, origin + Vector2i(23 + sway, 16 + lift), Vector2i(20, 10), shade)
	_draw_rect(image, origin + Vector2i(25 + sway, 14 + lift), Vector2i(16, 10), base)
	_draw_rect(image, origin + Vector2i(30 + sway, 13 + lift), Vector2i(6, 3), hi)
	if side:
		_draw_rect(image, origin + Vector2i(39 + sway, 19 + lift), Vector2i(4, 6), shade)

static func _draw_cape(image: Image, origin: Vector2i, base: Color, shade: Color, lift: int, sway: int, step: int, side: bool) -> void:
	var width: int = 14 if side else 18
	_draw_rect(image, origin + Vector2i(23 + sway, 29 + lift + step), Vector2i(width, 25), shade)
	_draw_rect(image, origin + Vector2i(25 + sway, 30 + lift + step), Vector2i(width - 4, 23), base)

static func _draw_weapon(image: Image, origin: Vector2i, base: Color, shade: Color, lift: int, sway: int, step: int, side: bool) -> void:
	var x: int = 46 if not side else 44
	_draw_rect(image, origin + Vector2i(x + sway, 24 + lift + step), Vector2i(3, 28), shade)
	_draw_rect(image, origin + Vector2i(x + 1 + sway, 22 + lift + step), Vector2i(2, 28), base)
	_draw_rect(image, origin + Vector2i(x - 3 + sway, 31 + lift + step), Vector2i(8, 3), base.lightened(0.25))

static func _draw_shield(image: Image, origin: Vector2i, base: Color, shade: Color, lift: int, sway: int, step: int, side: bool) -> void:
	var x: int = 14 if not side else 16
	_draw_rect(image, origin + Vector2i(x + sway, 32 + lift + step), Vector2i(12, 17), shade)
	_draw_rect(image, origin + Vector2i(x + 1 + sway, 31 + lift + step), Vector2i(10, 15), base)
	_draw_rect(image, origin + Vector2i(x + 5 + sway, 31 + lift + step), Vector2i(2, 15), base.lightened(0.25))

static func _draw_rect(image: Image, position: Vector2i, size: Vector2i, color: Color) -> void:
	image.fill_rect(Rect2i(position, size), color)

static func _save_visual_parts(absolute_dir: String, visual: PaperDollLayerVisual) -> Error:
	if PaperDollLayerVisual.is_mounted_only_layer(visual.render_layer):
		return _save_texture_png(
			absolute_dir.path_join("%s_mounted_unisex.png" % visual.visual_id),
			visual.mounted_unisex
		)
	if visual.gender_policy == PaperDollLayerVisual.GenderPolicy.UNISEX:
		var err: Error = _save_texture_png(
			absolute_dir.path_join("%s_on_foot_unisex.png" % visual.visual_id),
			visual.on_foot_unisex
		)
		if err != OK:
			return err
		return _save_texture_png(
			absolute_dir.path_join("%s_mounted_unisex.png" % visual.visual_id),
			visual.mounted_unisex
		)
	for pose_name: String in ["on_foot", "mounted"]:
		for gender_name: String in ["male", "female"]:
			var texture: Texture2D
			if pose_name == "on_foot":
				texture = visual.on_foot_male if gender_name == "male" else visual.on_foot_female
			else:
				texture = visual.mounted_male if gender_name == "male" else visual.mounted_female
			var err: Error = _save_texture_png(
				absolute_dir.path_join("%s_%s_%s.png" % [visual.visual_id, pose_name, gender_name]),
				texture
			)
			if err != OK:
				return err
	return OK

static func _save_texture_png(path: String, texture: Texture2D) -> Error:
	if texture == null:
		return ERR_DOES_NOT_EXIST
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return ERR_FILE_CORRUPT
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image.save_png(path)

static func _debug_mount_part(
		visual_id: StringName,
		layer: int,
		color: Color
	) -> PaperDollLayerVisual:
	var result: PaperDollLayerVisual = PaperDollLayerVisual.new()
	result.visual_id = visual_id
	result.render_layer = layer
	result.gender_policy = PaperDollLayerVisual.GenderPolicy.UNISEX
	result.mounted_unisex = _debug_texture(color, layer, true)
	return result

static func _debug_texture(color: Color, layer: int, mounted: bool) -> Texture2D:
	var image: Image = Image.create(
		PaperDollLayerVisual.SHEET_SIZE.x,
		PaperDollLayerVisual.SHEET_SIZE.y,
		false,
		Image.FORMAT_RGBA8
	)
	image.fill(Color.TRANSPARENT)
	for row: int in range(PaperDollLayerVisual.SOURCE_ROWS):
		for frame: int in range(PaperDollLayerVisual.FRAME_COLUMNS):
			var origin: Vector2i = Vector2i(
				frame * PaperDollLayerVisual.FRAME_SIZE.x,
				row * PaperDollLayerVisual.FRAME_SIZE.y
			)
			var sway: int = (frame % 4) - 1
			var bounce: int = -1 if frame % 2 == 1 else 0
			var rect: Rect2i = _debug_layer_rect(layer, mounted, sway, bounce)
			image.fill_rect(Rect2i(origin + rect.position, rect.size), color)
			image.set_pixelv(origin + rect.position + Vector2i(1, 1), Color.WHITE)
	return ImageTexture.create_from_image(image)

static func _debug_layer_rect(
		layer: int,
		mounted: bool,
		sway: int,
		bounce: int
	) -> Rect2i:
	var rider_lift: int = -15 if mounted else 0
	match layer:
		PaperDollLayerVisual.RenderLayer.MOUNT_TAIL:
			return Rect2i(5 + sway, 38 + bounce, 12, 5)
		PaperDollLayerVisual.RenderLayer.CAPE:
			return Rect2i(22 + sway, 31 + rider_lift + bounce, 17, 24)
		PaperDollLayerVisual.RenderLayer.MOUNT_BODY:
			return Rect2i(14 + sway, 36 + bounce, 36, 17)
		PaperDollLayerVisual.RenderLayer.BODY:
			return Rect2i(25 + sway, 25 + rider_lift + bounce, 15, 30)
		PaperDollLayerVisual.RenderLayer.ARMOR:
			return Rect2i(23 + sway, 34 + rider_lift + bounce, 19, 14)
		PaperDollLayerVisual.RenderLayer.HAIR:
			return Rect2i(24 + sway, 20 + rider_lift + bounce, 17, 8)
		PaperDollLayerVisual.RenderLayer.HELMET:
			return Rect2i(23 + sway, 17 + rider_lift + bounce, 19, 9)
		PaperDollLayerVisual.RenderLayer.WEAPON:
			return Rect2i(46 + sway, 25 + rider_lift + bounce, 4, 30)
		PaperDollLayerVisual.RenderLayer.SHIELD:
			return Rect2i(14 + sway, 33 + rider_lift + bounce, 11, 16)
		PaperDollLayerVisual.RenderLayer.MOUNT_HEAD:
			return Rect2i(46 + sway, 28 + bounce, 12, 14)
		PaperDollLayerVisual.RenderLayer.MOUNT_BARDING:
			return Rect2i(18 + sway, 37 + bounce, 29, 13)
		_:
			return Rect2i(30, 30, 4, 4)
