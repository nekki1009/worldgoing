extends RefCounted
## Test-process candidate first; never write a production source or atlas.
const EDITOR := "res://scripts/ui/human_character_3d_editor.gd"

static func candidate_source(before: String) -> String:
	var matcher := RegEx.new()
	assert(matcher.compile("(?ms)^func restore_appearance\\([^\\n]*\\n.*?(?=^func )") == OK)
	assert(matcher.search_all(before).size() == 1)
	var original := matcher.search(before).get_string()
	var loop := "\tfor slot: Dictionary in PART_SLOTS:\n\t\tif not select_part_by_id(slot.id, StringName(str(value.parts[str(slot.id)]))):\n\t\t\treturn false\n"
	var replacement := """
	# Only coalesce unrelated slot refreshes in this synchronous base-owner call.
	# Weapon/shield changes and animation changes still refresh immediately.
	var batch_weapons: bool = get_script() == HumanCharacter3DEditor and not _restoring_appearance_parts
	if batch_weapons:
		_update_weapon_sheath_state()
		_restoring_appearance_parts = true
	for slot: Dictionary in PART_SLOTS:
		if not select_part_by_id(slot.id, StringName(str(value.parts[str(slot.id)]))):
			if batch_weapons: _restoring_appearance_parts = false
			return false
	if batch_weapons: _restoring_appearance_parts = false
""" + "\n"
	assert(original.count(loop) == 1)
	var candidate := original.replace(loop, replacement)
	var refresh := "\t_update_weapon_sheath_state()\n\t_update_full_body_visibility()"
	assert(before.count(refresh) == 1)
	var source := before.replace(original, candidate).replace(refresh, "\tif not _restoring_appearance_parts or part_id in [&\"weapon\", &\"shield\"]:\n\t\t_update_weapon_sheath_state()\n\t_update_full_body_visibility()")
	assert(source.count("var _body_index: int = 0\n") == 1)
	return source.replace("var _body_index: int = 0\n", "var _body_index: int = 0\nvar _restoring_appearance_parts := false\n")

static func install(reference_control: bool = false) -> void:
	var script := load(EDITOR) as GDScript
	var before := FileAccess.get_file_as_string("res://output/site_appearance_restore_20260917/before/human_character_3d_editor.gd.txt").replace("\r", "")
	var source := candidate_source(before)
	assert(script.source_code.replace("\r", "") in [before, source], "Unrelated editor changes require a fresh candidate audit")
	if reference_control:
		var matcher := RegEx.new()
		assert(matcher.compile("(?ms)^func restore_appearance\\([^\\n]*\\n.*?(?=^func )") == OK)
		var original := matcher.search(before).get_string()
		source = source.replace("func restore_appearance(value: Dictionary) -> bool:\n", "func restore_appearance(value: Dictionary) -> bool:\n\tif _appearance_restore_reference: return _original_restore_appearance(value)\n")
		source += "\nvar _appearance_restore_reference := true\nvar _weapon_refresh_calls := 0\n" + original.replace("func restore_appearance(", "func _original_restore_appearance(")
		source = source.replace("func _update_weapon_sheath_state() -> void:\n", "func _update_weapon_sheath_state() -> void:\n\t_weapon_refresh_calls += 1\n")
	script.source_code = source
	assert(script.reload(true) == OK)
