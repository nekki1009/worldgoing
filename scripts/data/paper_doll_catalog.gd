class_name PaperDollCatalog
extends Resource

@export var layer_visuals: Array[PaperDollLayerVisual] = []
@export var mount_visuals: Array[PaperDollMountVisual] = []
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

func default_visual_id(layer: int, gender: int, is_mounted: bool = false) -> StringName:
	if layer == PaperDollLayerVisual.RenderLayer.BODY:
		return default_male_body_visual_id \
			if gender == PaperDollLayerVisual.Gender.MALE \
			else default_female_body_visual_id
	if layer == PaperDollLayerVisual.RenderLayer.HAIR:
		return default_male_hair_visual_id \
			if gender == PaperDollLayerVisual.Gender.MALE \
			else default_female_hair_visual_id
	for visual: PaperDollLayerVisual in visuals_for_layer(layer):
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

func resolve_recipe(draft: PaperDollPreviewDraft) -> PaperDollRecipe:
	if not validate_draft(draft).is_empty():
		return null
	var result: PaperDollRecipe = PaperDollRecipe.new(draft.is_mounted)
	for layer: int in draft.selected_layers():
		if layer == PaperDollLayerVisual.RenderLayer.MOUNT_BARDING and not draft.is_mounted:
			continue
		var visual: PaperDollLayerVisual = find_visual(draft.visual_id_for(layer))
		result.set_layer_texture(layer, visual.resolve(draft.gender, draft.is_mounted))
	if draft.is_mounted:
		var mount: PaperDollMountVisual = find_mount(draft.mount_visual_id)
		result.set_layer_texture(
			PaperDollLayerVisual.RenderLayer.MOUNT_TAIL,
			mount.tail.resolve(draft.gender, true)
		)
		result.set_layer_texture(
			PaperDollLayerVisual.RenderLayer.MOUNT_BODY,
			mount.body.resolve(draft.gender, true)
		)
		result.set_layer_texture(
			PaperDollLayerVisual.RenderLayer.MOUNT_HEAD,
			mount.head.resolve(draft.gender, true)
		)
	return result

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

func issues_for_id(visual_id: StringName) -> PackedStringArray:
	var visual: PaperDollLayerVisual = find_visual(visual_id)
	if visual != null:
		return visual.validation_issues()
	var mount: PaperDollMountVisual = find_mount(visual_id)
	return mount.validation_issues() if mount != null else PackedStringArray(["unknown visual id"])

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
	return str(left.visual_id) < str(right.visual_id)

static func _mount_less(left: PaperDollMountVisual, right: PaperDollMountVisual) -> bool:
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
