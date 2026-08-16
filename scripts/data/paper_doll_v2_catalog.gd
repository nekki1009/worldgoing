class_name PaperDollV2Catalog
extends Resource

## Catalog is the only lookup boundary for V2 normalized parts.

const REFERENCE_MATCH_DIR := "res://assets/paper_doll/reference_match"
const PACK_02_SPEC_PATH := "res://assets/paper_doll/v2/pack_02_spec.json"
const PACK_02_ROOT := "res://assets/paper_doll/v2/staging/pack_02"

@export var templates: Array[PaperDollV2BodyTemplate] = []
@export var manifests: Array[PaperDollV2AssetManifest] = []
var last_issues: PackedStringArray = []

func add_template(template: PaperDollV2BodyTemplate) -> bool:
	if template == null or not template.validation_issues().is_empty():
		return false
	for existing in templates:
		if existing != null and existing.template_id == template.template_id:
			return false
	templates.append(template)
	return true

func add_manifest(manifest: PaperDollV2AssetManifest) -> bool:
	if manifest == null:
		return false
	var template := template_for(manifest.state, manifest.gender) if manifest.gender_policy == PaperDollV2Contract.GenderPolicy.GENDERED else template_for(manifest.state, PaperDollV2Contract.Gender.MALE)
	if template == null or not manifest.validation_issues(template).is_empty():
		return false
	for existing in manifests:
		if existing != null and existing.visual_id == manifest.visual_id \
				and existing.render_layer == manifest.render_layer \
				and existing.state == manifest.state \
				and existing.gender == manifest.gender:
			return false
	manifests.append(manifest)
	return true

func template_for(state: int, gender: int) -> PaperDollV2BodyTemplate:
	for template in templates:
		if template != null and template.state == state and template.gender == gender:
			return template
	return null

func find_visual(visual_id: StringName, layer: int, state: int, gender: int) -> PaperDollV2AssetManifest:
	for manifest in manifests:
		if manifest == null or manifest.visual_id != visual_id or manifest.render_layer != layer or manifest.state != state:
			continue
		if manifest.is_compatible_with(gender):
			return manifest
	return null

func resolve_recipe(
		gender: int,
		state: int,
		selection: Dictionary,
		body_visual_id: StringName,
		mount_required: bool = true
	) -> PaperDollV2Recipe:
	last_issues = PackedStringArray()
	var template := template_for(state, gender)
	if template == null:
		last_issues.append("missing body template")
		return null
	var recipe := PaperDollV2Recipe.new(gender, state)
	recipe.template = template
	var body := find_visual(body_visual_id, PaperDollV2Contract.RenderLayer.BODY, state, gender)
	if body == null:
		last_issues.append("body visual not found: %s" % body_visual_id)
		return null
	recipe.set_layer_texture(PaperDollV2Contract.RenderLayer.BODY, body.texture)
	for layer_key in selection.keys():
		var layer := int(layer_key)
		var visual_id := StringName(selection[layer_key])
		if visual_id.is_empty():
			continue
		var manifest := find_visual(visual_id, layer, state, gender)
		if manifest == null:
			last_issues.append("visual not found: layer=%s id=%s" % [PaperDollV2Contract.layer_name(layer), visual_id])
			continue
		recipe.set_layer_texture(layer, manifest.texture)
	if state == PaperDollV2Contract.RenderState.MOUNTED and mount_required:
		for layer in [
			PaperDollV2Contract.RenderLayer.MOUNT_TAIL,
			PaperDollV2Contract.RenderLayer.MOUNT_BODY,
			PaperDollV2Contract.RenderLayer.MOUNT_HEAD,
		]:
			if recipe.texture_for(layer) == null:
				last_issues.append("mounted recipe missing %s" % PaperDollV2Contract.layer_name(layer))
	if not last_issues.is_empty():
		return null
	var recipe_issues := recipe.validation_issues()
	if not recipe_issues.is_empty():
		last_issues.append_array(recipe_issues)
		return null
	return recipe

func validation_issues() -> PackedStringArray:
	var issues := PackedStringArray()
	var ids := {}
	for template in templates:
		if template == null:
			issues.append("null body template")
			continue
		issues.append_array(template.validation_issues())
		var key := "%s:%d:%d" % [template.template_id, template.state, template.gender]
		if ids.has(key):
			issues.append("duplicate body template: %s" % key)
		ids[key] = true
	for manifest in manifests:
		if manifest == null:
			issues.append("null asset manifest")
			continue
		var template := template_for(manifest.state, manifest.gender) if manifest.gender_policy == PaperDollV2Contract.GenderPolicy.GENDERED else template_for(manifest.state, PaperDollV2Contract.Gender.MALE)
		issues.append_array(manifest.validation_issues(template))
	return issues

