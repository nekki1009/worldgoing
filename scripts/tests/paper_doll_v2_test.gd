extends SceneTree

## Focused V2 contract test.  It uses small generated RGBA textures so the
## geometry and fixed-pool assertions do not depend on unfinished art packs.

var _catalog := PaperDollV2Catalog.new()

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_contract_constants()
	_test_generated_pack()
	_build_catalog()
	_test_bad_manifest_is_rejected()
	await _test_recipe_and_composer()
	_test_animation()
	_test_dependency_boundary()
	print("PAPER_DOLL_V2_TEST_PASS templates=%d manifests=%d layers=%d" % [
		_catalog.templates.size(),
		_catalog.manifests.size(),
		PaperDollV2Contract.RenderLayer.COUNT,
	])
	quit(0)

func _test_contract_constants() -> void:
	assert(PaperDollV2Contract.frame_size(PaperDollV2Contract.RenderState.ON_FOOT) == Vector2i(64, 64))
	assert(PaperDollV2Contract.frame_size(PaperDollV2Contract.RenderState.MOUNTED) == Vector2i(64, 96))
	assert(PaperDollV2Contract.sheet_size(PaperDollV2Contract.RenderState.ON_FOOT) == Vector2i(512, 192))
	assert(PaperDollV2Contract.sheet_size(PaperDollV2Contract.RenderState.MOUNTED) == Vector2i(512, 288))
	assert(PaperDollV2Contract.anchor_px(PaperDollV2Contract.RenderState.ON_FOOT) == Vector2i(32, 56))
	assert(PaperDollV2Contract.anchor_px(PaperDollV2Contract.RenderState.MOUNTED) == Vector2i(32, 88))
	assert(PaperDollV2Contract.source_row_for(PaperDollV2Contract.Facing.LEFT) == PaperDollV2Contract.Facing.RIGHT)
	assert(PaperDollV2Contract.z_index_for(PaperDollV2Contract.RenderLayer.BOOTS, PaperDollV2Contract.Facing.DOWN) == 11)
	assert(PaperDollV2Contract.z_index_for(PaperDollV2Contract.RenderLayer.WEAPON, PaperDollV2Contract.Facing.LEFT) == -1)
	assert(PaperDollV2Contract.z_index_for(PaperDollV2Contract.RenderLayer.SHIELD, PaperDollV2Contract.Facing.RIGHT) == -2)

func _test_generated_pack() -> void:
	var generated := PaperDollV2Catalog.load_generated_pack()
	assert(generated.last_issues.is_empty(), "generated pack load: %s" % generated.last_issues)
	assert(generated.templates.size() == 4, "generated templates=%d" % generated.templates.size())
	assert(generated.manifests.size() >= 60, "generated manifests=%d" % generated.manifests.size())
	assert(PaperDollV2Validator.validate_catalog(generated).is_empty(), "generated catalog: %s" % PaperDollV2Validator.validate_catalog(generated))
	var mounted_body := generated.find_visual(
		&"body_male_default_mounted_unisex",
		PaperDollV2Contract.RenderLayer.BODY,
		PaperDollV2Contract.RenderState.MOUNTED,
		PaperDollV2Contract.Gender.MALE
	)
	assert(mounted_body != null)
	assert(Vector2i(mounted_body.texture.get_width(), mounted_body.texture.get_height()) == Vector2i(512, 288))
	var reference_body := generated.find_visual(
		&"reference_body_on_foot",
		PaperDollV2Contract.RenderLayer.BODY,
		PaperDollV2Contract.RenderState.ON_FOOT,
		PaperDollV2Contract.Gender.MALE
	)
	assert(reference_body != null, "calibrated reference preset is missing")
	var reference_mounted := generated.find_visual(
		&"reference_body_mounted",
		PaperDollV2Contract.RenderLayer.BODY,
		PaperDollV2Contract.RenderState.MOUNTED,
		PaperDollV2Contract.Gender.MALE
	)
	assert(reference_mounted != null)
	assert(Vector2i(reference_mounted.texture.get_width(), reference_mounted.texture.get_height()) == Vector2i(512, 288))
	for state: int in [PaperDollV2Contract.RenderState.ON_FOOT, PaperDollV2Contract.RenderState.MOUNTED]:
		var female_id := &"reference_female_body_mounted" if state == PaperDollV2Contract.RenderState.MOUNTED else &"reference_female_body_on_foot"
		var female_reference := generated.find_visual(
			female_id,
			PaperDollV2Contract.RenderLayer.BODY,
			state,
			PaperDollV2Contract.Gender.FEMALE
		)
		assert(female_reference != null, "female calibrated reference preset is missing: %s" % female_id)
		assert(Vector2i(female_reference.texture.get_width(), female_reference.texture.get_height()) == PaperDollV2Contract.sheet_size(state))

