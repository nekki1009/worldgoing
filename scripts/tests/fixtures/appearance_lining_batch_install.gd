extends RefCounted
const EDITOR := "res://scripts/ui/human_character_3d_editor.gd"
const BEFORE := "res://output/site_appearance_lining_20260917/before/human_character_3d_editor.gd.txt"
const ORIGINAL := "\t_update_lining_fit()\n\tif str(part_id) in EquipmentDye.SLOTS:"
const GUARD := "not _restoring_appearance_parts or part_id in [&\"face\", &\"outfit\", &\"armor\", &\"boots\"]"

static func candidate_source(before: String) -> String:
	assert(before.count(ORIGINAL) == 1)
	return before.replace(ORIGINAL, "\t# Face is the first restored slot; clothing/shoes retain immediate coverage.\n\tif " + GUARD + ":\n\t\t_update_lining_fit()\n\tif str(part_id) in EquipmentDye.SLOTS:")

static func install(reference_control: bool = false) -> void:
	var script := load(EDITOR) as GDScript
	var before := FileAccess.get_file_as_string(BEFORE).replace("\r", "")
	var source := candidate_source(before)
	assert(script.source_code.replace("\r", "") in [before, source], "Unrelated editor change requires fresh audit")
	if reference_control:
		source = source.replace("if " + GUARD + ":", "if _appearance_restore_reference or " + GUARD + ":")
		source += "\nvar _appearance_restore_reference := true\nvar _weapon_refresh_calls := 0\nvar _lining_refresh_calls := 0\n"
		source = source.replace("func _update_weapon_sheath_state() -> void:\n", "func _update_weapon_sheath_state() -> void:\n\t_weapon_refresh_calls += 1\n")
		source = source.replace("func _update_lining_fit() -> void:\n", "func _update_lining_fit() -> void:\n\t_lining_refresh_calls += 1\n")
	script.source_code = source
	assert(script.reload(true) == OK)