static func load_generated_pack() -> PaperDollV2Catalog:
	var result := PaperDollV2Catalog.new()
	var report_file := FileAccess.open("res://assets/paper_doll/v2/manifest.json", FileAccess.READ)
	if report_file == null:
		result.last_issues.append("V2 manifest.json is missing")
		return result
	var parsed = JSON.parse_string(report_file.get_as_text())
	if not parsed is Dictionary:
		result.last_issues.append("V2 manifest.json is invalid")
		return result
	var entries: Array = parsed.get("entries", []) as Array
	# The JSON is alphabetical, so parts can appear before Body.  Register all
	# body templates first; only then admit the remaining manifests.
	for entry_value in entries:
		if not entry_value is Dictionary:
			continue
		var body_entry: Dictionary = entry_value
		var body_id := StringName(String(body_entry.get("visual_id", "")))
		if _layer_for_visual_id(body_id) != PaperDollV2Contract.RenderLayer.BODY:
			continue
		var body_state_text := String(body_entry.get("state", "on_foot"))
		var body_state := PaperDollV2Contract.RenderState.MOUNTED if body_state_text == "mounted" else PaperDollV2Contract.RenderState.ON_FOOT
		var body_text := str(body_id)
		var body_gender := PaperDollV2Contract.Gender.FEMALE if body_text.find("female") >= 0 else PaperDollV2Contract.Gender.MALE
		if result.template_for(body_state, body_gender) != null:
			continue
		var body_texture := _load_png_texture(String(body_entry.get("file", "")))
		if body_texture == null:
			result.last_issues.append("V2 body texture could not load: %s" % body_id)
			continue
		var body_template := PaperDollV2BodyTemplate.new()
		body_template.template_id = StringName("body_%s_%s" % [PaperDollV2Contract.gender_name(body_gender), PaperDollV2Contract.state_name(body_state)])
		body_template.state = body_state
		body_template.gender = body_gender
		body_template.anchor_px = PaperDollV2Contract.anchor_px(body_state)
		body_template.foot_or_hoof_line = body_template.anchor_px.y
		body_template.texture = body_texture
		if not result.add_template(body_template):
			result.last_issues.append("V2 body template rejected: %s" % body_template.template_id)
	for entry_value in entries:
		if not entry_value is Dictionary:
			result.last_issues.append("V2 manifest entry is not an object")
			continue
		var entry: Dictionary = entry_value
		var file_path := String(entry.get("file", ""))
		var visual_id := StringName(String(entry.get("visual_id", "")))
		var state_text := String(entry.get("state", "on_foot"))
		var state := PaperDollV2Contract.RenderState.MOUNTED if state_text == "mounted" else PaperDollV2Contract.RenderState.ON_FOOT
		var texture := _load_png_texture(file_path)
		if texture == null:
			result.last_issues.append("V2 texture could not load: %s" % file_path)
			continue
		var layer := _layer_for_visual_id(visual_id)
		if layer < 0:
			# Full mounted boards are retained as source art but are not a V2 layer.
			continue
		var gender_policy := PaperDollV2Contract.GenderPolicy.UNISEX
		var gender := PaperDollV2Contract.Gender.MALE
		var visual_text := str(visual_id)
		if visual_text.ends_with("_male") or visual_text.find("_male_") >= 0:
			gender_policy = PaperDollV2Contract.GenderPolicy.GENDERED
			gender = PaperDollV2Contract.Gender.MALE
		elif visual_text.ends_with("_female") or visual_text.find("_female_") >= 0:
			gender_policy = PaperDollV2Contract.GenderPolicy.GENDERED
			gender = PaperDollV2Contract.Gender.FEMALE
		var template := result.template_for(state, gender if gender_policy == PaperDollV2Contract.GenderPolicy.GENDERED else PaperDollV2Contract.Gender.MALE)
		if layer == PaperDollV2Contract.RenderLayer.BODY:
			if template == null:
				result.last_issues.append("V2 body template missing: %s" % visual_id)
				continue
		var target_template := result.template_for(state, gender if gender_policy == PaperDollV2Contract.GenderPolicy.GENDERED else PaperDollV2Contract.Gender.MALE)
		if target_template == null:
			result.last_issues.append("V2 manifest has no template: %s" % visual_id)
			continue
		var manifest := PaperDollV2AssetManifest.new()
		manifest.visual_id = visual_id
		manifest.render_layer = layer
		manifest.state = state
		manifest.gender_policy = gender_policy
		manifest.gender = gender
		manifest.symmetry_policy = PaperDollV2Contract.SymmetryPolicy.MIRROR_RIGHT
		manifest.texture = texture
		manifest.source_path = file_path
		manifest.template_id = target_template.template_id
		manifest.required = layer == PaperDollV2Contract.RenderLayer.BODY
		if not result.add_manifest(manifest):
			result.last_issues.append("V2 manifest rejected: %s" % visual_id)
	_register_reference_manifests(result)
	return result

