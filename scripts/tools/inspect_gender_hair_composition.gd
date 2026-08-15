extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var body := _load("reference_match/reference_match_body_on_foot_unisex.png")
	var hair := _load("reference_parts/hair_twin_braids_on_foot_female.png")
	var recipe := PaperDollRecipe.new(false, PaperDollAnimation.Action.IDLE)
	recipe.set_layer_texture(PaperDollLayerVisual.RenderLayer.BODY, body)
	recipe.reference_hair_texture = hair
	recipe.reference_hair_is_hair_only = true
	var composed := PaperDollComposer.build_reference_body_texture(recipe)
	assert(composed != null)
	assert(composed.get_image().save_png(ProjectSettings.globalize_path(
		"res://.visual_captures/gendered_hair_lab/inspect_composed_twin_braids.png"
	)) == OK)
	var frame0 := composed.get_image().get_region(Rect2i(Vector2i.ZERO, Vector2i(64, 64)))
	frame0.resize(512, 512, Image.INTERPOLATE_NEAREST)
	assert(frame0.save_png(ProjectSettings.globalize_path(
		"res://.visual_captures/gendered_hair_lab/inspect_twin_frame0_x8.png"
	)) == OK)
	var hair_image := PaperDollComposer._reference_hair_image(hair, true)
	var body_image := body.get_image()
	var composed_image := composed.get_image()
	var diff := Image.create(512, 192, false, Image.FORMAT_RGBA8)
	diff.fill(Color.TRANSPARENT)
	for y: int in range(192):
		for x: int in range(512):
			if body_image.get_pixel(x, y) != composed_image.get_pixel(x, y):
				diff.set_pixel(x, y, Color(1.0, 0.1, 0.1, 1.0))
	diff.resize(1024, 384, Image.INTERPOLATE_NEAREST)
	assert(diff.save_png(ProjectSettings.globalize_path(
		"res://.visual_captures/gendered_hair_lab/inspect_twin_diff_x2.png"
	)) == OK)
	for row: int in range(PaperDollLayerVisual.SOURCE_ROWS):
		var frame_x := 0
		var origin := Vector2i(0, row * PaperDollLayerVisual.FRAME_SIZE.y)
		var body_frame := body.get_image().get_region(Rect2i(origin, PaperDollLayerVisual.FRAME_SIZE))
		var hair_frame := hair_image.get_region(Rect2i(origin, PaperDollLayerVisual.FRAME_SIZE))
		var source_rect := hair_frame.get_used_rect()
		var target := PaperDollComposer._reference_hair_target_rect(
			body_frame, true, source_rect.size, false
		)
		var source_alpha_below_head := 0
		var source_alpha_below_26 := 0
		var changed_below_head := 0
		var changed_below_26 := 0
		var changed_min := Vector2i(64, 64)
		var changed_max := Vector2i(-1, -1)
		for yy: int in range(PaperDollLayerVisual.FRAME_SIZE.y):
			for xx: int in range(PaperDollLayerVisual.FRAME_SIZE.x):
				var source_pixel: Color = hair_frame.get_pixel(xx, yy)
				if source_pixel.a > 0.05 and yy > 26:
					source_alpha_below_26 += 1
				if source_pixel.a > 0.05 and yy >= 27:
					source_alpha_below_head += 1
				var before: Color = body_image.get_pixel(frame_x * 64 + xx, row * 64 + yy)
				var after: Color = composed_image.get_pixel(frame_x * 64 + xx, row * 64 + yy)
				if before != after and yy > 26:
					changed_below_26 += 1
					changed_min.x = mini(changed_min.x, xx)
					changed_min.y = mini(changed_min.y, yy)
					changed_max.x = maxi(changed_max.x, xx)
					changed_max.y = maxi(changed_max.y, yy)
				if before != after and yy >= 27:
					changed_below_head += 1
		print("row=%d source=%s body_base=%s target=%s alpha_tail=%s source_below_26=%d changed_below_26=%d changed_below_head=%d changed_rect=%s..%s" % [
			row,
			source_rect,
			PaperDollComposer._reference_hair_rect(body_frame, false),
			target,
			hair_frame.get_pixel(32, 45).a,
			source_alpha_below_26,
			changed_below_26,
			changed_below_head,
			changed_min,
			changed_max,
		])
	quit()

func _load(relative_path: String) -> Texture2D:
	var image := Image.load_from_file(ProjectSettings.globalize_path(
		"res://assets/paper_doll/" + relative_path
	))
	assert(image != null and not image.is_empty())
	return ImageTexture.create_from_image(image)
