extends SceneTree

func _init() -> void:
	var catalog: PaperDollCatalog = PaperDollCatalog.create_art_gate1_catalog()
	var draft := PaperDollPreviewDraft.new()
	draft.set_visual(PaperDollLayerVisual.RenderLayer.BODY, &"body_male_default")
	draft.set_visual(PaperDollLayerVisual.RenderLayer.ARMOR, &"artgate1_armor")
	draft.set_visual(PaperDollLayerVisual.RenderLayer.HAIR, &"hair_male_default")
	draft.set_visual(PaperDollLayerVisual.RenderLayer.CAPE, &"artgate1_cape")
	draft.set_visual(PaperDollLayerVisual.RenderLayer.WEAPON, &"artgate1_weapon")
	draft.set_visual(PaperDollLayerVisual.RenderLayer.SHIELD, &"artgate1_shield")
	draft.action = PaperDollAnimation.Action.WALK
	var recipe := catalog.resolve_recipe(draft)
	var composer := PaperDollComposer.new()
	get_root().add_child(composer)
	composer.apply_recipe(recipe)
	var body_before: Color = composer.sprite_for(PaperDollLayerVisual.RenderLayer.BODY).texture.get_image().get_pixel(27, 13)
	composer.set_dye(PaperDollComposer.DyeGroup.HAIR_BROWS, Color("d13f8f"))
	var body_after: Color = composer.sprite_for(PaperDollLayerVisual.RenderLayer.BODY).texture.get_image().get_pixel(27, 13)
	print("DYE BODY PIXEL before=%s after=%s changed=%s" % [body_before, body_after, body_before != body_after])
	composer.queue_free()
	for visual_id: StringName in [&"body_male_default", &"hair_male_default", &"artgate1_armor", &"artgate1_cape", &"artgate1_weapon"]:
		var visual: PaperDollLayerVisual = catalog.find_visual(visual_id)
		print("ACTION INSPECT id=%s visual=%s issues=%s" % [visual_id, visual != null, visual.validation_issues() if visual != null else PackedStringArray(["missing"])])
		if visual == null:
			continue
		print("  base=%s walk=%s walk_has=%s" % [
			visual.on_foot_unisex.resource_path if visual.on_foot_unisex != null else "<null>",
			visual.on_foot_action_sheets[PaperDollAnimation.Action.WALK].resource_path if visual.has_action_sheet(false, PaperDollAnimation.Action.WALK) else "<none>",
			visual.has_action_sheet(false, PaperDollAnimation.Action.WALK),
		])
		if visual_id == &"body_male_default" and visual != null and visual.has_action_sheet(false, PaperDollAnimation.Action.WALK):
			var image: Image = visual.on_foot_action_sheets[PaperDollAnimation.Action.WALK].get_image()
			for row: int in range(3):
				var used: PackedStringArray = []
				for frame_x: int in range(8):
					var frame: Image = image.get_region(Rect2i(frame_x * 64, row * 64, 64, 64))
					used.append(str(frame.get_used_rect()))
				print("  body row=%d %s" % [row, " | ".join(used)])
		var raw: Image = Image.load_from_file(ProjectSettings.globalize_path("res://assets/paper_doll/action_parts/walk_on_foot_body.png"))
		print("  raw body format=%s size=%s row1f3=%s row1f6=%s" % [raw.get_format(), raw.get_size(), raw.get_region(Rect2i(192, 64, 64, 64)).get_used_rect(), raw.get_region(Rect2i(384, 64, 64, 64)).get_used_rect()])
		var green_count: int = 0
		for y: int in range(raw.get_height()):
			for x: int in range(raw.get_width()):
				var pixel: Color = raw.get_pixel(x, y)
				if pixel.a > 0.05 and pixel.g > pixel.r * 1.2 and pixel.g > pixel.b * 1.15:
					green_count += 1
		print("  raw body green_like_pixels=%d" % green_count)
		var authored_path := ProjectSettings.globalize_path(
			"res://assets/paper_doll/action_parts/walk_on_foot_%s.png" % visual_id.replace("artgate1_", "").replace("_male_default", "")
		)
		if FileAccess.file_exists(authored_path):
			var authored: Image = Image.load_from_file(authored_path)
			if authored != null and not authored.is_empty():
				var hits: PackedStringArray = []
				for y: int in range(authored.get_height()):
					for x: int in range(authored.get_width()):
						var pixel: Color = authored.get_pixel(x, y)
						if pixel.a > 0.05 and pixel.g > pixel.r * 1.18 and pixel.g > pixel.b * 1.12:
							if hits.size() < 40:
								hits.append("(%d,%d) rgba=%.3f,%.3f,%.3f,%.3f" % [x, y, pixel.r, pixel.g, pixel.b, pixel.a])
				print("  authored=%s green_like=%d first=%s" % [authored_path, hits.size(), " | ".join(hits)])
	quit()
