extends SceneTree
## Isolated original owner costs, NOT a battlefield/FPS benchmark.
const EDITOR := "res://scripts/ui/human_character_3d_editor.gd"
const METHODS := ["_update_lining_fit", "_update_equipment_dyes", "_update_weapon_sheath_state", "_update_hair_mask", "_update_full_body_visibility"]

func _initialize() -> void:
	if "--lining-batch" in OS.get_cmdline_user_args():
		preload("res://scripts/tests/fixtures/appearance_lining_batch_install.gd").install(true)
	var script := load(EDITOR) as GDScript
	var source := script.source_code
	for method: String in METHODS:
		var signature := "func " + method + "() -> void:\n"
		assert(source.count(signature) == 1)
		source = source.replace(signature, "func _timed_original" + method + "() -> void:\n")
		source += "\n" + signature + "\tvar begin := Time.get_ticks_usec()\n\t_timed_original" + method + "()\n\tvar elapsed := Time.get_ticks_usec() - begin\n\tvar costs: Dictionary = get_meta(&\"restore_costs\", {})\n\tvar row: Array = costs.get(\"" + method + "\", [0, 0])\n\trow[0] += elapsed\n\trow[1] += 1\n\tcosts[\"" + method + "\"] = row\n\tset_meta(&\"restore_costs\", costs)\n"
	script.source_code = source
	assert(script.reload(true) == OK)
	_run.call_deferred()

func _run() -> void:
	create_timer(40).timeout.connect(func() -> void: push_error("Restore profile deadline"); quit(1))
	assert(DisplayServer.get_name() != "headless")
	var actor := TerrainTestCharacter.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.initialize_visual()
	var editor := actor.editor
	editor.set_process(false)
	editor.set_playing(false)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.json"))
	var baseline: Dictionary = manifest.appearance
	var bare := baseline.duplicate(true)
	for slot: String in ["helmet", "outfit", "armor", "cape", "weapon", "shield", "boots"]: bare.parts[slot] = "none"
	var lining := baseline.duplicate(true)
	lining.parts.outfit = "outfit_chinese_lining_01"
	lining.parts.armor = "armor_mingguang_01"
	var cloth := baseline.duplicate(true)
	cloth.parts.armor = "outfit_medieval_chinese_01"
	cloth.parts.boots = "boots_medieval_chinese_01"
	var entries := [["leather", baseline], ["bare", bare], ["lining", lining], ["cloth", cloth], ["bare_after_cloth", bare]]
	var abba := "--lining-batch" in OS.get_cmdline_user_args()
	if abba:
		for warmup: int in 2:
			for entry: Array in entries: assert(editor.restore_appearance(entry[1]))
	var rows := []
	for pass_index: int in (8 if abba else 3):
		var reference: bool = [true, false, false, true][pass_index % 4]
		if abba: editor.set("_appearance_restore_reference", reference)
		for entry: Array in entries:
			editor.set_meta(&"restore_costs", {})
			var begin := Time.get_ticks_usec()
			assert(editor.restore_appearance(entry[1]))
			rows.append({"pass": pass_index, "reference": reference, "target": entry[0], "total_usec": Time.get_ticks_usec() - begin,
				"parts": editor.get_meta(&"restore_costs").duplicate(true)})
	var path := "res://output/site_appearance_lining_20260917/profile_%d.json" % int(Time.get_unix_time_from_system())
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"scope": "Synchronous actual editor restore; warm/cold separated, no FPS claim", "editor_sha256": FileAccess.get_sha256(EDITOR), "rows": rows}, "\t"))
	file.close()
	print("RESTORE_REFRESH_PROFILE_PASS output=" + path)
	actor.free()
	quit(0)
