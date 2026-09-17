extends RefCounted
## Test-only in-memory injection; original production files/provenance stay intact.
static func install(include_army: bool = false) -> void:
	var editor := load("res://scripts/ui/human_character_3d_editor.gd") as GDScript
	var anchor := "\tvar animation := animation_player.get_animation(play_anim)\n\t# Rewriting the same Resource value"
	assert(editor.source_code.count(anchor) == 1)
	editor.source_code = editor.source_code.replace(anchor, "\t_clip_safe_prepare(play_anim)\n" + anchor)
	for signature: String in ["func open() -> void:", "func _load_body_model(index: int, preview_model_path: String = \"\") -> void:", "func _on_part_selected(index: int, part_id: StringName) -> void:", "func restore_appearance(value: Dictionary) -> bool:", "func set_mount_enabled(enabled: bool) -> void:"]:
		assert(editor.source_code.count(signature) == 1)
		editor.source_code = editor.source_code.replace(signature + "\n", signature + "\n\t_clip_safe_restore(\"" + signature.get_slice("(", 0).trim_prefix("func ") + "\")\n")
	editor.source_code += "\n" + FileAccess.get_file_as_string("res://scripts/tests/fixtures/captain_clip_safe.gd.txt")
	assert(editor.reload(true) == OK)
	if not include_army: return
	var army := load("res://scripts/terrain_lab/terrain_army.gd") as GDScript
	var line := "\tvar pose := StringName(str(descriptor.get(\"pose\", frame.clip)))\n"
	assert(army.source_code.count(line) == 1)
	army.source_code = army.source_code.replace(line, line + "\tif exchange_enabled and presenter.get_script() == HumanCharacter3DEditor:\n\t\tif not presenter.has_meta(&\"clip_safe_attempted\"):\n\t\t\tpresenter.set_meta(&\"clip_safe_attempted\", true)\n\t\t\tpresenter.set_meta(&\"clip_safe_enabled\", true)\n\t\tpresenter._clip_safe_prepare(pose)\n")
	assert(army.reload(true) == OK)