func _build_catalog() -> void:
	for gender: int in [PaperDollV2Contract.Gender.MALE, PaperDollV2Contract.Gender.FEMALE]:
		for state: int in [PaperDollV2Contract.RenderState.ON_FOOT, PaperDollV2Contract.RenderState.MOUNTED]:
			var gender_name := PaperDollV2Contract.gender_name(gender)
			var state_name := PaperDollV2Contract.state_name(state)
			var template := PaperDollV2BodyTemplate.new()
			template.template_id = StringName("body_%s_%s" % [gender_name, state_name])
			template.gender = gender
			template.state = state
			template.anchor_px = PaperDollV2Contract.anchor_px(state)
			template.foot_or_hoof_line = template.anchor_px.y
			template.texture = _make_sheet(state, Color("e8a15a"), true)
			assert(template.validation_issues().is_empty(), "template rejected: %s" % template.template_id)
			assert(_catalog.add_template(template))

			var body := _manifest(
				StringName("body_%s_%s" % [gender_name, state_name]),
				PaperDollV2Contract.RenderLayer.BODY,
				state,
				PaperDollV2Contract.GenderPolicy.GENDERED,
				gender,
				template.texture,
				template.template_id,
				true
			)
			assert(_catalog.add_manifest(body))

	for state: int in [PaperDollV2Contract.RenderState.ON_FOOT, PaperDollV2Contract.RenderState.MOUNTED]:
		var state_name := PaperDollV2Contract.state_name(state)
		var template := _catalog.template_for(state, PaperDollV2Contract.Gender.MALE)
		for layer: int in [
			PaperDollV2Contract.RenderLayer.BOOTS,
			PaperDollV2Contract.RenderLayer.ARMOR,
			PaperDollV2Contract.RenderLayer.HAIR,
			PaperDollV2Contract.RenderLayer.CAPE,
			PaperDollV2Contract.RenderLayer.MOUNT_BARDING,
		]:
			if PaperDollV2Contract.is_mount_layer(layer) and state != PaperDollV2Contract.RenderState.MOUNTED:
				continue
			var visual_id := StringName("%s_%s" % [PaperDollV2Contract.layer_name(layer).to_lower(), state_name])
			var part := _manifest(
				visual_id,
				layer,
				state,
				PaperDollV2Contract.GenderPolicy.UNISEX,
				PaperDollV2Contract.Gender.MALE,
				_make_sheet(state, _layer_color(layer), false),
				template.template_id,
				false
			)
			assert(_catalog.add_manifest(part), "part rejected: %s" % visual_id)

		if state == PaperDollV2Contract.RenderState.MOUNTED:
			for layer: int in [
				PaperDollV2Contract.RenderLayer.MOUNT_TAIL,
				PaperDollV2Contract.RenderLayer.MOUNT_BODY,
				PaperDollV2Contract.RenderLayer.MOUNT_HEAD,
			]:
				var mount_id := StringName("%s_%s" % [PaperDollV2Contract.layer_name(layer).to_lower(), state_name])
				var mount_part := _manifest(
					mount_id,
					layer,
					state,
					PaperDollV2Contract.GenderPolicy.UNISEX,
					PaperDollV2Contract.Gender.MALE,
					_make_sheet(state, _layer_color(layer), false),
					template.template_id,
					false
				)
				assert(_catalog.add_manifest(mount_part), "mount part rejected: %s" % mount_id)

	assert(_catalog.validation_issues().is_empty(), "catalog issues: %s" % _catalog.validation_issues())

func _test_bad_manifest_is_rejected() -> void:
	var bad := PaperDollV2AssetManifest.new()
	bad.visual_id = &"bad_size"
	bad.render_layer = PaperDollV2Contract.RenderLayer.ARMOR
	bad.state = PaperDollV2Contract.RenderState.MOUNTED
	bad.template_id = &"body_male_mounted"
	bad.texture = _make_sheet(PaperDollV2Contract.RenderState.ON_FOOT, Color("ffffff"), false)
	assert(not bad.validation_issues(_catalog.template_for(
		PaperDollV2Contract.RenderState.MOUNTED,
		PaperDollV2Contract.Gender.MALE
	)).is_empty())

