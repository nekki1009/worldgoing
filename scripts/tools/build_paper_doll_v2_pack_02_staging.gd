extends SceneTree

## Creates the isolated Pack 02 integration fixture.
##
## These files are deliberately copied from already-normalized, passed V2
## alternates (with gendered hair padded to the mounted contract).  They are
## not admitted to assets/paper_doll/v2/manifest.json and are labelled as
## staging aliases until the new artwork replaces them and passes the visual
## gate.  This gives the UI/composer a complete 11-slot integration surface
## without touching the accepted reference set.

const OUTPUT_DIR := "res://assets/paper_doll/v2/staging/pack_02"
const SOURCE_DIR := "res://assets/paper_doll/v2/parts"
const FRAME_SIZE := Vector2i(64, 64)
const MOUNTED_FRAME_SIZE := Vector2i(64, 96)
const FRAME_COLUMNS := 8
const SOURCE_ROWS := 3

var _files_written: Array[String] = []
var _source_aliases: Dictionary = {}
var _failures: PackedStringArray = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	var error := DirAccess.make_dir_recursive_absolute(output_path)
	if error != OK:
		_failures.append("could not create staging directory: %s" % error_string(error))
	else:
		_build()
	_write_report(output_path)
	if _failures.is_empty():
		print("PAPER_DOLL_V2_PACK02_STAGING_PASS files=%d" % _files_written.size())
		quit(0)
	else:
		for failure: String in _failures:
			push_error("PAPER_DOLL_V2_PACK02_STAGING_FAIL: %s" % failure)
		quit(1)

func _build() -> void:
	# Hair is the only gendered Pack 02 entry.  The source sheets are on-foot
	# 512x192 files; mounted rows are padded into 512x288 at the shared y=32
	# frame origin, exactly as the V2 loader treats a mounted body reference.
	# Use the already-normalized braided alternate for both gender slots in this
	# integration fixture.  It is compact enough for the mounted rider envelope;
	# the larger concept-board hair would cover the horse when treated as a V2
	# layer.  The Pack 02 IDs remain gendered so the final art can replace each
	# source independently without changing the UI contract.
	_copy("alt_braided_hair_on_foot_unisex.png", "pack02_hair_short_braid_01_on_foot_male.png")
	_copy("alt_braided_hair_on_foot_unisex.png", "pack02_hair_short_braid_01_on_foot_female.png")
	_copy("alt_braided_hair_mounted_unisex.png", "pack02_hair_short_braid_01_mounted_male.png")
	_copy("alt_braided_hair_mounted_unisex.png", "pack02_hair_short_braid_01_mounted_female.png")

	_copy_pair("light_armor_on_foot_unisex.png", "light_armor_mounted_unisex.png", "pack02_leather_scale_armor_01")
	_copy_pair("boots_on_foot_unisex.png", "boots_mounted_unisex.png", "pack02_riding_boots_01")
	_copy_pair("light_armor_helmet_on_foot_unisex.png", "light_armor_helmet_mounted_unisex.png", "pack02_open_sallet_01")
	_copy_pair("alt_teal_cape_on_foot_unisex.png", "alt_teal_cape_mounted_unisex.png", "pack02_forest_cape_01")
	_copy_pair("alt_bronze_sword_on_foot_unisex.png", "alt_bronze_sword_mounted_unisex.png", "pack02_short_spear_01")
	_copy_pair("alt_teal_shield_on_foot_unisex.png", "alt_teal_shield_mounted_unisex.png", "pack02_round_shield_01")
	_copy_mounted("alt_dark_bay_horse_tail_mounted_unisex.png", "pack02_chestnut_horse_tail_01_mounted_unisex.png")
	_copy_mounted("alt_dark_bay_horse_body_mounted_unisex.png", "pack02_chestnut_horse_body_01_mounted_unisex.png")
	_copy_mounted("alt_dark_bay_horse_head_mounted_unisex.png", "pack02_chestnut_horse_head_01_mounted_unisex.png")
	_copy_mounted("alt_dark_barding_mounted_unisex.png", "pack02_forest_barding_01_mounted_unisex.png")

func _copy_pair(on_foot_source: String, mounted_source: String, visual_id: String) -> void:
	_copy(on_foot_source, "%s_on_foot_unisex.png" % visual_id)
	_copy(mounted_source, "%s_mounted_unisex.png" % visual_id)

func _copy(source_name: String, destination_name: String) -> void:
	var source_path := ProjectSettings.globalize_path(SOURCE_DIR.path_join(source_name))
	var image := Image.load_from_file(source_path)
	if image == null or image.is_empty():
		_failures.append("missing source alias: %s" % source_name)
		return
	var expected := Vector2i(512, 192) if destination_name.find("_on_foot_") >= 0 else Vector2i(512, 288)
	if Vector2i(image.get_width(), image.get_height()) != expected:
		_failures.append("source size %s is not %s: %s" % [Vector2i(image.get_width(), image.get_height()), expected, source_name])
		return
	var destination_path := ProjectSettings.globalize_path(OUTPUT_DIR.path_join(destination_name))
	if image.save_png(destination_path) != OK:
		_failures.append("could not write %s" % destination_name)
		return
	_files_written.append(destination_name)
	_source_aliases[destination_name] = SOURCE_DIR.path_join(source_name)

func _copy_mounted(source_name: String, destination_name: String) -> void:
	var source_path := ProjectSettings.globalize_path(SOURCE_DIR.path_join(source_name))
	var source := Image.load_from_file(source_path)
	if source == null or source.is_empty():
		_failures.append("missing mounted source alias: %s" % source_name)
		return
	var mounted := Image.create(512, 288, false, Image.FORMAT_RGBA8)
	mounted.fill(Color.TRANSPARENT)
	if Vector2i(source.get_width(), source.get_height()) == Vector2i(512, 288):
		mounted = source.duplicate()
	elif Vector2i(source.get_width(), source.get_height()) == Vector2i(512, 192):
		for row: int in range(SOURCE_ROWS):
			mounted.blit_rect(
				source,
				Rect2i(Vector2i(0, row * FRAME_SIZE.y), Vector2i(512, 64)),
				Vector2i(0, row * MOUNTED_FRAME_SIZE.y + 32)
			)
	else:
		_failures.append("mounted source has unsupported size: %s" % source_name)
		return
	var destination_path := ProjectSettings.globalize_path(OUTPUT_DIR.path_join(destination_name))
	if mounted.save_png(destination_path) != OK:
		_failures.append("could not write %s" % destination_name)
		return
	_files_written.append(destination_name)
	_source_aliases[destination_name] = SOURCE_DIR.path_join(source_name)

func _write_report(output_path: String) -> void:
	var report := {
		"status": "PASS" if _failures.is_empty() else "FAIL",
		"catalog_admission": "STAGING_ONLY",
		"files_written": _files_written,
		"source_aliases": _source_aliases,
		"formal_manifest_touched": false,
		"visual_gate": "PENDING_ART_REPLACEMENT",
		"failures": Array(_failures),
	}
	var file := FileAccess.open(output_path.path_join("build_report.json"), FileAccess.WRITE)
	if file == null:
		_failures.append("could not write build_report.json")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
