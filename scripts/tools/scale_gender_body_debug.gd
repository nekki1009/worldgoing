extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for name: String in [
		"female_body_hair_twin_braids.png",
		"female_body_hair_long_side_ponytail.png",
		"female_body_hair_low_bun.png",
	]:
		var path := ProjectSettings.globalize_path(
			"res://.visual_captures/gendered_hair_lab/" + name
		)
		var image := Image.load_from_file(path)
		assert(image != null and not image.is_empty())
		image.convert(Image.FORMAT_RGBA8)
		image.resize(image.get_width() * 4, image.get_height() * 4, Image.INTERPOLATE_NEAREST)
		assert(image.save_png(path.replace(".png", "_x4.png")) == OK)
	quit()
