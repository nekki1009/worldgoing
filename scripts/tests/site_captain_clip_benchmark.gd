extends "res://scripts/tests/site_army_scale_realtime_test.gd"
## Original main-scene benchmark; candidate exists only in this test process.

func _run() -> void:
	if "--compact-zero-keys" in OS.get_cmdline_user_args():
		var script := load(EDITOR) as GDScript
		var anchor := "\t_prepare_animation_loop_defaults()\n"
		assert(script.source_code.count(anchor) == 1)
		# Fresh raw GLTF animation resources already belong to this presenter.
		# Do not duplicate/serialize them: that changes raw rotation precision.
		script.source_code = script.source_code.replace(anchor, anchor + "\tif get_script() == HumanCharacter3DEditor:\n\t\tvar compactor = load(\"res://scripts/terrain_lab/terrain_army_contact_source.gd\").new()\n\t\tvar visited := {}\n\t\tfor clip: StringName in animation_player.get_animation_list():\n\t\t\tvar animation := animation_player.get_animation(clip)\n\t\t\tif not visited.has(animation):\n\t\t\t\tvisited[animation] = true\n\t\t\t\tcompactor._compact_constant_morph_keys(animation)\n\t\tset_meta(&\"zero_keys_compacted\", true)\n")
		assert(script.reload(true) == OK)
	if "--clip-safe" in OS.get_cmdline_user_args():
		preload("res://scripts/tests/fixtures/captain_clip_safe_install.gd").install(true)
	if "--clip-working-set" in OS.get_cmdline_user_args():
		var script := load(EDITOR) as GDScript
		var anchor := "\tvar animation := animation_player.get_animation(play_anim)\n\t# Rewriting the same Resource value"
		assert(script.source_code.count(anchor) == 1)
		script.source_code = script.source_code.replace(anchor, "\t_clip_set_probe_prepare(play_anim)\n" + anchor) + "\n" + FileAccess.get_file_as_string("res://scripts/tests/fixtures/captain_clip_working_set.gd.txt")
		assert(script.reload(true) == OK)
		var army_script := load(ARMY) as GDScript
		var creation := "\tif exchange_enabled:\n\t\teditor.set_process(false)\n\treturn editor"
		assert(army_script.source_code.count(creation) == 1)
		army_script.source_code = army_script.source_code.replace(creation, creation.replace("\treturn editor", "\teditor.set_meta(&\"clip_set_probe_enabled\", true)\n\treturn editor"))
		assert(army_script.reload(true) == OK)
	await super._run()

func _write() -> void:
	if is_instance_valid(lab) and "--compact-zero-keys" in OS.get_cmdline_user_args():
		report["zero_keys_compacted_presenters"] = []
		for node: Node in root.find_children("*", "Node", true, false):
			if node is HumanCharacter3DEditor and node.get_meta(&"zero_keys_compacted", false):
				report.zero_keys_compacted_presenters.append(str(node.get_path()))
	if is_instance_valid(lab) and "--clip-safe" in OS.get_cmdline_user_args():
		report["clip_safe_variant"] = "mobile" if "--clip-mobile" in OS.get_cmdline_user_args() else ("lifecycle" if "--clip-lifecycle" in OS.get_cmdline_user_args() else ("reactions" if "--clip-reactions" in OS.get_cmdline_user_args() else "three_clip"))
		if "--clip-mobile-lifecycle" in OS.get_cmdline_user_args(): report["clip_safe_variant"] = "mobile_lifecycle"
		var states := []
		for team: TerrainArmy in lab.combat_armies:
			for presenter: HumanCharacter3DEditor in team._live_presenters.values():
				states.append({"enabled": presenter.get_meta(&"clip_safe_enabled", false), "tracks": presenter.get_meta(&"clip_safe_tracks", 0), "fallback": presenter.get_meta(&"clip_safe_fallback", "")})
		report["clip_safe_presenters"] = states
	super._write()
