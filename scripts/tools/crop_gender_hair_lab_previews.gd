extends SceneTree

const IDS: Array[StringName] = [
	&"short_spiky", &"high_ponytail", &"bob", &"twin_braids",
	&"long_side_ponytail", &"crown_braid", &"low_bun", &"undercut_sweep",
]
const INPUT_DIR := "res://.visual_captures/gendered_hair_lab"
const OUTPUT_PATH := "res://.visual_captures/gendered_hair_lab/female_styles_contact.png"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var tile_size := Vector2i(220, 260)
	var contact := Image.create(tile_size.x * 4, tile_size.y * 2, false, Image.FORMAT_RGBA8)
	contact.fill(Color("111722"))
	for index: int in range(IDS.size()):
		var source := Image.load_from_file(ProjectSettings.globalize_path(
			INPUT_DIR.path_join("female_hair_%s.png" % IDS[index])
		))
		assert(source != null and not source.is_empty(), "Missing preview %s" % IDS[index])
		source.convert(Image.FORMAT_RGBA8)
		# Character position is stable in the production lab capture.  The crop
		# removes controls so the hairstyle silhouette can be inspected directly.
		var crop := source.get_region(Rect2i(1180, 300, 400, 520))
		crop.resize(tile_size.x, tile_size.y, Image.INTERPOLATE_NEAREST)
		contact.blit_rect(crop, Rect2i(Vector2i.ZERO, tile_size),
			Vector2i((index % 4) * tile_size.x, (index / 4) * tile_size.y))
	var output := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	assert(contact.save_png(output) == OK, "Could not save contact sheet")
	print("GENDERED_HAIR_CONTACT_PASS path=%s" % output)
	quit()