## Load the isolated Pack 02 test catalog without changing the admitted V2
## manifest.  The formal catalog remains the only production source; this
## loader deliberately starts from that catalog and appends staging manifests
## in memory, so a failed Pack 02 asset can never replace a passed baseline.
static func load_staging_pack_02() -> PaperDollV2Catalog:
	var result := load_generated_pack()
	if not result.last_issues.is_empty():
		return result
	var spec_file := FileAccess.open(PACK_02_SPEC_PATH, FileAccess.READ)
	if spec_file == null:
		result.last_issues.append("Pack 02 spec is missing")
		return result
	var parsed = JSON.parse_string(spec_file.get_as_text())
	if not parsed is Dictionary:
		result.last_issues.append("Pack 02 spec is invalid")
		return result
	var spec: Dictionary = parsed as Dictionary
	if String(spec.get("status", "")) == "STAGING_SPEC_ONLY":
		# The status describes admission to the formal pack, not whether the
		# isolated lab may inspect it.  Keep this path explicitly staging-only.
		result.last_issues.append_array(_register_pack_02_entries(result, spec))
	else:
		result.last_issues.append("Pack 02 spec status is not staging")
	return result

static func _register_pack_02_entries(
		catalog: PaperDollV2Catalog,
		spec: Dictionary
	) -> PackedStringArray:
	var issues := PackedStringArray()
	for raw_entry: Variant in spec.get("entries", []):
		if not raw_entry is Dictionary:
			issues.append("Pack 02 entry is not an object")
			continue
		var entry: Dictionary = raw_entry as Dictionary
		var visual_id := StringName(String(entry.get("visual_id", "")))
		var layer := _staging_layer_for_name(String(entry.get("layer", "")))
		if layer < 0:
			issues.append("Pack 02 layer is invalid: %s" % visual_id)
			continue
		var gender_policy_text := String(entry.get("gender_policy", "UNISEX"))
		var gender_policy := PaperDollV2Contract.GenderPolicy.GENDERED \
			if gender_policy_text == "GENDERED" \
			else PaperDollV2Contract.GenderPolicy.UNISEX
		var states: Array = entry.get("states", []) as Array
		var files_by_state: Dictionary = entry.get("files", {}) as Dictionary
		for state_text_variant: Variant in states:
			var state_text := String(state_text_variant)
			var state := PaperDollV2Contract.RenderState.MOUNTED \
				if state_text == "MOUNTED" \
				else PaperDollV2Contract.RenderState.ON_FOOT
			var state_files: Array = files_by_state.get(state_text, []) as Array
			if state_files.is_empty():
				issues.append("Pack 02 has no %s file: %s" % [state_text, visual_id])
				continue
			for file_variant: Variant in state_files:
				var file_name := String(file_variant)
				var texture_path := PACK_02_ROOT.path_join(file_name)
				var texture := _load_png_texture(texture_path)
				if texture == null:
					issues.append("Pack 02 texture could not load: %s" % texture_path)
					continue
				var gender := PaperDollV2Contract.Gender.MALE
				if gender_policy == PaperDollV2Contract.GenderPolicy.GENDERED:
					gender = PaperDollV2Contract.Gender.FEMALE \
						if file_name.find("_female") >= 0 \
						else PaperDollV2Contract.Gender.MALE
				var template := catalog.template_for(state, gender)
				if template == null:
					issues.append("Pack 02 has no template for %s" % texture_path)
					continue
				var manifest := PaperDollV2AssetManifest.new()
				manifest.visual_id = visual_id
				manifest.render_layer = layer
				manifest.state = state
				manifest.gender_policy = gender_policy
				manifest.gender = gender
				manifest.symmetry_policy = _staging_symmetry_for_name(
					String(entry.get("symmetry_policy", "MIRROR_RIGHT"))
				)
				manifest.texture = texture
				manifest.source_path = texture_path
				manifest.template_id = template.template_id
				manifest.normalization_version = &"pack_02_staging_v2_1"
				manifest.required = false
				var dye_masks: Array = entry.get("dye_masks", []) as Array
				if not dye_masks.is_empty():
					manifest.dye_mask_id = StringName(String(dye_masks[0]))
				if not catalog.add_manifest(manifest):
					issues.append("Pack 02 manifest rejected: %s" % texture_path)
	return issues

