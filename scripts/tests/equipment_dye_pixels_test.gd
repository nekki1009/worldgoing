extends SceneTree
## Exact unscaled GPU pixel isolation using the formal base/bow/crossbow assets.
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const DyeAtlas = preload("res://scripts/terrain_lab/terrain_army_dye_atlas.gd")
const OUT := "res://output/equipment_dye_20260914/pixels"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	assert(DisplayServer.get_name() != "headless")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var report := []
	for key: String in ["base", "bow_01", "crossbow_01"]:
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Atlas.BASE_MANIFEST if key == "base" else Atlas.RangedAtlas.ROOT + "/" + key + "/manifest.json"))
		var appearance: Dictionary = manifest.appearance.duplicate(true)
		var frame := Atlas.frame(appearance, "idle", "down", 0.0)
		# The base atlas is selected by TerrainArmy rather than Atlas.frame.
		if key == "base":
			var source := AtlasTexture.new()
			source.atlas = load(manifest.atlas.resource_path)
			var rectangle: Dictionary = manifest.frames[0].rect
			source.region = Rect2(rectangle.x, rectangle.y, rectangle.w, rectangle.h)
			frame = {"texture": source}
		assert(not frame.is_empty())
		var texture := frame.texture as AtlasTexture
		assert(texture != null)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(texture.get_size())
		viewport.disable_3d = true
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		viewport.add_child(sprite)
		var original := await _pixels(viewport)
		appearance.equipment_dyes = {"armor": "396fbbff", "boots": "26384eff"}
		assert(DyeAtlas.apply(sprite, appearance))
		for slot: String in DyeAtlas.Dye.SLOTS: sprite.set_instance_shader_parameter(slot + "_dye", Vector4.ZERO)
		var disabled := await _pixels(viewport)
		assert(original.get_data() == disabled.get_data(), "Disabled dye shader must preserve every original pixel: " + key)
		sprite.remove_meta("equipment_dye_appearance")
		assert(DyeAtlas.apply(sprite, appearance))
		var dyed := await _pixels(viewport)
		var mask := Image.load_from_file(DyeAtlas.ROOT + "/" + key + ".png").get_region(Rect2i(texture.region))
		var before := original.get_data()
		var after := dyed.get_data()
		var changed := 0
		var protected := 0
		for y in range(viewport.size.y):
			for x in range(viewport.size.x):
				var offset := (y * viewport.size.x + x) * 4
				assert(before[offset + 3] == after[offset + 3], "Dye must not alter alpha")
				var slot := roundi(mask.get_pixel(x, y).r * 255.0)
				var equal := before[offset] == after[offset] and before[offset + 1] == after[offset + 1] and before[offset + 2] == after[offset + 2]
				if slot not in [2, 3]:
					assert(equal, "Dye leaked into a protected or unselected pixel: " + key)
					if before[offset + 3] > 0: protected += 1
				if not equal: changed += 1
		assert(changed > 20 and protected > 20)
		assert(dyed.save_png(OUT + "/" + key + ".png") == OK)
		report.append({"atlas": key, "changed_pixels": changed, "protected_visible_pixels": protected, "disabled_exact": true, "alpha_exact": true})
		viewport.queue_free()
		await process_frame
	var file := FileAccess.open(OUT + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("EQUIPMENT DYE PIXELS PASS: 3 formal atlases, exact disabled output, exact protected pixels and alpha; actual dye changes verified")
	quit()

func _pixels(viewport: SubViewport) -> Image:
	for tick in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image()
	result.convert(Image.FORMAT_RGBA8)
	return result
