extends SceneTree

## Builds accepted alternate visuals from the approved reference-derived sheets.
##
## The first ImageGen alternate board is retained under art_source as a staged
## source, but its independently cropped silhouettes did not share the
## reference anchor. It is therefore never attached to the live Catalog.
## These variants preserve the approved alpha geometry byte-for-byte and only
## change palette, which makes a second selectable appearance safe to validate.
## The braided hairstyle is deliberately excluded: it is a real silhouette
## extracted by build_alternate_hairstyle_pack.gd, not a recoloured default.

const REFERENCE_DIR := "res://assets/paper_doll/reference_parts"
const OUTPUT_DIR := "res://assets/paper_doll/reference_parts"
const SHEET_SIZE := Vector2i(512, 192)
const VARIANTS := [
	{"id": "alt_bronze_armor", "base": "artgate1_armor", "hue": 0.075, "saturation": 0.66, "value": 0.82},
	{"id": "alt_teal_cape", "base": "artgate1_cape", "hue": 0.49, "saturation": 0.64, "value": 0.72},
	{"id": "alt_bronze_sword", "base": "artgate1_weapon", "hue": 0.075, "saturation": 0.70, "value": 0.86},
	{"id": "alt_teal_shield", "base": "artgate1_shield", "hue": 0.49, "saturation": 0.64, "value": 0.76},
	# Use a deep blue-teal rather than the reference magenta-red key range; the
	# QA gate reserves that hue band for source-board residue.
	{"id": "alt_dark_barding", "base": "artgate1_barding", "hue": 0.64, "saturation": 0.52, "value": 0.56},
]
const MOUNT_VARIANTS := [
	{"id": "alt_dark_bay_horse_head", "base": "artgate1_horse_head", "hue": 0.055, "saturation": 0.70, "value": 0.62},
	{"id": "alt_dark_bay_horse_body", "base": "artgate1_horse_body", "hue": 0.055, "saturation": 0.70, "value": 0.62},
	{"id": "alt_dark_bay_horse_tail", "base": "artgate1_horse_tail", "hue": 0.055, "saturation": 0.70, "value": 0.62},
]

func _init() -> void:
	var error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	if error != OK:
		push_error("Could not create alternate output directory: %s" % error)
		quit(1)
		return
	for variant: Dictionary in VARIANTS:
		var is_barding: bool = str(variant["id"]) == "alt_dark_barding"
		if (not is_barding and not _write_variant(variant, false)) or not _write_variant(variant, true):
			quit(1)
			return
	for variant: Dictionary in MOUNT_VARIANTS:
		if not _write_variant(variant, true):
			quit(1)
			return
	print("ALTERNATE PAPER DOLL PACK PASS: geometry-locked palette variants written")
	quit(0)

func _write_variant(variant: Dictionary, mounted: bool) -> bool:
	var id: String = str(variant["id"])
	var base: String = str(variant["base"])
	var base_file: String = "%s_%s_unisex.png" % [base, "mounted" if mounted else "on_foot"]
	var source_path: String = ProjectSettings.globalize_path(REFERENCE_DIR.path_join(base_file))
	var source: Image = Image.load_from_file(source_path)
	if source == null or source.is_empty():
		push_error("Missing approved base sheet for alternate %s: %s" % [id, source_path])
		return false
	if source.get_size() != SHEET_SIZE:
		push_error("Base sheet for %s has invalid size %s" % [id, source.get_size()])
		return false
	if source.get_format() != Image.FORMAT_RGBA8:
		source.convert(Image.FORMAT_RGBA8)
	var tinted: Image = _tint_sheet(source, float(variant["hue"]), float(variant["saturation"]), float(variant["value"]))
	var file_name: String = "%s_%s_unisex.png" % [id, "mounted" if mounted else "on_foot"]
	return tinted.save_png(ProjectSettings.globalize_path(OUTPUT_DIR.path_join(file_name))) == OK

func _tint_sheet(source: Image, hue: float, saturation: float, value_scale: float) -> Image:
	var result: Image = source.duplicate()
	for y: int in range(result.get_height()):
		for x: int in range(result.get_width()):
			var pixel: Color = result.get_pixel(x, y)
			if pixel.a <= 0.05:
				continue
			var luminance: float = pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114
			var value: float = clampf(luminance * value_scale / 0.72, 0.0, 1.0)
			var sat: float = clampf(saturation * (0.55 + pixel.s * 0.45), 0.04, 1.0)
			result.set_pixel(x, y, Color.from_hsv(hue, sat, value, pixel.a))
	return result