static func _staging_layer_for_name(value: String) -> int:
	match value.to_upper():
		"MOUNTTail", "MOUNTTAIL", "MOUNT_TAIL":
			return PaperDollV2Contract.RenderLayer.MOUNT_TAIL
		"CAPE":
			return PaperDollV2Contract.RenderLayer.CAPE
		"MOUNTBODY", "MOUNT_BODY":
			return PaperDollV2Contract.RenderLayer.MOUNT_BODY
		"BODY":
			return PaperDollV2Contract.RenderLayer.BODY
		"BOOTS":
			return PaperDollV2Contract.RenderLayer.BOOTS
		"ARMOR":
			return PaperDollV2Contract.RenderLayer.ARMOR
		"HAIR":
			return PaperDollV2Contract.RenderLayer.HAIR
		"HELMET":
			return PaperDollV2Contract.RenderLayer.HELMET
		"WEAPON":
			return PaperDollV2Contract.RenderLayer.WEAPON
		"SHIELD":
			return PaperDollV2Contract.RenderLayer.SHIELD
		"MOUNTHEAD", "MOUNT_HEAD":
			return PaperDollV2Contract.RenderLayer.MOUNT_HEAD
		"MOUNTBARDING", "MOUNT_BARDING":
			return PaperDollV2Contract.RenderLayer.MOUNT_BARDING
	return -1

static func _staging_symmetry_for_name(value: String) -> int:
	match value:
		"AUTHORED_LEFT":
			return PaperDollV2Contract.SymmetryPolicy.AUTHORED_LEFT
		"ASYMMETRIC_ALLOWED":
			return PaperDollV2Contract.SymmetryPolicy.ASYMMETRIC_ALLOWED
	return PaperDollV2Contract.SymmetryPolicy.MIRROR_RIGHT

func resolve_reference_recipe(
	gender: int,
	state: int,
	visual_id: StringName
) -> PaperDollV2Recipe:
	last_issues = PackedStringArray()
	var template := template_for(state, gender)
	if template == null:
		last_issues.append("missing reference body template")
		return null
	var manifest := find_visual(visual_id, PaperDollV2Contract.RenderLayer.BODY, state, gender)
	if manifest == null:
		last_issues.append("reference visual not found: %s" % visual_id)
		return null
	var recipe := PaperDollV2Recipe.new(gender, state)
	recipe.template = template
	recipe.is_reference_composite = true
	recipe.set_layer_texture(PaperDollV2Contract.RenderLayer.BODY, manifest.texture)
	var issues := recipe.validation_issues()
	if not issues.is_empty():
		last_issues.append_array(issues)
		return null
	return recipe

