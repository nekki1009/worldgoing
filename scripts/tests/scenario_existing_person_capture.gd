extends SceneTree
## Capture (visual): 選現成人物 v1 in the shipped demo A. Births the package taking over the first person of
## `-- --role=leader|head|chief|captain` (default chief) through the real boot path with the renderer on, lets the Site
## draw, and saves the window under `--out=<res://output/...>` (default res://output/scenario_existing_capture) as
## <role>.png; `--frames=N` also times N frames after the opening. Prints EXISTING_PERSON_CAPTURE lines and EXISTING_PERSON_CAPTURE_DONE; quit(1) when the world is not born.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const ScenarioPeople = preload("res://scripts/main_menu/scenario_people.gd")
const PACKAGE := "res://assets/scenarios/demo_a/demo_a.json"

func _arg(name: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--" + name + "="): return argument.get_slice("=", 1)
	return fallback

func _initialize() -> void:
	create_timer(600.0).timeout.connect(func() -> void:
		print("EXISTING_PERSON_CAPTURE deadline")
		quit(1))
	_run.call_deferred()

func _run() -> void:
	var role := _arg("role", "chief")
	var out := _arg("out", "res://output/scenario_existing_capture")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var person: Dictionary = {}
	for row: Dictionary in ScenarioPeople.people(PACKAGE).get("people", []):
		if str(row.role) == role:
			person = row
			break
	if person.is_empty() or not RegionEntry.request_new_world(person.site, {"name": str(person.name)}, "選人截圖", "", PACKAGE, {"mode": "neutral"}, {"surname": str(person.name).left(1)}, {"free_points": false, "template": "", "scenario": {"id": "demo_a_kaiken", "version": 1}}, [], {"name": str(person.name)}):
		print("EXISTING_PERSON_CAPTURE refused %s" % RegionEntry.menu_message)
		quit(1)
		return
	change_scene_to_file(SITE)
	var lab: TerrainLab = null
	var deadline := Time.get_ticks_msec() + 420000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if lab == null:
		print("EXISTING_PERSON_CAPTURE not born")
		quit(1)
		return
	for _frame: int in range(90): await process_frame
	# `--frames=N`: N more frames at the player's speed, their wall times (p50, p95, max) and the frames a second.
	var measure := int(_arg("frames", "0"))
	if measure > 0:
		var times: Array[float] = []
		if "--profile" in OS.get_cmdline_user_args():
			lab.combat_profile_enabled = true
			lab.combat_profile_usec = {}
		var began := Time.get_ticks_usec()
		for _frame: int in range(measure):
			var t := Time.get_ticks_usec()
			await process_frame
			times.append(float(Time.get_ticks_usec() - t) / 1000.0)
		var wall := float(Time.get_ticks_usec() - began) / 1000000.0
		times.sort()
		print("EXISTING_PERSON_CAPTURE frames %d in %.1f s: %.1f fps, p50 %.1f ms, p95 %.1f ms, max %.1f ms; %d crowd people" % [measure, wall, measure / maxf(wall, 0.001), times[times.size() / 2], times[int(times.size() * 0.95)], times.back(), lab.crowd_site._index_by_id.size()])
		if lab.combat_profile_enabled:
			var stages: Array = lab.combat_profile_usec.keys()
			stages.sort_custom(func(x: Variant, y: Variant) -> bool: return float(lab.combat_profile_usec[x]) > float(lab.combat_profile_usec[y]))
			for stage: Variant in stages.slice(0, 60): print("EXISTING_PERSON_CAPTURE stage %s %.1f ms a frame" % [str(stage), float(lab.combat_profile_usec[stage]) / 1000.0 / measure])
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := out.path_join(role + ".png")
	var saved := image.save_png(ProjectSettings.globalize_path(path))
	print("EXISTING_PERSON_CAPTURE %s %s %s %s at %s, controlled #%d" % [role, path, "ok" if saved == OK else error_string(saved), str(person.name), str(person.site), int(lab.controlled_person_id())])
	TerrainArmy.release_contact_source()
	await process_frame
	print("EXISTING_PERSON_CAPTURE_DONE")
	quit(0)
