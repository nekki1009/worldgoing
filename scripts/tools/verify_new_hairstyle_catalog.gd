extends SceneTree

## Lightweight catalog/import gate for the four new assets.  This stays
## separate from the Composer visual gate so a slow editor import cannot make
## the data-layer result ambiguous.

const NEW_HAIR_IDS := [
	&"hair_long_side_ponytail",
	&"hair_crown_braid",
	&"hair_low_bun",
	&"hair_undercut_sweep",
]

func _init() -> void:
	var issues: PackedStringArray = PackedStringArray()
	var catalog_source: String = FileAccess.get_file_as_string(
		ProjectSettings.globalize_path("res://scripts/data/paper_doll_catalog.gd")
	)
	for hair_id: StringName in NEW_HAIR_IDS:
		if not catalog_source.contains('_alternate_visual(&"%s"' % hair_id):
			issues.append("catalog does not register: %s" % hair_id)
		var image_path: String = ProjectSettings.globalize_path(
			"res://assets/paper_doll/reference_parts/%s_on_foot_unisex.png" % hair_id
		)
		var image: Image = Image.load_from_file(image_path)
		if image == null or image.is_empty():
			issues.append("missing/unreadable sheet: %s" % hair_id)
		elif image.get_size() != Vector2i(512, 192):
			issues.append("wrong sheet size: %s = %s" % [hair_id, image.get_size()])
	if issues.is_empty():
		print("NEW HAIRSTYLE CATALOG PASS: %d IDs registered, 8x3 sheets readable" % NEW_HAIR_IDS.size())
		quit(0)
	else:
		for issue: String in issues:
			push_error(issue)
		print("NEW HAIRSTYLE CATALOG FAIL: %d issue(s)" % issues.size())
		quit(1)