static func _register_reference_manifests(catalog: PaperDollV2Catalog) -> void:
	# These are calibrated complete boards derived from assets/doll/reference.
	# They are reference presets, not unisex equipment parts: gender is part of
	# the manifest key so a female preview can never silently reuse a male
	# silhouette (or the other way around).
	var cases: Array[Dictionary] = [
		{
			"visual_id": &"reference_body_on_foot",
			"state": PaperDollV2Contract.RenderState.ON_FOOT,
			"gender": PaperDollV2Contract.Gender.MALE,
			"file": "reference_match_body_on_foot_unisex.png",
		},
		{
			"visual_id": &"reference_armed_on_foot",
			"state": PaperDollV2Contract.RenderState.ON_FOOT,
			"gender": PaperDollV2Contract.Gender.MALE,
			"file": "reference_match_armed_on_foot_unisex.png",
		},
		{
			"visual_id": &"reference_body_mounted",
			"state": PaperDollV2Contract.RenderState.MOUNTED,
			"gender": PaperDollV2Contract.Gender.MALE,
			"file": "reference_match_body_mounted_unisex.png",
		},
		{
			"visual_id": &"reference_armed_mounted",
			"state": PaperDollV2Contract.RenderState.MOUNTED,
			"gender": PaperDollV2Contract.Gender.MALE,
			"file": "reference_match_armed_mounted_unisex.png",
		},
		{
			"visual_id": &"reference_female_body_on_foot",
			"state": PaperDollV2Contract.RenderState.ON_FOOT,
			"gender": PaperDollV2Contract.Gender.FEMALE,
			"file": "reference_match_female_body_on_foot.png",
		},
		{
			"visual_id": &"reference_female_armed_on_foot",
			"state": PaperDollV2Contract.RenderState.ON_FOOT,
			"gender": PaperDollV2Contract.Gender.FEMALE,
			"file": "reference_match_female_armed_on_foot.png",
		},
		{
			"visual_id": &"reference_female_body_mounted",
			"state": PaperDollV2Contract.RenderState.MOUNTED,
			"gender": PaperDollV2Contract.Gender.FEMALE,
			"file": "reference_match_female_body_mounted.png",
		},
		{
			"visual_id": &"reference_female_armed_mounted",
			"state": PaperDollV2Contract.RenderState.MOUNTED,
			"gender": PaperDollV2Contract.Gender.FEMALE,
			"file": "reference_match_female_armed_mounted.png",
		},
	]
	for entry: Dictionary in cases:
		var state: int = entry["state"]
		var gender: int = entry["gender"]
		var texture := _load_reference_texture(String(entry["file"]), state)
		if texture == null:
			catalog.last_issues.append("reference texture could not load: %s" % entry["file"])
			continue
		var template := catalog.template_for(state, gender)
		if template == null:
			catalog.last_issues.append("reference template missing for state=%d gender=%d" % [state, gender])
			continue
		var manifest := PaperDollV2AssetManifest.new()
		manifest.visual_id = entry["visual_id"]
		manifest.render_layer = PaperDollV2Contract.RenderLayer.BODY
		manifest.state = state
		manifest.gender_policy = PaperDollV2Contract.GenderPolicy.GENDERED
		manifest.gender = gender
		manifest.symmetry_policy = PaperDollV2Contract.SymmetryPolicy.AUTHORED_LEFT
		manifest.texture = texture
		manifest.source_path = REFERENCE_MATCH_DIR.path_join(String(entry["file"]))
		manifest.template_id = template.template_id
		manifest.normalization_version = &"reference_v1"
		manifest.required = false
		if not catalog.add_manifest(manifest):
			catalog.last_issues.append("reference manifest rejected: %s" % manifest.visual_id)

static func _load_reference_texture(file_name: String, state: int) -> Texture2D:
	var image := Image.load_from_file(ProjectSettings.globalize_path(REFERENCE_MATCH_DIR.path_join(file_name)))
	if image == null or image.is_empty():
		return null
	if state == PaperDollV2Contract.RenderState.MOUNTED:
		if image.get_width() != 512 or image.get_height() != 192:
			return null
		var padded := Image.create(512, 288, false, Image.FORMAT_RGBA8)
		padded.fill(Color.TRANSPARENT)
		# Convert each 64x64 source row into its own 64x96 cell.  Shifting
		# the whole 3-row sheet by 32 px would only align DOWN; UP and SIDE
		# would start at the top of their cells and fail the anchor contract.
		for row: int in range(PaperDollV2Contract.SOURCE_ROWS):
			padded.blit_rect(
				image,
				Rect2i(Vector2i(0, row * 64), Vector2i(512, 64)),
				Vector2i(0, row * 96 + 32)
			)
		image = padded
	return ImageTexture.create_from_image(image)

static func _load_png_texture(path: String) -> Texture2D:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)

static func _layer_for_visual_id(visual_id: StringName) -> int:
	var text := str(visual_id)
	if text.begins_with("body_"):
		return PaperDollV2Contract.RenderLayer.BODY
	if text.begins_with("boots_") or text.find("boots") >= 0:
		return PaperDollV2Contract.RenderLayer.BOOTS
	if text.find("_horse_tail_") >= 0:
		return PaperDollV2Contract.RenderLayer.MOUNT_TAIL
	if text.find("_horse_body_") >= 0:
		return PaperDollV2Contract.RenderLayer.MOUNT_BODY
	if text.find("_horse_head_") >= 0:
		return PaperDollV2Contract.RenderLayer.MOUNT_HEAD
	if text.find("barding") >= 0:
		return PaperDollV2Contract.RenderLayer.MOUNT_BARDING
	if text.find("helmet") >= 0 or text.find("sallet") >= 0:
		return PaperDollV2Contract.RenderLayer.HELMET
	if text.find("armor") >= 0:
		return PaperDollV2Contract.RenderLayer.ARMOR
	if text.find("hair") >= 0:
		return PaperDollV2Contract.RenderLayer.HAIR
	if text.find("cape") >= 0:
		return PaperDollV2Contract.RenderLayer.CAPE
	if text.find("shield") >= 0:
		return PaperDollV2Contract.RenderLayer.SHIELD
	if text.find("weapon") >= 0 or text.find("sword") >= 0 or text.find("spear") >= 0:
		return PaperDollV2Contract.RenderLayer.WEAPON
	return -1
