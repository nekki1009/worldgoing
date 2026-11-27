extends SceneTree
## Capture (visual): 選現成人物 v1 in the shipped demo A. Births the package taking over the first person of
## `-- --role=leader|head|chief|captain` (default chief) through the real boot path with the renderer on, lets the Site
## draw, and saves the window under `--out=<res://output/...>` (default res://output/scenario_existing_capture) as
## <role>.png; `--frames=N` also times N frames after the opening. Prints EXISTING_PERSON_CAPTURE lines and EXISTING_PERSON_CAPTURE_DONE; quit(1) when the world is not born.
## Timing options: `--profile` (the Lab's stage counters), `--skip=N` (N more frames first), `--wait-atlas` (wait until no look
## is being baked into user://equipment_atlas: an isolated verifier user folder bakes every captive look again, about 15 ms
## a frame for minutes and a freeze of seconds at its end), `--hide-test` (diagnostic: SubViewports and hidden parts).
## It also prints block medians, the engine-side split, atlas preparation start/end and every frame over 400 ms.
const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const ScenarioPeople = preload("res://scripts/main_menu/scenario_people.gd")
const PACKAGE := "res://assets/scenarios/demo_a/demo_a.json"
const EquipmentAtlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")

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
	for _frame: int in range(90 + int(_arg("skip", "0"))): await process_frame # `--skip=N`: N more frames before measuring
	# `--wait-atlas`: wait (at most 5 minutes) until no look is being baked into user://equipment_atlas for 60 frames in a row;
	# an isolated verifier user folder bakes every look again, and that bake runs inside the frames measured below.
	if "--wait-atlas" in OS.get_cmdline_user_args():
		var waited := Time.get_ticks_msec()
		var quiet := 0
		var frames_waited := 0
		while quiet < 60 and Time.get_ticks_msec() - waited < 300000:
			await process_frame
			frames_waited += 1
			quiet = 0 if is_instance_valid(EquipmentAtlas._preparation) else quiet + 1
		print("EXISTING_PERSON_CAPTURE atlas wait %.1f s, %d frames, quiet %d" % [float(Time.get_ticks_msec() - waited) / 1000.0, frames_waited, quiet])
	# `--frames=N`: N more frames at the player's speed, their wall times (p50, p95, max) and the frames a second.
	var measure := int(_arg("frames", "0"))
	if measure > 0:
		var times: Array[float] = []
		if "--profile" in OS.get_cmdline_user_args():
			lab.combat_profile_enabled = true
			lab.combat_profile_usec = {}
		# Engine-side split of the same frames: the whole _process pass, physics, and the main viewport's render CPU and GPU.
		var viewport_rid := root.get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
		var engine := {"process": 0.0, "physics": 0.0, "render_cpu": 0.0, "render_gpu": 0.0, "draw_calls": 0.0, "objects": 0.0, "to_post_draw": 0.0, "after_post_draw": 0.0}
		Engine.set_meta(&"probe_process", {}) # filled by temporary per-node _process probes, when present
		var began := Time.get_ticks_usec()
		var drawn_at := Time.get_ticks_usec()
		for _frame: int in range(measure):
			var t := Time.get_ticks_usec()
			await process_frame
			var processing := Time.get_ticks_usec()
			engine.after_post_draw += float(processing - drawn_at) / 1000.0 # present, sync and idle up to the next process
			await RenderingServer.frame_post_draw
			drawn_at = Time.get_ticks_usec()
			engine.to_post_draw += float(drawn_at - processing) / 1000.0 # every _process, physics, canvas draws and the render
			times.append(float(Time.get_ticks_usec() - t) / 1000.0)
			# Atlas preparation (a look baked into user://equipment_atlas while playing) starting or ending in this frame.
			var preparing := is_instance_valid(EquipmentAtlas._preparation)
			if preparing != bool(Engine.get_meta(&"capture_atlas_preparing", false)):
				print("EXISTING_PERSON_CAPTURE atlas preparation %s at frame %d" % ["started" if preparing else "ended", _frame])
				Engine.set_meta(&"capture_atlas_preparing", preparing)
			# A frame over 400 ms is named with the profile stages that grew most in it (with --profile).
			if times.back() > 400.0:
				var grown: Array[String] = []
				if lab.combat_profile_enabled:
					var before: Dictionary = Engine.get_meta(&"capture_profile_before", {})
					var stage_names: Array = lab.combat_profile_usec.keys()
					stage_names.sort_custom(func(x: Variant, y: Variant) -> bool: return int(lab.combat_profile_usec[x]) - int(before.get(x, 0)) > int(lab.combat_profile_usec[y]) - int(before.get(y, 0)))
					for stage: Variant in stage_names.slice(0, 8): grown.append("%s %.0f" % [str(stage), float(int(lab.combat_profile_usec[stage]) - int(before.get(stage, 0))) / 1000.0])
				var counts: Dictionary = Engine.get_meta(&"capture_counts_before", {})
				print("EXISTING_PERSON_CAPTURE hitch frame %d: %.0f ms (process start to post-draw %.0f ms), Site minute %s; nodes %d -> %d, objects %d -> %d, texture memory %.1f -> %.1f MB, video memory %.1f -> %.1f MB; %s" % [_frame, times.back(), float(drawn_at - processing) / 1000.0, str(lab.terrain.site.get("minute", "")),
					int(counts.get("nodes", 0)), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(counts.get("objects", 0)), int(Performance.get_monitor(Performance.OBJECT_COUNT)),
					float(counts.get("texture", 0.0)) / 1048576.0, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, float(counts.get("video", 0.0)) / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, ", ".join(grown)])
			Engine.set_meta(&"capture_counts_before", {"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "objects": Performance.get_monitor(Performance.OBJECT_COUNT),
				"texture": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED), "video": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)})
			if lab.combat_profile_enabled: Engine.set_meta(&"capture_profile_before", lab.combat_profile_usec.duplicate())
			engine.process += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			engine.physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			engine.render_cpu += RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid) + RenderingServer.get_frame_setup_time_cpu()
			engine.render_gpu += RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)
			engine.draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			engine.objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		var wall := float(Time.get_ticks_usec() - began) / 1000000.0
		# Frame times drift as the Site's day goes on: the median of each block of 150 frames, in order.
		var blocks: Array[String] = []
		for block_start: int in range(0, times.size(), 150):
			var block: Array[float] = times.slice(block_start, mini(times.size(), block_start + 150))
			block.sort()
			blocks.append("%.1f" % block[block.size() / 2])
		print("EXISTING_PERSON_CAPTURE block medians (150 frames each) %s ms; Site minute %s" % [", ".join(blocks), str(lab.terrain.site.get("minute", ""))])
		times.sort()
		print("EXISTING_PERSON_CAPTURE frames %d in %.1f s: %.1f fps, p50 %.1f ms, p95 %.1f ms, max %.1f ms; %d crowd people" % [measure, wall, measure / maxf(wall, 0.001), times[times.size() / 2], times[int(times.size() * 0.95)], times.back(), lab.crowd_site._index_by_id.size()])
		print("EXISTING_PERSON_CAPTURE engine a frame: process %.1f ms, physics %.1f ms, render cpu %.1f ms, render gpu %.1f ms, %.0f draw calls, %.0f objects; process start to post-draw %.1f ms, post-draw to next process %.1f ms" % [engine.process / measure, engine.physics / measure, engine.render_cpu / measure, engine.render_gpu / measure, engine.draw_calls / measure, engine.objects / measure, engine.to_post_draw / measure, engine.after_post_draw / measure])
		var probe: Dictionary = Engine.get_meta(&"probe_process", {})
		for key: Variant in probe: print("EXISTING_PERSON_CAPTURE node %s %s" % [str(key), "%d calls" % int(probe[key]) if str(key).ends_with("_calls") else "%.2f ms a frame" % (float(probe[key]) / 1000.0 / measure)])
		if lab.combat_profile_enabled:
			var stages: Array = lab.combat_profile_usec.keys()
			stages.sort_custom(func(x: Variant, y: Variant) -> bool: return float(lab.combat_profile_usec[x]) > float(lab.combat_profile_usec[y]))
			for stage: Variant in stages.slice(0, 60): print("EXISTING_PERSON_CAPTURE stage %s %.1f ms a frame" % [str(stage), float(lab.combat_profile_usec[stage]) / 1000.0 / measure])
	# `--hide-test`: 120 frames each with one presentation part hidden (diagnostic only; the picture below is taken with all shown).
	if "--hide-test" in OS.get_cmdline_user_args():
		lab.combat_profile_enabled = false
		# Every SubViewport in the tree, its update mode and its measured render time over 60 frames.
		var subviewports: Array[Node] = root.find_children("*", "SubViewport", true, false)
		for viewport: Node in subviewports: RenderingServer.viewport_set_measure_render_time((viewport as SubViewport).get_viewport_rid(), true)
		var sub_cpu := {}
		for _frame: int in range(60):
			await RenderingServer.frame_post_draw
			for viewport: Node in subviewports:
				var rid := (viewport as SubViewport).get_viewport_rid()
				sub_cpu[viewport] = float(sub_cpu.get(viewport, 0.0)) + RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.viewport_get_measured_render_time_gpu(rid)
		print("EXISTING_PERSON_CAPTURE subviewports %d" % subviewports.size())
		var sorted_viewports: Array = subviewports.duplicate()
		sorted_viewports.sort_custom(func(a: Variant, b: Variant) -> bool: return float(sub_cpu.get(a, 0.0)) > float(sub_cpu.get(b, 0.0)))
		for viewport: Variant in sorted_viewports.slice(0, 12):
			var sub := viewport as SubViewport
			print("EXISTING_PERSON_CAPTURE subviewport %s size %s mode %d render %.2f ms a frame" % [str(root.get_path_to(sub)).right(120), str(sub.size), int(sub.render_target_update_mode), float(sub_cpu.get(viewport, 0.0)) / 60.0])
		var modes := {}
		for viewport: Node in subviewports: modes[int((viewport as SubViewport).render_target_update_mode)] = int(modes.get(int((viewport as SubViewport).render_target_update_mode), 0)) + 1
		print("EXISTING_PERSON_CAPTURE subviewport modes %s (0 disabled, 1 once, 2 when visible, 3 when parent visible, 4 always)" % str(modes))
		var always: Array[SubViewport] = []
		for viewport: Node in subviewports:
			if (viewport as SubViewport).render_target_update_mode == SubViewport.UPDATE_ALWAYS: always.append(viewport)
		for viewport: SubViewport in always: viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var off_times: Array[float] = []
		for _frame: int in range(120):
			var t := Time.get_ticks_usec()
			await process_frame
			off_times.append(float(Time.get_ticks_usec() - t) / 1000.0)
		for viewport: SubViewport in always: viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		off_times.sort()
		print("EXISTING_PERSON_CAPTURE always-updating subviewports off (%d): p50 %.1f ms; %s" % [always.size(), off_times[off_times.size() / 2], str(always.map(func(v: SubViewport) -> String: return "%s visible_in_tree=%s owner_visible=%s" % [str(root.get_path_to(v)), str(v.get_parent() is CanvasItem and (v.get_parent() as CanvasItem).is_visible_in_tree()), str(v.get_parent().get("visible"))]))])
		var parts := {"none": [], "resource view": [lab.site_controller.view], "terrain": [lab.renderer]}
		for part: String in parts:
			for node: Variant in parts[part]: node.visible = false
			var part_times: Array[float] = []
			for _frame: int in range(120):
				var t := Time.get_ticks_usec()
				await process_frame
				part_times.append(float(Time.get_ticks_usec() - t) / 1000.0)
			for node: Variant in parts[part]: node.visible = true
			part_times.sort()
			print("EXISTING_PERSON_CAPTURE hidden %s: p50 %.1f ms (%d nodes)" % [part, part_times[part_times.size() / 2], parts[part].size()])
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := out.path_join(role + ".png")
	var saved := image.save_png(ProjectSettings.globalize_path(path))
	print("EXISTING_PERSON_CAPTURE %s %s %s %s at %s, controlled #%d" % [role, path, "ok" if saved == OK else error_string(saved), str(person.name), str(person.site), int(lab.controlled_person_id())])
	TerrainArmy.release_contact_source()
	await process_frame
	print("EXISTING_PERSON_CAPTURE_DONE")
	quit(0)