func _test_recipe_and_composer() -> void:
	var on_foot_selection := {
		PaperDollV2Contract.RenderLayer.BOOTS: &"boots_on_foot",
		PaperDollV2Contract.RenderLayer.ARMOR: &"armor_on_foot",
		PaperDollV2Contract.RenderLayer.HAIR: &"hair_on_foot",
		PaperDollV2Contract.RenderLayer.CAPE: &"cape_on_foot",
	}
	var on_foot := _catalog.resolve_recipe(
		PaperDollV2Contract.Gender.MALE,
		PaperDollV2Contract.RenderState.ON_FOOT,
		on_foot_selection,
		&"body_male_on_foot"
	)
	assert(on_foot != null, "on-foot recipe: %s" % _catalog.last_issues)

	var mounted_selection := {
		PaperDollV2Contract.RenderLayer.BOOTS: &"boots_mounted",
		PaperDollV2Contract.RenderLayer.ARMOR: &"armor_mounted",
		PaperDollV2Contract.RenderLayer.HAIR: &"hair_mounted",
		PaperDollV2Contract.RenderLayer.CAPE: &"cape_mounted",
		PaperDollV2Contract.RenderLayer.MOUNT_TAIL: &"mounttail_mounted",
		PaperDollV2Contract.RenderLayer.MOUNT_BODY: &"mountbody_mounted",
		PaperDollV2Contract.RenderLayer.MOUNT_HEAD: &"mounthead_mounted",
	}
	var mounted := _catalog.resolve_recipe(
		PaperDollV2Contract.Gender.MALE,
		PaperDollV2Contract.RenderState.MOUNTED,
		mounted_selection,
		&"body_male_mounted"
	)
	assert(mounted != null, "mounted recipe: %s" % _catalog.last_issues)

	var root := Node2D.new()
	get_root().add_child(root)
	var composer := PaperDollV2Composer.new()
	root.add_child(composer)
	await process_frame
	assert(composer.apply_recipe(on_foot), composer.last_error)
	assert(composer.sprite_count() == PaperDollV2Contract.RenderLayer.COUNT)
	assert(composer.frame_size() == Vector2i(64, 64))
	assert(composer.anchor_px() == Vector2i(32, 56))
	assert(composer.visible_sprite_count() == 5)
	assert(composer.sprite_for(PaperDollV2Contract.RenderLayer.BODY).offset == Vector2(-32, -56))
	assert(composer.update_frame(PaperDollV2Contract.Facing.LEFT, 3))
	for layer: int in range(PaperDollV2Contract.RenderLayer.COUNT):
		var sprite := composer.sprite_for(layer)
		assert(sprite.frame_coords == Vector2i(3, PaperDollV2Contract.Facing.RIGHT))
		assert(sprite.flip_h)
		assert(sprite.z_index == PaperDollV2Contract.z_index_for(layer, PaperDollV2Contract.Facing.LEFT))
	var hair_before := composer.sprite_for(PaperDollV2Contract.RenderLayer.HAIR).texture
	var body_before := composer.sprite_for(PaperDollV2Contract.RenderLayer.BODY).texture
	assert(composer.set_dye(PaperDollV2Composer.DyeGroup.HAIR_BROWS, Color("d13f8f")))
	assert(composer.sprite_for(PaperDollV2Contract.RenderLayer.HAIR).texture != hair_before)
	assert(composer.sprite_for(PaperDollV2Contract.RenderLayer.BODY).texture == body_before)
	# Every action clip drives the same Composer entry point.  This catches a
	# future per-layer timer or frame-range regression without relying on a UI.
	for action: int in range(PaperDollV2Animation.Action.COUNT):
		for frame_x: int in PaperDollV2Animation.frames_for(action):
			assert(composer.update_frame(PaperDollV2Contract.Facing.DOWN, frame_x))
			for layer: int in range(PaperDollV2Contract.RenderLayer.COUNT):
				var action_sprite := composer.sprite_for(layer)
				assert(action_sprite.frame_coords == Vector2i(frame_x, PaperDollV2Contract.Facing.DOWN))

	assert(composer.apply_recipe(mounted), composer.last_error)
	assert(composer.render_state == PaperDollV2Contract.RenderState.MOUNTED)
	assert(composer.frame_size() == Vector2i(64, 96))
	assert(composer.anchor_px() == Vector2i(32, 88))
	assert(composer.sprite_for(PaperDollV2Contract.RenderLayer.BODY).offset == Vector2(-32, -88))
	assert(composer.sprite_for(PaperDollV2Contract.RenderLayer.MOUNT_BODY).visible)
	assert(composer.visible_sprite_count() == 8)
	root.queue_free()

func _test_animation() -> void:
	for action: int in range(PaperDollV2Animation.Action.COUNT):
		var sequence := PaperDollV2Animation.frames_for(action)
		assert(not sequence.is_empty(), "empty action sequence: %d" % action)
		for frame_x: int in sequence:
			assert(frame_x >= 0 and frame_x < PaperDollV2Contract.FRAME_COLUMNS)
	assert(PaperDollV2Animation.frames_for(PaperDollV2Animation.Action.WALK).size() == 8)
	assert(PaperDollV2Animation.next_frame(PaperDollV2Animation.Action.WALK, 7) == 0)
	assert(PaperDollV2Animation.next_frame(PaperDollV2Animation.Action.ATTACK, 1) == 3)
	assert(PaperDollV2Animation.default_fps(PaperDollV2Animation.Action.RUN) == 12.0)

func _test_dependency_boundary() -> void:
	var composer_source := FileAccess.get_file_as_string("res://scripts/ui/paper_doll_v2_composer.gd")
	assert(composer_source.find("AnimatedSprite2D") == -1)
	assert(composer_source.find("func _process") == -1)
	var recipe_source := FileAccess.get_file_as_string("res://scripts/data/paper_doll_v2_recipe.gd")
	assert(recipe_source.find("GameSession") == -1)
	assert(recipe_source.find("Persistence") == -1)

func _manifest(
		visual_id: StringName,
		layer: int,
		state: int,
		gender_policy: int,
		gender: int,
		texture: Texture2D,
		template_id: StringName,
		required: bool
	) -> PaperDollV2AssetManifest:
	var result := PaperDollV2AssetManifest.new()
	result.visual_id = visual_id
	result.render_layer = layer
	result.state = state
	result.gender_policy = gender_policy
	result.gender = gender
	result.template_id = template_id
	result.texture = texture
	result.required = required
	return result

func _make_sheet(state: int, color: Color, face: bool) -> ImageTexture:
	var size := PaperDollV2Contract.sheet_size(state)
	var cell := PaperDollV2Contract.frame_size(state)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for row: int in range(PaperDollV2Contract.SOURCE_ROWS):
		for frame_x: int in range(PaperDollV2Contract.FRAME_COLUMNS):
			var origin := Vector2i(frame_x * cell.x, row * cell.y)
			var top := 8 if state == PaperDollV2Contract.RenderState.ON_FOOT else 20
			var bottom := cell.y - 8
			for y: int in range(top, bottom):
				for x: int in range(14, 50):
					var inside := absf(float(x - 32)) <= 18.0 - absf(float(y - top)) * 0.12
					if inside:
						image.set_pixel(origin.x + x, origin.y + y, color)
			if face:
				var eye_y := top + 8
				for eye_x in [27, 36]:
					image.set_pixel(origin.x + eye_x, origin.y + eye_y, Color("1b1520"))
					image.set_pixel(origin.x + eye_x + 1, origin.y + eye_y, Color("1b1520"))
	return ImageTexture.create_from_image(image)

func _layer_color(layer: int) -> Color:
	match layer:
		PaperDollV2Contract.RenderLayer.BOOTS:
			return Color("3b4558")
		PaperDollV2Contract.RenderLayer.ARMOR:
			return Color("aebbd0")
		PaperDollV2Contract.RenderLayer.HAIR:
			return Color("e8e9ef")
		PaperDollV2Contract.RenderLayer.CAPE:
			return Color("263653")
		PaperDollV2Contract.RenderLayer.MOUNT_TAIL:
			return Color("6b4327")
		PaperDollV2Contract.RenderLayer.MOUNT_BODY:
			return Color("986136")
		PaperDollV2Contract.RenderLayer.MOUNT_HEAD:
			return Color("b27945")
		PaperDollV2Contract.RenderLayer.MOUNT_BARDING:
			return Color("6b2631")
		_:
			return Color("ffffff")
